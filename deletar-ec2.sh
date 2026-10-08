#!/bin/bash
# Executar no computador local, sem sudo.
# Exclui uma EC2 do CoreTrace e todos os volumes EBS atualmente ligados a ela.
set -Eeuo pipefail
trap 'echo "Erro na linha $LINENO. A exclusão pode estar parcialmente concluída; confira a AWS antes de tentar novamente." >&2' ERR
cd "$(dirname "$0")"

export AWS_DEFAULT_REGION=us-east-1
export AWS_PAGER=""

if [ "$EUID" -eq 0 ]; then
    echo "Execute sem sudo, com as credenciais do responsável pelo laboratório."
    exit 1
fi
if [ "$#" -gt 1 ]; then
    echo "Uso: bash deletar-ec2.sh [ID_DA_INSTANCIA]"
    exit 1
fi

# Um ID informado no comando tem prioridade sobre o arquivo salvo pelo criador.
INSTANCIA="${1:-}"
if [ -z "$INSTANCIA" ] && [ -f instancia-id.txt ]; then
    INSTANCIA=$(cat instancia-id.txt)
fi
if [[ ! "$INSTANCIA" =~ ^i-([0-9a-f]{8}|[0-9a-f]{17})$ ]]; then
    echo "Informe um ID válido ou mantenha instancia-id.txt na pasta."
    echo "Uso: bash deletar-ec2.sh i-ID_DA_INSTANCIA"
    exit 1
fi

CONTA=$(aws sts get-caller-identity --query Account --output text)
ESTADO=$(aws ec2 describe-instances --region "$AWS_DEFAULT_REGION" \
    --instance-ids "$INSTANCIA" \
    --query 'Reservations[0].Instances[0].State.Name' --output text)
if [ "$ESTADO" = terminated ]; then
    echo "A instância $INSTANCIA já foi encerrada. Nenhum recurso foi alterado."
    echo "Volumes anteriormente desconectados precisam ser conferidos separadamente."
    exit 0
fi
if [ "$ESTADO" = shutting-down ]; then
    echo "A instância $INSTANCIA já está sendo encerrada. Aguarde e confira os volumes no console."
    exit 0
fi
case "$ESTADO" in
    pending|running|stopping|stopped) ;;
    *) echo "Estado não reconhecido: $ESTADO. Nenhuma exclusão realizada."; exit 1 ;;
esac

NOME=$(aws ec2 describe-instances --region "$AWS_DEFAULT_REGION" \
    --instance-ids "$INSTANCIA" \
    --query "Reservations[0].Instances[0].Tags[?Key=='Name'].Value | [0]" --output text)
case "$NOME" in
    coretrace-ec2|coretrace-ec2-*) ;;
    *) echo "A instância não tem nome coretrace-ec2 ou coretrace-ec2-*. Confira o ID."; exit 1 ;;
esac

PROTEGIDA=$(aws ec2 describe-instance-attribute --region "$AWS_DEFAULT_REGION" \
    --instance-id "$INSTANCIA" --attribute disableApiTermination \
    --query DisableApiTermination.Value --output text)
if [ "$PROTEGIDA" != False ] && [ "$PROTEGIDA" != false ]; then
    echo "A proteção contra encerramento está ativa ou não pôde ser confirmada."
    echo "Revise a proteção no console antes de executar este script."
    exit 1
fi

MAPEAMENTOS=$(aws ec2 describe-instances --region "$AWS_DEFAULT_REGION" \
    --instance-ids "$INSTANCIA" \
    --query 'Reservations[0].Instances[0].BlockDeviceMappings[?Ebs!=`null`].[DeviceName,Ebs.VolumeId]' \
    --output text)
VOLUMES=()
DISPOSITIVOS=()
while read -r dispositivo volume; do
    [ -n "$dispositivo" ] || continue
    if [[ ! "$volume" =~ ^vol-([0-9a-f]{8}|[0-9a-f]{17})$ ]] || \
       [[ ! "$dispositivo" =~ ^/dev/[a-zA-Z0-9/_-]+$ ]]; then
        echo "Mapeamento de volume inválido. Nenhuma exclusão realizada."
        exit 1
    fi
    # Não permite excluir um volume compartilhado ou cujo vínculo mudou.
    VINCULOS=$(aws ec2 describe-volumes --region "$AWS_DEFAULT_REGION" \
        --volume-ids "$volume" --query 'Volumes[0].Attachments[].InstanceId' --output text)
    if [ "$VINCULOS" != "$INSTANCIA" ]; then
        echo "O volume $volume tem vínculos diferentes do esperado. Nenhuma exclusão realizada."
        exit 1
    fi
    DISPOSITIVOS+=("$dispositivo")
    VOLUMES+=("$volume")
done <<< "$MAPEAMENTOS"

echo "Conta AWS: $CONTA | Região: $AWS_DEFAULT_REGION"
echo "Instância: $INSTANCIA | Nome: $NOME | Estado: $ESTADO"
echo "Volumes EBS que serão excluídos:"
for volume in "${VOLUMES[@]}"; do echo "  $volume"; done
echo "Os arquivos, containers e dados MySQL nesses volumes serão perdidos."
echo "S3, snapshots, VPC, sub-rede, grupos de segurança e pares de chaves serão preservados."
echo "Volumes desconectados e Elastic IPs não são removidos por este script."
read -r -p "Para confirmar a exclusão definitiva, digite $INSTANCIA: " CONFIRMACAO || exit 1
if [ "$CONFIRMACAO" != "$INSTANCIA" ]; then
    echo "Exclusão cancelada. Nenhum recurso foi alterado."
    exit 0
fi

# Faz a AWS excluir os volumes junto com a instância, incluindo discos adicionais.
for indice in "${!VOLUMES[@]}"; do
    aws ec2 modify-instance-attribute --region "$AWS_DEFAULT_REGION" \
        --instance-id "$INSTANCIA" \
        --block-device-mappings \
        "DeviceName=${DISPOSITIVOS[$indice]},Ebs={VolumeId=${VOLUMES[$indice]},DeleteOnTermination=true}"
done

echo "Encerrando a instância e excluindo seus volumes..."
aws ec2 terminate-instances --region "$AWS_DEFAULT_REGION" \
    --instance-ids "$INSTANCIA" >/dev/null
aws ec2 wait instance-terminated --region "$AWS_DEFAULT_REGION" --instance-ids "$INSTANCIA"
for volume in "${VOLUMES[@]}"; do
    aws ec2 wait volume-deleted --region "$AWS_DEFAULT_REGION" --volume-ids "$volume"
done
echo "EC2 $INSTANCIA e seus volumes EBS excluídos com sucesso."
echo "O Data Lake permanece disponível. Sua exclusão é feita pelo deletar-data-lake.sh."

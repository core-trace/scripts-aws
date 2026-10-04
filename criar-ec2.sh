#!/bin/bash
# Executar no computador local, sem sudo
set -Eeuo pipefail

trap 'echo "Erro na linha $LINENO. A instância pode já ter sido criada; confira antes de tentar novamente." >&2' ERR

# Trabalha na pasta onde este script está salvo
cd "$(dirname "$0")"

export AWS_DEFAULT_REGION=us-east-1
export AWS_PAGER=""

NOME=coretrace-ec2

IMAGEM= #COLOCAR

TIPO=t3.small

SUBREDE= #COLOCAR

# ID do grupo de segurança em EC2 > Grupos de segurança.
# Ele deve pertencer a mesma VPC da sub-rede acima.
# ANTES de executar: Regras de entrada > Editar regras > SSH > Meu IP.
# Conferir TCP 22 e o IP público do responsável com /32, e salvar.
GRUPO= #COLOCAR

# nome do par em EC2 > Pares de chaves.
# Manter vockey somente se corresponder a chave privada baixada.
# Aqui vai o NOME do par na AWS, não o caminho do arquivo .pem.
CHAVE=vockey

# Vê se existe o arquivo de configuraçaõ antes
if [ ! -f configuracao.sh ]; then
    echo "Arquivo configuracao.sh não encontrado nesta pasta."
    exit 1
fi

bash -n configuracao.sh

# Confere as credenciais do laboratório
aws sts get-caller-identity >/dev/null

# ADD - Acessa a EC2 e verifica a configuração automaticamente.
verificar_ec2() {
    local instancia="$1"
    local ip
    local conectado=false

    ip=$(aws ec2 describe-instances \
        --instance-ids "$instancia" \
        --query 'Reservations[0].Instances[0].PublicIpAddress' \
        --output text)

    if [ -z "$ip" ] || [ "$ip" = "None" ]; then
        echo "A instância não tem IP público disponível."
        echo "Confira se ela está ligada."
        return 1
    fi

    echo "Aguardando acesso SSH em $ip..."

    for tentativa in {1..60}; do
        if ssh \
            -i "$HOME/.ssh/labsuser.pem" \
            -o BatchMode=yes \
            -o ConnectTimeout=5 \
            -o StrictHostKeyChecking=accept-new \
            "ubuntu@$ip" true; then
            conectado=true
            break
        fi
        sleep 5
    done

    if [ "$conectado" != true ]; then
        echo "Não foi possível conectar por SSH."
        echo "Confira a chave e o IP permitido no grupo de segurança."
        return 1
    fi

    echo "Conectado. Aguardando a configuração automática..."

    ssh -i "$HOME/.ssh/labsuser.pem" "ubuntu@$ip" 'bash -s' <<'VERIFICACAO'
set -e

# Limita a espera a 20 minutos.
if ! sudo timeout 1200 cloud-init status --wait; then
    echo "A configuração automática apresentou problema ou excedeu o prazo."
    sudo tail -n 40 /var/log/cloud-init-output.log
    exit 1
fi

# Confirma que nosso script chegou ao final.
if ! sudo test -f /var/lib/coretrace-configuracao-concluida; then
    echo "O script não registrou conclusão."
    sudo tail -n 40 /var/log/coretrace-configuracao.log
    exit 1
fi

sudo systemctl is-active docker mysql
sudo mysql -uroot -e "SELECT 1;"

sudo docker exec coretrace_mysql sh -c \
    'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" mysql -uroot -e "SELECT 1;" CoreTrace'

echo "Verificação automática concluída com sucesso."
VERIFICACAO
}

# Evita criar outra instância com o mesmo nome
EXISTENTES=$(aws ec2 describe-instances \
    --filters \
        "Name=tag:Name,Values=$NOME" \
        "Name=instance-state-name,Values=pending,running,stopping,stopped" \
    --query 'Reservations[].Instances[].InstanceId' \
    --output text)

if [ -n "$EXISTENTES" ]; then
    echo "Já existe uma instância chamada $NOME:"
    echo "$EXISTENTES"
        echo "Nenhuma nova instância foi criada."

    # Pra nao escolher automaticamente se tiver mais de uma
    if [[ "$EXISTENTES" == *$'\t'* || "$EXISTENTES" == *$'\n'* ]]; then
        echo "Há várias instâncias com esse nome. Confira no console."
        exit 1
    fi

    verificar_ec2 "$EXISTENTES"
    exit 0
fi

echo "Criando a EC2 Ubuntu..."

INSTANCIA=$(aws ec2 run-instances \
    --image-id "$IMAGEM" \
    --instance-type "$TIPO" \
    --count 1 \
    --key-name "$CHAVE" \
    --subnet-id "$SUBREDE" \
    --security-group-ids "$GRUPO" \
    --associate-public-ip-address \
    --block-device-mappings \
        '[{"DeviceName":"/dev/sda1","Ebs":{"VolumeSize":20,"VolumeType":"gp3","DeleteOnTermination":true}}]' \
    --tag-specifications \
        "ResourceType=instance,Tags=[{Key=Name,Value=$NOME}]" \
    --user-data file://configuracao.sh \
    --query 'Instances[0].InstanceId' \
    --output text)

# Guarda o identificador para consultar depois
printf '%s\n' "$INSTANCIA" > instancia-id.txt
echo "Instância criada: $INSTANCIA"

echo "Aguardando a instância entrar em execução..."
aws ec2 wait instance-running --instance-ids "$INSTANCIA"

IP=$(aws ec2 describe-instances \
    --instance-ids "$INSTANCIA" \
    --query 'Reservations[0].Instances[0].PublicIpAddress' \
    --output text)

printf '%s\n' "$IP" > instancia-ip.txt

echo "IP público: $IP"
echo "O Ubuntu ainda pode estar instalando os programas."
echo "Comando para conectar:"
echo "ssh -i ~/.ssh/labsuser.pem ubuntu@$IP"

# ADD - Verifica a instância depois da criação
verificar_ec2 "$INSTANCIA"

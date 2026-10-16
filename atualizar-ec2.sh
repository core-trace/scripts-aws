#!/bin/bash
# Executar localmente. Envia o setup desta branch para uma EC2 existente.
set -Eeuo pipefail
cd "$(dirname "$0")"
export AWS_DEFAULT_REGION=us-east-1
export AWS_PAGER=""

if [ "$#" -gt 1 ]; then
    echo "Uso: bash atualizar-ec2.sh [i-ID_DA_INSTANCIA]"
    exit 1
fi
INSTANCIA="${1:-$(cat instancia-id.txt)}"
[[ "$INSTANCIA" =~ ^i-[0-9a-f]+$ ]] || { echo "ID de instância inválido."; exit 1; }
bash -n configuracao.sh
aws sts get-caller-identity >/dev/null

NOME=$(aws ec2 describe-instances --instance-ids "$INSTANCIA" \
    --query 'Reservations[0].Instances[0].Tags[?Key==`Name`].Value | [0]' --output text)
if [[ "$NOME" != coretrace-ec2 && "$NOME" != coretrace-ec2-* ]]; then
    echo "A instância $INSTANCIA não tem um nome coretrace-ec2 ou coretrace-ec2-*."
    exit 1
fi
ESTADO=$(aws ec2 describe-instances --instance-ids "$INSTANCIA" \
    --query 'Reservations[0].Instances[0].State.Name' --output text)
[ "$ESTADO" = running ] || { echo "A instância precisa estar ligada. Estado: $ESTADO"; exit 1; }
IP=$(aws ec2 describe-instances --instance-ids "$INSTANCIA" \
    --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)
[ -n "$IP" ] && [ "$IP" != None ] || { echo "Instância sem IP público."; exit 1; }

SSH_OPCOES=(-i "$HOME/.ssh/labsuser.pem" -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new)

ssh "${SSH_OPCOES[@]}" "ubuntu@$IP" 'bash -s' <<'ESPERAR'
set -eu
resultado=0
sudo timeout 1200 cloud-init status --wait || resultado=$?
if [ "$resultado" -eq 124 ]; then
    echo "Cloud-init ainda não terminou. Aguarde antes de atualizar."
    exit 1
fi
if [ "$resultado" -ne 0 ]; then
    echo "Cloud-init anterior apresentou erros. O setup atualizado tentará reparar a configuração."
fi
ESPERAR

DESTINO=$(ssh "${SSH_OPCOES[@]}" "ubuntu@$IP" 'mktemp /tmp/coretrace-configuracao.XXXXXXXX.sh')
[[ "$DESTINO" =~ ^/tmp/coretrace-configuracao\.[a-zA-Z0-9]+\.sh$ ]] || exit 1
printf -v LIMPEZA 'rm -f -- %q' "$DESTINO"
trap 'ssh "${SSH_OPCOES[@]}" "ubuntu@$IP" "$LIMPEZA" || true' EXIT
scp "${SSH_OPCOES[@]}" configuracao.sh "ubuntu@$IP:$DESTINO"

COMANDO='sudo env'
for variavel in BRANCH_DATABASE BRANCH_WEBSITE BRANCH_JAVA BRANCH_FILTRO BRANCH_CAPTURA SQL_INICIAL; do
    if [ -v "$variavel" ]; then
        printf -v VALOR ' %s=%q' "$variavel" "${!variavel}"
        COMANDO+="$VALOR"
    fi
done
printf -v EXECUCAO ' bash %q' "$DESTINO"
ssh "${SSH_OPCOES[@]}" "ubuntu@$IP" "$COMANDO$EXECUCAO"
echo "Setup atualizado. Aplicações ainda não foram iniciadas automaticamente."

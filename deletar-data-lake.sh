#!/bin/bash
# Executar no computador local, sem sudo

set -Eeuo pipefail

trap 'echo "Erro na linha $LINENO durante a exclusão do Data Lake." >&2' ERR

# Trabalha na pasta onde este script está salvo
cd "$(dirname "$0")"

export AWS_DEFAULT_REGION=us-east-1
export AWS_PAGER=""

# Mesmo nome utilizado no criar-ec2.sh
BUCKET_DATALAKE="bucket-coretrace"


# ============================================================
# CONFERE AS CREDENCIAIS AWS
# ============================================================

aws sts get-caller-identity >/dev/null


# ============================================================
# VERIFICA SE O DATA LAKE EXISTE
# ============================================================

BUCKET_EXISTE=$(aws s3api list-buckets \
    --query "Buckets[?Name=='$BUCKET_DATALAKE'].Name" \
    --output text)


if [ "$BUCKET_EXISTE" = "$BUCKET_DATALAKE" ]; then

    echo "Data Lake encontrado: $BUCKET_DATALAKE"

    read -r -p "Para apagar todos os dados, digite o nome do bucket: " CONFIRMACAO
    if [ "$CONFIRMACAO" != "$BUCKET_DATALAKE" ]; then
        echo "Exclusão cancelada."
        exit 1
    fi

    # ========================================================
    # ESVAZIA O DATA LAKE
    # ========================================================

    echo "Excluindo arquivos do Data Lake..."

    aws s3 rm \
        "s3://$BUCKET_DATALAKE" \
        --recursive

    # ========================================================
    # EXCLUI O BUCKET
    # ========================================================

    echo "Excluindo bucket..."

    aws s3api delete-bucket \
        --bucket "$BUCKET_DATALAKE"

    echo "Data Lake excluído com sucesso."

else

    echo "Data Lake $BUCKET_DATALAKE não existe."
    echo "Nenhuma exclusão necessária."

fi
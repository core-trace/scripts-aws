#!/bin/bash
# Executar no computador local, sem sudo
set -Eeuo pipefail

trap 'echo "Erro na linha $LINENO. A instância pode já ter sido criada; confira antes de tentar novamente." >&2' ERR

# Trabalha na pasta onde este script está salvo
cd "$(dirname "$0")"

export AWS_DEFAULT_REGION=us-east-1
export AWS_PAGER=""

NOME="${NOME:-coretrace-ec2}"

IMAGEM="${IMAGEM:-}"

TIPO="${TIPO:-t3.small}"

SUBREDE="${SUBREDE:-}"

# ID do grupo de segurança em EC2 > Grupos de segurança.
# Ele deve pertencer a mesma VPC da sub-rede acima.
# ANTES de executar: Regras de entrada > Editar regras > SSH > Meu IP.
# Conferir TCP 22 e o IP público do responsável com /32, e salvar.
GRUPO="${GRUPO:-}"

# nome do par em EC2 > Pares de chaves.
# Manter vockey somente se corresponder a chave privada baixada.
# Aqui vai o NOME do par na AWS, não o caminho do arquivo .pem.
CHAVE="${CHAVE:-vockey}"

# Opcional: nome do instance profile já permitido no laboratório.
# Vazio mantém a criação sem role. acesso das aplicações ao S3 fica pendente
PERFIL_IAM="${PERFIL_IAM:-}"
OPCOES_IAM=()
if [ -n "$PERFIL_IAM" ]; then
    OPCOES_IAM=(--iam-instance-profile "Name=$PERFIL_IAM")
fi

# Vê se existe o arquivo de configuraçaõ antes
if [ ! -f configuracao.sh ]; then
    echo "Arquivo configuracao.sh não encontrado nesta pasta."
    exit 1
fi

bash -n configuracao.sh

# Confere as credenciais do laboratório
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

validar_imagem() {
    local nome_imagem
    nome_imagem=$(aws ec2 describe-images \
        --image-ids "$1" \
        --owners 099720109477 \
        --filters \
            'Name=name,Values=ubuntu/images/hvm-ssd-gp3/ubuntu-resolute-26.04-amd64-server-*' \
            'Name=architecture,Values=x86_64' \
            'Name=state,Values=available' \
        --query 'Images[0].Name' --output text) || return 1

    if [ -z "$nome_imagem" ] || [ "$nome_imagem" = "None" ]; then
        echo "A AMI $1 não é uma imagem oficial disponível do Ubuntu Server 26.04 LTS x86_64." >&2
        return 1
    fi
    echo "Imagem validada: $nome_imagem ($1)"
}

if [ -z "$IMAGEM" ]; then
    echo "Procurando Ubuntu Server 26.04 LTS na região $AWS_DEFAULT_REGION..."
    IMAGEM=$(aws ec2 describe-images \
        --owners 099720109477 \
        --filters \
            'Name=name,Values=ubuntu/images/hvm-ssd-gp3/ubuntu-resolute-26.04-amd64-server-*' \
            'Name=architecture,Values=x86_64' \
            'Name=state,Values=available' \
        --query 'sort_by(Images, &CreationDate)[-1].ImageId' --output text)
fi

if [ -z "$IMAGEM" ] || [ "$IMAGEM" = "None" ]; then
    echo "Nenhuma AMI oficial do Ubuntu Server 26.04 LTS encontrada."
    exit 1
fi
validar_imagem "$IMAGEM"

# Confere a instância existente antes de alterar recursos no S3.
EXISTENTES=$(aws ec2 describe-instances \
    --filters \
        "Name=tag:Name,Values=$NOME" \
        "Name=instance-state-name,Values=pending,running,stopping,stopped" \
    --query 'Reservations[].Instances[].InstanceId' \
    --output text)

if [ -n "$EXISTENTES" ]; then
    if [[ "$EXISTENTES" == *$'\t'* || "$EXISTENTES" == *$'\n'* ]]; then
        echo "Há várias instâncias chamadas $NOME. Confira no console."
        exit 1
    fi
    IMAGEM_EXISTENTE=$(aws ec2 describe-instances \
        --instance-ids "$EXISTENTES" \
        --query 'Reservations[0].Instances[0].ImageId' --output text)
    if ! validar_imagem "$IMAGEM_EXISTENTE"; then
        echo "A instância $EXISTENTES usa outra imagem e não será reutilizada."
        echo "Para criar a EC2 com Ubuntu 26.04, escolha outro NOME no script."
        echo "A instância existente não foi alterada nem excluída."
        exit 1
    fi
fi

# ============================================================
# CRIAR DATA LAKE NO S3
# ============================================================

BUCKET_DATALAKE="${BUCKET_DATALAKE:-bucket-coretrace}"

if aws s3api head-bucket --bucket "$BUCKET_DATALAKE" --expected-bucket-owner "$AWS_ACCOUNT_ID" 2>/dev/null; then

    echo "Data Lake já existe: $BUCKET_DATALAKE"
    echo "Reutilizando o bucket..."

else

    echo "Criando Data Lake: $BUCKET_DATALAKE"

    aws s3api create-bucket \
        --bucket "$BUCKET_DATALAKE" \
        --region "$AWS_DEFAULT_REGION"

    echo "Data Lake criado com sucesso."

fi


# ============================================================
# CRIAR PREFIXOS
# ============================================================

for prefixo in raw trusted client
do

    if aws s3api head-object \
        --bucket "$BUCKET_DATALAKE" \
        --key "$prefixo/" >/dev/null 2>&1
    then

        echo "$prefixo/ já existe."

    else

        echo "Criando $prefixo/..."

        aws s3api put-object \
            --bucket "$BUCKET_DATALAKE" \
            --key "$prefixo/" >/dev/null

    fi

done

echo "Data Lake pronto:"
echo "s3://$BUCKET_DATALAKE"
echo "  raw/"
echo "  trusted/"
echo "  client/"

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
    'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" mysql -uroot -e "SELECT 1 FROM servidores LIMIT 0; SELECT 1 FROM componentes LIMIT 0;" coretrace'
VERSAO=$(sudo docker exec coretrace_mysql sh -c \
    'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" mysql -uroot -Nse "SELECT COUNT(*) FROM coretrace.coretrace_schema_version WHERE versao=\"001_inicial\";"')
[ "$VERSAO" = 1 ] || { echo "Registro de instalação inicial não encontrado."; exit 1; }
SQL_SHA256=$(sudo sha256sum /opt/coretrace/database/init-ec2.sql)
SQL_SHA256=${SQL_SHA256%% *}
INSTALADO_SHA256=$(sudo docker exec coretrace_mysql sh -c \
    'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" mysql -uroot -Nse "SELECT sql_sha256 FROM coretrace.coretrace_schema_version WHERE versao=\"001_inicial\";"')
[ "$SQL_SHA256" = "$INSTALADO_SHA256" ] || { echo "Banco não corresponde ao init atual. Confira o log do setup."; exit 1; }

sudo git -C /var/www/coretrace/website rev-parse --is-inside-work-tree
for repo in database api-java api-filtro-de-captura scripts-captura; do
    sudo git -C "/opt/coretrace/$repo" rev-parse --is-inside-work-tree
done

echo "Verificação automática concluída com sucesso."
VERIFICACAO
}

# Evita criar outra instância com o mesmo nome
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
    echo "Para aplicar mudanças no setup existente, use atualizar-ec2.sh"
    exit 0
fi

echo "Criando a EC2 Ubuntu..."
USER_DATA=$(mktemp)
trap 'rm -f "$USER_DATA"' EXIT
{
    printf '#!/bin/bash\nset -Eeuo pipefail\n'
    for variavel in BRANCH_DATABASE BRANCH_WEBSITE BRANCH_JAVA BRANCH_FILTRO BRANCH_CAPTURA; do
        if [ -v "$variavel" ]; then
            printf 'export %s=%q\n' "$variavel" "${!variavel}"
        fi
    done
    printf '%s\n' 'SETUP=$(mktemp)' 'trap '\''rm -f "$SETUP"'\'' EXIT'
    printf "base64 -d <<'CORETRACE_SETUP' | gzip -dc > \"\$SETUP\"\n"
    gzip -c configuracao.sh | base64
    printf 'CORETRACE_SETUP\n'
    printf 'bash "$SETUP"\n'
} > "$USER_DATA"
if [ "$(wc -c < "$USER_DATA")" -gt 16384 ]; then
    echo "Setup excedeu o limite de 16 KiB do user data mesmo após compressão."
    exit 1
fi

INSTANCIA=$(aws ec2 run-instances \
    --image-id "$IMAGEM" \
    --instance-type "$TIPO" \
    --count 1 \
    --key-name "$CHAVE" \
    --subnet-id "$SUBREDE" \
    --security-group-ids "$GRUPO" \
    --associate-public-ip-address \
    "${OPCOES_IAM[@]}" \
    --block-device-mappings \
        '[{"DeviceName":"/dev/sda1","Ebs":{"VolumeSize":20,"VolumeType":"gp3","DeleteOnTermination":true}}]' \
    --tag-specifications \
        "ResourceType=instance,Tags=[{Key=Name,Value=$NOME}]" \
    --user-data "file://$USER_DATA" \
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

#!/bin/bash
# Esse script não deve rodar localmente

# Para rodar o configuração.sh, execute SOMENTE na EC2
# no computador local, use bash -n configuracao.sh para conferir a sintaxe.

# para rodar o configuracao.sh
# primeiro, adicione esse shell ao nano configuracao.sh
# depois, fora do nano, adicione:
# chmod +x configuracao.sh
# e por fim:
# sudo ./configuracao.sh

# Verificar se está sendo executado como root
if [ "$EUID" -ne 0 ]; then
    echo "Execute este script com sudo."
    exit 1
fi

# ADD - Previne que se algo der errado, a execução não continue
set -Eeuo pipefail
# ADD - Regra de segurança para os arquivos
umask 027
# ADD - Pra ajudar a descobrir onde deu o erro. Ele diz a linha que aconteceu
trap 'echo "ERRO na linha $LINENO" >&2' ERR
# ADD - Grava um arquivo de logs da execução do sh
exec > >(tee -a /var/log/coretrace-configuracao.log) 2>&1
# ADD - Pras linhas que tiverem interação durante a execução, ele escolhe a configuraçaõ padrão. (Nem todas te config padrão, essas precisam ser respondidas)
export DEBIAN_FRONTEND=noninteractive
# ADD - Apaga a configuração concluída da última vez que rodou
rm -f /var/lib/coretrace-configuracao-concluida

# ============================================================
# ATUALIZAR O SISTEMA
# ============================================================

echo "Atualizando o sistema..."

apt update
apt upgrade -y


# ============================================================
# CRIAR GRUPO
# ============================================================

echo "Criando grupo devs..."


# ORIGINAL: groupadd devs
# ALT - Do modo que estava antes, a gente não conseguia rodar de novo o script se o grupo já existisse. Ex: Se tivesse um erro lá embaixo mas a etapa de criação tivesse dado tudo certo ia dar erro pra rodar de novo o script
getent group devs >/dev/null || groupadd devs


# ============================================================
# CRIAR USUÁRIOS
# ============================================================

echo "Criando usuários..."


# ALT - Só cria se o usuário não existir. Se ele existir, só configura o bash pra ele

if ! id livia >/dev/null 2>&1; then
    useradd -m -s /bin/bash livia
fi
usermod -s /bin/bash livia

if ! id raphael >/dev/null 2>&1; then
    useradd -m -s /bin/bash raphael
fi
usermod -s /bin/bash raphael

if ! id marcelly >/dev/null 2>&1; then
    useradd -m -s /bin/bash marcelly
fi
usermod -s /bin/bash marcelly

if ! id vitor >/dev/null 2>&1; then
    useradd -m -s /bin/bash vitor
fi
usermod -s /bin/bash vitor

if ! id carlos >/dev/null 2>&1; then
    useradd -m -s /bin/bash carlos
fi
usermod -s /bin/bash carlos

if ! id matheus >/dev/null 2>&1; then
    useradd -m -s /bin/bash matheus
fi
usermod -s /bin/bash matheus


# ============================================================
# GARANTIR AS HOMES E O SHELL DOS USUÁRIOS
# ============================================================

mkdir -p /home/livia
mkdir -p /home/raphael
mkdir -p /home/marcelly
mkdir -p /home/vitor
mkdir -p /home/carlos
mkdir -p /home/matheus

chown livia:devs /home/livia
chown raphael:devs /home/raphael
chown marcelly:devs /home/marcelly
chown vitor:devs /home/vitor
chown carlos:devs /home/carlos
chown matheus:devs /home/matheus

chmod 755 /home/livia
chmod 755 /home/raphael
chmod 755 /home/marcelly
chmod 755 /home/vitor
chmod 755 /home/carlos
chmod 755 /home/matheus


# ============================================================
# DEFINIR SENHAS
# ============================================================

echo "Definindo senhas..."

echo "livia:coretrace123" | chpasswd
echo "raphael:coretrace123" | chpasswd
echo "marcelly:coretrace123" | chpasswd
echo "vitor:coretrace123" | chpasswd
echo "carlos:coretrace123" | chpasswd
echo "matheus:coretrace123" | chpasswd

# ============================================================
# ADICIONAR USUÁRIOS AO GRUPO DEVS
# ============================================================

echo "Adicionando usuários ao grupo devs..."

usermod -aG devs livia
usermod -aG devs raphael
usermod -aG devs marcelly
usermod -aG devs vitor
usermod -aG devs carlos
usermod -aG devs matheus

# Dar sudo ao Raphael
usermod -aG sudo raphael


# ============================================================
# CONFIGURAR DIRETÓRIO DO PROJETO
# ============================================================

echo "Configurando diretório do projeto..."

mkdir -p /opt/site-institucional


# ALT - Os subdiretorios e arquivos herdam as configurações de acesso do grupo devs com 2770
# ORIGINAL: chmod 770 /opt/site-institucional
chown root:devs /opt/site-institucional
chmod 2770 /opt/site-institucional


# ============================================================
# SFTP
# ============================================================

echo "Configurando SFTP..."

# Criar diretórios do SFTP
mkdir -p /srv/urubu
mkdir -p /srv/urubu/data

# Configurar permissões do Chroot
chown root:root /srv/urubu
chmod 755 /srv/urubu

# Criar usuário SFTP

# ALT - Cria se não existir
# ORIGINAL: useradd -m -s /bin/false urubu_sftp
if ! id urubu_sftp >/dev/null 2>&1; then
    useradd -m -s /bin/false urubu_sftp
fi

# Dar permissão de escrita na pasta data

chown -R urubu_sftp:urubu_sftp /srv/urubu/data
# ADD - Só permissoes pra usuário e grupo urubu_sftp
chmod 750 /srv/urubu/data


# ============================================================
# CHAVE PÚBLICA DO SFTP
# ============================================================

echo "Configurando chave pública do SFTP..."

# Criar local para a chave pública
mkdir -p /etc/ssh/keys/urubu_sftp

#criar nova sem substuiutuir
# ssh-keygen -t ed25519 -f ~/.ssh/coretrace-sftp -C coretrace-sftp
# Para exibir a pública: cat ~/.ssh/coretrace-sftp.pub
SFTP_PUBLIC_KEY='ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAII6Qtap1lsc1kY/B6RJQFZ8F1U/8WA3Dva0wotKzOF79 urubu-sftp-key'

# ORIGINAL: echo "$SFTP_PUBLIC_KEY" > /etc/ssh/keys/urubu_sftp/authorized_keys

# ALT - Acrescenta a chave se ainda não estiver cadastrada
touch /etc/ssh/keys/urubu_sftp/authorized_keys

if ! grep -qxF "$SFTP_PUBLIC_KEY" /etc/ssh/keys/urubu_sftp/authorized_keys; then
    echo "$SFTP_PUBLIC_KEY" >> /etc/ssh/keys/urubu_sftp/authorized_keys
fi

# Configurar permissões da chave
chown -R urubu_sftp:urubu_sftp /etc/ssh/keys/urubu_sftp

chmod 755 /etc/ssh/keys
chmod 700 /etc/ssh/keys/urubu_sftp
chmod 600 /etc/ssh/keys/urubu_sftp/authorized_keys


# ============================================================
# CONFIGURAÇÃO DO SSH / TUNELAMENTO
# ============================================================

echo "Configurando SSH e tunelamento..."

# ADD - Instala o SSH e salva a configuração anterior, se existir
apt-get install -y openssh-server
SSH_CONFIG=/etc/ssh/sshd_config.d/00-coretrace.conf
SSH_BACKUP=$(mktemp)
SSH_EXISTIA=false
if [ -f "$SSH_CONFIG" ]; then
    cp -p "$SSH_CONFIG" "$SSH_BACKUP"
    SSH_EXISTIA=true
fi

cat > "$SSH_CONFIG" <<'EOF' 

# Permitir tunelamento SSH para os usuários da equipe
Match User livia,raphael,marcelly,vitor,carlos,matheus
    AllowTcpForwarding yes
    PasswordAuthentication yes

# Configuração do SSH para o usuário SFTP
Match User urubu_sftp
    ForceCommand internal-sftp
    ChrootDirectory /srv/urubu
    PermitTTY no
    X11Forwarding no
    AllowTcpForwarding no
    AuthorizedKeysFile /etc/ssh/keys/urubu_sftp/authorized_keys
    PasswordAuthentication no
    PubkeyAuthentication yes
Match all
EOF

# Garante o diretório de execução antes de validar o SSH durante o cloud-init.
install -d -o root -g root -m 0755 /run/sshd

# Verificar configuração do SSH
if /usr/sbin/sshd -t; then
    if systemctl is-active --quiet ssh; then
        systemctl reload ssh
    else
        systemctl start ssh
    fi
else
    if [ "$SSH_EXISTIA" = true ]; then
        cp -p "$SSH_BACKUP" "$SSH_CONFIG"
    else
        rm -f "$SSH_CONFIG"
    fi
    rm -f "$SSH_BACKUP"
    echo "Configuração SSH inválida; arquivo anterior restaurado."
    exit 1
fi
rm -f "$SSH_BACKUP"


# ============================================================
# INSTALAR PYTHON
# ============================================================

if command -v python3 >/dev/null 2>&1 && \
   dpkg -s python3-pip python3-venv >/dev/null 2>&1; then

    echo "Python já está instalado."

else

    echo "Instalando Python..."

    apt install -y python3 python3-pip python3-venv

fi


# ============================================================
# INSTALAR JAVA 21
# ============================================================

if dpkg -s openjdk-21-jdk >/dev/null 2>&1; then

    echo "Java 21 já está instalado."

else

    echo "Instalando Java 21..."

    apt install -y openjdk-21-jdk

fi

# ============================================================
# INSTALAR DOCKER
# ============================================================

if command -v docker >/dev/null 2>&1; then

    echo "Docker já está instalado."

else

    echo "Instalando Docker..."

    apt install -y docker.io

fi


# Garantir que o Docker inicia automaticamente
systemctl enable docker >/dev/null


# Só inicia se não estiver rodando
if systemctl is-active --quiet docker; then

    echo "Docker já está ativo."

else

    echo "Iniciando Docker..."

    systemctl start docker

fi

# Adicionar usuários da equipe ao grupo docker
echo "Adicionando usuários ao grupo docker..."

usermod -aG docker livia
usermod -aG docker raphael
usermod -aG docker marcelly
usermod -aG docker vitor
usermod -aG docker carlos
usermod -aG docker matheus


# ============================================================
# INSTALAR MYSQL
# ============================================================
if command -v mysql >/dev/null 2>&1 && \
   dpkg -s mysql-server >/dev/null 2>&1; then

    echo "MySQL já está instalado."

else

    echo "Instalando MySQL..."

    apt install -y mysql-server

fi


# Garantir que o MySQL inicia automaticamente
systemctl enable mysql >/dev/null


# Só inicia se não estiver rodando
if systemctl is-active --quiet mysql; then

    echo "MySQL já está ativo."

else

    echo "Iniciando MySQL..."

    systemctl start mysql

fi


# Testa se o MySQL está funcionando
systemctl is-active mysql
mysql -uroot -e "SELECT 1;"


# ============================================================
# VERIFICAR INSTALAÇÕES
# ============================================================

echo ""
echo "=========================================="
echo "       VERIFICANDO O AMBIENTE"
echo "=========================================="

echo ""
echo "Python:"
python3 --version

echo ""
echo "Java:"
java -version

echo ""
echo "Docker:"
docker --version

echo ""
echo "MySQL:"
mysql --version

# ============================================================

# MYSQL NO DOCKER

# ============================================================

echo "Configurando MySQL no Docker..."

# ADD - Coloca a senha e salva num arquivo com leitura e escrita só pelo root
install -d -o root -g root -m 700 /etc/coretrace

if [ ! -f /etc/coretrace/mysql.env ]; then
    printf 'MYSQL_ROOT_PASSWORD=coretrace123\nMYSQL_DATABASE=coretrace\n' \
        > /etc/coretrace/mysql.env
fi

chmod 600 /etc/coretrace/mysql.env

# Criar volume persistente

if ! docker volume inspect coretrace_mysql_data >/dev/null 2>&1; then
    docker volume create coretrace_mysql_data
fi

# Criar container somente se ele ainda não existir
if ! docker container inspect coretrace_mysql >/dev/null 2>&1; then

    # ALT - Usa o arquivo de configuração com a senha do banco
    docker run -d \
        --name coretrace_mysql \
        --env-file /etc/coretrace/mysql.env \
        -p 127.0.0.1:3307:3306 \
        -v coretrace_mysql_data:/var/lib/mysql \
        --restart unless-stopped \
        mysql:8.0

else
    # ADD - Se o container já existe, inicia
    docker start coretrace_mysql
fi

# ADD - Inicia container existente e testa consulta real no banco antes de registrar sucesso

BANCO_PRONTO=false
for tentativa in {1..60}; do
    if docker exec coretrace_mysql sh -c 'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" mysql -uroot -Nse "SELECT 1" coretrace' >/dev/null 2>&1; then
        BANCO_PRONTO=true
        break
    fi
    sleep 5
done
if [ "$BANCO_PRONTO" != true ]; then
    docker logs --tail 50 coretrace_mysql
    echo "MySQL não ficou pronto no prazo."
    exit 1
fi
docker exec coretrace_mysql mysql --version
systemctl is-active docker ssh
touch /var/lib/coretrace-configuracao-concluida

echo ""
echo "=========================================="
echo "       CONFIGURAÇÃO CONCLUÍDA"
echo "=========================================="
echo ""
echo "A EC2 foi configurada com:"
echo "- Usuários e grupo devs"
echo "- Permissões do projeto"
echo "- SFTP"
echo "- SSH e tunelamento"
echo "- Python"
echo "- Java 21"
echo "- Docker"
echo "- MySQL"
echo "- MySQL no Docker"
echo ""

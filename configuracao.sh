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
exec 9>/var/lock/coretrace-configuracao.lock
flock -n 9 || { echo "Outra configuração já está em execução."; exit 1; }

# Branches de implantação
BRANCH_DATABASE="${BRANCH_DATABASE:-main}"
BRANCH_WEBSITE="${BRANCH_WEBSITE:-dev}"
BRANCH_JAVA="${BRANCH_JAVA:-main}"
BRANCH_FILTRO="${BRANCH_FILTRO:-main}"
BRANCH_CAPTURA="${BRANCH_CAPTURA:-main}"
# Site em /var/www; código dos demais serviços e SQLs em /opt
PASTA_WEB=/var/www/coretrace
PASTA_SERVICOS=/opt/coretrace
# No teste antes do PR, pode apontar para o SQL local enviado separadamente à EC2.
SQL_INICIAL="${SQL_INICIAL:-$PASTA_SERVICOS/database/init-ec2.sql}"
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

# Ferramentas para clonar e preparar aplicações fora do Docker
apt install -y git openssh-client nodejs npm maven


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
# CONFIGURAR DIRETÓRIOS DO PROJETO
# ============================================================

echo "Configurando diretórios do projeto..."

install -d -o root -g root -m 755 /var/www

# Os novos arquivos herdam o grupo devs
install -d -o root -g devs -m 2770 "$PASTA_WEB"
install -d -o root -g devs -m 2770 "$PASTA_SERVICOS"

if [ -e "$PASTA_SERVICOS/website" ]; then
    echo "Site encontrado no caminho antigo: $PASTA_SERVICOS/website."
    echo "Confira e transfira-o para $PASTA_WEB/website antes de reaplicar o setup."
    echo "Nenhum arquivo foi movido ou apagado automaticamente."
    exit 1
fi

# ============================================================
# CLONAR OU ATUALIZAR REPOSITÓRIOS
# ============================================================
preparar_repositorio() (
    local nome="$1" branch="$2"
    local pasta="$3/$nome"
    local url="https://github.com/core-trace/$nome.git"
    local url_ssh="git@github.com:core-trace/$nome.git"
    local chaves="${CHAVES_GITHUB:-/etc/coretrace/github}"
    local chave="$chaves/$nome"
    local origem
    case "$nome" in
        database|api-java|scripts-captura)
            if [ ! -s "$chave" ]; then
                echo "core-trace/$nome é privado e falta sua chave em $chave."
                echo "Na EC2, execute preparar-github.sh e cadastre a chave pública no GitHub."
                echo "Depois, reaplique o setup com atualizar-ec2.sh."
                exit 1
            fi
            ;;
    esac
    if [ -f "$chave" ]; then
        if [ ! -s "$chaves/known_hosts" ]; then
            echo "Falta $chaves/known_hosts. Execute preparar-github.sh na EC2."
            exit 1
        fi
        case "$(stat -c %a "$chave")" in
            400|600) ;;
            *) echo "Ajuste a permissão de $chave para 600 antes de continuar."; exit 1 ;;
        esac
        printf -v GIT_SSH_COMMAND 'ssh -F /dev/null -i %q -o IdentitiesOnly=yes -o BatchMode=yes -o StrictHostKeyChecking=yes -o UserKnownHostsFile=%q -o GlobalKnownHostsFile=/dev/null -o ConnectTimeout=10' "$chave" "$chaves/known_hosts"
        export GIT_SSH_COMMAND
        url="$url_ssh"
    fi
    umask 002
    if [ -e "$pasta" ]; then
        origem=$(git -C "$pasta" config --get remote.origin.url) || exit 1
        if [ ! -d "$pasta/.git" ] || { [ "$origem" != "https://github.com/core-trace/$nome.git" ] && [ "$origem" != "$url_ssh" ]; }; then
            echo "Confira $pasta: diretório existente não corresponde ao repositório esperado."
            exit 1
        fi
        if [ -n "$(git -C "$pasta" status --porcelain)" ]; then
            echo "Há alterações locais em $pasta. Nenhum arquivo será descartado."
            exit 1
        fi
        if [ "$(git -C "$pasta" symbolic-ref --short -q HEAD)" != "$branch" ]; then
            echo "$pasta está em outra branch. Selecione $branch manualmente antes de atualizar."
            exit 1
        fi
    fi
    if ! GIT_TERMINAL_PROMPT=0 git ls-remote --exit-code "$url" "refs/heads/$branch" >/dev/null; then
        echo "Não foi possível acessar core-trace/$nome na branch $branch."
        echo "Se o repositório for privado, prepare sua deploy key com preparar-github.sh e autorize a chave pública no GitHub."
        echo "Não coloque tokens ou chaves privadas no setup ou no user data."
        exit 1
    fi
    if [ ! -e "$pasta" ]; then
        GIT_TERMINAL_PROMPT=0 git clone --branch "$branch" --single-branch "$url" "$pasta"
    else
        # Só alterna HTTPS/SSH depois de validar repositório, branch e acesso
        git -C "$pasta" remote set-url origin "$url"
        GIT_TERMINAL_PROMPT=0 git -C "$pasta" fetch origin "refs/heads/$branch"
        git -C "$pasta" merge --ff-only FETCH_HEAD
    fi
)

preparar_repositorio database "$BRANCH_DATABASE" "$PASTA_SERVICOS"
preparar_repositorio website "$BRANCH_WEBSITE" "$PASTA_WEB"

# Garantir que o website pertença ao grupo devs
chgrp -R devs "$PASTA_WEB/website"

# Permitir leitura e acesso ao grupo devs, bloqueando outros usuários
chmod -R g+rX,o-rwx "$PASTA_WEB/website"

preparar_repositorio api-java "$BRANCH_JAVA" "$PASTA_SERVICOS"
preparar_repositorio api-filtro-de-captura "$BRANCH_FILTRO" "$PASTA_SERVICOS"
preparar_repositorio scripts-captura "$BRANCH_CAPTURA" "$PASTA_SERVICOS"

# Usa o init da EC2, importado somente quando o banco está vazio.
if [ ! -s "$SQL_INICIAL" ]; then
    echo "SQL inicial não encontrado: $SQL_INICIAL."
    exit 1
fi


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

# O Maven pode instalar o Java padrão do Ubuntu (25), mesmo com o 21 presente.
# Seleciona explicitamente o runtime e o compilador usados pelo projeto.
JAVA21_HOME="/usr/lib/jvm/java-21-openjdk-$(dpkg --print-architecture)"
if [ ! -x "$JAVA21_HOME/bin/java" ] || [ ! -x "$JAVA21_HOME/bin/javac" ]; then
    echo "JDK 21 não encontrado em $JAVA21_HOME."
    exit 1
fi
update-alternatives --set java "$JAVA21_HOME/bin/java"
update-alternatives --set javac "$JAVA21_HOME/bin/javac"
export JAVA_HOME="$JAVA21_HOME"

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

# ============================================================
# INICIALIZAR AS TABELAS SEM APAGAR DADOS
# ============================================================
mysql_projeto() {
    docker exec -i coretrace_mysql sh -c \
        'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" mysql --default-character-set=utf8mb4 -uroot "$@"' sh "$@"
}

tabelas=$(mysql_projeto -Nse "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='coretrace';")
sql_sha256=$(sha256sum "$SQL_INICIAL")
sql_sha256=${sql_sha256%% *}
instalacao_nova=false
if [ "$tabelas" -eq 0 ]; then
    echo "Banco vazio: importando tabelas e dados iniciais da apresentação..."
    mysql_projeto < "$SQL_INICIAL"
    instalacao_nova=true
else
    marcador=$(mysql_projeto -Nse "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='coretrace' AND table_name='coretrace_schema_version';")
    if [ "$marcador" -ne 1 ]; then
        echo "O banco já tem tabelas, mas não tem registro desta instalação. Dados preservados."
        echo "Confira o banco manualmente antes de continuar; o SQL não será reaplicado."
        exit 1
    fi
    echo "Banco existente: verificando se corresponde ao init atual."
fi

# Confere todas as tabelas
for tabela in empresa endereco nivel_acesso permissoes nivel_acesso_permissoes usuario \
    perfil_servidor usuario_perfil_servidor servidores componentes componentes_perfil; do
    mysql_projeto coretrace -e "SELECT 1 FROM \`$tabela\` LIMIT 0;"
done

# o init do repositório
if [ "$instalacao_nova" = true ]; then
    mysql_projeto -e "CREATE TABLE IF NOT EXISTS coretrace.coretrace_schema_version (versao VARCHAR(50) PRIMARY KEY, sql_sha256 CHAR(64), aplicada_em TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP);"
    coluna=$(mysql_projeto -Nse "SELECT COUNT(*) FROM information_schema.columns WHERE table_schema='coretrace' AND table_name='coretrace_schema_version' AND column_name='sql_sha256';")
    if [ "$coluna" -eq 0 ]; then
        mysql_projeto -e "ALTER TABLE coretrace.coretrace_schema_version ADD COLUMN sql_sha256 CHAR(64);"
    fi
    mysql_projeto -e "INSERT INTO coretrace.coretrace_schema_version (versao, sql_sha256) VALUES ('001_inicial', '$sql_sha256') ON DUPLICATE KEY UPDATE sql_sha256=VALUES(sql_sha256);"
fi

versao=$(mysql_projeto -Nse "SELECT COUNT(*) FROM coretrace.coretrace_schema_version WHERE versao='001_inicial';")
if [ "$versao" -ne 1 ]; then
    echo "Instalação inicial incompleta. Dados preservados; confira o banco manualmente."
    exit 1
fi

checksum_disponivel=$(mysql_projeto -Nse "SELECT COUNT(*) FROM information_schema.columns WHERE table_schema='coretrace' AND table_name='coretrace_schema_version' AND column_name='sql_sha256';")
if [ "$checksum_disponivel" -ne 1 ]; then
    echo "Banco instalado com init antigo, sem checksum. Dados preservados."
    echo "Atualizar o Git não atualiza o MySQL. É necessária uma migração antes de concluir o setup."
    exit 1
fi
checksum_instalado=$(mysql_projeto -Nse "SELECT sql_sha256 FROM coretrace.coretrace_schema_version WHERE versao='001_inicial';")
if [ "$checksum_instalado" != "$sql_sha256" ]; then
    echo "O init-ec2.sql mudou desde a instalação deste banco. Dados preservados; SQL não reaplicado."
    echo "Prepare uma migração para atualizar o banco existente ou teste em uma EC2 com banco vazio."
    exit 1
fi
echo "Banco validado com o init atual (SHA-256: $sql_sha256)."

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
echo "- Site em $PASTA_WEB/website"
echo "- APIs, scripts e SQLs em $PASTA_SERVICOS"
echo "- Tabelas e dados iniciais no MySQL Docker (127.0.0.1:3307/coretrace)"
echo "Aplicações clonadas; dependências e inicialização dos serviços são a próxima etapa."
echo ""

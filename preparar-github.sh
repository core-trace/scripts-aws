#!/bin/bash
# Executar SOMENTE na EC2. Gera uma chave por repositório privado informado.
# Exemplo: sudo bash preparar-github.sh database api-java
set -Eeuo pipefail
if [ "$EUID" -ne 0 ]; then
    echo "Execute com sudo, somente na EC2."
    exit 1
fi
if [ "$#" -eq 0 ]; then
    echo "Uso: sudo bash preparar-github.sh REPOSITORIO [REPOSITORIO...]"
    echo "Nomes: database website api-java api-filtro-de-captura scripts-captura"
    exit 1
fi
# Valida todos os nomes antes de criar arquivos.
for repo in "$@"; do
    case "$repo" in
        database|website|api-java|api-filtro-de-captura|scripts-captura) ;;
        *) echo "Repositório não previsto: $repo"; exit 1 ;;
    esac
done
command -v ssh-keygen >/dev/null || { echo "Instale openssh-client antes de continuar."; exit 1; }
umask 077
PASTA=/etc/coretrace/github
install -d -o root -g root -m 700 /etc/coretrace "$PASTA"

if [ ! -e "$PASTA/known_hosts" ]; then
    printf '%s\n' 'github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl' > "$PASTA/known_hosts"
fi

for repo in "$@"; do
    chave="$PASTA/$repo"
    if [ ! -e "$chave" ]; then
        ssh-keygen -q -t ed25519 -N '' -C "coretrace-ec2-$repo" -f "$chave"
    fi
    chmod 600 "$chave"
    # Recria só a pública, se estiver ausente. não substitui uma privada existente.
    if [ ! -s "$chave.pub" ]; then
        ssh-keygen -y -P '' -f "$chave" > "$chave.pub"
    fi
    echo ""
    echo "core-trace/$repo: cadastre a chave PÚBLICA abaixo em Settings > Deploy keys."
    echo "Mantenha Allow write access desmarcado."
    cat "$chave.pub"
done
echo ""
echo "Depois de cadastrar as públicas, execute atualizar-ec2.sh no computador local."
echo "As chaves privadas permanecem na EC2; não as envie ao GitHub nem ao Git."

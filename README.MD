<a name="topo"></a>
<div align="center">
  <h1>Scripts AWS</h1>
  <p><strong>Criar e configurar instâncias EC2 na AWS</strong></p>
  <p>Automatiza a criação e configuração de servidores na nuvem AWS com scripts simples, mas eficientes</p>
  <p>
    <a href="#etapa-1">Arquivos</a> &nbsp;·&nbsp;
    <a href="#etapa-2">Preparar o computador</a> &nbsp;·&nbsp;
    <a href="#etapa-3">Credenciais do lab</a> &nbsp;·&nbsp;
    <a href="#etapa-6">Alterações obrigatórias no script</a> &nbsp;·&nbsp;
    <a href="#etapa-8">Execução do script</a> &nbsp;·&nbsp;
    <a href="#etapa-10">Exclusão</a>
  </p>
</div>

---

## Roteiro de execução

<details>
<summary><strong>Etapas do roteiro</strong></summary>

- [1. Baixar e conferir a pasta](#etapa-1)
- [2. Preparar o computador](#etapa-2)
- [3. Configurar as credenciais do AWS Academy Learner Lab](#etapa-3)
- [4. Preparar a chave de acesso pra EC2](#etapa-4)
- [5. Verificar o par de chaves na AWS](#etapa-5)
- [6. Escolher a sub-rede](#etapa-6)
- [7. Configurar o grupo de segurança](#etapa-7)
- [8. Conferir e executar o script](#etapa-8)
- [9. Confirmar a conclusão](#etapa-9)
- [10. Excluir a EC2 e seus volumes](#etapa-10)
- [11. Excluir o Data Lake](#etapa-11)

</details>

---

<a name="etapa-1"></a>

## 1. Baixar e conferir a pasta

Clone o repositório `scripts-aws`

Confira se estes quatro arquivos estão juntos na mesma pasta:

- `criar-ec2.sh`: executado no seu **computador local** para criar a infraestrutura na AWS
- `configuracao.sh`: enviado automaticamente pelo primeiro script pra configurar a instância
- `deletar-ec2.sh`: executado no **computador local** para deletar a infraestrutura na AWS
- `deletar-data-lake.sh`: executado no **computador local** para deletar a infraestrutura do Data Lake na AWS

Este roteiro utiliza esses quatro arquivos para criar, configurar e deletar instâncias EC2 na AWS.

Antes de executar, será necessário preparar o terminal, configurar o acesso na AWS e preencher os dados da instância no script `criar-ec2.sh`

<p align="right"><a href="#topo">↑ Voltar ao topo</a></p>

---

<a name="etapa-2"></a>

## 2. Preparar o computador

Abra o terminal e confirme se a AWS CLI e o SSH estão instalados:

```bash
aws --version
ssh -V
```

A AWS CLI serve para executar os comandos da AWS. O SSH permite acessar a instância criada na nuvem.

Se os dois comandos mostrarem suas versões e a AWS CLI aparecer como `aws-cli/2...`, pode avançar para o próxmo passo.

**Caso algum programa esteja faltando:**

<details open>
<summary><strong>Ubuntu/Debian</strong></summary>

Em Ubuntu/Debian instale as ferramentas:

```bash
sudo apt update
sudo apt install -y curl unzip openssh-client
```

Se a AWS CLI estiver faltando, confira a arquitetura do computador:

```bash
uname -m
```

Para resultado `x86_64`, execute:

```bash
mkdir -p ~/Downloads/instalador-aws-cli
cd ~/Downloads/instalador-aws-cli
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o awscliv2.zip
unzip awscliv2.zip
sudo ./aws/install
```

</details>

<details>
<summary><strong>Arch Linux</strong></summary>

Pra quem usa Arch Linux:

```bash
sudo pacman -Syu --needed aws-cli-v2 openssh
```

</details>

Quando terminar confirme se deu tudo certo com:

```bash
aws --version
ssh -V
```

Os dois comandos devem mostrar suas versões baixadas

<p align="right"><a href="#topo">↑ Voltar ao topo</a></p>

---

<a name="etapa-3"></a>

## 3. Configurar as credenciais do AWS Academy Learner Lab

**1. Iniciar o laboratório**

<details>
<summary><strong>Ver print</strong></summary>

<p align="center">
  <img src="assets/acesso-moodle.png" alt="Acesso ao AWS Login na disciplina SO em nuvem" width="813">
</p>

</details>

Acesse o AWS Academy Learner Lab pelo Moodle > SO em nuvem, e clique em **Start Lab**. Aguarde o indicador da AWS ficar verde.

<details>
<summary><strong>Ver print</strong></summary>

<p align="center">
  <img src="assets/start-lab.png" alt="Botão Start Lab no AWS Academy Learner Lab" width="1000">
</p>

</details>

**2. Copiar as credenciais**

Abra **AWS Details** e, na seção **AWS CLI**, clique em **Show**.

<details>
<summary><strong>Ver print</strong></summary>

<p align="center">
  <img src="assets/aws-details.png" alt="AWS Details e botão Show das credenciais AWS CLI" width="500">
</p>

</details>

Copie todo bloco que contém estes campos:

```ini
[default]
aws_access_key_id=...
aws_secret_access_key=...
aws_session_token=...
```

**3. Salvar as credenciais no computador**

No terminal do seu computador, crie a pasta de configuração:

```bash
mkdir -p ~/.aws
chmod 700 ~/.aws
```

Abra o arquivo de credenciais em um editor. Por exemplo, se você tiver o Nano:

```bash
nano ~/.aws/credentials
```

Se já tiver dados, substitua pelos mais recentes que você acabou de pegar no console da AWS.

No Nano, salve com **Ctrl + O**, confirme com **Enter** e saia com **Ctrl + X**.

Restrinja o acesso ao arquivo:

```bash
chmod 600 ~/.aws/credentials
```

> [!WARNING]
> As credenciais devem ficar nesse arquivo separado. Não coloque elas no script, na pasta do projeto e MUITO MENOS no Github

**4. Testar a comunicação**

Execute sem o `sudo`:

```bash
aws sts get-caller-identity --region us-east-1 --no-cli-pager
```

Se funcionar, vai aparecer uma resposta com os campos `UserId`, `Account` e `Arn`. Isso confirma que o terminal conseguiu se autenticar na AWS usando as credenciais.

Se aparecer `ExpiredToken`, copie de novo as credenciais do laboratório da AWS e atualize o arquivo.

> [!WARNING]
> IMPOSTANTE: As credenciais são temporárias, quando elas expirarem ou quando você encerrar o laboratório, será necessário repetir esse passo para pegar novas credenciais atualizadas.

<p align="right"><a href="#topo">↑ Voltar ao topo</a></p>

---

<a name="etapa-4"></a>

## 4. Preparar a chave de acesso pra EC2

**1. Baixar a chave do laboratório**

Ainda no **AWS Details**, procure a opção **Download PEM** pra baixar a chave SSH.

<details>
<summary><strong>Ver print</strong></summary>

<p align="center">
  <img src="assets/download-pem.png" alt="Botão Download PEM para baixar a chave do laboratório" width="477">
</p>

</details>

Salve o arquivo no computador. Automaticamente, ele é baixado com o nome `labsuser.pem`, se não for esse o nome do arquivo, renomeie para `labsuser.pem`. Não altere a extensão do arquivo.

**2. Guardar a chave na pasta certa**

No terminal, execute:

```bash
mkdir -p ~/.ssh
chmod 700 ~/.ssh
```

Se a chave estiver em `~/Downloads/labsuser.pem`, copie para a pasta de chaves SSH:

```bash
cp -i ~/Downloads/labsuser.pem ~/.ssh/labsuser.pem
```

Se estiver em outra pasta, ajuste o caminho de origem.

**3. Ajustar a permissão da chave**

```bash
chmod 400 ~/.ssh/labsuser.pem
```

Essa permissão permite que só seu usuário leia a chave.

**4. Conferir o arquivo**

```bash
ls -l ~/.ssh/labsuser.pem
```

A linha das permissões deve aparecer assim no começo:

```bash
-r--------
```

> [!WARNING]
> A chave `.pem` é privada. Nunca coloque o conteúdo dela no script e nem envie o arquivo pro GitHub.

<p align="right"><a href="#topo">↑ Voltar ao topo</a></p>

---

<a name="etapa-5"></a>

## 5. Verificar o par de chaves na AWS

**1. Abra o console da AWS**

Clique em **AWS** com a bolinha verde para abrir o console.

**2. Conferir a região**

No canto superior direito do console, selecione **Norte da virgínia — `us-east-1`** se não tiver selecionado. Essa é a região usada no script e precisa estar batendo.

<details>
<summary><strong>Ver print</strong></summary>

<p align="center">
  <img src="assets/norte-virginia.png" alt="Seleção da região Norte da Virgínia us-east-1" width="831">
</p>

</details>

**3. Abrir lista de pares de chaves**

Na barra de pesquisa digite **EC2** e abra o serviço

No menu lateral do EC2, procure a seção **Rede e segurança**

Clique em **Pares de chaves**

<details>
<summary><strong>Ver print</strong></summary>

<p align="center">
  <img src="assets/pares-chaves-ec2.png" alt="Pares de chaves no menu Rede e segurança do EC2" width="448">
</p>

</details>

**4. Procurar o par `vockey`**

Na lista, procure um par que o nome seja exatamente:

```text
vockey
```

Se ele aparecer, o nome corresponde ao valor configurado no script:

```bash
CHAVE=vockey
```

O nome `vockey` identifica o par na AWS. O arquivo `labsuser.pem` é a chave privada baixada do laboratório e salva no computador. Esse é o "par"

<p align="right"><a href="#topo">↑ Voltar ao topo</a></p>

---

<a name="etapa-6"></a>

## 6. Escolher a sub-rede

**1. Localizar as configurações de rede**

Ainda na tela **Executar instância**, vá até **Configurações de rede** e clique em **Editar**.

**2. Conferir a VPC**

No campo **VPC**, selecione a rede padrão e anote o **ID da VPC**, que começa com `vpc-`. O grupo de segurança escolhido na próxima etapa deve pertencer a essa mesma VPC.

**3. Selecionar uma sub-rede**

No campo **Sub-rede**, selecione uma opção dessa mesma VPC e copie seu id que começa com

```text
subnet-
```

<details>
<summary><strong>Ver print</strong></summary>

<p align="center">
  <img src="assets/subrede.png" alt="Campo Sub-rede e identificador da sub-rede selecionada" width="682">
</p>

</details>

Pro acesso SSH pela internet funcionar, a sub-rede precisa ter uma rota para um **Internet gateway**.

**4. Preencher o script**

No arquivo `criar-ec2.sh`, localize:

```bash
SUBREDE= #COLOCAR
```

Substitua pelo ID escolhido:

```bash
SUBREDE="subnet-ID_COPIADO"
```

A nível de curiosidade: O script já solicita um IP público para a EC2. A rota para o Internet gateway que dá pra consultar noo serviço VPC > Subredes > Tabela de rotas permite que esse IP seja usado para o acesso pela internet

<p align="right"><a href="#topo">↑ Voltar ao topo</a></p>

---

<a name="etapa-7"></a>

## 7. Configurar o grupo de segurança

**1. Abrir os grupos de segurança**

No console, acesse **EC2 → Rede e segurança → Grupos de segurança**.

**2. Escolher ou criar um grupo**

Clique em **Criar grupo de segurança** e preencha:

- **Nome:** `coretrace-sg`
- **Descrição:** `Acesso SSH a EC2 do Coretrace`
- **VPC:** a mesma VPC da sub-rede escolhida na fase anterior

**3. Liberar o acesso SSH**

Nas **Regras de entrada**, adicione:

| Campo | Valor |
|---|---|
| Tipo | SSH |
| Protocolo | TCP |
| Porta | 22 |
| Origem | Meu IP |

A origem deve mostrar seu IP público seguido de `/32`.

Para restringir o SSH aos IPs autorizados, não pode existir outra regra liberando a porta 22 para `0.0.0.0/0`

**4. Conferir as regras de saída**

Para a configuração automática baixar pacotes e imagens Docker, mantenha a regra de saída padrão:

- **Tipo:** Todo o tráfego / All traffic
- **Destino:** `0.0.0.0/0`

Clique em **Criar grupo de segurança**

**5. Copiar o ID do grupo**

Copie o **ID do grupo de segurança**, que começa com `sg-`.

No arquivo `criar-ec2.sh`, localize:

```bash
GRUPO= #COLOCAR
```

Substitua pelo ID real:

```bash
GRUPO="sg-ID_COPIADO"
```

Salve o arquivo

<p align="right"><a href="#topo">↑ Voltar ao topo</a></p>

---

<a name="etapa-8"></a>

## 8. Conferir e executar o script

Esta etapa deve ser feita **somente pelo integrante responsável por criar a EC2**, no computador local.

**1. Abrir o terminal na pasta `scripts-aws`**

Abra o terminal na pasta onde estão os scripts.


**2. Verificar a sintaxe dos scripts**

Execute os comandos separadamente:

```bash
bash -n criar-ec2.sh
```

```bash
bash -n configuracao.sh
```

Se não aparecer nenhuma mensagem, a sintaxe passou na verificação. Se aparecer um erro, corrija antes de continuar.

**3. Executar a criação**

Execute **sem `sudo`**:

```bash
bash criar-ec2.sh
```

Esse comando cria ou reutiliza o bucket S3 configurado, prepara os prefixos `bronze`, `silver` e `gold` e cria a EC2 caso não exista uma instância com o nome configurado.

O `configuracao.sh` é enviado automaticamente para executar dentro da EC2.

**4. Aguardar a conclusão**

Mantenha o terminal aberto. O script vai aguardar a EC2 iniciar, vai tentar conectar por SSH e vai verificar a configuração.

Ao concluir com sucesso, deve aparecer:

```text
Verificação automática concluída com sucesso.
```

Quando uma nova instância é criada, o script também salva:

- `instancia-id.txt`: identificador da EC2.
- `instancia-ip.txt`: IP público da EC2.

Se tiver um erro, salve a mensagem e confira o estado da instância no console antes de tentar de novo. Ela pode já ter sido criada mas estar subindo ainda.

<p align="right"><a href="#topo">↑ Voltar ao topo</a></p>

---

<a name="etapa-9"></a>

## 9. Confirmar a conclusão

A execução termina quando aparece:

```text
Verificação automática concluída com sucesso.
```

Essa mensagem confirma que a configuração automática terminou e que as verificações do Docker, do MySQL e do banco `CoreTrace` passaram.

Para acessar o servidor, execute no computador do responsável:

```bash
ssh -i ~/.ssh/labsuser.pem ubuntu@IP_PUBLICO_DA_EC2
```

Substitua `IP_PUBLICO_DA_EC2` pelo endereço informado pelo script em `instancia-ip.txt` ou no console da AWS

Se ocorrer `Connection timed out`, confira se o IP público atual do computador está autorizado na porta 22 do grupo de segurança.

Após corrigir a regra, execute novamente:

```bash
bash criar-ec2.sh
```

O script reutiliza a instância existente chamada `coretrace-ec2` e tenta verificar sua configuração.

<p align="right"><a href="#topo">↑ Voltar ao topo</a></p>

---

<a name="etapa-10"></a>

## 10. Excluir a EC2 e seus volumes

> [!WARNING]
> **A exclusão é definitiva:** os arquivos da EC2, os containers e os dados MySQL armazenados nos volumes excluídos serão perdidos. Faça backup dos dados que deseja guardar antes de continuar.

Na pasta `scripts-aws`, confira o ID salvo pelo script de criação:

```bash
cat instancia-id.txt
```

Confira no console se esse ID corresponde a instância que deseja excluir. Depois execute, sem `sudo`:

```bash
bash deletar-ec2.sh
```

O script mostra a conta AWS, a região, o ID e o nome da instância e os volumes EBS ligados a ela. Pra autorizar a exclusão, digite o ID completo da instância quando for solicitado. Qualquer outro texto cancela antes de alterar os recursos.

Para excluir outra instância do Coretrace, como por exemplo uma EC2 de teste, informe o ID completo dela no comando:

```bash
bash deletar-ec2.sh i-ID_DA_INSTANCIA
```

O script aceita instâncias com nome `coretrace-ec2` ou começando com `coretrace-ec2-`.

Ao terminar, deve aparecer:

```text
EC2 i-ID_DA_INSTANCIA e seus volumes EBS excluídos com sucesso.
```

O Data Lake S3, snapshots, VPC, sub-rede, grupos de segurança e pares de chaves são preservados.

<p align="right"><a href="#topo">↑ Voltar ao topo</a></p>

---

<a name="etapa-11"></a>

## 11. Excluir o Data Lake

O script `deletar-data-lake.sh` é separado da exclusão da EC2. Ele remove os objetos atuais e tenta excluir o bucket `coretrace-data-lake-sptech-grupo7-2026`

Execute no computador local e sem `sudo`:

```bash
bash deletar-data-lake.sh
```

<p align="right"><a href="#topo">↑ Voltar ao topo</a></p>

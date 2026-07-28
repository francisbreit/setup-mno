#!/usr/bin/bash
#########################################################
#########################################################
#
#    LOADING
#
export NEWT_COLORS='
#root=,white
#window=,black
#border=white,black
#textbox=white,black
#button=black,white

root=,white
border=black,gray
title=white,black
roottext=red,gray
window=red,gray
textbox=white,gray
button=white,green
compactbutton=white,black
listbox=black,white
actlistbox=white,black
actsellistbox=white,blue
checkbox=red,black
actcheckbox=white,blue
'  

clear


amarelo="\e[33m"   # Amarelo
branco="\e[97m"    # Branco
reset="\e[0m"      # Reseta

#
# FIM DE LOADING
#

#
# NOME DO PROGRAMA
#

{
  tput reset 2>/dev/null         # Reinicia o terminal de forma segura
  exec 0</dev/tty 1>/dev/tty 2>&1 # Força redirecionamentos explícitos
  sleep 0.01                     # Pausa microscópica para sincronia
  clear                          # Limpeza final antes do whiptail
} || true


function msg() {
		msg=$1
		whiptail --title "INSTALAÇÃO DO CHATWOOT-N: FERRAMENTA MULTICANAIS" --msgbox "$msg" --fb 10 70;
	}

  while true; do
CHOICE=$(
whiptail --title "INSTALAÇÃO DO CHATWOOT-N: FERRAMENTA MULTICANAIS" --menu "Aperte ENTER para iniciar a instalação do Chatwoot-N ou selecione SAIR (Utilize setas e Enter)\nINSTRUÇÕES\nAntes de prosseguir, apontar registros DNS para o(s) seguinte(s) dominio(s):\nRECORD A: Dê um nome para seu servidor (exemplo: manager1.seudominio.com.br) e aponte para o IP do seu servidor\nRECORD CNAME: Crie 1 subdominio para o seu Chatwoot (exemplo: atendimento.seudominio.com.br) e aponte para o nome do servidor criado (exemplo: manager1.seudominio.com.br)" 20 70 2 \
	"1)" "CONTINUAR"   \
	"2)" "SAIR"  3>&2 2>&1 1>&3	
)

case $CHOICE in
	"1)")   
		clear
        break
	;;
	
	"2)") 
       # sleep 1
        cd /
        cd
        exit 0
        ;; 
esac
#whiptail --msgbox "Pressione ENTER para voltar ao Menu Principal" 20 78
done


 #  Chatwoot variaveis - inicio

  while true ; do
		dominiochat=$(whiptail --title "URL do Chatwoot" --inputbox "Digite o dominio para acessar o Chatwoot (ex: app.dominio.com):" --fb 12 60 3>&1 1>&2 2>&3) ; saida=$?
		if [[ $saida -eq '0' ]] ; then
			if [[ -z $dominiochat ]] ; then msg "Digite o link do Chatwoot para poder continuar" ; continue ; else break; fi
		else
			echo $dominiochat ; echo "saindo..."  &  exit 0 ;
		fi
	done

  while true ; do
		nomeempresa=$(whiptail --title "Nome da Empresa" --inputbox "Digite o nome de sua empresa no Chatwoot (ex: Oficina Linhares):" --fb 12 60 3>&1 1>&2 2>&3) ; saida=$?
		if [[ $saida -eq '0' ]] ; then
			if [[ -z $nomeempresa ]] ; then msg "Digite o nome de sua Chatwoot para poder continuar" ; continue ; else break; fi
		else
			echo $nomeempresa ; echo "saindo..."  &  exit 0 ;
		fi
	done


     while true ; do
		emailchat=$(whiptail --title "Email de SMTP" --inputbox "Digite seu email de SMTP para envio de mensagens (ex: contato@dominio.com):" --fb 12 60 3>&1 1>&2 2>&3) ; saida=$?
		if [[ $saida -eq '0' ]] ; then
			if [[ -z $emailchat ]] ; then msg "Digite um email de SMTP do Chatwoot para poder continuar" ; continue ; else break; fi
		else
			echo $emailchat ; echo "saindo..."  &  exit 0 ;
		fi
	done

    hostsmtpchatwoot=$(whiptail --title "Host do SMTP" --inputbox "Pressione ENTER para configurar depois, ou digite o Host do seu SMTP (ex: mail.seudominio_smtp.com.br :" --fb 12 60 3>&1 1>&2 2>&3) ; saida=$?
		if [[ $saida -eq '0' ]] ; then if [[ -z $hostsmtpchatwoot ]] ; then hostsmtpchatwoot=mail.seudominio_smtp.com.br ; fi else echo "saindo..." ; exit ; fi


    dominiosmtpchatwoot=$(whiptail --title "Dominio do SMTP" --inputbox "Pressione ENTER para configurar depois, ou digite o Dominio do seu SMTP (ex: seudominiosmto.br :" --fb 12 60 3>&1 1>&2 2>&3) ; saida=$?
		if [[ $saida -eq '0' ]] ; then if [[ -z $dominiosmtpchatwoot ]] ; then dominiosmtpchatwoot=seudominio_smtp.com.br ; fi else echo "saindo..." ; exit ; fi

     
     smtpchatwoot=$(whiptail --title "Usuario do SMTP" --inputbox "Pressione ENTER para configurar depois, ou digite o usuario do seu SMTP (ex: suporte@seusite.com.br :" --fb 12 60 3>&1 1>&2 2>&3) ; saida=$?
		if [[ $saida -eq '0' ]] ; then if [[ -z $smtpchatwoot ]] ; then smtpchatwoot=usuario@seusite.com.br ; fi else echo "saindo..." ; exit ; fi

     portachatwoot=$(whiptail --title "Porta do SMTP" --inputbox "Pressione ENTER para configurar depois, ou digite digite a Porta SMTP (ex: 465):" --fb 12 60 3>&1 1>&2 2>&3) ; saida=$?
		if [[ $saida -eq '0' ]] ; then if [[ -z $portachatwoot ]] ; then portachatwoot=465 ; fi else echo "saindo..." ; exit ; fi
    
    senhaemailchatwoot=$(whiptail --title "Senha do SMTP" --inputbox "Pressione ENTER para configurar depois, ou digite Senha do seu Email:" --fb 12 60 3>&1 1>&2 2>&3) ; saida=$?
		if [[ $saida -eq '0' ]] ; then if [[ -z $senhaemailchatwoot ]] ; then senhaemailchatwoot=102030 ; fi else echo "saindo..." ; exit ; fi
    

# Perguntar ao usuário se deseja criar a stack no Portainer

 while true ; do
		criar_portainer=$(whiptail --title "Criar Stack no Portainer? - 0 ou 1" --inputbox "Digite 0 para poder editar stack no portainer ou 1 para não poder editar" --fb 12 60 3>&1 1>&2 2>&3) ; saida=$?
		if [[ $saida -eq '0' ]] ; then
		#	if [[ -z $senhamautic ]] ; then msg "Digite a senha do Mautic, para poder continuar" ; continue ; else break; fi
		if [[ "$criar_portainer" != "0" && "$criar_portainer" != "1" ]] ; then msg "Digite apenas o número 0 ou o número 1, para poder continuar. Digite 0 para poder editar stack no portainer ou 1 para não poder editar" ; continue ; else break; fi
    else
			echo $criar_portainer ; echo "saindo..."  &  exit 0 ;
		fi
	done


# Criando variaveis e banco

nome_principal_chatwoot="chatwoot"  #nome do app
sufixo_app=$(date | md5sum | head -c7)
nome_app_chatwoot=$nome_principal_chatwoot$sufixo_app
sufixo_traefik="_sslheader"
nome_app_chatwoot_sslheader=$nome_app_chatwoot$sufixo_traefik
postgres_password=$(grep -oP '(?<=POSTGRES_PASSWORD=).+' /root/postgres.yaml)



container_id=$(docker ps -qf name=postgres)
docker exec -it $container_id psql -U postgres -d postgres -c "CREATE  DATABASE $nome_app_chatwoot;" 

#  Chatwootn variaveis - fim


# Ajuste do terminal para garantir compatibilidade
{
  tput reset 2>/dev/null         # Reinicia o terminal de forma segura
  exec 0</dev/tty 1>/dev/tty 2>&1 # Força redirecionamentos explícitos
  sleep 0.01                     # Pausa microscópica para sincronia
  clear                          # Limpeza final antes do whiptail
} || true


    # Exibe as informações formatadas com mais espaço na tela
    whiptail --title "Dados Fornecidos" \
    --msgbox "Dados Preenchidos:\n\n1) Link do chatwoot: $dominiochat\n2) Email SMTP: $emailchat\n3) Nome da Empresa: $nomeempresa\n4) Host SMTP: $hostsmtpchatwoot\n5) Dominio SMTP: $dominiosmtpchatwoot\n6) Usuario do SMTP: $smtpchatwoot\n7) Porta SMTP: $portachatwoot\n8) Senha do Email: $senhaemailchatwoot\n9) Criar Stack no Portainer: $([ "$criar_portainer" == "0" ] && echo "0 (Editável)" || echo "1 (Não editável)")\n\nConfira e Tecle Enter para continuar. Na próxima etapa você poderá confirmar os dados ou corrigir, se necessário." \
    --fb 22 80

# Solicita confirmação dentro de um loop
while true; do
# Ajuste do terminal para garantir compatibilidade
{
  tput reset 2>/dev/null         # Reinicia o terminal de forma segura
  exec 0</dev/tty 1>/dev/tty 2>&1 # Força redirecionamentos explícitos
  sleep 0.01                     # Pausa microscópica para sincronia
  clear                          # Limpeza final antes do whiptail
} || true
    confirma1=$(whiptail --title "Confirmação" \
    --inputbox "Informações estavam corretas? Digite 'y' para confirmar e instalar ou 'n' para voltar e corrigir:" \
    --fb 10 60 3>&1 1>&2 2>&3)
    if [[ "$confirma1" =~ ^[yY]$ ]]; then
        break
    elif [[ "$confirma1" =~ ^[nN]$ ]]; then
        msg "Você digitou N e não confirmou os dados preenchidos. Tecle Enter para sair da instalação do Minio"
        exit 0
    else
        msg "Entrada inválida! Por favor, use apenas 'y' para sim ou 'n' para não. Digite Enter para continuar"
    fi
done


#
# FIM DE VERIFICAÇÃO DE DADOS
#
#########################################################
#
# MENSAGEM DE INSTALANDO
#
export NEWT_COLORS='
root=,white
window=,black
border=white,black
textbox=white,black
button=black,white
'  

clear
{

# Função para verificar o domínio


   # urlbaserow=$1
    ip_servidor=$(curl -s --max-time 10 ipinfo.io/ip)

    echo -e "XXX\n3\nVERIFICANDO SUBDOMÍNIO: $dominiochat \nXXX"
   sleep 3
    # Verifica apenas se o domínio está apontando para o IP correto
    dns_ip=$(timeout 10 nslookup $dominiochat | grep "Address" | tail -n1 | awk '{print $2}')
    if [[ "$dns_ip" != "$ip_servidor" ]]; then
        echo -e "XXX\n10\nERRO: SUBDOMÍNIO NÃO APONTA PARA O IP DO SERVIDOR ($ip_servidor) \nXXX"
    sleep 3
        echo -e "XXX\n18\nERRO: REGISTROS DNS NÃO ENCONTRADOS \nXXX"
        sleep 3
        exit 1
    fi

    echo -e "XXX\n15\nDOMÍNIO VERIFICADO COM SUCESSO \nXXX"
sleep 4


####### fim de verificando dominio 


echo -e "XXX\n24\nCRIANDO STACK DO CHATWOOT-N 1/4 \nXXX"
sleep 3
echo -e "XXX\n25\nCRIANDO STACK DO CHATWOOT-N 1/4 - CONCLUIDO \nXXX"
sleep 3 
echo -e "XXX\n25\nFAZENDO O BUILD DO STACK DO CHATWOOT-N 2/4 \nXXX"
sleep 3
echo -e "XXX\n50\nFAZENDO O BUILD DO STACK DO CHATWOOT-N 2/4 - CONCLUIDO \nXXX"
sleep 3
echo -e "XXX\n50\nCRIANDO BANCO DE DADOS DO CHATWOOT-N 3/4 \nXXX"
sleep 3
echo -e "XXX\n75\nCRIANDO BANCO DE DADOS DO CHATWOOT-N 3/4 - CONCLUIDO \nXXX"




# FIM DE MENSAGEM DE INSTALANDO
#
#######################################################
#
#  INSTALANDO O CHATWOOT
#

cd

cd

encryption_key=$(openssl rand -hex 16)

cat > $nome_app_chatwoot.yaml << EOL

version: "3.7"

##############
#
# Execute o  comando para migrar o banco:
#
# bundle exec rails db:chatwoot_prepare
#
#############

services:
  $nome_app_chatwoot-app:
    image: francisbreit/chatwoot-n:v3.10.3-pt-br
    hostname: $nome_app_chatwoot
    command: bundle exec rails s -p 3000 -b 0.0.0.0
    entrypoint: docker/entrypoints/rails.sh
    volumes:
      - $nome_app_chatwoot-data:/app/storage
      - $nome_app_chatwoot-email:/app/app/views/devise/mailer
      - $nome_app_chatwoot-local:/app/config/locales
      - $nome_app_chatwoot-webhooks:/app/lib/webhooks
    networks:
      - traefik
      - interna
    environment:
      - INSTALLATION_NAME=$nome_app_chatwoot
      - NODE_ENV=production
      - RAILS_ENV=production
      - DISABLE_DATABASE_ENVIRONMENT_CHECK=1
      - ENABLE_DB_POOLING=true
      - DB_POOL=10  # Deve ser <= max_client_conn do PgBouncer
      - PGSSLMODE=disable  # Se não usar SSL
      - INSTALLATION_ENV=docker
      - SECRET_KEY_BASE=$encryption_key
      - FRONTEND_URL=https://$dominiochat
      - DEFAULT_LOCALE=pt_BR
      - FORCE_SSL=true
      - ENABLE_ACCOUNT_SIGNUP=false
      - REDIS_URL=redis://redis:6379
      - POSTGRES_HOST=postgres
      - POSTGRES_PORT=5432
      - POSTGRES_USERNAME=postgres
      - POSTGRES_PASSWORD=$postgres_password
      - POSTGRES_DATABASE=$nome_app_chatwoot
      - DATABASE_URL=postgresql://postgres:$postgres_password@postgres:5432/$nome_app_chatwoot?prepared_statements=false
      - ACTIVE_STORAGE_SERVICE=local
      - RAILS_LOG_TO_STDOUT=true
      - USE_INBOX_AVATAR_FOR_BOT=true
      - COMPOSE_PROJECT_NAME=unochat
      - ENABLE_RACK_ATTACK=false
      - WHATSAPP_MESSAGE_WINDOW_ENABLED=false
      # Servidor de Email
      - MAILER_SENDER_EMAIL=$nomeempresa <$emailchat>
      - SMTP_DOMAIN=$dominiosmtpchatwoot
      - SMTP_ADDRESS=$hostsmtpchatwoot
      - SMTP_PORT=$portachatwoot
      - SMTP_USERNAME=$smtpchatwoot
      - SMTP_PASSWORD=$senhaemailchatwoot
      - SMTP_AUTHENTICATION=login
      - SMTP_TLS=true
      - SMTP_OPENSSL_VERIFY_MODE=peer
      - MAILER_INBOUND_EMAIL_DOMAIN=$emailchat
      - IGNORE_YOURSELF_MESSAGES=false
    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
          - node.role == manager
      #resources:
        #limits:
          #cpus: "1"
          #memory: 1024M
      labels:
        - traefik.enable=true
        - traefik.http.routers.$nome_app_chatwoot.rule=Host(\`$dominiochat\`)
        - traefik.http.routers.$nome_app_chatwoot.entrypoints=websecure
        - traefik.http.routers.$nome_app_chatwoot.tls.certresolver=letsencryptresolver
        - traefik.http.routers.$nome_app_chatwoot.priority=1
        - traefik.http.routers.$nome_app_chatwoot.service=$nome_app_chatwoot
        - traefik.http.services.$nome_app_chatwoot.loadbalancer.server.port=3000 
        - traefik.http.services.$nome_app_chatwoot.loadbalancer.passhostheader=true 
        - traefik.http.middlewares.$nome_app_chatwoot_sslheader.headers.customrequestheaders.X-Forwarded-Proto=https
        - traefik.http.routers.$nome_app_chatwoot.middlewares=$nome_app_chatwoot_sslheader@docker

  $nome_app_chatwoot-sidekiq:
    image: francisbreit/chatwoot-n:v3.10.3-pt-br
    hostname: $nome_app_chatwoot
    command: bundle exec sidekiq -C config/sidekiq.yml
    volumes:
      - $nome_app_chatwoot-data:/app/storage
      - $nome_app_chatwoot-email:/app/app/views/devise/mailer
      - $nome_app_chatwoot-local:/app/config/locales 
      - $nome_app_chatwoot-webhooks:/app/lib/webhooks

    networks:
      - traefik
      - interna
    environment:
      - INSTALLATION_NAME=$nome_app_chatwoot
      - NODE_ENV=production
      - RAILS_ENV=production
      - DISABLE_DATABASE_ENVIRONMENT_CHECK=1
      - ENABLE_DB_POOLING=true
      - DB_POOL=10  # Deve ser <= max_client_conn do PgBouncer
      - PGSSLMODE=disable  # Se não usar SSL
      - INSTALLATION_ENV=docker
      - SECRET_KEY_BASE=$encryption_key
      - FRONTEND_URL=https://$dominiochat
      - DEFAULT_LOCALE=pt_BR
      - FORCE_SSL=true
      - ENABLE_ACCOUNT_SIGNUP=false
      - REDIS_URL=redis://redis:6379
      - POSTGRES_HOST=postgres
      - POSTGRES_PORT=5432
      - POSTGRES_USERNAME=postgres
      - POSTGRES_PASSWORD=$postgres_password
      - POSTGRES_DATABASE=$nome_app_chatwoot
      - DATABASE_URL=postgresql://postgres:$postgres_password@postgres:5432/$nome_app_chatwoot?prepared_statements=false
      - ACTIVE_STORAGE_SERVICE=local
      - RAILS_LOG_TO_STDOUT=true
      - USE_INBOX_AVATAR_FOR_BOT=true
      - COMPOSE_PROJECT_NAME=unochat
      - ENABLE_RACK_ATTACK=false
      - WHATSAPP_MESSAGE_WINDOW_ENABLED=false
      # Servidor de Email
      - MAILER_SENDER_EMAIL=$nomeempresa <$emailchat>
      - SMTP_DOMAIN=$dominiosmtpchatwoot
      - SMTP_ADDRESS=$hostsmtpchatwoot
      - SMTP_PORT=$portachatwoot
      - SMTP_USERNAME=$smtpchatwoot
      - SMTP_PASSWORD=$senhaemailchatwoot
      - SMTP_AUTHENTICATION=login
      - SMTP_TLS=true
      - SMTP_OPENSSL_VERIFY_MODE=peer
      - MAILER_INBOUND_EMAIL_DOMAIN=$emailchat
      - IGNORE_YOURSELF_MESSAGES=false
    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
          - node.role == manager
      #resources:
        #limits:
          #cpus: "1"
          #memory: 1024M

volumes:
  $nome_app_chatwoot-data:
    external: true
    name: $nome_app_chatwoot-data
  $nome_app_chatwoot-email:
    external: true
    name: $nome_app_chatwoot-email
  $nome_app_chatwoot-local:
    external: true
    name: $nome_app_chatwoot-local
  $nome_app_chatwoot-webhooks:
    external: true
    name: $nome_app_chatwoot-webhooks


networks: 
  traefik: 
    external: true
    name: externa
  interna: 
    external: true
    name: interna



EOL

#docker stack deploy --prune --resolve-image always -c $nome_app_chatwoot.yaml $nome_app_chatwoot >/dev/null 2>&1

if [[ "$criar_portainer" == "0" ]]; then
    # A stack será criada no Portainer
    echo -e "XXX\n76\nCRIANDO STACK NO PORTAINER 3/4  \nXXX"
   # echo "Criando a stack no Portainer para edição."
    # Substituir pelo comando ou rotina para criar a stack no Portainer
    # Aqui pode chamar um novo script ou rotina específica, exemplo:
   ## /path/to/criar_stack_no_portainer.sh "$nome_app" "$painelpma"

#!/bin/bash

# Configurações

# Caminho para o arquivo de dados
dados_file="$HOME/dados_portainer/dados_portainer"

# Verifica se o arquivo existe
if [[ -f "$dados_file" ]]; then
    # Coleta as informações do arquivo
PORTAINER_URL=$(grep "Dominio do portainer:" "$dados_file" | cut -d':' -f2 | xargs)
ADMIN_USERNAME=$(grep "Usuario:" "$dados_file" | cut -d':' -f2 | xargs)
ADMIN_PASSWORD=$(grep "Senha:" "$dados_file" | cut -d':' -f2 | xargs)
STACK_NAME=$nome_app_chatwoot
STACK_FILE_PATH="/root/$nome_app_chatwoot.yaml"

else
   # echo "Erro: Arquivo de dados não encontrado em $dados_file."
    sleep 5
echo -e "XXX\n77\nSEM ARQUIVO DE DADOS DO PORTAINER 3/4  \nXXX"
docker stack deploy --prune --resolve-image always -c $nome_app_chatwoot.yaml $nome_app_chatwoot >/dev/null 2>&1
sleep 5
    exit 1
fi

# Função para autenticação
get_auth_token() {
    #echo "[INFO] Autenticando no Portainer..."
    echo -e "XXX\n77\nAUTENTICANDO NO PORTAINER... 3/4  \nXXX"
    RESPONSE=$(curl -sS -X POST "https://$PORTAINER_URL/api/auth" \
        -H "Content-Type: application/json" \
        -d "{\"username\": \"$ADMIN_USERNAME\", \"password\": \"$ADMIN_PASSWORD\"}")
    TOKEN=$(echo "$RESPONSE" | jq -r '.jwt')
    if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]; then
        # echo "[ERRO] Falha na autenticação."
        echo -e "XXX\n77\nFALHA NA AUTENTICAÇÃO.. 3/4  \nXXX"
sleep 5
echo -e "XXX\n78\nREVERTENDO E CRIANDO STACK PELO SERVIDOR 3/4  \nXXX"
docker stack deploy --prune --resolve-image always -c $nome_app_chatwoot.yaml $nome_app_chatwoot >/dev/null 2>&1
sleep 5
        exit 1
    fi
  #  echo "[SUCESSO] Autenticação realizada com sucesso. Token obtido."
 echo -e "XXX\n79\n[SUCESSO] AUTENTICAÇÃO OK 3/4  \nXXX"
}

# Função para obter o EndpointID
get_endpoint_id() {
   # echo "[INFO] Obtendo EndpointID..."
    echo -e "XXX\n80\n[INFO] OBTENDO ENDPOINTID 3/4  \nXXX"
    RESPONSE=$(curl -sS -X GET "https://$PORTAINER_URL/api/endpoints" \
        -H "Authorization: Bearer $TOKEN")
    ENDPOINT_ID=$(echo "$RESPONSE" | jq -r '.[0].Id')
    if [ -z "$ENDPOINT_ID" ] || [ "$ENDPOINT_ID" = "null" ]; then
        # echo "[ERRO] EndpointID não encontrado! Resposta: $RESPONSE"
        echo -e "XXX\n81\n[ERRO] ENDPOINTID NÃO ENCONTRADO 3/4  \nXXX"
        docker stack deploy --prune --resolve-image always -c $nome_app_chatwoot.yaml $nome_app_chatwoot >/dev/null 2>&1
        exit 1
    fi
     echo -e "XXX\n82\n[SUCESSO] ENDPOINTID OBTIDO: $ENDPOINT_ID  3/4  \nXXX"
    #echo "[SUCESSO] EndpointID obtido: $ENDPOINT_ID"
}

# Função para obter o SwarmID
get_swarm_id() {
   # echo "[INFO] Obtendo SwarmID..."
    echo -e "XXX\n83\n[INFO] OBTENDO SWARMID  3/4  \nXXX"
    RESPONSE=$(curl -sS -X GET "https://$PORTAINER_URL/api/endpoints/$ENDPOINT_ID/docker/swarm" \
        -H "Authorization: Bearer $TOKEN")
    SWARM_ID=$(echo "$RESPONSE" | jq -r '.ID')
    if [ -z "$SWARM_ID" ] || [ "$SWARM_ID" = "null" ]; then
        #echo "[ERRO] SwarmID não encontrado! Resposta: $RESPONSE"
        echo -e "XXX\n84\n[ERRO] SWARMID NÃO ENCONTRADO 3/4  \nXXX"
        docker stack deploy --prune --resolve-image always -c $nome_app_chatwoot.yaml $nome_app_chatwoot >/dev/null 2>&1
        exit 1
    fi
    #echo "[SUCESSO] SwarmID obtido: $SWARM_ID"
    echo -e "XXX\n85\n[SUCESSO] SWARMID OBTIDO: $SWARM_ID  3/4  \nXXX"
}

# Função para criar a stack
create_stack() {
    #echo "[INFO] Verificando existência do arquivo YAML..."
    echo -e "XXX\n86\n[INFO] VERIFICANDO SE YAML EXISTE 3/4  \nXXX"
    if [ ! -f "$STACK_FILE_PATH" ]; then
        #echo "[ERRO] Arquivo $STACK_FILE_PATH não encontrado!"
        echo -e "XXX\n87\n[ERRO] ARQUIVO $STACK_FILE_PATH NÃO ENCONTRADO 3/4  \nXXX"
        docker stack deploy --prune --resolve-image always -c $nome_app_chatwoot.yaml $nome_app_chatwoot >/dev/null 2>&1
        exit 1
    fi

    #echo "[INFO] Criando stack '$STACK_NAME' no Portainer..."
     echo -e "XXX\n88\n[INFO] CRIANDO STACK $STACK_NAME NO PORTAINER 3/4  \nXXX"
    response_output=$(mktemp)
    erro_output=$(mktemp)

    http_code=$(curl -s -o "$response_output" -w "%{http_code}"  -X POST \
        -H "Authorization: Bearer $TOKEN" \
        -F "Name=$STACK_NAME" \
        -F "file=@$STACK_FILE_PATH" \
        -F "SwarmID=$SWARM_ID" \
        -F "endpointId=$ENDPOINT_ID" \
        "https://$PORTAINER_URL/api/stacks/create/swarm/file" 2> "$erro_output")

    response=$(cat "$response_output")
    rm -f "$response_output" "$erro_output"

   # echo "[DEBUG] Resposta da criação da stack: $response"
   # echo "[DEBUG] Código HTTP: $http_code"

    if [ "$http_code" -ne 200 ]; then
       # echo "[ERRO] Erro ao criar a stack. Código HTTP: $http_code. Resposta: $response"
        echo -e "XXX\n89\n[ERRO] ERRO AO CRIAR STACK 3/4  \nXXX"
        docker stack deploy --prune --resolve-image always -c $nome_app_chatwoot.yaml $nome_app_chatwoot >/dev/null 2>&1
        exit 1
    fi

   # echo "[SUCESSO] Stack '$STACK_NAME' criada com sucesso!"
    echo -e "XXX\n90\n[SUCESSO] STACK $STACK_NAME  CRIADA COM SUCESSO 3/4  \nXXX"
}

# Fluxo de execução principal
# echo "[INFO] Iniciando processo de criação da stack..."
get_auth_token || exit 1
get_endpoint_id || exit 1
get_swarm_id || exit 1
create_stack || exit 1
# echo "[SUCESSO] Processo concluído."




elif [[ "$criar_portainer" == "1" ]]; then
    # A stack será criada diretamente no Docker
    echo "Criando a stack diretamente no Docker (não editável no Portainer)."
    docker stack deploy --prune --resolve-image always -c $nome_app_chatwoot.yaml $nome_app_chatwoot >/dev/null 2>&1
else
    # Caso inesperado (não deve ocorrer devido à validação anterior no while loop)
   # echo "Erro: valor inesperado para criar_portainer. Encerrando..."
    echo -e "XXX\n91\n[ERRO] ERRO INESPERADO PARA CRIAR STACK NO PORTAINER 3/4  \nXXX"
    sleep 5
    echo -e "XXX\n92\nREVERTENDO E CRIANDO STACK PELO SERVIDOR 3/4  \nXXX"
docker stack deploy --prune --resolve-image always -c $nome_app_chatwoot.yaml $nome_app_chatwoot >/dev/null 2>&1
sleep 5

    exit 1
fi


# FIM DE INSTALANDO O CHATWOOT
#
#######################################################


# FINALIZANDO INSTALACAO E LIBERANDO BRAND NO INSTALLATION CONFIGS
#
#######################################################

echo -e "XXX\n93\nFINALIZANDO BUILD DO CHATWOOT-N 4/4  \nXXX"

max_wait_time=600  #ajuste do tempo máximo de espera

wait_interval=60

elapsed_time=0

while [ $elapsed_time -lt $max_wait_time ]; do
	CONTAINER_ID=$(docker ps -qf name=$nome_app_chatwoot-app)
	if [ -n "$CONTAINER_ID" ]; then
		break
	fi
	sleep $wait_interval
	elaapsed_time=$((elaapsed_time + wait_interval))
done

if [ -z "$CONTAINER_ID" ]; then
	echo "O container não foi encontrado após $max_wait_time segundos."
	exit 1
fi

docker exec -it "$CONTAINER_ID" bundle exec rails db:chatwoot_prepare

sleep 20

CONTAINER_ID=$(docker ps -qf name=postgres)

if [ -z "$CONTAINER_ID" ]; then
	echo "Nenhum container Postgres com 'postgres' no nome encontrado."
	exit 1
fi

docker exec -i $CONTAINER_ID psql -U postgres <<EOF
\c $nome_app_chatwoot;
update installation_configs set locked = false;
\q
EOF
sleep 2
echo -e "XXX\n100\nFINALIZANDO BUILD DO CHATWOOT-N 4/4 - CONCLUIDO  \nXXX"

sleep 3

}|whiptail --title "CHATWOOT-N - PROGRESSO DA INSTALAÇÃO" --gauge "Aguarde a instalação dos ítens necessários" 6 60 0

cd \
#
# FIM DE FINALIZANDO INSTALACAO E LIBERANDO BRAND NO INSTALLATION CONFIGS
#
#######################################################

ip_servidor=$(curl -s --max-time 10 ipinfo.io/ip)
dns_ip=$(timeout 10 nslookup $dominiochat | grep "Address" | tail -n1 | awk '{print $2}')

if [[ "$dns_ip" != "$ip_servidor" ]]; then

whiptail --title "Mensagem" --msgbox "Não foi possivel acessar o subdominio do Chatwoot-N ($dominiochat). A instalação foi cancelada. Por favor, verifique se os apontamentos DNS estão corretos e propagados! Pressione ENTER para voltar ao Menu Principal" 20 78
 else

 whiptail --title "Mensagem" --msgbox "Parabéns, Chatwoot-N foi instalado com sucesso! Pressione ENTER para voltar ao Menu Principal" 20 78       
    fi

exit 0

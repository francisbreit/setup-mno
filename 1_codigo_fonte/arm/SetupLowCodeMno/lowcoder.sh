#!/usr/bin/bash
#########################################################
#
# LOADING
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
		whiptail --title "INSTALAÇÃO DO LOWCODER" --msgbox "$msg" --fb 10 70;
	}

  while true; do
CHOICE=$(
whiptail --title "INSTALAÇÃO DO LOWCODER" --menu "Aperte ENTER para iniciar a instalação do LOWCODER ou selecione SAIR (Utilize setas e Enter)\nINSTRUÇÕES\nAntes de prosseguir, apontar registros DNS para o(s) seguinte(s) dominio(s):\nRECORD A: Dê um nome para seu servidor (exemplo: manager1.seudominio.com.br) e aponte para o IP do seu servidor\nRECORD CNAME: Crie um subdominio para o lowcoder (exemplo: lowcoder.seudominio.com.br) a aponte para o nome do servidor criado (exemplo: manager1.seudominio.com.br)" 20 70 2 \
	"1)" "CONTINUAR"   \
	"2)" "SAIR"  3>&2 2>&1 1>&3	
)

case $CHOICE in
	"1)")   
		clear
        break
	;;
	
	"2)") 
      #  sleep 1
        cd /
        cd
        exit 0
        ;; 
esac
#whiptail --msgbox "Pressione ENTER para voltar ao Menu Principal" 20 78
done
mongodb_container=$(docker ps -qf name=mongodb)

  while true ; do
		url_lowcoder=$(whiptail --title "URL do LOWCODER" --inputbox "Digite o Link do LOWCODER (ex: lowcoder.seudominio.com):" --fb 12 60 3>&1 1>&2 2>&3) ; saida=$?
		if [[ $saida -eq '0' ]] ; then
			if [[ -z $url_lowcoder ]] ; then msg "Digite o link do lowcoder, para poder continuar" ; continue ; else break; fi
		else
			echo $url_lowcoder ; echo "saindo..."  &  exit 0 ;
		fi
	done

 if [[ ("$mongodb_container" == "") ]]; then
     while true ; do
		user_mongodb_lowcoder=$(whiptail --title "Usuario do Mongodb" --inputbox "Crie o usuario do Mongodb:" --fb 12 60 3>&1 1>&2 2>&3) ; saida=$?
		if [[ $saida -eq '0' ]] ; then
			#if [[ -z $user_mongodb ]] ; then msg "Crie e preencha o usuário do Mongodb para poder continuar" ; continue ; else break; fi
		  if [[ (-z $user_mongodb_lowcoder) || ("$user_mongodb_lowcoder" =~ [^a-zA-Z0-9]) || (${#user_mongodb_lowcoder} -gt 16) ]] ; then msg "Crie a so usuário do Mongodb, sem caracteres especiais e até 16 digitos para poder continuar" ; continue ; else break; fi
    else
			echo $user_mongodb_lowcoderb ; echo "saindo..."  &  exit 0 ;
		fi
	done
    fi

     if [[ ("$mongodb_container" == "") ]]; then
    while true ; do
		pass_mongodb_lowcoder=$(whiptail --title "Senha do Mongodb" --inputbox "Crie a senha do Mongodb (obs: use senha segura):" --fb 12 60 3>&1 1>&2 2>&3) ; saida=$?
		if [[ $saida -eq '0' ]] ; then
			#if [[ -z $mongodb_senha ]] ; then msg "Crie e preencha a senha do Mongodb para poder continuar" ; continue ; else break; fi
		  if [[ (-z $pass_mongodb_lowcoder) || ("$pass_mongodb_lowcoder" =~ [^a-zA-Z0-9]) || (${#pass_mongodb_lowcoder} -gt 16) ]] ; then msg "Crie a senha do Mongodb, sem caracteres especiais e até 16 digitos para poder continuar" ; continue ; else break; fi
    else
			echo $pass_mongodb_lowcoder ; echo "saindo..."  &  exit 0 ;
		fi
	done
    fi

   email_smtp_lowcoder=$(whiptail --title "Email do SMTP" --inputbox "Pressione ENTER para configurar depois, ou digite o email do SMTP(ex: contato@dominio.com):" --fb 12 60 3>&1 1>&2 2>&3) ; saida=$?
		if [[ $saida -eq '0' ]] ; then if [[ -z $email_smtp_lowcoder ]] ; then email_smtp_lowcoder=contato@dominio.com ; fi else echo "saindo..." ; exit ; fi

  user_smtp_lowcoder=$(whiptail --title "Usuário para o SMTP" --inputbox "Pressione ENTER para configurar depois, ou digite o usuário do SMTP(ex: contato@dominio.com):" --fb 12 60 3>&1 1>&2 2>&3) ; saida=$?
		if [[ $saida -eq '0' ]] ; then if [[ -z $user_smtp_lowcoder ]] ; then user_smtp_lowcoder=contato@dominio.com ; fi else echo "saindo..." ; exit ; fi

    senha_smtp_lowcoder=$(whiptail --title "Senha para o SMTP" --inputbox "Pressione ENTER para configurar depois, ou digite a senha do SMTP do email:" --fb 12 60 3>&1 1>&2 2>&3) ; saida=$?
		if [[ $saida -eq '0' ]] ; then if [[ -z $senha_smtp_lowcoder ]] ; then senha_smtp_lowcoder=Kgdgd6jkm ; fi else echo "saindo..." ; exit ; fi

    
    host_smtp_lowcoder=$(whiptail --title "Host do SMTP do Email" --inputbox "Pressione ENTER para configurar depois, ou digite o Host do SMTP (ex: smtp.hostinger.com):" --fb 12 60 3>&1 1>&2 2>&3) ; saida=$?
		if [[ $saida -eq '0' ]] ; then if [[ -z $host_smtp_lowcoder ]] ; then host_smtp_lowcoder=smtp.site.com ; fi else echo "saindo..." ; exit ; fi


 porta_smtp_lowcoder=$(whiptail --title "Porta do SMTP" --inputbox "Pressione ENTER para configurar depois, ou digite digite a Porta SMTP (ex: 465):" --fb 12 60 3>&1 1>&2 2>&3) ; saida=$?
		if [[ $saida -eq '0' ]] ; then if [[ -z $porta_smtp_lowcoder ]] ; then porta_smtp_lowcoder=465 ; fi else echo "saindo..." ; exit ; fi

 ## Verifica se a porta é 465, se sim deixa o ssl true, se não, deixa false 
    if [ "$porta_smtp_lowcoder" -eq 465 ]; then
    smtp_secure_lowcoder_ssl=true
    smtp_secure_lowcoder_startls=false
    else
    smtp_secure_lowcoder_ssl=false
    smtp_secure_lowcoder_startls=true
    fi


    
 
# FIM DE PERGUNTAS PARA VARIAVEIS
#
#########################################################
#
# VERIFICAÇÃO DE DADOS
#


nome_principal="lowcoder"  #nome do app
sufixo_app=$(date | md5sum | head -c7)
nome_app=$nome_principal$sufixo_app


if [[ ("$mongodb_container" == "") ]]; then
 

cd

cd

cat > mongodb$sufixo_app.yaml << EOL
version: "3.7"
services:


  mongodb$sufixo_app:
    image: mongo:latest
    command: mongod --port 27017

    volumes:
      - mongodb$sufixo_app-data:/data/db
      - mongodb$sufixo_app-dump:/dump
      - mongodb$sufixo_app-configdb_data:/data/configdb

    networks:
      - network_public
    #ports:
    #  - 27017:27017

    environment:
      ## Dados de acesso
      - MONGO_INITDB_ROOT_USERNAME=$user_mongodb_lowcoder
      - MONGO_INITDB_ROOT_PASSWORD=$pass_mongodb_lowcoder
      - PUID=1000
      - PGID=1000

    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
          - node.role == manager
      resources:
        limits:
          cpus: '1'
          memory: 2048M


volumes:
  mongodb$sufixo_app-data:
    external: true
    name: mongodb$sufixo_app-data
  mongodb$sufixo_app-dump:
    external: true
    name: mongodb$sufixo_app-dump
  mongodb$sufixo_app-configdb_data:
    external: true
    name: mongodb$sufixo_app-configdb_data

networks:
  network_public:
    name: network_public
    external: true

EOL

docker stack deploy --prune --resolve-image always -c mongodb$sufixo_app.yaml mongodb$sufixo_app >/dev/null 2>&1

else
stack_name=$(docker inspect $mongodb_container --format '{{ index .Config.Labels "com.docker.stack.namespace" }}')
user_mongodb_lowcoder=$(grep -oP '(?<=MONGO_INITDB_ROOT_USERNAME=).+' /root/$stack_name.yaml)
pass_mongodb_lowcoder=$(grep -oP '(?<=MONGO_INITDB_ROOT_PASSWORD=).+' /root/$stack_name.yaml)

fi 	


clear

echo ""
echo -e "URL do LOWCODER: \e[33m$url_lowcoder\e[0m"
if [[ ("$mongodb_container" == "") ]]; then
echo -e "Usuário do Mongodb: \e[33m$user_mongodb_lowcoder\e[0m"
echo -e "Senha do Mongodb: \e[33m$pass_mongodb_lowcoder\e[0m"
fi
echo -e "Email do SMTP: \e[33m$email_smtp_lowcoder\e[0m"
echo -e "Usuário do SMTP: \e[33m$user_smtp_lowcoder\e[0m"
echo -e "Senha do SMTP: \e[33m$senha_smtp_lowcoder\e[0m"
echo -e "Host do SMTP: \e[33m$host_smtp_lowcoder\e[0m"
echo -e "Porta do SMTP: \e[33m$porta_smtp_lowcoder\e[0m"
echo ""
echo ""
read -p "As informações estão certas? (y/n): " confirma1
if [ "$confirma1" == "y" ]; then

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
echo -e "XXX\n0\nCRIANDO STACK DO LOWCODER 1/4 \nXXX"
sleep 3
echo -e "XXX\n25\nCRIANDO STACK DO LOWCODER 1/4 - CONCLUIDO \nXXX"
sleep 3 
echo -e "XXX\n25\nFAZENDO O BUILD DO STACK DO LOWCODER 2/4 \nXXX"
sleep 3
echo -e "XXX\n50\nFAZENDO O BUILD DO STACK DO LOWCODER 2/4 - CONCLUIDO \nXXX"
sleep 3
echo -e "XXX\n50\nCRIANDO BANCO DE DADOS DO LOWCODER 3/4 \nXXX"
sleep 3
echo -e "XXX\n75\nCRIANDO BANCO DE DADOS DO LOWCODER 3/4 - CONCLUIDO \nXXX"





#######################################################
#
#  INSTALANDO O LOWCODER
#

cd

cd

## Gerando Encryption
encryption_key_lowcoder1=$(openssl rand -hex 16)
encryption_key_lowcoder2=$(openssl rand -hex 16)
encryption_key_lowcoder3=$(openssl rand -hex 32)

## pega ip da vps
ip=$(hostname -I | cut -d' ' -f1) 

clear


cat > $nome_app.yaml << EOL

version: "3.7"
services:


  $nome_app-api:
    image: lowcoderorg/lowcoder-ce-api-service:latest

    networks:
      - network_public

    environment:
      - LOWCODER_PUID=9001
      - LOWCODER_PGID=9001

      ## Dados MongoDB
      - LOWCODER_MONGODB_URL=mongodb://$user_mongodb_lowcoder:$pass_mongodb_lowcoder@$ip:27017/$nome_app?authSource=admin&readPreference=primary&ssl=false&directConnection=true

      ## Dados Redis
      - LOWCODER_REDIS_URL=redis://redis:6379

      ## Dominio
      - LOWCODER_NODE_SERVICE_URL=http://$nome_app-node:6060

      ## Configurações
      - LOWCODER_MAX_QUERY_TIMEOUT=120
      - LOWCODER_EMAIL_AUTH_ENABLED=true
      - LOWCODER_EMAIL_SIGNUP_ENABLED=true ## true = permitir criar novas contas
      - LOWCODER_CREATE_WORKSPACE_ON_SIGNUP=true ## true = permitir criar novos workspaces
      - LOWCODER_WORKSPACE_MODE=SAAS

      ## Encryption
      - LOWCODER_DB_ENCRYPTION_PASSWORD=$encryption_key_lowcoder1 ## hash Encryption
      - LOWCODER_DB_ENCRYPTION_SALT=$encryption_key_lowcoder2 ## hash Encryption
      - LOWCODER_API_KEY_SECRET=$encryption_key_lowcoder3 # hash Encryption

      ## Outras configurações
      - LOWCODER_CORS_DOMAINS=*
      - LOWCODER_MAX_ORGS_PER_USER=100
      - LOWCODER_MAX_MEMBERS_PER_ORG=1000
      - LOWCODER_MAX_GROUPS_PER_ORG=100
      - LOWCODER_MAX_APPS_PER_ORG=1000
      - LOWCODER_MAX_DEVELOPERS=50

      ## Dados SMTP
      - LOWCODER_ADMIN_SMTP_HOST=$host_smtp_lowcoder
      - LOWCODER_ADMIN_SMTP_PORT=$porta_smtp_lowcoder
      - LOWCODER_ADMIN_SMTP_USERNAME=$user_smtp_lowcoder
      - LOWCODER_ADMIN_SMTP_PASSWORD=$senha_smtp_lowcoder
      - LOWCODER_ADMIN_SMTP_AUTH=true
      - LOWCODER_ADMIN_SMTP_SSL_ENABLED=$smtp_secure_lowcoder_ssl
      - LOWCODER_ADMIN_SMTP_STARTTLS_ENABLED=$smtp_secure_lowcoder_startls
      - LOWCODER_ADMIN_SMTP_STARTTLS_REQUIRED=$smtp_secure_lowcoder_startls
      - LOWCODER_EMAIL_NOTIFICATIONS_SENDER=$email_smtp_lowcoder
    
    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
          - node.role == manager
      resources:
        limits:
          cpus: "0.5"
          memory: 1024M

  $nome_app-node:
    image: lowcoderorg/lowcoder-ce-node-service:latest

    networks:
      - network_public

    environment:
      - LOWCODER_PUID=9001
      - LOWCODER_PGID=9001
      - LOWCODER_API_SERVICE_URL=http://$nome_app-api:8080

    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
          - node.role == manager
      resources:
        limits:
          cpus: "0.5"
          memory: 1024M


  $nome_app-frontend:
    image: lowcoderorg/lowcoder-ce-frontend:latest

    volumes:
     - $nome_app-assets:/lowcoder/assets

    networks:
      - network_public

    environment:
      - LOWCODER_PUID=9001
      - LOWCODER_PGID=9001
      - LOWCODER_MAX_REQUEST_SIZE=20m
      - LOWCODER_MAX_QUERY_TIMEOUT=120
      - LOWCODER_API_SERVICE_URL=http://$nome_app-api:8080
      - LOWCODER_NODE_SERVICE_URL=http://$nome_app-node:6060

    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
          - node.role == manager  
      labels:
        - traefik.enable=true
        - traefik.http.routers.$nome_app.rule=Host(\`$url_lowcoder\`) && PathPrefix(\`/\`)
        - traefik.http.services.$nome_app.loadbalancer.server.port=3000
        - traefik.http.routers.$nome_app.service=$nome_app
        - traefik.http.routers.$nome_app.entrypoints=websecure
        - traefik.http.routers.$nome_app.tls.certresolver=letsencryptresolver
        - traefik.http.routers.$nome_app.tls=true


volumes:
  $nome_app-assets:
    external: true
    name: $nome_app-assets

networks:
  network_public: ## Nome da rede interna
    external: true
    name: network_public ## Nome da rede interna


EOL

docker stack deploy --prune --resolve-image always -c $nome_app.yaml $nome_app >/dev/null 2>&1

echo -e "XXX\n75\nFINALIZANDO BUILD DO LOWCODER 4/4  \nXXX"

sleep 2

echo -e "XXX\n100\nFINALIZANDO BUILD DO LOWCODER 4/4 - CONCLUIDO  \nXXX"

sleep 3
}|whiptail --title "LOWCODER - PROGRESSO DA INSTALAÇÃO" --gauge "Aguarde a instalação dos ítens necessários" 6 60 0

# FIM DE INSTALANDO O LOWCODER
#
#######################################################


#
# MENSAGEM DE INSTLADO + DADOS
#

whiptail --msgbox "Parabéns seu LOWCODER foi instalado com sucesso! Pressione ENTER para voltar ao Menu Principal" 20 78


#
# FIM DE MENSAGEM DE INSTLADO + DADOS
#
#########################################################
#
# USUARIO PREENCHEU DADOS ERRADOS
#

elif [ "$confirma1" == "n" ]; then
    echo "Encerrando a instalaço, por favor, inicie a instalaão novamente."
    exit 0
else
    echo "Resposta inválida. Digite 'y' para confirmar ou 'n' para encerrar a instalação."
    exit 1
fi

#
# FIM DE USUARIO PREENCHEU DADOS ERRADOS
#
#########################################################

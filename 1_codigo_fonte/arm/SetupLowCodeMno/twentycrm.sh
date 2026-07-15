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
		whiptail --title "INSTALAÇÃO DO TWENTYCRM" --msgbox "$msg" --fb 10 70;
	}

  while true; do
CHOICE=$(
whiptail --title "INSTALAÇÃO DO TWENTYCRM" --menu "Aperte ENTER para iniciar a instalação do Twentycrm ou selecione SAIR (Utilize setas e Enter)\nINSTRUÇÕES\nAntes de prosseguir, apontar registros DNS para o(s) seguinte(s) dominio(s):\nRECORD A: Dê um nome para seu servidor (exemplo: manager1.seudominio.com.br) e aponte para o IP do seu servidor\nRECORDS CNAME: Crie subdominio para o Twentycrm, apontando para o nome do servidor criado (exemplo: manager1.seudominio.com.br)" 20 70 2 \
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


  while true ; do
		url_twentycrm=$(whiptail --title "1/7 - URL do Twentycrm" --inputbox "Digite o Link do Twentycrm (ex: twentycrm.seudominio.com):" --fb 12 60 3>&1 1>&2 2>&3) ; saida=$?
		if [[ $saida -eq '0' ]] ; then
			if [[ -z $url_twentycrm ]] ; then msg "Digite o link do Twentycrm, para poder continuar" ; continue ; else break; fi
		else
			echo $url_twentycrm ; echo "saindo..."  &  exit 0 ;
		fi
	done

 while true ; do
		nome_twentycrm=$(whiptail --title "2/7 - Nome do remetente SMTP" --inputbox "Digite o seu nome para enviar emails (ex: Marcos):" --fb 12 60 3>&1 1>&2 2>&3) ; saida=$?
		if [[ $saida -eq '0' ]] ; then
			if [[ -z $nome_twentycrm ]] ; then msg "Digite o nome do SMTP, para poder continuar" ; continue ; else break; fi
		else
			echo $nome_twentycrm ; echo "saindo..."  &  exit 0 ;
		fi
	done 


      while true ; do
		email_smtp_twentycrm=$(whiptail --title "3/7 - Email para o SMTP" --inputbox "Digite o Email do SMTP (ex: contato@dominio.com):" --fb 12 60 3>&1 1>&2 2>&3) ; saida=$?
		if [[ $saida -eq '0' ]] ; then
			if [[ -z $email_smtp_twentycrm ]] ; then msg "Digite o email, para poder continuar" ; continue ; else break; fi
		else
			echo $email_smtp_twentycrm ; echo "saindo..."  &  exit 0 ;
		fi
	done

     user_smtp_twentycrm=$(whiptail --title "4/7 Usuário para o SMTP" --inputbox "Pressione ENTER para configurar depois, ou digite o usuário do SMTP(ex: contato@dominio.com):" --fb 12 60 3>&1 1>&2 2>&3) ; saida=$?
		if [[ $saida -eq '0' ]] ; then if [[ -z $user_smtp_twentycrm ]] ; then user_smtp_twentycrm=contato@dominio.com ; fi else echo "saindo..." ; exit ; fi

    pass_smtp_twentycrm=$(whiptail --title "5/7 Senha para o SMTP" --inputbox "Pressione ENTER para configurar depois, ou digite a senha do SMTP do email:" --fb 12 60 3>&1 1>&2 2>&3) ; saida=$?
		if [[ $saida -eq '0' ]] ; then if [[ -z $pass_smtp_twentycrm ]] ; then pass_smtp_twentycrm=Kgdgd6jkm ; fi else echo "saindo..." ; exit ; fi

    
    host_smtp_twentycrm=$(whiptail --title "6/7 Host do SMTP do Email" --inputbox "Pressione ENTER para configurar depois, ou digite o Host do SMTP (ex: smtp.hostinger.com):" --fb 12 60 3>&1 1>&2 2>&3) ; saida=$?
		if [[ $saida -eq '0' ]] ; then if [[ -z $host_smtp_twentycrm ]] ; then host_smtp_twentycrm=smtp.site.com ; fi else echo "saindo..." ; exit ; fi


 porta_smtp_twentycrm=$(whiptail --title "7/7 Porta do SMTP" --inputbox "Pressione ENTER para configurar depois, ou digite digite a Porta SMTP (ex: 465):" --fb 12 60 3>&1 1>&2 2>&3) ; saida=$?
		if [[ $saida -eq '0' ]] ; then if [[ -z $porta_smtp_twentycrm ]] ; then porta_smtp_twentycrm=465 ; fi else echo "saindo..." ; exit ; fi


   if [ "$porta_smtp_twentycrm" -eq 465 ] || [ "$porta_smtp_twentycrmt" -eq 25 ]; then
        ssl_twentycrm=1
    else
        ssl_twentycrm=0
    fi

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
# FIM DE PERGUNTAS PARA VARIAVEIS
#
#########################################################
#
# VERIFICAÇO DE DADOS
#


nome_principal="twentycrm"  #nome do app
sufixo_app=$(date | md5sum | head -c7)
nome_app=$nome_principal$sufixo_app
postgres_password=$(grep -oP '(?<=POSTGRES_PASSWORD=).+' /root/postgres.yaml)
container_id=$(docker ps -qf name=postgres)
docker exec -it $container_id psql -U postgres -d postgres -c "CREATE  DATABASE $nome_app;" 



# Ajuste do terminal para garantir compatibilidade
{
  tput reset 2>/dev/null         # Reinicia o terminal de forma segura
  exec 0</dev/tty 1>/dev/tty 2>&1 # Força redirecionamentos explícitos
  sleep 0.01                     # Pausa microscópica para sincronia
  clear                          # Limpeza final antes do whiptail
} || true


    # Exibe as informações formatadas com mais espaço na tela
    whiptail --title "Dados Fornecidos" \
    --msgbox "Dados Preenchidos:\n\n1) URL do Twentycrm: $url_twentycrm\n2) Nome do remetente SMTP: $nome_twentycrm\n3) Email para o SMTP: $email_smtp_twentycrm\n4) Usuário para o SMTP: $user_smtp_twentycrm\n5) Senha para o SMTP: $pass_smtp_twentycrm\n6) Host do SMTP do Email: $host_smtp_twentycrm\n7) Porta do SMTP: $porta_smtp_twentycrm\n8) Criar Stack no Portainer: $([ "$criar_portainer" == "0" ] && echo "0 (Editável)" || echo "1 (Não editável)")\n\nConfira e Tecle Enter para continuar. Na próxima etapa você poderá confirmar os dados ou corrigir, se necessário." \
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
        msg "Você digitou N e não confirmou os dados preenchidos. Tecle Enter para sair da instalação"
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

    echo -e "XXX\n3\nVERIFICANDO SUBDOMÍNIO: $url_twentycrm \nXXX"
   sleep 3
    # Verifica apenas se o domínio está apontando para o IP correto
    dns_ip=$(timeout 10 nslookup $url_twentycrm | grep "Address" | tail -n1 | awk '{print $2}')
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
  
echo -e "XXX\n23\nCRIANDO STACK DO TWENTYCRM 1/4 \nXXX"
sleep 3
echo -e "XXX\n25\nCRIANDO STACK DO TWENTYCRM 1/4 - CONCLUIDO \nXXX"
sleep 3 
echo -e "XXX\n25\nFAZENDO O BUILD DO STACK DO TWENTYCRM 2/4 \nXXX"
sleep 3
echo -e "XXX\n50\nFAZENDO O BUILD DO STACK DO TWENTYCRM 2/4 - CONCLUIDO \nXXX"
sleep 3
echo -e "XXX\n50\nCRIANDO BANCO DE DADOS DO TWENTYCRM 3/4 \nXXX"
sleep 3
echo -e "XXX\n75\nCRIANDO BANCO DE DADOS DO TWENTYCRM 3/4 - CONCLUIDO \nXXX"





#######################################################
#
#  INSTALANDO O TWENTYCRM
#

cd

cd
Key_aleatoria_twentycrm=$(openssl rand -hex 16)
Key_aleatoria_twentycrm_1=$(openssl rand -hex 16)


clear


cat > $nome_app.yaml << EOL

version: "3.7"
services:



  $nome_app-server:
    image: twentycrm/twenty:v0.32.4

    volumes:
      - twentycrm_data:/app/packages/twenty-server/.local-storage
      - twentycrm_docker:/app/docker-data

    networks: 
      - externa
      - interna

    environment:
      - PORT=3000
      - SERVICE_BASE64_32_SECRET=$Key_aleatoria_twentycrm
      - SERVICE_FQDN_TWENTY=https://$url_twentycrm
      - SERVICE_PASSWORD_POSTGRES=$postgres_password
      - API_RATE_LIMITING_LIMIT=100
      - API_RATE_LIMITING_TTL=100

      - DEBUG_MODE=false
      - PG_DATABASE_URL=postgres://postgres:$postgres_password@postgres:5432/$nome_app
      - SERVER_URL=https://$url_twentycrm
      - FRONT_BASE_URL=https://$url_twentycrm
      - REDIS_URL=redis://redis:6379  # Já configurado
      - ENABLE_DB_MIGRATIONS=true
      - IS_SIGN_UP_DISABLED=false
      - SIGN_IN_PREFILLED=false
      - STORAGE_TYPE=local
      - APP_SECRET=$Key_aleatoria_twentycrm_1
      - EMAIL_FROM_ADDRESS=$email_smtp_twentycrm
      - EMAIL_FROM_NAME=$nome_twentycrm
      - EMAIL_SYSTEM_ADDRESS=$email_smtp_twentycrm
      - EMAIL_DRIVER=logger
      - EMAIL_SMTP_HOST=$host_smtp_twentycrm
      - EMAIL_SMTP_PORT=$porta_smtp_twentycrm
      - EMAIL_SMTP_USER=$user_smtp_twentycrm
      - EMAIL_SMTP_PASSWORD=$pass_smtp_twentycrm
      - CACHE_STORAGE_TYPE=redis

    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
          - node.role == manager
      resources:
        limits:
          cpus: "1"
          memory: 4192M
      labels:
        - traefik.enable=true
        - traefik.http.routers.$nome_app.rule=Host(\`$url_twentycrm\`)
        - traefik.http.services.$nome_app.loadbalancer.server.port=3000
        - traefik.http.routers.$nome_app.service=$nome_app
        - traefik.http.routers.$nome_app.tls.certresolver=letsencryptresolver
        - traefik.http.routers.$nome_app.entrypoints=websecure
        - traefik.http.routers.$nome_app.tls=true



  $nome_app-worker:
    image: twentycrm/twenty:v0.32.4
    command: ["yarn", "worker:prod"]

    networks: 
      - externa
      - interna

    environment:
      - PORT=3000
      - SERVICE_BASE64_32_SECRET=$Key_aleatoria_twentycrm
      - SERVICE_FQDN_TWENTY=https://$url_twentycrm
      - SERVICE_PASSWORD_POSTGRES=$postgres_password
      - API_RATE_LIMITING_LIMIT=100
      - API_RATE_LIMITING_TTL=100

      - DEBUG_MODE=false
      - PG_DATABASE_URL=postgres://postgres:$postgres_password@postgres:5432/$nome_app
      - SERVER_URL=https://$url_twentycrm
      - FRONT_BASE_URL=https://$url_twentycrm
      - REDIS_URL=redis://redis:6379  # Já configurado
      - ENABLE_DB_MIGRATIONS=true
      - IS_SIGN_UP_DISABLED=false
      - SIGN_IN_PREFILLED=false
      - STORAGE_TYPE=local
      - APP_SECRET=$Key_aleatoria_twentycrm_1
      - EMAIL_FROM_ADDRESS=$email_smtp_twentycrm
      - EMAIL_FROM_NAME=$nome_twentycrm
      - EMAIL_SYSTEM_ADDRESS=$email_smtp_twentycrm
      - EMAIL_DRIVER=logger
      - EMAIL_SMTP_HOST=$host_smtp_twentycrm
      - EMAIL_SMTP_PORT=$porta_smtp_twentycrm
      - EMAIL_SMTP_USER=$user_smtp_twentycrm
      - EMAIL_SMTP_PASSWORD=$pass_smtp_twentycrm
      - CACHE_STORAGE_TYPE=redis

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
  


volumes:
  twentycrm_data:
    external: true
    name: twentycrm_data
  twentycrm_docker:
    external: true
    name: twentycrm_docker

networks: 
  externa: 
    external: true
  interna: 
    external: true


EOL

#docker stack deploy --prune --resolve-image always -c $nome_app.yaml $nome_app >/dev/null 2>&1



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
STACK_NAME=$nome_app
STACK_FILE_PATH="/root/$nome_app.yaml"

else
   # echo "Erro: Arquivo de dados não encontrado em $dados_file."
    sleep 5
echo -e "XXX\n77\nSEM ARQUIVO DE DADOS DO PORTAINER 3/4  \nXXX"
docker stack deploy --prune --resolve-image always -c $nome_app.yaml $nome_app >/dev/null 2>&1
sleep 5
    exit 1
fi

# Função para autenticação
get_auth_token() {
    #echo "[INFO] Autenticando no Portainer..."
    echo -e "XXX\n77\nAUTENTICANDO NO PORTAINER... 3/4  \nXXX"
    RESPONSE=$(curl -sk -X POST "https://$PORTAINER_URL/api/auth" \
        -H "Content-Type: application/json" \
        -d "{\"username\": \"$ADMIN_USERNAME\", \"password\": \"$ADMIN_PASSWORD\"}")
    TOKEN=$(echo "$RESPONSE" | jq -r '.jwt')
    if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]; then
        # echo "[ERRO] Falha na autenticação."
        echo -e "XXX\n77\nFALHA NA AUTENTICAÇÃO.. 3/4  \nXXX"
sleep 5
echo -e "XXX\n78\nREVERTENDO E CRIANDO STACK PELO SERVIDOR 3/4  \nXXX"
docker stack deploy --prune --resolve-image always -c $nome_app.yaml $nome_app >/dev/null 2>&1
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
    RESPONSE=$(curl -sk -X GET "https://$PORTAINER_URL/api/endpoints" \
        -H "Authorization: Bearer $TOKEN")
    ENDPOINT_ID=$(echo "$RESPONSE" | jq -r '.[0].Id')
    if [ -z "$ENDPOINT_ID" ] || [ "$ENDPOINT_ID" = "null" ]; then
        # echo "[ERRO] EndpointID não encontrado! Resposta: $RESPONSE"
        echo -e "XXX\n81\n[ERRO] ENDPOINTID NÃO ENCONTRADO 3/4  \nXXX"
        docker stack deploy --prune --resolve-image always -c $nome_app.yaml $nome_app >/dev/null 2>&1
        exit 1
    fi
     echo -e "XXX\n82\n[SUCESSO] ENDPOINTID OBTIDO: $ENDPOINT_ID  3/4  \nXXX"
    #echo "[SUCESSO] EndpointID obtido: $ENDPOINT_ID"
}

# Função para obter o SwarmID
get_swarm_id() {
   # echo "[INFO] Obtendo SwarmID..."
    echo -e "XXX\n83\n[INFO] OBTENDO SWARMID  3/4  \nXXX"
    RESPONSE=$(curl -sk -X GET "https://$PORTAINER_URL/api/endpoints/$ENDPOINT_ID/docker/swarm" \
        -H "Authorization: Bearer $TOKEN")
    SWARM_ID=$(echo "$RESPONSE" | jq -r '.ID')
    if [ -z "$SWARM_ID" ] || [ "$SWARM_ID" = "null" ]; then
        #echo "[ERRO] SwarmID não encontrado! Resposta: $RESPONSE"
        echo -e "XXX\n84\n[ERRO] SWARMID NÃO ENCONTRADO 3/4  \nXXX"
        docker stack deploy --prune --resolve-image always -c $nome_app.yaml $nome_app >/dev/null 2>&1
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
        docker stack deploy --prune --resolve-image always -c $nome_app.yaml $nome_app >/dev/null 2>&1
        exit 1
    fi

    #echo "[INFO] Criando stack '$STACK_NAME' no Portainer..."
     echo -e "XXX\n88\n[INFO] CRIANDO STACK $STACK_NAME NO PORTAINER 3/4  \nXXX"
    response_output=$(mktemp)
    erro_output=$(mktemp)

    http_code=$(curl -s -o "$response_output" -w "%{http_code}" -k -X POST \
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
        docker stack deploy --prune --resolve-image always -c $nome_app.yaml $nome_app >/dev/null 2>&1
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
    docker stack deploy --prune --resolve-image always -c $nome_app.yaml $nome_app >/dev/null 2>&1
else
    # Caso inesperado (não deve ocorrer devido à validação anterior no while loop)
   # echo "Erro: valor inesperado para criar_portainer. Encerrando..."
    echo -e "XXX\n91\n[ERRO] ERRO INESPERADO PARA CRIAR STACK NO PORTAINER 3/4  \nXXX"
    sleep 5
    echo -e "XXX\n92\nREVERTENDO E CRIANDO STACK PELO SERVIDOR 3/4  \nXXX"
docker stack deploy --prune --resolve-image always -c $nome_app.yaml $nome_app >/dev/null 2>&1
sleep 5

    exit 1
fi



echo -e "XXX\n93\nFINALIZANDO BUILD DO TWENTYCRM 4/4  \nXXX"

sleep 2

echo -e "XXX\n100\nFINALIZANDO BUILD DO TWENTYCRM 4/4 - CONCLUIDO  \nXXX"

sleep 3

}|whiptail --title "TWENTYCRM - PROGRESSO DA INSTALAÇÃO" --gauge "Aguarde a instalação dos ítens necessários" 6 60 0

# FIM DE INSTALANDO O TWENTYCRM
#
#######################################################


#
# MENSAGEM DE INSTLADO + DADOS
#
ip_servidor=$(curl -s --max-time 10 ipinfo.io/ip)
dns_ip=$(timeout 10 nslookup $url_twentycrm | grep "Address" | tail -n1 | awk '{print $2}')

if [[ "$dns_ip" != "$ip_servidor" ]]; then

whiptail --title "Mensagem" --msgbox "Não foi possivel acessar o subdominio do Twentycrm ($url_twentycrm). A instalação foi cancelada. Por favor, verifique se os apontamentos DNS estão corretos e propagados! Pressione ENTER para voltar ao Menu Principal" 20 78
 else

 whiptail --title "Mensagem" --msgbox "Parabéns, seu Twentycrm foi instalado com sucesso! Pressione ENTER para voltar ao Menu Principal" 20 78       
    fi

exit 0

#!/usr/bin/bash
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
		whiptail --title "HABILITAR EDIÇÃO DOS ESSENCIAIS NO PORTAINER" --msgbox "$msg" --fb 10 70;
	}

while true; do

# Ajuste do terminal para garantir compatibilidade
{
  tput reset 2>/dev/null         # Reinicia o terminal de forma segura
  exec 0</dev/tty 1>/dev/tty 2>&1 # Força redirecionamentos explícitos
  sleep 0.01                     # Pausa microscópica para sincronia
  clear                          # Limpeza final antes do whiptail
} || true

CHOICE=$(
whiptail --title "HABILITAR EDIÇÃO DOS ESSENCIAIS NO PORTAINER" --menu "Aperte ENTER para iniciar o setup para que as ferramentas essenciais (Postgres, Redis e Pgbouncer) tenham os stacks editáveis no Portainer ou selecione SAIR (Utilize setas e Enter)" 20 70 2 \
	"1)" "CONTINUAR"   \
	"2)" "SAIR"  3>&2 2>&1 1>&3	
)

case $CHOICE in
	"1)")   
		clear
        break
	;;
	
	"2)") 
        cd /
        cd
        exit 0
        ;; 
esac
done

#########################################################
#
#    LOADING - CONFIGURAÇÃO DE CORES
#
export NEWT_COLORS='
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

{


clear

##### PARTE 1: POSTGRES
   # A stack será criada no Portainer
    echo -e "XXX\n3\nDEIXANDO STACK DO POSTGRES EDITÁVEL  \nXXX"
   # echo "Criando a stack no Portainer para edição."
    # Substituir pelo comando ou rotina para criar a stack no Portainer
    # Aqui pode chamar um novo script ou rotina específica, exemplo:
   ## /path/to/criar_stack_no_portainer.sh "postgres" "$painelpma"

#!/bin/bash

# Configurações
sleep 2
# Caminho para o arquivo de dados
dados_file="$HOME/dados_portainer/dados_portainer"
cd
docker stack rm postgres >/dev/null 2>&1
# Verifica se o arquivo existe
if [[ -f "$dados_file" ]]; then
    # Coleta as informações do arquivo
PORTAINER_URL=$(grep "Dominio do portainer:" "$dados_file" | cut -d':' -f2 | xargs)
ADMIN_USERNAME=$(grep "Usuario:" "$dados_file" | cut -d':' -f2 | xargs)
ADMIN_PASSWORD=$(grep "Senha:" "$dados_file" | cut -d':' -f2 | xargs)
STACK_NAME=postgres
STACK_FILE_PATH="/root/postgres.yaml"

else
   # echo "Erro: Arquivo de dados não encontrado em $dados_file."
    sleep 2
echo -e "XXX\n10\nDEIXANDO STACK DO POSTGRES EDITÁVEL  \nXXX"
docker stack deploy --prune --resolve-image always -c postgres.yaml postgres >/dev/null 2>&1
sleep 5
    #exit 1
    #break
fi

# Função para autenticação
get_auth_token() {
    #echo "[INFO] Autenticando no Portainer..."
    sleep 2
    echo -e "XXX\n15\nAUTENTICANDO NO PORTAINER...  \nXXX"
    RESPONSE=$(curl -sk -X POST "https://$PORTAINER_URL/api/auth" \
        -H "Content-Type: application/json" \
        -d "{\"username\": \"$ADMIN_USERNAME\", \"password\": \"$ADMIN_PASSWORD\"}")
    TOKEN=$(echo "$RESPONSE" | jq -r '.jwt')
    if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]; then
        # echo "[ERRO] Falha na autenticação."
        echo -e "XXX\n20\nFALHA NA AUTENTICAÇÃO..  \nXXX"
sleep 5
echo -e "XXX\n26\nREVERTENDO E CRIANDO STACK PELO SERVIDOR  \nXXX"
docker stack deploy --prune --resolve-image always -c postgres.yaml postgres >/dev/null 2>&1
sleep 5
echo -e "XXX\n27\nCASO O POSTGRES JÁ ESTIVER EDITÁVEL, SERÁ MANTIDO  \nXXX"
       # exit 1
       #break
    fi
  #  echo "[SUCESSO] Autenticação realizada com sucesso. Token obtido."
 echo -e "XXX\n29\n[SUCESSO] AUTENTICAÇÃO OK  \nXXX"
}

# Função para obter o EndpointID
get_endpoint_id() {
   # echo "[INFO] Obtendo EndpointID..."
    echo -e "XXX\n32\n[INFO] OBTENDO ENDPOINTID \nXXX"
    RESPONSE=$(curl -sk -X GET "https://$PORTAINER_URL/api/endpoints" \
        -H "Authorization: Bearer $TOKEN")
    ENDPOINT_ID=$(echo "$RESPONSE" | jq -r '.[0].Id' 2>/dev/null)
    if [ -z "$ENDPOINT_ID" ] || [ "$ENDPOINT_ID" = "null" ]; then
        # echo "[ERRO] EndpointID não encontrado! Resposta: $RESPONSE"
        echo -e "XXX\n34\n[ERRO] ENDPOINTID NÃO ENCONTRADO \nXXX"
        sleep 5
        docker stack deploy --prune --resolve-image always -c postgres.yaml postgres >/dev/null 2>&1
       # exit 1
       #break
    fi
     echo -e "XXX\n35\n[SUCESSO] ENDPOINTID OBTIDO: $ENDPOINT_ID   \nXXX"
     sleep 3
    #echo "[SUCESSO] EndpointID obtido: $ENDPOINT_ID"
}

# Função para obter o SwarmID
get_swarm_id() {
   # echo "[INFO] Obtendo SwarmID..."
    echo -e "XXX\n38\n[INFO] OBTENDO SWARMID  \nXXX"
    RESPONSE=$(curl -sk -X GET "https://$PORTAINER_URL/api/endpoints/$ENDPOINT_ID/docker/swarm" \
        -H "Authorization: Bearer $TOKEN")
    SWARM_ID=$(echo "$RESPONSE" | jq -r '.ID' 2>/dev/null)
    if [ -z "$SWARM_ID" ] || [ "$SWARM_ID" = "null" ]; then
        #echo "[ERRO] SwarmID não encontrado! Resposta: $RESPONSE"
        echo -e "XXX\n39\n[ERRO] SWARMID NÃO ENCONTRADO   \nXXX"
        docker stack deploy --prune --resolve-image always -c postgres.yaml postgres >/dev/null 2>&1
       # exit 1
      # break
    fi
    #echo "[SUCESSO] SwarmID obtido: $SWARM_ID"
    echo -e "XXX\n40\n[SUCESSO] SWARMID OBTIDO: $SWARM_ID   \nXXX"
}

# Função para criar a stack
create_stack() {
    #echo "[INFO] Verificando existência do arquivo YAML..."
    echo -e "XXX\n41\n[INFO] VERIFICANDO SE YAML EXISTE  \nXXX"
    if [ ! -f "$STACK_FILE_PATH" ]; then
        #echo "[ERRO] Arquivo $STACK_FILE_PATH não encontrado!"
        echo -e "XXX\n42\n[ERRO] ARQUIVO $STACK_FILE_PATH NÃO ENCONTRADO 3/4  \nXXX"
        docker stack deploy --prune --resolve-image always -c postgres.yaml postgres >/dev/null 2>&1
       # exit 1
      #break
    fi

    #echo "[INFO] Criando stack '$STACK_NAME' no Portainer..."
     echo -e "XXX\n45\n[INFO] CRIANDO STACK $STACK_NAME NO PORTAINER 3/4  \nXXX"
    
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
        echo -e "XXX\n51\n[ERRO] ERRO AO CRIAR STACK  \nXXX"
        docker stack deploy --prune --resolve-image always -c postgres.yaml postgres >/dev/null 2>&1
        sleep 3
        echo -e "XXX\n52\nMANTENDO STACK DO POSTGRES NO PADRÃO ATUAL  \nXXX"
        sleep 3
       # exit 1
      # break
    fi

   # echo "[SUCESSO] Stack '$STACK_NAME' criada com sucesso!"
    echo -e "XXX\n52\n[SUCESSO] STACK $STACK_NAME  CRIADA COM SUCESSO  \nXXX"
}
sleep 5
# Fluxo de execução principal
# echo "[INFO] Iniciando processo de criação da stack..."
get_auth_token || exit 1
get_endpoint_id || exit 1
get_swarm_id || exit 1
create_stack || exit 1
# echo "[SUCESSO] Processo concluído."



##### PARTE 2: PGBOUNCER
   # A stack será criada no Portainer
    echo -e "XXX\n53\nDEIXANDO STACK DO PGBOUNCER EDITÁVEL  \nXXX"
   # echo "Criando a stack no Portainer para edição."
    # Substituir pelo comando ou rotina para criar a stack no Portainer
    # Aqui pode chamar um novo script ou rotina específica, exemplo:
   ## /path/to/criar_stack_no_portainer.sh "pgbouncer" "$painelpma"

#!/bin/bash

# Configurações
sleep 2
# Caminho para o arquivo de dados
dados_file="$HOME/dados_portainer/dados_portainer"
cd
docker stack rm pgbouncer >/dev/null 2>&1
# Verifica se o arquivo existe
if [[ -f "$dados_file" ]]; then
    # Coleta as informações do arquivo
PORTAINER_URL=$(grep "Dominio do portainer:" "$dados_file" | cut -d':' -f2 | xargs)
ADMIN_USERNAME=$(grep "Usuario:" "$dados_file" | cut -d':' -f2 | xargs)
ADMIN_PASSWORD=$(grep "Senha:" "$dados_file" | cut -d':' -f2 | xargs)
STACK_NAME=pgbouncer
STACK_FILE_PATH="/root/pgbouncer.yaml"

else
   # echo "Erro: Arquivo de dados não encontrado em $dados_file."
    sleep 2
echo -e "XXX\n55\nDEIXANDO STACK DO PGBOUNCER EDITÁVEL  \nXXX"
docker stack deploy --prune --resolve-image always -c pgbouncer.yaml pgbouncer >/dev/null 2>&1
sleep 5
   # exit 1
   #break
fi

# Função para autenticação
get_auth_token() {
    #echo "[INFO] Autenticando no Portainer..."
    sleep 2
    echo -e "XXX\n57\nAUTENTICANDO NO PORTAINER...  \nXXX"
    RESPONSE=$(curl -sk -X POST "https://$PORTAINER_URL/api/auth" \
        -H "Content-Type: application/json" \
        -d "{\"username\": \"$ADMIN_USERNAME\", \"password\": \"$ADMIN_PASSWORD\"}")
    TOKEN=$(echo "$RESPONSE" | jq -r '.jwt')
    if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]; then
        # echo "[ERRO] Falha na autenticação."
        echo -e "XXX\n59\nFALHA NA AUTENTICAÇÃO..  \nXXX"
sleep 5
echo -e "XXX\n60\nREVERTENDO E CRIANDO STACK PELO SERVIDOR  \nXXX"
docker stack deploy --prune --resolve-image always -c pgbouncer.yaml pgbouncer >/dev/null 2>&1
sleep 5
echo -e "XXX\n60\nCASO O PGBOUNCER JÁ ESTIVER EDITÁVEL, SERÁ MANTIDO  \nXXX"
        #exit 1
       # break
    fi
  #  echo "[SUCESSO] Autenticação realizada com sucesso. Token obtido."
 echo -e "XXX\n61\n[SUCESSO] AUTENTICAÇÃO OK  \nXXX"
}

# Função para obter o EndpointID
get_endpoint_id() {
   # echo "[INFO] Obtendo EndpointID..."
    echo -e "XXX\n62\n[INFO] OBTENDO ENDPOINTID \nXXX"
    RESPONSE=$(curl -sk -X GET "https://$PORTAINER_URL/api/endpoints" \
        -H "Authorization: Bearer $TOKEN")
    ENDPOINT_ID=$(echo "$RESPONSE" | jq -r '.[0].Id' 2>/dev/null)
    if [ -z "$ENDPOINT_ID" ] || [ "$ENDPOINT_ID" = "null" ]; then
        # echo "[ERRO] EndpointID não encontrado! Resposta: $RESPONSE"
        echo -e "XXX\n63\n[ERRO] ENDPOINTID NÃO ENCONTRADO \nXXX"
        sleep 5
        docker stack deploy --prune --resolve-image always -c pgbouncer.yaml pgbouncer >/dev/null 2>&1
        #exit 1
        #break
    fi
     echo -e "XXX\n64\n[SUCESSO] ENDPOINTID OBTIDO: $ENDPOINT_ID   \nXXX"
     sleep 3
    #echo "[SUCESSO] EndpointID obtido: $ENDPOINT_ID"
}

# Função para obter o SwarmID
get_swarm_id() {
   # echo "[INFO] Obtendo SwarmID..."
    echo -e "XXX\n65\n[INFO] OBTENDO SWARMID  \nXXX"
    RESPONSE=$(curl -sk -X GET "https://$PORTAINER_URL/api/endpoints/$ENDPOINT_ID/docker/swarm" \
        -H "Authorization: Bearer $TOKEN")
    SWARM_ID=$(echo "$RESPONSE" | jq -r '.ID' 2>/dev/null)
    if [ -z "$SWARM_ID" ] || [ "$SWARM_ID" = "null" ]; then
        #echo "[ERRO] SwarmID não encontrado! Resposta: $RESPONSE"
        echo -e "XXX\n66\n[ERRO] SWARMID NÃO ENCONTRADO   \nXXX"
        docker stack deploy --prune --resolve-image always -c pgbouncer.yaml pgbouncer >/dev/null 2>&1
       # exit 1
      # break
    fi
    #echo "[SUCESSO] SwarmID obtido: $SWARM_ID"
    echo -e "XXX\n67\n[SUCESSO] SWARMID OBTIDO: $SWARM_ID   \nXXX"
}

# Função para criar a stack
create_stack() {
    #echo "[INFO] Verificando existência do arquivo YAML..."
    echo -e "XXX\n68\n[INFO] VERIFICANDO SE YAML EXISTE  \nXXX"
    if [ ! -f "$STACK_FILE_PATH" ]; then
        #echo "[ERRO] Arquivo $STACK_FILE_PATH não encontrado!"
        echo -e "XXX\n69\n[ERRO] ARQUIVO $STACK_FILE_PATH NÃO ENCONTRADO 3/4  \nXXX"
        docker stack deploy --prune --resolve-image always -c pgbouncer.yaml pgbouncer >/dev/null 2>&1
        #exit 1
       # break
    fi

    #echo "[INFO] Criando stack '$STACK_NAME' no Portainer..."
     echo -e "XXX\n70\n[INFO] CRIANDO STACK $STACK_NAME NO PORTAINER 3/4  \nXXX"
    
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
        echo -e "XXX\n71\n[ERRO] ERRO AO CRIAR STACK  \nXXX"
        docker stack deploy --prune --resolve-image always -c pgbouncer.yaml pgbouncer >/dev/null 2>&1
        sleep 3
        echo -e "XXX\n72\nMANTENDO STACK DO PGBOUNCER NO PADRÃO ATUAL  \nXXX"
        sleep 3
       # exit 1
      # break
    fi

   # echo "[SUCESSO] Stack '$STACK_NAME' criada com sucesso!"
    echo -e "XXX\n72\n[SUCESSO] STACK $STACK_NAME  CRIADA COM SUCESSO  \nXXX"
}
sleep 5
# Fluxo de execução principal
# echo "[INFO] Iniciando processo de criação da stack..."
get_auth_token || exit 1
get_endpoint_id || exit 1
get_swarm_id || exit 1
create_stack || exit 1
# echo "[SUCESSO] Processo concluído."

##### PARTE 3: REDIS
   # A stack será criada no Portainer
    echo -e "XXX\n73\nDEIXANDO STACK DO REDIS EDITÁVEL  \nXXX"
   # echo "Criando a stack no Portainer para edição."
    # Substituir pelo comando ou rotina para criar a stack no Portainer
    # Aqui pode chamar um novo script ou rotina específica, exemplo:
   ## /path/to/criar_stack_no_portainer.sh "redis" "$painelpma"

#!/bin/bash

# Configurações
sleep 2
# Caminho para o arquivo de dados
dados_file="$HOME/dados_portainer/dados_portainer"
cd
docker stack rm redis >/dev/null 2>&1
# Verifica se o arquivo existe
if [[ -f "$dados_file" ]]; then
    # Coleta as informações do arquivo
PORTAINER_URL=$(grep "Dominio do portainer:" "$dados_file" | cut -d':' -f2 | xargs)
ADMIN_USERNAME=$(grep "Usuario:" "$dados_file" | cut -d':' -f2 | xargs)
ADMIN_PASSWORD=$(grep "Senha:" "$dados_file" | cut -d':' -f2 | xargs)
STACK_NAME=redis
STACK_FILE_PATH="/root/redis.yaml"

else
   # echo "Erro: Arquivo de dados não encontrado em $dados_file."
    sleep 2
echo -e "XXX\n74\nDEIXANDO STACK DO REDIS EDITÁVEL  \nXXX"
docker stack deploy --prune --resolve-image always -c redis.yaml redis >/dev/null 2>&1
sleep 5
    exit 1
fi

# Função para autenticação
get_auth_token() {
    #echo "[INFO] Autenticando no Portainer..."
    sleep 2
    echo -e "XXX\n75\nAUTENTICANDO NO PORTAINER...  \nXXX"
    RESPONSE=$(curl -sk -X POST "https://$PORTAINER_URL/api/auth" \
        -H "Content-Type: application/json" \
        -d "{\"username\": \"$ADMIN_USERNAME\", \"password\": \"$ADMIN_PASSWORD\"}")
    TOKEN=$(echo "$RESPONSE" | jq -r '.jwt')
    if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]; then
        # echo "[ERRO] Falha na autenticação."
        echo -e "XXX\n76\nFALHA NA AUTENTICAÇÃO..  \nXXX"
sleep 5
echo -e "XXX\n77\nREVERTENDO E CRIANDO STACK PELO SERVIDOR  \nXXX"
docker stack deploy --prune --resolve-image always -c redis.yaml redis >/dev/null 2>&1
sleep 5
echo -e "XXX\n78\nCASO O REDIS JÁ ESTIVER EDITÁVEL, SERÁ MANTIDO  \nXXX"
        exit 1
    fi
  #  echo "[SUCESSO] Autenticação realizada com sucesso. Token obtido."
 echo -e "XXX\n79\n[SUCESSO] AUTENTICAÇÃO OK  \nXXX"
}

# Função para obter o EndpointID
get_endpoint_id() {
   # echo "[INFO] Obtendo EndpointID..."
    echo -e "XXX\n80\n[INFO] OBTENDO ENDPOINTID \nXXX"
    RESPONSE=$(curl -sk -X GET "https://$PORTAINER_URL/api/endpoints" \
        -H "Authorization: Bearer $TOKEN")
    ENDPOINT_ID=$(echo "$RESPONSE" | jq -r '.[0].Id' 2>/dev/null)
    if [ -z "$ENDPOINT_ID" ] || [ "$ENDPOINT_ID" = "null" ]; then
        # echo "[ERRO] EndpointID não encontrado! Resposta: $RESPONSE"
        echo -e "XXX\n81\n[ERRO] ENDPOINTID NÃO ENCONTRADO \nXXX"
        sleep 5
        docker stack deploy --prune --resolve-image always -c redis.yaml redis >/dev/null 2>&1
        exit 1
    fi
     echo -e "XXX\n82\n[SUCESSO] ENDPOINTID OBTIDO: $ENDPOINT_ID   \nXXX"
     sleep 3
    #echo "[SUCESSO] EndpointID obtido: $ENDPOINT_ID"
}

# Função para obter o SwarmID
get_swarm_id() {
   # echo "[INFO] Obtendo SwarmID..."
    echo -e "XXX\n83\n[INFO] OBTENDO SWARMID  \nXXX"
    RESPONSE=$(curl -sk -X GET "https://$PORTAINER_URL/api/endpoints/$ENDPOINT_ID/docker/swarm" \
        -H "Authorization: Bearer $TOKEN")
    SWARM_ID=$(echo "$RESPONSE" | jq -r '.ID' 2>/dev/null)
    if [ -z "$SWARM_ID" ] || [ "$SWARM_ID" = "null" ]; then
        #echo "[ERRO] SwarmID não encontrado! Resposta: $RESPONSE"
        echo -e "XXX\n84\n[ERRO] SWARMID NÃO ENCONTRADO   \nXXX"
        docker stack deploy --prune --resolve-image always -c redis.yaml redis >/dev/null 2>&1
        exit 1
    fi
    #echo "[SUCESSO] SwarmID obtido: $SWARM_ID"
    echo -e "XXX\n90\n[SUCESSO] SWARMID OBTIDO: $SWARM_ID   \nXXX"
}

# Função para criar a stack
create_stack() {
    #echo "[INFO] Verificando existência do arquivo YAML..."
    echo -e "XXX\n91\n[INFO] VERIFICANDO SE YAML EXISTE  \nXXX"
    if [ ! -f "$STACK_FILE_PATH" ]; then
        #echo "[ERRO] Arquivo $STACK_FILE_PATH não encontrado!"
        echo -e "XXX\n92\n[ERRO] ARQUIVO $STACK_FILE_PATH NÃO ENCONTRADO 3/4  \nXXX"
        docker stack deploy --prune --resolve-image always -c redis.yaml redis >/dev/null 2>&1
        exit 1
    fi

    #echo "[INFO] Criando stack '$STACK_NAME' no Portainer..."
     echo -e "XXX\n93\n[INFO] CRIANDO STACK $STACK_NAME NO PORTAINER 3/4  \nXXX"
    
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
        echo -e "XXX\n95\n[ERRO] ERRO AO CRIAR STACK  \nXXX"
        docker stack deploy --prune --resolve-image always -c redis.yaml redis >/dev/null 2>&1
        sleep 3
        echo -e "XXX\n97\nMANTENDO STACK DO REDIS NO PADRÃO ATUAL  \nXXX"
        sleep 3
        exit 1
    fi

   # echo "[SUCESSO] Stack '$STACK_NAME' criada com sucesso!"
    echo -e "XXX\n98\n[SUCESSO] STACK $STACK_NAME  CRIADA COM SUCESSO  \nXXX"
}
sleep 5
# Fluxo de execução principal
# echo "[INFO] Iniciando processo de criação da stack..."
get_auth_token || exit 1
get_endpoint_id || exit 1
get_swarm_id || exit 1
create_stack || exit 1
# echo "[SUCESSO] Processo concluído."

 echo -e "XXX\n100\nPROCESSO CONCLUÍDO \nXXX"

 sleep 5
{
  tput reset 2>/dev/null         # Reinicia o terminal de forma segura
  exec 0</dev/tty 1>/dev/tty 2>&1 # Força redirecionamentos explícitos
  sleep 0.01                     # Pausa microscópica para sincronia
  clear                          # Limpeza final antes do whiptail
} || true
}|whiptail --title "AJUSTE DE ESSENCIAIS EDITÁVEIS NO PORTAINER" --gauge "Aguarde a instalação dos ítens necessários" 6 60 0


exit 0

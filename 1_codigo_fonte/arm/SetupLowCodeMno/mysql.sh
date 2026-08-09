#!/usr/bin/bash

# Aguarda o MySQL 8.0 compartilhado aceitar uma consulta autenticada.
setupmno_mysql80_service_exists() {
    docker service inspect mysql_mysql >/dev/null 2>&1
}

setupmno_mysql80_wait_ready() {
    local yaml_file="${1:-/root/mysql.yaml}"
    local progress_mode="${2:-silent}"
    local service_name="${SETUPMNO_MYSQL80_SERVICE_NAME:-mysql_mysql}"
    local attempt probe percent elapsed progress_message

    MYSQL80_CONTAINER_ID=""
    MYSQL80_ROOT_PASSWORD=""

    if [ "$progress_mode" = "progress" ]; then
        printf 'XXX\n3\nPreparando a validação do MySQL 8.0...\nXXX\n'
    fi

    [ -s "$yaml_file" ] || return 65
    MYSQL80_ROOT_PASSWORD=$(sed -n 's/^[[:space:]]*-[[:space:]]*MYSQL_ROOT_PASSWORD=//p' "$yaml_file" | head -n1)
    [ -n "$MYSQL80_ROOT_PASSWORD" ] || return 66

    for attempt in $(seq 1 181); do
        MYSQL80_CONTAINER_ID=$(docker ps \
            --filter "label=com.docker.swarm.service.name=$service_name" \
            --format '{{.ID}}' | head -n1)
        if [ -n "$MYSQL80_CONTAINER_ID" ]; then
            probe=$(docker exec "$MYSQL80_CONTAINER_ID" sh -c \
                'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" exec mysql -uroot --batch --skip-column-names -e "SELECT 1"' \
                2>/dev/null) || probe=""
            if [ "$probe" = "1" ]; then
                if [ "$progress_mode" = "progress" ]; then
                    printf 'XXX\n100\nMySQL 8.0 pronto. Continuando a instalação...\nXXX\n'
                    sleep 1
                fi
                return 0
            fi
        fi

        if [ "$progress_mode" = "progress" ]; then
            percent=$((10 + (attempt * 85 / 181)))
            elapsed=$(((attempt - 1) * 5))
            if [ -n "$MYSQL80_CONTAINER_ID" ]; then
                progress_message="MySQL 8.0 iniciou. Aguardando aceitar conexões autenticadas... (${elapsed}s)"
            else
                progress_message="Aguardando o serviço MySQL 8.0 iniciar... (${elapsed}s de até 900s)"
            fi
            printf 'XXX\n%s\n%s\nXXX\n' "$percent" "$progress_message"
        fi

        [ "$attempt" -lt 181 ] && sleep 5
    done

    return 67
}

setupmno_mysql80_require_ready() {
    local yaml_file="${1:-/root/mysql.yaml}"
    local status message gauge_pid

    exec 9> >(whiptail --title "INICIALIZANDO MYSQL 8.0" --gauge \
        "O banco está iniciando. Aguarde; este processo pode levar alguns minutos." \
        8 76 0)
    gauge_pid=$!

    setupmno_mysql80_wait_ready "$yaml_file" progress >&9
    status=$?

    exec 9>&-
    [ -n "$gauge_pid" ] && wait "$gauge_pid" 2>/dev/null || true

    [ "$status" -eq 0 ] && return 0

    case "$status" in
        65) message="O arquivo de configuração do MySQL 8.0 não foi encontrado." ;;
        66) message="A senha do MySQL 8.0 não pôde ser recuperada com segurança." ;;
        *)  message="O MySQL 8.0 não aceitou conexão autenticada em até 15 minutos." ;;
    esac

    whiptail --title "ERRO MYSQL 8.0" --msgbox \
        "$message\n\nA instalação foi interrompida antes de criar ou usar o banco." \
        13 76 1>&2
    return "$status"
}

setupmno_mysql80_create_database() {
    local database_name="$1"
    local query

    [[ "$database_name" =~ ^[A-Za-z0-9_]+$ ]] || return 68
    [ -n "$MYSQL80_CONTAINER_ID" ] || return 69
    [ -n "$MYSQL80_ROOT_PASSWORD" ] || return 70

    query="CREATE DATABASE IF NOT EXISTS \`$database_name\`;"
    docker exec "$MYSQL80_CONTAINER_ID" sh -c \
        'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" exec mysql -uroot -e "$1"' \
        setupmno-mysql "$query" >/dev/null 2>&1
}

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
		whiptail --title "INSTALAÇÃO DO MYSQL: BANCO DE DADOS" --msgbox "$msg" --fb 10 70;
	}

  while true; do
CHOICE=$(
whiptail --title "INSTALAÇÃO DO MYSQL: BANCO DE DADOS" --menu "Aperte ENTER para iniciar a instalação do MYSQL ou selecione SAIR (Utilize setas e Enter) " 20 70 2 \
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

#########################################################
#
# VERIFICAÇÃO DE DADOS
#

senha_mysql=$(openssl rand -hex 8)
# Ajuste do terminal para garantir compatibilidade
{
  tput reset 2>/dev/null         # Reinicia o terminal de forma segura
  exec 0</dev/tty 1>/dev/tty 2>&1 # Força redirecionamentos explícitos
  sleep 0.01                     # Pausa microscópica para sincronia
  clear                          # Limpeza final antes do whiptail
} || true

    # Exibe as informações formatadas com mais espaço na tela
    whiptail --title "Dados da Instalação" \
    --msgbox "Dados Gerados:\n\n1) Senha do seu Mysql gerada: \e[33m$senha_mysql\n2) Criar Stack no Portainer: $([ "$criar_portainer" == "0" ] && echo "0 (Editável)" || echo "1 (Não editável)")\n\nConfira e Tecle Enter para continuar. Na próxima etapa você poderá confirmar os dados ou corrigir, se necessário." \
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
export NEWT_COLORS='
root=,white
window=,black
border=white,black
textbox=white,black
button=black,white
'  

clear
{
echo -e "XXX\n3\nCRIANDO STACKS DO MYSQL 1/4 \nXXX"
sleep 3
echo -e "XXX\n25\nCRIANDO STACKS DO MYSQL 1/4 - CONCLUIDO \nXXX"
sleep 3 
echo -e "XXX\n25\nFAZENDO O BUILD DOS STACKS DO MYSQL 2/4 \nXXX"
sleep 3
echo -e "XXX\n50\nFAZENDO O BUILD DOS STACKS DO MYSQL 2/4 - CONCLUIDO \nXXX"
sleep 3
echo -e "XXX\n50\nINICIANDO BUILD DO MYSQL 3/4 \nXXX"
sleep 3
echo -e "XXX\n75\nINICIANDO BUILD DO MYSQL 3/4 - CONCLUIDO \nXXX"

#######################################################
#
#  INSTALANDO O MYSQL
#

cd

cd
mysql_container=""
if setupmno_mysql80_service_exists; then
    mysql_container="mysql_mysql"
fi


if [[ ("$mysql_container" == "") ]]; then
cat > mysql.yaml << EOL
version: '3.7'
services:
    mysql:
        image: percona/percona-server:8.0
        environment:
            - MYSQL_ROOT_PASSWORD=$senha_mysql
            - TZ=America/Fortaleza
        networks: 
            - externa
            - interna

        volumes:
            - mysql_data:/var/lib/mysql
        deploy:
            placement:
                constraints: [node.role == manager]
        command:
            --character-set-server=utf8mb4 --collation-server=utf8mb4_general_ci --sql-mode="" --default-authentication-plugin=mysql_native_password  --port=3306 --max-allowed-packet=512MB
volumes:
    mysql_data:

networks: 
    externa: 
        external: true
    interna: 
        external: true

EOL

#docker stack deploy --prune --resolve-image always -c mysql.yaml mysql >/dev/null 2>&1

if [[ "$criar_portainer" == "0" ]]; then
    # A stack será criada no Portainer
    echo -e "XXX\n6\nCRIANDO STACK NO PORTAINER 3/4  \nXXX"
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
STACK_NAME=mysql
STACK_FILE_PATH="/root/mysql.yaml"

else
   # echo "Erro: Arquivo de dados não encontrado em $dados_file."
    sleep 5
echo -e "XXX\n7\nSEM ARQUIVO DE DADOS DO PORTAINER 3/4  \nXXX"
docker stack deploy --prune --resolve-image always -c mysql.yaml mysql >/dev/null 2>&1
sleep 5
    exit 1
fi

# Função para autenticação
get_auth_token() {
    #echo "[INFO] Autenticando no Portainer..."
    echo -e "XXX\n8\nAUTENTICANDO NO PORTAINER... 3/4  \nXXX"
    RESPONSE=$(curl -sS -X POST "https://$PORTAINER_URL/api/auth" \
        -H "Content-Type: application/json" \
        -d "{\"username\": \"$ADMIN_USERNAME\", \"password\": \"$ADMIN_PASSWORD\"}")
    TOKEN=$(echo "$RESPONSE" | jq -r '.jwt')
    if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]; then
        # echo "[ERRO] Falha na autenticação."
        echo -e "XXX\n9\nFALHA NA AUTENTICAÇÃO.. 3/4  \nXXX"
sleep 5
echo -e "XXX\n78\nREVERTENDO E CRIANDO STACK PELO SERVIDOR 3/4  \nXXX"
docker stack deploy --prune --resolve-image always -c mysql.yaml mysql >/dev/null 2>&1
sleep 5
        exit 1
    fi
  #  echo "[SUCESSO] Autenticação realizada com sucesso. Token obtido."
 echo -e "XXX\n10\n[SUCESSO] AUTENTICAÇÃO OK 3/4  \nXXX"
}

# Função para obter o EndpointID
get_endpoint_id() {
   # echo "[INFO] Obtendo EndpointID..."
    echo -e "XXX\n11\n[INFO] OBTENDO ENDPOINTID 3/4  \nXXX"
    RESPONSE=$(curl -sS -X GET "https://$PORTAINER_URL/api/endpoints" \
        -H "Authorization: Bearer $TOKEN")
    ENDPOINT_ID=$(echo "$RESPONSE" | jq -r '.[0].Id')
    if [ -z "$ENDPOINT_ID" ] || [ "$ENDPOINT_ID" = "null" ]; then
        # echo "[ERRO] EndpointID não encontrado! Resposta: $RESPONSE"
        echo -e "XXX\n12\n[ERRO] ENDPOINTID NÃO ENCONTRADO 3/4  \nXXX"
        docker stack deploy --prune --resolve-image always -c mysql.yaml mysql >/dev/null 2>&1
        exit 1
    fi
     echo -e "XXX\n13\n[SUCESSO] ENDPOINTID OBTIDO: $ENDPOINT_ID  3/4  \nXXX"
    #echo "[SUCESSO] EndpointID obtido: $ENDPOINT_ID"
}

# Função para obter o SwarmID
get_swarm_id() {
   # echo "[INFO] Obtendo SwarmID..."
    echo -e "XXX\n14\n[INFO] OBTENDO SWARMID  3/4  \nXXX"
    RESPONSE=$(curl -sS -X GET "https://$PORTAINER_URL/api/endpoints/$ENDPOINT_ID/docker/swarm" \
        -H "Authorization: Bearer $TOKEN")
    SWARM_ID=$(echo "$RESPONSE" | jq -r '.ID')
    if [ -z "$SWARM_ID" ] || [ "$SWARM_ID" = "null" ]; then
        #echo "[ERRO] SwarmID não encontrado! Resposta: $RESPONSE"
        echo -e "XXX\n15\n[ERRO] SWARMID NÃO ENCONTRADO 3/4  \nXXX"
        docker stack deploy --prune --resolve-image always -c mysql.yaml mysql >/dev/null 2>&1
        exit 1
    fi
    #echo "[SUCESSO] SwarmID obtido: $SWARM_ID"
    echo -e "XXX\n16\n[SUCESSO] SWARMID OBTIDO: $SWARM_ID  3/4  \nXXX"
}

# Função para criar a stack
create_stack() {
    #echo "[INFO] Verificando existência do arquivo YAML..."
    echo -e "XXX\n17\n[INFO] VERIFICANDO SE YAML EXISTE 3/4  \nXXX"
    if [ ! -f "$STACK_FILE_PATH" ]; then
        #echo "[ERRO] Arquivo $STACK_FILE_PATH não encontrado!"
        echo -e "XXX\n18\n[ERRO] ARQUIVO $STACK_FILE_PATH NÃO ENCONTRADO 3/4  \nXXX"
        docker stack deploy --prune --resolve-image always -c mysql.yaml mysql >/dev/null 2>&1
        exit 1
    fi

    #echo "[INFO] Criando stack '$STACK_NAME' no Portainer..."
     echo -e "XXX\n19\n[INFO] CRIANDO STACK $STACK_NAME NO PORTAINER 3/4  \nXXX"
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
        echo -e "XXX\n20\n[ERRO] ERRO AO CRIAR STACK 3/4  \nXXX"
        docker stack deploy --prune --resolve-image always -c mysql.yaml mysql >/dev/null 2>&1
        exit 1
    fi

   # echo "[SUCESSO] Stack '$STACK_NAME' criada com sucesso!"
    echo -e "XXX\n21\n[SUCESSO] STACK $STACK_NAME  CRIADA COM SUCESSO 3/4  \nXXX"
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
    docker stack deploy --prune --resolve-image always -c mysql.yaml mysql >/dev/null 2>&1
else
    # Caso inesperado (não deve ocorrer devido à validação anterior no while loop)
   # echo "Erro: valor inesperado para criar_portainer. Encerrando..."
    echo -e "XXX\n22\n[ERRO] ERRO INESPERADO PARA CRIAR STACK NO PORTAINER 3/4  \nXXX"
    sleep 5
    echo -e "XXX\n22\nREVERTENDO E CRIANDO STACK PELO SERVIDOR 3/4  \nXXX"
docker stack deploy --prune --resolve-image always -c mysql.yaml mysql >/dev/null 2>&1
sleep 5

    exit 1
fi



fi

echo -e "XXX\n75\nFINALIZANDO BUILD DO MYSQL 4/4  \nXXX"

sleep 5

echo -e "XXX\n100\nFINALIZANDO BUILD DO MYSQL 4/4 - CONCLUIDO  \nXXX"
}|whiptail --title "MYSQL - PROGRESSO DA INSTALAÇÃO" --gauge "Aguarde a instalaão dos ítens necessários" 6 60 0

setupmno_mysql80_require_ready /root/mysql.yaml || exit 1

# FIM DE INSTALANDO O APPSMITH
#
#######################################################
if [[ ("$mysql_container" == "") ]]; then
whiptail --msgbox "Parabéns, Mysql foi instalado com sucesso! Pressione ENTER para voltar ao Menu Principal" 20 78

else
whiptail --msgbox "Atenção: Já havia um Mysql instalado e o mesmo foi mantido! Pressione ENTER para voltar ao Menu Principal" 20 78

fi

exit 0

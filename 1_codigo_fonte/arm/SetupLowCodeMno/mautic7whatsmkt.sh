#!/usr/bin/bash
#########################################################
# # cloudflare tunnel - records automáticos
#    LOADING
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

clear

amarelo="\e[33m"
verde="\e[32m"
branco="\e[97m"
bege="\e[93m"
vermelho="\e[91m"
reset="\e[0m"

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

# VERIFICAR TIPO DE INSTALAÇÃO
INSTALL_TYPE_FILE="/root/.cloudflared_config/installation_type"
if [ -f "$INSTALL_TYPE_FILE" ]; then
    INSTALL_TYPE=$(cat "$INSTALL_TYPE_FILE")
else
    INSTALL_TYPE="TRADICIONAL"
fi

# CARREGAR CREDENCIAIS CONFORME TIPO DE INSTALAÇÃO
if [ "$INSTALL_TYPE" = "CLOUDFLARE_TUNNEL" ]; then
    if [ -f "/root/.cloudflared_config/cloudflare_credentials" ]; then
        source "/root/.cloudflared_config/cloudflare_credentials"
    fi
else
    if [ -f "/root/.tradicional_config/tradicional_credentials" ]; then
        source "/root/.tradicional_config/tradicional_credentials"
    fi
fi

function msg() {
                msg=$1
                whiptail --title "MAUTIC 7 + WHATSAPP MKT: AUTOMAÇÃO DE MARKETING" --msgbox "$msg" --fb 10 70;
        }

  while true; do
CHOICE=$(
whiptail --title "MAUTIC 7 + WHATSAPP MKT: AUTOMAÇÃO DE MARKETING" --menu "Aperte ENTER para iniciar a instalação do MAUTIC 7 + WHATSAPP MKT ou selecione SAIR (Utilize setas e Enter)\n\nTIPO DE INSTALAÇÃO DETECTADO: $INSTALL_TYPE\n\nINSTRUÇÕES:\nAntes de prosseguir, verifique os registros DNS conforme seu tipo de instalação:" 20 70 2 \
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
done


  while true ; do
                url_mautic=$(whiptail --title "URL do Mautic" --inputbox "Digite o Link do Mautic (ex: mkt.seudominio.com):" --fb 12 60 3>&1 1>&2 2>&3) ; saida=$?
                if [[ $saida -eq '0' ]] ; then
                        if [[ -z $url_mautic ]] ; then msg "Digite o link do Mautic, para poder continuar" ; continue ; else break; fi
                else
                        echo $url_mautic ; echo "saindo..."  &  exit 0 ;
                fi
        done



# Perguntar ao usuário se deseja criar a stack no Portainer

 while true ; do
                criar_portainer=$(whiptail --title "Criar Stack no Portainer? - 0 ou 1" --inputbox "Digite 0 para poder editar stack no portainer ou 1 para não poder editar" --fb 12 60 3>&1 1>&2 2>&3) ; saida=$?
                if [[ $saida -eq '0' ]] ; then
                #       if [[ -z $senhamautic ]] ; then msg "Digite a senha do Mautic, para poder continuar" ; continue ; else break; fi
                if [[ "$criar_portainer" != "0" && "$criar_portainer" != "1" ]] ; then msg "Digite apenas o número 0 ou o número 1, para poder continuar. Digite 0 para poder editar stack no portainer ou 1 para não poder editar" ; continue ; else break; fi
    else
                        echo $criar_portainer ; echo "saindo..."  &  exit 0 ;
                fi
        done



# FIM DE PERGUNTAS PARA VARIAVEIS
#
#########################################################
#
# VERIFICAÇÃO DE DADOS
#


nome_principal="mautic"  #nome do app
sufixo_app=$(date | md5sum | head -c7)
nome_app=$nome_principal$sufixo_app
mysql_container=$(docker ps -qf name=mysql84)

if [[ ("$mysql_container" == "") ]]; then
 senha_mysql=$(openssl rand -hex 8)

cd

cd

cat > mysql84.yaml << EOL
version: '3.7'
services:
    mysql84:
        image: percona/percona-server:8.4
        environment:
            - MYSQL_ROOT_PASSWORD=$senha_mysql
            - TZ=America/Fortaleza
        networks:
            - externa
            - interna
        volumes:
            - mysql84_data:/var/lib/mysql
        deploy:
            placement:
                constraints: [node.role == manager]
        command:
            - --character-set-server=utf8mb4
            - --collation-server=utf8mb4_general_ci
            - --sql-mode=
            - --mysql-native-password=ON       # <<< substitui default-authentication-plugin
            - --port=3306
            - --max-allowed-packet=512MB
volumes:
    mysql84_data:
networks:
    externa:
        external: true
    interna:
        external: true

EOL

#docker stack deploy --prune --resolve-image always -c mysql84.yaml mysql84 >/dev/null 2>&1

if [[ "$criar_portainer" == "0" ]]; then

{
  tput reset 2>/dev/null         # Reinicia o terminal de forma segura
  exec 0</dev/tty 1>/dev/tty 2>&1 # Força redirecionamentos explícitos
  sleep 0.01                     # Pausa microscópica para sincronia
  clear                          # Limpeza final antes do whiptail
} || true

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
{




    # A stack será criada no Portainer
    echo -e "XXX\n6\nCRIANDO STACK NO PORTAINER 3/4  \nXXX"

# Configurações

# Caminho para o arquivo de dados
dados_file="$HOME/dados_portainer/dados_portainer"

# Verifica se o arquivo existe
if [[ -f "$dados_file" ]]; then
    # Coleta as informações do arquivo
PORTAINER_URL=$(grep "Dominio do portainer:" "$dados_file" | cut -d':' -f2 | xargs)
ADMIN_USERNAME=$(grep "Usuario:" "$dados_file" | cut -d':' -f2 | xargs)
ADMIN_PASSWORD=$(grep "Senha:" "$dados_file" | cut -d':' -f2 | xargs)
STACK_NAME=mysql84
STACK_FILE_PATH="/root/mysql84.yaml"

else
   # echo "Erro: Arquivo de dados não encontrado em $dados_file."
    sleep 5
echo -e "XXX\n7\nSEM ARQUIVO DE DADOS DO PORTAINER 3/4  \nXXX"
docker stack deploy --prune --resolve-image always -c mysql84.yaml mysql84 >/dev/null 2>&1
sleep 5
    exit 1
fi

# Função para autenticação
get_auth_token() {
    #echo "[INFO] Autenticando no Portainer..."
    echo -e "XXX\n8\nAUTENTICANDO NO PORTAINER... 3/4  \nXXX"
    RESPONSE=$(curl -sk -X POST "https://$PORTAINER_URL/api/auth" \
        -H "Content-Type: application/json" \
        -d "{\"username\": \"$ADMIN_USERNAME\", \"password\": \"$ADMIN_PASSWORD\"}")
    TOKEN=$(echo "$RESPONSE" | jq -r '.jwt')
    if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]; then
        # echo "[ERRO] Falha na autenticação."
        echo -e "XXX\n9\nFALHA NA AUTENTICAÇÃO.. 3/4  \nXXX"
sleep 5
echo -e "XXX\n78\nREVERTENDO E CRIANDO STACK PELO SERVIDOR 3/4  \nXXX"
docker stack deploy --prune --resolve-image always -c mysql84.yaml mysql84 >/dev/null 2>&1
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
    RESPONSE=$(curl -sk -X GET "https://$PORTAINER_URL/api/endpoints" \
        -H "Authorization: Bearer $TOKEN")
    ENDPOINT_ID=$(echo "$RESPONSE" | jq -r '.[0].Id')
    if [ -z "$ENDPOINT_ID" ] || [ "$ENDPOINT_ID" = "null" ]; then
        # echo "[ERRO] EndpointID não encontrado! Resposta: $RESPONSE"
        echo -e "XXX\n12\n[ERRO] ENDPOINTID NÃO ENCONTRADO 3/4  \nXXX"
        docker stack deploy --prune --resolve-image always -c mysql84.yaml mysql84 >/dev/null 2>&1
        exit 1
    fi
     echo -e "XXX\n13\n[SUCESSO] ENDPOINTID OBTIDO: $ENDPOINT_ID  3/4  \nXXX"
    #echo "[SUCESSO] EndpointID obtido: $ENDPOINT_ID"
}

# Função para obter o SwarmID
get_swarm_id() {
   # echo "[INFO] Obtendo SwarmID..."
    echo -e "XXX\n14\n[INFO] OBTENDO SWARMID  3/4  \nXXX"
    RESPONSE=$(curl -sk -X GET "https://$PORTAINER_URL/api/endpoints/$ENDPOINT_ID/docker/swarm" \
        -H "Authorization: Bearer $TOKEN")
    SWARM_ID=$(echo "$RESPONSE" | jq -r '.ID')
    if [ -z "$SWARM_ID" ] || [ "$SWARM_ID" = "null" ]; then
        #echo "[ERRO] SwarmID não encontrado! Resposta: $RESPONSE"
        echo -e "XXX\n15\n[ERRO] SWARMID NÃO ENCONTRADO 3/4  \nXXX"
        docker stack deploy --prune --resolve-image always -c mysql84.yaml mysql84 >/dev/null 2>&1
        exit 1
    fi
    #echo "[SUCESSO] SwarmID obtido: $SWARM_ID"
    echo -e "XXX\n16\n[SUCESSO] SWARMID OBTIDO: $SWARM_ID  3/4  \nXXX"
}

# Função para criar a stack
create_stack() {
    ##echo "[INFO] Verificando existência do arquivo YAML..."
    echo -e "XXX\n17\n[INFO] VERIFICANDO SE YAML EXISTE 3/4  \nXXX"
    if [ ! -f "$STACK_FILE_PATH" ]; then
        #echo "[ERRO] Arquivo $STACK_FILE_PATH não encontrado!"
        echo -e "XXX\n18\n[ERRO] ARQUIVO $STACK_FILE_PATH NÃO ENCONTRADO 3/4  \nXXX"
        docker stack deploy --prune --resolve-image always -c mysql84.yaml mysql84 >/dev/null 2>&1
        exit 1
    fi

    #echo "[INFO] Criando stack '$STACK_NAME' no Portainer..."
     echo -e "XXX\n19\n[INFO] CRIANDO STACK $STACK_NAME NO PORTAINER 3/4  \nXXX"
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
        echo -e "XXX\n20\n[ERRO] ERRO AO CRIAR STACK 3/4  \nXXX"
        docker stack deploy --prune --resolve-image always -c mysql84.yaml mysql84 >/dev/null 2>&1
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

}|whiptail --title "CRIANDO STACK MYSQL" --gauge "Aguarde a instalação dos ítens necessários" 6 60 0

elif [[ "$criar_portainer" == "1" ]]; then
    # A stack será criada diretamente no Docker
    echo -e "XXX\n22\nCRIANDO STACK NO PORTAINER 3/4  \nXXX"
    docker stack deploy --prune --resolve-image always -c mysql84.yaml mysql84 >/dev/null 2>&1
else
    # Caso inesperado (não deve ocorrer devido à validação anterior no while loop)
   # echo "Erro: valor inesperado para criar_portainer. Encerrando..."
    echo -e "XXX\n22\n[ERRO] ERRO INESPERADO PARA CRIAR STACK NO PORTAINER 3/4  \nXXX"
    sleep 5
    echo -e "XXX\n22\nREVERTENDO E CRIANDO STACK PELO SERVIDOR 3/4  \nXXX"
docker stack deploy --prune --resolve-image always -c mysql84.yaml mysql84 >/dev/null 2>&1
sleep 5

    exit 1
fi

fi



#CRIAÇÃO DE BANCO MYSQL INICIO

{
  tput reset 2>/dev/null         # Reinicia o terminal de forma segura
  exec 0</dev/tty 1>/dev/tty 2>&1 # Força redirecionamentos explícitos
  sleep 0.01                     # Pausa microscópica para sincronia
  clear                          # Limpeza final antes do whiptail
} || true

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
{


sleep 1
echo -e "XXX\n23\nBANCO DE DADOS DO MAUTIC - ATÉ 15 MINUTOS\nXXX"
sleep 60
# Aguardar container MySQL ficar disponível
max_wait_time=2000
wait_interval=60
elapsed_time=0
container_id2=""

while [ $elapsed_time -lt $max_wait_time ]; do
    container_id2=$(docker ps -qf name=mysql84)
    if [ -n "$container_id2" ]; then
        break
    fi
    sleep $wait_interval
    elapsed_time=$((elapsed_time + wait_interval))  # CORREÇÃO: removed extra 'a'
done

if [ -z "$container_id2" ]; then
    echo -e "XXX\n24\nERRO: Container MySQL não encontrado\nXXX"
    sleep 5
    exit 1
fi

echo -e "XXX\n25\nCONTAINER MYSQL ENCONTRADO\nXXX"

# Extrair senha do MySQL
senha_mysql=$(grep -oP '(?<=MYSQL_ROOT_PASSWORD=).+' /root/mysql84.yaml)

if [ -z "$senha_mysql" ]; then
    echo -e "XXX\n25\nERRO: Senha MySQL não encontrada\nXXX"
    sleep 5
    exit 1
fi

echo -e "XXX\n26\nCRIANDO BANCO: $nome_app\nXXX"

# Criar banco de dados (versão mais segura)
 if docker exec -i $container_id2 bash -c "MYSQL_PWD=\"$senha_mysql\" mysql -u root -e \"CREATE DATABASE $nome_app;\"" >/dev/null 2>&1; then
    echo -e "XXX\n27\nBANCO $nome_app CRIADO COM SUCESSO\nXXX"
    sleep 5
else
    echo -e "XXX\n28\nERRO AO CRIAR BANCO DE DADOS, CANCELANDO INSTALAÇÃO\nXXX"
    sleep 5
setup-mno
fi

echo -e "XXX\n29\nCRIAÇÃO DO BANCO FINALIZADA\nXXX"
sleep 5





}|whiptail --title "CRIANDO BANCO MYSQL" --gauge "Aguarde a instalação dos ítens necessários" 6 60 0

#CRIAÇÃO DE BANCO MYSQL FIM

# Ajuste do terminal para garantir compatibilidade
{
  tput reset 2>/dev/null         # Reinicia o terminal de forma segura
  exec 0</dev/tty 1>/dev/tty 2>&1 # Força redirecionamentos explícitos
  sleep 0.01                     # Pausa microscópica para sincronia
  clear                          # Limpeza final antes do whiptail
} || true


    # Exibe as informações formatadas com mais espaço na tela
    whiptail --title "Dados Fornecidos" \
    --msgbox "TIPO DE INSTALAÇÃO: $INSTALL_TYPE\n\nDados Preenchidos:\n\n1) URL do Mautic: $url_mautic\n2) Criar Stack no Portainer: $([ "$criar_portainer" == "0" ] && echo "0 (Editável)" || echo "1 (Não editável)")\n\nConfira e Tecle Enter para continuar. Na próxima etapa você poderá confirmar os dados ou corrigir, se necessário." \
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
echo -e "XXX\n29\nVERIFICANDO CONFIGURAÇÃO... \nXXX"

if [ "$INSTALL_TYPE" = "TRADICIONAL" ] && [ "$criar_dns" = "0" ]; then
    # CONFIGURAÇÃO TRADICIONAL COM DNS AUTOMÁTICO
    echo -e "XXX\n29\nCONFIGURANDO DNS AUTOMÁTICO (TRADICIONAL)... \nXXX"
    
    DOMINIO_PRINCIPAL=$(echo "$url_mautic" | cut -d'.' -f2-)
    SUBDOMINIO=${url_mautic%%.$DOMINIO_PRINCIPAL}

    # Verificar e remover registros existentes
    echo -e "XXX\n29\nVERIFICANDO REGISTROS EXISTENTES... \nXXX"
    EXISTING_RECORDS=$(curl -s -X GET \
        "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records?name=${url_mautic}" \
        -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
        -H "Content-Type: application/json")

    COUNT=$(echo "$EXISTING_RECORDS" | jq '.result | length')
    if [[ "$COUNT" -gt 0 ]]; then
        echo -e "XXX\n29\nREMOVENDO REGISTROS ANTIGOS... \nXXX"
        echo "$EXISTING_RECORDS" | jq -r '.result[].id' | while read -r REC_ID; do
            [[ -z "$REC_ID" ]] && continue
            curl -s -X DELETE \
                "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records/${REC_ID}" \
                -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
                -H "Content-Type: application/json" >/dev/null 2>&1
        done
    fi

    # Criar registro CNAME
    echo -e "XXX\n29\nCRIANDO REGISTRO CNAME... \nXXX"
    CNAME_RESPONSE=$(curl -s -X POST \
        "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records" \
        -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
        -H "Content-Type: application/json" \
        --data '{"type":"CNAME","name":"'${url_mautic}'","content":"'${nome_servidor}'.'${DOMINIO_PRINCIPAL}'","ttl":1,"proxied":false}')

    if echo "$CNAME_RESPONSE" | grep -q '"success":true'; then
        echo -e "XXX\n30\nREGISTRO CNAME CRIADO COM SUCESSO! \nXXX"
    else
        echo -e "XXX\n30\nAVISO: ERRO AO CRIAR REGISTRO CNAME \nXXX"
    fi

elif [ "$INSTALL_TYPE" = "CLOUDFLARE_TUNNEL" ]; then
    # CONFIGURAÇÃO CLOUDFLARE TUNNEL - DNS E ROTAS
    echo -e "XXX\n30\nCONFIGURANDO CLOUDFLARE TUNNEL (DNS + ROTAS)... \nXXX"
    
    DOMINIO_PRINCIPAL=$(echo "$url_mautic" | cut -d'.' -f2-)
    SUBDOMINIO=${url_mautic%%.$DOMINIO_PRINCIPAL}

    # 1. PRIMEIRO CONFIGURAR O DNS
    echo -e "XXX\n30\nCONFIGURANDO REGISTRO DNS... \nXXX"
    
    # Verificar e remover registros existentes
    EXISTING_RECORDS=$(curl -s -X GET \
        "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records?name=${url_mautic}" \
        -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
        -H "Content-Type: application/json")

    COUNT=$(echo "$EXISTING_RECORDS" | jq '.result | length')
    if [[ "$COUNT" -gt 0 ]]; then
        echo -e "XXX\n30\nREMOVENDO REGISTROS DNS ANTIGOS... \nXXX"
        echo "$EXISTING_RECORDS" | jq -r '.result[].id' | while read -r REC_ID; do
            [[ -z "$REC_ID" ]] && continue
            curl -s -X DELETE \
                "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records/${REC_ID}" \
                -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
                -H "Content-Type: application/json" >/dev/null 2>&1
        done
    fi

    # Criar registro CNAME para o tunnel
    echo -e "XXX\n30\nCRIANDO REGISTRO CNAME PARA TUNNEL... \nXXX"
    DNS_RESPONSE=$(curl -s -X POST \
        "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records" \
        -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
        -H "Content-Type: application/json" \
        --data "{\"type\":\"CNAME\",\"name\":\"${url_mautic}\",\"content\":\"${TUNNEL_ID}.cfargotunnel.com\",\"ttl\":1,\"proxied\":true}")

    if echo "$DNS_RESPONSE" | grep -q '"success":true'; then
        echo -e "XXX\n30\nREGISTRO DNS CRIADO COM SUCESSO! \nXXX"
    else
        echo -e "XXX\n30\nAVISO: ERRO AO CRIAR REGISTRO DNS \nXXX"
    fi

    # 2. AGORA ATUALIZAR AS ROTAS DO TUNNEL
    echo -e "XXX\n35\nATUALIZANDO CONFIGURAÇÃO DO TUNNEL... \nXXX"

    # Configuração do novo serviço para o Baserow
    NEW_SERVICE="http://mautic_web${sufixo_app}:80"
    
    # Arquivos temporários
    TIMESTAMP=$(date -u +%Y%m%dT%H%M%SZ)
    TMPDIR=$(mktemp -d)
    BACKUP_RAW="$TMPDIR/backup_raw.$TIMESTAMP.json"
    TO_PUT="$TMPDIR/to_put.$TIMESTAMP.json"

    # 1) Obter configuração atual do tunnel
    echo -e "XXX\n40\nOBTENDO CONFIGURAÇÃO ATUAL DO TUNNEL... \nXXX"
    curl -sS -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
      "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/cfd_tunnel/$TUNNEL_ID/configurations" \
      | jq '.' > "$BACKUP_RAW"

    # Verificar se obteve sucesso
    if ! jq -e '.success == true' "$BACKUP_RAW" >/dev/null 2>&1; then
        echo -e "XXX\n45\nERRO: FALHA AO OBTER CONFIGURAÇÃO DO TUNNEL \nXXX"
        sleep 3
    else
        echo -e "XXX\n45\nCONFIGURAÇÃO OBTIDA COM SUCESSO \nXXX"
    fi

    # 2) Construir novo payload
    echo -e "XXX\n50\nCONFIGURANDO NOVAS ROTAS... \nXXX"
    
    jq --arg host "$url_mautic" --arg service "$NEW_SERVICE" '
      (.result.config // {}) as $cfg
      | ($cfg.ingress // []) as $ing
      # Remover entradas catch-all existentes no meio
      | ($ing | map(select(.service != "http_status:404"))) as $clean
      # Coletar hostnames existentes para evitar duplicatas
      | ($clean | map(.hostname // "")) as $existing_names
      # Se o novo host já existe, não adicionar duplicata; senão adicionar nova rota
      | (if ($existing_names | index($host)) then $clean else ($clean + [ { hostname: $host, service: $service, originRequest: { noTlsVerify: true, httpHostHeader: $host } } ]) end) as $merged
      # Adicionar exatamente um catch-all
      | ($merged + [{ service: "http_status:404" }]) as $final_ing
      # Construir novo objeto de configuração, preservando outras chaves
      | ($cfg + { ingress: $final_ing }) as $newcfg
      | { config: $newcfg }
    ' "$BACKUP_RAW" > "$TO_PUT"

    # 3) Aplicar nova configuração
    echo -e "XXX\n55\nAPLICANDO NOVA CONFIGURAÇÃO DO TUNNEL... \nXXX"
    APPLY_RESPONSE=$(curl -sS -X PUT "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/cfd_tunnel/$TUNNEL_ID/configurations" \
      -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
      -H "Content-Type: application/json" \
      --data-binary @"$TO_PUT")

    if echo "$APPLY_RESPONSE" | grep -q '"success":true'; then
        echo -e "XXX\n60\nTUNNEL CONFIGURADO COM SUCESSO! \nXXX"
    else
        echo -e "XXX\n60\nAVISO: ERRO AO CONFIGURAR TUNNEL \nXXX"
    fi

    # Limpeza
    rm -rf "$TMPDIR"

 else
    # INSTALAÇÃO TRADICIONAL SEM DNS AUTOMÁTICO
    echo -e "XXX\n10\nVERIFICANDO CONFIGURAÇÃO (TRADICIONAL SEM AUTOMAÇÃO)... \nXXX"
    # Verificação básica de DNS
    if nslookup "$url_mautic" >/dev/null 2>&1; then
        echo -e "XXX\n15\nDNS CONFIGURADO \nXXX"
    else
        echo -e "XXX\n15\nAVISO: VERIFIQUE A CONFIGURAÇÃO DNS \nXXX"
    fi
fi


if [ "$INSTALL_TYPE" = "TRADICIONAL" ] && [ "$criar_dns" = "1" ]; then


# Função para verificar o domínio quando fora do cloudflare
# url_mautic=$1
ip_servidor=$(curl -s --max-time 10 ipinfo.io/ip)

echo -e "XXX\n3\nVERIFICANDO SUBDOMÍNIO: $url_mautic \nXXX"
sleep 3

tentativas=5
tentativa_atual=1
sucesso=0

while [ $tentativa_atual -le $tentativas ]; do
    echo -e "XXX\n$(( (tentativa_atual * 12) / tentativas + 3 ))\nTentativa $tentativa_atual de $tentativas...\nXXX"
    
    dns_ip=$(timeout 10 nslookup -type=A "$url_mautic" | grep -E "Address: [0-9]+\." | awk '{print $2}' | head -n1)
    
    if [[ -n "$dns_ip" && "$dns_ip" == "$ip_servidor" ]]; then
        sucesso=1
       # break
    fi
    
  #  sleep $((tentativa_atual * 2))
  sleep 1
    ((tentativa_atual++))
done

if [ $sucesso -eq 0 ]; then

    echo -e "XXX\n10\nERRO: SUBDOMÍNIO NÃO APONTA PARA O IP ($ip_servidor) \nXXX"
    sleep 3
    echo -e "XXX\n18\nERRO: DNS NÃO CONFIGURADO CORRETAMENTE \nXXX"
    sleep 3
    exit 1
fi
    echo -e "XXX\n18\nDOMÍNIO VERIFICADO COM SUCESSO \nXXX"
sleep 4
fi


####### fim de verificando dominio

echo -e "XXX\n27\nCRIANDO STACK DO MAUTIC 7 1/4 \nXXX"
sleep 1
echo -e "XXX\n29\nFAZENDO O BUILD DO STACK DO MAUTIC 7 2/4 \nXXX"
sleep 1
echo -e "XXX\n50\nFAZENDO O BUILD DO STACK DO MAUTIC 7 2/4 - CONCLUIDO \nXXX"
sleep 1




#######################################################
#
#  INSTALANDO O MAUTIC 7
#

cd

cd


#######################################################
# ETAPA DE BUILD DA IMAGEM CUSTOMIZADA (WHATS MKT)
#######################################################
echo -e "XXX\n45\nCUSTOMIZANDO - PODE DEMORAR ALGUNS MINUTOS... \nXXX"
sleep 2

# Cria um diretório temporário isolado para o processo de compilação
mkdir -p /tmp/mautic_build_$sufixo_app
cd /tmp/mautic_build_$sufixo_app

# 1. Gera o arquivo de cron estático que será injetado na imagem
cat << 'EOF' > mautic_cron
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
BASH_ENV=/tmp/cron.env

0,4,8,12,16,20,24,28,32,36,40,44,48,52,56 * * * * php /var/www/html/bin/console mautic:segments:update --batch-limit=300 > /dev/null 2>&1
1,5,9,13,17,21,25,29,33,37,41,45,49,53,57 * * * * php /var/www/html/bin/console mautic:campaigns:update > /dev/null 2>&1
2,6,10,14,18,22,26,30,34,38,42,46,50,54,58 * * * * php /var/www/html/bin/console mautic:campaigns:trigger --batch-limit=100 > /dev/null 2>&1
* * * * * php /var/www/html/bin/console messenger:consume email --time-limit=55 --memory-limit=128M --no-interaction > /dev/null 2>&1
*/5 * * * * php /var/www/html/bin/console mautic:import --limit=1000 > /dev/null 2>&1
*/3 * * * * php /var/www/html/bin/console mautic:contacts:scheduled_export > /dev/null 2>&1
*/10 * * * * php /var/www/html/bin/console mautic:email:fetch > /dev/null 2>&1
*/15 * * * * php /var/www/html/bin/console mautic:social:monitoring > /dev/null 2>&1
*/4 * * * * php /var/www/html/bin/console mautic:webhooks:process > /dev/null 2>&1
*/2 * * * * php /var/www/html/bin/console mautic:broadcasts:send > /dev/null 2>&1
10,25,40,55 * * * * php /var/www/html/bin/console mautic:messages:send > /dev/null 2>&1
* 1 * * * php /var/www/html/bin/console mautic:maintenance:cleanup --days-old=365 --no-interaction > /dev/null 2>&1
*/5 * * * * php /var/www/html/bin/console mautic:reports:scheduler > /dev/null 2>&1
EOF

echo -e "XXX\n45\nCUSTOMIZAÇÃO MAUTIC 7 - LEVA ALGUNS MINUTOS \nXXX"
sleep 3


# 2. Cria o Dockerfile que estruturará a nova imagem padrão do setup
cat << 'EOF' > Dockerfile
FROM mautic/mautic:7.1.2-20260601-apache

USER root

# Garante ferramentas essenciais para baixar e descompactar os pacotes
RUN apt-get update && apt-get install -y --no-install-recommends wget unzip && rm -rf /var/lib/apt/lists/*

# Cria toda a estrutura de pastas necessária CORRIGIDA com o docroot ANTES de baixar os arquivos
RUN mkdir -p /var/www/html/docroot/app/bundles/SmsBundle/Assets/img/ \
             /var/www/html/docroot/app/bundles/SmsBundle/Integration/Twilio/ \
             /var/www/html/docroot/app/bundles/SmsBundle/Form/Type/ \
             /var/www/html/docroot/app/bundles/SmsBundle/Resources/views/Sms/ \
             /usr/src/mautic/docroot/app/bundles/SmsBundle/Assets/img/ \
             /usr/src/mautic/docroot/app/bundles/SmsBundle/Integration/Twilio/ \
             /usr/src/mautic/docroot/app/bundles/SmsBundle/Form/Type/ \
             /usr/src/mautic/docroot/app/bundles/SmsBundle/Resources/views/Sms/

# Baixa as customizações core do WhatsMkt e injeta no SmsBundle dentro do docroot (/var/www/html/docroot)
RUN wget --tries=3 --timeout=15 -O /var/www/html/docroot/app/bundles/SmsBundle/Assets/img/Twilio.png "https://manualnegocioonline.com.br/downloads/mautic6/Twilio.png" \
    && wget --tries=3 --timeout=15 -O /var/www/html/docroot/app/bundles/SmsBundle/Integration/Twilio/TwilioTransport.php "https://manualnegocioonline.com.br/downloads/mautic6/TwilioTransport.txt" \
    && wget --tries=3 --timeout=15 -O /var/www/html/docroot/app/bundles/SmsBundle/Integration/Twilio/Configuration.php "https://manualnegocioonline.com.br/downloads/mautic6/Configuration.txt" \
    && wget --tries=3 --timeout=15 -O /var/www/html/docroot/app/bundles/SmsBundle/Form/Type/SmsType.php "https://manualnegocioonline.com.br/downloads/mautic712/SmsType.txt" \
    && wget --tries=3 --timeout=15 -O /var/www/html/docroot/app/bundles/SmsBundle/Resources/views/Sms/form.html.twig "https://manualnegocioonline.com.br/downloads/mautic712/form.html.twig.txt"

# Sincroniza os arquivos baixados com o diretório correspondente no usr/src/mautic/docroot
RUN cp /var/www/html/docroot/app/bundles/SmsBundle/Assets/img/Twilio.png /usr/src/mautic/docroot/app/bundles/SmsBundle/Assets/img/Twilio.png \
    && cp /var/www/html/docroot/app/bundles/SmsBundle/Integration/Twilio/TwilioTransport.php /usr/src/mautic/docroot/app/bundles/SmsBundle/Integration/Twilio/TwilioTransport.php \
    && cp /var/www/html/docroot/app/bundles/SmsBundle/Integration/Twilio/Configuration.php /usr/src/mautic/docroot/app/bundles/SmsBundle/Integration/Twilio/Configuration.php \
    && cp /var/www/html/docroot/app/bundles/SmsBundle/Form/Type/SmsType.php /usr/src/mautic/docroot/app/bundles/SmsBundle/Form/Type/SmsType.php \
    && cp /var/www/html/docroot/app/bundles/SmsBundle/Resources/views/Sms/form.html.twig /usr/src/mautic/docroot/app/bundles/SmsBundle/Resources/views/Sms/form.html.twig

# Baixa e extrai as traduções pt_BR nos locais corretos da estrutura
RUN wget --tries=3 --timeout=20 -O /tmp/pt_BR.zip "https://manualnegocioonline.com.br/downloads/mautic712/pt_BR.zip" \
    && unzip -o /tmp/pt_BR.zip -d /var/www/html/docroot/translations/ \
    && unzip -o /tmp/pt_BR.zip -d /usr/src/mautic/docroot/translations/ \
    && rm /tmp/pt_BR.zip

# Embuti o arquivo de cron configurado dentro do diretório padrão
COPY mautic_cron /opt/mautic/cron/mautic
RUN chmod 644 /opt/mautic/cron/mautic && chown root:root /opt/mautic/cron/mautic

# Aplica a permissão de forma cirúrgica apenas nas pastas modificadas dentro do docroot
RUN chown -R www-data:www-data \
    /var/www/html/docroot/app/bundles/SmsBundle \
    /usr/src/mautic/docroot/app/bundles/SmsBundle \
    /var/www/html/docroot/translations \
    /usr/src/mautic/docroot/translations \
    /opt/mautic/cron/mautic
EOF

# Executa o build usando a rede do host e salvando os logs
docker build --network=host -q -t mautic-mno:7.1.2 . > /tmp/mautic_build.log 2>&1

# Captura o status de execução do build
BUILD_STATUS=$?

# Retorna ao diretório padrão e limpa arquivos temporários locais
cd ~
rm -rf /tmp/mautic_build_$sufixo_app

# Validação caso ocorra algum erro inesperado
if [ $BUILD_STATUS -ne 0 ]; then
    echo -e "XXX\n46\nERRO CRÍTICO: Falha ao compilar a imagem. Verifique /tmp/mautic_build.log\nXXX"
    sleep 5
    exit 1
fi

echo -e "XXX\n50\nBUILD DA IMAGEM CONCLUÍDO COM SUCESSO! \nXXX"



sleep 3

#secret_key="base64:$(openssl rand -base64 32)"

clear
senha_mysql=$(grep -oP '(?<=MYSQL_ROOT_PASSWORD=).+' /root/mysql84.yaml)

cat > $nome_app.yaml << EOL

version: "3.7"
services:


  mautic_web$sufixo_app:
    image: mautic-mno:7.1.2

    volumes:
      - $nome_app-config:/var/www/html/config
      - $nome_app-media:/var/www/html/docroot/media
      - $nome_app-themes:/var/www/html/docroot/themes
      - $nome_app-logs:/var/www/html/var/logs
      - $nome_app-var-import:/var/www/html/var/import

    networks:
      - externa
      - interna

    environment:
      ## Dados MySQL
      - MAUTIC_DB_NAME=$nome_app
      - MAUTIC_DB_HOST=mysql84
      - MAUTIC_DB_PORT=3306
      - MAUTIC_DB_USER=root
      - MAUTIC_DB_PASSWORD=$senha_mysql

      ## Dados de acesso
      - MAUTIC_ADMIN_EMAIL=
      - MAUTIC_ADMIN_USERNAME=
      - MAUTIC_ADMIN_PASSWORD=
      - MAUTIC_URL=https://$url_mautic

      ## Configurações
      - MAUTIC_TRUSTED_PROXIES=["0.0.0.0/0"]
      - DOCKER_MAUTIC_ROLE=mautic_web
      - DOCKER_MAUTIC_WORKERS_CONSUME_EMAIL=2
      - DOCKER_MAUTIC_WORKERS_CONSUME_HIT=2
      - DOCKER_MAUTIC_WORKERS_CONSUME_FAILED=2
      - PHP_INI_VALUE_MEMORY_LIMIT=1024M
      - PHP_INI_VALUE_UPLOAD_MAX_FILESIZE=1024M
      - PHP_INI_VALUE_POST_MAX_FILESIZE=1024M
      - PHP_INI_VALUE_MAX_EXECUTION_TIME=600

    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
          - node.role == manager
      resources:
        limits:
          cpus: "2"
          memory: 2048M
EOL
# Adicionar as labels apenas se for instalação tradicional
if [ "$INSTALL_TYPE" = "TRADICIONAL" ]; then
cat >> $nome_app.yaml << EOL
      labels:
        - traefik.enable=true
        - traefik.http.routers.$nome_app.rule=Host(\`$url_mautic\`) # substitua SeuDominio.com.br pelo seu domínio
        - traefik.http.services.$nome_app.loadbalancer.server.port=80
        - traefik.http.routers.$nome_app.entrypoints=websecure
        - traefik.http.routers.$nome_app.service=$nome_app
        - traefik.http.routers.$nome_app.tls.certresolver=letsencryptresolver
        - traefik.http.services.$nome_app.loadbalancer.passHostHeader=true
EOL
fi
cat >> $nome_app.yaml << EOL

  mautic_worker$sufixo_app:
    image: mautic-mno:7.1.2

    volumes:
      - $nome_app-config:/var/www/html/config
      - $nome_app-media:/var/www/html/docroot/media
      - $nome_app-themes:/var/www/html/docroot/themes
      - $nome_app-logs:/var/www/html/var/logs
      - $nome_app-var-import:/var/www/html/var/import

    networks:
      - externa
      - interna

    environment:
      ## Dados MySQL
      - MAUTIC_DB_NAME=$nome_app
      - MAUTIC_DB_HOST=mysql84
      - MAUTIC_DB_PORT=3306
      - MAUTIC_DB_USER=root
      - MAUTIC_DB_PASSWORD=$senha_mysql

       ## Dados de acesso
      - MAUTIC_ADMIN_EMAIL=
      - MAUTIC_ADMIN_USERNAME=
      - MAUTIC_ADMIN_PASSWORD=
      - MAUTIC_URL=https://$url_mautic

      ## Configurações
      - MAUTIC_TRUSTED_PROXIES=["0.0.0.0/0"]
      - DOCKER_MAUTIC_ROLE=mautic_worker
      - DOCKER_MAUTIC_WORKERS_CONSUME_EMAIL=2
      - DOCKER_MAUTIC_WORKERS_CONSUME_HIT=2
      - DOCKER_MAUTIC_WORKERS_CONSUME_FAILED=2
      - PHP_INI_VALUE_MEMORY_LIMIT=1024M
      - PHP_INI_VALUE_UPLOAD_MAX_FILESIZE=1024M
      - PHP_INI_VALUE_POST_MAX_FILESIZE=1024M
      - PHP_INI_VALUE_MAX_EXECUTION_TIME=600

    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
          - node.role == manager
      resources:
        limits:
          cpus: "2"
          memory: 2048M


  mautic_cron$sufixo_app:
    image: mautic-mno:7.1.2

    volumes:
      - $nome_app-config:/var/www/html/config
      - $nome_app-media:/var/www/html/docroot/media
      - $nome_app-themes:/var/www/html/docroot/themes
      - $nome_app-logs:/var/www/html/var/logs
      - $nome_app-var-import:/var/www/html/var/import

    networks:
      - externa
      - interna

    environment:
      ## Dados MySQL
      - MAUTIC_DB_NAME=$nome_app
      - MAUTIC_DB_HOST=mysql84
      - MAUTIC_DB_PORT=3306
      - MAUTIC_DB_USER=root
      - MAUTIC_DB_PASSWORD=$senha_mysql

       ## Dados de acesso
      - MAUTIC_ADMIN_EMAIL=
      - MAUTIC_ADMIN_USERNAME=
      - MAUTIC_ADMIN_PASSWORD=
      - MAUTIC_URL=https://$url_mautic

      ## Configurações
      - MAUTIC_TRUSTED_PROXIES=["0.0.0.0/0"]
      - DOCKER_MAUTIC_ROLE=mautic_cron
      - DOCKER_MAUTIC_WORKERS_CONSUME_EMAIL=2
      - DOCKER_MAUTIC_WORKERS_CONSUME_HIT=2
      - DOCKER_MAUTIC_WORKERS_CONSUME_FAILED=2
      - PHP_INI_VALUE_MEMORY_LIMIT=1024M
      - PHP_INI_VALUE_UPLOAD_MAX_FILESIZE=1024M
      - PHP_INI_VALUE_POST_MAX_FILESIZE=1024M
      - PHP_INI_VALUE_MAX_EXECUTION_TIME=600

    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
          - node.role == manager
      resources:
        limits:
          cpus: "2"
          memory: 2048M

volumes:
  $nome_app-config:
    external: true
    name: $nome_app-config
  $nome_app-media:
    external: true
    name: $nome_app-media
  $nome_app-themes:
    external: true
    name: $nome_app-themes
  $nome_app-logs:
    external: true
    name: $nome_app-logs
  $nome_app-var-import:
    external: true
    name: $nome_app-var-import

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
    echo -e "XXX\n91\nCRIANDO STACK NO PORTAINER 3/4  \nXXX"
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


echo -e "XXX\n93\nREALIZANDO CUSTOMIZAÇÕES NO MAUTIC 7  \nXXX"

sleep 8

echo -e "XXX\n94\nREALIZANDO CUSTOMIZAÇÕES NO MAUTIC 7  \nXXX"

sleep 3


#######################################################

# Aguardar a stack subir completamente
echo -e "XXX\n95\nCUSTOMIZAÇÕES NO MAUTIC 7 - LEVA ATÉ 15 MIN  \nXXX"

max_wait_time=800  #ajuste do tempo máximo de espera

wait_interval=60

elapsed_time=0

while [ $elapsed_time -lt $max_wait_time ]; do
        CONTAINER_ID=$(docker ps -qf name=mautic_web$sufixo_app)
        if [ -n "$CONTAINER_ID" ]; then
                break
        fi
        sleep $wait_interval
        elapsed_time=$((elapsed_time + wait_interval))
done

if [ -z "$CONTAINER_ID" ]; then
echo -e "XXX\n94\nERRO: CONTAINER DO MAUTIC NÃO ENCONTRADO  \nXXX"
        exit 1
fi

sleep 15

################################################################
#
# CUSTOMIZAÇÃO AUTOMÁTICA DOS ARQUIVOS
#



# Criar o arquivo substituindo variáveis do Bash, mas protegendo o PHP
# Note que o EOF está sem aspas, e o $parameters tem uma \ na frente
cat << EOF > /tmp/local.php
<?php
\$parameters = array(
        'db_driver' => 'pdo_mysql',
        'db_host' => 'mysql84',
        'db_port' => '3306',
        'db_name' => '$nome_app',
        'db_user' => 'root',
        'db_password' => '$senha_mysql',
        'db_table_prefix' => null,
        'db_backup_tables' => 0,
        'db_backup_prefix' => 'bak_',
        'db_host_ro' => null,
        'db_server_version' => null,
        'secret_key' => 'eb6ed6d0babe0a51ec3057731e985fd039bfe72117dba89e5bf126e03d202a1e',
        'site_url' => 'http://$url_mautic',
        'api_enabled' => 0,
        'api_enable_basic_auth' => false,
        'api_oauth2_access_token_lifetime' => 60,
        'api_oauth2_refresh_token_lifetime' => 14,
        'api_batch_max_limit' => 200,
        'upload_dir' => '/var/www/html/docroot/media/files',
        'max_size' => '6',
        'allowed_extensions' => array(
                '0' => 'csv',
                '1' => 'doc',
                '2' => 'docx',
                '3' => 'epub',
                '4' => 'gif',
                '5' => 'jpg',
                '6' => 'jpeg',
                '7' => 'mpg',
                '8' => 'mpeg',
                '9' => 'mp3',
                '10' => 'odt',
                '11' => 'odp',
                '12' => 'ods',
                '13' => 'pdf',
                '14' => 'png',
                '15' => 'ppt',
                '16' => 'pptx',
                '17' => 'tif',
                '18' => 'tiff',
                '19' => 'txt',
                '20' => 'xls',
                '21' => 'xlsx',
                '22' => 'wav'
        ),
     'streamed_extensions' => array(
                '0' => 'gif',
                '1' => 'jpg',
                '2' => 'jpeg',
                '3' => 'mpg',
                '4' => 'mpeg',
                '5' => 'mp3',
                '6' => 'pdf',
                '7' => 'png',
                '8' => 'wav'
        ),
        'allowed_mimetypes' => array(
                'csv' => 'text/csv',
                'doc' => 'application/msword',
                'docx' => 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
                'epub' => 'application/epub+zip',
                'gif' => 'image/gif',
                'jpg' => 'image/jpeg',
                'jpeg' => 'image/jpeg',
                'mpg' => 'video/mpeg',
                'mpeg' => 'video/mpeg',
                'mp3' => 'audio/mpeg',
                'odt' => 'application/vnd.oasis.opendocument.text',
                'odp' => 'application/vnd.oasis.opendocument.presentation',
                'ods' => 'application/vnd.oasis.opendocument.spreadsheet',
                'pdf' => 'application/pdf',
                'png' => 'image/png',
                'ppt' => 'application/vnd.ms-powerpoint',
                'pptx' => 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
                'tif' => 'image/tiff',
                'tiff' => 'image/tiff',
                'txt' => 'text/plain',
                'xls' => 'application/vnd.ms-excel',
                'xlsx' => 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
                'wav' => 'audio/wav'
        ),
        'campaign_time_wait_on_event_false' => 'PT1H',
        'campaign_use_summary' => 0,
        'campaign_by_range' => 0,
        'delete_campaign_event_log_in_background' => false,
        'campaign_email_stats_enabled' => 1,
        'peak_interaction_timer_cache_timeout' => 43800,
        'peak_interaction_timer_best_default_hour_start' => 9,
        'peak_interaction_timer_best_default_hour_end' => 12,
        'peak_interaction_timer_best_default_days' => array(
                '0' => '1',
                '1' => '2',
                '2' => '4'
        ),
        'peak_interaction_timer_fetch_interactions_from' => '-60 days',
        'peak_interaction_timer_fetch_limit' => 50,
        'peak_interaction_timer_max_optimal_days' => 3,
        'import_campaigns_dir' => '/var/www/html/var/import',
        'campaign_republish_behavior' => 'count_all_time',
        'campaign_contact_count_cache_ttl' => 43200,
        'webroot' => null,
        '404_page' => null,
        'cache_path' => '/var/www/html/var/cache',
        'log_path' => '/var/www/html/var/logs',
        'max_log_files' => 7,
        'log_file_name' => 'mautic_prod.php',
        'image_path' => 'media/images',
        'media_path' => 'media',
        'tmp_path' => '/var/www/html/var/tmp',
        'brand_name' => 'Your Brand (configurable)',
        'primary_brand_color' => '000000',
        'rounded_corners' => '0',
        'locale' => 'pt_BR',
        'dev_hosts' => array(

        ),
        'trusted_hosts' => array(

        ),
        'trusted_proxies' => array(
                '0' => '0.0.0.0/0'
        ),
        'validate_remote_domains' => false,
        'allowed_remote_domains' => array(

        ),
        'rememberme_key' => 'eb6ed6d0babe0a51ec3057731e985fd039bfe72117dba89e5bf126e03d202a1e',
        'rememberme_lifetime' => 7776000,
        'rememberme_path' => '/',
        'default_pagelimit' => 30,
        'default_timezone' => 'America/Sao_Paulo',
        'date_format_full' => 'F j, Y g:i a T',
        'date_format_short' => 'D, M d',
        'date_format_dateonly' => 'F j, Y',
        'date_format_timeonly' => 'g:i a',
        'ip_lookup_service' => 'maxmind_download',
        'ip_lookup_auth' => null,
        'ip_lookup_config' => array(

        ),
        'ip_lookup_create_organization' => 0,
        'update_stability' => 'stable',
        'cookie_path' => '/',
        'cookie_secure' => true,
        'cookie_httponly' => false,
        'do_not_track_ips' => array(

        ),

      'do_not_track_internal_ips' => array(

        ),
        'track_private_ip_ranges' => false,
        'link_shortener_url' => null,
        'shortener_email_enable' => null,
        'shortener_sms_enable' => null,
        'cached_data_timeout' => 10,
        'batch_sleep_time' => 1,
        'batch_campaign_sleep_time' => false,
        'transliterate_page_title' => 0,
        'cors_restrict_domains' => 1,
        'cors_valid_domains' => array(

        ),
        'headers_sts' => 0,
        'headers_sts_expire_time' => null,
        'headers_sts_subdomains' => null,
        'headers_sts_preload' => null,
        'max_entity_lock_time' => 0,
        'default_daterange_filter' => '-1 month',
        'debug' => false,
        'anonymize_ip_address_in_background' => false,
        'motd_url' => 'https://mautic.github.io/motd/motd.json',
        'motd_cache_path' => '/var/www/html/var/cache/motd.json',
        'motd_cache_ttl' => 3600,
        'translations_list_url' => 'https://language-packs.mautic.com/manifest.json',
        'translations_fetch_url' => 'https://language-packs.mautic.com/',
        'stats_update_url' => 'https://updates.mautic.org/stats/send',
        'install_source' => 'Mautic',
        'system_update_url' => 'https://api.github.com/repos/mautic/mautic/releases',
        'editor_fonts' => array(
                '0' => array(
                        'name' => 'Arial',
                        'font' => 'Arial, Helvetica Neue, Helvetica, sans-serif'
                ),
                '1' => array(
                        'name' => 'Bitter',
                        'font' => 'Bitter, Georgia, Times, Times New Roman, serif',
                        'url' => 'https://fonts.googleapis.com/css?family=Bitter'
                ),
                '2' => array(
                        'name' => 'Courier New',
                        'font' => 'Courier New, Courier, Lucida Sans Typewriter, Lucida Typewriter, monospace'
                ),
                '3' => array(
                        'name' => 'Droid Serif',
                        'font' => 'Droid Serif, Georgia, Times, Times New Roman, serif',
                        'url' => 'https://fonts.googleapis.com/css?family=Droid+Serif'
                ),
                '4' => array(
                        'name' => 'Georgia',
                        'font' => 'Georgia, Times, Times New Roman, serif'
                ),
                '5' => array(
                        'name' => 'Helvetica',
                        'font' => 'Helvetica Neue, Helvetica, Arial, sans-serif'
                ),
                '6' => array(
                        'name' => 'Lato',
                        'font' => 'Lato, Tahoma, Verdana, Segoe, sans-serif',
                        'url' => 'https://fonts.googleapis.com/css?family=Lato'
                ),
                '7' => array(
                        'name' => 'Lucida Sans Unicode',
                        'font' => 'Lucida Sans Unicode, Lucida Grande, Lucida Sans, Geneva, Verdana, sans-serif'
                ),
                '8' => array(
                        'name' => 'Montserrat',
                        'font' => 'Montserrat, Trebuchet MS, Lucida Grande, Lucida Sans Unicode, Lucida Sans, Tahoma, sans-serif',
                        'url' => 'https://fonts.googleapis.com/css?family=Montserrat'
                ),
                '9' => array(
                        'name' => 'Open Sans',
                        'font' => 'Open Sans, Helvetica Neue, Helvetica, Arial, sans-serif',
                        'url' => 'https://fonts.googleapis.com/css?family=Open+Sans'
                ),
                '10' => array(
                        'name' => 'Roboto',
                        'font' => 'Roboto, Tahoma, Verdana, Segoe, sans-serif',
                        'url' => 'https://fonts.googleapis.com/css?family=Roboto'
                ),
                '11' => array(
                        'name' => 'Source Sans Pro',
                        'font' => 'Source Sans Pro, Tahoma, Verdana, Segoe, sans-serif',
                        'url' => 'https://fonts.googleapis.com/css?family=Source+Sans+Pro'
                ),
                '12' => array(
                        'name' => 'Tahoma',
                        'font' => 'Tahoma, Geneva, Segoe, sans-serif'
                ),
                '13' => array(
                        'name' => 'Times New Roman',
                        'font' => 'TimesNewRoman, Times New Roman, Times, Beskerville, Georgia, serif'
                ),
                '14' => array(
                        'name' => 'Trebuchet MS',
                        'font' => 'Trebuchet MS, Lucida Grande, Lucida Sans Unicode, Lucida Sans, Tahoma, sans-serif'
                ),
                '15' => array(
                        'name' => 'Ubuntu',
                        'font' => 'Ubuntu, Tahoma, Verdana, Segoe, sans-serif',
                        'url' => 'https://fonts.googleapis.com/css?family=Ubuntu'
                ),
                '16' => array(
                        'name' => 'Verdana',
                        'font' => 'Verdana, Geneva, sans-serif'
                ),
                '17' => array(
                        'name' => 'ヒラギノ角ゴ Pro W3',
                        'font' => 'ヒラギノ角ゴ Pro W3, Hiragino Kaku Gothic Pro,Osaka, メイリオ, Meiryo, ＭＳ Ｐゴシック, MS PGothic, sans-serif'
                ),
                '18' => array(
                        'name' => 'メイリオ',
                        'font' => 'メイリオ, Meiryo, ＭＳ Ｐゴシック, MS PGothic, ヒラギノ角ゴ Pro W3, Hiragino Kaku Gothic Pro,Osaka, sans-serif'
                )
        ),
        'composer_updates' => 0,
        'redis_primary_only' => false,
        'shortener_service' => null,
        'gdpr_user_purge_threshold' => 1095,
        'last_shown_tab' => null,
        'theme' => 'blank',
        'theme_import_allowed_extensions' => array(
                '0' => 'json',
                '1' => 'twig',
                '2' => 'css',
                '3' => 'js',
                '4' => 'htm',
                '5' => 'html',
                '6' => 'txt',
                '7' => 'jpg',
                '8' => 'jpeg',
                '9' => 'png',
                '10' => 'gif'
        ),
        'accent' => '06',
        'mailer_from_name' => 'Mautic',
        'mailer_from_email' => 'email@yoursite.com',
        'mailer_reply_to_email' => null,
        'mailer_return_path' => null,
        'mailer_address_length_limit' => 320,
        'mailer_append_tracking_pixel' => 1,
        'mailer_convert_embed_images' => 0,
        'mailer_custom_headers' => array(

        ),
        'mailer_dsn' => 'smtp://localhost:1025',
        'unsubscribe_text' => '<a href="|URL|">Unsubscribe</a> to no longer receive emails from us.',
        'webview_text' => '<a href="|URL|">Having trouble reading this email? Click here.</a>',
        'unsubscribe_message' => 'We are sorry to see you go! |EMAIL| will no longer receive emails from us. If this was by mistake, <a href="|URL|">click here to re-subscribe</a>.',
        'resubscribe_message' => '|EMAIL| has been re-subscribed. If this was by mistake, <a href="|URL|">click here to unsubscribe</a>.',
        'monitored_email' => array(
                'general' => array(
                        'address' => '',
                        'host' => '',
                        'port' => '993',
                        'encryption' => '/ssl',
                        'user' => '',
                        'password' => '',
                        'use_attachments' => ''
                ),
                'EmailBundle_bounces' => array(
                        'address' => '',
                        'host' => '',
                        'port' => '993',
                        'encryption' => '/ssl',
                        'user' => '',
                        'password' => '',
                        'override_settings' => '0',
                        'folder' => ''
                ),
                'EmailBundle_unsubscribes' => array(
                        'address' => '',
                        'host' => '',
                        'port' => '993',
                        'encryption' => '/ssl',
                        'user' => '',
                        'password' => '',
                        'override_settings' => '0',
                        'folder' => ''
                ),
                'EmailBundle_replies' => array(
                        'address' => '',
                        'host' => '',
                        'port' => '993',
                        'encryption' => '/ssl',
                        'user' => '',
                        'password' => '',
                        'override_settings' => '0',
                        'folder' => ''
                )
        ),
        'mailer_is_owner' => 0,
        'default_signature_text' => 'Best regards, |FROM_NAME|',
        'email_frequency_number' => 0,
        'email_frequency_time' => 'DAY',
        'show_contact_preferences' => 0,
        'show_contact_frequency' => 0,
        'show_contact_pause_dates' => 0,
        'show_contact_preferred_channels' => 0,
        'show_contact_categories' => 0,
        'show_contact_segments' => 0,
        'disable_trackable_urls' => 0,
        'email_draft_enabled' => 0,
        'theme_email_default' => 'blank',
        'mailer_memory_msg_limit' => 100,
        'minify_email_html' => 0,
        'bot_helper_bot_ratio_threshold' => 0.6,
        'bot_helper_time_email_threshold' => 2,
        'bot_helper_blocked_user_agents' => array(
                '0' => 'Googlebot/2.1 (+http://www.google.com/bot.html)',
                '1' => 'LinkedInBot/1.0 (compatible; Mozilla/5.0; Jakarta Commons-HttpClient/3.1 +http://www.linkedin.com)'
        ),
        'bot_helper_blocked_ip_addresses' => array(

        ),
        'smime_signing_enabled' => false,
        'smime_certificates_path' => '/var/www/html/var/smime_certificates',
        'form_upload_dir' => '/var/www/html/docroot/media/files/form',
        'blacklisted_extensions' => array(
                '0' => 'php',
                '1' => 'sh'
        ),
        'do_not_submit_emails' => array(

        ),

        'form_results_data_sources' => 0,
        'successful_submit_action' => 'top',
        'parallel_import_limit' => 1,
        'background_import_if_more_rows_than' => 0,
        'contact_api_count_cache_ttl' => 5,
        'delete_segment_in_background' => false,
        'segment_api_count_cache_ttl' => 43200,
        'contact_columns' => array(
                '0' => 'name',
                '1' => 'email',
                '2' => 'location',
                '3' => 'stage',
                '4' => 'points',
                '5' => 'last_active',
                '6' => 'id'
        ),
        'create_custom_field_in_background' => false,
        'contact_unique_identifiers_operator' => 'OR',
        'segment_rebuild_time_warning' => 30,
        'segment_build_time_warning' => 30,
        'contact_export_in_background' => 1,
        'contact_export_dir' => '/var/www/html/docroot/media/files/temp',
        'contact_export_batch_size' => 20000,
        'contact_export_limit' => 0,
        'contact_allow_multiple_companies' => 1,
        'import_leads_dir' => '/var/www/html/var/import',
        'update_segment_contact_count_in_background' => false,
        'clear_export_files_after_days' => 7,
        'company_unique_identifiers_operator' => 'OR',
        'messenger_dsn_email' => 'sync://',
        'messenger_dsn_hit' => 'sync://',
        'messenger_retry_strategy_max_retries' => 3,
        'messenger_retry_strategy_delay' => 1000,
        'messenger_retry_strategy_multiplier' => 2,
        'messenger_retry_strategy_max_delay' => 0,
        'notification_enabled' => false,
        'notification_landing_page_enabled' => true,
        'notification_tracking_page_enabled' => false,
        'notification_app_id' => null,
        'notification_rest_api_key' => null,
        'notification_safari_web_id' => null,
        'gcm_sender_id' => '482941778795',
        'notification_subdomain_name' => null,
        'welcomenotification_enabled' => true,
        'campaign_send_notification_to_author' => 1,
        'campaign_notification_email_addresses' => null,
        'webhook_send_notification_to_author' => 1,
        'webhook_notification_email_addresses' => null,
        'cat_in_page_url' => 0,
        'google_analytics' => null,
        'anonymize_ip' => 0,
        'track_contact_by_ip' => 0,
        'facebook_pixel_id' => null,
        'facebook_pixel_trackingpage_enabled' => 0,
        'facebook_pixel_landingpage_enabled' => 0,
        'google_analytics_id' => null,
        'google_analytics_trackingpage_enabled' => 0,
        'google_analytics_landingpage_enabled' => 0,
        'google_analytics_anonymize_ip' => 0,
        'do_not_track_404_anonymous' => 0,
        'append_segment_id_tracking_url' => 0,
        'report_temp_dir' => '/var/www/html/docroot/media/files/temp',
        'report_export_batch_size' => 1000,
        'report_export_max_filesize_in_bytes' => 5000000,
        'csv_always_enclose' => 0,
        'sms_enabled' => false,
        'sms_username' => null,
        'sms_password' => null,
        'sms_messaging_service_sid' => null,
        'sms_frequency_number' => 0,
        'sms_frequency_time' => 'DAY',
        'sms_transport' => 'mautic.sms.twilio.transport',
        'sms_disable_trackable_urls' => 0,
        'saml_idp_entity_id' => 'http://$url_mautic',
        'saml_idp_email_attribute' => 'EmailAddress',
        'saml_idp_username_attribute' => null,
        'saml_idp_firstname_attribute' => 'FirstName',
        'saml_idp_lastname_attribute' => 'LastName',
        'saml_idp_default_role' => null,
        'webhook_limit' => 10,
        'webhook_time_limit' => 600,
        'webhook_log_max' => 1000,
        'webhook_health_check_time' => 300,
        'webhook_retry_delay' => 3600,
        'clean_webhook_logs_in_background' => false,
        'webhook_disable_limit' => 100,
        'webhook_timeout' => 15,
        'queue_mode' => 'immediate_process',
        'events_orderby_dir' => 'ASC',
        'webhook_email_details' => 1,
        'disable_auto_unpublish' => false,
        'first_webhook_failure_notification_time' => 3600,
        'webhook_failure_notification_interval' => 86400,
        'webhook_allowed_private_addresses' => array(

        ),
);
EOF

echo -e "XXX\n97\nSOBRESCREVENDO O local.php  \nXXX"
sleep 2

# 2. Copiar e sobrescrever direto no container principal
docker cp /tmp/local.php $CONTAINER_ID:/var/www/html/config/local.php >/dev/null 2>&1

# 3. O docker cp copia como usuário "root". Precisamos devolver a posse para o Mautic (www-data)
docker exec $CONTAINER_ID chown www-data:www-data /var/www/html/config/local.php

# 4. Verificar se a cópia funcionou
if docker exec $CONTAINER_ID test -f /var/www/html/config/local.php; then
    echo -e "XXX\n98\nlocal.php ATUALIZADO COM SUCESSO  \nXXX"
    sleep 4
else
    echo -e "XXX\n98\nERRO AO ATUALIZAR local.php  \nXXX"
    sleep 4
fi

# Limpar arquivo temporário do host
rm /tmp/local.php >/dev/null 2>&1






# Ajustar permissões
echo -e "XXX\n99\nFINALIZANDO BUILD DO MAUTIC  \nXXX"
docker exec temp_container chown -R www-data:www-data /var/www/html >/dev/null 2>&1
docker exec temp_container chmod -R g+rw /var/www/html >/dev/null 2>&1


# Limpar cache para forçar a leitura do novo local.php
docker exec -i $CONTAINER_ID rm -rf /var/www/html/var/cache/* >/dev/null 2>&1


# Remover container temporário
echo -e "XXX\n100\nFINALIZANDO - AGUARDE  \nXXX"

cd
cd
BD_MAUTIC7_SIMPLES="https://manualnegocioonline.com.br/downloads/mautic712/backupsimples.zip"
wget $BD_MAUTIC7_SIMPLES >/dev/null 2>&1
unzip backupsimples.zip  >/dev/null 2>&1

mysql_container=$(docker ps -qf name=mysql84)
docker exec -i $mysql_container mysql -p$senha_mysql -u root $nome_app < backupsimples.sql >/dev/null 2>&1

sleep 1


docker exec -i $CONTAINER_ID chown -R www-data:www-data /var/www/html/var/import
docker exec -i $CONTAINER_ID chmod -R 755 /var/www/html/var/import



rm backupsimples.sql 
rm backupsimples.zip 



docker exec -i $CONTAINER_ID rm -r /var/www/html/var/cache/ >/dev/null 2>&1
################################################################


docker service ls --filter name=$nome_app -q | xargs -I {} docker service update --force {} >/dev/null 2>&1

}|whiptail --title "MAUTIC 7 - PROGRESSO DA INSTALAÇÃO" --gauge "Aguarde a instalação dos ítens necessários" 6 60 0

# FIM DE INSTALANDO O MAUTIC 7
#

# VERIFICAÇÃO FINAL
#
senha_mysql=$(grep -oP '(?<=MYSQL_ROOT_PASSWORD=).+' /root/mysql84.yaml)
# Verificação conforme tipo de instalação
if [ "$INSTALL_TYPE" = "TRADICIONAL" ]; then
    ip_servidor=$(curl -s --max-time 10 ipinfo.io/ip)
    dns_ip=$(timeout 10 nslookup $url_mautic | grep "Address" | tail -n1 | awk '{print $2}' 2>/dev/null)

    if [[ "$dns_ip" != "$ip_servidor" ]]; then
        whiptail --title "Mensagem" --msgbox "Não foi possivel acessar o dominio do MAUTIC 7 com WhatsApp e SMS Marketing ($url_mautic). A instalação foi cancelada. Por favor, verifique se os apontamentos DNS estão corretos e propagados!. Depois, instale novamente. Pressione ENTER para voltar ao Menu Principal" 20 78
    else
        sleep 2
         CONTAINER_ID=$(docker ps -qf name=mautic_web$sufixo_app)
        docker exec -it $CONTAINER_ID rm -r /var/www/html/var/cache/ >/dev/null 2>&1
        whiptail --title "Mensagem" --msgbox "MAUTIC 7 com WhatsApp e SMS Marketing instalado com sucesso!\n\nAcesse: https://$url_mautic\nConfiguração Cloudflare Tunnel concluída com rotas e DNS.\nPressione ENTER para voltar ao Menu Principal\nATENÇÃO: Foram criados um usuário e senha provisórios para você realizar o primeiro acesso.\nOs dados estão abaixo. Assim que acessar pela primeira vez crie um usuário e senha seguros.\nDADOS DE ACESSO:\nUsuario: admin123@example.com\nSenha: admin@1234567" 20 78
    fi
else
    # Para Cloudflare Tunnel, verificação mais simples
    if nslookup "$url_mautic" >/dev/null 2>&1; then
         sleep 2
         CONTAINER_ID=$(docker ps -qf name=mautic_web$sufixo_app)
        docker exec -it $CONTAINER_ID rm -r /var/www/html/var/cache/ >/dev/null 2>&1
    whiptail --title "Mensagem" --msgbox "MAUTIC 7 com WhatsApp e SMS Marketing instalado com sucesso!\n\nAcesse: https://$url_mautic\nPressione ENTER para voltar ao Menu Principal\nATENÇÃO: Foram criados um usuário e senha provisórios para você realizar o primeiro acesso.\nOs dados estão abaixo. Assim que acessar pela primeira vez crie um usuário e senha seguros.\nDADOS DE ACESSO:\nUsuario: admin123@example.com\nSenha: admin@1234567" 20 78
   
    else

        whiptail --title "Mensagem" --msgbox "AVISO: O domínio do MAUTIC 7 com WhatsApp e SMS Marketing ($url_mautic) não está resolvendo.\nVerifique a configuração do Cloudflare Tunnel.\n\nA instalação foi concluída, mas o acesso pode não funcionar até que o DNS esteja configurado corretamente.\n\nPressione ENTER para voltar ao Menu Principal" 20 78
    fi
fi

exit 0



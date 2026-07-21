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
                whiptail --title "MAUTIC 7 PADRÃO: AUTOMAÇÃO DE MARKETING" --msgbox "$msg" --fb 10 70;
        }

  while true; do
CHOICE=$(
whiptail --title "MAUTIC 7 PADRÃO: AUTOMAÇÃO DE MARKETING" --menu "Aperte ENTER para iniciar a instalação do MAUTIC 7 PADRÃO ou selecione SAIR (Utilize setas e Enter)\n\nTIPO DE INSTALAÇÃO DETECTADO: $INSTALL_TYPE\n\nINSTRUÇÕES:\nAntes de prosseguir, verifique os registros DNS conforme seu tipo de instalação:" 20 70 2 \
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
sleep 30
# Aguardar container MySQL ficar disponível
max_wait_time=800  # 2 minutos máximo
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
    echo -e "XXX\n23\nERRO: Container MySQL não encontrado\nXXX"
    sleep 5
    exit 1
fi

echo -e "XXX\n24\nCONTAINER MYSQL ENCONTRADO\nXXX"

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
echo -e "XXX\n5\nVERIFICANDO CONFIGURAÇÃO... \nXXX"

if [ "$INSTALL_TYPE" = "TRADICIONAL" ] && [ "$criar_dns" = "0" ]; then
    # CONFIGURAÇÃO TRADICIONAL COM DNS AUTOMÁTICO
    echo -e "XXX\n10\nCONFIGURANDO DNS AUTOMÁTICO (TRADICIONAL)... \nXXX"
    
    DOMINIO_PRINCIPAL=$(echo "$url_mautic" | cut -d'.' -f2-)
    SUBDOMINIO=${url_mautic%%.$DOMINIO_PRINCIPAL}

    # Verificar e remover registros existentes
    echo -e "XXX\n15\nVERIFICANDO REGISTROS EXISTENTES... \nXXX"
    EXISTING_RECORDS=$(curl -s -X GET \
        "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records?name=${url_mautic}" \
        -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
        -H "Content-Type: application/json")

    COUNT=$(echo "$EXISTING_RECORDS" | jq '.result | length')
    if [[ "$COUNT" -gt 0 ]]; then
        echo -e "XXX\n20\nREMOVENDO REGISTROS ANTIGOS... \nXXX"
        echo "$EXISTING_RECORDS" | jq -r '.result[].id' | while read -r REC_ID; do
            [[ -z "$REC_ID" ]] && continue
            curl -s -X DELETE \
                "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records/${REC_ID}" \
                -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
                -H "Content-Type: application/json" >/dev/null 2>&1
        done
    fi

    # Criar registro CNAME
    echo -e "XXX\n25\nCRIANDO REGISTRO CNAME... \nXXX"
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
    echo -e "XXX\n10\nCONFIGURANDO CLOUDFLARE TUNNEL (DNS + ROTAS)... \nXXX"
    
    DOMINIO_PRINCIPAL=$(echo "$url_mautic" | cut -d'.' -f2-)
    SUBDOMINIO=${url_mautic%%.$DOMINIO_PRINCIPAL}

    # 1. PRIMEIRO CONFIGURAR O DNS
    echo -e "XXX\n15\nCONFIGURANDO REGISTRO DNS... \nXXX"
    
    # Verificar e remover registros existentes
    EXISTING_RECORDS=$(curl -s -X GET \
        "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records?name=${url_mautic}" \
        -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
        -H "Content-Type: application/json")

    COUNT=$(echo "$EXISTING_RECORDS" | jq '.result | length')
    if [[ "$COUNT" -gt 0 ]]; then
        echo -e "XXX\n20\nREMOVENDO REGISTROS DNS ANTIGOS... \nXXX"
        echo "$EXISTING_RECORDS" | jq -r '.result[].id' | while read -r REC_ID; do
            [[ -z "$REC_ID" ]] && continue
            curl -s -X DELETE \
                "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records/${REC_ID}" \
                -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
                -H "Content-Type: application/json" >/dev/null 2>&1
        done
    fi

    # Criar registro CNAME para o tunnel
    echo -e "XXX\n25\nCRIANDO REGISTRO CNAME PARA TUNNEL... \nXXX"
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
      
      # Se o novo host já existe, não adicionar duplicata; senão adicionar nova rota
      | ($clean | map(select(.hostname != $host))) as $filtered
      | ($filtered + [ { hostname: $host, service: $service, originRequest: { noTlsVerify: true, httpHostHeader: $host } } ]) as $merged
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

#secret_key="base64:$(openssl rand -base64 32)"

clear
senha_mysql=$(grep -oP '(?<=MYSQL_ROOT_PASSWORD=).+' /root/mysql84.yaml)

cat > $nome_app.yaml << EOL

version: "3.7"
services:


  mautic_web$sufixo_app:
    image: mautic/mautic:7.1.2-20260601-apache

    volumes:
      - $nome_app-config:/var/www/html/config
      - $nome_app-docroot:/var/www/html/docroot
      - $nome_app-media:/var/www/html/docroot/media
      - $nome_app-logs:/var/www/html/var/logs
      - $nome_app-cron:/opt/mautic/cron
      - $nome_app-var-import:/var/www/html/var/import  # <-- Adicionar esta linha

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
    image: mautic/mautic:7.1.2-20260601-apache

    volumes:
      - $nome_app-config:/var/www/html/config
      - $nome_app-docroot:/var/www/html/docroot
      - $nome_app-media:/var/www/html/docroot/media
      - $nome_app-logs:/var/www/html/var/logs
      - $nome_app-cron:/opt/mautic/cron
      - $nome_app-var-import:/var/www/html/var/import  # <-- Adicionar esta linha

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
    image: mautic/mautic:7.1.2-20260601-apache

    volumes:
      - $nome_app-config:/var/www/html/config
      - $nome_app-docroot:/var/www/html/docroot
      - $nome_app-media:/var/www/html/docroot/media
      - $nome_app-logs:/var/www/html/var/logs
      - $nome_app-cron:/opt/mautic/cron
      - $nome_app-var-import:/var/www/html/var/import  # <-- Adicionar esta linha

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
  $nome_app-docroot:
    external: true
    name: $nome_app-docroot
  $nome_app-media:
    external: true
    name: $nome_app-media
  $nome_app-logs:
    external: true
    name: $nome_app-logs
  $nome_app-cron:
    external: true
    name: $nome_app-cron
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

sleep 2

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


echo -e "XXX\n95\nINICIANDO CUSTOMIZAÇÃO AUTOMÁTICA  \nXXX"


docker run -d --rm --name temp_container -v $nome_app-docroot:/var/www/html busybox sleep 3600 >/dev/null 2>&1

# Atualizar o arquivo de cron
echo -e "XXX\n98\nATUALIZANDO CRON JOB  \nXXX"
sleep 2
# Conteúdo do novo cron

# Criar container temporário ESPECÍFICO para o volume do cron
docker logout >/dev/null 2>&1
docker run -d --rm --name cron_container -v $nome_app-cron:/opt/mautic/cron busybox sleep 3600 >/dev/null 2>&1


# 1. Usar cat com EOF para garantir a quebra de linha no final (Exigência do Cron)
cat << 'EOF' > /tmp/mautic_cron
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
BASH_ENV=/tmp/cron.env

# Core (Excelente offset mantido)
0,4,8,12,16,20,24,28,32,36,40,44,48,52,56 * * * * php /var/www/html/bin/console mautic:segments:update --batch-limit=300 > /dev/null 2>&1
1,5,9,13,17,21,25,29,33,37,41,45,49,53,57 * * * * php /var/www/html/bin/console mautic:campaigns:update > /dev/null 2>&1
2,6,10,14,18,22,26,30,34,38,42,46,50,54,58 * * * * php /var/www/html/bin/console mautic:campaigns:trigger --batch-limit=100 > /dev/null 2>&1

# O Worker  (Com limite de tempo e memória)
* * * * * php /var/www/html/bin/console messenger:consume email --time-limit=55 --memory-limit=128M --no-interaction > /dev/null 2>&1

# Outras tarefas espaçadas adequadamente
*/5 * * * * php /var/www/html/bin/console mautic:import --limit=1000 > /dev/null 2>&1
*/3 * * * * php /var/www/html/bin/console mautic:contacts:scheduled_export > /dev/null 2>&1
*/10 * * * * php /var/www/html/bin/console mautic:email:fetch > /dev/null 2>&1
*/15 * * * * php /var/www/html/bin/console mautic:social:monitoring > /dev/null 2>&1
*/4 * * * * php /var/www/html/bin/console mautic:webhooks:process > /dev/null 2>&1
*/2 * * * * php /var/www/html/bin/console mautic:broadcasts:send > /dev/null 2>&1
10,25,40,55 * * * * php /var/www/html/bin/console mautic:messages:send > /dev/null 2>&1
* 1 * * * php /var/www/html/bin/console mautic:maintenance:cleanup --days-old=365 --no-interaction > /dev/null 2>&1
*/5 * * * * php /var/www/html/bin/console mautic:reports:scheduler > /dev/null 2>&1

#0 * * * * php /var/www/html/bin/console mautic:iplookup:download > /dev/null 2>&1
# MaxMind CCPA compliance - at 03:02 on sunday, at 03:12 on sunday
#2 3 * * 0 php /var/www/html/bin/console mautic:donotsell:download > /dev/null 2>&1
#12 3 * * 0 php /var/www/html/bin/console mautic:max-mind:purge > /dev/null 2>&1

# Mautic Integrations - every 13 min - READ DOCUMENTATION BEFORE ENABLING
#*/13 * * * 0 php /var/www/html/bin/console mautic:integration:fetchleads > /dev/null 2>&1
#*/13 * * * 0 php /var/www/html/bin/console mautic:integration:pushactivity > /dev/null 2>&1

EOF


# Copiar para o container CRON
docker cp /tmp/mautic_cron cron_container:/opt/mautic/cron/mautic >/dev/null 2>&1
rm /tmp/mautic_cron >/dev/null 2>&1


# Verificar se a cópia foi bem sucedida
if docker exec cron_container test -f /opt/mautic/cron/mautic; then
    echo -e "XXX\n98\nCRON ATUALIZADO COM SUCESSO  \nXXX"
    sleep 4

# 2. Aplicar permissões específicas (CORRIGIDO PARA 644)
    docker exec cron_container chown root:root /opt/mautic/cron/mautic
    docker exec cron_container chmod 644 /opt/mautic/cron/mautic
else
    echo -e "XXX\n98\nERRO AO ATUALIZAR CRON  \nXXX"
    sleep 4
fi

# Remover container do cron
docker stop cron_container >/dev/null 2>&1


# Ajustar permissões
echo -e "XXX\n99\nFINALIZANDO BUILD DO MAUTIC  \nXXX"
docker exec temp_container chown -R www-data:www-data /var/www/html >/dev/null 2>&1
docker exec temp_container chmod -R g+rw /var/www/html >/dev/null 2>&1

# Limpar cache para forçar a leitura do novo local.php
docker exec -it $CONTAINER_ID rm -rf /var/www/html/var/cache/* >/dev/null 2>&1

# Remover container temporário
echo -e "XXX\n100\nFINALIZANDO - ISSO PODE LEVAR ALGUNS MINUTOS  \nXXX"

docker exec -it $CONTAINER_ID chown -R www-data:www-data /var/www/html/var/import
docker exec -it $CONTAINER_ID chmod -R 755 /var/www/html/var/import

docker stop temp_container >/dev/null 2>&1

################################################################


docker service ls --filter name=$nome_app -q | xargs -I {} docker service update --force {} >/dev/null 2>&1

}|whiptail --title "MAUTIC 7 - PROGRESSO DA INSTALAÇÃO" --gauge "Aguarde a instalação dos ítens necessários" 6 60 0

# FIM DE INSTALANDO O MAUTIC 7
#

#
# VERIFICAÇÃO FINAL
#
senha_mysql=$(grep -oP '(?<=MYSQL_ROOT_PASSWORD=).+' /root/mysql84.yaml)
# Verificação conforme tipo de instalação
if [ "$INSTALL_TYPE" = "TRADICIONAL" ]; then
    ip_servidor=$(curl -s --max-time 10 ipinfo.io/ip)
    dns_ip=$(timeout 10 nslookup "$url_mautic" | grep "Address" | tail -n1 | awk '{print $2}' 2>/dev/null)

    if [[ "$dns_ip" != "$ip_servidor" ]]; then
        whiptail --title "Mensagem" --msgbox "Não foi possivel acessar o dominio do MAUTIC 7 Padrão ($url_mautic). A instalação foi cancelada. Por favor, verifique se os apontamentos DNS estão corretos e propagados!. Depois, instale novamente. Pressione ENTER para voltar ao Menu Principal" 20 78
    else
        whiptail --title "Mensagem" --msgbox "MAUTIC 7 Padrão foi instalado com sucesso!\nPressione ENTER para voltar ao Menu Principal\nATENÇÃO SALVE DOS DADOS ABAIXO, ANTES DE SAIR: Foram criados um banco de dados e senha do banco para você finalizar a instalação.\nOs dados estão abaixo. Copie/anote em um local seguro! Assim que acessar pela primeira a pagina de instalação, insira o nome do banco de dados e a senha do mesmo.\nDADOS DE ACESSO:\nDatabase Host: mysql84\nLink do Mautic: $url_mautic\nNome do Banco de dados: $nome_app\nSenha do Banco de dados: $senha_mysql" 20 78
    fi
else
    # Para Cloudflare Tunnel, verificação mais simples
    if nslookup "$url_mautic" >/dev/null 2>&1; then
        whiptail --title "Mensagem" --msgbox "MAUTIC 7 Padrão foi instalado com sucesso!\nConfiguração Cloudflare Tunnel concluída com rotas e DNS.\nPressione ENTER para voltar ao Menu Principal\nATENÇÃO SALVE DOS DADOS ABAIXO, ANTES DE SAIR: Foram criados um banco de dados e senha do banco para você finalizar a instalação.\nOs dados estão abaixo. Copie/anote em um local seguro! Assim que acessar pela primeira a pagina de instalação, insira o nome do banco de dados e a senha do mesmo.\n\nDADOS DE ACESSO:\nDatabase Host: mysql84\nLink do Mautic: $url_mautic\nNome do Banco de dados: $nome_app\nSenha do Banco de dados: $senha_mysql" 20 78
    else
        whiptail --title "Mensagem" --msgbox "AVISO: O domínio do MAUTIC 7 Padrão ($url_mautic) não está resolvendo.\nVerifique a configuração do Cloudflare Tunnel.\n\nA instalação foi concluída, mas o acesso pode não funcionar até que o DNS esteja configurado corretamente.\n\nPressione ENTER para voltar ao Menu Principal" 20 78
    fi
fi

exit 0

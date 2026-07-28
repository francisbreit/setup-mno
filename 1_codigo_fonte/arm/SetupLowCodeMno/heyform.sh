#!/usr/bin/bash
#########################################################
#
# LOADING
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

{
  tput reset 2>/dev/null
  exec 0</dev/tty 1>/dev/tty 2>&1
  sleep 0.01
  clear
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
    whiptail --title "INSTALAÇÃO DO HEYFORM: FORMULÁRIOS" --msgbox "$msg" --fb 10 70;
}

while true; do
CHOICE=$(
whiptail --title "INSTALAÇÃO DO HEYFORM: FORMULÁRIOS" --menu "Aperte ENTER para iniciar a instalação ou selecione SAIR (Utilize setas e Enter)\n\nTIPO DE INSTALAÇÃO DETECTADA: $INSTALL_TYPE\n\nINSTRUÇÕES:\nAntes de prosseguir, verifique os registros DNS conforme seu tipo de instalação:" 20 70 2 \
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


while true ; do
    url_heyform=$(whiptail --title "1/3 - URL do HeyForm" --inputbox "Digite o dominio para acessar o HeyForm (ex: forms.dominio.com):" --fb 12 60 3>&1 1>&2 2>&3) ; saida=$?
    if [[ $saida -eq '0' ]] ; then
        if [[ -z $url_heyform ]] ; then msg "Digite o link do HEYFORM para poder continuar" ; continue ; else break; fi
    else
        echo $url_heyform ; echo "saindo..."  &  exit 0 ;
    fi
done

# Verificar se URL já existe no Cloudflare Tunnel (ANTES do gauge)
if [ "$INSTALL_TYPE" = "CLOUDFLARE_TUNNEL" ]; then
    CHECK_RESPONSE=$(curl -sS -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
      "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/cfd_tunnel/$TUNNEL_ID/configurations")
    EXISTING_HOST=$(echo "$CHECK_RESPONSE" | jq -r --arg h "$url_heyform" '.result.config.ingress[] | select(.hostname == $h) | .hostname' 2>/dev/null)
    if [[ -n "$EXISTING_HOST" ]]; then
        EXISTING_SERVICE=$(echo "$CHECK_RESPONSE" | jq -r --arg h "$url_heyform" '.result.config.ingress[] | select(.hostname == $h) | .service' 2>/dev/null)
        whiptail --title "Rota Existente" --msgbox "Já existe uma rota configurada para:\n\nURL: $url_heyform\nServiço atual: $EXISTING_SERVICE\n\nA rota será substituída pela nova aplicação." --fb 14 70
    fi
fi

while true ; do
    criar_portainer=$(whiptail --title "2/3 - Criar Stack no Portainer?" --inputbox "Digite 0 para criar stack editável no Portainer ou 1 para criar direto no Docker:" --fb 12 60 3>&1 1>&2 2>&3) ; saida=$?
    if [[ $saida -eq '0' ]] ; then
        if [[ "$criar_portainer" != "0" && "$criar_portainer" != "1" ]] ; then msg "Digite apenas 0 ou 1" ; continue ; else break; fi
    else
        echo $criar_portainer ; echo "saindo..."  &  exit 0 ;
    fi
done

clear

#
# VERIFICAÇÃO DE DADOS
#

nome_principal="heyform"
sufixo_app=$(date | md5sum | head -c7)
nome_app=$nome_principal$sufixo_app

{
  tput reset 2>/dev/null
  exec 0</dev/tty 1>/dev/tty 2>&1
  sleep 0.01
  clear
} || true

    whiptail --title "Dados Fornecidos" \
    --msgbox "TIPO DE INSTALAÇÃO: $INSTALL_TYPE\n\nDados Preenchidos:\n\n1) Dominio do HeyForm: $url_heyform\n2) Criar Stack no Portainer: $([ "$criar_portainer" == "0" ] && echo "0 (Editável)" || echo "1 (Não editável)")\n\nConfira e Tecle Enter para continuar." \
    --fb 16 80

while true; do
{
  tput reset 2>/dev/null
  exec 0</dev/tty 1>/dev/tty 2>&1
  sleep 0.01
  clear
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
        msg "Entrada inválida! Por favor, use apenas 'y' para sim ou 'n' para não."
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

echo -e "XXX\n5\nVERIFICANDO CONFIGURAÇÃO... \nXXX"

if [ "$INSTALL_TYPE" = "TRADICIONAL" ]; then
    echo -e "XXX\n10\nCONFIGURANDO DNS AUTOMÁTICO (TRADICIONAL)... \nXXX"

    DOMINIO_PRINCIPAL=$(echo "$url_heyform" | cut -d'.' -f2-)

    echo -e "XXX\n15\nVERIFICANDO REGISTROS EXISTENTES... \nXXX"
    EXISTING_RECORDS=$(curl -s -X GET \
        "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records?name=${url_heyform}" \
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

    echo -e "XXX\n25\nCRIANDO REGISTRO CNAME... \nXXX"
    CNAME_RESPONSE=$(curl -s -X POST \
        "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records" \
        -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
        -H "Content-Type: application/json" \
        --data '{"type":"CNAME","name":"'${url_heyform}'","content":"'${nome_servidor}'.'${DOMINIO_PRINCIPAL}'","ttl":1,"proxied":false}')

    if echo "$CNAME_RESPONSE" | grep -q '"success":true'; then
        echo -e "XXX\n30\nREGISTRO CNAME CRIADO COM SUCESSO! \nXXX"
    else
        echo -e "XXX\n30\nAVISO: ERRO AO CRIAR REGISTRO CNAME \nXXX"
    fi

elif [ "$INSTALL_TYPE" = "CLOUDFLARE_TUNNEL" ]; then
    echo -e "XXX\n10\nCONFIGURANDO CLOUDFLARE TUNNEL (DNS + ROTAS)... \nXXX"

    DOMINIO_PRINCIPAL=$(echo "$url_heyform" | cut -d'.' -f2-)

    echo -e "XXX\n15\nCONFIGURANDO REGISTRO DNS... \nXXX"

    EXISTING_RECORDS=$(curl -s -X GET \
        "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records?name=${url_heyform}" \
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

    echo -e "XXX\n25\nCRIANDO REGISTRO CNAME PARA TUNNEL... \nXXX"
    DNS_RESPONSE=$(curl -s -X POST \
        "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records" \
        -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
        -H "Content-Type: application/json" \
        --data "{\"type\":\"CNAME\",\"name\":\"${url_heyform}\",\"content\":\"${TUNNEL_ID}.cfargotunnel.com\",\"ttl\":1,\"proxied\":true}")

    if echo "$DNS_RESPONSE" | grep -q '"success":true'; then
        echo -e "XXX\n30\nREGISTRO DNS CRIADO COM SUCESSO! \nXXX"
    else
        echo -e "XXX\n30\nAVISO: ERRO AO CRIAR REGISTRO DNS \nXXX"
    fi

    echo -e "XXX\n35\nATUALIZANDO CONFIGURAÇÃO DO TUNNEL... \nXXX"

    NEW_SERVICE="http://${nome_app}_app:9157"

    TIMESTAMP=$(date -u +%Y%m%dT%H%M%SZ)
    TMPDIR=$(mktemp -d)
    BACKUP_RAW="$TMPDIR/backup_raw.$TIMESTAMP.json"
    TO_PUT="$TMPDIR/to_put.$TIMESTAMP.json"

    echo -e "XXX\n40\nOBTENDO CONFIGURAÇÃO ATUAL DO TUNNEL... \nXXX"
    curl -sS -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
      "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/cfd_tunnel/$TUNNEL_ID/configurations" \
      | jq '.' > "$BACKUP_RAW"

    if ! jq -e '.success == true' "$BACKUP_RAW" >/dev/null 2>&1; then
        echo -e "XXX\n45\nERRO: FALHA AO OBTER CONFIGURAÇÃO DO TUNNEL \nXXX"
        sleep 3
    else
        echo -e "XXX\n45\nCONFIGURAÇÃO OBTIDA COM SUCESSO \nXXX"
    fi

    echo -e "XXX\n50\nCONFIGURANDO NOVAS ROTAS... \nXXX"

    jq --arg host "$url_heyform" --arg service "$NEW_SERVICE" '
      (.result.config // {}) as $cfg
      | ($cfg.ingress // []) as $ing
      | ($ing | map(select(.service != "http_status:404"))) as $clean
      
      | ($clean | map(select(.hostname != $host))) as $filtered
      | ($filtered + [ { hostname: $host, service: $service, originRequest: { noTlsVerify: true, httpHostHeader: $host } } ]) as $merged
      | ($merged + [{ service: "http_status:404" }]) as $final_ing
      | ($cfg + { ingress: $final_ing }) as $newcfg
      | { config: $newcfg }
    ' "$BACKUP_RAW" > "$TO_PUT"

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

    rm -rf "$TMPDIR"

else
    echo -e "XXX\n10\nVERIFICANDO CONFIGURAÇÃO (TRADICIONAL SEM AUTOMAÇÃO)... \nXXX"
    if nslookup "$url_heyform" >/dev/null 2>&1; then
        echo -e "XXX\n15\nDNS CONFIGURADO \nXXX"
    else
        echo -e "XXX\n15\nAVISO: VERIFIQUE A CONFIGURAÇÃO DNS \nXXX"
    fi
fi


echo -e "XXX\n70\nVERIFICANDO MONGODB... \nXXX"

# Verificar se MongoDB já existe
if docker stack ls | grep -q "mongodb "; then
    echo -e "XXX\n75\nMONGODB JÁ INSTALADO - EXTRANDO CREDENCIAIS... \nXXX"
    user_mongo=$(grep -oP '(?<=MONGO_INITDB_ROOT_USERNAME=).+' /root/mongodb.yaml)
    pass_mongo=$(grep -oP '(?<=MONGO_INITDB_ROOT_PASSWORD=).+' /root/mongodb.yaml)
    echo -e "XXX\n80\nCREDENCIAIS DO MONGODB OBTIDAS \nXXX"
else
    echo -e "XXX\n75\nMONGODB NÃO ENCONTRADO - INSTALANDO... \nXXX"

    user_mongo="admin"
    pass_mongo=$(openssl rand -hex 16)

    # Criar mongodb.yaml completo em /root (padrão MySQL)
    cat > /root/mongodb.yaml << EOL
version: '3.7'
services:
    mongodb:
        image: mongo:7
        hostname: mongodb
        environment:
            - MONGO_INITDB_ROOT_USERNAME=$user_mongo
            - MONGO_INITDB_ROOT_PASSWORD=$pass_mongo
        networks:
            - interna
        volumes:
            - mongodb_data:/data/db
            - mongodb_configdb:/data/configdb
        deploy:
            placement:
                constraints: [node.role == manager]
volumes:
    mongodb_data:
    mongodb_configdb:
networks:
    interna:
        external: true
        name: interna
EOL

    docker stack deploy --prune --resolve-image always -c mongodb.yaml mongodb >/dev/null 2>&1

    echo -e "XXX\n80\nMONGODB INSTALADO \nXXX"

    # Aguardar MongoDB ficar pronto
    sleep 15
fi

echo -e "XXX\n85\nMONGODB CONFIGURADO \nXXX"
sleep 1
echo -e "XXX\n50\nCRIANDO STACK DO HEYFORM 2/3 \nXXX"
sleep 1


# FIM DE MENSAGEM DE INSTALANDO
#
#######################################################
#
#  INSTALANDO O HEYFORM
#

cd

cd

sessionkey_heyform=$(openssl rand -hex 16)
encryptionkey_heyform=$(openssl rand -hex 16)

cat > $nome_app.yaml << EOL

version: "3.8"
services:
  ${nome_app}_app:
    image: heyform/community-edition:v0.1.0
    hostname: ${nome_app}_app
    networks:
      - externa
      - interna
    volumes:
      - ${nome_app}_uploads:/app/static/upload
    environment:
      - NODE_ENV=production
      - APP_LISTEN_PORT=9157
      - APP_LISTEN_HOSTNAME=0.0.0.0
      - APP_HOMEPAGE_URL=https://$url_heyform
      - APP_DISABLE_REGISTRATION=false
      - COOKIE_MAX_AGE=1y
      - COOKIE_DOMAIN=
      - SESSION_KEY=$sessionkey_heyform
      - SESSION_MAX_AGE=15d
      - FORM_ENCRYPTION_KEY=$encryptionkey_heyform
      - MONGO_URI=mongodb://mongodb:27017/$nome_app?authSource=admin
      - MONGO_USER=$user_mongo
      - MONGO_PASSWORD=$pass_mongo
      - REDIS_HOST=${nome_app}_redis
      - REDIS_PORT=6379
      - REDIS_PASSWORD=
      - REDIS_DB=0
      - UPLOAD_FILE_SIZE=10485760
      - UPLOAD_FILE_TYPES=
      - BCRYPT_SALT=10
      - BULL_JOB_ATTEMPTS=3
      - BULL_JOB_TIMEOUT=1m
      - BULL_JOB_BACKOFF_DELAY=3000
      - BULL_JOB_BACKOFF_TYPE=fixed
      - INVITE_CODE_EXPIRE_DAYS=7
      - FORM_REPORT_RATE=5s
      - VERIFICATION_CODE_EXPIRE=10m
      - VERIFICATION_CODE_LIMIT=5
      - ACCOUNT_DELETION_SCHEDULE_INTERVAL=2d
    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
        - node.role == manager
      resources:
        limits:
          cpus: "1"
          memory: 1024M
EOL
if [ "$INSTALL_TYPE" = "TRADICIONAL" ]; then
cat >> $nome_app.yaml << EOL
      labels:
      - traefik.enable=true
      - traefik.http.routers.$nome_app.rule=Host(\`$url_heyform\`)
      - traefik.http.routers.$nome_app.entrypoints=websecure
      - traefik.http.routers.$nome_app.priority=1
      - traefik.http.routers.$nome_app.tls.certresolver=letsencryptresolver
      - traefik.http.routers.$nome_app.tls=true
      - traefik.http.routers.$nome_app.service=$nome_app
      - traefik.http.services.$nome_app.loadbalancer.server.port=9157
      - traefik.http.services.$nome_app.loadbalancer.passHostHeader=1
EOL
fi
cat >> $nome_app.yaml << EOL

  ${nome_app}_redis:
    image: redis:7-alpine
    hostname: ${nome_app}_redis
    networks:
      - interna
    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
        - node.role == manager

networks:
  externa:
    external: true
  interna:
    external: true

volumes:
  ${nome_app}_uploads:
    external: true
    name: ${nome_app}_uploads

EOL


if [[ "$criar_portainer" == "0" ]]; then
    echo -e "XXX\n76\nCRIANDO STACK NO PORTAINER 3/3  \nXXX"

dados_file="$HOME/dados_portainer/dados_portainer"

if [[ -f "$dados_file" ]]; then
PORTAINER_URL=$(grep "Dominio do portainer:" "$dados_file" | cut -d':' -f2 | xargs)
ADMIN_USERNAME=$(grep "Usuario:" "$dados_file" | cut -d':' -f2 | xargs)
ADMIN_PASSWORD=$(grep "Senha:" "$dados_file" | cut -d':' -f2 | xargs)
STACK_NAME=$nome_app
STACK_FILE_PATH="/root/$nome_app.yaml"

else
    sleep 5
echo -e "XXX\n77\nSEM ARQUIVO DE DADOS DO PORTAINER 3/3  \nXXX"
docker stack deploy --prune --resolve-image always -c $nome_app.yaml $nome_app >/dev/null 2>&1
sleep 5
    exit 1
fi

get_auth_token() {
    echo -e "XXX\n77\nAUTENTICANDO NO PORTAINER... 3/3  \nXXX"
    RESPONSE=$(curl -sS -X POST "https://$PORTAINER_URL/api/auth" \
        -H "Content-Type: application/json" \
        -d "{\"username\": \"$ADMIN_USERNAME\", \"password\": \"$ADMIN_PASSWORD\"}")
    TOKEN=$(echo "$RESPONSE" | jq -r '.jwt')
    if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]; then
        echo -e "XXX\n77\nFALHA NA AUTENTICAÇÃO.. 3/3  \nXXX"
sleep 5
echo -e "XXX\n78\nREVERTENDO E CRIANDO STACK PELO SERVIDOR 3/3  \nXXX"
docker stack deploy --prune --resolve-image always -c $nome_app.yaml $nome_app >/dev/null 2>&1
sleep 5
        exit 1
    fi
 echo -e "XXX\n79\n[SUCESSO] AUTENTICAÇÃO OK 3/3  \nXXX"
}

get_endpoint_id() {
    echo -e "XXX\n80\n[INFO] OBTENDO ENDPOINTID 3/3  \nXXX"
    RESPONSE=$(curl -sS -X GET "https://$PORTAINER_URL/api/endpoints" \
        -H "Authorization: Bearer $TOKEN")
    ENDPOINT_ID=$(echo "$RESPONSE" | jq -r '.[0].Id')
    if [ -z "$ENDPOINT_ID" ] || [ "$ENDPOINT_ID" = "null" ]; then
        echo -e "XXX\n81\n[ERRO] ENDPOINTID NÃO ENCONTRADO 3/3  \nXXX"
        docker stack deploy --prune --resolve-image always -c $nome_app.yaml $nome_app >/dev/null 2>&1
        exit 1
    fi
     echo -e "XXX\n82\n[SUCESSO] ENDPOINTID OBTIDO: $ENDPOINT_ID  3/3  \nXXX"
}

get_swarm_id() {
    echo -e "XXX\n83\n[INFO] OBTENDO SWARMID  3/3  \nXXX"
    RESPONSE=$(curl -sS -X GET "https://$PORTAINER_URL/api/endpoints/$ENDPOINT_ID/docker/swarm" \
        -H "Authorization: Bearer $TOKEN")
    SWARM_ID=$(echo "$RESPONSE" | jq -r '.ID')
    if [ -z "$SWARM_ID" ] || [ "$SWARM_ID" = "null" ]; then
        echo -e "XXX\n84\n[ERRO] SWARMID NÃO ENCONTRADO 3/3  \nXXX"
        docker stack deploy --prune --resolve-image always -c $nome_app.yaml $nome_app >/dev/null 2>&1
        exit 1
    fi
    echo -e "XXX\n85\n[SUCESSO] SWARMID OBTIDO: $SWARM_ID  3/3  \nXXX"
}

create_stack() {
    echo -e "XXX\n86\n[INFO] VERIFICANDO SE YAML EXISTE 3/3  \nXXX"
    if [ ! -f "$STACK_FILE_PATH" ]; then
        echo -e "XXX\n87\n[ERRO] ARQUIVO $STACK_FILE_PATH NÃO ENCONTRADO 3/3  \nXXX"
        docker stack deploy --prune --resolve-image always -c $nome_app.yaml $nome_app >/dev/null 2>&1
        exit 1
    fi

     echo -e "XXX\n88\n[INFO] CRIANDO STACK $STACK_NAME NO PORTAINER 3/3  \nXXX"
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

    if [ "$http_code" -ne 200 ]; then
        echo -e "XXX\n89\n[ERRO] ERRO AO CRIAR STACK 3/3  \nXXX"
        docker stack deploy --prune --resolve-image always -c $nome_app.yaml $nome_app >/dev/null 2>&1
        exit 1
    fi

    echo -e "XXX\n90\n[SUCESSO] STACK $STACK_NAME  CRIADA COM SUCESSO 3/3  \nXXX"
}

get_auth_token || exit 1
get_endpoint_id || exit 1
get_swarm_id || exit 1
create_stack || exit 1



elif [[ "$criar_portainer" == "1" ]]; then
    echo "Criando a stack diretamente no Docker (não editável no Portainer)."
    docker stack deploy --prune --resolve-image always -c $nome_app.yaml $nome_app >/dev/null 2>&1
else
    echo -e "XXX\n91\n[ERRO] ERRO INESPERADO PARA CRIAR STACK NO PORTAINER 3/3  \nXXX"
    sleep 5
    echo -e "XXX\n92\nREVERTENDO E CRIANDO STACK PELO SERVIDOR 3/3  \nXXX"
docker stack deploy --prune --resolve-image always -c $nome_app.yaml $nome_app >/dev/null 2>&1
sleep 5

    exit 1
fi


echo -e "XXX\n95\nFINALIZANDO BUILD DO HEYFORM 3/3  \nXXX"

sleep 12

echo -e "XXX\n100\nFINALIZANDO BUILD DO HEYFORM 3/3 - CONCLUIDO  \nXXX"

sleep 3

}|whiptail --title "HEYFORM - PROGRESSO DA INSTALAÇÃO" --gauge "Aguarde a instalação dos ítens necessários" 6 60 0


#######################################################
#
# VERIFICAÇÃO FINAL
#

if [ "$INSTALL_TYPE" = "TRADICIONAL" ]; then
    ip_servidor=$(curl -s --max-time 10 ipinfo.io/ip)
    dns_ip=$(timeout 10 nslookup "$url_heyform" | grep "Address" | tail -n1 | awk '{print $2}' 2>/dev/null)

    if [[ "$dns_ip" != "$ip_servidor" ]]; then
        whiptail --title "Mensagem" --msgbox "Não foi possivel acessar o dominio do HeyForm ($url_heyform). Verifique os apontamentos DNS. Pressione ENTER para voltar ao Menu Principal" 20 78
    else
        whiptail --title "Mensagem" --msgbox "Parabéns, HeyForm foi instalado com sucesso!\n\nAcesse: https://$url_heyform\nCrie sua conta no primeiro acesso.\n\nPressione ENTER para voltar ao Menu Principal" 20 78
    fi
else
    if nslookup "$url_heyform" >/dev/null 2>&1; then
        whiptail --title "Mensagem" --msgbox "Parabéns, HeyForm foi instalado com sucesso!\n\nAcesse: https://$url_heyform\nCrie sua conta no primeiro acesso.\n\nPressione ENTER para voltar ao Menu Principal" 20 78
    else
        whiptail --title "Mensagem" --msgbox "AVISO: O domínio do HeyForm ($url_heyform) não está resolvendo.\nVerifique a configuração do Cloudflare Tunnel.\n\nPressione ENTER para voltar ao Menu Principal" 20 78
    fi
fi

exit 0

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

#
# NOME DO PROGRAMA
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
    whiptail --title "INSTALAÇÃO DO JITSI MEET" --msgbox "$msg" --fb 10 70;
}

while true; do
CHOICE=$(
whiptail --title "INSTALAÇÃO DO JITSI MEET" --menu "Aperte ENTER para iniciar a instalação ou selecione SAIR (Utilize setas e Enter)\n\nTIPO DE INSTALAÇÃO DETECTADA: $INSTALL_TYPE\n\nINSTRUÇÕES:\nAntes de prosseguir, verifique os registros DNS conforme seu tipo de instalação:" 20 70 2 \
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
    url_jitsi=$(whiptail --title "1/5 - URL do Jitsi" --inputbox "Digite o dominio para acessar o Jitsi (ex: jitsi.dominio.com):" --fb 12 60 3>&1 1>&2 2>&3) ; saida=$?
    if [[ $saida -eq '0' ]] ; then
        if [[ -z $url_jitsi ]] ; then msg "Digite o link do JITSI para poder continuar" ; continue ; else break; fi
    else
        echo $url_jitsi ; echo "saindo..."  &  exit 0 ;
    fi
done

while true ; do
    ip_jitsi=$(whiptail --title "2/5 - IP Publico da VPS" --inputbox "Digite o IP Publico da VPS (ex: $(hostname -I | awk '{print $1}')):" --fb 12 60 3>&1 1>&2 2>&3) ; saida=$?
    if [[ $saida -eq '0' ]] ; then
        if [[ -z $ip_jitsi ]] ; then msg "Digite o IP Publico da VPS para poder continuar" ; continue ; else break; fi
    else
        echo $ip_jitsi ; echo "saindo..."  &  exit 0 ;
    fi
done

while true ; do
    user_jitsi=$(whiptail --title "3/5 - Usuario Admin" --inputbox "Digite o usuario admin para o Jitsi (ex: admin):" --fb 12 60 3>&1 1>&2 2>&3) ; saida=$?
    if [[ $saida -eq '0' ]] ; then
        if [[ -z $user_jitsi ]] ; then msg "Digite o usuario admin para poder continuar" ; continue ; else break; fi
    else
        echo $user_jitsi ; echo "saindo..."  &  exit 0 ;
    fi
done

while true ; do
    pass_jitsi=$(whiptail --title "4/5 - Senha Admin" --inputbox "Digite a senha do admin (ex: @Senha123_):" --fb 12 60 3>&1 1>&2 2>&3) ; saida=$?
    if [[ $saida -eq '0' ]] ; then
        if [[ -z $pass_jitsi ]] ; then msg "Digite a senha do admin para poder continuar" ; continue ; else break; fi
    else
        echo $pass_jitsi ; echo "saindo..."  &  exit 0 ;
    fi
done

while true ; do
    criar_portainer=$(whiptail --title "5/5 - Criar Stack no Portainer?" --inputbox "Digite 0 para criar stack editável no Portainer ou 1 para criar direto no Docker:" --fb 12 60 3>&1 1>&2 2>&3) ; saida=$?
    if [[ $saida -eq '0' ]] ; then
        if [[ "$criar_portainer" != "0" && "$criar_portainer" != "1" ]] ; then msg "Digite apenas 0 ou 1" ; continue ; else break; fi
    else
        echo $criar_portainer ; echo "saindo..."  &  exit 0 ;
    fi
done

    # Exibe as informações formatadas
    whiptail --title "Dados Fornecidos" \
    --msgbox "TIPO DE INSTALAÇÃO: $INSTALL_TYPE\n\nDados Preenchidos:\n\n1) Dominio do Jitsi: $url_jitsi\n2) IP Publico da VPS: $ip_jitsi\n3) Usuario Admin: $user_jitsi\n4) Senha Admin: $pass_jitsi\n5) Criar Stack no Portainer: $([ "$criar_portainer" == "0" ] && echo "0 (Editável)" || echo "1 (Não editável)")\n\nConfira e Tecle Enter para continuar." \
    --fb 20 80

# Solicita confirmação dentro de um loop
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

# Verificar se variáveis do Cloudflare estão definidas
if [ -z "$CLOUDFLARE_API_TOKEN" ] || [ -z "$CLOUDFLARE_ZONE_ID" ]; then
    echo -e "XXX\n8\nAVISO: CREDENCIAIS DO CLOUDFLARE NÃO ENCONTRADAS \nXXX"
    sleep 3
fi

# GERAR SUFIXO ÚNICO (como keycloak.sh)
nome_principal="jitsi"
sufixo_app=$(date | md5sum | head -c7)
nome_app=$nome_principal$sufixo_app

if [ "$INSTALL_TYPE" = "TRADICIONAL" ]; then
    # CONFIGURAÇÃO TRADICIONAL COM DNS AUTOMÁTICO
    echo -e "XXX\n10\nCONFIGURANDO DNS AUTOMÁTICO (TRADICIONAL)... \nXXX"

    DOMINIO_PRINCIPAL=$(echo "$url_jitsi" | cut -d'.' -f2-)
    SUBDOMINIO=${url_jitsi%%.$DOMINIO_PRINCIPAL}

    # Verificar se nome_servidor está definido
    if [ -z "$nome_servidor" ]; then
        echo -e "XXX\n12\nAVISO: nome_servidor NÃO DEFINIDO - Usando IP do servidor \nXXX"
        nome_servidor=$(hostname -I | awk '{print $1}')
    fi

    echo -e "XXX\n15\nVERIFICANDO REGISTROS EXISTENTES... \nXXX"
    EXISTING_RECORDS=$(curl -s -X GET \
        "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records?name=${url_jitsi}" \
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
        --data '{"type":"CNAME","name":"'${url_jitsi}'","content":"'${nome_servidor}'.'${DOMINIO_PRINCIPAL}'","ttl":1,"proxied":false}')

    if echo "$CNAME_RESPONSE" | grep -q '"success":true'; then
        echo -e "XXX\n30\nREGISTRO CNAME CRIADO COM SUCESSO! \nXXX"
    else
        echo -e "XXX\n30\nAVISO: ERRO AO CRIAR REGISTRO CNAME \nXXX"
        echo "$CNAME_RESPONSE" | jq -r '.errors[].message' 2>/dev/null
    fi

elif [ "$INSTALL_TYPE" = "CLOUDFLARE_TUNNEL" ]; then
    # CONFIGURAÇÃO CLOUDFLARE TUNNEL - DNS E ROTAS (API)
    echo -e "XXX\n10\nCONFIGURANDO CLOUDFLARE TUNNEL (DNS + ROTAS)... \nXXX"

    DOMINIO_PRINCIPAL=$(echo "$url_jitsi" | cut -d'.' -f2-)
    SUBDOMINIO=${url_jitsi%%.$DOMINIO_PRINCIPAL}

    echo -e "XXX\n15\nCONFIGURANDO REGISTRO DNS... \nXXX"

    EXISTING_RECORDS=$(curl -s -X GET \
        "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records?name=${url_jitsi}" \
        -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
        -H "Content-Type: application/json")

    COUNT=$(echo "$EXISTING_RECORDS" | jq '.result | length')
    if [[ "$COUNT" -gt 0 ]]; then
        echo "$EXISTING_RECORDS" | jq -r '.result[].id' | while read -r REC_ID; do
            [[ -z "$REC_ID" ]] && continue
            curl -s -X DELETE \
                "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records/${REC_ID}" \
                -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
                -H "Content-Type: application/json" >/dev/null 2>&1
        done
    fi

    CNAME_RESPONSE=$(curl -s -X POST \
        "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records" \
        -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
        -H "Content-Type: application/json" \
        --data '{"type":"CNAME","name":"'${url_jitsi}'","content":"'${TUNNEL_ID}'.cfargotunnel.com","ttl":1,"proxied":true}')

    if echo "$CNAME_RESPONSE" | grep -q '"success":true'; then
        echo -e "XXX\n20\nREGISTRO DNS CRIADO COM SUCESSO! \nXXX"
    else
        echo -e "XXX\n20\nAVISO: ERRO AO CRIAR REGISTRO DNS \nXXX"
    fi

    echo -e "XXX\n25\nATUALIZANDO CONFIGURAÇÃO DO TUNNEL... \nXXX"

    NEW_SERVICE="http://${nome_app}_web:80"

    TIMESTAMP=$(date -u +%Y%m%dT%H%M%SZ)
    TMPDIR=$(mktemp -d)
    BACKUP_RAW="$TMPDIR/backup_raw.$TIMESTAMP.json"
    TO_PUT="$TMPDIR/to_put.$TIMESTAMP.json"

    echo -e "XXX\n30\nOBTENDO CONFIGURAÇÃO ATUAL DO TUNNEL... \nXXX"
    curl -sS -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
      "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/cfd_tunnel/$TUNNEL_ID/configurations" \
      | jq '.' > "$BACKUP_RAW"

    if ! jq -e '.success == true' "$BACKUP_RAW" >/dev/null 2>&1; then
        echo -e "XXX\n35\nERRO: FALHA AO OBTER CONFIGURAÇÃO DO TUNNEL \nXXX"
        sleep 3
    else
        echo -e "XXX\n35\nCONFIGURAÇÃO OBTIDA COM SUCESSO \nXXX"
    fi

    echo -e "XXX\n40\nCONFIGURANDO NOVAS ROTAS... \nXXX"

    jq --arg host "$url_jitsi" --arg service "$NEW_SERVICE" '
      (.result.config // {}) as $cfg
      | ($cfg.ingress // []) as $ing
      | ($ing | map(select(.service != "http_status:404"))) as $clean
      | ($clean | map(.hostname // "")) as $existing_names
      | (if ($existing_names | index($host)) then $clean else ($clean + [ { hostname: $host, service: $service, originRequest: { noTlsVerify: true, httpHostHeader: $host } } ]) end) as $merged
      | ($merged + [{ service: "http_status:404" }]) as $final_ing
      | ($cfg + { ingress: $final_ing }) as $newcfg
      | { config: $newcfg }
    ' "$BACKUP_RAW" > "$TO_PUT"

    echo -e "XXX\n45\nAPLICANDO NOVA CONFIGURAÇÃO DO TUNNEL... \nXXX"
    APPLY_RESPONSE=$(curl -sS -X PUT "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/cfd_tunnel/$TUNNEL_ID/configurations" \
      -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
      -H "Content-Type: application/json" \
      --data-binary @"$TO_PUT")

    if echo "$APPLY_RESPONSE" | grep -q '"success":true'; then
        echo -e "XXX\n50\nTUNNEL CONFIGURADO COM SUCESSO! \nXXX"
    else
        echo -e "XXX\n50\nAVISO: ERRO AO CONFIGURAR TUNNEL \nXXX"
    fi

    rm -rf "$TMPDIR"

else
    # TRADICIONAL COM DNS MANUAL
    echo -e "XXX\n10\nMODO DNS MANUAL - Verificando subdomínio... \nXXX"

    ip_servidor=$(curl -s --max-time 10 ipinfo.io/ip)

    echo -e "XXX\n15\nVERIFICANDO SUBDOMÍNIO: $url_jitsi \nXXX"
    sleep 3

    tentativas=5
    tentativa_atual=1
    sucesso=0

    while [ $tentativa_atual -le $tentativas ]; do
        echo -e "XXX\n$(( (tentativa_atual * 12) / tentativas + 3 ))\nTentativa $tentativa_atual de $tentativas...\nXXX"

        dns_ip=$(timeout 10 nslookup -type=A "$url_jitsi" | grep -E "Address: [0-9]+\." | awk '{print $2}' | head -n1)

        if [[ -n "$dns_ip" && "$dns_ip" == "$ip_servidor" ]]; then
            sucesso=1
        fi

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


echo -e "XXX\n55\nCRIANDO STACK DO JITSI... \nXXX"
sleep 1

cd
cd

# Gerar secrets aleatórios
jicofo_secret_jitsi=$(openssl rand -hex 16)
jicofo_component_jitsi=$(openssl rand -hex 16)
jvb_auth_jitsi=$(openssl rand -hex 16)

# Criar o docker-compose.yml (com sufixo no nome)
cat > $nome_app.yaml << EOL
version: "3.7"
services:

  ${nome_app}_web:
    image: jitsi/web:stable

    networks:
      - interna

    volumes:
      - ${nome_app}_web_config:/config:Z
      - ${nome_app}_web_crontabs:/var/spool/cron/crontabs:Z
      - ${nome_app}_transcripts:/usr/share/jitsi-meet/transcripts:Z

    environment:
      - TZ=America/Sao_Paulo
      - ENABLE_AUTH=1
      - AUTH_TYPE=internal
      - ENABLE_GUESTS=1
      - ENABLE_LOBBY=1
      - PUBLIC_URL=https://$url_jitsi
      - ENABLE_PREJOIN_PAGE=1
      - ENABLE_WELCOME_PAGE=1
      - ENABLE_CLOSE_PAGE=1
      - ENABLE_BREAKOUT_ROOMS=1
      - ENABLE_AV_MODERATION=1
      - ENABLE_END_CONFERENCE=1
      - ENABLE_REQUIRE_DISPLAY_NAME=1
      - ENABLE_RECORDING=0
      - ENABLE_FILE_RECORDING_SHARING=0
      - ENABLE_TRANSCRIPTIONS=0
      - ENABLE_POLLS=1
      - ENABLE_REACTIONS=1
      - ENABLE_RAISE_HAND=1
      - ENABLE_P2P=1
      - ENABLE_NOISE_SUPPRESSION=1
      - ENABLE_STEREO=0
      - ENABLE_TALK_WHILE_MUTED=1
      - ENABLE_NO_AUDIO_DETECTION=1
      - XMPP_SERVER=${nome_app}_prosody
      - XMPP_DOMAIN=meet.jitsi
      - XMPP_AUTH_DOMAIN=auth.meet.jitsi
      - XMPP_GUEST_DOMAIN=guest.meet.jitsi
      - XMPP_MUC_DOMAIN=muc.meet.jitsi
      - XMPP_BOSH_URL_BASE=http://${nome_app}_prosody:5280
      - ENABLE_XMPP_WEBSOCKET=1

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
# Adicionar as labels apenas se for instalação tradicional
if [ "$INSTALL_TYPE" = "TRADICIONAL" ]; then
cat >> $nome_app.yaml << EOL
      labels:
      - traefik.enable=true
      - traefik.docker.network=externa
      - traefik.http.routers.${nome_app}_web.rule=Host(\`$url_jitsi\`)
      - traefik.http.routers.${nome_app}_web.entrypoints=websecure
      - traefik.http.routers.${nome_app}_web.priority=1
      - traefik.http.routers.${nome_app}_web.tls.certresolver=letsencryptresolver
      - traefik.http.routers.${nome_app}_web.tls=true
      - traefik.http.routers.${nome_app}_web.service=${nome_app}_web
      - traefik.http.services.${nome_app}_web.loadbalancer.server.port=80
EOL
fi
cat >> $nome_app.yaml << EOL

  ${nome_app}_prosody:
    image: jitsi/prosody:stable

    volumes:
      - ${nome_app}_prosody_config:/config:Z
      - ${nome_app}_prosody_plugins:/prosody-plugins-custom:Z

    networks:
      - interna

    environment:
      - TZ=America/Sao_Paulo
      - ENABLE_AUTH=1
      - AUTH_TYPE=internal
      - ENABLE_GUESTS=1
      - JICOFO_AUTH_USER=focus
      - JICOFO_AUTH_PASSWORD=$jicofo_secret_jitsi
      - JICOFO_COMPONENT_SECRET=$jicofo_component_jitsi
      - JVB_AUTH_USER=jvb
      - JVB_AUTH_PASSWORD=$jvb_auth_jitsi
      - XMPP_DOMAIN=meet.jitsi
      - XMPP_AUTH_DOMAIN=auth.meet.jitsi
      - XMPP_GUEST_DOMAIN=guest.meet.jitsi
      - XMPP_MUC_DOMAIN=muc.meet.jitsi
      - XMPP_INTERNAL_MUC_DOMAIN=internal-muc.meet.jitsi
      - ENABLE_XMPP_WEBSOCKET=1

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

  ${nome_app}_jicofo:
    image: jitsi/jicofo:stable

    volumes:
      - ${nome_app}_jicofo_config:/config:Z

    networks:
      - interna

    environment:
      - TZ=America/Sao_Paulo
      - ENABLE_AUTH=1
      - AUTH_TYPE=internal
      - JICOFO_COMPONENT_SECRET=$jicofo_component_jitsi
      - JICOFO_AUTH_USER=focus
      - JICOFO_AUTH_PASSWORD=$jicofo_secret_jitsi
      - XMPP_DOMAIN=meet.jitsi
      - XMPP_SERVER=${nome_app}_prosody
      - XMPP_AUTH_DOMAIN=auth.meet.jitsi

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

  ${nome_app}_jvb:
    image: jitsi/jvb:stable

    volumes:
      - ${nome_app}_jvb_config:/config:Z

    networks:
      - interna
    ports:
      - target: 10000
        published: 10000
        protocol: udp
        mode: host
      - target: 4443
        published: 4443
        protocol: tcp
        mode: host

    environment:
      - TZ=America/Sao_Paulo
      - JVB_AUTH_USER=jvb
      - JVB_AUTH_PASSWORD=$jvb_auth_jitsi
      - JVB_BREWERY_MUC=jvbbrewery
      - JVB_PORT=10000
      - JVB_TCP_PORT=4443
      - JVB_TCP_HARVESTER_DISABLED=false
      - DOCKER_HOST_ADDRESS=$ip_jitsi
      - JVB_ADVERTISE_IPS=$ip_jitsi
      - JVB_STUN_SERVERS=stun.l.google.com:19302
      - XMPP_SERVER=${nome_app}_prosody
      - XMPP_DOMAIN=meet.jitsi
      - XMPP_AUTH_DOMAIN=auth.meet.jitsi
      - XMPP_INTERNAL_MUC_DOMAIN=internal-muc.meet.jitsi

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
  ${nome_app}_web_config:
    external: true
    name: ${nome_app}_web_config
  ${nome_app}_web_crontabs:
    external: true
    name: ${nome_app}_web_crontabs
  ${nome_app}_transcripts:
    external: true
    name: ${nome_app}_transcripts
  ${nome_app}_prosody_config:
    external: true
    name: ${nome_app}_prosody_config
  ${nome_app}_prosody_plugins:
    external: true
    name: ${nome_app}_prosody_plugins
  ${nome_app}_jicofo_config:
    external: true
    name: ${nome_app}_jicofo_config
  ${nome_app}_jvb_config:
    external: true
    name: ${nome_app}_jvb_config

networks:
  interna:
    external: true
    name: interna

EOL

echo -e "XXX\n60\nSTACK DO JITSI $nome_app CRIADA! \nXXX"
sleep 1

echo -e "XXX\n62\nCRIANDO VOLUMES EXTERNOS... \nXXX"
sleep 1

# Criar volumes externos (com sufixo)
for vol in ${nome_app}_web_config ${nome_app}_web_crontabs ${nome_app}_transcripts ${nome_app}_prosody_config ${nome_app}_prosody_plugins ${nome_app}_jicofo_config ${nome_app}_jvb_config; do
    docker volume create --name $vol > /dev/null 2>&1
done

echo -e "XXX\n64\nVOLUMES CRIADOS! \nXXX"
sleep 1

echo -e "XXX\n66\nFAZENDO DEPLOY DA STACK... \nXXX"
sleep 1

# Deploy da stack
if [ "$criar_portainer" = "0" ]; then
    # Criar stack via Portainer API
    STACK_NAME=$nome_app
    STACK_FILE_PATH="/root/$nome_app.yaml"
    
    # Ler credenciais do Portainer
    dados_file="$HOME/dados_portainer/dados_portainer"
    if [[ -f "$dados_file" ]]; then
        PORTAINER_URL=$(grep "Dominio do portainer:" "$dados_file" | cut -d':' -f2- | xargs)
        ADMIN_USERNAME=$(grep "Usuario:" "$dados_file" | cut -d':' -f2 | xargs)
        ADMIN_PASSWORD=$(grep "Senha:" "$dados_file" | cut -d':' -f2 | xargs)
        
        echo -e "XXX\n68\nCONECTANDO AO PORTAINER: $PORTAINER_URL \nXXX"
        
        # Autenticar no Portainer
        RESPONSE=$(curl -sk -X POST "https://$PORTAINER_URL/api/auth" \
            -H "Content-Type: application/json" \
            -d "{\"username\": \"$ADMIN_USERNAME\", \"password\": \"$ADMIN_PASSWORD\"}")
        TOKEN=$(echo "$RESPONSE" | jq -r '.jwt')
        
        if [ -n "$TOKEN" ] && [ "$TOKEN" != "null" ]; then
            echo -e "XXX\n69\nAUTENTICAÇÃO OK - OBTENDO ENDPOINTS... \nXXX"
            
            # Obter EndpointID
            RESPONSE=$(curl -sk -X GET "https://$PORTAINER_URL/api/endpoints" \
                -H "Authorization: Bearer $TOKEN")
            ENDPOINT_ID=$(echo "$RESPONSE" | jq -r '.[0].Id')
            
            # Obter SwarmID
            RESPONSE=$(curl -sk -X GET "https://$PORTAINER_URL/api/endpoints/$ENDPOINT_ID/docker/swarm" \
                -H "Authorization: Bearer $TOKEN")
            SWARM_ID=$(echo "$RESPONSE" | jq -r '.ID')
            
            echo -e "XXX\n70\nCRIANDO STACK $STACK_NAME NO PORTAINER... \nXXX"
            
            # Criar stack
            http_code=$(curl -s -o /dev/null -w "%{http_code}" -k -X POST \
                -H "Authorization: Bearer $TOKEN" \
                -F "Name=$STACK_NAME" \
                -F "file=@$STACK_FILE_PATH" \
                -F "SwarmID=$SWARM_ID" \
                -F "endpointId=$ENDPOINT_ID" \
                "https://$PORTAINER_URL/api/stacks/create/swarm/file")
            
            if [ "$http_code" = "200" ]; then
                echo -e "XXX\n72\n✅ STACK CRIADA NO PORTAINER COM SUCESSO! \nXXX"
            else
                echo -e "XXX\n72\n⚠️ ERRO HTTP $http_code AO CRIAR STACK - Usando docker deploy... \nXXX"
                docker stack deploy --prune --resolve-image always -c $nome_app.yaml $nome_app > /dev/null 2>&1
            fi
        else
            echo -e "XXX\n72\n⚠️ ERRO NA AUTENTICAÇÃO DO PORTAINER - Usando docker deploy... \nXXX"
            docker stack deploy --prune --resolve-image always -c $nome_app.yaml $nome_app > /dev/null 2>&1
        fi
    else
        echo -e "XXX\n72\n⚠️ ARQUIVO dados_portainer NÃO ENCONTRADO - Usando docker deploy... \nXXX"
        docker stack deploy --prune --resolve-image always -c $nome_app.yaml $nome_app > /dev/null 2>&1
    fi
else
    # Criar stack direto no Docker
    echo -e "XXX\n68\nCRIANDO STACK DIRETO NO DOCKER... \nXXX"
    docker stack deploy --prune --resolve-image always -c $nome_app.yaml $nome_app > /dev/null 2>&1
    echo -e "XXX\n72\n✅ STACK CRIADA COM SUCESSO! \nXXX"
fi

echo -e "XXX\n74\nSTACK EM DEPLOY... \nXXX"
sleep 3

echo -e "XXX\n76\nAGUARDANDO SERVIÇOS... \nXXX"

# Aguardar serviços ficarem prontos
for i in $(seq 1 60); do
    if docker service ls --filter "name=${nome_app}" --format "{{.Replicas}}" | grep -q "1/1"; then
        break
    fi
    sleep 5
    echo -e "XXX\n$((76 + (i * 5)/60))\nAGUARDANDO SERVIÇOS... ($i/60)\nXXX"
done

echo -e "XXX\n82\nCRIANDO USUARIO ADMIN... \nXXX"
sleep 1

# Aguardar prosody estar pronto
sleep 10

# Registrar usuario admin (usando nome do container com sufixo)
docker exec -t "$(docker ps --filter "name=${nome_app}_prosody" -q)" bash -c "prosodyctl --config /config/prosody.cfg.lua register $user_jitsi meet.jitsi $pass_jitsi" > /dev/null 2>&1

echo -e "XXX\n85\nUSUARIO CRIADO! \nXXX"
sleep 1

echo -e "XXX\n92\nINSTALAÇÃO CONCLUIDA! \nXXX"
sleep 1

}|whiptail --title "SETUPMNO" --gauge "Aguarde a instalação do Jitsi Meet" 6 60 0

clear

# Exibir dados finais
whiptail --title "JITSI MEET INSTALADO COM SUCESSO!" \
--msgbox "✅ JITSI MEET INSTALADO!\n\n📌 ACESSO: https://$url_jitsi\n\n👤 USUARIO: $user_jitsi\n\n🔑 SENHA: $pass_jitsi\n\n⚠️ Guarde estes dados!" \
--fb 14 70

cd /
cd

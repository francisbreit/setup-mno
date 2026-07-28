#!/usr/bin/bash
#########################################################
# # cloudflare tunnel - records automáticos
#   LOADING
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
    whiptail --title "INSTALAÇÃO DO SEARXNG" --msgbox "$msg" --fb 10 70
}

while true; do
CHOICE=$(
whiptail --title "INSTALAÇÃO DO SEARXNG" --menu "Aperte ENTER para iniciar a instalação ou selecione SAIR (Utilize setas e Enter)\n\nTIPO DE INSTALAÇÃO DETECTADA: $INSTALL_TYPE\n\nINSTRUÇÕES:\nAntes de prosseguir, verifique os registros DNS conforme seu tipo de instalação:" 20 70 2 \
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

# SOLICITAR URL DO SEARXNG
while true; do
    urlsearxng=$(whiptail --title "URL do SearXNG" --inputbox "Digite o Link de acesso (ex: buscar.seudominio.com):" --fb 12 60 3>&1 1>&2 2>&3)
    saida=$?
    if [[ $saida -eq '0' ]]; then
        if [[ -z $urlsearxng ]]; then 
            msg "Digite o link para poder continuar"
            continue
        else 
            break
        fi
    else
        echo $urlsearxng
        echo "saindo..."
        exit 0
    fi
done

auth_secret_hex=$(openssl rand -hex 32)
while true ; do
    auth_secret=$(whiptail --title "Auth Secret" --inputbox "Digite uma chave secreta para criptografia interna do buscador (sugestão gerada aleatoriamente: $auth_secret_hex):" --fb 12 75 3>&1 1>&2 2>&3) ; saida=$?
    if [[ $saida -eq '0' ]] ; then
        if [[ -z $auth_secret ]] ; then msg "Crie um Auth Secret para continuar" ; continue ; else break; fi
    else
        echo $auth_secret ; echo "saindo..."  &  exit 0 ;
    fi
done

# SOLICITAR SE CRIA STACK NO PORTAINER
while true; do
    criar_portainer=$(whiptail --title "Criar Stack no Portainer? - 0 ou 1" --inputbox "Digite 0 para poder editar stack no portainer ou 1 para não poder editar" --fb 12 60 3>&1 1>&2 2>&3)
    saida=$?
    if [[ $saida -eq '0' ]]; then
        if [[ "$criar_portainer" != "0" && "$criar_portainer" != "1" ]]; then 
            msg "Digite apenas o número 0 ou o número 1, para poder continuar."
            continue
        else 
            break
        fi
    else
        echo $criar_portainer
        echo "saindo..."
        exit 0
    fi
done

#########################################################
# VERIFICAÇÃO DE DADOS
#########################################################

nome_principal="searxng"
sufixo_app=$(date | md5sum | head -c7)
nome_app=$nome_principal$sufixo_app

{
  tput reset 2>/dev/null
  exec 0</dev/tty 1>/dev/tty 2>&1
  sleep 0.01
  clear
} || true

whiptail --title "Dados Fornecidos" \
 --msgbox "TIPO DE INSTALAÇÃO: $INSTALL_TYPE\n\nDados Preenchidos:\n\n1) Url: $urlsearxng\n2) Auth Secret: $auth_secret\n3) Criar Stack no Portainer: $([ "$criar_portainer" == "0" ] && echo "0 (Editável)" || echo "1 (Não editável)")\n\nConfira e Tecle Enter para continuar." \
 --fb 22 80

while true; do
    confirma1=$(whiptail --title "Confirmação" \
    --inputbox "Informações estão corretas? Digite 'y' para confirmar e instalar ou 'n' para voltar e corrigir:" \
    --fb 10 60 3>&1 1>&2 2>&3)
    
    if [[ "$confirma1" =~ ^[yY]$ ]]; then
        break
    elif [[ "$confirma1" =~ ^[nN]$ ]]; then
        msg "Você digitou N. Tecle Enter para sair da instalação"
        exit 0
    else
        msg "Entrada inválida! Por favor, use apenas 'y' ou 'n'."
    fi
done

#########################################################
# CRIAÇÃO DE DNS E ROTAS CLOUDFLARE TUNNEL
#########################################################
clear

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

if [ "$INSTALL_TYPE" = "TRADICIONAL" ] && [ "$criar_dns" = "0" ]; then
    echo -e "XXX\n10\nCONFIGURANDO DNS AUTOMÁTICO (TRADICIONAL)... \nXXX"
    DOMINIO_PRINCIPAL=$(echo "$urlsearxng" | cut -d'.' -f2-)
    
    EXISTING_RECORDS=$(curl -s -X GET \
        "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records?name=${urlsearxng}" \
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
        --data '{"type":"CNAME","name":"'${urlsearxng}'","content":"'${nome_servidor}'.'${DOMINIO_PRINCIPAL}'","ttl":1,"proxied":false}')

    if echo "$CNAME_RESPONSE" | grep -q '"success":true'; then
        echo -e "XXX\n30\nREGISTRO CNAME CRIADO COM SUCESSO! \nXXX"
    else
        echo -e "XXX\n30\nAVISO: ERRO AO CRIAR REGISTRO CNAME \nXXX"
    fi

elif [ "$INSTALL_TYPE" = "CLOUDFLARE_TUNNEL" ]; then
    echo -e "XXX\n10\nCONFIGURANDO CLOUDFLARE TUNNEL (DNS + ROTAS)... \nXXX"
    
    EXISTING_RECORDS=$(curl -s -X GET \
        "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records?name=${urlsearxng}" \
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

    DNS_RESPONSE=$(curl -s -X POST \
        "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records" \
        -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
        -H "Content-Type: application/json" \
        --data "{\"type\":\"CNAME\",\"name\":\"${urlsearxng}\",\"content\":\"${TUNNEL_ID}.cfargotunnel.com\",\"ttl\":1,\"proxied\":true}")

    echo -e "XXX\n35\nATUALIZANDO CONFIGURAÇÃO DO TUNNEL... \nXXX"
    NEW_SERVICE="http://${nome_app}-web:8080"
    
    TIMESTAMP=$(date -u +%Y%m%dT%H%M%SZ)
    TMPDIR=$(mktemp -d)
    BACKUP_RAW="$TMPDIR/backup_raw.$TIMESTAMP.json"
    TO_PUT="$TMPDIR/to_put.$TIMESTAMP.json"

    curl -sS -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
      "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/cfd_tunnel/$TUNNEL_ID/configurations" \
      | jq '.' > "$BACKUP_RAW"

    jq --arg host "$urlsearxng" --arg service "$NEW_SERVICE" '
      (.result.config // {}) as $cfg
      | ($cfg.ingress // []) as $ing
      | ($ing | map(select(.service != "http_status:404"))) as $clean
      
      | ($clean | map(select(.hostname != $host))) as $filtered
      | ($filtered + [ { hostname: $host, service: $service, originRequest: { noTlsVerify: true, httpHostHeader: $host } } ]) as $merged
      | ($merged + [{ service: "http_status:404" }]) as $final_ing
      | ($cfg + { ingress: $final_ing }) as $newcfg
      | { config: $newcfg }
    ' "$BACKUP_RAW" > "$TO_PUT"

    APPLY_RESPONSE=$(curl -sS -X PUT "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/cfd_tunnel/$TUNNEL_ID/configurations" \
      -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
      -H "Content-Type: application/json" \
      --data-binary @"$TO_PUT")

    rm -rf "$TMPDIR"

else
    echo -e "XXX\n10\nVERIFICANDO CONFIGURAÇÃO (TRADICIONAL SEM AUTOMAÇÃO)... \nXXX"
    if ! nslookup "$urlsearxng" >/dev/null 2>&1; then
        echo -e "XXX\n15\nAVISO: VERIFIQUE A CONFIGURAÇÃO DNS \nXXX"
    fi
fi

if [ "$INSTALL_TYPE" = "TRADICIONAL" ] && [ "$criar_dns" = "1" ]; then
    ip_servidor=$(curl -s --max-time 10 ipinfo.io/ip)
    echo -e "XXX\n3\nVERIFICANDO SUBDOMÍNIO: $urlsearxng \nXXX"
    sleep 3

    tentativas=5
    tentativa_atual=1
    sucesso=0

    while [ $tentativa_atual -le $tentativas ]; do
        echo -e "XXX\n$(( (tentativa_atual * 12) / tentativas + 3 ))\nTentativa $tentativa_atual de $tentativas...\nXXX"
        dns_ip=$(timeout 10 nslookup -type=A "$urlsearxng" | grep -E "Address: [0-9]+\." | awk '{print $2}' | head -n1)
        if [[ -n "$dns_ip" && "$dns_ip" == "$ip_servidor" ]]; then
            sucesso=1
            break
        fi
        sleep 1
        ((tentativa_atual++))
    done

    if [ $sucesso -eq 0 ]; then
        echo -e "XXX\n10\nERRO: SUBDOMÍNIO NÃO APONTA PARA O IP ($ip_servidor) \nXXX"
        sleep 3
        exit 1
    fi
fi

#######################################################
#  INSTALAÇÃO DO SEARXNG
#######################################################
echo -e "XXX\n65\nCRIANDO STACK DO SEARXNG... \nXXX"
cd ~/

cat > $nome_app.yaml << EOL
version: "3.9"

services:

  ${nome_app}-redis:
    image: redis:alpine
    hostname: ${nome_app}-redis
    container_name: ${nome_app}-redis
    restart: unless-stopped
    networks:
      - interna
    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
          - node.role == manager

  ${nome_app}-web:
    image: searxng/searxng:latest
    hostname: ${nome_app}-web
    container_name: ${nome_app}-web
    init: true
    restart: unless-stopped
    networks:
      - externa
      - interna
    volumes:
      - ${nome_app}-data:/etc/searxng
    ports:
      - "8880:8080"
    environment:
      - SEARXNG_BASE_URL=https://${urlsearxng}/
      - SEARXNG_SECRET=${auth_secret}
      - SEARXNG_REDIS_URL=redis://${nome_app}-redis:6379/0
    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
          - node.role == manager
EOL

if [ "$INSTALL_TYPE" = "TRADICIONAL" ]; then
cat >> $nome_app.yaml << EOL
      labels:
        - traefik.enable=true
        - traefik.docker.network=externa
        - traefik.http.routers.${nome_app}-web.rule=Host(\`${urlsearxng}\`)
        - traefik.http.routers.${nome_app}-web.entrypoints=websecure
        - traefik.http.routers.${nome_app}-web.priority=1
        - traefik.http.routers.${nome_app}-web.tls.certresolver=letsencryptresolver
        - traefik.http.routers.${nome_app}-web.service=${nome_app}-web
        - traefik.http.routers.${nome_app}-web.middlewares=websocket-headers@docker
        - traefik.http.services.${nome_app}-web.loadbalancer.server.port=8080
        - traefik.http.services.${nome_app}-web.loadbalancer.passHostHeader=true
        - traefik.http.middlewares.redirect-to-secure.redirectscheme.scheme=https
        - traefik.http.middlewares.websocket-headers.headers.customrequestheaders.X-Forwarded-Proto=https
        - traefik.http.middlewares.websocket-headers.headers.customrequestheaders.X-Forwarded-Port=443
EOL
fi

cat >> $nome_app.yaml << EOL

volumes:
  ${nome_app}-data:
    external: true
    name: ${nome_app}-data

networks:
  externa:
    external: true
  interna:
    external: true
EOL

echo -e "XXX\n70\nIMPLANTANDO SEARXNG... \nXXX"

if [[ "$criar_portainer" == "0" ]]; then
    echo -e "XXX\n76\nCRIANDO STACK NO PORTAINER 3/4  \nXXX"
    dados_file="$HOME/dados_portainer/dados_portainer"
    
    if [[ -f "$dados_file" ]]; then
        PORTAINER_URL=$(grep "Dominio do portainer:" "$dados_file" | cut -d':' -f2 | xargs)
        ADMIN_USERNAME=$(grep "Usuario:" "$dados_file" | cut -d':' -f2 | xargs)
        ADMIN_PASSWORD=$(grep "Senha:" "$dados_file" | cut -d':' -f2 | xargs)
        STACK_NAME=$nome_app
        STACK_FILE_PATH="/root/$nome_app.yaml"
    else
        docker stack deploy --prune --resolve-image always -c $nome_app.yaml $nome_app >/dev/null 2>&1
    fi

    get_auth_token() {
        RESPONSE=$(curl -sS -X POST "https://$PORTAINER_URL/api/auth" -H "Content-Type: application/json" -d "{\"username\": \"$ADMIN_USERNAME\", \"password\": \"$ADMIN_PASSWORD\"}")
        TOKEN=$(echo "$RESPONSE" | jq -r '.jwt')
        if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]; then
            docker stack deploy --prune --resolve-image always -c $nome_app.yaml $nome_app >/dev/null 2>&1
            return 1
        fi
    }

    get_endpoint_id() {
        RESPONSE=$(curl -sS -X GET "https://$PORTAINER_URL/api/endpoints" -H "Authorization: Bearer $TOKEN")
        ENDPOINT_ID=$(echo "$RESPONSE" | jq -r '.[0].Id')
    }

    get_swarm_id() {
        RESPONSE=$(curl -sS -X GET "https://$PORTAINER_URL/api/endpoints/$ENDPOINT_ID/docker/swarm" -H "Authorization: Bearer $TOKEN")
        SWARM_ID=$(echo "$RESPONSE" | jq -r '.ID')
    }

    create_stack() {
        response_output=$(mktemp)
        erro_output=$(mktemp)
        http_code=$(curl -s -o "$response_output" -w "%{http_code}"  -X POST \
            -H "Authorization: Bearer $TOKEN" \
            -F "Name=$STACK_NAME" -F "file=@$STACK_FILE_PATH" \
            -F "SwarmID=$SWARM_ID" -F "endpointId=$ENDPOINT_ID" \
            "https://$PORTAINER_URL/api/stacks/create/swarm/file" 2> "$erro_output")
        rm -f "$response_output" "$erro_output"
        
        if [ "$http_code" -ne 200 ]; then
            docker stack deploy --prune --resolve-image always -c $nome_app.yaml $nome_app >/dev/null 2>&1
        fi
    }

    if [[ -f "$dados_file" ]]; then
        get_auth_token && get_endpoint_id && get_swarm_id && create_stack
    fi

elif [[ "$criar_portainer" == "1" ]]; then
    docker stack deploy --prune --resolve-image always -c $nome_app.yaml $nome_app >/dev/null 2>&1
else
    docker stack deploy --prune --resolve-image always -c $nome_app.yaml $nome_app >/dev/null 2>&1
fi

#######################################################
# FINALIZANDO INSTALAÇÃO DO SEARXNG
#######################################################

echo -e "XXX\n85\nAGUARDANDO INICIALIZAÇÃO DOS CONTAINERS... \nXXX"
max_wait_time=300
wait_interval=5
elapsed_time=0

while [ $elapsed_time -lt $max_wait_time ]; do
    CONTAINER_ID=$(docker ps -qf name=${nome_app}-web)
    if [ -n "$CONTAINER_ID" ]; then break; fi
    sleep $wait_interval
    elapsed_time=$((elapsed_time + wait_interval))
done

if [ -z "$CONTAINER_ID" ]; then
    echo "O container não foi encontrado após $max_wait_time segundos."
    exit 1
fi

echo -e "XXX\n95\nFINALIZANDO CONFIGURAÇÕES... \nXXX"
sleep 5

echo -e "XXX\n98\nCONFIGURAÇÃO CONCLUÍDA... \nXXX"
echo -e "XXX\n100\nINSTALAÇÃO DO SEARXNG CONCLUÍDA! \nXXX"
sleep 3

}|whiptail --title "SEARXNG - PROGRESSO DA INSTALAÇÃO" --gauge "Aguarde a instalação" 6 60 0

#######################################################
# VERIFICAÇÃO FINAL E INSTRUÇÕES DE SETUP
#######################################################

TEXTO_ACESSO="👉 Acesse: https://$urlsearxng\n\nAgora os seus agentes de IA podem utilizar essa URL (no n8n, Flowise, Dify, etc) para fazer pesquisas na internet de forma 100% gratuita e privada!"

if [ "$INSTALL_TYPE" = "TRADICIONAL" ]; then
    ip_servidor=$(curl -s --max-time 10 ipinfo.io/ip)
    dns_ip=$(timeout 10 nslookup "$urlsearxng" | grep "Address" | tail -n1 | awk '{print $2}' 2>/dev/null)

    if [[ "$dns_ip" != "$ip_servidor" ]]; then
        whiptail --title "Mensagem" --msgbox "Não foi possivel acessar o dominio ($urlsearxng). A instalação foi cancelada. Por favor, verifique se os apontamentos DNS estão corretos e propagados!. Depois, instale novamente. Pressione ENTER para voltar ao Menu Principal" 20 78
    else
        whiptail --title "Instalação Concluída" --msgbox "Parabéns, SearXNG foi instalado com sucesso!\n\n$TEXTO_ACESSO\n\nPressione ENTER para voltar ao Menu Principal" 24 85
    fi
else
    if timeout 10 nslookup "$urlsearxng" >/dev/null 2>&1; then
        whiptail --title "Instalação Concluída" --msgbox "Parabéns, SearXNG foi instalado com sucesso!\n\nConfiguração Cloudflare Tunnel concluída com rotas e DNS.\n\n$TEXTO_ACESSO\n\nPressione ENTER para voltar ao Menu Principal" 24 85
    else
        whiptail --title "Mensagem" --msgbox "AVISO: O domínio ($urlsearxng) não está resolvendo.\nVerifique a configuração do Cloudflare Tunnel.\n\nA instalação foi concluída, mas o acesso pode não funcionar até que o DNS esteja configurado corretamente.\n\n$TEXTO_ACESSO\n\nPressione ENTER para voltar ao Menu Principal" 24 85
    fi
fi

exit 0

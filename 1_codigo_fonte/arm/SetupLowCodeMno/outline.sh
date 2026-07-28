#!/usr/bin/bash
# ============================================================
# INSTALAÇÃO DO OUTLINE (Wiki/Knowledge Base)
# ============================================================

# LOADING - Cores e funções auxiliares
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

msg() { echo -e "${RED}$1${NC}"; }

# DETECÇÃO DO TIPO DE INSTALAÇÃO
INSTALL_TYPE_FILE="/root/.cloudflared_config/installation_type"
if [ -f "$INSTALL_TYPE_FILE" ]; then
    INSTALL_TYPE=$(cat "$INSTALL_TYPE_FILE")
else
    INSTALL_TYPE="TRADICIONAL"
fi

# CARREGAMENTO DE CREDENCIAIS
if [ "$INSTALL_TYPE" = "CLOUDFLARE_TUNNEL" ]; then
    source "/root/.cloudflared_config/cloudflare_credentials"
else
    source "/root/.tradicional_config/tradicional_credentials"
fi

# MENU INICIAL
while true; do
    opcao=$(whiptail --title "INSTALAÇÃO DO OUTLINE" --menu "O que deseja fazer?" --fb 12 60 2 \
        "1" "Instalar Outline" \
        "2" "Sair" 3>&1 1>&2 2>&3)
    case $opcao in
        "1") break ;;
        "2") exit 0 ;;
        *) msg "Opção inválida" ;;
    esac
done

# COLETA DE DADOS
while true; do
    url_outline=$(whiptail --title "1/4 - URL do Outline" --inputbox "Digite o domínio (ex: wiki.dominio.com):" --fb 12 60 3>&1 1>&2 2>&3) ; saida=$?
    if [[ $saida -eq '0' ]]; then
        [[ -z $url_outline ]] && { msg "Digite o link do Outline"; continue; } || break
    else
        echo $url_outline; echo "saindo..." & exit 0
    fi
done

while true; do
    oidc_provider=$(whiptail --title "2/4 - Provedor OAuth" --menu "Selecione o provedor de autenticação:\n\n(O Outline NÃO tem login local. É obrigatório pelo menos 1 provedor OAuth.)" --fb 16 60 4 \
        "1" "OIDC (Keycloak)" \
        "2" "Google" \
        "3" "Slack" \
        "4" "Microsoft (Azure AD)" 3>&1 1>&2 2>&3) ; saida=$?
    if [[ $saida -eq '0' ]]; then
        [[ -z $oidc_provider ]] && { msg "Selecione uma opção"; continue; } || break
    else
        echo $oidc_provider; echo "saindo..." & exit 0
    fi
done

# Coletar credenciais do provedor selecionado
case $oidc_provider in
    "1") # OIDC (Keycloak)
        oidc_display_name="Keycloak"
        while true; do
            oidc_client_id=$(whiptail --title "OIDC - Client ID" --inputbox "Digite o Client ID do OIDC:" --fb 12 60 3>&1 1>&2 2>&3) ; saida=$?
            if [[ $saida -eq '0' ]]; then
                [[ -z $oidc_client_id ]] && { msg "Preencha o Client ID"; continue; } || break
            else exit 0; fi
        done
        while true; do
            oidc_client_secret=$(whiptail --title "OIDC - Client Secret" --inputbox "Digite o Client Secret do OIDC:" --fb 12 60 3>&1 1>&2 2>&3) ; saida=$?
            if [[ $saida -eq '0' ]]; then
                [[ -z $oidc_client_secret ]] && { msg "Preencha o Client Secret"; continue; } || break
            else exit 0; fi
        done
        while true; do
            oidc_auth_uri=$(whiptail --title "OIDC - Auth URI" --inputbox "URI de autorização (ex: https://auth.dominio.com/realms/master/protocol/openid-connect/auth):" --fb 12 80 3>&1 1>&2 2>&3) ; saida=$?
            if [[ $saida -eq '0' ]]; then
                [[ -z $oidc_auth_uri ]] && { msg "Preencha a Auth URI"; continue; } || break
            else exit 0; fi
        done
        while true; do
            oidc_token_uri=$(whiptail --title "OIDC - Token URI" --inputbox "URI do token (ex: https://auth.dominio.com/realms/master/protocol/openid-connect/token):" --fb 12 80 3>&1 1>&2 2>&3) ; saida=$?
            if [[ $saida -eq '0' ]]; then
                [[ -z $oidc_token_uri ]] && { msg "Preencha a Token URI"; continue; } || break
            else exit 0; fi
        done
        while true; do
            oidc_userinfo_uri=$(whiptail --title "OIDC - Userinfo URI" --inputbox "URI de userinfo (ex: https://auth.dominio.com/realms/master/protocol/openid-connect/userinfo):" --fb 12 80 3>&1 1>&2 2>&3) ; saida=$?
            if [[ $saida -eq '0' ]]; then
                [[ -z $oidc_userinfo_uri ]] && { msg "Preencha a Userinfo URI"; continue; } || break
            else exit 0; fi
        done
        oidc_logout_uri=""
        ;;
    "2") # Google
        oidc_display_name="Google"
        oidc_client_id=""
        oidc_client_secret=""
        oidc_auth_uri="https://accounts.google.com/o/oauth2/v2/auth"
        oidc_token_uri="https://oauth2.googleapis.com/token"
        oidc_userinfo_uri="https://www.googleapis.com/oauth2/v3/userinfo"
        oidc_logout_uri=""
        while true; do
            oidc_client_id=$(whiptail --title "Google - Client ID" --inputbox "Digite o Client ID do Google OAuth:" --fb 12 60 3>&1 1>&2 2>&3) ; saida=$?
            if [[ $saida -eq '0' ]]; then
                [[ -z $oidc_client_id ]] && { msg "Preencha o Client ID"; continue; } || break
            else exit 0; fi
        done
        while true; do
            oidc_client_secret=$(whiptail --title "Google - Client Secret" --inputbox "Digite o Client Secret do Google OAuth:" --fb 12 60 3>&1 1>&2 2>&3) ; saida=$?
            if [[ $saida -eq '0' ]]; then
                [[ -z $oidc_client_secret ]] && { msg "Preencha o Client Secret"; continue; } || break
            else exit 0; fi
        done
        ;;
    "3") # Slack
        oidc_display_name="Slack"
        oidc_auth_uri=""
        oidc_token_uri=""
        oidc_userinfo_uri=""
        oidc_logout_uri=""
        while true; do
            oidc_client_id=$(whiptail --title "Slack - Client ID" --inputbox "Digite o Client ID do Slack:" --fb 12 60 3>&1 1>&2 2>&3) ; saida=$?
            if [[ $saida -eq '0' ]]; then
                [[ -z $oidc_client_id ]] && { msg "Preencha o Client ID"; continue; } || break
            else exit 0; fi
        done
        while true; do
            oidc_client_secret=$(whiptail --title "Slack - Client Secret" --inputbox "Digite o Client Secret do Slack:" --fb 12 60 3>&1 1>&2 2>&3) ; saida=$?
            if [[ $saida -eq '0' ]]; then
                [[ -z $oidc_client_secret ]] && { msg "Preencha o Client Secret"; continue; } || break
            else exit 0; fi
        done
        ;;
    "4") # Microsoft
        oidc_display_name="Microsoft"
        oidc_auth_uri="https://login.microsoftonline.com/common/oauth2/v2.0/authorize"
        oidc_token_uri="https://login.microsoftonline.com/common/oauth2/v2.0/token"
        oidc_userinfo_uri="https://graph.microsoft.com/v1.0/me"
        oidc_logout_uri=""
        while true; do
            oidc_client_id=$(whiptail --title "Microsoft - Client ID" --inputbox "Digite o Application (Client) ID:" --fb 12 60 3>&1 1>&2 2>&3) ; saida=$?
            if [[ $saida -eq '0' ]]; then
                [[ -z $oidc_client_id ]] && { msg "Preencha o Client ID"; continue; } || break
            else exit 0; fi
        done
        while true; do
            oidc_client_secret=$(whiptail --title "Microsoft - Client Secret" --inputbox "Digite o Client Secret:" --fb 12 60 3>&1 1>&2 2>&3) ; saida=$?
            if [[ $saida -eq '0' ]]; then
                [[ -z $oidc_client_secret ]] && { msg "Preencha o Client Secret"; continue; } || break
            else exit 0; fi
        done
        ;;
esac

# Pergunta Portainer
while true; do
    criar_portainer=$(whiptail --title "4/4 - Criar Stack no Portainer?" --inputbox "Digite 0 para criar stack editável no Portainer ou 1 para criar direto no Docker:" --fb 12 60 3>&1 1>&2 2>&3) ; saida=$?
    if [[ $saida -eq '0' ]]; then
        if [[ "$criar_portainer" != "0" && "$criar_portainer" != "1" ]]; then msg "Digite apenas 0 ou 1"; continue; else break; fi
    else
        echo $criar_portainer; echo "saindo..." & exit 0
    fi
done

# TELA DE CONFIRMAÇÃO
clear
{
    tput reset 2>/dev/null
    exec 0</dev/tty 1>/dev/tty 2>&1
    sleep 0.01
    clear
} || true

whiptail --title "Dados Fornecidos" \
    --msgbox "TIPO DE INSTALAÇÃO: $INSTALL_TYPE\n\nDados Preenchidos:\n\n1) URL do Outline: $url_outline\n2) Provedor OAuth: $oidc_display_name\n3) Criar Stack no Portainer: $([ "$criar_portainer" == "0" ] && echo "0 (Editável)" || echo "1 (Não editável)")\n\nConfira e Tecle Enter para continuar." \
    --fb 18 70

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
    if [[ $confirma1 =~ ^[yY]$ ]]; then
        break
    elif [[ $confirma1 =~ ^[nN]$ ]]; then
        msg "Você digitou N e não confirmou os dados preenchidos. Tecle Enter para sair da instalação"
        exit 0
    else
        msg "Entrada inválida! Por favor, use apenas 'y' para sim ou 'n' para não."
    fi
done

# CRIAR USUARIO E BANCO NO POSTGRESQL COMPARTILHADO
# (ANTES do gauge para garantir execução)
outline_secret=$(openssl rand -hex 32)
outline_utils=$(openssl rand -hex 32)

container_id=$(docker ps -qf name=postgres)
docker exec $container_id psql -U postgres -d postgres -c "DROP DATABASE IF EXISTS outline;" >/dev/null 2>&1
docker exec $container_id psql -U postgres -d postgres -c "DROP USER IF EXISTS outline;" >/dev/null 2>&1
docker exec $container_id psql -U postgres -d postgres -c "CREATE USER outline WITH PASSWORD '${outline_secret}';" >/dev/null 2>&1
docker exec $container_id psql -U postgres -d postgres -c "CREATE DATABASE outline OWNER outline;" >/dev/null 2>&1
docker exec $container_id psql -U postgres -d postgres -c "GRANT ALL PRIVILEGES ON DATABASE outline TO outline;" >/dev/null 2>&1
docker exec $container_id psql -U postgres -d outline -c "GRANT ALL ON SCHEMA public TO outline;" >/dev/null 2>&1

# GERAR SUFIXO ÚNICO
nome_principal="outline"
sufixo_app=$(date | md5sum | head -c7)
nome_app=$nome_principal$sufixo_app

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

echo -e "XXX\n5\nVERIFICANDO CONFIGURAÇÃO... \nXXX"

if [ "$INSTALL_TYPE" = "TRADICIONAL" ]; then
    echo -e "XXX\n10\nCONFIGURANDO DNS AUTOMÁTICO (TRADICIONAL)... \nXXX"
    DOMINIO_PRINCIPAL=$(echo "$url_outline" | cut -d'.' -f2-)

    echo -e "XXX\n15\nVERIFICANDO REGISTROS EXISTENTES... \nXXX"
    EXISTING_RECORDS=$(curl -s -X GET \
        "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records?name=${url_outline}" \
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
        --data '{"type":"CNAME","name":"'${url_outline}'","content":"'${nome_servidor}'.'${DOMINIO_PRINCIPAL}'","ttl":1,"proxied":false}')
    if echo "$CNAME_RESPONSE" | grep -q '"success":true'; then
        echo -e "XXX\n30\nREGISTRO CNAME CRIADO COM SUCESSO! \nXXX"
    else
        echo -e "XXX\n30\nAVISO: ERRO AO CRIAR REGISTRO CNAME \nXXX"
    fi

elif [ "$INSTALL_TYPE" = "CLOUDFLARE_TUNNEL" ]; then
    echo -e "XXX\n10\nCONFIGURANDO CLOUDFLARE TUNNEL (DNS + ROTAS)... \nXXX"
    DOMINIO_PRINCIPAL=$(echo "$url_outline" | cut -d'.' -f2-)

    echo -e "XXX\n15\nCONFIGURANDO REGISTRO DNS... \nXXX"
    EXISTING_RECORDS=$(curl -s -X GET \
        "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records?name=${url_outline}" \
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
        --data "{\"type\":\"CNAME\",\"name\":\"${url_outline}\",\"content\":\"${TUNNEL_ID}.cfargotunnel.com\",\"ttl\":1,\"proxied\":true}")
    if echo "$DNS_RESPONSE" | grep -q '"success":true'; then
        echo -e "XXX\n30\nREGISTRO DNS CRIADO COM SUCESSO! \nXXX"
    else
        echo -e "XXX\n30\nAVISO: ERRO AO CRIAR REGISTRO DNS \nXXX"
    fi

    echo -e "XXX\n35\nATUALIZANDO CONFIGURAÇÃO DO TUNNEL... \nXXX"
    NEW_SERVICE="http://${nome_app}:3000"

    TIMESTAMP=$(date -u +%Y%m%dT%H%M%SZ)
    TMPDIR=$(mktemp -d)
    BACKUP_RAW="$TMPDIR/backup_raw.$TIMESTAMP.json"
    TO_PUT="$TMPDIR/to_put.$TIMESTAMP.json"

    curl -sS -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
        "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/cfd_tunnel/$TUNNEL_ID/configurations" \
        | jq '.' > "$BACKUP_RAW"

    jq --arg host "$url_outline" --arg service "$NEW_SERVICE" '
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

    if echo "$APPLY_RESPONSE" | grep -q '"success":true'; then
        echo -e "XXX\n40\nTUNNEL ATUALIZADO COM SUCESSO! \nXXX"
    else
        echo -e "XXX\n40\nAVISO: ERRO AO ATUALIZAR TUNNEL \nXXX"
    fi
fi

echo -e "XXX\n50\nGERANDO CHAVES DE SEGURANÇA... \nXXX"
sleep 1

echo -e "XXX\n60\nCRIANDO BANCO DE DADOS... \nXXX"
sleep 1

echo -e "XXX\n70\nCRIANDO STACK DO OUTLINE... \nXXX"

# CONSTRUIR URL DE CALLBACK CONFORME PROVEDOR
case $oidc_provider in
    "1") # OIDC
        OIDC_REDIRECT_URI="https://${url_outline}/auth/oidc.callback"
        ;;
    "2") # Google
        OIDC_REDIRECT_URI="https://${url_outline}/auth/google.callback"
        ;;
    "3") # Slack
        OIDC_REDIRECT_URI=""
        ;;
    "4") # Microsoft
        OIDC_REDIRECT_URI="https://${url_outline}/auth/azure-ad.callback"
        ;;
esac

# FIM DE MENSAGEM DE INSTALANDO
#
#######################################################
#
#  INSTALANDO O OUTLINE
#

cd
cd

cat > $nome_app.yaml << EOL

version: "3.7"
services:
  $nome_app:
    image: outlinewiki/outline:latest
    hostname: $nome_app
    networks:
      - externa
      - interna
    environment:
      - NODE_ENV=production
      - SECRET_KEY=$outline_secret
      - UTILS_SECRET=$outline_utils
      - URL=https://$url_outline
      - PORT=3000
      - FORCE_HTTPS=true
      - DATABASE_URL=postgres://outline:${outline_secret}@postgres:5432/outline
      - DATABASE_CONNECTION_POOL_MIN=0
      - DATABASE_CONNECTION_POOL_MAX=10
      - PGSSLMODE=disable
      - REDIS_URL=redis://${nome_app}_redis:6379
      - FILE_STORAGE=local
      - FILE_STORAGE_LOCAL_ROOT_DIR=/var/lib/outline/data
      - DEFAULT_LANGUAGE=pt_BR
      - WEB_CONCURRENCY=1
      - LOG_LEVEL=info
EOL

# ADICIONAR CONFIGURAÇÕES DO PROVEDOR OIDC
case $oidc_provider in
    "1") # OIDC (Keycloak)
cat >> $nome_app.yaml << EOL
      - OIDC_CLIENT_ID=$oidc_client_id
      - OIDC_CLIENT_SECRET=$oidc_client_secret
      - OIDC_AUTH_URI=$oidc_auth_uri
      - OIDC_TOKEN_URI=$oidc_token_uri
      - OIDC_USERINFO_URI=$oidc_userinfo_uri
      - OIDC_SCOPES=openid profile email
      - OIDC_USERNAME_CLAIM=preferred_username
      - OIDC_DISPLAY_NAME=$oidc_display_name
EOL
        ;;
    "2") # Google
cat >> $nome_app.yaml << EOL
      - GOOGLE_CLIENT_ID=$oidc_client_id
      - GOOGLE_CLIENT_SECRET=$oidc_client_secret
EOL
        ;;
    "3") # Slack
cat >> $nome_app.yaml << EOL
      - SLACK_CLIENT_ID=$oidc_client_id
      - SLACK_CLIENT_SECRET=$oidc_client_secret
EOL
        ;;
    "4") # Microsoft
cat >> $nome_app.yaml << EOL
      - AZURE_CLIENT_ID=$oidc_client_id
      - AZURE_CLIENT_SECRET=$oidc_client_secret
EOL
        ;;
esac

cat >> $nome_app.yaml << EOL
    volumes:
      - ${nome_app}_data:/var/lib/outline/data
    depends_on:
      - ${nome_app}_redis
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

  ${nome_app}_redis:
    image: redis:7-alpine
    hostname: ${nome_app}_redis
    networks:
      - interna
    volumes:
      - ${nome_app}_redis:/data
    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
        - node.role == manager
      resources:
        limits:
          cpus: "0.5"
          memory: 256M
EOL

# LABELS TRAEFIK (APENAS PARA TRADICIONAL)
if [ "$INSTALL_TYPE" = "TRADICIONAL" ]; then
cat >> $nome_app.yaml << EOL
      labels:
      - traefik.enable=true
      - traefik.docker.network=externa
      - traefik.http.routers.${nome_app}.rule=Host(\`${url_outline}\`)
      - traefik.http.routers.${nome_app}.entrypoints=websecure
      - traefik.http.routers.${nome_app}.priority=1
      - traefik.http.routers.${nome_app}.tls.certresolver=letsencryptresolver
      - traefik.http.routers.${nome_app}.tls=true
      - traefik.http.routers.${nome_app}.service=${nome_app}
      - traefik.http.services.${nome_app}.loadbalancer.server.port=3000
EOL
fi

cat >> $nome_app.yaml << EOL

networks:
  externa:
    external: true
  interna:
    external: true

volumes:
  ${nome_app}_data:
    external: true
    name: ${nome_app}_data
  ${nome_app}_redis:
    external: true
    name: ${nome_app}_redis
EOL

# DEPLOY
if [[ "$criar_portainer" == "0" ]]; then
    echo -e "XXX\n76\nCRIANDO STACK NO PORTAINER... \nXXX"

    dados_file="$HOME/dados_portainer/dados_portainer"

    if [[ -f "$dados_file" ]]; then
        PORTAINER_URL=$(grep "Dominio do portainer:" "$dados_file" | cut -d':' -f2 | xargs)
        ADMIN_USERNAME=$(grep "Usuario:" "$dados_file" | cut -d':' -f2 | xargs)
        ADMIN_PASSWORD=$(grep "Senha:" "$dados_file" | cut -d':' -f2 | xargs)
        STACK_NAME=$nome_app
        STACK_FILE_PATH="/root/$nome_app.yaml"
    else
        echo -e "XXX\n77\nSEM ARQUIVO DE DADOS DO PORTAINER \nXXX"
        docker stack deploy --prune --resolve-image always -c $nome_app.yaml $nome_app >/dev/null 2>&1
        exit 1
    fi

    get_auth_token() {
        echo -e "XXX\n77\nAUTENTICANDO NO PORTAINER... \nXXX"
        RESPONSE=$(curl -sS -X POST "https://$PORTAINER_URL/api/auth" \
            -H "Content-Type: application/json" \
            -d "{\"username\": \"$ADMIN_USERNAME\", \"password\": \"$ADMIN_PASSWORD\"}")
        TOKEN=$(echo "$RESPONSE" | jq -r '.jwt')
        if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]; then
            docker stack deploy --prune --resolve-image always -c $nome_app.yaml $nome_app >/dev/null 2>&1
            exit 1
        fi
    }

    get_endpoint_id() {
        echo -e "XXX\n80\nOBTENDO ENDPOINT ID... \nXXX"
        RESPONSE=$(curl -sS -X GET "https://$PORTAINER_URL/api/endpoints" \
            -H "Authorization: Bearer $TOKEN")
        ENDPOINT_ID=$(echo "$RESPONSE" | jq -r '.[0].Id')
        if [ -z "$ENDPOINT_ID" ] || [ "$ENDPOINT_ID" = "null" ]; then
            docker stack deploy --prune --resolve-image always -c $nome_app.yaml $nome_app >/dev/null 2>&1
            exit 1
        fi
    }

    get_swarm_id() {
        echo -e "XXX\n83\nOBTENDO SWARM ID... \nXXX"
        RESPONSE=$(curl -sS -X GET "https://$PORTAINER_URL/api/endpoints/$ENDPOINT_ID/docker/swarm" \
            -H "Authorization: Bearer $TOKEN")
        SWARM_ID=$(echo "$RESPONSE" | jq -r '.ID')
        if [ -z "$SWARM_ID" ] || [ "$SWARM_ID" = "null" ]; then
            docker stack deploy --prune --resolve-image always -c $nome_app.yaml $nome_app >/dev/null 2>&1
            exit 1
        fi
    }

    create_stack() {
        echo -e "XXX\n86\nCRIANDO STACK $STACK_NAME NO PORTAINER... \nXXX"
        if [ ! -f "$STACK_FILE_PATH" ]; then
            docker stack deploy --prune --resolve-image always -c $nome_app.yaml $nome_app >/dev/null 2>&1
            exit 1
        fi
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
            docker stack deploy --prune --resolve-image always -c $nome_app.yaml $nome_app >/dev/null 2>&1
            exit 1
        fi
    }

    get_auth_token || exit 1
    get_endpoint_id || exit 1
    get_swarm_id || exit 1
    create_stack || exit 1

elif [[ "$criar_portainer" == "1" ]]; then
    docker stack deploy --prune --resolve-image always -c $nome_app.yaml $nome_app >/dev/null 2>&1
else
    docker stack deploy --prune --resolve-image always -c $nome_app.yaml $nome_app >/dev/null 2>&1
    exit 1
fi

echo -e "XXX\n95\nFINALIZANDO BUILD DO OUTLINE... \nXXX"
sleep 12
echo -e "XXX\n100\nINSTALAÇÃO CONCLUÍDA! \nXXX"
sleep 3

}|whiptail --title "OUTLINE - PROGRESSO DA INSTALAÇÃO" --gauge "Aguarde a instalação dos itens necessários" 6 60 0

# VERIFICAÇÃO FINAL
if [ "$INSTALL_TYPE" = "TRADICIONAL" ]; then
    ip_servidor=$(curl -s --max-time 10 ipinfo.io/ip)
    dns_ip=$(timeout 10 nslookup "$url_outline" | grep "Address" | tail -n1 | awk '{print $2}' 2>/dev/null)
    if [[ "$dns_ip" != "$ip_servidor" ]]; then
        whiptail --title "Mensagem" --msgbox "Não foi possível acessar o domínio do Outline ($url_outline). Verifique os apontamentos DNS. Pressione ENTER para voltar ao Menu Principal" 20 78
    else
        whiptail --title "Mensagem" --msgbox "Parabéns, Outline foi instalado com sucesso!\n\nAcesse: https://$url_outline\nProvedor: $oidc_display_name\n\n⚠️ Configure o OAuth no provedor com o redirect URI:\n$OIDC_REDIRECT_URI\n\nPressione ENTER para voltar ao Menu Principal" 22 78
    fi
else
    if nslookup "$url_outline" >/dev/null 2>&1; then
        whiptail --title "Mensagem" --msgbox "Parabéns, Outline foi instalado com sucesso!\n\nAcesse: https://$url_outline\nProvedor: $oidc_display_name\n\n⚠️ Configure o OAuth no provedor com o redirect URI:\n$OIDC_REDIRECT_URI\n\nPressione ENTER para voltar ao Menu Principal" 22 78
    else
        whiptail --title "Mensagem" --msgbox "AVISO: O domínio do Outline ($url_outline) não está resolvendo.\nVerifique a configuração do Cloudflare Tunnel.\n\nPressione ENTER para voltar ao Menu Principal" 20 78
    fi
fi

exit 0

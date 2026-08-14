#!/usr/bin/bash
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'
msg() { echo -e "${RED}$1${NC}"; }

INSTALL_TYPE_FILE="/root/.cloudflared_config/installation_type"
if [ -f "$INSTALL_TYPE_FILE" ]; then
    INSTALL_TYPE=$(cat "$INSTALL_TYPE_FILE")
else
    INSTALL_TYPE="TRADICIONAL"
fi

if [ "$INSTALL_TYPE" = "CLOUDFLARE_TUNNEL" ]; then
    source "${SETUPMNO_CLOUDFLARE_CREDENTIALS_FILE:-/root/.cloudflared_config/cloudflare_credentials}"
else
    source "${SETUPMNO_TRADITIONAL_CREDENTIALS_FILE:-/root/.tradicional_config/tradicional_credentials}"
fi

while true; do
    opcao=$(whiptail --title "INSTALAÇÃO DO HOME ASSISTANT" --menu "O que deseja fazer?" --fb 12 60 2 \
        "1" "Instalar Home Assistant" \
        "2" "Sair" 3>&1 1>&2 2>&3)
    case $opcao in
        "1") break ;;
        "2") exit 0 ;;
        *) msg "Opção inválida" ;;
    esac
done

while true; do
    url_app=$(whiptail --title "1/2 - URL do Home Assistant" --inputbox "Digite o domínio (ex: home.dominio.com):" --fb 12 60 3>&1 1>&2 2>&3) ; saida=$?
    if [[ $saida -eq '0' ]]; then
        [[ -z $url_app ]] && { msg "Digite o link do Home Assistant"; continue; } || break
    else
        echo $url_app; echo "saindo..." & exit 0
    fi
done

while true; do
    criar_portainer=$(whiptail --title "2/2 - Criar Stack no Portainer?" --inputbox "Digite 0 para criar stack editável no Portainer ou 1 para criar direto no Docker:" --fb 12 60 3>&1 1>&2 2>&3) ; saida=$?
    if [[ $saida -eq '0' ]]; then
        if [[ "$criar_portainer" != "0" && "$criar_portainer" != "1" ]]; then msg "Digite apenas 0 ou 1"; continue; else break; fi
    else
        echo $criar_portainer; echo "saindo..." & exit 0
    fi
done

clear
{
    tput reset 2>/dev/null
    exec 0</dev/tty 1>/dev/tty 2>&1
    sleep 0.01
    clear
} || true

whiptail --title "Dados Fornecidos" \
    --msgbox "TIPO DE INSTALAÇÃO: $INSTALL_TYPE\n\nDados Preenchidos:\n\n1) URL do Home Assistant: $url_app\n2) Criar Stack no Portainer: $([ "$criar_portainer" == "0" ] && echo "0 (Editável)" || echo "1 (Não editável)")\n\nConfira e Tecle Enter para continuar." \
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

nome_principal="homeassistant"
sufixo_app=$(date | md5sum | head -c7)
nome_app=$nome_principal$sufixo_app

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
    DOMINIO_PRINCIPAL="${SETUPMNO_SELECTED_ROOT_DOMAIN:-${SETUPMNO_DOMAIN_ROOT:-${CLOUDFLARE_ZONE_NAME:-}}}"

    echo -e "XXX\n15\nVERIFICANDO REGISTROS EXISTENTES... \nXXX"
    EXISTING_RECORDS=$(curl -s -X GET \
        "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records?name=${url_app}" \
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
        --data '{"type":"CNAME","name":"'${url_app}'","content":"'${nome_servidor}'.'${DOMINIO_PRINCIPAL}'","ttl":1,"proxied":false}')
    if echo "$CNAME_RESPONSE" | grep -q '"success":true'; then
        echo -e "XXX\n30\nREGISTRO CNAME CRIADO COM SUCESSO! \nXXX"
    else
        echo -e "XXX\n30\nAVISO: ERRO AO CRIAR REGISTRO CNAME \nXXX"
    fi

elif [ "$INSTALL_TYPE" = "CLOUDFLARE_TUNNEL" ]; then
    echo -e "XXX\n10\nCONFIGURANDO CLOUDFLARE TUNNEL (DNS + ROTAS)... \nXXX"
    DOMINIO_PRINCIPAL="${SETUPMNO_SELECTED_ROOT_DOMAIN:-${SETUPMNO_DOMAIN_ROOT:-${CLOUDFLARE_ZONE_NAME:-}}}"

    echo -e "XXX\n15\nVERIFICANDO REGISTRO DNS... \nXXX"
    EXISTING_RECORDS=$(curl -s -X GET \
        "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records?name=${url_app}" \
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
        --data "{\"type\":\"CNAME\",\"name\":\"${url_app}\",\"content\":\"${TUNNEL_ID}.cfargotunnel.com\",\"ttl\":1,\"proxied\":true}")
    if echo "$DNS_RESPONSE" | grep -q '"success":true'; then
        echo -e "XXX\n30\nREGISTRO DNS CRIADO COM SUCESSO! \nXXX"
    else
        echo -e "XXX\n30\nAVISO: ERRO AO CRIAR REGISTRO DNS \nXXX"
    fi

    echo -e "XXX\n35\nATUALIZANDO CONFIGURAÇÃO DO TUNNEL... \nXXX"
    NEW_SERVICE="http://${nome_app}:8123"

    TIMESTAMP=$(date -u +%Y%m%dT%H%M%SZ)
    TMPDIR=$(mktemp -d)
    BACKUP_RAW="$TMPDIR/backup_raw.$TIMESTAMP.json"
    TO_PUT="$TMPDIR/to_put.$TIMESTAMP.json"

    curl -sS -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
        "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/cfd_tunnel/$TUNNEL_ID/configurations" \
        | jq '.' > "$BACKUP_RAW"

    jq --arg host "$url_app" --arg service "$NEW_SERVICE" '
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

echo -e "XXX\n50\nCRIANDO VOLUME DE CONFIGURAÇÃO... \nXXX"
docker volume create ${nome_app}_config >/dev/null 2>&1 || true

echo -e "XXX\n60\nCRIANDO STACK DO HOME ASSISTANT... \nXXX"

cd
cd

cat > $nome_app.yaml << EOL

version: "3.7"
services:
  ${nome_app}:
    image: ghcr.io/home-assistant/home-assistant:stable
    hostname: ${nome_app}
    networks:
      - externa
      - interna
    environment:
      - TZ=America/Sao_Paulo
    volumes:
      - ${nome_app}_config:/config
    command:
      - sh
      - -c
      - |
        if [ ! -f /config/configuration.yaml ]; then
          echo "default_config:" > /config/configuration.yaml
          echo "" >> /config/configuration.yaml
          echo "http:" >> /config/configuration.yaml
          echo "  use_x_forwarded_for: true" >> /config/configuration.yaml
          echo "  trusted_proxies:" >> /config/configuration.yaml
          echo "    - 10.0.0.0/8" >> /config/configuration.yaml
          echo "    - 172.16.0.0/12" >> /config/configuration.yaml
          echo "    - 192.168.0.0/16" >> /config/configuration.yaml
        fi
        exec /init
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
      - traefik.docker.network=externa
      - traefik.http.routers.${nome_app}.rule=Host(\`${url_app}\`)
      - traefik.http.routers.${nome_app}.entrypoints=websecure
      - traefik.http.routers.${nome_app}.priority=1
      - traefik.http.routers.${nome_app}.tls.certresolver=letsencryptresolver
      - traefik.http.routers.${nome_app}.tls=true
      - traefik.http.routers.${nome_app}.service=${nome_app}
      - traefik.http.services.${nome_app}.loadbalancer.server.port=8123
EOL
fi

cat >> $nome_app.yaml << EOL

networks:
  externa:
    external: true
  interna:
    external: true

volumes:
  ${nome_app}_config:
    external: true
    name: ${nome_app}_config
EOL

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

echo -e "XXX\n95\nAGUARDANDO SERVIÇOS INICIAREM... \nXXX"
sleep 30

echo -e "XXX\n100\nINSTALAÇÃO CONCLUÍDA! \nXXX"
sleep 2

}|whiptail --title "HOME ASSISTANT - PROGRESSO DA INSTALAÇÃO" --gauge "Aguarde a instalação dos itens necessários" 6 60 0

whiptail --title "✅ Instalação Concluída" \
    --msgbox "Parabéns, Home Assistant foi instalado com sucesso!\n\n🌐 Acesse: https://$url_app\n\nNo primeiro acesso, crie sua conta de administrador.\n\n⚠️ A configuração inicial é feita via web UI. O banco SQLite padrão está em /config.\n\nPressione ENTER para voltar ao Menu Principal" \
    --fb 18 70

exit 0

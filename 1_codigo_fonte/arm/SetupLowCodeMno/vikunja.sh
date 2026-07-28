#!/usr/bin/bash
# ============================================================
# INSTALAÇÃO DO VIKUNJA (To-Do / Kanban - Todoist Alternative)
# ============================================================

RED='\033[0;31m'
NC='\033[0m'
msg() { echo -e "${RED}$1${NC}"; }

INSTALL_TYPE_FILE="/root/.cloudflared_config/installation_type"
if [ -f "$INSTALL_TYPE_FILE" ]; then INSTALL_TYPE=$(cat "$INSTALL_TYPE_FILE"); else INSTALL_TYPE="TRADICIONAL"; fi

if [ "$INSTALL_TYPE" = "CLOUDFLARE_TUNNEL" ]; then source "/root/.cloudflared_config/cloudflare_credentials"
else source "/root/.tradicional_config/tradicional_credentials"; fi

while true; do
    opcao=$(whiptail --title "INSTALAÇÃO DO VIKUNJA" --menu "O que deseja fazer?" --fb 12 60 2 "1" "Instalar Vikunja" "2" "Sair" 3>&1 1>&2 2>&3)
    case $opcao in "1") break;; "2") exit 0;; *) msg "Opção inválida";; esac
done

while true; do
    url_vikunja=$(whiptail --title "1/3 - URL do Vikunja" --inputbox "Digite o domínio (ex: tasks.dominio.com):" --fb 12 60 3>&1 1>&2 2>&3) ; saida=$?
    if [[ $saida -eq '0' ]]; then [[ -z $url_vikunja ]] && { msg "Digite o link"; continue; } || break
    else echo $url_vikunja; echo "saindo..." & exit 0; fi
done

while true; do
    criar_portainer=$(whiptail --title "2/3 - Criar Stack no Portainer?" --inputbox "Digite 0 (Portainer) ou 1 (Docker):" --fb 12 60 3>&1 1>&2 2>&3) ; saida=$?
    if [[ $saida -eq '0' ]]; then
        if [[ "$criar_portainer" != "0" && "$criar_portainer" != "1" ]]; then msg "Digite 0 ou 1"; continue; else break; fi
    else echo $criar_portainer; echo "saindo..." & exit 0; fi
done

# GERAR SENHA E SUFIXO
vikunja_db_pass=$(openssl rand -hex 32)
vikunja_jwt=$(openssl rand -hex 32)
nome_principal="vikunja"
sufixo_app=$(date | md5sum | head -c7)
nome_app=$nome_principal$sufixo_app

# CRIAR USUARIO E BANCO NO POSTGRESQL COMPARTILHADO
container_id=$(docker ps -qf name=postgres)
docker exec $container_id psql -U postgres -d postgres -c "DROP DATABASE IF EXISTS vikunja;" >/dev/null 2>&1
docker exec $container_id psql -U postgres -d postgres -c "DROP USER IF EXISTS vikunja;" >/dev/null 2>&1
docker exec $container_id psql -U postgres -d postgres -c "CREATE USER vikunja WITH PASSWORD '${vikunja_db_pass}';" >/dev/null 2>&1
docker exec $container_id psql -U postgres -d postgres -c "CREATE DATABASE vikunja OWNER vikunja;" >/dev/null 2>&1
docker exec $container_id psql -U postgres -d postgres -c "GRANT ALL PRIVILEGES ON DATABASE vikunja TO vikunja;" >/dev/null 2>&1
docker exec $container_id psql -U postgres -d vikunja -c "GRANT ALL ON SCHEMA public TO vikunja;" >/dev/null 2>&1

clear
{ tput reset 2>/dev/null; exec 0</dev/tty 1>/dev/tty 2>&1; sleep 0.01; clear; } || true
whiptail --title "Dados Fornecidos" \
    --msgbox "TIPO: $INSTALL_TYPE\n\n1) URL: $url_vikunja\n2) Portainer: $([ "$criar_portainer" == "0" ] && echo "0 (Editável)" || echo "1 (Docker)")\n\nTecle Enter." --fb 12 70

while true; do
    { tput reset 2>/dev/null; exec 0</dev/tty 1>/dev/tty 2>&1; sleep 0.01; clear; } || true
    confirma1=$(whiptail --title "Confirmação" --inputbox "Confirmar? (y/n):" --fb 10 60 3>&1 1>&2 2>&3)
    if [[ $confirma1 =~ ^[yY]$ ]]; then break; elif [[ $confirma1 =~ ^[nN]$ ]]; then exit 0; else msg "Use 'y' ou 'n'"; fi
done

export NEWT_COLORS='root=,white window=,black border=white,black textbox=white,black button=black,white'

clear
{
echo -e "XXX\n5\nCONFIGURANDO... \nXXX"

if [ "$INSTALL_TYPE" = "TRADICIONAL" ]; then
    DOMINIO_PRINCIPAL=$(echo "$url_vikunja" | cut -d'.' -f2-)
    EXISTING_RECORDS=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records?name=${url_vikunja}" \
        -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" -H "Content-Type: application/json")
    COUNT=$(echo "$EXISTING_RECORDS" | jq '.result | length')
    if [[ "$COUNT" -gt 0 ]]; then
        echo "$EXISTING_RECORDS" | jq -r '.result[].id' | while read -r REC_ID; do
            [[ -z "$REC_ID" ]] && continue
            curl -s -X DELETE "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records/${REC_ID}" \
                -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" -H "Content-Type: application/json" >/dev/null 2>&1
        done
    fi
    curl -s -X POST "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records" \
        -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" -H "Content-Type: application/json" \
        --data '{"type":"CNAME","name":"'${url_vikunja}'","content":"'${nome_servidor}'.'${DOMINIO_PRINCIPAL}'","ttl":1,"proxied":false}' >/dev/null 2>&1

elif [ "$INSTALL_TYPE" = "CLOUDFLARE_TUNNEL" ]; then
    DOMINIO_PRINCIPAL=$(echo "$url_vikunja" | cut -d'.' -f2-)
    EXISTING_RECORDS=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records?name=${url_vikunja}" \
        -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" -H "Content-Type: application/json")
    COUNT=$(echo "$EXISTING_RECORDS" | jq '.result | length')
    if [[ "$COUNT" -gt 0 ]]; then
        echo "$EXISTING_RECORDS" | jq -r '.result[].id' | while read -r REC_ID; do
            [[ -z "$REC_ID" ]] && continue
            curl -s -X DELETE "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records/${REC_ID}" \
                -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" -H "Content-Type: application/json" >/dev/null 2>&1
        done
    fi
    curl -s -X POST "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records" \
        -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" -H "Content-Type: application/json" \
        --data "{\"type\":\"CNAME\",\"name\":\"${url_vikunja}\",\"content\":\"${TUNNEL_ID}.cfargotunnel.com\",\"ttl\":1,\"proxied\":true}" >/dev/null 2>&1

    NEW_SERVICE="http://${nome_app}:3456"
    TIMESTAMP=$(date -u +%Y%m%dT%H%M%SZ)
    TMPDIR=$(mktemp -d)
    BACKUP_RAW="$TMPDIR/backup_raw.$TIMESTAMP.json"
    TO_PUT="$TMPDIR/to_put.$TIMESTAMP.json"
    curl -sS -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
        "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/cfd_tunnel/$TUNNEL_ID/configurations" | jq '.' > "$BACKUP_RAW"
    jq --arg host "$url_vikunja" --arg service "$NEW_SERVICE" '
        (.result.config // {}) as $cfg | ($cfg.ingress // []) as $ing | ($ing | map(select(.service != "http_status:404"))) as $clean | ($clean | map(select(.hostname != $host))) as $filtered | ($filtered + [ { hostname: $host, service: $service, originRequest: { noTlsVerify: true, httpHostHeader: $host } } ]) as $merged | ($merged + [{ service: "http_status:404" }]) as $final_ing | ($cfg + { ingress: $final_ing }) as $newcfg | { config: $newcfg }
    ' "$BACKUP_RAW" > "$TO_PUT"
    curl -sS -X PUT "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/cfd_tunnel/$TUNNEL_ID/configurations" \
        -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" -H "Content-Type: application/json" --data-binary @"$TO_PUT" >/dev/null 2>&1
    rm -rf "$TMPDIR"
fi

echo -e "XXX\n50\nCRIANDO STACK... \nXXX"

cd
cd

cat > $nome_app.yaml << EOL

version: "3.7"
services:
  ${nome_app}_init:
    image: busybox:latest
    hostname: ${nome_app}_init
    networks:
      - interna
    volumes:
      - ${nome_app}_files:/app/vikunja/files
    command: chown -R 1000:0 /app/vikunja/files
    deploy:
      mode: replicated
      replicas: 1
      restart_policy:
        condition: none
      placement:
        constraints:
        - node.role == manager

  ${nome_app}:
    image: vikunja/vikunja:latest
    hostname: ${nome_app}
    networks:
      - externa
      - interna
    environment:
      - VIKUNJA_SERVICE_PUBLICURL=https://$url_vikunja
      - VIKUNJA_SERVICE_JWTSECRET=$vikunja_jwt
      - VIKUNJA_DATABASE_TYPE=postgres
      - VIKUNJA_DATABASE_HOST=postgres
      - VIKUNJA_DATABASE_PORT=5432
      - VIKUNJA_DATABASE_DATABASE=vikunja
      - VIKUNJA_DATABASE_USER=vikunja
      - VIKUNJA_DATABASE_PASSWORD=$vikunja_db_pass
      - VIKUNJA_SERVICE_TIMEZONE=America/Sao_Paulo
      - TZ=America/Sao_Paulo
    volumes:
      - ${nome_app}_files:/app/vikunja/files
    depends_on:
      - ${nome_app}_init
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

if [ "$INSTALL_TYPE" = "TRADICIONAL" ]; then
cat >> $nome_app.yaml << EOL
      labels:
      - traefik.enable=true
      - traefik.docker.network=externa
      - traefik.http.routers.${nome_app}.rule=Host(\`${url_vikunja}\`)
      - traefik.http.routers.${nome_app}.entrypoints=websecure
      - traefik.http.routers.${nome_app}.priority=1
      - traefik.http.routers.${nome_app}.tls.certresolver=letsencryptresolver
      - traefik.http.routers.${nome_app}.tls=true
      - traefik.http.routers.${nome_app}.service=${nome_app}
      - traefik.http.services.${nome_app}.loadbalancer.server.port=3456
EOL
fi

cat >> $nome_app.yaml << EOL

networks:
  externa:
    external: true
  interna:
    external: true

volumes:
  ${nome_app}_files:
    external: true
    name: ${nome_app}_files
EOL

# DEPLOY
if [[ "$criar_portainer" == "0" ]]; then
    dados_file="$HOME/dados_portainer/dados_portainer"
    if [[ -f "$dados_file" ]]; then
        PORTAINER_URL=$(grep "Dominio do portainer:" "$dados_file" | cut -d':' -f2 | xargs)
        ADMIN_USERNAME=$(grep "Usuario:" "$dados_file" | cut -d':' -f2 | xargs)
        ADMIN_PASSWORD=$(grep "Senha:" "$dados_file" | cut -d':' -f2 | xargs)
        STACK_NAME=$nome_app
        STACK_FILE_PATH="/root/$nome_app.yaml"
    else
        docker stack deploy --prune --resolve-image always -c $nome_app.yaml $nome_app >/dev/null 2>&1; exit 1
    fi
    get_auth_token() {
        RESPONSE=$(curl -sS -X POST "https://$PORTAINER_URL/api/auth" -H "Content-Type: application/json" -d "{\"username\": \"$ADMIN_USERNAME\", \"password\": \"$ADMIN_PASSWORD\"}")
        TOKEN=$(echo "$RESPONSE" | jq -r '.jwt')
        if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]; then docker stack deploy --prune --resolve-image always -c $nome_app.yaml $nome_app >/dev/null 2>&1; exit 1; fi
    }
    get_endpoint_id() {
        RESPONSE=$(curl -sS -X GET "https://$PORTAINER_URL/api/endpoints" -H "Authorization: Bearer $TOKEN")
        ENDPOINT_ID=$(echo "$RESPONSE" | jq -r '.[0].Id')
        if [ -z "$ENDPOINT_ID" ] || [ "$ENDPOINT_ID" = "null" ]; then docker stack deploy --prune --resolve-image always -c $nome_app.yaml $nome_app >/dev/null 2>&1; exit 1; fi
    }
    get_swarm_id() {
        RESPONSE=$(curl -sS -X GET "https://$PORTAINER_URL/api/endpoints/$ENDPOINT_ID/docker/swarm" -H "Authorization: Bearer $TOKEN")
        SWARM_ID=$(echo "$RESPONSE" | jq -r '.ID')
        if [ -z "$SWARM_ID" ] || [ "$SWARM_ID" = "null" ]; then docker stack deploy --prune --resolve-image always -c $nome_app.yaml $nome_app >/dev/null 2>&1; exit 1; fi
    }
    create_stack() {
        if [ ! -f "$STACK_FILE_PATH" ]; then docker stack deploy --prune --resolve-image always -c $nome_app.yaml $nome_app >/dev/null 2>&1; exit 1; fi
        response_output=$(mktemp); erro_output=$(mktemp)
        http_code=$(curl -s -o "$response_output" -w "%{http_code}"  -X POST -H "Authorization: Bearer $TOKEN" -F "Name=$STACK_NAME" -F "file=@$STACK_FILE_PATH" -F "SwarmID=$SWARM_ID" -F "endpointId=$ENDPOINT_ID" "https://$PORTAINER_URL/api/stacks/create/swarm/file" 2> "$erro_output")
        response=$(cat "$response_output"); rm -f "$response_output" "$erro_output"
        if [ "$http_code" -ne 200 ]; then docker stack deploy --prune --resolve-image always -c $nome_app.yaml $nome_app >/dev/null 2>&1; exit 1; fi
    }
    get_auth_token || exit 1; get_endpoint_id || exit 1; get_swarm_id || exit 1; create_stack || exit 1
elif [[ "$criar_portainer" == "1" ]]; then
    docker stack deploy --prune --resolve-image always -c $nome_app.yaml $nome_app >/dev/null 2>&1
else
    docker stack deploy --prune --resolve-image always -c $nome_app.yaml $nome_app >/dev/null 2>&1; exit 1
fi

echo -e "XXX\n90\nFINALIZANDO... \nXXX"; sleep 10
echo -e "XXX\n100\nCONCLUÍDO! \nXXX"; sleep 3

}|whiptail --title "VIKUNJA - INSTALAÇÃO" --gauge "Aguarde..." 6 60 0

if [ "$INSTALL_TYPE" = "TRADICIONAL" ]; then
    ip_servidor=$(curl -s --max-time 10 ipinfo.io/ip)
    dns_ip=$(timeout 10 nslookup "$url_vikunja" | grep "Address" | tail -n1 | awk '{print $2}' 2>/dev/null)
    if [[ "$dns_ip" != "$ip_servidor" ]]; then
        whiptail --title "Mensagem" --msgbox "Não foi possível acessar $url_vikunja. Verifique o DNS.\n\nPressione ENTER." 20 78
    else
        whiptail --title "Mensagem" --msgbox "Vikunja instalado!\n\nAcesse: https://$url_vikunja\nCrie sua conta na primeira visita.\n\nPressione ENTER." 20 78
    fi
else
    if nslookup "$url_vikunja" >/dev/null 2>&1; then
        whiptail --title "Mensagem" --msgbox "Vikunja instalado!\n\nAcesse: https://$url_vikunja\nCrie sua conta na primeira visita.\n\nPressione ENTER." 20 78
    else
        whiptail --title "Mensagem" --msgbox "AVISO: $url_vikunja não está resolvendo.\nVerifique o Cloudflare Tunnel.\n\nPressione ENTER." 20 78
    fi
fi

exit 0

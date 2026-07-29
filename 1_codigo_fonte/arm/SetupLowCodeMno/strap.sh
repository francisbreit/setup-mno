#!/usr/bin/bash
# STRAPI PRO — imagem própria gerada a partir do projeto oficial Strapi v5.
set -o pipefail

INSTALL_TYPE_FILE="/root/.cloudflared_config/installation_type"
INSTALL_TYPE="TRADICIONAL"
[ -f "$INSTALL_TYPE_FILE" ] && INSTALL_TYPE=$(cat "$INSTALL_TYPE_FILE")
if [ "$INSTALL_TYPE" = "CLOUDFLARE_TUNNEL" ]; then
  [ -f /root/.cloudflared_config/cloudflare_credentials ] && source /root/.cloudflared_config/cloudflare_credentials
else
  [ -f /root/.tradicional_config/tradicional_credentials ] && source /root/.tradicional_config/tradicional_credentials
fi

msg(){ whiptail --title "STRAPI" --msgbox "$1" 12 72; }
ask(){ local value status; while true; do value=$(whiptail --title "STRAPI" --inputbox "$1" 12 72 3>&1 1>&2 2>&3); status=$?; [ "$status" -ne 0 ] && exit 0; [ -n "$value" ] && { printf '%s' "$value"; return; }; msg "Este campo é obrigatório."; done; }

whiptail --title "STRAPI PRO" --yesno "Instalar Strapi v5 como stack PRO?\n\nA imagem será construída localmente a partir do projeto oficial." 12 72 || exit 0
url_strapi=$(ask "1/3 — Domínio do Strapi (ex.: strapi.seudominio.com):")
criar_portainer=$(ask "2/3 — Criar Stack no Portainer?\n0 = editável no Portainer | 1 = Docker direto")
[[ "$criar_portainer" =~ ^[01]$ ]] || { msg "Digite somente 0 ou 1."; exit 1; }

nome_principal="strapi"
sufixo_app=$(date +%s | md5sum | head -c7)
nome_app="${nome_principal}${sufixo_app}"
postgres_password=$(grep -oP '(?<=POSTGRES_PASSWORD=).+' /root/postgres.yaml)
[ -n "$postgres_password" ] || { msg "Não foi possível obter a senha de /root/postgres.yaml."; exit 1; }

if [ "$INSTALL_TYPE" = "CLOUDFLARE_TUNNEL" ]; then
  CHECK_RESPONSE=$(curl -sS -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/cfd_tunnel/$TUNNEL_ID/configurations")
  EXISTING_SERVICE=$(echo "$CHECK_RESPONSE" | jq -r --arg h "$url_strapi" '.result.config.ingress[] | select(.hostname == $h) | .service' 2>/dev/null)
  [ -n "$EXISTING_SERVICE" ] && [ "$EXISTING_SERVICE" != "null" ] && msg "A rota $url_strapi será substituída.\nServiço atual: $EXISTING_SERVICE"
fi

whiptail --title "Confirmar instalação" --yesno "Strapi PRO\nDomínio: $url_strapi\nInstalação: $INSTALL_TYPE\nPortainer: $criar_portainer" 14 72 || exit 0

{
echo "XXX\n5\nCRIANDO BANCO DE DADOS...\nXXX"
postgres_id=$(docker ps -qf name=postgres | head -n1)
[ -n "$postgres_id" ] || { echo "XXX\n100\nPOSTGRES COMPARTILHADO NÃO ENCONTRADO\nXXX"; exit 1; }
docker exec -i "$postgres_id" psql -U postgres -d postgres -tc "SELECT 1 FROM pg_database WHERE datname='$nome_app'" | grep -q 1 || docker exec -i "$postgres_id" psql -U postgres -d postgres -c "CREATE DATABASE $nome_app;" >/dev/null

echo "XXX\n20\nGERANDO IMAGEM STRAPI V5...\nXXX"
cd; cd
build_dir="/root/${nome_app}-build"
mkdir -p "$build_dir"
cat > "$build_dir/Dockerfile" <<'EOL'
FROM node:22-alpine
RUN apk add --no-cache libc6-compat
WORKDIR /opt/strapi
RUN npx --yes create-strapi@5.46.1 . --skip-cloud --no-run --use-npm --typescript --dbclient=postgres --dbhost=postgres --dbport=5432 --dbname=strapi --dbusername=postgres --dbpassword=strapi --dbssl=false
RUN npm run build
EXPOSE 1337
CMD ["npm", "run", "start"]
EOL
docker build --pull -t "${nome_app}:5.46.1" "$build_dir" >/dev/null

echo "XXX\n55\nGERANDO STACK...\nXXX"
app_keys="$(openssl rand -hex 16),$(openssl rand -hex 16),$(openssl rand -hex 16),$(openssl rand -hex 16)"
cat > "/root/$nome_app.yaml" <<EOL

version: "3.7"
services:
  $nome_app:
    image: ${nome_app}:5.46.1
    hostname: $nome_app
    networks:
      - externa
      - interna
    environment:
      - NODE_ENV=production
      - HOST=0.0.0.0
      - PORT=1337
      - APP_KEYS=$app_keys
      - API_TOKEN_SALT=$(openssl rand -hex 16)
      - ADMIN_JWT_SECRET=$(openssl rand -hex 32)
      - TRANSFER_TOKEN_SALT=$(openssl rand -hex 16)
      - JWT_SECRET=$(openssl rand -hex 32)
      - DATABASE_CLIENT=postgres
      - DATABASE_HOST=postgres
      - DATABASE_PORT=5432
      - DATABASE_NAME=$nome_app
      - DATABASE_USERNAME=postgres
      - DATABASE_PASSWORD=$postgres_password
      - DATABASE_SSL=false
      - STRAPI_TELEMETRY_DISABLED=true
    volumes:
      - ${nome_app}_uploads:/opt/strapi/public/uploads
    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
        - node.role == manager
      resources:
        limits:
          cpus: "1"
          memory: 1536M
EOL
if [ "$INSTALL_TYPE" = "TRADICIONAL" ]; then cat >> "/root/$nome_app.yaml" <<EOL
      labels:
      - traefik.enable=true
      - traefik.docker.network=externa
      - traefik.http.routers.$nome_app.rule=Host(\`$url_strapi\`)
      - traefik.http.routers.$nome_app.entrypoints=websecure
      - traefik.http.routers.$nome_app.priority=1
      - traefik.http.routers.$nome_app.tls.certresolver=letsencryptresolver
      - traefik.http.routers.$nome_app.tls=true
      - traefik.http.routers.$nome_app.service=$nome_app
      - traefik.http.services.$nome_app.loadbalancer.server.port=1337
EOL
fi
cat >> "/root/$nome_app.yaml" <<EOL

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
docker volume create "${nome_app}_uploads" >/dev/null

echo "XXX\n70\nCONFIGURANDO DNS...\nXXX"
if [ "$INSTALL_TYPE" = "CLOUDFLARE_TUNNEL" ]; then
  curl -sS -X POST "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records" -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" -H "Content-Type: application/json" --data '{"type":"CNAME","name":"'"$url_strapi"'","content":"'"$TUNNEL_ID"'.cfargotunnel.com","ttl":1,"proxied":true}' >/dev/null
  curl -sS -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/cfd_tunnel/$TUNNEL_ID/configurations" | jq --arg host "$url_strapi" --arg service "http://${nome_app}:1337" '(.result.config // {}) as $cfg | ($cfg.ingress // []) | map(select(.service != "http_status:404" and .hostname != $host)) + [{hostname:$host,service:$service,originRequest:{noTlsVerify:true,httpHostHeader:$host}},{service:"http_status:404"}] | {config:($cfg + {ingress:.})}' > /tmp/${nome_app}-tunnel.json
  curl -sS -X PUT "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/cfd_tunnel/$TUNNEL_ID/configurations" -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" -H "Content-Type: application/json" --data-binary @/tmp/${nome_app}-tunnel.json >/dev/null
  rm -f /tmp/${nome_app}-tunnel.json
fi

echo "XXX\n85\nPUBLICANDO STACK...\nXXX"
if [ "$criar_portainer" = "0" ] && [ -f "$HOME/dados_portainer/dados_portainer" ]; then
  PORTAINER_URL=$(grep "Dominio do portainer:" "$HOME/dados_portainer/dados_portainer" | cut -d: -f2- | xargs); ADMIN_USERNAME=$(grep "Usuario:" "$HOME/dados_portainer/dados_portainer" | cut -d: -f2- | xargs); ADMIN_PASSWORD=$(grep "Senha:" "$HOME/dados_portainer/dados_portainer" | cut -d: -f2- | xargs)
  TOKEN=$(curl -sk -X POST "https://$PORTAINER_URL/api/auth" -H 'Content-Type: application/json' -d "{\"username\":\"$ADMIN_USERNAME\",\"password\":\"$ADMIN_PASSWORD\"}" | jq -r .jwt)
  ENDPOINT_ID=$(curl -sk "https://$PORTAINER_URL/api/endpoints" -H "Authorization: Bearer $TOKEN" | jq -r '.[0].Id'); SWARM_ID=$(curl -sk "https://$PORTAINER_URL/api/endpoints/$ENDPOINT_ID/docker/swarm" -H "Authorization: Bearer $TOKEN" | jq -r .ID)
  curl -sk -X POST -H "Authorization: Bearer $TOKEN" -F "Name=$nome_app" -F "file=@/root/$nome_app.yaml" -F "SwarmID=$SWARM_ID" -F "endpointId=$ENDPOINT_ID" "https://$PORTAINER_URL/api/stacks/create/swarm/file" >/dev/null || docker stack deploy --prune --resolve-image never -c "/root/$nome_app.yaml" "$nome_app"
else docker stack deploy --prune --resolve-image never -c "/root/$nome_app.yaml" "$nome_app"; fi
echo "XXX\n100\nSTRAPI INSTALADO\nXXX"
} | whiptail --title "STRAPI PRO" --gauge "Preparando Strapi..." 8 70 0

whiptail --title "STRAPI PRO" --msgbox "Strapi instalado.\n\nAcesse: https://$url_strapi/admin\n\nCrie o primeiro administrador na tela inicial." 14 72

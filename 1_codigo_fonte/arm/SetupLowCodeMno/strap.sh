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

install_log="/tmp/${nome_app}-install.log"
error_file="/tmp/${nome_app}-error.log"
: > "$install_log"
: > "$error_file"

{
echo "XXX\n5\nCRIANDO BANCO DE DADOS...\nXXX"
postgres_id=$(docker ps -qf name=postgres | head -n1)
if [ -z "$postgres_id" ]; then
  echo "PostgreSQL compartilhado não encontrado." > "$error_file"
  echo "XXX\n100\nERRO: POSTGRES NÃO ENCONTRADO\nXXX"
  exit 10
fi
if ! docker exec -i "$postgres_id" psql -U postgres -d postgres -tc "SELECT 1 FROM pg_database WHERE datname='$nome_app'" 2>>"$install_log" | grep -q 1; then
  if ! docker exec -i "$postgres_id" psql -U postgres -d postgres -c "CREATE DATABASE $nome_app;" >>"$install_log" 2>&1; then
    echo "Falha ao criar o banco PostgreSQL $nome_app." > "$error_file"
    echo "XXX\n100\nERRO AO CRIAR BANCO DE DADOS\nXXX"
    exit 11
  fi
fi

echo "XXX\n20\nGERANDO IMAGEM STRAPI V5...\nXXX"
cd; cd
build_dir="/root/${nome_app}-build"
mkdir -p "$build_dir"
cat > "$build_dir/Dockerfile" <<'EOL'
FROM node:22-alpine
RUN apk add --no-cache libc6-compat build-base gcc autoconf automake zlib-dev libpng-dev vips-dev git
WORKDIR /opt/strapi
RUN npx --yes create-strapi@5.46.1 . --skip-cloud --no-run --use-npm --typescript --dbclient=postgres --dbhost=postgres --dbport=5432 --dbname=strapi --dbusername=postgres --dbpassword=strapi --dbssl=false
RUN npm run build
EXPOSE 1337
CMD ["npm", "run", "start"]
EOL
if ! docker build --pull --progress=plain -t "${nome_app}:5.46.1" "$build_dir" >>"$install_log" 2>&1; then
  {
    echo "Falha ao construir a imagem ${nome_app}:5.46.1."
    echo
    tail -n 18 "$install_log"
  } > "$error_file"
  echo "XXX\n100\nERRO AO CRIAR IMAGEM STRAPI\nXXX"
  exit 20
fi
if ! docker image inspect "${nome_app}:5.46.1" >>"$install_log" 2>&1; then
  echo "O build terminou, mas a imagem ${nome_app}:5.46.1 não foi encontrada no Docker." > "$error_file"
  echo "XXX\n100\nIMAGEM STRAPI NÃO ENCONTRADA\nXXX"
  exit 21
fi

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
if ! docker volume create "${nome_app}_uploads" >>"$install_log" 2>&1; then
  echo "Falha ao criar o volume ${nome_app}_uploads." > "$error_file"
  echo "XXX\n100\nERRO AO CRIAR VOLUME\nXXX"
  exit 30
fi

echo "XXX\n70\nCONFIGURANDO DNS...\nXXX"
if [ "$INSTALL_TYPE" = "CLOUDFLARE_TUNNEL" ]; then
  curl -sS -X POST "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records" -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" -H "Content-Type: application/json" --data '{"type":"CNAME","name":"'"$url_strapi"'","content":"'"$TUNNEL_ID"'.cfargotunnel.com","ttl":1,"proxied":true}' >>"$install_log" 2>&1
  curl -sS -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/cfd_tunnel/$TUNNEL_ID/configurations" 2>>"$install_log" | jq --arg host "$url_strapi" --arg service "http://${nome_app}:1337" '(.result.config // {}) as $cfg | ($cfg.ingress // []) | map(select(.service != "http_status:404" and .hostname != $host)) + [{hostname:$host,service:$service,originRequest:{noTlsVerify:true,httpHostHeader:$host}},{service:"http_status:404"}] | {config:($cfg + {ingress:.})}' > /tmp/${nome_app}-tunnel.json 2>>"$install_log"
  curl -sS -X PUT "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/cfd_tunnel/$TUNNEL_ID/configurations" -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" -H "Content-Type: application/json" --data-binary @/tmp/${nome_app}-tunnel.json >>"$install_log" 2>&1
  rm -f /tmp/${nome_app}-tunnel.json
fi

echo "XXX\n85\nPUBLICANDO STACK...\nXXX"
if [ "$criar_portainer" = "0" ] && [ -f "$HOME/dados_portainer/dados_portainer" ]; then
  PORTAINER_URL=$(grep "Dominio do portainer:" "$HOME/dados_portainer/dados_portainer" | cut -d: -f2- | xargs); ADMIN_USERNAME=$(grep "Usuario:" "$HOME/dados_portainer/dados_portainer" | cut -d: -f2- | xargs); ADMIN_PASSWORD=$(grep "Senha:" "$HOME/dados_portainer/dados_portainer" | cut -d: -f2- | xargs)
  TOKEN=$(curl -sk -X POST "https://$PORTAINER_URL/api/auth" -H 'Content-Type: application/json' -d "{\"username\":\"$ADMIN_USERNAME\",\"password\":\"$ADMIN_PASSWORD\"}" 2>>"$install_log" | jq -r .jwt 2>>"$install_log")
  if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]; then
    echo "Falha ao autenticar no Portainer." > "$error_file"
    echo "XXX\n100\nERRO DE AUTENTICAÇÃO NO PORTAINER\nXXX"
    exit 40
  fi
  ENDPOINT_ID=$(curl -sk "https://$PORTAINER_URL/api/endpoints" -H "Authorization: Bearer $TOKEN" 2>>"$install_log" | jq -r '.[0].Id' 2>>"$install_log")
  SWARM_ID=$(curl -sk "https://$PORTAINER_URL/api/endpoints/$ENDPOINT_ID/docker/swarm" -H "Authorization: Bearer $TOKEN" 2>>"$install_log" | jq -r .ID 2>>"$install_log")
  if [ -z "$ENDPOINT_ID" ] || [ "$ENDPOINT_ID" = "null" ] || [ -z "$SWARM_ID" ] || [ "$SWARM_ID" = "null" ]; then
    echo "EndpointID ou SwarmID não encontrado no Portainer." > "$error_file"
    echo "XXX\n100\nERRO AO LER O SWARM NO PORTAINER\nXXX"
    exit 41
  fi
  echo "XXX\n82\nENVIANDO IMAGEM PARA O PORTAINER...\nXXX"
  image_load_response=$(mktemp)
  image_archive=$(mktemp --suffix=.tar)
  if ! docker save -o "$image_archive" "${nome_app}:5.46.1" >>"$install_log" 2>&1; then
    echo "Falha ao exportar a imagem ${nome_app}:5.46.1 para envio ao Portainer." > "$error_file"
    rm -f "$image_load_response" "$image_archive"
    echo "XXX\n100\nERRO AO EXPORTAR IMAGEM STRAPI\nXXX"
    exit 42
  fi
  if ! curl -sk --fail-with-body -X POST \
      -H "Authorization: Bearer $TOKEN" \
      -H "Content-Type: application/x-tar" \
      --data-binary @"$image_archive" \
      "https://$PORTAINER_URL/api/endpoints/$ENDPOINT_ID/docker/images/load?quiet=1" \
      >"$image_load_response" 2>>"$install_log"; then
    {
      echo "Falha ao enviar a imagem ${nome_app}:5.46.1 para o Portainer."
      echo
      cat "$image_load_response"
      tail -n 12 "$install_log"
    } > "$error_file"
    rm -f "$image_load_response" "$image_archive"
    echo "XXX\n100\nERRO AO ENVIAR IMAGEM AO PORTAINER\nXXX"
    exit 42
  fi
  cat "$image_load_response" >>"$install_log"
  rm -f "$image_load_response" "$image_archive"
  if ! curl -sk --fail \
      -H "Authorization: Bearer $TOKEN" \
      "https://$PORTAINER_URL/api/endpoints/$ENDPOINT_ID/docker/images/${nome_app}:5.46.1/json" \
      >>"$install_log" 2>&1; then
    echo "A API do Portainer não confirmou a imagem ${nome_app}:5.46.1 após o upload." > "$error_file"
    echo "XXX\n100\nPORTAINER NÃO CONFIRMOU A IMAGEM\nXXX"
    exit 43
  fi
  portainer_response=$(mktemp)
  http_code=$(curl -sk -o "$portainer_response" -w "%{http_code}" -X POST -H "Authorization: Bearer $TOKEN" -F "Name=$nome_app" -F "file=@/root/$nome_app.yaml" -F "SwarmID=$SWARM_ID" -F "endpointId=$ENDPOINT_ID" "https://$PORTAINER_URL/api/stacks/create/swarm/file" 2>>"$install_log")
  if ! [[ "$http_code" =~ ^[0-9]{3}$ ]] || [ "$http_code" -lt 200 ] || [ "$http_code" -ge 300 ]; then
    {
      echo "Portainer recusou a stack. HTTP $http_code."
      echo
      cat "$portainer_response"
    } > "$error_file"
    rm -f "$portainer_response"
    echo "XXX\n100\nERRO AO CRIAR STACK NO PORTAINER\nXXX"
    exit 44
  fi
  cat "$portainer_response" >>"$install_log"
  rm -f "$portainer_response"
else
  if ! docker stack deploy --prune --resolve-image never -c "/root/$nome_app.yaml" "$nome_app" >>"$install_log" 2>&1; then
    {
      echo "Falha ao criar a stack diretamente no Docker."
      echo
      tail -n 18 "$install_log"
    } > "$error_file"
    echo "XXX\n100\nERRO AO CRIAR STACK NO DOCKER\nXXX"
    exit 45
  fi
fi
echo "XXX\n100\nSTRAPI INSTALADO\nXXX"
} | whiptail --title "STRAPI PRO" --gauge "Preparando Strapi..." 8 70 0
install_status=${PIPESTATUS[0]}

if [ "$install_status" -ne 0 ]; then
  error_detail=$(cat "$error_file" 2>/dev/null)
  [ -n "$error_detail" ] || error_detail=$(tail -n 18 "$install_log" 2>/dev/null)
  whiptail --title "ERRO NA INSTALAÇÃO DO STRAPI" --scrolltext --msgbox "A instalação foi interrompida com segurança.\n\n$error_detail\n\nLog completo: $install_log" 24 90
  exit "$install_status"
fi

whiptail --title "STRAPI PRO" --msgbox "Strapi instalado.\n\nAcesse: https://$url_strapi/admin\n\nCrie o primeiro administrador na tela inicial." 14 72

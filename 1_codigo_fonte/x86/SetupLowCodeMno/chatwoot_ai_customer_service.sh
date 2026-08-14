#!/usr/bin/bash
#########################################################
# COMBO 1: AI CUSTOMER SERVICE PLATFORM (PRO)
# Chatwoot + Evolution 2.0 + RabbitMQ + MinIO
# + n8n + Ollama + LiteLLM + Qdrant
#
# Contact center com IA integrada:
# WhatsApp chega → Chatwoot atende → n8n processa
# → Ollama responde com IA → Qdrant busca contexto
# → MinIO armazena anexos
#########################################################

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
actlistbox=black,white
actsellistbox=white,blue
checkbox=red,black
actcheckbox=white,blue
'

clear
amarelo="\e[33m"
verde="\e[32m"
branco="\e[97m"
reset="\e[0m"

{
  tput reset 2>/dev/null
  exec 0</dev/tty 1>/dev/tty 2>&1
  sleep 0.01
  clear
} || true

# --- VERIFICAR TIPO DE INSTALACAO ---
INSTALL_TYPE_FILE="/root/.cloudflared_config/installation_type"
if [ -f "$INSTALL_TYPE_FILE" ]; then
    INSTALL_TYPE=$(cat "$INSTALL_TYPE_FILE")
else
    INSTALL_TYPE="TRADICIONAL"
fi

# --- CARREGAR CREDENCIAIS ---
if [ "$INSTALL_TYPE" = "CLOUDFLARE_TUNNEL" ]; then
    if [ -f "${SETUPMNO_CLOUDFLARE_CREDENTIALS_FILE:-/root/.cloudflared_config/cloudflare_credentials}" ]; then
        source "${SETUPMNO_CLOUDFLARE_CREDENTIALS_FILE:-/root/.cloudflared_config/cloudflare_credentials}"
    fi
else
    if [ -f "${SETUPMNO_TRADITIONAL_CREDENTIALS_FILE:-/root/.tradicional_config/tradicional_credentials}" ]; then
        source "${SETUPMNO_TRADITIONAL_CREDENTIALS_FILE:-/root/.tradicional_config/tradicional_credentials}"
    fi
fi

function msg() {
    whiptail --title "AI CUSTOMER SERVICE PLATFORM" --msgbox "$1" --fb 10 70
}

# --- MENU INICIAL ---
while true; do
CHOICE=$(
whiptail --title "AI CUSTOMER SERVICE PLATFORM" --menu \
"INSTALACAO COMPLETA: Chatwoot + Evolution + RabbitMQ + MinIO + n8n + Ollama + LiteLLM + Qdrant\n\n\
TIPO DE INSTALACAO: $INSTALL_TYPE\n\n\
Este combo instala um contact center com IA integrada.\n\
Cada servico recebe um dominio propio.\n\n\
Pressione ENTER para continuar ou SAIR para cancelar." 22 78 2 \
    "1)" "CONTINUAR" \
    "2)" "SAIR" 3>&2 2>&1 1>&3
)

case $CHOICE in
    "1)") clear; break ;;
    "2)") cd /; exit 0 ;;
esac
done

# --- VERIFICAR CONTAINERS EXISTENTES ---
minio_container=$(docker ps -qf "name=minio")
chatwoot_container=$(docker ps -qf "name=chatwoot")
evo_container=$(docker ps -qf "name=evolution")
rabbitmq_container=$(docker ps -qf "name=rabbitmq")
n8n_container=$(docker ps -qf "name=n8n")
ollama_container=$(docker ps -qf "name=ollama")
litellm_container=$(docker ps -qf "name=litellm")
qdrant_container=$(docker ps -qf "name=qdrant")

# --- VARIAVEIS GLOBAIS ---
postgres_password=$(grep -oP '(?<=POSTGRES_PASSWORD=).+' /root/postgres.yaml 2>/dev/null || echo "")

# --- COLETA DE DOMINIOS ---
# Dominios obrigatorios: Chatwoot, Evolution, RabbitMQ, MinIO, n8n, LiteLLM
# Dominios opcionais: Ollama (pode rodar sem web UI), Qdrant (acesso interno)

collect_domain() {
    local title="$1"
    local desc="$2"
    local varname="$3"
    while true; do
        val=$(whiptail --title "$title" --inputbox "$desc" 12 60 3>&1 1>&2 2>&3)
        if [ $? -ne 0 ]; then cd /; exit 0; fi
        if [ -z "$val" ]; then
            msg "Digite o dominio para continuar."
            continue
        fi
        eval "$varname='$val'"
        break
    done
}

# MinIO (se nao existir)
if [[ "$minio_container" == "" ]]; then
    collect_domain "Dominio do MinIO" "Digite o dominio do painel MinIO (ex: minio.seudominio.com):" DOMINIO_MINIO
fi

# Chatwoot
if [[ "$chatwoot_container" == "" ]]; then
    collect_domain "Dominio do Chatwoot" "Digite o dominio do Chatwoot (ex: chat.seudominio.com):" DOMINIO_CHATWOOT
fi

# Evolution
if [[ "$evo_container" == "" ]]; then
    collect_domain "Dominio da Evolution" "Digite o dominio da Evolution API (ex: evo.seudominio.com):" DOMINIO_EVOLUTION
fi

# RabbitMQ
if [[ "$rabbitmq_container" == "" ]]; then
    collect_domain "Dominio do RabbitMQ" "Digite o dominio do painel RabbitMQ (ex: rabbitmq.seudominio.com):" DOMINIO_RABBITMQ
fi

# n8n
if [[ "$n8n_container" == "" ]]; then
    collect_domain "Dominio do n8n" "Digite o dominio do n8n (ex: n8n.seudominio.com):" DOMINIO_N8N
fi

# LiteLLM
if [[ "$litellm_container" == "" ]]; then
    collect_domain "Dominio do LiteLLM" "Digite o dominio do LiteLLM (ex: llm.seudominio.com):" DOMINIO_LITELLM
fi

# --- CREDENCIAIS ---
# MinIO
if [[ "$minio_container" == "" ]]; then
    while true; do
        MINIO_USER=$(whiptail --title "Usuario MinIO" --inputbox "Crie o usuario do MinIO:" 10 60 3>&1 1>&2 2>&3)
        [ $? -ne 0 ] && cd / && exit 0
        [ -n "$MINIO_USER" ] && break
        msg "Usuario e obrigatorio."
    done
    while true; do
        MINIO_PASS=$(whiptail --title "Senha MinIO" --inputbox "Crie a senha do MinIO (minimo 8 caracteres):" 10 60 3>&1 1>&2 2>&3)
        [ $? -ne 0 ] && cd / && exit 0
        [ ${#MINIO_PASS} -ge 8 ] && break
        msg "Senha deve ter minimo 8 caracteres."
    done
fi

# Chatwoot
if [[ "$chatwoot_container" == "" ]]; then
    while true; do
        CHATWOOT_SECRET=$(whiptail --title "Secret Key Chatwoot" --inputbox "Digite a SECRET_KEY_BASE do Chatwoot (ou ENTER para gerar):" 10 60 3>&1 1>&2 2>&3)
        [ $? -ne 0 ] && cd / && exit 0
        if [ -z "$CHATWOOT_SECRET" ]; then
            CHATWOOT_SECRET=$(openssl rand -hex 64)
        fi
        break
    done
fi

# RabbitMQ
if [[ "$rabbitmq_container" == "" ]]; then
    while true; do
        RABBIT_USER=$(whiptail --title "Usuario RabbitMQ" --inputbox "Crie o usuario do RabbitMQ:" 10 60 3>&1 1>&2 2>&3)
        [ $? -ne 0 ] && cd / && exit 0
        [ -n "$RABBIT_USER" ] && break
        msg "Usuario e obrigatorio."
    done
    while true; do
        RABBIT_PASS=$(whiptail --title "Senha RabbitMQ" --inputbox "Crie a senha do RabbitMQ:" 10 60 3>&1 1>&2 2>&3)
        [ $? -ne 0 ] && cd / && exit 0
        [ -n "$RABBIT_PASS" ] && break
        msg "Senha e obrigatoria."
    done
fi

# n8n
if [[ "$n8n_container" == "" ]]; then
    while true; do
        N8N_USER=$(whiptail --title "Email n8n" --inputbox "Digite o email do admin do n8n:" 10 60 3>&1 1>&2 2>&3)
        [ $? -ne 0 ] && cd / && exit 0
        [ -n "$N8N_USER" ] && break
        msg "Email e obrigatorio."
    done
    while true; do
        N8N_PASS=$(whiptail --title "Senha n8n" --inputbox "Crie a senha do n8n:" 10 60 3>&1 1>&2 2>&3)
        [ $? -ne 0 ] && cd / && exit 0
        [ -n "$N8N_PASS" ] && break
        msg "Senha e obrigatoria."
    done
fi

# LiteLLM
if [[ "$litellm_container" == "" ]]; then
    LITELLM_KEY=$(openssl rand -hex 16)
    while true; do
        LITELLM_USER=$(whiptail --title "Usuario LiteLLM" --inputbox "Crie o usuario do LiteLLM UI:" 10 60 3>&1 1>&2 2>&3)
        [ $? -ne 0 ] && cd / && exit 0
        [ -n "$LITELLM_USER" ] && break
        msg "Usuario e obrigatorio."
    done
    while true; do
        LITELLM_PASS=$(whiptail --title "Senha LiteLLM" --inputbox "Crie a senha do LiteLLM UI:" 10 60 3>&1 1>&2 2>&3)
        [ $? -ne 0 ] && cd / && exit 0
        [ -n "$LITELLM_PASS" ] && break
        msg "Senha e obrigatoria."
    done
fi

# --- CRIAR DATABASES NO POSTGRES ---
if [[ "$chatwoot_container" == "" ]]; then
    CONTAINER_ID=$(docker ps -q -f "name=^postgres_")
    if [ -n "$CONTAINER_ID" ]; then
        docker exec -i $CONTAINER_ID psql -U postgres -c "CREATE DATABASE chatwoot;" 2>/dev/null
        docker exec -i $CONTAINER_ID psql -U postgres -c "CREATE DATABASE evolution;" 2>/dev/null
        docker exec -i $CONTAINER_ID psql -U postgres -c "CREATE DATABASE litellm;" 2>/dev/null
    fi
fi

# --- GERAR NOMES DAS STACKS ---
NOME_CHATWOOT="chatwoot-ai"
NOME_EVOLUTION="evolution-ai"
NOME_RABBITMQ="rabbitmq-ai"
NOME_MINIO="minio-ai"
NOME_N8N="n8n-ai"
NOME_OLLAMA="ollama-ai"
NOME_LITELLM="litellm-ai"
NOME_QDRANT="qdrant-ai"
NOME_CWT_REDIS="chatwoot-redis-ai"
NOME_EVO_REDIS="evo-redis-ai"

# --- DNS AUTOMATION ---
export NEWT_COLORS='
root=,white
window=,black
border=white,black
textbox=white,black
button=black,white
'

clear
{

# Funcao para criar DNS (reutilizavel)
create_dns() {
    local dominio="$1"
    local servico="$2"
    
    if [ "$INSTALL_TYPE" = "TRADICIONAL" ] && [ "$criar_dns" = "0" ]; then
        # TRADICIONAL + DNS AUTOMATICO
        DOMINIO_PRINC="${SETUPMNO_SELECTED_ROOT_DOMAIN:-${SETUPMNO_DOMAIN_ROOT:-${CLOUDFLARE_ZONE_NAME:-}}}"
        
        EXISTING=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records?name=${dominio}" \
            -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" -H "Content-Type: application/json")
        COUNT=$(echo "$EXISTING" | jq '.result | length')
        if [ "$COUNT" -gt 0 ]; then
            echo "$EXISTING" | jq -r '.result[].id' | while read -r REC_ID; do
                [ -z "$REC_ID" ] && continue
                curl -s -X DELETE "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records/${REC_ID}" \
                    -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" -H "Content-Type: application/json" >/dev/null 2>&1
            done
        fi
        
        curl -s -X POST "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records" \
            -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" -H "Content-Type: application/json" \
            --data "{\"type\":\"CNAME\",\"name\":\"${dominio}\",\"content\":\"${nome_servidor}.${DOMINIO_PRINC}\",\"ttl\":1,\"proxied\":false}" >/dev/null 2>&1

    elif [ "$INSTALL_TYPE" = "CLOUDFLARE_TUNNEL" ]; then
        # CLOUDFLARE TUNNEL
        DOMINIO_PRINC="${SETUPMNO_SELECTED_ROOT_DOMAIN:-${SETUPMNO_DOMAIN_ROOT:-${CLOUDFLARE_ZONE_NAME:-}}}"
        
        EXISTING=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records?name=${dominio}" \
            -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" -H "Content-Type: application/json")
        COUNT=$(echo "$EXISTING" | jq '.result | length')
        if [ "$COUNT" -gt 0 ]; then
            echo "$EXISTING" | jq -r '.result[].id' | while read -r REC_ID; do
                [ -z "$REC_ID" ] && continue
                curl -s -X DELETE "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records/${REC_ID}" \
                    -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" -H "Content-Type: application/json" >/dev/null 2>&1
            done
        fi
        
        curl -s -X POST "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records" \
            -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" -H "Content-Type: application/json" \
            --data "{\"type\":\"CNAME\",\"name\":\"${dominio}\",\"content\":\"${TUNNEL_ID}.cfargotunnel.com\",\"ttl\":1,\"proxied\":true}" >/dev/null 2>&1
        
        # Adicionar rota ao tunnel
        add_tunnel_route "$dominio" "$servico"
    fi
}

add_tunnel_route() {
    local host="$1"
    local service="$2"
    local TMPDIR=$(mktemp -d)
    local BACKUP="$TMPDIR/backup.json"
    local PAYLOAD="$TMPDIR/payload.json"
    
    curl -sS -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
        "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/cfd_tunnel/$TUNNEL_ID/configurations" \
        | jq '.' > "$BACKUP"
    
    jq --arg host "$host" --arg service "$service" '
        (.result.config // {}) as $cfg
        | ($cfg.ingress // []) as $ing
        | ($ing | map(select(.service != "http_status:404"))) as $clean
        | ($clean | map(.hostname // "")) as $existing
        | (if ($existing | index($host)) then $clean else ($clean + [{ hostname: $host, service: $service, originRequest: { noTlsVerify: true, httpHostHeader: $host } }]) end) as $merged
        | ($merged + [{ service: "http_status:404" }]) as $final
        | { config: ($cfg + { ingress: $final }) }
    ' "$BACKUP" > "$PAYLOAD"
    
    curl -sS -X PUT "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/cfd_tunnel/$TUNNEL_ID/configurations" \
        -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" -H "Content-Type: application/json" \
        --data-binary @"$PAYLOAD" >/dev/null 2>&1
    
    rm -rf "$TMPDIR"
}

# Criar DNS para cada servico
if [[ -n "$DOMINIO_MINIO" ]]; then
    echo -e "XXX\n5\nCONFIGURANDO DNS MINIO...\nXXX"
    create_dns "$DOMINIO_MINIO" "http://${NOME_MINIO}:9001"
fi

if [[ -n "$DOMINIO_CHATWOOT" ]]; then
    echo -e "XXX\n10\nCONFIGURANDO DNS CHATWOOT...\nXXX"
    create_dns "$DOMINIO_CHATWOOT" "http://${NOME_CHATWOOT}:3000"
fi

if [[ -n "$DOMINIO_EVOLUTION" ]]; then
    echo -e "XXX\n15\nCONFIGURANDO DNS EVOLUTION...\nXXX"
    create_dns "$DOMINIO_EVOLUTION" "http://${NOME_EVOLUTION}:8080"
fi

if [[ -n "$DOMINIO_RABBITMQ" ]]; then
    echo -e "XXX\n20\nCONFIGURANDO DNS RABBITMQ...\nXXX"
    create_dns "$DOMINIO_RABBITMQ" "http://${NOME_RABBITMQ}:15672"
fi

if [[ -n "$DOMINIO_N8N" ]]; then
    echo -e "XXX\n25\nCONFIGURANDO DNS N8N...\nXXX"
    create_dns "$DOMINIO_N8N" "http://${NOME_N8N}:5678"
fi

if [[ -n "$DOMINIO_LITELLM" ]]; then
    echo -e "XXX\n30\nCONFIGURANDO DNS LITELLM...\nXXX"
    create_dns "$DOMINIO_LITELLM" "http://${NOME_LITELLM}:4000"
fi

echo -e "XXX\n35\nDNS CONFIGURADO - INICIANDO INSTALACAO...\nXXX"
sleep 3

# ============================================================
# INSTALACAO DOS SERVICOS
# ============================================================

cd

# --- 1. MINIO ---
if [[ "$minio_container" == "" ]] && [[ -n "$DOMINIO_MINIO" ]]; then
    echo -e "XXX\n38\nINSTALANDO MINIO...\nXXX"
    
    cat > ${NOME_MINIO}.yaml << EOL
version: "3.7"
services:
  ${NOME_MINIO}:
    image: minio/minio:latest
    hostname: ${NOME_MINIO}
    command: server /data --console-address ":9001"
    environment:
      - MINIO_ROOT_USER=$MINIO_USER
      - MINIO_ROOT_PASSWORD=$MINIO_PASS
    volumes:
      - ${NOME_MINIO}_data:/data
    networks:
      - interna
      - externa
    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
          - node.role == manager
EOL

    if [ "$INSTALL_TYPE" = "TRADICIONAL" ]; then
    cat >> ${NOME_MINIO}.yaml << EOL
      labels:
        - traefik.enable=1
        - traefik.http.routers.${NOME_MINIO}.rule=Host(\`${DOMINIO_MINIO}\`)
        - traefik.http.routers.${NOME_MINIO}.entrypoints=websecure
        - traefik.http.routers.${NOME_MINIO}.priority=1
        - traefik.http.routers.${NOME_MINIO}.tls.certresolver=letsencryptresolver
        - traefik.http.routers.${NOME_MINIO}.service=${NOME_MINIO}
        - traefik.http.services.${NOME_MINIO}.loadbalancer.server.port=9001
EOL
    fi

    cat >> ${NOME_MINIO}.yaml << EOL
volumes:
  ${NOME_MINIO}_data:
    external: true
    name: ${NOME_MINIO}_data
networks:
  interna:
    external: true
  externa:
    external: true
EOL

    docker volume create ${NOME_MINIO}_data >/dev/null 2>&1
    docker stack deploy --prune --resolve-image always -c ${NOME_MINIO}.yaml ${NOME_MINIO} >/dev/null 2>&1
fi

# --- 2. RABBITMQ ---
if [[ "$rabbitmq_container" == "" ]] && [[ -n "$DOMINIO_RABBITMQ" ]]; then
    echo -e "XXX\n42\nINSTALANDO RABBITMQ...\nXXX"
    
    cat > ${NOME_RABBITMQ}.yaml << EOL
version: "3.7"
services:
  ${NOME_RABBITMQ}:
    image: rabbitmq:3-management
    hostname: ${NOME_RABBITMQ}
    environment:
      - RABBITMQ_DEFAULT_USER=$RABBIT_USER
      - RABBITMQ_DEFAULT_PASS=$RABBIT_PASS
      - RABBITMQ_ERLANG_COOKIE=server
    volumes:
      - ${NOME_RABBITMQ}_data:/var/lib/rabbitmq
    networks:
      - interna
      - externa
    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
          - node.role == manager
EOL

    if [ "$INSTALL_TYPE" = "TRADICIONAL" ]; then
    cat >> ${NOME_RABBITMQ}.yaml << EOL
      labels:
        - traefik.enable=1
        - traefik.http.routers.${NOME_RABBITMQ}.rule=Host(\`${DOMINIO_RABBITMQ}\`)
        - traefik.http.routers.${NOME_RABBITMQ}.entrypoints=websecure
        - traefik.http.routers.${NOME_RABBITMQ}.priority=1
        - traefik.http.routers.${NOME_RABBITMQ}.tls.certresolver=letsencryptresolver
        - traefik.http.routers.${NOME_RABBITMQ}.service=${NOME_RABBITMQ}
        - traefik.http.services.${NOME_RABBITMQ}.loadbalancer.server.port=15672
EOL
    fi

    cat >> ${NOME_RABBITMQ}.yaml << EOL
volumes:
  ${NOME_RABBITMQ}_data:
    external: true
    name: ${NOME_RABBITMQ}_data
networks:
  interna:
    external: true
  externa:
    external: true
EOL

    docker volume create ${NOME_RABBITMQ}_data >/dev/null 2>&1
    docker stack deploy --prune --resolve-image always -c ${NOME_RABBITMQ}.yaml ${NOME_RABBITMQ} >/dev/null 2>&1
fi

# --- 3. EVOLUTION 2.0 ---
if [[ "$evo_container" == "" ]] && [[ -n "$DOMINIO_EVOLUTION" ]]; then
    echo -e "XXX\n48\nINSTALANDO EVOLUTION 2.0...\nXXX"
    
    cat > ${NOME_EVOLUTION}.yaml << EOL
version: "3.7"
services:
  ${NOME_EVOLUTION}:
    image: atendai/evolution-api:v2.2.3
    hostname: ${NOME_EVOLUTION}
    environment:
      - SERVER_URL=https://${DOMINIO_EVOLUTION}
      - AUTHENTICATION_API_KEY=\$(openssl rand -hex 16)
      - DATABASE_ENABLED=true
      - DATABASE_PROVIDER=postgresql
      - DATABASE_CONNECTION_URI=postgres://postgres:${postgres_password}@postgres:5432/evolution
      - CACHE_REDIS_ENABLED=true
      - CACHE_REDIS_URI=redis://${NOME_EVO_REDIS}:6379/1
      - RABBITMQ_ENABLED=true
      - RABBITMQ_URI=amqp://${RABBIT_USER}:${RABBIT_PASS}@${NOME_RABBITMQ}:5672/%2F
      - RABBITMQ_EXCHANGE=evolution
      - RABBITMQ_GLOBAL_ENABLED=false
      - RABBITMQ_EVENTS_CONNECTION_UPDATE=true
    volumes:
      - ${NOME_EVOLUTION}_data:/evolution/instances
    networks:
      - interna
      - externa
    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
          - node.role == manager
EOL

    if [ "$INSTALL_TYPE" = "TRADICIONAL" ]; then
    cat >> ${NOME_EVOLUTION}.yaml << EOL
      labels:
        - traefik.enable=1
        - traefik.http.routers.${NOME_EVOLUTION}.rule=Host(\`${DOMINIO_EVOLUTION}\`)
        - traefik.http.routers.${NOME_EVOLUTION}.entrypoints=websecure
        - traefik.http.routers.${NOME_EVOLUTION}.priority=1
        - traefik.http.routers.${NOME_EVOLUTION}.tls.certresolver=letsencryptresolver
        - traefik.http.routers.${NOME_EVOLUTION}.service=${NOME_EVOLUTION}
        - traefik.http.services.${NOME_EVOLUTION}.loadbalancer.server.port=8080
EOL
    fi

    cat >> ${NOME_EVOLUTION}.yaml << EOL
volumes:
  ${NOME_EVOLUTION}_data:
    external: true
    name: ${NOME_EVOLUTION}_data
networks:
  interna:
    external: true
  externa:
    external: true
EOL

    docker volume create ${NOME_EVOLUTION}_data >/dev/null 2>&1
    docker stack deploy --prune --resolve-image always -c ${NOME_EVOLUTION}.yaml ${NOME_EVOLUTION} >/dev/null 2>&1
fi

# --- 4. EVOLUTION REDIS ---
if [[ "$evo_container" == "" ]]; then
    echo -e "XXX\n52\nINSTALANDO EVOLUTION REDIS...\nXXX"
    
    cat > ${NOME_EVO_REDIS}.yaml << EOL
version: "3.7"
services:
  ${NOME_EVO_REDIS}:
    image: redis:7.2.4
    command: ["redis-server", "--appendonly", "yes", "--port", "6379"]
    volumes:
      - ${NOME_EVO_REDIS}_data:/data
    networks:
      - interna
    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
          - node.role == manager
volumes:
  ${NOME_EVO_REDIS}_data:
    external: true
    name: ${NOME_EVO_REDIS}_data
networks:
  interna:
    external: true
EOL

    docker volume create ${NOME_EVO_REDIS}_data >/dev/null 2>&1
    docker stack deploy --prune --resolve-image always -c ${NOME_EVO_REDIS}.yaml ${NOME_EVO_REDIS} >/dev/null 2>&1
fi

# --- 5. CHATWOOT ---
if [[ "$chatwoot_container" == "" ]] && [[ -n "$DOMINIO_CHATWOOT" ]]; then
    echo -e "XXX\n56\nINSTALANDO CHATWOOT...\nXXX"
    
    cat > ${NOME_CWT_REDIS}.yaml << EOL
version: "3.7"
services:
  ${NOME_CWT_REDIS}:
    image: redis:7.2.4
    command: ["redis-server", "--appendonly", "yes", "--port", "6379"]
    volumes:
      - ${NOME_CWT_REDIS}_data:/data
    networks:
      - interna
    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
          - node.role == manager
volumes:
  ${NOME_CWT_REDIS}_data:
    external: true
    name: ${NOME_CWT_REDIS}_data
networks:
  interna:
    external: true
EOL

    docker volume create ${NOME_CWT_REDIS}_data >/dev/null 2>&1
    docker stack deploy --prune --resolve-image always -c ${NOME_CWT_REDIS}.yaml ${NOME_CWT_REDIS} >/dev/null 2>&1

    # Chatwoot Rails
    cat > ${NOME_CHATWOOT}-rails.yaml << EOL
version: "3.7"
services:
  ${NOME_CHATWOOT}-rails:
    image: chatwoot/chatwoot:latest
    hostname: ${NOME_CHATWOOT}-rails
    command: bundle exec rails s -p 3000 -b 0.0.0.0
    environment:
      - RAILS_ENV=production
      - SECRET_KEY_BASE=$CHATWOOT_SECRET
      - DATABASE_URL=postgresql://postgres:${postgres_password}@postgres:5432/chatwoot
      - REDIS_URL=redis://${NOME_CWT_REDIS}:6379/1
      - FRONTEND_URL=https://${DOMINIO_CHATWOOT}
      - RAILS_LOG_TO_STDOUT=true
    networks:
      - interna
      - externa
    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
          - node.role == manager
EOL

    if [ "$INSTALL_TYPE" = "TRADICIONAL" ]; then
    cat >> ${NOME_CHATWOOT}-rails.yaml << EOL
      labels:
        - traefik.enable=1
        - traefik.http.routers.${NOME_CHATWOOT}.rule=Host(\`${DOMINIO_CHATWOOT}\`)
        - traefik.http.routers.${NOME_CHATWOOT}.entrypoints=websecure
        - traefik.http.routers.${NOME_CHATWOOT}.priority=1
        - traefik.http.routers.${NOME_CHATWOOT}.tls.certresolver=letsencryptresolver
        - traefik.http.routers.${NOME_CHATWOOT}.service=${NOME_CHATWOOT}
        - traefik.http.services.${NOME_CHATWOOT}.loadbalancer.server.port=3000
EOL
    fi

    cat >> ${NOME_CHATWOOT}-rails.yaml << EOL
networks:
  interna:
    external: true
  externa:
    external: true
EOL

    docker stack deploy --prune --resolve-image always -c ${NOME_CHATWOOT}-rails.yaml ${NOME_CHATWOOT} >/dev/null 2>&1
fi

# --- 6. N8N ---
if [[ "$n8n_container" == "" ]] && [[ -n "$DOMINIO_N8N" ]]; then
    echo -e "XXX\n62\nINSTALANDO N8N...\nXXX"
    
    cat > ${NOME_N8N}.yaml << EOL
version: "3.7"
services:
  ${NOME_N8N}:
    image: n8nio/n8n:latest
    hostname: ${NOME_N8N}
    environment:
      - N8N_BASIC_AUTH_ACTIVE=true
      - N8N_BASIC_AUTH_USER=$N8N_USER
      - N8N_BASIC_AUTH_PASSWORD=$N8N_PASS
      - N8N_HOST=${DOMINIO_N8N}
      - N8N_PORT=5678
      - N8N_PROTOCOL=https
      - WEBHOOK_URL=https://${DOMINIO_N8N}
      - DB_TYPE=postgresdb
      - DB_POSTGRESDB_HOST=postgres
      - DB_POSTGRESDB_DATABASE=n8n
      - DB_POSTGRESDB_USER=postgres
      - DB_POSTGRESDB_PASSWORD=$postgres_password
    volumes:
      - ${NOME_N8N}_data:/home/node/.n8n
    networks:
      - interna
      - externa
    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
          - node.role == manager
EOL

    if [ "$INSTALL_TYPE" = "TRADICIONAL" ]; then
    cat >> ${NOME_N8N}.yaml << EOL
      labels:
        - traefik.enable=1
        - traefik.http.routers.${NOME_N8N}.rule=Host(\`${DOMINIO_N8N}\`)
        - traefik.http.routers.${NOME_N8N}.entrypoints=websecure
        - traefik.http.routers.${NOME_N8N}.priority=1
        - traefik.http.routers.${NOME_N8N}.tls.certresolver=letsencryptresolver
        - traefik.http.routers.${NOME_N8N}.service=${NOME_N8N}
        - traefik.http.services.${NOME_N8N}.loadbalancer.server.port=5678
EOL
    fi

    cat >> ${NOME_N8N}.yaml << EOL
volumes:
  ${NOME_N8N}_data:
    external: true
    name: ${NOME_N8N}_data
networks:
  interna:
    external: true
  externa:
    external: true
EOL

    docker volume create ${NOME_N8N}_data >/dev/null 2>&1
    docker stack deploy --prune --resolve-image always -c ${NOME_N8N}.yaml ${NOME_N8N} >/dev/null 2>&1
fi

# --- 7. OLLAMA ---
if [[ "$ollama_container" == "" ]]; then
    echo -e "XXX\n68\nINSTALANDO OLLAMA...\nXXX"
    
    cat > ${NOME_OLLAMA}.yaml << EOL
version: "3.7"
services:
  ${NOME_OLLAMA}:
    image: ollama/ollama:latest
    hostname: ${NOME_OLLAMA}
    volumes:
      - ${NOME_OLLAMA}_data:/root/.ollama
    networks:
      - interna
    deploy:
      mode: replicated
      replicas: 1
      resources:
        limits:
          cpus: "4"
          memory: 8192M
      placement:
        constraints:
          - node.role == manager
volumes:
  ${NOME_OLLAMA}_data:
    external: true
    name: ${NOME_OLLAMA}_data
networks:
  interna:
    external: true
EOL

    docker volume create ${NOME_OLLAMA}_data >/dev/null 2>&1
    docker stack deploy --prune --resolve-image always -c ${NOME_OLLAMA}.yaml ${NOME_OLLAMA} >/dev/null 2>&1
fi

# --- 8. QDRANT ---
if [[ "$qdrant_container" == "" ]]; then
    echo -e "XXX\n72\nINSTALANDO QDRANT...\nXXX"
    
    cat > ${NOME_QDRANT}.yaml << EOL
version: "3.7"
services:
  ${NOME_QDRANT}:
    image: qdrant/qdrant:latest
    hostname: ${NOME_QDRANT}
    volumes:
      - ${NOME_QDRANT}_data:/qdrant/storage
    networks:
      - interna
    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
          - node.role == manager
volumes:
  ${NOME_QDRANT}_data:
    external: true
    name: ${NOME_QDRANT}_data
networks:
  interna:
    external: true
EOL

    docker volume create ${NOME_QDRANT}_data >/dev/null 2>&1
    docker stack deploy --prune --resolve-image always -c ${NOME_QDRANT}.yaml ${NOME_QDRANT} >/dev/null 2>&1
fi

# --- 9. LITELLM ---
if [[ "$litellm_container" == "" ]] && [[ -n "$DOMINIO_LITELLM" ]]; then
    echo -e "XXX\n76\nINSTALANDO LITELLM...\nXXX"
    
    # Criar config do LiteLLM com Ollama
    cat > /tmp/litellm_config.yaml << EOL
model_list:
  - model_name: gpt-3.5-turbo
    litellm_params:
      model: ollama/llama3.2
      api_base: http://${NOME_OLLAMA}:11434
  - model_name: gpt-4
    litellm_params:
      model: ollama/llama3.2
      api_base: http://${NOME_OLLAMA}:11434
  - model_name: local-embeddings
    litellm_params:
      model: ollama/nomic-embed-text
      api_base: http://${NOME_OLLAMA}:11434

general_settings:
  master_key: sk-${LITELLM_KEY}

litellm_settings:
  drop_params: true
  disable_spend_logs: true
EOL

    cat > ${NOME_LITELLM}.yaml << EOL
version: "3.7"
services:
  ${NOME_LITELLM}:
    image: ghcr.io/berriai/litellm:main-v1.68.1
    hostname: ${NOME_LITELLM}
    command: --config /app/config.yaml
    environment:
      - DATABASE_URL=postgres://postgres:${postgres_password}@postgres:5432/litellm
      - STORE_MODEL_IN_DB=true
      - LITELLM_DROP_PARAMS=true
      - LITELLM_MASTER_KEY=sk-${LITELLM_KEY}
      - UI_USERNAME=${LITELLM_USER}
      - UI_PASSWORD=${LITELLM_PASS}
    volumes:
      - /tmp/litellm_config.yaml:/app/config.yaml:ro
    networks:
      - interna
      - externa
    deploy:
      mode: replicated
      replicas: 1
      resources:
        limits:
          cpus: "2"
          memory: 1524M
      placement:
        constraints:
          - node.role == manager
EOL

    if [ "$INSTALL_TYPE" = "TRADICIONAL" ]; then
    cat >> ${NOME_LITELLM}.yaml << EOL
      labels:
        - traefik.enable=1
        - traefik.http.routers.${NOME_LITELLM}.rule=Host(\`${DOMINIO_LITELLM}\`)
        - traefik.http.routers.${NOME_LITELLM}.entrypoints=websecure
        - traefik.http.routers.${NOME_LITELLM}.priority=1
        - traefik.http.routers.${NOME_LITELLM}.tls.certresolver=letsencryptresolver
        - traefik.http.routers.${NOME_LITELLM}.service=${NOME_LITELLM}
        - traefik.http.services.${NOME_LITELLM}.loadbalancer.server.port=4000
EOL
    fi

    cat >> ${NOME_LITELLM}.yaml << EOL
networks:
  interna:
    external: true
  externa:
    external: true
EOL

    docker stack deploy --prune --resolve-image always -c ${NOME_LITELLM}.yaml ${NOME_LITELLM} >/dev/null 2>&1
fi

# --- 10. CRIAR DATABASES EXTRAS ---
CONTAINER_ID=$(docker ps -q -f "name=^postgres_")
if [ -n "$CONTAINER_ID" ]; then
    docker exec -i $CONTAINER_ID psql -U postgres -c "CREATE DATABASE n8n;" 2>/dev/null
fi

# ============================================================
# MENSAGEM FINAL
# ============================================================
echo -e "XXX\n95\nFINALIZANDO INSTALACAO...\nXXX"
sleep 5
echo -e "XXX\n100\nINSTALACAO CONCLUIDA!\nXXX"

}|whiptail --title "AI CUSTOMER SERVICE PLATFORM - INSTALACAO" --gauge "Aguarde a instalacao dos servicos..." 6 70 0

# --- TELA FINAL ---
clear
echo -e "${verde}"
echo "============================================="
echo "  AI CUSTOMER SERVICE PLATFORM - INSTALADO!"
echo "============================================="
echo -e "${reset}"
echo ""
echo "SERVICOS INSTALADOS:"
echo ""
[[ -n "$DOMINIO_MINIO" ]] && echo "  MinIO (Storage):    https://$DOMINIO_MINIO"
[[ -n "$DOMINIO_CHATWOOT" ]] && echo "  Chatwoot (CRM):     https://$DOMINIO_CHATWOOT"
[[ -n "$DOMINIO_EVOLUTION" ]] && echo "  Evolution (API):    https://$DOMINIO_EVOLUTION"
[[ -n "$DOMINIO_RABBITMQ" ]] && echo "  RabbitMQ (Filas):   https://$DOMINIO_RABBITMQ"
[[ -n "$DOMINIO_N8N" ]] && echo "  n8n (Automacao):    https://$DOMINIO_N8N"
[[ -n "$DOMINIO_LITELLM" ]] && echo "  LiteLLM (AI GW):    https://$DOMINIO_LITELLM"
echo "  Ollama (LLM):       Interno (porta 11434)"
echo "  Qdrant (Vector):    Interno (porta 6333)"
echo ""
echo "CREDENCIAIS:"
echo ""
[[ -n "$MINIO_USER" ]] && echo "  MinIO:      $MINIO_USER / $MINIO_PASS"
[[ -n "$RABBIT_USER" ]] && echo "  RabbitMQ:   $RABBIT_USER / $RABBIT_PASS"
[[ -n "$N8N_USER" ]] && echo "  n8n:        $N8N_USER / $N8N_PASS"
[[ -n "$LITELLM_USER" ]] && echo "  LiteLLM:    $LITELLM_USER / $LITELLM_PASS"
[[ -n "$LITELLM_KEY" ]] && echo "  LiteLLM Key: sk-${LITELLM_KEY}"
echo ""
echo "INTEGRACAO AI:"
echo ""
echo "  LiteLLM conecta ao Ollama (http://${NOME_OLLAMA}:11434)"
echo "  Qdrant para embeddings (http://${NOME_QDRANT}:6333)"
echo "  n8n pode chamar LiteLLM para workflows AI"
echo "  Chatwoot pode usar n8n para respostas automaticas"
echo ""
echo "PROXIMOS PASSOS:"
echo ""
echo "  1. Acesse o Ollama e baixe um modelo:"
echo "     docker exec -it ollama-ai ollama pull llama3.2"
echo ""
echo "  2. No LiteLLM, configure os modelos via UI"
echo ""
echo "  3. No n8n, crie workflows que conectam:"
echo "     Chatwoot → n8n → LiteLLM → Chatwoot"
echo ""
echo "============================================="
echo -e "${reset}"

cd /

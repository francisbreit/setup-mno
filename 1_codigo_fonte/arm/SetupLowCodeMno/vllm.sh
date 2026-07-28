#!/usr/bin/bash
# LOADING
SCRIPTS_VERSION="4.77.0"
loading() {
    local i=0
    local char=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")
    while true; do
        echo -ne "\r${char[$i]} $1"
        ((i = (i + 1) % 10))
        sleep 0.1
    done
}

GREEN="\\033[32m"
RED="\\033[31m"
YELLOW="\\033[33m"
RESET="\\033[0m"

msg() { echo -e "$1"; }

# DETECÇÃO DO TIPO DE INSTALAÇÃO
INSTALL_TYPE_FILE="/root/.cloudflared_config/installation_type"
if [ -f "$INSTALL_TYPE_FILE" ]; then
    INSTALL_TYPE=$(cat "$INSTALL_TYPE_FILE")
else
    INSTALL_TYPE="TRADICIONAL"
fi

# CARREGAMENTO DE CREDENCIAIS
if [ "$INSTALL_TYPE" = "CLOUDFLARE_TUNNEL" ]; then
    if [ -f "/root/.cloudflared_config/cloudflare_credentials" ]; then
        source "/root/.cloudflared_config/cloudflare_credentials"
    fi
else
    if [ -f "/root/.tradicional_config/tradicional_credentials" ]; then
        source "/root/.tradicional_config/tradicional_credentials"
    fi
fi

# FALLBACK
if [ -z "$nome_servidor" ]; then
    nome_servidor=$(hostname -I | awk '{print $1}')
fi

# CARREGAR SENHA DO POSTGRES
postgres_password=$(grep -oP '(?<=POSTGRES_PASSWORD=).+' /root/postgres.yaml 2>/dev/null || echo "postgres")

while true; do
    opcao=$(whiptail --title "INSTALAÇÃO DO VLLM" --menu "O que deseja fazer?" --fb 12 60 2 "1" "Instalar vLLM" "2" "Sair" 3>&1 1>&2 2>&3)
    case $opcao in "1") break;; "2") exit 0;; *) msg "Opção inválida";; esac
done

while true; do
    url_vllm=$(whiptail --title "1/3 - URL do vLLM" --inputbox "Digite o domínio (ex: llm.dominio.com):" --fb 12 60 3>&1 1>&2 2>&3) ; saida=$?
    if [[ $saida -eq '0' ]]; then [[ -z $url_vllm ]] && { msg "Digite o link"; continue; } || break
    else echo $url_vllm; echo "saindo..." & exit 0; fi
done

while true; do
    model_vllm=$(whiptail --title "Modelo LLM" --inputbox "Digite o nome do modelo a carregar (ex: Qwen/Qwen2.5-1.5B-Instruct):" --fb 12 60 3>&1 1>&2 2>&3) ; saida=$?
    if [[ $saida -eq '0' ]]; then [[ -z $model_vllm ]] && { msg "Digite o modelo"; continue; } || break
    else echo $model_vllm; echo "saindo..." & exit 0; fi
done

while true; do
    kv_cache=$(whiptail --title "KV Cache Space (GB)" --inputbox "Digite o espaço em GB para KV Cache (ex: 8):" --fb 12 60 3>&1 1>&2 2>&3) ; saida=$?
    if [[ $saida -eq '0' ]]; then
        [[ -z $kv_cache ]] && kv_cache="8"
        [[ "$kv_cache" =~ ^[0-9]+$ ]] && break || msg "Digite apenas números"
    else echo $kv_cache; echo "saindo..." & exit 0; fi
done

while true; do
    criar_portainer=$(whiptail --title "4/4 - Criar Stack no Portainer?" --inputbox "Digite 0 (Portainer) ou 1 (Docker):" --fb 12 60 3>&1 1>&2 2>&3) ; saida=$?
    if [[ $saida -eq '0' ]]; then
        if [[ "$criar_portainer" != "0" && "$criar_portainer" != "1" ]]; then msg "Digite 0 ou 1"; continue; else break; fi
    else echo $criar_portainer; echo "saindo..." & exit 0; fi
done

# TELA DE CONFIRMAÇÃO
whiptail --title "CONFIRMAÇÃO" --yesno "Confirme os dados:\n\nDomínio: $url_vllm\nModelo: $model_vllm\nKV Cache: ${kv_cache}GB\nTunnel: $INSTALL_TYPE\nPortainer: $criar_portainer" --fb 16 60
if [[ $? -ne 0 ]]; then echo "Cancelado"; exit 1; fi

# INÍCIO DA INSTALAÇÃO
(
echo "XXX\n10\nConfigurando DNS...\nXXX"
sleep 1

# GERAR SUFIXO ÚNICO
nome_principal="vllm"
sufixo_app=$(date | md5sum | head -c7)
nome_app=$nome_principal$sufixo_app

# CONFIGURAR DNS
if [ -n "$CLOUDFLARE_API_TOKEN" ] && [ -n "$CLOUDFLARE_ZONE_ID" ]; then
    if [ "$INSTALL_TYPE" = "TRADICIONAL" ]; then
        CNAME_RESPONSE=$(curl -s -X POST "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records" \
            -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
            -H "Content-Type: application/json" \
            --data '{"type":"CNAME","name":"'"$url_vllm"'","content":"'"$nome_servidor"'.'"$DOMINIO_PRINCIPAL"'","ttl":1,"proxied":false}')
    elif [ "$INSTALL_TYPE" = "CLOUDFLARE_TUNNEL" ]; then
        CNAME_RESPONSE=$(curl -s -X POST "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records" \
            -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
            -H "Content-Type: application/json" \
            --data '{"type":"CNAME","name":"'"$url_vllm"'","content":"'"$TUNNEL_ID"'.cfargotunnel.com","ttl":1,"proxied":true}')
    fi
fi

echo "XXX\n25\nCriando volumes...\nXXX"
sleep 1
docker volume create ${nome_app}_cache >/dev/null 2>&1

echo "XXX\n30\nCriando arquivo YAML...\nXXX"
cd
cd

cat > $nome_app.yaml << 'EOL'
version: "3.7"
services:
EOL

cat >> $nome_app.yaml << EOL
  $nome_app:
    image: vllm/vllm-openai-cpu:latest
    hostname: $nome_app
    shm_size: ${kv_cache}g
    networks:
      - externa
      - interna
    environment:
      - VLLM_CPU_KVCACHE_SPACE=$kv_cache
    volumes:
      - ${nome_app}_cache:/root/.cache/huggingface
    command: --model $model_vllm --port 8000 --host 0.0.0.0
    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
          - node.role == manager
      resources:
        limits:
          cpus: "4"
          memory: ${kv_cache}G
EOL

# LABELS TRAEFIK (APENAS TRADICIONAL)
if [ "$INSTALL_TYPE" = "TRADICIONAL" ]; then
cat >> $nome_app.yaml << EOL
      labels:
        - traefik.enable=true
        - traefik.docker.network=externa
        - traefik.http.routers.${nome_app}.rule=Host(\`$url_vllm\`)
        - traefik.http.routers.${nome_app}.entrypoints=websecure
        - traefik.http.routers.${nome_app}.priority=1
        - traefik.http.routers.${nome_app}.tls.certresolver=letsencryptresolver
        - traefik.http.routers.${nome_app}.tls=true
        - traefik.http.routers.${nome_app}.service=${nome_app}
        - traefik.http.services.${nome_app}.loadbalancer.server.port=8000
EOL
fi

cat >> $nome_app.yaml << EOL

networks:
  externa:
    external: true
  interna:
    external: true

volumes:
  ${nome_app}_cache:
    external: true
    name: ${nome_app}_cache
EOL

echo "XXX\n50\nRealizando deploy...\nXXX"
sleep 1

# DEPLOY
dados_file="$HOME/dados_portainer/dados_portainer"

if [ "$criar_portainer" = "0" ] && [ -f "$dados_file" ]; then
    PORTAINER_URL=$(grep "Dominio do portainer:" "$dados_file" | cut -d':' -f2 | xargs)
    ADMIN_USERNAME=$(grep "Usuario:" "$dados_file" | cut -d':' -f2 | xargs)
    ADMIN_PASSWORD=$(grep "Senha:" "$dados_file" | cut -d':' -f2 | xargs)
    STACK_NAME=$nome_app
    STACK_FILE_PATH="/root/$nome_app.yaml"

    get_auth_token() {
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
        RESPONSE=$(curl -sS -X GET "https://$PORTAINER_URL/api/endpoints" \
            -H "Authorization: Bearer $TOKEN")
        ENDPOINT_ID=$(echo "$RESPONSE" | jq -r '.[0].Id')
        if [ -z "$ENDPOINT_ID" ] || [ "$ENDPOINT_ID" = "null" ]; then
            docker stack deploy --prune --resolve-image always -c $nome_app.yaml $nome_app >/dev/null 2>&1
            exit 1
        fi
    }
    get_swarm_id() {
        RESPONSE=$(curl -sS -X GET "https://$PORTAINER_URL/api/endpoints/$ENDPOINT_ID/docker/swarm" \
            -H "Authorization: Bearer $TOKEN")
        SWARM_ID=$(echo "$RESPONSE" | jq -r '.ID')
        if [ -z "$SWARM_ID" ] || [ "$SWARM_ID" = "null" ]; then
            docker stack deploy --prune --resolve-image always -c $nome_app.yaml $nome_app >/dev/null 2>&1
            exit 1
        fi
    }
    create_stack() {
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
else
    docker stack deploy --prune --resolve-image always -c $nome_app.yaml $nome_app >/dev/null 2>&1
fi

echo "XXX\n75\nAguardando serviços...\nXXX"
sleep 5

# CONFIGURAR TUNNEL (CLOUDFLARE_TUNNEL)
if [ "$INSTALL_TYPE" = "CLOUDFLARE_TUNNEL" ] && [ -n "$CLOUDFLARE_API_TOKEN" ] && [ -n "$TUNNEL_ID" ]; then
    TIMESTAMP=$(date -u +%Y%m%dT%H%M%SZ)
    TMPDIR=$(mktemp -d)
    BACKUP_RAW="$TMPDIR/backup_raw.$TIMESTAMP.json"
    TO_PUT="$TMPDIR/to_put.$TIMESTAMP.json"
    curl -sS -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
      "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/cfd_tunnel/$TUNNEL_ID/configurations" \
      | jq '.' > "$BACKUP_RAW"
    NEW_SERVICE="http://${nome_app}:8000"
    jq --arg host "$url_vllm" --arg service "$NEW_SERVICE" '
      (.result.config // {}) as $cfg
      | ($cfg.ingress // []) as $ing
      | ($ing | map(select(.service != "http_status:404"))) as $clean
      | ($clean | map(select(.hostname != $host))) as $filtered
      | ($filtered + [ { hostname: $host, service: $service, originRequest: { noTlsVerify: true, httpHostHeader: $host } } ]) as $merged
      | ($merged + [{ service: "http_status:404" }]) as $final_ing
      | ($cfg + { ingress: $final_ing }) as $newcfg
      | { config: $newcfg }
    ' "$BACKUP_RAW" > "$TO_PUT"
    curl -sS -X PUT "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/cfd_tunnel/$TUNNEL_ID/configurations" \
      -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
      -H "Content-Type: application/json" \
      --data-binary @"$TO_PUT" >/dev/null 2>&1
    rm -rf "$TMPDIR"
fi

echo "XXX\n100\nINSTALAÇÃO CONCLUÍDA!\nXXX"
sleep 2
) |
whiptail --title "SETUPMNO v4.77.0" --gauge "Aguarde a instalação do vLLM..." 8 60 0

# TELA FINAL
if [ "$INSTALL_TYPE" = "CLOUDFLARE_TUNNEL" ]; then
    whiptail --title "Mensagem" --msgbox "vLLM instalado!\n\nAPI Endpoint: https://$url_vllm\nModelo: $model_vllm\n\nAPI OpenAI-compatible:\n- POST /v1/chat/completions\n- GET /v1/models\n- GET /health\n\nUse a API com qualquer cliente OpenAI-compatible.\n\nPressione ENTER." 22 78
else
    whiptail --title "Mensagem" --msgbox "vLLM instalado!\n\nAPI Endpoint: https://$url_vllm\n\nAPI OpenAI-compatible:\n- POST /v1/chat/completions\n- GET /v1/models\n- GET /health\n\nPressione ENTER." 22 78
fi

exit 0

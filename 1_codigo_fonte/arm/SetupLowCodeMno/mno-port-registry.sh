#!/usr/bin/bash
# ==============================================================================
# Setup MNO — Registro e Consulta da Lista Telefônica Universal de Portas
# Permite consultar, registrar e auditar portas canônicas de 172+ aplicações
# Utilizado pelo Fleet Clone, instaladores e criadores de novos setups.
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REGISTRY_FILE=""

# Encontrar arquivo de registro com fallback
for candidate in \
    "/root/SetupLowCodeMno/mno_universal_ports.json" \
    "$SCRIPT_DIR/mno_universal_ports.json" \
    "/root/SetupLowCodeMno/.control/mno_universal_ports.json"; do
    if [ -f "$candidate" ]; then
        REGISTRY_FILE="$candidate"
        break
    fi
done

if [ -z "$REGISTRY_FILE" ]; then
    REGISTRY_FILE="$SCRIPT_DIR/mno_universal_ports.json"
fi

cmd="${1:-help}"

case "$cmd" in
    get)
        app="${2:-}"
        [ -z "$app" ] && { echo "80"; exit 0; }
        app_norm=$(echo "$app" | tr '[:upper:]' '[:lower:]')

        if [ -f "$REGISTRY_FILE" ] && command -v jq >/dev/null 2>&1; then
            # 1. Busca exata pela chave
            exact_port=$(jq -r --arg a "$app_norm" '.ports[$a].port // empty' "$REGISTRY_FILE" 2>/dev/null || true)
            if [ -n "$exact_port" ] && [ "$exact_port" != "null" ]; then
                echo "$exact_port"
                exit 0
            fi

            # 2. Busca por substring / prefixo em chaves existentes
            fuzzy_port=$(jq -r --arg a "$app_norm" '
                .ports | to_entries | map(select($a | contains(.key) or (.key | contains($a)))) | first | .value.port // empty
            ' "$REGISTRY_FILE" 2>/dev/null || true)
            if [ -n "$fuzzy_port" ] && [ "$fuzzy_port" != "null" ]; then
                echo "$fuzzy_port"
                exit 0
            fi
        fi

        # 3. Fallback inteligente baseado nas regras canônicas do Setup MNO
        case "$app_norm" in
            *nginxproxymanager*) echo "81" ;;
            *planka*|*strap*|*strapi*) echo "1337" ;;
            *pocketid*) echo "1411" ;;
            *immich*) echo "2283" ;;
            *photoprism*) echo "2342" ;;
            *ghost*) echo "2368" ;;
            *botpress*|*calcom*|*chatwoot*|*dify*|*docmost*|*documenso*|*docuseal*|*evoai*|*flowise*|*formbricks*|*gitea*|*grafana*|*karakeep*|*langfuse*|*linkwarden*|*lowcoder*|*maybe*|*memgraph*|*metabase*|*milvus*|*outline*|*reactiveresume*|*rocketchat*|*tooljet*|*twentycrm*|*typebot*|*umami*|*waha*|*wikijs*|*woofedcrm*) echo "3000" ;;
            *anythingllm*|*uptime*|*uptimekuma*) echo "3001" ;;
            *firecrawl*) echo "3002" ;;
            *affine*) echo "3010" ;;
            *librechat*) echo "3080" ;;
            *paperclip*) echo "3100" ;;
            *lobechat*) echo "3210" ;;
            *vikunja*) echo "3456" ;;
            *evolutiongo*|*litellm*) echo "4000" ;;
            *databasus*) echo "4005" ;;
            *openfang*) echo "4200" ;;
            *navidrome*) echo "4533" ;;
            *changedetection*) echo "5000" ;;
            *actualbudget*) echo "5006" ;;
            *openobserve*) echo "5080" ;;
            *memos*) echo "5230" ;;
            *redisinsight*) echo "5540" ;;
            *n8n*) echo "5678" ;;
            *qdrant*) echo "6333" ;;
            *siyuan*) echo "6806" ;;
            *neo4j*) echo "7474" ;;
            *meilisearch*) echo "7700" ;;
            *langflow*) echo "7860" ;;
            *focalboard*|*vllm*|*windmill*|*zep*|*paperless*|*chromadb*|*cognee*) echo "8000" ;;
            *directus*) echo "8055" ;;
            *mattermost*) echo "8065" ;;
            *odoo*) echo "8069" ;;
            *evolution*|*evo*|*dozzle*|*glance*|*netdada*|*nocodb*|*openproject*|*openwebui*|*penpot*|*searxng*|*setupmno_control*|*stirlingpdf*|*triliumnext*|*weaviate*|*wekan*|*wuzap*|*homepage*|*infisical*|*keycloak*|*moodle*) echo "8080" ;;
            *autogen*|*redicommander*) echo "8081" ;;
            *superset*) echo "8088" ;;
            *beszel*|*pocketbase*) echo "8090" ;;
            *jellyfin*) echo "8096" ;;
            *clickhouse*|*homeassistant*) echo "8123" ;;
            *duplicati*) echo "8200" ;;
            *syncthing*) echo "8384" ;;
            *codeserver*) echo "8443" ;;
            *minio*) echo "9001" ;;
            *portainer*) echo "9000" ;;
            *hermes*) echo "9119" ;;
            *heyform*) echo "9157" ;;
            *ollama*) echo "11434" ;;
            *nocobase*) echo "13000" ;;
            *rabbitmq*) echo "15672" ;;
            *openclaw*) echo "18789" ;;
            *joplin*) echo "22300" ;;
            *quepasa*) echo "31000" ;;
            *) echo "80" ;;
        esac
        ;;

    register)
        app="${2:-}"
        port="${3:-}"
        service="${4:-}"
        category="${5:-geral}"

        if [ -z "$app" ] || [ -z "$port" ]; then
            echo "Uso: $0 register <nome_app> <porta> [nome_servico] [categoria]" >&2
            exit 1
        fi

        app_norm=$(echo "$app" | tr '[:upper:]' '[:lower:]')
        [ -z "$service" ] && service="${app_norm}_app"

        # Inicializa se não existir
        if [ ! -f "$REGISTRY_FILE" ]; then
            mkdir -p "$(dirname "$REGISTRY_FILE")"
            echo '{"version":"1.0","description":"Lista Telefonica Universal - Setup MNO","totalEntries":0,"updatedAt":"","ports":{}}' > "$REGISTRY_FILE"
        fi

        tmp_json=$(mktemp)
        now=$(date -u +%Y-%m-%dT%H:%M:%SZ)

        jq --arg a "$app_norm" \
           --argjson p "$port" \
           --arg s "$service" \
           --arg c "$category" \
           --arg now "$now" '
            .ports[$a] = {
                appName: $a,
                port: $p,
                service: $s,
                category: $c,
                multiPorts: null
            } |
            .updatedAt = $now |
            .totalEntries = (.ports | length)
        ' "$REGISTRY_FILE" > "$tmp_json"

        mv "$tmp_json" "$REGISTRY_FILE"
        chmod 644 "$REGISTRY_FILE"
        echo "[+] Aplicação '$app_norm' registrada com sucesso na porta $port na Lista Telefônica Universal!"
        ;;

    check)
        port="${2:-}"
        [ -z "$port" ] && { echo "Uso: $0 check <porta>"; exit 1; }

        if [ -f "$REGISTRY_FILE" ] && command -v jq >/dev/null 2>&1; then
            matches=$(jq -r --argjson p "$port" '
                .ports | to_entries | map(select(.value.port == $p)) | map(.key) | join(", ")
            ' "$REGISTRY_FILE" 2>/dev/null || true)

            if [ -n "$matches" ] && [ "$matches" != "null" ]; then
                echo "⚠️  Porta $port em uso por: $matches"
            else
                echo "✅ Porta $port está LIVRE na Lista Telefônica Universal."
            fi
        fi
        ;;

    list)
        if [ -f "$REGISTRY_FILE" ] && command -v jq >/dev/null 2>&1; then
            echo "================================================================="
            echo "   LISTA TELEFÔNICA UNIVERSAL DE APLICAÇÕES - SETUP MNO"
            echo "================================================================="
            printf "%-30s | %-8s | %-20s | %-15s\n" "APLICAÇÃO" "PORTA" "SERVIÇO" "CATEGORIA"
            echo "-------------------------------+----------+----------------------+----------------"
            jq -r '
                .ports | to_entries | sort_by(.value.port)[] |
                [.key, (.value.port | tostring), (.value.service // "-"), (.value.category // "-")] |
                @tsv
            ' "$REGISTRY_FILE" | while IFS=$'\t' read -r k p s c; do
                printf "%-30s | %-8s | %-20s | %-15s\n" "$k" "$p" "$s" "$c"
            done
            total=$(jq '.ports | length' "$REGISTRY_FILE")
            echo "-----------------------------------------------------------------"
            echo "Total de aplicações registradas: $total"
        fi
        ;;

    *)
        echo "Uso: $0 {get <app>|register <app> <porta> [servico] [cat]|check <porta>|list}"
        exit 1
        ;;
esac

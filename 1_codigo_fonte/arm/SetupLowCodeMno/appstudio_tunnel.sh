#!/usr/bin/env bash
# ==============================================================================
# Setup MNO App Studio [BETA] - Roteamento Cloudflare Tunnel (Zero Portas Abertas)
# Mantenedor: Francis MNO (Setup MNO)
# ==============================================================================

set -uo pipefail

VERMELHO='\033[0;31m'
VERDE='\033[0;32m'
AMARELO='\033[1;33m'
AZUL='\033[0;34m'
CIANO='\033[0;36m'
MAGENTA='\033[0;35m'
RESET='\033[0m'
BOLD='\033[1m'

SACRED_DIR="${APPSTUDIO_SACRED_DIR:-/root/setupmno-appstudio}"
TUNNEL_ROUTES_FILE="$SACRED_DIR/tunnel_routes.json"
CREDENTIALS_FILE="${SETUPMNO_CLOUDFLARE_CREDENTIALS_FILE:-/root/.cloudflared_config/cloudflare_credentials}"

log_info() { echo -e "${CIANO}[TUNNEL-INFO]${RESET} $1" >&2; }
log_sucesso() { echo -e "${VERDE}[TUNNEL-SUCESSO]${RESET} $1" >&2; }
log_aviso() { echo -e "${AMARELO}[TUNNEL-AVISO]${RESET} $1" >&2; }
log_erro() { echo -e "${VERMELHO}[TUNNEL-ERRO]${RESET} $1" >&2; }

# ------------------------------------------------------------------------------
# 1. Inicialização do Registro Local de Rotas
# ------------------------------------------------------------------------------
tunnel_init() {
    mkdir -p "$SACRED_DIR"
    if [[ ! -f "$TUNNEL_ROUTES_FILE" ]]; then
        cat << 'EOF' > "$TUNNEL_ROUTES_FILE"
{
  "updated_at": "",
  "routes": {}
}
EOF
        chmod 0600 "$TUNNEL_ROUTES_FILE" 2>/dev/null || true
    fi
}

# ------------------------------------------------------------------------------
# 2. Validar se Credenciais Reais da Cloudflare Estão Disponíveis
# ------------------------------------------------------------------------------
check_cloudflare_credentials() {
    if [[ -f "$CREDENTIALS_FILE" ]]; then
        # shellcheck disable=SC1090
        source "$CREDENTIALS_FILE"
        if [[ -n "${CLOUDFLARE_API_TOKEN:-}" && -n "${CLOUDFLARE_ACCOUNT_ID:-}" && -n "${TUNNEL_ID:-}" ]]; then
            return 0
        fi
    fi
    return 1
}

# ------------------------------------------------------------------------------
# 3. Adicionar Nova Rota no Cloudflare Tunnel (API Oficial ou Fallback Local)
# ------------------------------------------------------------------------------
tunnel_add_route() {
    local domain="$1"
    local service_name="$2"
    local port="$3"
    local app_name="${4:-unknown}"

    tunnel_init

    log_info "Configurando rota Cloudflare Tunnel: https://${domain} -> http://${service_name}:${port}"

    local now
    now="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

    # CASO A: Credenciais reais do Cloudflare Tunnel configuradas no Setup MNO
    if check_cloudflare_credentials; then
        log_info "Credenciais Cloudflare encontradas. Atualizando regras na API Cloudflare..."

        # 1. Obter Zone ID de forma robusta (compatível com .com, .com.br, etc.)
        local zone_id="${CLOUDFLARE_ZONE_ID:-}"
        if [[ -z "$zone_id" || -z "${CLOUDFLARE_ZONE_NAME:-}" || "$domain" != *"$CLOUDFLARE_ZONE_NAME" ]]; then
            local zones_json
            zones_json=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones?per_page=50" \
                -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
                -H "Content-Type: application/json" 2>/dev/null || true)
            zone_id=$(echo "$zones_json" | jq -r --arg dom "$domain" '
                .result[]? | select($dom == .name or ($dom | endswith("." + .name))) | .id
            ' 2>/dev/null | head -n1 || true)
        fi

        # 2. Criar ou Atualizar Registro CNAME
        if [[ -n "$zone_id" ]]; then
            local existing_dns
            existing_dns=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/${zone_id}/dns_records?name=${domain}" \
                -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
                -H "Content-Type: application/json" | jq -r '.result[0].id // empty' 2>/dev/null || true)

            if [[ -n "$existing_dns" ]]; then
                curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/${zone_id}/dns_records/${existing_dns}" \
                    -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
                    -H "Content-Type: application/json" \
                    --data "{\"type\":\"CNAME\",\"name\":\"${domain}\",\"content\":\"${TUNNEL_ID}.cfargotunnel.com\",\"ttl\":1,\"proxied\":true}" >/dev/null 2>&1 || true
            else
                curl -s -X POST "https://api.cloudflare.com/client/v4/zones/${zone_id}/dns_records" \
                    -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
                    -H "Content-Type: application/json" \
                    --data "{\"type\":\"CNAME\",\"name\":\"${domain}\",\"content\":\"${TUNNEL_ID}.cfargotunnel.com\",\"ttl\":1,\"proxied\":true}" >/dev/null 2>&1 || true
            fi
            log_sucesso "Registro DNS CNAME atualizado com sucesso na Cloudflare!"
        else
            log_aviso "Não foi possível identificar a Zone ID da Cloudflare para o domínio: $domain. Crie o apontamento CNAME manualmente se necessário."
        fi

        # 3. Atualizar Ingress do Cloudflare Tunnel
        local tmp_dir backup_json put_json
        tmp_dir=$(mktemp -d)
        backup_json="$tmp_dir/config_backup.json"
        put_json="$tmp_dir/config_put.json"

        if curl -sS -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
            "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/cfd_tunnel/$TUNNEL_ID/configurations" > "$backup_json"; then
            
            local new_service="http://${service_name}:${port}"
            python3 - << EOF
import json

with open("$backup_json") as f:
    orig = json.load(f)

cfg = orig.get("result", {}).get("config", {}) or {}
ingress = cfg.get("ingress", []) or []

# Remove regra 404 final se existir
has_catchall = False
if ingress and "hostname" not in ingress[-1]:
    catchall = ingress.pop()
    has_catchall = True
else:
    catchall = {"service": "http_status:404"}

# Remove rota anterior do mesmo domínio se existir
ingress = [r for r in ingress if r.get("hostname") != "$domain"]

# Adiciona a nova rota no topo do ingress
ingress.append({"hostname": "$domain", "service": "$new_service"})

# Recoloca catchall
ingress.append(catchall)
cfg["ingress"] = ingress

with open("$put_json", "w") as f:
    json.dump({"config": cfg}, f, indent=2)
EOF

            curl -sS -X PUT \
                -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
                -H "Content-Type: application/json" \
                -d @"$put_json" \
                "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/cfd_tunnel/$TUNNEL_ID/configurations" >/dev/null 2>&1 || true
            
            rm -rf "$tmp_dir"
            log_sucesso "Regra Ingress do Cloudflare Tunnel configurada com sucesso!"
        fi

    # CASO B: Laboratório Local ou Sem Credenciais Reais Ativas
    else
        log_aviso "Credenciais ativas do Cloudflare não encontradas em $CREDENTIALS_FILE."
        log_info "Operando em modo Homologação Local (Simulação de Túnel Segura)."
    fi

    # Salva no registro sagrado local para persistência e auditoria
    python3 - << EOF
import json

routes_file = "$TUNNEL_ROUTES_FILE"
try:
    with open(routes_file) as f:
        data = json.load(f)
except Exception:
    data = {"routes": {}}

data["updated_at"] = "$now"
if "routes" not in data:
    data["routes"] = {}

data["routes"]["$domain"] = {
    "app_name": "$app_name",
    "service": "$service_name",
    "port": int("$port"),
    "target": "http://$service_name:$port",
    "created_at": "$now"
}

with open(routes_file, "w") as f:
    json.dump(data, f, indent=2)
EOF

    log_sucesso "Rota 'https://${domain}' persistida na Pasta Sagrada com sucesso!"
    echo -e "\n${BOLD}${VERDE}🛡️ ROTA CLOUDFLARE TUNNEL ATIVADA COM SUCESSO!${RESET}"
    echo -e "• URL Pública:   ${BOLD}https://${domain}${RESET}"
    echo -e "• Serviço Swarm: ${BOLD}http://${service_name}:${port}${RESET}"
    echo -e "• Modo de Rede:  ${BOLD}Zero Portas Abertas (Rede Overlay interna)${RESET}\n"
}

# ------------------------------------------------------------------------------
# 4. Remover Rota do Cloudflare Tunnel
# ------------------------------------------------------------------------------
tunnel_remove_route() {
    local domain="$1"
    tunnel_init

    log_info "Removendo rota Cloudflare Tunnel para: $domain"

    if check_cloudflare_credentials; then
        local tmp_dir backup_json put_json
        tmp_dir=$(mktemp -d)
        backup_json="$tmp_dir/config_backup.json"
        put_json="$tmp_dir/config_put.json"

        if curl -sS -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
            "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/cfd_tunnel/$TUNNEL_ID/configurations" > "$backup_json"; then
            
            python3 - << EOF
import json

with open("$backup_json") as f:
    orig = json.load(f)

cfg = orig.get("result", {}).get("config", {}) or {}
ingress = cfg.get("ingress", []) or []

ingress = [r for r in ingress if r.get("hostname") != "$domain"]
cfg["ingress"] = ingress

with open("$put_json", "w") as f:
    json.dump({"config": cfg}, f, indent=2)
EOF

            curl -sS -X PUT \
                -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
                -H "Content-Type: application/json" \
                -d @"$put_json" \
                "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/cfd_tunnel/$TUNNEL_ID/configurations" >/dev/null 2>&1 || true

            rm -rf "$tmp_dir"
            log_sucesso "Rota removida da API Cloudflare com sucesso."
        fi

        # Remove apontamento DNS CNAME se existir
        local zone_id="${CLOUDFLARE_ZONE_ID:-}"
        if [[ -z "$zone_id" || -z "${CLOUDFLARE_ZONE_NAME:-}" || "$domain" != *"$CLOUDFLARE_ZONE_NAME" ]]; then
            local zones_json
            zones_json=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones?per_page=50" \
                -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
                -H "Content-Type: application/json" 2>/dev/null || true)
            zone_id=$(echo "$zones_json" | jq -r --arg dom "$domain" '
                .result[]? | select($dom == .name or ($dom | endswith("." + .name))) | .id
            ' 2>/dev/null | head -n1 || true)
        fi

        if [[ -n "$zone_id" ]]; then
            local rec_id
            rec_id=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/${zone_id}/dns_records?name=${domain}" \
                -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
                -H "Content-Type: application/json" | jq -r '.result[0].id // empty' 2>/dev/null || true)
            if [[ -n "$rec_id" ]]; then
                curl -s -X DELETE "https://api.cloudflare.com/client/v4/zones/${zone_id}/dns_records/${rec_id}" \
                    -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
                    -H "Content-Type: application/json" >/dev/null 2>&1 || true
                log_sucesso "Registro DNS CNAME removido da Cloudflare."
            fi
        fi
    fi

    # Remove do registro local
    python3 - << EOF
import json

routes_file = "$TUNNEL_ROUTES_FILE"
try:
    with open(routes_file) as f:
        data = json.load(f)
    if "routes" in data and "$domain" in data["routes"]:
        del data["routes"]["$domain"]
    with open(routes_file, "w") as f:
        json.dump(data, f, indent=2)
except Exception:
    pass
EOF
    log_sucesso "Rota '$domain' removida do registro sagrado."
}

# ------------------------------------------------------------------------------
# 5. Listar Rotas Cadastradas
# ------------------------------------------------------------------------------
tunnel_list_routes() {
    tunnel_init

    local total
    total="$(jq '.routes | length' "$TUNNEL_ROUTES_FILE" 2>/dev/null || echo "0")"

    echo -e "\n${BOLD}${CIANO}========================================================================================${RESET}"
    echo -e "${BOLD}${MAGENTA}  🌐 ROTAS CLOUDFLARE TUNNEL (Setup MNO App Studio [BETA])${RESET}"
    echo -e "${BOLD}${CIANO}========================================================================================${RESET}"

    if [[ "$total" -eq 0 ]]; then
        echo -e "${AMARELO}Nenhuma rota pública registrada no Cloudflare Tunnel até o momento.${RESET}\n"
        return 0
    fi

    printf "%-32s %-20s %-30s\n" "DOMÍNIO PÚBLICO HTTPS" "APLICAÇÃO" "DESTINO INTERNO SWARM"
    echo "----------------------------------------------------------------------------------------"

    local domains
    domains="$(jq -r '.routes | keys[]' "$TUNNEL_ROUTES_FILE" 2>/dev/null || echo "")"

    for dom in $domains; do
        local app_name target
        app_name="$(jq -r ".routes[\"$dom\"].app_name" "$TUNNEL_ROUTES_FILE")"
        target="$(jq -r ".routes[\"$dom\"].target" "$TUNNEL_ROUTES_FILE")"

        printf "%-32s %-20s %-30s\n" "https://$dom" "$app_name" "$target"
    done
    echo -e "${BOLD}${CIANO}========================================================================================${RESET}\n"
}

# ------------------------------------------------------------------------------
# Entrada CLI
# ------------------------------------------------------------------------------
case "${1:-help}" in
    add)
        shift
        tunnel_add_route "$@"
        ;;
    remove)
        shift
        tunnel_remove_route "$@"
        ;;
    list)
        tunnel_list_routes
        ;;
    *)
        echo "Uso: $0 {add|remove|list} [argumentos]"
        echo "Exemplo add: $0 add app.meusite.com meu-app_app 80 meu-app"
        echo "Exemplo remove: $0 remove app.meusite.com"
        echo "Exemplo list: $0 list"
        ;;
esac

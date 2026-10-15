#!/usr/bin/env bash
# ==============================================================================
# Setup MNO App Studio [BETA] - Registro Sagrado de Aplicações
# Mantenedor: Francis MNO (Setup MNO)
# Localização Sagrada: /root/setupmno-appstudio/registry.json
# ==============================================================================

set -uo pipefail

# Cores e Formatação
VERMELHO='\033[0;31m'
VERDE='\033[0;32m'
AMARELO='\033[1;33m'
AZUL='\033[0;34m'
CIANO='\033[0;36m'
MAGENTA='\033[0;35m'
RESET='\033[0m'
BOLD='\033[1m'

# Diretório Sagrado Persistente:
# Em produção: /root/setupmno-appstudio (fora de /root/SetupLowCodeMno)
SACRED_DIR="${APPSTUDIO_SACRED_DIR:-/root/setupmno-appstudio}"
REGISTRY_FILE="$SACRED_DIR/registry.json"

log_info() {
    echo -e "${CIANO}[REGISTRY-INFO]${RESET} $1" >&2
}

log_sucesso() {
    echo -e "${VERDE}[REGISTRY-SUCESSO]${RESET} $1" >&2
}

log_aviso() {
    echo -e "${AMARELO}[REGISTRY-AVISO]${RESET} $1" >&2
}

log_erro() {
    echo -e "${VERMELHO}[REGISTRY-ERRO]${RESET} $1" >&2
}

# ------------------------------------------------------------------------------
# 1. Inicialização do Diretório Sagrado e do Banco JSON
# ------------------------------------------------------------------------------
registry_init() {
    if [[ ! -d "$SACRED_DIR" ]]; then
        mkdir -p "$SACRED_DIR/apps" "$SACRED_DIR/repos"
        chmod 0700 "$SACRED_DIR" 2>/dev/null || true
        log_info "Diretório sagrado persistente inicializado em: $SACRED_DIR"
    fi

    if [[ ! -f "$REGISTRY_FILE" ]]; then
        cat << 'EOF' > "$REGISTRY_FILE"
{
  "schema_version": "1.0.0",
  "updated_at": "",
  "apps": {}
}
EOF
        chmod 0600 "$REGISTRY_FILE" 2>/dev/null || true
        log_sucesso "Arquivo de registro inicializado: $REGISTRY_FILE"
    fi
}

# ------------------------------------------------------------------------------
# 2. Registrar Nova Aplicação (Operação Atômica)
# ------------------------------------------------------------------------------
registry_register_app() {
    local app_name="$1"
    local stack_name="$2"
    local image_tag="$3"
    local runtime="$4"
    local internal_port="$5"
    local domain="${6:-none}"
    local postgres_injected="${7:-false}"
    local redis_injected="${8:-false}"
    local cpu_limit="${9:-0.50}"
    local mem_limit="${10:-512M}"
    local source_dir="${11:-none}"
    local install_type="${12:-CLOUDFLARE_TUNNEL}"
    local git_repo="${13:-none}"
    local git_branch="${14:-main}"
    local portainer_editable="${15:-0}"

    registry_init

    local now
    now="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

    # Criar pasta persistente do aplicativo dentro da pasta sagrada
    local app_persistent_dir="$SACRED_DIR/apps/$app_name"
    mkdir -p "$app_persistent_dir"

    # Salvar metadados atômicos usando Python 3 para garantir integridade do JSON
    local temp_registry="$SACRED_DIR/registry.tmp.$$"
    
    python3 - << EOF
import json
import sys

registry_path = "$REGISTRY_FILE"
temp_path = "$temp_registry"

try:
    with open(registry_path, "r", encoding="utf-8") as f:
        data = json.load(f)
except Exception:
    data = {"schema_version": "1.0.0", "apps": {}}

data["updated_at"] = "$now"
if "apps" not in data:
    data["apps"] = {}

domain_raw = "$domain"
domains_list = [d.strip() for d in domain_raw.split(",") if d.strip() and d.strip().lower() != "none"]

data["apps"]["$app_name"] = {
    "name": "$app_name",
    "stack_name": "$stack_name",
    "image_tag": "$image_tag",
    "runtime": "$runtime",
    "internal_port": int("$internal_port"),
    "domain": domain_raw,
    "domains": domains_list,
    "install_type": "$install_type",
    "portainer_editable": "$portainer_editable" == "0",
    "git": {
        "repo": "$git_repo",
        "branch": "$git_branch"
    },
    "connections": {
        "postgres": "$postgres_injected" == "true",
        "redis": "$redis_injected" == "true"
    },
    "resources": {
        "cpu_limit": "$cpu_limit",
        "memory_limit": "$mem_limit"
    },
    "source_dir": "$source_dir",
    "created_at": data["apps"].get("$app_name", {}).get("created_at", "$now"),
    "last_deploy_at": "$now"
}

with open(temp_path, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2, ensure_ascii=False)

EOF

    if [[ -f "$temp_registry" ]]; then
        mv -f "$temp_registry" "$REGISTRY_FILE"
        chmod 0600 "$REGISTRY_FILE" 2>/dev/null || true
        mkdir -p /root/SetupLowCodeMno/.control 2>/dev/null || true
        cp -f "$REGISTRY_FILE" /root/SetupLowCodeMno/.control/appstudio_registry.json 2>/dev/null || true
        log_sucesso "Aplicação '$app_name' registrada no banco sagrado com sucesso! (Modo: $install_type)"
    else
        log_erro "Falha ao gravar arquivo atômico de registro."
        return 1
    fi
}

# ------------------------------------------------------------------------------
# 3. Consultar Metadados de um App Específico
# ------------------------------------------------------------------------------
registry_get_app() {
    local app_name="$1"
    registry_init

    if ! grep -q "\"$app_name\":" "$REGISTRY_FILE" 2>/dev/null; then
        log_erro "Aplicação '$app_name' não encontrada no registro."
        return 1
    fi

    jq -r ".apps[\"$app_name\"]" "$REGISTRY_FILE"
}

# ------------------------------------------------------------------------------
# 4. Remover Registro de uma Aplicação
# ------------------------------------------------------------------------------
registry_unregister_app() {
    local app_name="$1"
    local purge_files="${2:-false}"

    registry_init

    local temp_registry="$SACRED_DIR/registry.tmp.$$"
    local now
    now="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

    python3 - << EOF
import json

registry_path = "$REGISTRY_FILE"
temp_path = "$temp_registry"

try:
    with open(registry_path, "r", encoding="utf-8") as f:
        data = json.load(f)
except Exception:
    data = {"schema_version": "1.0.0", "apps": {}}

data["updated_at"] = "$now"
if "apps" in data and "$app_name" in data["apps"]:
    del data["apps"]["$app_name"]

with open(temp_path, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
EOF

    if [[ -f "$temp_registry" ]]; then
        mv -f "$temp_registry" "$REGISTRY_FILE"
        chmod 0600 "$REGISTRY_FILE" 2>/dev/null || true
        mkdir -p /root/SetupLowCodeMno/.control 2>/dev/null || true
        cp -f "$REGISTRY_FILE" /root/SetupLowCodeMno/.control/appstudio_registry.json 2>/dev/null || true
        log_sucesso "Aplicação '$app_name' desregistrada do banco sagrado."
    fi

    if [[ "$purge_files" == "true" ]]; then
        local app_dir="$SACRED_DIR/apps/$app_name"
        if [[ -d "$app_dir" ]]; then
            rm -rf "$app_dir"
            log_sucesso "Arquivos da pasta sagrada do app '$app_name' foram expurgados."
        fi
    fi
}

# ------------------------------------------------------------------------------
# 5. Listar Todas as Aplicações
# ------------------------------------------------------------------------------
registry_list_apps() {
    registry_init

    local total
    total="$(jq '.apps | length' "$REGISTRY_FILE" 2>/dev/null || echo "0")"

    echo -e "\n${BOLD}${CIANO}========================================================================================${RESET}"
    echo -e "${BOLD}${MAGENTA}  🚀 MEUS APPS INSTALADOS (Setup MNO App Studio [BETA] - Registro Sagrado)${RESET}"
    echo -e "${BOLD}${CIANO}========================================================================================${RESET}"

    if [[ "$total" -eq 0 ]]; then
        echo -e "${AMARELO}Nenhuma aplicação customizada registrada até o momento.${RESET}"
        echo -e "Use o instalador para implantar seu primeiro micro-serviço IA no Docker Swarm.\n"
        return 0
    fi

    printf "%-18s %-16s %-8s %-25s %-16s %-20s\n" "APLICAÇÃO" "RUNTIME" "PORTA" "STATUS SWARM" "BANCOS" "DOMÍNIO"
    echo "----------------------------------------------------------------------------------------"

    local app_keys
    app_keys="$(jq -r '.apps | keys[]' "$REGISTRY_FILE" 2>/dev/null || echo "")"

    for app in $app_keys; do
        local runtime port stack_name domain has_pg has_redis
        runtime="$(jq -r ".apps[\"$app\"].runtime" "$REGISTRY_FILE")"
        port="$(jq -r ".apps[\"$app\"].internal_port" "$REGISTRY_FILE")"
        stack_name="$(jq -r ".apps[\"$app\"].stack_name" "$REGISTRY_FILE")"
        domain="$(jq -r ".apps[\"$app\"].domain" "$REGISTRY_FILE")"
        has_pg="$(jq -r ".apps[\"$app\"].connections.postgres" "$REGISTRY_FILE")"
        has_redis="$(jq -r ".apps[\"$app\"].connections.redis" "$REGISTRY_FILE")"

        # Verifica status no Docker Swarm
        local service_name="${stack_name}_app"
        local replicas
        replicas="$(docker service ls --filter "name=${service_name}" --format '{{.Replicas}}' 2>/dev/null || echo "")"

        local status_label
        if [[ "$replicas" == "1/1" ]]; then
            status_label="${VERDE}● Ativo (1/1)${RESET}"
        elif [[ -n "$replicas" ]]; then
            status_label="${AMARELO}○ Iniciando ($replicas)${RESET}"
        else
            status_label="${VERMELHO}✖ Parado${RESET}"
        fi

        local dbs=""
        [[ "$has_pg" == "true" ]] && dbs+="[PG]"
        [[ "$has_redis" == "true" ]] && dbs+="[Redis]"
        [[ -z "$dbs" ]] && dbs="[Nenhum]"

        [[ "$domain" == "none" ]] && domain="—"

        printf "%-18s %-16s %-8s %-25b %-16s %-20s\n" "$app" "$runtime" "$port" "$status_label" "$dbs" "$domain"
    done
    echo -e "${BOLD}${CIANO}========================================================================================${RESET}\n"
}

# ------------------------------------------------------------------------------
# Entrada CLI
# ------------------------------------------------------------------------------
case "${1:-help}" in
    init)
        registry_init
        ;;
    register)
        shift
        registry_register_app "$@"
        ;;
    unregister)
        shift
        registry_unregister_app "$@"
        ;;
    get)
        shift
        registry_get_app "$@"
        ;;
    list)
        registry_list_apps
        ;;
    path)
        echo "$SACRED_DIR"
        ;;
    *)
        echo "Uso: $0 {init|register|unregister|get|list|path} [argumentos]"
        ;;
esac

#!/usr/bin/bash
# Utilitário seguro para leitura e comutação do modo MNO Fleet Hub.
# Garante atomicidade, permissões 0644 e validação fail-closed.
set -euo pipefail
umask 077

CONTROL_DIR="${SETUPMNO_CONTROL_DIR:-/root/SetupLowCodeMno/.control}"
ENV_FILE="$CONTROL_DIR/environment.json"

fail() {
    printf '%s\n' "$1" >&2
    exit 1
}

get_status() {
    if [ ! -f "$ENV_FILE" ] || [ -L "$ENV_FILE" ]; then
        printf 'disabled\n'
        return 0
    fi
    jq -r '.fleetMode // "disabled"' "$ENV_FILE" 2>/dev/null || printf 'disabled\n'
}

get_info() {
    if [ ! -f "$ENV_FILE" ] || [ -L "$ENV_FILE" ]; then
        printf 'Modo: disabled\n'
        return 0
    fi
    local mode node_id token master_url
    mode=$(jq -r '.fleetMode // "disabled"' "$ENV_FILE" 2>/dev/null || printf 'disabled')
    node_id=$(jq -r '.fleetNodeId // "não definido"' "$ENV_FILE" 2>/dev/null || printf 'não definido')
    token=$(jq -r '.fleetToken // "não definido"' "$ENV_FILE" 2>/dev/null || printf 'não definido')
    master_url=$(jq -r '.fleetMasterUrl // "não configurado"' "$ENV_FILE" 2>/dev/null || printf 'não configurado')
    printf 'Modo: %s\nNode ID: %s\nToken de Pareamento: %s\nMaster URL: %s\n' "$mode" "$node_id" "$token" "$master_url"
}

set_mode() {
    local requested_mode="${1:-}"
    case "$requested_mode" in
        disabled|master|worker) ;;
        *) fail "Modo fleet inválido: '$requested_mode'. Use 'disabled', 'master' ou 'worker'." ;;
    esac

    if [ ! -f "$ENV_FILE" ] || [ -L "$ENV_FILE" ]; then
        fail "Arquivo de ambiente do Control Center ($ENV_FILE) indisponível."
    fi

    local schema_version installation_type plan
    schema_version=$(jq -r '.schemaVersion // 0' "$ENV_FILE" 2>/dev/null)
    [ "$schema_version" = "1" ] || fail "SchemaVersion de $ENV_FILE inválido (esperado: 1)."

    installation_type=$(jq -r '.installationType // ""' "$ENV_FILE" 2>/dev/null)
    plan=$(jq -r '.plan // ""' "$ENV_FILE" 2>/dev/null)

    # Validação de Segurança: Fleet Hub é exclusivo para planos PRO / PRO MASTER e Cloudflare Tunnel
    if [ "$requested_mode" != "disabled" ]; then
        if [ "$plan" != "pro" ] && [ "$plan" != "pro-master" ]; then
            fail "O MNO Fleet Hub é exclusivo para assinantes dos planos PRO e PRO MASTER."
        fi
        if [ "$installation_type" != "CLOUDFLARE_TUNNEL" ]; then
            fail "O MNO Fleet Hub é exclusivo para instalações configuradas com Cloudflare Tunnel (Zero Portas Abertas)."
        fi
    fi

    # Obter ou gerar node ID único para o nó
    local existing_node_id node_id
    existing_node_id=$(jq -r '.fleetNodeId // empty' "$ENV_FILE" 2>/dev/null || true)
    if [ -n "$existing_node_id" ]; then
        node_id="$existing_node_id"
    else
        if command -v uuidgen >/dev/null 2>&1; then
            node_id=$(uuidgen | tr '[:upper:]' '[:lower:]')
        else
            node_id=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || tr -dc 'a-f0-9' </dev/urandom | head -c 32)
        fi
    fi

    # Obter ou gerar token criptográfico único para pareamento do nó
    local existing_token token
    existing_token=$(jq -r '.fleetToken // empty' "$ENV_FILE" 2>/dev/null || true)
    if [ -n "$existing_token" ]; then
        token="$existing_token"
    else
        token=$(tr -dc 'a-f0-9' </dev/urandom | head -c 48 || true)
    fi

    local temp_file
    temp_file=$(mktemp "$CONTROL_DIR/environment.json.tmp.XXXXXX") || fail "Erro ao criar arquivo temporário."
    chmod 0644 "$temp_file" || { rm -f "$temp_file"; fail "Erro ao definir permissões."; }

    if [ "$requested_mode" = "disabled" ]; then
        jq --arg mode "$requested_mode" \
           '.fleetMode = $mode' "$ENV_FILE" >"$temp_file" || { rm -f "$temp_file"; fail "Erro ao atualizar JSON."; }
    else
        jq --arg mode "$requested_mode" --arg nodeId "$node_id" --arg token "$token" \
           '.fleetMode = $mode | .fleetNodeId = $nodeId | .fleetToken = (.fleetToken // $token)' "$ENV_FILE" >"$temp_file" || { rm -f "$temp_file"; fail "Erro ao atualizar JSON."; }
    fi

    mv -f "$temp_file" "$ENV_FILE"
    printf 'Modo MNO Fleet Hub atualizado para: %s\n' "$requested_mode"
}

show_menu() {
    local installation_type="TRADICIONAL"
    local plan="free"
    if [ -f "$ENV_FILE" ] && [ ! -L "$ENV_FILE" ]; then
        installation_type=$(jq -r '.installationType // "TRADICIONAL"' "$ENV_FILE" 2>/dev/null || printf 'TRADICIONAL')
        plan=$(jq -r '.plan // "free"' "$ENV_FILE" 2>/dev/null || printf 'free')
    fi
    if [ "$plan" != "pro" ] && [ "$plan" != "pro-master" ]; then
        whiptail --title "RECURSO EXCLUSIVO PRO" --msgbox \
            "O recurso MNO Fleet Hub (Vibe Ops) é exclusivo para assinantes dos planos PRO e PRO MASTER.\n\nPara gerenciar múltiplos servidores e orquestrar sua frota com Zero Portas Abertas, faça o upgrade para o plano PRO." 15 76
        return 0
    fi
    if [ "$installation_type" != "CLOUDFLARE_TUNNEL" ]; then
        whiptail --title "MNO FLEET HUB — SEGURANÇA MÁXIMA" --msgbox \
            "O MNO Fleet Hub exige a arquitetura Zero-Trust do Cloudflare Tunnel para proteger a comunicação da frota com Zero Portas Abertas no firewall.\n\nNo modo Tradicional, o Fleet Hub não está disponível para prevenir riscos de segurança.\n\nPara habilitar este recurso, reconfigure o Setup MNO escolhendo a Opção 2 (Cloudflare Tunnel)." 16 80
        return 0
    fi

    local is_wsl=false
    if grep -qEi "(Microsoft|WSL)" /proc/version 2>/dev/null; then
        is_wsl=true
    fi

    local current_mode
    current_mode=$(get_status)

    local status_desc="DESATIVADO (Modo Simples Standalone)"
    case "$current_mode" in
        master) status_desc="ATIVADO (Torre de Controle / Master Hub)" ;;
        worker) status_desc="ATIVADO (Nó de Frota / Worker)" ;;
    esac

    local fleet_choice
    fleet_choice=$(whiptail --title "MNO FLEET HUB — GESTÃO DE SERVIDORES" --menu \
        "Estado Atual: $status_desc\n\nSelecione uma opção:" 19 78 5 \
        "1" "Manter Modo Simples Standalone (Desativado - 0 MB overhead)" \
        "2" "Ativar como Torre Master (Gerenciar 1 servidor ou múltiplos)" \
        "3" "Conectar à Frota como Nó Worker (Subordinado a outro Master)" \
        "4" "Ver Informações de Pareamento (ID e Token do Nó)" \
        "5" "Voltar ao Menu Principal" \
        3>&1 1>&2 2>&3) || return 0

    case "$fleet_choice" in
        1)
            set_mode disabled >/dev/null
            whiptail --title "MNO FLEET HUB" --msgbox "Modo Simples Standalone configurado com sucesso.\n\nO servidor opera de forma isolada com zero overhead." 10 70
            ;;
        2)
            set_mode master >/dev/null
            local cur_id cur_token
            cur_id=$(jq -r '.fleetNodeId // "indisponível"' "$ENV_FILE" 2>/dev/null)
            cur_token=$(jq -r '.fleetToken // "indisponível"' "$ENV_FILE" 2>/dev/null)
            whiptail --title "MNO FLEET HUB" --msgbox "Torre de Controle (Master Hub) ativada com sucesso!\n\nEste servidor agora gerencia suas aplicações locais e está pronto para gerenciar múltiplos servidores e o Co-piloto de IA.\n\nID da Torre: $cur_id\nToken da Frota: $cur_token" 15 76
            ;;
        3)
            if [ "$is_wsl" = "true" ]; then
                whiptail --title "WSL2 DETECTADO — MODO LABORATÓRIO" --msgbox \
                    "O WSL2 roda no seu computador pessoal (atrás de NAT residencial) e desliga quando o computador é desligado.\n\nPor segurança e confiabilidade, o modo Nó Worker deve ser instalado em uma VPS na nuvem com conexão 24/7.\n\nNo WSL2, você pode usar o modo Torre Master para estudar e testar o painel localmente." 16 78
                return 0
            fi
            set_mode worker >/dev/null
            local cur_id cur_token
            cur_id=$(jq -r '.fleetNodeId // "indisponível"' "$ENV_FILE" 2>/dev/null)
            cur_token=$(jq -r '.fleetToken // "indisponível"' "$ENV_FILE" 2>/dev/null)
            whiptail --title "MNO FLEET HUB" --msgbox "Nó de Frota (Worker) ativado com sucesso!\n\nEsta VPS agora está configurada com endpoint seguro e token de pareamento para ser comandada pela sua Torre Master.\n\nID do Nó: $cur_id\nToken de Pareamento: $cur_token" 15 76
            ;;
        4)
            local cur_info
            cur_info=$(get_info)
            whiptail --title "INFORMAÇÕES DE PAREAMENTO — FLEET HUB" --msgbox \
                "$cur_info\n\nUse o Token de Pareamento acima na sua Torre Master para conectar este nó à sua frota centralizada." 15 76
            ;;
        *)
            return 0
            ;;
    esac
}

action="${1:-status}"
case "$action" in
    status)
        get_status
        ;;
    info)
        get_info
        ;;
    set)
        shift
        set_mode "${1:-}"
        ;;
    menu)
        show_menu
        ;;
    *)
        fail "Ação desconhecida: $action. Use: $0 [status | info | set <disabled|master|worker> | menu]"
        ;;
esac

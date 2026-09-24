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

get_role() {
    if [ -f "/root/.ssh/fleet_role.json" ]; then
        local r
        r=$(jq -r '.fleetRole // empty' "/root/.ssh/fleet_role.json" 2>/dev/null || true)
        if [ "$r" = "active" ] || [ "$r" = "standby" ]; then
            printf '%s\n' "$r"
            return 0
        fi
    fi
    if [ ! -f "$ENV_FILE" ] || [ -L "$ENV_FILE" ]; then
        printf 'active\n'
        return 0
    fi
    jq -r '.fleetRole // "active"' "$ENV_FILE" 2>/dev/null || printf 'active\n'
}

get_info() {
    if [ ! -f "$ENV_FILE" ] || [ -L "$ENV_FILE" ]; then
        printf 'Modo: disabled\n'
        return 0
    fi
    local mode node_id token master_url role
    mode=$(jq -r '.fleetMode // "disabled"' "$ENV_FILE" 2>/dev/null || printf 'disabled')
    node_id=$(jq -r '.fleetNodeId // "não definido"' "$ENV_FILE" 2>/dev/null || printf 'não definido')
    token=$(jq -r '.fleetToken // "não definido"' "$ENV_FILE" 2>/dev/null || printf 'não definido')
    master_url=$(jq -r '.fleetMasterUrl // "não configurado"' "$ENV_FILE" 2>/dev/null || printf 'não configurado')
    role=$(get_role)
    if [ "$mode" = "master" ]; then
        printf 'Modo: %s\nPapel da Torre: %s\nNode ID: %s\nToken de Pareamento: %s\nMaster URL: %s\n' "$mode" "$role" "$node_id" "$token" "$master_url"
    else
        printf 'Modo: %s\nNode ID: %s\nToken de Pareamento: %s\nMaster URL: %s\n' "$mode" "$node_id" "$token" "$master_url"
    fi
}

set_role() {
    local requested_role="${1:-}"
    case "$requested_role" in
        active|standby) ;;
        *) fail "Papel fleet inválido: '$requested_role'. Use 'active' ou 'standby'." ;;
    esac

    if [ ! -f "$ENV_FILE" ] || [ -L "$ENV_FILE" ]; then
        fail "Arquivo de ambiente do Control Center ($ENV_FILE) indisponível."
    fi

    local current_mode
    current_mode=$(get_status)
    if [ "$current_mode" != "master" ]; then
        fail "O papel de Torre (active/standby) só pode ser configurado quando o modo for 'master'."
    fi

    local temp_file
    temp_file=$(mktemp "$CONTROL_DIR/environment.json.tmp.XXXXXX") || fail "Erro ao criar arquivo temporário."
    chmod 0644 "$temp_file" || { rm -f "$temp_file"; fail "Erro ao definir permissões."; }

    jq --arg role "$requested_role" \
       '.fleetRole = $role' "$ENV_FILE" >"$temp_file" || { rm -f "$temp_file"; fail "Erro ao atualizar JSON."; }

    mv -f "$temp_file" "$ENV_FILE"

    # Persistência de redundância segura em /root/.ssh/fleet_role.json para paridade com containers read-only
    if [ -d "/root/.ssh" ] && [ -w "/root/.ssh" ]; then
        local now
        now=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || printf "2026-09-23T00:00:00Z")
        local ssh_tmp
        ssh_tmp=$(mktemp "/root/.ssh/fleet_role.json.tmp.XXXXXX" 2>/dev/null || true)
        if [ -n "$ssh_tmp" ]; then
            printf '{\n  "fleetRole": "%s",\n  "updatedAt": "%s"\n}\n' "$requested_role" "$now" >"$ssh_tmp" 2>/dev/null || true
            chmod 0644 "$ssh_tmp" 2>/dev/null || true
            mv -f "$ssh_tmp" "/root/.ssh/fleet_role.json" 2>/dev/null || rm -f "$ssh_tmp"
        fi
    fi

    printf 'Papel da Torre Master atualizado para: %s\n' "$requested_role"
}

set_mode() {
    local requested_mode="${1:-}"
    case "$requested_mode" in
        disabled|master|worker|operario) ;;
        *) fail "Modo fleet inválido: '$requested_mode'. Use 'disabled', 'master' ou 'worker'." ;;
    esac
    if [ "$requested_mode" = "operario" ]; then
        requested_mode="worker"
    fi

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
        local default_role="active"
        jq --arg mode "$requested_mode" --arg nodeId "$node_id" --arg token "$token" --arg defRole "$default_role" \
           '.fleetMode = $mode | .fleetNodeId = $nodeId | .fleetToken = (.fleetToken // $token) | .fleetRole = (.fleetRole // $defRole)' "$ENV_FILE" >"$temp_file" || { rm -f "$temp_file"; fail "Erro ao atualizar JSON."; }
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

    local current_mode current_role
    current_mode=$(get_status)
    current_role=$(get_role)

    local status_desc="DESATIVADO (Modo Simples Standalone)"
    case "$current_mode" in
        master)
            if [ "$current_role" = "standby" ]; then
                status_desc="ATIVADO (Torre Master · Cockpit Standby / Passiva)"
            else
                status_desc="ATIVADO (Torre Master · Primária Ativa 24/7)"
            fi
            ;;
        worker) status_desc="ATIVADO (Nó Operário Subordinado)" ;;
    esac

    local fleet_choice
    fleet_choice=$(whiptail --title "MNO FLEET HUB — GESTÃO DE SERVIDORES" --menu \
        "Estado Atual: $status_desc\n\nSelecione uma opção:" 22 78 8 \
        "1" "Manter Modo Simples Standalone (Desativado - 0 MB overhead)" \
        "2" "Ativar como Torre Master (Torre de Controle no WSL2 ou VPS)" \
        "3" "Conectar à Frota como Nó Operário (Subordinado à Torre Master)" \
        "4" "Ver Informações de Pareamento (ID e Token do Nó)" \
        "5" "Clone, Transferência e Backup de Aplicações da Frota" \
        "6" "Sincronizar Inventário de outra Torre Master (Master-to-Master)" \
        "7" "Alternar Papel da Torre Master (Ativa 24/7 ⇄ Cockpit Standby)" \
        "8" "Voltar ao Menu Principal" \
        3>&1 1>&2 2>&3) || return 0

    case "$fleet_choice" in
        1)
            set_mode disabled >/dev/null
            whiptail --title "MNO FLEET HUB" --msgbox "Modo Simples Standalone configurado com sucesso.\n\nO servidor opera de forma isolada com zero overhead." 10 70
            ;;
        2)
            set_mode master >/dev/null
            local cur_id cur_token cur_role
            cur_id=$(jq -r '.fleetNodeId // "indisponível"' "$ENV_FILE" 2>/dev/null)
            cur_token=$(jq -r '.fleetToken // "indisponível"' "$ENV_FILE" 2>/dev/null)
            cur_role=$(get_role)
            if [ "$is_wsl" = "true" ]; then
                whiptail --title "MNO FLEET HUB — TORRE MASTER (WSL2)" --msgbox \
                    "Torre Master ativada com sucesso no WSL2!\n\nSeu computador pessoal agora é a Torre de Controle da sua frota.\nPapel atribuído: Primária Ativa (24/7).\n\nVocê pode cadastrar e gerenciar seus servidores remotos (Nós Operários) diretamente desta tela, com zero portas abertas no seu roteador residencial.\n\nID da Torre: $cur_id\nToken da Frota: $cur_token\nPapel: $cur_role" 17 78
            else
                whiptail --title "MNO FLEET HUB" --msgbox "Torre de Controle (Master Hub) ativada com sucesso!\n\nEste servidor agora gerencia suas aplicações locais e está pronto para gerenciar múltiplos servidores e o Co-piloto de IA.\nPapel atribuído: Primária Ativa (24/7).\n\nID da Torre: $cur_id\nToken da Frota: $cur_token\nPapel: $cur_role" 16 76
            fi
            ;;
        3)
            if [ "$is_wsl" = "true" ]; then
                if ! whiptail --title "WSL2 DETECTADO — ALERTA IMPORTANTE" --yesno \
                    "ATENÇÃO: Você está configurando este ambiente WSL2 como Nó Operário (Subordinado à Torre Master)!\n\nNo computador pessoal / WSL2, se a conexão de internet oscilar ou cair, se o PC for desligado ou a tampa do notebook/laptop for fechada, todas as aplicações hospedadas neste nó ficarão indisponíveis imediatamente para os usuários externos.\n\nDeseja realmente continuar e ativar este WSL2 como Nó Operário?" 16 78; then
                    return 0
                fi
            fi
            set_mode worker >/dev/null
            local cur_id cur_token
            cur_id=$(jq -r '.fleetNodeId // "indisponível"' "$ENV_FILE" 2>/dev/null)
            cur_token=$(jq -r '.fleetToken // "indisponível"' "$ENV_FILE" 2>/dev/null)
            local is_mfa_active="false"
            if [ -f "$CONTROL_DIR/mfa-state.json" ] && [ "$(jq -r '.effectiveMFA // false' "$CONTROL_DIR/mfa-state.json" 2>/dev/null)" = "true" ]; then
                is_mfa_active="true"
            elif [ -f "$ENV_FILE" ] && [ "$(jq -r '.accessJwtRequired // false' "$ENV_FILE" 2>/dev/null)" = "true" ]; then
                is_mfa_active="true"
            fi
            local ctrl_script
            ctrl_script="$(dirname "$CONTROL_DIR")/setupmno_control.sh"
            [ -x "$ctrl_script" ] || ctrl_script="/root/SetupLowCodeMno/setupmno_control.sh"
            if [ "$is_mfa_active" = "true" ] && [ -x "$ctrl_script" ]; then
                "$ctrl_script" --add-telemetry-bypass >/dev/null 2>&1 || true
            fi
            whiptail --title "MNO FLEET HUB" --msgbox "Nó Operário ativado com sucesso!\n\nEste servidor agora está configurado com endpoint seguro e token de pareamento para ser comandado pela sua Torre Master.\n\nID do Nó: $cur_id\nToken de Pareamento: $cur_token" 15 76
            ;;
        4)
            local cur_info
            cur_info=$(get_info)
            whiptail --title "INFORMAÇÕES DE PAREAMENTO — FLEET HUB" --msgbox \
                "$cur_info\n\nUse o Token de Pareamento acima na sua Torre Master para conectar este nó à sua frota centralizada." 15 76
            ;;
        5)
            local clone_script="/root/SetupLowCodeMno/fleet-clone.sh"
            if [ ! -f "$clone_script" ]; then
                clone_script="$(dirname "${BASH_SOURCE[0]}")/fleet-clone.sh"
            fi
            if [ -f "$clone_script" ]; then
                bash "$clone_script" menu
            else
                whiptail --title "MNO FLEET HUB" --msgbox "Script fleet-clone.sh não localizado." 10 60
            fi
            ;;
        6)
            sync_master_inventory
            ;;
        7)
            if [ "$current_mode" != "master" ]; then
                whiptail --title "PAPEL DA TORRE MASTER" --msgbox \
                    "A configuração de Papel da Torre (Ativa vs Standby) é aplicável somente quando o servidor está no modo Torre Master (Opção 2).\n\nAtive a Torre Master antes de ajustar esta opção." 13 74
                return 0
            fi
            local cur_role
            cur_role=$(get_role)
            local role_choice
            role_choice=$(whiptail --title "PAPEL DA TORRE MASTER" --menu \
                "Papel atual: $cur_role\n\nEscolha o papel operacional desta Torre Master:" 16 78 2 \
                "1" "Torre Primária Ativa 24/7 (VPS na Nuvem - Varreduras e Sentinel)" \
                "2" "Torre Cockpit Standby (Notebook WSL2 - Sob demanda / Silenciosa)" \
                3>&1 1>&2 2>&3) || return 0

            if [ "$role_choice" = "1" ]; then
                set_role active >/dev/null
                whiptail --title "TORRE ATIVA CONFIGURADA" --msgbox \
                    "Esta Torre Master agora é a TORRE PRIMÁRIA ATIVA (24/7).\n\n• Varreduras periódicas de frota ativadas em background.\n• Sentinel autônomo ativo para monitorar e alertar sobre incidentes." 13 74
            elif [ "$role_choice" = "2" ]; then
                set_role standby >/dev/null
                whiptail --title "TORRE STANDBY CONFIGURADA" --msgbox \
                    "Esta Torre Master agora é a TORRE COCKPIT STANDBY (Passiva).\n\n• Ideal para notebook / WSL2 ou torre reserva.\n• Varreduras automáticas em loop pausadas para economizar recursos.\n• Sentinel autônomo silenciado para evitar alertas duplicados com a VPS.\n• Todos os comandos manuais continuam 100% disponíveis!" 15 76
            fi
            ;;
        8)
            return 0
            ;;
        *)
            return 0
            ;;
    esac
}

sync_master_inventory() {
    local cur_mode
    cur_mode=$(get_status)
    if [ "$cur_mode" != "master" ]; then
        whiptail --title "SINCRONIZAÇÃO MASTER-TO-MASTER" --msgbox \
            "Esta operação exige que este servidor esteja ativado como Torre Master (Opção 2).\n\nConfigure este servidor como Torre Master antes de importar o inventário de nós." 13 74
        return 0
    fi

    local remote_endpoint
    remote_endpoint=$(whiptail --title "SINCRONIZAÇÃO MASTER-TO-MASTER" --inputbox \
        "Informe o Endpoint HTTPS da Torre Master de Origem (ex: sua VPS em produção):\nExemplo: https://setupXXXXX.manualnegocioonline.com.br" 12 78 \
        3>&1 1>&2 2>&3) || return 0

    remote_endpoint=$(echo "$remote_endpoint" | tr -d '[:space:]' | sed 's:/*$::')
    if [ -z "$remote_endpoint" ]; then
        whiptail --title "ERRO" --msgbox "Endpoint não informado." 8 40
        return 0
    fi

    local remote_token
    remote_token=$(whiptail --title "TOKEN DA TORRE REMOTA" --passwordbox \
        "Cole o Token de Frota da Torre Master remota:\n(Encontrado no menu Opção 4 daquela Torre)" 12 78 \
        3>&1 1>&2 2>&3) || return 0

    remote_token=$(echo "$remote_token" | tr -d '[:space:]')
    if [ -z "$remote_token" ]; then
        whiptail --title "ERRO" --msgbox "Token não informado." 8 40
        return 0
    fi

    local strat_choice
    strat_choice=$(whiptail --title "ESTRATÉGIA DE IMPORTAÇÃO" --menu \
        "Escolha como mesclar os servidores importados com os nós existentes:" 14 76 2 \
        "1" "Mesclar (Merge) — Preserva nós atuais e adiciona/atualiza novos" \
        "2" "Substituir (Replace) — Espelho exato (remove nós locais ausentes na origem)" \
        3>&1 1>&2 2>&3) || return 0

    local strategy="merge"
    if [ "$strat_choice" = "2" ]; then
        strategy="replace"
    fi

    local temp_resp
    temp_resp=$(mktemp) || return 1

    whiptail --title "CONECTANDO..." --infobox "Consultando Torre Master de origem em:\n$remote_endpoint..." 8 60

    local http_code
    http_code=$(curl -sS -k -w "%{http_code}" -o "$temp_resp" \
        --max-time 15 \
        -H "X-SetupMNO-Fleet-Token: $remote_token" \
        -H "Accept: application/json" \
        "$remote_endpoint/api/fleet/inventory/export" 2>/dev/null || echo "000")

    if [ "$http_code" = "401" ] || [ "$http_code" = "403" ]; then
        rm -f "$temp_resp"
        whiptail --title "AUTENTICAÇÃO RECUSADA" --msgbox \
            "A Torre Master remota recusou o token informado (HTTP $http_code).\n\nVerifique se o token de frota da Torre remota está correto." 12 65
        return 0
    fi

    if [ "$http_code" != "200" ]; then
        rm -f "$temp_resp"
        whiptail --title "FALHA DE CONEXÃO" --msgbox \
            "Falha ao conectar à Torre Master remota (HTTP $http_code).\n\nVerifique se a URL está correta e com o Cloudflare Tunnel ativo." 12 65
        return 0
    fi

    local imported_count
    imported_count=$(jq '.nodes | length' "$temp_resp" 2>/dev/null || echo "0")

    if [ "$imported_count" -le 0 ]; then
        rm -f "$temp_resp"
        whiptail --title "AVISO" --msgbox "A Torre remota não possui nós operários subordinados para exportar." 10 65
        return 0
    fi

    local inv_file="$CONTROL_DIR/fleet-inventory.json"
    local temp_inv
    temp_inv=$(mktemp "$CONTROL_DIR/fleet-inventory.tmp.XXXXXX") || { rm -f "$temp_resp"; return 1; }
    chmod 0600 "$temp_inv"

    local current_json="{}"
    if [ -f "$inv_file" ]; then
        current_json=$(cat "$inv_file")
    else
        current_json='{"schemaVersion":1,"policyVersion":"1.0.0","updatedAt":"","nodes":[]}'
    fi

    if [ "$strategy" = "replace" ]; then
        jq --slurpfile exp "$temp_resp" '
            .schemaVersion = 1 |
            .policyVersion = "1.0.0" |
            .updatedAt = (now | todate) |
            .nodes = [
                (.nodes[] | select(.mode == "master" or (.id | startswith("node-master")))),
                $exp[0].nodes[]
            ]
        ' <<< "$current_json" > "$temp_inv" || { rm -f "$temp_resp" "$temp_inv"; fail "Erro ao compor JSON."; }
    else
        jq --slurpfile exp "$temp_resp" '
            .schemaVersion = 1 |
            .policyVersion = "1.0.0" |
            .updatedAt = (now | todate) |
            .nodes as $existing |
            $exp[0].nodes as $new |
            .nodes = ($existing + [$new[] | select( [.] as $item | $existing | map(.id == $item[0].id or (.endpoint != "" and .endpoint == $item[0].endpoint)) | any | not )])
        ' <<< "$current_json" > "$temp_inv" || { rm -f "$temp_resp" "$temp_inv"; fail "Erro ao compor JSON."; }
    fi

    mv -f "$temp_inv" "$inv_file"
    rm -f "$temp_resp"

    whiptail --title "SINCRONIZAÇÃO CONCLUÍDA" --msgbox \
        "Inventário sincronizado com sucesso!\n\nForam processados $imported_count nós da Torre Master:\n$remote_endpoint\n\nEstratégia aplicada: $strategy\n\nAbra o Control Center Web para visualizar a frota conectada." 15 74
}

action="${1:-status}"
case "$action" in
    status)
        get_status
        ;;
    get-role)
        get_role
        ;;
    role)
        shift
        set_role "${1:-}"
        ;;
    info)
        get_info
        ;;
    set)
        shift
        set_mode "${1:-}"
        ;;
    sync-inventory)
        shift
        sync_master_inventory
        ;;
    menu)
        show_menu
        ;;
    *)
        fail "Ação desconhecida: $action. Use: $0 [status | get-role | role <active|standby> | info | set <disabled|master|worker> | sync-inventory | menu]"
        ;;
esac

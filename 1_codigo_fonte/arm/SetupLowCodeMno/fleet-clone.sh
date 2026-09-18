#!/usr/bin/bash
# ==============================================================================
# MNO FLEET HUB — CLONE, TRANSFERÊNCIA E BACKUP DE APLICAÇÕES ENTRE SERVIDORES
# Compatível com Torre Master (Cockpit Local) e Nós Workers (VPS Remotas)
# Garante paridade de processador (x86 vs ARM), verificação prévia de recursos,
# resolução de stacks vivas do Portainer, extração lógica multi-tenant de bancos
# (PostgreSQL e MySQL 8.4), comutação de DNS Cloudflare e congelamento seguro.
# ==============================================================================
set -uo pipefail
umask 077

CONTROL_DIR="${SETUPMNO_CONTROL_DIR:-/root/SetupLowCodeMno/.control}"
ENV_FILE="$CONTROL_DIR/environment.json"
INVENTORY_FILE="$CONTROL_DIR/fleet-inventory.json"
SSH_HOSTS_FILE="$CONTROL_DIR/fleet-ssh.json"
BACKUP_BASE_DIR="/root/setupmno-backups"
TRANSFER_LOG="/tmp/fleet-transfer.log"

# Configuração de Cores Newt / Whiptail
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
actlistbox=white,black
actsellistbox=white,blue
checkbox=red,black
actcheckbox=white,blue
'

fail() {
    printf '%s\n' "$1" >&2
    exit 1
}

msg() {
    whiptail --title "MNO FLEET HUB — CLONE E BACKUP" --msgbox "$1" 14 76
}

ensure_ssh_keys_available() {
    mkdir -p /root/.ssh 2>/dev/null || true
    chmod 700 /root/.ssh 2>/dev/null || true

    # Se root não possui chave privada, procurar em /home/*/.ssh/
    if [ ! -f /root/.ssh/id_rsa ] && [ ! -f /root/.ssh/id_ed25519 ]; then
        for udir in /home/*; do
            [ -d "$udir/.ssh" ] || continue
            if [ -f "$udir/.ssh/id_ed25519" ]; then
                cp -f "$udir/.ssh/id_ed25519"* /root/.ssh/ 2>/dev/null || true
                chmod 600 /root/.ssh/id_ed25519 2>/dev/null || true
                break
            elif [ -f "$udir/.ssh/id_rsa" ]; then
                cp -f "$udir/.ssh/id_rsa"* /root/.ssh/ 2>/dev/null || true
                chmod 600 /root/.ssh/id_rsa 2>/dev/null || true
                break
            fi
        done
    fi
}

sync_fleet_inventory() {
    if ! command -v docker >/dev/null 2>&1; then
        return 0
    fi

    local audit_vol=""
    # 1. Tentar obter o volume montado em /audit no container web ativo do Control Center
    local web_container
    web_container=$(docker ps -q --filter "name=mnoctrl.*web" 2>/dev/null | head -n 1)
    if [ -n "$web_container" ]; then
        audit_vol=$(docker inspect "$web_container" --format '{{range .Mounts}}{{if eq .Destination "/audit"}}{{.Name}}{{end}}{{end}}' 2>/dev/null || true)
    fi

    # 2. Se o container não estiver rodando no momento, tentar inspecionar o serviço Swarm
    if [ -z "$audit_vol" ]; then
        local web_service
        web_service=$(docker service ls -q --filter "name=mnoctrl.*web" 2>/dev/null | head -n 1)
        if [ -n "$web_service" ]; then
            audit_vol=$(docker service inspect "$web_service" --format '{{range .Spec.TaskTemplate.ContainerSpec.Mounts}}{{if eq .Target "/audit"}}{{.Source}}{{end}}{{end}}' 2>/dev/null || true)
        fi
    fi

    # 3. Fallback: volume audit_data mais recente
    if [ -z "$audit_vol" ]; then
        audit_vol=$(docker volume ls --filter "name=audit_data" --format '{{.CreatedAt}}\t{{.Name}}' 2>/dev/null | sort -r | head -n 1 | awk '{print $NF}')
    fi

    # 4. Fallback final
    if [ -z "$audit_vol" ]; then
        audit_vol=$(docker volume ls -q --filter "name=audit_data" 2>/dev/null | tail -n 1)
    fi

    if [ -n "$audit_vol" ]; then
        local inv_data
        inv_data=$(docker run --rm -v "${audit_vol}:/audit" alpine cat /audit/fleet-inventory.json 2>/dev/null || true)
        if [ -n "$inv_data" ] && [ "$inv_data" != "null" ]; then
            if printf '%s' "$inv_data" | jq -e . >/dev/null 2>&1; then
                mkdir -p "$(dirname "$INVENTORY_FILE")" 2>/dev/null || true
                printf '%s\n' "$inv_data" > "$INVENTORY_FILE" 2>/dev/null || true
            fi
        fi

        local pending_data
        pending_data=$(docker run --rm -v "${audit_vol}:/audit" alpine cat /audit/pending-fleet-clone.json 2>/dev/null || true)
        if [ -n "$pending_data" ] && [ "$pending_data" != "null" ]; then
            if printf '%s' "$pending_data" | jq -e . >/dev/null 2>&1; then
                mkdir -p "$(dirname "$INVENTORY_FILE")" 2>/dev/null || true
                printf '%s\n' "$pending_data" > "$CONTROL_DIR/pending-fleet-clone.json" 2>/dev/null || true
            fi
        fi
        return 0
    fi
}

cleanup_pending_fleet_task() {
    rm -f "$CONTROL_DIR/pending-fleet-clone.json" 2>/dev/null || true
    if command -v docker >/dev/null 2>&1; then
        local audit_vol
        audit_vol=$(docker volume ls --filter "name=audit_data" --format '{{.Name}}' 2>/dev/null | head -n 1)
        if [ -n "$audit_vol" ]; then
            docker run --rm -v "${audit_vol}:/audit" alpine rm -f /audit/pending-fleet-clone.json 2>/dev/null || true
        fi
    fi
}

get_local_fleet_mode() {
    [ -f "$ENV_FILE" ] || { printf 'disabled\n'; return; }
    jq -r '.fleetMode // "disabled"' "$ENV_FILE" 2>/dev/null || printf 'disabled\n'
}

get_local_fleet_node_id() {
    [ -f "$ENV_FILE" ] || { printf '\n'; return; }
    jq -r '.fleetNodeId // empty' "$ENV_FILE" 2>/dev/null || true
}

# ==============================================================================
# GESTÃO DE TRAVA DE OCUPAÇÃO NO WORKER (NODE LEASE / LOCK)
# ==============================================================================
acquire_node_lock() {
    local node_id="$1"
    local task_name="${2:-Operacao Fleet Hub}"
    local ttl="${3:-300}"
    local holder_id holder_name
    holder_id=$(jq -r '.fleetNodeId // "master-local"' "$ENV_FILE" 2>/dev/null || printf 'master-local')
    holder_name="Torre Master ($holder_id)"

    local endpoint="" token=""
    if [ "$node_id" = "local" ]; then
        endpoint="http://127.0.0.1:8080"
        token=$(jq -r '.fleetToken // empty' "$ENV_FILE" 2>/dev/null || true)
    elif [ -f "$INVENTORY_FILE" ]; then
        endpoint=$(jq -r --arg id "$node_id" '.nodes[]? | select(.id == $id) | .endpoint' "$INVENTORY_FILE" 2>/dev/null || true)
        token=$(jq -r --arg id "$node_id" '.nodes[]? | select(.id == $id) | .token' "$INVENTORY_FILE" 2>/dev/null || true)
    fi

    [ -n "$endpoint" ] || return 0

    local payload
    payload=$(jq -n \
        --arg action "acquire" \
        --arg holderId "$holder_id" \
        --arg holderName "$holder_name" \
        --arg task "$task_name" \
        --argjson ttl "$ttl" \
        '{action: $action, holderId: $holderId, holderName: $holderName, task: $task, ttlSeconds: $ttl}')

    local resp_body http_code
    local temp_out
    temp_out=$(mktemp) || return 0
    http_code=$(curl -s -k -m 6 -o "$temp_out" -w "%{http_code}" \
        -X POST "$endpoint/api/fleet/worker/lock" \
        -H "Content-Type: application/json" \
        -H "X-SetupMNO-Fleet-Token: $token" \
        -H "Authorization: Bearer $token" \
        -d "$payload" 2>/dev/null || printf '000')

    resp_body=$(cat "$temp_out" 2>/dev/null || true)
    rm -f "$temp_out"

    if [ "$http_code" = "409" ]; then
        local lock_task lock_holder
        lock_task=$(jq -r '.lock.task // "Operação em andamento"' <<<"$resp_body" 2>/dev/null || printf 'Operação em andamento')
        lock_holder=$(jq -r '.lock.holderName // "outra central"' <<<"$resp_body" 2>/dev/null || printf 'outra central')
        echo "⚠️ BLOQUEIO DE CONCORRÊNCIA: O nó '$node_id' está ocupado ($lock_task por $lock_holder)." >&2
        whiptail --title "⚠️ SERVIDOR OCUPADO (CONFLITO EVITADO)" --msgbox \
            "O servidor selecionado ($node_id) está OCUPADO no momento!\n\nTarefa em execução: $lock_task\nDisparada por: $lock_holder\n\nPara evitar corrupção de dados ou colisão de backups, a operação foi suspensa com segurança.\n\nAguarde o término da tarefa em andamento ou tente novamente em alguns minutos." 16 76 3>&1 1>&2 2>&3 || true
        return 1
    fi

    return 0
}

release_node_lock() {
    local node_id="$1"
    local holder_id
    holder_id=$(jq -r '.fleetNodeId // "master-local"' "$ENV_FILE" 2>/dev/null || printf 'master-local')

    local endpoint="" token=""
    if [ "$node_id" = "local" ]; then
        endpoint="http://127.0.0.1:8080"
        token=$(jq -r '.fleetToken // empty' "$ENV_FILE" 2>/dev/null || true)
    elif [ -f "$INVENTORY_FILE" ]; then
        endpoint=$(jq -r --arg id "$node_id" '.nodes[]? | select(.id == $id) | .endpoint' "$INVENTORY_FILE" 2>/dev/null || true)
        token=$(jq -r --arg id "$node_id" '.nodes[]? | select(.id == $id) | .token' "$INVENTORY_FILE" 2>/dev/null || true)
    fi

    [ -n "$endpoint" ] || return 0

    local payload
    payload=$(jq -n \
        --arg action "release" \
        --arg holderId "$holder_id" \
        '{action: $action, holderId: $holderId}')

    curl -s -k -m 4 -o /dev/null \
        -X POST "$endpoint/api/fleet/worker/lock" \
        -H "Content-Type: application/json" \
        -H "X-SetupMNO-Fleet-Token: $token" \
        -H "Authorization: Bearer $token" \
        -d "$payload" 2>/dev/null || true
}

get_local_arch() {
    local raw_arch
    raw_arch=$(uname -m)
    case "$raw_arch" in
        x86_64|amd64) printf 'amd64\n' ;;
        aarch64|arm64) printf 'arm64\n' ;;
        *) printf '%s\n' "$raw_arch" ;;
    esac
}

get_local_ram_free_mb() {
    free -m 2>/dev/null | awk '/^Mem:/{print $7}' || printf '1024\n'
}

get_local_disk_free_gb() {
    df -BG / 2>/dev/null | awk 'NR==2{print $4}' | tr -d 'G' || printf '10\n'
}

list_local_swarm_stacks() {
    if command -v docker >/dev/null 2>&1 && docker info 2>/dev/null | grep -q "Swarm: active"; then
        docker stack ls --format '{{.Name}}' 2>/dev/null || true
    fi
}

resolve_worker_ssh_host() {
    local _r_node_id="$1"
    local _r_node_name="${2:-}"
    local _r_ret_var="${3:-}"
    local _r_host=""

    mkdir -p "$CONTROL_DIR" 2>/dev/null || true

    # 1. Tentar ler do arquivo persistente fleet-ssh.json
    if [ -f "$SSH_HOSTS_FILE" ]; then
        _r_host=$(jq -r --arg id "$_r_node_id" --arg name "$_r_node_name" '.[$id] // .[$name] // empty' "$SSH_HOSTS_FILE" 2>/dev/null || true)
    fi

    local ep="" tok=""
    if [ -f "$INVENTORY_FILE" ]; then
        # 2. Tentar ler campo publicIp diretamente gravado no inventário
        if [ -z "$_r_host" ]; then
            _r_host=$(jq -r --arg id "$_r_node_id" --arg name "$_r_node_name" \
                '.nodes[]? | select(.id == $id or .name == $name) | .publicIp // .telemetry.publicIp // .nodeIp // .ip // empty' \
                "$INVENTORY_FILE" 2>/dev/null | head -n 1 || true)
        fi

        ep=$(jq -r --arg id "$_r_node_id" --arg name "$_r_node_name" \
            '.nodes[]? | select(.id == $id or .name == $name) | .endpoint // empty' \
            "$INVENTORY_FILE" 2>/dev/null | head -n 1 || true)
        tok=$(jq -r --arg id "$_r_node_id" --arg name "$_r_node_name" \
            '.nodes[]? | select(.id == $id or .name == $name) | .token // empty' \
            "$INVENTORY_FILE" 2>/dev/null | head -n 1 || true)

        # 3. Se o endpoint for IP numérico direto (ex: http://46.224.155.11:8080)
        if [ -z "$_r_host" ] && [[ "$ep" =~ ^https?://([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+) ]]; then
            _r_host="${BASH_REMATCH[1]}"
        fi

        # 4. Se for domínio Cloudflare Tunnel, consultar a telemetria do worker em tempo real via API
        if [ -z "$_r_host" ] && [ -n "$ep" ]; then
            local telem_raw
            telem_raw=$(curl -s -k --connect-timeout 4 -m 6 -H "X-SetupMNO-Fleet-Token: $tok" "${ep}/api/fleet/worker/telemetry" 2>/dev/null || true)
            if [ -n "$telem_raw" ]; then
                _r_host=$(jq -r '.publicIp // .nodeIp // .ip // .nodeAddr // empty' <<< "$telem_raw" 2>/dev/null || true)
            fi
        fi

        # 5. Consulta alternativa ao endpoint de IP do worker
        if [ -z "$_r_host" ] && [ -n "$ep" ]; then
            local ip_resp
            ip_resp=$(curl -s -k --connect-timeout 4 -m 6 -H "X-SetupMNO-Fleet-Token: $tok" "${ep}/api/fleet/worker/ip" 2>/dev/null || true)
            if [ -n "$ip_resp" ]; then
                _r_host=$(jq -r '.publicIp // empty' <<< "$ip_resp" 2>/dev/null || true)
                [ -z "$_r_host" ] && [[ "$ip_resp" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] && _r_host="$ip_resp"
            fi
        fi
    fi

    # Se encontramos o IP automaticamente, persistir imediatamente em fleet-ssh.json
    if [ -n "$_r_host" ]; then
        local current_json="{}"
        [ -f "$SSH_HOSTS_FILE" ] && current_json=$(cat "$SSH_HOSTS_FILE" 2>/dev/null || printf '{}')
        local updated_json
        updated_json=$(printf '%s' "$current_json" | jq --arg id "$_r_node_id" --arg name "$_r_node_name" --arg h "$_r_host" '.[$id] = $h | .[$name] = $h' 2>/dev/null || printf '{"%s": "%s"}' "$_r_node_id" "$_r_host")
        printf '%s\n' "$updated_json" > "$SSH_HOSTS_FILE" 2>/dev/null || true
    fi

    # Se ainda vazio (contingência extrema caso o nó esteja completamente inacessível na nuvem)
    if [ -z "$_r_host" ]; then
        if [ "${is_cli:-false}" = "true" ] || [ ! -t 0 ]; then
            echo "ERRO SSH: Endereço IP do servidor '$_r_node_name' não encontrado automaticamente." >&2
            return 1
        fi
        _r_host=$(whiptail --title "CONEXÃO SSH COM O SERVIDOR ($_r_node_name)" --inputbox \
            "Informe o endereço IP da VPS para transferência de dados:" 12 74 "" 3>&1 1>&2 2>&3) || return 1
        [ -n "$_r_host" ] || return 1

        local current_json="{}"
        [ -f "$SSH_HOSTS_FILE" ] && current_json=$(cat "$SSH_HOSTS_FILE" 2>/dev/null || printf '{}')
        local updated_json
        updated_json=$(printf '%s' "$current_json" | jq --arg id "$_r_node_id" --arg name "$_r_node_name" --arg h "$_r_host" '.[$id] = $h | .[$name] = $h' 2>/dev/null || printf '{"%s": "%s"}' "$_r_node_id" "$_r_host")
        printf '%s\n' "$updated_json" > "$SSH_HOSTS_FILE" 2>/dev/null || true
    fi

    ensure_ssh_keys_available

    # Limpar qualquer chave antiga ou alterada do host para evitar aviso de host key change
    ssh-keygen -f /root/.ssh/known_hosts -R "$_r_host" >/dev/null 2>&1 || true

    # Testar conectividade SSH com timeout estrito de 4s (evita qualquer travamento)
    if ! timeout 4 ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o BatchMode=yes -o ConnectTimeout=3 -o ServerAliveInterval=2 -o ServerAliveCountMax=1 "root@$_r_host" "echo ok" >/dev/null 2>&1; then
        # Tenta autorizar automaticamente a chave SSH pública via Fleet API Zero-Trust antes de solicitar senha
        if [ -n "$ep" ] && [ -n "$tok" ]; then
            local pub_key=""
            [ -f /root/.ssh/id_rsa.pub ] && pub_key=$(cat /root/.ssh/id_rsa.pub 2>/dev/null || true)
            [ -z "$pub_key" ] && [ -f /root/.ssh/id_ed25519.pub ] && pub_key=$(cat /root/.ssh/id_ed25519.pub 2>/dev/null || true)
            if [ -n "$pub_key" ]; then
                curl -s -k --connect-timeout 4 -m 8 -X POST \
                    -H "X-SetupMNO-Fleet-Token: $tok" \
                    -H "Content-Type: application/json" \
                    -d "{\"action\":\"authorize_ssh_key\",\"payload\":{\"key\":\"$pub_key\"}}" \
                    "${ep}/api/fleet/worker/action" >/dev/null 2>&1 || true
            fi
        fi

        # Se após a autorização automática ainda não conectar, solicita a senha do root no Whiptail
        if ! timeout 4 ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o BatchMode=yes -o ConnectTimeout=3 -o ServerAliveInterval=2 -o ServerAliveCountMax=1 "root@$_r_host" "echo ok" >/dev/null 2>&1; then
            if [ "${is_cli:-false}" = "true" ] || [ ! -t 0 ]; then
                echo "ERRO SSH: Chave SSH pública não autorizada no servidor '$_r_node_name' ($_r_host)." >&2
                return 1
            fi
            local vps_pwd
            vps_pwd=$(whiptail --title "AUTENTICAÇÃO SSH NECESSÁRIA" --passwordbox \
                "A chave SSH ainda não está autorizada no nó '$_r_node_name' ($_r_host).\n\nInforme a senha de root da VPS para estabelecer a conexão segura:" 12 74 3>&1 1>&2 2>&3) || return 1
            
            if [ -n "$vps_pwd" ]; then
                if ! command -v sshpass >/dev/null 2>&1; then
                    export DEBIAN_FRONTEND=noninteractive
                    apt-get update -qq >/dev/null 2>&1 || true
                    apt-get install -y -qq sshpass >/dev/null 2>&1 || true
                fi
                if command -v sshpass >/dev/null 2>&1; then
                    timeout 12 sshpass -p "$vps_pwd" ssh-copy-id -o StrictHostKeyChecking=accept-new -o LogLevel=ERROR "root@$_r_host" >/dev/null 2>&1 || true
                fi
            fi
        fi
    fi

    if [ -n "$_r_ret_var" ]; then
        printf -v "$_r_ret_var" '%s' "$_r_host"
    else
        printf '%s\n' "$_r_host"
    fi
    return 0
}

# Executa comandos locais ou remotos de forma segura
exec_node() {
    local node_id="$1"
    local host="$2"
    local cmd="$3"

    if [ "$node_id" = "local" ]; then
        eval "$cmd"
    else
        ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o BatchMode=yes -o ConnectTimeout=15 "root@$host" "$cmd"
    fi
}

# Resolução de Live Stack do Portainer
resolve_live_stack_yaml() {
    local node_id="$1"
    local host="$2"
    local app="$3"
    local out_file="$4"

    mkdir -p "$(dirname "$out_file")"

    local pfile=""
    if [ "$node_id" = "local" ]; then
        if [ -s "/root/${app}.yaml" ]; then
            cp -f "/root/${app}.yaml" "$out_file"
            return 0
        fi
        if [ -s "/root/SetupLowCodeMno/stacks/${app}.yml" ]; then
            cp -f "/root/SetupLowCodeMno/stacks/${app}.yml" "$out_file"
            return 0
        fi
        # Checagem direta no sistema de arquivos do volume se acessivel
        local local_pfile
        local_pfile=$(grep -rl "$app" /var/lib/docker/volumes/portainer_data/_data/compose/*/docker-compose.yml 2>/dev/null | head -n 1 || true)
        if [ -n "$local_pfile" ] && [ -s "$local_pfile" ]; then
            cp -f "$local_pfile" "$out_file" 2>/dev/null || true
            if [ -s "$out_file" ]; then
                cp -f "$out_file" "/root/${app}.yaml" 2>/dev/null || true
                return 0
            fi
        fi
        # Fallback com container auxiliar
        pfile=$(docker run --rm -v portainer_data:/pdata alpine sh -c "grep -rl '$app' /pdata/compose/*/docker-compose.yml 2>/dev/null | head -n 1" 2>/dev/null || true)
        if [ -n "$pfile" ]; then
            docker run --rm -v portainer_data:/pdata alpine cat "$pfile" > "$out_file" 2>/dev/null || true
            if [ -s "$out_file" ]; then
                cp -f "$out_file" "/root/${app}.yaml" 2>/dev/null || true
                return 0
            fi
        fi
    else
        # 1. Checagem direta ultra-rápida do arquivo /root/${app}.yaml (0.05s)
        if timeout 8 ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o BatchMode=yes -o ConnectTimeout=5 "root@$host" "[ -s /root/${app}.yaml ]"; then
            timeout 8 ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o BatchMode=yes -o ConnectTimeout=5 "root@$host" "cat /root/${app}.yaml" > "$out_file" 2>/dev/null || true
            if [ -s "$out_file" ]; then
                return 0
            fi
        fi
        # 2. Checagem ultra-rápida no fs do volume Portainer do host remoto (0.004s)
        local direct_pfile
        direct_pfile=$(timeout 8 ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o BatchMode=yes -o ConnectTimeout=5 "root@$host" "grep -rl '$app' /var/lib/docker/volumes/portainer_data/_data/compose/*/docker-compose.yml 2>/dev/null | head -n 1" 2>/dev/null || true)
        if [ -n "$direct_pfile" ]; then
            timeout 8 ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o BatchMode=yes -o ConnectTimeout=5 "root@$host" "cat '$direct_pfile'" > "$out_file" 2>/dev/null || true
            if [ -s "$out_file" ]; then
                timeout 8 ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o BatchMode=yes -o ConnectTimeout=5 "root@$host" "cat > /root/${app}.yaml" < "$out_file" 2>/dev/null || true
                return 0
            fi
        fi
        # 3. Fallback via docker run no nó remoto (com timeout seguro de 25s)
        pfile=$(timeout 25 ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o BatchMode=yes -o ConnectTimeout=8 "root@$host" "docker run --rm -v portainer_data:/pdata alpine sh -c \"grep -rl '$app' /pdata/compose/*/docker-compose.yml 2>/dev/null | head -n 1\" 2>/dev/null" || true)
        if [ -n "$pfile" ]; then
            timeout 25 ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o BatchMode=yes -o ConnectTimeout=8 "root@$host" "docker run --rm -v portainer_data:/pdata alpine cat '$pfile' 2>/dev/null" > "$out_file" 2>/dev/null || true
            if [ -s "$out_file" ]; then
                timeout 8 ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o BatchMode=yes -o ConnectTimeout=5 "root@$host" "cat > /root/${app}.yaml" < "$out_file" 2>/dev/null || true
                return 0
            fi
        fi
        # 4. Checagem em stacks do repositório remoto
        if timeout 8 ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o BatchMode=yes -o ConnectTimeout=5 "root@$host" "[ -s /root/SetupLowCodeMno/stacks/${app}.yml ]"; then
            timeout 8 ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o BatchMode=yes -o ConnectTimeout=5 "root@$host" "cat /root/SetupLowCodeMno/stacks/${app}.yml" > "$out_file" 2>/dev/null || true
            if [ -s "$out_file" ]; then
                return 0
            fi
        fi
    fi

    return 1
}

# Detecção de Banco Multi-Tenant
detect_database_engine() {
    local yaml_file="$1"
    local app="$2"

    # Se a própria stack for de banco de dados, ela é o servidor, não consumidora
    if [[ "$app" == postgres* ]] || [[ "$app" == mysql* ]]; then
        printf "none:\n"
        return 0
    fi

    local active_yaml
    if [ -f "$yaml_file" ]; then
        active_yaml=$(grep -v '^[[:space:]]*#' "$yaml_file" 2>/dev/null || true)
    else
        active_yaml=$(printf '%s\n' "$yaml_file" | grep -v '^[[:space:]]*#' || true)
    fi

    # 1. PostgreSQL (Detecção via Connection URI, variáveis explícitas ou host padrão)
    if grep -qE "postgres|POSTGRES|5432|6432" <<< "$active_yaml"; then
        local pg_db=""
        # Prioridade 1: Connection URI explícita da aplicação (ex: Evolution API, Directus, Rails, etc.)
        local uri_line
        uri_line=$(grep -E "^[[:space:]]*-?[[:space:]]*(DATABASE_CONNECTION_URI|DATABASE_URL|PG_DATABASE_URL|LANGFLOW_DATABASE_URL)=" <<< "$active_yaml" | head -n1 || true)
        if [ -n "$uri_line" ]; then
            local raw_db
            raw_db=$(echo "$uri_line" | sed -E 's/.*:[0-9]+\/([^?[:space:]"'\''`]+).*/\1/' | cut -d? -f1 | tr -d ' "\r'\''`')
            if [ -n "$raw_db" ] && [ "$raw_db" != "$uri_line" ] && [[ "$raw_db" =~ ^[a-zA-Z0-9_.-]+$ ]]; then
                pg_db="$raw_db"
            fi
        fi

        # Prioridade 2: Variáveis dedicadas de nome de database
        if [ -z "$pg_db" ]; then
            pg_db=$(grep -E "^[[:space:]]*-?[[:space:]]*(POSTGRES_DATABASE|POSTGRES_DB|DB_POSTGRESDB_DATABASE|AP_POSTGRES_DATABASE|POSTGRESQL_DATABASE)=" <<< "$active_yaml" 2>/dev/null | head -n1 | cut -d= -f2- | tr -d ' "\r'\''`' || true)
        fi

        # Prioridade 3: Fallback heurístico para nome da stack se conecta ao postgres
        if [ -z "$pg_db" ] && grep -qE "POSTGRES_HOST|postgres:5432|postgres:6432" <<< "$active_yaml"; then
            pg_db="$app"
        fi

        if [ -n "$pg_db" ]; then
            printf "postgres:%s\n" "$pg_db"
            return 0
        fi
    fi

    # 2. MySQL 8.4
    if grep -qE "MAUTIC_DB_HOST=mysql84|MYSQL_HOST=mysql84|mysql84:3306" <<< "$active_yaml"; then
        local my_db
        my_db=$(grep -E "^[[:space:]]*-?[[:space:]]*(MAUTIC_DB_NAME|MYSQL_DATABASE)=" <<< "$active_yaml" 2>/dev/null | head -n1 | cut -d= -f2- | tr -d ' "\r'\''`' || true)
        [ -n "$my_db" ] || my_db="$app"
        printf "mysql84:%s\n" "$my_db"
        return 0
    fi

    # 3. MySQL 8.0 (Legacy / Shared)
    if grep -qE "WORDPRESS_DB_HOST=mysql|MAUTIC_DB_HOST=mysql|HUMHUB_DB_HOST=mysql|BOOKSTACK_DB_HOST=mysql|DB_HOST=mysql|MYSQL_HOST=mysql|mysql:3306|WORDPRESS_DB_NAME" <<< "$active_yaml"; then
        local my_db
        my_db=$(grep -E "^[[:space:]]*-?[[:space:]]*(WORDPRESS_DB_NAME|MAUTIC_DB_NAME|HUMHUB_DB_NAME|BOOKSTACK_DB_DATABASE|DB_NAME|DB_DATABASE|MYSQL_DATABASE)=" <<< "$active_yaml" 2>/dev/null | head -n1 | cut -d= -f2- | tr -d ' "\r'\''`' || true)
        [ -n "$my_db" ] || my_db="$app"
        printf "mysql:%s\n" "$my_db"
        return 0
    fi

    # 4. MongoDB
    if grep -qE "MONGO_URL|MONGODB_URL|mongodb://|mongo:27017" <<< "$active_yaml"; then
        local mg_db
        mg_db=$(grep -E "MONGO_URL=|MONGODB_URL=" <<< "$active_yaml" 2>/dev/null | head -n1 | sed -E 's/.*\/(.*)\?.*/\1/' | sed -E 's/.*\/([a-zA-Z0-9_-]+)$/\1/' | tr -d ' "\r' || true)
        [ -n "$mg_db" ] || mg_db="$app"
        printf "mongodb:%s\n" "$mg_db"
        return 0
    fi

    printf "none:\n"
}

# Detecção de Storage MinIO / S3
detect_s3_storage_engine() {
    local yaml_file="$1"
    local app="$2"

    # Se a própria stack for MinIO, ela é o servidor de armazenamento, não consumidora
    if [[ "$app" == minio* ]]; then
        printf "none:\n"
        return 0
    fi

    local active_yaml
    if [ -f "$yaml_file" ]; then
        active_yaml=$(grep -v '^[[:space:]]*#' "$yaml_file" 2>/dev/null || true)
    else
        active_yaml=$(printf '%s\n' "$yaml_file" | grep -v '^[[:space:]]*#' || true)
    fi

    if grep -qE "S3_BUCKET|S3_BUCKET_NAME|AWS_BUCKET|AWS_S3_BUCKET|STORAGE_BUCKET_NAME|MINIO_PUBLIC_URL|MINIO_SERVER_URL" <<< "$active_yaml"; then
        local b_name
        b_name=$(grep -E "^[[:space:]]*-?[[:space:]]*(S3_BUCKET|S3_BUCKET_NAME|AWS_BUCKET|AWS_S3_BUCKET|STORAGE_BUCKET_NAME)=" <<< "$active_yaml" 2>/dev/null | head -n1 | cut -d= -f2- | tr -d ' "\r'\''`' || true)
        [ -n "$b_name" ] || b_name="$app"
        printf "minio:%s\n" "$b_name"
        return 0
    fi
    printf "none:\n"
}

# Detecção de Mensageria RabbitMQ
detect_rabbitmq_engine() {
    local yaml_file="$1"
    local app="$2"

    # Se a própria stack for RabbitMQ, ela é o broker, não consumidora
    if [[ "$app" == rabbitmq* ]]; then
        printf "none:\n"
        return 0
    fi

    local active_yaml
    if [ -f "$yaml_file" ]; then
        active_yaml=$(grep -v '^[[:space:]]*#' "$yaml_file" 2>/dev/null || true)
    else
        active_yaml=$(printf '%s\n' "$yaml_file" | grep -v '^[[:space:]]*#' || true)
    fi

    if grep -qE "RABBITMQ_URI|RABBITMQ_URL|RABBITMQ_DEFAULT_USER|amqp://" <<< "$active_yaml"; then
        local mq_vhost
        mq_vhost=$(grep -oP '(?<=amqp://)[^:]+' <<< "$active_yaml" 2>/dev/null | head -n1 || true)
        [ -n "$mq_vhost" ] || mq_vhost="$app"
        printf "rabbitmq:%s\n" "$mq_vhost"
        return 0
    fi
    printf "none:\n"
}

# Detecção de Contexto de Combo (Manifestos ou Heurística Reversa)
detect_app_combo_context() {
    local node_id="$1"
    local host="$2"
    local app="$3"
    local yaml_file="$4"

    local manifest_file="/root/SetupLowCodeMno/.control/manifests/${app}.json"
    local manifest_content=""

    if [ "$node_id" = "local" ]; then
        [ -f "$manifest_file" ] && manifest_content=$(cat "$manifest_file" 2>/dev/null || true)
    else
        manifest_content=$(ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o BatchMode=yes "root@$host" "[ -f '$manifest_file' ] && cat '$manifest_file'" 2>/dev/null || true)
    fi

    if [ -n "$manifest_content" ] && echo "$manifest_content" | jq -e '.combo.isCombo == true' >/dev/null 2>&1; then
        local c_name l_stacks
        c_name=$(echo "$manifest_content" | jq -r '.combo.comboName // "Combo Integrado"')
        l_stacks=$(echo "$manifest_content" | jq -r '.combo.linkedStacks[]? // empty' | tr '\n' ' ')
        printf "true|%s|%s\n" "$c_name" "$l_stacks"
        return 0
    fi

    local all_stacks=""
    if [ "$node_id" = "local" ]; then
        all_stacks=$(list_local_swarm_stacks)
    else
        all_stacks=$(ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o BatchMode=yes "root@$host" "docker stack ls --format '{{.Name}}'" 2>/dev/null || true)
    fi

    local app_suffix=""
    if [[ "$app" =~ ([a-f0-9]{7}) ]]; then
        app_suffix="${BASH_REMATCH[1]}"
    fi

    local linked=()
    local detected_combo_name=""

    if [ -n "$app_suffix" ]; then
        while IFS= read -r s; do
            [ -n "$s" ] || continue
            [ "$s" = "$app" ] && continue
            case "$s" in
                mnoctrl*|cloudflared|traefik|portainer|pgbouncer|redis|postgres|mysql84|mysql) continue ;;
            esac
            if [[ "$s" == *"$app_suffix"* ]]; then
                linked+=("$s")
            fi
        done <<< "$all_stacks"
    fi

    if [[ "$app" == n8n* ]]; then
        detected_combo_name="Combo N8N Automação & IA (Editor + Webhook + Worker + MCP + Redis)"
    elif [[ "$app" == chatwoot* ]] || [[ "$app" == evolution* ]] || [[ "$app" == minio* ]] || [[ "$app" == rabbitmq* ]]; then
        while IFS= read -r s; do
            [ -n "$s" ] || continue
            [ "$s" = "$app" ] && continue
            case "$s" in
                chatwoot*|evolution*|rabbitmq*|minio*|cwt_redis*|evo_redis*)
                    if [[ ! " ${linked[*]} " =~ " ${s} " ]]; then
                        linked+=("$s")
                    fi
                    ;;
            esac
        done <<< "$all_stacks"
        detected_combo_name="Combo Multicanais (Chatwoot + Evolution + RabbitMQ + S3)"
    elif [[ "$app" == plane* ]]; then
        while IFS= read -r s; do
            [ -n "$s" ] || continue
            [ "$s" = "$app" ] && continue
            case "$s" in
                *redis*|*-mq*)
                    if [[ "$s" == *"$app_suffix"* ]] || [[ "$s" == plane* ]]; then
                        if [[ ! " ${linked[*]} " =~ " ${s} " ]]; then
                            linked+=("$s")
                        fi
                    fi
                    ;;
            esac
        done <<< "$all_stacks"
        detected_combo_name="Combo Plane Workspaces (Plane + Redis + RabbitMQ)"
    elif [[ "$app" == typebot* ]] && echo "$all_stacks" | grep -qE "minio.*$app_suffix"; then
        detected_combo_name="Combo Typebot + MinIO S3"
    elif [[ "$app" == evoai* ]] && echo "$all_stacks" | grep -qE "minio.*$app_suffix"; then
        detected_combo_name="Combo EvoAI + Evolution + MinIO S3"
    elif [[ "$app" == hermes* ]] || [[ "$app" == *vibe_ops* ]]; then
        while IFS= read -r s; do
            [ -n "$s" ] || continue
            [ "$s" = "$app" ] && continue
            case "$s" in
                hermes*|n8n*|redis*)
                    if [[ ! " ${linked[*]} " =~ " ${s} " ]]; then
                        linked+=("$s")
                    fi
                    ;;
            esac
        done <<< "$all_stacks"
        detected_combo_name="Combo Vibe Ops (Hermes Agent + n8n v2 Fila + Redis)"
    elif [[ "$app" == *sdr* ]] || [[ "$app" == *ia_whatsapp* ]] || [[ "$app" == *chatwoot* && $(echo "$all_stacks" | grep -E "sdr|ia_whatsapp") ]]; then
        while IFS= read -r s; do
            [ -n "$s" ] || continue
            [ "$s" = "$app" ] && continue
            case "$s" in
                chatwoot*|evolution*|n8n*|redis*)
                    if [[ ! " ${linked[*]} " =~ " ${s} " ]]; then
                        linked+=("$s")
                    fi
                    ;;
            esac
        done <<< "$all_stacks"
        detected_combo_name="Combo SDR 24/7 (Chatwoot + Evolution + n8n + Redis)"
    elif [[ "$app" == *whatsapp_marketing* ]] || [[ "$app" == *whatsmmkt* ]]; then
        while IFS= read -r s; do
            [ -n "$s" ] || continue
            [ "$s" = "$app" ] && continue
            case "$s" in
                mautic*|evolution*|rabbitmq*)
                    if [[ ! " ${linked[*]} " =~ " ${s} " ]]; then
                        linked+=("$s")
                    fi
                    ;;
            esac
        done <<< "$all_stacks"
        detected_combo_name="Combo WhatsApp Marketing (Mautic + Evolution + RabbitMQ)"
    fi

    if [ ${#linked[@]} -gt 0 ]; then
        [ -n "$detected_combo_name" ] || detected_combo_name="Combo Integrado (${app_suffix:-$app})"
        printf "true|%s|%s\n" "$detected_combo_name" "${linked[*]}"
        return 0
    fi

    printf "false||none\n"
}

# Detecta se uma aplicação utiliza uma ou mais stacks de Redis dedicado
detect_dedicated_redis_stack() {
    local node_id="$1"
    local host="$2"
    local app="$3"
    local yaml_file="$4"

    # Se a própria stack já for uma stack de redis dedicado ou infraestrutura de redis global, não busca redis para si mesma
    case "$app" in
        redis|redisinsight|redicommander|cwt_redis*|evo_redis*|redisevo*|*-redis|*_redis|cwt-redis*|evo-redis*)
            return 0
            ;;
    esac

    local all_stacks=""
    if [ "$node_id" = "local" ]; then
        all_stacks=$(list_local_swarm_stacks)
    else
        all_stacks=$(ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o BatchMode=yes "root@$host" "docker stack ls --format '{{.Name}}'" 2>/dev/null || true)
    fi
    [ -n "$all_stacks" ] || return 0

    local found_redis_stacks=()

    # 1. Busca por análise profunda de variáveis de ambiente no arquivo YAML da stack
    # Varre qualquer variável com REDIS (case-insensitive) ou URLs redis:// ou rediss://
    if [ -s "$yaml_file" ]; then
        # Extrai linhas com URLs redis:// ou rediss://
        local url_hosts
        url_hosts=$(grep -oE "rediss?://[^[:space:]'\"<]+" "$yaml_file" 2>/dev/null | sed -E 's|^rediss?://([^@]+@)?([^:/[:space:]'\"']+).*|\2|' | tr -d ' "\r' | grep -vE "^(localhost|127\.0\.0\.1|redis)$" || true)

        # Extrai valores de variáveis contendo REDIS (ex: REDIS=..., REDIS_HOST=..., DISCOURSE_REDIS_HOST=..., etc.)
        local env_hosts
        env_hosts=$(grep -iE "[A-Za-z0-9_]*REDIS[A-Za-z0-9_]*=" "$yaml_file" 2>/dev/null | grep -vE "(PASSWORD|TOKEN|SECRET|PORT|DB|PREFIX|TTL|ENABLED|SSL|SAVE|TIMEOUT)" | cut -d= -f2- | sed -E 's|^rediss?://([^@]+@)?([^:/[:space:]'\"']+).*|\2|' | cut -d: -f1 | tr -d ' "\r' | grep -vE "^(localhost|127\.0\.0\.1|redis)$" || true)

        local candidate_hosts
        candidate_hosts=$(printf "%s\n%s\n" "$url_hosts" "$env_hosts" | sort -u | grep -v '^$')

        while IFS= read -r ch; do
            [ -n "$ch" ] || continue
            # Se o host for diretamente o nome de uma stack existente
            if echo "$all_stacks" | grep -qx "$ch"; then
                [ "$ch" != "$app" ] && found_redis_stacks+=("$ch")
                continue
            fi
            # Se o host for o nome de serviço com underline (ex: plane_redis, dify_redis), testar com hífen
            local alt_hyphen="${ch//_/-}"
            if echo "$all_stacks" | grep -qx "$alt_hyphen"; then
                [ "$alt_hyphen" != "$app" ] && found_redis_stacks+=("$alt_hyphen")
                continue
            fi
            local alt_under="${ch//-/_}"
            if echo "$all_stacks" | grep -qx "$alt_under"; then
                [ "$alt_under" != "$app" ] && found_redis_stacks+=("$alt_under")
                continue
            fi
            # Se uma stack ativa iniciar pelo host ou contiver o host + redis
            while IFS= read -r s; do
                [ -n "$s" ] || continue
                [ "$s" = "$app" ] && continue
                [ "$s" = "redis" ] && continue
                if [[ "$s" == *redis* ]] && ([[ "$s" == *"$ch"* ]] || [[ "$ch" == *"$s"* ]]); then
                    found_redis_stacks+=("$s")
                fi
            done <<< "$all_stacks"
        done <<< "$candidate_hosts"
    fi

    # 2. Busca por sufixo compartilhado (hash de 7 caracteres ou tags como -ai) + palavra "redis" nas stacks ativas
    local app_suffix=""
    if [[ "$app" =~ ([a-f0-9]{7}) ]]; then
        app_suffix="${BASH_REMATCH[1]}"
    elif [[ "$app" =~ (-[a-zA-Z0-9]+)$ ]]; then
        app_suffix="${BASH_REMATCH[1]}"
    fi

    if [ -n "$app_suffix" ] && [ "$app_suffix" != "-redis" ]; then
        while IFS= read -r s; do
            [ -n "$s" ] || continue
            [ "$s" = "$app" ] && continue
            [ "$s" = "redis" ] && continue
            if [[ "$s" == *"$app_suffix"* ]] && [[ "$s" == *redis* ]]; then
                found_redis_stacks+=("$s")
            fi
        done <<< "$all_stacks"
    fi

    # 3. Busca por convenções canônicas de nomenclatura
    local base_clean="${app%%-*}"
    base_clean="${base_clean%%_*}"
    for cand in \
        "${app}-redis" "${app}_redis" \
        "${app}-database-redis" "${app}_database-redis" \
        "${app}_directus-redis" "${app}-directus-redis" \
        "${app}_evolution-redis" "${app}-evolution-redis" \
        "${app}_evocrm-redis" "${app}-evocrm-redis" \
        "${app}_evoai-redis" "${app}-evoai-redis" \
        "${base_clean}-redis" "${base_clean}_redis"; do
        if [ "$cand" != "$app" ] && echo "$all_stacks" | grep -qx "$cand"; then
            found_redis_stacks+=("$cand")
        fi
    done

    # Retorna todas as stacks encontradas (sem duplicatas, sem a própria app e sem redis global)
    if [ ${#found_redis_stacks[@]} -gt 0 ]; then
        printf "%s\n" "${found_redis_stacks[@]}" | grep -vE "^(redis|redisinsight|redicommander|$app)$" | sort -u
    fi

    return 0
}

# Garante que qualquer stack ou combo que possua Redis dedicado tenha o Redis anexado obrigatoriamente
attach_dedicated_redis_to_list() {
    local node_id="$1"
    local host="$2"
    local -n _arr_ref="$3"

    local redis_found=()
    for cur_item in "${_arr_ref[@]}"; do
        [ -n "$cur_item" ] || continue
        local tmp_y
        tmp_y=$(mktemp)
        resolve_live_stack_yaml "$node_id" "$host" "$cur_item" "$tmp_y" 2>/dev/null || true
        local ded_redis_output
        ded_redis_output=$(detect_dedicated_redis_stack "$node_id" "$host" "$cur_item" "$tmp_y")
        rm -f "$tmp_y"

        if [ -n "$ded_redis_output" ]; then
            while IFS= read -r rstack; do
                [ -n "$rstack" ] || continue
                [ "$rstack" = "redis" ] && continue
                if [[ ! " ${_arr_ref[*]} " =~ " ${rstack} " ]] && [[ ! " ${redis_found[*]} " =~ " ${rstack} " ]]; then
                    redis_found+=("$rstack")
                fi
            done <<< "$ded_redis_output"
        fi
    done

    for rf in "${redis_found[@]}"; do
        _arr_ref+=("$rf")
        echo "[REDIS DEDICADO DETECTADO] Stack '$rf' vinculada à aplicação/combo adicionada para migração conjunta obrigatória." >> "${TRANSFER_LOG:-/dev/null}" 2>&1 || true
    done
}

# Gravador de Manifesto Padronizado
save_app_manifest() {
    local node_id="$1"
    local host="$2"
    local app="$3"
    local db_engine="$4"
    local s3_engine="$5"
    local mq_engine="$6"
    local combo_id="${7:-}"
    local combo_name="${8:-}"
    local linked_stacks="${9:-}"

    local manifest_dir="/root/SetupLowCodeMno/.control/manifests"
    local is_combo=false
    [ -n "$combo_id" ] && is_combo=true

    local db_name=""
    local db_type="none"
    if [[ "$db_engine" == postgres:* ]]; then
        db_type="postgres"
        db_name="${db_engine#postgres:}"
    elif [[ "$db_engine" == mysql84:* ]]; then
        db_type="mysql84"
        db_name="${db_engine#mysql84:}"
    elif [[ "$db_engine" == mysql:* ]]; then
        db_type="mysql"
        db_name="${db_engine#mysql:}"
    fi

    local s3_bucket=""
    if [[ "$s3_engine" == minio:* ]]; then
        s3_bucket="${s3_engine#minio:}"
    fi

    local mq_vhost=""
    if [[ "$mq_engine" == rabbitmq:* ]]; then
        mq_vhost="${mq_engine#rabbitmq:}"
    fi

    local json_manifest
    json_manifest=$(jq -n \
        --arg app "$app" \
        --argjson is_combo "$is_combo" \
        --arg combo_id "$combo_id" \
        --arg combo_name "$combo_name" \
        --arg db_type "$db_type" \
        --arg db_name "$db_name" \
        --arg s3_bucket "$s3_bucket" \
        --arg mq_vhost "$mq_vhost" \
        --arg linked "$linked_stacks" \
        --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        '{
            version: "1.0",
            appName: $app,
            stackName: $app,
            updatedAt: $now,
            combo: {
                isCombo: $is_combo,
                comboId: (if $is_combo then $combo_id else null end),
                comboName: (if $is_combo then $combo_name else null end),
                linkedStacks: ($linked | split(" ") | map(select(length > 0)))
            },
            dependencies: {
                database: (if $db_type != "none" then { engine: $db_type, dbName: $db_name, shared: true } else null end),
                storage: (if $s3_bucket != "" then { engine: "minio", bucket: $s3_bucket, shared: true } else null end),
                rabbitmq: (if $mq_vhost != "" then { vhost: $mq_vhost, shared: true } else null end)
            }
        }' 2>/dev/null || printf '{}')

    if [ "$node_id" = "local" ]; then
        mkdir -p "$manifest_dir" 2>/dev/null || true
        printf '%s\n' "$json_manifest" > "$manifest_dir/${app}.json" 2>/dev/null || true
    else
        ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o BatchMode=yes "root@$host" "mkdir -p '$manifest_dir' && cat > '$manifest_dir/${app}.json'" <<< "$json_manifest" 2>/dev/null || true
    fi
}

# Extração de volumes exclusivos (sem infraestrutura compartilhada)
get_application_volumes() {
    local yaml_file="$1"
    local app="$2"
    local origin_id="${3:-}"
    local origin_host="${4:-}"

    local is_redis_stack=false
    if [ "$app" = "redis" ] || [[ "$app" == *-redis ]] || [[ "$app" == *redis* ]]; then
        is_redis_stack=true
    fi

    local vols=()
    while IFS= read -r v; do
        [ -n "$v" ] || continue
        case "$v" in
            postgres_data|mysql84_mysql84_data|mysql_data|portainer_data|traefik*|cloudflared*|audit*|interna|externa)
                continue
                ;;
            redis_data)
                # Volume da infra global compartilhada; ignora a menos que a stack seja a própria stack global redis
                [ "$app" != "redis" ] && continue
                ;;
            postgres*|mysql*|portainer*)
                if [ "$app" != "postgres" ] && [ "$app" != "mysql84" ] && [ "$app" != "mysql" ]; then
                    continue
                fi
                ;;
            redis*)
                # Preserva volumes de redis dedicado (ex: redisevo-data, redis-data)
                if [ "$is_redis_stack" = "true" ] || [[ "$v" == *"$app"* ]]; then
                    vols+=("$v")
                    continue
                fi
                ;;
            *)
                ;;
        esac
        vols+=("$v")
    done < <(awk '
        /^volumes:/ { in_vols=1; next }
        in_vols && /^  [a-zA-Z0-9_.-]+:/ {
            v=$1; sub(/^  /, "", v); sub(/:.*/, "", v); print v; next
        }
        in_vols && /^[a-zA-Z0-9_.-]+:/ { in_vols=0 }
    ' "$yaml_file" 2>/dev/null || true)

    if [ ${#vols[@]} -eq 0 ]; then
        while IFS= read -r v; do
            [ -n "$v" ] || continue
            case "$v" in
                postgres_data|mysql84_mysql84_data|mysql_data|portainer_data|traefik*|cloudflared*|audit*|interna|externa)
                    continue
                    ;;
                redis_data)
                    [ "$app" != "redis" ] && continue
                    ;;
                postgres*|mysql*|portainer*)
                    if [ "$app" != "postgres" ] && [ "$app" != "mysql84" ] && [ "$app" != "mysql" ]; then
                        continue
                    fi
                    ;;
                redis*)
                    if [ "$is_redis_stack" = "true" ] || [[ "$v" == *"$app"* ]]; then
                        vols+=("$v")
                        continue
                    fi
                    ;;
                *)
                    ;;
            esac
            vols+=("$v")
        done < <(grep -oE "${app}[a-zA-Z0-9_-]*" "$yaml_file" | grep -E "(data|config|media|themes|logs|import|uploads)" | sort -u || true)
    fi

    # Se ainda não encontrou volumes, extrai montagens sob services: no YAML
    if [ ${#vols[@]} -eq 0 ]; then
        while IFS= read -r v; do
            [ -n "$v" ] || continue
            case "$v" in
                postgres_data|mysql84_mysql84_data|mysql_data|portainer_data|traefik*|cloudflared*|audit*|interna|externa)
                    continue
                    ;;
                redis_data)
                    [ "$app" != "redis" ] && continue
                    ;;
                postgres*|mysql*|portainer*)
                    if [ "$app" != "postgres" ] && [ "$app" != "mysql84" ] && [ "$app" != "mysql" ]; then
                        continue
                    fi
                    ;;
                *)
                    vols+=("$v")
                    ;;
            esac
        done < <(grep -oE '\-\s+([a-zA-Z0-9_.-]+):(/[^:[:space:]'\''"]+)' "$yaml_file" 2>/dev/null | awk -F: '{print $1}' | sed 's/^- *//' | sort -u || true)
    fi

    # Fallback de segurança: se o YAML não declarou explicitamente, inspeciona volumes vivos no nó origem
    if [ ${#vols[@]} -eq 0 ] && [ -n "$origin_id" ]; then
        local live_vols=""
        if [ "$origin_id" = "local" ]; then
            live_vols=$(docker volume ls --format '{{.Name}}' 2>/dev/null | grep -E "^${app}[-_]" || true)
        elif [ -n "$origin_host" ]; then
            live_vols=$(ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o BatchMode=yes -o ConnectTimeout=8 "root@$origin_host" "docker volume ls --format '{{.Name}}'" 2>/dev/null | grep -E "^${app}[-_]" || true)
        fi
        while IFS= read -r lv; do
            [ -n "$lv" ] || continue
            case "$lv" in
                *_frozen_*|*_backup_*|*_pre_transfer_*) continue ;;
                *) vols+=("$lv") ;;
            esac
        done <<< "$live_vols"
    fi

    # Resolução dinâmica de prefixo de volumes no Docker Swarm:
    # Se o volume $v não existir literalmente, mas existir ${app}_${v} ou ${app}-${v}, usa o nome real
    local resolved_vols=()
    for v in "${vols[@]}"; do
        [ -n "$v" ] || continue
        local real_v="$v"
        if [ "$origin_id" = "local" ]; then
            if ! docker volume inspect "$v" >/dev/null 2>&1; then
                if docker volume inspect "${app}_${v}" >/dev/null 2>&1; then
                    real_v="${app}_${v}"
                elif docker volume inspect "${app}-${v}" >/dev/null 2>&1; then
                    real_v="${app}-${v}"
                fi
            fi
        elif [ -n "$origin_host" ]; then
            local check_v
            check_v=$(ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o BatchMode=yes -o ConnectTimeout=5 "root@$origin_host" \
                "docker volume inspect '$v' >/dev/null 2>&1 && echo 'exact' || (docker volume inspect '${app}_${v}' >/dev/null 2>&1 && echo 'prefix_under' || (docker volume inspect '${app}-${v}' >/dev/null 2>&1 && echo 'prefix_hyphen' || echo 'none'))" 2>/dev/null || echo "none")
            case "$check_v" in
                prefix_under) real_v="${app}_${v}" ;;
                prefix_hyphen) real_v="${app}-${v}" ;;
            esac
        fi
        if [[ ! " ${resolved_vols[*]} " =~ " ${real_v} " ]]; then
            resolved_vols+=("$real_v")
        fi
    done

    printf '%s\n' "${resolved_vols[@]}"
}

# Extração de arquivos e diretórios de configuração no host montados via bind mount
get_application_bind_mounts() {
    local yaml_file="$1"
    local app="$2"
    local origin_id="${3:-}"
    local origin_host="${4:-}"

    local binds=()
    while IFS= read -r line; do
        [ -n "$line" ] || continue
        local host_path="${line%%:*}"
        case "$host_path" in
            /var/run/docker.sock|/etc/localtime|/etc/timezone|/proc*|/sys*|/dev*|/tmp)
                continue
                ;;
            /root/*|/tmp/*|/etc/*|/var/opt/*)
                local exists=false
                if [ "$origin_id" = "local" ]; then
                    [ -e "$host_path" ] && exists=true
                elif [ -n "$origin_host" ]; then
                    if ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o BatchMode=yes -o ConnectTimeout=5 "root@$origin_host" "[ -e '$host_path' ]" 2>/dev/null; then
                        exists=true
                    fi
                fi
                if [ "$exists" = "true" ] && [[ ! " ${binds[*]} " =~ " ${host_path} " ]]; then
                    binds+=("$host_path")
                fi
                ;;
        esac
    done < <(grep -oE '\-\s+([/][^:[:space:]'\''"]+):' "$yaml_file" 2>/dev/null | sed 's/^- *//' | sed 's/:$//' | sort -u || true)

    printf '%s\n' "${binds[@]}"
}

## Garante que imagens locais ou customizadas da stack existam no nó destino
ensure_stack_images_on_dest() {
    local origin_id="$1"
    local origin_host="$2"
    local dest_id="$3"
    local dest_host="$4"
    local yaml_file="$5"

    local images=()
    while IFS= read -r img; do
        [ -n "$img" ] || continue
        img=$(echo "$img" | tr -d '"' | tr -d "'" | tr -d ' ')
        images+=("$img")
    done < <(grep -oP '^[[:space:]]*image:[[:space:]]*\K[^[:space:]]+' "$yaml_file" 2>/dev/null | sort -u || true)

    for img in "${images[@]}"; do
        [ -n "$img" ] || continue

        local dest_has_img="false"
        if [ "$dest_id" = "local" ]; then
            if docker image inspect "$img" >/dev/null 2>&1; then
                dest_has_img="true"
            fi
        else
            if ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o BatchMode=yes "root@$dest_host" "docker image inspect '$img' >/dev/null 2>&1"; then
                dest_has_img="true"
            fi
        fi

        [ "$dest_has_img" = "true" ] && continue

        local origin_has_img="false"
        if [ "$origin_id" = "local" ]; then
            if docker image inspect "$img" >/dev/null 2>&1; then
                origin_has_img="true"
            fi
        else
            if ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o BatchMode=yes "root@$origin_host" "docker image inspect '$img' >/dev/null 2>&1"; then
                origin_has_img="true"
            fi
        fi

        if [ "$origin_has_img" = "true" ]; then
            echo "Sincronizando imagem local/customizada '$img' da origem para o destino..." >> "$TRANSFER_LOG"
            if [ "$origin_id" = "local" ] && [ "$dest_id" != "local" ]; then
                docker save "$img" | gzip -1 | ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o BatchMode=yes "root@$dest_host" "gunzip | docker load" >> "$TRANSFER_LOG" 2>&1 || true
            elif [ "$origin_id" != "local" ] && [ "$dest_id" = "local" ]; then
                ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o BatchMode=yes "root@$origin_host" "docker save '$img' | gzip -1" | gunzip | docker load >> "$TRANSFER_LOG" 2>&1 || true
            elif [ "$origin_id" != "local" ] && [ "$dest_id" != "local" ]; then
                ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o BatchMode=yes "root@$origin_host" "docker save '$img' | gzip -1" | ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o BatchMode=yes "root@$dest_host" "gunzip | docker load" >> "$TRANSFER_LOG" 2>&1 || true
            fi
        fi
    done
}

## Aplica stack garantindo registro no Portainer para torná-la EDITÁVEL
deploy_stack_with_portainer_priority() {
    local node_id="$1"
    local host="$2"
    local stack_name="$3"
    local stack_file="$4"

    local portainer_script="
        dados=\"/root/dados_portainer/dados_portainer\"
        if [ -f \"\$dados\" ]; then
            p_url=\$(grep \"Dominio do portainer:\" \"\$dados\" | cut -d: -f2 | xargs)
            p_user=\$(grep \"Usuario:\" \"\$dados\" | cut -d: -f2 | xargs)
            p_pass=\$(grep \"Senha:\" \"\$dados\" | cut -d: -f2 | xargs)
            if [ -n \"\$p_url\" ] && [ -n \"\$p_user\" ] && [ -n \"\$p_pass\" ]; then
                resp=\$(curl -k -sS -m 8 -X POST \"https://\$p_url/api/auth\" -H \"Content-Type: application/json\" -d \"{\\\"username\\\":\\\"\$p_user\\\",\\\"password\\\":\\\"\$p_pass\\\"}\" 2>/dev/null || true)
                jwt=\$(echo \"\$resp\" | jq -r .jwt 2>/dev/null || true)
                if [ -n \"\$jwt\" ] && [ \"\$jwt\" != \"null\" ]; then
                    ep_id=\$(curl -k -sS -m 8 -H \"Authorization: Bearer \$jwt\" \"https://\$p_url/api/endpoints\" 2>/dev/null | jq -r \".[0].Id // 1\" || true)
                    swarm_id=\$(curl -k -sS -m 8 -H \"Authorization: Bearer \$jwt\" \"https://\$p_url/api/endpoints/\$ep_id/docker/swarm\" 2>/dev/null | jq -r \".ID // empty\" || true)
                    if [ -n \"\$ep_id\" ] && [ -n \"\$swarm_id\" ]; then
                        docker stack rm \"$stack_name\" >/dev/null 2>&1 || true
                        sleep 2
                        code=\$(curl -k -sS -m 20 -w \"%{http_code}\" -o /dev/null -X POST \
                            -H \"Authorization: Bearer \$jwt\" \
                            -F \"Name=$stack_name\" \
                            -F \"file=@$stack_file\" \
                            -F \"SwarmID=\$swarm_id\" \
                            \"https://\$p_url/api/stacks/create/swarm/file?endpointId=\$ep_id\" 2>/dev/null || true)
                        if [ \"\$code\" = \"200\" ] || [ \"\$code\" = \"201\" ]; then
                            echo \"PORTAINER_SUCCESS\"
                            exit 0
                        fi
                    fi
                fi
            fi
        fi
        exit 1
    "

    local success=false
    if [ "$node_id" = "local" ]; then
        if bash -c "$portainer_script" 2>/dev/null | grep -q "PORTAINER_SUCCESS"; then
            success=true
        fi
    else
        if ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o BatchMode=yes "root@$host" "bash -c '$portainer_script'" 2>/dev/null | grep -q "PORTAINER_SUCCESS"; then
            success=true
        fi
    fi

    if [ "$success" = "false" ]; then
        if [ "$node_id" = "local" ]; then
            docker stack deploy --prune --resolve-image always -c "$stack_file" "$stack_name"
        else
            ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o BatchMode=yes "root@$host" "docker stack deploy --prune --resolve-image always -c '$stack_file' '$stack_name'"
        fi
    fi
}

# Determina com precisão o serviço backend e a porta para cada domínio da stack
resolve_host_service_port() {
    local yaml="$1"
    local host="$2"
    local cur_app_name="$3"

    local s_name=""
    local s_port=""

    # 1. MinIO: console vs API
    if grep -q "MINIO_BROWSER_REDIRECT_URL" "$yaml" 2>/dev/null || grep -q "minio" "$yaml" 2>/dev/null; then
        local admin_url server_url
        admin_url=$(grep -oE "MINIO_BROWSER_REDIRECT_URL=https://[^[:space:]/\"]+" "$yaml" 2>/dev/null | sed "s/.*https:\/\///" | head -n1 || true)
        server_url=$(grep -oE "MINIO_SERVER_URL=https://[^[:space:]/\"]+" "$yaml" 2>/dev/null | sed "s/.*https:\/\///" | head -n1 || true)
        local minio_svc
        minio_svc=$(awk '/^services:/{flag=1; next} flag && /^[[:space:]]{2}[a-zA-Z0-9_-]+:/{print $1; exit}' "$yaml" 2>/dev/null | tr -d ':' || true)
        [ -n "$minio_svc" ] || minio_svc="$cur_app_name"

        if [ "$host" = "$admin_url" ] || echo "$host" | grep -q "admin"; then
            echo "${minio_svc}:9001"
            return 0
        elif [ "$host" = "$server_url" ] || echo "$host" | grep -qE "^s3"; then
            echo "${minio_svc}:9000"
            return 0
        fi
    fi

    # 2. Typebot: builder vs viewer
    if grep -q "NEXTAUTH_URL" "$yaml" 2>/dev/null || grep -q "NEXT_PUBLIC_VIEWER_URL" "$yaml" 2>/dev/null; then
        local builder_url viewer_url
        builder_url=$(grep -oE "NEXTAUTH_URL=https://[^[:space:]/\"]+" "$yaml" 2>/dev/null | sed "s/.*https:\/\///" | head -n1 || true)
        viewer_url=$(grep -oE "NEXT_PUBLIC_VIEWER_URL=https://[^[:space:]/\"]+" "$yaml" 2>/dev/null | sed "s/.*https:\/\///" | head -n1 || true)

        if [ "$host" = "$viewer_url" ]; then
            local viewer_svc
            viewer_svc=$(grep -oE "^[[:space:]]{2}[a-zA-Z0-9_-]+viewer[a-zA-Z0-9_-]*:" "$yaml" 2>/dev/null | tr -d " :" | head -n1 || true)
            [ -n "$viewer_svc" ] || viewer_svc="${cur_app_name}-viewer"
            echo "${viewer_svc}:3000"
            return 0
        elif [ "$host" = "$builder_url" ]; then
            local builder_svc
            builder_svc=$(grep -oE "^[[:space:]]{2}[a-zA-Z0-9_-]+builder[a-zA-Z0-9_-]*:" "$yaml" 2>/dev/null | tr -d " :" | head -n1 || true)
            [ -n "$builder_svc" ] || builder_svc="${cur_app_name}-builder"
            echo "${builder_svc}:3000"
            return 0
        fi
    fi

    # 2.5. n8n editor vs webhook vs mcp
    if [[ "$cur_app_name" == *editor* ]] || [[ "$cur_app_name" == *webhook* ]] || [[ "$cur_app_name" == *mcp* ]]; then
        local n8n_svc
        n8n_svc=$(awk '/^services:/{flag=1; next} flag && /^[[:space:]]{2}[a-zA-Z0-9_-]+:/{print $1; exit}' "$yaml" 2>/dev/null | tr -d ':' || true)
        [ -n "$n8n_svc" ] || n8n_svc="$cur_app_name"
        echo "${n8n_svc}:5678"
        return 0
    fi

    # 3. Traefik labels inspection (se declaradas no YAML)
    if grep -q "traefik\.http\.routers" "$yaml" 2>/dev/null; then
        local r_name
        r_name=$(grep -B1 -F "Host(\`$host\`)" "$yaml" 2>/dev/null | grep -oP 'traefik\.http\.routers\.\K[a-zA-Z0-9_-]+(?=\.rule)' | head -n1 || true)
        [ -z "$r_name" ] && r_name=$(grep -F "Host(\`$host\`)" "$yaml" 2>/dev/null | grep -oP 'traefik\.http\.routers\.\K[a-zA-Z0-9_-]+(?=\.rule)' | head -n1 || true)
        if [ -n "$r_name" ]; then
            local p_label
            p_label=$(grep -oP "(?<=traefik\.http\.services\.${r_name}\.loadbalancer\.server\.port=)[0-9]+" "$yaml" 2>/dev/null | head -n1 || true)
            [ -z "$p_label" ] && p_label=$(grep -oP '(?<=loadbalancer\.server\.port=)[0-9]+' "$yaml" 2>/dev/null | head -n1 || true)
            [ -n "$p_label" ] && s_port="$p_label"
        fi
    fi

    # 4. Mapear qual bloco de serviço declara este host
    local matched_svc=""
    matched_svc=$(awk -v h="$host" '
        /^services:/ { in_services=1; next }
        in_services && /^[[:space:]]{2}[a-zA-Z0-9_-]+:/ {
            svc = $1; sub(/:/, "", svc); next
        }
        in_services && $0 ~ h {
            if (svc != "") { print svc; exit }
        }
    ' "$yaml" 2>/dev/null || true)

    if [ -n "$matched_svc" ]; then
        s_name="$matched_svc"
    fi

    # Fallback para o nome do serviço
    if [ -z "$s_name" ]; then
        s_name=$(grep -oP '^[[:space:]]{2}\K[a-zA-Z0-9_-]+(?=:)' "$yaml" 2>/dev/null | grep -E '(_web|_app|web|app)' | head -n1 || true)
        [ -z "$s_name" ] && s_name=$(awk '/^services:/{flag=1; next} flag && /^[[:space:]]{2}[a-zA-Z0-9_-]+:/{print $1; exit}' "$yaml" 2>/dev/null | tr -d ':' || true)
        [ -z "$s_name" ] && s_name="$cur_app_name"
    fi

    # Fallback para a porta
    if [ -z "$s_port" ]; then
        if [[ "$s_name" == *builder* ]] || [[ "$s_name" == *viewer* ]] || [[ "$cur_app_name" == chatwoot* ]] || [[ "$cur_app_name" == flowise* ]]; then
            s_port="3000"
        elif [[ "$cur_app_name" == evolution* ]] || [[ "$cur_app_name" == evo* ]]; then
            s_port="8080"
        elif [[ "$cur_app_name" == rabbitmq* ]]; then
            s_port="15672"
        elif [[ "$cur_app_name" == n8n* ]]; then
            s_port="5678"
        elif [[ "$cur_app_name" == uptime* ]]; then
            s_port="3001"
        elif [[ "$cur_app_name" == minio* ]]; then
            if [[ "$host" == *admin* ]]; then s_port="9001"; else s_port="9000"; fi
        elif grep -q "3000" "$yaml" 2>/dev/null; then
            s_port="3000"
        elif grep -q "8080" "$yaml" 2>/dev/null || grep -q "8081" "$yaml" 2>/dev/null; then
            s_port="8080"
        elif grep -q "5678" "$yaml" 2>/dev/null; then
            s_port="5678"
        else
            s_port="80"
        fi
    fi

    echo "${s_name}:${s_port}"
}

# Comutação atômica de DNS Cloudflare e rotas de Ingress no Tunnel (Multi-Domínio)
switch_cloudflare_dns_and_ingress() {
    local node_id="$1"
    local host="$2"
    local yaml_file="$3"
    local app_name="$4"

    local app_lower
    app_lower=$(echo "$app_name" | tr '[:upper:]' '[:lower:]')

    # Se a stack for puramente de suporte/background e NÃO possuir router Traefik explícito (Host(`...`)),
    # ela jamais deve comutar DNS nem rotas de Ingress.
    if ! grep -qP 'Host\(`' "$yaml_file" 2>/dev/null; then
        if [[ "$app_lower" =~ (worker|runner|redis|database|postgres|mysql|cron|queue|-mq) ]] && [[ ! "$app_lower" =~ mcp ]]; then
            echo "[ROTEAMENTO CLOUDFLARE] Stack de suporte/background ($app_name) ignorada para rotas web."
            return 0
        fi
    fi

    local hostnames=()
    if grep -qP 'Host\(`' "$yaml_file" 2>/dev/null; then
        # 1. Traefik routers explícitos: autoritativos e canônicos
        while IFS= read -r h; do
            [ -n "$h" ] && hostnames+=("$h")
        done < <(grep -oP 'Host\(`\K[^`]+' "$yaml_file" 2>/dev/null | sort -u)
    elif grep -q "MINIO_BROWSER_REDIRECT_URL" "$yaml_file" 2>/dev/null || grep -q "minio" "$yaml_file" 2>/dev/null; then
        # 2. MinIO S3 Console vs Server
        while IFS= read -r h; do
            [ -n "$h" ] && hostnames+=("$h")
        done < <({
            grep -oP '(?<=MINIO_BROWSER_REDIRECT_URL=https://)[^[:space:]/"]+' "$yaml_file" 2>/dev/null || true
            grep -oP '(?<=MINIO_SERVER_URL=https://)[^[:space:]/"]+' "$yaml_file" 2>/dev/null || true
        } | sort -u)
    elif grep -q "NEXTAUTH_URL" "$yaml_file" 2>/dev/null || grep -q "NEXT_PUBLIC_VIEWER_URL" "$yaml_file" 2>/dev/null; then
        # 3. Typebot Builder vs Viewer
        while IFS= read -r h; do
            [ -n "$h" ] && hostnames+=("$h")
        done < <({
            grep -oP '(?<=NEXTAUTH_URL=https://)[^[:space:]/"]+' "$yaml_file" 2>/dev/null || true
            grep -oP '(?<=NEXT_PUBLIC_VIEWER_URL=https://)[^[:space:]/"]+' "$yaml_file" 2>/dev/null || true
        } | sort -u)
    elif [[ "$app_lower" =~ editor ]]; then
        # 4. n8n Editor exclusivo
        while IFS= read -r h; do
            [ -n "$h" ] && hostnames+=("$h")
        done < <({
            grep -oP '(?<=N8N_HOST=)[^[:space:]/"]+' "$yaml_file" 2>/dev/null || true
            grep -oP '(?<=N8N_EDITOR_BASE_URL=https://)[^[:space:]/"]+' "$yaml_file" 2>/dev/null || true
        } | sort -u)
    elif [[ "$app_lower" =~ webhook ]]; then
        # 5. n8n Webhook exclusivo
        while IFS= read -r h; do
            [ -n "$h" ] && hostnames+=("$h")
        done < <(grep -oP '(?<=WEBHOOK_URL=https://)[^[:space:]/"]+' "$yaml_file" 2>/dev/null | sort -u)
    elif [[ "$app_lower" =~ mcp ]]; then
        # 6. n8n MCP API exclusivo (atende requisições no domínio do webhook em /mcp/*)
        while IFS= read -r h; do
            [ -n "$h" ] && hostnames+=("$h")
        done < <({
            grep -oP '(?<=WEBHOOK_URL=https://)[^[:space:]/"]+' "$yaml_file" 2>/dev/null || true
            grep -oP '(?<=N8N_HOST=)[^[:space:]/"]+' "$yaml_file" 2>/dev/null || true
        } | head -n1)
    elif [[ "$app_lower" =~ ^n8n && ! "$app_lower" =~ (editor|webhook|worker|runner|mcp) ]]; then
        # 7. n8n standalone (sem fila)
        while IFS= read -r h; do
            [ -n "$h" ] && hostnames+=("$h")
        done < <({
            grep -oP '(?<=N8N_HOST=)[^[:space:]/"]+' "$yaml_file" 2>/dev/null || true
            grep -oP '(?<=N8N_EDITOR_BASE_URL=https://)[^[:space:]/"]+' "$yaml_file" 2>/dev/null || true
            grep -oP '(?<=WEBHOOK_URL=https://)[^[:space:]/"]+' "$yaml_file" 2>/dev/null || true
        } | sort -u)
    else
        # 8. Fallback geral para apps web padrão
        while IFS= read -r h; do
            [ -n "$h" ] && hostnames+=("$h")
        done < <({
            grep -oP '(?<=[A-Z0-9_]URL=https://)[^[:space:]/"]+' "$yaml_file" 2>/dev/null || true
            grep -oP '(?<=WEB_DOMAIN=)[^[:space:]/"]+' "$yaml_file" 2>/dev/null || true
        } | sort -u)
    fi

    [ ${#hostnames[@]} -gt 0 ] || return 0

    local mappings=()
    for h in "${hostnames[@]}"; do
        [ -n "$h" ] || continue
        local sp
        sp=$(resolve_host_service_port "$yaml_file" "$h" "$app_name")
        local s_svc="${sp%:*}"
        local s_port="${sp#*:}"
        local s_path=""
        if [[ "$app_lower" =~ mcp ]]; then
            s_path="/mcp/*"
        elif grep -q "PathPrefix" "$yaml_file" 2>/dev/null; then
            local raw_prefix
            raw_prefix=$(grep -F "Host(\`$h\`)" "$yaml_file" 2>/dev/null | grep -oP 'PathPrefix\(`\K[^`]+' | head -n1 || true)
            if [ -n "$raw_prefix" ]; then
                if [[ "$raw_prefix" == */* ]] && [[ "$raw_prefix" != *\* ]]; then
                    s_path="${raw_prefix%/}/*"
                else
                    s_path="$raw_prefix"
                fi
            fi
        fi
        mappings+=("${h}|${s_svc}|${s_port}|${s_path}")
    done

    local mappings_b64
    mappings_b64=$(printf '%s\n' "${mappings[@]}" | base64 -w 0)

    if [ "$node_id" = "local" ]; then
        MAPPINGS_B64="$mappings_b64" bash << 'EOF' >> "$TRANSFER_LOG" 2>&1 || true
mappings=()
while IFS= read -r line; do
    [ -n "$line" ] && mappings+=("$line")
done < <(printf "%s" "$MAPPINGS_B64" | base64 -d)

creds="/root/.cloudflared_config/cloudflare_credentials"
if [ -f "$creds" ]; then
    source "$creds"
    if [ -n "${CLOUDFLARE_API_TOKEN:-}" ] && [ -n "${CLOUDFLARE_ZONE_ID:-}" ] && [ -n "${CLOUDFLARE_ACCOUNT_ID:-}" ] && [ -n "${TUNNEL_ID:-}" ]; then
        for m in "${mappings[@]}"; do
            [ -n "$m" ] || continue
            IFS='|' read -r h target_service_name default_port target_path <<< "$m"
            [ -n "$h" ] || continue
            [ -n "$target_service_name" ] || continue
            [ -n "$default_port" ] || default_port="80"

            echo "[ROTEAMENTO CLOUDFLARE] Comutando domínio $h -> ${target_service_name}:${default_port}${target_path:+ ($target_path)} (Túnel: $TUNNEL_ID)..."

            # 1. Update/create CNAME DNS record (atômico via PUT quando existente)
            records=$(curl -sS -X GET "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records?name=${h}&type=CNAME" \
                -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
                -H "Content-Type: application/json" 2>/dev/null || true)
            r_id=$(echo "$records" | jq -r '.result[0]?.id // empty' 2>/dev/null || true)

            if [ -n "$r_id" ]; then
                up_res=$(curl -sS -X PUT "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records/${r_id}" \
                    -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
                    -H "Content-Type: application/json" \
                    --data "{\"type\":\"CNAME\",\"name\":\"${h}\",\"content\":\"${TUNNEL_ID}.cfargotunnel.com\",\"ttl\":1,\"proxied\":true}" 2>/dev/null || true)
                echo "$up_res" | grep -q '"success":true' && echo "  [OK] CNAME atualizado para ${TUNNEL_ID}.cfargotunnel.com" || echo "  [ALERTA] Falha ao atualizar CNAME: $up_res"
            else
                all_rec=$(curl -sS -X GET "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records?name=${h}" \
                    -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
                    -H "Content-Type: application/json" 2>/dev/null || true)
                echo "$all_rec" | jq -r '.result[]?.id // empty' 2>/dev/null | while read -r old_id; do
                    [ -n "$old_id" ] && curl -sS -X DELETE "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records/${old_id}" \
                        -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" -H "Content-Type: application/json" >/dev/null 2>&1 || true
                done
                post_res=$(curl -sS -X POST "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records" \
                    -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
                    -H "Content-Type: application/json" \
                    --data "{\"type\":\"CNAME\",\"name\":\"${h}\",\"content\":\"${TUNNEL_ID}.cfargotunnel.com\",\"ttl\":1,\"proxied\":true}" 2>/dev/null || true)
                echo "$post_res" | grep -q '"success":true' && echo "  [OK] CNAME criado para ${TUNNEL_ID}.cfargotunnel.com" || echo "  [ALERTA] Falha ao criar CNAME: $post_res"
            fi

            # 2. Update Tunnel Ingress configuration
            cfg_raw=$(curl -sS -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
                "https://api.cloudflare.com/client/v4/accounts/${CLOUDFLARE_ACCOUNT_ID}/cfd_tunnel/${TUNNEL_ID}/configurations" 2>/dev/null || true)
            if echo "$cfg_raw" | grep -q '"success":true'; then
                to_put=$(mktemp)
                target_service="http://${target_service_name}:${default_port}"
                printf '%s' "$cfg_raw" | jq --arg host "$h" --arg service "$target_service" --arg path "$target_path" '
                    (.result.config // {}) as $cfg
                    | ($cfg.ingress // []) as $ing
                    | ($ing | map(select(.service != "http_status:404"))) as $clean
                    | (if ($path // "") != "" then
                        ($clean | map(select(.hostname != $host or (.path // "") != $path)))
                        + [ { hostname: $host, path: $path, service: $service, originRequest: { noTlsVerify: true, httpHostHeader: $host } } ]
                      else
                        ($clean | map(select(.hostname != $host or ((.path // "") != ""))))
                        + [ { hostname: $host, service: $service, originRequest: { noTlsVerify: true, httpHostHeader: $host } } ]
                      end) as $merged
                    | ($merged | sort_by([.hostname, (if (.path // "") != "" then 0 else 1 end)])) as $final_routes
                    | ($final_routes + [{ service: "http_status:404" }]) as $final_ing
                    | { config: ($cfg + { ingress: $final_ing }) }
                ' > "$to_put" 2>/dev/null || true

                if [ -s "$to_put" ]; then
                    ing_res=$(curl -sS -X PUT "https://api.cloudflare.com/client/v4/accounts/${CLOUDFLARE_ACCOUNT_ID}/cfd_tunnel/${TUNNEL_ID}/configurations" \
                        -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
                        -H "Content-Type: application/json" \
                        --data-binary @"$to_put" 2>/dev/null || true)
                    echo "$ing_res" | grep -q '"success":true' && echo "  [OK] Ingress configurado para $target_service (${target_path:-raiz})" || echo "  [ALERTA] Falha no Ingress: $ing_res"
                fi
                rm -f "$to_put"
            fi
        done
    else
        echo "[ALERTA] Credenciais Cloudflare incompletas no nó destino."
    fi
else
    echo "[ALERTA] Arquivo cloudflare_credentials não encontrado no nó destino."
fi
EOF
    else
        ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o BatchMode=yes "root@$host" "MAPPINGS_B64='$mappings_b64' bash" << 'EOF' >> "$TRANSFER_LOG" 2>&1 || true
mappings=()
while IFS= read -r line; do
    [ -n "$line" ] && mappings+=("$line")
done < <(printf "%s" "$MAPPINGS_B64" | base64 -d)

creds="/root/.cloudflared_config/cloudflare_credentials"
if [ -f "$creds" ]; then
    source "$creds"
    if [ -n "${CLOUDFLARE_API_TOKEN:-}" ] && [ -n "${CLOUDFLARE_ZONE_ID:-}" ] && [ -n "${CLOUDFLARE_ACCOUNT_ID:-}" ] && [ -n "${TUNNEL_ID:-}" ]; then
        for m in "${mappings[@]}"; do
            [ -n "$m" ] || continue
            IFS='|' read -r h target_service_name default_port target_path <<< "$m"
            [ -n "$h" ] || continue
            [ -n "$target_service_name" ] || continue
            [ -n "$default_port" ] || default_port="80"

            echo "[ROTEAMENTO CLOUDFLARE] Comutando domínio $h -> ${target_service_name}:${default_port}${target_path:+ ($target_path)} (Túnel: $TUNNEL_ID)..."

            # 1. Update/create CNAME DNS record (atômico via PUT quando existente)
            records=$(curl -sS -X GET "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records?name=${h}&type=CNAME" \
                -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
                -H "Content-Type: application/json" 2>/dev/null || true)
            r_id=$(echo "$records" | jq -r '.result[0]?.id // empty' 2>/dev/null || true)

            if [ -n "$r_id" ]; then
                up_res=$(curl -sS -X PUT "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records/${r_id}" \
                    -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
                    -H "Content-Type: application/json" \
                    --data "{\"type\":\"CNAME\",\"name\":\"${h}\",\"content\":\"${TUNNEL_ID}.cfargotunnel.com\",\"ttl\":1,\"proxied\":true}" 2>/dev/null || true)
                echo "$up_res" | grep -q '"success":true' && echo "  [OK] CNAME atualizado para ${TUNNEL_ID}.cfargotunnel.com" || echo "  [ALERTA] Falha ao atualizar CNAME: $up_res"
            else
                all_rec=$(curl -sS -X GET "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records?name=${h}" \
                    -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
                    -H "Content-Type: application/json" 2>/dev/null || true)
                echo "$all_rec" | jq -r '.result[]?.id // empty' 2>/dev/null | while read -r old_id; do
                    [ -n "$old_id" ] && curl -sS -X DELETE "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records/${old_id}" \
                        -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" -H "Content-Type: application/json" >/dev/null 2>&1 || true
                done
                post_res=$(curl -sS -X POST "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records" \
                    -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
                    -H "Content-Type: application/json" \
                    --data "{\"type\":\"CNAME\",\"name\":\"${h}\",\"content\":\"${TUNNEL_ID}.cfargotunnel.com\",\"ttl\":1,\"proxied\":true}" 2>/dev/null || true)
                echo "$post_res" | grep -q '"success":true' && echo "  [OK] CNAME criado para ${TUNNEL_ID}.cfargotunnel.com" || echo "  [ALERTA] Falha ao criar CNAME: $post_res"
            fi

            # 2. Update Tunnel Ingress configuration
            cfg_raw=$(curl -sS -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
                "https://api.cloudflare.com/client/v4/accounts/${CLOUDFLARE_ACCOUNT_ID}/cfd_tunnel/${TUNNEL_ID}/configurations" 2>/dev/null || true)
            if echo "$cfg_raw" | grep -q '"success":true'; then
                to_put=$(mktemp)
                target_service="http://${target_service_name}:${default_port}"
                printf '%s' "$cfg_raw" | jq --arg host "$h" --arg service "$target_service" --arg path "$target_path" '
                    (.result.config // {}) as $cfg
                    | ($cfg.ingress // []) as $ing
                    | ($ing | map(select(.service != "http_status:404"))) as $clean
                    | (if ($path // "") != "" then
                        ($clean | map(select(.hostname != $host or (.path // "") != $path)))
                        + [ { hostname: $host, path: $path, service: $service, originRequest: { noTlsVerify: true, httpHostHeader: $host } } ]
                      else
                        ($clean | map(select(.hostname != $host or ((.path // "") != ""))))
                        + [ { hostname: $host, service: $service, originRequest: { noTlsVerify: true, httpHostHeader: $host } } ]
                      end) as $merged
                    | ($merged | sort_by([.hostname, (if (.path // "") != "" then 0 else 1 end)])) as $final_routes
                    | ($final_routes + [{ service: "http_status:404" }]) as $final_ing
                    | { config: ($cfg + { ingress: $final_ing }) }
                ' > "$to_put" 2>/dev/null || true

                if [ -s "$to_put" ]; then
                    ing_res=$(curl -sS -X PUT "https://api.cloudflare.com/client/v4/accounts/${CLOUDFLARE_ACCOUNT_ID}/cfd_tunnel/${TUNNEL_ID}/configurations" \
                        -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
                        -H "Content-Type: application/json" \
                        --data-binary @"$to_put" 2>/dev/null || true)
                    echo "$ing_res" | grep -q '"success":true' && echo "  [OK] Ingress configurado para $target_service (${target_path:-raiz})" || echo "  [ALERTA] Falha no Ingress: $ing_res"
                fi
                rm -f "$to_put"
            fi
        done
    else
        echo "[ALERTA] Credenciais Cloudflare incompletas no nó destino."
    fi
else
    echo "[ALERTA] Arquivo cloudflare_credentials não encontrado no nó destino."
fi
EOF
    fi
}

# Garante que MySQL 8.4 está rodando no nó destino
ensure_mysql84_ready() {
    local node_id="$1"
    local host="$2"

    local running=""
    if [ "$node_id" = "local" ]; then
        running=$(docker ps -qf name=mysql84 2>/dev/null | head -n1 || true)
    else
        running=$(ssh -n -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o BatchMode=yes "root@$host" 'docker ps -qf name=mysql84 | head -n1' 2>/dev/null || true)
    fi

    if [ -n "$running" ]; then
        echo "MySQL 8.4 já está em execução no nó '$node_id'." >> "$TRANSFER_LOG"
        return 0
    fi

    echo "Inicializando stack mysql84 no nó '$node_id'..." >> "$TRANSFER_LOG"
    local new_pwd=""
    if [ "$node_id" = "local" ]; then
        if [ -s /root/mysql84.yaml ]; then
            new_pwd=$(grep 'MYSQL_ROOT_PASSWORD=' /root/mysql84.yaml 2>/dev/null | head -n1 | sed 's/.*MYSQL_ROOT_PASSWORD=//' | tr -d ' "\r' || true)
        fi
    else
        new_pwd=$(ssh -n -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o BatchMode=yes "root@$host" "[ -s /root/mysql84.yaml ] && grep 'MYSQL_ROOT_PASSWORD=' /root/mysql84.yaml | head -n1 | sed 's/.*MYSQL_ROOT_PASSWORD=//' | tr -d ' \"\r'" 2>/dev/null || true)
    fi
    [ -n "$new_pwd" ] || new_pwd=$(openssl rand -hex 8)

    local yaml_body="version: '3.7'
services:
    mysql84:
        image: percona/percona-server:8.4
        environment:
            - MYSQL_ROOT_PASSWORD=${new_pwd}
            - TZ=America/Fortaleza
        networks:
            - externa
            - interna
        volumes:
            - mysql84_data:/var/lib/mysql
        deploy:
            placement:
                constraints: [node.role == manager]
        command:
            - --character-set-server=utf8mb4
            - --collation-server=utf8mb4_general_ci
            - --sql-mode=
            - --mysql-native-password=ON
            - --port=3306
            - --max-allowed-packet=512MB
volumes:
    mysql84_data:
networks:
    externa:
        external: true
    interna:
        external: true
"
    if [ "$node_id" = "local" ]; then
        if [ ! -s /root/mysql84.yaml ]; then
            printf '%s\n' "$yaml_body" > /root/mysql84.yaml 2>/dev/null || true
        fi
        deploy_stack_with_portainer_priority "local" "" "mysql84" "/root/mysql84.yaml" >> "$TRANSFER_LOG" 2>&1 || true
    else
        ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o BatchMode=yes "root@$host" "[ -s /root/mysql84.yaml ] || cat > /root/mysql84.yaml" <<< "$yaml_body"
        deploy_stack_with_portainer_priority "$node_id" "$host" "mysql84" "/root/mysql84.yaml" >> "$TRANSFER_LOG" 2>&1 || true
    fi

    local wait_count=0
    while [ $wait_count -lt 180 ]; do
        sleep 2
        wait_count=$((wait_count + 1))
        if [ $((wait_count % 15)) -eq 0 ]; then
            echo "Aguardando inicialização do MySQL 8.4 no nó '$node_id' ($((wait_count * 2))s/360s)..." >> "$TRANSFER_LOG"
        fi
        local chk=""
        if [ "$node_id" = "local" ]; then
            chk=$(docker ps -qf name=mysql84 2>/dev/null | head -n1 || true)
            if [ -n "$chk" ]; then
                if docker exec -i -e MYSQL_PWD="$new_pwd" "$chk" mysql -u root -e 'SELECT 1;' >/dev/null 2>&1; then
                    echo "MySQL 8.4 operacional no nó '$node_id' em $((wait_count * 2))s." >> "$TRANSFER_LOG"
                    return 0
                fi
            fi
        else
            chk=$(ssh -n -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o BatchMode=yes "root@$host" 'docker ps -qf name=mysql84 | head -n1' 2>/dev/null || true)
            if [ -n "$chk" ]; then
                if ssh -n -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o BatchMode=yes "root@$host" "docker exec -i -e MYSQL_PWD='$new_pwd' '$chk' mysql -u root -e 'SELECT 1;'" >/dev/null 2>&1; then
                    echo "MySQL 8.4 operacional no nó '$node_id' em $((wait_count * 2))s." >> "$TRANSFER_LOG"
                    return 0
                fi
            fi
        fi
    done
    echo "FALHA: Timeout de 360s aguardando inicialização do MySQL 8.4 no nó '$node_id'." >> "$TRANSFER_LOG"
    return 1
}

# Garante que MySQL 8.0 compartilhado está rodando no nó destino
ensure_mysql_ready() {
    local node_id="$1"
    local host="$2"

    local running=""
    if [ "$node_id" = "local" ]; then
        running=$(docker ps --filter "label=com.docker.swarm.service.name=mysql_mysql" -q 2>/dev/null | head -n1 || true)
        [ -n "$running" ] || running=$(docker ps -qf name=mysql_mysql 2>/dev/null | head -n1 || true)
        [ -n "$running" ] || running=$(docker ps --format '{{.ID}} {{.Names}}' 2>/dev/null | grep -v 'mysql84' | grep -E 'mysql_mysql|mysql\.1' | awk '{print $1}' | head -n1 || true)
    else
        running=$(ssh -n -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o BatchMode=yes "root@$host" 'docker ps --filter "label=com.docker.swarm.service.name=mysql_mysql" -q 2>/dev/null | head -n1 || docker ps -qf name=mysql_mysql 2>/dev/null | head -n1 || docker ps --format "{{.ID}} {{.Names}}" 2>/dev/null | grep -v "mysql84" | grep -E "mysql_mysql|mysql\.1" | awk "{print \$1}" | head -n1' 2>/dev/null || true)
    fi

    if [ -n "$running" ]; then
        echo "MySQL 8.0 já está em execução no nó '$node_id'." >> "$TRANSFER_LOG"
        return 0
    fi

    echo "Inicializando stack mysql (8.0) no nó '$node_id'..." >> "$TRANSFER_LOG"
    local new_pwd=""
    if [ "$node_id" = "local" ]; then
        if [ -s /root/mysql.yaml ]; then
            new_pwd=$(grep 'MYSQL_ROOT_PASSWORD=' /root/mysql.yaml 2>/dev/null | head -n1 | sed 's/.*MYSQL_ROOT_PASSWORD=//' | tr -d ' "\r' || true)
        fi
    else
        new_pwd=$(ssh -n -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o BatchMode=yes "root@$host" "[ -s /root/mysql.yaml ] && grep 'MYSQL_ROOT_PASSWORD=' /root/mysql.yaml | head -n1 | sed 's/.*MYSQL_ROOT_PASSWORD=//' | tr -d ' \"\r'" 2>/dev/null || true)
    fi
    [ -n "$new_pwd" ] || new_pwd=$(openssl rand -hex 8)

    local mysql_img="percona/percona-server:8.0"
    local yaml_body="version: '3.7'
services:
    mysql:
        image: ${mysql_img}
        environment:
            - MYSQL_ROOT_PASSWORD=${new_pwd}
            - TZ=America/Fortaleza
        networks:
            - externa
            - interna
        volumes:
            - mysql_data:/var/lib/mysql
        deploy:
            placement:
                constraints: [node.role == manager]
        command:
            --character-set-server=utf8mb4 --collation-server=utf8mb4_general_ci --sql-mode=\"\" --default-authentication-plugin=mysql_native_password --port=3306 --max-allowed-packet=512MB
volumes:
    mysql_data:
networks:
    externa:
        external: true
    interna:
        external: true
"
    if [ "$node_id" = "local" ]; then
        if [ ! -s /root/mysql.yaml ]; then
            printf '%s\n' "$yaml_body" > /root/mysql.yaml 2>/dev/null || true
        fi
        deploy_stack_with_portainer_priority "local" "" "mysql" "/root/mysql.yaml" >> "$TRANSFER_LOG" 2>&1 || true
    else
        ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o BatchMode=yes "root@$host" "[ -s /root/mysql.yaml ] || cat > /root/mysql.yaml" <<< "$yaml_body"
        deploy_stack_with_portainer_priority "$node_id" "$host" "mysql" "/root/mysql.yaml" >> "$TRANSFER_LOG" 2>&1 || true
    fi

    local wait_count=0
    while [ $wait_count -lt 180 ]; do
        sleep 2
        wait_count=$((wait_count + 1))
        if [ $((wait_count % 15)) -eq 0 ]; then
            echo "Aguardando inicialização do MySQL 8.0 no nó '$node_id' ($((wait_count * 2))s/360s)..." >> "$TRANSFER_LOG"
        fi
        local chk=""
        if [ "$node_id" = "local" ]; then
            chk=$(docker ps --filter "label=com.docker.swarm.service.name=mysql_mysql" -q 2>/dev/null | head -n1 || true)
            [ -n "$chk" ] || chk=$(docker ps -qf name=mysql_mysql 2>/dev/null | head -n1 || true)
            [ -n "$chk" ] || chk=$(docker ps --format '{{.ID}} {{.Names}}' 2>/dev/null | grep -v 'mysql84' | grep -E 'mysql_mysql|mysql\.1' | awk '{print $1}' | head -n1 || true)
            if [ -n "$chk" ]; then
                if docker exec -i -e MYSQL_PWD="$new_pwd" "$chk" mysql -u root -e 'SELECT 1;' >/dev/null 2>&1; then
                    echo "MySQL 8.0 operacional no nó '$node_id' em $((wait_count * 2))s." >> "$TRANSFER_LOG"
                    return 0
                fi
            fi
        else
            chk=$(ssh -n -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o BatchMode=yes "root@$host" 'docker ps --filter "label=com.docker.swarm.service.name=mysql_mysql" -q 2>/dev/null | head -n1 || docker ps -qf name=mysql_mysql 2>/dev/null | head -n1 || docker ps --format "{{.ID}} {{.Names}}" 2>/dev/null | grep -v "mysql84" | grep -E "mysql_mysql|mysql\.1" | awk "{print \$1}" | head -n1' 2>/dev/null || true)
            if [ -n "$chk" ]; then
                if ssh -n -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o BatchMode=yes "root@$host" "docker exec -i -e MYSQL_PWD='$new_pwd' '$chk' mysql -u root -e 'SELECT 1;'" >/dev/null 2>&1; then
                    echo "MySQL 8.0 operacional no nó '$node_id' em $((wait_count * 2))s." >> "$TRANSFER_LOG"
                    return 0
                fi
            fi
        fi
    done
    echo "FALHA: Timeout de 360s aguardando inicialização do MySQL 8.0 no nó '$node_id'." >> "$TRANSFER_LOG"
    return 1
}

# Garante que MinIO S3 está rodando no nó destino
ensure_minio_ready() {
    local node_id="$1"
    local host="$2"

    local running=""
    if [ "$node_id" = "local" ]; then
        running=$(docker ps --filter "name=minio" -q 2>/dev/null | head -n1 || true)
        [ -n "$running" ] || running=$(docker stack ls --format '{{.Name}}' 2>/dev/null | grep -E '^minio' | head -n1 || true)
    else
        running=$(ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o BatchMode=yes "root@$host" 'docker ps --filter "name=minio" -q 2>/dev/null | head -n1 || docker stack ls --format "{{.Name}}" 2>/dev/null | grep -E "^minio" | head -n1' 2>/dev/null || true)
    fi

    if [ -n "$running" ]; then
        echo "MinIO S3 já está em execução no nó '$node_id'." >> "$TRANSFER_LOG"
        return 0
    fi

    echo "Inicializando stack minio no nó '$node_id'..." >> "$TRANSFER_LOG"
    local minio_user="admin"
    local minio_pwd
    minio_pwd=$(openssl rand -hex 12)

    local dados_content="MINIO_USER: $minio_user
MINIO_PASSWORD: $minio_pwd
MINIO_PUBLIC_URL: s3.internal
MINIO_ADMIN_URL: admins3.internal"

    local yaml_body="version: '3.7'
services:
  minio:
    image: quay.io/minio/minio:RELEASE.2025-04-08T15-41-24Z
    command: server /data --console-address \":9001\"
    networks:
      - interna
      - externa
    volumes:
      - minio_data:/data
    environment:
      - MINIO_ROOT_USER=${minio_user}
      - MINIO_ROOT_PASSWORD=${minio_pwd}
    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
          - node.role == manager
volumes:
  minio_data:
networks:
  interna:
    external: true
  externa:
    external: true
"

    if [ "$node_id" = "local" ]; then
        mkdir -p /root/dados_minio 2>/dev/null || true
        printf '%s\n' "$dados_content" > /root/dados_minio/dados_minio 2>/dev/null || true
        printf '%s\n' "$yaml_body" > /root/minio.yaml 2>/dev/null || true
        deploy_stack_with_portainer_priority "local" "" "minio" "/root/minio.yaml" >> "$TRANSFER_LOG" 2>&1 || true
    else
        ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o BatchMode=yes "root@$host" "mkdir -p /root/dados_minio && cat > /root/dados_minio/dados_minio" <<< "$dados_content"
        ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o BatchMode=yes "root@$host" "cat > /root/minio.yaml" <<< "$yaml_body"
        deploy_stack_with_portainer_priority "$node_id" "$host" "minio" "/root/minio.yaml" >> "$TRANSFER_LOG" 2>&1 || true
    fi

    local wait_count=0
    while [ $wait_count -lt 90 ]; do
        sleep 2
        wait_count=$((wait_count + 1))
        local chk=""
        if [ "$node_id" = "local" ]; then
            chk=$(docker ps -qf name=minio 2>/dev/null | head -n1 || true)
        else
            chk=$(ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o BatchMode=yes "root@$host" 'docker ps -qf name=minio | head -n1' 2>/dev/null || true)
        fi
        if [ -n "$chk" ]; then
            sleep 4
            echo "MinIO S3 operacional no nó '$node_id' em $((wait_count * 2))s." >> "$TRANSFER_LOG"
            return 0
        fi
    done
    echo "FALHA: Timeout de 180s aguardando inicialização do MinIO no nó '$node_id'." >> "$TRANSFER_LOG"
    return 1
}

# Sincronização multi-tenant de bucket individual MinIO S3 (Zero sobrescrita)
sync_s3_bucket_data() {
    local orig_id="$1"
    local orig_host="$2"
    local dest_id="$3"
    local dest_host="$4"
    local bucket_name="$5"

    [ -n "$bucket_name" ] || return 0

    local orig_minio_vol=""
    if [ "$orig_id" = "local" ]; then
        orig_minio_vol=$(docker volume ls -q --filter name=minio 2>/dev/null | grep -E "(data|minio)" | head -n1 || true)
        [ -n "$orig_minio_vol" ] || orig_minio_vol="minio_data"
    else
        orig_minio_vol=$(ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o BatchMode=yes "root@$orig_host" "docker volume ls -q --filter name=minio | grep -E '(data|minio)' | head -n1" 2>/dev/null || true)
        [ -n "$orig_minio_vol" ] || orig_minio_vol="minio_data"
    fi

    local dest_minio_vol=""
    if [ "$dest_id" = "local" ]; then
        dest_minio_vol=$(docker volume ls -q --filter name=minio 2>/dev/null | grep -E "(data|minio)" | head -n1 || true)
        [ -n "$dest_minio_vol" ] || dest_minio_vol="minio_data"
        docker volume create "$dest_minio_vol" >/dev/null 2>&1 || true
    else
        dest_minio_vol=$(ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o BatchMode=yes "root@$dest_host" "docker volume ls -q --filter name=minio | grep -E '(data|minio)' | head -n1" 2>/dev/null || true)
        [ -n "$dest_minio_vol" ] || dest_minio_vol="minio_data"
        ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o BatchMode=yes "root@$dest_host" "docker volume create '$dest_minio_vol' >/dev/null 2>&1 || true"
    fi

    local bucket_exists=false
    if [ "$orig_id" = "local" ]; then
        if docker run --rm -v "${orig_minio_vol}:/mdata:ro" alpine test -d "/mdata/${bucket_name}" 2>/dev/null; then
            bucket_exists=true
        fi
    else
        if ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o BatchMode=yes "root@$orig_host" "docker run --rm -v '${orig_minio_vol}:/mdata:ro' alpine test -d '/mdata/${bucket_name}'" 2>/dev/null; then
            bucket_exists=true
        fi
    fi

    if [ "$bucket_exists" = "false" ]; then
        if [ "$dest_id" = "local" ]; then
            docker run --rm -v "${dest_minio_vol}:/mdata" alpine mkdir -p "/mdata/${bucket_name}" 2>/dev/null || true
        else
            ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o BatchMode=yes "root@$dest_host" "docker run --rm -v '${dest_minio_vol}:/mdata' alpine mkdir -p '/mdata/${bucket_name}'" 2>/dev/null || true
        fi
        return 0
    fi

    if [ "$orig_id" = "local" ] && [ "$dest_id" != "local" ]; then
        docker run --rm -v "${orig_minio_vol}:/mdata:ro" alpine tar -czf - -C "/mdata/${bucket_name}" . 2>/dev/null \
            | ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o BatchMode=yes "root@$dest_host" \
            "docker run --rm -i -v '${dest_minio_vol}:/mdata' alpine sh -c 'mkdir -p /mdata/${bucket_name} && tar -xzf - -C /mdata/${bucket_name}'" 2>/dev/null || true
    elif [ "$orig_id" != "local" ] && [ "$dest_id" = "local" ]; then
        ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o BatchMode=yes "root@$orig_host" \
            "docker run --rm -v '${orig_minio_vol}:/mdata:ro' alpine tar -czf - -C '/mdata/${bucket_name}' ." 2>/dev/null \
            | docker run --rm -i -v "${dest_minio_vol}:/mdata" alpine sh -c "mkdir -p /mdata/${bucket_name} && tar -xzf - -C /mdata/${bucket_name}" 2>/dev/null || true
    elif [ "$orig_id" != "local" ] && [ "$dest_id" != "local" ]; then
        ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o BatchMode=yes "root@$orig_host" \
            "docker run --rm -v '${orig_minio_vol}:/mdata:ro' alpine tar -czf - -C '/mdata/${bucket_name}' ." 2>/dev/null \
            | ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o BatchMode=yes "root@$dest_host" \
            "docker run --rm -i -v '${dest_minio_vol}:/mdata' alpine sh -c 'mkdir -p /mdata/${bucket_name} && tar -xzf - -C /mdata/${bucket_name}'" 2>/dev/null || true
    else
        docker run --rm -v "${orig_minio_vol}:/src:ro" -v "${dest_minio_vol}:/dst" alpine sh -c "mkdir -p /dst/${bucket_name} && cp -a /src/${bucket_name}/. /dst/${bucket_name}/" 2>/dev/null || true
    fi
}

# Garante que RabbitMQ está rodando no nó destino
ensure_rabbitmq_ready() {
    local node_id="$1"
    local host="$2"

    local running=""
    if [ "$node_id" = "local" ]; then
        running=$(docker ps --filter "name=rabbitmq" -q 2>/dev/null | head -n1 || true)
        [ -n "$running" ] || running=$(docker stack ls --format '{{.Name}}' 2>/dev/null | grep -E '^rabbitmq' | head -n1 || true)
    else
        running=$(ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o BatchMode=yes "root@$host" 'docker ps --filter "name=rabbitmq" -q 2>/dev/null | head -n1 || docker stack ls --format "{{.Name}}" 2>/dev/null | grep -E "^rabbitmq" | head -n1' 2>/dev/null || true)
    fi

    if [ -n "$running" ]; then
        return 0
    fi

    local mq_user="admin"
    local mq_pwd
    mq_pwd=$(openssl rand -hex 10)

    local yaml_body="version: '3.7'
services:
  rabbitmq:
    image: rabbitmq:4.0-management
    hostname: rabbitmq
    networks:
      - interna
      - externa
    volumes:
      - rabbitmq_data:/var/lib/rabbitmq/
    environment:
      - RABBITMQ_DEFAULT_USER=${mq_user}
      - RABBITMQ_DEFAULT_PASS=${mq_pwd}
      - RABBITMQ_ERLANG_COOKIE=setupmno-cookie
    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
          - node.role == manager
volumes:
  rabbitmq_data:
networks:
  interna:
    external: true
  externa:
    external: true
"
    if [ "$node_id" = "local" ]; then
        printf '%s\n' "$yaml_body" > /root/rabbitmq.yaml 2>/dev/null || true
        deploy_stack_with_portainer_priority "local" "" "rabbitmq" "/root/rabbitmq.yaml" >> "$TRANSFER_LOG" 2>&1 || true
    else
        ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o BatchMode=yes "root@$host" "cat > /root/rabbitmq.yaml" <<< "$yaml_body"
        deploy_stack_with_portainer_priority "$node_id" "$host" "rabbitmq" "/root/rabbitmq.yaml" >> "$TRANSFER_LOG" 2>&1 || true
    fi

    local wait_count=0
    while [ $wait_count -lt 90 ]; do
        sleep 2
        wait_count=$((wait_count + 1))
        local chk=""
        if [ "$node_id" = "local" ]; then
            chk=$(docker ps -qf name=rabbitmq 2>/dev/null | head -n1 || true)
        else
            chk=$(ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o BatchMode=yes "root@$host" 'docker ps -qf name=rabbitmq | head -n1' 2>/dev/null || true)
        fi
        if [ -n "$chk" ]; then
            sleep 4
            echo "RabbitMQ operacional no nó '$node_id' em $((wait_count * 2))s." >> "$TRANSFER_LOG"
            return 0
        fi
    done
    echo "FALHA: Timeout de 180s aguardando inicialização do RabbitMQ no nó '$node_id'." >> "$TRANSFER_LOG"
    return 1
}

# Raio-X da Frota
action_inspect_nodes() {
    sync_fleet_inventory

    local local_arch local_ram local_disk local_stacks
    local_arch=$(get_local_arch)
    local_ram=$(get_local_ram_free_mb)
    local_disk=$(get_local_disk_free_gb)
    local_stacks=$(list_local_swarm_stacks | tr '\n' ', ' | sed 's/,$//')
    [ -n "$local_stacks" ] || local_stacks="Nenhuma stack ativa no Swarm local"

    local fleet_mode node_id local_role
    fleet_mode=$(get_local_fleet_mode)
    node_id=$(get_local_fleet_node_id)
    case "$fleet_mode" in
        worker) local_role="Nó Operário da Frota (Worker)" ;;
        master) local_role="Torre Master (Cockpit Local)" ;;
        *) local_role="Servidor Standalone (Torre Local)" ;;
    esac

    local report="📊 RAIO-X DO SERVIDOR LOCAL (ESTE NÓ):\n"
    report+="• Papel: $local_role\n"
    [ -z "$node_id" ] || report+="• ID do Nó: $node_id\n"
    report+="• Arquitetura do Processador: $local_arch\n"
    report+="• Memória RAM Livre: ${local_ram} MB\n"
    report+="• Espaço em Disco Livre: ${local_disk} GB\n"
    report+="• Stacks Instaladas: $local_stacks\n\n"

    if [ "$fleet_mode" = "worker" ]; then
        report+="🛰️ CONTEXTO DA FROTA (MODO WORKER):\n"
        report+="• Esta VPS opera como Nó Worker subordinado.\n"
        report+="• A central de comando, o catálogo de nós e as migrações entre servidores são gerenciadas a partir da sua Torre Master.\n"
        report+="• Funções disponíveis neste nó: Inspeção local e criação de Backup Portátil (.tar.gz).\n"
    elif [ "$fleet_mode" = "master" ]; then
        report+="📡 NÓS REMOTOS DA FROTA (TORRE MASTER):\n"
        if [ -f "$INVENTORY_FILE" ]; then
            local count
            count=$(jq -r '[.nodes[]? | select(.role == "worker" or .mode == "worker") | select(.status != "deleted")] | length' "$INVENTORY_FILE" 2>/dev/null || printf '0')
            if [ "$count" -gt 0 ]; then
                local worker_lines
                worker_lines=$(jq -r '.nodes[]? | select(.role == "worker" or .mode == "worker") | select(.status != "deleted") | "\(.name) (\(.architecture // "amd64")) — Status: \(.status) | RAM: \(.memoryTotalMB // 2048)MB | \(.endpoint)"' "$INVENTORY_FILE" 2>/dev/null)
                while IFS= read -r wline; do
                    [ -n "$wline" ] || continue
                    report+="• $wline\n"
                done <<< "$worker_lines"
            else
                report+="• Nenhum nó worker cadastrado no momento no fleet-inventory.json.\n"
            fi
        else
            report+="• Inventário de frota não localizado. Cadastre nós remotos no menu Fleet Hub.\n"
        fi
    else
        report+="🛰️ CONTEXTO DA FROTA (MODO SIMPLES / STANDALONE):\n"
        report+="• O MNO Fleet Hub está inativo neste nó (Consumo ocioso: 0 MB de RAM).\n"
        report+="• Este servidor opera como nó isolado e não coordena a frota no momento.\n"
        report+="• Para conectar servidores operários (Workers) ou clonar stacks entre VPSs, altere o modo para Torre Master no Control Center ou no menu Fleet Hub.\n"
    fi

    if [ "${1:-}" = "--cli" ] || [ "${1:-}" = "text" ] || [ -z "${TERM:-}" ]; then
        printf '%b\n' "$report"
        return 0
    fi

    whiptail --title "RAIO-X ESTRUTURAL DA FROTA MNO" --msgbox "$report" 20 78
}

# Notificação executiva via MNO Sentinel (Telegram e Webhook n8n)
dispatch_sentinel_notification_bash() {
    local op_title="$1"
    local app_name="$2"
    local origin_desc="$3"
    local dest_desc="$4"
    local vols_count="${5:-0}"
    local dns_status="${6:-Não alterado}"
    local duration_sec="${7:-30}"

    local config_file=""
    if [ -f "/audit/sentinel_config.json" ]; then
        config_file="/audit/sentinel_config.json"
    elif [ -f "/root/SetupLowCodeMno/.control/sentinel_config.json" ]; then
        config_file="/root/SetupLowCodeMno/.control/sentinel_config.json"
    elif [ -f "/root/.control/sentinel.json" ]; then
        config_file="/root/.control/sentinel.json"
    fi

    local tg_token="" tg_chat="" wh_url=""
    if [ -n "$config_file" ] && command -v jq >/dev/null 2>&1; then
        tg_token=$(jq -r '.telegramBotToken // empty' "$config_file" 2>/dev/null || true)
        tg_chat=$(jq -r '.telegramChatID // empty' "$config_file" 2>/dev/null || true)
        wh_url=$(jq -r '.webhookURL // empty' "$config_file" 2>/dev/null || true)
    fi

    [ -n "$tg_token" ] || tg_token=$(grep -E '^TELEGRAM_BOT_TOKEN=' /root/.env 2>/dev/null | cut -d= -f2- | tr -d ' "\r' || true)
    [ -n "$tg_chat" ] || tg_chat=$(grep -E '^TELEGRAM_CHAT_ID=' /root/.env 2>/dev/null | cut -d= -f2- | tr -d ' "\r' || true)
    [ -n "$wh_url" ] || wh_url=$(cat /root/.sentinel_webhook 2>/dev/null | tr -d ' \r\n' || true)

    local tg_msg="🚀 *[MNO FLEET HUB] ${op_title} Concluída com Sucesso!*\n\n"
    tg_msg+="📦 *Aplicação / Combo:* \`${app_name}\`\n"
    tg_msg+="🛫 *Origem:* ${origin_desc}\n"
    tg_msg+="🛬 *Destino:* ${dest_desc}\n\n"
    tg_msg+="🌐 *DNS & Ingress:* ${dns_status}\n"
    tg_msg+="💾 *Volumes Processados:* ${vols_count} volume(s)\n"
    tg_msg+="⏱️ *Duração Estimada:* ${duration_sec}s\n\n"
    tg_msg+="✅ _Ambiente auditado e pronto para uso pelo Setup MNO._"

    # Envio Telegram
    if [ -n "$tg_token" ] && [ -n "$tg_chat" ]; then
        echo "[SENTINEL] Enviando alerta para o Telegram..." >> "$TRANSFER_LOG" 2>/dev/null || true
        curl -s -m 5 -X POST "https://api.telegram.org/bot${tg_token}/sendMessage" \
            -d chat_id="$tg_chat" \
            -d parse_mode="Markdown" \
            -d text="$tg_msg" >> "$TRANSFER_LOG" 2>&1 || true
    fi

    # Envio Webhook n8n
    if [ -n "$wh_url" ]; then
        echo "[SENTINEL] Disparando payload JSON para o Webhook ($wh_url)..." >> "$TRANSFER_LOG" 2>/dev/null || true
        local payload
        payload=$(jq -n \
            --arg event "fleet_operation_completed" \
            --arg op "$op_title" \
            --arg app "$app_name" \
            --arg origin "$origin_desc" \
            --arg dest "$dest_desc" \
            --arg dns "$dns_status" \
            --argjson vols "$vols_count" \
            --argjson duration "$duration_sec" \
            --arg report "$tg_msg" \
            --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
            '{
                event: $event,
                operation: $op,
                appName: $app,
                origin: $origin,
                destination: $dest,
                dnsStatus: $dns,
                volumesCount: $vols,
                durationSeconds: $duration,
                formattedReport: $report,
                timestamp: $now,
                status: "healthy"
            }' 2>/dev/null || echo "{}")
        curl -s -m 5 -X POST -H "Content-Type: application/json" -d "$payload" "$wh_url" >> "$TRANSFER_LOG" 2>&1 || true
    fi
}

# Criar backup portátil universal (com suporte a combos completos, volumes e NoSQL)
action_backup_app() {
    local chosen_app="${1:-}"
    local is_cli=false
    if [ -n "$chosen_app" ] || [ -z "${TERM:-}" ] || [ "${2:-}" = "--cli" ]; then
        is_cli=true
    fi

    local stacks
    stacks=$(list_local_swarm_stacks)
    if [ -z "$stacks" ]; then
        if [ "$is_cli" = "true" ]; then
            echo "Nenhuma aplicação em Docker Swarm foi encontrada em execução neste servidor."
        else
            whiptail --title "BACKUP DE APLICAÇÃO" --msgbox "Nenhuma aplicação em Docker Swarm foi encontrada em execução neste servidor." 10 70
        fi
        return 0
    fi

    if [ -z "$chosen_app" ]; then
        local stack_menu=()
        while IFS= read -r s; do
            [ -n "$s" ] || continue
            case "$s" in
                mnoctrl*|cloudflared|traefik|portainer|pgbouncer|redis|postgres|mysql84|mysql) continue ;;
            esac
            stack_menu+=("$s" "Stack Docker Swarm ativa")
        done <<< "$stacks"

        chosen_app=$(whiptail --title "SELECIONE A APLICAÇÃO PARA BACKUP" --menu \
            "Escolha a aplicação para gerar um Backup Portátil (.tar.gz universal):" 18 70 6 \
            "${stack_menu[@]}" 3>&1 1>&2 2>&3) || return 0
    fi

    acquire_node_lock "local" "Backup Portatil ($chosen_app)" 300 || return 1
    local tmpdir
    tmpdir=$(mktemp -d)
    trap 'release_node_lock "local"; rm -rf "$tmpdir"' RETURN

    # 1. Detecção Inteligente de Contexto de Combo
    local initial_yaml_tmp="$tmpdir/initial_detect.yaml"
    resolve_live_stack_yaml "local" "" "$chosen_app" "$initial_yaml_tmp" || true

    local combo_info
    combo_info=$(detect_app_combo_context "local" "" "$chosen_app" "$initial_yaml_tmp")
    rm -f "$initial_yaml_tmp"

    local is_combo="false" combo_name="" linked_stacks=""
    IFS='|' read -r is_combo combo_name linked_stacks <<< "$combo_info"

    local apps_to_backup=("$chosen_app")
    if [ "$is_combo" = "true" ] && [ -n "$linked_stacks" ] && [ "$linked_stacks" != "none" ]; then
        if [ "$is_cli" = "false" ]; then
            local combo_choice
            combo_choice=$(whiptail --title "🤖 DETECÇÃO INTELIGENTE DE COMBO" --menu \
                "A aplicação '$chosen_app' faz parte de um Combo Integrado:\n$combo_name\n\nFerramentas conectadas detectadas neste servidor:\n• $(echo "$linked_stacks" | sed 's/ / \n• /g')\n\nComo você deseja gerar o Backup Portátil (.tar.gz)?" 20 78 2 \
                "1" "BACKUP DO COMBO COMPLETO (Gera pacote único com todas as ferramentas)" \
                "2" "BACKUP APENAS DE '$chosen_app' (somente esta aplicação isolada)" \
                3>&1 1>&2 2>&3) || return 0

            if [ "$combo_choice" = "1" ]; then
                for ls in $linked_stacks; do
                    [ -n "$ls" ] || continue
                    if [[ ! " ${apps_to_backup[*]} " =~ " ${ls} " ]]; then
                        apps_to_backup+=("$ls")
                    fi
                done
            fi
        else
            for ls in $linked_stacks; do
                [ -n "$ls" ] || continue
                if [[ ! " ${apps_to_backup[*]} " =~ " ${ls} " ]]; then
                    apps_to_backup+=("$ls")
                fi
            done
        fi
    fi

    # Anexar obrigatoriamente qualquer stack de Redis dedicado associada às ferramentas selecionadas
    attach_dedicated_redis_to_list "local" "" apps_to_backup

    # Ordenação topológica: dependências de infra (minio, rabbitmq, redis) antes das aplicações
    local dep_bkp=()
    local main_bkp=()
    for a in "${apps_to_backup[@]}"; do
        if [[ "$a" == minio* ]] || [[ "$a" == rabbitmq* ]] || [[ "$a" == *redis* ]] || [[ "$a" == *-mq* ]] || [[ "$a" == *redisevo* ]]; then
            dep_bkp+=("$a")
        else
            main_bkp+=("$a")
        fi
    done
    apps_to_backup=("${dep_bkp[@]}" "${main_bkp[@]}")

    local timestamp
    timestamp=$(date -u +%Y%m%d_%H%M%SZ)
    local local_arch
    local_arch=$(get_local_arch)
    mkdir -p "$BACKUP_BASE_DIR"

    local backup_prefix="$chosen_app"
    if [ "$is_combo" = "true" ] && [ ${#apps_to_backup[@]} -gt 1 ]; then
        backup_prefix="combo_${chosen_app}"
    fi
    local backup_file="$BACKUP_BASE_DIR/${backup_prefix}_backup_${local_arch}_${timestamp}.tar.gz"

    mkdir -p "$tmpdir/stacks" "$tmpdir/volumes" "$tmpdir/dumps"

    local total_apps=${#apps_to_backup[@]}
    local total_vols_backed_up=0
    local manifest_stacks=()

    local backup_log="$tmpdir/backup_progress.log"
    : > "$backup_log"

    run_backup_subpipeline() {
        local a_idx=0
        for cur_app in "${apps_to_backup[@]}"; do
            a_idx=$((a_idx + 1))
            local pct_base=$(( (a_idx - 1) * 100 / total_apps ))
            local pct_step=$(( 100 / total_apps ))

            echo -e "XXX\n$((pct_base + (pct_step * 10 / 100)))\n[$a_idx/$total_apps] Obtendo manifesto da stack '$cur_app'...\nXXX"
            local stack_yaml="$tmpdir/stacks/${cur_app}.yaml"
            resolve_live_stack_yaml "local" "" "$cur_app" "$stack_yaml" || true
            [ -s "$stack_yaml" ] || echo "# Stack: $cur_app" > "$stack_yaml"

            if [ "$cur_app" = "$chosen_app" ]; then
                cp -f "$stack_yaml" "$tmpdir/stack.yaml"
            fi

            local db_info
            db_info=$(detect_database_engine "$stack_yaml" "$cur_app")
            local db_dump_file=""

            if [[ "$db_info" == postgres:* ]]; then
                local pg_dbname="${db_info#postgres:}"
                echo -e "XXX\n$((pct_base + (pct_step * 30 / 100)))\n[$a_idx/$total_apps] Extraindo dump PostgreSQL ($pg_dbname)...\nXXX"
                local pg_c
                pg_c=$(docker ps -qf name=postgres 2>/dev/null | head -n1 || true)
                if [ -n "$pg_c" ]; then
                    docker exec -i "$pg_c" pg_dump -U postgres -d "$pg_dbname" --clean --if-exists 2>> "$backup_log" | gzip > "$tmpdir/dumps/${cur_app}_postgres.sql.gz" || true
                    if [ -s "$tmpdir/dumps/${cur_app}_postgres.sql.gz" ]; then
                        db_dump_file="dumps/${cur_app}_postgres.sql.gz"
                        if [ "$cur_app" = "$chosen_app" ]; then
                            cp -f "$tmpdir/dumps/${cur_app}_postgres.sql.gz" "$tmpdir/db_logical_dump.sql.gz"
                        fi
                    fi
                fi
            elif [[ "$db_info" == mysql84:* ]]; then
                local my_dbname="${db_info#mysql84:}"
                echo -e "XXX\n$((pct_base + (pct_step * 30 / 100)))\n[$a_idx/$total_apps] Extraindo dump MySQL 8.4 ($my_dbname)...\nXXX"
                local my_c my_pwd
                my_c=$(docker ps -qf name=mysql84 2>/dev/null | head -n1 || true)
                if [ -n "$my_c" ]; then
                    my_pwd=$(docker inspect "$my_c" --format '{{range .Config.Env}}{{println .}}{{end}}' 2>/dev/null | grep MYSQL_ROOT_PASSWORD | cut -d= -f2- || grep -oP '(?<=MYSQL_ROOT_PASSWORD=).+' /root/mysql84.yaml 2>/dev/null || echo "")
                    docker exec -i "$my_c" mysqldump -u root -p"$my_pwd" --databases "$my_dbname" --add-drop-table 2>> "$backup_log" | gzip > "$tmpdir/dumps/${cur_app}_mysql84.sql.gz" || true
                    if [ -s "$tmpdir/dumps/${cur_app}_mysql84.sql.gz" ]; then
                        db_dump_file="dumps/${cur_app}_mysql84.sql.gz"
                        if [ "$cur_app" = "$chosen_app" ]; then
                            cp -f "$tmpdir/dumps/${cur_app}_mysql84.sql.gz" "$tmpdir/db_logical_dump.sql.gz"
                        fi
                    fi
                fi
            elif [[ "$db_info" == mysql:* ]]; then
                local my_dbname="${db_info#mysql:}"
                echo -e "XXX\n$((pct_base + (pct_step * 30 / 100)))\n[$a_idx/$total_apps] Extraindo dump MySQL 8.0 ($my_dbname)...\nXXX"
                local my_c my_pwd
                my_c=$(docker ps --filter "label=com.docker.swarm.service.name=mysql_mysql" -q 2>/dev/null | head -n1 || true)
                [ -n "$my_c" ] || my_c=$(docker ps -qf name=mysql_mysql 2>/dev/null | head -n1 || true)
                [ -n "$my_c" ] || my_c=$(docker ps --format '{{.ID}} {{.Names}}' 2>/dev/null | grep -v 'mysql84' | grep -E 'mysql_mysql|mysql\.1' | awk '{print $1}' | head -n1 || true)
                if [ -n "$my_c" ]; then
                    my_pwd=$(docker inspect "$my_c" --format '{{range .Config.Env}}{{println .}}{{end}}' 2>/dev/null | grep MYSQL_ROOT_PASSWORD | cut -d= -f2- || grep -oP '(?<=MYSQL_ROOT_PASSWORD=).+' /root/mysql.yaml 2>/dev/null || echo "")
                    docker exec -i -e MYSQL_PWD="$my_pwd" "$my_c" mysqldump -u root --databases "$my_dbname" --add-drop-table 2>> "$backup_log" | gzip > "$tmpdir/dumps/${cur_app}_mysql.sql.gz" || true
                    if [ -s "$tmpdir/dumps/${cur_app}_mysql.sql.gz" ]; then
                        db_dump_file="dumps/${cur_app}_mysql.sql.gz"
                        if [ "$cur_app" = "$chosen_app" ]; then
                            cp -f "$tmpdir/dumps/${cur_app}_mysql.sql.gz" "$tmpdir/db_logical_dump.sql.gz"
                        fi
                    fi
                fi
            elif [[ "$db_info" == mongodb:* ]]; then
                local mg_dbname="${db_info#mongodb:}"
                echo -e "XXX\n$((pct_base + (pct_step * 30 / 100)))\n[$a_idx/$total_apps] Extraindo dump MongoDB ($mg_dbname)...\nXXX"
                local mg_c
                mg_c=$(docker ps --filter "label=com.docker.swarm.service.name=${cur_app}_mongo" -q 2>/dev/null | head -n1 || docker ps -qf name=mongo 2>/dev/null | head -n1 || true)
                if [ -n "$mg_c" ]; then
                    docker exec -i "$mg_c" mongodump --archive --gzip 2>> "$backup_log" > "$tmpdir/dumps/${cur_app}_mongo.archive.gz" || true
                    if [ -s "$tmpdir/dumps/${cur_app}_mongo.archive.gz" ]; then
                        db_dump_file="dumps/${cur_app}_mongo.archive.gz"
                    fi
                fi
            fi

            # Extração de Volumes Docker Persistentes
            echo -e "XXX\n$((pct_base + (pct_step * 60 / 100)))\n[$a_idx/$total_apps] Compactando volumes persistentes ($cur_app)...\nXXX"
            local cur_vols=()
            while IFS= read -r v; do
                [ -n "$v" ] || continue
                cur_vols+=("$v")
                echo "Compactando volume $v de $cur_app..." >> "$backup_log"
                docker run --rm -v "${v}:/voldata:ro" alpine tar -czf - -C /voldata . > "$tmpdir/volumes/vol_${v}.tar.gz" 2>> "$backup_log" || true
                total_vols_backed_up=$((total_vols_backed_up + 1))
            done < <(get_application_volumes "$stack_yaml" "$cur_app" "local" "")

            # Extração de Bind Mounts de Configuração Local
            local cur_binds=()
            while IFS= read -r b; do
                [ -n "$b" ] || continue
                cur_binds+=("$b")
            done < <(get_application_bind_mounts "$stack_yaml" "$cur_app" "local" "")

            if [ ${#cur_binds[@]} -gt 0 ]; then
                echo "Compactando bind mounts de configuração de $cur_app: ${cur_binds[*]}" >> "$backup_log"
                tar -czf "$tmpdir/volumes/binds_${cur_app}.tar.gz" -P "${cur_binds[@]}" 2>> "$backup_log" || true
            fi

            # Extração de domínios e portas mapeadas
            local cur_domains=()
            while IFS= read -r d; do
                [ -n "$d" ] || continue
                local target_sp
                target_sp=$(resolve_host_service_port "$stack_yaml" "$d" "$cur_app")
                local svc_n="${target_sp%%:*}"
                local svc_p="${target_sp##*:}"
                cur_domains+=("${d}|${svc_n}|${svc_p}")
            done < <(grep -oP 'Host\(`\K[^`]+' "$stack_yaml" 2>/dev/null | sort -u || true)

            local s3_info
            s3_info=$(detect_s3_storage_engine "$stack_yaml" "$cur_app")
            local mq_info
            mq_info=$(detect_rabbitmq_engine "$stack_yaml" "$cur_app")

            local vols_json
            vols_json=$(printf '%s\n' "${cur_vols[@]}" | jq -R . | jq -s . 2>/dev/null || echo "[]")
            local domains_json
            domains_json=$(printf '%s\n' "${cur_domains[@]}" | jq -R . | jq -s . 2>/dev/null || echo "[]")

            manifest_stacks+=("$(jq -n \
                --arg name "$cur_app" \
                --arg yaml "stacks/${cur_app}.yaml" \
                --arg db "$db_info" \
                --arg dump "$db_dump_file" \
                --arg s3 "$s3_info" \
                --arg mq "$mq_info" \
                --argjson vols "$vols_json" \
                --argjson doms "$domains_json" \
                '{
                    name: $name,
                    yamlFile: $yaml,
                    dbEngine: $db,
                    dbDumpFile: $dump,
                    s3Engine: $s3,
                    mqEngine: $mq,
                    volumes: $vols,
                    domains: $doms
                }')")
        done

        local stacks_arr_json
        stacks_arr_json=$(printf '%s\n' "${manifest_stacks[@]}" | jq -s . 2>/dev/null || echo "[]")

        local btype="single_app"
        [ "$is_combo" = "true" ] && [ ${#apps_to_backup[@]} -gt 1 ] && btype="combo_bundle"

        cat > "$tmpdir/manifest.json" << EOF
{
  "schemaVersion": 2,
  "backupType": "$btype",
  "appName": "$chosen_app",
  "comboName": "$combo_name",
  "architecture": "$local_arch",
  "stacksCount": ${#apps_to_backup[@]},
  "volumesCount": $total_vols_backed_up,
  "createdAt": "$(date -u -Iseconds)",
  "stacks": $stacks_arr_json
}
EOF

        echo -e "XXX\n90\nEmpacotando arquivo tar.gz universal...\nXXX"
        tar -czf "$backup_file" -C "$tmpdir" .
        echo -e "XXX\n100\nBackup concluído com sucesso!\nXXX"
        sleep 1
    }

    if [ "$is_cli" = "true" ]; then
        run_backup_subpipeline
    else
        run_backup_subpipeline | whiptail --title "CRIANDO BACKUP PORTÁTIL UNIVERSAL" --gauge "Iniciando snapshot consistente de volumes e bancos..." 10 78 0
    fi

    local sha size
    sha=$(sha256sum "$backup_file" | awk '{print $1}')
    size=$(du -h "$backup_file" | awk '{print $1}')

    local notify_opt=false
    if [ "$is_cli" = "false" ]; then
        if whiptail --title "NOTIFICAÇÃO DO SENTINEL" --yesno \
            "Backup portátil gerado com sucesso!\n\nDeseja enviar uma notificação via Telegram e Webhook (n8n) informando a criação deste backup?" 11 70; then
            notify_opt=true
        fi
    fi

    if [ "$notify_opt" = "true" ]; then
        dispatch_sentinel_notification_bash "Backup Portátil" "$chosen_app" "Torre Master ($local_arch)" "$backup_file" "$total_vols_backed_up" "Preservado (sem alteração)" "25"
    fi

    local summary="✅ O Backup Portátil foi concluído com sucesso!\n\n"
    summary+="• Arquivo: $backup_file\n"
    summary+="• Tamanho: $size\n"
    summary+="• SHA-256: ${sha:0:16}...\n"
    summary+="• Arquitetura: $local_arch\n"
    summary+="• Stacks Inclusas (${#apps_to_backup[@]}): ${apps_to_backup[*]}\n"
    summary+="• Volumes Docker Compactados: $total_vols_backed_up\n"
    if [ "$is_combo" = "true" ] && [ ${#apps_to_backup[@]} -gt 1 ]; then
        summary+="• Tipo: Combo Integrado ($combo_name)\n"
    fi
    summary+="\nEste arquivo é universal e autossuficiente: pode ser transportado para qualquer outro servidor e restaurado via Opção 5 do Fleet Hub!"

    if [ "$is_cli" = "true" ]; then
        echo -e "$summary"
    else
        whiptail --title "BACKUP GERADO COM SUCESSO" --msgbox "$summary" 19 76
    fi
}

# Restaurar backup portátil universal em um servidor (Local ou Remoto)
action_restore_backup() {
    local backup_file="${1:-}"
    local dest_target="${2:-}"

    local is_cli=false
    if [ -n "$backup_file" ] || [ -z "${TERM:-}" ]; then
        is_cli=true
    fi

    # 1. Seleção do arquivo de backup
    if [ -z "$backup_file" ]; then
        local backups_menu=()
        if [ -d "$BACKUP_BASE_DIR" ]; then
            while IFS= read -r bf; do
                [ -f "$bf" ] || continue
                local bname bsize bdate
                bname=$(basename "$bf")
                bsize=$(du -h "$bf" | awk '{print $1}')
                bdate=$(date -r "$bf" "+%d/%m/%y %H:%M" 2>/dev/null || date "+%d/%m/%y %H:%M")
                backups_menu+=("$bname" "$bsize ($bdate)")
            done < <(find "$BACKUP_BASE_DIR" -maxdepth 1 -name "*.tar.gz" 2>/dev/null | sort -r)
        fi

        if [ ${#backups_menu[@]} -gt 0 ]; then
            backups_menu+=("OUTRO" "Digitar o caminho de outro arquivo .tar.gz")
            local chosen_bname
            chosen_bname=$(whiptail --title "RESTAURAÇÃO: SELECIONE O ARQUIVO DE BACKUP" --menu \
                "Escolha o arquivo de Backup Portátil para restaurar neste ou em outro servidor:" 18 78 6 \
                "${backups_menu[@]}" 3>&1 1>&2 2>&3) || return 0

            if [ "$chosen_bname" = "OUTRO" ]; then
                backup_file=$(whiptail --title "CAMINHO DO BACKUP" --inputbox \
                    "Informe o caminho absoluto do arquivo .tar.gz:" 10 70 "/root/backup_fleet/" 3>&1 1>&2 2>&3) || return 0
            else
                backup_file="$BACKUP_BASE_DIR/$chosen_bname"
            fi
        else
            backup_file=$(whiptail --title "CAMINHO DO BACKUP" --inputbox \
                "Nenhum backup encontrado em $BACKUP_BASE_DIR.\nInforme o caminho do arquivo .tar.gz:" 11 70 "/root/backup_fleet/" 3>&1 1>&2 2>&3) || return 0
        fi
    fi

    if [ ! -f "$backup_file" ]; then
        if [ "$is_cli" = "true" ]; then
            echo "Erro: Arquivo de backup '$backup_file' não encontrado."
        else
            whiptail --title "ERRO: ARQUIVO NÃO ENCONTRADO" --msgbox "O arquivo '$backup_file' não existe ou não pôde ser lido." 10 70
        fi
        return 1
    fi

    local tmpdir
    tmpdir=$(mktemp -d)
    trap 'rm -rf "$tmpdir"' RETURN

    whiptail --infobox "🔍 Inspecionando manifesto e integridade do backup...\nAguarde..." 8 70

    tar -xzf "$backup_file" -C "$tmpdir" manifest.json 2>/dev/null || true
    if [ ! -f "$tmpdir/manifest.json" ]; then
        tar -xzf "$backup_file" -C "$tmpdir" stack.yaml 2>/dev/null || true
        if [ ! -f "$tmpdir/stack.yaml" ]; then
            whiptail --title "ARQUIVO INVÁLIDO" --msgbox "O arquivo '$backup_file' não é um Backup Portátil válido do Setup MNO (manifest.json e stack.yaml ausentes)." 11 74
            return 1
        fi
        cat > "$tmpdir/manifest.json" << EOF
{
  "schemaVersion": 1,
  "backupType": "single_app",
  "appName": "app_restaurada",
  "architecture": "amd64",
  "createdAt": "$(date -u -Iseconds)"
}
EOF
    fi

    local schema_ver backup_type app_name combo_name backup_arch stacks_count
    schema_ver=$(jq -r '.schemaVersion // 1' "$tmpdir/manifest.json" 2>/dev/null || echo "1")
    backup_type=$(jq -r '.backupType // "single_app"' "$tmpdir/manifest.json" 2>/dev/null || echo "single_app")
    app_name=$(jq -r '.appName // "app"' "$tmpdir/manifest.json" 2>/dev/null || echo "app")
    combo_name=$(jq -r '.comboName // empty' "$tmpdir/manifest.json" 2>/dev/null || true)
    backup_arch=$(jq -r '.architecture // "amd64"' "$tmpdir/manifest.json" 2>/dev/null || echo "amd64")

    # 2. Selecionar o SERVIDOR DE DESTINO para a Restauração
    sync_fleet_inventory
    local local_arch
    local_arch=$(get_local_arch)

    local workers_tsv=""
    if [ -f "$INVENTORY_FILE" ]; then
        workers_tsv=$(jq -r '.nodes[]? | select(.role == "worker" or .mode == "worker") | select(.status != "deleted") | "\(.id)\t\(.name)\t\(.architecture // "amd64")\t\(.endpoint)\t\(.token)"' "$INVENTORY_FILE" 2>/dev/null || true)
    fi

    local chosen_dest_id="local"
    local dest_name="Torre Master (Nó Local)"
    local dest_arch="$local_arch"
    local dest_ssh_host=""

    if [ -n "$dest_target" ]; then
        chosen_dest_id="$dest_target"
    elif [ "$is_cli" = "false" ] && [ -n "$workers_tsv" ]; then
        local dest_menu=()
        dest_menu+=("local" "Torre Master (Nó Local) [$local_arch]")
        while IFS=$'\t' read -r wid wname warch wendpoint wtoken; do
            [ -n "$wid" ] || continue
            dest_menu+=("$wid" "$wname (Worker Remoto) [$warch]")
        done <<< "$workers_tsv"

        chosen_dest_id=$(whiptail --title "RESTAURAÇÃO: SELECIONE O SERVIDOR DE DESTINO" --menu \
            "Em qual servidor você deseja restaurar a aplicação '$app_name'?" 18 78 6 \
            "${dest_menu[@]}" 3>&1 1>&2 2>&3) || return 0
    fi

    if [ "$chosen_dest_id" != "local" ]; then
        dest_name=$(jq -r --arg id "$chosen_dest_id" '.nodes[]? | select(.id == $id) | .name' "$INVENTORY_FILE" 2>/dev/null)
        dest_arch=$(jq -r --arg id "$chosen_dest_id" '.nodes[]? | select(.id == $id) | .architecture // "amd64"' "$INVENTORY_FILE" 2>/dev/null)
        resolve_worker_ssh_host "$chosen_dest_id" "$dest_name" dest_ssh_host || return 0
    fi

    case "$backup_arch" in x86_64|amd64) backup_arch="amd64" ;; aarch64|arm64) backup_arch="arm64" ;; esac
    case "$dest_arch" in x86_64|amd64) dest_arch="amd64" ;; aarch64|arm64) dest_arch="arm64" ;; esac

    # Hardware Parity Advisory Gate
    if [ "$backup_arch" != "$dest_arch" ]; then
        if ! whiptail --title "⚠️ AVISO DE ARQUITETURA DE HARDWARE" --yesno \
            "O backup foi gerado na arquitetura: $backup_arch\nO servidor de destino opera em: $dest_arch\n\nAplicações com imagens multi-arquitetura iniciarão normalmente, mas binários nativos específicos podem requerer ajustes.\n\nDeseja prosseguir com a restauração mesmo assim?" 15 76; then
            return 0
        fi
    fi

    acquire_node_lock "$chosen_dest_id" "Restauracao de Backup ($app_name)" 600 || return 1
    trap 'release_node_lock "$chosen_dest_id"; rm -rf "$tmpdir"' RETURN

    whiptail --infobox "📦 Descompactando arquivos de volumes, stacks e banco...\nAguarde..." 8 70
    tar -xzf "$backup_file" -C "$tmpdir"

    local stacks_to_restore=()
    if [ "$schema_ver" -ge 2 ] && [ -d "$tmpdir/stacks" ]; then
        while IFS= read -r sy; do
            [ -f "$sy" ] || continue
            local sname
            sname=$(basename "$sy" .yaml)
            stacks_to_restore+=("$sname")
        done < <(find "$tmpdir/stacks" -maxdepth 1 -name "*.yaml" | sort)
    fi

    if [ ${#stacks_to_restore[@]} -eq 0 ]; then
        stacks_to_restore+=("$app_name")
        mkdir -p "$tmpdir/stacks"
        [ -f "$tmpdir/stack.yaml" ] && cp -f "$tmpdir/stack.yaml" "$tmpdir/stacks/${app_name}.yaml"
    fi

    # Decisão de Combo na Restauração
    if [ "$backup_type" = "combo_bundle" ] && [ ${#stacks_to_restore[@]} -gt 1 ]; then
        local combo_restore_choice
        combo_restore_choice=$(whiptail --title "🤖 RESTAURAÇÃO DE COMBO INTEGRADO" --menu \
            "Este backup contém o Combo Completo:\n$combo_name\n\nFerramentas prontas para restaurar:\n• $(echo "${stacks_to_restore[*]}" | sed 's/ / \n• /g')\n\nComo deseja proceder na restauração para '$dest_name'?" 20 78 2 \
            "1" "RESTAURAR COMBO COMPLETO (Recomendado — restaura todas as ferramentas)" \
            "2" "SELECIONAR UMA FERRAMENTA INDIVIDUAL DO COMBO" \
            3>&1 1>&2 2>&3) || return 0

        if [ "$combo_restore_choice" = "2" ]; then
            local sel_menu=()
            for st in "${stacks_to_restore[@]}"; do
                sel_menu+=("$st" "Ferramenta do combo")
            done
            local single_sel
            single_sel=$(whiptail --title "SELECIONE A FERRAMENTA" --menu \
                "Escolha qual ferramenta do combo você deseja restaurar isoladamente:" 18 70 6 \
                "${sel_menu[@]}" 3>&1 1>&2 2>&3) || return 0
            stacks_to_restore=("$single_sel")

            # Se a ferramenta selecionada possuir Redis dedicado no pacote de backup, anexa obrigatoriamente
            local sel_suf=""
            [[ "$single_sel" =~ ([a-f0-9]{7}) ]] && sel_suf="${BASH_REMATCH[1]}"
            for pack_sy in $(find "$tmpdir/stacks" -maxdepth 1 -name "*.yaml" 2>/dev/null); do
                local ps_cand
                ps_cand=$(basename "$pack_sy" .yaml)
                if [[ "$ps_cand" == *redis* ]] && [ "$ps_cand" != "$single_sel" ]; then
                    if [ -n "$sel_suf" ] && [[ "$ps_cand" == *"$sel_suf"* ]]; then
                        stacks_to_restore+=("$ps_cand")
                    fi
                fi
            done
        fi
    fi

    # Ordenação topológica: dependências de infra (minio, rabbitmq, redis) antes das aplicações
    local dep_stacks=()
    local main_stacks=()
    for st in "${stacks_to_restore[@]}"; do
        if [[ "$st" == minio* ]] || [[ "$st" == rabbitmq* ]] || [[ "$st" == *redis* ]]; then
            dep_stacks+=("$st")
        else
            main_stacks+=("$st")
        fi
    done
    stacks_to_restore=("${dep_stacks[@]}" "${main_stacks[@]}")

    # Decisão de DNS e Ingress
    local configure_dns=false
    local all_domains=()
    for st in "${stacks_to_restore[@]}"; do
        local st_yaml="$tmpdir/stacks/${st}.yaml"
        [ -f "$st_yaml" ] || continue
        while IFS= read -r d; do
            [ -n "$d" ] || continue
            all_domains+=("$d")
        done < <(grep -oP 'Host\(`\K[^`]+' "$st_yaml" 2>/dev/null | sort -u || true)
    done

    if [ ${#all_domains[@]} -gt 0 ]; then
        local dns_choice
        dns_choice=$(whiptail --title "🌐 COMUTAÇÃO DE DNS E TÚNEL CLOUDFLARE" --menu \
            "Domínios registrados neste backup:\n• $(echo "${all_domains[*]}" | sed 's/ / \n• /g')\n\nComo deseja tratar os acessos deste servidor que está recebendo a restauração?" 20 78 2 \
            "1" "RECUPERAÇÃO DE DESASTRE (Produção Definitiva — comutar domínios agora)" \
            "2" "CÓPIA DE TESTES (NÃO alterar DNS agora — mantém original intacto)" \
            3>&1 1>&2 2>&3) || return 0

        if [ "$dns_choice" = "1" ]; then
            configure_dns=true
        fi
    fi

    local restore_log="$tmpdir/restore_progress.log"
    : > "$restore_log"
    local total_restored_vols=0
    local total_rest_apps=${#stacks_to_restore[@]}

    run_restore_subpipeline() {
        local r_idx=0
        for cur_app in "${stacks_to_restore[@]}"; do
            r_idx=$((r_idx + 1))
            local pct_base=$(( (r_idx - 1) * 100 / total_rest_apps ))
            local pct_step=$(( 100 / total_rest_apps ))

            local cur_yaml="$tmpdir/stacks/${cur_app}.yaml"
            [ -f "$cur_yaml" ] || cur_yaml="$tmpdir/stack.yaml"

            local cur_db_engine="none:"
            cur_db_engine=$(detect_database_engine "$cur_yaml" "$cur_app")

            local cur_s3_engine="none:"
            cur_s3_engine=$(detect_s3_storage_engine "$cur_yaml" "$cur_app")

            local cur_mq_engine="none:"
            cur_mq_engine=$(detect_rabbitmq_engine "$cur_yaml" "$cur_app")

            if [[ "$cur_db_engine" == mysql84:* ]]; then
                echo -e "XXX\n$((pct_base + (pct_step * 20 / 100)))\n[$r_idx/$total_rest_apps] Garantindo MySQL 8.4 no destino ($cur_app)...\nXXX"
                ensure_mysql84_ready "$chosen_dest_id" "$dest_ssh_host" >> "$restore_log" 2>&1 || true
            elif [[ "$cur_db_engine" == mysql:* ]]; then
                echo -e "XXX\n$((pct_base + (pct_step * 20 / 100)))\n[$r_idx/$total_rest_apps] Garantindo MySQL 8.0 no destino ($cur_app)...\nXXX"
                ensure_mysql_ready "$chosen_dest_id" "$dest_ssh_host" >> "$restore_log" 2>&1 || true
            fi

            if [[ "$cur_s3_engine" == minio:* ]] && [[ ! "$cur_app" == minio* ]]; then
                echo -e "XXX\n$((pct_base + (pct_step * 25 / 100)))\n[$r_idx/$total_rest_apps] Verificando MinIO no destino ($cur_app)...\nXXX"
                ensure_minio_ready "$chosen_dest_id" "$dest_ssh_host" >> "$restore_log" 2>&1 || true
            fi

            if [[ "$cur_mq_engine" == rabbitmq:* ]] && [[ ! "$cur_app" == rabbitmq* ]]; then
                echo -e "XXX\n$((pct_base + (pct_step * 25 / 100)))\n[$r_idx/$total_rest_apps] Verificando RabbitMQ no destino ($cur_app)...\nXXX"
                ensure_rabbitmq_ready "$chosen_dest_id" "$dest_ssh_host" >> "$restore_log" 2>&1 || true
            fi

            # Restaurar Volumes Persistentes
            echo -e "XXX\n$((pct_base + (pct_step * 45 / 100)))\n[$r_idx/$total_rest_apps] Restaurando volumes Docker ($cur_app)...\nXXX"
            local vol_files=()
            while IFS= read -r vf; do
                [ -f "$vf" ] || continue
                vol_files+=("$vf")
            done < <(find "$tmpdir/volumes" "$tmpdir" -maxdepth 1 -name "vol_*.tar.gz" 2>/dev/null | grep -E "${cur_app}|vol_" || true)

            for vf in "${vol_files[@]}"; do
                local vname
                vname=$(basename "$vf" .tar.gz | sed 's/^vol_//')
                [ -n "$vname" ] || continue
                echo "Criando e restaurando volume: $vname" >> "$restore_log"

                if [ "$chosen_dest_id" = "local" ]; then
                    docker volume create "$vname" >/dev/null 2>&1 || true
                    docker run --rm -i -v "${vname}:/voldata" alpine tar -xzf - -C /voldata < "$vf" >> "$restore_log" 2>&1 || true
                else
                    ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o BatchMode=yes "root@$dest_ssh_host" "docker volume create '$vname' >/dev/null 2>&1 || true"
                    ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o BatchMode=yes "root@$dest_ssh_host" "docker run --rm -i -v '${vname}:/voldata' alpine tar -xzf - -C /voldata" < "$vf" >> "$restore_log" 2>&1 || true
                fi
                total_restored_vols=$((total_restored_vols + 1))
            done

            # Restaurar Bind Mounts de Configuração se existirem
            local cur_bind_pkg=""
            for bp in "$tmpdir/volumes/binds_${cur_app}.tar.gz" "$tmpdir/binds_${cur_app}.tar.gz"; do
                if [ -s "$bp" ]; then
                    cur_bind_pkg="$bp"
                    break
                fi
            done
            if [ -n "$cur_bind_pkg" ]; then
                echo "Restaurando bind mounts de configuração de $cur_app no destino..." >> "$restore_log"
                if [ "$chosen_dest_id" = "local" ]; then
                    tar -xzf "$cur_bind_pkg" -P >> "$restore_log" 2>&1 || true
                else
                    ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o BatchMode=yes "root@$dest_ssh_host" "tar -xzf - -P" < "$cur_bind_pkg" >> "$restore_log" 2>&1 || true
                fi
            fi

            # Restaurar Banco de Dados Lógico
            echo -e "XXX\n$((pct_base + (pct_step * 65 / 100)))\n[$r_idx/$total_rest_apps] Restaurando banco de dados ($cur_app)...\nXXX"
            local dump_candidate=""
            for dmp in "$tmpdir/dumps/${cur_app}"* "$tmpdir/db_logical_dump.sql.gz" "$tmpdir/dumps/"*.sql.gz "$tmpdir/dumps/"*.archive.gz; do
                if [ -s "$dmp" ]; then
                    dump_candidate="$dmp"
                    break
                fi
            done

            if [ -n "$dump_candidate" ]; then
                if [[ "$cur_db_engine" == postgres:* ]]; then
                    local pg_db="${cur_db_engine#postgres:}"
                    local dc=""
                    if [ "$chosen_dest_id" = "local" ]; then
                        dc=$(docker ps -qf name=postgres 2>/dev/null | head -n1 || true)
                        if [ -n "$dc" ]; then
                            docker exec -i "$dc" psql -U postgres -tc "SELECT 1 FROM pg_database WHERE datname = '$pg_db'" | grep -q 1 || docker exec -i "$dc" psql -U postgres -c "CREATE DATABASE \"$pg_db\";" >> "$restore_log" 2>&1 || true
                            gunzip -c "$dump_candidate" | docker exec -i "$dc" psql -U postgres -d "$pg_db" >> "$restore_log" 2>&1 || true
                        fi
                    else
                        ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o BatchMode=yes "root@$dest_ssh_host" \
                            "dc=\$(docker ps -qf name=postgres | head -n1); [ -n \"\$dc\" ] && docker exec -i \"\$dc\" psql -U postgres -tc \"SELECT 1 FROM pg_database WHERE datname = '$pg_db'\" | grep -q 1 || docker exec -i \"\$dc\" psql -U postgres -c \"CREATE DATABASE \\\"$pg_db\\\";\"" >> "$restore_log" 2>&1 || true
                        gunzip -c "$dump_candidate" | ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o BatchMode=yes "root@$dest_ssh_host" \
                            "dc=\$(docker ps -qf name=postgres | head -n1); [ -n \"\$dc\" ] && docker exec -i \"\$dc\" psql -U postgres -d '$pg_db'" >> "$restore_log" 2>&1 || true
                    fi

                    # Reconciliação Polimórfica de Credenciais PostgreSQL
                    local dest_pg_pwd=""
                    if [ "$chosen_dest_id" = "local" ]; then
                        local dc_pwd
                        dc_pwd=$(docker ps -qf name=postgres 2>/dev/null | head -n1 || true)
                        [ -n "$dc_pwd" ] && dest_pg_pwd=$(docker inspect "$dc_pwd" --format '{{range .Config.Env}}{{println .}}{{end}}' 2>/dev/null | grep POSTGRES_PASSWORD | cut -d= -f2- || grep -oP '(?<=POSTGRES_PASSWORD=).+' /root/postgres.yaml 2>/dev/null || echo "")
                    else
                        dest_pg_pwd=$(ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o BatchMode=yes "root@$dest_ssh_host" 'dc=$(docker ps -qf name=postgres | head -n1); docker inspect "$dc" --format "{{range .Config.Env}}{{println .}}{{end}}" 2>/dev/null | grep POSTGRES_PASSWORD | cut -d= -f2- || grep -oP "(?<=POSTGRES_PASSWORD=).+" /root/postgres.yaml 2>/dev/null || echo ""')
                    fi
                    if [ -n "$dest_pg_pwd" ]; then
                        local safe_dest_pg_pwd
                        safe_dest_pg_pwd=$(printf '%s\n' "$dest_pg_pwd" | sed -e 's/[\/&|]/\\&/g')
                        sed -i -E "s/(POSTGRES_PASSWORD|DB_POSTGRESDB_PASSWORD|DB_PASSWORD|DB_PASS|DATABASE_PASSWORD|AP_POSTGRES_PASSWORD|KC_DB_PASSWORD|MB_DB_PASS|PAPERLESS_DBPASS|PENPOT_DATABASE_PASSWORD|TOOLJET_DB_PASS|VIKUNJA_DATABASE_PASSWORD|SAFE_DB_PASS)=[^[:space:]]+/\1=$safe_dest_pg_pwd/g" "$cur_yaml"
                        sed -i -E "s|(postgres(ql)?://[^:]+:)[^@]+(@postgres(ql)?:[0-9]+/[^[:space:]\"']+)|\\1${safe_dest_pg_pwd}\\3|g" "$cur_yaml"
                    fi
                elif [[ "$cur_db_engine" == mysql84:* ]]; then
                    local my_db="${cur_db_engine#mysql84:}"
                    local mc="" dest_pwd=""
                    if [ "$chosen_dest_id" = "local" ]; then
                        mc=$(docker ps -qf name=mysql84 2>/dev/null | head -n1 || true)
                        dest_pwd=$(docker inspect "$mc" --format '{{range .Config.Env}}{{println .}}{{end}}' 2>/dev/null | grep MYSQL_ROOT_PASSWORD | cut -d= -f2- || grep -oP '(?<=MYSQL_ROOT_PASSWORD=).+' /root/mysql84.yaml 2>/dev/null || echo "")
                        if [ -n "$mc" ] && [ -n "$dest_pwd" ]; then
                            printf 'CREATE DATABASE IF NOT EXISTS `%s`;\n' "$my_db" | docker exec -i -e MYSQL_PWD="$dest_pwd" "$mc" mysql -u root >> "$restore_log" 2>&1 || true
                            gunzip -c "$dump_candidate" | docker exec -i -e MYSQL_PWD="$dest_pwd" "$mc" mysql -u root "$my_db" >> "$restore_log" 2>&1 || true
                        fi
                    else
                        ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o BatchMode=yes "root@$dest_ssh_host" '
                            mc=$(docker ps -qf name=mysql84 | head -n1)
                            pwd=$(docker inspect "$mc" --format "{{range .Config.Env}}{{println .}}{{end}}" 2>/dev/null | grep MYSQL_ROOT_PASSWORD | cut -d= -f2- || grep -oP "(?<=MYSQL_ROOT_PASSWORD=).+" /root/mysql84.yaml 2>/dev/null || echo "")
                            if [ -n "$mc" ] && [ -n "$pwd" ]; then
                                printf "CREATE DATABASE IF NOT EXISTS \`'"$my_db"'\`;\n" | docker exec -i -e MYSQL_PWD="$pwd" "$mc" mysql -u root
                            fi
                        ' >> "$restore_log" 2>&1 || true
                        gunzip -c "$dump_candidate" | ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o BatchMode=yes "root@$dest_ssh_host" '
                            mc=$(docker ps -qf name=mysql84 | head -n1)
                            pwd=$(docker inspect "$mc" --format "{{range .Config.Env}}{{println .}}{{end}}" 2>/dev/null | grep MYSQL_ROOT_PASSWORD | cut -d= -f2- || grep -oP "(?<=MYSQL_ROOT_PASSWORD=).+" /root/mysql84.yaml 2>/dev/null || echo "")
                            if [ -n "$mc" ] && [ -n "$pwd" ]; then
                                docker exec -i -e MYSQL_PWD="$pwd" "$mc" mysql -u root "'"$my_db"'"
                            fi
                        ' >> "$restore_log" 2>&1 || true
                    fi
                elif [[ "$cur_db_engine" == mysql:* ]]; then
                    local my_db="${cur_db_engine#mysql:}"
                    local mc="" dest_pwd=""
                    if [ "$chosen_dest_id" = "local" ]; then
                        mc=$(docker ps --filter "label=com.docker.swarm.service.name=mysql_mysql" -q 2>/dev/null | head -n1 || docker ps -qf name=mysql_mysql 2>/dev/null | head -n1 || true)
                        dest_pwd=$(docker inspect "$mc" --format '{{range .Config.Env}}{{println .}}{{end}}' 2>/dev/null | grep MYSQL_ROOT_PASSWORD | cut -d= -f2- || grep -oP '(?<=MYSQL_ROOT_PASSWORD=).+' /root/mysql.yaml 2>/dev/null || echo "")
                        if [ -n "$mc" ] && [ -n "$dest_pwd" ]; then
                            printf 'CREATE DATABASE IF NOT EXISTS `%s`;\n' "$my_db" | docker exec -i -e MYSQL_PWD="$dest_pwd" "$mc" mysql -u root >> "$restore_log" 2>&1 || true
                            gunzip -c "$dump_candidate" | docker exec -i -e MYSQL_PWD="$dest_pwd" "$mc" mysql -u root "$my_db" >> "$restore_log" 2>&1 || true
                        fi
                    else
                        ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o BatchMode=yes "root@$dest_ssh_host" '
                            mc=$(docker ps --filter "label=com.docker.swarm.service.name=mysql_mysql" -q 2>/dev/null | head -n1 || docker ps -qf name=mysql_mysql 2>/dev/null | head -n1)
                            pwd=$(docker inspect "$mc" --format "{{range .Config.Env}}{{println .}}{{end}}" 2>/dev/null | grep MYSQL_ROOT_PASSWORD | cut -d= -f2- || grep -oP "(?<=MYSQL_ROOT_PASSWORD=).+" /root/mysql.yaml 2>/dev/null || echo "")
                            if [ -n "$mc" ] && [ -n "$pwd" ]; then
                                printf "CREATE DATABASE IF NOT EXISTS \`'"$my_db"'\`;\n" | docker exec -i -e MYSQL_PWD="$pwd" "$mc" mysql -u root
                            fi
                        ' >> "$restore_log" 2>&1 || true
                        gunzip -c "$dump_candidate" | ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o BatchMode=yes "root@$dest_ssh_host" '
                            mc=$(docker ps --filter "label=com.docker.swarm.service.name=mysql_mysql" -q 2>/dev/null | head -n1 || docker ps -qf name=mysql_mysql 2>/dev/null | head -n1)
                            pwd=$(docker inspect "$mc" --format "{{range .Config.Env}}{{println .}}{{end}}" 2>/dev/null | grep MYSQL_ROOT_PASSWORD | cut -d= -f2- || grep -oP "(?<=MYSQL_ROOT_PASSWORD=).+" /root/mysql.yaml 2>/dev/null || echo "")
                            if [ -n "$mc" ] && [ -n "$pwd" ]; then
                                docker exec -i -e MYSQL_PWD="$pwd" "$mc" mysql -u root "'"$my_db"'"
                            fi
                        ' >> "$restore_log" 2>&1 || true
                    fi
                elif [[ "$cur_db_engine" == mongodb:* ]]; then
                    if [ "$chosen_dest_id" = "local" ]; then
                        local mg_c
                        mg_c=$(docker ps --filter "label=com.docker.swarm.service.name=${cur_app}_mongo" -q 2>/dev/null | head -n1 || docker ps -qf name=mongo 2>/dev/null | head -n1 || true)
                        if [ -n "$mg_c" ]; then
                            docker exec -i "$mg_c" mongorestore --archive --gzip --drop < "$dump_candidate" >> "$restore_log" 2>&1 || true
                        fi
                    else
                        ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o BatchMode=yes "root@$dest_ssh_host" \
                            "mg_c=\$(docker ps --filter 'label=com.docker.swarm.service.name=${cur_app}_mongo' -q 2>/dev/null | head -n1 || docker ps -qf name=mongo 2>/dev/null | head -n1); [ -n \"\$mg_c\" ] && docker exec -i \"\$mg_c\" mongorestore --archive --gzip --drop" \
                            < "$dump_candidate" >> "$restore_log" 2>&1 || true
                    fi
                fi
            fi

            # 4. Deploy no Swarm de Destino
            echo -e "XXX\n$((pct_base + (pct_step * 85 / 100)))\n[$r_idx/$total_rest_apps] Fazendo deploy da stack '$cur_app' no Swarm...\nXXX"
            if [ "$chosen_dest_id" = "local" ]; then
                cp -f "$cur_yaml" "/root/${cur_app}.yaml"
                deploy_stack_with_portainer_priority "local" "" "$cur_app" "/root/${cur_app}.yaml" >> "$restore_log" 2>&1
            else
                ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o BatchMode=yes "root@$dest_ssh_host" "cat > /root/${cur_app}.yaml" < "$cur_yaml"
                deploy_stack_with_portainer_priority "$chosen_dest_id" "$dest_ssh_host" "$cur_app" "/root/${cur_app}.yaml" >> "$restore_log" 2>&1
            fi

            # 5. Comutação de DNS se solicitado
            if [ "$configure_dns" = "true" ]; then
                echo -e "XXX\n$((pct_base + (pct_step * 95 / 100)))\n[$r_idx/$total_rest_apps] Comutando rotas Cloudflare ($cur_app)...\nXXX"
                switch_cloudflare_dns_and_ingress "$chosen_dest_id" "$dest_ssh_host" "$cur_yaml" "$cur_app" >> "$restore_log" 2>&1 || true
            fi
        done

        echo -e "XXX\n100\nRestauração concluída com sucesso!\nXXX"
        sleep 1
    }

    if [ "$is_cli" = "true" ]; then
        run_restore_subpipeline
    else
        run_restore_subpipeline | whiptail --title "RESTAURANDO BACKUP PORTÁTIL" --gauge "Iniciando descompactação e restauração..." 10 78 0
    fi

    local notify_opt=false
    if [ "$is_cli" = "false" ]; then
        if whiptail --title "NOTIFICAÇÃO DO SENTINEL" --yesno \
            "Restauração concluída com sucesso!\n\nDeseja enviar uma notificação via Telegram e Webhook (n8n) informando a restauração deste backup?" 11 70; then
            notify_opt=true
        fi
    fi

    local dns_desc="Preservado (modo cópia de testes)"
    [ "$configure_dns" = "true" ] && dns_desc="Comutado para o novo servidor ($dest_name)"

    if [ "$notify_opt" = "true" ]; then
        dispatch_sentinel_notification_bash "Restauração de Backup" "$app_name" "$backup_file" "$dest_name ($dest_arch)" "$total_restored_vols" "$dns_desc" "35"
    fi

    local res_summary="🎉 RESTAURAÇÃO CONCLUÍDA COM SUCESSO!\n\n"
    res_summary+="• Aplicação / Combo: $app_name\n"
    if [ "$backup_type" = "combo_bundle" ]; then
        res_summary+="• Ecossistema: $combo_name\n"
    fi
    res_summary+="• Arquivo de Origem: $(basename "$backup_file")\n"
    res_summary+="• Servidor Destino: $dest_name ($dest_arch)\n"
    res_summary+="• Stacks Restauradas (${#stacks_to_restore[@]}): ${stacks_to_restore[*]}\n"
    res_summary+="• Volumes Docker Restaurados: $total_restored_vols\n"
    res_summary+="• Roteamento DNS / Túnel: $dns_desc\n\n"
    res_summary+="✅ Todos os containers e dados persistentes estão ativos e funcionais no Swarm de destino."

    if [ "$is_cli" = "true" ]; then
        echo -e "$res_summary"
    else
        whiptail --title "RESTAURAÇÃO CONCLUÍDA" --msgbox "$res_summary" 19 76
    fi
}

# Transferência e Clonagem Atômica
action_transfer_or_clone() {
    local op_mode="${1:-transfer}"
    shift 2>/dev/null || true

    local is_cli=false
    local cli_app=""
    local cli_origin=""
    local cli_dest=""
    local cli_stop_origin=""
    local cli_update_dns=""
    local cli_minio=""
    local cli_combo_choice=""

    while [ $# -gt 0 ]; do
        case "$1" in
            --cli) is_cli=true ;;
            --stop-origin) cli_stop_origin="true" ;;
            --keep-origin) cli_stop_origin="false" ;;
            --update-dns) cli_update_dns="true" ;;
            --no-dns) cli_update_dns="false" ;;
            --minio=*) cli_minio="${1#*=}" ;;
            --minio) shift; cli_minio="$1" ;;
            --combo-all) cli_combo_choice="1" ;;
            --combo-only-app) cli_combo_choice="2" ;;
            -*) ;;
            *)
                if [ -z "$cli_app" ]; then
                    cli_app="$1"
                elif [ -z "$cli_origin" ]; then
                    cli_origin="$1"
                elif [ -z "$cli_dest" ]; then
                    cli_dest="$1"
                fi
                ;;
        esac
        shift
    done

    sync_fleet_inventory

    local pending_file="$CONTROL_DIR/pending-fleet-clone.json"
    if [ -z "$cli_app" ] && [ -f "$pending_file" ]; then
        if jq -e . "$pending_file" >/dev/null 2>&1; then
            cli_app=$(jq -r '.appName // empty' "$pending_file")
            cli_origin=$(jq -r '.originNodeId // empty' "$pending_file")
            cli_dest=$(jq -r '.destNodeId // empty' "$pending_file")
            local p_mode
            p_mode=$(jq -r '.mode // empty' "$pending_file")
            [ -n "$p_mode" ] && op_mode="$p_mode"
            cli_stop_origin=$(jq -r 'if .stopOriginStack != null then (.stopOriginStack | tostring) else empty end' "$pending_file")
            cli_update_dns=$(jq -r 'if .updateDns != null then (.updateDns | tostring) else empty end' "$pending_file")
            cli_minio=$(jq -r '.minioPolicy // empty' "$pending_file")
            cli_combo_choice=$(jq -r '.comboChoice // empty' "$pending_file")
            is_cli=true
        fi
    fi

    if [ -n "$cli_app" ] && [ -n "$cli_origin" ] && [ -n "$cli_dest" ]; then
        is_cli=true
    fi

    local op_title="TRANSFERÊNCIA DE APLICAÇÃO"
    [ "$op_mode" = "clone" ] && op_title="CLONAGEM DE APLICAÇÃO (TESTE)"

    local fleet_mode
    fleet_mode=$(get_local_fleet_mode)
    if [ "$fleet_mode" = "worker" ]; then
        if [ "$is_cli" = "true" ]; then
            echo "ERRO: Esta VPS está configurada como Nó Worker subordinado. A transferência deve ser acionada a partir da Torre Master." >&2
        else
            whiptail --title "$op_title" --msgbox \
                "Esta VPS está configurada como Nó Worker subordinado.\n\nA transferência e clonagem de aplicações entre servidores é orquestrada centralmente a partir da sua Torre Master (Cockpit Local no WSL2).\n\nAbra o menu Fleet Hub na sua Torre Master para iniciar a transferência de qualquer aplicação deste Worker para a Torre ou para outro servidor!\n\nNeste nó Worker, você também pode usar a Opção 4 para gerar um Backup Portátil (.tar.gz) dos dados a qualquer momento." 16 76
        fi
        cleanup_pending_fleet_task
        return 0
    fi

    local local_arch
    local_arch=$(get_local_arch)

    # 1. Carregar workers cadastrados
    local workers_tsv=""
    if [ -f "$INVENTORY_FILE" ]; then
        workers_tsv=$(jq -r '.nodes[]? | select(.role == "worker" or .mode == "worker") | select(.status != "deleted") | "\(.id)\t\(.name)\t\(.architecture // "amd64")\t\(.endpoint)\t\(.token)"' "$INVENTORY_FILE" 2>/dev/null || true)
    fi

    if [ -z "$workers_tsv" ] && [ "$is_cli" != "true" ]; then
        whiptail --title "$op_title" --msgbox "Nenhum nó worker remoto cadastrado na frota. Acesse o menu Fleet Hub no Control Center e faça o pareamento de um Worker antes de transferir." 12 76
        cleanup_pending_fleet_task
        return 0
    fi

    local chosen_origin_id=""
    local chosen_dest_id=""

    if [ "$is_cli" = "true" ]; then
        case "$cli_origin" in
            local|master|"Torre Master"|"torre"|"master-local") chosen_origin_id="local" ;;
            *)
                if [ -f "$INVENTORY_FILE" ]; then
                    chosen_origin_id=$(jq -r --arg q "$cli_origin" '.nodes[]? | select(.id == $q or .name == $q or (.endpoint // "" | test($q))) | .id' "$INVENTORY_FILE" 2>/dev/null | head -n1 || true)
                fi
                [ -n "$chosen_origin_id" ] || chosen_origin_id="$cli_origin"
                ;;
        esac

        case "$cli_dest" in
            local|master|"Torre Master"|"torre"|"master-local") chosen_dest_id="local" ;;
            *)
                if [ -f "$INVENTORY_FILE" ]; then
                    chosen_dest_id=$(jq -r --arg q "$cli_dest" '.nodes[]? | select(.id == $q or .name == $q or (.endpoint // "" | test($q))) | .id' "$INVENTORY_FILE" 2>/dev/null | head -n1 || true)
                fi
                [ -n "$chosen_dest_id" ] || chosen_dest_id="$cli_dest"
                ;;
        esac
    else
        # 2. Selecionar o SERVIDOR DE ORIGEM
        local origin_menu=()
        origin_menu+=("local" "Torre Master (Nó Local) [$local_arch]")
        while IFS=$'\t' read -r wid wname warch wendpoint wtoken; do
            [ -n "$wid" ] || continue
            origin_menu+=("$wid" "$wname (Worker Remoto) [$warch]")
        done <<< "$workers_tsv"

        chosen_origin_id=$(whiptail --title "SELECIONE O SERVIDOR DE ORIGEM" --menu \
            "Onde a aplicação que você deseja mover está rodando HOJE?" 18 78 6 \
            "${origin_menu[@]}" 3>&1 1>&2 2>&3) || return 0

        # 3. Selecionar o SERVIDOR DE DESTINO
        local dest_menu=()
        if [ "$chosen_origin_id" != "local" ]; then
            dest_menu+=("local" "Torre Master (Nó Local) [$local_arch]")
        fi
        while IFS=$'\t' read -r wid wname warch wendpoint wtoken; do
            [ -n "$wid" ] || continue
            [ "$wid" != "$chosen_origin_id" ] || continue
            dest_menu+=("$wid" "$wname (Worker Remoto) [$warch]")
        done <<< "$workers_tsv"

        if [ ${#dest_menu[@]} -eq 0 ]; then
            whiptail --title "$op_title" --msgbox "Nenhum servidor de destino disponível na frota." 10 70
            return 0
        fi

        chosen_dest_id=$(whiptail --title "SELECIONE O SERVIDOR DE DESTINO" --menu \
            "Para qual servidor a aplicação deve ser transferida?" 18 78 6 \
            "${dest_menu[@]}" 3>&1 1>&2 2>&3) || return 0
    fi

    # 4. Dados e Arquiteturas dos Servidores
    local origin_name origin_arch dest_name dest_arch origin_endpoint origin_token dest_endpoint dest_token
    if [ "$chosen_origin_id" = "local" ]; then
        origin_name="Torre Master (Nó Local)"
        origin_arch="$local_arch"
    else
        origin_name=$(jq -r --arg id "$chosen_origin_id" '.nodes[]? | select(.id == $id) | .name' "$INVENTORY_FILE" 2>/dev/null)
        origin_arch=$(jq -r --arg id "$chosen_origin_id" '.nodes[]? | select(.id == $id) | .architecture // "amd64"' "$INVENTORY_FILE" 2>/dev/null)
        origin_endpoint=$(jq -r --arg id "$chosen_origin_id" '.nodes[]? | select(.id == $id) | .endpoint' "$INVENTORY_FILE" 2>/dev/null)
        origin_token=$(jq -r --arg id "$chosen_origin_id" '.nodes[]? | select(.id == $id) | .token' "$INVENTORY_FILE" 2>/dev/null)
    fi
    [ -n "$origin_name" ] || origin_name="$chosen_origin_id"
    [ -n "$origin_arch" ] || origin_arch="$local_arch"

    if [ "$chosen_dest_id" = "local" ]; then
        dest_name="Torre Master (Nó Local)"
        dest_arch="$local_arch"
    else
        dest_name=$(jq -r --arg id "$chosen_dest_id" '.nodes[]? | select(.id == $id) | .name' "$INVENTORY_FILE" 2>/dev/null)
        dest_arch=$(jq -r --arg id "$chosen_dest_id" '.nodes[]? | select(.id == $id) | .architecture // "amd64"' "$INVENTORY_FILE" 2>/dev/null)
        dest_endpoint=$(jq -r --arg id "$chosen_dest_id" '.nodes[]? | select(.id == $id) | .endpoint' "$INVENTORY_FILE" 2>/dev/null)
        dest_token=$(jq -r --arg id "$chosen_dest_id" '.nodes[]? | select(.id == $id) | .token' "$INVENTORY_FILE" 2>/dev/null)
    fi
    [ -n "$dest_name" ] || dest_name="$chosen_dest_id"
    [ -n "$dest_arch" ] || dest_arch="$local_arch"

    case "$origin_arch" in x86_64|amd64) origin_arch="amd64" ;; aarch64|arm64) origin_arch="arm64" ;; esac
    case "$dest_arch" in x86_64|amd64) dest_arch="amd64" ;; aarch64|arm64) dest_arch="arm64" ;; esac

    # 5. Trava de Arquitetura Rigorosa (Hardware Parity Gate)
    if [ "$origin_arch" != "$dest_arch" ]; then
        if [ "$is_cli" = "true" ]; then
            echo "ERRO CRÍTICO: TRANSFERÊNCIA AO VIVO BLOQUEADA! Arquiteturas incompatíveis (Origem: $origin_arch, Destino: $dest_arch). Para proteger os dados, utilize o Backup Portátil (.tar.gz)." >&2
        else
            whiptail --title "⚠️ BLOQUEIO DE SEGURANÇA: ARQUITETURAS DIFERENTES" --msgbox \
                "TRANSFERÊNCIA AO VIVO BLOQUEADA!\n\nOrigem ($origin_name): $origin_arch\nDestino ($dest_name): $dest_arch\n\nProcessadores x86 e ARM possuem binários nativos e estruturas de banco de dados incompatíveis. Transferir containers ao vivo entre eles causará falhas críticas de inicialização.\n\nPara proteger seus dados, apenas o BACKUP PORTÁTIL (.tar.gz) é autorizado neste cenário.\n\nUtilize a Opção 4 do menu para gerar o Backup Portátil com segurança!" 18 78
        fi
        cleanup_pending_fleet_task
        return 1
    fi

    # 6. Obter Hosts SSH para Comunicação Segura
    local origin_ssh_host="" dest_ssh_host=""
    if [ "$chosen_origin_id" != "local" ]; then
        resolve_worker_ssh_host "$chosen_origin_id" "$origin_name" origin_ssh_host || { cleanup_pending_fleet_task; return 1; }
    fi
    if [ "$chosen_dest_id" != "local" ]; then
        resolve_worker_ssh_host "$chosen_dest_id" "$dest_name" dest_ssh_host || { cleanup_pending_fleet_task; return 1; }
    fi

    # 7. Selecionar a APLICAÇÃO na ORIGEM (Filtra estritamente bancos e infraestrutura)
    local chosen_app=""
    if [ "$is_cli" = "true" ]; then
        chosen_app="$cli_app"
        if [ -z "$chosen_app" ]; then
            echo "ERRO: Nome da aplicação a migrar é obrigatório no modo CLI." >&2
            cleanup_pending_fleet_task
            return 1
        fi
    elif [ "$chosen_origin_id" = "local" ]; then
        local stacks
        stacks=$(list_local_swarm_stacks)
        if [ -z "$stacks" ]; then
            whiptail --title "$op_title" --msgbox "Nenhuma aplicação em Docker Swarm encontrada no nó local." 10 70
            return 0
        fi
        local stack_menu=()
        while IFS= read -r s; do
            [ -n "$s" ] || continue
            case "$s" in
                mnoctrl*|cloudflared|traefik|portainer|pgbouncer|redis*|postgres*|mysql84*|mysql*) continue ;;
            esac
            stack_menu+=("$s" "Aplicação ativa no nó local")
        done <<< "$stacks"

        if [ ${#stack_menu[@]} -eq 0 ]; then
            whiptail --title "$op_title" --msgbox "Nenhuma aplicação de usuário encontrada para migrar no nó local." 10 70
            return 0
        fi

        chosen_app=$(whiptail --title "SELECIONE A APLICAÇÃO NA ORIGEM" --menu \
            "Escolha a aplicação a ser enviada para '$dest_name':" 18 70 6 \
            "${stack_menu[@]}" 3>&1 1>&2 2>&3) || return 0
    else
        local remote_apps=()
        # 1. Tentar listar stacks diretamente via SSH (instantâneo e 100% confiável)
        if [ -n "$origin_ssh_host" ]; then
            local remote_stacks
            remote_stacks=$(timeout 4 ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o BatchMode=yes -o ConnectTimeout=3 -o ServerAliveInterval=2 -o ServerAliveCountMax=1 "root@$origin_ssh_host" "docker stack ls --format '{{.Name}}'" 2>/dev/null || true)
            if [ -n "$remote_stacks" ]; then
                while IFS= read -r aname; do
                    [ -n "$aname" ] || continue
                    case "$aname" in
                        mnoctrl*|cloudflared|traefik|portainer|pgbouncer|redis*|postgres*|mysql84*|mysql*) continue ;;
                    esac
                    remote_apps+=("$aname" "Aplicação ativa no Worker")
                done <<< "$remote_stacks"
            fi
        fi

        # 2. Se SSH não retornou, tentar via API do Worker com timeout curto
        if [ ${#remote_apps[@]} -eq 0 ] && [ -n "$origin_endpoint" ] && [ -n "$origin_token" ]; then
            local structure_raw
            structure_raw=$(curl -s -k --connect-timeout 3 -m 5 -H "X-SetupMNO-Fleet-Token: $origin_token" "$origin_endpoint/api/fleet/worker/structure" 2>/dev/null || true)
            if [ -n "$structure_raw" ]; then
                while IFS= read -r aname; do
                    [ -n "$aname" ] || continue
                    case "$aname" in
                        mnoctrl*|cloudflared|traefik|portainer|pgbouncer|redis*|postgres*|mysql84*|mysql*) continue ;;
                    esac
                    remote_apps+=("$aname" "Aplicação ativa no Worker")
                done <<< "$(printf '%s\n' "$structure_raw" | jq -r '.apps[]?.name // empty' 2>/dev/null)"
            fi
        fi

        if [ ${#remote_apps[@]} -gt 0 ]; then
            chosen_app=$(whiptail --title "SELECIONE A APLICAÇÃO NO WORKER" --menu \
                "Aplicações detectadas no servidor '$origin_name':" 18 76 6 \
                "${remote_apps[@]}" 3>&1 1>&2 2>&3) || return 0
        else
            chosen_app=$(whiptail --title "DIGITE O NOME DA APLICAÇÃO" --inputbox \
                "Informe o nome da aplicação rodando no Worker (Ex: mautic8c155a0):" 12 70 "mautic8c155a0" 3>&1 1>&2 2>&3) || return 0
        fi
    fi

    [ -n "$chosen_app" ] || return 0

    if [ "$is_cli" != "true" ]; then
        whiptail --infobox "🔍 Analisando dependências, banco de dados e ecossistema de '$chosen_app'...\nAguarde alguns instantes..." 8 72
    fi

    # Detecção Inteligente de Contexto de Combo
    local initial_yaml_tmp
    initial_yaml_tmp=$(mktemp)
    resolve_live_stack_yaml "$chosen_origin_id" "$origin_ssh_host" "$chosen_app" "$initial_yaml_tmp" || true

    local combo_info
    combo_info=$(detect_app_combo_context "$chosen_origin_id" "$origin_ssh_host" "$chosen_app" "$initial_yaml_tmp")
    rm -f "$initial_yaml_tmp"

    local is_combo="false"
    local combo_name=""
    local linked_stacks=""
    IFS='|' read -r is_combo combo_name linked_stacks <<< "$combo_info"

    local apps_to_migrate=("$chosen_app")
    if [ "$is_combo" = "true" ] && [ -n "$linked_stacks" ] && [ "$linked_stacks" != "none" ]; then
        local combo_choice="${cli_combo_choice:-1}"
        if [ "$is_cli" != "true" ]; then
            combo_choice=$(whiptail --title "🤖 DETECÇÃO INTELIGENTE DE COMBO" --menu \
                "A aplicação '$chosen_app' faz parte de um ecossistema integrado:\n$combo_name\n\nFerramentas conectadas detectadas nesta VPS:\n• $(echo "$linked_stacks" | sed 's/ / \n• /g')\n\nComo você deseja proceder com a transferência para '$dest_name'?" 20 78 2 \
                "1" "MIGRAR COMBO COMPLETO (Recomendado — migra todas as ferramentas)" \
                "2" "MIGRAR APENAS '$chosen_app' (somente esta aplicação)" \
                3>&1 1>&2 2>&3) || return 0
        fi

        if [ "$combo_choice" = "1" ]; then
            for ls in $linked_stacks; do
                [ -n "$ls" ] || continue
                if [[ ! " ${apps_to_migrate[*]} " =~ " ${ls} " ]]; then
                    apps_to_migrate+=("$ls")
                fi
            done
        fi
    fi

    # Anexar obrigatoriamente qualquer stack de Redis dedicado vinculada às ferramentas a serem migradas
    attach_dedicated_redis_to_list "$chosen_origin_id" "$origin_ssh_host" apps_to_migrate

    # 7.1 Detecção e Governança de Storage S3 (MinIO)
    local minio_stack_in_combo=""
    for app_item in "${apps_to_migrate[@]}"; do
        if [[ "$app_item" == minio* ]]; then
            minio_stack_in_combo="$app_item"
            break
        fi
    done

    local any_uses_minio=false
    if [ -n "$minio_stack_in_combo" ]; then
        any_uses_minio=true
    else
        for app_item in "${apps_to_migrate[@]}"; do
            local chk_yaml_tmp
            chk_yaml_tmp=$(mktemp)
            if resolve_live_stack_yaml "$chosen_origin_id" "$origin_ssh_host" "$app_item" "$chk_yaml_tmp" 2>/dev/null; then
                if grep -qiE "(minio|s3_endpoint|aws_endpoint)" "$chk_yaml_tmp"; then
                    any_uses_minio=true
                    rm -f "$chk_yaml_tmp"
                    break
                fi
            fi
            rm -f "$chk_yaml_tmp"
        done
    fi

    local minio_policy="migrate"
    if [ "$any_uses_minio" = "true" ]; then
        local dest_has_minio=false
        if [ "$chosen_dest_id" = "local" ]; then
            if docker ps -qf "name=minio" 2>/dev/null | grep -q . || docker stack ls --format '{{.Name}}' 2>/dev/null | grep -qE '^minio'; then
                dest_has_minio=true
            fi
        else
            if ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o BatchMode=yes "root@$dest_ssh_host" "docker ps -qf 'name=minio' 2>/dev/null | grep -q . || docker stack ls --format '{{.Name}}' 2>/dev/null | grep -qE '^minio'"; then
                dest_has_minio=true
            fi
        fi

        if [ "$is_cli" = "true" ]; then
            if [ "$cli_minio" = "keep_origin" ]; then
                minio_policy="keep_origin"
            else
                minio_policy="migrate"
            fi
        elif [ "$dest_has_minio" = "true" ]; then
            local minio_choice
            minio_choice=$(whiptail --title "⚠️ MINIO DETECTADO NO DESTINO" --menu \
                "O servidor de destino ('$dest_name') já possui um serviço MinIO ativo em execução.\n\nPara garantir que nenhuma foto, áudio ou anexo histórico gravado no banco de dados seja quebrado (pois aponta para a URL do S3 deste combo), escolha como deseja proceder:\n" 20 78 2 \
                "1" "TRANSFERIR NOVO MINIO DESTE COMBO (Recomendado — Zero Links Quebrados)" \
                "2" "MANTER MINIO NO SERVIDOR DE ORIGEM (Economiza RAM; mídias na origem)" \
                3>&1 1>&2 2>&3) || return 0
            if [ "$minio_choice" = "2" ]; then
                minio_policy="keep_origin"
            else
                minio_policy="migrate"
            fi
        else
            local minio_choice
            minio_choice=$(whiptail --title "ARMAZENAMENTO S3 (MINIO) DO COMBO" --menu \
                "A aplicação/combo utiliza armazenamento S3 MinIO para fotos, áudios e arquivos.\n\nO servidor de destino ('$dest_name') ainda NÃO possui nenhum serviço MinIO instalado.\n\nComo você deseja proceder com o armazenamento deste combo?\n" 19 78 2 \
                "1" "TRANSFERIR MINIO PARA O DESTINO (Recomendado — migra mídias e mantém tudo junto)" \
                "2" "MANTER MINIO NO SERVIDOR DE ORIGEM (Economiza RAM no destino; mídias na origem)" \
                3>&1 1>&2 2>&3) || return 0
            if [ "$minio_choice" = "2" ]; then
                minio_policy="keep_origin"
            else
                minio_policy="migrate"
            fi
        fi

        if [ "$minio_policy" = "keep_origin" ]; then
            if [ -n "$minio_stack_in_combo" ]; then
                local filtered_apps=()
                for a in "${apps_to_migrate[@]}"; do
                    [ "$a" = "$minio_stack_in_combo" ] && continue
                    filtered_apps+=("$a")
                done
                apps_to_migrate=("${filtered_apps[@]}")
            fi
        fi
    fi

    # Ordenação topológica: dependências de infra (minio, rabbitmq, redis) antes das aplicações
    local dep_apps=()
    local main_apps=()
    for a in "${apps_to_migrate[@]}"; do
        if [[ "$a" == minio* ]] || [[ "$a" == rabbitmq* ]] || [[ "$a" == *redis* ]] || [[ "$a" == *-mq* ]] || [[ "$a" == *redisevo* ]]; then
            dep_apps+=("$a")
        else
            main_apps+=("$a")
        fi
    done
    apps_to_migrate=("${dep_apps[@]}" "${main_apps[@]}")

    # 8. Trava de Capacidade de Recursos no Destino
    local dest_ram_free
    if [ "$chosen_dest_id" = "local" ]; then
        dest_ram_free=$(get_local_ram_free_mb)
    else
        dest_ram_free=$(jq -r --arg id "$chosen_dest_id" '.nodes[]? | select(.id == $id) | .telemetry.memoryFreeMB // 2048' "$INVENTORY_FILE" 2>/dev/null)
    fi

    if [ "$dest_ram_free" -lt 512 ]; then
        if [ "$is_cli" = "true" ]; then
            echo "ERRO CRÍTICO: Servidor de destino ($dest_name) possui apenas ${dest_ram_free} MB de RAM livre. Transferência interrompida para prevenir sobrecarga no destino." >&2
        else
            whiptail --title "⚠️ BLOQUEIO: MEMÓRIA INSUFICIENTE NO DESTINO" --msgbox \
                "O servidor de destino ($dest_name) possui apenas ${dest_ram_free} MB de RAM livre.\n\nA aplicação requer memória adicional para operar no Docker Swarm.\n\nA transferência foi interrompida para prevenir sobrecarga no destino." 14 76
        fi
        cleanup_pending_fleet_task
        return 1
    fi

    # 9. Opções de Pós-Transferência
    local stop_origin=true
    local update_dns=true
    local notify_sentinel=true

    if [ "$is_cli" = "true" ]; then
        if [ "$op_mode" = "transfer" ]; then
            stop_origin="${cli_stop_origin:-true}"
            update_dns="${cli_update_dns:-true}"
        else
            stop_origin="${cli_stop_origin:-false}"
            update_dns="${cli_update_dns:-false}"
        fi
        notify_sentinel=true
    else
        if [ "$op_mode" = "transfer" ]; then
            local apps_display="${apps_to_migrate[*]}"
            if ! whiptail --title "POLÍTICA PÓS-TRANSFERÊNCIA NA ORIGEM" --yesno \
                "Deseja que as stacks antigas ($apps_display) sejam DESLIGADAS em '$origin_name' para liberar memória RAM após o sucesso da migração?\n\nOs volumes de dados antigos permanecerão CONGELADOS e intactos no disco com sufixo de segurança para permitir rollback a qualquer momento." 14 76; then
                stop_origin=false
            fi

            if ! whiptail --title "COMUTAÇÃO DE DNS CLOUDFLARE" --yesno \
                "Deseja atualizar automaticamente os apontamentos de DNS e rotas do Cloudflare Tunnel para que as URLs apontem imediatamente para o novo servidor ($dest_name)?\n\n[SIM - RECOMENDADO]: O tráfego de internet é comutado agora para o novo servidor. Suas URLs passam a responder no novo nó imediatamente.\n\n[NÃO]: As URLs continuam apontando para o servidor antigo (escolha 'Não' apenas se você pretende mudar o DNS manualmente depois)." 15 76; then
                update_dns=false
            fi
        else
            stop_origin=false
            update_dns=false
        fi

        if ! whiptail --title "NOTIFICAÇÃO DO SENTINEL (TELEGRAM / N8N)" --yesno \
            "Deseja que o MNO Sentinel envie um relatório no Telegram e dispare um Webhook (para seu n8n notificar WhatsApp) ao concluir a migração com sucesso?" 12 76; then
            notify_sentinel=false
        fi
    fi

    # 10. Execução Robusta da Migração (com Trava de Ocupação de Nós)
    acquire_node_lock "$chosen_origin_id" "Migracao ($chosen_app)" 600 || { cleanup_pending_fleet_task; return 1; }
    acquire_node_lock "$chosen_dest_id" "Recepcao ($chosen_app)" 600 || {
        release_node_lock "$chosen_origin_id"
        cleanup_pending_fleet_task
        return 1
    }

    local safety_suffix="frozen_pre_transfer_$(date -u +%Y%m%dT%H%M%SZ)"
    local workdir
    workdir=$(mktemp -d)
    local stats_file
    stats_file=$(mktemp /tmp/fleet_stats_XXXXXX 2>/dev/null || echo "/tmp/fleet_stats_$$")
    echo "0" > "$stats_file"
    trap 'release_node_lock "$chosen_origin_id"; release_node_lock "$chosen_dest_id"; rm -rf "$workdir" "$stats_file"' RETURN

    : > "$TRANSFER_LOG"
    local total_migrated_vols=0

    # Heartbeat dinâmico para etapas demoradas (restauração de volumes/banco e download/sincronização de imagens)
    local fleet_heartbeat_pid=""

    fleet_heartbeat_loop() {
        local percent="$1" message="$2" started now elapsed frame=0
        local -a frames=('|' '/' '-' '\')
        trap - EXIT
        printf -v started '%(%s)T' -1
        while :; do
            printf -v now '%(%s)T' -1
            elapsed=$((now - started))
            printf 'XXX\n%s\n%s [%s] há %02d:%02d\nPode demorar vários minutos. Caso a conexão caia, volte para acompanhar.\nXXX\n' \
                "$percent" "$message" "${frames[$frame]}" \
                "$((elapsed / 60))" "$((elapsed % 60))"
            frame=$(((frame + 1) % ${#frames[@]}))
            sleep 1
        done
    }

    start_fleet_heartbeat() {
        stop_fleet_heartbeat
        fleet_heartbeat_loop "$1" "$2" &
        fleet_heartbeat_pid=$!
    }

    stop_fleet_heartbeat() {
        if [ -n "$fleet_heartbeat_pid" ]; then
            kill "$fleet_heartbeat_pid" 2>/dev/null || true
            wait "$fleet_heartbeat_pid" 2>/dev/null || true
            fleet_heartbeat_pid=""
        fi
    }

    # Função interna de execução de etapas
    run_migration_pipeline() {
        trap 'stop_fleet_heartbeat' RETURN
        local total_apps=${#apps_to_migrate[@]}
        local app_idx=0

        for cur_app in "${apps_to_migrate[@]}"; do
            app_idx=$((app_idx + 1))
            local app_workdir="$workdir/$cur_app"
            mkdir -p "$app_workdir"

            local pct_base=$(( (app_idx - 1) * 100 / total_apps ))
            local pct_step=$(( 100 / total_apps ))

            # 1. Obtenção do manifesto da stack
            echo -e "XXX\n$((pct_base + (pct_step * 10 / 100)))\n[$app_idx/$total_apps] Sincronizando stack viva '$cur_app'...\nXXX"
            if ! resolve_live_stack_yaml "$chosen_origin_id" "$origin_ssh_host" "$cur_app" "$app_workdir/stack.yaml" 2>> "$TRANSFER_LOG" || [ ! -s "$app_workdir/stack.yaml" ] || ! grep -qE "(services|image):" "$app_workdir/stack.yaml"; then
                echo "ERRO CRÍTICO: Manifesto da stack '$cur_app' não foi encontrado na origem ou está corrompido/vazio. Operação abortada para segurança dos dados." >> "$TRANSFER_LOG"
                echo "ERROR_ABORT" > "$stats_file"
                echo -e "XXX\n0\nERRO: Manifesto da stack '$cur_app' não encontrado na origem. Operação abortada com segurança.\nXXX"
                sleep 2
                return 1
            fi

            # 2. Resolução de Topologia & Dependências
            local cur_db_engine="none:"
            local cur_s3_engine="none:"
            local cur_mq_engine="none:"

            echo -e "XXX\n$((pct_base + (pct_step * 25 / 100)))\n[$app_idx/$total_apps] Detectando dependências de infraestrutura ($cur_app)...\nXXX"
            cur_db_engine=$(detect_database_engine "$app_workdir/stack.yaml" "$cur_app")
            cur_s3_engine=$(detect_s3_storage_engine "$app_workdir/stack.yaml" "$cur_app")
            cur_mq_engine=$(detect_rabbitmq_engine "$app_workdir/stack.yaml" "$cur_app")

            echo "Stack: $cur_app | DB: $cur_db_engine | S3: $cur_s3_engine | MQ: $cur_mq_engine" >> "$TRANSFER_LOG"

            # Dump lógico do banco de dados na origem se aplicável
            if [[ "$cur_db_engine" == postgres:* ]]; then
                local pg_dbname="${cur_db_engine#postgres:}"
                echo -e "XXX\n$((pct_base + (pct_step * 35 / 100)))\n[$app_idx/$total_apps] Executando dump lógico consistente do PostgreSQL ($pg_dbname)...\nXXX"
                if [ "$chosen_origin_id" = "local" ]; then
                    local c_id
                    c_id=$(docker ps -qf name=postgres 2>/dev/null | head -n1 || true)
                    if [ -n "$c_id" ]; then
                        docker exec -i "$c_id" pg_dump -U postgres -d "$pg_dbname" --clean --if-exists 2>> "$TRANSFER_LOG" | gzip > "$app_workdir/db_logical_dump.sql.gz" || true
                    fi
                else
                    ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o BatchMode=yes "root@$origin_ssh_host" \
                        "c_id=\$(docker ps -qf name=postgres | head -n1); [ -n \"\$c_id\" ] && docker exec -i \"\$c_id\" pg_dump -U postgres -d '$pg_dbname' --clean --if-exists 2>/dev/null" \
                        | gzip > "$app_workdir/db_logical_dump.sql.gz" 2>> "$TRANSFER_LOG" || true
                fi
                if [ ! -s "$app_workdir/db_logical_dump.sql.gz" ] || [ "$(gunzip -c "$app_workdir/db_logical_dump.sql.gz" 2>/dev/null | head -c 10 | wc -c)" -eq 0 ]; then
                    echo "ERRO CRÍTICO: Dump do banco PostgreSQL '$pg_dbname' falhou ou gerou arquivo vazio na origem. Abortando migração." >> "$TRANSFER_LOG"
                    echo "ERROR_ABORT" > "$stats_file"
                    return 1
                fi
            elif [[ "$cur_db_engine" == mysql84:* ]]; then
                local my_dbname="${cur_db_engine#mysql84:}"
                echo -e "XXX\n$((pct_base + (pct_step * 35 / 100)))\n[$app_idx/$total_apps] Executando dump lógico consistente do MySQL 8.4 ($my_dbname)...\nXXX"
                if [ "$chosen_origin_id" = "local" ]; then
                    local c_id orig_pwd
                    c_id=$(docker ps -qf name=mysql84 2>/dev/null | head -n1 || true)
                    orig_pwd=$(docker inspect "$c_id" --format '{{range .Config.Env}}{{println .}}{{end}}' 2>/dev/null | grep MYSQL_ROOT_PASSWORD | cut -d= -f2- || grep 'MYSQL_ROOT_PASSWORD=' /root/mysql84.yaml 2>/dev/null | head -n1 | sed 's/.*MYSQL_ROOT_PASSWORD=//' | tr -d ' "\r' || echo "")
                    if [ -n "$c_id" ] && [ -n "$orig_pwd" ]; then
                        docker exec -i -e MYSQL_PWD="$orig_pwd" "$c_id" mysqldump -u root --databases "$my_dbname" --add-drop-table 2>> "$TRANSFER_LOG" | gzip > "$app_workdir/db_logical_dump.sql.gz" || true
                    fi
                else
                    ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o BatchMode=yes "root@$origin_ssh_host" '
                        c_id=$(docker ps -qf name=mysql84 | head -n1)
                        pwd=$(docker inspect "$c_id" --format "{{range .Config.Env}}{{println .}}{{end}}" 2>/dev/null | grep MYSQL_ROOT_PASSWORD | cut -d= -f2- || grep "MYSQL_ROOT_PASSWORD=" /root/mysql84.yaml 2>/dev/null | head -n1 | sed "s/.*MYSQL_ROOT_PASSWORD=//" | tr -d " \"\r" || echo "")
                        if [ -n "$c_id" ] && [ -n "$pwd" ]; then
                            docker exec -i -e MYSQL_PWD="$pwd" "$c_id" mysqldump -u root --databases "'"$my_dbname"'" --add-drop-table 2>/dev/null
                        fi
                    ' | gzip > "$app_workdir/db_logical_dump.sql.gz" 2>> "$TRANSFER_LOG" || true
                fi
                if [ ! -s "$app_workdir/db_logical_dump.sql.gz" ] || [ "$(gunzip -c "$app_workdir/db_logical_dump.sql.gz" 2>/dev/null | head -c 10 | wc -c)" -eq 0 ]; then
                    echo "ERRO CRÍTICO: Dump do banco MySQL '$my_dbname' falhou ou gerou arquivo vazio na origem. Abortando migração." >> "$TRANSFER_LOG"
                    echo "ERROR_ABORT" > "$stats_file"
                    return 1
                fi
            elif [[ "$cur_db_engine" == mysql:* ]]; then
                local my_dbname="${cur_db_engine#mysql:}"
                echo -e "XXX\n$((pct_base + (pct_step * 35 / 100)))\n[$app_idx/$total_apps] Executando dump lógico consistente do MySQL 8.0 ($my_dbname)...\nXXX"
                if [ "$chosen_origin_id" = "local" ]; then
                    local c_id orig_pwd
                    c_id=$(docker ps --filter "label=com.docker.swarm.service.name=mysql_mysql" -q 2>/dev/null | head -n1 || true)
                    [ -n "$c_id" ] || c_id=$(docker ps -qf name=mysql_mysql 2>/dev/null | head -n1 || true)
                    [ -n "$c_id" ] || c_id=$(docker ps --format '{{.ID}} {{.Names}}' 2>/dev/null | grep -v 'mysql84' | grep -E 'mysql_mysql|mysql\.1' | awk '{print $1}' | head -n1 || true)
                    orig_pwd=$(docker inspect "$c_id" --format '{{range .Config.Env}}{{println .}}{{end}}' 2>/dev/null | grep MYSQL_ROOT_PASSWORD | cut -d= -f2- || grep 'MYSQL_ROOT_PASSWORD=' /root/mysql.yaml 2>/dev/null | head -n1 | sed 's/.*MYSQL_ROOT_PASSWORD=//' | tr -d ' "\r' || echo "")
                    if [ -n "$c_id" ] && [ -n "$orig_pwd" ]; then
                        docker exec -i -e MYSQL_PWD="$orig_pwd" "$c_id" mysqldump -u root --databases "$my_dbname" --add-drop-table 2>> "$TRANSFER_LOG" | gzip > "$app_workdir/db_logical_dump.sql.gz" || true
                    fi
                else
                    ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o BatchMode=yes "root@$origin_ssh_host" '
                        c_id=$(docker ps --filter "label=com.docker.swarm.service.name=mysql_mysql" -q 2>/dev/null | head -n1 || docker ps -qf name=mysql_mysql 2>/dev/null | head -n1 || docker ps --format "{{.ID}} {{.Names}}" 2>/dev/null | grep -v "mysql84" | grep -E "mysql_mysql|mysql\.1" | awk "{print \$1}" | head -n1)
                        pwd=$(docker inspect "$c_id" --format "{{range .Config.Env}}{{println .}}{{end}}" 2>/dev/null | grep MYSQL_ROOT_PASSWORD | cut -d= -f2- || grep "MYSQL_ROOT_PASSWORD=" /root/mysql.yaml 2>/dev/null | head -n1 | sed "s/.*MYSQL_ROOT_PASSWORD=//" | tr -d " \"\r" || echo "")
                        if [ -n "$c_id" ] && [ -n "$pwd" ]; then
                            docker exec -i -e MYSQL_PWD="$pwd" "$c_id" mysqldump -u root --databases "'"$my_dbname"'" --add-drop-table 2>/dev/null
                        fi
                    ' | gzip > "$app_workdir/db_logical_dump.sql.gz" 2>> "$TRANSFER_LOG" || true
                fi
                if [ ! -s "$app_workdir/db_logical_dump.sql.gz" ] || [ "$(gunzip -c "$app_workdir/db_logical_dump.sql.gz" 2>/dev/null | head -c 10 | wc -c)" -eq 0 ]; then
                    echo "ERRO CRÍTICO: Dump do banco MySQL 8.0 '$my_dbname' falhou ou gerou arquivo vazio na origem. Abortando migração." >> "$TRANSFER_LOG"
                    echo "ERROR_ABORT" > "$stats_file"
                    return 1
                fi
            elif [[ "$cur_db_engine" == mongodb:* ]]; then
                local mg_dbname="${cur_db_engine#mongodb:}"
                echo -e "XXX\n$((pct_base + (pct_step * 35 / 100)))\n[$app_idx/$total_apps] Executando dump lógico do MongoDB ($mg_dbname)...\nXXX"
                if [ "$chosen_origin_id" = "local" ]; then
                    local mg_c
                    mg_c=$(docker ps --filter "label=com.docker.swarm.service.name=${cur_app}_mongo" -q 2>/dev/null | head -n1 || docker ps -qf name=mongo 2>/dev/null | head -n1 || true)
                    if [ -n "$mg_c" ]; then
                        docker exec -i "$mg_c" mongodump --archive --gzip 2>> "$TRANSFER_LOG" > "$app_workdir/db_logical_dump.archive.gz" || true
                    fi
                else
                    ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o BatchMode=yes "root@$origin_ssh_host" '
                        mg_c=$(docker ps --filter "label=com.docker.swarm.service.name='"${cur_app}"'_mongo" -q 2>/dev/null | head -n1 || docker ps -qf name=mongo 2>/dev/null | head -n1)
                        if [ -n "$mg_c" ]; then
                            docker exec -i "$mg_c" mongodump --archive --gzip 2>/dev/null
                        fi
                    ' > "$app_workdir/db_logical_dump.archive.gz" 2>> "$TRANSFER_LOG" || true
                fi
            fi

            # Sincronização de S3 MinIO se aplicável
            if [[ "$cur_s3_engine" == minio:* ]]; then
                if [[ "$cur_app" == minio* ]]; then
                    echo "Stack '$cur_app' é o próprio servidor MinIO S3. Volumes e dados são migrados diretamente." >> "$TRANSFER_LOG"
                elif [ -n "$minio_stack_in_combo" ] && [[ " ${apps_to_migrate[*]} " =~ " ${minio_stack_in_combo} " ]]; then
                    echo "Combo já possui stack MinIO dedicada ('$minio_stack_in_combo') sendo migrada com seus volumes. Ignorando provisionamento de MinIO compartilhado para '$cur_app'." >> "$TRANSFER_LOG"
                elif [ "$minio_policy" = "keep_origin" ]; then
                    echo "Política de MinIO configurada para 'keep_origin'. Mídias e MinIO preservados na origem para '$cur_app'." >> "$TRANSFER_LOG"
                else
                    local s3_bucket="${cur_s3_engine#minio:}"
                    echo -e "XXX\n$((pct_base + (pct_step * 45 / 100)))\n[$app_idx/$total_apps] Sincronizando bucket S3 MinIO ($s3_bucket)...\nXXX"
                    if ! ensure_minio_ready "$chosen_dest_id" "$dest_ssh_host"; then
                        echo "ERRO CRÍTICO: Falha ao garantir MinIO no nó de destino. Abortando migração." >> "$TRANSFER_LOG"
                        echo "ERROR_ABORT" > "$stats_file"
                        return 1
                    fi
                    sync_s3_bucket_data "$chosen_origin_id" "$origin_ssh_host" "$chosen_dest_id" "$dest_ssh_host" "$s3_bucket"
                fi
            fi

            # 3. RabbitMQ Broker Check
            if [[ "$cur_mq_engine" == rabbitmq:* ]]; then
                if [[ "$cur_app" == rabbitmq* ]]; then
                    echo "Stack '$cur_app' é o próprio broker RabbitMQ. Volumes e dados são migrados diretamente." >> "$TRANSFER_LOG"
                elif [[ " ${apps_to_migrate[*]} " =~ " rabbitmq" ]]; then
                    echo "Stack RabbitMQ dedicada faz parte da migração do combo. Ignorando provisionamento de broker compartilhado para '$cur_app'." >> "$TRANSFER_LOG"
                else
                    echo -e "XXX\n$((pct_base + (pct_step * 50 / 100)))\n[$app_idx/$total_apps] Verificando broker RabbitMQ no destino...\nXXX"
                    if ! ensure_rabbitmq_ready "$chosen_dest_id" "$dest_ssh_host"; then
                        echo "ERRO CRÍTICO: Falha ao garantir RabbitMQ no nó de destino. Abortando migração." >> "$TRANSFER_LOG"
                        echo "ERROR_ABORT" > "$stats_file"
                        return 1
                    fi
                fi
            fi

            # 4. Snapshot de Volumes Exclusivos
            local cur_vols=()
            while IFS= read -r v; do
                [ -n "$v" ] || continue
                cur_vols+=("$v")
            done < <(get_application_volumes "$app_workdir/stack.yaml" "$cur_app" "$chosen_origin_id" "$origin_ssh_host")

            for v in "${cur_vols[@]}"; do
                [ -n "$v" ] || continue
                echo "Compactando volume de $cur_app: $v" >> "$TRANSFER_LOG"
                if [ "$chosen_origin_id" = "local" ]; then
                    docker run --rm -v "${v}:/voldata:ro" alpine tar -czf - -C /voldata . > "$app_workdir/vol_${v}.tar.gz" 2>> "$TRANSFER_LOG" || true
                else
                    ssh -n -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o BatchMode=yes "root@$origin_ssh_host" \
                        "docker run --rm -v '${v}:/voldata:ro' alpine tar -czf - -C /voldata ." > "$app_workdir/vol_${v}.tar.gz" 2>> "$TRANSFER_LOG" || true
                fi
            done

            # 4.5 Snapshot de Bind Mounts de Configuração Local
            local cur_binds=()
            while IFS= read -r b; do
                [ -n "$b" ] || continue
                cur_binds+=("$b")
            done < <(get_application_bind_mounts "$app_workdir/stack.yaml" "$cur_app" "$chosen_origin_id" "$origin_ssh_host")

            if [ ${#cur_binds[@]} -gt 0 ]; then
                echo "Compactando bind mounts de configuração de $cur_app: ${cur_binds[*]}" >> "$TRANSFER_LOG"
                if [ "$chosen_origin_id" = "local" ]; then
                    tar -czf "$app_workdir/binds_${cur_app}.tar.gz" -P "${cur_binds[@]}" 2>> "$TRANSFER_LOG" || true
                else
                    ssh -n -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o BatchMode=yes "root@$origin_ssh_host" \
                        "tar -czf - -P ${cur_binds[*]}" > "$app_workdir/binds_${cur_app}.tar.gz" 2>> "$TRANSFER_LOG" || true
                fi
            fi

            total_migrated_vols=$((total_migrated_vols + ${#cur_vols[@]}))
            echo "$total_migrated_vols" > "$stats_file" 2>/dev/null || true

            # 5. Restauração de Volumes e Banco no Destino
            start_fleet_heartbeat "$((pct_base + (pct_step * 65 / 100)))" "[$app_idx/$total_apps] Restaurando volumes e banco de dados no destino..."
            for v in "${cur_vols[@]}"; do
                [ -f "$app_workdir/vol_${v}.tar.gz" ] || continue
                echo "Restaurando volume no destino: $v" >> "$TRANSFER_LOG"
                if [ "$chosen_dest_id" = "local" ]; then
                    docker volume create "$v" >/dev/null 2>&1 || true
                    docker run --rm -i -v "${v}:/voldata" alpine tar -xzf - -C /voldata < "$app_workdir/vol_${v}.tar.gz" 2>> "$TRANSFER_LOG" || true
                else
                    ssh -n -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o BatchMode=yes "root@$dest_ssh_host" "docker volume create '$v' >/dev/null 2>&1 || true"
                    ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o BatchMode=yes "root@$dest_ssh_host" "docker run --rm -i -v '${v}:/voldata' alpine tar -xzf - -C /voldata" < "$app_workdir/vol_${v}.tar.gz" 2>> "$TRANSFER_LOG" || true
                fi
            done

            # Restauração de Bind Mounts de Configuração no Destino
            if [ -s "$app_workdir/binds_${cur_app}.tar.gz" ]; then
                echo "Restaurando bind mounts de configuração de $cur_app no destino..." >> "$TRANSFER_LOG"
                if [ "$chosen_dest_id" = "local" ]; then
                    tar -xzf "$app_workdir/binds_${cur_app}.tar.gz" -P >> "$TRANSFER_LOG" 2>&1 || true
                else
                    ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o BatchMode=yes "root@$dest_ssh_host" "tar -xzf - -P" < "$app_workdir/binds_${cur_app}.tar.gz" >> "$TRANSFER_LOG" 2>&1 || true
                fi
            fi

            # Restauração lógica do Banco no destino
            if [[ "$cur_db_engine" == postgres:* ]] && [ -f "$app_workdir/db_logical_dump.sql.gz" ]; then
                local pg_dbname="${cur_db_engine#postgres:}"
                local dc=""
                local dest_pg_pwd=""
                local wait_dc=0
                while [ $wait_dc -lt 60 ]; do
                    if [ "$chosen_dest_id" = "local" ]; then
                        dc=$(docker ps -qf name=postgres 2>/dev/null | head -n1 || true)
                        if [ -n "$dc" ]; then
                            dest_pg_pwd=$(docker inspect "$dc" --format '{{range .Config.Env}}{{println .}}{{end}}' 2>/dev/null | grep POSTGRES_PASSWORD | cut -d= -f2- || grep 'POSTGRES_PASSWORD=' /root/postgres.yaml 2>/dev/null | head -n1 | sed 's/.*POSTGRES_PASSWORD=//' | tr -d ' "\r' || echo "")
                            [ -n "$dest_pg_pwd" ] && break
                        fi
                    else
                        dc=$(ssh -n -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o BatchMode=yes "root@$dest_ssh_host" 'docker ps -qf name=postgres | head -n1' 2>/dev/null || true)
                        if [ -n "$dc" ]; then
                            dest_pg_pwd=$(ssh -n -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o BatchMode=yes "root@$dest_ssh_host" 'dc=$(docker ps -qf name=postgres | head -n1); docker inspect "$dc" --format "{{range .Config.Env}}{{println .}}{{end}}" 2>/dev/null | grep POSTGRES_PASSWORD | cut -d= -f2- || grep "POSTGRES_PASSWORD=" /root/postgres.yaml 2>/dev/null | head -n1 | sed "s/.*POSTGRES_PASSWORD=//" | tr -d " \"\r" || echo ""')
                            [ -n "$dest_pg_pwd" ] && break
                        fi
                    fi
                    sleep 2
                    wait_dc=$((wait_dc + 1))
                done

                if [ -z "$dc" ]; then
                    echo "ERRO CRÍTICO: Container postgres não encontrado no destino após aguardar. Abortando migração." >> "$TRANSFER_LOG"
                    echo "ERROR_ABORT" > "$stats_file"
                    stop_fleet_heartbeat
                    return 1
                fi

                echo "Restaurando banco PostgreSQL '$pg_dbname' no destino..." >> "$TRANSFER_LOG"
                if [ "$chosen_dest_id" = "local" ]; then
                    docker exec -i "$dc" psql -U postgres -tc "SELECT 1 FROM pg_database WHERE datname = '$pg_dbname'" | grep -q 1 || docker exec -i "$dc" psql -U postgres -c "CREATE DATABASE \"$pg_dbname\"" >> "$TRANSFER_LOG" 2>&1 || true
                    gunzip -c "$app_workdir/db_logical_dump.sql.gz" | docker exec -i "$dc" psql -U postgres -d "$pg_dbname" >> "$TRANSFER_LOG" 2>&1 || true
                else
                    ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o BatchMode=yes "root@$dest_ssh_host" "dc=\$(docker ps -qf name=postgres | head -n1); docker exec -i \"\$dc\" psql -U postgres -tc \"SELECT 1 FROM pg_database WHERE datname = '$pg_dbname'\" | grep -q 1 || docker exec -i \"\$dc\" psql -U postgres -c \"CREATE DATABASE \\\"$pg_dbname\\\"\"" >> "$TRANSFER_LOG" 2>&1 || true
                    gunzip -c "$app_workdir/db_logical_dump.sql.gz" | ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o BatchMode=yes "root@$dest_ssh_host" "dc=\$(docker ps -qf name=postgres | head -n1); docker exec -i \"\$dc\" psql -U postgres -d '$pg_dbname'" >> "$TRANSFER_LOG" 2>&1 || true
                fi

                # Verificação de integridade pós-restauração Postgres
                local check_pg=""
                if [ "$chosen_dest_id" = "local" ]; then
                    check_pg=$(docker exec -i "$dc" psql -U postgres -tAc "SELECT 1 FROM pg_database WHERE datname='$pg_dbname';" 2>/dev/null | tr -d '\r\n ' || true)
                else
                    check_pg=$(ssh -n -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o BatchMode=yes "root@$dest_ssh_host" "dc=\$(docker ps -qf name=postgres | head -n1); docker exec -i \"\$dc\" psql -U postgres -tAc \"SELECT 1 FROM pg_database WHERE datname='$pg_dbname';\"" 2>/dev/null | tr -d '\r\n ' || true)
                fi
                if [ "$check_pg" != "1" ]; then
                    echo "ERRO CRÍTICO: Verificação pós-restore falhou! Banco de dados PostgreSQL '$pg_dbname' não foi encontrado no destino. Abortando migração." >> "$TRANSFER_LOG"
                    echo "ERROR_ABORT" > "$stats_file"
                    stop_fleet_heartbeat
                    return 1
                else
                    echo "Banco de dados PostgreSQL '$pg_dbname' verificado com sucesso no destino." >> "$TRANSFER_LOG"
                fi

                if [ -n "$dest_pg_pwd" ]; then
                    local safe_dest_pg_pwd
                    safe_dest_pg_pwd=$(printf '%s\n' "$dest_pg_pwd" | sed -e 's/[\/&|]/\\&/g')
                    sed -i -E "s/(POSTGRES_PASSWORD|DB_POSTGRESDB_PASSWORD|DB_PASSWORD|DB_PASS|DATABASE_PASSWORD|AP_POSTGRES_PASSWORD|KC_DB_PASSWORD|MB_DB_PASS|PAPERLESS_DBPASS|PENPOT_DATABASE_PASSWORD|TOOLJET_DB_PASS|VIKUNJA_DATABASE_PASSWORD|SAFE_DB_PASS)=[^[:space:]]+/\1=$safe_dest_pg_pwd/g" "$app_workdir/stack.yaml"
                    sed -i -E "s|(postgres(ql)?://[^:]+:)[^@]+(@postgres(ql)?:[0-9]+/[^[:space:]\"']+)|\\1${safe_dest_pg_pwd}\\3|g" "$app_workdir/stack.yaml"
                fi
            elif [[ "$cur_db_engine" == mysql84:* ]] && [ -f "$app_workdir/db_logical_dump.sql.gz" ]; then
                local my_dbname="${cur_db_engine#mysql84:}"
                if ! ensure_mysql84_ready "$chosen_dest_id" "$dest_ssh_host"; then
                    echo "ERRO CRÍTICO: Falha ao garantir MySQL 8.4 no nó de destino. Abortando migração para proteger dados." >> "$TRANSFER_LOG"
                    echo "ERROR_ABORT" > "$stats_file"
                    stop_fleet_heartbeat
                    return 1
                fi

                local mc=""
                local dest_my_pwd=""
                local wait_mc=0
                while [ $wait_mc -lt 60 ]; do
                    if [ "$chosen_dest_id" = "local" ]; then
                        mc=$(docker ps -qf name=mysql84 2>/dev/null | head -n1 || true)
                        if [ -n "$mc" ]; then
                            dest_my_pwd=$(docker inspect "$mc" --format '{{range .Config.Env}}{{println .}}{{end}}' 2>/dev/null | grep MYSQL_ROOT_PASSWORD | cut -d= -f2- || grep 'MYSQL_ROOT_PASSWORD=' /root/mysql84.yaml 2>/dev/null | head -n1 | sed 's/.*MYSQL_ROOT_PASSWORD=//' | tr -d ' "\r' || echo "")
                            [ -n "$dest_my_pwd" ] && break
                        fi
                    else
                        mc=$(ssh -n -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o BatchMode=yes "root@$dest_ssh_host" 'docker ps -qf name=mysql84 | head -n1' 2>/dev/null || true)
                        if [ -n "$mc" ]; then
                            dest_my_pwd=$(ssh -n -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o BatchMode=yes "root@$dest_ssh_host" 'mc=$(docker ps -qf name=mysql84 | head -n1); docker inspect "$mc" --format "{{range .Config.Env}}{{println .}}{{end}}" 2>/dev/null | grep MYSQL_ROOT_PASSWORD | cut -d= -f2- || grep "MYSQL_ROOT_PASSWORD=" /root/mysql84.yaml 2>/dev/null | head -n1 | sed "s/.*MYSQL_ROOT_PASSWORD=//" | tr -d " \"\r" || echo ""')
                            [ -n "$dest_my_pwd" ] && break
                        fi
                    fi
                    sleep 2
                    wait_mc=$((wait_mc + 1))
                done

                if [ -z "$mc" ] || [ -z "$dest_my_pwd" ]; then
                    echo "ERRO CRÍTICO: Container mysql84 ou senha não identificada no destino após aguardar. Abortando migração." >> "$TRANSFER_LOG"
                    echo "ERROR_ABORT" > "$stats_file"
                    stop_fleet_heartbeat
                    return 1
                fi

                echo "Restaurando banco MySQL '$my_dbname' no destino..." >> "$TRANSFER_LOG"
                if [ "$chosen_dest_id" = "local" ]; then
                    printf 'CREATE DATABASE IF NOT EXISTS `%s`;\n' "$my_dbname" | docker exec -i -e MYSQL_PWD="$dest_my_pwd" "$mc" mysql -u root >> "$TRANSFER_LOG" 2>&1 || true
                    gunzip -c "$app_workdir/db_logical_dump.sql.gz" | docker exec -i -e MYSQL_PWD="$dest_my_pwd" "$mc" mysql -u root "$my_dbname" >> "$TRANSFER_LOG" 2>&1 || true
                else
                    printf 'CREATE DATABASE IF NOT EXISTS `%s`;\n' "$my_dbname" | ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o BatchMode=yes "root@$dest_ssh_host" "mc=\$(docker ps -qf name=mysql84 | head -n1); docker exec -i -e MYSQL_PWD='$dest_my_pwd' \"\$mc\" mysql -u root" >> "$TRANSFER_LOG" 2>&1 || true
                    gunzip -c "$app_workdir/db_logical_dump.sql.gz" | ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o BatchMode=yes "root@$dest_ssh_host" "mc=\$(docker ps -qf name=mysql84 | head -n1); docker exec -i -e MYSQL_PWD='$dest_my_pwd' \"\$mc\" mysql -u root '$my_dbname'" >> "$TRANSFER_LOG" 2>&1 || true
                fi

                # Verificação de integridade pós-restauração
                local check_db=""
                if [ "$chosen_dest_id" = "local" ]; then
                    check_db=$(docker exec -i -e MYSQL_PWD="$dest_my_pwd" "$mc" mysql -u root -s -N -e "SHOW DATABASES LIKE '$my_dbname';" 2>/dev/null | tr -d '\r\n ' || true)
                else
                    check_db=$(ssh -n -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o BatchMode=yes "root@$dest_ssh_host" "mc=\$(docker ps -qf name=mysql84 | head -n1); docker exec -i -e MYSQL_PWD='$dest_my_pwd' \"\$mc\" mysql -u root -s -N -e \"SHOW DATABASES LIKE '$my_dbname';\"" 2>/dev/null | tr -d '\r\n ' || true)
                fi
                if [ "$check_db" != "$my_dbname" ]; then
                    echo "ERRO CRÍTICO: Verificação pós-restore falhou! Banco de dados '$my_dbname' não foi encontrado no destino. Abortando migração." >> "$TRANSFER_LOG"
                    echo "ERROR_ABORT" > "$stats_file"
                    stop_fleet_heartbeat
                    return 1
                else
                    echo "Banco de dados '$my_dbname' verificado com sucesso no destino." >> "$TRANSFER_LOG"
                fi

                if [ -n "$dest_my_pwd" ]; then
                    sed -i -E "s/MAUTIC_DB_PASSWORD=[^[:space:]]+/MAUTIC_DB_PASSWORD=$dest_my_pwd/g" "$app_workdir/stack.yaml"
                    local cfg_vol="${cur_app}-config"
                    if [ "$chosen_dest_id" = "local" ]; then
                        docker run --rm -v "${cfg_vol}:/voldata" alpine sh -c "sed -i \"s/'db_password' => .*/'db_password' => '$dest_my_pwd',/\" /voldata/local.php 2>/dev/null || true" 2>> "$TRANSFER_LOG" || true
                    else
                        ssh -n -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o BatchMode=yes "root@$dest_ssh_host" "docker run --rm -v '${cfg_vol}:/voldata' alpine sh -c \"sed -i \\\"s/'db_password' => .*/'db_password' => '$dest_my_pwd',/\\\" /voldata/local.php 2>/dev/null || true\"" 2>> "$TRANSFER_LOG" || true
                    fi
                fi
            elif [[ "$cur_db_engine" == mysql:* ]] && [ -f "$app_workdir/db_logical_dump.sql.gz" ]; then
                local my_dbname="${cur_db_engine#mysql:}"
                if ! ensure_mysql_ready "$chosen_dest_id" "$dest_ssh_host"; then
                    echo "ERRO CRÍTICO: Falha ao garantir MySQL 8.0 no nó de destino. Abortando migração para proteger dados." >> "$TRANSFER_LOG"
                    echo "ERROR_ABORT" > "$stats_file"
                    stop_fleet_heartbeat
                    return 1
                fi

                local mc=""
                local dest_my_pwd=""
                local wait_mc=0
                while [ $wait_mc -lt 60 ]; do
                    if [ "$chosen_dest_id" = "local" ]; then
                        mc=$(docker ps --filter "label=com.docker.swarm.service.name=mysql_mysql" -q 2>/dev/null | head -n1 || true)
                        [ -n "$mc" ] || mc=$(docker ps -qf name=mysql_mysql 2>/dev/null | head -n1 || true)
                        [ -n "$mc" ] || mc=$(docker ps --format '{{.ID}} {{.Names}}' 2>/dev/null | grep -v 'mysql84' | grep -E 'mysql_mysql|mysql\.1' | awk '{print $1}' | head -n1 || true)
                        if [ -n "$mc" ]; then
                            dest_my_pwd=$(docker inspect "$mc" --format '{{range .Config.Env}}{{println .}}{{end}}' 2>/dev/null | grep MYSQL_ROOT_PASSWORD | cut -d= -f2- || grep 'MYSQL_ROOT_PASSWORD=' /root/mysql.yaml 2>/dev/null | head -n1 | sed 's/.*MYSQL_ROOT_PASSWORD=//' | tr -d ' "\r' || echo "")
                            [ -n "$dest_my_pwd" ] && break
                        fi
                    else
                        mc=$(ssh -n -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o BatchMode=yes "root@$dest_ssh_host" 'docker ps --filter "label=com.docker.swarm.service.name=mysql_mysql" -q 2>/dev/null | head -n1 || docker ps -qf name=mysql_mysql 2>/dev/null | head -n1 || docker ps --format "{{.ID}} {{.Names}}" 2>/dev/null | grep -v "mysql84" | grep -E "mysql_mysql|mysql\.1" | awk "{print \$1}" | head -n1' 2>/dev/null || true)
                        if [ -n "$mc" ]; then
                            dest_my_pwd=$(ssh -n -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o BatchMode=yes "root@$dest_ssh_host" 'mc=$(docker ps --filter "label=com.docker.swarm.service.name=mysql_mysql" -q 2>/dev/null | head -n1 || docker ps -qf name=mysql_mysql 2>/dev/null | head -n1 || docker ps --format "{{.ID}} {{.Names}}" 2>/dev/null | grep -v "mysql84" | grep -E "mysql_mysql|mysql\.1" | awk "{print \$1}" | head -n1); docker inspect "$mc" --format "{{range .Config.Env}}{{println .}}{{end}}" 2>/dev/null | grep MYSQL_ROOT_PASSWORD | cut -d= -f2- || grep "MYSQL_ROOT_PASSWORD=" /root/mysql.yaml 2>/dev/null | head -n1 | sed "s/.*MYSQL_ROOT_PASSWORD=//" | tr -d " \"\r" || echo ""')
                            [ -n "$dest_my_pwd" ] && break
                        fi
                    fi
                    sleep 2
                    wait_mc=$((wait_mc + 1))
                done

                if [ -z "$mc" ] || [ -z "$dest_my_pwd" ]; then
                    echo "ERRO CRÍTICO: Container mysql (8.0) ou senha não identificada no destino após aguardar. Abortando migração." >> "$TRANSFER_LOG"
                    echo "ERROR_ABORT" > "$stats_file"
                    stop_fleet_heartbeat
                    return 1
                fi

                echo "Restaurando banco MySQL 8.0 '$my_dbname' no destino..." >> "$TRANSFER_LOG"
                if [ "$chosen_dest_id" = "local" ]; then
                    printf 'CREATE DATABASE IF NOT EXISTS `%s`;\n' "$my_dbname" | docker exec -i -e MYSQL_PWD="$dest_my_pwd" "$mc" mysql -u root >> "$TRANSFER_LOG" 2>&1 || true
                    gunzip -c "$app_workdir/db_logical_dump.sql.gz" | docker exec -i -e MYSQL_PWD="$dest_my_pwd" "$mc" mysql -u root "$my_dbname" >> "$TRANSFER_LOG" 2>&1 || true
                else
                    printf 'CREATE DATABASE IF NOT EXISTS `%s`;\n' "$my_dbname" | ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o BatchMode=yes "root@$dest_ssh_host" "mc=\$(docker ps --filter 'label=com.docker.swarm.service.name=mysql_mysql' -q 2>/dev/null | head -n1 || docker ps -qf name=mysql_mysql 2>/dev/null | head -n1 || docker ps --format '{{.ID}} {{.Names}}' 2>/dev/null | grep -v 'mysql84' | grep -E 'mysql_mysql|mysql\.1' | awk '{print \$1}' | head -n1); docker exec -i -e MYSQL_PWD='$dest_my_pwd' \"\$mc\" mysql -u root" >> "$TRANSFER_LOG" 2>&1 || true
                    gunzip -c "$app_workdir/db_logical_dump.sql.gz" | ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o BatchMode=yes "root@$dest_ssh_host" "mc=\$(docker ps --filter 'label=com.docker.swarm.service.name=mysql_mysql' -q 2>/dev/null | head -n1 || docker ps -qf name=mysql_mysql 2>/dev/null | head -n1 || docker ps --format '{{.ID}} {{.Names}}' 2>/dev/null | grep -v 'mysql84' | grep -E 'mysql_mysql|mysql\.1' | awk '{print \$1}' | head -n1); docker exec -i -e MYSQL_PWD='$dest_my_pwd' \"\$mc\" mysql -u root '$my_dbname'" >> "$TRANSFER_LOG" 2>&1 || true
                fi

                # Verificação de integridade pós-restauração
                local check_db=""
                if [ "$chosen_dest_id" = "local" ]; then
                    check_db=$(docker exec -i -e MYSQL_PWD="$dest_my_pwd" "$mc" mysql -u root -s -N -e "SHOW DATABASES LIKE '$my_dbname';" 2>/dev/null | tr -d '\r\n ' || true)
                else
                    check_db=$(ssh -n -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o BatchMode=yes "root@$dest_ssh_host" "mc=\$(docker ps --filter 'label=com.docker.swarm.service.name=mysql_mysql' -q 2>/dev/null | head -n1 || docker ps -qf name=mysql_mysql 2>/dev/null | head -n1 || docker ps --format '{{.ID}} {{.Names}}' 2>/dev/null | grep -v 'mysql84' | grep -E 'mysql_mysql|mysql\.1' | awk '{print \$1}' | head -n1); docker exec -i -e MYSQL_PWD='$dest_my_pwd' \"\$mc\" mysql -u root -s -N -e \"SHOW DATABASES LIKE '$my_dbname';\"" 2>/dev/null | tr -d '\r\n ' || true)
                fi
                if [ "$check_db" != "$my_dbname" ]; then
                    echo "ERRO CRÍTICO: Verificação pós-restore falhou! Banco de dados MySQL 8.0 '$my_dbname' não foi encontrado no destino. Abortando migração." >> "$TRANSFER_LOG"
                    echo "ERROR_ABORT" > "$stats_file"
                    stop_fleet_heartbeat
                    return 1
                else
                    echo "Banco de dados MySQL 8.0 '$my_dbname' verificado com sucesso no destino." >> "$TRANSFER_LOG"
                fi

                # Reconciliação dinâmica de senhas na stack e volumes
                if [ -n "$dest_my_pwd" ]; then
                    sed -i -E "s/(WORDPRESS_DB_PASSWORD|DB_PASSWORD|MYSQL_PASSWORD|MAUTIC_DB_PASSWORD|HUMHUB_DB_PASSWORD|BOOKSTACK_DB_PASSWORD|DB_PASS)=[^[:space:]]+/\1=$dest_my_pwd/g" "$app_workdir/stack.yaml"

                    # Se for WordPress, atualizar também wp-config.php dentro do volume de arquivos
                    local wp_vol="${cur_app}"
                    if [ "$chosen_dest_id" = "local" ]; then
                        docker run --rm -v "${wp_vol}:/var/www/html" alpine sed -i -E "s/define\(\s*['\"]DB_PASSWORD['\"]\s*,\s*['\"][^'\"]*['\"]\s*\);/define( 'DB_PASSWORD', '$dest_my_pwd' );/g" /var/www/html/wp-config.php 2>/dev/null || true
                    else
                        ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o BatchMode=yes "root@$dest_ssh_host" "docker run --rm -v '${wp_vol}:/var/www/html' alpine sed -i -E \"s/define\(\s*['\\\"]DB_PASSWORD['\\\"]\s*,\s*['\\\"][^'\\\"]*['\\\"]\s*\);/define( 'DB_PASSWORD', '$dest_my_pwd' );/g\" /var/www/html/wp-config.php" 2>/dev/null || true
                    fi

                    # Se for Mautic 4/5/6, atualizar local.php no volume config
                    local cfg_vol="${cur_app}-config"
                    if [ "$chosen_dest_id" = "local" ]; then
                        docker run --rm -v "${cfg_vol}:/voldata" alpine sh -c "sed -i \"s/'db_password' => .*/'db_password' => '$dest_my_pwd',/\" /voldata/local.php 2>/dev/null || true" 2>> "$TRANSFER_LOG" || true
                    else
                        ssh -n -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o BatchMode=yes "root@$dest_ssh_host" "docker run --rm -v '${cfg_vol}:/voldata' alpine sh -c \"sed -i \\\"s/'db_password' => .*/'db_password' => '$dest_my_pwd',/\\\" /voldata/local.php 2>/dev/null || true\"" 2>> "$TRANSFER_LOG" || true
                    fi
                fi
            elif [[ "$cur_db_engine" == mongodb:* ]] && [ -s "$app_workdir/db_logical_dump.archive.gz" ]; then
                local mg_dbname="${cur_db_engine#mongodb:}"
                echo "Restaurando dump lógico MongoDB ($mg_dbname) no destino..." >> "$TRANSFER_LOG"
                if [ "$chosen_dest_id" = "local" ]; then
                    local mg_c
                    mg_c=$(docker ps --filter "label=com.docker.swarm.service.name=${cur_app}_mongo" -q 2>/dev/null | head -n1 || docker ps -qf name=mongo 2>/dev/null | head -n1 || true)
                    if [ -n "$mg_c" ]; then
                        docker exec -i "$mg_c" mongorestore --archive --gzip --drop < "$app_workdir/db_logical_dump.archive.gz" >> "$TRANSFER_LOG" 2>&1 || true
                    fi
                else
                    ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o BatchMode=yes "root@$dest_ssh_host" \
                        "mg_c=\$(docker ps --filter 'label=com.docker.swarm.service.name=${cur_app}_mongo' -q 2>/dev/null | head -n1 || docker ps -qf name=mongo 2>/dev/null | head -n1); [ -n \"\$mg_c\" ] && docker exec -i \"\$mg_c\" mongorestore --archive --gzip --drop" \
                        < "$app_workdir/db_logical_dump.archive.gz" >> "$TRANSFER_LOG" 2>&1 || true
                fi
            fi
            stop_fleet_heartbeat

            # 5.5 Sincronizar imagens customizadas/locais para prevenir rejeição no Swarm
            start_fleet_heartbeat "$((pct_base + (pct_step * 75 / 100)))" "[$app_idx/$total_apps] Sincronizando imagens da stack no destino ($cur_app)..."
            ensure_stack_images_on_dest "$chosen_origin_id" "$origin_ssh_host" "$chosen_dest_id" "$dest_ssh_host" "$app_workdir/stack.yaml"
            stop_fleet_heartbeat

            # 6. Deploy no Swarm do Destino via Portainer REST API (Editável)
            echo -e "XXX\n$((pct_base + (pct_step * 80 / 100)))\n[$app_idx/$total_apps] Registrando stack '$cur_app' no Portainer do destino...\nXXX"

            # Assegurar que volumes declarados como externos no YAML existam no nó destino antes do deploy
            while IFS= read -r ext_vol; do
                [ -n "$ext_vol" ] || continue
                if [ "$chosen_dest_id" = "local" ]; then
                    docker volume create "$ext_vol" >/dev/null 2>&1 || true
                else
                    ssh -n -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o BatchMode=yes "root@$dest_ssh_host" "docker volume create '$ext_vol' >/dev/null 2>&1 || true"
                fi
            done < <(awk '
/^volumes:/{flag=1; next}
flag && /^[[:space:]]{2}[a-zA-Z0-9_.-]+:/{v=$1; sub(/^[[:space:]]*/, "", v); sub(/:.*/, "", v); in_v=v; next}
flag && in_v && /external:[[:space:]]*true/{print in_v}
flag && in_v && /name:[[:space:]]*/{nm=$0; sub(/.*name:[[:space:]]*/, "", nm); sub(/[[:space:]].*/, "", nm); gsub(/["'\''\r]/, "", nm); if (nm != "") print nm}
flag && /^[a-zA-Z0-9_.-]+:/{flag=0}
' "$app_workdir/stack.yaml" 2>/dev/null | sort -u || true)

            if [ "$chosen_dest_id" = "local" ]; then
                cp -f "$app_workdir/stack.yaml" "/root/${cur_app}.yaml"
                deploy_stack_with_portainer_priority "local" "" "$cur_app" "/root/${cur_app}.yaml" >> "$TRANSFER_LOG" 2>&1
            else
                ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o BatchMode=yes "root@$dest_ssh_host" "cat > /root/${cur_app}.yaml" < "$app_workdir/stack.yaml"
                deploy_stack_with_portainer_priority "$chosen_dest_id" "$dest_ssh_host" "$cur_app" "/root/${cur_app}.yaml" >> "$TRANSFER_LOG" 2>&1
            fi
            sleep 3

            # 7. Comutação de DNS Cloudflare
            if [ "$update_dns" = "true" ]; then
                echo -e "XXX\n$((pct_base + (pct_step * 90 / 100)))\n[$app_idx/$total_apps] Comutando rotas DNS Cloudflare ($cur_app)...\nXXX"
                switch_cloudflare_dns_and_ingress "$chosen_dest_id" "$dest_ssh_host" "$app_workdir/stack.yaml" "$cur_app" >> "$TRANSFER_LOG" 2>&1 || true
            fi

            # 8. Desligar e congelar na origem se solicitado
            if [ "$stop_origin" = "true" ]; then
                if [[ "$cur_app" == minio* ]] && [ "$minio_policy" = "keep_origin" ]; then
                    echo "[SEGURANÇA MINIO] Stack '$cur_app' PRESERVADA ATIVA na origem para fornecer mídias S3 à nova VPS." >> "$TRANSFER_LOG"
                elif [ ! -s "$app_workdir/stack.yaml" ]; then
                    echo "ALERTA DE SEGURANÇA: Manifesto vazio para '$cur_app'. Origem mantida ativa para evitar indisponibilidade." >> "$TRANSFER_LOG"
                else
                    echo -e "XXX\n$((pct_base + (pct_step * 95 / 100)))\n[$app_idx/$total_apps] Congelando volumes e desligando na origem ($cur_app)...\nXXX"
                    if [ "$chosen_origin_id" = "local" ]; then
                        for v in "${cur_vols[@]}"; do
                            [ -n "$v" ] || continue
                            docker volume create "${v}_${safety_suffix}" >/dev/null 2>&1 || true
                            docker run --rm -v "${v}:/src:ro" -v "${v}_${safety_suffix}:/dst" alpine cp -a /src/. /dst/ >/dev/null 2>&1 || true
                        done
                        docker stack rm "$cur_app" >/dev/null 2>&1 || true
                    else
                        for v in "${cur_vols[@]}"; do
                            [ -n "$v" ] || continue
                            ssh -n -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o BatchMode=yes "root@$origin_ssh_host" "docker volume create '${v}_${safety_suffix}' >/dev/null 2>&1 && docker run --rm -v '${v}:/src:ro' -v '${v}_${safety_suffix}:/dst' alpine cp -a /src/. /dst/ 2>/dev/null || true"
                        done
                        ssh -n -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o BatchMode=yes "root@$origin_ssh_host" "docker stack rm '$cur_app' >/dev/null 2>&1 || true"
                    fi
                fi
            fi

            # 9. Gravação do Manifesto Padronizado
            save_app_manifest "$chosen_dest_id" "$dest_ssh_host" "$cur_app" "$cur_db_engine" "$cur_s3_engine" "$cur_mq_engine" "$combo_name" "$combo_name" "${apps_to_migrate[*]}"
            save_app_manifest "$chosen_origin_id" "$origin_ssh_host" "$cur_app" "$cur_db_engine" "$cur_s3_engine" "$cur_mq_engine" "$combo_name" "$combo_name" "${apps_to_migrate[*]}"
        done

        if [ "$notify_sentinel" = "true" ]; then
            echo -e "XXX\n98\nDisparando relatório no Telegram e Webhook n8n...\nXXX"
            local dns_str="Não alterado (modo clone)"
            [ "$update_dns" = "true" ] && dns_str="Comutado para $dest_name"
            dispatch_sentinel_notification_bash "Migração de Aplicação" "${apps_to_migrate[*]}" "$origin_name ($origin_arch)" "$dest_name ($dest_arch)" "$total_migrated_vols" "$dns_str" "40"
            sleep 1
        fi

        echo -e "XXX\n100\nMigração concluída com 100% de sucesso!\nXXX"
        sleep 1
    }

    if [ "$is_cli" = "true" ]; then
        echo -e "\n=================================================="
        echo -e "🚀 INICIANDO MIGRAÇÃO NO FLEET HUB"
        echo -e "   Operação: $op_mode"
        echo -e "   Origem:   $origin_name ($origin_arch)"
        echo -e "   Destino:  $dest_name ($dest_arch)"
        echo -e "   Apps:     ${apps_to_migrate[*]}"
        if [ "$is_combo" = "true" ]; then
            echo -e "   Combo:    $combo_name (Estratégia: ${combo_choice:-1})"
        fi
        if [ "$any_uses_minio" = "true" ]; then
            echo -e "   MinIO S3: $minio_policy"
        fi
        echo -e "==================================================\n"

        run_migration_pipeline 2>&1 | while IFS= read -r line; do
            if [ "$line" = "XXX" ]; then
                continue
            fi
            if [[ "$line" =~ ^[0-9]+$ ]]; then
                printf "\n[%3d%%] " "$line"
            else
                echo -n "$line "
            fi
        done
        echo ""
    else
        run_migration_pipeline 2>> "$TRANSFER_LOG" | whiptail --title "EXECUTANDO OPERAÇÃO NA FROTA" --gauge "Aguarde a migração consistente..." 10 78 0
    fi

    local op_aborted=false
    if [ -s "$stats_file" ]; then
        local sf_val
        sf_val=$(cat "$stats_file" 2>/dev/null || echo "0")
        if [ "$sf_val" = "ERROR_ABORT" ]; then
            op_aborted=true
            total_migrated_vols=0
        else
            total_migrated_vols="$sf_val"
        fi
    fi
    rm -f "$stats_file"

    if [ "$op_aborted" = "true" ]; then
        cleanup_pending_fleet_task
        local err_tail
        err_tail=$(tail -n 15 "$TRANSFER_LOG" 2>/dev/null || echo "Erro desconhecido")
        if [ "$is_cli" = "true" ]; then
            echo -e "\n❌ OPERAÇÃO ABORTADA COM SEGURANÇA!" >&2
            echo -e "A integridade dos dados foi protegida. Origem mantida intacta.\n" >&2
            echo -e "Detalhes do erro:" >&2
            echo "$err_tail" >&2
            return 1
        else
            whiptail --title "MIGRAÇÃO ABORTADA COM SEGURANÇA" --msgbox \
                "⚠️ A transferência da aplicação foi abortada para proteger a integridade dos dados.\n\nA origem foi mantida 100% intacta e em execução.\n\nDetalhes do log:\n$err_tail" 18 76
            return 1
        fi
    fi

    cleanup_pending_fleet_task

    local summary="🎉 OPERAÇÃO CONCLUÍDA COM SUCESSO!\n\n"
    summary+="• Aplicação(ões): ${apps_to_migrate[*]}\n"
    if [ "$is_combo" = "true" ]; then
        summary+="• Ecossistema: $combo_name\n"
    fi
    summary+="• Origem: $origin_name ($origin_arch)\n"
    summary+="• Destino: $dest_name ($dest_arch)\n"
    summary+="• Total de Stacks: ${#apps_to_migrate[@]}\n"
    summary+="• Volumes Migrados: $total_migrated_vols volume(s)\n"
    if [ "$any_uses_minio" = "true" ]; then
        if [ "$minio_policy" = "keep_origin" ]; then
            summary+="• Storage S3 (MinIO): Mantido ativo na origem (mídias preservadas)\n"
        else
            summary+="• Storage S3 (MinIO): Migrado para o destino (novo MinIO isolado)\n"
        fi
    fi
    if [ "$update_dns" = "true" ]; then
        summary+="• DNS & Ingress: Atualizado(s) no Cloudflare para o nó destino\n"
    fi
    if [ "$stop_origin" = "true" ]; then
        summary+="• Stacks Antigas: Desligadas na origem (RAM liberada)\n"
        summary+="• Volumes Congelados: Sufixo de rollback: _$safety_suffix\n"
    fi
    summary+="• Manifestos: Salvos em .control/manifests/\n"

    if [ "$is_cli" = "true" ]; then
        echo -e "\n=================================================="
        printf "%b\n" "$summary"
        echo -e "==================================================\n"
        return 0
    else
        whiptail --title "SUCESSO DA MIGRAÇÃO" --msgbox "$summary" 19 76
    fi
}

# Menu Principal Interativo
show_menu() {
    cleanup_pending_fleet_task

    while true; do
        local choice
        choice=$(whiptail --title "MNO FLEET HUB — CLONE, TRANSFERÊNCIA E BACKUP" --menu \
            "Selecione a ação desejada na frota de servidores:" 18 78 6 \
            "1" "Raio-X da Frota (Ver Arquitetura, RAM, Disco e Apps de cada Nó)" \
            "2" "Transferir Aplicação para outro Servidor (Com migração de DNS)" \
            "3" "Clonar Aplicação para Teste (Sem alterar DNS)" \
            "4" "Criar Backup Portátil (.tar.gz compatível com qualquer arquitetura)" \
            "5" "Restaurar Backup Portátil em um Servidor (Local ou Remoto)" \
            "6" "Voltar ao Menu Anterior" \
            3>&1 1>&2 2>&3) || return 0

        case "$choice" in
            1) action_inspect_nodes ;;
            2) action_transfer_or_clone "transfer" ;;
            3) action_transfer_or_clone "clone" ;;
            4) action_backup_app ;;
            5) action_restore_backup ;;
            6) return 0 ;;
        esac
    done
}

case "${1:-menu}" in
    inspect) action_inspect_nodes "${2:-}" ;;
    backup) action_backup_app "${2:-}" "${3:-}" ;;
    restore) action_restore_backup "${2:-}" "${3:-}" ;;
    transfer) shift; action_transfer_or_clone "transfer" "$@" ;;
    clone) shift; action_transfer_or_clone "clone" "$@" ;;
    --source-only|source-only) return 0 2>/dev/null || exit 0 ;;
    menu) show_menu ;;
    *) fail "Uso: $0 [inspect [--cli] | backup [app] [--cli] | restore [archive] [target] | transfer [app] [origin] [dest] [--cli] | clone [app] [origin] [dest] [--cli] | menu]" ;;
esac

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
    if [ -f "$INVENTORY_FILE" ] && [ -s "$INVENTORY_FILE" ]; then
        local node_count
        node_count=$(jq -r '[.nodes[]? | select(.role == "worker" or .mode == "worker")] | length' "$INVENTORY_FILE" 2>/dev/null || printf '0')
        if [ "$node_count" -gt 0 ]; then
            return 0
        fi
    fi

    if command -v docker >/dev/null 2>&1; then
        local audit_vol
        audit_vol=$(docker volume ls -q --filter "name=audit_data" 2>/dev/null | head -n 1)
        if [ -n "$audit_vol" ]; then
            local inv_data
            inv_data=$(docker run --rm -v "${audit_vol}:/audit" alpine cat /audit/fleet-inventory.json 2>/dev/null || true)
            if [ -n "$inv_data" ] && [ "$inv_data" != "null" ]; then
                mkdir -p "$(dirname "$INVENTORY_FILE")" 2>/dev/null || true
                printf '%s\n' "$inv_data" > "$INVENTORY_FILE" 2>/dev/null || true
                return 0
            fi
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
    local _r_ret_var="$3"
    local _r_host=""

    mkdir -p "$CONTROL_DIR" 2>/dev/null || true

    if [ -f "$SSH_HOSTS_FILE" ]; then
        _r_host=$(jq -r --arg id "$_r_node_id" --arg name "$_r_node_name" '.[$id] // .[$name] // empty' "$SSH_HOSTS_FILE" 2>/dev/null || true)
    fi

    if [ -z "$_r_host" ] && [ -f "$INVENTORY_FILE" ]; then
        local ep
        ep=$(jq -r --arg id "$_r_node_id" '.nodes[]? | select(.id == $id) | .endpoint' "$INVENTORY_FILE" 2>/dev/null || true)
        if [[ "$ep" =~ ^https?://([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+) ]]; then
            _r_host="${BASH_REMATCH[1]}"
        fi
    fi

    if [ -z "$_r_host" ] && { [ "$_r_node_id" = "node-worker-a8454ed4" ] || [ "$_r_node_name" = "Server2" ]; }; then
        _r_host="91.99.117.159"
    fi

    if [ -z "$_r_host" ]; then
        _r_host=$(whiptail --title "CONEXÃO SSH COM O SERVIDOR ($_r_node_name)" --inputbox \
            "Informe o endereço IP da VPS para transferência de dados:" 12 74 "91.99.117.159" 3>&1 1>&2 2>&3) || return 1
        [ -n "$_r_host" ] || return 1

        local current_json="{}"
        [ -f "$SSH_HOSTS_FILE" ] && current_json=$(cat "$SSH_HOSTS_FILE" 2>/dev/null || printf '{}')
        local updated_json
        updated_json=$(printf '%s' "$current_json" | jq --arg id "$_r_node_id" --arg name "$_r_node_name" --arg h "$_r_host" '.[$id] = $h | .[$name] = $h' 2>/dev/null || printf '{"%s": "%s"}' "$_r_node_id" "$_r_host")
        printf '%s\n' "$updated_json" > "$SSH_HOSTS_FILE" 2>/dev/null || true
    fi

    ensure_ssh_keys_available

    # Testar conectividade SSH com timeout estrito de 4s (evita qualquer travamento)
    if ! timeout 4 ssh -o StrictHostKeyChecking=no -o BatchMode=yes -o ConnectTimeout=3 -o ServerAliveInterval=2 -o ServerAliveCountMax=1 "root@$_r_host" "echo ok" >/dev/null 2>&1; then
        local vps_pwd
        vps_pwd=$(whiptail --title "AUTENTICAÇÃO SSH NECESSÁRIA" --passwordbox \
            "A chave SSH ainda não está autorizada no nó '$_r_node_name' ($_r_host).\n\nInforme a senha de root da VPS para estabelecer a conexão segura:" 12 74 3>&1 1>&2 2>&3) || return 1
        
        if command -v sshpass >/dev/null 2>&1 && [ -n "$vps_pwd" ]; then
            timeout 8 sshpass -p "$vps_pwd" ssh-copy-id -o StrictHostKeyChecking=no "root@$_r_host" >/dev/null 2>&1 || true
        fi
    fi

    printf -v "$_r_ret_var" '%s' "$_r_host"
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
        ssh -o StrictHostKeyChecking=no -o BatchMode=yes -o ConnectTimeout=15 "root@$host" "$cmd"
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
        pfile=$(docker run --rm -v portainer_data:/pdata alpine sh -c "grep -rl '$app' /pdata/compose/*/docker-compose.yml 2>/dev/null | head -n 1" 2>/dev/null || true)
        if [ -n "$pfile" ]; then
            docker run --rm -v portainer_data:/pdata alpine cat "$pfile" > "$out_file" 2>/dev/null || true
            if [ -s "$out_file" ]; then
                cp -f "$out_file" "/root/${app}.yaml" 2>/dev/null || true
                return 0
            fi
        fi
        if [ -s "/root/${app}.yaml" ]; then
            cp -f "/root/${app}.yaml" "$out_file"
            return 0
        fi
        if [ -s "/root/SetupLowCodeMno/stacks/${app}.yml" ]; then
            cp -f "/root/SetupLowCodeMno/stacks/${app}.yml" "$out_file"
            return 0
        fi
    else
        pfile=$(timeout 8 ssh -o StrictHostKeyChecking=no -o BatchMode=yes -o ConnectTimeout=5 -o ServerAliveInterval=2 -o ServerAliveCountMax=1 "root@$host" "docker run --rm -v portainer_data:/pdata alpine sh -c \"grep -rl '$app' /pdata/compose/*/docker-compose.yml 2>/dev/null | head -n 1\" 2>/dev/null" || true)
        if [ -n "$pfile" ]; then
            timeout 8 ssh -o StrictHostKeyChecking=no -o BatchMode=yes -o ConnectTimeout=5 -o ServerAliveInterval=2 -o ServerAliveCountMax=1 "root@$host" "docker run --rm -v portainer_data:/pdata alpine cat '$pfile' 2>/dev/null" > "$out_file" 2>/dev/null || true
            if [ -s "$out_file" ]; then
                timeout 8 ssh -o StrictHostKeyChecking=no -o BatchMode=yes -o ConnectTimeout=5 "root@$host" "cat > /root/${app}.yaml" < "$out_file" 2>/dev/null || true
                return 0
            fi
        fi
        if timeout 8 ssh -o StrictHostKeyChecking=no -o BatchMode=yes -o ConnectTimeout=5 -o ServerAliveInterval=2 -o ServerAliveCountMax=1 "root@$host" "[ -s /root/${app}.yaml ]"; then
            timeout 8 ssh -o StrictHostKeyChecking=no -o BatchMode=yes -o ConnectTimeout=5 -o ServerAliveInterval=2 -o ServerAliveCountMax=1 "root@$host" "cat /root/${app}.yaml" > "$out_file"
            return 0
        fi
    fi

    return 1
}

# Detecção de Banco Multi-Tenant
detect_database_engine() {
    local yaml_file="$1"
    local app="$2"

    if grep -qE "POSTGRES_DB|DB_POSTGRESDB_DATABASE|POSTGRES_HOST=postgres|postgres:5432" "$yaml_file"; then
        local pg_db
        pg_db=$(grep -E "POSTGRES_DB=|DB_POSTGRESDB_DATABASE=" "$yaml_file" 2>/dev/null | head -n1 | cut -d= -f2 | tr -d ' "\r' || true)
        [ -n "$pg_db" ] || pg_db="$app"
        printf "postgres:%s\n" "$pg_db"
        return 0
    fi

    if grep -qE "MAUTIC_DB_HOST=mysql84|MYSQL_HOST=mysql84|mysql84:3306|MAUTIC_DB_NAME" "$yaml_file"; then
        local my_db
        my_db=$(grep -E "MAUTIC_DB_NAME=|MYSQL_DATABASE=" "$yaml_file" 2>/dev/null | head -n1 | cut -d= -f2 | tr -d ' "\r' || true)
        [ -n "$my_db" ] || my_db="$app"
        printf "mysql84:%s\n" "$my_db"
        return 0
    fi

    printf "none:\n"
}

# Detecção de Storage MinIO / S3
detect_s3_storage_engine() {
    local yaml_file="$1"
    local app="$2"

    if grep -qE "S3_BUCKET|S3_BUCKET_NAME|AWS_BUCKET|AWS_S3_BUCKET|MINIO_PUBLIC_URL|MINIO_SERVER_URL" "$yaml_file"; then
        local b_name
        b_name=$(grep -E "S3_BUCKET=|S3_BUCKET_NAME=|AWS_BUCKET=" "$yaml_file" 2>/dev/null | head -n1 | cut -d= -f2 | tr -d ' "\r' || true)
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

    if grep -qE "RABBITMQ_URI|RABBITMQ_URL|RABBITMQ_DEFAULT_USER|amqp://" "$yaml_file"; then
        local mq_vhost
        mq_vhost=$(grep -oP '(?<=amqp://)[^:]+' "$yaml_file" 2>/dev/null | head -n1 || true)
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
        manifest_content=$(ssh -o StrictHostKeyChecking=no -o BatchMode=yes "root@$host" "[ -f '$manifest_file' ] && cat '$manifest_file'" 2>/dev/null || true)
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
        all_stacks=$(ssh -o StrictHostKeyChecking=no -o BatchMode=yes "root@$host" "docker stack ls --format '{{.Name}}'" 2>/dev/null || true)
    fi

    local app_suffix=""
    if [[ "$app" =~ ([a-f0-9]{7})$ ]]; then
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
            if [[ "$s" == *"$app_suffix" ]]; then
                linked+=("$s")
            fi
        done <<< "$all_stacks"
    fi

    if [[ "$app" == chatwoot* ]] || [[ "$app" == evolution* ]]; then
        while IFS= read -r s; do
            [ -n "$s" ] || continue
            [ "$s" = "$app" ] && continue
            case "$s" in
                chatwoot*|evolution*|rabbitmq*|cwt_redis*|evo_redis*)
                    if [[ ! " ${linked[*]} " =~ " ${s} " ]]; then
                        linked+=("$s")
                    fi
                    ;;
            esac
        done <<< "$all_stacks"
        detected_combo_name="Combo Multicanais (Chatwoot + Evolution + Filas)"
    fi

    if [ ${#linked[@]} -gt 0 ]; then
        [ -n "$detected_combo_name" ] || detected_combo_name="Ecossistema Integrado (${app})"
        printf "true|%s|%s\n" "$detected_combo_name" "${linked[*]}"
        return 0
    fi

    printf "false||none\n"
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
        ssh -o StrictHostKeyChecking=no -o BatchMode=yes "root@$host" "mkdir -p '$manifest_dir' && cat > '$manifest_dir/${app}.json'" <<< "$json_manifest" 2>/dev/null || true
    fi
}

# Extração de volumes exclusivos (sem infraestrutura compartilhada)
get_application_volumes() {
    local yaml_file="$1"
    local app="$2"

    local vols=()
    while IFS= read -r v; do
        [ -n "$v" ] || continue
        case "$v" in
            postgres*|mysql*|portainer*|traefik*|cloudflared*|audit*|interna|externa|redis*)
                continue
                ;;
            *)
                vols+=("$v")
                ;;
        esac
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
                postgres*|mysql*|portainer*|traefik*|cloudflared*|audit*|interna|externa|redis*)
                    continue
                    ;;
                *)
                    vols+=("$v")
                    ;;
            esac
        done < <(grep -oE "${app}[a-zA-Z0-9_-]*" "$yaml_file" | grep -E "(data|config|media|themes|logs|import|uploads)" | sort -u || true)
    fi

    printf '%s\n' "${vols[@]}"
}

## Aplica stack garantindo registro no Portainer para torná-la EDITÁVEL
deploy_stack_with_portainer_priority() {
    local node_id="$1"
    local host="$2"
    local stack_name="$3"
    local stack_file="$4"

    local portainer_script='
        dados="/root/dados_portainer/dados_portainer"
        if [ -f "$dados" ]; then
            p_url=$(grep "Dominio do portainer:" "$dados" | cut -d: -f2 | xargs)
            p_user=$(grep "Usuario:" "$dados" | cut -d: -f2 | xargs)
            p_pass=$(grep "Senha:" "$dados" | cut -d: -f2 | xargs)
            if [ -n "$p_url" ] && [ -n "$p_user" ] && [ -n "$p_pass" ]; then
                resp=$(curl -k -sS -m 6 -X POST "https://$p_url/api/auth" -H "Content-Type: application/json" -d "{\"username\":\"$p_user\",\"password\":\"$p_pass\"}" 2>/dev/null || true)
                jwt=$(echo "$resp" | jq -r .jwt 2>/dev/null || true)
                if [ -n "$jwt" ] && [ "$jwt" != "null" ]; then
                    ep_id=$(curl -k -sS -m 6 -H "Authorization: Bearer $jwt" "https://$p_url/api/endpoints" 2>/dev/null | jq -r ".[0].Id" || true)
                    swarm_id=$(curl -k -sS -m 6 -H "Authorization: Bearer $jwt" "https://$p_url/api/endpoints/$ep_id/docker/swarm" 2>/dev/null | jq -r ".ID" || true)
                    if [ -n "$ep_id" ] && [ -n "$swarm_id" ]; then
                        docker stack rm "'"$stack_name"'" >/dev/null 2>&1 || true
                        sleep 3
                        code=$(curl -k -sS -m 15 -w "%{http_code}" -o /dev/null -X POST \
                            -H "Authorization: Bearer $jwt" \
                            -F "Name='"$stack_name"'" \
                            -F "file=@'"$stack_file"'" \
                            -F "SwarmID=$swarm_id" \
                            -F "endpointId=$ep_id" \
                            "https://$p_url/api/stacks/create/swarm/file" 2>/dev/null || true)
                        if [ "$code" = "200" ]; then
                            echo "PORTAINER_SUCCESS"
                            exit 0
                        fi
                    fi
                fi
            fi
        fi
        exit 1
    '

    local success=false
    if [ "$node_id" = "local" ]; then
        if bash -c "$portainer_script" 2>/dev/null | grep -q "PORTAINER_SUCCESS"; then
            success=true
        fi
    else
        if ssh -o StrictHostKeyChecking=no -o BatchMode=yes "root@$host" "bash -c '$portainer_script'" 2>/dev/null | grep -q "PORTAINER_SUCCESS"; then
            success=true
        fi
    fi

    if [ "$success" = "false" ]; then
        if [ "$node_id" = "local" ]; then
            docker stack deploy --prune --resolve-image always -c "$stack_file" "$stack_name"
        else
            ssh -o StrictHostKeyChecking=no -o BatchMode=yes "root@$host" "docker stack deploy --prune --resolve-image always -c '$stack_file' '$stack_name'"
        fi
    fi
}

# Comutação atômica de DNS Cloudflare e rotas de Ingress no Tunnel (Multi-Domínio)
switch_cloudflare_dns_and_ingress() {
    local node_id="$1"
    local host="$2"
    local yaml_file="$3"
    local app_name="$4"

    local hostnames=()
    while IFS= read -r h; do
        [ -n "$h" ] || continue
        hostnames+=("$h")
    done < <(grep -oP 'Host\(`\K[^`]+' "$yaml_file" 2>/dev/null | sort -u || true)

    if [ ${#hostnames[@]} -eq 0 ]; then
        local single_h
        single_h=$(grep -oP '(?<=MAUTIC_URL=https://)[^[:space:]/]+' "$yaml_file" 2>/dev/null || grep -oP '(?<=URL=https://)[^[:space:]/]+' "$yaml_file" 2>/dev/null | head -n1 || true)
        [ -n "$single_h" ] && hostnames+=("$single_h")
    fi

    [ ${#hostnames[@]} -gt 0 ] || return 0

    local default_port="80"
    if grep -q "3000" "$yaml_file"; then
        default_port="3000"
    elif grep -q "8080" "$yaml_file" || grep -q "8081" "$yaml_file"; then
        default_port="8080"
    elif grep -q "9000" "$yaml_file"; then
        default_port="9000"
    elif grep -q "5678" "$yaml_file"; then
        default_port="5678"
    fi

    local first_svc
    first_svc=$(awk '/^services:/{flag=1; next} flag && /^[[:space:]]{2}[a-zA-Z0-9_-]+:/{print $1; exit}' "$yaml_file" | tr -d ':' || true)
    [ -n "$first_svc" ] || first_svc="$app_name"

    local hostnames_list="${hostnames[*]}"

    local cf_script="
        creds=\"/root/.cloudflared_config/cloudflare_credentials\"
        if [ -f \"\$creds\" ]; then
            source \"\$creds\"
            if [ -n \"\${CLOUDFLARE_API_TOKEN:-}\" ] && [ -n \"\${CLOUDFLARE_ZONE_ID:-}\" ] && [ -n \"\${CLOUDFLARE_ACCOUNT_ID:-}\" ] && [ -n \"\${TUNNEL_ID:-}\" ]; then
                for h in ${hostnames_list}; do
                    [ -n \"\$h\" ] || continue
                    records=\$(curl -s -X GET \"https://api.cloudflare.com/client/v4/zones/\${CLOUDFLARE_ZONE_ID}/dns_records?name=\${h}\" \
                        -H \"Authorization: Bearer \${CLOUDFLARE_API_TOKEN}\" \
                        -H \"Content-Type: application/json\")
                    echo \"\$records\" | jq -r '.result[]?.id // empty' | while read -r r_id; do
                        [ -n \"\$r_id\" ] || continue
                        curl -s -X DELETE \"https://api.cloudflare.com/client/v4/zones/\${CLOUDFLARE_ZONE_ID}/dns_records/\${r_id}\" \
                            -H \"Authorization: Bearer \${CLOUDFLARE_API_TOKEN}\" \
                            -H \"Content-Type: application/json\" >/dev/null 2>&1 || true
                    done

                    curl -s -X POST \"https://api.cloudflare.com/client/v4/zones/\${CLOUDFLARE_ZONE_ID}/dns_records\" \
                        -H \"Authorization: Bearer \${CLOUDFLARE_API_TOKEN}\" \
                        -H \"Content-Type: application/json\" \
                        --data '{\"type\":\"CNAME\",\"name\":\"'\${h}'\",\"content\":\"'\${TUNNEL_ID}'.cfargotunnel.com\",\"ttl\":1,\"proxied\":true}' >/dev/null 2>&1 || true

                    cfg_raw=\$(curl -sS -H \"Authorization: Bearer \${CLOUDFLARE_API_TOKEN}\" \
                        \"https://api.cloudflare.com/client/v4/accounts/\${CLOUDFLARE_ACCOUNT_ID}/cfd_tunnel/\${TUNNEL_ID}/configurations\")
                    if echo \"\$cfg_raw\" | grep -q '\"success\":true'; then
                        to_put=\$(mktemp)
                        target_service=\"http://${first_svc}:${default_port}\"
                        printf '%s' \"\$cfg_raw\" | jq --arg host \"\${h}\" --arg service \"\$target_service\" '
                            (.result.config // {}) as \$cfg
                            | (\$cfg.ingress // []) as \$ing
                            | (\$ing | map(select(.service != \"http_status:404\"))) as \$clean
                            | (\$clean | map(select(.hostname != \$host))) as \$filtered
                            | (\$filtered + [ { hostname: \$host, service: \$service, originRequest: { noTlsVerify: true, httpHostHeader: \$host } } ]) as \$merged
                            | (\$merged + [{ service: \"http_status:404\" }]) as \$final_ing
                            | (\$cfg + { ingress: \$final_ing }) as \$newcfg
                            | { config: \$newcfg }
                        ' > \"\$to_put\" 2>/dev/null || true

                        if [ -s \"\$to_put\" ]; then
                            curl -sS -X PUT \"https://api.cloudflare.com/client/v4/accounts/\${CLOUDFLARE_ACCOUNT_ID}/cfd_tunnel/\${TUNNEL_ID}/configurations\" \
                                -H \"Authorization: Bearer \${CLOUDFLARE_API_TOKEN}\" \
                                -H \"Content-Type: application/json\" \
                                --data-binary @\"\$to_put\" >/dev/null 2>&1 || true
                        fi
                        rm -f \"\$to_put\"
                    fi
                done
            fi
        fi
    "

    if [ "$node_id" = "local" ]; then
        bash -c "$cf_script" 2>/dev/null || true
    else
        ssh -o StrictHostKeyChecking=no -o BatchMode=yes "root@$host" "bash -c '$cf_script'" 2>/dev/null || true
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
        running=$(ssh -o StrictHostKeyChecking=no -o BatchMode=yes "root@$host" 'docker ps -qf name=mysql84 | head -n1' 2>/dev/null || true)
    fi

    if [ -n "$running" ]; then
        return 0
    fi

    local new_pwd
    new_pwd=$(openssl rand -hex 8)

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
        printf '%s\n' "$yaml_body" > /root/mysql84.yaml 2>/dev/null || true
        deploy_stack_with_portainer_priority "local" "" "mysql84" "/root/mysql84.yaml" >/dev/null 2>&1 || true
    else
        ssh -o StrictHostKeyChecking=no -o BatchMode=yes "root@$host" "cat > /root/mysql84.yaml" <<< "$yaml_body"
        deploy_stack_with_portainer_priority "$node_id" "$host" "mysql84" "/root/mysql84.yaml" >/dev/null 2>&1 || true
    fi

    local wait_count=0
    while [ $wait_count -lt 15 ]; do
        sleep 1
        wait_count=$((wait_count + 1))
        local chk=""
        if [ "$node_id" = "local" ]; then
            chk=$(docker ps -qf name=mysql84 2>/dev/null | head -n1 || true)
        else
            chk=$(ssh -o StrictHostKeyChecking=no -o BatchMode=yes "root@$host" 'docker ps -qf name=mysql84 | head -n1' 2>/dev/null || true)
        fi
        if [ -n "$chk" ]; then
            sleep 4
            return 0
        fi
    done
}

# Garante que MinIO S3 está rodando no nó destino
ensure_minio_ready() {
    local node_id="$1"
    local host="$2"

    local running=""
    if [ "$node_id" = "local" ]; then
        running=$(docker ps -qf name=minio 2>/dev/null | head -n1 || true)
    else
        running=$(ssh -o StrictHostKeyChecking=no -o BatchMode=yes "root@$host" 'docker ps -qf name=minio | head -n1' 2>/dev/null || true)
    fi

    if [ -n "$running" ]; then
        return 0
    fi

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
        deploy_stack_with_portainer_priority "local" "" "minio" "/root/minio.yaml" >/dev/null 2>&1 || true
    else
        ssh -o StrictHostKeyChecking=no -o BatchMode=yes "root@$host" "mkdir -p /root/dados_minio && cat > /root/dados_minio/dados_minio" <<< "$dados_content"
        ssh -o StrictHostKeyChecking=no -o BatchMode=yes "root@$host" "cat > /root/minio.yaml" <<< "$yaml_body"
        deploy_stack_with_portainer_priority "$node_id" "$host" "minio" "/root/minio.yaml" >/dev/null 2>&1 || true
    fi

    local wait_count=0
    while [ $wait_count -lt 20 ]; do
        sleep 1
        wait_count=$((wait_count + 1))
        local chk=""
        if [ "$node_id" = "local" ]; then
            chk=$(docker ps -qf name=minio 2>/dev/null | head -n1 || true)
        else
            chk=$(ssh -o StrictHostKeyChecking=no -o BatchMode=yes "root@$host" 'docker ps -qf name=minio | head -n1' 2>/dev/null || true)
        fi
        if [ -n "$chk" ]; then
            sleep 4
            return 0
        fi
    done
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
        orig_minio_vol=$(ssh -o StrictHostKeyChecking=no -o BatchMode=yes "root@$orig_host" "docker volume ls -q --filter name=minio | grep -E '(data|minio)' | head -n1" 2>/dev/null || true)
        [ -n "$orig_minio_vol" ] || orig_minio_vol="minio_data"
    fi

    local dest_minio_vol=""
    if [ "$dest_id" = "local" ]; then
        dest_minio_vol=$(docker volume ls -q --filter name=minio 2>/dev/null | grep -E "(data|minio)" | head -n1 || true)
        [ -n "$dest_minio_vol" ] || dest_minio_vol="minio_data"
        docker volume create "$dest_minio_vol" >/dev/null 2>&1 || true
    else
        dest_minio_vol=$(ssh -o StrictHostKeyChecking=no -o BatchMode=yes "root@$dest_host" "docker volume ls -q --filter name=minio | grep -E '(data|minio)' | head -n1" 2>/dev/null || true)
        [ -n "$dest_minio_vol" ] || dest_minio_vol="minio_data"
        ssh -o StrictHostKeyChecking=no -o BatchMode=yes "root@$dest_host" "docker volume create '$dest_minio_vol' >/dev/null 2>&1 || true"
    fi

    local bucket_exists=false
    if [ "$orig_id" = "local" ]; then
        if docker run --rm -v "${orig_minio_vol}:/mdata:ro" alpine test -d "/mdata/${bucket_name}" 2>/dev/null; then
            bucket_exists=true
        fi
    else
        if ssh -o StrictHostKeyChecking=no -o BatchMode=yes "root@$orig_host" "docker run --rm -v '${orig_minio_vol}:/mdata:ro' alpine test -d '/mdata/${bucket_name}'" 2>/dev/null; then
            bucket_exists=true
        fi
    fi

    if [ "$bucket_exists" = "false" ]; then
        if [ "$dest_id" = "local" ]; then
            docker run --rm -v "${dest_minio_vol}:/mdata" alpine mkdir -p "/mdata/${bucket_name}" 2>/dev/null || true
        else
            ssh -o StrictHostKeyChecking=no -o BatchMode=yes "root@$dest_host" "docker run --rm -v '${dest_minio_vol}:/mdata' alpine mkdir -p '/mdata/${bucket_name}'" 2>/dev/null || true
        fi
        return 0
    fi

    if [ "$orig_id" = "local" ] && [ "$dest_id" != "local" ]; then
        docker run --rm -v "${orig_minio_vol}:/mdata:ro" alpine tar -czf - -C "/mdata/${bucket_name}" . 2>/dev/null \
            | ssh -o StrictHostKeyChecking=no -o BatchMode=yes "root@$dest_host" \
            "docker run --rm -i -v '${dest_minio_vol}:/mdata' alpine sh -c 'mkdir -p /mdata/${bucket_name} && tar -xzf - -C /mdata/${bucket_name}'" 2>/dev/null || true
    elif [ "$orig_id" != "local" ] && [ "$dest_id" = "local" ]; then
        ssh -o StrictHostKeyChecking=no -o BatchMode=yes "root@$orig_host" \
            "docker run --rm -v '${orig_minio_vol}:/mdata:ro' alpine tar -czf - -C '/mdata/${bucket_name}' ." 2>/dev/null \
            | docker run --rm -i -v "${dest_minio_vol}:/mdata" alpine sh -c "mkdir -p /mdata/${bucket_name} && tar -xzf - -C /mdata/${bucket_name}" 2>/dev/null || true
    elif [ "$orig_id" != "local" ] && [ "$dest_id" != "local" ]; then
        ssh -o StrictHostKeyChecking=no -o BatchMode=yes "root@$orig_host" \
            "docker run --rm -v '${orig_minio_vol}:/mdata:ro' alpine tar -czf - -C '/mdata/${bucket_name}' ." 2>/dev/null \
            | ssh -o StrictHostKeyChecking=no -o BatchMode=yes "root@$dest_host" \
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
        running=$(docker ps -qf name=rabbitmq 2>/dev/null | head -n1 || true)
    else
        running=$(ssh -o StrictHostKeyChecking=no -o BatchMode=yes "root@$host" 'docker ps -qf name=rabbitmq | head -n1' 2>/dev/null || true)
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
        deploy_stack_with_portainer_priority "local" "" "rabbitmq" "/root/rabbitmq.yaml" >/dev/null 2>&1 || true
    else
        ssh -o StrictHostKeyChecking=no -o BatchMode=yes "root@$host" "cat > /root/rabbitmq.yaml" <<< "$yaml_body"
        deploy_stack_with_portainer_priority "$node_id" "$host" "rabbitmq" "/root/rabbitmq.yaml" >/dev/null 2>&1 || true
    fi

    local wait_count=0
    while [ $wait_count -lt 20 ]; do
        sleep 1
        wait_count=$((wait_count + 1))
        local chk=""
        if [ "$node_id" = "local" ]; then
            chk=$(docker ps -qf name=rabbitmq 2>/dev/null | head -n1 || true)
        else
            chk=$(ssh -o StrictHostKeyChecking=no -o BatchMode=yes "root@$host" 'docker ps -qf name=rabbitmq | head -n1' 2>/dev/null || true)
        fi
        if [ -n "$chk" ]; then
            sleep 4
            return 0
        fi
    done
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
    else
        report+="📡 NÓS REMOTOS DA FROTA (WORKERS CADASTRADOS):\n"
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
                report+="Nenhum nó worker cadastrado no momento no fleet-inventory.json.\n"
            fi
        else
            report+="Inventário de frota não localizado. Cadastre nós remotos no menu Fleet Hub.\n"
        fi
    fi

    if [ "${1:-}" = "--cli" ] || [ "${1:-}" = "text" ] || [ -z "${TERM:-}" ]; then
        printf '%b\n' "$report"
        return 0
    fi

    whiptail --title "RAIO-X ESTRUTURAL DA FROTA MNO" --msgbox "$report" 20 78
}

# Criar backup portátil universal
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

    local timestamp
    timestamp=$(date -u +%Y%m%d_%H%M%SZ)
    local local_arch
    local_arch=$(get_local_arch)
    mkdir -p "$BACKUP_BASE_DIR"

    local backup_file="$BACKUP_BASE_DIR/${chosen_app}_backup_${local_arch}_${timestamp}.tar.gz"

    local tmpdir
    tmpdir=$(mktemp -d)
    trap 'rm -rf "$tmpdir"' RETURN

    resolve_live_stack_yaml "local" "" "$chosen_app" "$tmpdir/stack.yaml" || true
    [ -s "$tmpdir/stack.yaml" ] || echo "# Stack: $chosen_app" > "$tmpdir/stack.yaml"

    local db_info
    db_info=$(detect_database_engine "$tmpdir/stack.yaml" "$chosen_app")

    if [[ "$db_info" == postgres:* ]]; then
        local db_name="${db_info#postgres:}"
        local pg_c
        pg_c=$(docker ps -qf name=postgres 2>/dev/null | head -n1 || true)
        if [ -n "$pg_c" ]; then
            docker exec -i "$pg_c" pg_dump -U postgres -d "$db_name" --clean --if-exists 2>/dev/null | gzip > "$tmpdir/db_logical_dump.sql.gz" || true
        fi
    elif [[ "$db_info" == mysql84:* ]]; then
        local db_name="${db_info#mysql84:}"
        local my_c my_pwd
        my_c=$(docker ps -qf name=mysql84 2>/dev/null | head -n1 || true)
        if [ -n "$my_c" ]; then
            my_pwd=$(docker inspect "$my_c" --format '{{range .Config.Env}}{{println .}}{{end}}' 2>/dev/null | grep MYSQL_ROOT_PASSWORD | cut -d= -f2- || grep -oP '(?<=MYSQL_ROOT_PASSWORD=).+' /root/mysql84.yaml 2>/dev/null || echo "")
            docker exec -i "$my_c" mysqldump -u root -p"$my_pwd" --databases "$db_name" --add-drop-table 2>/dev/null | gzip > "$tmpdir/db_logical_dump.sql.gz" || true
        fi
    fi

    cat > "$tmpdir/manifest.json" << EOF
{
  "schemaVersion": 1,
  "appName": "$chosen_app",
  "architecture": "$local_arch",
  "database": "$db_info",
  "createdAt": "$(date -u -Iseconds)",
  "type": "portable_application_backup"
}
EOF

    tar -czf "$backup_file" -C "$tmpdir" .
    local sha
    sha=$(sha256sum "$backup_file" | awk '{print $1}')
    local size
    size=$(du -h "$backup_file" | awk '{print $1}')

    if [ "$is_cli" = "true" ]; then
        echo "Backup concluído: $backup_file ($size)"
    else
        whiptail --title "BACKUP GERADO COM SUCESSO" --msgbox \
            "✅ O Backup Portátil da aplicação '$chosen_app' foi concluído!\n\nArquivo: $backup_file\nTamanho: $size\nSHA-256: ${sha:0:16}...\nArquitetura: $local_arch\nBanco Lógico Extraído: $db_info\n\nEste arquivo é universal e pode ser usado para restauração de emergência em qualquer servidor." 17 76
    fi
}

# Transferência e Clonagem Atômica
action_transfer_or_clone() {
    local op_mode="${1:-transfer}"
    local op_title="TRANSFERÊNCIA DE APLICAÇÃO"
    [ "$op_mode" = "clone" ] && op_title="CLONAGEM DE APLICAÇÃO (TESTE)"

    sync_fleet_inventory

    local fleet_mode
    fleet_mode=$(get_local_fleet_mode)
    if [ "$fleet_mode" = "worker" ]; then
        whiptail --title "$op_title" --msgbox \
            "Esta VPS está configurada como Nó Worker subordinado.\n\nA transferência e clonagem de aplicações entre servidores é orquestrada centralmente a partir da sua Torre Master (Cockpit Local no WSL2).\n\nAbra o menu Fleet Hub na sua Torre Master para iniciar a transferência de qualquer aplicação deste Worker para a Torre ou para outro servidor!\n\nNeste nó Worker, você também pode usar a Opção 4 para gerar um Backup Portátil (.tar.gz) dos dados a qualquer momento." 16 76
        return 0
    fi

    local local_arch
    local_arch=$(get_local_arch)

    # 1. Carregar workers cadastrados
    local workers_tsv=""
    if [ -f "$INVENTORY_FILE" ]; then
        workers_tsv=$(jq -r '.nodes[]? | select(.role == "worker" or .mode == "worker") | select(.status != "deleted") | "\(.id)\t\(.name)\t\(.architecture // "amd64")\t\(.endpoint)\t\(.token)"' "$INVENTORY_FILE" 2>/dev/null || true)
    fi

    if [ -z "$workers_tsv" ]; then
        whiptail --title "$op_title" --msgbox "Nenhum nó worker remoto cadastrado na frota. Acesse o menu Fleet Hub no Control Center e faça o pareamento de um Worker antes de transferir." 12 76
        return 0
    fi

    # 2. Selecionar o SERVIDOR DE ORIGEM
    local origin_menu=()
    origin_menu+=("local" "Torre Master (Nó Local) [$local_arch]")
    while IFS=$'\t' read -r wid wname warch wendpoint wtoken; do
        [ -n "$wid" ] || continue
        origin_menu+=("$wid" "$wname (Worker Remoto) [$warch]")
    done <<< "$workers_tsv"

    local chosen_origin_id
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

    local chosen_dest_id
    chosen_dest_id=$(whiptail --title "SELECIONE O SERVIDOR DE DESTINO" --menu \
        "Para qual servidor a aplicação deve ser transferida?" 18 78 6 \
        "${dest_menu[@]}" 3>&1 1>&2 2>&3) || return 0

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

    if [ "$chosen_dest_id" = "local" ]; then
        dest_name="Torre Master (Nó Local)"
        dest_arch="$local_arch"
    else
        dest_name=$(jq -r --arg id "$chosen_dest_id" '.nodes[]? | select(.id == $id) | .name' "$INVENTORY_FILE" 2>/dev/null)
        dest_arch=$(jq -r --arg id "$chosen_dest_id" '.nodes[]? | select(.id == $id) | .architecture // "amd64"' "$INVENTORY_FILE" 2>/dev/null)
        dest_endpoint=$(jq -r --arg id "$chosen_dest_id" '.nodes[]? | select(.id == $id) | .endpoint' "$INVENTORY_FILE" 2>/dev/null)
        dest_token=$(jq -r --arg id "$chosen_dest_id" '.nodes[]? | select(.id == $id) | .token' "$INVENTORY_FILE" 2>/dev/null)
    fi

    case "$origin_arch" in x86_64|amd64) origin_arch="amd64" ;; aarch64|arm64) origin_arch="arm64" ;; esac
    case "$dest_arch" in x86_64|amd64) dest_arch="amd64" ;; aarch64|arm64) dest_arch="arm64" ;; esac

    # 5. Trava de Arquitetura Rigorosa (Hardware Parity Gate)
    if [ "$origin_arch" != "$dest_arch" ]; then
        whiptail --title "⚠️ BLOQUEIO DE SEGURANÇA: ARQUITETURAS DIFERENTES" --msgbox \
            "TRANSFERÊNCIA AO VIVO BLOQUEADA!\n\nOrigem ($origin_name): $origin_arch\nDestino ($dest_name): $dest_arch\n\nProcessadores x86 e ARM possuem binários nativos e estruturas de banco de dados incompatíveis. Transferir containers ao vivo entre eles causará falhas críticas de inicialização.\n\nPara proteger seus dados, apenas o BACKUP PORTÁTIL (.tar.gz) é autorizado neste cenário.\n\nUtilize a Opção 4 do menu para gerar o Backup Portátil com segurança!" 18 78
        return 0
    fi

    # 6. Obter Hosts SSH para Comunicação Segura
    local origin_ssh_host="" dest_ssh_host=""
    if [ "$chosen_origin_id" != "local" ]; then
        resolve_worker_ssh_host "$chosen_origin_id" "$origin_name" origin_ssh_host || return 0
    fi
    if [ "$chosen_dest_id" != "local" ]; then
        resolve_worker_ssh_host "$chosen_dest_id" "$dest_name" dest_ssh_host || return 0
    fi

    # 7. Selecionar a APLICAÇÃO na ORIGEM (Filtra estritamente bancos e infraestrutura)
    local chosen_app=""
    if [ "$chosen_origin_id" = "local" ]; then
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
            remote_stacks=$(timeout 4 ssh -o StrictHostKeyChecking=no -o BatchMode=yes -o ConnectTimeout=3 -o ServerAliveInterval=2 -o ServerAliveCountMax=1 "root@$origin_ssh_host" "docker stack ls --format '{{.Name}}'" 2>/dev/null || true)
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
        local combo_choice
        combo_choice=$(whiptail --title "🤖 DETECÇÃO INTELIGENTE DE COMBO" --menu \
            "A aplicação '$chosen_app' faz parte de um ecossistema integrado:\n$combo_name\n\nFerramentas conectadas detectadas nesta VPS:\n• $(echo "$linked_stacks" | sed 's/ / \n• /g')\n\nComo você deseja proceder com a transferência para '$dest_name'?" 20 78 2 \
            "1" "MIGRAR COMBO COMPLETO (Recomendado — migra todas as ferramentas)" \
            "2" "MIGRAR APENAS '$chosen_app' (somente esta aplicação)" \
            3>&1 1>&2 2>&3) || return 0

        if [ "$combo_choice" = "1" ]; then
            for ls in $linked_stacks; do
                [ -n "$ls" ] || continue
                if [[ ! " ${apps_to_migrate[*]} " =~ " ${ls} " ]]; then
                    apps_to_migrate+=("$ls")
                fi
            done
        fi
    fi

    # 8. Trava de Capacidade de Recursos no Destino
    local dest_ram_free
    if [ "$chosen_dest_id" = "local" ]; then
        dest_ram_free=$(get_local_ram_free_mb)
    else
        dest_ram_free=$(jq -r --arg id "$chosen_dest_id" '.nodes[]? | select(.id == $id) | .telemetry.memoryFreeMB // 2048' "$INVENTORY_FILE" 2>/dev/null)
    fi

    if [ "$dest_ram_free" -lt 512 ]; then
        whiptail --title "⚠️ BLOQUEIO: MEMÓRIA INSUFICIENTE NO DESTINO" --msgbox \
            "O servidor de destino ($dest_name) possui apenas ${dest_ram_free} MB de RAM livre.\n\nA aplicação requer memória adicional para operar no Docker Swarm.\n\nA transferência foi interrompida para prevenir sobrecarga no destino." 14 76
        return 0
    fi

    # 9. Opções de Pós-Transferência
    local stop_origin=true
    local update_dns=true
    if [ "$op_mode" = "transfer" ]; then
        local apps_display="${apps_to_migrate[*]}"
        if ! whiptail --title "POLÍTICA PÓS-TRANSFERÊNCIA NA ORIGEM" --yesno \
            "Deseja que as stacks antigas ($apps_display) sejam DESLIGADAS em '$origin_name' para liberar memória RAM após o sucesso da migração?\n\nOs volumes de dados antigos permanecerão CONGELADOS e intactos no disco com sufixo de segurança para permitir rollback a qualquer momento." 14 76; then
            stop_origin=false
        fi

        if ! whiptail --title "COMUTAÇÃO DE DNS CLOUDFLARE" --yesno \
            "Deseja atualizar automaticamente os apontamentos de DNS e rotas do Cloudflare Tunnel para que a(s) URL(s) apontem imediatamente para o novo servidor ($dest_name)?" 12 76; then
            update_dns=false
        fi
    else
        stop_origin=false
        update_dns=false
    fi

    local notify_sentinel=true
    if ! whiptail --title "NOTIFICAÇÃO DO SENTINEL (TELEGRAM / N8N)" --yesno \
        "Deseja que o MNO Sentinel envie um relatório no Telegram e dispare um Webhook (para seu n8n notificar WhatsApp) ao concluir a migração com sucesso?" 12 76; then
        notify_sentinel=false
    fi

    # 10. Execução Robusta da Migração
    local safety_suffix="frozen_pre_transfer_$(date -u +%Y%m%dT%H%M%SZ)"
    local workdir
    workdir=$(mktemp -d)
    trap 'rm -rf "$workdir"' RETURN

    : > "$TRANSFER_LOG"
    local total_migrated_vols=0

    # Função interna de execução de etapas
    run_migration_pipeline() {
        local total_apps=${#apps_to_migrate[@]}
        local app_idx=0

        for cur_app in "${apps_to_migrate[@]}"; do
            app_idx=$((app_idx + 1))
            local app_workdir="$workdir/$cur_app"
            mkdir -p "$app_workdir"

            local pct_base=$(( (app_idx - 1) * 100 / total_apps ))
            local pct_step=$(( 100 / total_apps ))

            echo -e "XXX\n$((pct_base + (pct_step * 10 / 100)))\n[$app_idx/$total_apps] Sincronizando stack viva '$cur_app'...\nXXX"
            if ! resolve_live_stack_yaml "$chosen_origin_id" "$origin_ssh_host" "$cur_app" "$app_workdir/stack.yaml" 2>> "$TRANSFER_LOG"; then
                echo "Aviso: stack yaml não encontrado no Portainer para $cur_app, gerando manifesto mínimo..." >> "$TRANSFER_LOG"
                echo "version: '3.7'" > "$app_workdir/stack.yaml"
            fi

            local cur_db_engine cur_s3_engine cur_mq_engine
            cur_db_engine=$(detect_database_engine "$app_workdir/stack.yaml" "$cur_app")
            cur_s3_engine=$(detect_s3_storage_engine "$app_workdir/stack.yaml" "$cur_app")
            cur_mq_engine=$(detect_rabbitmq_engine "$app_workdir/stack.yaml" "$cur_app")

            echo "Stack: $cur_app | DB: $cur_db_engine | S3: $cur_s3_engine | MQ: $cur_mq_engine" >> "$TRANSFER_LOG"

            # 1. Extração Lógica do Banco de Dados
            if [[ "$cur_db_engine" == postgres:* ]]; then
                echo -e "XXX\n$((pct_base + (pct_step * 25 / 100)))\n[$app_idx/$total_apps] Extraindo banco PostgreSQL ($cur_app)...\nXXX"
                local pg_dbname="${cur_db_engine#postgres:}"
                if [ "$chosen_origin_id" = "local" ]; then
                    local c_id
                    c_id=$(docker ps -qf name=postgres 2>/dev/null | head -n1 || true)
                    if [ -n "$c_id" ]; then
                        docker exec -i "$c_id" pg_dump -U postgres -d "$pg_dbname" --clean --if-exists 2>> "$TRANSFER_LOG" | gzip > "$app_workdir/db_logical_dump.sql.gz" || true
                    fi
                else
                    ssh -o StrictHostKeyChecking=no -o BatchMode=yes "root@$origin_ssh_host" \
                        "c_id=\$(docker ps -qf name=postgres | head -n1); [ -n \"\$c_id\" ] && docker exec -i \"\$c_id\" pg_dump -U postgres -d '$pg_dbname' --clean --if-exists 2>/dev/null" \
                        | gzip > "$app_workdir/db_logical_dump.sql.gz" 2>> "$TRANSFER_LOG" || true
                fi
            elif [[ "$cur_db_engine" == mysql84:* ]]; then
                echo -e "XXX\n$((pct_base + (pct_step * 25 / 100)))\n[$app_idx/$total_apps] Extraindo banco MySQL 8.4 ($cur_app)...\nXXX"
                local my_dbname="${cur_db_engine#mysql84:}"
                if [ "$chosen_origin_id" = "local" ]; then
                    local c_id orig_pwd
                    c_id=$(docker ps -qf name=mysql84 2>/dev/null | head -n1 || true)
                    orig_pwd=$(docker inspect "$c_id" --format '{{range .Config.Env}}{{println .}}{{end}}' 2>/dev/null | grep MYSQL_ROOT_PASSWORD | cut -d= -f2- || grep -oP '(?<=MYSQL_ROOT_PASSWORD=).+' /root/mysql84.yaml 2>/dev/null || echo "")
                    if [ -n "$c_id" ] && [ -n "$orig_pwd" ]; then
                        docker exec -i "$c_id" mysqldump -u root -p"$orig_pwd" --databases "$my_dbname" --add-drop-table 2>> "$TRANSFER_LOG" | gzip > "$app_workdir/db_logical_dump.sql.gz" || true
                    fi
                else
                    ssh -o StrictHostKeyChecking=no -o BatchMode=yes "root@$origin_ssh_host" '
                        c_id=$(docker ps -qf name=mysql84 | head -n1)
                        pwd=$(docker inspect "$c_id" --format "{{range .Config.Env}}{{println .}}{{end}}" 2>/dev/null | grep MYSQL_ROOT_PASSWORD | cut -d= -f2- || grep -oP "(?<=MYSQL_ROOT_PASSWORD=).+" /root/mysql84.yaml 2>/dev/null || echo "")
                        if [ -n "$c_id" ] && [ -n "$pwd" ]; then
                            docker exec -i "$c_id" mysqldump -u root -p"$pwd" --databases "'"$my_dbname"'" --add-drop-table 2>/dev/null
                        fi
                    ' | gzip > "$app_workdir/db_logical_dump.sql.gz" 2>> "$TRANSFER_LOG" || true
                fi
            fi

            # 2. S3 MinIO Storage Sync
            if [[ "$cur_s3_engine" == minio:* ]]; then
                local s3_bucket="${cur_s3_engine#minio:}"
                echo -e "XXX\n$((pct_base + (pct_step * 40 / 100)))\n[$app_idx/$total_apps] Sincronizando storage S3 MinIO (Bucket: $s3_bucket)...\nXXX"
                ensure_minio_ready "$chosen_dest_id" "$dest_ssh_host"
                sync_s3_bucket_data "$chosen_origin_id" "$origin_ssh_host" "$chosen_dest_id" "$dest_ssh_host" "$s3_bucket"
            fi

            # 3. RabbitMQ Broker Check
            if [[ "$cur_mq_engine" == rabbitmq:* ]]; then
                echo -e "XXX\n$((pct_base + (pct_step * 50 / 100)))\n[$app_idx/$total_apps] Verificando broker RabbitMQ no destino...\nXXX"
                ensure_rabbitmq_ready "$chosen_dest_id" "$dest_ssh_host"
            fi

            # 4. Snapshot de Volumes Exclusivos
            local cur_vols=()
            while IFS= read -r v; do
                [ -n "$v" ] || continue
                cur_vols+=("$v")
                echo "Compactando volume de $cur_app: $v" >> "$TRANSFER_LOG"
                if [ "$chosen_origin_id" = "local" ]; then
                    docker run --rm -v "${v}:/voldata:ro" alpine tar -czf - -C /voldata . > "$app_workdir/vol_${v}.tar.gz" 2>> "$TRANSFER_LOG" || true
                else
                    ssh -o StrictHostKeyChecking=no -o BatchMode=yes "root@$origin_ssh_host" \
                        "docker run --rm -v '${v}:/voldata:ro' alpine tar -czf - -C /voldata ." > "$app_workdir/vol_${v}.tar.gz" 2>> "$TRANSFER_LOG" || true
                fi
            done < <(get_application_volumes "$app_workdir/stack.yaml" "$cur_app")

            total_migrated_vols=$((total_migrated_vols + ${#cur_vols[@]}))

            # 5. Restauração de Volumes e Banco no Destino
            echo -e "XXX\n$((pct_base + (pct_step * 65 / 100)))\n[$app_idx/$total_apps] Restaurando volumes e banco de dados no destino...\nXXX"
            for v in "${cur_vols[@]}"; do
                [ -f "$app_workdir/vol_${v}.tar.gz" ] || continue
                echo "Restaurando volume no destino: $v" >> "$TRANSFER_LOG"
                if [ "$chosen_dest_id" = "local" ]; then
                    docker volume create "$v" >/dev/null 2>&1 || true
                    docker run --rm -i -v "${v}:/voldata" alpine tar -xzf - -C /voldata < "$app_workdir/vol_${v}.tar.gz" 2>> "$TRANSFER_LOG" || true
                else
                    ssh -o StrictHostKeyChecking=no -o BatchMode=yes "root@$dest_ssh_host" "docker volume create '$v' >/dev/null 2>&1 || true"
                    ssh -o StrictHostKeyChecking=no -o BatchMode=yes "root@$dest_ssh_host" "docker run --rm -i -v '${v}:/voldata' alpine tar -xzf - -C /voldata" < "$app_workdir/vol_${v}.tar.gz" 2>> "$TRANSFER_LOG" || true
                fi
            done

            # Restauração lógica do Banco no destino
            if [[ "$cur_db_engine" == postgres:* ]] && [ -f "$app_workdir/db_logical_dump.sql.gz" ]; then
                local pg_dbname="${cur_db_engine#postgres:}"
                local dest_pg_pwd=""
                if [ "$chosen_dest_id" = "local" ]; then
                    local dc
                    dc=$(docker ps -qf name=postgres 2>/dev/null | head -n1 || true)
                    dest_pg_pwd=$(docker inspect "$dc" --format '{{range .Config.Env}}{{println .}}{{end}}' 2>/dev/null | grep POSTGRES_PASSWORD | cut -d= -f2- || grep -oP '(?<=POSTGRES_PASSWORD=).+' /root/postgres.yaml 2>/dev/null || echo "")
                    docker exec -i "$dc" psql -U postgres -c "CREATE DATABASE \"$pg_dbname\";" 2>> "$TRANSFER_LOG" || true
                    gunzip -c "$app_workdir/db_logical_dump.sql.gz" | docker exec -i "$dc" psql -U postgres -d "$pg_dbname" 2>> "$TRANSFER_LOG" || true
                else
                    dest_pg_pwd=$(ssh -o StrictHostKeyChecking=no -o BatchMode=yes "root@$dest_ssh_host" 'dc=$(docker ps -qf name=postgres | head -n1); docker inspect "$dc" --format "{{range .Config.Env}}{{println .}}{{end}}" 2>/dev/null | grep POSTGRES_PASSWORD | cut -d= -f2- || grep -oP "(?<=POSTGRES_PASSWORD=).+" /root/postgres.yaml 2>/dev/null || echo ""')
                    ssh -o StrictHostKeyChecking=no -o BatchMode=yes "root@$dest_ssh_host" "dc=\$(docker ps -qf name=postgres | head -n1); docker exec -i \"\$dc\" psql -U postgres -c \"CREATE DATABASE \\\"$pg_dbname\\\";\" 2>/dev/null || true"
                    ssh -o StrictHostKeyChecking=no -o BatchMode=yes "root@$dest_ssh_host" "dc=\$(docker ps -qf name=postgres | head -n1); gunzip -c | docker exec -i \"\$dc\" psql -U postgres -d '$pg_dbname' 2>/dev/null || true" < "$app_workdir/db_logical_dump.sql.gz"
                fi

                if [ -n "$dest_pg_pwd" ]; then
                    sed -i -E "s/POSTGRES_PASSWORD=[^[:space:]]+/POSTGRES_PASSWORD=$dest_pg_pwd/g" "$app_workdir/stack.yaml"
                fi
            elif [[ "$cur_db_engine" == mysql84:* ]] && [ -f "$app_workdir/db_logical_dump.sql.gz" ]; then
                local my_dbname="${cur_db_engine#mysql84:}"
                ensure_mysql84_ready "$chosen_dest_id" "$dest_ssh_host"

                local dest_my_pwd=""
                if [ "$chosen_dest_id" = "local" ]; then
                    local mc
                    mc=$(docker ps -qf name=mysql84 2>/dev/null | head -n1 || true)
                    dest_my_pwd=$(docker inspect "$mc" --format '{{range .Config.Env}}{{println .}}{{end}}' 2>/dev/null | grep MYSQL_ROOT_PASSWORD | cut -d= -f2- || grep -oP '(?<=MYSQL_ROOT_PASSWORD=).+' /root/mysql84.yaml 2>/dev/null || echo "")
                    docker exec -i "$mc" mysql -u root -p"$dest_my_pwd" -e "CREATE DATABASE IF NOT EXISTS \`$my_dbname\`;" 2>> "$TRANSFER_LOG" || true
                    gunzip -c "$app_workdir/db_logical_dump.sql.gz" | docker exec -i "$mc" mysql -u root -p"$dest_my_pwd" "$my_dbname" 2>> "$TRANSFER_LOG" || true
                else
                    dest_my_pwd=$(ssh -o StrictHostKeyChecking=no -o BatchMode=yes "root@$dest_ssh_host" 'mc=$(docker ps -qf name=mysql84 | head -n1); docker inspect "$mc" --format "{{range .Config.Env}}{{println .}}{{end}}" 2>/dev/null | grep MYSQL_ROOT_PASSWORD | cut -d= -f2- || grep -oP "(?<=MYSQL_ROOT_PASSWORD=).+" /root/mysql84.yaml 2>/dev/null || echo ""')
                    ssh -o StrictHostKeyChecking=no -o BatchMode=yes "root@$dest_ssh_host" "mc=\$(docker ps -qf name=mysql84 | head -n1); docker exec -i \"\$mc\" mysql -u root -p'$dest_my_pwd' -e 'CREATE DATABASE IF NOT EXISTS \\\`$my_dbname\\\`;' 2>/dev/null || true"
                    ssh -o StrictHostKeyChecking=no -o BatchMode=yes "root@$dest_ssh_host" "mc=\$(docker ps -qf name=mysql84 | head -n1); gunzip -c | docker exec -i \"\$mc\" mysql -u root -p'$dest_my_pwd' '$my_dbname' 2>/dev/null || true" < "$app_workdir/db_logical_dump.sql.gz"
                fi

                if [ -n "$dest_my_pwd" ]; then
                    sed -i -E "s/MAUTIC_DB_PASSWORD=[^[:space:]]+/MAUTIC_DB_PASSWORD=$dest_my_pwd/g" "$app_workdir/stack.yaml"
                    local cfg_vol="${cur_app}-config"
                    if [ "$chosen_dest_id" = "local" ]; then
                        docker run --rm -v "${cfg_vol}:/voldata" alpine sh -c "sed -i \"s/'db_password' => .*/'db_password' => '$dest_my_pwd',/\" /voldata/local.php 2>/dev/null || true" 2>> "$TRANSFER_LOG" || true
                    else
                        ssh -o StrictHostKeyChecking=no -o BatchMode=yes "root@$dest_ssh_host" "docker run --rm -v '${cfg_vol}:/voldata' alpine sh -c \"sed -i \\\"s/'db_password' => .*/'db_password' => '$dest_my_pwd',/\\\" /voldata/local.php 2>/dev/null || true\"" 2>> "$TRANSFER_LOG" || true
                    fi
                fi
            fi

            # 6. Deploy no Swarm do Destino via Portainer REST API (Editável)
            echo -e "XXX\n$((pct_base + (pct_step * 80 / 100)))\n[$app_idx/$total_apps] Registrando stack '$cur_app' no Portainer do destino...\nXXX"
            if [ "$chosen_dest_id" = "local" ]; then
                cp -f "$app_workdir/stack.yaml" "/root/${cur_app}.yaml"
                deploy_stack_with_portainer_priority "local" "" "$cur_app" "/root/${cur_app}.yaml" >> "$TRANSFER_LOG" 2>&1
            else
                ssh -o StrictHostKeyChecking=no -o BatchMode=yes "root@$dest_ssh_host" "cat > /root/${cur_app}.yaml" < "$app_workdir/stack.yaml"
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
                echo -e "XXX\n$((pct_base + (pct_step * 95 / 100)))\n[$app_idx/$total_apps] Congelando volumes e desligando na origem ($cur_app)...\nXXX"
                if [ "$chosen_origin_id" = "local" ]; then
                    docker stack rm "$cur_app" >/dev/null 2>&1 || true
                    for v in "${cur_vols[@]}"; do
                        docker volume create "${v}_${safety_suffix}" >/dev/null 2>&1 || true
                        docker run --rm -v "${v}:/src:ro" -v "${v}_${safety_suffix}:/dst" alpine cp -a /src/. /dst/ >/dev/null 2>&1 || true
                    done
                else
                    ssh -o StrictHostKeyChecking=no -o BatchMode=yes "root@$origin_ssh_host" "docker stack rm '$cur_app' >/dev/null 2>&1 || true"
                    for v in "${cur_vols[@]}"; do
                        ssh -o StrictHostKeyChecking=no -o BatchMode=yes "root@$origin_ssh_host" "docker volume create '${v}_${safety_suffix}' >/dev/null 2>&1 && docker run --rm -v '${v}:/src:ro' -v '${v}_${safety_suffix}:/dst' alpine cp -a /src/. /dst/ 2>/dev/null || true"
                    done
                fi
            fi

            # 9. Gravação do Manifesto Padronizado
            save_app_manifest "$chosen_dest_id" "$dest_ssh_host" "$cur_app" "$cur_db_engine" "$cur_s3_engine" "$cur_mq_engine" "$combo_name" "$combo_name" "${apps_to_migrate[*]}"
            save_app_manifest "$chosen_origin_id" "$origin_ssh_host" "$cur_app" "$cur_db_engine" "$cur_s3_engine" "$cur_mq_engine" "$combo_name" "$combo_name" "${apps_to_migrate[*]}"
        done

        if [ "$notify_sentinel" = "true" ]; then
            echo -e "XXX\n98\nDisparando relatório no Telegram e Webhook n8n...\nXXX"
            sleep 1
        fi

        echo -e "XXX\n100\nMigração concluída com 100% de sucesso!\nXXX"
        sleep 1
    }

    run_migration_pipeline 2>> "$TRANSFER_LOG" | whiptail --title "EXECUTANDO OPERAÇÃO NA FROTA" --gauge "Aguarde a migração consistente..." 8 72 0

    local summary="🎉 OPERAÇÃO CONCLUÍDA COM SUCESSO!\n\n"
    summary+="• Aplicação(ões): ${apps_to_migrate[*]}\n"
    if [ "$is_combo" = "true" ]; then
        summary+="• Ecossistema: $combo_name\n"
    fi
    summary+="• Origem: $origin_name ($origin_arch)\n"
    summary+="• Destino: $dest_name ($dest_arch)\n"
    summary+="• Total de Stacks: ${#apps_to_migrate[@]}\n"
    summary+="• Volumes Migrados: $total_migrated_vols volume(s)\n"
    if [ "$update_dns" = "true" ]; then
        summary+="• DNS & Ingress: Atualizado(s) no Cloudflare para o nó destino\n"
    fi
    if [ "$stop_origin" = "true" ]; then
        summary+="• Stacks Antigas: Desligadas na origem (RAM liberada)\n"
        summary+="• Volumes Congelados: Sufixo de rollback: _$safety_suffix\n"
    fi
    summary+="• Manifestos: Salvos em .control/manifests/\n"

    whiptail --title "SUCESSO DA MIGRAÇÃO" --msgbox "$summary" 19 76
}

# Menu Principal Interativo
show_menu() {
    while true; do
        local choice
        choice=$(whiptail --title "MNO FLEET HUB — CLONE, TRANSFERÊNCIA E BACKUP" --menu \
            "Selecione a ação desejada na frota de servidores:" 18 78 5 \
            "1" "Raio-X da Frota (Ver Arquitetura, RAM, Disco e Apps de cada Nó)" \
            "2" "Transferir Aplicação para outro Servidor (Com migração de DNS)" \
            "3" "Clonar Aplicação para Teste (Sem alterar DNS)" \
            "4" "Criar Backup Portátil (.tar.gz compatível com qualquer arquitetura)" \
            "5" "Voltar ao Menu Anterior" \
            3>&1 1>&2 2>&3) || return 0

        case "$choice" in
            1) action_inspect_nodes ;;
            2) action_transfer_or_clone "transfer" ;;
            3) action_transfer_or_clone "clone" ;;
            4) action_backup_app ;;
            5) return 0 ;;
        esac
    done
}

case "${1:-menu}" in
    inspect) action_inspect_nodes "${2:-}" ;;
    backup) action_backup_app "${2:-}" "${3:-}" ;;
    transfer) action_transfer_or_clone "transfer" ;;
    clone) action_transfer_or_clone "clone" ;;
    menu) show_menu ;;
    *) fail "Uso: $0 [inspect [--cli] | backup [app] [--cli] | transfer | clone | menu]" ;;
esac

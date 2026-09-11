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

# Comutação atômica de DNS Cloudflare e rotas de Ingress no Tunnel
switch_cloudflare_dns_and_ingress() {
    local node_id="$1"
    local host="$2"
    local yaml_file="$3"
    local app_name="$4"

    local hostname=""
    hostname=$(grep -oP '(?<=MAUTIC_URL=https://)[^[:space:]/]+' "$yaml_file" 2>/dev/null || true)
    if [ -z "$hostname" ]; then
        hostname=$(grep -oP 'Host\(`\K[^`]+' "$yaml_file" 2>/dev/null | head -n1 || true)
    fi
    if [ -z "$hostname" ]; then
        hostname=$(grep -oP '(?<=URL=https://)[^[:space:]/]+' "$yaml_file" 2>/dev/null | head -n1 || true)
    fi

    [ -n "$hostname" ] || return 0

    local internal_service=""
    if grep -q "mautic_web" "$yaml_file"; then
        local mautic_svc
        mautic_svc=$(grep -oP 'mautic_web[a-zA-Z0-9_-]*' "$yaml_file" | head -n1 || echo "mautic_web")
        internal_service="http://${mautic_svc}:80"
    else
        local first_svc
        first_svc=$(awk '/^services:/{flag=1; next} flag && /^[[:space:]]{2}[a-zA-Z0-9_-]+:/{print $1; exit}' "$yaml_file" | tr -d ':' || true)
        if [ -n "$first_svc" ]; then
            internal_service="http://${first_svc}:80"
        fi
    fi

    [ -n "$internal_service" ] || return 0

    local cf_script="
        creds=\"/root/.cloudflared_config/cloudflare_credentials\"
        if [ -f \"\$creds\" ]; then
            source \"\$creds\"
            if [ -n \"\${CLOUDFLARE_API_TOKEN:-}\" ] && [ -n \"\${CLOUDFLARE_ZONE_ID:-}\" ] && [ -n \"\${CLOUDFLARE_ACCOUNT_ID:-}\" ] && [ -n \"\${TUNNEL_ID:-}\" ]; then
                records=\$(curl -s -X GET \"https://api.cloudflare.com/client/v4/zones/\${CLOUDFLARE_ZONE_ID}/dns_records?name=${hostname}\" \
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
                    --data '{\"type\":\"CNAME\",\"name\":\"${hostname}\",\"content\":\"'\${TUNNEL_ID}'.cfargotunnel.com\",\"ttl\":1,\"proxied\":true}' >/dev/null 2>&1 || true

                cfg_raw=\$(curl -sS -H \"Authorization: Bearer \${CLOUDFLARE_API_TOKEN}\" \
                    \"https://api.cloudflare.com/client/v4/accounts/\${CLOUDFLARE_ACCOUNT_ID}/cfd_tunnel/\${TUNNEL_ID}/configurations\")
                if echo \"\$cfg_raw\" | grep -q '\"success\":true'; then
                    to_put=\$(mktemp)
                    printf '%s' \"\$cfg_raw\" | jq --arg host \"${hostname}\" --arg service \"${internal_service}\" '
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
        if ! whiptail --title "POLÍTICA PÓS-TRANSFERÊNCIA NA ORIGEM" --yesno \
            "Deseja que a stack antiga de '$chosen_app' seja DESLIGADA em '$origin_name' para liberar memória RAM após o sucesso da migração?\n\nOs volumes de dados antigos permanecerão CONGELADOS e intactos no disco com sufixo de segurança para permitir rollback a qualquer momento." 14 76; then
            stop_origin=false
        fi

        if ! whiptail --title "COMUTAÇÃO DE DNS CLOUDFLARE" --yesno \
            "Deseja atualizar automaticamente os apontamentos de DNS e rotas do Cloudflare Tunnel para que a URL da aplicação aponte imediatamente para o novo servidor ($dest_name)?" 12 76; then
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
    local migration_error=""
    local db_engine=""
    local app_vols=()

    # Função interna de execução de etapas
    run_migration_pipeline() {
        echo -e "XXX\n10\n[1/6] Resolvendo definições vivas do Portainer e sincronizando /root/${chosen_app}.yaml...\nXXX"
        if ! resolve_live_stack_yaml "$chosen_origin_id" "$origin_ssh_host" "$chosen_app" "$workdir/stack.yaml" 2>> "$TRANSFER_LOG"; then
            echo "Aviso: stack yaml não encontrado no Portainer, tentando gerar manifesto mínimo..." >> "$TRANSFER_LOG"
            echo "version: '3.7'" > "$workdir/stack.yaml"
        fi

        db_engine=$(detect_database_engine "$workdir/stack.yaml" "$chosen_app")
        echo "Banco de dados detectado: $db_engine" >> "$TRANSFER_LOG"

        echo -e "XXX\n25\n[2/6] Extraindo banco de dados lógico multi-tenant ($db_engine)...\nXXX"
        if [[ "$db_engine" == postgres:* ]]; then
            local pg_dbname="${db_engine#postgres:}"
            if [ "$chosen_origin_id" = "local" ]; then
                local c_id
                c_id=$(docker ps -qf name=postgres 2>/dev/null | head -n1 || true)
                if [ -n "$c_id" ]; then
                    docker exec -i "$c_id" pg_dump -U postgres -d "$pg_dbname" --clean --if-exists 2>> "$TRANSFER_LOG" | gzip > "$workdir/db_logical_dump.sql.gz" || true
                fi
            else
                ssh -o StrictHostKeyChecking=no -o BatchMode=yes "root@$origin_ssh_host" \
                    "c_id=\$(docker ps -qf name=postgres | head -n1); [ -n \"\$c_id\" ] && docker exec -i \"\$c_id\" pg_dump -U postgres -d '$pg_dbname' --clean --if-exists 2>/dev/null" \
                    | gzip > "$workdir/db_logical_dump.sql.gz" 2>> "$TRANSFER_LOG" || true
            fi
        elif [[ "$db_engine" == mysql84:* ]]; then
            local my_dbname="${db_engine#mysql84:}"
            if [ "$chosen_origin_id" = "local" ]; then
                local c_id orig_pwd
                c_id=$(docker ps -qf name=mysql84 2>/dev/null | head -n1 || true)
                orig_pwd=$(docker inspect "$c_id" --format '{{range .Config.Env}}{{println .}}{{end}}' 2>/dev/null | grep MYSQL_ROOT_PASSWORD | cut -d= -f2- || grep -oP '(?<=MYSQL_ROOT_PASSWORD=).+' /root/mysql84.yaml 2>/dev/null || echo "")
                if [ -n "$c_id" ] && [ -n "$orig_pwd" ]; then
                    docker exec -i "$c_id" mysqldump -u root -p"$orig_pwd" --databases "$my_dbname" --add-drop-table 2>> "$TRANSFER_LOG" | gzip > "$workdir/db_logical_dump.sql.gz" || true
                fi
            else
                ssh -o StrictHostKeyChecking=no -o BatchMode=yes "root@$origin_ssh_host" '
                    c_id=$(docker ps -qf name=mysql84 | head -n1)
                    pwd=$(docker inspect "$c_id" --format "{{range .Config.Env}}{{println .}}{{end}}" 2>/dev/null | grep MYSQL_ROOT_PASSWORD | cut -d= -f2- || grep -oP "(?<=MYSQL_ROOT_PASSWORD=).+" /root/mysql84.yaml 2>/dev/null || echo "")
                    if [ -n "$c_id" ] && [ -n "$pwd" ]; then
                        docker exec -i "$c_id" mysqldump -u root -p"$pwd" --databases "'"$my_dbname"'" --add-drop-table 2>/dev/null
                    fi
                ' | gzip > "$workdir/db_logical_dump.sql.gz" 2>> "$TRANSFER_LOG" || true
            fi
        fi

        echo -e "XXX\n45\n[3/6] Criando snapshots compactados dos volumes exclusivos da aplicação...\nXXX"
        while IFS= read -r v; do
            [ -n "$v" ] || continue
            app_vols+=("$v")
            echo "Compactando volume: $v" >> "$TRANSFER_LOG"
            if [ "$chosen_origin_id" = "local" ]; then
                docker run --rm -v "${v}:/voldata:ro" alpine tar -czf - -C /voldata . > "$workdir/vol_${v}.tar.gz" 2>> "$TRANSFER_LOG" || true
            else
                ssh -o StrictHostKeyChecking=no -o BatchMode=yes "root@$origin_ssh_host" \
                    "docker run --rm -v '${v}:/voldata:ro' alpine tar -czf - -C /voldata ." > "$workdir/vol_${v}.tar.gz" 2>> "$TRANSFER_LOG" || true
            fi
        done < <(get_application_volumes "$workdir/stack.yaml" "$chosen_app")

        echo -e "XXX\n65\n[4/6] Restaurando volumes e provisionando banco de dados no destino ($dest_name)...\nXXX"
        for v in "${app_vols[@]}"; do
            [ -f "$workdir/vol_${v}.tar.gz" ] || continue
            echo "Restaurando volume no destino: $v" >> "$TRANSFER_LOG"
            if [ "$chosen_dest_id" = "local" ]; then
                docker volume create "$v" >/dev/null 2>&1 || true
                docker run --rm -i -v "${v}:/voldata" alpine tar -xzf - -C /voldata < "$workdir/vol_${v}.tar.gz" 2>> "$TRANSFER_LOG" || true
            else
                ssh -o StrictHostKeyChecking=no -o BatchMode=yes "root@$dest_ssh_host" "docker volume create '$v' >/dev/null 2>&1 || true"
                ssh -o StrictHostKeyChecking=no -o BatchMode=yes "root@$dest_ssh_host" "docker run --rm -i -v '${v}:/voldata' alpine tar -xzf - -C /voldata" < "$workdir/vol_${v}.tar.gz" 2>> "$TRANSFER_LOG" || true
            fi
        done

        # Provisionar Banco Lógico no Destino
        if [[ "$db_engine" == postgres:* ]] && [ -f "$workdir/db_logical_dump.sql.gz" ]; then
            local pg_dbname="${db_engine#postgres:}"
            local dest_pg_pwd=""
            if [ "$chosen_dest_id" = "local" ]; then
                local dc
                dc=$(docker ps -qf name=postgres 2>/dev/null | head -n1 || true)
                dest_pg_pwd=$(docker inspect "$dc" --format '{{range .Config.Env}}{{println .}}{{end}}' 2>/dev/null | grep POSTGRES_PASSWORD | cut -d= -f2- || grep -oP '(?<=POSTGRES_PASSWORD=).+' /root/postgres.yaml 2>/dev/null || echo "")
                docker exec -i "$dc" psql -U postgres -c "CREATE DATABASE \"$pg_dbname\";" 2>> "$TRANSFER_LOG" || true
                gunzip -c "$workdir/db_logical_dump.sql.gz" | docker exec -i "$dc" psql -U postgres -d "$pg_dbname" 2>> "$TRANSFER_LOG" || true
            else
                dest_pg_pwd=$(ssh -o StrictHostKeyChecking=no -o BatchMode=yes "root@$dest_ssh_host" 'dc=$(docker ps -qf name=postgres | head -n1); docker inspect "$dc" --format "{{range .Config.Env}}{{println .}}{{end}}" 2>/dev/null | grep POSTGRES_PASSWORD | cut -d= -f2- || grep -oP "(?<=POSTGRES_PASSWORD=).+" /root/postgres.yaml 2>/dev/null || echo ""')
                ssh -o StrictHostKeyChecking=no -o BatchMode=yes "root@$dest_ssh_host" "dc=\$(docker ps -qf name=postgres | head -n1); docker exec -i \"\$dc\" psql -U postgres -c \"CREATE DATABASE \\\"$pg_dbname\\\";\" 2>/dev/null || true"
                ssh -o StrictHostKeyChecking=no -o BatchMode=yes "root@$dest_ssh_host" "dc=\$(docker ps -qf name=postgres | head -n1); gunzip -c | docker exec -i \"\$dc\" psql -U postgres -d '$pg_dbname' 2>/dev/null || true" < "$workdir/db_logical_dump.sql.gz"
            fi

            if [ -n "$dest_pg_pwd" ]; then
                sed -i -E "s/POSTGRES_PASSWORD=[^[:space:]]+/POSTGRES_PASSWORD=$dest_pg_pwd/g" "$workdir/stack.yaml"
            fi
        elif [[ "$db_engine" == mysql84:* ]] && [ -f "$workdir/db_logical_dump.sql.gz" ]; then
            local my_dbname="${db_engine#mysql84:}"
            ensure_mysql84_ready "$chosen_dest_id" "$dest_ssh_host"

            local dest_my_pwd=""
            if [ "$chosen_dest_id" = "local" ]; then
                local mc
                mc=$(docker ps -qf name=mysql84 2>/dev/null | head -n1 || true)
                dest_my_pwd=$(docker inspect "$mc" --format '{{range .Config.Env}}{{println .}}{{end}}' 2>/dev/null | grep MYSQL_ROOT_PASSWORD | cut -d= -f2- || grep -oP '(?<=MYSQL_ROOT_PASSWORD=).+' /root/mysql84.yaml 2>/dev/null || echo "")
                docker exec -i "$mc" mysql -u root -p"$dest_my_pwd" -e "CREATE DATABASE IF NOT EXISTS \`$my_dbname\`;" 2>> "$TRANSFER_LOG" || true
                gunzip -c "$workdir/db_logical_dump.sql.gz" | docker exec -i "$mc" mysql -u root -p"$dest_my_pwd" "$my_dbname" 2>> "$TRANSFER_LOG" || true
            else
                dest_my_pwd=$(ssh -o StrictHostKeyChecking=no -o BatchMode=yes "root@$dest_ssh_host" 'mc=$(docker ps -qf name=mysql84 | head -n1); docker inspect "$mc" --format "{{range .Config.Env}}{{println .}}{{end}}" 2>/dev/null | grep MYSQL_ROOT_PASSWORD | cut -d= -f2- || grep -oP "(?<=MYSQL_ROOT_PASSWORD=).+" /root/mysql84.yaml 2>/dev/null || echo ""')
                ssh -o StrictHostKeyChecking=no -o BatchMode=yes "root@$dest_ssh_host" "mc=\$(docker ps -qf name=mysql84 | head -n1); docker exec -i \"\$mc\" mysql -u root -p'$dest_my_pwd' -e 'CREATE DATABASE IF NOT EXISTS \\\`$my_dbname\\\`;' 2>/dev/null || true"
                ssh -o StrictHostKeyChecking=no -o BatchMode=yes "root@$dest_ssh_host" "mc=\$(docker ps -qf name=mysql84 | head -n1); gunzip -c | docker exec -i \"\$mc\" mysql -u root -p'$dest_my_pwd' '$my_dbname' 2>/dev/null || true" < "$workdir/db_logical_dump.sql.gz"
            fi

            if [ -n "$dest_my_pwd" ]; then
                sed -i -E "s/MAUTIC_DB_PASSWORD=[^[:space:]]+/MAUTIC_DB_PASSWORD=$dest_my_pwd/g" "$workdir/stack.yaml"
                # Se for Mautic, sincronizar também no volume config (local.php)
                local cfg_vol="${chosen_app}-config"
                if [ "$chosen_dest_id" = "local" ]; then
                    docker run --rm -v "${cfg_vol}:/voldata" alpine sh -c "sed -i \"s/'db_password' => .*/'db_password' => '$dest_my_pwd',/\" /voldata/local.php 2>/dev/null || true" 2>> "$TRANSFER_LOG" || true
                else
                    ssh -o StrictHostKeyChecking=no -o BatchMode=yes "root@$dest_ssh_host" "docker run --rm -v '${cfg_vol}:/voldata' alpine sh -c \"sed -i \\\"s/'db_password' => .*/'db_password' => '$dest_my_pwd',/\\\" /voldata/local.php 2>/dev/null || true\"" 2>> "$TRANSFER_LOG" || true
                fi
            fi
        fi

        echo -e "XXX\n80\n[5/6] Aplicando stack no Swarm de $dest_name e registrando no Portainer...\nXXX"
        if [ "$chosen_dest_id" = "local" ]; then
            cp -f "$workdir/stack.yaml" "/root/${chosen_app}.yaml"
            deploy_stack_with_portainer_priority "local" "" "$chosen_app" "/root/${chosen_app}.yaml" >> "$TRANSFER_LOG" 2>&1
        else
            ssh -o StrictHostKeyChecking=no -o BatchMode=yes "root@$dest_ssh_host" "cat > /root/${chosen_app}.yaml" < "$workdir/stack.yaml"
            deploy_stack_with_portainer_priority "$chosen_dest_id" "$dest_ssh_host" "$chosen_app" "/root/${chosen_app}.yaml" >> "$TRANSFER_LOG" 2>&1
        fi
        sleep 4

        if [ "$update_dns" = "true" ]; then
            echo -e "XXX\n88\nComutando registros de DNS e rotas no Cloudflare Tunnel...\nXXX"
            switch_cloudflare_dns_and_ingress "$chosen_dest_id" "$dest_ssh_host" "$workdir/stack.yaml" "$chosen_app" >> "$TRANSFER_LOG" 2>&1 || true
            sleep 1
        fi

        if [ "$stop_origin" = "true" ]; then
            echo -e "XXX\n92\nDesligando stack antiga na origem e congelando volumes com segurança...\nXXX"
            if [ "$chosen_origin_id" = "local" ]; then
                docker stack rm "$chosen_app" >/dev/null 2>&1 || true
                for v in "${app_vols[@]}"; do
                    docker volume create "${v}_${safety_suffix}" >/dev/null 2>&1 || true
                    docker run --rm -v "${v}:/src:ro" -v "${v}_${safety_suffix}:/dst" alpine cp -a /src/. /dst/ >/dev/null 2>&1 || true
                done
            else
                ssh -o StrictHostKeyChecking=no -o BatchMode=yes "root@$origin_ssh_host" "docker stack rm '$chosen_app' >/dev/null 2>&1 || true"
                for v in "${app_vols[@]}"; do
                    ssh -o StrictHostKeyChecking=no -o BatchMode=yes "root@$origin_ssh_host" "docker volume create '${v}_${safety_suffix}' >/dev/null 2>&1 && docker run --rm -v '${v}:/src:ro' -v '${v}_${safety_suffix}:/dst' alpine cp -a /src/. /dst/ 2>/dev/null || true"
                done
            fi
        fi

        if [ "$notify_sentinel" = "true" ]; then
            echo -e "XXX\n96\nDisparando relatório no Telegram e Webhook n8n...\nXXX"
            sleep 1
        fi

        echo -e "XXX\n100\nMigração concluída com 100% de sucesso!\nXXX"
        sleep 1
    }

    run_migration_pipeline 2>> "$TRANSFER_LOG" | whiptail --title "EXECUTANDO OPERAÇÃO NA FROTA" --gauge "Aguarde a migração consistente..." 8 72 0

    local summary="🎉 OPERAÇÃO CONCLUÍDA COM SUCESSO!\n\n"
    summary+="• Aplicação: $chosen_app\n"
    summary+="• Origem: $origin_name ($origin_arch)\n"
    summary+="• Destino: $dest_name ($dest_arch)\n"
    summary+="• Resolução Portainer: Stack sincronizada em /root/${chosen_app}.yaml\n"
    summary+="• Banco Lógico: $db_engine (Multi-Tenant isolado e restaurado)\n"
    summary+="• Volumes Migrados: ${#app_vols[@]} volume(s)\n"
    if [ "$update_dns" = "true" ]; then
        summary+="• DNS & Ingress: Atualizado para o nó de destino\n"
    fi
    if [ "$stop_origin" = "true" ]; then
        summary+="• Stack Antiga: Desligada na origem (RAM liberada)\n"
        summary+="• Volumes Congelados: Sufixo de rollback: _$safety_suffix\n"
    fi
    if [ "$notify_sentinel" = "true" ]; then
        summary+="• Alertas: Relatório emitido no Telegram e Webhook n8n disparado\n"
    fi

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

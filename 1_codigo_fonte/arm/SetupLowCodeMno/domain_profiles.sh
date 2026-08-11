#!/usr/bin/bash
# Camada aditiva de perfis de domínio do Setup MNO.
# Este arquivo não contém credenciais. Os tokens permanecem em arquivos 0600.

: "${SETUPMNO_DOMAIN_STATE_DIR:=/root/.setupmno/domains}"
: "${SETUPMNO_DOMAIN_REGISTRY:=${SETUPMNO_DOMAIN_STATE_DIR}/registry.json}"
: "${SETUPMNO_DOMAIN_CREDENTIALS_DIR:=${SETUPMNO_DOMAIN_STATE_DIR}/credentials.d}"
: "${SETUPMNO_DOMAIN_TUNNELS_DIR:=${SETUPMNO_DOMAIN_STATE_DIR}/tunnels}"
: "${SETUPMNO_DOMAIN_APP_LIST:=/root/SetupLowCodeMno/domain_profile_apps.list}"
: "${SETUPMNO_CF_API_BASE:=https://api.cloudflare.com/client/v4}"

setupmno_domain_msg() {
    whiptail --title "DOMÍNIOS CLOUDFLARE" --msgbox "$1" 22 84 1>&2
}

setupmno_domain_error() {
    whiptail --title "ERRO NOS DOMÍNIOS CLOUDFLARE" --msgbox "$1" 22 84 1>&2
}

setupmno_domain_requirements() {
    command -v jq >/dev/null 2>&1 || {
        setupmno_domain_error "O utilitário jq não está instalado. Atualize os componentes essenciais do Setup MNO e tente novamente."
        return 1
    }
    command -v curl >/dev/null 2>&1 || {
        setupmno_domain_error "O utilitário curl não está instalado. Atualize os componentes essenciais do Setup MNO e tente novamente."
        return 1
    }
}

setupmno_domain_prepare_dirs() {
    umask 077
    mkdir -p "$SETUPMNO_DOMAIN_CREDENTIALS_DIR" "$SETUPMNO_DOMAIN_TUNNELS_DIR" || return 1
    chmod 700 "$SETUPMNO_DOMAIN_STATE_DIR" "$SETUPMNO_DOMAIN_CREDENTIALS_DIR" "$SETUPMNO_DOMAIN_TUNNELS_DIR" || return 1
}

setupmno_domain_normalize() {
    local value="$1"
    value=$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')
    value=${value%.}
    printf '%s' "$value"
}

setupmno_domain_name_valid() {
    local value="$1" label
    [ "${#value}" -le 253 ] || return 1
    [[ "$value" == *.* ]] || return 1
    [[ "$value" =~ ^[a-z0-9]([a-z0-9.-]*[a-z0-9])?$ ]] || return 1
    [[ "$value" != *..* ]] || return 1
    IFS='.' read -r -a labels <<<"$value"
    for label in "${labels[@]}"; do
        [ -n "$label" ] && [ "${#label}" -le 63 ] || return 1
        [[ "$label" != -* && "$label" != *- ]] || return 1
    done
}

setupmno_domain_registry_valid() {
    local registry="${1:-$SETUPMNO_DOMAIN_REGISTRY}" size
    [ -f "$registry" ] && [ ! -L "$registry" ] || return 1
    size=$(stat -c '%s' "$registry" 2>/dev/null) || return 1
    [ "$size" -gt 0 ] && [ "$size" -le 131072 ] || return 1
    jq -e '
        .schemaVersion == 1 and
        (.primaryProfileId | type == "string" and length > 0) and
        (.profiles | type == "array" and length > 0) and
        ([.profiles[].id] | length == (unique | length)) and
        ([.profiles[].rootDomain] | length == (unique | length)) and
        (.primaryProfileId as $primary | any(.profiles[]; .id == $primary and .infrastructure == true)) and
        all(.profiles[];
            (.id | type == "string" and length > 0) and
            (.rootDomain | type == "string" and length > 0) and
            (.zoneId | type == "string" and length > 0) and
            (.accountId | type == "string" and length > 0) and
            (.installationType == "TRADICIONAL" or .installationType == "CLOUDFLARE_TUNNEL") and
            (.credentialFile | type == "string" and length > 0)
        )
    ' "$registry" >/dev/null 2>&1
}

setupmno_domain_credential_path_valid() {
    local path="$1" resolved allowed_secondary permissions owner
    [ -f "$path" ] && [ ! -L "$path" ] || return 1
    [ "$(stat -c '%s' "$path" 2>/dev/null || printf '999999')" -le 16384 ] || return 1
    owner=$(stat -c '%u' "$path" 2>/dev/null) || return 1
    permissions=$(stat -c '%a' "$path" 2>/dev/null) || return 1
    [ "$owner" = "0" ] || [ "${SETUPMNO_DOMAIN_TEST_MODE:-0}" = "1" ] || return 1
    [ $((8#$permissions & 077)) -eq 0 ] || return 1
    resolved=$(realpath -m "$path" 2>/dev/null) || return 1
    allowed_secondary=$(realpath -m "$SETUPMNO_DOMAIN_CREDENTIALS_DIR" 2>/dev/null) || return 1
    case "$resolved" in
        /root/.cloudflared_config/cloudflare_credentials|/root/.tradicional_config/tradicional_credentials|"$allowed_secondary"/*) ;;
        *) return 1 ;;
    esac
}

setupmno_domain_atomic_json() {
    local source_file="$1" destination="$2" temporary
    temporary=$(mktemp "${destination}.tmp.XXXXXX") || return 1
    chmod 600 "$temporary" || { rm -f "$temporary"; return 1; }
    jq '.' "$source_file" >"$temporary" || { rm -f "$temporary"; return 1; }
    mv -f "$temporary" "$destination"
}

setupmno_cf_request() {
    local method="$1" endpoint="$2" token="$3" output="$4" data_file="${5:-}"
    local args
    args=(-sS --connect-timeout 10 --max-time 45 -X "$method"
          -H "Authorization: Bearer $token"
          -H "Content-Type: application/json"
          "${SETUPMNO_CF_API_BASE}${endpoint}")
    if [ -n "$data_file" ]; then
        args+=(--data-binary "@$data_file")
    fi
    curl "${args[@]}" >"$output" 2>/dev/null
}

setupmno_cf_success() {
    jq -e '.success == true' "$1" >/dev/null 2>&1
}

setupmno_cf_error_text() {
    local file="$1" fallback="${2:-A Cloudflare recusou a operação.}"
    jq -r '[.errors[]?.message, .messages[]?.message] | map(select(length > 0)) | join("\n")' "$file" 2>/dev/null |
        awk -v fallback="$fallback" 'BEGIN{found=0} {if(length($0)){print; found=1}} END{if(!found) print fallback}' |
        head -c 2000
}

setupmno_domain_install_type() {
    local type_file="/root/.cloudflared_config/installation_type" value
    if [ -f "$type_file" ] && [ ! -L "$type_file" ]; then
        value=$(head -n 1 "$type_file" | tr -d '\r\n')
    else
        value="TRADICIONAL"
    fi
    case "$value" in
        TRADICIONAL|CLOUDFLARE_TUNNEL) printf '%s' "$value" ;;
        *) return 1 ;;
    esac
}

setupmno_primary_portainer_hostname() {
    local data_file="/root/dados_portainer/dados_portainer"
    [ -f "$data_file" ] && [ ! -L "$data_file" ] || return 1
    sed -n 's/^[[:space:]]*Dominio do portainer:[[:space:]]*//p' "$data_file" | head -n 1 | tr -d '\r'
}

setupmno_domain_bootstrap_primary() {
    local install_type credential_file verify_file zone_file zone_id account_id root_domain
    local tunnel_id="" portainer_hostname created_at temporary

    setupmno_domain_requirements || return 1
    if [ -e "$SETUPMNO_DOMAIN_REGISTRY" ] || [ -L "$SETUPMNO_DOMAIN_REGISTRY" ]; then
        setupmno_domain_registry_valid
        return $?
    fi
    install_type=$(setupmno_domain_install_type) || return 1
    if [ "$install_type" = "CLOUDFLARE_TUNNEL" ]; then
        credential_file="/root/.cloudflared_config/cloudflare_credentials"
    else
        credential_file="/root/.tradicional_config/tradicional_credentials"
    fi
    setupmno_domain_credential_path_valid "$credential_file" || return 1

    unset CLOUDFLARE_API_TOKEN CLOUDFLARE_ZONE_ID CLOUDFLARE_ACCOUNT_ID TUNNEL_ID
    # shellcheck disable=SC1090
    source "$credential_file"
    [ -n "${CLOUDFLARE_API_TOKEN:-}" ] && [ -n "${CLOUDFLARE_ZONE_ID:-}" ] || return 1
    zone_id="$CLOUDFLARE_ZONE_ID"
    verify_file=$(mktemp) || return 1
    zone_file=$(mktemp) || { rm -f "$verify_file"; return 1; }
    chmod 600 "$verify_file" "$zone_file"
    if ! setupmno_cf_request GET "/user/tokens/verify" "$CLOUDFLARE_API_TOKEN" "$verify_file" ||
       ! jq -e '.success == true and .result.status == "active"' "$verify_file" >/dev/null 2>&1 ||
       ! setupmno_cf_request GET "/zones/${zone_id}" "$CLOUDFLARE_API_TOKEN" "$zone_file" ||
       ! setupmno_cf_success "$zone_file"; then
        rm -f "$verify_file" "$zone_file"
        unset CLOUDFLARE_API_TOKEN CLOUDFLARE_ZONE_ID CLOUDFLARE_ACCOUNT_ID TUNNEL_ID
        return 1
    fi
    root_domain=$(jq -r '.result.name // empty' "$zone_file")
    account_id=$(jq -r '.result.account.id // empty' "$zone_file")
    [ -n "$root_domain" ] && [ -n "$account_id" ] || {
        rm -f "$verify_file" "$zone_file"
        return 1
    }
    if [ "$install_type" = "CLOUDFLARE_TUNNEL" ]; then
        tunnel_id="${TUNNEL_ID:-}"
        [ -n "$tunnel_id" ] || { rm -f "$verify_file" "$zone_file"; return 1; }
    fi
    portainer_hostname=$(setupmno_primary_portainer_hostname 2>/dev/null || true)
    created_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    setupmno_domain_prepare_dirs || { rm -f "$verify_file" "$zone_file"; return 1; }
    temporary=$(mktemp) || { rm -f "$verify_file" "$zone_file"; return 1; }
    jq -n \
        --arg root "$root_domain" --arg zone "$zone_id" --arg account "$account_id" \
        --arg type "$install_type" --arg credentials "$credential_file" \
        --arg tunnel "$tunnel_id" --arg portainer "$portainer_hostname" --arg now "$created_at" \
        '{
          schemaVersion: 1,
          primaryProfileId: "primary",
          profiles: [{
            id: "primary",
            name: "Domínio principal",
            rootDomain: $root,
            zoneId: $zone,
            accountId: $account,
            installationType: $type,
            credentialFile: $credentials,
            tunnelId: $tunnel,
            tunnelScope: (if $type == "CLOUDFLARE_TUNNEL" then "primary" else "none" end),
            infrastructure: true,
            portainerHostname: $portainer,
            status: "validated",
            createdAt: $now,
            validatedAt: $now
          }]
        }' >"$temporary" || { rm -f "$temporary" "$verify_file" "$zone_file"; return 1; }
    setupmno_domain_atomic_json "$temporary" "$SETUPMNO_DOMAIN_REGISTRY" || {
        rm -f "$temporary" "$verify_file" "$zone_file"
        return 1
    }
    rm -f "$temporary" "$verify_file" "$zone_file"
    unset CLOUDFLARE_API_TOKEN CLOUDFLARE_ZONE_ID CLOUDFLARE_ACCOUNT_ID TUNNEL_ID
    setupmno_domain_registry_valid
}

setupmno_domain_dns_write_probe() {
    local token="$1" zone_id="$2" root_domain="$3"
    local lookup payload response delete_response record_id probe_name
    lookup=$(mktemp) || return 1
    payload=$(mktemp) || { rm -f "$lookup"; return 1; }
    response=$(mktemp) || { rm -f "$lookup" "$payload"; return 1; }
    delete_response=$(mktemp) || { rm -f "$lookup" "$payload" "$response"; return 1; }
    chmod 600 "$lookup" "$payload" "$response" "$delete_response"
    probe_name="_setupmno-check-$(date +%s)-$(openssl rand -hex 3).${root_domain}"
    jq -n --arg name "$probe_name" --arg value "setupmno-domain-permission-check" \
        '{type:"TXT",name:$name,content:$value,ttl:120,comment:"Verificação temporária do Setup MNO"}' >"$payload"
    if ! setupmno_cf_request POST "/zones/${zone_id}/dns_records" "$token" "$response" "$payload" ||
       ! setupmno_cf_success "$response"; then
        SETUPMNO_DOMAIN_LAST_ERROR=$(setupmno_cf_error_text "$response" "O token não possui permissão para editar DNS nesta zona.")
        rm -f "$lookup" "$payload" "$response" "$delete_response"
        return 1
    fi
    record_id=$(jq -r '.result.id // empty' "$response")
    if [ -z "$record_id" ] ||
       ! setupmno_cf_request DELETE "/zones/${zone_id}/dns_records/${record_id}" "$token" "$delete_response" ||
       ! setupmno_cf_success "$delete_response"; then
        SETUPMNO_DOMAIN_LAST_ERROR="A permissão de criação foi confirmada, mas o registro temporário ${probe_name} não pôde ser removido. Remova-o no painel Cloudflare antes de tentar novamente."
        rm -f "$lookup" "$payload" "$response" "$delete_response"
        return 1
    fi
    rm -f "$lookup" "$payload" "$response" "$delete_response"
}

setupmno_domain_tunnel_write_probe() {
    local token="$1" account_id="$2" tunnel_id="$3" get_file put_file payload
    get_file=$(mktemp) || return 1
    put_file=$(mktemp) || { rm -f "$get_file"; return 1; }
    payload=$(mktemp) || { rm -f "$get_file" "$put_file"; return 1; }
    chmod 600 "$get_file" "$put_file" "$payload"
    if ! setupmno_cf_request GET "/accounts/${account_id}/cfd_tunnel/${tunnel_id}/configurations" "$token" "$get_file" ||
       ! setupmno_cf_success "$get_file"; then
        SETUPMNO_DOMAIN_LAST_ERROR=$(setupmno_cf_error_text "$get_file" "O token não pode consultar o túnel selecionado.")
        rm -f "$get_file" "$put_file" "$payload"
        return 1
    fi
    jq '{config:(.result.config // {ingress:[{service:"http_status:404"}]})}' "$get_file" >"$payload" || {
        rm -f "$get_file" "$put_file" "$payload"
        return 1
    }
    if ! setupmno_cf_request PUT "/accounts/${account_id}/cfd_tunnel/${tunnel_id}/configurations" "$token" "$put_file" "$payload" ||
       ! setupmno_cf_success "$put_file"; then
        SETUPMNO_DOMAIN_LAST_ERROR=$(setupmno_cf_error_text "$put_file" "O token não possui permissão para editar a configuração do túnel.")
        rm -f "$get_file" "$put_file" "$payload"
        return 1
    fi
    rm -f "$get_file" "$put_file" "$payload"
}

setupmno_domain_ensure_traditional_origin() {
    local token="$1" zone_id="$2" root_domain="$3" profile_id="$4"
    local public_ip origin_label origin_name lookup payload response record_id record_type method endpoint
    SETUPMNO_NEW_ORIGIN_CREATED=false
    public_ip=$(curl -4 -sS --connect-timeout 8 --max-time 20 https://api.ipify.org 2>/dev/null) || return 1
    [[ "$public_ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || {
        SETUPMNO_DOMAIN_LAST_ERROR="Não foi possível identificar o IPv4 público deste servidor."
        return 1
    }
    origin_label="setupmno-origin-${profile_id#domain-}"
    origin_name="${origin_label}.${root_domain}"
    lookup=$(mktemp) || return 1
    payload=$(mktemp) || { rm -f "$lookup"; return 1; }
    response=$(mktemp) || { rm -f "$lookup" "$payload"; return 1; }
    chmod 600 "$lookup" "$payload" "$response"
    if ! setupmno_cf_request GET "/zones/${zone_id}/dns_records?name=${origin_name}&per_page=5" "$token" "$lookup" ||
       ! setupmno_cf_success "$lookup"; then
        SETUPMNO_DOMAIN_LAST_ERROR=$(setupmno_cf_error_text "$lookup" "Falha ao consultar o registro de origem do servidor.")
        rm -f "$lookup" "$payload" "$response"
        return 1
    fi
    record_id=$(jq -r '.result[0].id // empty' "$lookup")
    record_type=$(jq -r '.result[0].type // empty' "$lookup")
    if [ -n "$record_id" ] && [ "$record_type" != "A" ]; then
        SETUPMNO_DOMAIN_LAST_ERROR="O hostname ${origin_name} já está ocupado por um registro ${record_type}. Nada foi alterado."
        rm -f "$lookup" "$payload" "$response"
        return 1
    fi
    if [ -n "$record_id" ]; then
        method="PUT"
        endpoint="/zones/${zone_id}/dns_records/${record_id}"
    else
        method="POST"
        endpoint="/zones/${zone_id}/dns_records"
    fi
    jq -n --arg name "$origin_name" --arg ip "$public_ip" \
        '{type:"A",name:$name,content:$ip,ttl:1,proxied:false,comment:"Origem do Setup MNO para aplicações deste domínio"}' >"$payload"
    if ! setupmno_cf_request "$method" "$endpoint" "$token" "$response" "$payload" ||
       ! setupmno_cf_success "$response"; then
        SETUPMNO_DOMAIN_LAST_ERROR=$(setupmno_cf_error_text "$response" "Falha ao preparar o endereço de origem do servidor.")
        rm -f "$lookup" "$payload" "$response"
        return 1
    fi
    SETUPMNO_NEW_ORIGIN_LABEL="$origin_label"
    SETUPMNO_NEW_ORIGIN_RECORD_ID=$(jq -r '.result.id // empty' "$response")
    [ "$method" = "POST" ] && SETUPMNO_NEW_ORIGIN_CREATED=true
    rm -f "$lookup" "$payload" "$response"
}

setupmno_domain_rollback_traditional_origin() {
    local token="$1" zone_id="$2" record_id="$3" created="$4" response
    [ "$created" = "true" ] && [ -n "$record_id" ] || return 0
    response=$(mktemp) || return 0
    chmod 600 "$response"
    setupmno_cf_request DELETE "/zones/${zone_id}/dns_records/${record_id}" "$token" "$response" || true
    rm -f "$response"
}

setupmno_domain_create_dedicated_tunnel() {
    local token="$1" account_id="$2" profile_id="$3"
    local secret payload response token_response tunnel_secret tunnel_id tunnel_token
    local tunnel_name secret_name stack_name stack_file token_file log_file attempt replicas ready=false
    secret=$(openssl rand -base64 32 | tr -d '\n') || return 1
    payload=$(mktemp) || return 1
    response=$(mktemp) || { rm -f "$payload"; return 1; }
    token_response=$(mktemp) || { rm -f "$payload" "$response"; return 1; }
    token_file=$(mktemp) || { rm -f "$payload" "$response" "$token_response"; return 1; }
    chmod 600 "$payload" "$response" "$token_response" "$token_file"
    tunnel_name="setupmno-${profile_id}"
    jq -n --arg name "$tunnel_name" --arg secret "$secret" \
        '{name:$name,config_src:"cloudflare",tunnel_secret:$secret}' >"$payload"
    if ! setupmno_cf_request POST "/accounts/${account_id}/cfd_tunnel" "$token" "$response" "$payload" ||
       ! setupmno_cf_success "$response"; then
        SETUPMNO_DOMAIN_LAST_ERROR=$(setupmno_cf_error_text "$response" "Não foi possível criar o túnel dedicado.")
        rm -f "$payload" "$response" "$token_response" "$token_file"
        return 1
    fi
    tunnel_id=$(jq -r '.result.id // empty' "$response")
    if [ -z "$tunnel_id" ] ||
       ! setupmno_cf_request GET "/accounts/${account_id}/cfd_tunnel/${tunnel_id}/token" "$token" "$token_response" ||
       ! setupmno_cf_success "$token_response"; then
        SETUPMNO_DOMAIN_LAST_ERROR="O túnel foi criado, mas a Cloudflare não entregou seu token. ID: ${tunnel_id:-indisponível}."
        [ -n "$tunnel_id" ] && setupmno_cf_request DELETE "/accounts/${account_id}/cfd_tunnel/${tunnel_id}" "$token" "$response" || true
        rm -f "$payload" "$response" "$token_response" "$token_file"
        return 1
    fi
    tunnel_token=$(jq -r '.result // empty' "$token_response")
    [ -n "$tunnel_token" ] || {
        SETUPMNO_DOMAIN_LAST_ERROR="A Cloudflare retornou um token de túnel vazio."
        setupmno_cf_request DELETE "/accounts/${account_id}/cfd_tunnel/${tunnel_id}" "$token" "$response" || true
        rm -f "$payload" "$response" "$token_response" "$token_file"
        return 1
    }
    printf '%s' "$tunnel_token" >"$token_file"
    secret_name="setupmno_domain_tunnel_${profile_id//-/_}"
    stack_name="setupmno-domain-${profile_id}"
    stack_file="${SETUPMNO_DOMAIN_TUNNELS_DIR}/${profile_id}.yaml"
    log_file="/tmp/${stack_name}-install.log"
    : >"$log_file"
    if ! command -v docker >/dev/null 2>&1 ||
       ! docker info --format '{{.Swarm.LocalNodeState}}' 2>/dev/null | grep -Fxq active ||
       ! docker network inspect externa >/dev/null 2>&1; then
        SETUPMNO_DOMAIN_LAST_ERROR="O Docker Swarm ou a rede externa não está disponível para iniciar o túnel dedicado."
        setupmno_cf_request DELETE "/accounts/${account_id}/cfd_tunnel/${tunnel_id}" "$token" "$response" || true
        rm -f "$payload" "$response" "$token_response" "$token_file"
        return 1
    fi
    if docker secret inspect "$secret_name" >/dev/null 2>&1 ||
       ! docker secret create "$secret_name" "$token_file" >>"$log_file" 2>&1; then
        SETUPMNO_DOMAIN_LAST_ERROR="Não foi possível criar com segurança o Docker Secret do túnel dedicado."
        setupmno_cf_request DELETE "/accounts/${account_id}/cfd_tunnel/${tunnel_id}" "$token" "$response" || true
        rm -f "$payload" "$response" "$token_response" "$token_file"
        return 1
    fi
    cat >"$stack_file" <<EOF
version: "3.7"
services:
  cloudflared:
    image: cloudflare/cloudflared
    command: tunnel run --token-file /run/secrets/${secret_name}
    secrets:
      - ${secret_name}
    networks:
      - externa
    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
          - node.role == manager
      resources:
        limits:
          cpus: "0.50"
          memory: 256M
secrets:
  ${secret_name}:
    external: true
networks:
  externa:
    external: true
EOF
    chmod 600 "$stack_file"
    if ! docker stack deploy --prune --resolve-image always -c "$stack_file" "$stack_name" >>"$log_file" 2>&1; then
        SETUPMNO_DOMAIN_LAST_ERROR="Falha ao iniciar a stack do túnel dedicado. Log: ${log_file}"
        docker secret rm "$secret_name" >>"$log_file" 2>&1 || true
        setupmno_cf_request DELETE "/accounts/${account_id}/cfd_tunnel/${tunnel_id}" "$token" "$response" || true
        rm -f "$payload" "$response" "$token_response" "$token_file"
        return 1
    fi
    for attempt in $(seq 1 45); do
        replicas=$(docker service ls --filter "name=${stack_name}_cloudflared" --format '{{.Replicas}}' 2>/dev/null | head -n 1)
        if [ "$replicas" = "1/1" ]; then
            ready=true
            break
        fi
        sleep 2
    done
    if [ "$ready" != "true" ]; then
        docker service ps --no-trunc "${stack_name}_cloudflared" >>"$log_file" 2>&1 || true
        SETUPMNO_DOMAIN_LAST_ERROR="O túnel dedicado foi criado, mas sua stack não atingiu 1/1 réplica. Log: ${log_file}"
        docker stack rm "$stack_name" >>"$log_file" 2>&1 || true
        for attempt in $(seq 1 20); do
            docker service inspect "${stack_name}_cloudflared" >/dev/null 2>&1 || break
            sleep 1
        done
        docker secret rm "$secret_name" >>"$log_file" 2>&1 || true
        setupmno_cf_request DELETE "/accounts/${account_id}/cfd_tunnel/${tunnel_id}" "$token" "$response" || true
        rm -f "$payload" "$response" "$token_response" "$token_file"
        return 1
    fi
    SETUPMNO_NEW_TUNNEL_ID="$tunnel_id"
    SETUPMNO_NEW_TUNNEL_NAME="$tunnel_name"
    SETUPMNO_NEW_TUNNEL_STACK="$stack_name"
    SETUPMNO_NEW_TUNNEL_SECRET="$secret_name"
    rm -f "$payload" "$response" "$token_response" "$token_file"
}

setupmno_domain_rollback_dedicated_tunnel() {
    local token="$1" account_id="$2" tunnel_id="$3" stack_name="$4" secret_name="$5"
    local response attempt services
    [ -n "$tunnel_id" ] || return 0
    if [ -n "$stack_name" ] && command -v docker >/dev/null 2>&1; then
        docker stack rm "$stack_name" >/dev/null 2>&1 || true
        for attempt in $(seq 1 20); do
            services=$(docker service ls --format '{{.Name}}' 2>/dev/null || true)
            grep -q "^${stack_name}_" <<<"$services" || break
            sleep 1
        done
    fi
    if [ -n "$secret_name" ] && command -v docker >/dev/null 2>&1; then
        docker secret rm "$secret_name" >/dev/null 2>&1 || true
    fi
    response=$(mktemp) || return 0
    chmod 600 "$response"
    setupmno_cf_request DELETE "/accounts/${account_id}/cfd_tunnel/${tunnel_id}" "$token" "$response" || true
    rm -f "$response"
}

setupmno_domain_write_credentials() {
    local destination="$1" token="$2" account_id="$3" zone_id="$4" root_domain="$5"
    local profile_id="$6" install_type="$7" tunnel_id="${8:-}" tunnel_name="${9:-}" origin_label="${10:-}"
    local temporary
    temporary=$(mktemp "${destination}.tmp.XXXXXX") || return 1
    chmod 600 "$temporary" || { rm -f "$temporary"; return 1; }
    {
        printf 'CLOUDFLARE_API_TOKEN=%q\n' "$token"
        printf 'CLOUDFLARE_ACCOUNT_ID=%q\n' "$account_id"
        printf 'CLOUDFLARE_ZONE_ID=%q\n' "$zone_id"
        printf 'SETUPMNO_DOMAIN_ROOT=%q\n' "$root_domain"
        printf 'SETUPMNO_DOMAIN_PROFILE_ID=%q\n' "$profile_id"
        if [ "$install_type" = "CLOUDFLARE_TUNNEL" ]; then
            printf 'TUNNEL_ID=%q\n' "$tunnel_id"
            printf 'TUNNEL_NAME=%q\n' "$tunnel_name"
        else
            printf 'nome_servidor=%q\n' "$origin_label"
            printf 'criar_dns=%q\n' "0"
        fi
    } >"$temporary" || { rm -f "$temporary"; return 1; }
    mv -f "$temporary" "$destination"
}

setupmno_domain_register() {
    local install_type root_domain token verify zone_result dns_read
    local zone_id account_id profile_id credentials primary_account primary_tunnel
    local tunnel_id="" tunnel_name="" tunnel_scope="none" owned_stack="" owned_secret=""
    local origin_label="" origin_record_id="" origin_created=false now temporary updated choice

    setupmno_domain_requirements || return 1
    setupmno_domain_bootstrap_primary || {
        setupmno_domain_error "Não foi possível validar e importar o domínio principal. Verifique a conexão, o token atual e o Zone ID antes de adicionar outro domínio. A instalação antiga foi preservada."
        return 1
    }
    install_type=$(setupmno_domain_install_type) || return 1
    root_domain=$(whiptail --title "NOVO DOMÍNIO" --inputbox \
        "Digite o domínio raiz que já está ativo na Cloudflare.\n\nExemplos: cliente.com ou empresa.com.br\n\nNão digite o subdomínio da aplicação." \
        16 78 3>&1 1>&2 2>&3) || return 130
    root_domain=$(setupmno_domain_normalize "$root_domain")
    if ! setupmno_domain_name_valid "$root_domain"; then
        setupmno_domain_error "O domínio informado é inválido. Digite somente o domínio raiz, como empresa.com.br."
        return 1
    fi
    if jq -e --arg root "$root_domain" 'any(.profiles[]; .rootDomain == $root)' "$SETUPMNO_DOMAIN_REGISTRY" >/dev/null; then
        setupmno_domain_error "O domínio ${root_domain} já está cadastrado. Nenhuma credencial foi alterada."
        return 1
    fi
    token=$(whiptail --title "API TOKEN DO NOVO DOMÍNIO" --passwordbox \
        "Cole uma API Token que tenha acesso a ${root_domain}.\n\nPermissões obrigatórias:\n- Zona > Zona > Leitura\n- Zona > DNS > Edição\n$([ "$install_type" = "CLOUDFLARE_TUNNEL" ] && printf '%s' '- Conta > Cloudflare Tunnel > Edição')\n\nO token não será exibido nem gravado em logs." \
        20 82 3>&1 1>&2 2>&3) || return 130
    [ -n "$token" ] || { setupmno_domain_error "A API Token não pode ficar vazia."; return 1; }

    verify=$(mktemp) || return 1
    zone_result=$(mktemp) || { rm -f "$verify"; return 1; }
    dns_read=$(mktemp) || { rm -f "$verify" "$zone_result"; return 1; }
    chmod 600 "$verify" "$zone_result" "$dns_read"
    whiptail --title "VALIDANDO CLOUDFLARE" --infobox "Validando token, zona, conta e permissões..." 8 70
    if ! setupmno_cf_request GET "/user/tokens/verify" "$token" "$verify" ||
       ! jq -e '.success == true and .result.status == "active"' "$verify" >/dev/null 2>&1; then
        setupmno_domain_error "A API Token é inválida, está expirada ou foi desativada.\n\n$(setupmno_cf_error_text "$verify" "A verificação do token falhou.")"
        rm -f "$verify" "$zone_result" "$dns_read"
        return 1
    fi
    if ! setupmno_cf_request GET "/zones?name=${root_domain}&status=active&per_page=5" "$token" "$zone_result" ||
       ! setupmno_cf_success "$zone_result" ||
       [ "$(jq '.result | length' "$zone_result" 2>/dev/null)" != "1" ]; then
        setupmno_domain_error "O token não encontrou exatamente uma zona ativa chamada ${root_domain}.\n\nConfirme se o domínio foi adicionado à Cloudflare e se o token possui Zona > Zona > Leitura para essa zona."
        rm -f "$verify" "$zone_result" "$dns_read"
        return 1
    fi
    zone_id=$(jq -r '.result[0].id // empty' "$zone_result")
    account_id=$(jq -r '.result[0].account.id // empty' "$zone_result")
    [ -n "$zone_id" ] && [ -n "$account_id" ] || {
        setupmno_domain_error "A Cloudflare não retornou os identificadores da zona e da conta."
        rm -f "$verify" "$zone_result" "$dns_read"
        return 1
    }
    if ! setupmno_cf_request GET "/zones/${zone_id}/dns_records?per_page=1" "$token" "$dns_read" ||
       ! setupmno_cf_success "$dns_read"; then
        setupmno_domain_error "O token não possui acesso de leitura ao DNS de ${root_domain}.\n\n$(setupmno_cf_error_text "$dns_read")"
        rm -f "$verify" "$zone_result" "$dns_read"
        return 1
    fi
    choice=$(whiptail --title "CONFIRMAR TESTE DE PERMISSÕES" --yesno \
        "Zona confirmada: ${root_domain}\nConta: ${account_id:0:8}...\nModo atual: ${install_type}\n\nPara confirmar DNS > Edição, o Setup MNO criará e removerá imediatamente um registro TXT temporário. Nenhum registro existente será modificado.\n\nDeseja continuar?" \
        18 82 3>&1 1>&2 2>&3; printf '%s' "$?")
    if [ "$choice" != "0" ]; then
        rm -f "$verify" "$zone_result" "$dns_read"
        return 130
    fi
    if ! setupmno_domain_dns_write_probe "$token" "$zone_id" "$root_domain"; then
        setupmno_domain_error "Não foi possível confirmar DNS > Edição.\n\n${SETUPMNO_DOMAIN_LAST_ERROR:-Permissão insuficiente.}\n\nEdite a API Token e tente novamente."
        rm -f "$verify" "$zone_result" "$dns_read"
        return 1
    fi

    profile_id="domain-$(printf '%s' "$root_domain" | sha256sum | cut -c1-12)"
    primary_account=$(jq -r '.primaryProfileId as $id | .profiles[] | select(.id == $id) | .accountId' "$SETUPMNO_DOMAIN_REGISTRY")
    if [ "$install_type" = "CLOUDFLARE_TUNNEL" ]; then
        if [ "$account_id" = "$primary_account" ]; then
            primary_tunnel=$(jq -r '.primaryProfileId as $id | .profiles[] | select(.id == $id) | .tunnelId // empty' "$SETUPMNO_DOMAIN_REGISTRY")
            if [ -z "$primary_tunnel" ] || ! setupmno_domain_tunnel_write_probe "$token" "$account_id" "$primary_tunnel"; then
                setupmno_domain_error "O domínio está na conta principal, mas o token não conseguiu editar o túnel existente.\n\n${SETUPMNO_DOMAIN_LAST_ERROR:-Adicione Conta > Cloudflare Tunnel > Edição ao token.}"
                rm -f "$verify" "$zone_result" "$dns_read"
                return 1
            fi
            tunnel_id="$primary_tunnel"
            tunnel_name="Túnel principal"
            tunnel_scope="shared-primary"
        else
            choice=$(whiptail --title "CONTA CLOUDFLARE DIFERENTE" --yesno \
                "O domínio ${root_domain} pertence a outra conta Cloudflare.\n\nPor segurança e por limitação da Cloudflare, será criado um túnel dedicado e uma pequena stack cloudflared (limite de 256 MB). Portainer e Control Center continuarão no domínio principal.\n\nDeseja criar o túnel dedicado agora?" \
                18 84 3>&1 1>&2 2>&3; printf '%s' "$?")
            if [ "$choice" != "0" ]; then
                rm -f "$verify" "$zone_result" "$dns_read"
                return 130
            fi
            whiptail --title "CRIANDO TÚNEL DEDICADO" --infobox "Criando o túnel e iniciando a conexão segura. Aguarde..." 8 74
            if ! setupmno_domain_create_dedicated_tunnel "$token" "$account_id" "$profile_id"; then
                setupmno_domain_error "O domínio não foi cadastrado.\n\n${SETUPMNO_DOMAIN_LAST_ERROR:-Falha ao criar o túnel dedicado.}"
                rm -f "$verify" "$zone_result" "$dns_read"
                return 1
            fi
            tunnel_id="$SETUPMNO_NEW_TUNNEL_ID"
            tunnel_name="$SETUPMNO_NEW_TUNNEL_NAME"
            tunnel_scope="dedicated-account"
            owned_stack="$SETUPMNO_NEW_TUNNEL_STACK"
            owned_secret="$SETUPMNO_NEW_TUNNEL_SECRET"
        fi
    else
        whiptail --title "PREPARANDO ORIGEM TRAEFIK" --infobox "Criando o endereço técnico de origem neste domínio. Aguarde..." 8 74
        if ! setupmno_domain_ensure_traditional_origin "$token" "$zone_id" "$root_domain" "$profile_id"; then
            setupmno_domain_error "O domínio não foi cadastrado.\n\n${SETUPMNO_DOMAIN_LAST_ERROR:-Falha ao preparar a origem do Traefik.}"
            rm -f "$verify" "$zone_result" "$dns_read"
            return 1
        fi
        origin_label="$SETUPMNO_NEW_ORIGIN_LABEL"
        origin_record_id="$SETUPMNO_NEW_ORIGIN_RECORD_ID"
        origin_created="$SETUPMNO_NEW_ORIGIN_CREATED"
    fi

    if ! setupmno_domain_prepare_dirs; then
        [ "$tunnel_scope" = "dedicated-account" ] &&
            setupmno_domain_rollback_dedicated_tunnel "$token" "$account_id" "$tunnel_id" "$owned_stack" "$owned_secret"
        setupmno_domain_rollback_traditional_origin "$token" "$zone_id" "$origin_record_id" "$origin_created"
        setupmno_domain_error "Não foi possível preparar o diretório protegido dos perfis. Os recursos recém-criados foram revertidos."
        rm -f "$verify" "$zone_result" "$dns_read"
        return 1
    fi
    credentials="${SETUPMNO_DOMAIN_CREDENTIALS_DIR}/${profile_id}.env"
    if ! setupmno_domain_write_credentials "$credentials" "$token" "$account_id" "$zone_id" "$root_domain" \
        "$profile_id" "$install_type" "$tunnel_id" "$tunnel_name" "$origin_label"; then
        if [ "$tunnel_scope" = "dedicated-account" ]; then
            setupmno_domain_rollback_dedicated_tunnel "$token" "$account_id" "$tunnel_id" "$owned_stack" "$owned_secret"
        fi
        setupmno_domain_rollback_traditional_origin "$token" "$zone_id" "$origin_record_id" "$origin_created"
        setupmno_domain_error "Não foi possível gravar a credencial protegida. O registro de perfis não foi alterado."
        rm -f "$verify" "$zone_result" "$dns_read"
        return 1
    fi
    now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    temporary=$(mktemp) || {
        [ "$tunnel_scope" = "dedicated-account" ] &&
            setupmno_domain_rollback_dedicated_tunnel "$token" "$account_id" "$tunnel_id" "$owned_stack" "$owned_secret"
        setupmno_domain_rollback_traditional_origin "$token" "$zone_id" "$origin_record_id" "$origin_created"
        rm -f "$credentials" "$verify" "$zone_result" "$dns_read"
        return 1
    }
    updated=$(mktemp) || {
        [ "$tunnel_scope" = "dedicated-account" ] &&
            setupmno_domain_rollback_dedicated_tunnel "$token" "$account_id" "$tunnel_id" "$owned_stack" "$owned_secret"
        setupmno_domain_rollback_traditional_origin "$token" "$zone_id" "$origin_record_id" "$origin_created"
        rm -f "$temporary" "$credentials" "$verify" "$zone_result" "$dns_read"
        return 1
    }
    jq -n --arg id "$profile_id" --arg name "$root_domain" --arg root "$root_domain" \
        --arg zone "$zone_id" --arg account "$account_id" --arg type "$install_type" \
        --arg credentials "$credentials" --arg tunnel "$tunnel_id" --arg tunnelName "$tunnel_name" \
        --arg tunnelScope "$tunnel_scope" --arg stack "$owned_stack" --arg secret "$owned_secret" \
        --arg originLabel "$origin_label" --arg originRecord "$origin_record_id" --arg now "$now" \
        '{id:$id,name:$name,rootDomain:$root,zoneId:$zone,accountId:$account,
          installationType:$type,credentialFile:$credentials,tunnelId:$tunnel,tunnelName:$tunnelName,
          tunnelScope:$tunnelScope,ownedStack:$stack,ownedSecret:$secret,
          originLabel:$originLabel,originRecordId:$originRecord,infrastructure:false,
          status:"validated",createdAt:$now,validatedAt:$now}' >"$temporary"
    jq --slurpfile profile "$temporary" '.profiles += [$profile[0]]' "$SETUPMNO_DOMAIN_REGISTRY" >"$updated" || {
        if [ "$tunnel_scope" = "dedicated-account" ]; then
            setupmno_domain_rollback_dedicated_tunnel "$token" "$account_id" "$tunnel_id" "$owned_stack" "$owned_secret"
        fi
        setupmno_domain_rollback_traditional_origin "$token" "$zone_id" "$origin_record_id" "$origin_created"
        rm -f "$temporary" "$updated" "$credentials" "$verify" "$zone_result" "$dns_read"
        return 1
    }
    if ! setupmno_domain_atomic_json "$updated" "$SETUPMNO_DOMAIN_REGISTRY" ||
       ! setupmno_domain_registry_valid; then
        if [ "$tunnel_scope" = "dedicated-account" ]; then
            setupmno_domain_rollback_dedicated_tunnel "$token" "$account_id" "$tunnel_id" "$owned_stack" "$owned_secret"
        fi
        setupmno_domain_rollback_traditional_origin "$token" "$zone_id" "$origin_record_id" "$origin_created"
        rm -f "$temporary" "$updated" "$credentials" "$verify" "$zone_result" "$dns_read"
        setupmno_domain_error "O registro multidomínio não passou na validação. A credencial adicional foi descartada."
        return 1
    fi
    rm -f "$temporary" "$updated" "$verify" "$zone_result" "$dns_read"
    setupmno_domain_msg "DOMÍNIO CADASTRADO COM SUCESSO!\n\nDomínio: ${root_domain}\nConta: ${account_id:0:8}...\nModo: ${install_type}\nTúnel: ${tunnel_scope}\n\nPortainer e Setup MNO Control Center permanecem fixos no domínio principal. Nas próximas instalações, selecione este perfil e preencha todos os endereços usando subdomínios de ${root_domain}."
}

setupmno_domain_load_profile() {
    local profile_id="$1" profile credential install_type status infrastructure
    setupmno_domain_registry_valid || return 1
    profile=$(jq -c --arg id "$profile_id" '.profiles[] | select(.id == $id)' "$SETUPMNO_DOMAIN_REGISTRY")
    [ -n "$profile" ] || return 1
    credential=$(jq -r '.credentialFile' <<<"$profile")
    install_type=$(jq -r '.installationType' <<<"$profile")
    status=$(jq -r '.status // "invalid"' <<<"$profile")
    infrastructure=$(jq -r '.infrastructure // false' <<<"$profile")
    if [ "$infrastructure" != "true" ] && [ "$status" != "validated" ]; then
        setupmno_domain_error "Este domínio adicional não está validado. Use GERENCIAR DOMÍNIOS CLOUDFLARE > Revalidar antes de instalar a aplicação."
        return 1
    fi
    setupmno_domain_credential_path_valid "$credential" || return 1
    export SETUPMNO_DOMAIN_PROFILE_ID="$profile_id"
    export SETUPMNO_SELECTED_ROOT_DOMAIN
    SETUPMNO_SELECTED_ROOT_DOMAIN=$(jq -r '.rootDomain' <<<"$profile")
    if [ "$install_type" = "CLOUDFLARE_TUNNEL" ]; then
        export SETUPMNO_CLOUDFLARE_CREDENTIALS_FILE="$credential"
        unset SETUPMNO_TRADITIONAL_CREDENTIALS_FILE
    else
        export SETUPMNO_TRADITIONAL_CREDENTIALS_FILE="$credential"
        unset SETUPMNO_CLOUDFLARE_CREDENTIALS_FILE
    fi
}

setupmno_domain_clear_selection() {
    unset SETUPMNO_DOMAIN_PROFILE_ID SETUPMNO_SELECTED_ROOT_DOMAIN
    unset SETUPMNO_CLOUDFLARE_CREDENTIALS_FILE SETUPMNO_TRADITIONAL_CREDENTIALS_FILE
}

setupmno_domain_select_for_app() {
    local script="$1" count primary_id choice options=() line id root label infrastructure status
    setupmno_domain_clear_selection
    [ -f "$SETUPMNO_DOMAIN_APP_LIST" ] && grep -Fxq "$script" "$SETUPMNO_DOMAIN_APP_LIST" || return 0
    if ! setupmno_domain_bootstrap_primary; then
        # Compatibilidade absoluta: se a migração não puder ocorrer agora, o
        # instalador antigo continua usando os arquivos originais.
        return 0
    fi
    count=$(jq '.profiles | length' "$SETUPMNO_DOMAIN_REGISTRY")
    primary_id=$(jq -r '.primaryProfileId' "$SETUPMNO_DOMAIN_REGISTRY")
    if [ "$count" -eq 1 ]; then
        setupmno_domain_load_profile "$primary_id"
        return $?
    fi
    while IFS=$'\t' read -r id root infrastructure status; do
        if [ "$infrastructure" = "true" ]; then
            label="PRINCIPAL — Portainer e Control Center"
        else
            label="ADICIONAL"
        fi
        options+=("$id" "$root — $label — $status")
    done < <(jq -r '.profiles[] | [.id,.rootDomain,(.infrastructure|tostring),(.status // "invalid")] | @tsv' "$SETUPMNO_DOMAIN_REGISTRY")
    options+=("ADD" "Cadastrar e validar outro domínio" "CANCEL" "Voltar ao menu")
    choice=$(whiptail --title "DOMÍNIO DESTA APLICAÇÃO" --menu \
        "Escolha o domínio que será usado nesta instalação.\n\nDepois, quando a aplicação pedir os endereços, todos devem terminar no domínio selecionado." \
        22 90 12 "${options[@]}" 3>&1 1>&2 2>&3) || return 130
    case "$choice" in
        ADD)
            setupmno_domain_register || return $?
            setupmno_domain_select_for_app "$script"
            ;;
        CANCEL|"") return 130 ;;
        *) setupmno_domain_load_profile "$choice" ;;
    esac
}

setupmno_domain_list() {
    local text
    setupmno_domain_bootstrap_primary || {
        setupmno_domain_error "O domínio principal ainda não pôde ser importado. Verifique a API Token, o Zone ID e a conexão com a Cloudflare."
        return 1
    }
    text=$(jq -r '.profiles[] |
        (if .infrastructure then "[PRINCIPAL] " else "[ADICIONAL] " end) + .rootDomain +
        "\n  Conta: " + (.accountId[0:8]) + "..." +
        "\n  Modo: " + .installationType +
        "\n  Túnel: " + (.tunnelScope // "none") +
        "\n  Estado: " + (.status // "desconhecido") + "\n"' "$SETUPMNO_DOMAIN_REGISTRY")
    setupmno_domain_msg "PERFIS DE DOMÍNIO\n\n${text}\nO perfil principal é permanente e continua sendo usado pelo Portainer e pelo Control Center."
}

setupmno_domain_revalidate() {
    local updated temporary id root zone account type credential token response ok now tunnel
    setupmno_domain_bootstrap_primary || {
        setupmno_domain_error "Não foi possível importar ou validar o domínio principal."
        return 1
    }
    updated=$(mktemp) || return 1
    cp "$SETUPMNO_DOMAIN_REGISTRY" "$updated" || { rm -f "$updated"; return 1; }
    while IFS=$'\t' read -r id root zone account type credential tunnel; do
        ok=false
        response=$(mktemp) || { rm -f "$updated"; return 1; }
        chmod 600 "$response"
        if setupmno_domain_credential_path_valid "$credential"; then
            unset CLOUDFLARE_API_TOKEN
            # shellcheck disable=SC1090
            source "$credential"
            token="${CLOUDFLARE_API_TOKEN:-}"
            if [ -n "$token" ] &&
               setupmno_cf_request GET "/zones/${zone}" "$token" "$response" &&
               setupmno_cf_success "$response" &&
               [ "$(jq -r '.result.name // empty' "$response")" = "$root" ] &&
               [ "$(jq -r '.result.account.id // empty' "$response")" = "$account" ]; then
                ok=true
                if [ "$type" = "CLOUDFLARE_TUNNEL" ]; then
                    setupmno_cf_request GET "/accounts/${account}/cfd_tunnel/${tunnel}/configurations" "$token" "$response" &&
                    setupmno_cf_success "$response" || ok=false
                fi
            fi
        fi
        now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
        temporary=$(mktemp) || { rm -f "$response" "$updated"; return 1; }
        jq --arg id "$id" --arg status "$([ "$ok" = true ] && printf validated || printf invalid)" --arg now "$now" \
            '(.profiles[] | select(.id == $id)) |= (.status=$status | .validatedAt=$now)' "$updated" >"$temporary" || {
            rm -f "$response" "$temporary" "$updated"
            return 1
        }
        mv -f "$temporary" "$updated"
        rm -f "$response"
    done < <(jq -r '.profiles[] | [.id,.rootDomain,.zoneId,.accountId,.installationType,.credentialFile,(.tunnelId // "")] | @tsv' "$SETUPMNO_DOMAIN_REGISTRY")
    if ! setupmno_domain_atomic_json "$updated" "$SETUPMNO_DOMAIN_REGISTRY"; then
        rm -f "$updated"
        return 1
    fi
    rm -f "$updated"
    unset CLOUDFLARE_API_TOKEN
    setupmno_domain_list
}

setupmno_domain_manage() {
    local choice status
    setupmno_domain_requirements || return 1
    while true; do
        choice=$(whiptail --title "GERENCIAR DOMÍNIOS CLOUDFLARE" --menu \
            "O domínio principal permanece reservado ao Portainer e ao Setup MNO Control Center. Cadastre domínios adicionais para as aplicações." \
            19 86 6 \
            "LIST" "Listar domínios cadastrados" \
            "ADD" "Adicionar e validar outro domínio" \
            "TEST" "Revalidar zonas, contas, tokens e túneis" \
            "BACK" "Voltar ao menu principal" \
            3>&1 1>&2 2>&3) || return 0
        case "$choice" in
            LIST) setupmno_domain_list || true ;;
            ADD)
                setupmno_domain_register
                status=$?
                [ "$status" -eq 130 ] || true
                ;;
            TEST) setupmno_domain_revalidate || setupmno_domain_error "A revalidação foi interrompida. Nenhuma credencial foi substituída." ;;
            BACK|"") return 0 ;;
        esac
    done
}

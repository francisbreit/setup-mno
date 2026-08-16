#!/usr/bin/bash
#########################################################
#
#    LOADING
#
export NEWT_COLORS='
#root=,white
#window=,black
#border=white,black
#textbox=white,black
#button=black,white

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

clear


amarelo="\e[33m"
verde="\e[32m"
branco="\e[97m"
bege="\e[93m"
vermelho="\e[91m"
reset="\e[0m"

control_center_installed() {
    command -v docker >/dev/null 2>&1 || return 1
    docker service ls --format '{{.Name}}' 2>/dev/null |
        grep -Eq '^mnoctrl[[:alnum:]]+-(web|agent|terminal|assistant)_'
}

essential_services_ready() {
    local service
    command -v docker >/dev/null 2>&1 || return 1
    docker info >/dev/null 2>&1 || return 1
    for service in traefik portainer postgres redis pgbouncer; do
        docker service ls --filter "name=$service" --format '{{.Name}}' 2>/dev/null |
            grep -q "$service" || return 1
    done
}

wait_for_portainer_ready() {
    local attempt replicas
    for attempt in $(seq 1 30); do
        replicas=$(docker service ls --filter "name=portainer" --format '{{.Replicas}}' 2>/dev/null | head -n1)
        if [[ "$replicas" =~ ^[1-9][0-9]*/[1-9][0-9]*$ ]]; then
            return 0
        fi
        sleep 2
    done
    return 1
}

CONTROL_MFA_STATE_FILE="/root/SetupLowCodeMno/.control/mfa-state.json"

control_mfa_state_valid() {
    [ -f "$CONTROL_MFA_STATE_FILE" ] && [ ! -L "$CONTROL_MFA_STATE_FILE" ] &&
    [ "$(stat -c '%s' "$CONTROL_MFA_STATE_FILE" 2>/dev/null || printf '0')" -le 2048 ] &&
    jq -e '.schemaVersion == 1 and .decisionRecorded == true and
        (.desiredMFA | type == "boolean") and (.effectiveMFA | type == "boolean") and
        (.activationPromptPending | type == "boolean") and
        (.source | type == "string" and length > 0) and
        ((.desiredMFA == false and .effectiveMFA == false and .activationPromptPending == false) or
         (.desiredMFA == true and .effectiveMFA == true and .activationPromptPending == false) or
         (.desiredMFA == true and .effectiveMFA == false))' \
        "$CONTROL_MFA_STATE_FILE" >/dev/null 2>&1
}

write_control_mfa_state() {
    local desired="$1" effective="$2" pending="$3" source="$4" state_dir temporary_file
    case "$desired:$effective:$pending" in
        true:true:false|true:false:true|true:false:false|false:false:false) ;;
        *) return 1 ;;
    esac
    [[ "$source" =~ ^[a-z0-9-]{3,40}$ ]] || return 1
    state_dir=$(dirname "$CONTROL_MFA_STATE_FILE")
    [ ! -L "$state_dir" ] || return 1
    mkdir -p "$state_dir" || return 1
    [ ! -e "$CONTROL_MFA_STATE_FILE" ] ||
        { [ -f "$CONTROL_MFA_STATE_FILE" ] && [ ! -L "$CONTROL_MFA_STATE_FILE" ]; } || return 1
    temporary_file=$(mktemp "$state_dir/mfa-state.json.tmp.XXXXXX") || return 1
    chmod 0600 "$temporary_file" || { rm -f "$temporary_file"; return 1; }
    jq -n --argjson desired "$desired" --argjson effective "$effective" \
        --argjson pending "$pending" --arg source "$source" \
        --arg updatedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        '{schemaVersion:1,decisionRecorded:true,desiredMFA:$desired,
          effectiveMFA:$effective,activationPromptPending:$pending,
          source:$source,updatedAt:$updatedAt}' >"$temporary_file" || {
        rm -f "$temporary_file"
        return 1
    }
    mv -f "$temporary_file" "$CONTROL_MFA_STATE_FILE"
}

show_control_mfa_instructions() {
    whiptail --title "COMO PREPARAR O MFA" --msgbox \
        "O MFA será usado pelo Setup MNO Control Center, não pelo login do Portainer. Nesta etapa registramos apenas sua escolha; o domínio e o e-mail do Control Center serão solicitados quando o painel for instalado.\n\n1. Abra dash.cloudflare.com e entre em Zero Trust.\n2. Acesse Access controls > Access settings.\n3. Habilite Allow multi-factor authentication (MFA).\n4. Permita Authenticator application (TOTP), biometria ou chave de segurança.\n5. O token do Setup precisará de Access: Apps and Policies Write e Access: Organizations Read.\n\nVocê poderá alterar esta escolha depois em CONFIGURAR MFA CONTROL CENTER." \
        23 92
}

choose_control_mfa_preference() {
    local choice
    while true; do
        choice=$(whiptail --title "SEGURANÇA DO CONTROL CENTER" --default-item "MFA" --menu \
            "Escolha uma única vez como deseja proteger o futuro Setup MNO Control Center. Esta decisão ficará registrada e não será perguntada novamente nas próximas atualizações:" \
            19 94 3 \
            "MFA" "Ativar Cloudflare Access + segundo fator (RECOMENDADO)" \
            "SEM_MFA" "Manter Tunnel direto, login local e Terminal Remoto" \
            "INSTRUCOES" "Ver o passo a passo antes de escolher" \
            3>&1 1>&2 2>&3) || return 130
        case "$choice" in
            MFA) CONTROL_MFA_DESIRED="true"; CONTROL_MFA_PENDING="true"; return 0 ;;
            SEM_MFA) CONTROL_MFA_DESIRED="false"; CONTROL_MFA_PENDING="false"; return 0 ;;
            INSTRUCOES) show_control_mfa_instructions ;;
        esac
    done
}

offer_control_center_installation() {
    local installer="/root/SetupLowCodeMno/setupmno_control" status
    [ -x "$installer" ] || return 0
    essential_services_ready || return 0
    control_center_installed && return 0

    if ! wait_for_portainer_ready; then
        whiptail --title "CONTROL CENTER ADIADO" --msgbox \
            "O Portainer ainda não ficou saudável após 60 segundos.\n\nO Control Center não será iniciado nesta etapa. Execute-o depois pelo menu principal, quando o Portainer estiver operacional." \
            14 82
        return 0
    fi

    if whiptail --title "SETUP MNO CONTROL CENTER (OPCIONAL)" --yesno \
        "Deseja instalar agora o Setup MNO Control Center?\n\nEle adiciona uma interface web para acompanhar o servidor, consultar o catálogo, visualizar Blueprints, usar o Assistente MNO e abrir o Instalador Seguro.\n\nA instalação é opcional. Se escolher NÃO, o Setup MNO continuará funcionando normalmente e você poderá instalar o Control Center depois pelo menu principal." \
        20 82; then
        clear
        SETUPMNO_INSTALLATION_TYPE="$INSTALL_CHOICE" "$installer"
        status=$?
        if [ "$status" -ne 0 ]; then
            whiptail --title "CONTROL CENTER NÃO INSTALADO" --msgbox \
                "A instalação opcional do Control Center não foi concluída.\n\nAs ferramentas essenciais do Setup MNO permanecem instaladas. Você poderá tentar novamente pelo menu principal." \
                14 78
        fi
    fi
}


# Validação preventiva das credenciais Cloudflare.
# Em caso de credencial inválida, a instalação NÃO avança para as operações
# de DNS/Tunnel; o questionário de credenciais é apresentado novamente.
CLOUDFLARE_VALIDATION_ERROR=""

validate_cloudflare_api_token() {
    local api_token="$1" response

    CLOUDFLARE_VALIDATION_ERROR=""
    response=$(curl -sS --connect-timeout 10 --max-time 20 \
        "https://api.cloudflare.com/client/v4/user/tokens/verify" \
        -H "Authorization: Bearer ${api_token}" \
        -H "Content-Type: application/json" 2>/dev/null) || {
        CLOUDFLARE_VALIDATION_ERROR="Não foi possível conectar à API da Cloudflare para validar o API Token."
        return 1
    }

    if ! printf '%s' "$response" | jq -e \
        '.success == true and .result.status == "active"' >/dev/null 2>&1; then
        CLOUDFLARE_VALIDATION_ERROR="API Token inválido, expirado, desativado ou sem acesso à API da Cloudflare."
        return 1
    fi

    return 0
}

validate_cloudflare_zone_dns() {
    local api_token="$1" zone_id="$2" expected_account_id="${3:-}"
    local response

    response=$(curl -sS --connect-timeout 10 --max-time 20 \
        "https://api.cloudflare.com/client/v4/zones/${zone_id}" \
        -H "Authorization: Bearer ${api_token}" \
        -H "Content-Type: application/json" 2>/dev/null) || {
        CLOUDFLARE_VALIDATION_ERROR="Não foi possível conectar à API da Cloudflare para validar o Zone ID."
        return 1
    }

    if ! printf '%s' "$response" | jq -e --arg zone_id "$zone_id" \
        '.success == true and .result.id == $zone_id' >/dev/null 2>&1; then
        CLOUDFLARE_VALIDATION_ERROR="Zone ID inválido ou o API Token não possui acesso a essa zona."
        return 1
    fi

    if [ -n "$expected_account_id" ] && \
       ! printf '%s' "$response" | jq -e --arg account_id "$expected_account_id" \
            '.result.account.id == $account_id' >/dev/null 2>&1; then
        CLOUDFLARE_VALIDATION_ERROR="O Zone ID informado não pertence ao Account ID informado."
        return 1
    fi

    response=$(curl -sS --connect-timeout 10 --max-time 20 \
        "https://api.cloudflare.com/client/v4/zones/${zone_id}/dns_records?per_page=5" \
        -H "Authorization: Bearer ${api_token}" \
        -H "Content-Type: application/json" 2>/dev/null) || {
        CLOUDFLARE_VALIDATION_ERROR="Não foi possível validar a permissão de DNS para a zona informada."
        return 1
    }

    if ! printf '%s' "$response" | jq -e '.success == true' >/dev/null 2>&1; then
        CLOUDFLARE_VALIDATION_ERROR="O API Token não possui permissão suficiente de DNS para o Zone ID informado. Verifique a permissão Zone.DNS Edit."
        return 1
    fi

    return 0
}

validate_cloudflare_tunnel_credentials() {
    local api_token="$1" account_id="$2" zone_id="$3" tunnel_id="$4"
    local response

    validate_cloudflare_api_token "$api_token" || return 1
    validate_cloudflare_zone_dns "$api_token" "$zone_id" "$account_id" || return 1

    response=$(curl -sS --connect-timeout 10 --max-time 20 \
        "https://api.cloudflare.com/client/v4/accounts/${account_id}/cfd_tunnel/${tunnel_id}" \
        -H "Authorization: Bearer ${api_token}" \
        -H "Content-Type: application/json" 2>/dev/null) || {
        CLOUDFLARE_VALIDATION_ERROR="Não foi possível conectar à API da Cloudflare para validar Account ID e Tunnel ID."
        return 1
    }

    if ! printf '%s' "$response" | jq -e --arg tunnel_id "$tunnel_id" \
        '.success == true and .result.id == $tunnel_id' >/dev/null 2>&1; then
        CLOUDFLARE_VALIDATION_ERROR="Account ID ou Tunnel ID inválido, ou o API Token não possui acesso ao Tunnel informado."
        return 1
    fi

    # Valida também a permissão necessária para obter o token do Tunnel.
    # Essa é a mesma operação utilizada mais adiante na instalação.
    response=$(curl -sS --connect-timeout 10 --max-time 20 \
        "https://api.cloudflare.com/client/v4/accounts/${account_id}/cfd_tunnel/${tunnel_id}/token" \
        -H "Authorization: Bearer ${api_token}" \
        -H "Content-Type: application/json" 2>/dev/null) || {
        CLOUDFLARE_VALIDATION_ERROR="Não foi possível validar a permissão de acesso ao token do Cloudflare Tunnel."
        return 1
    }

    if ! printf '%s' "$response" | jq -e \
        '.success == true and (.result | type == "string") and (.result | startswith("ey"))' >/dev/null 2>&1; then
        CLOUDFLARE_VALIDATION_ERROR="As credenciais do Tunnel não permitem obter o Tunnel Token. Verifique API Token, Account ID, Tunnel ID e a permissão Cloudflare Tunnel Edit."
        return 1
    fi

    return 0
}

validate_cloudflare_traditional_credentials() {
    local api_token="$1" zone_id="$2"

    validate_cloudflare_api_token "$api_token" || return 1
    validate_cloudflare_zone_dns "$api_token" "$zone_id" || return 1
    return 0
}

normalize_cloudflare_hostname() {
    local hostname="$1"
    hostname=${hostname#*://}
    hostname=${hostname%%/*}
    hostname=${hostname%%:*}
    hostname=${hostname%.}
    hostname=$(printf '%s' "$hostname" | tr '[:upper:]' '[:lower:]')
    [[ "$hostname" =~ ^[a-z0-9]([a-z0-9.-]*[a-z0-9])?$ ]] &&
    [[ "$hostname" == *.* ]] || return 1
    printf '%s' "$hostname"
}

discover_cloudflare_zone_context() {
    local api_token="$1" hostname="$2" response candidates page total_pages page_matches selected count
    response=$(mktemp) || return 1
    candidates=$(mktemp) || { rm -f "$response"; return 1; }
    chmod 600 "$response" "$candidates"
    printf '[]' >"$candidates"
    validate_cloudflare_api_token "$api_token" || { rm -f "$response" "$candidates"; return 1; }

    page=1
    total_pages=1
    while [ "$page" -le "$total_pages" ] && [ "$page" -le 50 ]; do
        if ! curl -sS --connect-timeout 10 --max-time 25 \
            "https://api.cloudflare.com/client/v4/zones?status=active&per_page=50&page=${page}" \
            -H "Authorization: Bearer ${api_token}" \
            -H "Content-Type: application/json" >"$response" 2>/dev/null ||
           ! jq -e '.success == true and (.result | type == "array")' "$response" >/dev/null 2>&1; then
            CLOUDFLARE_VALIDATION_ERROR="Não foi possível descobrir a zona do domínio pela API. Confirme Zona > Zona > Leitura no API Token."
            rm -f "$response" "$candidates"
            return 1
        fi
        page_matches=$(jq -c --arg host "$hostname" \
            '[.result[]? as $zone | select($host == $zone.name or ($host | endswith("." + $zone.name))) | $zone]' \
            "$response") || { rm -f "$response" "$candidates"; return 1; }
        jq --argjson matches "$page_matches" '. + $matches' "$candidates" >"${candidates}.new" || {
            rm -f "$response" "$candidates" "${candidates}.new"
            return 1
        }
        mv -f "${candidates}.new" "$candidates"
        total_pages=$(jq -r '.result_info.total_pages // 1' "$response")
        [[ "$total_pages" =~ ^[0-9]+$ ]] || total_pages=1
        page=$((page + 1))
    done

    count=$(jq 'length' "$candidates")
    if [ "$count" -eq 0 ]; then
        CLOUDFLARE_VALIDATION_ERROR="O API Token não encontrou uma zona ativa compatível com ${hostname}. Verifique o domínio e restrinja o token à zona correta."
        rm -f "$response" "$candidates"
        return 1
    fi
    selected=$(jq -c 'sort_by(.name | length) | last' "$candidates")
    CLOUDFLARE_ZONE_ID=$(printf '%s' "$selected" | jq -r '.id // empty')
    CLOUDFLARE_ACCOUNT_ID=$(printf '%s' "$selected" | jq -r '.account.id // empty')
    CLOUDFLARE_ZONE_NAME=$(printf '%s' "$selected" | jq -r '.name // empty')
    rm -f "$response" "$candidates"
    [ -n "$CLOUDFLARE_ZONE_ID" ] && [ -n "$CLOUDFLARE_ACCOUNT_ID" ] && [ -n "$CLOUDFLARE_ZONE_NAME" ] || {
        CLOUDFLARE_VALIDATION_ERROR="A Cloudflare encontrou a zona, mas não retornou Zone ID e Account ID válidos."
        return 1
    }
    validate_cloudflare_zone_dns "$api_token" "$CLOUDFLARE_ZONE_ID" "$CLOUDFLARE_ACCOUNT_ID"
}

collect_primary_tunnel_context() {
    local hostname="$1"
    while true; do
        TUNNEL_SETUP_MODE=$(choose_primary_tunnel_mode) || return $?
        CLOUDFLARE_API_TOKEN=$(whiptail --title "API TOKEN DA CLOUDFLARE" --passwordbox \
            "Informe o API Token. Permissões necessárias:\n\nConta > Cloudflare Tunnel > Edição\nZona > Zona > Leitura\nZona > DNS > Edição" \
            16 82 3>&1 1>&2 2>&3) || return 130
        if [ -z "$CLOUDFLARE_API_TOKEN" ]; then
            whiptail --title "API TOKEN OBRIGATÓRIO" --msgbox "Informe o API Token para continuar." 9 62
            continue
        fi
        if ! discover_cloudflare_zone_context "$CLOUDFLARE_API_TOKEN" "$hostname"; then
            whiptail --title "DOMÍNIO OU TOKEN INVÁLIDO" --msgbox \
                "${CLOUDFLARE_VALIDATION_ERROR}\n\nAccount ID e Zone ID são descobertos automaticamente; você não precisa copiá-los do painel." \
                15 82
            continue
        fi
        if [ "$TUNNEL_SETUP_MODE" = "AUTO" ]; then
            TUNNEL_ID=""
            TUNNEL_NAME=$(primary_tunnel_random_name) || {
                CLOUDFLARE_VALIDATION_ERROR="Não foi possível gerar um nome exclusivo para o Tunnel automático."
                continue
            }
            if validate_cloudflare_tunnel_creation_access "$CLOUDFLARE_API_TOKEN" \
                "$CLOUDFLARE_ACCOUNT_ID" "$CLOUDFLARE_ZONE_ID"; then
                whiptail --title "CLOUDFLARE VALIDADA" --msgbox \
                    "Zona identificada automaticamente: ${CLOUDFLARE_ZONE_NAME}\n\nO Tunnel ${TUNNEL_NAME} será criado somente depois da confirmação final." \
                    12 78
                return 0
            fi
        else
            TUNNEL_ID=$(whiptail --title "TUNNEL EXISTENTE" --inputbox \
                "Informe somente o Tunnel ID criado anteriormente no painel da Cloudflare:" \
                11 80 3>&1 1>&2 2>&3) || return 130
            if [ -z "$TUNNEL_ID" ]; then
                CLOUDFLARE_VALIDATION_ERROR="O Tunnel ID é obrigatório no método clássico."
            elif validate_cloudflare_tunnel_credentials "$CLOUDFLARE_API_TOKEN" \
                "$CLOUDFLARE_ACCOUNT_ID" "$CLOUDFLARE_ZONE_ID" "$TUNNEL_ID"; then
                TUNNEL_NAME="Tunnel existente"
                whiptail --title "TUNNEL EXISTENTE VALIDADO" --msgbox \
                    "Zona identificada automaticamente: ${CLOUDFLARE_ZONE_NAME}\n\nO Tunnel foi validado e será tratado como externo: o Setup MNO nunca o excluirá." \
                    13 80
                return 0
            fi
        fi
        whiptail --title "CREDENCIAIS CLOUDFLARE INVÁLIDAS" --msgbox \
            "${CLOUDFLARE_VALIDATION_ERROR}\n\nNenhuma configuração foi aplicada. Revise o token ou escolha outro método." \
            14 80
    done
}

PRIMARY_TUNNEL_STATE_FILE="/root/.setupmno/cloudflare/primary-tunnel.json"
PRIMARY_TUNNEL_LOG="/tmp/setupmno-primary-tunnel-install.log"
SETUPMNO_PRIMARY_TUNNEL_TRANSACTION=false
SETUPMNO_PRIMARY_DELETE_ON_ROLLBACK=false
SETUPMNO_PRIMARY_STACK_CREATED=false
SETUPMNO_PRIMARY_DNS_RECORD_ID=""
SETUPMNO_PRIMARY_DNS_BACKUP=""
SETUPMNO_PRIMARY_DNS_MUTATED=false
SETUPMNO_PRIMARY_TUNNEL_CONFIG_BACKUP=""
SETUPMNO_PRIMARY_TUNNEL_CONFIG_MAY_BE_EMPTY=false
SETUPMNO_PRIMARY_TUNNEL_SECRET=""
SETUPMNO_PRIMARY_CREDENTIALS_BACKUP=""
SETUPMNO_PRIMARY_CREDENTIALS_EXISTED=false
PRIMARY_TUNNEL_HTTP_CODE=""

primary_tunnel_cf_api() {
    local method="$1" endpoint="$2" output="$3" payload="${4:-}"
    local http_code
    local args=(-sS --connect-timeout 10 --max-time 45 -X "$method"
        -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}"
        -H "Content-Type: application/json")
    [ -z "$payload" ] || args+=(--data-binary "@$payload")
    PRIMARY_TUNNEL_HTTP_CODE=""
    http_code=$(curl "${args[@]}" -o "$output" -w '%{http_code}' \
        "https://api.cloudflare.com/client/v4${endpoint}" 2>/dev/null) || {
        PRIMARY_TUNNEL_HTTP_CODE="000"
        return 1
    }
    PRIMARY_TUNNEL_HTTP_CODE="$http_code"
    [[ "$http_code" =~ ^[0-9]{3}$ ]]
}

primary_tunnel_api_success() {
    jq -e '.success == true' "$1" >/dev/null 2>&1
}

primary_tunnel_response_is_live() {
    local response="$1" expected_id="$2"
    jq -e --arg tunnel_id "$expected_id" '
        .success == true and
        .result.id == $tunnel_id and
        ((.result.deleted_at // null) == null)' \
        "$response" >/dev/null 2>&1
}

primary_tunnel_response_is_deleted() {
    local response="$1" expected_id="$2"
    jq -e --arg tunnel_id "$expected_id" '
        .success == true and
        .result.id == $tunnel_id and
        ((.result.deleted_at // null) != null)' \
        "$response" >/dev/null 2>&1
}

primary_tunnel_error_text() {
    jq -r '[.errors[]?.message, .messages[]?.message] | map(select(length > 0)) | join("\n")' "$1" 2>/dev/null |
        awk 'NF {print; found=1} END {if(!found) print "A Cloudflare recusou a operação."}' |
        head -c 1800
}

primary_tunnel_configuration_missing() {
    local response="$1" http_code="${2:-}"
    [ "$http_code" = "404" ] && return 0
    jq -e '.success == true and ((.result.config // null) == null)' \
        "$response" >/dev/null 2>&1 && return 0
    jq -e '.success == false and
        ([.errors[]?.message, .messages[]?.message] | map(select(type == "string")) |
         join(" ") | ascii_downcase |
         test("(configuration|config).*(not found|does not exist|missing|not configured)|no (configuration|config)"))' \
        "$response" >/dev/null 2>&1
}

primary_tunnel_get_configuration() {
    local output="$1" allow_empty="${2:-false}" attempt attempts delay detail last_missing=false
    attempts="${SETUPMNO_TUNNEL_CONFIG_ATTEMPTS:-6}"
    [[ "$attempts" =~ ^[1-9][0-9]*$ ]] && [ "$attempts" -le 12 ] || attempts=6
    for attempt in $(seq 1 "$attempts"); do
        : >"$output"
        if primary_tunnel_cf_api GET \
            "/accounts/${CLOUDFLARE_ACCOUNT_ID}/cfd_tunnel/${TUNNEL_ID}/configurations" "$output" &&
           primary_tunnel_api_success "$output" &&
           jq -e '.result.config | type == "object"' "$output" >/dev/null 2>&1; then
            printf '%s configuração disponível na tentativa %s/%s (HTTP %s).\n' \
                "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$attempt" "$attempts" \
                "${PRIMARY_TUNNEL_HTTP_CODE:-desconhecido}" >>"$PRIMARY_TUNNEL_LOG"
            return 0
        fi
        if primary_tunnel_configuration_missing "$output" "${PRIMARY_TUNNEL_HTTP_CODE:-}"; then
            last_missing=true
        else
            last_missing=false
        fi
        detail=$(primary_tunnel_error_text "$output")
        printf '%s configuração indisponível na tentativa %s/%s (HTTP %s): %s\n' \
            "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$attempt" "$attempts" \
            "${PRIMARY_TUNNEL_HTTP_CODE:-desconhecido}" "$detail" >>"$PRIMARY_TUNNEL_LOG"
        case "${PRIMARY_TUNNEL_HTTP_CODE:-}" in 401|403) break ;; esac
        if [ "$attempt" -lt "$attempts" ]; then
            delay="$attempt"
            [ "${SETUPMNO_TUNNEL_TEST_MODE:-0}" = "1" ] && delay=0
            [ "$delay" -eq 0 ] || sleep "$delay"
        fi
    done
    if [ "$allow_empty" = "true" ] && [ "$last_missing" = "true" ]; then
        jq -n '{success:true,result:{config:{}},setupmnoInitialEmpty:true}' >"$output" || return 1
        printf '%s Tunnel automático ainda sem configuração; iniciando primeiro ingresso vazio de forma controlada.\n' \
            "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >>"$PRIMARY_TUNNEL_LOG"
        return 0
    fi
    CLOUDFLARE_VALIDATION_ERROR="Não foi possível obter a configuração do Tunnel. HTTP ${PRIMARY_TUNNEL_HTTP_CODE:-indisponível}: $(primary_tunnel_error_text "$output")"
    return 1
}

primary_tunnel_wait_for_route() {
    local output="$1" hostname="$2" service="$3" attempt attempts delay detail
    attempts="${SETUPMNO_TUNNEL_CONFIG_ATTEMPTS:-6}"
    [[ "$attempts" =~ ^[1-9][0-9]*$ ]] && [ "$attempts" -le 12 ] || attempts=6
    for attempt in $(seq 1 "$attempts"); do
        : >"$output"
        if primary_tunnel_cf_api GET \
            "/accounts/${CLOUDFLARE_ACCOUNT_ID}/cfd_tunnel/${TUNNEL_ID}/configurations" "$output" &&
           primary_tunnel_api_success "$output" &&
           jq -e --arg host "$hostname" --arg service "$service" \
             'any(.result.config.ingress[]?; .hostname == $host and .service == $service)' \
             "$output" >/dev/null 2>&1; then
            printf '%s rota confirmada na tentativa %s/%s (HTTP %s).\n' \
                "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$attempt" "$attempts" \
                "${PRIMARY_TUNNEL_HTTP_CODE:-desconhecido}" >>"$PRIMARY_TUNNEL_LOG"
            return 0
        fi
        detail=$(primary_tunnel_error_text "$output")
        printf '%s rota ainda não confirmada na tentativa %s/%s (HTTP %s): %s\n' \
            "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$attempt" "$attempts" \
            "${PRIMARY_TUNNEL_HTTP_CODE:-desconhecido}" "$detail" >>"$PRIMARY_TUNNEL_LOG"
        case "${PRIMARY_TUNNEL_HTTP_CODE:-}" in 401|403) break ;; esac
        if [ "$attempt" -lt "$attempts" ]; then
            delay="$attempt"
            [ "${SETUPMNO_TUNNEL_TEST_MODE:-0}" = "1" ] && delay=0
            [ "$delay" -eq 0 ] || sleep "$delay"
        fi
    done
    CLOUDFLARE_VALIDATION_ERROR="A API não confirmou a rota do Portainer. HTTP ${PRIMARY_TUNNEL_HTTP_CODE:-indisponível}: $(primary_tunnel_error_text "$output")"
    return 1
}

primary_tunnel_prepare_state_dir() {
    local state_dir
    state_dir=$(dirname "$PRIMARY_TUNNEL_STATE_FILE")
    [ ! -L "$state_dir" ] || return 1
    mkdir -p "$state_dir" || return 1
    chmod 700 "$state_dir" || return 1
}

primary_tunnel_state_valid() {
    local size owner permissions
    [ -f "$PRIMARY_TUNNEL_STATE_FILE" ] && [ ! -L "$PRIMARY_TUNNEL_STATE_FILE" ] || return 1
    size=$(stat -c '%s' "$PRIMARY_TUNNEL_STATE_FILE" 2>/dev/null) || return 1
    owner=$(stat -c '%u' "$PRIMARY_TUNNEL_STATE_FILE" 2>/dev/null) || return 1
    permissions=$(stat -c '%a' "$PRIMARY_TUNNEL_STATE_FILE" 2>/dev/null) || return 1
    [ "$size" -gt 0 ] && [ "$size" -le 4096 ] || return 1
    [ "$owner" = "0" ] || [ "${SETUPMNO_TUNNEL_TEST_MODE:-0}" = "1" ] || return 1
    [ $((8#$permissions & 077)) -eq 0 ] || return 1
    jq -e '.schemaVersion == 1 and
        (.accountId | type == "string" and length > 0) and
        (.zoneId | type == "string" and length > 0) and
        (.tunnelId | type == "string" and length > 0) and
        (.tunnelName | type == "string" and length > 0) and
        (.ownership == "external" or .ownership == "setupmno") and
        (.status == "pending" or .status == "active")' \
        "$PRIMARY_TUNNEL_STATE_FILE" >/dev/null 2>&1
}

primary_tunnel_write_state() {
    local ownership="$1" status="$2" account_id="$3" zone_id="$4" tunnel_id="$5" tunnel_name="$6"
    local state_dir temporary
    case "$ownership:$status" in
        external:pending|external:active|setupmno:pending|setupmno:active) ;;
        *) return 1 ;;
    esac
    primary_tunnel_prepare_state_dir || return 1
    state_dir=$(dirname "$PRIMARY_TUNNEL_STATE_FILE")
    temporary=$(mktemp "$state_dir/primary-tunnel.json.tmp.XXXXXX") || return 1
    chmod 600 "$temporary" || { rm -f "$temporary"; return 1; }
    jq -n --arg account "$account_id" --arg zone "$zone_id" --arg tunnel "$tunnel_id" \
        --arg name "$tunnel_name" --arg ownership "$ownership" --arg status "$status" \
        --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        '{schemaVersion:1,accountId:$account,zoneId:$zone,tunnelId:$tunnel,
          tunnelName:$name,ownership:$ownership,status:$status,updatedAt:$now}' >"$temporary" || {
        rm -f "$temporary"
        return 1
    }
    mv -f "$temporary" "$PRIMARY_TUNNEL_STATE_FILE"
}

primary_tunnel_random_name() {
    local suffix=""
    if command -v openssl >/dev/null 2>&1; then
        suffix=$(openssl rand -hex 6 2>/dev/null || true)
    fi
    if ! [[ "$suffix" =~ ^[0-9a-f]{12}$ ]] && [ -r /dev/urandom ]; then
        suffix=$(od -An -N6 -tx1 /dev/urandom 2>/dev/null | tr -d '[:space:]')
    fi
    if ! [[ "$suffix" =~ ^[0-9a-f]{12}$ ]]; then
        suffix=$(printf '%s:%s:%s' "$(date +%s%N)" "$$" "${RANDOM:-0}" | sha256sum | cut -c1-12)
    fi
    [[ "$suffix" =~ ^[0-9a-f]{12}$ ]] || return 1
    printf 'setupmno-primary-%s' "$suffix"
}

validate_cloudflare_tunnel_creation_access() {
    local api_token="$1" account_id="$2" zone_id="$3" response old_token
    validate_cloudflare_api_token "$api_token" || return 1
    validate_cloudflare_zone_dns "$api_token" "$zone_id" "$account_id" || return 1
    response=$(mktemp) || return 1
    chmod 600 "$response"
    old_token="${CLOUDFLARE_API_TOKEN:-}"
    CLOUDFLARE_API_TOKEN="$api_token"
    if ! primary_tunnel_cf_api GET "/accounts/${account_id}/cfd_tunnel?is_deleted=false&per_page=1" "$response" ||
       ! primary_tunnel_api_success "$response"; then
        CLOUDFLARE_VALIDATION_ERROR="O API Token não pode consultar Cloudflare Tunnels nesta conta. Adicione Conta > Cloudflare Tunnel > Edição."
        CLOUDFLARE_API_TOKEN="$old_token"
        rm -f "$response"
        return 1
    fi
    CLOUDFLARE_API_TOKEN="$old_token"
    rm -f "$response"
}

show_primary_tunnel_instructions() {
    whiptail --title "COMO CONFIGURAR O CLOUDFLARE TUNNEL" --msgbox \
        "O Setup MNO oferece dois caminhos:\n\nAUTOMÁTICO — o Setup cria um Tunnel remoto, guarda o token em Docker Secret, inicia o conector e valida a conexão.\n\nEXISTENTE — mantém o método clássico. Você cria o Tunnel no painel e informa o Tunnel ID. Esse Tunnel será tratado como externo e nunca será excluído pelo Setup.\n\nPermissões do API Token:\n- Conta > Cloudflare Tunnel > Edição\n- Zona > Zona > Leitura\n- Zona > DNS > Edição\n\nPortainer e Control Center continuarão no domínio principal." \
        24 88 1>&2
}

choose_primary_tunnel_mode() {
    local choice
    while true; do
        choice=$(whiptail --title "ORIGEM DO CLOUDFLARE TUNNEL" --default-item "AUTO" --menu \
            "Escolha como o Tunnel principal será preparado. Nenhuma criação automática ocorrerá antes da confirmação final da instalação." \
            18 92 4 \
            "AUTO" "Criar e validar automaticamente — RECOMENDADO" \
            "EXISTENTE" "Informar Tunnel ID — método clássico" \
            "INSTRUCOES" "Ver permissões e funcionamento" \
            "VOLTAR" "Cancelar esta configuração" \
            3>&1 1>&2 2>&3) || return 130
        case "$choice" in
            AUTO|EXISTENTE) printf '%s' "$choice"; return 0 ;;
            INSTRUCOES) show_primary_tunnel_instructions ;;
            VOLTAR) return 130 ;;
        esac
    done
}

primary_tunnel_get_token() {
    local tunnel_id="$1" response token
    response=$(mktemp) || return 1
    chmod 600 "$response"
    if ! primary_tunnel_cf_api GET "/accounts/${CLOUDFLARE_ACCOUNT_ID}/cfd_tunnel/${tunnel_id}/token" "$response" ||
       ! primary_tunnel_api_success "$response"; then
        CLOUDFLARE_VALIDATION_ERROR="Não foi possível obter o token do Tunnel. $(primary_tunnel_error_text "$response")"
        rm -f "$response"
        return 1
    fi
    token=$(jq -r '.result // empty' "$response")
    rm -f "$response"
    [[ "$token" == ey* ]] || {
        CLOUDFLARE_VALIDATION_ERROR="A Cloudflare retornou um Tunnel Token vazio ou inválido."
        return 1
    }
    printf '%s' "$token"
}

primary_tunnel_begin_existing() {
    TUNNEL_TOKEN=$(primary_tunnel_get_token "$TUNNEL_ID") || return 1
    TUNNEL_NAME="Tunnel existente"
    TUNNEL_OWNERSHIP="external"
    SETUPMNO_PRIMARY_TUNNEL_CONFIG_MAY_BE_EMPTY=false
    SETUPMNO_PRIMARY_DELETE_ON_ROLLBACK=false
    primary_tunnel_write_state external pending "$CLOUDFLARE_ACCOUNT_ID" "$CLOUDFLARE_ZONE_ID" "$TUNNEL_ID" "$TUNNEL_NAME" || return 1
    SETUPMNO_PRIMARY_TUNNEL_TRANSACTION=true
    trap 'primary_tunnel_exit_handler $?' EXIT
}

primary_tunnel_begin_automatic() {
    local expected_name response payload existing_count state_status state_account state_zone state_tunnel state_name detail
    # Cada criação automática recebe uma identidade nova. Um nome vindo de
    # credenciais antigas jamais deve ressuscitar a referência de outro projeto.
    expected_name=$(primary_tunnel_random_name) || {
        CLOUDFLARE_VALIDATION_ERROR="Não foi possível gerar um nome exclusivo para o Tunnel automático."
        return 1
    }
    TUNNEL_NAME="$expected_name"
    response=$(mktemp) || return 1
    payload=$(mktemp) || { rm -f "$response"; return 1; }
    chmod 600 "$response" "$payload"

    if [ -e "$PRIMARY_TUNNEL_STATE_FILE" ] && ! primary_tunnel_state_valid; then
        CLOUDFLARE_VALIDATION_ERROR="O estado local do Tunnel principal existe, mas é inválido. Nenhum Tunnel novo será criado até esse estado ser reparado."
        rm -f "$response" "$payload"
        return 1
    fi

    if primary_tunnel_state_valid; then
        state_account=$(jq -r '.accountId' "$PRIMARY_TUNNEL_STATE_FILE")
        state_zone=$(jq -r '.zoneId' "$PRIMARY_TUNNEL_STATE_FILE")
        state_tunnel=$(jq -r '.tunnelId' "$PRIMARY_TUNNEL_STATE_FILE")
        state_name=$(jq -r '.tunnelName' "$PRIMARY_TUNNEL_STATE_FILE")
        state_status=$(jq -r '.status' "$PRIMARY_TUNNEL_STATE_FILE")
        if [ "$state_account" = "$CLOUDFLARE_ACCOUNT_ID" ] && [ "$state_zone" = "$CLOUDFLARE_ZONE_ID" ] &&
           [ "$(jq -r '.ownership' "$PRIMARY_TUNNEL_STATE_FILE")" = "setupmno" ]; then
            : >"$response"
            if ! primary_tunnel_cf_api GET "/accounts/${CLOUDFLARE_ACCOUNT_ID}/cfd_tunnel/${state_tunnel}" "$response"; then
                CLOUDFLARE_VALIDATION_ERROR="Não foi possível consultar o Tunnel registrado antes de decidir pela recuperação. Nenhum Tunnel novo foi criado."
                rm -f "$response" "$payload"
                return 1
            fi
            if primary_tunnel_response_is_live "$response" "$state_tunnel"; then
                TUNNEL_ID="$state_tunnel"
                TUNNEL_NAME="$state_name"
                TUNNEL_TOKEN=$(primary_tunnel_get_token "$TUNNEL_ID") || { rm -f "$response" "$payload"; return 1; }
                TUNNEL_OWNERSHIP="setupmno"
                # Um Tunnel vivo criado pelo Setup pode ter perdido somente a
                # configuração remota; nesse caso o primeiro ingresso é seguro.
                SETUPMNO_PRIMARY_TUNNEL_CONFIG_MAY_BE_EMPTY=true
                [ "$state_status" = "pending" ] && SETUPMNO_PRIMARY_DELETE_ON_ROLLBACK=true || SETUPMNO_PRIMARY_DELETE_ON_ROLLBACK=false
                SETUPMNO_PRIMARY_TUNNEL_TRANSACTION=true
                trap 'primary_tunnel_exit_handler $?' EXIT
                rm -f "$response" "$payload"
                return 0
            fi
            if primary_tunnel_response_is_deleted "$response" "$state_tunnel" ||
               [ "${PRIMARY_TUNNEL_HTTP_CODE:-}" = "404" ]; then
                printf '%s estado local apontava para Tunnel excluído; uma nova identidade automática será criada.\n' \
                    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >>"$PRIMARY_TUNNEL_LOG"
                expected_name=$(primary_tunnel_random_name) || {
                    CLOUDFLARE_VALIDATION_ERROR="O Tunnel anterior foi excluído e não foi possível gerar uma nova identidade exclusiva."
                    rm -f "$response" "$payload"
                    return 1
                }
                TUNNEL_NAME="$expected_name"
            else
                detail=$(primary_tunnel_error_text "$response")
                CLOUDFLARE_VALIDATION_ERROR="A Cloudflare não confirmou que o Tunnel registrado está vivo nem excluído. HTTP ${PRIMARY_TUNNEL_HTTP_CODE:-indisponível}: ${detail}. Nenhum Tunnel novo foi criado."
                rm -f "$response" "$payload"
                return 1
            fi
        fi
    fi

    if ! primary_tunnel_cf_api GET "/accounts/${CLOUDFLARE_ACCOUNT_ID}/cfd_tunnel?is_deleted=false&per_page=100" "$response" ||
       ! primary_tunnel_api_success "$response"; then
        CLOUDFLARE_VALIDATION_ERROR="Não foi possível consultar os Tunnels existentes. $(primary_tunnel_error_text "$response")"
        rm -f "$response" "$payload"
        return 1
    fi
    existing_count=$(jq --arg name "$expected_name" '[.result[]? | select(.name == $name)] | length' "$response")
    if [ "$existing_count" -gt 0 ]; then
        CLOUDFLARE_VALIDATION_ERROR="Já existe um Tunnel chamado ${expected_name}, mas ele não possui estado transacional reconhecido. Selecione USAR TÚNEL EXISTENTE e informe seu ID."
        rm -f "$response" "$payload"
        return 1
    fi

    jq -n --arg name "$expected_name" '{name:$name,config_src:"cloudflare"}' >"$payload"
    if ! primary_tunnel_cf_api POST "/accounts/${CLOUDFLARE_ACCOUNT_ID}/cfd_tunnel" "$response" "$payload" ||
       ! primary_tunnel_api_success "$response"; then
        CLOUDFLARE_VALIDATION_ERROR="A criação automática foi recusada. $(primary_tunnel_error_text "$response")"
        rm -f "$response" "$payload"
        return 1
    fi
    TUNNEL_ID=$(jq -r '.result.id // empty' "$response")
    TUNNEL_NAME=$(jq -r '.result.name // empty' "$response")
    [ -n "$TUNNEL_ID" ] && [ "$TUNNEL_NAME" = "$expected_name" ] || {
        if [ -n "$TUNNEL_ID" ]; then
            primary_tunnel_cf_api DELETE "/accounts/${CLOUDFLARE_ACCOUNT_ID}/cfd_tunnel/${TUNNEL_ID}" "$response" || true
        fi
        CLOUDFLARE_VALIDATION_ERROR="A Cloudflare não devolveu uma identificação válida para o Tunnel criado."
        rm -f "$response" "$payload"
        return 1
    }
    TUNNEL_TOKEN=$(jq -r '.result.token // empty' "$response")
    if [[ "$TUNNEL_TOKEN" != ey* ]]; then
        TUNNEL_TOKEN=$(primary_tunnel_get_token "$TUNNEL_ID") || {
            primary_tunnel_cf_api DELETE "/accounts/${CLOUDFLARE_ACCOUNT_ID}/cfd_tunnel/${TUNNEL_ID}" "$response" || true
            rm -f "$response" "$payload"
            return 1
        }
    fi
    TUNNEL_OWNERSHIP="setupmno"
    SETUPMNO_PRIMARY_TUNNEL_CONFIG_MAY_BE_EMPTY=true
    if ! primary_tunnel_write_state setupmno pending "$CLOUDFLARE_ACCOUNT_ID" "$CLOUDFLARE_ZONE_ID" "$TUNNEL_ID" "$TUNNEL_NAME"; then
        primary_tunnel_cf_api DELETE "/accounts/${CLOUDFLARE_ACCOUNT_ID}/cfd_tunnel/${TUNNEL_ID}" "$response" || true
        CLOUDFLARE_VALIDATION_ERROR="O Tunnel foi criado, mas o estado transacional não pôde ser salvo; a criação foi revertida."
        rm -f "$response" "$payload"
        return 1
    fi
    SETUPMNO_PRIMARY_DELETE_ON_ROLLBACK=true
    SETUPMNO_PRIMARY_TUNNEL_TRANSACTION=true
    trap 'primary_tunnel_exit_handler $?' EXIT
    rm -f "$response" "$payload"
}

primary_tunnel_write_credentials() {
    local destination="/root/.cloudflared_config/cloudflare_credentials" temporary
    mkdir -p "$(dirname "$destination")" || return 1
    if [ -z "$SETUPMNO_PRIMARY_CREDENTIALS_BACKUP" ]; then
        SETUPMNO_PRIMARY_CREDENTIALS_BACKUP=$(mktemp) || return 1
        chmod 600 "$SETUPMNO_PRIMARY_CREDENTIALS_BACKUP" || return 1
        if [ -f "$destination" ] && [ ! -L "$destination" ]; then
            cp -p "$destination" "$SETUPMNO_PRIMARY_CREDENTIALS_BACKUP" || return 1
            SETUPMNO_PRIMARY_CREDENTIALS_EXISTED=true
        fi
    fi
    temporary=$(mktemp "${destination}.tmp.XXXXXX") || return 1
    chmod 600 "$temporary" || { rm -f "$temporary"; return 1; }
    {
        printf 'CLOUDFLARE_API_TOKEN=%q\n' "$CLOUDFLARE_API_TOKEN"
        printf 'CLOUDFLARE_ACCOUNT_ID=%q\n' "$CLOUDFLARE_ACCOUNT_ID"
        printf 'CLOUDFLARE_ZONE_ID=%q\n' "$CLOUDFLARE_ZONE_ID"
        printf 'CLOUDFLARE_ZONE_NAME=%q\n' "$CLOUDFLARE_ZONE_NAME"
        printf 'TUNNEL_NAME=%q\n' "$TUNNEL_NAME"
        printf 'TUNNEL_ID=%q\n' "$TUNNEL_ID"
        printf 'TUNNEL_OWNERSHIP=%q\n' "$TUNNEL_OWNERSHIP"
    } >"$temporary" || { rm -f "$temporary"; return 1; }
    mv -f "$temporary" "$destination"
}

primary_tunnel_restore_configuration() {
    local payload response
    [ -n "$SETUPMNO_PRIMARY_TUNNEL_CONFIG_BACKUP" ] &&
    [ -f "$SETUPMNO_PRIMARY_TUNNEL_CONFIG_BACKUP" ] || return 0
    payload=$(mktemp) || return 0
    response=$(mktemp) || { rm -f "$payload"; return 0; }
    chmod 600 "$payload" "$response"
    jq '{config:(.result.config // {ingress:[{service:"http_status:404"}]})}' \
        "$SETUPMNO_PRIMARY_TUNNEL_CONFIG_BACKUP" >"$payload" 2>/dev/null || {
        rm -f "$payload" "$response"
        return 0
    }
    primary_tunnel_cf_api PUT "/accounts/${CLOUDFLARE_ACCOUNT_ID}/cfd_tunnel/${TUNNEL_ID}/configurations" "$response" "$payload" || true
    rm -f "$payload" "$response"
}

primary_tunnel_rollback() {
    local response attempt record payload
    SETUPMNO_PRIMARY_TUNNEL_TRANSACTION=false
    primary_tunnel_restore_configuration
    response=$(mktemp 2>/dev/null || true)
    [ -z "$response" ] || chmod 600 "$response"
    if [ -n "$SETUPMNO_PRIMARY_DNS_RECORD_ID" ] && [ -n "$response" ]; then
        primary_tunnel_cf_api DELETE "/zones/${CLOUDFLARE_ZONE_ID}/dns_records/${SETUPMNO_PRIMARY_DNS_RECORD_ID}" "$response" || true
    fi
    if [ "$SETUPMNO_PRIMARY_DNS_MUTATED" = "true" ] && [ -f "$SETUPMNO_PRIMARY_DNS_BACKUP" ] && [ -n "$response" ]; then
        while IFS= read -r record; do
            payload=$(mktemp) || continue
            printf '%s' "$record" | jq '{type,name,content,ttl,proxied} +
                (if .priority != null then {priority} else {} end) +
                (if .comment != null then {comment} else {} end) +
                (if .tags != null then {tags} else {} end)' >"$payload" 2>/dev/null || {
                rm -f "$payload"
                continue
            }
            primary_tunnel_cf_api POST "/zones/${CLOUDFLARE_ZONE_ID}/dns_records" "$response" "$payload" || true
            rm -f "$payload"
        done < <(jq -c '.result[]?' "$SETUPMNO_PRIMARY_DNS_BACKUP" 2>/dev/null)
    fi
    if [ "$SETUPMNO_PRIMARY_STACK_CREATED" = "true" ] && command -v docker >/dev/null 2>&1; then
        docker stack rm cloudflared >>"$PRIMARY_TUNNEL_LOG" 2>&1 || true
        for attempt in $(seq 1 20); do
            docker service inspect cloudflared_cloudflared >/dev/null 2>&1 || break
            sleep 1
        done
    fi
    if [ -n "$SETUPMNO_PRIMARY_TUNNEL_SECRET" ] && command -v docker >/dev/null 2>&1; then
        docker secret rm "$SETUPMNO_PRIMARY_TUNNEL_SECRET" >>"$PRIMARY_TUNNEL_LOG" 2>&1 || true
    fi
    if [ "$SETUPMNO_PRIMARY_DELETE_ON_ROLLBACK" = "true" ] && [ -n "$response" ]; then
        primary_tunnel_cf_api DELETE "/accounts/${CLOUDFLARE_ACCOUNT_ID}/cfd_tunnel/${TUNNEL_ID}" "$response" || true
    fi
    if primary_tunnel_state_valid && [ "$(jq -r '.status' "$PRIMARY_TUNNEL_STATE_FILE")" = "pending" ] &&
       [ "$(jq -r '.tunnelId' "$PRIMARY_TUNNEL_STATE_FILE")" = "$TUNNEL_ID" ]; then
        rm -f "$PRIMARY_TUNNEL_STATE_FILE"
    fi
    if [ "$SETUPMNO_PRIMARY_CREDENTIALS_EXISTED" = "true" ] && [ -f "$SETUPMNO_PRIMARY_CREDENTIALS_BACKUP" ]; then
        cp -p "$SETUPMNO_PRIMARY_CREDENTIALS_BACKUP" /root/.cloudflared_config/cloudflare_credentials 2>/dev/null || true
    elif [ -n "$SETUPMNO_PRIMARY_CREDENTIALS_BACKUP" ]; then
        rm -f /root/.cloudflared_config/cloudflare_credentials
    fi
    rm -f "${response:-}" "${SETUPMNO_PRIMARY_TUNNEL_CONFIG_BACKUP:-}" "${SETUPMNO_PRIMARY_DNS_BACKUP:-}"
    rm -f "${SETUPMNO_PRIMARY_CREDENTIALS_BACKUP:-}"
}

primary_tunnel_exit_handler() {
    local status="$1"
    if [ "$SETUPMNO_PRIMARY_TUNNEL_TRANSACTION" = "true" ]; then
        printf '%s [%s] rollback: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$status" \
            "${CLOUDFLARE_VALIDATION_ERROR:-falha não especificada}" >>"$PRIMARY_TUNNEL_LOG"
        primary_tunnel_rollback
    fi
    return "$status"
}

primary_tunnel_deploy_connector() {
    local token_file stack_file secret_suffix attempt replicas status_file status ready=false
    if docker service inspect cloudflared_cloudflared >/dev/null 2>&1; then
        CLOUDFLARE_VALIDATION_ERROR="Já existe um serviço cloudflared no Swarm. A instalação automática não substituirá um conector preexistente."
        return 1
    fi
    secret_suffix=$(printf '%s' "$TUNNEL_ID" | tr -d '-' | cut -c1-16)
    SETUPMNO_PRIMARY_TUNNEL_SECRET="setupmno_primary_tunnel_${secret_suffix}"
    token_file=$(mktemp) || return 1
    stack_file=$(mktemp) || { rm -f "$token_file"; return 1; }
    chmod 600 "$token_file" "$stack_file"
    printf '%s' "$TUNNEL_TOKEN" >"$token_file"
    if docker secret inspect "$SETUPMNO_PRIMARY_TUNNEL_SECRET" >/dev/null 2>&1; then
        docker secret rm "$SETUPMNO_PRIMARY_TUNNEL_SECRET" >>"$PRIMARY_TUNNEL_LOG" 2>&1 || {
            CLOUDFLARE_VALIDATION_ERROR="Um Docker Secret residual está em uso e não pôde ser renovado."
            rm -f "$token_file" "$stack_file"
            return 1
        }
    fi
    docker secret create "$SETUPMNO_PRIMARY_TUNNEL_SECRET" "$token_file" >>"$PRIMARY_TUNNEL_LOG" 2>&1 || {
        CLOUDFLARE_VALIDATION_ERROR="Não foi possível criar o Docker Secret do Tunnel."
        rm -f "$token_file" "$stack_file"
        return 1
    }
    cat >"$stack_file" <<EOF
version: '3.7'
services:
  cloudflared:
    image: cloudflare/cloudflared
    command: tunnel run --token-file /run/secrets/${SETUPMNO_PRIMARY_TUNNEL_SECRET}
    secrets:
      - ${SETUPMNO_PRIMARY_TUNNEL_SECRET}
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
          cpus: '0.50'
          memory: 256M
secrets:
  ${SETUPMNO_PRIMARY_TUNNEL_SECRET}:
    external: true
networks:
  externa:
    external: true
EOF
    if ! docker stack deploy --prune --resolve-image always -c "$stack_file" cloudflared >>"$PRIMARY_TUNNEL_LOG" 2>&1; then
        CLOUDFLARE_VALIDATION_ERROR="O deploy do cloudflared falhou. Log: ${PRIMARY_TUNNEL_LOG}"
        docker secret rm "$SETUPMNO_PRIMARY_TUNNEL_SECRET" >>"$PRIMARY_TUNNEL_LOG" 2>&1 || true
        SETUPMNO_PRIMARY_TUNNEL_SECRET=""
        rm -f "$token_file" "$stack_file"
        return 1
    fi
    SETUPMNO_PRIMARY_STACK_CREATED=true
    rm -f "$token_file" "$stack_file"
    for attempt in $(seq 1 45); do
        replicas=$(docker service ls --filter name=cloudflared_cloudflared --format '{{.Replicas}}' 2>/dev/null | head -n1)
        [ "$replicas" = "1/1" ] && { ready=true; break; }
        sleep 2
    done
    [ "$ready" = "true" ] || {
        docker service ps --no-trunc cloudflared_cloudflared >>"$PRIMARY_TUNNEL_LOG" 2>&1 || true
        CLOUDFLARE_VALIDATION_ERROR="O cloudflared não atingiu 1/1 réplica. Log: ${PRIMARY_TUNNEL_LOG}"
        return 1
    }
    ready=false
    status_file=$(mktemp) || return 1
    chmod 600 "$status_file"
    for attempt in $(seq 1 45); do
        if primary_tunnel_cf_api GET "/accounts/${CLOUDFLARE_ACCOUNT_ID}/cfd_tunnel/${TUNNEL_ID}" "$status_file" &&
           primary_tunnel_api_success "$status_file"; then
            status=$(jq -r '.result.status // empty' "$status_file")
            [ "$status" = "healthy" ] && { ready=true; break; }
        fi
        sleep 2
    done
    rm -f "$status_file"
    [ "$ready" = "true" ] || {
        CLOUDFLARE_VALIDATION_ERROR="A stack iniciou, mas a Cloudflare não confirmou o Tunnel como Healthy dentro do limite."
        return 1
    }
}

primary_tunnel_commit() {
    primary_tunnel_write_state "$TUNNEL_OWNERSHIP" active "$CLOUDFLARE_ACCOUNT_ID" \
        "$CLOUDFLARE_ZONE_ID" "$TUNNEL_ID" "$TUNNEL_NAME" || return 1
    SETUPMNO_PRIMARY_TUNNEL_TRANSACTION=false
    SETUPMNO_PRIMARY_DELETE_ON_ROLLBACK=false
    trap - EXIT
    rm -f "${SETUPMNO_PRIMARY_TUNNEL_CONFIG_BACKUP:-}"
    rm -f "${SETUPMNO_PRIMARY_DNS_BACKUP:-}"
    rm -f "${SETUPMNO_PRIMARY_CREDENTIALS_BACKUP:-}"
}


#
# FIM DE LOADING
#

#
# NOME DO PROGRAMA
#

{
  tput reset 2>/dev/null         # Reinicia o terminal de forma segura
  exec 0</dev/tty 1>/dev/tty 2>&1 # Força redirecionamentos explícitos
  sleep 0.01                     # Pausa microscópica para sincronia
  clear                          # Limpeza final antes do whiptail
} || true

#########################################################
#
# ESCOLHA DO TIPO DE INSTALAÇÃO
#

export NEWT_COLORS='
root=,white
border=black,gray
title=white,blue
roottext=red,gray
window=red,gray
textbox=white,gray
button=white,green
compactbutton=white,black
listbox=black,white
actlistbox=black,white
actsellistbox=white,green
checkbox=green,black
actcheckbox=white,green
'

# Verificar se já existe uma instalação anterior para determinar o padrão
INSTALL_TYPE_FILE="/root/.cloudflared_config/installation_type"
if [ -f "$INSTALL_TYPE_FILE" ]; then
    DEFAULT_INSTALL_TYPE=$(cat "$INSTALL_TYPE_FILE")
else
    DEFAULT_INSTALL_TYPE="TRADICIONAL"
fi

# Diretório e arquivo onde as informações do trial estão armazenadas
TRIAL_DIR="/root/SetupLowCodeMno/.meu_app_trial"
TRIAL_FILE="$TRIAL_DIR/trial_info"

valid_setup_plan() {
    case "$1" in
        pro|"trial pro"|trial|free|free1|free2) return 0 ;;
        *) return 1 ;;
    esac
}

sync_control_center_installation_type() {
    local environment_file="/root/SetupLowCodeMno/.control/environment.json"
    local temporary_file

    [ -f "$environment_file" ] && [ ! -L "$environment_file" ] || return 1
    temporary_file=$(mktemp "${environment_file}.tmp.XXXXXX") || return 1
    chmod 0644 "$temporary_file" || { rm -f "$temporary_file"; return 1; }
    jq --arg installation_type "$INSTALL_CHOICE" \
        'if .schemaVersion == 1 and (.plan == "pro" or .plan == "free" or .plan == "free1" or .plan == "free2")
         then .installationType = $installation_type
         else error("estado runtime inválido")
         end' \
        "$environment_file" >"$temporary_file" || {
            rm -f "$temporary_file"
            return 1
        }
    mv -f "$temporary_file" "$environment_file"
}

valid_setup_date() {
    local value="$1" formatted
    [[ "$value" =~ ^[0-9]{2}/[0-9]{2}/[0-9]{4}$ ]] || return 1
    formatted=$(printf '%s' "$value" | awk -F/ '{print $2 "/" $1 "/" $3}')
    date -d "$formatted" +%s >/dev/null 2>&1
}

write_trial_state() {
    local temporary_file
    temporary_file=$(mktemp "$TRIAL_DIR/trial_info.tmp.XXXXXX") || return 1
    chmod 600 "$temporary_file" || { rm -f "$temporary_file"; return 1; }
    {
        printf 'DATA_INSTALACAO=%s\n' "$DATA_INSTALACAO"
        printf 'DAYS_TRIAL=%s\n' "$DAYS_TRIAL"
        printf 'PLANO=%q\n' "$PLANO"
    } >"$temporary_file" || { rm -f "$temporary_file"; return 1; }
    mv -f "$temporary_file" "$TRIAL_FILE"
}

# O licenciamento já foi validado pelo start_full. O dockerswarm nunca recebe
# nem persiste as credenciais e deve somente preservar o estado autenticado.
if [ ! -f "$TRIAL_FILE" ] || [ -L "$TRIAL_FILE" ] ||
   [ "$(stat -c '%s' "$TRIAL_FILE" 2>/dev/null || printf '0')" -gt 1024 ]; then
    whiptail --title "ESTADO DE LICENÇA INVÁLIDO" --msgbox \
        "O estado local do plano está ausente ou inseguro. Execute novamente o instalador oficial do Setup MNO para autenticar e reparar a instalação." 14 76
    exit 41
fi

# shellcheck disable=SC1090
source "$TRIAL_FILE"
if ! valid_setup_plan "$PLANO" || ! valid_setup_date "$DATA_INSTALACAO"; then
    whiptail --title "ESTADO DE LICENÇA INVÁLIDO" --msgbox \
        "O plano salvo está vazio ou inválido. Execute novamente o instalador oficial do Setup MNO. O estado atual não será sobrescrito." 14 76
    exit 41
fi

DATA_FORMATADA=$(printf '%s' "$DATA_INSTALACAO" | awk -F/ '{print $2 "/" $1 "/" $3}')
DATA_INSTALACAO_TIMESTAMP=$(date -d "$DATA_FORMATADA" +%s)
DATA_ATUAL_TIMESTAMP=$(date +%s)
DIFERENCA_SEGUNDOS=$(( DATA_INSTALACAO_TIMESTAMP + 7*86400 - DATA_ATUAL_TIMESTAMP ))
DAYS_TRIAL=$(( (DIFERENCA_SEGUNDOS / 86400) + 1 ))
[ "$DAYS_TRIAL" -lt 0 ] && DAYS_TRIAL=0

if ! write_trial_state; then
    whiptail --title "ERRO AO SALVAR O PLANO" --msgbox \
        "Não foi possível atualizar o estado local do plano com segurança. A preparação do servidor foi interrompida." 12 76
    exit 41
fi

# 🚀 DETECÇÃO DE AMBIENTE (WSL2 vs NUVEM)
IS_WSL=0
if grep -qEi "(Microsoft|WSL)" /proc/version &> /dev/null; then
    IS_WSL=1
fi

if [ "$IS_WSL" -eq 1 ]; then
    # Se for WSL2, força Cloudflare Tunnel e avisa o usuário
    whiptail --title "AMBIENTE LOCAL DETECTADO" --msgbox "⚠️ AMBIENTE WINDOWS/MAC (WSL2) DETECTADO!\n\nPara garantir que suas automações funcionem perfeitamente na sua máquina local e consigam furar o bloqueio do seu roteador de internet, o modo TRADICIONAL foi desabilitado.\n\nA instalação prosseguirá obrigatoriamente usando CLOUDFLARE TUNNEL." 15 70
    INSTALL_CHOICE="CLOUDFLARE_TUNNEL"
else
    # Se for VPS na Nuvem, exibe o menu normal
    INSTALL_CHOICE=$(
        whiptail --title "TIPO DE INSTALAÇÃO" --menu "Escolha o tipo de configuração do proxy reverso:" 15 70 3 \
            "TRADICIONAL" "Apenas Traefik (Menos Seguro)" \
            "CLOUDFLARE_TUNNEL" "Cloudflare Tunnel + Traefik (Mais Seguro)" \
            "SAIR" "Abortar a instalação" 3>&2 2>&1 1>&3
        )
fi

if [ $? -ne 0 ]; then
    exit 1
fi
if [ "$INSTALL_CHOICE" = "SAIR" ]; then

    clear
    echo -e "\033[1;36m"
    echo "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓"
    echo -e "\033[1;33m"
    echo "  ███╗   ███╗███╗   ██╗ ██████╗"
    echo "  ████╗ ████║████╗  ██║██╔═══██╗"
    echo "  ██╔████╔██║██╔██╗ ██║██║   ██║"
    echo "  ██║╚██╔╝██║██║╚██╗██║██║   ██║"
    echo "  ██║ ╚═╝ ██║██║ ╚████║╚██████╔╝"
    echo "  ╚═╝     ╚═╝╚═╝  ╚═══╝ ╚═════╝"
    echo -e "\033[1;36m"
    echo "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓"
    echo -e "\033[0m"

    # Efeito de digitação
    type_effect() {
        text=$1
        for (( i=0; i<${#text}; i++ )); do
            echo -n "${text:$i:1}"
            sleep 0.03
        done
        echo ""
    }
    echo -e "\033[1;32m"
    echo -n " ➤ "
    type_effect "INSTALAÇÃO DO SETUP MNO INTERROMPIDA!"
    echo -n " ➤ "
    type_effect "P/ A INSTALAÇÃO RECOMENDAMOS LINUX DEBIAN 12 LIMPO E ZERADO"
      echo -n " ➤ "
    type_effect "P/ RETOMAR A INSTALAÇÃO: DIGITE 'setup-mno' NO TERMINAL"
    echo "┣━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┫"
    echo -e "   \033[1;35m🚀 REQUISITOS MÍNMOS DO SERVIDOR:\033[1;37m 4gb RAM - 2 CVPU\033[1;32m         "
    echo -e "   \033[1;35m🚀 REQUISITOS RECOMENDADOS:\033[1;37m 8gb RAM - 4 CVPU\033[1;32m         "
    echo -e "   \033[1;35m🚀 ANTES DE INSTALAR:\033[1;37m Apontar registros DNS do Portainer\033[1;32m         "
    echo -e "   \033[1;35m📡 CANAIS DE SUPORTE:\033[1;32m                                 "
    echo -e "      \033[1;36m● WhatsApp: +55 (11) 96816-2690\033[1;32m                    "
    echo -e "      \033[1;36m● Email: francisbreit@gmail.com\033[1;32m                    "
    echo -e "      \033[1;36m● GitHub: github.com/francisbreit\033[1;32m                  "
    echo -e "   \033[1;33m⚠️  INSTALAÇÃO INCOMPLETA \033[1;32m                     "
    # Efeito de loading final
    echo -e "\033[1;35m"
    echo -n "  INICIANDO SEQUÊNCIA DE SAÍDA "
    for i in {1..10}; do
        echo -n "●"
        sleep 0.2
    done
    echo ""
    echo -e "\033[1;32m  ✅ SISTEMA ENCERRADO - ATÉ A PRÓXIMA!\033[0m"
        cd /
        cd
    sleep 3

    $SHELL


fi

# Registrar tipo de instalação
mkdir -p "/root/.cloudflared_config"
echo "$INSTALL_CHOICE" > "$INSTALL_TYPE_FILE"
if ! sync_control_center_installation_type; then
    whiptail --title "TIPO DE INSTALAÇÃO NÃO SINCRONIZADO" --msgbox \
        "Não foi possível registrar o tipo escolhido no estado do Control Center. A instalação foi interrompida para evitar uma configuração divergente." 12 78
    exit 41
fi

# As credenciais Cloudflare são coletadas somente depois da URL do Portainer.
# Assim, Account ID e Zone ID podem ser descobertos sem pedir dados redundantes.

# FIM DA ESCOLHA DO TIPO DE INSTALAÇÃO

function msg() {
                msg=$1
                whiptail --title "PARTE INICIAL: INSTALAÇÃO OBRIGATÓRIA DO DOCKER SWARM + ESSENCIAIS (TRAEFIK, PORTAINER, POSTGRES, PGBOUNCER E REDIS)" --msgbox "$msg" --fb 10 70;
        }

if [ "$INSTALL_CHOICE" = "CLOUDFLARE_TUNNEL" ]; then
    INSTALL_DNS_GUIDANCE="O Setup identificará a zona e criará o DNS do Portainer automaticamente. Você não precisa copiar Account ID nem Zone ID."
else
    INSTALL_DNS_GUIDANCE="No modo tradicional você poderá escolher entre criar o DNS automaticamente ou usar apontamentos já existentes."
fi

  while true; do
CHOICE=$(
whiptail --title "PARTE INICIAL: INSTALAÇÃO OBRIGATÓRIA DO DOCKER SWARM + ESSENCIAIS (TRAEFIK, PORTAINER, POSTGRES, PGBOUNCER E REDIS)" --menu "Use setas para navegar e Enter para selecionar.\n\nINSTALAR: prepara Docker Swarm e os serviços essenciais.\nGERADOR DE REGISTROS DNS: gera orientações para configuração manual.\n\n${INSTALL_DNS_GUIDANCE}" 18 78 3 \
  "INSTALAR" "" \
  "GERADOR DE REGISTROS DNS" "" \
  "SAIR" ""  3>&2 2>&1 1>&3
)


case $CHOICE in

        "INSTALAR")
                clear
        break
        ;;
   "GERADOR DE REGISTROS DNS")
          clear
        cd && cd SetupLowCodeMno && ./geracloudflare
    ;;

"SAIR")
    clear
    echo -e "\033[1;36m"
    echo "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓"
    echo -e "\033[1;33m"
    echo "  ███╗   ███╗███╗   ██╗ ██████╗"
    echo "  ████╗ ████║████╗  ██║██╔═══██╗"
    echo "  ██╔████╔██║██╔██╗ ██║██║   ██║"
    echo "  ██║╚██╔╝██║██║╚██╗██║██║   ██║"
    echo "  ██║ ╚═╝ ██║██║ ╚████║╚██████╔╝"
    echo "  ╚═╝     ╚═╝╚═╝  ╚═══╝ ╚═════╝"
    echo -e "\033[1;36m"
    echo "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓"
    echo -e "\033[0m"

    # Efeito de digitação
    type_effect() {
        text=$1
        for (( i=0; i<${#text}; i++ )); do
            echo -n "${text:$i:1}"
            sleep 0.03
        done
        echo ""
    }
    echo -e "\033[1;32m"
    echo -n " ➤ "
    type_effect "INSTALAÇÃO DO SETUP MNO INTERROMPIDA!"
    echo -n " ➤ "
    type_effect "P/ A INSTALAÇÃO RECOMENDAMOS LINUX DEBIAN 12 LIMPO E ZERADO"
      echo -n " ➤ "
    type_effect "P/ RETOMAR A INSTALAÇÃO: DIGITE 'setup-mno' NO TERMINAL"
    echo "┣━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┫"
    echo -e "   \033[1;35m🚀 REQUISITOS MÍNMOS DO SERVIDOR:\033[1;37m 4gb RAM - 2 CVPU\033[1;32m         "
    echo -e "   \033[1;35m🚀 REQUISITOS RECOMENDADOS:\033[1;37m 8gb RAM - 4 CVPU\033[1;32m         "
    echo -e "   \033[1;35m🚀 ANTES DE INSTALAR:\033[1;37m Apontar registros DNS do Portainer\033[1;32m         "
    echo -e "   \033[1;35m📡 CANAIS DE SUPORTE:\033[1;32m                                 "
    echo -e "      \033[1;36m● WhatsApp: +55 (11) 96816-2690\033[1;32m                    "
    echo -e "      \033[1;36m● Email: francisbreit@gmail.com\033[1;32m                    "
    echo -e "      \033[1;36m● GitHub: github.com/francisbreit\033[1;32m                  "
    echo -e "   \033[1;33m⚠️  INSTALAÇÃO INCOMPLETA \033[1;32m                     "
    # Efeito de loading final
    echo -e "\033[1;35m"
    echo -n "  INICIANDO SEQUÊNCIA DE SAÍDA "
    for i in {1..10}; do
        echo -n "●"
        sleep 0.2
    done
    echo ""
    echo -e "\033[1;32m  ✅ SISTEMA ENCERRADO - ATÉ A PRÓXIMA!\033[0m"
        cd /
        cd
    sleep 3
    $SHELL
    ;;
esac
done

if command -v docker > /dev/null 2>&1; then
network_id_agent_network=$(docker network ls --filter name=agent_network --format "{{.ID}}")
network_id_externa=$(docker network ls --filter name=externa --format "{{.ID}}")
network_id_interna=$(docker network ls --filter name=interna --format "{{.ID}}")
traefik_container=$(docker ps -qf name=traefik)
portainer_container=$(docker ps -qf name=portainer)
postgres_container=$(docker ps -qf name=postgres)
redis_container=$(docker ps -qf name=redis)
pgbouncer_container=$(docker ps -qf name=pgbouncer)

else
network_id_agent_network=""
network_id_externa=""
network_id_interna=""
traefik_container=""
portainer_container=""
postgres_container=""
redis_container=""
pgbouncer_container=""


fi

    if [[ ("$portainer_container" == "") ]]; then
    while true ; do
                dominio=$(whiptail --title "URL do Portainer" --inputbox "Digite seu dominio para acessar o Portainer (Sem https://  ex: admin.dominio.com):" --fb 12 60 3>&1 1>&2 2>&3) ; saida=$?
                if [[ $saida -eq '0' ]] ; then
                        dominio_normalizado=$(normalize_cloudflare_hostname "$dominio" 2>/dev/null || true)
                        if [[ -z $dominio_normalizado ]] ; then msg "Digite um domínio válido para o Portainer, sem caminho. Exemplo: painel.seudominio.com.br" ; continue ; else dominio="$dominio_normalizado"; break; fi
                else
                        echo $dominio ; echo "saindo..."  &  exit 0 ;
                fi
        done

if [ "$INSTALL_CHOICE" = "CLOUDFLARE_TUNNEL" ]; then
    collect_primary_tunnel_context "$dominio" || exit $?
fi

# Verificar se URL já existe no Cloudflare Tunnel
if [ "$INSTALL_CHOICE" = "CLOUDFLARE_TUNNEL" ] && [ "$TUNNEL_SETUP_MODE" = "EXISTENTE" ]; then
    CHECK_RESPONSE=$(curl -sS -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
      "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/cfd_tunnel/$TUNNEL_ID/configurations")
    EXISTING_HOST=$(echo "$CHECK_RESPONSE" | jq -r --arg h "$dominio" '.result.config.ingress[] | select(.hostname == $h) | .hostname' 2>/dev/null)
    if [[ -n "$EXISTING_HOST" ]]; then
        EXISTING_SERVICE=$(echo "$CHECK_RESPONSE" | jq -r --arg h "$dominio" '.result.config.ingress[] | select(.hostname == $h) | .service' 2>/dev/null)
        whiptail --title "Rota Existente" --msgbox "Já existe uma rota configurada para:\n\nURL: $dominio\nServiço: $EXISTING_SERVICE\n\nA rota será substituída pela nova aplicação." --fb 14 70
    fi
fi

    while true ; do
                usuariopt=$(whiptail --title "Crie o Usuário do Portainer" --inputbox "Digite o Usuario do Portainer(ex: Nome):" --fb 12 60 3>&1 1>&2 2>&3) ; saida=$?
                if [[ $saida -eq '0' ]] ; then
                if [[ (-z $usuariopt) || ("$usuariopt" =~ [^a-zA-Z0-9]) || (${#usuariopt} -gt 16) ]] ; then msg "Digite o usuário do Portainer, sem caracteres especiais e até 16 digitos para poder continuar" ; continue ; else break; fi
    else
                        echo $usuariomq ; echo "saindo..."  &  exit 0 ;
                fi
        done

    while true ; do
    senhapt=$(whiptail --title "Criar senha do Portainer" --inputbox "Crie Senha do Portainer (mínimo 12 caracteres, máximo 16, sem caracteres especiais):" --fb 12 60 3>&1 1>&2 2>&3)
    saida=$?

    if [[ $saida -eq '0' ]]; then
        # Verificações em cascata
        if [[ -z $senhapt ]]; then
            msg "A senha não pode estar vazia! Digite uma senha válida."
            continue
        elif [[ "${#senhapt}" -lt 12 ]]; then
            msg "A senha deve ter no mínimo 12 caracteres! Tente novamente."
            continue
        elif [[ "${#senhapt}" -gt 16 ]]; then
            msg "A senha não pode ultrapassar 16 caracteres! Tente novamente."
            continue
        elif [[ "$senhapt" =~ [^a-zA-Z0-9] ]]; then
            msg "Caracteres especiais não são permitidos! Use apenas letras e números."
            continue
        else
            break
        fi
    else
        echo "Operação cancelada pelo usuário."
        exit 0
    fi
done

    fi

     if [[ ("$traefik_container" == "") ]]; then
      while true ; do
                mail=$(whiptail --title "Seu Email" --inputbox "Digite seu email (ex: contato@dominio.com | sera usado no proxy reverso):" --fb 12 60 3>&1 1>&2 2>&3) ; saida=$?
                if [[ $saida -eq '0' ]] ; then
                        if [[ -z $mail ]] ; then msg "Digite o email para poder continuar" ; continue ; else break; fi
                else
                        echo $mail ; echo "saindo..."  &  exit 0 ;
                fi
        done
    fi

    if [[ ("$postgres_container" == "") ]]; then
     while true ; do
                postgres_senha=$(whiptail --title "Senha do Postgres" --inputbox "Crie a senha do Postgres (obs: use senha segura):" --fb 12 60 3>&1 1>&2 2>&3) ; saida=$?
                if [[ $saida -eq '0' ]] ; then
                if [[ (-z $postgres_senha) || ("$postgres_senha" =~ [^a-zA-Z0-9]) || (${#postgres_senha} -gt 16) ]] ; then msg "Crie a senha do Postgres, sem caracteres especiais e até 16 digitos para poder continuar" ; continue ; else break; fi
    else
                        echo $postgres_senha ; echo "saindo..."  &  exit 0 ;
                fi
        done
    fi

if [ "$INSTALL_CHOICE" = "TRADICIONAL" ]; then
 # Perguntar ao usuário se deseja criar a stack no Portainer

 dns_choice=$(whiptail --title "CONFIGURAÇÃO DO DNS" --default-item "AUTOMATICO" --menu \
    "Escolha como o domínio do Portainer será configurado:" 15 78 3 \
    "AUTOMATICO" "Criar e validar os registros pela Cloudflare — RECOMENDADO" \
    "MANUAL" "Usar registros DNS que já foram configurados" \
    "VOLTAR" "Cancelar a instalação" \
    3>&1 1>&2 2>&3) || exit 130
 case "$dns_choice" in
    AUTOMATICO) criar_dns="0" ;;
    MANUAL) criar_dns="1" ;;
    *) exit 130 ;;
 esac


if [ "$criar_dns" = "0" ]; then


     while true ; do
                nome_servidor=$(whiptail --title "Nomw do Servidor" --inputbox "Crie o nome do servidor c/ letras minúsculas, sem acento e sem o dominio (exemplo: manager1, server02, etc):" --fb 12 60 3>&1 1>&2 2>&3) ; saida=$?
                if [[ $saida -eq '0' ]] ; then
                if [[ (-z $nome_servidor) || ("$nome_servidor" =~ [^a-zA-Z0-9]) || (${#nome_servidor} -gt 16) ]] ; then msg "Crie a nome do servidor, sem caracteres especiais e até 16 digitos para poder continuar" ; continue ; else break; fi
    else
                        echo $nome_servidor ; echo "saindo..."  &  exit 0 ;
                fi
        done


 # Coletar e VALIDAR credenciais do Cloudflare
    while true; do
        # Início do questionário Cloudflare do modo TRADICIONAL.
        # Qualquer falha retorna para este ponto e solicita novamente os dados.
        while true; do
            CLOUDFLARE_API_TOKEN2=$(whiptail --title "API TOKEN DA CLOUDFLARE" --passwordbox "Informe o API Token com estas permissões:\n\nZona > Zona > Leitura\nZona > DNS > Edição\n\nAccount ID e Zone ID serão descobertos automaticamente." 15 82 3>&1 1>&2 2>&3)
            if [ $? -ne 0 ]; then
                exit 1
            fi
            if [ -z "$CLOUDFLARE_API_TOKEN2" ]; then
                whiptail --msgbox "O Cloudflare API Token é obrigatório para criar os registros DNS automaticamente." 10 70
            else
                break
            fi
        done

        if discover_cloudflare_zone_context "$CLOUDFLARE_API_TOKEN2" "$dominio"; then
            CLOUDFLARE_ZONE_ID2="$CLOUDFLARE_ZONE_ID"
            CLOUDFLARE_ACCOUNT_ID2="$CLOUDFLARE_ACCOUNT_ID"
            CLOUDFLARE_ZONE_NAME2="$CLOUDFLARE_ZONE_NAME"

            whiptail --title "CREDENCIAIS CLOUDFLARE VÁLIDAS" --msgbox \
                "Zona identificada automaticamente: ${CLOUDFLARE_ZONE_NAME2}\n\nAPI Token, leitura da zona e acesso ao DNS validados. A criação automática dos registros poderá continuar." \
                12 76
            break
        fi

        whiptail --title "CREDENCIAIS CLOUDFLARE INVÁLIDAS" --msgbox \
            "${CLOUDFLARE_VALIDATION_ERROR}\n\nNenhuma configuração DNS foi aplicada. Você não precisa informar Account ID nem Zone ID; revise somente o domínio e o API Token." \
            16 78
    done

fi

fi

CONTROL_MFA_DESIRED="false"
CONTROL_MFA_PENDING="false"
if control_mfa_state_valid; then
    CONTROL_MFA_DESIRED=$(jq -r '.desiredMFA' "$CONTROL_MFA_STATE_FILE")
    CONTROL_MFA_PENDING=$(jq -r '.activationPromptPending' "$CONTROL_MFA_STATE_FILE")
elif [ "$INSTALL_CHOICE" = "CLOUDFLARE_TUNNEL" ]; then
    choose_control_mfa_preference || exit 0
fi
if [ "$CONTROL_MFA_DESIRED" = "true" ]; then
    CONTROL_MFA_SUMMARY="Ativar MFA no Control Center quando o painel for instalado"
else
    CONTROL_MFA_SUMMARY="Desativado (modo original; pode ser alterado no menu)"
fi

clear


# FIM DAS PERGUNTAS PARA VARIAVEIS

# VERIFICAÇÃO DE DADOS

clear

while true; do
    # Exibe as informações formatadas com mais espaço na tela
    if [[ "$INSTALL_CHOICE" = "CLOUDFLARE_TUNNEL" ]]; then
        if [ "$TUNNEL_SETUP_MODE" = "AUTO" ]; then
            TUNNEL_METHOD_SUMMARY="Criação automática (recomendada)"
            TUNNEL_ID_SUMMARY="Será criado após a confirmação"
        else
            TUNNEL_METHOD_SUMMARY="Tunnel existente (método clássico)"
            TUNNEL_ID_SUMMARY="$TUNNEL_ID"
        fi
        whiptail --title "Dados Fornecidos" \
        --msgbox "TIPO DE INSTALAÇÃO: CLOUDFLARE TUNNEL\n\nDados Preenchidos:\n\n1) Dominio Portainer: $dominio\n2) Usuário do Portainer: $usuariopt\n3) Senha do Portainer: $senhapt\n4) Seu Email: $mail\n5) Senha do Postgres: $postgres_senha\n6) MFA Control Center: $CONTROL_MFA_SUMMARY\n\nCloudflare:\n- Zona identificada: $CLOUDFLARE_ZONE_NAME\n- Método: $TUNNEL_METHOD_SUMMARY\n- Tunnel ID: $TUNNEL_ID_SUMMARY\n\nAccount ID e Zone ID foram descobertos automaticamente.\n\nConfira e Tecle Enter para continuar. Na próxima etapa você poderá confirmar os dados ou corrigir, se necessário." \
        --fb 22 80
    else
    if [ "$criar_dns" = "0" ]; then
        whiptail --title "Dados Fornecidos" \
        --msgbox "TIPO DE INSTALAÇÃO: TRADICIONAL\n\nDados Preenchidos:\n\n1) Dominio Portainer: $dominio\n2) Usuário do Portainer: $usuariopt\n3) Senha do Portainer: $senhapt\n4) Seu Email: $mail\n5) Senha do Postgres: $postgres_senha\n\nCloudflare:\n- Zona identificada: $CLOUDFLARE_ZONE_NAME2\n- DNS: criação automática\n\nAccount ID e Zone ID foram descobertos automaticamente.\n\nConfira e Tecle Enter para continuar. Na próxima etapa você poderá confirmar os dados ou corrigir, se necessário." \
        --fb 22 80
    else

       whiptail --title "Dados Fornecidos" \
        --msgbox "TIPO DE INSTALAÇÃO: TRADICIONAL\n\nDados Preenchidos:\n\n1) Dominio Portainer: $dominio\n2) Usuário do Portainer: $usuariopt\n3) Senha do Portainer: $senhapt\n4) Seu Email: $mail\n5) Senha do Postgres: $postgres_senha\n\nConfira e Tecle Enter para continuar. Na próxima etapa você poderá confirmar os dados ou corrigir, se necessário." \
        --fb 22 80

    fi
    fi

    # Solicita confirmação com inputbox
    confirma1=$(whiptail --title "Confirmação" \
    --inputbox "Informações estavam corretas? Digite 'y' para confirmar e continuar a instalação ou 'n' para voltar e corrigir:" \
    --fb 10 60 3>&1 1>&2 2>&3)

 # Se o usuário digitou "y" ou "Y", continue
    if [[ "$confirma1" =~ ^[yY]$ ]]; then
        break
    elif [[ "$confirma1" =~ ^[nN]$ ]]; then
        # Se o usuário digitou "n" ou "N", saia do script
        msg "Você digitou N e não confirmou os dados preenchidos. Tecle Enter para sair da instalação."
        exit 0
    else
        # Qualquer outra entrada, mostre uma mensagem de erro e repita
        msg "Entrada inválida! Por favor, use apenas 'y' para sim ou 'n' para não. Digite Enter para continuar"
    fi
done

# FIM DE VERIFICAÇÃO DE DADOS

if ! control_mfa_state_valid; then
    if ! write_control_mfa_state "$CONTROL_MFA_DESIRED" false "$CONTROL_MFA_PENDING" fresh-portainer; then
        whiptail --title "ERRO AO REGISTRAR A SEGURANÇA" --msgbox \
            "Não foi possível registrar com segurança a preferência de MFA. A instalação foi interrompida antes de criar os serviços." 13 82
        exit 41
    fi
fi

#  INSTALANDO AS DEPENDENCIAS E DOCKER SWARM

export NEWT_COLORS='
root=,white
window=,black
border=white,black
textbox=white,black
button=black,white
'

clear
set -o pipefail
{

# Função para verificar o domínio


    if [[ "$INSTALL_CHOICE" = "CLOUDFLARE_TUNNEL" ]]; then
      echo -e "XXX\n2\nCLOUDFLARE VALIDADA; O TUNNEL SERÁ PREPARADO APÓS O DOCKER SWARM\nXXX"
      sleep 2


else


    mkdir -p /root/.tradicional_config
  cat > /root/.tradicional_config/tradicional_credentials << EOL
nome_servidor=$nome_servidor
criar_dns=$criar_dns
CLOUDFLARE_API_TOKEN=$CLOUDFLARE_API_TOKEN2
CLOUDFLARE_ZONE_ID=$CLOUDFLARE_ZONE_ID2
CLOUDFLARE_ACCOUNT_ID=$CLOUDFLARE_ACCOUNT_ID2
CLOUDFLARE_ZONE_NAME=$CLOUDFLARE_ZONE_NAME2

EOL
  chmod 600 /root/.tradicional_config/tradicional_credentials

        # Verificação tradicional (com IP)

if [ "$criar_dns" = "1" ]; then
   ip_servidor=$(curl -s --max-time 10 ipinfo.io/ip)
    echo -e "XXX\n3\nVERIFICANDO SUBDOMÍNIO: $dominio \nXXX"
   sleep 3
    # Verifica apenas se o domínio está apontando para o IP correto
    dns_ip=$(timeout 10 nslookup $dominio | grep "Address" | tail -n1 | awk '{print $2}')
    if [[ "$dns_ip" != "$ip_servidor" ]]; then
        echo -e "XXX\n10\nERRO: SUBDOMÍNIO NÃO APONTA PARA O IP DO SERVIDOR ($ip_servidor) \nXXX"
    sleep 3
        echo -e "XXX\n18\nERRO: REGISTROS DNS NÃO ENCONTRADOS \nXXX"
        sleep 3
        exit 1
    fi

    echo -e "XXX\n15\nDOMÍNIO VERIFICADO COM SUCESSO \nXXX"
sleep 4

fi

fi

####### fim de verificando dominio
estado=$(docker info --format '{{.Swarm.LocalNodeState}}' 2>/dev/null)

if [ "$estado" != "active" ] && [ "$estado" != "pending" ]; then



echo -e "XXX\n16\nATUALIZANDO PACOTES DO SERVIDOR 1/4 \nXXX"


# --- Início: detecção de distro / validação de versão ---
. /etc/os-release

OS_ID="${ID,,}"                       # 'debian' ou 'ubuntu' (força lowercase)
VERSION_ID_RAW="${VERSION_ID}"        # por exemplo "11" ou "22.04"
VERSION_CODENAME="${VERSION_CODENAME:-$(lsb_release -cs 2>/dev/null || true)}"

# Normaliza VERSION_ID (remove aspas se houver)
VERSION_ID=$(echo "$VERSION_ID_RAW" | tr -d '"')

# Verifica se distro suportada
supported=false
if [ "$OS_ID" = "debian" ]; then
  case "$VERSION_ID" in
    11|12|13) supported=true ;;
  esac
elif [ "$OS_ID" = "ubuntu" ]; then
  case "$VERSION_ID" in
    22.04|24.04|26.04) supported=true ;;
  esac
fi

if [ "$supported" != "true" ]; then
  echo -e "XXX\n16\nERRO: Distribuição ou versão não suportada: $OS_ID $VERSION_ID\nXXX"
  sleep 4
  echo "Suportado: debian 11,12,13 e ubuntu 22.04,24.04,26.04"
  echo -e "XXX\n17\nSuportado: debian 11,12,13 e ubuntu 22.04,24.04,26.04\nXXX"
  sleep 4
  exit 1
fi

  echo -e "XXX\n17\nDistribuição detectada: $OS_ID $VERSION_ID ($VERSION_CODENAME) - AGUARDE\nXXX"
  sleep 2
# --- Fim da detecção ---


cd /
cd

# Pacotes base
apt-get install sudo -y >/dev/null 2>&1
sudo apt-get update -y >/dev/null 2>&1
sudo apt upgrade -y >/dev/null 2>&1
sudo apt-get install -y apt-utils >/dev/null 2>&1
sudo apt-get install -y apparmor-utils >/dev/null 2>&1
# sudo DEBIAN_FRONTEND=noninteractive apt install -y dnsutils >/dev/null 2>&1
apt install -y sudo gnupg2 wget ca-certificates apt-transport-https curl gnupg nano htop lsb-release >/dev/null 2>&1
sudo install -m 0755 -d /etc/apt/keyrings >/dev/null 2>&1
sudo apt-get install jq -y >/dev/null 2>&1
sudo apt-get install git -y >/dev/null 2>&1

# Preparar repositório Docker (usa caminho apropriado para debian/ubuntu)
sudo apt-get update -y >/dev/null 2>&1
sudo apt-get install -y ca-certificates curl gnupg lsb-release >/dev/null 2>&1
sudo install -m 0755 -d /etc/apt/keyrings >/dev/null 2>&1

# Baixa a chave e cria keyring no local recomendado
curl -fsSL "https://download.docker.com/linux/${OS_ID}/gpg" \
| sudo gpg --batch --yes --dearmor -o /etc/apt/keyrings/docker.gpg >/dev/null 2>&1

sudo chmod a+r /etc/apt/keyrings/docker.gpg >/dev/null 2>&1

echo \
"deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/${OS_ID} \
${VERSION_CODENAME} stable" \
| sudo tee /etc/apt/sources.list.d/docker.list >/dev/null 2>&1


sudo apt-get update -y >/dev/null 2>&1


# Instala o Docker (Se for VPS) ou Pula (Se for WSL2)
echo -e "XXX\n25\nATUALIZANDO PACOTES DO SERVIDOR 1/4 - CONCLUIDO \nXXX"

if [ "$IS_WSL" -eq 0 ]; then
    # --- INSTALAÇÃO NA NUVEM (VPS) ---
    echo -e "XXX\n25\nINSTALANDO DOCKER ENGINE 2/4 \nXXX"
    sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin >/dev/null 2>&1

    # 🔧 CORREÇÃO PARA COMPATIBILIDADE DA API DOCKER
    echo -e "XXX\n28\nCONFIGURANDO COMPATIBILIDADE DA API DOCKER\nXXX"
    sudo mkdir -p /etc/systemd/system/docker.service.d >/dev/null 2>&1
    sudo tee /etc/systemd/system/docker.service.d/override.conf >/dev/null <<EOF
[Service]
Environment=DOCKER_MIN_API_VERSION=1.24
EOF

    sudo systemctl daemon-reexec >/dev/null 2>&1
    sudo systemctl daemon-reload >/dev/null 2>&1
    sudo systemctl restart docker >/dev/null 2>&1
    sleep 3
    # 🔧 FIM DA CORREÇÃO

    sudo systemctl enable docker.service >/dev/null 2>&1
    sudo systemctl enable containerd.service >/dev/null 2>&1
    
    # Pega o IP real da placa de rede da VPS
    ip=$(hostname -I | cut -d' ' -f1)

else
    # --- INSTALAÇÃO LOCAL (WSL2) ---
    echo -e "XXX\n25\nAMBIENTE WSL: USANDO DOCKER DESKTOP EXISTENTE 2/4 \nXXX"
    sleep 2
    
    # Força o Swarm a usar o localhost para nunca dar erro ao reiniciar o Windows
    ip="127.0.0.1"
fi

sudo timedatectl set-timezone America/Sao_Paulo >/dev/null 2>&1
sudo apt-get install -y postgresql-client >/dev/null 2>&1

sleep 5


max_attempts=3
attempt=0

while [ $attempt -le $max_attempts ]; do
   sudo docker swarm init --advertise-addr $ip > /dev/null 2>&1
    if [ $? -eq 0 ]; then
        echo -e "XXX\n32\nINICIANDO SWARM - OK \nXXX"
        break
    else
        echo -e "XXX\n35\nINICIANDO SWARM - ERRO \nXXX"
        sleep 2
        echo -e "XXX\n35\nERRO: TENTATIVA $attempt de $max_attempts  \nXXX"
        attempt=$((attempt + 1))
        sleep 3
    fi
done

if [ $attempt -gt $max_attempts ]; then
   echo -e "XXX\n35\nERRO: NÃO FOI POSSÍVEL INICIAR O SWARM APÓS $max_attempts TENTATIVAS \nXXX"
   sleep 3
   echo -e "XXX\n36\nERRO: FORMATE O VPS\nXXX"
   sleep 3
   echo -e "XXX\n37\nERRO: USE VPS VAZIA\nXXX"
   sleep 4
fi

docker network create --driver=overlay agent_network >/dev/null 2>&1
docker network create --driver=overlay externa >/dev/null 2>&1
docker network create --driver=overlay interna >/dev/null 2>&1


sudo apt install -y ca-certificates curl gnupg >/dev/null 2>&1

curl -fsSL https://azlux.fr/repo.gpg.key \
| sudo gpg --batch --yes --dearmor -o /usr/share/keyrings/azlux-archive-keyring.gpg >/dev/null 2>&1

# 🔴 SEM usar ubuntu/noble (causa 404)
# 🔴 Sempre usar debian stable (funciona em Debian e Ubuntu)

echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/azlux-archive-keyring.gpg] \
http://packages.azlux.fr/debian stable main" \
| sudo tee /etc/apt/sources.list.d/azlux.list >/dev/null 2>&1

sudo apt update -y >/dev/null 2>&1
sudo apt install -y docker-ctop >/dev/null 2>&1 || true
sudo apt install -y btop >/dev/null 2>&1
cd
cd


echo -e "XXX\n50\nINSTALANDO DOCKER 2/4 - CONCLUIDO \nXXX"
sleep 3
echo -e "XXX\n51\nINSTALANDO TRAEFIK E PORTAINER 3/4 \nXXX"
sleep 3

fi
#
# FIM DE INSTALANDO AS DEPENDENCIAS E DOCKER SWARM

#  INSTALANDO O TRAEFIK
#
cd
cd

if [[ ("$traefik_container" == "") ]]; then

if [ "$INSTALL_CHOICE" = "TRADICIONAL" ]; then
    # CONFIGURAÇÃO TRADICIONAL (com portas)
    cat > traefik.yaml << EOL

version: '3.7'
services:
    traefik:
        image: traefik:v2.11.46
        command:
            - "--providers.docker=true"
            - "--providers.docker.swarmMode=true"
            - "--providers.docker.endpoint=unix:///var/run/docker.sock"
            - "--providers.docker.exposedbydefault=false"
            - "--providers.docker.network=externa"
            - "--entrypoints.web.address=:80"
            - "--entrypoints.web.http.redirections.entryPoint.to=websecure"
            - "--entrypoints.web.http.redirections.entryPoint.scheme=https"
            - "--entrypoints.web.http.redirections.entrypoint.permanent=true"
            - "--entrypoints.websecure.address=:443"
            - "--certificatesresolvers.letsencryptresolver.acme.httpchallenge=true"
            - "--certificatesresolvers.letsencryptresolver.acme.httpchallenge.entrypoint=web"
            - "--certificatesresolvers.letsencryptresolver.acme.email=$mail"
            - "--certificatesresolvers.letsencryptresolver.acme.storage=/etc/traefik/letsencrypt/acme.json"
            - "--log.level=DEBUG"
            - "--log.format=common"
            - "--log.filePath=/var/log/traefik/traefik.log"
            - "--accesslog=true"
            - "--accesslog.filepath=/var/log/traefik/access-log"
        deploy:
            placement:
                constraints:
                    - node.role == manager
            labels:
                - "traefik.enable=true"
                - "traefik.http.middlewares.redirect-https.redirectscheme.scheme=https"
                - "traefik.http.middlewares.redirect-https.redirectscheme.permanent=true"
                - "traefik.http.routers.http-catchall.rule=hostregexp(\`{host:.+}\`)"
                - "traefik.http.routers.http-catchall.entrypoints=web"
                - "traefik.http.routers.http-catchall.middlewares=redirect-https@docker"
                - "traefik.http.routers.http-catchall.priority=1"
        volumes:
            - "/var/run/docker.sock:/var/run/docker.sock:ro"
            - "vol_certificates:/etc/traefik/letsencrypt"
        ports:
            - target: 80
              published: 80
              mode: host
            - target: 443
              published: 443
              mode: host

        networks:
            - externa
volumes:
    vol_shared:
        external: true
        name: volume_swarm_shared
    vol_certificates:
        external: true
        name: volume_swarm_certificates
networks:
    externa:
        external: true

EOL

else
    # CONFIGURAÇÃO CLOUDFLARE TUNNEL (sem portas)
    cat > traefik.yaml << EOL

version: '3.7'
services:
    traefik:
        image: traefik:v2.11.46
        command:
            - "--providers.docker=true"
            - "--providers.docker.swarmMode=true"
            - "--providers.docker.endpoint=unix:///var/run/docker.sock"
            - "--providers.docker.exposedbydefault=false"
            - "--providers.docker.network=externa"
            - "--entrypoints.web.address=:80"
            - "--entrypoints.web.http.redirections.entryPoint.to=websecure"
            - "--entrypoints.web.http.redirections.entryPoint.scheme=https"
            - "--entrypoints.web.http.redirections.entrypoint.permanent=true"
            - "--entrypoints.websecure.address=:443"
            - "--certificatesresolvers.letsencryptresolver.acme.httpchallenge=true"
            - "--certificatesresolvers.letsencryptresolver.acme.httpchallenge.entrypoint=web"
            - "--certificatesresolvers.letsencryptresolver.acme.email=$mail"
            - "--certificatesresolvers.letsencryptresolver.acme.storage=/etc/traefik/letsencrypt/acme.json"
            - "--log.level=DEBUG"
            - "--log.format=common"
            - "--log.filePath=/var/log/traefik/traefik.log"
            - "--accesslog=true"
            - "--accesslog.filepath=/var/log/traefik/access-log"
        deploy:
            placement:
                constraints:
                    - node.role == manager
            labels:
                - "traefik.enable=true"
                - "traefik.http.middlewares.redirect-https.redirectscheme.scheme=https"
                - "traefik.http.middlewares.redirect-https.redirectscheme.permanent=true"
                - "traefik.http.routers.http-catchall.rule=hostregexp(\`{host:.+}\`)"
                - "traefik.http.routers.http-catchall.entrypoints=web"
                - "traefik.http.routers.http-catchall.middlewares=redirect-https@docker"
                - "traefik.http.routers.http-catchall.priority=1"
        volumes:
            - "/var/run/docker.sock:/var/run/docker.sock:ro"
            - "vol_certificates:/etc/traefik/letsencrypt"

        networks:
            - externa
volumes:
    vol_shared:
        external: true
        name: volume_swarm_shared
    vol_certificates:
        external: true
        name: volume_swarm_certificates
networks:
    externa:
        external: true

EOL
fi

docker stack deploy --prune --resolve-image always -c traefik.yaml traefik >/dev/null 2>&1
fi

# FIM DE INSTALANDO O TRAEFIK
#
#  INSTALANDO ROTA CLOUDFLARED TUNNEL (se necessário)
#
if [[ "$INSTALL_CHOICE" = "CLOUDFLARE_TUNNEL" ]]; then
  echo -e "XXX\n55\nCRIANDO SERVIÇO E ROTA CLOUDFLARE TUNNEL \nXXX"
  sleep 3
  : >"$PRIMARY_TUNNEL_LOG"
  chmod 600 "$PRIMARY_TUNNEL_LOG"

  if [ "$TUNNEL_SETUP_MODE" = "AUTO" ]; then
      echo -e "XXX\n55\nCRIANDO O TUNNEL PRINCIPAL PELA API DA CLOUDFLARE\nXXX"
      primary_tunnel_begin_automatic || {
          exit 1
      }
  else
      echo -e "XXX\n55\nPREPARANDO O TUNNEL EXISTENTE SEM TRANSFERIR SUA PROPRIEDADE\nXXX"
      primary_tunnel_begin_existing || {
          exit 1
      }
  fi
  primary_tunnel_write_credentials || {
      CLOUDFLARE_VALIDATION_ERROR="Não foi possível salvar as credenciais da Cloudflare de forma atômica."
      exit 1
  }

NEW_SERVICE="http://portainer:9000"
DOMINIO_PRINCIPAL="$CLOUDFLARE_ZONE_NAME"
FORCE_VERSION=3   # deixe vazio "" se não quiser forçar


# ----------- sanity checks ------------
command -v curl >/dev/null 2>&1 || { echo "curl required"; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "jq required"; exit 2; }

# ----------- temp files ------------
TIMESTAMP=$(date -u +%Y%m%dT%H%M%SZ)
TMPDIR=$(mktemp -d)
BACKUP_RAW="$TMPDIR/backup_raw.$TIMESTAMP.json"
TO_PUT="$TMPDIR/to_put.$TIMESTAMP.json"

# echo "[*] tmpdir: $TMPDIR"

# ----------- 1) GET current configuration (backup) ------------
if ! primary_tunnel_get_configuration "$BACKUP_RAW" \
    "$SETUPMNO_PRIMARY_TUNNEL_CONFIG_MAY_BE_EMPTY"; then
  exit 1
fi
if jq -e '.setupmnoInitialEmpty == true' "$BACKUP_RAW" >/dev/null 2>&1; then
  SETUPMNO_PRIMARY_TUNNEL_CONFIG_BACKUP=""
else
  SETUPMNO_PRIMARY_TUNNEL_CONFIG_BACKUP="$BACKUP_RAW"
fi

# ----------- 2) build safe payload (preserve existing, avoid duplicates, one catch-all) ------------


jq --arg host "$dominio" --arg service "$NEW_SERVICE" '
  (.result.config // {}) as $cfg
  | ($cfg.ingress // []) as $ing
  # remove any existing catch-all entries in the middle
  | ($ing | map(select(.service != "http_status:404"))) as $clean
  # gather existing hostnames for dedupe (empty string for entries that have no hostname)
  
  # if new host already present, do not append duplicate; else append new route
  | ($clean | map(select(.hostname != $host))) as $filtered
      | ($filtered + [ { hostname: $host, service: $service, originRequest: { noTlsVerify: true, httpHostHeader: $host } } ]) as $merged
  # append exactly one catch-all
  | ($merged + [{ service: "http_status:404" }]) as $final_ing
  # construct new config object, preserve other keys in config (warp-routing, etc.)
  | ($cfg + { ingress: $final_ing }) as $newcfg
  | { config: $newcfg }
' "$BACKUP_RAW" > "$TO_PUT"

# optionally force version:
if [[ -n "${FORCE_VERSION:-}" ]]; then
  jq --argjson v "$FORCE_VERSION" '.config.version = $v' "$TO_PUT" > "${TO_PUT}.v" && mv "${TO_PUT}.v" "$TO_PUT"
fi

# ----------- 3) PUT apply ------------
echo -e "XXX\n56\nATUALIZANDO CONFIGURAÇÕES DO TUNNEL 1 \nXXX"
PUT_RESPONSE="$TMPDIR/put_response.$TIMESTAMP.json"
if ! primary_tunnel_cf_api PUT \
    "/accounts/${CLOUDFLARE_ACCOUNT_ID}/cfd_tunnel/${TUNNEL_ID}/configurations" \
    "$PUT_RESPONSE" "$TO_PUT" || ! primary_tunnel_api_success "$PUT_RESPONSE"; then
  CLOUDFLARE_VALIDATION_ERROR="A Cloudflare recusou a nova rota do Portainer. HTTP ${PRIMARY_TUNNEL_HTTP_CODE:-indisponível}: $(primary_tunnel_error_text "$PUT_RESPONSE")"
  exit 1
fi
sleep 3
# ----------- 4) verify ------------
echo -e "XXX\n57\nATUALIZANDO CONFIGURAÇÕES DO TUNNEL 2 \nXXX"
VERIFY_RESPONSE="$TMPDIR/verify_response.$TIMESTAMP.json"
if ! primary_tunnel_wait_for_route "$VERIFY_RESPONSE" "$dominio" "$NEW_SERVICE"; then
  exit 1
fi

echo -e "XXX\n57\nINICIANDO E VALIDANDO O CONECTOR CLOUDFLARED\nXXX"
primary_tunnel_deploy_connector || exit 1


sleep 3
# ----------- 5) criar o registro DNS CNAME ------------
#echo ""
echo -e "XXX\n57\nVERIFICANDO E CRIANDO REGISTRO DNS CNAME... \nXXX"
# Extrair apenas o subdomínio (parte antes do domínio principal)
SUBDOMINIO=${dominio%%.$DOMINIO_PRINCIPAL}

# Verificar registros A ou CNAME existentes
#echo "[5.2] Verificando se já existe algum registro A ou CNAME para $dominio..."
EXISTING_RECORDS=$(curl -s -X GET \
  "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records?name=${dominio}" \
  -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
  -H "Content-Type: application/json")
if ! printf '%s' "$EXISTING_RECORDS" | jq -e '.success == true and (.result | type == "array")' >/dev/null 2>&1; then
  CLOUDFLARE_VALIDATION_ERROR="Não foi possível inventariar os registros DNS existentes antes da alteração."
  exit 1
fi
SETUPMNO_PRIMARY_DNS_BACKUP="$TMPDIR/dns_backup.$TIMESTAMP.json"
printf '%s' "$EXISTING_RECORDS" >"$SETUPMNO_PRIMARY_DNS_BACKUP"
chmod 600 "$SETUPMNO_PRIMARY_DNS_BACKUP"

# Contar registros encontrados
COUNT=$(echo "$EXISTING_RECORDS" | jq '.result | length')

if [[ "$COUNT" -gt 0 ]]; then
  SETUPMNO_PRIMARY_DNS_MUTATED=true
  #echo ""S
  #echo "⚠️  Foram encontrados $COUNT registro(s) existentes para $dominio:"
 # echo "---------------------------------------------------------------"
  echo "$EXISTING_RECORDS" | jq -r '.result[] | "ID: \(.id)\tTipo: \(.type)\tConteúdo: \(.content)"'
  #echo "---------------------------------------------------------------"
  #read -p "Deseja APAGAR esses registros antes de criar o novo CNAME? (y/N): " DELETE_CONFIRM


    #echo ""
    #echo "[5.3] Removendo registros antigos..."
    while read -r REC_ID; do
      [[ -z "$REC_ID" ]] && continue
      DELETE_RESPONSE=$(curl -s -X DELETE \
        "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records/${REC_ID}" \
        -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
        -H "Content-Type: application/json")
      if ! printf '%s' "$DELETE_RESPONSE" | jq -e '.success == true' >/dev/null 2>&1; then
        CLOUDFLARE_VALIDATION_ERROR="A Cloudflare recusou a substituição de um registro DNS existente."
        exit 1
      fi
    done < <(printf '%s' "$EXISTING_RECORDS" | jq -r '.result[].id')


else
echo -e "XXX\n58\nVERIFICANDO...ISSO PODE DEMORAR UM POUCO \nXXX"
 # echo "✅ Nenhum registro existente encontrado. Prosseguindo com a criação do novo CNAME..."
fi

# Criar o novo registro CNAME
#secho "[5.4] Criando registro CNAME..."
DNS_RESPONSE=$(curl -s -X POST \
  "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records" \
  -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
  -H "Content-Type: application/json" \
  --data "{\"type\":\"CNAME\",\"name\":\"${dominio}\",\"content\":\"${TUNNEL_ID}.cfargotunnel.com\",\"ttl\":1,\"proxied\":true}")

if echo "$DNS_RESPONSE" | grep -q '"success":true'; then
SETUPMNO_PRIMARY_DNS_RECORD_ID=$(printf '%s' "$DNS_RESPONSE" | jq -r '.result.id // empty')
#  echo ""
echo -e "XXX\n59\n✅ REGISTRO DNS CNAME CRIADO COM SUCESSO! \nXXX"
 # echo "✅ REGISTRO DNS CNAME CRIADO COM SUCESSO!"
#  echo "→ Host: $dominio"
#  echo "→ Aponta para: ${TUNNEL_ID}.cfargotunnel.com"

else
 # echo ""
 echo -e "XXX\n59\n❌ ERRO AO CRIAR REGISTRO DNS CNAME \nXXX"
 # echo "❌ ERRO AO CRIAR REGISTRO DNS CNAME"
#  echo "Resposta: $DNS_RESPONSE"
  exit 1

fi

primary_tunnel_commit || {
  CLOUDFLARE_VALIDATION_ERROR="A infraestrutura foi criada, mas o estado final do Tunnel não pôde ser confirmado."
  exit 1
}
echo -e "XXX\n60\nCLOUDFLARE TUNNEL IMPLANTADO E VALIDADO\nXXX"
sleep 3

fi


#fim2 tradicional inicio

if [ "$INSTALL_CHOICE" = "TRADICIONAL" ] && [ "$criar_dns" = "0" ] ; then
DOMINIO_PRINCIPAL="$CLOUDFLARE_ZONE_NAME2"

# ----------- 5) criar o registro DNS CNAME ------------

echo -e "XXX\n55\nVERIFICANDO E CRIANDO REGISTRO DNS CNAME.. \nXXX"

# Extrair apenas o subdomínio (parte antes do domínio principal)
SUBDOMINIO=${dominio%%.$DOMINIO_PRINCIPAL}

# Verificar registros A ou CNAME existentes
echo -e "XXX\n56\nVERIFICANDO...ISSO PODE DEMORAR UM POUCO \nXXX"
EXISTING_RECORDS=$(curl -s -X GET \
  "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID2}/dns_records?name=${dominio}" \
  -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN2}" \
  -H "Content-Type: application/json")

# Contar registros encontrados
COUNT=$(echo "$EXISTING_RECORDS" | jq '.result | length')

if [[ "$COUNT" -gt 0 ]]; then



  echo "$EXISTING_RECORDS" | jq -r '.result[] | "ID: \(.id)\tTipo: \(.type)\tConteúdo: \(.content)"'




echo -e "XXX\n56\nRemovendo registros antigos... \nXXX"
    echo "$EXISTING_RECORDS" | jq -r '.result[].id' | while read -r REC_ID; do
      [[ -z "$REC_ID" ]] && continue
      curl -s -X DELETE \
        "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID2}/dns_records/${REC_ID}" \
        -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN2}" \
        -H "Content-Type: application/json" | jq '.'
done


else
  echo -e "XXX\n56\Criando registro CNAME (Isso pode demorar um pouco) \nXXX"
fi

# Criar o novo registro CNAME
  echo -e "XXX\n57\Criando registro CNAME... \nXXX"

CNAME_RESPONSE=$(curl -s -X POST \
  "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID2}/dns_records" \
  -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN2}" \
  -H "Content-Type: application/json" \
  --data '{"type":"CNAME","name":"'${dominio}'","content":"'${nome_servidor}'.'${DOMINIO_PRINCIPAL}'","ttl":1,"proxied":false}')

if echo "$CNAME_RESPONSE" | grep -q '"success":true'; then
  echo -e "XXX\n58\REGISTRO DNS CNAME CRIADO COM SUCESSO! \nXXX"
  echo "→ Host: $dominio"
  echo "→ Aponta para: ${nome_servidor}.${DOMINIO_PRINCIPAL}"
else
 echo -e "XXX\n58\ERRO AO CRIAR REGISTRO DNS CNAME \nXXX"
  echo "Resposta: $CNAME_RESPONSE"
  exit 1
fi


# Criar o novo registro A
  echo -e "XXX\n58\Criando registro A... \nXXX"
ip_servidor=$(curl -s --max-time 10 ipinfo.io/ip)
A_RESPONSE=$(curl -s -X POST \
  "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID2}/dns_records" \
  -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN2}" \
  -H "Content-Type: application/json" \
  --data '{"type":"A","name":"'${nome_servidor}'","content":"'${ip_servidor}'","ttl":1,"proxied":false}')

if echo "$A_RESPONSE" | grep -q '"success":true'; then
  echo -e "XXX\n58\✅ REGISTRO DNS A CRIADO COM SUCESSO! \nXXX"
  echo "→ Host: $nome_servidor"
  echo "→ Aponta para: $ip_servidor"
else

  echo -e "XXX\n58\❌ ERRO AO CRIAR REGISTRO DNS A \nXXX"
  echo "Resposta: $A_RESPONSE"
  exit 1
fi



fi
#fim2 tradicional fim


#
#  INSTALANDO O PORTAINER
#
if [[ ("$portainer_container" == "") ]]; then
cd
rm -r dados_portainer >/dev/null 2>&1
mkdir dados_portainer >/dev/null 2>&1
cd dados_portainer >/dev/null 2>&1
cat > dados_portainer <<EOL
[ PORTAINER ]

Dominio do portainer: $dominio

Usuario: $usuariopt

Senha: $senhapt
EOL

cd

# VERIFICAR TIPO DE INSTALAÇÃO
INSTALL_TYPE_FILE="/root/.cloudflared_config/installation_type"
if [ -f "$INSTALL_TYPE_FILE" ]; then
    INSTALL_TYPE=$(cat "$INSTALL_TYPE_FILE")
else
    INSTALL_TYPE="TRADICIONAL"
fi

cat > portainer.yaml << EOL

version: "3.7"

services:

  agent:
    image: portainer/agent:2.41.1-alpine
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - /var/lib/docker/volumes:/var/lib/docker/volumes

    networks:
      - agent_network
      - externa
    deploy:
      mode: global
      placement:
        constraints: [node.platform.os == linux]

  portainer:
    image: portainer/portainer-ce:2.41.1-alpine
    command: -H tcp://tasks.agent:9001 --tlsskipverify
    volumes:
      - portainer_data:/data
    networks:
      - agent_network
      - externa
    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints: [node.role == manager]
EOL
# Adicionar as labels apenas se for instalação tradicional
if [ "$INSTALL_TYPE" = "TRADICIONAL" ]; then
cat >> portainer.yaml << EOL
      labels:
        - "traefik.enable=true"
        - "traefik.docker.network=externa"
        - "traefik.http.routers.portainer.rule=Host(\`$dominio\`)"
        - "traefik.http.routers.portainer.entrypoints=websecure"
        - "traefik.http.routers.portainer.priority=1"
        - "traefik.http.routers.portainer.tls.certresolver=letsencryptresolver"
        - "traefik.http.routers.portainer.service=portainer"
        - "traefik.http.services.portainer.loadbalancer.server.port=9000"
EOL
fi
cat >> portainer.yaml << EOL

networks:
  externa:
    external: true
  agent_network:
    external: true

volumes:
  portainer_data:
    external: true
    name: portainer_data


EOL

docker stack deploy --prune --resolve-image always -c portainer.yaml portainer >/dev/null 2>&1
## espera Portainer rodar
max_wait_time=300  #ajuste do tempo máximo de espera
wait_interval=60
elapsed_time=0

while [ $elapsed_time -lt $max_wait_time ]; do
        CONTAINER_ID=$(docker ps --filter "name=portainer_portainer" --format "{{.ID}}" | head -n1)
        if [ -n "$CONTAINER_ID" ]; then
                break
        fi
        sleep $wait_interval
        elapsed_time=$((elapsed_time + wait_interval))
done

if [ -z "$CONTAINER_ID" ]; then
        echo "O container no foi encontrado após $max_wait_time segundos."
        exit 1
fi

# No modo TRADICIONAL, após o container real do Portainer estar em execução,
# força a recriação dos serviços Portainer e Traefik. Isso garante que o
# Traefik releia o serviço/labels do Portainer e reinicie o ciclo do HTTPS/ACME.
if [[ "$INSTALL_CHOICE" = "TRADICIONAL" ]]; then
    echo -e "XXX\n62\nPORTAINER ATIVO - REINICIANDO PORTAINER E TRAEFIK \nXXX"

    if ! docker service update --force portainer_portainer >/dev/null 2>&1; then
        echo -e "XXX\n62\nERRO AO REINICIAR O SERVIÇO PORTAINER \nXXX"
        exit 1
    fi

    if ! docker service update --force traefik_traefik >/dev/null 2>&1; then
        echo -e "XXX\n62\nERRO AO REINICIAR O SERVIÇO TRAEFIK \nXXX"
        exit 1
    fi

    # Dá tempo para os dois serviços recriarem as tasks antes da checagem HTTPS.
    sleep 8
fi


## VERIFICAÇÃO ESPECÍFICA PARA CLOUDFLARE TUNNEL
if [[ "$INSTALL_CHOICE" = "CLOUDFLARE_TUNNEL" ]]; then
    echo -e "XXX\n63\nAGUARDANDO CLOUDFLARE TUNNEL FICAR ATIVO\nXXX"

    # Verificação mais robusta do estado dos serviços
    echo "Verificando estado dos serviços Docker..."
    docker service ls | grep -E "(portainer|cloudflared|traefik)"

    # Aguarda um pouco mais para o tunnel estabilizar
    sleep 8

    echo "Verificando se o Cloudflare Tunnel está funcionando..."

    # Verifica se o serviço cloudflared está rodando
    if docker service ls | grep -q "cloudflared"; then
        echo -e "XXX\n64\nCLOUDFLARE TUNNEL ATIVO - VERIFICANDO ACESSO\nXXX"
    else
        echo -e "XXX\n64\nAVISO: SERVIÇO CLOUDFLARED NÃO ENCONTRADO\nXXX"
        sleep 8
    fi


fi


## cria senha no portaoner

# Configurações
PORTAINER_URL="https://$dominio/api"

# Função para verificar se o Portainer está pronto

wait_for_portainer() {
    echo -e "XXX\n64\nAGUARDANDO PORTAINER INICIALIZAR \nXXX"

    local max_attempts=30
    local attempt=1

    while [ $attempt -le $max_attempts ]; do
        # Durante a emissão/propagação inicial do certificado ACME, o Traefik
        # pode apresentar temporariamente o certificado padrão. O -k evita que
        # essa etapa interrompa toda a instalação antes do Let's Encrypt concluir.
        STATUS=$(curl -sk --connect-timeout 10 --max-time 15 -o /dev/null -w "%{http_code}" "$PORTAINER_URL/status" || true)
        STATUS=${STATUS:-000}

        if [ "$STATUS" = "200" ]; then
            echo -e "XXX\n65\nPORTAINER INICIALIZADO COM SUCESSO \nXXX"
            break
        fi

        echo -e "XXX\n64\nTENTATIVA $attempt/$max_attempts - STATUS: $STATUS \nXXX"
        sleep 5
        attempt=$((attempt + 1))
    done

    if [ "$STATUS" != "200" ]; then
        echo -e "XXX\n65\nERRO: PORTAINER NÃO RESPONDEU APÓS $max_attempts TENTATIVAS \nXXX"
        return 1
    fi

    return 0
}
sleep 12
# Função para verificar se o usuário administrador já existe
check_admin_user() {
    echo -e "XXX\n66\nVERIFICANDO USUÁRIO ADMIN \nXXX"
    RESPONSE=$(curl -sk -o /dev/null -w "%{http_code}" -X GET "$PORTAINER_URL/users" || true)
    RESPONSE=${RESPONSE:-000}
    if [ "$RESPONSE" -eq 401 ]; then
        echo -e "XXX\n67\nUSUÁRIO ADMIN AINDA NÃO CONFIGURADO \nXXX"
        return 1
    elif [ "$RESPONSE" -eq 200 ]; then
        echo -e "XXX\n68\nUSUÁRIO ADMINISTRADOR JÁ CONFIGURADO \nXXX"
        return 0
    else
        echo -e "XXX\n68\nERRO AO VERIFICAR USUÁRIO ADMIN \nXXX"
        exit 1
    fi
}

# Função para criar o usuário admin
create_admin_user() {
    echo -e "XXX\n69\nCRIANDO USUÁRIO ADMIN NO PORTAINER... \nXXX"
    RESPONSE=$(curl -sk -X POST "$PORTAINER_URL/users/admin/init" \
        -H "Content-Type: application/json" \
        -d "{\"Username\": \"$usuariopt\", \"Password\": \"$senhapt\"}")

    # Verificar se a criação foi bem-sucedida
    if echo "$RESPONSE" | grep -q '"Username":"'"$usuariopt"'"'; then
        echo -e "XXX\n70\nUSUÁRIO ADMIN CRIADO COM SUCESSO \nXXX"
    else
    echo -e "XXX\n71\nERRO AO CRIAR USUÁRIO ADMIN \nXXX"
    fi
}

# Executar as funções. Não continue para as demais ferramentas se o
# Portainer realmente não estiver acessível após todas as tentativas.
if ! wait_for_portainer; then
    echo -e "XXX\n65\nERRO: PORTAINER INDISPONÍVEL. VERIFIQUE DNS, PORTAS 80/443 E LOGS DO TRAEFIK. \nXXX"
    exit 1
fi
if ! check_admin_user; then
    create_admin_user
fi



fi
sleep 3
echo -e "XXX\n72\nINSTALANDO TRAEFIK E PORTAINER 3/4 - CONCLUIDO \nXXX"
echo -e "XXX\n73\nINSTALANDO REDIS, POSTGRES E PGBOUNCER 4/4 \nXXX"

# FIM DE INSTALANDO O PORTAINER

#  INSTALANDO O POSTGRES - pgvector
#
if [[ ("$postgres_container" == "") ]]; then
cat > postgres.yaml << EOL

version: "3.7"

services:
  postgres:
    image: pgvector/pgvector:pg16
    environment:
      - POSTGRES_PASSWORD=$postgres_senha
    command: >
      postgres -c max_connections=1000
    networks:
      - interna
    ports:
      - 5432:5432
    volumes:
      - postgres_data:/var/lib/postgresql/data
    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
          - node.role == manager
          #- node.hostname == worker1
      resources:
       limits:
         cpus: "2"
         memory: 2048M

volumes:
  postgres_data:
    external: true
    name: postgres_data

networks:
  interna:
    external: true



EOL

docker stack deploy --prune --resolve-image always -c postgres.yaml postgres >/dev/null 2>&1
fi

# FIM DE INSTALANDO O POSTGRES

#  INSTALANDO O REDIS

if [[ ("$redis_container" == "") ]]; then
cat > redis.yaml << EOL

version: "3.7"

services:
  redis:
    image: redis:7.2.4
    command: [
        "redis-server",
        "--appendonly",
        "yes",
        "--port",
        "6379"
      ]
    volumes:
      - redis_data:/data
    networks:
      - interna
    deploy:
      placement:
        constraints:
          - node.role == manager
     # resources:
      #  limits:
        #  cpus: "0.5"
        #  memory: 1024M

volumes:
  redis_data:
    external: true
    name: redis_data

networks:
  interna:
    external: true


EOL

docker stack deploy --prune --resolve-image always -c redis.yaml redis >/dev/null 2>&1
fi

# FIM DE INSTALANDO O REDIS

#  INSTALANDO O PGBOUNCER
#
if [[ ("$pgbouncer_container" == "") ]]; then
    # Criar diretório de configuração
    mkdir -p /etc/pgbouncer

    # Criar pgbouncer.ini
    cat > /etc/pgbouncer/pgbouncer.ini << EOL

[databases]
* = host=postgres port=5432 user=postgres password=$postgres_senha

[pgbouncer]
listen_addr = *
listen_port = 6432
auth_type = md5
auth_file = /etc/pgbouncer/userlist.txt
admin_users = postgres,admin
pool_mode = transaction
max_client_conn = 1000
default_pool_size = 100
reserve_pool_size = 100
reserve_pool_timeout = 1
server_idle_timeout = 60
server_lifetime = 3600
server_connect_timeout = 5
query_timeout = 30
client_idle_timeout = 60
ignore_startup_parameters = extra_float_digits
log_connections = 1
log_disconnections = 1
log_pooler_errors = 1
stats_period = 60

EOL

    # Gerar userlist.txt com hash SCRAM-SHA-256
echo -n "$postgres_senhapostgres" | md5sum | awk '{print "\"postgres\" \"md5" substr($1,1,32) "\""}' > /etc/pgbouncer/userlist.txt

    # Garantir permissões corretas
    chown -R 70:70 /etc/pgbouncer
    chmod 644 /etc/pgbouncer/*
    chmod 600 /etc/pgbouncer/userlist.txt



cat > pgbouncer.yaml << EOL

version: "3.7"

services:
  pgbouncer:
    # Imagem do Serviço
    # https://hub.docker.com/r/edoburu/pgbouncer
    image: edoburu/pgbouncer:v1.23.1-p0
    networks:
      - interna
    # Configura a porta do Serviço para acesso externo
    #ports:
    #  - 6432:6432
    environment:
      - DB_USER=postgres
      - DB_PASSWORD=$postgres_senha
      - DB_HOST=postgres
      - POOL_MODE=transaction  # Modo obrigatório para Rails
      - AUTH_TYPE=scram-sha-256
      - DB_PORT=5432
      - ADMIN_USERS=postgres,admin
      - MAX_CLIENT_CONN=1000
      - DEFAULT_POOL_SIZE=100
      - RESERVE_POOL_SIZE=100
      - RESERVE_POOL_TIMEOUT=1
    volumes:
      - /etc/pgbouncer/pgbouncer.ini:/etc/pgbouncer/pgbouncer.ini:ro
      - /etc/pgbouncer/userlist.txt:/etc/pgbouncer/userlist.txt:ro

      # Bancos de dados que deve atuar (vazio para todos)
      #- DB_NAME=db1,db2
    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
          - node.role == manager # Rodar serviço no Manager
      resources:
        limits:
          cpus: "2"
          memory: 2048M

networks:
  interna:
    external: true


EOL

docker stack deploy --prune --resolve-image always -c pgbouncer.yaml pgbouncer >/dev/null 2>&1
fi

# FIM DE INSTALANDO O PGBOuNCER

#
# MENSAGEM DE INSTALADO + DADOS
#
sleep 5
echo -e "XXX\n76\nINSTALANDO REDIS, POSTGRES E PGBOUNCER 4/4 - CONCLUIDO \nXXX"
#}|whiptail --title "SETUP MNO - FERRAMENTAS ESSENCIAIS" --gauge "Aguarde a instalação dos ítens necessários" 6 60 0



clear



if command -v docker > /dev/null 2>&1; then

echo -e "XXX\n76\nAGUARDE: CHECANDO TODOS SERVIÇOS \nXXX"

# VERIFICA SERVIÇO TRAEFIK
sleep 1

echo -e "XXX\n75\nAGUARDE: CHECANDO TRAEFIK \nXXX"
while true; do
    # Verifica se o serviço traefik está ativo
    if docker service ls --filter "name=traefik" | grep "traefik"; then
        sleep 10
        break
    fi

    sleep 1
done

echo -e "XXX\n80\nAGUARDE: TRAEFIK OK \nXXX"
sleep 1

#######################################################################
# VERIFICA SERVIÇO PORTAINER
sleep 1
echo -e "XXX\n84\nAGUARDE: CHECANDO PORTAINER \nXXX"
while true; do
    # Verifica se o serviço portainer está ativo
    if docker service ls --filter "name=portainer" | grep "portainer"; then
        sleep 10
        break
    fi

    sleep 1
done
echo -e "XXX\n88\nAGUARDE: PORTAINER OK \nXXX"

sleep 1


# VERIFICA SERVIÇO POSTGRES
sleep 1
echo -e "XXX\n90\nAGUARDE: CHECANDO POSTGRES \nXXX"
while true; do
    # Verifica se o serviço postgres está ativo
    if docker service ls --filter "name=postgres" | grep "postgres"; then
        sleep 10
        break
    fi

    sleep 1
done
echo -e "XXX\n93\nAGUARDE: POSTGRES OK \nXXX"

sleep 1


# VERIFICA SERVIÇO REDIS

sleep 1
echo -e "XXX\n96\nAGUARDE: CHECANDO REDIS \nXXX"
while true; do
    # Verifica se o serviço redis está ativo
    if docker service ls --filter "name=redis" | grep "redis"; then
        sleep 10
        break
    fi

    sleep 1
done
echo -e "XXX\n97\nAGUARDE: REDIS OK \nXXX"

# VERIFICA SERVIÇO TRAEFIK
sleep 1

echo -e "XXX\n98\nAGUARDE: CHECANDO PGBOUNCER \nXXX"
while true; do
    # Verifica se o serviço traefik está ativo
    if docker service ls --filter "name=pgbouncer" | grep "pgbouncer"; then
        sleep 10
        break
    fi

    sleep 1
done

echo -e "XXX\n99\nAGUARDE: PGBOUNCER OK \nXXX"
sleep 1
echo -e "XXX\n100\nCONCLUÍDO: INICIANDO SETUP MNO \nXXX"

#######################################################################

else

    echo -e "XXX\n76\nERRO: Não foi possível iniciar o Docker \nXXX"
    sleep 5
    echo -e "XXX\n76\nERRO: formate a VPS e tente novamente \nXXX"
    sleep 5
    echo -e "XXX\n80\nERRO: Obrigatório o uso de VPS vazia \nXXX"
    sleep 10

    $SHELL

fi
}|whiptail --title "SETUP MNO - FERRAMENTAS ESSENCIAIS" --gauge "Aguarde a instalação dos ítens necessários" 6 60 0
INSTALL_GAUGE_STATUS=$?
set +o pipefail
if [ "$INSTALL_GAUGE_STATUS" -ne 0 ]; then
    whiptail --title "INSTALAÇÃO INTERROMPIDA COM SEGURANÇA" --msgbox \
        "Uma etapa obrigatória falhou e o rollback dos recursos automáticos foi executado.\n\nLog técnico: $PRIMARY_TUNNEL_LOG\n\nCorrija a causa indicada no log e execute setup-mno novamente." \
        15 82
    exit 1
fi

# O Control Center deve ser oferecido apenas na instalação tradicional e
# antes da mensagem final que solicita o reinício do servidor.

   # offer_control_center_installation


# Verificação final de DNS
if [ "$INSTALL_CHOICE" = "TRADICIONAL" ]; then
    ip_servidor=$(curl -s --max-time 10 ipinfo.io/ip)
    dns_ip=$(timeout 10 nslookup $dominio | grep "Address" | tail -n1 | awk '{print $2}')

    if [[ "$dns_ip" != "$ip_servidor" ]]; then
        whiptail --title "Mensagem" --msgbox "Não foi possivel acessar o dominio do Portainer ($dominio). A instalação foi cancelada. Por favor, verifique se os apontamentos DNS estão corretos e propagados! Pressione ENTER para sair. Digite setup-mno e enter sempre que quiser iniciar o instalador." 20 78
        exit 1
    else
    offer_control_center_installation
    exit 0
    fi
else
    # Para Cloudflare Tunnel, apenas verificar se o domínio resolve
    if ! nslookup "$dominio" >/dev/null 2>&1; then
        whiptail --title "Mensagem" --msgbox "Não foi possivel resolver o dominio do Portainer ($dominio). Verifique se o domínio está configurado no Cloudflare. Pressione ENTER para sair." 20 78
        exit 1
    else
    offer_control_center_installation
        exit 0
    fi
fi

# FIM DE MENSAGEM DE INSTALADO + DADOS

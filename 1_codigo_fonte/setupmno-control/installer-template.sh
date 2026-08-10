#!/usr/bin/bash
# SETUP MNO CONTROL CENTER — painel web oficial de deploys e monitoramento.
set -o pipefail
umask 077

CONTROL_VERSION="4.16.4"
CLOUDFLARE_CONNECT_TIMEOUT=10
CLOUDFLARE_MAX_TIME=30

if [ "${SETUPMNO_SHC_SMOKE_TEST:-0}" = "1" ]; then
    printf '%s\n' "setupmno-control-shc-ok"
    exit 0
fi

extract_control_bundle() {
    local archive="/root/SetupLowCodeMno/.control/control-source.tar.gz"
    local release="/root/SetupLowCodeMno/.control/release.json"
    local expected_sha expected_bytes actual_sha actual_bytes
    [ -f "$archive" ] && [ ! -L "$archive" ] && [ -f "$release" ] &&
    [ ! -L "$release" ] || return 1
    expected_sha=$(jq -r '.controlSourceSHA256 // empty' "$release")
    expected_bytes=$(jq -r '.controlSourceBytes // 0' "$release")
    actual_sha=$(sha256sum "$archive" | awk '{print $1}')
    actual_bytes=$(stat -c '%s' "$archive")
    [ -n "$expected_sha" ] && [ "$expected_sha" = "$actual_sha" ] &&
    [ "$expected_bytes" = "$actual_bytes" ] &&
    [ "$actual_bytes" -le $((2 * 1024 * 1024)) ] || return 1
    cat "$archive"
}

INSTALL_TYPE_FILE="/root/.cloudflared_config/installation_type"
[ -f "$INSTALL_TYPE_FILE" ] && [ ! -L "$INSTALL_TYPE_FILE" ] || {
    printf '%s\n' "Tipo de instalação do Portainer indisponível. Execute primeiro o dockerswarm." >&2
    exit 1
}
INSTALL_TYPE=$(cat "$INSTALL_TYPE_FILE")
case "$INSTALL_TYPE" in
    CLOUDFLARE_TUNNEL|TRADICIONAL) ;;
    *)
        printf '%s\n' "Tipo de instalação do Portainer inválido." >&2
        exit 1
        ;;
esac
REQUESTED_INSTALL_TYPE="${SETUPMNO_INSTALLATION_TYPE:-}"
if [ -n "$REQUESTED_INSTALL_TYPE" ]; then
    case "$REQUESTED_INSTALL_TYPE" in
        CLOUDFLARE_TUNNEL|TRADICIONAL) ;;
        *)
            printf '%s\n' "Tipo de instalação recebido do Setup MNO é inválido." >&2
            exit 1
            ;;
    esac
    [ "$REQUESTED_INSTALL_TYPE" = "$INSTALL_TYPE" ] || {
        printf '%s\n' "Tipo recebido diverge do tipo persistido para o Portainer." >&2
        exit 1
    }
fi

CONTROL_ENVIRONMENT_FILE="/root/SetupLowCodeMno/.control/environment.json"
[ -f "$CONTROL_ENVIRONMENT_FILE" ] && [ ! -L "$CONTROL_ENVIRONMENT_FILE" ] || {
    printf '%s\n' "Estado de plano do Control Center indisponível." >&2
    exit 1
}
CONTROL_PLAN=$(jq -er \
    'select(.schemaVersion == 1) | .plan | select(. == "pro" or . == "free" or . == "free1" or . == "free2")' \
    "$CONTROL_ENVIRONMENT_FILE") || {
    printf '%s\n' "Estado de plano do Control Center inválido." >&2
    exit 1
}
if [ "$INSTALL_TYPE" = "CLOUDFLARE_TUNNEL" ]; then
    CREDENTIALS_FILE="/root/.cloudflared_config/cloudflare_credentials"
else
    CREDENTIALS_FILE="/root/.tradicional_config/tradicional_credentials"
fi
[ -f "$CREDENTIALS_FILE" ] && source "$CREDENTIALS_FILE"
if [ "$INSTALL_TYPE" = "TRADICIONAL" ]; then
    case "${criar_dns:-}" in
        0|1) ;;
        *)
            printf '%s\n' "Opção de DNS do Portainer indisponível. Execute novamente o dockerswarm." >&2
            exit 1
            ;;
    esac
fi

msg() {
    # As funções de coleta são chamadas por substituição de comando. Direcionar
    # a interface para stderr mantém o Whiptail visível no terminal/ttyd.
    whiptail --title "SETUP MNO CONTROL CENTER" --msgbox "$1" 14 78 1>&2
}

load_cloudflare_mfa_helper() {
    local helper
    declare -F prepare_cloudflare_mfa_token >/dev/null && return 0
    helper=$(mktemp) || return 1
    chmod 0700 "$helper"
    if ! extract_control_bundle | tar -xzOf - cloudflare-mfa.sh >"$helper"; then
        rm -f "$helper"
        return 1
    fi
    . "$helper"
    rm -f "$helper"
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

show_cloudflare_access_guide() {
    local team_hint="${access_team_name:-SEU-TIME}"
    whiptail --title "GUIA RÁPIDO — CLOUDFLARE ACCESS" --msgbox \
        "O MFA é opcional; o modo original permanece compatível com versões antigas.\n\nATIVAÇÃO AUTOMÁTICA\n1. O Setup valida as 5 permissões do token.\n2. Habilita TOTP, login por código, App Launcher e política do e-mail.\n3. Cria a proteção Access com cookie Lax.\n4. Você abre https://${team_hint}.cloudflareaccess.com/AddMfaDevice e lê o QR Code em Authenticator application.\n\nPERMISSÕES DO TOKEN\n• Configurações da conta > Editar\n• Cloudflare Tunnel > Editar\n• DNS > Editar\n• Access: Apps and Policies > Editar\n• Access: Organizations, Identity Providers, and Groups > Editar\n\nO assistente permite validar o token atual ou substituir o token armazenado sem alterar Account ID, Zone ID ou Tunnel." \
        24 94 1>&2
}

choose_cloudflare_access_security() {
    local choice status
    while true; do
        choice=$(whiptail --title "SEGURANÇA DO ACESSO REMOTO" --default-item "MFA" --menu \
            "Escolha como o Control Center será publicado. O modo original mantém os mesmos acessos das versões anteriores; o MFA adiciona Cloudflare Access e um segundo fator:" \
            20 94 4 \
            "MFA" "Access + código do aplicativo autenticador (RECOMENDADO)" \
            "SEM_MFA" "Modo original: Tunnel direto, login local e Terminal Remoto" \
            "INSTRUCOES" "Ver o passo a passo no Cloudflare antes de continuar" \
            3>&1 1>&2 2>&3)
        status=$?
        [ "$status" -ne 0 ] && return 130
        case "$choice" in
            MFA)
                access_mfa_enabled="true"
                return 0
                ;;
            SEM_MFA)
                access_mfa_enabled="false"
                return 0
                ;;
            INSTRUCOES)
                show_cloudflare_access_guide
                ;;
        esac
    done
}

ask_required() {
    local prompt="$1" value status
    while true; do
        value=$(whiptail --title "SETUP MNO CONTROL CENTER" --inputbox "$prompt" 12 78 3>&1 1>&2 2>&3)
        status=$?
        [ "$status" -ne 0 ] && return 130
        [ -n "$value" ] && {
            printf '%s' "$value"
            return
        }
        msg "Este campo é obrigatório."
    done
}

collect_cloudflare_access_email() {
    local step_label="$1" email status
    while true; do
        if ! email=$(ask_required \
            "$step_label — E-mail autorizado no Cloudflare Access:\n\nUse um endereço REAL que você controla e que consiga usar em um método de login do Zero Trust. O instalador criará a permissão automaticamente; ele não cria a conta de e-mail."); then
            return 130
        fi
        email=$(printf '%s' "$email" | tr '[:upper:]' '[:lower:]')
        if [[ "$email" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]] &&
           [ "${#email}" -le 254 ]; then
            printf '%s' "$email"
            return 0
        else
            msg "Informe um endereço de e-mail válido. Nenhuma política foi criada."
        fi
    done
}

build_cloudflare_access_payload() {
    local output_file="$1" app_name="$2" domain="$3" email="$4" mfa_enabled="$5"
    jq -n \
        --arg name "$app_name" \
        --arg domain "$domain" \
        --arg email "$email" \
        --argjson mfa "$mfa_enabled" '
        {
          name:$name,
          type:"self_hosted",
          domain:$domain,
          destinations:[{type:"public",uri:$domain}],
          session_duration:"8h",
          app_launcher_visible:false,
          allow_iframe:false,
          allow_authenticate_via_warp:false,
          skip_interstitial:false,
          same_site_cookie_attribute:"lax",
          options_preflight_bypass:false,
          mfa_config:(if $mfa then {
            mfa_disabled:false,
            session_duration:"8h",
            allowed_authenticators:["totp"]
          } else {mfa_disabled:true} end),
          policies:[{
            name:(if $mfa then
              "Setup MNO - identidade autorizada com MFA"
            else "Setup MNO - identidade autorizada sem MFA extra" end),
            decision:"allow",
            precedence:1,
            include:[{email:{email:$email}}],
            exclude:[],
            require:[],
            mfa_config:(if $mfa then {
              mfa_disabled:false,
              session_duration:"8h",
              allowed_authenticators:["totp"]
            } else {mfa_disabled:true} end)
          }]
        }
    ' >"$output_file"
}

build_control_tunnel_route_payload() {
    local input_file="$1" output_file="$2" host="$3" service="$4"
    local require_access="$5" team="$6" aud="$7"
    jq --arg host "$host" --arg service "$service" --arg team "$team" --arg aud "$aud" \
        --argjson requireAccess "$require_access" '
        (.result.config // {}) as $cfg
        | ($cfg.ingress // [])
        | map(select(.service != "http_status:404" and .hostname != $host))
        + [{hostname:$host,service:$service,originRequest:
             (if $requireAccess then {
                noTlsVerify:true,
                httpHostHeader:$host,
                access:{required:true,teamName:$team,audTag:[$aud]}
              } else {
                noTlsVerify:true,
                httpHostHeader:$host
              } end)},
           {service:"http_status:404"}]
        | {config:($cfg + {ingress:.})}
    ' "$input_file" >"$output_file"
}

control_center_installed() {
    command -v docker >/dev/null 2>&1 || return 1
    docker service ls --format '{{.Name}}' 2>/dev/null |
        grep -Eq '^mnoctrl[[:alnum:]]+-(web|agent|terminal|assistant)_'
}

control_service_env_value() {
    local service="$1" key="$2"
    docker service inspect --format '{{range .Spec.TaskTemplate.ContainerSpec.Env}}{{println .}}{{end}}' \
        "$service" 2>/dev/null | sed -n "s/^${key}=//p" | head -n1
}

rollback_existing_access_migration() {
    local state_file="$1" log_file="$2" web_service app_id original_tunnel onboarding_state delete_response
    local route_restored="true" app_removed="true"
    [ -s "$state_file" ] || return 0
    [ "$(jq -r '.active // false' "$state_file" 2>/dev/null)" = "true" ] || return 0
    web_service=$(jq -r '.webService // empty' "$state_file")
    app_id=$(jq -r '.appId // empty' "$state_file")
    original_tunnel=$(jq -r '.originalTunnel // empty' "$state_file")
    onboarding_state=$(jq -r '.onboardingState // empty' "$state_file")
    if [[ "$web_service" =~ ^mnoctrl[[:alnum:]]+-web_mnoctrl[[:alnum:]]+-web$ ]]; then
        docker service update --detach=true \
            --env-rm ACCESS_JWT_REQUIRED \
            --env-rm ACCESS_TEAM_DOMAIN \
            --env-rm ACCESS_POLICY_AUD \
            --env-rm ACCESS_ALLOWED_EMAIL \
            --env-rm ACCESS_MFA_REQUIRED \
            "$web_service" >>"$log_file" 2>&1 || true
    fi
    if [ -s "$original_tunnel" ]; then
        if ! curl -sS \
            --connect-timeout "$CLOUDFLARE_CONNECT_TIMEOUT" \
            --max-time "$CLOUDFLARE_MAX_TIME" \
            -X PUT \
            "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/cfd_tunnel/$TUNNEL_ID/configurations" \
            -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
            -H "Content-Type: application/json" \
            --data-binary @"$original_tunnel" >>"$log_file" 2>&1; then
            route_restored="false"
        fi
    fi
    if [ "$route_restored" = "true" ] && [[ "$app_id" =~ ^[A-Fa-f0-9-]{32,36}$ ]]; then
        delete_response="${state_file}.app-delete"
        if ! curl -sS \
            --connect-timeout "$CLOUDFLARE_CONNECT_TIMEOUT" \
            --max-time "$CLOUDFLARE_MAX_TIME" \
            -X DELETE \
            "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/access/apps/$app_id" \
            -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" >"$delete_response" 2>>"$log_file" ||
           [ "$(jq -r '.success // false' "$delete_response" 2>/dev/null)" != "true" ]; then
            app_removed="false"
        fi
    fi
    if [ "$route_restored" = "true" ] && [ "$app_removed" = "true" ] && [ -s "$onboarding_state" ]; then
        load_cloudflare_mfa_helper &&
            rollback_cloudflare_mfa_onboarding "$onboarding_state" "$log_file" || true
    fi
}

prepare_existing_access_migration() {
    local web_service="$1" work_dir="$2" log_file="$3" state_file="$4"
    local activation_mode="${5:-preserve}"
    local email status tunnel_raw organization_file applications_file hostname service_target onboarding_state
    local auth_domain team_name payload response app_id aud tunnel_payload tunnel_response original_tunnel access_error
    local access_required access_team access_aud access_email access_mfa
    local access_mfa_enabled="true"
    jq -n '{active:false}' >"$state_file" || return 1
    [ "$INSTALL_TYPE" = "CLOUDFLARE_TUNNEL" ] || return 0
    access_required=$(control_service_env_value "$web_service" ACCESS_JWT_REQUIRED)
    access_team=$(control_service_env_value "$web_service" ACCESS_TEAM_DOMAIN)
    access_aud=$(control_service_env_value "$web_service" ACCESS_POLICY_AUD)
    access_email=$(control_service_env_value "$web_service" ACCESS_ALLOWED_EMAIL)
    access_mfa=$(control_service_env_value "$web_service" ACCESS_MFA_REQUIRED)
    if [ "$access_required" = "true" ]; then
        if [ -z "$access_team" ] || [ -z "$access_aud" ] || [ -z "$access_email" ]; then
            msg "A instalação possui metadados Cloudflare Access parciais ou inconsistentes. Por segurança, nada foi alterado. Revise as variáveis ACCESS_* do serviço web antes de atualizar."
            return 1
        fi
        if [ "$activation_mode" = "preserve" ] && [ "$access_mfa" = "false" ]; then
            restore_existing_access_original_mode "$web_service" "$work_dir" "$log_file"
            return $?
        fi
        return 0
    fi
    if [ -n "$access_team" ] || [ -n "$access_aud" ] || [ -n "$access_email" ] ||
       { [ -n "$access_required" ] && [ "$access_required" != "false" ]; }; then
        msg "A instalação possui metadados Cloudflare Access parciais ou inconsistentes. Por segurança, nada foi alterado. Revise as variáveis ACCESS_* do serviço web antes de atualizar."
        return 1
    fi
    [ "$activation_mode" = "activate-mfa" ] || return 0

    whiptail --title "ATIVAR MFA NO CONTROL CENTER" --msgbox \
        "O Control Center está no modo original, sem Cloudflare Access.\n\nO Setup MNO validará o token, preparará automaticamente o login por e-mail, o aplicativo autenticador e o App Launcher, criará uma aplicação exclusiva e exigirá MFA. Se você cancelar, o acesso atual será preservado." \
        17 88 1>&2
    load_cloudflare_mfa_helper || {
        msg "O assistente autenticado de MFA não pôde ser carregado. Atualize o Setup MNO e tente novamente."
        return 1
    }
    prepare_cloudflare_mfa_token "$work_dir" "$log_file"
    status=$?
    [ "$status" -eq 0 ] || return "$status"
    email=$(collect_cloudflare_access_email "IDENTIDADE DO MFA") || return 130

    tunnel_raw="$work_dir/access-migration-tunnel.json"
    organization_file="$work_dir/access-migration-organization.json"
    applications_file="$work_dir/access-migration-applications.json"
    if ! curl -sS --connect-timeout "$CLOUDFLARE_CONNECT_TIMEOUT" --max-time "$CLOUDFLARE_MAX_TIME" \
            -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
            "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/cfd_tunnel/$TUNNEL_ID/configurations" \
            >"$tunnel_raw" 2>>"$log_file" ||
           ! curl -sS --connect-timeout "$CLOUDFLARE_CONNECT_TIMEOUT" --max-time "$CLOUDFLARE_MAX_TIME" \
            -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
            "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/access/organizations" \
            >"$organization_file" 2>>"$log_file" ||
           ! curl -sS --connect-timeout "$CLOUDFLARE_CONNECT_TIMEOUT" --max-time "$CLOUDFLARE_MAX_TIME" \
            -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
            "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/access/apps?per_page=100" \
            >"$applications_file" 2>>"$log_file"; then
        msg "A migração não conseguiu consultar Tunnel, organização e aplicativos Access. A instalação atual foi preservada."
        return 1
    fi
    if [ "$(jq -r '.success // false' "$tunnel_raw")" != "true" ] ||
           [ "$(jq -r '.success // false' "$organization_file")" != "true" ] ||
           [ "$(jq -r '.success // false' "$applications_file")" != "true" ]; then
        msg "A Cloudflare recusou a migração. Verifique as cinco permissões apresentadas pelo assistente. A instalação atual foi preservada."
        return 1
    fi
    auth_domain=$(jq -r '.result.auth_domain // empty' "$organization_file")
    if [[ ! "$auth_domain" =~ ^[A-Za-z0-9-]+\.cloudflareaccess\.com$ ]]; then
        msg "O Zero Trust ainda não possui um domínio de autenticação válido. Crie o nome da equipe uma única vez no painel Cloudflare e tente novamente. A instalação atual foi preservada."
        return 1
    fi
    service_target="http://${web_service}:8080"
    hostname=$(jq -r --arg service "$service_target" \
        '[.result.config.ingress[]? | select(.service == $service) | .hostname][0] // empty' "$tunnel_raw")
    if [[ ! "$hostname" =~ ^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$ ]] || [[ "$hostname" != *.* ]]; then
        msg "A rota Cloudflare Tunnel do painel existente não foi identificada com segurança. A instalação atual foi preservada."
        return 1
    fi
    if jq -e --arg host "$hostname" '
        any(.result[]?; .domain == $host or any(.destinations[]?; .type == "public" and .uri == $host))
    ' "$applications_file" >/dev/null 2>&1; then
        msg "Já existe um aplicativo Access para $hostname. Por segurança, a migração não substituirá políticas externas. Revise-o no Zero Trust ou solicite uma migração assistida."
        return 1
    fi
    if ! whiptail --title "CONFIRMAR ATIVAÇÃO DO MFA" --yesno \
        "Domínio protegido: $hostname\nE-mail autorizado: $email\n\nA partir daqui o Setup automatizará TOTP, login por e-mail, App Launcher e a política do Control Center. O modo original continuará ativo até tudo ser concluído; em caso de falha, as mudanças serão revertidas.\n\nDeseja ativar o MFA agora?" \
        18 92 1>&2; then
        return 130
    fi

    onboarding_state="$work_dir/access-migration-onboarding.json"
    ensure_cloudflare_mfa_onboarding "$work_dir" "$email" "$log_file" "$onboarding_state" || return 1

    team_name="${auth_domain%.cloudflareaccess.com}"
    payload="$work_dir/access-migration-payload.json"
    response="$work_dir/access-migration-response.json"
    build_cloudflare_access_payload "$payload" \
        "Setup MNO Control Center - $hostname" "$hostname" "$email" \
        true 2>>"$log_file" || {
        rollback_cloudflare_mfa_onboarding "$onboarding_state" "$log_file"
        return 1
    }
    if ! curl -sS --connect-timeout "$CLOUDFLARE_CONNECT_TIMEOUT" --max-time "$CLOUDFLARE_MAX_TIME" \
        -X POST "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/access/apps" \
        -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" -H "Content-Type: application/json" \
        --data-binary @"$payload" >"$response" 2>>"$log_file" ||
       [ "$(jq -r '.success // false' "$response")" != "true" ]; then
        rollback_cloudflare_mfa_onboarding "$onboarding_state" "$log_file"
        access_error=$(cf_mfa_error "$response")
        msg "A Cloudflare recusou a criação da proteção Access escolhida. ${access_error:+Detalhe: $access_error }A instalação atual foi preservada."
        return 1
    fi
    app_id=$(jq -r '.result.id // empty' "$response")
    aud=$(jq -r '.result.aud // empty' "$response")
    if [[ ! "$app_id" =~ ^[A-Fa-f0-9-]{32,36}$ ]] || [ "${#aud}" -lt 16 ] || [ "${#aud}" -gt 128 ]; then
        if [[ "$app_id" =~ ^[A-Fa-f0-9-]{32,36}$ ]]; then
            jq -n --arg web "$web_service" --arg app "$app_id" --arg onboarding "$onboarding_state" \
                '{active:true,webService:$web,appId:$app,originalTunnel:"",onboardingState:$onboarding}' >"$state_file" &&
                rollback_existing_access_migration "$state_file" "$log_file"
        fi
        return 1
    fi

    jq -n --arg web "$web_service" --arg app "$app_id" --arg onboarding "$onboarding_state" \
        '{active:true,webService:$web,appId:$app,originalTunnel:"",onboardingState:$onboarding}' >"$state_file" || return 1

    original_tunnel="$work_dir/access-migration-tunnel-original.json"
    tunnel_payload="$work_dir/access-migration-tunnel-payload.json"
    tunnel_response="$work_dir/access-migration-tunnel-response.json"
    if ! jq '{config:.result.config}' "$tunnel_raw" >"$original_tunnel" 2>>"$log_file"; then
        rollback_existing_access_migration "$state_file" "$log_file"
        return 1
    fi
    jq -n --arg web "$web_service" --arg app "$app_id" --arg original "$original_tunnel" \
        --arg onboarding "$onboarding_state" \
        '{active:true,webService:$web,appId:$app,originalTunnel:$original,onboardingState:$onboarding}' >"$state_file" || {
        rollback_existing_access_migration "$state_file" "$log_file"
        return 1
    }
    if ! jq --arg host "$hostname" --arg team "$team_name" --arg aud "$aud" '
        (.result.config // {}) as $cfg
        | {config:($cfg + {ingress:[($cfg.ingress // [])[] |
            if .hostname == $host then
              .originRequest = ((.originRequest // {}) + {access:{required:true,teamName:$team,audTag:[$aud]}})
            else . end]})}
    ' "$tunnel_raw" >"$tunnel_payload" 2>>"$log_file"; then
        rollback_existing_access_migration "$state_file" "$log_file"
        return 1
    fi
    if ! curl -sS --connect-timeout "$CLOUDFLARE_CONNECT_TIMEOUT" --max-time "$CLOUDFLARE_MAX_TIME" \
        -X PUT "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/cfd_tunnel/$TUNNEL_ID/configurations" \
        -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" -H "Content-Type: application/json" \
        --data-binary @"$tunnel_payload" >"$tunnel_response" 2>>"$log_file" ||
       [ "$(jq -r '.success // false' "$tunnel_response")" != "true" ]; then
        rollback_existing_access_migration "$state_file" "$log_file"
        msg "A rota existente recusou a proteção Access. A instalação atual foi preservada."
        return 1
    fi

    if ! docker service update --detach=true \
        --env-add ACCESS_JWT_REQUIRED=true \
        --env-add "ACCESS_TEAM_DOMAIN=https://$auth_domain" \
        --env-add "ACCESS_POLICY_AUD=$aud" \
        --env-add "ACCESS_ALLOWED_EMAIL=$email" \
        --env-add "ACCESS_MFA_REQUIRED=true" \
        "$web_service" >>"$log_file" 2>&1; then
        rollback_existing_access_migration "$state_file" "$log_file"
        msg "O serviço existente recusou os metadados Access. Rota e política anteriores foram restauradas."
        return 1
    fi
    return 0
}

restore_existing_access_original_mode() {
    local web_service="$1" work_dir="$2" log_file="$3"
    local team_domain aud email applications_file tunnel_file app_count app_id hostname service_target
    local original_tunnel tunnel_payload tunnel_response delete_response previous_mfa

    team_domain=$(control_service_env_value "$web_service" ACCESS_TEAM_DOMAIN)
    aud=$(control_service_env_value "$web_service" ACCESS_POLICY_AUD)
    email=$(control_service_env_value "$web_service" ACCESS_ALLOWED_EMAIL)
    previous_mfa=$(control_service_env_value "$web_service" ACCESS_MFA_REQUIRED)
    case "$previous_mfa" in true|false) ;; *) previous_mfa="false" ;; esac
    [[ "$team_domain" =~ ^https://[A-Za-z0-9-]+\.cloudflareaccess\.com$ ]] &&
    [ "${#aud}" -ge 16 ] && [ "${#aud}" -le 128 ] &&
    [[ "$email" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]] || {
        msg "O modo sem MFA possui metadados incompletos. A instalação foi preservada para evitar alterar uma política externa."
        return 1
    }
    applications_file="$work_dir/original-mode-applications.json"
    tunnel_file="$work_dir/original-mode-tunnel.json"
    original_tunnel="$work_dir/original-mode-tunnel-original.json"
    tunnel_payload="$work_dir/original-mode-tunnel-payload.json"
    tunnel_response="$work_dir/original-mode-tunnel-response.json"
    delete_response="$work_dir/original-mode-delete-response.json"
    if ! curl -sS --connect-timeout "$CLOUDFLARE_CONNECT_TIMEOUT" --max-time "$CLOUDFLARE_MAX_TIME" \
        -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
        "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/access/apps?per_page=100" \
        >"$applications_file" 2>>"$log_file" ||
       ! curl -sS --connect-timeout "$CLOUDFLARE_CONNECT_TIMEOUT" --max-time "$CLOUDFLARE_MAX_TIME" \
        -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
        "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/cfd_tunnel/$TUNNEL_ID/configurations" \
        >"$tunnel_file" 2>>"$log_file" ||
       [ "$(jq -r '.success // false' "$applications_file")" != "true" ] ||
       [ "$(jq -r '.success // false' "$tunnel_file")" != "true" ]; then
        msg "Não foi possível restaurar o modo original porque a Cloudflare não retornou a aplicação e a rota atuais. Nenhuma alteração foi realizada."
        return 1
    fi
    app_count=$(jq -r --arg aud "$aud" '[.result[]? | select(.aud == $aud)] | length' "$applications_file")
    app_id=$(jq -r --arg aud "$aud" '[.result[]? | select(.aud == $aud)][0].id // empty' "$applications_file")
    if [ "$app_count" -ne 1 ] || [[ ! "$app_id" =~ ^[A-Fa-f0-9-]{32,36}$ ]]; then
        msg "A aplicação Access criada para o modo sem MFA não foi identificada de forma única. Nada foi removido."
        return 1
    fi
    service_target="http://${web_service}:8080"
    hostname=$(jq -r --arg service "$service_target" \
        '[.result.config.ingress[]? | select(.service == $service) | .hostname][0] // empty' "$tunnel_file")
    if [[ ! "$hostname" =~ ^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$ ]] ||
       ! jq -e --arg aud "$aud" --arg host "$hostname" '
          [.result[]? | select(.aud == $aud and
            (.domain == $host or any(.destinations[]?; .type == "public" and .uri == $host)))]
          | length == 1
       ' "$applications_file" >/dev/null 2>&1; then
        msg "A aplicação Access não corresponde de forma inequívoca à rota do Control Center. Nada foi removido."
        return 1
    fi
    jq '{config:.result.config}' "$tunnel_file" >"$original_tunnel" 2>>"$log_file" || return 1
    if ! jq --arg host "$hostname" --arg service "$service_target" '
        (.result.config // {}) as $cfg
        | {config:($cfg + {ingress:[($cfg.ingress // [])[] |
            if .hostname == $host and .service == $service then
              del(.originRequest.access)
            else . end]})}
    ' "$tunnel_file" >"$tunnel_payload" 2>>"$log_file"; then
        return 1
    fi
    if ! curl -sS --connect-timeout "$CLOUDFLARE_CONNECT_TIMEOUT" --max-time "$CLOUDFLARE_MAX_TIME" \
        -X PUT \
        "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/cfd_tunnel/$TUNNEL_ID/configurations" \
        -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" -H "Content-Type: application/json" \
        --data-binary @"$tunnel_payload" >"$tunnel_response" 2>>"$log_file" ||
       [ "$(jq -r '.success // false' "$tunnel_response")" != "true" ]; then
        msg "A Cloudflare recusou a restauração da rota original. O acesso atual foi preservado."
        return 1
    fi
    if ! docker service update --detach=false \
        --env-rm ACCESS_JWT_REQUIRED \
        --env-rm ACCESS_TEAM_DOMAIN \
        --env-rm ACCESS_POLICY_AUD \
        --env-rm ACCESS_ALLOWED_EMAIL \
        --env-rm ACCESS_MFA_REQUIRED \
        --env-add ACCESS_JWT_REQUIRED=false \
        --env-add ACCESS_MFA_REQUIRED=false \
        "$web_service" >>"$log_file" 2>&1; then
        curl -sS --connect-timeout "$CLOUDFLARE_CONNECT_TIMEOUT" --max-time "$CLOUDFLARE_MAX_TIME" \
            -X PUT \
            "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/cfd_tunnel/$TUNNEL_ID/configurations" \
            -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" -H "Content-Type: application/json" \
            --data-binary @"$original_tunnel" >>"$log_file" 2>&1 || true
        msg "O serviço web recusou o modo original. A rota anterior foi restaurada."
        return 1
    fi
    if ! curl -sS --connect-timeout "$CLOUDFLARE_CONNECT_TIMEOUT" --max-time "$CLOUDFLARE_MAX_TIME" \
        -X DELETE \
        "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/access/apps/$app_id" \
        -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" >"$delete_response" 2>>"$log_file" ||
       [ "$(jq -r '.success // false' "$delete_response")" != "true" ]; then
        docker service update --detach=false \
            --env-rm ACCESS_JWT_REQUIRED --env-rm ACCESS_MFA_REQUIRED \
            --env-add ACCESS_JWT_REQUIRED=true \
            --env-add "ACCESS_TEAM_DOMAIN=$team_domain" \
            --env-add "ACCESS_POLICY_AUD=$aud" \
            --env-add "ACCESS_ALLOWED_EMAIL=$email" \
            --env-add "ACCESS_MFA_REQUIRED=$previous_mfa" \
            "$web_service" >>"$log_file" 2>&1 || true
        curl -sS --connect-timeout "$CLOUDFLARE_CONNECT_TIMEOUT" --max-time "$CLOUDFLARE_MAX_TIME" \
            -X PUT \
            "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/cfd_tunnel/$TUNNEL_ID/configurations" \
            -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" -H "Content-Type: application/json" \
            --data-binary @"$original_tunnel" >>"$log_file" 2>&1 || true
        msg "A aplicação Access não pôde ser removida. Serviço e rota anteriores foram restaurados."
        return 1
    fi
    load_cloudflare_mfa_helper &&
        remove_setupmno_launcher_policy "$work_dir" "$email" "$log_file" || true
    write_control_mfa_state false false false menu-disabled || {
        msg "O modo original foi restaurado, mas o registro persistente de MFA não pôde ser atualizado. Execute novamente o Setup MNO antes de outra atualização."
        return 1
    }
    return 0
}

reconcile_existing_control_center() {
    local upgrade_dir upgrade_log upgrade_error upgrade_state status detail noop
    local terminal_service terminal_image control_image plan finalizer_name
    local has_image_env has_plan_env
    local -a terminal_update_args
    local existing_web migration_state

    upgrade_dir=$(mktemp -d) || return 1
    upgrade_log="/tmp/setupmno-control-reconcile-${CONTROL_VERSION}.log"
    upgrade_error="$upgrade_dir/error.log"
    upgrade_state="$upgrade_dir/terminal-update.json"
    : >"$upgrade_log"
    : >"$upgrade_error"
    if ! extract_control_bundle 2>>"$upgrade_log" |
        tar -xzf - -C "$upgrade_dir" >>"$upgrade_log" 2>&1; then
        rm -rf -- "$upgrade_dir"
        msg "O pacote autenticado do Control Center não pôde ser extraído. A instalação existente foi preservada."
        return 1
    fi
    [ -s "$upgrade_dir/control-upgrade.sh" ] &&
    [ ! -L "$upgrade_dir/control-upgrade.sh" ] || {
        rm -rf -- "$upgrade_dir"
        msg "O reconciliador interno não foi encontrado no pacote desta versão."
        return 1
    }

    existing_web=$(docker service ls --format '{{.Name}}' 2>>"$upgrade_log" |
        grep -E '^mnoctrl[[:alnum:]]+-web_mnoctrl[[:alnum:]]+-web$' | head -n1)
    [[ "$existing_web" =~ ^mnoctrl[[:alnum:]]+-web_mnoctrl[[:alnum:]]+-web$ ]] || {
        rm -rf -- "$upgrade_dir"
        msg "O serviço web existente não pôde ser identificado com segurança. A instalação foi preservada."
        return 1
    }
    migration_state="$upgrade_dir/access-migration-state.json"
    if ! prepare_existing_access_migration "$existing_web" "$upgrade_dir" "$upgrade_log" "$migration_state"; then
        rm -rf -- "$upgrade_dir"
        return 1
    fi

    /usr/bin/bash "$upgrade_dir/control-upgrade.sh" "$upgrade_dir" \
        "$CONTROL_VERSION" "$upgrade_log" "$upgrade_error" "$upgrade_state" |
        whiptail --title "SINCRONIZANDO CONTROL CENTER" --gauge \
            "Preservando stacks, secrets, domínio e Portainer..." 8 84 0
    status=${PIPESTATUS[0]}
    if [ "$status" -ne 0 ] || [ ! -s "$upgrade_state" ]; then
        detail=$(cat "$upgrade_error" 2>/dev/null)
        [ -n "$detail" ] || detail=$(tail -n 20 "$upgrade_log" 2>/dev/null)
        rollback_existing_access_migration "$migration_state" "$upgrade_log"
        rm -rf -- "$upgrade_dir"
        whiptail --title "ERRO NA SINCRONIZAÇÃO DO CONTROL CENTER" --msgbox \
            "A sincronização foi interrompida e os serviços alterados foram revertidos.\n\n$detail\n\nLog: $upgrade_log" \
            24 94
        return "${status:-1}"
    fi

    noop=$(jq -r '.noop // false' "$upgrade_state")
    if [ "$noop" = "true" ]; then
        rm -rf -- "$upgrade_dir"
        return 0
    fi

    terminal_service=$(jq -er '.service' "$upgrade_state") || return 1
    terminal_image=$(jq -er '.image' "$upgrade_state") || return 1
    control_image=$(jq -er '.controlImage' "$upgrade_state") || return 1
    plan=$(jq -er '.plan' "$upgrade_state") || return 1
    has_image_env=$(jq -r '.hasImageEnv' "$upgrade_state")
    has_plan_env=$(jq -r '.hasPlanEnv' "$upgrade_state")
    [[ "$terminal_service" =~ ^mnoctrl[[:alnum:]]+-terminal_mnoctrl[[:alnum:]]+-terminal$ ]] || return 1
    [[ "$terminal_image" =~ ^mnoctrl[[:alnum:]]+-terminal:[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 1
    [[ "$control_image" =~ ^mnoctrl[[:alnum:]]+-app:[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 1
    [[ "$plan" =~ ^(pro|free|free1|free2)$ ]] || return 1

    terminal_update_args=(--image "$terminal_image")
    [ "$has_image_env" = "true" ] && terminal_update_args+=(--env-rm SETUPMNO_CONTROL_IMAGE)
    terminal_update_args+=(--env-add "SETUPMNO_CONTROL_IMAGE=$control_image")
    [ "$has_plan_env" = "true" ] && terminal_update_args+=(--env-rm SETUPMNO_CONTROL_PLAN)
    terminal_update_args+=(--env-add "SETUPMNO_CONTROL_PLAN=$plan" --force --detach=true "$terminal_service")
    finalizer_name="${terminal_service%%_*}-reconcile-finalizer"
    if ! docker run -d --rm --network none --name "$finalizer_name" \
        -v /var/run/docker.sock:/var/run/docker.sock \
        --entrypoint /usr/bin/bash "$terminal_image" \
        -c 'sleep 4; docker service update "$@"' _ \
        "${terminal_update_args[@]}" >>"$upgrade_log" 2>&1; then
        rm -rf -- "$upgrade_dir"
        msg "Painel e agente foram atualizados, mas o reinício final do Terminal Seguro não pôde ser agendado."
        return 1
    fi
    rm -rf -- "$upgrade_dir"
    return 0
}

build_existing_access_policy_payload() {
    local application_file="$1" output_file="$2" email="$3" enable_mfa="$4"
    jq --arg email "$email" --argjson enableMfa "$enable_mfa" '
        [.result.policies[]? |
          select(any(.include[]?; .email.email? == $email))] as $matches
        | if ($matches | length) != 1 then
            error("a política exata do Setup MNO não foi identificada")
          else
            $matches[0] as $policy
            | {
                name:$policy.name,
                decision:$policy.decision,
                precedence:($policy.precedence // 1),
                include:$policy.include,
                exclude:($policy.exclude // []),
                require:($policy.require // []),
                mfa_config:(if $enableMfa then {
                  mfa_disabled:false,
                  session_duration:"8h",
                  allowed_authenticators:["totp"]
                } else {mfa_disabled:true} end)
              }
          end
    ' "$application_file" >"$output_file"
}

configure_existing_access_mfa() {
    local work_dir log_file web_service service_count access_required access_mfa team_domain aud email
    local organization_file applications_file application_file policy_payload rollback_payload response_file
    local auth_domain app_count app_id policy_count policy_id current_mfa_disabled current_mfa_enabled
    local action rollback_response activation_state status onboarding_state

    if [ "$INSTALL_TYPE" != "CLOUDFLARE_TUNNEL" ]; then
        msg "O MFA independente desta opção pertence ao Cloudflare Access.\n\nEste Control Center usa acesso tradicional, portanto nenhuma alteração foi realizada."
        return 0
    fi
    if [ -z "${CLOUDFLARE_ACCOUNT_ID:-}" ] || [ -z "${CLOUDFLARE_API_TOKEN:-}" ]; then
        msg "As credenciais do Cloudflare não estão disponíveis. Execute novamente a configuração do ambiente para recuperar o token e tente outra vez."
        return 1
    fi

    service_count=$(docker service ls --format '{{.Name}}' 2>/dev/null |
        grep -Ec '^mnoctrl[[:alnum:]]+-web_mnoctrl[[:alnum:]]+-web$')
    [ "$service_count" -eq 1 ] || {
        msg "Não foi possível identificar com segurança um único serviço web do Control Center. Nenhuma política foi alterada."
        return 1
    }
    web_service=$(docker service ls --format '{{.Name}}' 2>/dev/null |
        grep -E '^mnoctrl[[:alnum:]]+-web_mnoctrl[[:alnum:]]+-web$')
    access_required=$(control_service_env_value "$web_service" ACCESS_JWT_REQUIRED)
    access_mfa=$(control_service_env_value "$web_service" ACCESS_MFA_REQUIRED)
    team_domain=$(control_service_env_value "$web_service" ACCESS_TEAM_DOMAIN)
    aud=$(control_service_env_value "$web_service" ACCESS_POLICY_AUD)
    email=$(control_service_env_value "$web_service" ACCESS_ALLOWED_EMAIL)
    if [ "$access_required" != "true" ]; then
        if [ -n "$team_domain" ] || [ -n "$aud" ] || [ -n "$email" ] ||
           { [ -n "$access_required" ] && [ "$access_required" != "false" ]; }; then
            msg "A instalação possui metadados Cloudflare Access parciais. Por segurança, nenhuma política foi alterada."
            return 1
        fi
        while true; do
            action=$(whiptail --title "CONFIGURAR MFA CONTROL CENTER" --default-item "ATIVAR" --menu \
                "O Control Center está no modo original. Escolha como deseja continuar:" \
                18 92 3 \
                "ATIVAR" "Configurar Cloudflare Access + MFA agora" \
                "INSTRUCOES" "Ver o passo a passo completo do Cloudflare" \
                "CANCELAR" "Manter o modo original e voltar ao menu" \
                3>&1 1>&2 2>&3) || return 0
            case "$action" in
                ATIVAR) break ;;
                INSTRUCOES) show_cloudflare_access_guide ;;
                CANCELAR) return 0 ;;
            esac
        done
        work_dir=$(mktemp -d) || return 1
        log_file="/tmp/setupmno-control-mfa-${CONTROL_VERSION}.log"
        activation_state="$work_dir/activation-state.json"
        : >"$log_file"
        prepare_existing_access_migration "$web_service" "$work_dir" "$log_file" \
            "$activation_state" activate-mfa
        status=$?
        if [ "$status" -eq 130 ]; then
            rm -rf -- "$work_dir"
            return 0
        fi
        if [ "$status" -ne 0 ]; then
            rm -rf -- "$work_dir"
            return "$status"
        fi
        team_domain=$(control_service_env_value "$web_service" ACCESS_TEAM_DOMAIN)
        email=$(control_service_env_value "$web_service" ACCESS_ALLOWED_EMAIL)
        write_control_mfa_state true true false menu-enabled || {
            msg "O MFA foi ativado, mas o estado persistente não pôde ser registrado. Execute novamente esta opção antes de atualizar o Setup MNO."
            return 1
        }
        rm -rf -- "$work_dir"
        msg "MFA ATIVADO COM SUCESSO!\n\nE-mail protegido: $email\n\nA Cloudflare foi preparada automaticamente. Próximo passo:\n1. Abra ${team_domain}/AddMfaDevice\n2. Entre com o mesmo e-mail\n3. Escolha Aplicativo autenticador e leia o QR Code\n4. Volte e abra o Control Center"
        return 0
    fi
    if [ "$access_required" != "true" ] ||
       [[ ! "$team_domain" =~ ^https://[A-Za-z0-9-]+\.cloudflareaccess\.com$ ]] ||
       [ "${#aud}" -lt 16 ] || [ "${#aud}" -gt 128 ] ||
       [[ ! "$email" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
        msg "A instalação não possui metadados Cloudflare Access completos e válidos. Por segurança, nenhuma política foi alterada."
        return 1
    fi

    if [ "$access_mfa" = "true" ]; then
        while true; do
            action=$(whiptail --title "CONFIGURAR MFA CONTROL CENTER" --default-item "CANCELAR" --menu \
                "O MFA está ATIVO para $email. Você pode mantê-lo, consultar as instruções ou voltar ao modo original das versões sem MFA:" \
                19 94 3 \
                "DESATIVAR" "Remover Access e restaurar Tunnel direto + login local" \
                "INSTRUCOES" "Ver o guia de MFA do Cloudflare" \
                "CANCELAR" "Manter o MFA ativo e voltar ao menu" \
                3>&1 1>&2 2>&3) || return 0
            case "$action" in
                INSTRUCOES) show_cloudflare_access_guide ;;
                CANCELAR) return 0 ;;
                DESATIVAR)
                    if ! whiptail --title "DESATIVAR MFA?" --yesno \
                        "O aplicativo Access exclusivo do Control Center será removido e o acesso voltará ao modo original: Cloudflare Tunnel direto, login local e Terminal Remoto.\n\nEm caso de falha, serviço e rota serão restaurados. Deseja continuar?" \
                        18 92 1>&2; then
                        return 0
                    fi
                    work_dir=$(mktemp -d) || return 1
                    log_file="/tmp/setupmno-control-mfa-${CONTROL_VERSION}.log"
                    : >"$log_file"
                    if restore_existing_access_original_mode "$web_service" "$work_dir" "$log_file"; then
                        rm -rf -- "$work_dir"
                        msg "MFA DESATIVADO COM SUCESSO!\n\nO Control Center voltou ao modo original com Tunnel direto, login local e Terminal Remoto. A opção de MFA continuará disponível no menu."
                        return 0
                    fi
                    rm -rf -- "$work_dir"
                    return 1
                    ;;
            esac
        done
    fi

    work_dir=$(mktemp -d) || return 1
    log_file="/tmp/setupmno-control-mfa-${CONTROL_VERSION}.log"
    organization_file="$work_dir/organization.json"
    applications_file="$work_dir/applications.json"
    application_file="$work_dir/application.json"
    policy_payload="$work_dir/policy-mfa.json"
    rollback_payload="$work_dir/policy-rollback.json"
    response_file="$work_dir/policy-response.json"
    onboarding_state="$work_dir/existing-access-onboarding.json"
    : >"$log_file"
    load_cloudflare_mfa_helper || {
        rm -rf -- "$work_dir"
        msg "O assistente autenticado de MFA não pôde ser carregado. Atualize o Setup MNO e tente novamente."
        return 1
    }
    prepare_cloudflare_mfa_token "$work_dir" "$log_file"
    status=$?
    if [ "$status" -ne 0 ]; then
        rm -rf -- "$work_dir"
        [ "$status" -eq 130 ] && return 0
        return "$status"
    fi
    if ! curl -sS --connect-timeout "$CLOUDFLARE_CONNECT_TIMEOUT" --max-time "$CLOUDFLARE_MAX_TIME" \
        -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
        "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/access/organizations" \
        >"$organization_file" 2>>"$log_file" ||
       [ "$(jq -r '.success // false' "$organization_file")" != "true" ]; then
        rm -rf -- "$work_dir"
        msg "A Cloudflare não respondeu durante a validação do MFA. Nenhuma política foi alterada.\n\nLog: $log_file"
        return 1
    fi
    auth_domain=$(jq -r '.result.auth_domain // empty' "$organization_file")
    if [ "$team_domain" != "https://$auth_domain" ]; then
        rm -rf -- "$work_dir"
        msg "O domínio de autenticação retornado pela Cloudflare diverge do Control Center instalado. Nenhuma política foi alterada."
        return 1
    fi

    if ! curl -sS --connect-timeout "$CLOUDFLARE_CONNECT_TIMEOUT" --max-time "$CLOUDFLARE_MAX_TIME" \
        -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
        "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/access/apps?per_page=100" \
        >"$applications_file" 2>>"$log_file" ||
       [ "$(jq -r '.success // false' "$applications_file")" != "true" ]; then
        rm -rf -- "$work_dir"
        msg "Não foi possível localizar a aplicação Access do Control Center. Confirme Access: Apps and Policies > Editar. Nenhuma política foi alterada.\n\nLog: $log_file"
        return 1
    fi
    app_count=$(jq -r --arg aud "$aud" '[.result[]? | select(.aud == $aud)] | length' "$applications_file")
    app_id=$(jq -r --arg aud "$aud" '[.result[]? | select(.aud == $aud)][0].id // empty' "$applications_file")
    if [ "$app_count" -ne 1 ] || [[ ! "$app_id" =~ ^[A-Fa-f0-9-]{32,36}$ ]]; then
        rm -rf -- "$work_dir"
        msg "A aplicação Access associada ao Control Center não foi identificada de forma única. Nenhuma política foi alterada."
        return 1
    fi
    if ! curl -sS --connect-timeout "$CLOUDFLARE_CONNECT_TIMEOUT" --max-time "$CLOUDFLARE_MAX_TIME" \
        -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
        "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/access/apps/$app_id" \
        >"$application_file" 2>>"$log_file" ||
       [ "$(jq -r '.success // false' "$application_file")" != "true" ]; then
        rm -rf -- "$work_dir"
        msg "A política Access atual não pôde ser consultada. Nenhuma alteração foi realizada.\n\nLog: $log_file"
        return 1
    fi
    policy_count=$(jq -r --arg email "$email" \
        '[.result.policies[]? | select(any(.include[]?; .email.email? == $email))] | length' \
        "$application_file")
    policy_id=$(jq -r --arg email "$email" \
        '[.result.policies[]? | select(any(.include[]?; .email.email? == $email))][0].id // empty' \
        "$application_file")
    if [ "$policy_count" -ne 1 ] || [[ ! "$policy_id" =~ ^[A-Fa-f0-9-]{32,36}$ ]]; then
        rm -rf -- "$work_dir"
        msg "A política do e-mail autorizado não foi identificada de forma única. Nenhuma alteração foi realizada."
        return 1
    fi
    current_mfa_disabled=$(jq -r --arg email "$email" \
        'if [.result.policies[]? | select(any(.include[]?; .email.email? == $email))][0].mfa_config.mfa_disabled == false then "false" else "true" end' \
        "$application_file")
    if [ "$current_mfa_disabled" = "false" ]; then
        if ! ensure_cloudflare_mfa_onboarding "$work_dir" "$email" "$log_file" "$onboarding_state"; then
            rm -rf -- "$work_dir"
            return 1
        fi
        if ! ensure_cloudflare_access_cookie_lax "$application_file" "$app_id" "$work_dir" "$log_file"; then
            rollback_cloudflare_mfa_onboarding "$onboarding_state" "$log_file"
            rm -rf -- "$work_dir"
            return 1
        fi
        if [ -n "$(control_service_env_value "$web_service" ACCESS_MFA_REQUIRED)" ]; then
            docker service update --detach=true --env-rm ACCESS_MFA_REQUIRED \
                --env-add ACCESS_MFA_REQUIRED=true "$web_service" >>"$log_file" 2>&1 || true
        else
            docker service update --detach=true --env-add ACCESS_MFA_REQUIRED=true \
                "$web_service" >>"$log_file" 2>&1 || true
        fi
        write_control_mfa_state true true false existing-enabled || {
            rm -rf -- "$work_dir"
            msg "O MFA está ativo, mas o estado persistente não pôde ser registrado."
            return 1
        }
        rm -rf -- "$work_dir"
        msg "O MFA já está ativo para $email e a preparação automática do cadastro foi confirmada.\n\nUse o aplicativo autenticador em:\n${team_domain}/AddMfaDevice"
        return 0
    fi
    if ! whiptail --title "ATIVAR MFA NO CONTROL CENTER?" --yesno \
        "O Setup preparará automaticamente o login por e-mail e a página de cadastro. A política de $email passará a exigir código do aplicativo autenticador.\n\nDepois, basta abrir:\n${team_domain}/AddMfaDevice\n\nDeseja ativar agora?" \
        17 92 1>&2; then
        rm -rf -- "$work_dir"
        return 0
    fi
    build_existing_access_policy_payload "$application_file" "$policy_payload" "$email" true || {
        rm -rf -- "$work_dir"
        msg "Não foi possível preparar a política MFA com segurança. Nenhuma alteração foi realizada."
        return 1
    }
    build_existing_access_policy_payload "$application_file" "$rollback_payload" "$email" false || {
        rm -rf -- "$work_dir"
        msg "Não foi possível preparar o rollback da política MFA. Nenhuma alteração foi realizada."
        return 1
    }
    if ! ensure_cloudflare_mfa_onboarding "$work_dir" "$email" "$log_file" "$onboarding_state"; then
        rm -rf -- "$work_dir"
        return 1
    fi
    if ! ensure_cloudflare_access_cookie_lax "$application_file" "$app_id" "$work_dir" "$log_file"; then
        rollback_cloudflare_mfa_onboarding "$onboarding_state" "$log_file"
        rm -rf -- "$work_dir"
        return 1
    fi
    if ! curl -sS --connect-timeout "$CLOUDFLARE_CONNECT_TIMEOUT" --max-time "$CLOUDFLARE_MAX_TIME" \
        -X PUT \
        "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/access/apps/$app_id/policies/$policy_id" \
        -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" -H "Content-Type: application/json" \
        --data-binary @"$policy_payload" >"$response_file" 2>>"$log_file" ||
       [ "$(jq -r '.success // false' "$response_file")" != "true" ] ||
       [ "$(jq -r 'if .result.mfa_config.mfa_disabled == false then "false" else "true" end' "$response_file")" != "false" ]; then
        rollback_cloudflare_mfa_onboarding "$onboarding_state" "$log_file"
        rm -rf -- "$work_dir"
        msg "A Cloudflare recusou a ativação do MFA. A política anterior foi preservada.\n\nLog: $log_file"
        return 1
    fi
    if [ -n "$(control_service_env_value "$web_service" ACCESS_MFA_REQUIRED)" ]; then
        current_mfa_enabled="--env-rm"
        if ! docker service update --detach=true --env-rm ACCESS_MFA_REQUIRED \
            --env-add ACCESS_MFA_REQUIRED=true "$web_service" >>"$log_file" 2>&1; then
            current_mfa_enabled="failed"
        fi
    elif ! docker service update --detach=true --env-add ACCESS_MFA_REQUIRED=true \
        "$web_service" >>"$log_file" 2>&1; then
        current_mfa_enabled="failed"
    else
        current_mfa_enabled="added"
    fi
    if [ "$current_mfa_enabled" = "failed" ]; then
        rollback_response="$work_dir/rollback-response.json"
        curl -sS --connect-timeout "$CLOUDFLARE_CONNECT_TIMEOUT" --max-time "$CLOUDFLARE_MAX_TIME" \
            -X PUT \
            "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/access/apps/$app_id/policies/$policy_id" \
            -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" -H "Content-Type: application/json" \
            --data-binary @"$rollback_payload" >"$rollback_response" 2>>"$log_file" || true
        rollback_cloudflare_mfa_onboarding "$onboarding_state" "$log_file"
        rm -rf -- "$work_dir"
        msg "O Control Center não conseguiu registrar o novo estado. A política anterior foi restaurada.\n\nLog: $log_file"
        return 1
    fi
    write_control_mfa_state true true false menu-enabled || {
        rm -rf -- "$work_dir"
        msg "O MFA foi ativado, mas o estado persistente não pôde ser registrado. Execute novamente esta opção antes de atualizar o Setup MNO."
        return 1
    }
    rm -rf -- "$work_dir"
    msg "MFA ATIVADO COM SUCESSO!\n\nE-mail protegido: $email\n\nA Cloudflare foi preparada automaticamente. Próximo passo:\n1. Abra ${team_domain}/AddMfaDevice\n2. Entre com o mesmo e-mail\n3. Escolha Aplicativo autenticador e leia o QR Code\n4. Volte e abra o Control Center"
    return 0
}

command -v flock >/dev/null 2>&1 || {
    msg "A trava de instalação segura (flock) não está disponível. Nenhuma alteração foi realizada."
    exit 1
}
exec 9>"/root/SetupLowCodeMno/.setupmno-control-install.lock" || {
    msg "Não foi possível criar a trava de instalação do Control Center. Nenhuma alteração foi realizada."
    exit 1
}
flock -n 9 || {
    msg "Já existe uma instalação do Setup MNO Control Center em andamento neste servidor.\n\nAguarde a conclusão antes de tentar novamente."
    exit 0
}

if control_center_installed; then
    case "${1:-}" in
        --reconcile-existing)
            reconcile_existing_control_center
            exit $?
            ;;
        --configure-access-mfa)
            configure_existing_access_mfa
            exit $?
            ;;
    esac
    msg "Já existe um Setup MNO Control Center neste servidor.\n\nPor segurança, somente uma instalação é permitida por servidor. A instalação atual foi preservada."
    exit 0
fi

ask_with_default() {
    local prompt="$1" default_value="$2" value status
    while true; do
        value=$(whiptail --title "SETUP MNO CONTROL CENTER" --inputbox \
            "$prompt" 13 82 "$default_value" 3>&1 1>&2 2>&3)
        status=$?
        [ "$status" -ne 0 ] && return 130
        [ -n "$value" ] && {
            printf '%s' "$value"
            return
        }
        msg "Este campo é obrigatório."
    done
}

ask_llm_key() {
    local provider_name="$1" value status
    while true; do
        value=$(whiptail --title "SETUP MNO CONTROL CENTER" --passwordbox \
            "Informe a chave da API $provider_name.\n\nEla será armazenada exclusivamente como Docker Secret e nunca será exibida em logs." \
            14 82 3>&1 1>&2 2>&3)
        status=$?
        [ "$status" -ne 0 ] && return 130
        if [ "${#value}" -ge 20 ] && [[ "$value" != *[[:space:]]* ]]; then
            printf '%s' "$value"
            return
        fi
        msg "A chave informada é inválida. Verifique e tente novamente."
    done
}

ask_password() {
    local value confirmation status
    while true; do
        value=$(whiptail --title "SETUP MNO CONTROL CENTER" --passwordbox \
            "3/${wizard_total:-5} — Crie a senha administrativa:\n\nMínimo de 12 caracteres, com maiúscula, minúscula, número e símbolo." \
            14 78 3>&1 1>&2 2>&3)
        status=$?
        [ "$status" -ne 0 ] && return 130
        if [ "${#value}" -lt 12 ]; then
            msg "Senha inválida: use pelo menos 12 caracteres."
            continue
        fi
        if [[ ! "$value" =~ [[:upper:]] ]]; then
            msg "Senha inválida: inclua pelo menos uma letra maiúscula."
            continue
        fi
        if [[ ! "$value" =~ [[:lower:]] ]]; then
            msg "Senha inválida: inclua pelo menos uma letra minúscula."
            continue
        fi
        if [[ ! "$value" =~ [[:digit:]] ]]; then
            msg "Senha inválida: inclua pelo menos um número."
            continue
        fi
        if [[ "$value" =~ [[:space:]] ]]; then
            msg "Senha inválida: não use espaços."
            continue
        fi
        if [[ ! "$value" =~ [^[:alnum:][:space:]] ]]; then
            msg "Senha inválida: inclua pelo menos um símbolo, como !, @, # ou %."
            continue
        fi
        confirmation=$(whiptail --title "SETUP MNO CONTROL CENTER" --passwordbox \
            "Confirme a senha administrativa:" 11 78 3>&1 1>&2 2>&3)
        status=$?
        [ "$status" -ne 0 ] && return 130
        [ "$value" = "$confirmation" ] && {
            printf '%s' "$value"
            return
        }
        msg "As senhas não coincidem."
    done
}

check_cloudflare_route() {
    local output_file="$1" status_file error_file curl_status
    status_file=$(mktemp) || {
        msg "Não foi possível preparar a verificação segura do Cloudflare Tunnel."
        return 1
    }
    error_file=$(mktemp) || {
        rm -f "$status_file"
        msg "Não foi possível preparar a verificação segura do Cloudflare Tunnel."
        return 1
    }

    {
        echo -e "XXX\n10\nCONECTANDO À API DO CLOUDFLARE...\nXXX"
        if curl -sS \
            --connect-timeout "$CLOUDFLARE_CONNECT_TIMEOUT" \
            --max-time "$CLOUDFLARE_MAX_TIME" \
            -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
            "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/cfd_tunnel/$TUNNEL_ID/configurations" \
            >"$output_file" 2>"$error_file"; then
            printf '0\n' >"$status_file"
        else
            printf '%s\n' "$?" >"$status_file"
        fi
        echo -e "XXX\n100\nVERIFICAÇÃO DO CLOUDFLARE CONCLUÍDA\nXXX"
    } | whiptail --title "SETUP MNO CONTROL CENTER" --gauge \
        "Verificando o domínio informado..." 8 78 0

    curl_status=$(cat "$status_file" 2>/dev/null)
    rm -f "$status_file" "$error_file"
    case "$curl_status" in
        0) ;;
        6)
            msg "Não foi possível resolver api.cloudflare.com. Verifique o DNS e a conexão do servidor."
            return 1
            ;;
        7)
            msg "Não foi possível conectar à API do Cloudflare. Verifique a conexão do servidor."
            return 1
            ;;
        28)
            msg "A API do Cloudflare não respondeu em até ${CLOUDFLARE_MAX_TIME} segundos. Nenhum recurso foi alterado. Tente novamente quando a conexão estiver estável."
            return 1
            ;;
        *)
            msg "Não foi possível consultar o Cloudflare Tunnel. Nenhum recurso foi alterado. Verifique a conexão e tente novamente."
            return 1
            ;;
    esac

    if ! jq -e '.success == true and (.result.config.ingress | type == "array")' \
        "$output_file" >/dev/null 2>&1; then
        msg "A Cloudflare recusou a consulta ou retornou uma resposta inválida. Verifique as credenciais do Tunnel. Nenhum recurso foi alterado."
        return 1
    fi
}

check_cloudflare_access() {
    local organization_file="$1" applications_file="$2" status_file error_file curl_status
    status_file=$(mktemp) || return 1
    error_file=$(mktemp) || {
        rm -f "$status_file"
        return 1
    }
    {
        echo -e "XXX\n10\nVALIDANDO O CLOUDFLARE ZERO TRUST...\nXXX"
        if curl -sS \
            --connect-timeout "$CLOUDFLARE_CONNECT_TIMEOUT" \
            --max-time "$CLOUDFLARE_MAX_TIME" \
            -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
            "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/access/organizations" \
            >"$organization_file" 2>"$error_file" && \
           curl -sS \
            --connect-timeout "$CLOUDFLARE_CONNECT_TIMEOUT" \
            --max-time "$CLOUDFLARE_MAX_TIME" \
            -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
            "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/access/apps?per_page=100" \
            >"$applications_file" 2>>"$error_file"; then
            printf '0\n' >"$status_file"
        else
            printf '%s\n' "$?" >"$status_file"
        fi
        echo -e "XXX\n100\nZERO TRUST VALIDADO\nXXX"
    } | whiptail --title "SEGURANÇA CLOUDFLARE ACCESS" --gauge \
        "Confirmando identidade, modo de segurança e permissões..." 8 82 0

    curl_status=$(cat "$status_file" 2>/dev/null)
    rm -f "$status_file" "$error_file"
    [ "$curl_status" = "0" ] || {
        msg "Não foi possível consultar o Cloudflare Access.\n\nUse o assistente de token para validar as cinco permissões necessárias. Nenhum recurso foi alterado."
        return 1
    }
    if [ "$(jq -r '.success // false' "$organization_file" 2>/dev/null)" != "true" ] ||
       [ "$(jq -r '.success // false' "$applications_file" 2>/dev/null)" != "true" ]; then
        msg "A Cloudflare recusou a validação do Zero Trust.\n\nConfirme Access: Apps and Policies > Editar e Access: Organizations, Identity Providers, and Groups > Editar. Nenhum recurso foi alterado."
        return 1
    fi
    access_auth_domain=$(jq -r '.result.auth_domain // empty' "$organization_file")
    if [[ ! "$access_auth_domain" =~ ^[A-Za-z0-9-]+\.cloudflareaccess\.com$ ]]; then
        msg "A organização Zero Trust ainda não possui um domínio de autenticação válido. Configure o Cloudflare Zero Trust antes de instalar o Control Center."
        return 1
    fi
    existing_access_app=$(jq -r --arg host "$url_control" '
        [.result[]? | select(
            .domain == $host or
            any(.destinations[]?; .type == "public" and .uri == $host)
        )][0].id // empty
    ' "$applications_file" 2>/dev/null)
    if [ -n "$existing_access_app" ]; then
        msg "Já existe um aplicativo Cloudflare Access protegendo $url_control.\n\nPara evitar substituir políticas de segurança que podem pertencer a outro sistema, informe outro domínio ou remova conscientemente o aplicativo existente no Zero Trust. Nenhum recurso foi alterado."
        return 1
    fi
    access_team_domain="https://$access_auth_domain"
    access_team_name="${access_auth_domain%.cloudflareaccess.com}"
    return 0
}

whiptail --title "SETUP MNO CONTROL CENTER" --yesno \
    "Instalar o painel web oficial do Setup MNO?\n\nO Control Center mostra aplicações instaladas, saúde do Docker Swarm, CPU, RAM, disco, catálogo de setups, auditoria, diagnóstico local e acesso autenticado ao instalador original." \
    16 82 || exit 0

wizard_total=5
assistant_step=4
portainer_step=5
if [ "$INSTALL_TYPE" = "CLOUDFLARE_TUNNEL" ]; then
    wizard_total=6
    assistant_step=5
    portainer_step=6
fi

while true; do
    if ! url_control=$(ask_required "1/$wizard_total — Domínio do painel (ex.: setup.seudominio.com):"); then
        exit 0
    fi
    if [[ "$url_control" =~ ^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$ ]] &&
       [[ "$url_control" == *.* ]]; then
        break
    fi
    msg "Informe somente o domínio, sem http://, https://, barras ou caminhos."
done

if [ "$INSTALL_TYPE" = "CLOUDFLARE_TUNNEL" ]; then
    route_check=$(mktemp) || {
        msg "Não foi possível preparar a verificação segura do Cloudflare Tunnel."
        exit 1
    }
    if ! check_cloudflare_route "$route_check"; then
        rm -f "$route_check"
        exit 1
    fi
    existing_service=$(jq -r --arg host "$url_control" \
        '.result.config.ingress[]? | select(.hostname == $host) | .service' "$route_check" 2>/dev/null | head -n1)
    rm -f "$route_check"
    if [ -n "$existing_service" ] && [ "$existing_service" != "null" ]; then
        msg "Já existe uma rota para:\n\n$url_control\n\nServiço atual: $existing_service\n\nA rota será substituída pela nova instalação."
    fi
fi

while true; do
    if ! usuario_control=$(ask_required "2/$wizard_total — Usuário administrador do painel:"); then
        exit 0
    fi
    if [[ "$usuario_control" =~ ^[A-Za-z0-9_.-]{3,40}$ ]]; then
        break
    fi
    msg "Use de 3 a 40 caracteres: letras, números, ponto, hífen ou sublinhado."
done

if ! senha_control=$(ask_password); then
    exit 0
fi

access_email=""
access_team_domain=""
access_team_name=""
access_mfa_enabled="false"
if [ "$INSTALL_TYPE" = "CLOUDFLARE_TUNNEL" ]; then
    if control_mfa_state_valid; then
        access_mfa_enabled=$(jq -r '.desiredMFA' "$CONTROL_MFA_STATE_FILE")
        if [ "$access_mfa_enabled" = "true" ]; then
            whiptail --title "4/6 — PREFERÊNCIA DE MFA REGISTRADA" --msgbox \
                "Você escolheu MFA durante a preparação do ambiente. Essa decisão foi preservada e não será perguntada novamente.\n\nAgora serão solicitados apenas os dados necessários para ativar a proteção do Control Center." \
                16 88 1>&2
        fi
    else
        whiptail --title "4/6 — PROTEÇÃO CLOUDFLARE ACCESS" --msgbox \
            "Esta instalação ainda não possui uma preferência registrada. Escolha MFA ou modo original; a decisão será preservada nas próximas atualizações." \
            15 88 1>&2
        choose_cloudflare_access_security || exit 0
        if [ "$access_mfa_enabled" = "true" ]; then
            write_control_mfa_state true false true control-fallback || exit 1
        else
            write_control_mfa_state false false false control-fallback || exit 1
        fi
    fi
    if [ "$access_mfa_enabled" = "true" ]; then
        access_token_work=$(mktemp -d) || exit 1
        access_token_log="/tmp/setupmno-control-mfa-token-${CONTROL_VERSION}.log"
        : >"$access_token_log"
        if ! load_cloudflare_mfa_helper; then
            rm -rf -- "$access_token_work"
            msg "O assistente autenticado de MFA não pôde ser carregado. Atualize o Setup MNO e tente novamente."
            exit 1
        fi
        prepare_cloudflare_mfa_token "$access_token_work" "$access_token_log"
        access_token_status=$?
        rm -rf -- "$access_token_work"
        if [ "$access_token_status" -ne 0 ]; then
            [ "$access_token_status" -eq 130 ] && exit 0
            exit "$access_token_status"
        fi
        access_email=$(collect_cloudflare_access_email "4/6") || exit 0
        access_organization_file=$(mktemp) || exit 1
        access_applications_file=$(mktemp) || {
            rm -f "$access_organization_file"
            exit 1
        }
        while true; do
            check_cloudflare_access "$access_organization_file" "$access_applications_file"
            access_check_status=$?
            case "$access_check_status" in
                0)
                    break
                    ;;
                *)
                    if ! whiptail --title "NÃO FOI POSSÍVEL VALIDAR O ACCESS" --yesno \
                        "A validação não passou, mas nada foi alterado.\n\nDeseja corrigir o Cloudflare/token e tentar novamente?\n\nEscolha Não para usar o modo original sem MFA." \
                        15 88 1>&2; then
                        access_mfa_enabled="false"
                        write_control_mfa_state false false false validation-fallback || exit 1
                        break
                    fi
                    ;;
            esac
        done
        rm -f "$access_organization_file" "$access_applications_file"
        if [ "$access_mfa_enabled" = "false" ]; then
            access_email=""
            access_team_domain=""
            access_team_name=""
        fi
    fi
fi

mem_total_mb=$(awk '/MemTotal:/ {print int($2/1024)}' /proc/meminfo)
mem_available_mb=$(awk '/MemAvailable:/ {print int($2/1024)}' /proc/meminfo)
assistant_mode="basic"
assistant_model=""
assistant_base_url=""
llm_api_key=""

if [ "$CONTROL_PLAN" != "pro" ]; then
    msg "O plano $CONTROL_PLAN inclui o Control Center com diagnóstico básico local.\n\nO Assistente com IA permanece desativado neste plano, mesmo que exista uma configuração antiga de provedor. Nenhuma chave ou stack de LLM será criada."
elif [ "${mem_total_mb:-0}" -lt 4096 ] || [ "${mem_available_mb:-0}" -lt 1536 ]; then
    msg "O Control Center será instalado com o diagnóstico básico.\n\nMemória total: ${mem_total_mb:-0} MB\nMemória disponível: ${mem_available_mb:-0} MB\n\nO Copiloto com LLM é opcional e foi desativado para proteger este servidor. Você poderá configurá-lo futuramente após ampliar os recursos."
else
    while true; do
        assistant_choice=$(whiptail --title "$assistant_step/$wizard_total — ASSISTENTE MNO" --default-item "OPENAI" --menu \
            "Escolha como o Copiloto de Infraestrutura funcionará.\n\nOpenAI é a seleção inicial. Todo conector usa uma stack isolada de 256 MB, sem acesso ao Docker ou terminal." \
            23 92 7 \
            "OPENAI" "LLM externa pela Responses API (padrão inicial)" \
            "OPENROUTER" "Catálogo multi-modelo pela API compatível" \
            "DEEPSEEK" "Modelos oficiais DeepSeek" \
            "OLLAMA" "Modelo existente em um endpoint Ollama" \
            "BASIC" "Diagnóstico local sem LLM" \
            "LATER" "Configurar o conector de IA futuramente" \
            3>&1 1>&2 2>&3)
        assistant_status=$?
        [ "$assistant_status" -ne 0 ] && exit 0
        case "$assistant_choice" in
            BASIC)
                assistant_mode="basic"
                break
                ;;
            LATER)
                assistant_mode="later"
                break
                ;;
            OPENAI)
                if ! llm_api_key=$(ask_llm_key "OpenAI"); then
                    exit 0
                fi
                if ! assistant_model=$(ask_with_default \
                    "Modelo OpenAI para o Copiloto:\n\nO padrão equilibra qualidade, latência e custo. Você pode informar outro modelo compatível com a Responses API." \
                    "gpt-5.6-terra"); then
                    exit 0
                fi
                assistant_mode="openai"
                assistant_base_url="https://api.openai.com/v1"
                break
                ;;
            OPENROUTER)
                if ! llm_api_key=$(ask_llm_key "OpenRouter"); then
                    exit 0
                fi
                if ! assistant_model=$(ask_with_default \
                    "Modelo OpenRouter para o Copiloto:\n\nInforme o identificador exato no formato provedor/modelo." \
                    "openai/gpt-5.4"); then
                    exit 0
                fi
                assistant_mode="openrouter"
                assistant_base_url="https://openrouter.ai/api/v1"
                break
                ;;
            DEEPSEEK)
                if ! llm_api_key=$(ask_llm_key "DeepSeek"); then
                    exit 0
                fi
                if ! assistant_model=$(ask_with_default \
                    "Modelo DeepSeek para o Copiloto:\n\nVocê pode informar outro identificador aceito atualmente pelo provedor." \
                    "deepseek-v4-flash"); then
                    exit 0
                fi
                assistant_mode="deepseek"
                assistant_base_url="https://api.deepseek.com"
                break
                ;;
            OLLAMA)
                if [ "${mem_total_mb:-0}" -lt 8192 ] || [ "${mem_available_mb:-0}" -lt 4096 ]; then
                    msg "O modo Ollama local exige pelo menos 8 GB de RAM total e 4 GB disponíveis.\n\nUse OpenAI, mantenha o diagnóstico básico ou amplie o servidor. Esta proteção evita degradação dos setups já instalados."
                    continue
                fi
                if ! assistant_base_url=$(ask_required \
                    "Endpoint do Ollama já instalado (ex.: https://apiollama.seudominio.com):"); then
                    exit 0
                fi
                assistant_base_url="${assistant_base_url%/}"
                if [[ ! "$assistant_base_url" =~ ^https?://[^[:space:]]+$ ]]; then
                    msg "Informe uma URL HTTP ou HTTPS válida para o endpoint Ollama."
                    continue
                fi
                if ! assistant_model=$(ask_required \
                    "Nome exato do modelo já baixado no Ollama (ex.: qwen3:8b):"); then
                    exit 0
                fi
                assistant_mode="ollama"
                break
                ;;
        esac
    done
fi

while true; do
    if ! criar_portainer=$(ask_required \
        "$portainer_step/$wizard_total — Criar Stack no Portainer?\n\n0 = editável no Portainer\n1 = direto no Docker"); then
        exit 0
    fi
    [[ "$criar_portainer" =~ ^[01]$ ]] && break
    msg "Digite somente 0 ou 1."
done

nome_principal="mnoctrl"
sufixo_app=$(date +%s%N | md5sum | head -c7)
nome_app="${nome_principal}${sufixo_app}"
web_stack="${nome_app}-web"
agent_stack="${nome_app}-agent"
terminal_stack="${nome_app}-terminal"
assistant_stack="${nome_app}-assistant"
web_service="${nome_app}-web"
agent_service="${nome_app}-agent"
terminal_service="${nome_app}-terminal"
assistant_service="${nome_app}-assistant"
control_image="${nome_app}-app:${CONTROL_VERSION}"
terminal_image="${nome_app}-terminal:${CONTROL_VERSION}"
admin_secret="${nome_app}-admin-password"
agent_secret="${nome_app}-agent-token"
llm_secret="${nome_app}-llm-api-key"
if [ "$criar_portainer" = "0" ]; then
    control_stack_manager="portainer"
else
    control_stack_manager="docker"
fi

assistant_label="Diagnóstico básico (sem LLM)"
assistant_has_llm="false"
memory_limit="576 MB"
assistant_internal_url=""
assistant_external="false"
if [ "$assistant_mode" = "openai" ] ||
   [ "$assistant_mode" = "openrouter" ] ||
   [ "$assistant_mode" = "deepseek" ]; then
    case "$assistant_mode" in
        openai) assistant_provider_label="OpenAI" ;;
        openrouter) assistant_provider_label="OpenRouter" ;;
        deepseek) assistant_provider_label="DeepSeek" ;;
    esac
    assistant_label="$assistant_provider_label · $assistant_model"
    assistant_has_llm="true"
    memory_limit="832 MB"
    assistant_internal_url="http://${assistant_stack}_${assistant_service}:7070"
    assistant_external="true"
elif [ "$assistant_mode" = "ollama" ]; then
    assistant_label="Ollama · $assistant_model"
    assistant_has_llm="true"
    memory_limit="832 MB + consumo do modelo Ollama"
    assistant_internal_url="http://${assistant_stack}_${assistant_service}:7070"
elif [ "$assistant_mode" = "later" ]; then
    assistant_label="Conector de IA adiado (chat desativado)"
fi

dns_mode="Cloudflare Tunnel"
if [ "$INSTALL_TYPE" = "TRADICIONAL" ]; then
    if [ "$criar_dns" = "0" ]; then
        dns_mode="Tradicional com DNS automático"
    else
        dns_mode="Tradicional com DNS manual"
    fi
fi

access_summary="Não aplicável (instalação tradicional)"
if [ "$INSTALL_TYPE" = "CLOUDFLARE_TUNNEL" ]; then
    if [ "$access_mfa_enabled" = "true" ]; then
        access_summary="E-mail exato + MFA independente · $access_email"
    else
        access_summary="Desativado · modo original com Tunnel direto"
    fi
fi
whiptail --title "CONFIRMAR INSTALAÇÃO" --yesno \
    "Setup MNO Control Center\n\nDomínio: $url_control\nAdministrador: $usuario_control\nCloudflare Access: $access_summary\nPlano: $CONTROL_PLAN\nAssistente: $assistant_label\nInstalação: $dns_mode\nDeploy: $([ "$criar_portainer" = "0" ] && echo "Portainer editável" || echo "Docker direto")\nArquiteturas: X86 e ARM\nLimite de memória do Control: $memory_limit\n\nO terminal executará o instalador original dentro de tmux e será acessível somente após autenticação em camadas." \
    23 88 || exit 0

install_log="/tmp/${nome_app}-install.log"
error_file="/tmp/${nome_app}-error.log"
: >"$install_log"
: >"$error_file"

{
    work_dir=$(mktemp -d)
    access_app_created="false"
    access_app_id=""
    access_app_aud=""
    access_onboarding_state="$work_dir/access-onboarding-state.json"
    tunnel_updated="false"
    tunnel_original_payload=""

    cleanup_install() {
        local status=$? route_rollback_ok="true" access_delete_ok="true" access_delete_response
        if [ "$status" -ne 0 ] && [ "$INSTALL_TYPE" = "CLOUDFLARE_TUNNEL" ]; then
            if [ "$tunnel_updated" = "true" ] && [ -s "$tunnel_original_payload" ]; then
                if ! curl -sS \
                    --connect-timeout "$CLOUDFLARE_CONNECT_TIMEOUT" \
                    --max-time "$CLOUDFLARE_MAX_TIME" \
                    -X PUT \
                    "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/cfd_tunnel/$TUNNEL_ID/configurations" \
                    -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
                    -H "Content-Type: application/json" \
                    --data-binary @"$tunnel_original_payload" >>"$install_log" 2>&1; then
                    route_rollback_ok="false"
                    echo "Rollback da rota do Tunnel falhou; política Access foi preservada por segurança." >>"$install_log"
                fi
            fi
            if [ "$access_app_created" = "true" ] && [ "$route_rollback_ok" = "true" ] &&
               [[ "$access_app_id" =~ ^[A-Fa-f0-9-]{32,36}$ ]]; then
                access_delete_response="$work_dir/access-app-delete-response.json"
                if ! curl -sS \
                    --connect-timeout "$CLOUDFLARE_CONNECT_TIMEOUT" \
                    --max-time "$CLOUDFLARE_MAX_TIME" \
                    -X DELETE \
                    "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/access/apps/$access_app_id" \
                    -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" >"$access_delete_response" 2>>"$install_log" ||
                   [ "$(jq -r '.success // false' "$access_delete_response" 2>/dev/null)" != "true" ]; then
                    access_delete_ok="false"
                    echo "Rollback da aplicação Access falhou; preparação MFA foi preservada por segurança." >>"$install_log"
                fi
            fi
            if [ "$route_rollback_ok" = "true" ] && [ "$access_delete_ok" = "true" ] &&
               [ -s "$access_onboarding_state" ]; then
                rollback_cloudflare_mfa_onboarding "$access_onboarding_state" "$install_log" || true
            fi
        fi
        rm -rf -- "$work_dir"
        return "$status"
    }
    trap cleanup_install EXIT

    fail_install() {
        local code="$1" progress="$2" message="$3"
        printf '%s\n' "$message" >"$error_file"
        echo -e "XXX\n100\n$progress\nXXX"
        exit "$code"
    }

    echo -e "XXX\n4\nVALIDANDO AMBIENTE... \nXXX"
    for required_command in docker curl jq tar openssl; do
        command -v "$required_command" >/dev/null 2>&1 ||
            fail_install 10 "DEPENDÊNCIA NÃO ENCONTRADA" "O comando obrigatório '$required_command' não está instalado."
    done
    docker info >>"$install_log" 2>&1 ||
        fail_install 11 "DOCKER INDISPONÍVEL" "O Docker Engine ou o Swarm não está disponível."
    swarm_state=$(docker info --format '{{.Swarm.LocalNodeState}}' 2>>"$install_log")
    [ "$swarm_state" = "active" ] ||
        fail_install 11 "SWARM INATIVO" "O Docker Swarm precisa estar ativo antes de instalar o Control Center."
    docker network inspect interna >>"$install_log" 2>&1 ||
        fail_install 12 "REDE INTERNA INDISPONÍVEL" "A rede overlay 'interna' não foi encontrada."
    docker network inspect externa >>"$install_log" 2>&1 ||
        fail_install 13 "REDE EXTERNA INDISPONÍVEL" "A rede overlay 'externa' não foi encontrada."
    [ -x /root/SetupLowCodeMno/install ] ||
        fail_install 14 "INSTALADOR NÃO ENCONTRADO" "O executável /root/SetupLowCodeMno/install não foi encontrado."
    [ -s /root/SetupLowCodeMno/.control/release.json ] &&
    [ -s /root/SetupLowCodeMno/.control/catalog.json ] ||
        fail_install 14 "ESTADO DO SETUP NÃO ENCONTRADO" "Atualize o Setup MNO antes de instalar o Control Center. O manifesto ou catálogo runtime não foi encontrado."
    runtime_catalog_sha=$(sha256sum /root/SetupLowCodeMno/.control/catalog.json | awk '{print $1}')
    expected_catalog_sha=$(jq -r '.catalogSHA256 // empty' /root/SetupLowCodeMno/.control/release.json 2>>"$install_log")
    [ -n "$expected_catalog_sha" ] && [ "$runtime_catalog_sha" = "$expected_catalog_sha" ] ||
        fail_install 14 "CATÁLOGO DO SETUP INVÁLIDO" "O catálogo runtime não corresponde ao manifesto da versão instalada."
    [ -f "$CREDENTIALS_FILE" ] ||
        fail_install 15 "CREDENCIAIS NÃO ENCONTRADAS" "Arquivo de credenciais não encontrado: $CREDENTIALS_FILE"

    if [ "$INSTALL_TYPE" = "CLOUDFLARE_TUNNEL" ] ||
       { [ "$INSTALL_TYPE" = "TRADICIONAL" ] && [ "$criar_dns" = "0" ]; }; then
        if [ -z "$CLOUDFLARE_API_TOKEN" ] || [ -z "$CLOUDFLARE_ZONE_ID" ]; then
            fail_install 16 "CREDENCIAIS CLOUDFLARE INVÁLIDAS" "Token ou Zone ID do Cloudflare não encontrado."
        fi
    fi
    if [ "$INSTALL_TYPE" = "CLOUDFLARE_TUNNEL" ] &&
       { [ -z "$CLOUDFLARE_ACCOUNT_ID" ] || [ -z "$TUNNEL_ID" ]; }; then
        fail_install 17 "DADOS DO TUNNEL INVÁLIDOS" "Account ID ou Tunnel ID não encontrado."
    fi

    echo -e "XXX\n10\nEXTRAINDO O CONTROL CENTER... \nXXX"
    mkdir -p "$work_dir/source"
    if ! extract_control_bundle 2>>"$install_log" |
        tar -xzf - -C "$work_dir/source" >>"$install_log" 2>&1; then
        fail_install 20 "BUNDLE DO PAINEL INVÁLIDO" "Não foi possível validar e extrair os fontes internos do Control Center."
    fi
    runtime_catalog="/root/SetupLowCodeMno/.control/catalog.json"
    runtime_release="/root/SetupLowCodeMno/.control/release.json"
    [ -f "$runtime_catalog" ] &&
    [ ! -L "$runtime_catalog" ] &&
    [ -f "$runtime_release" ] &&
    [ ! -L "$runtime_release" ] ||
        fail_install 21 "CATÁLOGO RUNTIME AUSENTE" "Atualize o Setup MNO para receber o catálogo validado."
    runtime_catalog_sha=$(sha256sum "$runtime_catalog" | awk '{print $1}')
    expected_catalog_sha=$(jq -r '.catalogSHA256 // empty' "$runtime_release" 2>>"$install_log")
    [ -n "$expected_catalog_sha" ] &&
    [ "$runtime_catalog_sha" = "$expected_catalog_sha" ] ||
        fail_install 21 "CATÁLOGO RUNTIME INVÁLIDO" "O catálogo não corresponde ao manifesto desta release."
    install -m 0644 "$runtime_catalog" "$work_dir/source/catalog.json"
    for source_file in go.mod Dockerfile terminal.Dockerfile prepare-ttyd-index.sh \
        terminal-menu.sh configure-control.sh control-upgrade.sh cloudflare-mfa.sh \
        main.go access.go knowledge.go retrieval.go routing.go prompts.go blueprint_recommendation.go evals.go provider_evals.go feedback.go audit.go catalog.json \
        web/index.html web/app.js web/assistant-route.js web/styles.css web/terminal-bridge.js; do
        [ -s "$work_dir/source/$source_file" ] ||
            fail_install 21 "FONTE INCOMPLETO" "O arquivo interno '$source_file' não foi encontrado no bundle."
        [ ! -L "$work_dir/source/$source_file" ] ||
            fail_install 21 "FONTE INSEGURO" "O arquivo interno '$source_file' não pode ser um link simbólico."
    done

    runtime_knowledge_dir="/root/SetupLowCodeMno/.control/knowledge-package"
    [ -f "$runtime_knowledge_dir/manifest.json" ] &&
    [ ! -L "$runtime_knowledge_dir/manifest.json" ] &&
    [ -f "$runtime_knowledge_dir/knowledge-package.tar.gz" ] &&
    [ ! -L "$runtime_knowledge_dir/knowledge-package.tar.gz" ] ||
        fail_install 22 "CONHECIMENTO RUNTIME AUSENTE" "Atualize o Setup MNO para receber o pacote de conhecimento validado."
    runtime_knowledge_sha=$(sha256sum "$runtime_knowledge_dir/knowledge-package.tar.gz" | awk '{print $1}')
    expected_knowledge_sha=$(jq -r '.archiveSHA256 // empty' "$runtime_knowledge_dir/manifest.json" 2>>"$install_log")
    release_knowledge_sha=$(jq -r '.knowledgeArchiveSHA256 // empty' /root/SetupLowCodeMno/.control/release.json 2>>"$install_log")
    knowledge_setup_version=$(jq -r '.setupVersion // empty' "$runtime_knowledge_dir/manifest.json" 2>>"$install_log")
    knowledge_control_version=$(jq -r '.controlVersion // empty' "$runtime_knowledge_dir/manifest.json" 2>>"$install_log")
    knowledge_entries=$(jq -r '.documentEntries // 0' "$runtime_knowledge_dir/manifest.json" 2>>"$install_log")
    knowledge_chunks=$(jq -r '.chunkEntries // 0' "$runtime_knowledge_dir/manifest.json" 2>>"$install_log")
    knowledge_index_schema=$(jq -r '.indexSchemaVersion // 0' "$runtime_knowledge_dir/manifest.json" 2>>"$install_log")
    knowledge_retrieval_version=$(jq -r '.retrievalVersion // empty' "$runtime_knowledge_dir/manifest.json" 2>>"$install_log")
    eval_schema=$(jq -r '.evalSchemaVersion // 0' "$runtime_knowledge_dir/manifest.json" 2>>"$install_log")
    eval_dataset_version=$(jq -r '.evalDatasetVersion // empty' "$runtime_knowledge_dir/manifest.json" 2>>"$install_log")
    eval_grader_version=$(jq -r '.evalGraderVersion // empty' "$runtime_knowledge_dir/manifest.json" 2>>"$install_log")
    eval_dataset_sha=$(jq -r '.evalDatasetSHA256 // empty' "$runtime_knowledge_dir/manifest.json" 2>>"$install_log")
    eval_case_entries=$(jq -r '.evalCaseEntries // 0' "$runtime_knowledge_dir/manifest.json" 2>>"$install_log")
    release_eval_dataset_sha=$(jq -r '.evalDatasetSHA256 // empty' /root/SetupLowCodeMno/.control/release.json 2>>"$install_log")
    release_knowledge_entries=$(jq -r '.knowledgeEntries // 0' /root/SetupLowCodeMno/.control/release.json 2>>"$install_log")
    knowledge_archive_bytes=$(jq -r '.archiveBytes // 0' "$runtime_knowledge_dir/manifest.json" 2>>"$install_log")
    actual_knowledge_bytes=$(stat -c '%s' "$runtime_knowledge_dir/knowledge-package.tar.gz")
    [ -n "$expected_knowledge_sha" ] &&
    [ "$runtime_knowledge_sha" = "$expected_knowledge_sha" ] &&
    [ "$release_knowledge_sha" = "$expected_knowledge_sha" ] &&
    [ "$knowledge_setup_version" = "$(jq -r '.setupVersion' /root/SetupLowCodeMno/.control/release.json)" ] &&
    [ "$knowledge_control_version" = "$CONTROL_VERSION" ] &&
    [ "$knowledge_entries" -gt 0 ] &&
    [ "$knowledge_chunks" -gt "$knowledge_entries" ] &&
    [ "$knowledge_index_schema" = "2" ] &&
    [ "$knowledge_retrieval_version" = "1.3.0" ] &&
    [ "$eval_schema" = "1" ] &&
    [ "$eval_dataset_version" = "1.9.0" ] &&
    [ "$eval_grader_version" = "1.9.0" ] &&
    [ "${#eval_dataset_sha}" -eq 64 ] &&
    [ "$eval_dataset_sha" = "$release_eval_dataset_sha" ] &&
    [ "$eval_case_entries" = "843" ] &&
    [ "$knowledge_entries" = "$release_knowledge_entries" ] &&
    [ "$knowledge_archive_bytes" = "$actual_knowledge_bytes" ] &&
    [ "$knowledge_archive_bytes" -le $((8 * 1024 * 1024)) ] &&
    tar -tzf "$runtime_knowledge_dir/knowledge-package.tar.gz" >>"$install_log" 2>&1 &&
    tar -tvzf "$runtime_knowledge_dir/knowledge-package.tar.gz" 2>>"$install_log" |
        awk 'substr($1, 1, 1) != "-" { exit 1 }' ||
        fail_install 22 "PACOTE DE CONHECIMENTO INVÁLIDO" "O conhecimento runtime diverge do manifesto desta release."

    build_knowledge_dir="$work_dir/source/knowledge-package"
    mkdir -p "$build_knowledge_dir"
    install -m 0644 "$runtime_knowledge_dir/manifest.json" \
        "$build_knowledge_dir/manifest.json"
    install -m 0644 "$runtime_knowledge_dir/knowledge-package.tar.gz" \
        "$build_knowledge_dir/knowledge-package.tar.gz"

    echo -e "XXX\n20\nCONSTRUINDO O PAINEL WEB... \nXXX"
    if ! docker build --pull -t "$control_image" "$work_dir/source" >>"$install_log" 2>&1; then
        {
            echo "Falha ao construir a imagem do painel."
            echo
            tail -n 20 "$install_log"
        } >"$error_file"
        echo -e "XXX\n100\nERRO NO BUILD DO PAINEL\nXXX"
        exit 30
    fi
    if ! docker image inspect --format \
        'Painel: {{.Id}} | Arquitetura: {{.Architecture}} | Tamanho: {{.Size}} bytes' \
        "$control_image" >>"$install_log" 2>&1; then
        fail_install 31 "IMAGEM DO PAINEL NÃO ENCONTRADA" "O build terminou, mas a imagem do painel não foi confirmada."
    fi
    if ! docker run --rm --entrypoint /setupmno-control \
        "$control_image" knowledgecheck >>"$install_log" 2>&1; then
        fail_install 31 "CONHECIMENTO DA IMAGEM INVÁLIDO" "A imagem não validou o pacote de conhecimento somente leitura."
    fi
    if ! docker run --rm --entrypoint /setupmno-control \
        "$control_image" evalcheck >>"$install_log" 2>&1; then
        fail_install 31 "REGRESSÃO DE QUALIDADE DETECTADA" "A suíte canônica de 843 casos não atingiu os gates mínimos desta release."
    fi
    fallback_check="$work_dir/knowledge-fallback.json"
    if ! docker run --rm \
        -e KNOWLEDGE_PACKAGE_DIR=/pacote-ausente \
        --entrypoint /setupmno-control \
        "$control_image" knowledgecheck >"$fallback_check" 2>>"$install_log" ||
       [ "$(jq -r '.source // empty' "$fallback_check" 2>>"$install_log")" != "embedded-fallback" ] ||
       [ "$(jq -r '.stale // false' "$fallback_check" 2>>"$install_log")" != "true" ]; then
        fail_install 31 "FALLBACK DE CONHECIMENTO INVÁLIDO" "A imagem não confirmou a base embutida de contingência."
    fi

    echo -e "XXX\n38\nCONSTRUINDO O TERMINAL PROTEGIDO... \nXXX"
    if ! docker build --pull -f "$work_dir/source/terminal.Dockerfile" \
        -t "$terminal_image" "$work_dir/source" >>"$install_log" 2>&1; then
        {
            echo "Falha ao construir a imagem do terminal protegido."
            echo
            tail -n 20 "$install_log"
        } >"$error_file"
        echo -e "XXX\n100\nERRO NO BUILD DO TERMINAL\nXXX"
        exit 32
    fi
    if ! docker image inspect --format \
        'Terminal: {{.Id}} | Arquitetura: {{.Architecture}} | Tamanho: {{.Size}} bytes' \
        "$terminal_image" >>"$install_log" 2>&1; then
        fail_install 33 "IMAGEM DO TERMINAL NÃO ENCONTRADA" "O build terminou, mas a imagem do terminal não foi confirmada."
    fi

    echo -e "XXX\n46\nVALIDANDO COMPATIBILIDADE DO INSTALADOR... \nXXX"
    if ! docker run --rm \
        --entrypoint /usr/bin/ldd \
        -v /root:/root:ro \
        -v /usr/bin/bash:/usr/bin/bash:ro \
        "$terminal_image" \
        /root/SetupLowCodeMno/install >>"$install_log" 2>&1; then
        {
            echo "O terminal foi construído, mas sua GLIBC não é compatível com o instalador do Setup MNO."
            echo
            tail -n 16 "$install_log"
        } >"$error_file"
        echo -e "XXX\n100\nTERMINAL INCOMPATÍVEL COM O INSTALADOR\nXXX"
        exit 34
    fi

    access_jwt_required="false"
    access_mfa_required="false"
    if [ "$INSTALL_TYPE" = "CLOUDFLARE_TUNNEL" ] &&
       [ "$access_mfa_enabled" = "true" ]; then
        access_mfa_required="true"
        echo -e "XXX\n48\nPREPARANDO LOGIN E MFA NA CLOUDFLARE... \nXXX"
        if ! ensure_cloudflare_mfa_onboarding "$work_dir" "$access_email" "$install_log" \
            "$access_onboarding_state"; then
            fail_install 35 "AUTOMAÇÃO DO MFA RECUSADA" "Não foi possível preparar TOTP, login por e-mail e App Launcher. Revise as duas permissões Access do token."
        fi
        echo -e "XXX\n49\nCRIANDO CLOUDFLARE ACCESS COM MFA... \nXXX"
        access_payload="$work_dir/access-app-payload.json"
        access_response="$work_dir/access-app-response.json"
        if ! build_cloudflare_access_payload "$access_payload" \
            "Setup MNO Control Center - $url_control" "$url_control" \
            "$access_email" "$access_mfa_enabled" 2>>"$install_log"; then
            fail_install 35 "POLÍTICA ACCESS INVÁLIDA" "Não foi possível preparar a política de identidade e segurança escolhida."
        fi
        if ! curl -sS \
            --connect-timeout "$CLOUDFLARE_CONNECT_TIMEOUT" \
            --max-time "$CLOUDFLARE_MAX_TIME" \
            -X POST \
            "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/access/apps" \
            -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
            -H "Content-Type: application/json" \
            --data-binary @"$access_payload" >"$access_response" 2>>"$install_log" ||
           [ "$(jq -r '.success // false' "$access_response" 2>>"$install_log")" != "true" ]; then
            access_error=$(jq -r '[.errors[]?.message] | join("; ")' "$access_response" 2>/dev/null)
            fail_install 35 "CLOUDFLARE ACCESS RECUSADO" "Não foi possível criar a proteção Access escolhida: ${access_error:-resposta inválida da API}."
        fi
        access_app_id=$(jq -r '.result.id // empty' "$access_response")
        access_app_aud=$(jq -r '.result.aud // empty' "$access_response")
        [[ "$access_app_id" =~ ^[A-Fa-f0-9-]{32,36}$ ]] &&
        [ "${#access_app_aud}" -ge 16 ] && [ "${#access_app_aud}" -le 128 ] ||
            fail_install 35 "CLOUDFLARE ACCESS INCOMPLETO" "A Cloudflare criou o aplicativo sem ID ou audiência validáveis."
        access_app_created="true"
        access_jwt_required="true"
        echo "Access confirmado para o domínio do Control Center com MFA em todo login." >>"$install_log"
    fi

    echo -e "XXX\n51\nCRIANDO SEGREDOS DO PAINEL... \nXXX"
    if ! printf '%s' "$senha_control" |
        docker secret create "$admin_secret" - >>"$install_log" 2>&1; then
        fail_install 40 "ERRO AO CRIAR SENHA" "Não foi possível criar o segredo da senha administrativa."
    fi
    unset senha_control
    if ! openssl rand -hex 32 |
        docker secret create "$agent_secret" - >>"$install_log" 2>&1; then
        fail_install 41 "ERRO AO CRIAR TOKEN" "Não foi possível criar o token privado do agente."
    fi
    if [ "$assistant_mode" = "openai" ] ||
       [ "$assistant_mode" = "openrouter" ] ||
       [ "$assistant_mode" = "deepseek" ]; then
        if ! printf '%s' "$llm_api_key" |
            docker secret create "$llm_secret" - >>"$install_log" 2>&1; then
            fail_install 42 "ERRO AO PROTEGER CHAVE LLM" "Não foi possível armazenar a chave do provedor como Docker Secret."
        fi
    fi
    unset llm_api_key

    echo -e "XXX\n58\nGERANDO STACKS ISOLADAS... \nXXX"
    cd
    cd
    cat >"${terminal_stack}.yaml" <<EOL

version: "3.7"
services:
  $terminal_service:
    image: $terminal_image
    hostname: $terminal_service
    command:
      - -p
      - "7681"
      - -b
      - /terminal
      - -a
      - -W
      - -O
      - -P
      - "10"
      - -m
      - "1"
      - /usr/local/bin/setupmno-terminal-menu
    environment:
      - LANG=C.UTF-8
      - LC_ALL=C.UTF-8
      - TERM=xterm-256color
      - ADMIN_PASSWORD_FILE=/run/secrets/admin_password
      - SETUPMNO_CONTROL_PREFIX=$nome_app
      - SETUPMNO_CONTROL_IMAGE=$control_image
      - SETUPMNO_CONTROL_WEB_SERVICE=${web_stack}_${web_service}
      - SETUPMNO_CONTROL_TERMINAL_SERVICE=${terminal_stack}_${terminal_service}
      - SETUPMNO_CONTROL_AGENT_SERVICE=${agent_stack}_${agent_service}
      - SETUPMNO_CONTROL_ASSISTANT_STACK=$assistant_stack
      - SETUPMNO_CONTROL_ASSISTANT_COMPONENT=$assistant_service
      - SETUPMNO_CONTROL_STACK_MANAGER=$control_stack_manager
      - SETUPMNO_CONTROL_PORTAINER_CREDENTIALS=/root/dados_portainer/dados_portainer
      - SETUPMNO_CONTROL_AGENT_SECRET=$agent_secret
      - SETUPMNO_CONTROL_ADMIN_SECRET=$admin_secret
      - SETUPMNO_CONTROL_ADMIN_USERNAME=$usuario_control
      - SETUPMNO_CONTROL_PLAN=$CONTROL_PLAN
    networks:
      - interna
    volumes:
      - /root:/root
      - /tmp:/tmp
      - /usr/bin/bash:/usr/bin/bash:ro
      - /var/run/docker.sock:/var/run/docker.sock
      - /etc/localtime:/etc/localtime:ro
    secrets:
      - source: $admin_secret
        target: admin_password
    healthcheck:
      test:
        - CMD
        - curl
        - -fsS
        - http://127.0.0.1:7681/terminal/
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 15s
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

networks:
  interna:
    external: true

secrets:
  $admin_secret:
    external: true
EOL

    cat >"${agent_stack}.yaml" <<EOL

version: "3.7"
services:
  $agent_service:
    image: $control_image
    hostname: $agent_service
    read_only: true
    cap_drop:
      - ALL
    environment:
      - MODE=agent
      - HEALTHCHECK_URL=http://127.0.0.1:9090/health
      - AGENT_TOKEN_FILE=/run/secrets/$agent_secret
      - SETUP_STATE_DIR=/runtime-control
      - HOST_DISK_PATH=/runtime-control
    networks:
      - interna
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - /proc:/host/proc:ro
      - /root/SetupLowCodeMno/.control:/runtime-control:ro
    secrets:
      - $agent_secret
    healthcheck:
      test:
        - CMD
        - /setupmno-control
        - healthcheck
      interval: 30s
      timeout: 5s
      retries: 5
      start_period: 60s
    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
        - node.role == manager
      resources:
        limits:
          cpus: "0.25"
          memory: 128M

networks:
  interna:
    external: true

secrets:
  $agent_secret:
    external: true
EOL

    if [ "$assistant_has_llm" = "true" ]; then
        cat >"${assistant_stack}.yaml" <<EOL

version: "3.7"
services:
  $assistant_service:
    image: $control_image
    hostname: $assistant_service
    user: "65532:65532"
    read_only: true
    cap_drop:
      - ALL
    environment:
      - MODE=assistant
      - HEALTHCHECK_URL=http://127.0.0.1:7070/health
      - ASSISTANT_PROVIDER=$assistant_mode
      - ASSISTANT_MODEL=$assistant_model
      - ASSISTANT_BASE_URL=$assistant_base_url
      - KNOWLEDGE_PACKAGE_DIR=/knowledge-package
      - RETRIEVAL_SHADOW_ENABLED=true
      - RETRIEVAL_INSPECTION_ENABLED=true
      - RETRIEVAL_PROMPT_ENABLED=true
      - BLUEPRINT_HOMOLOGATION_ENABLED=true
      - AGENT_TOKEN_FILE=/run/secrets/$agent_secret
      - AGENT_URL=http://${agent_stack}_${agent_service}:9090
EOL
        if [ "$assistant_external" = "true" ]; then
            cat >>"${assistant_stack}.yaml" <<EOL
      - LLM_API_KEY_FILE=/run/secrets/llm_api_key
EOL
        fi
        cat >>"${assistant_stack}.yaml" <<EOL
    networks:
      - interna
    secrets:
      - $agent_secret
EOL
        if [ "$assistant_external" = "true" ]; then
            cat >>"${assistant_stack}.yaml" <<EOL
      - source: $llm_secret
        target: llm_api_key
EOL
        fi
        cat >>"${assistant_stack}.yaml" <<EOL
    healthcheck:
      test:
        - CMD
        - /setupmno-control
        - healthcheck
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 15s
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

networks:
  interna:
    external: true

secrets:
  $agent_secret:
    external: true
EOL
        if [ "$assistant_external" = "true" ]; then
            cat >>"${assistant_stack}.yaml" <<EOL
  $llm_secret:
    external: true
EOL
        fi
    fi

    cat >"${web_stack}.yaml" <<EOL

version: "3.7"
services:
  $web_service:
    image: $control_image
    hostname: $web_service
    user: "65532:65532"
    read_only: true
    cap_drop:
      - ALL
    environment:
      - MODE=web
      - APP_VERSION=$CONTROL_VERSION
      - ADMIN_USERNAME=$usuario_control
      - ADMIN_PASSWORD_FILE=/run/secrets/admin_password
      - AGENT_TOKEN_FILE=/run/secrets/$agent_secret
      - AGENT_URL=http://${agent_stack}_${agent_service}:9090
      - TERMINAL_URL=http://${terminal_stack}_${terminal_service}:7681
      - ASSISTANT_MODE=$assistant_mode
      - ASSISTANT_MODEL=$assistant_model
      - ASSISTANT_URL=$assistant_internal_url
      - SETUPMNO_PLAN=$CONTROL_PLAN
      - SETUPMNO_INSTALL_TYPE=$INSTALL_TYPE
      - FEEDBACK_STORE_PATH=/feedback/feedback.json
      - AUDIT_STORE_PATH=/audit/audit.json
      - COOKIE_SECURE=true
      - ACCESS_JWT_REQUIRED=$access_jwt_required
      - ACCESS_TEAM_DOMAIN=$access_team_domain
      - ACCESS_POLICY_AUD=$access_app_aud
      - ACCESS_ALLOWED_EMAIL=$access_email
      - ACCESS_MFA_REQUIRED=$access_mfa_required
    networks:
      - externa
      - interna
    secrets:
      - source: $admin_secret
        target: admin_password
      - $agent_secret
    volumes:
      - feedback_data:/feedback
      - audit_data:/audit
    healthcheck:
      test:
        - CMD
        - /setupmno-control
        - healthcheck
      interval: 30s
      timeout: 5s
      retries: 5
      start_period: 10s
    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
        - node.role == manager
      resources:
        limits:
          cpus: "0.50"
          memory: 192M
EOL

    if [ "$INSTALL_TYPE" = "TRADICIONAL" ]; then
        cat >>"${web_stack}.yaml" <<EOL
      labels:
      - traefik.enable=true
      - traefik.docker.network=externa
      - traefik.http.routers.$web_service.rule=Host(\`$url_control\`)
      - traefik.http.routers.$web_service.entrypoints=websecure
      - traefik.http.routers.$web_service.priority=1
      - traefik.http.routers.$web_service.tls.certresolver=letsencryptresolver
      - traefik.http.routers.$web_service.tls=true
      - traefik.http.routers.$web_service.service=$web_service
      - traefik.http.services.$web_service.loadbalancer.server.port=8080
EOL
    fi

    cat >>"${web_stack}.yaml" <<EOL

networks:
  externa:
    external: true
  interna:
    external: true

secrets:
  $admin_secret:
    external: true
  $agent_secret:
    external: true

volumes:
  feedback_data:
  audit_data:
EOL

    stack_files=("${terminal_stack}.yaml" "${agent_stack}.yaml")
    if [ "$assistant_has_llm" = "true" ]; then
        stack_files+=("${assistant_stack}.yaml")
    fi
    stack_files+=("${web_stack}.yaml")
    for stack_file in "${stack_files[@]}"; do
        if ! docker stack config -c "/root/$stack_file" >"$work_dir/validated-$stack_file" 2>>"$install_log"; then
            {
                echo "O YAML '$stack_file' é inválido."
                echo
                tail -n 20 "$install_log"
            } >"$error_file"
            echo -e "XXX\n100\nERRO NO YAML DAS STACKS\nXXX"
            exit 50
        fi
    done

    if [ "$INSTALL_TYPE" = "CLOUDFLARE_TUNNEL" ] ||
       { [ "$INSTALL_TYPE" = "TRADICIONAL" ] && [ "$criar_dns" = "0" ]; }; then
        echo -e "XXX\n67\nCONFIGURANDO DNS DE FORMA IDEMPOTENTE... \nXXX"
        dns_lookup="$work_dir/dns-lookup.json"
        dns_response="$work_dir/dns-response.json"
        if [ "$INSTALL_TYPE" = "CLOUDFLARE_TUNNEL" ]; then
            dns_content="${TUNNEL_ID}.cfargotunnel.com"
            dns_proxied="true"
        else
            DOMINIO_PRINCIPAL=$(echo "$url_control" | cut -d'.' -f2-)
            [ -n "$nome_servidor" ] || nome_servidor=$(hostname -I | awk '{print $1}')
            dns_content="${nome_servidor}.${DOMINIO_PRINCIPAL}"
            dns_proxied="false"
        fi
        dns_payload=$(jq -nc \
            --arg name "$url_control" \
            --arg content "$dns_content" \
            --argjson proxied "$dns_proxied" \
            '{type:"CNAME",name:$name,content:$content,ttl:1,proxied:$proxied}')
        if ! curl -sS \
            --connect-timeout "$CLOUDFLARE_CONNECT_TIMEOUT" \
            --max-time "$CLOUDFLARE_MAX_TIME" \
            --get \
            "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records" \
            -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
            --data-urlencode "name=$url_control" >"$dns_lookup" 2>>"$install_log"; then
            fail_install 60 "ERRO AO CONSULTAR DNS" "Falha ao consultar o DNS $url_control no Cloudflare."
        fi
        dns_record_id=$(jq -r '.result[0].id // empty' "$dns_lookup")
        dns_record_type=$(jq -r '.result[0].type // empty' "$dns_lookup")
        if [ -n "$dns_record_id" ] && [ "$dns_record_type" != "CNAME" ]; then
            fail_install 61 "CONFLITO DE REGISTRO DNS" "Já existe um registro $dns_record_type para $url_control."
        fi
        if [ -n "$dns_record_id" ]; then
            dns_method="PUT"
            dns_url="https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records/${dns_record_id}"
        else
            dns_method="POST"
            dns_url="https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records"
        fi
        if ! curl -sS \
            --connect-timeout "$CLOUDFLARE_CONNECT_TIMEOUT" \
            --max-time "$CLOUDFLARE_MAX_TIME" \
            -X "$dns_method" "$dns_url" \
            -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
            -H "Content-Type: application/json" \
            --data "$dns_payload" >"$dns_response" 2>>"$install_log" ||
           [ "$(jq -r '.success // false' "$dns_response")" != "true" ]; then
            dns_error=$(jq -r '[.errors[]?.message] | join("; ")' "$dns_response" 2>/dev/null)
            fail_install 62 "ERRO AO CONFIGURAR DNS" "Cloudflare recusou o CNAME: ${dns_error:-resposta inválida da API}."
        fi
        echo "DNS confirmado: $url_control -> $dns_content" >>"$install_log"
    fi

    if [ "$INSTALL_TYPE" = "CLOUDFLARE_TUNNEL" ]; then
        echo -e "XXX\n73\nATUALIZANDO ROTA DO CLOUDFLARE TUNNEL... \nXXX"
        tunnel_raw="$work_dir/tunnel-raw.json"
        tunnel_payload="$work_dir/tunnel-payload.json"
        tunnel_response="$work_dir/tunnel-response.json"
        if ! curl -sS \
            --connect-timeout "$CLOUDFLARE_CONNECT_TIMEOUT" \
            --max-time "$CLOUDFLARE_MAX_TIME" \
            -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
            "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/cfd_tunnel/$TUNNEL_ID/configurations" \
            >"$tunnel_raw" 2>>"$install_log" ||
           [ "$(jq -r '.success // false' "$tunnel_raw")" != "true" ]; then
            fail_install 70 "ERRO AO CONSULTAR TUNNEL" "Não foi possível obter a configuração atual do Cloudflare Tunnel."
        fi
        tunnel_original_payload="$work_dir/tunnel-original-payload.json"
        if ! jq '{config:.result.config}' "$tunnel_raw" >"$tunnel_original_payload" 2>>"$install_log"; then
            fail_install 71 "ERRO AO PREPARAR ROLLBACK" "Falha ao preservar a configuração anterior do Cloudflare Tunnel."
        fi
        if ! build_control_tunnel_route_payload "$tunnel_raw" "$tunnel_payload" \
            "$url_control" "http://${web_stack}_${web_service}:8080" \
            "$access_jwt_required" "$access_team_name" "$access_app_aud" \
            2>>"$install_log"; then
            fail_install 71 "ERRO AO PREPARAR ROTA" "Falha ao preparar a nova rota do Cloudflare Tunnel."
        fi
        if ! curl -sS \
            --connect-timeout "$CLOUDFLARE_CONNECT_TIMEOUT" \
            --max-time "$CLOUDFLARE_MAX_TIME" \
            -X PUT \
            "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/cfd_tunnel/$TUNNEL_ID/configurations" \
            -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
            -H "Content-Type: application/json" \
            --data-binary @"$tunnel_payload" >"$tunnel_response" 2>>"$install_log" ||
           [ "$(jq -r '.success // false' "$tunnel_response")" != "true" ]; then
            tunnel_error=$(jq -r '[.errors[]?.message] | join("; ")' "$tunnel_response" 2>/dev/null)
            fail_install 72 "ERRO AO ATUALIZAR TUNNEL" "Cloudflare recusou a rota: ${tunnel_error:-resposta inválida da API}."
        fi
        tunnel_updated="true"
        echo "Rota confirmada: $url_control -> http://${web_stack}_${web_service}:8080" >>"$install_log"
    fi

    if [ "$assistant_has_llm" = "false" ]; then
        echo -e "XXX\n80\nPREPARANDO DEPLOY DAS TRÊS STACKS... \nXXX"
    else
        echo -e "XXX\n80\nPREPARANDO DEPLOY DAS QUATRO STACKS... \nXXX"
    fi
    if [ "$criar_portainer" = "0" ]; then
        dados_file="$HOME/dados_portainer/dados_portainer"
        [ -f "$dados_file" ] ||
            fail_install 80 "CREDENCIAIS DO PORTAINER NÃO ENCONTRADAS" "Arquivo não encontrado: $dados_file"
        PORTAINER_URL=$(grep "Dominio do portainer:" "$dados_file" | cut -d':' -f2- | xargs)
        ADMIN_USERNAME=$(grep "Usuario:" "$dados_file" | cut -d':' -f2- | xargs)
        ADMIN_PASSWORD=$(grep "Senha:" "$dados_file" | cut -d':' -f2- | xargs)
        [ -n "$PORTAINER_URL" ] && [ -n "$ADMIN_USERNAME" ] && [ -n "$ADMIN_PASSWORD" ] ||
            fail_install 81 "CREDENCIAIS DO PORTAINER INVÁLIDAS" "Domínio, usuário ou senha do Portainer não encontrado."

        auth_payload="$work_dir/portainer-auth-payload.json"
        auth_response="$work_dir/portainer-auth.json"
        if ! jq -nc --arg username "$ADMIN_USERNAME" --arg password "$ADMIN_PASSWORD" \
            '{username:$username,password:$password}' >"$auth_payload"; then
            fail_install 82 "ERRO AO PREPARAR AUTENTICAÇÃO" "Não foi possível preparar a autenticação segura do Portainer."
        fi
        if ! curl -sk -X POST "https://$PORTAINER_URL/api/auth" \
            -H "Content-Type: application/json" \
            --data-binary @"$auth_payload" \
            >"$auth_response" 2>>"$install_log"; then
            fail_install 82 "ERRO DE COMUNICAÇÃO COM PORTAINER" "Não foi possível acessar a API do Portainer."
        fi
        unset ADMIN_PASSWORD
        TOKEN=$(jq -r '.jwt // empty' "$auth_response")
        [ -n "$TOKEN" ] ||
            fail_install 83 "ERRO DE AUTENTICAÇÃO NO PORTAINER" "O Portainer não retornou token válido."
        endpoint_response="$work_dir/portainer-endpoints.json"
        if ! curl -sk "https://$PORTAINER_URL/api/endpoints" \
            -H "Authorization: Bearer $TOKEN" >"$endpoint_response" 2>>"$install_log"; then
            fail_install 84 "ERRO AO CONSULTAR ENDPOINT" "Falha ao consultar endpoints do Portainer."
        fi
        ENDPOINT_ID=$(jq -r '.[0].Id // empty' "$endpoint_response")
        [ -n "$ENDPOINT_ID" ] ||
            fail_install 85 "ENDPOINT NÃO ENCONTRADO" "Nenhum endpoint foi encontrado no Portainer."
        swarm_response="$work_dir/portainer-swarm.json"
        if ! curl -sk "https://$PORTAINER_URL/api/endpoints/$ENDPOINT_ID/docker/swarm" \
            -H "Authorization: Bearer $TOKEN" >"$swarm_response" 2>>"$install_log"; then
            fail_install 86 "ERRO AO CONSULTAR SWARM" "Falha ao consultar o Swarm pelo Portainer."
        fi
        SWARM_ID=$(jq -r '.ID // empty' "$swarm_response")
        [ -n "$SWARM_ID" ] ||
            fail_install 87 "SWARM NÃO ENCONTRADO" "O Portainer não retornou um Swarm ID válido."

        for image_ref in "$control_image" "$terminal_image"; do
            image_encoded=$(printf '%s' "$image_ref" | jq -sRr @uri)
            image_http=$(curl -sk -o "$work_dir/image-check.json" -w "%{http_code}" \
                "https://$PORTAINER_URL/api/endpoints/$ENDPOINT_ID/docker/images/$image_encoded/json" \
                -H "Authorization: Bearer $TOKEN" 2>>"$install_log")
            if [ "$image_http" != "200" ]; then
                fail_install 88 "IMAGEM LOCAL NÃO VISÍVEL NO PORTAINER" \
                    "A imagem '$image_ref' existe no Docker, mas não está visível no endpoint selecionado do Portainer (HTTP $image_http). Nenhum upload foi tentado."
            fi
        done

        create_portainer_stack() {
            local stack_name="$1" stack_file="$2" response_file="$work_dir/portainer-${1}.json" http_code
            http_code=$(curl -sk -o "$response_file" -w "%{http_code}" -X POST \
                -H "Authorization: Bearer $TOKEN" \
                -F "Name=$stack_name" \
                -F "file=@/root/$stack_file" \
                -F "SwarmID=$SWARM_ID" \
                -F "endpointId=$ENDPOINT_ID" \
                "https://$PORTAINER_URL/api/stacks/create/swarm/file" 2>>"$install_log")
            if ! [[ "$http_code" =~ ^[0-9]{3}$ ]] ||
               [ "$http_code" -lt 200 ] || [ "$http_code" -ge 300 ]; then
                portainer_error=$(jq -r '.message // empty' "$response_file" 2>/dev/null)
                [ -n "$portainer_error" ] || portainer_error=$(head -c 1500 "$response_file")
                printf 'Portainer recusou a stack %s (HTTP %s): %s\n' \
                    "$stack_name" "${http_code:-indisponível}" "${portainer_error:-sem detalhes}" >"$error_file"
                return 1
            fi
            echo "Stack criada no Portainer: $stack_name (HTTP $http_code)" >>"$install_log"
        }

        echo -e "XXX\n87\nCRIANDO TERMINAL NO PORTAINER... \nXXX"
        create_portainer_stack "$terminal_stack" "${terminal_stack}.yaml" ||
            fail_install 89 "ERRO NA STACK DO TERMINAL" "$(cat "$error_file")"
        echo -e "XXX\n90\nCRIANDO AGENTE NO PORTAINER... \nXXX"
        create_portainer_stack "$agent_stack" "${agent_stack}.yaml" ||
            fail_install 90 "ERRO NA STACK DO AGENTE" "$(cat "$error_file")"
        if [ "$assistant_has_llm" = "true" ]; then
            echo -e "XXX\n92\nCRIANDO ASSISTENTE NO PORTAINER... \nXXX"
            create_portainer_stack "$assistant_stack" "${assistant_stack}.yaml" ||
                fail_install 91 "ERRO NA STACK DO ASSISTENTE" "$(cat "$error_file")"
        fi
        echo -e "XXX\n93\nCRIANDO PAINEL NO PORTAINER... \nXXX"
        create_portainer_stack "$web_stack" "${web_stack}.yaml" ||
            fail_install 92 "ERRO NA STACK DO PAINEL" "$(cat "$error_file")"
    else
        echo -e "XXX\n87\nCRIANDO TERMINAL NO DOCKER... \nXXX"
        docker stack deploy --prune --resolve-image never \
            -c "/root/${terminal_stack}.yaml" "$terminal_stack" >>"$install_log" 2>&1 ||
            fail_install 92 "ERRO NA STACK DO TERMINAL" "Falha ao publicar a stack do terminal no Docker."
        echo -e "XXX\n90\nCRIANDO AGENTE NO DOCKER... \nXXX"
        docker stack deploy --prune --resolve-image never \
            -c "/root/${agent_stack}.yaml" "$agent_stack" >>"$install_log" 2>&1 ||
            fail_install 93 "ERRO NA STACK DO AGENTE" "Falha ao publicar a stack do agente no Docker."
        if [ "$assistant_has_llm" = "true" ]; then
            echo -e "XXX\n92\nCRIANDO ASSISTENTE NO DOCKER... \nXXX"
            docker stack deploy --prune --resolve-image never \
                -c "/root/${assistant_stack}.yaml" "$assistant_stack" >>"$install_log" 2>&1 ||
                fail_install 94 "ERRO NA STACK DO ASSISTENTE" "Falha ao publicar a stack do assistente no Docker."
        fi
        echo -e "XXX\n93\nCRIANDO PAINEL NO DOCKER... \nXXX"
        docker stack deploy --prune --resolve-image never \
            -c "/root/${web_stack}.yaml" "$web_stack" >>"$install_log" 2>&1 ||
            fail_install 95 "ERRO NA STACK DO PAINEL" "Falha ao publicar a stack do painel no Docker."
    fi

    echo -e "XXX\n96\nAGUARDANDO OS SERVIÇOS... \nXXX"
    expected_services=(
        "${terminal_stack}_${terminal_service}"
        "${agent_stack}_${agent_service}"
    )
    if [ "$assistant_has_llm" = "true" ]; then
        expected_services+=("${assistant_stack}_${assistant_service}")
    fi
    expected_services+=("${web_stack}_${web_service}")
    for service_name in "${expected_services[@]}"; do
        ready="false"
        for _ in $(seq 1 100); do
            replicas=$(docker service ls --filter "name=$service_name" \
                --format '{{.Replicas}}' 2>>"$install_log" | head -n1)
            if [ "$replicas" = "1/1" ]; then
                ready="true"
                break
            fi
            sleep 3
        done
        if [ "$ready" != "true" ]; then
            {
                echo "O serviço não atingiu 1/1 réplica: $service_name"
                echo
                docker service ps "$service_name" --no-trunc \
                    --format 'Estado: {{.CurrentState}} | Erro: {{.Error}}' 2>/dev/null | head -n 8
            } >"$error_file"
            echo -e "XXX\n100\nSERVIÇO NÃO FICOU PRONTO\nXXX"
            exit 96
        fi
        echo "Serviço confirmado: $service_name com 1/1 réplica." >>"$install_log"
    done

    echo -e "XXX\n100\nCONTROL CENTER INSTALADO COM SUCESSO\nXXX"
} 2>>"$install_log" | whiptail --title "SETUP MNO CONTROL CENTER" --gauge \
    "Preparando o painel..." 8 78 0
install_status=${PIPESTATUS[0]}
unset llm_api_key

if [ "$install_status" -ne 0 ]; then
    error_detail=$(cat "$error_file" 2>/dev/null)
    [ -n "$error_detail" ] || error_detail=$(tail -n 20 "$install_log" 2>/dev/null)
    whiptail --title "ERRO NA INSTALAÇÃO DO CONTROL CENTER" --msgbox \
        "A instalação foi interrompida com segurança.\n\n$error_detail\n\nLog completo: $install_log" \
        24 94
    exit "$install_status"
fi

if [ "$INSTALL_TYPE" = "CLOUDFLARE_TUNNEL" ] && [ "$access_mfa_enabled" = "true" ]; then
    write_control_mfa_state true true false control-installed || {
        msg "O Control Center foi instalado e o MFA está ativo, mas o estado persistente não pôde ser atualizado. Execute CONFIGURAR MFA CONTROL CENTER antes da próxima atualização."
        exit 1
    }
else
    write_control_mfa_state false false false control-installed || {
        msg "O Control Center foi instalado, mas a preferência sem MFA não pôde ser registrada. Execute novamente o Setup MNO antes da próxima atualização."
        exit 1
    }
fi

manual_dns_note=""
access_next_step=""
if [ "$INSTALL_TYPE" = "TRADICIONAL" ] && [ "$criar_dns" = "1" ]; then
    manual_dns_note="\n\nDNS manual: aponte $url_control para o servidor antes de acessar."
fi
if [ "$INSTALL_TYPE" = "CLOUDFLARE_TUNNEL" ]; then
    if [ "$access_mfa_enabled" = "true" ]; then
        access_next_step="\n\nPRIMEIRO ACESSO COM MFA:\n1. Abra https://${access_team_name}.cloudflareaccess.com/AddMfaDevice\n2. Entre com $access_email\n3. Cadastre seu aplicativo autenticador pelo QR Code\n4. Depois abra https://$url_control"
    else
        access_next_step="\n\nMODO ORIGINAL SEM MFA:\nAbra https://$url_control e use o usuário e a senha locais do painel. O Terminal Remoto continua disponível pelo mesmo fluxo do Control Center. Para ativar MFA depois, use CONFIGURAR MFA CONTROL CENTER no menu do Setup MNO."
    fi
fi

whiptail --title "SETUP MNO CONTROL CENTER" --msgbox \
    "Control Center instalado com sucesso.\n\nAcesse: https://$url_control\nUsuário: $usuario_control\nSenha: definida durante a instalação\nCloudflare Access: $access_summary\nAssistente: $assistant_label\n\nStacks:\n- $web_stack\n- $agent_stack\n- $terminal_stack$([ "$assistant_has_llm" = "true" ] && printf '\\n- %s' "$assistant_stack")\n\nAs imagens foram construídas localmente e validadas sem upload pelo Cloudflare.$access_next_step$manual_dns_note" \
    24 94

exit 0

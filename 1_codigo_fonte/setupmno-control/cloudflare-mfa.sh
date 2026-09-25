#!/usr/bin/bash
# Assistente autenticado do Cloudflare MFA. Este arquivo é carregado somente do
# control-source.tar.gz validado pelo manifesto runtime do Setup MNO.

CF_MFA_API="https://api.cloudflare.com/client/v4"
CF_MFA_LOGIN_HEADER="Acesso seguro ao Setup MNO"
CF_MFA_LOGIN_FOOTER="Digite o código de 6 dígitos gerado pelo seu aplicativo autenticador."
CF_MFA_LOGIN_LOGO="https://ativa2.manualnegocioonline.com.br/setup-mno-logo.svg"
CF_MFA_LOGIN_BACKGROUND="#07090d"
CF_MFA_LOGIN_TEXT="#f4f6f8"

cf_mfa_api() {
    local method="$1" path="$2" output="$3" payload="${4:-}"
    local -a args=(curl -sS --connect-timeout "${CLOUDFLARE_CONNECT_TIMEOUT:-10}"
        --max-time "${CLOUDFLARE_MAX_TIME:-30}" -X "$method"
        -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN")
    [ -z "$payload" ] || args+=(-H "Content-Type: application/json" --data-binary "@$payload")
    "${args[@]}" "$CF_MFA_API$path" >"$output"
}

cf_mfa_error() {
    jq -r '[.errors[]?.message] | map(select(length > 0)) | join("; ")' "$1" 2>/dev/null |
        tr '\r\n' ' ' | cut -c1-300
}

show_cloudflare_token_permissions() {
    whiptail --title "PERMISSÕES DO TOKEN CLOUDFLARE" --msgbox \
        "Para automatizar o MFA, o token usado pelo Setup MNO precisa destas 7 permissões:\n\nPERMISSÕES ANTIGAS — MANTENHA\n1. Conta > Configurações da conta > Editar\n2. Conta > Cloudflare Tunnel > Editar\n3. Zona > DNS > Editar\n\nPERMISSÕES MFA — ADICIONE\n4. Conta > Access: Apps and Policies > Editar\n5. Conta > Access: Organizations, Identity Providers, and Groups > Editar\n6. Conta > Access: Organizations, Identity Providers, and Groups > Revogar\n7. Conta > Access: Audit Logs > Ler\n\nAs duas últimas permissões são verificadas em toda ativação e reativação. A leitura de auditoria é testada diretamente; a capacidade de revogação é comprovada sem remover usuários, aplicativos ou políticas. O Setup só continuará quando todas as operações necessárias forem autorizadas.\n\nRestrinja Recursos da conta e Recursos de zona à conta e ao domínio usados pelo Setup MNO. Edite o token atual em Meu perfil > Tokens de API ou crie outro token personalizado." \
        25 96 1>&2
}

validate_cloudflare_mfa_revoke_capability() {
    local work="$1" response detail code
    response="$work/token-revogacao.json"
    if ! cf_mfa_api DELETE \
        "/accounts/$CLOUDFLARE_ACCOUNT_ID/access/users/00000000-0000-4000-8000-000000000000/mfa_authenticators/00000000-0000-4000-8000-000000000000" \
        "$response" 2>>"${CF_MFA_LOG:-/dev/null}"; then
        CF_MFA_VALIDATION_ERROR="Falha ao comprovar a capacidade de revogação do token. Permissão necessária: Access: Organizations, Identity Providers, and Groups > Revogar."
        return 1
    fi
    code=$(jq -r '.errors[0].code // empty' "$response" 2>/dev/null)
    if [ "$(jq -r '.success // false' "$response" 2>/dev/null)" = "true" ] ||
       [ "$code" = "12167" ]; then
        return 0
    fi
    detail=$(cf_mfa_error "$response")
    CF_MFA_VALIDATION_ERROR="Falha ao comprovar a capacidade de revogação do token. Permissão necessária: Access: Organizations, Identity Providers, and Groups > Revogar.${detail:+\n\nCloudflare: $detail}"
    return 1
}

validate_cloudflare_mfa_token() {
    local candidate="$1" work="$2" item path permission response detail old_token
    [[ "$candidate" =~ ^[A-Za-z0-9_-]{20,256}$ ]] || {
        CF_MFA_VALIDATION_ERROR="O token informado não possui um formato válido."
        return 1
    }
    old_token="${CLOUDFLARE_API_TOKEN:-}"
    CLOUDFLARE_API_TOKEN="$candidate"
    whiptail --title "VALIDANDO TOKEN CLOUDFLARE" --infobox \
        "Verificando validade, conta, Tunnel, DNS, Access, auditoria e revogação..." 8 82
    while IFS='|' read -r item path permission; do
        response="$work/token-${item}.json"
        if ! cf_mfa_api GET "$path" "$response" 2>>"${CF_MFA_LOG:-/dev/null}" ||
           [ "$(jq -r '.success // false' "$response" 2>/dev/null)" != "true" ]; then
            detail=$(cf_mfa_error "$response")
            CF_MFA_VALIDATION_ERROR="Falha em $item. Permissão necessária: $permission.${detail:+\n\nCloudflare: $detail}"
            CLOUDFLARE_API_TOKEN="$old_token"
            return 1
        fi
    done <<EOF
validade|/user/tokens/verify|token ativo
conta|/accounts/$CLOUDFLARE_ACCOUNT_ID|Configurações da conta > Editar
tunnel|/accounts/$CLOUDFLARE_ACCOUNT_ID/cfd_tunnel/$TUNNEL_ID/configurations|Cloudflare Tunnel > Editar
dns|/zones/$CLOUDFLARE_ZONE_ID/dns_records?per_page=1|DNS > Editar
access|/accounts/$CLOUDFLARE_ACCOUNT_ID/access/apps?per_page=100|Access: Apps and Policies > Editar
organizacao|/accounts/$CLOUDFLARE_ACCOUNT_ID/access/organizations|Access: Organizations, Identity Providers, and Groups > Editar
identidades|/accounts/$CLOUDFLARE_ACCOUNT_ID/access/identity_providers|Access: Organizations, Identity Providers, and Groups > Editar
auditoria|/accounts/$CLOUDFLARE_ACCOUNT_ID/access/logs/access_requests?per_page=1|Access: Audit Logs > Ler
EOF
    if [ "$(jq -r '.result.status // empty' "$work/token-validade.json")" != "active" ]; then
        CF_MFA_VALIDATION_ERROR="O token existe, mas não está ativo."
        CLOUDFLARE_API_TOKEN="$old_token"
        return 1
    fi
    if ! validate_cloudflare_mfa_revoke_capability "$work"; then
        CLOUDFLARE_API_TOKEN="$old_token"
        return 1
    fi
    CLOUDFLARE_API_TOKEN="$candidate"
    return 0
}

resolve_cloudflare_mfa_server_name() {
    local hint="${1:-}" candidate=""
    if [ -n "$hint" ]; then
        candidate="$hint"
    elif [ -n "${SETUPMNO_SERVER_NAME:-}" ]; then
        candidate="$SETUPMNO_SERVER_NAME"
    elif [ -n "${nome_servidor:-}" ] && ! [[ "$nome_servidor" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        candidate="$nome_servidor"
    elif [ -f /root/.tradicional_config/tradicional_credentials ]; then
        local trad_nome
        trad_nome=$(grep -E "^nome_servidor=" /root/.tradicional_config/tradicional_credentials 2>/dev/null | cut -d"=" -f2- | tr -d "\"'\''")
        if [ -n "$trad_nome" ] && ! [[ "$trad_nome" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            candidate="$trad_nome"
        fi
    fi
    if [ -z "$candidate" ]; then
        local raw_host="${url_control:-${hostname:-}}"
        [ -n "$raw_host" ] && candidate="$raw_host"
    fi
    if [ -z "$candidate" ]; then
        local tf found_h
        for tf in /tmp/tmp.*/token-tunnel.json /tmp/tmp.*/access-migration-tunnel.json /tmp/access-migration-tunnel.json; do
            if [ -f "$tf" ]; then
                found_h=$(jq -r '[.result.config.ingress[]? | select(.service | test("mnoctrl.*-web")) | .hostname][0] // empty' "$tf" 2>/dev/null)
                if [ -n "$found_h" ] && [ "$found_h" != "null" ]; then
                    candidate="$found_h"
                    break
                fi
            fi
        done
    fi
    [ -n "$candidate" ] || return 0
    if [[ "$candidate" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        return 0
    fi
    if [[ "$candidate" == *.* ]]; then
        candidate="${candidate%%.*}"
    fi
    local clean
    clean=$(printf "%s" "$candidate" | sed "y/áàãâéêíóôõúüçÁÀÃÂÉÊÍÓÔÕÚÜÇ/aaaaeeiooouucAAAAEEIOOOUUC/" | LC_ALL=C tr "[:upper:]" "[:lower:]" | LC_ALL=C tr -cd "a-z0-9")
    if [[ "$clean" =~ ^setupmno[a-z0-9]+$ ]] && [ "${#clean}" -gt 8 ]; then
        clean="${clean#setupmno}"
    elif [[ "$clean" =~ ^setup[a-z0-9]+$ ]] && [ "${#clean}" -gt 5 ]; then
        clean="${clean#setup}"
    elif [ "$clean" = "setup" ] || [ "$clean" = "setupmno" ] || [[ "$clean" =~ ^[0-9]+$ ]]; then
        clean=""
    fi
    printf "%s" "$clean"
}

generate_cloudflare_mfa_alias() {
    local email="$1" hint="${2:-${url_control:-${hostname:-}}}"
    local local_part domain base tag effective server_clean
    [[ "$email" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]] || return 1
    local_part=${email%@*}
    domain=${email##*@}
    domain=${domain,,}
    base=${local_part%%+*}
    server_clean=$(resolve_cloudflare_mfa_server_name "$hint")
    if [ -n "$server_clean" ]; then
        tag="$server_clean"
    else
        tag="mno$(date -u +%y%m%d%H%M%S)$(od -An -N2 -tx1 /dev/urandom | tr -d ' \n')"
    fi
    effective="${base}+${tag}@${domain}"
    [ -n "$base" ] && [ "${#base}" -le 40 ] && [ "${#effective}" -le 254 ] || return 1
    printf '%s\n' "$effective"
}

show_cloudflare_mfa_alias_instructions() {
    local original_email="$1" access_email="$2"
    whiptail --title "COPIE O E-MAIL DE ACESSO CLOUDFLARE" --msgbox \
        "CAIXA POSTAL ORIGINAL:\n$original_email\n\nE-MAIL DE ACESSO CLOUDFLARE:\n$access_email\n\nATENÇÃO: na página da Cloudflare, NÃO digite o e-mail original. Preencha exatamente o alias completo acima (com o sinal de + e o nome do servidor). O código chegará na caixa postal original e, depois da confirmação, será exibido o novo QR Code." \
        20 96 1>&2
}

prepare_cloudflare_mfa_enrollment_email() {
    local email="$1" mode="${2:-reactivation}" hint="${3:-${url_control:-${hostname:-}}}"
    local state_file="${CONTROL_MFA_STATE_FILE:-}" source="" choice
    local domain effective replacement status
    [[ "$email" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]] || return 1
    if [ "$mode" = "initial" ]; then
        effective=$(generate_cloudflare_mfa_alias "$email" "$hint") || {
            whiptail --title "NÃO FOI POSSÍVEL CRIAR O ALIAS" --msgbox \
                "Use uma caixa postal real que aceite endereços com +alias. Gmail é recomendado para garantir o recebimento do código e a criação de um novo QR Code." \
                12 86 1>&2
            return 130
        }
        show_cloudflare_mfa_alias_instructions "$email" "$effective"
        printf '%s\n' "$effective"
        return 0
    fi
    [ "$mode" = "reactivation" ] || return 1
    if [ -f "$state_file" ] && [ ! -L "$state_file" ] &&
       [ "$(stat -c '%s' "$state_file" 2>/dev/null || printf '99999')" -le 2048 ]; then
        source=$(jq -r '.source // empty' "$state_file" 2>/dev/null)
    fi
    [ "$source" = "menu-disabled" ] || {
        printf '%s\n' "$email"
        return 0
    }
    domain=${email##*@}
    domain=${domain,,}
    if [ "$domain" = "gmail.com" ] || [ "$domain" = "googlemail.com" ]; then
        choice=$(whiptail --title "REATIVAÇÃO DO MFA" --default-item "NOVO_QR" --menu \
            "Para gerar outro QR, o Setup criará um E-MAIL DE ACESSO com o nome do servidor. Ele usa a mesma caixa Gmail, mas na Cloudflare você NÃO deve digitar o e-mail original: deverá preencher o alias completo que será mostrado:" \
            20 96 4 \
            "NOVO_QR" "Mesmo Gmail: gerar alias com o servidor e novo QR" \
            "REUTILIZAR" "Reutilizar o cadastro e o código do autenticador anterior" \
            "OUTRO_EMAIL" "Informar outro e-mail para uma identidade nova" \
            "CANCELAR" "Voltar sem alterar Cloudflare ou Control Center" \
            3>&1 1>&2 2>&3) || return 130
    else
        choice=$(whiptail --title "REATIVAÇÃO DO MFA" --default-item "OUTRO_EMAIL" --menu \
            "Este Control Center já teve MFA. A API pública da Cloudflare não lista os identificadores dos autenticadores independentes. Para garantir um novo QR, use outro e-mail; ou reutilize o código anterior:" \
            19 96 3 \
            "OUTRO_EMAIL" "Informar outro e-mail para uma identidade nova" \
            "REUTILIZAR" "Reutilizar o cadastro e o código do autenticador anterior" \
            "CANCELAR" "Voltar sem alterar Cloudflare ou Control Center" \
            3>&1 1>&2 2>&3) || return 130
    fi
    case "$choice" in
        NOVO_QR)
            { [ "$domain" = "gmail.com" ] || [ "$domain" = "googlemail.com" ]; } || return 1
            effective=$(generate_cloudflare_mfa_alias "$email" "${hint:+${hint}$(date -u +%y%m%d%H%M)}") || {
                whiptail --title "ALIAS GMAIL MUITO LONGO" --msgbox \
                    "O endereço informado não comporta um alias seguro. Escolha OUTRO E-MAIL na próxima tentativa." \
                    10 82 1>&2
                return 130
            }
            show_cloudflare_mfa_alias_instructions "$email" "$effective"
            printf '%s\n' "$effective"
            ;;
        REUTILIZAR)
            printf '%s\n' "$email"
            ;;
        OUTRO_EMAIL)
            replacement=$(collect_cloudflare_access_email "NOVA IDENTIDADE DO MFA")
            status=$?
            [ "$status" -eq 0 ] || return 130
            printf '%s\n' "$replacement"
            ;;
        *) return 130 ;;
    esac
}

persist_cloudflare_token_file() {
    local token="$1" credentials="$2" temporary found="false" line directory
    [ -f "$credentials" ] && [ ! -L "$credentials" ] &&
    [ "$(stat -c '%s' "$credentials" 2>/dev/null || echo 99999)" -le 16384 ] || return 1
    directory=$(dirname "$credentials")
    temporary=$(mktemp "$directory/.cloudflare_credentials.tmp.XXXXXX") || return 1
    chmod 0600 "$temporary" || { rm -f "$temporary"; return 1; }
    while IFS= read -r line || [ -n "$line" ]; do
        case "$line" in
            CLOUDFLARE_API_TOKEN=*)
                [ "$found" = "false" ] || { rm -f "$temporary"; return 1; }
                printf 'CLOUDFLARE_API_TOKEN=%s\n' "$token" >>"$temporary"
                found="true"
                ;;
            *) printf '%s\n' "$line" >>"$temporary" ;;
        esac
    done <"$credentials"
    [ "$found" = "true" ] || { rm -f "$temporary"; return 1; }
    mv -f "$temporary" "$credentials" || { rm -f "$temporary"; return 1; }
    CLOUDFLARE_API_TOKEN="$token"
}

persist_cloudflare_token() {
    [ "$CREDENTIALS_FILE" = "/root/.cloudflared_config/cloudflare_credentials" ] || return 1
    persist_cloudflare_token_file "$1" "$CREDENTIALS_FILE"
}

prepare_cloudflare_mfa_token() {
    local work="$1" log="$2" mode="${3:-guided}" choice candidate status
    CF_MFA_LOG="$log"
    if [ "$mode" = "current-first" ] && validate_cloudflare_mfa_token "$CLOUDFLARE_API_TOKEN" "$work"; then
        return 0
    fi
    show_cloudflare_token_permissions
    while true; do
        choice=$(whiptail --title "TOKEN PARA AUTOMAÇÃO DO MFA" --default-item "ATUAL" --menu \
            "Escolha como deseja continuar. Nenhum token novo será salvo antes de passar por todas as validações:" \
            19 94 4 \
            "ATUAL" "Já editei o token atual e adicionei as quatro permissões Access" \
            "NOVO" "Validar e usar outro token da Cloudflare" \
            "INSTRUCOES" "Rever as sete permissões necessárias" \
            "CANCELAR" "Voltar sem alterar credenciais ou Cloudflare" \
            3>&1 1>&2 2>&3) || return 130
        case "$choice" in
            INSTRUCOES) show_cloudflare_token_permissions ;;
            CANCELAR) return 130 ;;
            ATUAL)
                if validate_cloudflare_mfa_token "$CLOUDFLARE_API_TOKEN" "$work"; then
                    msg "Token atual validado com sucesso. Todas as consultas necessárias ao MFA foram autorizadas."
                    return 0
                fi
                msg "$CF_MFA_VALIDATION_ERROR\n\nEdite o token atual e tente novamente ou escolha fornecer outro token."
                ;;
            NOVO)
                while true; do
                    candidate=$(whiptail --title "NOVO TOKEN CLOUDFLARE" --passwordbox \
                        "Cole o novo API Token. Ele não será exibido nem salvo antes da validação completa." \
                        13 86 3>&1 1>&2 2>&3)
                    status=$?
                    [ "$status" -eq 0 ] || break
                    if validate_cloudflare_mfa_token "$candidate" "$work"; then
                        if persist_cloudflare_token "$candidate"; then
                            unset candidate
                            msg "Novo token validado e atualizado com segurança. As demais credenciais do Tunnel foram preservadas."
                            return 0
                        fi
                        unset candidate
                        msg "O token é válido, mas o arquivo de credenciais não pôde ser atualizado atomicamente. O token anterior foi preservado."
                        return 1
                    fi
                    unset candidate
                    msg "$CF_MFA_VALIDATION_ERROR\n\nPressione OK para informar o token novamente."
                done
                ;;
        esac
    done
}

prepare_cloudflare_mfa_deactivation() {
    local work="$1" log="$2" email="$3" status
    prepare_cloudflare_mfa_token "$work" "$log" current-first
    status=$?
    [ "$status" -eq 0 ] || return "$status"
    whiptail --title "DESATIVAR MFA?" --yesno \
        "O aplicativo Access exclusivo do Control Center será removido e o acesso voltará ao modo original: Tunnel direto, login local e Terminal Remoto.\n\nA identidade Zero Trust de $email será preservada, pois excluir o usuário não remove com segurança o TOTP independente e pode deixá-lo órfão. Na próxima reativação, o Setup oferecerá uma identidade nova para garantir outro QR Code ou permitirá reutilizar o autenticador anterior.\n\nDeseja continuar?" \
        21 94 1>&2 || return 130
}

cf_mfa_org_payload() {
    jq --arg header "$CF_MFA_LOGIN_HEADER" --arg footer "$CF_MFA_LOGIN_FOOTER" \
        --arg logo "$CF_MFA_LOGIN_LOGO" --arg background "$CF_MFA_LOGIN_BACKGROUND" \
        --arg text "$CF_MFA_LOGIN_TEXT" '
        def preserve($value; $fallback):
          if (($value | type) == "string" and ($value | length) > 0)
          then $value else $fallback end;
        .result
        | (.login_design // {}) as $design
        | {auth_domain,name,
           mfa_config:((.mfa_config // {}) + {
             allowed_authenticators:(((.mfa_config.allowed_authenticators // []) + ["totp"]) | unique),
             session_duration:(.mfa_config.session_duration // "24h")
           }),
           login_design:{
             header_text:preserve($design.header_text; $header),
             footer_text:preserve($design.footer_text; $footer),
             logo_path:preserve($design.logo_path; $logo),
             background_color:preserve($design.background_color; $background),
             text_color:preserve($design.text_color; $text)
           }}
    ' "$1" >"$2"
}

cf_mfa_org_is_ready() {
    jq -e '
        ((.result.mfa_config.allowed_authenticators // []) | index("totp") != null) and
        ([.result.login_design.header_text, .result.login_design.footer_text,
          .result.login_design.logo_path, .result.login_design.background_color,
          .result.login_design.text_color]
         | all(type == "string" and length > 0))
    ' "$1" >/dev/null 2>&1
}

cf_mfa_launcher_policy_payload() {
    jq -n --arg email "$1" --arg name "Setup MNO - cadastro MFA - $1" --argjson precedence "$2" \
        '{name:$name,decision:"allow",precedence:$precedence,include:[{email:{email:$email}}],exclude:[],require:[]}' >"$3"
}

cf_mfa_save_onboarding_state() {
    local state="$1" active="$2" org_changed="$3" org_rollback="$4" idp="$5"
    local idp_created="$6" app="$7" app_created="$8" launcher_changed="$9"
    local launcher_rollback="${10}" policy="${11}" policy_created="${12}"
    jq -n --argjson active "$active" --argjson orgChanged "$org_changed" \
        --arg org "$org_rollback" --arg idp "$idp" --argjson otpCreated "$idp_created" \
        --arg app "$app" --argjson appCreated "$app_created" \
        --argjson launcherChanged "$launcher_changed" --arg launcherRollback "$launcher_rollback" \
        --arg policy "$policy" --argjson policyCreated "$policy_created" \
        '{active:$active,organizationChanged:$orgChanged,organizationRollback:$org,
          otpIdpId:$idp,otpCreated:$otpCreated,launcherAppId:$app,
          launcherAppCreated:$appCreated,launcherChanged:$launcherChanged,
          launcherRollback:$launcherRollback,launcherPolicyId:$policy,
          launcherPolicyCreated:$policyCreated}' >"$state"
}

rollback_cloudflare_mfa_onboarding() {
    local state="$1" log="$2" app policy idp org launcher response
    [ -s "$state" ] || return 0
    app=$(jq -r '.launcherAppId // empty' "$state")
    policy=$(jq -r '.launcherPolicyId // empty' "$state")
    idp=$(jq -r '.otpIdpId // empty' "$state")
    org=$(jq -r '.organizationRollback // empty' "$state")
    launcher=$(jq -r '.launcherRollback // empty' "$state")
    if [ "$(jq -r '.launcherPolicyCreated // false' "$state")" = "true" ] &&
       [[ "$app" =~ ^[A-Fa-f0-9-]{32,36}$ ]] && [[ "$policy" =~ ^[A-Fa-f0-9-]{32,36}$ ]]; then
        cf_mfa_api DELETE "/accounts/$CLOUDFLARE_ACCOUNT_ID/access/apps/$app/policies/$policy" \
            "${state}.policy-delete" 2>>"$log" || true
    fi
    if [ "$(jq -r '.launcherAppCreated // false' "$state")" = "true" ] &&
       [[ "$app" =~ ^[A-Fa-f0-9-]{32,36}$ ]]; then
        cf_mfa_api DELETE "/accounts/$CLOUDFLARE_ACCOUNT_ID/access/apps/$app" \
            "${state}.app-delete" 2>>"$log" || true
    elif [ "$(jq -r '.launcherChanged // false' "$state")" = "true" ] &&
         [[ "$app" =~ ^[A-Fa-f0-9-]{32,36}$ ]] && [ -s "$launcher" ]; then
        cf_mfa_api PUT "/accounts/$CLOUDFLARE_ACCOUNT_ID/access/apps/$app" \
            "${state}.launcher-rollback" "$launcher" 2>>"$log" || true
    fi
    if [ "$(jq -r '.otpCreated // false' "$state")" = "true" ] &&
       [[ "$idp" =~ ^[A-Fa-f0-9-]{32,36}$ ]]; then
        cf_mfa_api DELETE "/accounts/$CLOUDFLARE_ACCOUNT_ID/access/identity_providers/$idp" \
            "${state}.idp-delete" 2>>"$log" || true
    fi
    if [ "$(jq -r '.organizationChanged // false' "$state")" = "true" ] && [ -s "$org" ]; then
        response="${state}.org-rollback"
        cf_mfa_api PUT "/accounts/$CLOUDFLARE_ACCOUNT_ID/access/organizations" "$response" "$org" \
            2>>"$log" || true
    fi
}

ensure_cloudflare_mfa_onboarding() {
    local work="$1" email="$2" log="$3" state="$4"
    local org org_payload org_response idps idp_payload idp_response otp_id="" otp_created="false"
    local apps launcher_id="" launcher_created="false" launcher_changed="false" launcher_rollback=""
    local policies policy_payload policy_response policy_id="" policy_created="false" precedence
    local org_changed="false" org_rollback="" launcher_payload launcher_response
    org="$work/onboarding-organization.json"
    idps="$work/onboarding-idps.json"
    apps="$work/onboarding-apps.json"
    cf_mfa_save_onboarding_state "$state" false false "" "" false "" false false "" "" false || return 1
    if ! cf_mfa_api GET "/accounts/$CLOUDFLARE_ACCOUNT_ID/access/organizations" "$org" 2>>"$log" ||
       ! cf_mfa_api GET "/accounts/$CLOUDFLARE_ACCOUNT_ID/access/identity_providers" "$idps" 2>>"$log" ||
       ! cf_mfa_api GET "/accounts/$CLOUDFLARE_ACCOUNT_ID/access/apps?per_page=100" "$apps" 2>>"$log" ||
       [ "$(jq -r '.success // false' "$org")" != true ] ||
       [ "$(jq -r '.success // false' "$idps")" != true ] ||
       [ "$(jq -r '.success // false' "$apps")" != true ]; then
        msg "Não foi possível preparar automaticamente o MFA. Confirme as quatro permissões Access do token."
        return 1
    fi
    if ! cf_mfa_org_is_ready "$org"; then
        org_payload="$work/organization-totp.json"
        org_response="$work/organization-totp-response.json"
        org_rollback="$work/organization-rollback.json"
        cf_mfa_org_payload "$org" "$org_payload" || return 1
        jq '.result | {auth_domain,name,mfa_config:(.mfa_config // {}),
            login_design:((.login_design // {})
              | {background_color,footer_text,header_text,logo_path,text_color}
              | with_entries(select(.value != null)))}' "$org" >"$org_rollback" || return 1
        if ! cf_mfa_api PUT "/accounts/$CLOUDFLARE_ACCOUNT_ID/access/organizations" "$org_response" "$org_payload" 2>>"$log" ||
           [ "$(jq -r '.success // false' "$org_response")" != true ]; then
            msg "A Cloudflare não permitiu habilitar o TOTP e preparar a identidade visual do Setup MNO. Confirme Organizations, Identity Providers, and Groups > Editar."
            return 1
        fi
        org_changed="true"
        cf_mfa_save_onboarding_state "$state" false "$org_changed" "$org_rollback" "" false "" false false "" "" false || return 1
    fi
    otp_id=$(jq -r '[.result[]? | select(.type == "onetimepin")][0].id // empty' "$idps")
    if [ -z "$otp_id" ]; then
        idp_payload="$work/otp-payload.json"
        idp_response="$work/otp-response.json"
        jq -n '{name:"Setup MNO - código por e-mail",type:"onetimepin",config:{}}' >"$idp_payload"
        if ! cf_mfa_api POST "/accounts/$CLOUDFLARE_ACCOUNT_ID/access/identity_providers" "$idp_response" "$idp_payload" 2>>"$log" ||
           [ "$(jq -r '.success // false' "$idp_response")" != true ]; then
            rollback_cloudflare_mfa_onboarding "$state" "$log"
            msg "A Cloudflare não permitiu criar o login One-time PIN necessário para e-mails externos."
            return 1
        fi
        otp_id=$(jq -r '.result.id // empty' "$idp_response")
        otp_created="true"
        cf_mfa_save_onboarding_state "$state" false "$org_changed" "$org_rollback" "$otp_id" "$otp_created" "" false false "" "" false || return 1
    fi
    if [[ ! "$otp_id" =~ ^[A-Fa-f0-9-]{32,36}$ ]]; then
        rollback_cloudflare_mfa_onboarding "$state" "$log"
        msg "A Cloudflare não retornou um identificador válido para o login por e-mail."
        return 1
    fi
    launcher_id=$(jq -r '[.result[]? | select(.type == "app_launcher")][0].id // empty' "$apps")
    if [ -z "$launcher_id" ]; then
        policy_payload="$work/launcher-create.json"
        cf_mfa_launcher_policy_payload "$email" 1 "$work/launcher-inline-policy.json" || return 1
        jq -n --arg idp "$otp_id" --slurpfile policy "$work/launcher-inline-policy.json" \
            '{name:"App Launcher",type:"app_launcher",allowed_idps:[$idp],auto_redirect_to_identity:true,policies:$policy}' >"$policy_payload"
        policy_response="$work/launcher-create-response.json"
        if ! cf_mfa_api POST "/accounts/$CLOUDFLARE_ACCOUNT_ID/access/apps" "$policy_response" "$policy_payload" 2>>"$log" ||
           [ "$(jq -r '.success // false' "$policy_response")" != true ]; then
            rollback_cloudflare_mfa_onboarding "$state" "$log"
            msg "A Cloudflare recusou a ativação automática do App Launcher."
            return 1
        fi
        launcher_id=$(jq -r '.result.id // empty' "$policy_response")
        launcher_created="true"
        cf_mfa_save_onboarding_state "$state" false "$org_changed" "$org_rollback" "$otp_id" "$otp_created" "$launcher_id" true false "" "" false || return 1
    else
        if ! jq -e --arg app "$launcher_id" --arg idp "$otp_id" '
            [.result[]? | select(.id == $app)][0] as $launcher
            | (($launcher.allowed_idps // []) | length == 0) or
              (($launcher.allowed_idps // []) | index($idp) != null)
        ' "$apps" >/dev/null; then
            launcher_payload="$work/launcher-update.json"
            launcher_response="$work/launcher-update-response.json"
            launcher_rollback="$work/launcher-rollback.json"
            jq --arg app "$launcher_id" --arg idp "$otp_id" '
                [.result[]? | select(.id == $app)][0]
                | {name:(.name // "App Launcher"),type:"app_launcher",
                   allowed_idps:(((.allowed_idps // []) + [$idp]) | unique),
                   auto_redirect_to_identity:false}
            ' "$apps" >"$launcher_payload" || return 1
            jq --arg app "$launcher_id" '
                [.result[]? | select(.id == $app)][0]
                | {name:(.name // "App Launcher"),type:"app_launcher",
                   allowed_idps:(.allowed_idps // []),
                   auto_redirect_to_identity:(.auto_redirect_to_identity // false)}
            ' "$apps" >"$launcher_rollback" || return 1
            if ! cf_mfa_api PUT "/accounts/$CLOUDFLARE_ACCOUNT_ID/access/apps/$launcher_id" \
                "$launcher_response" "$launcher_payload" 2>>"$log" ||
               [ "$(jq -r '.success // false' "$launcher_response")" != true ]; then
                rollback_cloudflare_mfa_onboarding "$state" "$log"
                msg "O App Launcher existente não permitiu adicionar o login One-time PIN."
                return 1
            fi
            launcher_changed="true"
            cf_mfa_save_onboarding_state "$state" false "$org_changed" "$org_rollback" "$otp_id" "$otp_created" "$launcher_id" false true "$launcher_rollback" "" false || return 1
        fi
        policies="$work/launcher-policies.json"
        if ! cf_mfa_api GET "/accounts/$CLOUDFLARE_ACCOUNT_ID/access/apps/$launcher_id/policies" "$policies" 2>>"$log" ||
           [ "$(jq -r '.success // false' "$policies")" != true ]; then
            rollback_cloudflare_mfa_onboarding "$state" "$log"
            msg "Não foi possível consultar as políticas atuais do App Launcher."
            return 1
        fi
        policy_id=$(jq -r --arg email "$email" '[.result[]? | select(.decision == "allow" and any(.include[]?; .email.email? == $email))][0].id // empty' "$policies")
        if [ -z "$policy_id" ]; then
            precedence=$(jq -r '([.result[]?.precedence // 0] | max // 0) + 1' "$policies")
            policy_payload="$work/launcher-policy.json"
            policy_response="$work/launcher-policy-response.json"
            cf_mfa_launcher_policy_payload "$email" "$precedence" "$policy_payload" || return 1
            if ! cf_mfa_api POST "/accounts/$CLOUDFLARE_ACCOUNT_ID/access/apps/$launcher_id/policies" "$policy_response" "$policy_payload" 2>>"$log" ||
               [ "$(jq -r '.success // false' "$policy_response")" != true ]; then
                rollback_cloudflare_mfa_onboarding "$state" "$log"
                msg "A Cloudflare recusou a política automática do App Launcher."
                return 1
            fi
            policy_id=$(jq -r '.result.id // empty' "$policy_response")
            policy_created="true"
            cf_mfa_save_onboarding_state "$state" false "$org_changed" "$org_rollback" "$otp_id" "$otp_created" "$launcher_id" false "$launcher_changed" "$launcher_rollback" "$policy_id" true || return 1
        fi
    fi
    if [[ ! "$launcher_id" =~ ^[A-Fa-f0-9-]{32,36}$ ]]; then
        rollback_cloudflare_mfa_onboarding "$state" "$log"
        return 1
    fi
    cf_mfa_save_onboarding_state "$state" true "$org_changed" "$org_rollback" "$otp_id" "$otp_created" \
        "$launcher_id" "$launcher_created" "$launcher_changed" "$launcher_rollback" "$policy_id" "$policy_created"
}

remove_setupmno_launcher_policy() {
    local work="$1" email="$2" log="$3" apps app policies policy_id
    apps="$work/remove-launcher-apps.json"
    cf_mfa_api GET "/accounts/$CLOUDFLARE_ACCOUNT_ID/access/apps?per_page=100" "$apps" 2>>"$log" || return 1
    app=$(jq -r '[.result[]? | select(.type == "app_launcher")][0].id // empty' "$apps")
    [[ "$app" =~ ^[A-Fa-f0-9-]{32,36}$ ]] || return 0
    policies="$work/remove-launcher-policies.json"
    cf_mfa_api GET "/accounts/$CLOUDFLARE_ACCOUNT_ID/access/apps/$app/policies" "$policies" 2>>"$log" || return 1
    policy_id=$(jq -r --arg email "$email" '[.result[]? | select((.name // "") | startswith("Setup MNO - cadastro MFA - ")) | select(any(.include[]?; .email.email? == $email))][0].id // empty' "$policies")
    [ -z "$policy_id" ] || cf_mfa_api DELETE "/accounts/$CLOUDFLARE_ACCOUNT_ID/access/apps/$app/policies/$policy_id" "$work/remove-launcher-response.json" 2>>"$log"
}

ensure_cloudflare_access_cookie_lax() {
    local application="$1" app_id="$2" work="$3" log="$4" payload response
    [ "$(jq -r '.result.same_site_cookie_attribute // "auto"' "$application")" = "lax" ] && return 0
    payload="$work/access-cookie-lax.json"
    response="$work/access-cookie-lax-response.json"
    jq '.result | {
        name,type,domain,destinations,session_duration,app_launcher_visible,allow_iframe,
        allowed_idps,auto_redirect_to_identity,allow_authenticate_via_warp,skip_interstitial,
        options_preflight_bypass,mfa_config,same_site_cookie_attribute:"lax",
        policies:[.policies[]? | {id,precedence}]
      } | with_entries(select(.value != null))' "$application" >"$payload" || return 1
    if ! cf_mfa_api PUT "/accounts/$CLOUDFLARE_ACCOUNT_ID/access/apps/$app_id" \
        "$response" "$payload" 2>>"$log" ||
       [ "$(jq -r '.success // false' "$response")" != true ]; then
        msg "A Cloudflare recusou o ajuste automático do cookie para Lax. Esse ajuste evita ciclos de redirecionamento após o TOTP."
        return 1
    fi
}

manage_access_bypass_cli() {
    local action="${1:-}" target_arg="${2:-}"
    local work_dir log_file credentials_file app_id aud url_control
    
    work_dir=$(mktemp -d "/tmp/setupmno-bypass-work.XXXXXX") || return 1
    log_file="$work_dir/bypass.log"
    
    credentials_file="${SETUPMNO_CLOUDFLARE_CREDENTIALS_FILE:-/root/.cloudflared_config/cloudflare_credentials}"
    if [ ! -f "$credentials_file" ] && [ -f "/root/.cloudflared/cloudflare_credentials" ]; then
        credentials_file="/root/.cloudflared/cloudflare_credentials"
    fi
    if [ ! -f "$credentials_file" ] && [ -f "/root/SetupLowCodeMno/cloudflare_credentials" ]; then
        credentials_file="/root/SetupLowCodeMno/cloudflare_credentials"
    fi
    if [ ! -f "$credentials_file" ] && [ -n "${3:-}" ] && [ -f "$3" ]; then
        credentials_file="$3"
    fi
    if [ -f "$credentials_file" ]; then
        # shellcheck disable=SC1090
        . "$credentials_file"
    fi
    
    if [ -z "${CLOUDFLARE_API_TOKEN:-}" ] || [ -z "${CLOUDFLARE_ACCOUNT_ID:-}" ]; then
        echo "ERRO: CLOUDFLARE_API_TOKEN ou CLOUDFLARE_ACCOUNT_ID não configurados." >&2
        rm -rf -- "$work_dir"
        return 1
    fi
    
    local env_file="${SETUPMNO_CONTROL_ENV_FILE:-/root/SetupLowCodeMno/.control/environment.json}"
    if [ -f "$env_file" ]; then
        aud=$(jq -r '.accessAud // empty' "$env_file" 2>/dev/null || true)
        url_control=$(jq -r '.controlDomain // empty' "$env_file" 2>/dev/null || true)
    fi
    if [ -z "${url_control:-}" ] && [ -f "/root/setupmno-control.env" ]; then
        url_control=$(grep -E '^(url_control|CONTROL_DOMAIN)=' "/root/setupmno-control.env" | head -n1 | cut -d= -f2- | tr -d '"'\'' ')
    fi
    
    local apps_file="$work_dir/apps.json"
    if ! cf_mfa_api GET "/accounts/$CLOUDFLARE_ACCOUNT_ID/access/apps?per_page=100" "$apps_file" 2>>"$log_file" ||
       [ "$(jq -r '.success // false' "$apps_file" 2>/dev/null)" != "true" ]; then
        echo "ERRO: Falha ao consultar aplicações Access na Cloudflare. Verifique a conexão e o token." >&2
        rm -rf -- "$work_dir"
        return 1
    fi
    
    if [ -n "${aud:-}" ]; then
        app_id=$(jq -r --arg aud "$aud" '[.result[]? | select(.aud == $aud)][0].id // empty' "$apps_file" 2>/dev/null || true)
    fi
    if [ -z "${app_id:-}" ] && [ -n "${url_control:-}" ]; then
        app_id=$(jq -r --arg dom "$url_control" '[.result[]? | select(.domain == $dom)][0].id // empty' "$apps_file" 2>/dev/null || true)
    fi
    if [ -z "${app_id:-}" ]; then
        app_id=$(jq -r '[.result[]? | select((.name // "") | startswith("Setup MNO Control Center"))][0].id // empty' "$apps_file" 2>/dev/null || true)
    fi
    
    if [[ ! "${app_id:-}" =~ ^[A-Fa-f0-9-]{32,36}$ ]]; then
        echo "ERRO: Não foi possível localizar a aplicação Access do Control Center na Cloudflare." >&2
        rm -rf -- "$work_dir"
        return 1
    fi
    
    if [ -z "${url_control:-}" ]; then
        url_control=$(jq -r --arg id "$app_id" '[.result[]? | select(.id == $id)][0].domain // empty' "$apps_file" 2>/dev/null || true)
    fi
    
    case "$action" in
        add|add-ip)
            local ip="$target_arg"
            if [ -z "$ip" ]; then
                echo "ERRO: Informe o IP da Torre Master (ex: --add-access-bypass 5.161.x.x)" >&2
                rm -rf -- "$work_dir"
                return 1
            fi
            if [[ "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
                ip="${ip}/32"
            fi
            
            local pol_file="$work_dir/policies.json"
            cf_mfa_api GET "/accounts/$CLOUDFLARE_ACCOUNT_ID/access/apps/$app_id/policies" "$pol_file" 2>>"$log_file"
            
            local existing_pol_id
            existing_pol_id=$(jq -r --arg ip "$ip" '[.result[]? | select(.decision == "bypass" and any(.include[]?; .ip.ip? == $ip))][0].id // empty' "$pol_file" 2>/dev/null || true)
            if [ -n "$existing_pol_id" ]; then
                echo "[OK] A regra de Bypass para o IP $ip já existe e está ativa na Cloudflare (Policy ID: $existing_pol_id)."
                rm -rf -- "$work_dir"
                return 0
            fi
            
            local p1_id
            p1_id=$(jq -r '[.result[]? | select(.precedence == 1 and .decision != "bypass")][0].id // empty' "$pol_file" 2>/dev/null || true)
            if [ -n "$p1_id" ]; then
                local p1_json="$work_dir/p1.json"
                local p1_resp="$work_dir/p1-resp.json"
                jq -c --arg id "$p1_id" '([.result[]? | select(.id == $id)][0]) | .precedence = 10' "$pol_file" >"$p1_json"
                cf_mfa_api PUT "/accounts/$CLOUDFLARE_ACCOUNT_ID/access/apps/$app_id/policies/$p1_id" "$p1_resp" "$p1_json" 2>>"$log_file" || true
            fi
            
            local payload="$work_dir/bypass-payload.json"
            local response="$work_dir/bypass-response.json"
            jq -n --arg ip "$ip" '{
                name: ("Setup MNO - Bypass Torre Master (" + $ip + ")"),
                decision: "bypass",
                precedence: 1,
                include: [{ip: {ip: $ip}}],
                exclude: [],
                require: []
            }' >"$payload"
            
            if ! cf_mfa_api POST "/accounts/$CLOUDFLARE_ACCOUNT_ID/access/apps/$app_id/policies" "$response" "$payload" 2>>"$log_file" ||
               [ "$(jq -r '.success // false' "$response" 2>/dev/null)" != "true" ]; then
                local err_msg
                err_msg=$(cf_mfa_error "$response")
                echo "ERRO ao criar política de Bypass na Cloudflare: $err_msg" >&2
                rm -rf -- "$work_dir"
                return 1
            fi
            
            if [ -n "${TUNNEL_ID:-}" ]; then
                local tunnel_raw="$work_dir/tunnel-config.json"
                local tunnel_payload="$work_dir/tunnel-payload.json"
                local tunnel_resp="$work_dir/tunnel-resp.json"
                if cf_mfa_api GET "/accounts/$CLOUDFLARE_ACCOUNT_ID/cfd_tunnel/$TUNNEL_ID/configurations" "$tunnel_raw" 2>>"$log_file" &&
                   jq -e --arg h "$url_control" 'any(.result.config.ingress[]?; .hostname == $h and .originRequest.access != null)' "$tunnel_raw" >/dev/null 2>&1; then
                    jq --arg h "$url_control" '
                        (.result.config // {}) as $cfg
                        | {config: ($cfg + {ingress: [($cfg.ingress // [])[] |
                            if .hostname == $h then .originRequest = ((.originRequest // {}) | del(.access))
                            else . end]})}' "$tunnel_raw" >"$tunnel_payload" 2>>"$log_file"
                    cf_mfa_api PUT "/accounts/$CLOUDFLARE_ACCOUNT_ID/cfd_tunnel/$TUNNEL_ID/configurations" "$tunnel_resp" "$tunnel_payload" 2>>"$log_file" || true
                fi
            fi
            
            local created_id
            created_id=$(jq -r '.result.id // empty' "$response")
            echo "[OK] Regra de Bypass para a Torre Master (IP: $ip) criada com sucesso na Cloudflare! (Policy ID: $created_id)"
            rm -rf -- "$work_dir"
            return 0
            ;;
            
        remove|remove-ip)
            local pol_file="$work_dir/policies.json"
            cf_mfa_api GET "/accounts/$CLOUDFLARE_ACCOUNT_ID/access/apps/$app_id/policies" "$pol_file" 2>>"$log_file"
            
            local pol_ids
            if [ -n "$target_arg" ]; then
                local ip="$target_arg"
                [[ "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]] && ip="${ip}/32"
                pol_ids=$(jq -r --arg ip "$ip" '.result[]? | select(.decision == "bypass" and any(.include[]?; .ip.ip? == $ip)) | .id' "$pol_file" 2>/dev/null || true)
            else
                pol_ids=$(jq -r '.result[]? | select(.decision == "bypass" and ((.name // "") | startswith("Setup MNO - Bypass"))) | .id' "$pol_file" 2>/dev/null || true)
            fi
            
            if [ -z "$pol_ids" ] && [ -n "$target_arg" ]; then
                echo "[INFO] Nenhuma regra de Bypass do Setup MNO encontrada para remover."
                rm -rf -- "$work_dir"
                return 0
            fi
            
            for pid in $pol_ids; do
                cf_mfa_api DELETE "/accounts/$CLOUDFLARE_ACCOUNT_ID/access/apps/$app_id/policies/$pid" "$work_dir/del-$pid.json" 2>>"$log_file" || true
                echo "[OK] Regra de Bypass $pid removida da Cloudflare."
            done

            if [ -z "$target_arg" ]; then
                local telem_apps
                telem_apps=$(jq -r --arg dom1 "$url_control/api/fleet/*" --arg dom2 "$url_control/api/fleet/worker/*" \
                    '.result[]? | select(.domain == $dom1 or .domain == $dom2) | .id' "$apps_file" 2>/dev/null || true)
                for tid in $telem_apps; do
                    cf_mfa_api DELETE "/accounts/$CLOUDFLARE_ACCOUNT_ID/access/apps/$tid" "$work_dir/del-telem-$tid.json" 2>>"$log_file" || true
                    echo "[OK] Aplicação de Bypass de Telemetria $tid removida da Cloudflare."
                done
            fi
            rm -rf -- "$work_dir"
            return 0
            ;;
            
        add-telemetry)
            if [ -z "${url_control:-}" ]; then
                url_control=$(jq -r --arg id "$app_id" '[.result[]? | select(.id == $id)][0].domain // empty' "$apps_file" 2>/dev/null || true)
            fi
            if [ -z "${url_control:-}" ]; then
                echo "ERRO: Domínio do Control Center não identificado." >&2
                rm -rf -- "$work_dir"
                return 1
            fi
            
            local telem_domain="$url_control/api/fleet/worker/*"
            local old_telem_domain="$url_control/api/fleet/*"
            local existing_telem_app_id
            existing_telem_app_id=$(jq -r --arg dom "$telem_domain" '[.result[]? | select(.domain == $dom)][0].id // empty' "$apps_file" 2>/dev/null || true)
            local old_telem_app_id
            old_telem_app_id=$(jq -r --arg dom "$old_telem_domain" '[.result[]? | select(.domain == $dom)][0].id // empty' "$apps_file" 2>/dev/null || true)

            if [ -n "$old_telem_app_id" ] && [ -z "$existing_telem_app_id" ]; then
                local update_payload="$work_dir/telem-update-payload.json"
                local update_response="$work_dir/telem-update-response.json"
                jq -n --arg name "Setup MNO Telemetria - $url_control" --arg domain "$telem_domain" '{
                    name: $name,
                    domain: $domain,
                    destinations: [{type: "public", uri: $domain}]
                }' >"$update_payload"
                if cf_mfa_api PUT "/accounts/$CLOUDFLARE_ACCOUNT_ID/access/apps/$old_telem_app_id" "$update_response" "$update_payload" 2>>"$log_file" &&
                   [ "$(jq -r '.success // false' "$update_response" 2>/dev/null)" = "true" ]; then
                    existing_telem_app_id="$old_telem_app_id"
                fi
            elif [ -n "$old_telem_app_id" ] && [ -n "$existing_telem_app_id" ] && [ "$old_telem_app_id" != "$existing_telem_app_id" ]; then
                cf_mfa_api DELETE "/accounts/$CLOUDFLARE_ACCOUNT_ID/access/apps/$old_telem_app_id" "$work_dir/del-old.json" 2>>"$log_file" || true
            fi

            local created_app_id="$existing_telem_app_id"
            if [ -z "$existing_telem_app_id" ]; then
                local payload="$work_dir/telem-payload.json"
                local response="$work_dir/telem-response.json"
                jq -n --arg name "Setup MNO Telemetria - $url_control" --arg domain "$telem_domain" '{
                    name: $name,
                    type: "self_hosted",
                    domain: $domain,
                    destinations: [{type: "public", uri: $domain}],
                    session_duration: "24h",
                    app_launcher_visible: false,
                    allow_iframe: false,
                    allow_authenticate_via_warp: false,
                    skip_interstitial: true,
                    same_site_cookie_attribute: "lax",
                    policies: [{
                        name: "Setup MNO - Bypass Telemetria da Frota",
                        decision: "bypass",
                        precedence: 1,
                        include: [{everyone: {}}],
                        exclude: [],
                        require: []
                    }]
                }' >"$payload"
                
                if ! cf_mfa_api POST "/accounts/$CLOUDFLARE_ACCOUNT_ID/access/apps" "$response" "$payload" 2>>"$log_file" ||
                   [ "$(jq -r '.success // false' "$response" 2>/dev/null)" != "true" ]; then
                    local err_msg
                    err_msg=$(cf_mfa_error "$response")
                    echo "ERRO ao criar aplicação de Bypass de Telemetria na Cloudflare: $err_msg" >&2
                    rm -rf -- "$work_dir"
                    return 1
                fi
                created_app_id=$(jq -r '.result.id // empty' "$response")
            fi
            
            if [ -n "${TUNNEL_ID:-}" ]; then
                local tunnel_raw="$work_dir/tunnel-config.json"
                local tunnel_payload="$work_dir/tunnel-payload.json"
                local tunnel_resp="$work_dir/tunnel-resp.json"
                if cf_mfa_api GET "/accounts/$CLOUDFLARE_ACCOUNT_ID/cfd_tunnel/$TUNNEL_ID/configurations" "$tunnel_raw" 2>>"$log_file" &&
                   jq -e --arg h "$url_control" 'any(.result.config.ingress[]?; .hostname == $h and .originRequest.access != null)' "$tunnel_raw" >/dev/null 2>&1; then
                    jq --arg h "$url_control" '
                        (.result.config // {}) as $cfg
                        | {config: ($cfg + {ingress: [($cfg.ingress // [])[] |
                            if .hostname == $h then .originRequest = ((.originRequest // {}) | del(.access))
                            else . end]})}' "$tunnel_raw" >"$tunnel_payload" 2>>"$log_file"
                    cf_mfa_api PUT "/accounts/$CLOUDFLARE_ACCOUNT_ID/cfd_tunnel/$TUNNEL_ID/configurations" "$tunnel_resp" "$tunnel_payload" 2>>"$log_file" || true
                fi
            fi
            
            echo "[OK] Bypass de Telemetria (/api/fleet/worker/*) garantido na Cloudflare! (App ID: $created_app_id)"
            rm -rf -- "$work_dir"
            return 0
            ;;
            
        *)
            echo "Ação desconhecida: $action" >&2
            rm -rf -- "$work_dir"
            return 1
            ;;
    esac
}

manage_access_bypass_interactive() {
    local choice master_ip out
    choice=$(whiptail --title "GERENCIAR BYPASS CLOUDFLARE ACCESS" --default-item "ADD_IP" --menu \
        "Escolha como liberar o acesso da Torre Master sem exigir autenticação MFA:" \
        18 84 3 \
        "ADD_IP" "Liberar pelo IP público fixo da Torre Master (VPS)" \
        "ADD_TELEM" "Liberar rota /api/fleet/worker/* para telemetria (WSL2 / IP Dinâmico)" \
        "REMOVE" "Remover regras de Bypass anteriores" \
        3>&1 1>&2 2>&3) || return 0
    case "$choice" in
        ADD_IP)
            master_ip=$(whiptail --title "BYPASS POR IP DA TORRE MASTER" --inputbox \
                "Informe o IP público da sua Torre Master:" 11 70 3>&1 1>&2 2>&3) || return 0
            master_ip=$(printf '%s' "$master_ip" | tr -d '[:space:]')
            [ -n "$master_ip" ] || return 0
            out=$(manage_access_bypass_cli add "$master_ip" 2>&1)
            whiptail --title "RESULTADO DO BYPASS" --msgbox "$out" 12 76 1>&2
            ;;
        ADD_TELEM)
            out=$(manage_access_bypass_cli add-telemetry 2>&1)
            whiptail --title "RESULTADO DO BYPASS" --msgbox "$out" 12 76 1>&2
            ;;
        REMOVE)
            out=$(manage_access_bypass_cli remove 2>&1)
            whiptail --title "RESULTADO DO BYPASS" --msgbox "$out" 12 76 1>&2
            ;;
    esac
}

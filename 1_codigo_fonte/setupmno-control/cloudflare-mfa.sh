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
    local -a args=(curl -sS --connect-timeout "$CLOUDFLARE_CONNECT_TIMEOUT"
        --max-time "$CLOUDFLARE_MAX_TIME" -X "$method"
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

prepare_cloudflare_mfa_enrollment_email() {
    local email="$1" state_file="${CONTROL_MFA_STATE_FILE:-}" source="" choice
    local local_part domain base tag effective replacement status
    [[ "$email" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]] || return 1
    if [ -f "$state_file" ] && [ ! -L "$state_file" ] &&
       [ "$(stat -c '%s' "$state_file" 2>/dev/null || printf '99999')" -le 2048 ]; then
        source=$(jq -r '.source // empty' "$state_file" 2>/dev/null)
    fi
    [ "$source" = "menu-disabled" ] || {
        printf '%s\n' "$email"
        return 0
    }
    local_part=${email%@*}
    domain=${email##*@}
    domain=${domain,,}
    if [ "$domain" = "gmail.com" ] || [ "$domain" = "googlemail.com" ]; then
        choice=$(whiptail --title "REATIVAÇÃO DO MFA" --default-item "NOVO_QR" --menu \
            "Este Control Center já teve MFA. Para evitar um autenticador antigo ou órfão, escolha como deseja reativar. O alias Gmail recomendado entrega os códigos na mesma caixa postal, mas deve ser digitado exatamente como será mostrado:" \
            20 96 4 \
            "NOVO_QR" "Criar identidade nova na mesma caixa Gmail e exibir novo QR" \
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
            base=${local_part%%+*}
            tag="setupmno$(date -u +%y%m%d%H%M%S)$(od -An -N2 -tx1 /dev/urandom | tr -d ' \n')"
            effective="${base}+${tag}@${domain}"
            [ "${#base}" -le 40 ] && [ "${#effective}" -le 254 ] || {
                whiptail --title "ALIAS GMAIL MUITO LONGO" --msgbox \
                    "O endereço informado não comporta um alias seguro. Escolha OUTRO E-MAIL na próxima tentativa." \
                    10 82 1>&2
                return 130
            }
            whiptail --title "NOVO QR CODE CONFIRMADO" --msgbox \
                "O Setup usará esta identidade exclusiva:\n\n$effective\n\nOs códigos por e-mail continuarão chegando em $email. Na tela da Cloudflare, digite exatamente o endereço com +setupmno mostrado acima. Depois do código por e-mail, será exibido um novo QR Code." \
                17 94 1>&2
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

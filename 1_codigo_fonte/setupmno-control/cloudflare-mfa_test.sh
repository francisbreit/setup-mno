#!/usr/bin/bash
set -euo pipefail

project_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT

msg() { printf '%s' "$1" >"$test_dir/message.txt"; }
whiptail() { return 0; }
CLOUDFLARE_CONNECT_TIMEOUT=10
CLOUDFLARE_MAX_TIME=30
CLOUDFLARE_ACCOUNT_ID="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
CLOUDFLARE_ZONE_ID="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
TUNNEL_ID="cccccccc-cccc-cccc-cccc-cccccccccccc"
CLOUDFLARE_API_TOKEN="token-original-abcdefghijklmnopqrstuvwxyz"
CF_MFA_LOG="$test_dir/api.log"
. "$project_dir/cloudflare-mfa.sh"

credentials="$test_dir/cloudflare_credentials"
printf '%s\n' \
    'CLOUDFLARE_ACCOUNT_ID=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' \
    'CLOUDFLARE_API_TOKEN=token-antigo-abcdefghijklmnopqrstuvwxyz' \
    'CLOUDFLARE_ZONE_ID=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb' \
    'TUNNEL_ID=cccccccc-cccc-cccc-cccc-cccccccccccc' >"$credentials"
chmod 0644 "$credentials"
new_token="cfut_ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789abcdefgh"
persist_cloudflare_token_file "$new_token" "$credentials"
[ "$(stat -c '%a' "$credentials")" = "600" ]
[ "$(grep -c '^CLOUDFLARE_API_TOKEN=' "$credentials")" -eq 1 ]
grep -Fqx "CLOUDFLARE_API_TOKEN=$new_token" "$credentials"
grep -Fqx 'TUNNEL_ID=cccccccc-cccc-cccc-cccc-cccccccccccc' "$credentials"
if persist_cloudflare_token_file "$new_token" "$test_dir"; then
    printf 'ERRO: credencial não regular foi aceita.\n' >&2
    exit 1
fi

validation_mode="success"
cf_mfa_api() {
    local method="$1" path="$2" output="$3"
    [ "$method" = "GET" ]
    if [ "$validation_mode" = "denied" ] && [[ "$path" == */access/apps* ]]; then
        printf '%s\n' '{"success":false,"errors":[{"message":"permission denied"}]}' >"$output"
    elif [ "$path" = "/user/tokens/verify" ]; then
        printf '%s\n' '{"success":true,"result":{"status":"active"}}' >"$output"
    else
        printf '%s\n' '{"success":true,"result":{}}' >"$output"
    fi
}
candidate="cfut_1234567890ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefgh"
valid_candidate="$candidate"
validate_cloudflare_mfa_token "$candidate" "$test_dir"
[ "$CLOUDFLARE_API_TOKEN" = "$candidate" ]
validation_mode="denied"
if validate_cloudflare_mfa_token "$candidate" "$test_dir"; then
    printf 'ERRO: token sem Access foi aceito.\n' >&2
    exit 1
fi
[[ "$CF_MFA_VALIDATION_ERROR" == *"Apps and Policies"* ]]

validation_mode="success"
password_counter="$test_dir/password-counter"
printf '0\n' >"$password_counter"
whiptail() {
    if [[ " $* " == *" --menu "* ]]; then
        printf '%s' 'NOVO' >&2
    elif [[ " $* " == *" --passwordbox "* ]]; then
        local count
        count=$(<"$password_counter")
        count=$((count + 1))
        printf '%s\n' "$count" >"$password_counter"
        if [ "$count" -eq 1 ]; then
            printf '%s' 'curto' >&2
        else
            printf '%s' "$valid_candidate" >&2
        fi
    fi
    return 0
}
persist_cloudflare_token() {
    persist_cloudflare_token_file "$1" "$credentials"
}
prepare_cloudflare_mfa_token "$test_dir" "$test_dir/token-assistant.log"
[ "$(<"$password_counter")" -eq 2 ]
grep -Fqx "CLOUDFLARE_API_TOKEN=$valid_candidate" "$credentials"

org_fixture="$test_dir/org.json"
org_payload="$test_dir/org-payload.json"
printf '%s\n' '{"result":{"auth_domain":"setupmno.cloudflareaccess.com","name":"Setup MNO","mfa_config":{"allowed_authenticators":["security_key"],"session_duration":"12h"}}}' >"$org_fixture"
cf_mfa_org_payload "$org_fixture" "$org_payload"
jq -e '.mfa_config.allowed_authenticators == ["security_key","totp"] and
       .mfa_config.session_duration == "12h" and
       .login_design.header_text == "Acesso seguro ao Setup MNO" and
       .login_design.footer_text == "Digite o código de 6 dígitos gerado pelo seu aplicativo autenticador." and
       .login_design.logo_path == "https://ativa2.manualnegocioonline.com.br/setup-mno-logo.svg" and
       .login_design.background_color == "#07090d" and
       .login_design.text_color == "#f4f6f8"' "$org_payload" >/dev/null
if cf_mfa_org_is_ready "$org_fixture"; then
    printf 'ERRO: organização sem identidade visual foi considerada pronta.\n' >&2
    exit 1
fi

custom_org_fixture="$test_dir/org-custom.json"
custom_org_payload="$test_dir/org-custom-payload.json"
printf '%s\n' '{"result":{"auth_domain":"custom.cloudflareaccess.com","name":"Empresa","mfa_config":{"allowed_authenticators":["totp"]},"login_design":{"header_text":"Portal da Empresa","footer_text":"Suporte interno","logo_path":"https://example.com/custom.svg","background_color":"#123456","text_color":"#abcdef"}}}' >"$custom_org_fixture"
cf_mfa_org_payload "$custom_org_fixture" "$custom_org_payload"
cf_mfa_org_is_ready "$custom_org_fixture"
jq -e '.login_design.header_text == "Portal da Empresa" and
       .login_design.footer_text == "Suporte interno" and
       .login_design.logo_path == "https://example.com/custom.svg" and
       .login_design.background_color == "#123456" and
       .login_design.text_color == "#abcdef"' "$custom_org_payload" >/dev/null
policy_payload="$test_dir/policy.json"
cf_mfa_launcher_policy_payload 'admin@example.com' 3 "$policy_payload"
jq -e '.decision == "allow" and .precedence == 3 and
       .include[0].email.email == "admin@example.com"' "$policy_payload" >/dev/null

api_log="$test_dir/onboarding-api.log"
onboarding_mode="success"
cf_mfa_api() {
    local method="$1" path="$2" output="$3" payload="${4:-}"
    printf '%s %s\n' "$method" "$path" >>"$api_log"
    if [ "$method" = "PUT" ] && [[ "$path" == */access/organizations ]] && [ -s "$payload" ]; then
        cp "$payload" "$test_dir/organization-update-captured.json"
    fi
    case "$method:$path" in
        GET:*/access/organizations)
            printf '%s\n' '{"success":true,"result":{"auth_domain":"setupmno.cloudflareaccess.com","name":"Setup MNO","mfa_config":{"allowed_authenticators":[]}}}' >"$output"
            ;;
        GET:*/access/identity_providers)
            printf '%s\n' '{"success":true,"result":[]}' >"$output"
            ;;
        GET:*/access/apps\?per_page=100)
            printf '%s\n' '{"success":true,"result":[{"id":"11111111-2222-3333-4444-555555555555","type":"app_launcher","name":"App Launcher","allowed_idps":[]}]}' >"$output"
            ;;
        GET:*/access/apps/11111111-2222-3333-4444-555555555555/policies)
            printf '%s\n' '{"success":true,"result":[]}' >"$output"
            ;;
        PUT:*/access/organizations)
            printf '%s\n' '{"success":true,"result":{}}' >"$output"
            ;;
        POST:*/access/identity_providers)
            printf '%s\n' '{"success":true,"result":{"id":"22222222-3333-4444-5555-666666666666"}}' >"$output"
            ;;
        POST:*/access/apps/11111111-2222-3333-4444-555555555555/policies)
            if [ "$onboarding_mode" = "policy-failure" ]; then
                printf '%s\n' '{"success":false,"errors":[{"message":"denied"}]}' >"$output"
            else
                printf '%s\n' '{"success":true,"result":{"id":"33333333-4444-5555-6666-777777777777"}}' >"$output"
            fi
            ;;
        DELETE:*|PUT:*/access/apps/*)
            printf '%s\n' '{"success":true,"result":{}}' >"$output"
            ;;
        *)
            printf 'ERRO: chamada simulada inesperada: %s %s\n' "$method" "$path" >&2
            return 1
            ;;
    esac
}
state="$test_dir/onboarding-state.json"
ensure_cloudflare_mfa_onboarding "$test_dir" 'admin@example.com' "$test_dir/onboarding.log" "$state"
jq -e '.active == true and .organizationChanged == true and .otpCreated == true and
       .launcherPolicyCreated == true' "$state" >/dev/null
jq -e '.login_design.header_text == "Acesso seguro ao Setup MNO" and
       .login_design.footer_text == "Digite o código de 6 dígitos gerado pelo seu aplicativo autenticador." and
       .login_design.logo_path == "https://ativa2.manualnegocioonline.com.br/setup-mno-logo.svg" and
       .login_design.background_color == "#07090d" and
       .login_design.text_color == "#f4f6f8"' \
    "$test_dir/organization-update-captured.json" >/dev/null
jq -e '.login_design == {}' "$test_dir/organization-rollback.json" >/dev/null
grep -Fq 'PUT /accounts/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/access/organizations' "$api_log"
grep -Fq 'POST /accounts/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/access/identity_providers' "$api_log"
grep -Fq 'POST /accounts/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/access/apps/11111111-2222-3333-4444-555555555555/policies' "$api_log"

: >"$api_log"
onboarding_mode="policy-failure"
if ensure_cloudflare_mfa_onboarding "$test_dir" 'outro@example.com' "$test_dir/onboarding-failure.log" "$state"; then
    printf 'ERRO: falha da política do App Launcher foi aceita.\n' >&2
    exit 1
fi
grep -Fq 'DELETE /accounts/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/access/identity_providers/22222222-3333-4444-5555-666666666666' "$api_log"
grep -Fq 'PUT /accounts/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/access/organizations' "$api_log"

app_fixture="$test_dir/access-app.json"
printf '%s\n' '{"result":{"id":"44444444-5555-6666-7777-888888888888","name":"Control","type":"self_hosted","domain":"control.example.com","destinations":[{"type":"public","uri":"control.example.com"}],"same_site_cookie_attribute":"strict","policies":[{"id":"55555555-6666-7777-8888-999999999999","precedence":1}]}}' >"$app_fixture"
onboarding_mode="success"
: >"$api_log"
ensure_cloudflare_access_cookie_lax "$app_fixture" '44444444-5555-6666-7777-888888888888' "$test_dir" "$test_dir/cookie.log"
jq -e '.same_site_cookie_attribute == "lax" and
       .policies[0].id == "55555555-6666-7777-8888-999999999999"' "$test_dir/access-cookie-lax.json" >/dev/null

if rg -n "$new_token|$valid_candidate" "$test_dir" --glob '*.log' >/dev/null; then
    printf 'ERRO: token apareceu em log de teste.\n' >&2
    exit 1
fi

printf 'Assistente Cloudflare MFA: token, automação, rollback e cookie Lax aprovados.\n'

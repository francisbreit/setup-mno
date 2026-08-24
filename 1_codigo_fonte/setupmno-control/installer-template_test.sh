#!/usr/bin/bash
set -euo pipefail

project_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
template="$project_dir/installer-template.sh"
heartbeat="$project_dir/install-heartbeat.sh"
# shellcheck disable=SC1091
. "$project_dir/cloudflare-route-guard.sh"
# shellcheck disable=SC1091
. "$project_dir/cloudflare-access-reconcile.sh"
grep -Fq 'LATER)' "$template"
grep -Fq 'assistant_mode="later"' "$template"
grep -Fq 'assistant_has_llm="false"' "$template"
grep -Fq 'if [ "$assistant_has_llm" = "true" ]; then' "$template"
grep -Fq 'control_stack_manager="portainer"' "$template"
grep -Fq 'control_stack_manager="docker"' "$template"
grep -Fq 'SETUPMNO_CONTROL_STACK_MANAGER=$control_stack_manager' "$template"
grep -Fq 'SETUPMNO_CONTROL_PORTAINER_CREDENTIALS=/root/dados_portainer/dados_portainer' "$template"
grep -Fq 'if control_center_installed; then' "$template"
grep -Fq 'somente uma instalação é permitida por servidor' "$template"
grep -Fq '/root/SetupLowCodeMno/.setupmno-control-install.lock' "$template"
grep -Fq 'flock -n 9' "$template"
grep -Fq 'start_install_heartbeat 20 "CONSTRUINDO O PAINEL WEB..."' "$template"
grep -Fq 'start_install_heartbeat 38 "CONSTRUINDO O TERMINAL PROTEGIDO..."' "$template"
grep -Fq 'start_install_heartbeat 96 "AGUARDANDO OS SERVIÇOS DO CONTROL CENTER..."' "$template"
grep -Fq '. "$work_dir/source/install-heartbeat.sh"' "$template"
grep -Fq 'stop_install_heartbeat' "$template"
grep -Fq 'Processando há %02d:%02d' "$heartbeat"

initial_mfa_flow=$(awk '
    /^access_email=""$/ { inside=1 }
    inside { print }
    inside && /^mem_total_mb=/ { exit }
' "$template")
[ -n "$initial_mfa_flow" ] || {
    printf 'ERRO: fluxo MFA da instalação inicial não foi localizado.\n' >&2
    exit 1
}
grep -Fq 'load_cloudflare_mfa_helper' <<<"$initial_mfa_flow" &&
grep -Fq 'prepare_cloudflare_mfa_token "$access_token_work" "$access_token_log"' \
    <<<"$initial_mfa_flow" || {
    printf 'ERRO: instalação inicial com MFA não valida as sete permissões do token.\n' >&2
    exit 1
}
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT

(
    # shellcheck disable=SC1090
    . "$heartbeat"

    install_log="$test_dir/install-heartbeat.log"
    heartbeat_gauge="$test_dir/install-heartbeat-gauge.log"
    : >"$install_log"

    sleep() {
        command sleep 0.02
    }
    heartbeat_success() {
        command sleep 0.12
        printf '%s\n' 'saída técnica preservada'
    }
    heartbeat_failure() {
        command sleep 0.08
        printf '%s\n' 'falha técnica preservada'
        return 37
    }

    start_install_heartbeat 20 "CONSTRUINDO O PAINEL WEB..." >"$heartbeat_gauge"
    heartbeat_success >>"$install_log"
    stop_install_heartbeat
    [ -z "$install_heartbeat_pid" ]
    grep -Fq 'CONSTRUINDO O PAINEL WEB...' "$heartbeat_gauge"
    grep -Fq 'Processando há 00:00' "$heartbeat_gauge"
    grep -Fq '[|]' "$heartbeat_gauge"
    grep -Fq '[/]' "$heartbeat_gauge"
    grep -Fq '[-]' "$heartbeat_gauge"
    grep -Fq '[\]' "$heartbeat_gauge"
    grep -Fq 'saída técnica preservada' "$install_log"

    start_install_heartbeat 38 "CONSTRUINDO O TERMINAL PROTEGIDO..." >>"$heartbeat_gauge"
    heartbeat_status=0
    heartbeat_failure >>"$install_log" || heartbeat_status=$?
    stop_install_heartbeat
    if [ "$heartbeat_status" -eq 0 ]; then
        printf 'ERRO: heartbeat descartou a falha da operação monitorada.\n' >&2
        exit 1
    fi
    [ "$heartbeat_status" -eq 37 ] || {
        printf 'ERRO: heartbeat alterou o código de falha da operação.\n' >&2
        exit 1
    }
    [ -z "$install_heartbeat_pid" ]
    grep -Fq 'falha técnica preservada' "$install_log"
)

for migration_function in \
    control_mfa_state_valid \
    write_control_mfa_state \
    show_cloudflare_access_guide \
    choose_cloudflare_access_security \
    ask_required \
    collect_cloudflare_access_email \
    build_cloudflare_access_payload \
    control_service_env_value \
    rollback_existing_access_migration \
    prepare_existing_access_migration \
    control_mfa_restore_progress \
    restore_existing_access_original_mode \
    build_existing_access_policy_payload \
    configure_existing_access_mfa; do
    migration_source=$(awk -v name="$migration_function" '
        $0 ~ "^" name "\\(\\)" { inside=1 }
        inside { print }
        inside && /^}/ { exit }
    ' "$template")
    [ -n "$migration_source" ] || {
        printf 'ERRO: função %s ausente.\n' "$migration_function" >&2
        exit 1
    }
    eval "$migration_source"
done

CLOUDFLARE_CONNECT_TIMEOUT=10
CLOUDFLARE_MAX_TIME=30
CONTROL_VERSION="test"
CONTROL_MFA_STATE_FILE="$test_dir/mfa-state.json"
CLOUDFLARE_API_TOKEN="test-token-not-secret"
CLOUDFLARE_ACCOUNT_ID="test-account"
TUNNEL_ID="test-tunnel"
message_capture="$test_dir/message.txt"
gauge_capture="$test_dir/gauge.txt"
export MOCK_CURL_MODE="success" GAUGE_CAPTURE="$gauge_capture"

msg() {
    printf '%s' "$1" >"$message_capture"
}

mkdir -p "$test_dir/bin"
cat >"$test_dir/bin/whiptail" <<'EOF'
#!/usr/bin/bash
if [[ " $* " == *" --gauge "* ]]; then
    cat >"$GAUGE_CAPTURE"
    exit 0
fi
if [[ " $* " == *" --inputbox "* ]]; then
    printf '%s' 'admin@example.com' >&2
    exit 0
fi
if [[ " $* " == *" --menu "* ]]; then
    printf '%s' "${MOCK_WHIPTAIL_CHOICE:-MFA}" >&2
    exit 0
fi
if [[ "$*" == *"--yesno"* ]] || [[ "$*" == *"--msgbox"* ]]; then
    exit 0
fi
exit 90
EOF
cat >"$test_dir/bin/curl" <<'EOF'
#!/usr/bin/bash
[[ " $* " == *" --connect-timeout 10 "* ]] || exit 91
[[ " $* " == *" --max-time 30 "* ]] || exit 92
url=""
method="GET"
previous=""
for argument in "$@"; do
    [[ "$argument" == https://* ]] && url="$argument"
    [ "$previous" = "-X" ] && method="$argument"
    previous="$argument"
done
[ -z "${MOCK_CURL_LOG:-}" ] || printf '%s %s\n' "$method" "$url" >>"$MOCK_CURL_LOG"
case "$MOCK_CURL_MODE" in
    success)
        case "$url" in
            */access/organizations)
                printf '%s\n' '{"success":true,"result":{"auth_domain":"setupmno.cloudflareaccess.com","mfa_config":{"allowed_authenticators":["totp","security_key"]}}}'
                ;;
            */access/apps*)
                if [ "$method" = "POST" ]; then
                    printf '%s\n' '{"success":true,"result":{"id":"11111111-2222-3333-4444-555555555555","aud":"setupmno-test-audience-12345678901234567890"}}'
                else
                    printf '%s\n' '{"success":true,"result":[]}'
                fi
                ;;
            *)
                if [ "$method" = "GET" ]; then
                    printf '%s\n' '{"success":true,"result":{"config":{"ingress":[{"hostname":"control.example.com","service":"http://mnoctrlabc1234-web_mnoctrlabc1234-web:8080"},{"service":"http_status:404"}]}}}'
                else
                    printf '%s\n' '{"success":true,"result":{}}'
                fi
                ;;
        esac
        ;;
    mfa_missing)
        case "$url" in
            */access/organizations)
                printf '%s\n' '{"success":true,"result":{"auth_domain":"setupmno.cloudflareaccess.com","mfa_config":{"allowed_authenticators":[]}}}'
                ;;
            */access/apps*) printf '%s\n' '{"success":true,"result":[]}' ;;
            *) printf '%s\n' '{"success":true,"result":{"config":{"ingress":[]}}}' ;;
        esac
        ;;
    mfa_upgrade)
        case "$url" in
            */access/organizations)
                printf '%s\n' '{"success":true,"result":{"auth_domain":"setupmno.cloudflareaccess.com","mfa_config":{"allowed_authenticators":["totp","security_key"]}}}'
                ;;
            */access/apps/11111111-2222-3333-4444-555555555555/policies/aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee)
                [ "$method" = "PUT" ] || exit 94
                printf '%s\n' '{"success":true,"result":{"id":"aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee","mfa_config":{"mfa_disabled":false}}}'
                ;;
            */access/apps/11111111-2222-3333-4444-555555555555)
                printf '%s\n' '{"success":true,"result":{"id":"11111111-2222-3333-4444-555555555555","aud":"setupmno-test-audience","policies":[{"id":"aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee","name":"Setup MNO - identidade autorizada sem MFA extra","decision":"allow","precedence":1,"include":[{"email":{"email":"admin@example.com"}}],"exclude":[],"require":[],"mfa_config":{"mfa_disabled":true}}]}}'
                ;;
            */access/apps*)
                printf '%s\n' '{"success":true,"result":[{"id":"11111111-2222-3333-4444-555555555555","aud":"setupmno-test-audience"}]}'
                ;;
            *) exit 95 ;;
        esac
        ;;
    restore_original)
        case "$url" in
            */access/apps/11111111-2222-3333-4444-555555555555)
                [ "$method" = "DELETE" ] || exit 96
                printf '%s\n' '{"success":true,"result":{"id":"11111111-2222-3333-4444-555555555555"}}'
                ;;
            */access/apps\?per_page=100)
                printf '%s\n' '{"success":true,"result":[{"id":"11111111-2222-3333-4444-555555555555","aud":"setupmno-test-audience","domain":"control.example.com","destinations":[{"type":"public","uri":"control.example.com"}]}]}'
                ;;
            */configurations)
                if [ "$method" = "PUT" ]; then
                    printf '%s\n' '{"success":true,"result":{}}'
                else
                    printf '%s\n' '{"success":true,"result":{"config":{"ingress":[{"hostname":"control.example.com","service":"http://mnoctrlabc1234-web_mnoctrlabc1234-web:8080","originRequest":{"access":{"required":true,"teamName":"setupmno","audTag":["setupmno-test-audience"]}}},{"service":"http_status:404"}]}}}'
                fi
                ;;
            *) exit 97 ;;
        esac
        ;;
    restore_original_missing_app)
        case "$url" in
            */access/apps\?per_page=100)
                printf '%s\n' '{"success":true,"result":[]}'
                ;;
            */configurations)
                if [ "$method" = "PUT" ]; then
                    printf '%s\n' '{"success":true,"result":{}}'
                else
                    printf '%s\n' '{"success":true,"result":{"config":{"ingress":[{"hostname":"control.example.com","service":"http://mnoctrlabc1234-web_mnoctrlabc1234-web:8080","originRequest":{"access":{"required":true,"teamName":"setupmno","audTag":["setupmno-test-audience"]}}},{"service":"http_status:404"}]}}}'
                fi
                ;;
            *) exit 98 ;;
        esac
        ;;
    existing_access)
        case "$url" in
            */access/organizations)
                printf '%s\n' '{"success":true,"result":{"auth_domain":"setupmno.cloudflareaccess.com","mfa_config":{"allowed_authenticators":["totp"]}}}'
                ;;
            */access/apps*)
                printf '%s\n' '{"success":true,"result":[{"id":"existing-id","domain":"control.example.com","destinations":[{"type":"public","uri":"control.example.com"}]}]}'
                ;;
            *) printf '%s\n' '{"success":true,"result":{"config":{"ingress":[]}}}' ;;
        esac
        ;;
    sem_mfa_exact)
        case "$url" in
            */access/apps/11111111-2222-3333-4444-555555555555)
                [ "$method" = "DELETE" ] || exit 99
                printf '%s\n' '{"success":true,"result":{"id":"11111111-2222-3333-4444-555555555555"}}'
                ;;
            */access/apps\?per_page=100)
                printf '%s\n' '{"success":true,"result":[{"id":"11111111-2222-3333-4444-555555555555","name":"Setup antigo","domain":"control.example.com","destinations":[{"type":"public","uri":"control.example.com"}]},{"id":"aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee","name":"Proteção wildcard","domain":"*.example.com","destinations":[{"type":"public","uri":"*.example.com"}]}]}'
                ;;
            *) exit 99 ;;
        esac
        ;;
    sem_mfa_wildcard)
        case "$url" in
            */access/apps\?per_page=100)
                printf '%s\n' '{"success":true,"result":[{"id":"aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee","name":"Proteção wildcard","domain":"*.example.com","destinations":[{"type":"public","uri":"*.example.com"}]}]}'
                ;;
            *) exit 99 ;;
        esac
        ;;
    sem_mfa_shared)
        case "$url" in
            */access/apps\?per_page=100)
                printf '%s\n' '{"success":true,"result":[{"id":"11111111-2222-3333-4444-555555555555","name":"Aplicação compartilhada","domain":"control.example.com","destinations":[{"type":"public","uri":"control.example.com"},{"type":"public","uri":"outro.example.com"}]}]}'
                ;;
            *) exit 99 ;;
        esac
        ;;
    sem_mfa_changed)
        case "$url" in
            */access/apps\?per_page=100)
                printf '%s\n' '{"success":true,"result":[{"id":"99999999-2222-3333-4444-555555555555","name":"Aplicação substituída","domain":"control.example.com","destinations":[{"type":"public","uri":"control.example.com"}]}]}'
                ;;
            *) exit 99 ;;
        esac
        ;;
    timeout)
        exit 28
        ;;
    invalid)
        printf '%s\n' '{"success":false,"errors":[{"message":"denied"}]}'
        ;;
    *)
        exit 93
        ;;
esac
EOF
cat >"$test_dir/bin/docker" <<'EOF'
#!/usr/bin/bash
if [ "${1:-}" = "service" ] && [ "${2:-}" = "inspect" ]; then
    case "${MOCK_ACCESS_STATE:-missing}" in
        ready|ready_mfa)
            printf '%s\n' \
                'ACCESS_JWT_REQUIRED=true' \
                'ACCESS_TEAM_DOMAIN=https://setupmno.cloudflareaccess.com' \
                'ACCESS_POLICY_AUD=setupmno-test-audience' \
                'ACCESS_ALLOWED_EMAIL=admin@example.com' \
                "ACCESS_MFA_REQUIRED=$([ "${MOCK_ACCESS_STATE}" = ready_mfa ] && printf true || printf false)"
            ;;
        partial)
            printf '%s\n' 'ACCESS_JWT_REQUIRED=true'
            ;;
    esac
    exit 0
fi
if [ "${1:-}" = "service" ] && [ "${2:-}" = "update" ]; then
    printf '%s\n' "$*" >>"$MOCK_DOCKER_LOG"
    exit 0
fi
if [ "${MOCK_CONTROL_CENTER:-absent}" = "installed" ]; then
    printf '%s\n' 'mnoctrlabc1234-web_mnoctrlabc1234-web'
else
    printf '%s\n' 'portainer_portainer'
fi
EOF
chmod 0755 "$test_dir/bin/whiptail" "$test_dir/bin/curl" "$test_dir/bin/docker"
PATH="$test_dir/bin:$PATH"

# A lógica detalhada do assistente vive no bundle autenticado e possui suíte
# própria. Aqui isolamos apenas a integração do template com esse contrato.
load_cloudflare_mfa_helper() { return 0; }
prepare_cloudflare_mfa_token() { return 0; }
prepare_cloudflare_mfa_deactivation() { return 0; }
prepare_cloudflare_mfa_enrollment_email() { printf '%s\n' "$1"; }
ensure_cloudflare_mfa_onboarding() {
    jq -n '{active:true}' >"$4"
}
rollback_cloudflare_mfa_onboarding() { return 0; }
remove_setupmno_launcher_policy() { return 0; }
ensure_cloudflare_access_cookie_lax() { return 0; }
cf_mfa_error() { printf '%s' 'erro simulado'; }

write_control_mfa_state false false false test-original
control_mfa_state_valid
jq -e '.desiredMFA == false and .effectiveMFA == false and
       .activationPromptPending == false and .source == "test-original"' \
    "$CONTROL_MFA_STATE_FILE" >/dev/null
write_control_mfa_state true false true test-requested
jq -e '.desiredMFA == true and .effectiveMFA == false and
       .activationPromptPending == true' "$CONTROL_MFA_STATE_FILE" >/dev/null
if write_control_mfa_state false true false invalid-state; then
    printf 'ERRO: combinação impossível de estado MFA foi aceita.\n' >&2
    exit 1
fi

control_function_source=$(awk '
    /^control_center_installed\(\)/ { inside=1 }
    inside { print }
    inside && /^}/ { exit }
' "$template")
[ -n "$control_function_source" ]
eval "$control_function_source"
export MOCK_CONTROL_CENTER="installed"
control_center_installed
export MOCK_CONTROL_CENTER="absent"
if control_center_installed; then
    printf 'ERRO: serviço não relacionado foi identificado como Control Center.\n' >&2
    exit 1
fi

export MOCK_CURL_MODE="success"
: >"$message_capture"
url_control="control.example.com"
access_mfa_enabled="true"
organization_output="$test_dir/organization.json"
applications_output="$test_dir/applications.json"
check_cloudflare_access "$organization_output" "$applications_output"
[ "$access_team_domain" = "https://setupmno.cloudflareaccess.com" ]
[ "$access_team_name" = "setupmno" ]
[ ! -s "$message_capture" ]

export MOCK_CURL_MODE="mfa_missing"
: >"$message_capture"
check_cloudflare_access "$organization_output" "$applications_output"
access_mfa_enabled="false"
check_cloudflare_access "$organization_output" "$applications_output"

mfa_payload="$test_dir/access-mfa.json"
simple_payload="$test_dir/access-simple.json"
build_cloudflare_access_payload "$mfa_payload" "Control" \
    "control.example.com" "admin@example.com" true
build_cloudflare_access_payload "$simple_payload" "Control" \
    "control.example.com" "admin@example.com" false
jq -e '.mfa_config.mfa_disabled == false and
       .same_site_cookie_attribute == "lax" and
       .mfa_config.session_duration == "8h" and
       .mfa_config.allowed_authenticators == ["totp"] and
       .policies[0].mfa_config.mfa_disabled == false and
       .policies[0].include[0].email.email == "admin@example.com"' \
    "$mfa_payload" >/dev/null
jq -e '.mfa_config.mfa_disabled == true and
       .policies[0].mfa_config.mfa_disabled == true and
       (.policies[0].name | contains("sem MFA extra"))' \
    "$simple_payload" >/dev/null

tunnel_fixture="$test_dir/tunnel-fixture.json"
tunnel_original_route="$test_dir/tunnel-original-route.json"
tunnel_mfa_route="$test_dir/tunnel-mfa-route.json"
printf '%s\n' '{"result":{"config":{"ingress":[{"service":"http_status:404"}]}}}' >"$tunnel_fixture"
build_control_tunnel_route_payload "$tunnel_fixture" "$tunnel_original_route" \
    "control.example.com" "http://control:8080" false "" ""
build_control_tunnel_route_payload "$tunnel_fixture" "$tunnel_mfa_route" \
    "control.example.com" "http://control:8080" true "setupmno" "test-aud"
jq -e '.config.ingress[0].originRequest.access? == null and
       .config.ingress[0].service == "http://control:8080"' \
    "$tunnel_original_route" >/dev/null
jq -e '.config.ingress[0].originRequest.access.required == true and
       .config.ingress[0].originRequest.access.teamName == "setupmno"' \
    "$tunnel_mfa_route" >/dev/null

export MOCK_WHIPTAIL_CHOICE="MFA"
choose_cloudflare_access_security
[ "$access_mfa_enabled" = "true" ]
export MOCK_WHIPTAIL_CHOICE="SEM_MFA"
choose_cloudflare_access_security
[ "$access_mfa_enabled" = "false" ]
show_cloudflare_access_guide
choose_source=$(awk '/^choose_cloudflare_access_security\(\)/,/^}/' "$template")
collect_source=$(awk '/^collect_cloudflare_access_email\(\)/,/^}/' "$template")
! grep -Fq -- '--yesno' <<<"$choose_source"
! grep -Fq -- '--yesno' <<<"$collect_source"

export MOCK_CURL_MODE="existing_access"
: >"$message_capture"
if check_cloudflare_access "$organization_output" "$applications_output"; then
    printf 'ERRO: política Access preexistente foi sobrescrita.\n' >&2
    exit 1
fi
grep -Fq 'Já existe um aplicativo Cloudflare Access' "$message_capture"

sem_mfa_fixture="$test_dir/sem-mfa-fixture.json"
sem_mfa_inventory="$test_dir/sem-mfa-inventory.json"
printf '%s\n' '{"success":true,"result":[{"id":"11111111-2222-3333-4444-555555555555","name":"Setup antigo","domain":"https://CONTROL.EXAMPLE.COM/path"},{"id":"aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee","name":"Wildcard","destinations":[{"type":"public","uri":"*.example.com"}]},{"id":"bbbbbbbb-cccc-dddd-eeee-ffffffffffff","name":"Outro wildcard","domain":"*.other.example"}]}' >"$sem_mfa_fixture"
build_access_hostname_inventory "$sem_mfa_fixture" "control.example.com" "$sem_mfa_inventory"
jq -e '.hostname == "control.example.com" and
       (.exactApps | length) == 1 and
       .exactApps[0].id == "11111111-2222-3333-4444-555555555555" and
       (.wildcardApps | length) == 1 and
       .wildcardApps[0].id == "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"' \
    "$sem_mfa_inventory" >/dev/null

export MOCK_CURL_MODE="sem_mfa_exact" MOCK_WHIPTAIL_CHOICE="REMOVER"
export MOCK_CURL_LOG="$test_dir/sem-mfa-curl.log"
: >"$MOCK_CURL_LOG"
url_control="control.example.com"
inspect_sem_mfa_access_conflicts
[ "$sem_mfa_access_decision" = "REMOVE" ]
[ "$sem_mfa_access_app_id" = "11111111-2222-3333-4444-555555555555" ]
sem_mfa_remove_work="$test_dir/sem-mfa-remove"
mkdir -p "$sem_mfa_remove_work"
remove_confirmed_sem_mfa_access_app "$sem_mfa_remove_work" "$test_dir/sem-mfa-remove.log"
grep -Fxq 'DELETE https://api.cloudflare.com/client/v4/accounts/test-account/access/apps/11111111-2222-3333-4444-555555555555' "$MOCK_CURL_LOG"
if grep -E '^DELETE .*(cfd_tunnel|dns_records)' "$MOCK_CURL_LOG"; then
    printf 'ERRO: reconciliação SEM_MFA alterou Tunnel ou DNS.\n' >&2
    exit 1
fi
grep -Fq 'Tunnel, DNS e wildcards preservados' "$test_dir/sem-mfa-remove.log"

export MOCK_CURL_MODE="sem_mfa_exact" MOCK_WHIPTAIL_CHOICE="MANTER"
: >"$MOCK_CURL_LOG"
inspect_sem_mfa_access_conflicts
[ "$sem_mfa_access_decision" = "KEEP" ]
remove_confirmed_sem_mfa_access_app "$sem_mfa_remove_work" "$test_dir/sem-mfa-keep.log"
if grep -Fq 'DELETE ' "$MOCK_CURL_LOG"; then
    printf 'ERRO: opção MANTER removeu a aplicação Access existente.\n' >&2
    exit 1
fi

export MOCK_CURL_MODE="sem_mfa_wildcard" MOCK_WHIPTAIL_CHOICE="MANTER"
: >"$MOCK_CURL_LOG"
inspect_sem_mfa_access_conflicts
[ "$sem_mfa_access_decision" = "KEEP" ]
[ -z "$sem_mfa_access_app_id" ]
if grep -Fq 'DELETE ' "$MOCK_CURL_LOG"; then
    printf 'ERRO: wildcard Access foi removido automaticamente.\n' >&2
    exit 1
fi

export MOCK_CURL_MODE="sem_mfa_shared" MOCK_WHIPTAIL_CHOICE="MANTER"
: >"$MOCK_CURL_LOG"
inspect_sem_mfa_access_conflicts
[ "$sem_mfa_access_decision" = "KEEP" ]
if grep -Fq 'DELETE ' "$MOCK_CURL_LOG"; then
    printf 'ERRO: aplicação Access compartilhada foi removida automaticamente.\n' >&2
    exit 1
fi

export MOCK_CURL_MODE="sem_mfa_exact" MOCK_WHIPTAIL_CHOICE="VOLTAR"
if inspect_sem_mfa_access_conflicts; then
    printf 'ERRO: opção VOLTAR não interrompeu a reconciliação Access.\n' >&2
    exit 1
else
    [ "$?" -eq 20 ]
fi

export MOCK_CURL_MODE="sem_mfa_changed" MOCK_WHIPTAIL_CHOICE="REMOVER"
sem_mfa_access_decision="REMOVE"
sem_mfa_access_app_id="11111111-2222-3333-4444-555555555555"
: >"$MOCK_CURL_LOG"
if remove_confirmed_sem_mfa_access_app "$sem_mfa_remove_work" "$test_dir/sem-mfa-changed.log"; then
    printf 'ERRO: aplicação Access alterada após confirmação foi removida.\n' >&2
    exit 1
fi
if grep -Fq 'DELETE ' "$MOCK_CURL_LOG"; then
    printf 'ERRO: revalidação divergente executou DELETE.\n' >&2
    exit 1
fi

export MOCK_CURL_MODE="success" MOCK_ACCESS_STATE="missing"
export MOCK_WHIPTAIL_CHOICE="MFA"
export MOCK_DOCKER_LOG="$test_dir/docker.log"
: >"$MOCK_DOCKER_LOG"
INSTALL_TYPE="CLOUDFLARE_TUNNEL"
CLOUDFLARE_ZONE_ID="test-zone"
migration_state="$test_dir/migration-state.json"
migration_work="$test_dir/migration-work"
mkdir -p "$migration_work"
prepare_existing_access_migration \
    "mnoctrlabc1234-web_mnoctrlabc1234-web" \
    "$migration_work" "$test_dir/migration.log" "$migration_state"
jq -e '.active == false' "$migration_state" >/dev/null
[ ! -s "$MOCK_DOCKER_LOG" ]
prepare_existing_access_migration \
    "mnoctrlabc1234-web_mnoctrlabc1234-web" \
    "$migration_work" "$test_dir/migration.log" "$migration_state" activate-mfa
jq -e '.active == true and .appId == "11111111-2222-3333-4444-555555555555"' \
    "$migration_state" >/dev/null
grep -Fq -- '--env-add ACCESS_JWT_REQUIRED=true' "$MOCK_DOCKER_LOG"
grep -Fq -- '--env-add ACCESS_ALLOWED_EMAIL=admin@example.com' "$MOCK_DOCKER_LOG"
rollback_existing_access_migration "$migration_state" "$test_dir/migration.log"
grep -Fq -- '--env-rm ACCESS_JWT_REQUIRED' "$MOCK_DOCKER_LOG"

export MOCK_ACCESS_STATE="partial"
: >"$message_capture"
if prepare_existing_access_migration \
    "mnoctrlabc1234-web_mnoctrlabc1234-web" \
    "$migration_work" "$test_dir/migration.log" "$migration_state"; then
    printf 'ERRO: metadados Access parciais foram sobrescritos.\n' >&2
    exit 1
fi
grep -Fq 'metadados Cloudflare Access parciais ou inconsistentes' "$message_capture"

export MOCK_CURL_MODE="restore_original" MOCK_ACCESS_STATE="ready" MOCK_CONTROL_CENTER="installed"
export MOCK_CURL_LOG="$test_dir/curl.log"
: >"$MOCK_DOCKER_LOG"
: >"$MOCK_CURL_LOG"
prepare_existing_access_migration \
    "mnoctrlabc1234-web_mnoctrlabc1234-web" \
    "$migration_work" "$test_dir/migration.log" "$migration_state"
grep -Fq -- '--env-rm ACCESS_JWT_REQUIRED' "$MOCK_DOCKER_LOG"
grep -Fq -- '--env-add ACCESS_JWT_REQUIRED=false' "$MOCK_DOCKER_LOG"
grep -Fq 'DELETE https://api.cloudflare.com/client/v4/accounts/test-account/access/apps/11111111-2222-3333-4444-555555555555' "$MOCK_CURL_LOG"

export MOCK_CURL_MODE="mfa_upgrade" MOCK_ACCESS_STATE="ready" MOCK_CONTROL_CENTER="installed"
export MOCK_WHIPTAIL_CHOICE="ATIVAR"
: >"$message_capture"
: >"$MOCK_DOCKER_LOG"
configure_existing_access_mfa
grep -Fq -- '--env-rm ACCESS_MFA_REQUIRED --env-add ACCESS_MFA_REQUIRED=true' "$MOCK_DOCKER_LOG"
grep -Fq 'MFA ATIVADO!' "$message_capture"
grep -Fq 'NÃO use o e-mail original' "$message_capture"
grep -Fq 'Digite exatamente o endereço acima' "$message_capture"
jq -e '.desiredMFA == true and .effectiveMFA == true' "$CONTROL_MFA_STATE_FILE" >/dev/null

export MOCK_CURL_MODE="restore_original" MOCK_ACCESS_STATE="ready_mfa" MOCK_WHIPTAIL_CHOICE="DESATIVAR"
: >"$message_capture"
: >"$MOCK_DOCKER_LOG"
: >"$MOCK_CURL_LOG"
configure_existing_access_mfa
grep -Fq 'MFA DESATIVADO COM SUCESSO' "$message_capture"
grep -Fq -- '--env-add ACCESS_JWT_REQUIRED=false' "$MOCK_DOCKER_LOG"
grep -Fq 'Ativando login local e Terminal Remoto' "$gauge_capture"
grep -Fq 'Modo original restaurado com sucesso.' "$gauge_capture"
jq -e '.desiredMFA == false and .effectiveMFA == false and
       .activationPromptPending == false' "$CONTROL_MFA_STATE_FILE" >/dev/null

write_control_mfa_state true true false test-app-removed
export MOCK_CURL_MODE="restore_original_missing_app" MOCK_ACCESS_STATE="ready_mfa"
: >"$message_capture"
: >"$gauge_capture"
: >"$MOCK_DOCKER_LOG"
: >"$MOCK_CURL_LOG"
configure_existing_access_mfa
grep -Fq 'MFA DESATIVADO COM SUCESSO' "$message_capture"
grep -Fq -- '--env-add ACCESS_JWT_REQUIRED=false' "$MOCK_DOCKER_LOG"
grep -Fq 'Modo original restaurado com sucesso.' "$gauge_capture"
if grep -Fq 'DELETE https://api.cloudflare.com/client/v4/accounts/test-account/access/apps/' "$MOCK_CURL_LOG"; then
    printf 'ERRO: desativação tentou remover novamente uma aplicação Access já ausente.\n' >&2
    exit 1
fi
jq -e '.desiredMFA == false and .effectiveMFA == false and
       .activationPromptPending == false' "$CONTROL_MFA_STATE_FILE" >/dev/null

application_fixture="$test_dir/application-fixture.json"
policy_fixture="$test_dir/policy-fixture.json"
printf '%s\n' '{"result":{"policies":[{"id":"aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee","name":"Setup MNO","decision":"allow","include":[{"email":{"email":"admin@example.com"}}]}]}}' >"$application_fixture"
build_existing_access_policy_payload "$application_fixture" "$policy_fixture" \
    "admin@example.com" true
jq -e '.mfa_config.mfa_disabled == false and .include[0].email.email == "admin@example.com"' \
    "$policy_fixture" >/dev/null
jq -e '.mfa_config.session_duration == "8h" and
       .mfa_config.allowed_authenticators == ["totp"]' "$policy_fixture" >/dev/null

printf 'Progresso, timeout, Access e MFA do Cloudflare aprovados.\n'

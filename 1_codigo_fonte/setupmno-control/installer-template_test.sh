#!/usr/bin/bash
set -euo pipefail

project_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
template="$project_dir/installer-template.sh"
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
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT

function_source=$(awk '
    /^check_cloudflare_route\(\)/ { inside=1 }
    inside { print }
    inside && /^}/ { exit }
' "$template")
[ -n "$function_source" ] || {
    printf 'ERRO: função check_cloudflare_route ausente.\n' >&2
    exit 1
}
eval "$function_source"

access_function_source=$(awk '
    /^check_cloudflare_access\(\)/ { inside=1 }
    inside { print }
    inside && /^}/ { exit }
' "$template")
[ -n "$access_function_source" ] || {
    printf 'ERRO: função check_cloudflare_access ausente.\n' >&2
    exit 1
}
eval "$access_function_source"

for migration_function in \
    show_cloudflare_access_guide \
    choose_cloudflare_access_security \
    collect_cloudflare_access_email \
    build_cloudflare_access_payload \
    control_service_env_value \
    rollback_existing_access_migration \
    prepare_existing_access_migration \
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
CLOUDFLARE_API_TOKEN="test-token-not-secret"
CLOUDFLARE_ACCOUNT_ID="test-account"
TUNNEL_ID="test-tunnel"
message_capture="$test_dir/message.txt"
gauge_capture="$test_dir/gauge.txt"
export MOCK_CURL_MODE="success" GAUGE_CAPTURE="$gauge_capture"

msg() {
    printf '%s' "$1" >"$message_capture"
}

ask_required() {
    printf '%s' 'admin@example.com'
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
        ready)
            printf '%s\n' \
                'ACCESS_JWT_REQUIRED=true' \
                'ACCESS_TEAM_DOMAIN=https://setupmno.cloudflareaccess.com' \
                'ACCESS_POLICY_AUD=setupmno-test-audience' \
                'ACCESS_ALLOWED_EMAIL=admin@example.com' \
                'ACCESS_MFA_REQUIRED=false'
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

route_output="$test_dir/route.json"
check_cloudflare_route "$route_output"
jq -e '.success == true' "$route_output" >/dev/null
grep -Fq 'CONECTANDO À API DO CLOUDFLARE' "$gauge_capture"
grep -Fq 'VERIFICAÇÃO DO CLOUDFLARE CONCLUÍDA' "$gauge_capture"
[ ! -s "$message_capture" ]

export MOCK_CURL_MODE="timeout"
: >"$message_capture"
if check_cloudflare_route "$route_output"; then
    printf 'ERRO: timeout do Cloudflare foi aceito.\n' >&2
    exit 1
fi
grep -Fq 'não respondeu em até 30 segundos' "$message_capture"

export MOCK_CURL_MODE="invalid"
: >"$message_capture"
if check_cloudflare_route "$route_output"; then
    printf 'ERRO: resposta inválida do Cloudflare foi aceita.\n' >&2
    exit 1
fi
grep -Fq 'resposta inválida' "$message_capture"

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
if check_cloudflare_access "$organization_output" "$applications_output"; then
    printf 'ERRO: organização sem MFA foi aceita.\n' >&2
    exit 1
else
    [ "$?" -eq 42 ] || {
        printf 'ERRO: ausência de MFA não retornou o diagnóstico esperado.\n' >&2
        exit 1
    }
fi
access_mfa_enabled="false"
check_cloudflare_access "$organization_output" "$applications_output"

mfa_payload="$test_dir/access-mfa.json"
simple_payload="$test_dir/access-simple.json"
build_cloudflare_access_payload "$mfa_payload" "Control" \
    "control.example.com" "admin@example.com" true
build_cloudflare_access_payload "$simple_payload" "Control" \
    "control.example.com" "admin@example.com" false
jq -e '.mfa_config.mfa_disabled == false and
       .policies[0].mfa_config.mfa_disabled == false and
       .policies[0].include[0].email.email == "admin@example.com"' \
    "$mfa_payload" >/dev/null
jq -e '.mfa_config.mfa_disabled == true and
       .policies[0].mfa_config.mfa_disabled == true and
       (.policies[0].name | contains("sem MFA extra"))' \
    "$simple_payload" >/dev/null

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

export MOCK_CURL_MODE="mfa_upgrade" MOCK_ACCESS_STATE="ready" MOCK_CONTROL_CENTER="installed"
: >"$message_capture"
: >"$MOCK_DOCKER_LOG"
configure_existing_access_mfa
grep -Fq -- '--env-rm ACCESS_MFA_REQUIRED --env-add ACCESS_MFA_REQUIRED=true' "$MOCK_DOCKER_LOG"
grep -Fq 'MFA ATIVADO COM SUCESSO' "$message_capture"

application_fixture="$test_dir/application-fixture.json"
policy_fixture="$test_dir/policy-fixture.json"
printf '%s\n' '{"result":{"policies":[{"id":"aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee","name":"Setup MNO","decision":"allow","include":[{"email":{"email":"admin@example.com"}}]}]}}' >"$application_fixture"
build_existing_access_policy_payload "$application_fixture" "$policy_fixture" \
    "admin@example.com" true
jq -e '.mfa_config.mfa_disabled == false and .include[0].email.email == "admin@example.com"' \
    "$policy_fixture" >/dev/null

printf 'Progresso, timeout, Access e MFA do Cloudflare aprovados.\n'

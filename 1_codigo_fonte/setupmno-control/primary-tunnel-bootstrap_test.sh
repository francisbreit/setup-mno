#!/usr/bin/bash
set -euo pipefail

project_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source_root=$(cd "$project_dir/.." && pwd)
x86="$source_root/x86/SetupLowCodeMno/dockerswarm.sh"
arm="$source_root/arm/SetupLowCodeMno/dockerswarm.sh"
temporary_dir=$(mktemp -d)
trap 'rm -rf "$temporary_dir"' EXIT

extract_primary_tunnel_runtime() {
    sed -n '/^normalize_cloudflare_hostname()/,/^# FIM DE LOADING/p' "$1" | sed '$d'
}

extract_primary_tunnel_runtime "$x86" >"$temporary_dir/x86-runtime.sh"
extract_primary_tunnel_runtime "$arm" >"$temporary_dir/arm-runtime.sh"
cmp -s "$temporary_dir/x86-runtime.sh" "$temporary_dir/arm-runtime.sh" || {
    printf 'ERRO: fluxo do Tunnel principal diverge entre x86 e ARM.\n' >&2
    exit 1
}

for script in "$x86" "$arm"; do
    bash -n "$script"
    grep -Fq '"AUTO" "Criar e validar automaticamente — RECOMENDADO"' "$script"
    grep -Fq '"EXISTENTE" "Informar Tunnel ID — método clássico"' "$script"
    grep -Fq 'TUNNEL_OWNERSHIP="external"' "$script"
    grep -Fq 'TUNNEL_OWNERSHIP="setupmno"' "$script"
    grep -Fq 'command: tunnel run --token-file /run/secrets/' "$script"
    grep -Fq 'SETUPMNO_PRIMARY_DNS_RECORD_ID=' "$script"
    grep -Fq 'INSTALL_GAUGE_STATUS=$?' "$script"
    grep -Fq 'set -o pipefail' "$script"
    grep -Fq 'discover_cloudflare_zone_context "$CLOUDFLARE_API_TOKEN" "$hostname"' "$script"
    grep -Fq 'discover_cloudflare_zone_context "$CLOUDFLARE_API_TOKEN2" "$dominio"' "$script"
    grep -Fq 'CLOUDFLARE_ACCOUNT_ID2="$CLOUDFLARE_ACCOUNT_ID"' "$script"
    grep -Fq 'CLOUDFLARE_ZONE_ID2="$CLOUDFLARE_ZONE_ID"' "$script"
    grep -Fq 'CLOUDFLARE_ZONE_NAME2="$CLOUDFLARE_ZONE_NAME"' "$script"
    grep -Fq 'DOMINIO_PRINCIPAL="$CLOUDFLARE_ZONE_NAME"' "$script"
    grep -Fq 'DOMINIO_PRINCIPAL="$CLOUDFLARE_ZONE_NAME2"' "$script"
    grep -Fq 'primary_tunnel_random_name()' "$script"
    grep -Fq 'primary_tunnel_get_configuration()' "$script"
    grep -Fq 'primary_tunnel_wait_for_route()' "$script"
    grep -Fq 'SETUPMNO_PRIMARY_TUNNEL_CONFIG_MAY_BE_EMPTY' "$script"
    grep -Fq 'HTTP ${PRIMARY_TUNNEL_HTTP_CODE:-indisponível}' "$script"
    grep -Fq 'primary_tunnel_get_configuration "$BACKUP_RAW"' "$script"
    grep -Fq 'primary_tunnel_wait_for_route "$VERIFY_RESPONSE" "$dominio" "$NEW_SERVICE"' "$script"
    grep -Fq 'setupmnoInitialEmpty == true' "$script"
    ! grep -Fq 'primary_tunnel_deterministic_name' "$script" || {
        printf 'ERRO: nome determinístico do Tunnel ainda existe em %s.\n' "$script" >&2
        exit 1
    }
    grep -Fq -- '--passwordbox' "$script"
    ! grep -Fq -- '--title "Cloudflare Account ID"' "$script" || {
        printf 'ERRO: dockerswarm ainda solicita Account ID manualmente em %s.\n' "$script" >&2
        exit 1
    }
    ! grep -Fq -- '--title "Cloudflare Zone ID"' "$script" || {
        printf 'ERRO: dockerswarm ainda solicita Zone ID manualmente em %s.\n' "$script" >&2
        exit 1
    }
    credentials_function=$(awk '/^primary_tunnel_write_credentials\(\)/,/^}/' "$script")
    grep -Fq 'CLOUDFLARE_ACCOUNT_ID=' <<<"$credentials_function"
    grep -Fq 'CLOUDFLARE_ZONE_ID=' <<<"$credentials_function"
    grep -Fq 'CLOUDFLARE_ZONE_NAME=' <<<"$credentials_function"
    ! grep -Fq 'TUNNEL_TOKEN' <<<"$credentials_function" || {
        printf 'ERRO: Tunnel Token não pode ser persistido nas credenciais em %s.\n' "$script" >&2
        exit 1
    }
done

run_runtime_test() (
    # shellcheck disable=SC1090
    source "$temporary_dir/x86-runtime.sh"
    SETUPMNO_TUNNEL_TEST_MODE=1
    PRIMARY_TUNNEL_STATE_FILE="$temporary_dir/primary-tunnel.json"
    PRIMARY_TUNNEL_LOG="$temporary_dir/primary-tunnel.log"
    CLOUDFLARE_API_TOKEN="token-test"
    CLOUDFLARE_ACCOUNT_ID="account-test"
    CLOUDFLARE_ZONE_ID="zone-test"
    SETUPMNO_TUNNEL_CONFIG_ATTEMPTS=3
    config_scenario=""
    config_calls=0
    first_random_name=$(primary_tunnel_random_name)
    second_random_name=$(primary_tunnel_random_name)
    [[ "$first_random_name" =~ ^setupmno-primary-[0-9a-f]{12}$ ]]
    [[ "$second_random_name" =~ ^setupmno-primary-[0-9a-f]{12}$ ]]
    [ "$first_random_name" != "$second_random_name" ]
    TUNNEL_NAME="$first_random_name"
    api_log="$temporary_dir/api.log"
    : >"$api_log"

    validate_cloudflare_api_token() {
        return 0
    }

    validate_cloudflare_zone_dns() {
        return 0
    }

    curl() {
        local argument url=""
        for argument in "$@"; do
            case "$argument" in
                https://*) url="$argument" ;;
            esac
        done
        case "$url" in
            *'&page=1')
                printf '%s' '{"success":true,"result":[{"id":"zone-root","name":"example.com","account":{"id":"account-root"}}],"result_info":{"total_pages":2}}'
                ;;
            *'&page=2')
                printf '%s' '{"success":true,"result":[{"id":"zone-nested","name":"sub.example.com","account":{"id":"account-nested"}}],"result_info":{"total_pages":2}}'
                ;;
            *)
                printf '%s' '{"success":false,"errors":[{"message":"URL mock inesperada"}]}'
                return 1
                ;;
        esac
    }

    [ "$(normalize_cloudflare_hostname 'HTTPS://Painel.Sub.Example.COM/caminho')" = 'painel.sub.example.com' ]
    discover_cloudflare_zone_context 'token-test' 'painel.sub.example.com'
    [ "$CLOUDFLARE_ZONE_ID" = 'zone-nested' ]
    [ "$CLOUDFLARE_ACCOUNT_ID" = 'account-nested' ]
    [ "$CLOUDFLARE_ZONE_NAME" = 'sub.example.com' ]
    if discover_cloudflare_zone_context 'token-test' 'painel.outro-dominio.com'; then
        printf 'ERRO: descoberta aceitou hostname sem zona correspondente.\n' >&2
        exit 1
    fi

    CLOUDFLARE_ACCOUNT_ID="account-test"
    CLOUDFLARE_ZONE_ID="zone-test"

    primary_tunnel_cf_api() {
        local method="$1" endpoint="$2" output="$3"
        printf '%s %s\n' "$method" "$endpoint" >>"$api_log"
        PRIMARY_TUNNEL_HTTP_CODE=200
        case "$method:$endpoint" in
            GET:*/configurations)
                config_calls=$((config_calls + 1))
                case "$config_scenario" in
                    delayed)
                        if [ "$config_calls" -lt 3 ]; then
                            PRIMARY_TUNNEL_HTTP_CODE=404
                            printf '{"success":false,"errors":[{"code":1003,"message":"Tunnel configuration not found"}]}' >"$output"
                        else
                            printf '{"success":true,"result":{"config":{"ingress":[{"service":"http_status:404"}]}}}' >"$output"
                        fi
                        ;;
                    absent)
                        PRIMARY_TUNNEL_HTTP_CODE=404
                        printf '{"success":false,"errors":[{"code":1003,"message":"Tunnel configuration not found"}]}' >"$output"
                        ;;
                    null_config)
                        printf '{"success":true,"result":{"config":null}}' >"$output"
                        ;;
                    permission)
                        PRIMARY_TUNNEL_HTTP_CODE=403
                        printf '{"success":false,"errors":[{"code":9109,"message":"Unauthorized to access requested resource"}]}' >"$output"
                        ;;
                    route_delayed)
                        if [ "$config_calls" -lt 2 ]; then
                            printf '{"success":true,"result":{"config":{"ingress":[{"service":"http_status:404"}]}}}' >"$output"
                        else
                            printf '{"success":true,"result":{"config":{"ingress":[{"hostname":"portainer.example.com","service":"http://portainer:9000"},{"service":"http_status:404"}]}}}' >"$output"
                        fi
                        ;;
                    *)
                        printf '{"success":true,"result":{"config":{"ingress":[{"service":"http_status:404"}]}}}' >"$output"
                        ;;
                esac
                ;;
            GET:*/cfd_tunnel\?*)
                printf '{"success":true,"result":[]}' >"$output"
                ;;
            POST:*/cfd_tunnel)
                printf '{"success":true,"result":{"id":"auto-tunnel-id","name":"%s","token":"ey-auto-token"}}' \
                    "$TUNNEL_NAME" >"$output"
                ;;
            GET:*/existing-tunnel-id/token)
                printf '{"success":true,"result":"ey-existing-token"}' >"$output"
                ;;
            DELETE:*)
                printf '{"success":true,"result":null}' >"$output"
                ;;
            *)
                printf '{"success":false,"errors":[{"message":"mock inesperado"}]}' >"$output"
                return 1
                ;;
        esac
    }

    primary_tunnel_begin_automatic
    [ "$TUNNEL_ID" = "auto-tunnel-id" ]
    [ "$TUNNEL_OWNERSHIP" = "setupmno" ]
    [ "$SETUPMNO_PRIMARY_TUNNEL_CONFIG_MAY_BE_EMPTY" = "true" ]
    [ "$TUNNEL_NAME" = "$first_random_name" ]
    primary_tunnel_state_valid
    [ "$(jq -r '.status' "$PRIMARY_TUNNEL_STATE_FILE")" = "pending" ]
    [ "$(stat -c '%a' "$PRIMARY_TUNNEL_STATE_FILE")" = "600" ]
    primary_tunnel_rollback
    trap - EXIT
    grep -Fq 'DELETE /accounts/account-test/cfd_tunnel/auto-tunnel-id' "$api_log"
    [ ! -e "$PRIMARY_TUNNEL_STATE_FILE" ]

    : >"$api_log"
    TUNNEL_ID="existing-tunnel-id"
    primary_tunnel_begin_existing
    [ "$TUNNEL_OWNERSHIP" = "external" ]
    [ "$SETUPMNO_PRIMARY_TUNNEL_CONFIG_MAY_BE_EMPTY" = "false" ]
    primary_tunnel_rollback
    trap - EXIT
    ! grep -Fq 'DELETE /accounts/account-test/cfd_tunnel/existing-tunnel-id' "$api_log"
    [ ! -e "$PRIMARY_TUNNEL_STATE_FILE" ]

    config_output="$temporary_dir/configuration.json"
    config_scenario=delayed
    config_calls=0
    primary_tunnel_get_configuration "$config_output" false
    [ "$config_calls" -eq 3 ]
    jq -e '.success == true and .result.config.ingress[0].service == "http_status:404"' \
        "$config_output" >/dev/null

    config_scenario=absent
    config_calls=0
    primary_tunnel_get_configuration "$config_output" true
    [ "$config_calls" -eq 3 ]
    jq -e '.success == true and .setupmnoInitialEmpty == true and .result.config == {}' \
        "$config_output" >/dev/null

    config_scenario=null_config
    config_calls=0
    primary_tunnel_get_configuration "$config_output" true
    [ "$config_calls" -eq 3 ]
    jq -e '.setupmnoInitialEmpty == true and .result.config == {}' "$config_output" >/dev/null

    config_calls=0
    if primary_tunnel_get_configuration "$config_output" false; then
        printf 'ERRO: Tunnel externo aceitou configuração ausente.\n' >&2
        exit 1
    fi
    [ "$config_calls" -eq 3 ]

    config_scenario=permission
    config_calls=0
    if primary_tunnel_get_configuration "$config_output" true; then
        printf 'ERRO: HTTP 403 foi confundido com configuração inicial vazia.\n' >&2
        exit 1
    fi
    [ "$config_calls" -eq 1 ]
    [[ "$CLOUDFLARE_VALIDATION_ERROR" == *"HTTP 403"* ]]

    config_scenario=route_delayed
    config_calls=0
    primary_tunnel_wait_for_route "$config_output" \
        "portainer.example.com" "http://portainer:9000"
    [ "$config_calls" -eq 2 ]

    printf '{"schemaVersion":1,"status":"corrompido"}' >"$PRIMARY_TUNNEL_STATE_FILE"
    chmod 600 "$PRIMARY_TUNNEL_STATE_FILE"
    : >"$api_log"
    if primary_tunnel_begin_automatic; then
        printf 'ERRO: estado local inválido permitiu criar outro Tunnel.\n' >&2
        exit 1
    fi
    ! grep -Fq 'POST /accounts/account-test/cfd_tunnel' "$api_log"
    rm -f "$PRIMARY_TUNNEL_STATE_FILE"
)

run_runtime_test
printf 'OK: criação automática e proteção do Tunnel externo validadas.\n'

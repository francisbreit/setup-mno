#!/usr/bin/bash
set -euo pipefail

project_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source_root=$(cd "$project_dir/.." && pwd)
x86="$source_root/x86/SetupLowCodeMno/dockerswarm.sh"
arm="$source_root/arm/SetupLowCodeMno/dockerswarm.sh"
temporary_dir=$(mktemp -d)
trap 'rm -rf "$temporary_dir"' EXIT

extract_primary_tunnel_runtime() {
    sed -n '/^PRIMARY_TUNNEL_STATE_FILE=/,/^# FIM DE LOADING/p' "$1" | sed '$d'
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
    credentials_function=$(awk '/^primary_tunnel_write_credentials\(\)/,/^}/' "$script")
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
    api_log="$temporary_dir/api.log"
    : >"$api_log"

    primary_tunnel_cf_api() {
        local method="$1" endpoint="$2" output="$3"
        printf '%s %s\n' "$method" "$endpoint" >>"$api_log"
        case "$method:$endpoint" in
            GET:*/cfd_tunnel\?*)
                printf '{"success":true,"result":[]}' >"$output"
                ;;
            POST:*/cfd_tunnel)
                printf '{"success":true,"result":{"id":"auto-tunnel-id","name":"%s","token":"ey-auto-token"}}' \
                    "$(primary_tunnel_deterministic_name "$CLOUDFLARE_ACCOUNT_ID" "$CLOUDFLARE_ZONE_ID")" >"$output"
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
    primary_tunnel_rollback
    trap - EXIT
    ! grep -Fq 'DELETE /accounts/account-test/cfd_tunnel/existing-tunnel-id' "$api_log"
    [ ! -e "$PRIMARY_TUNNEL_STATE_FILE" ]

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

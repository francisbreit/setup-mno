#!/usr/bin/bash
set -euo pipefail

project_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
. "$project_dir/cloudflare-route-guard.sh"

test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
CLOUDFLARE_ACCOUNT_ID="account-test"
CLOUDFLARE_ZONE_ID="zone-test"
CLOUDFLARE_API_TOKEN="token-test"
MOCK_DNS='[]'
MOCK_TUNNELS='[]'
MOCK_CONFIG_OLD='{"ingress":[{"service":"http_status:404"}]}'
MOCK_FAIL_OLD_PUT_ONCE=false
MOCK_OLD_PUT_CALLS=0
api_log="$test_dir/api.log"
: >"$api_log"

cf_route_guard_api() {
    local method="$1" endpoint="$2" output="$3" payload="${4:-}"
    printf '%s %s\n' "$method" "$endpoint" >>"$api_log"
    case "$method:$endpoint" in
        GET:/zones/*/dns_records*)
            jq -n --argjson result "$MOCK_DNS" '{success:true,result:$result}' >"$output"
            ;;
        GET:/accounts/*/cfd_tunnel\?*)
            jq -n --argjson result "$MOCK_TUNNELS" \
                '{success:true,result:$result,result_info:{total_pages:1}}' >"$output"
            ;;
        GET:/accounts/*/cfd_tunnel/old-remote/configurations)
            jq -n --argjson config "$MOCK_CONFIG_OLD" '{success:true,result:{config:$config}}' >"$output"
            ;;
        GET:/accounts/*/cfd_tunnel/current/configurations)
            printf '%s' '{"success":true,"result":{"config":{"ingress":[{"service":"http_status:404"}]}}}' >"$output"
            ;;
        PUT:/accounts/*/cfd_tunnel/old-remote/configurations)
            MOCK_OLD_PUT_CALLS=$((MOCK_OLD_PUT_CALLS + 1))
            [ -z "$payload" ] || cp "$payload" "$test_dir/old-put-${MOCK_OLD_PUT_CALLS}.json"
            if [ "$MOCK_FAIL_OLD_PUT_ONCE" = "true" ] && [ "$MOCK_OLD_PUT_CALLS" -eq 1 ]; then
                CF_ROUTE_GUARD_ERROR="falha simulada"
                return 1
            fi
            printf '%s' '{"success":true,"result":{}}' >"$output"
            ;;
        PUT:/zones/*/dns_records/dns-old)
            [ -z "$payload" ] || cp "$payload" "$test_dir/dns-put.json"
            printf '%s' '{"success":true,"result":{"id":"dns-old"}}' >"$output"
            ;;
        POST:/zones/*/dns_records)
            printf '%s' '{"success":true,"result":{"id":"dns-new"}}' >"$output"
            ;;
        DELETE:/zones/*/dns_records/dns-new)
            printf '%s' '{"success":true,"result":{}}' >"$output"
            ;;
        *)
            printf 'API mock inesperada: %s %s\n' "$method" "$endpoint" >&2
            return 1
            ;;
    esac
}

inventory="$test_dir/inventory.json"
MOCK_DNS='[]'
MOCK_TUNNELS='[]'
cf_route_guard_inventory "free.example.com" "" "$inventory"
[ "$(cf_route_guard_classify "$inventory")" = "FREE" ]

MOCK_DNS='[{"id":"dns-old","type":"CNAME","name":"used.example.com","content":"old-remote.cfargotunnel.com","ttl":1,"proxied":true}]'
MOCK_TUNNELS='[
  {"id":"old-remote","name":"Tunnel legado","config_src":"cloudflare"},
  {"id":"current","name":"Tunnel atual","config_src":"cloudflare"}
]'
MOCK_CONFIG_OLD='{"ingress":[
  {"hostname":"used.example.com","service":"http://legacy:80"},
  {"hostname":"keep.example.com","service":"http://keep:80"},
  {"service":"http_status:404"}
]}'
cf_route_guard_inventory "used.example.com" "current" "$inventory"
[ "$(cf_route_guard_classify "$inventory")" = "OVERWRITE" ]
jq -e '.routeConflicts == [{tunnelId:"old-remote",tunnelName:"Tunnel legado",configSrc:"cloudflare",service:"http://legacy:80"}]' \
    "$inventory" >/dev/null

whiptail() {
    printf '%s' "$MOCK_CHOICE" >&2
}
MOCK_CHOICE=VOLTAR
set +e
cf_route_guard_choose "$inventory"
choice_status=$?
set -e
[ "$choice_status" -eq 20 ]
MOCK_CHOICE=SOBRESCREVER
cf_route_guard_choose "$inventory"
[ "$CF_ROUTE_GUARD_DECISION" = "OVERWRITE" ]

dns_tx="$test_dir/dns-transaction.json"
cf_route_guard_apply_dns "$inventory" "used.example.com" \
    "current.cfargotunnel.com" true "$dns_tx" "$test_dir/install.log"
jq -e '.mode == "updated" and .recordId == "dns-old" and
       .original.content == "old-remote.cfargotunnel.com"' "$dns_tx" >/dev/null
jq -e '.content == "current.cfargotunnel.com"' "$test_dir/dns-put.json" >/dev/null
cf_route_guard_restore_dns "$dns_tx" "$test_dir/install.log"
jq -e '.content == "old-remote.cfargotunnel.com"' "$test_dir/dns-put.json" >/dev/null

changes="$test_dir/tunnel-changes.json"
MOCK_OLD_PUT_CALLS=0
cf_route_guard_remove_old_routes "$inventory" "used.example.com" "current" \
    "$changes" "$test_dir/install.log"
jq -e 'length == 1 and .[0].tunnelId == "old-remote"' "$changes" >/dev/null
jq -e '([.config.ingress[]? | select(.hostname == "used.example.com")] | length) == 0 and
       any(.config.ingress[]?; .hostname == "keep.example.com") and
       ([.config.ingress[]? | select(.service == "http_status:404")] | length) == 1' \
    "$test_dir/old-put-1.json" >/dev/null
cf_route_guard_restore_tunnels "$changes" "$test_dir/install.log"
jq -e 'any(.config.ingress[]?; .hostname == "used.example.com" and .service == "http://legacy:80")' \
    "$test_dir/old-put-2.json" >/dev/null

# Se a remoção falhar, o próprio helper restaura o snapshot antes de retornar.
MOCK_OLD_PUT_CALLS=0
MOCK_FAIL_OLD_PUT_ONCE=true
if cf_route_guard_remove_old_routes "$inventory" "used.example.com" "current" \
    "$changes" "$test_dir/install.log"; then
    printf 'ERRO: falha simulada ao remover rota antiga foi aceita.\n' >&2
    exit 1
fi
[ "$MOCK_OLD_PUT_CALLS" -eq 2 ]
jq -e 'any(.config.ingress[]?; .hostname == "used.example.com")' \
    "$test_dir/old-put-2.json" >/dev/null
MOCK_FAIL_OLD_PUT_ONCE=false

# Registros incompatíveis e Tunnels locais nunca oferecem sobrescrita automática.
MOCK_DNS='[{"id":"dns-a","type":"A","name":"blocked.example.com","content":"192.0.2.10"}]'
MOCK_TUNNELS='[]'
cf_route_guard_inventory "blocked.example.com" "current" "$inventory"
[ "$(cf_route_guard_classify "$inventory")" = "BLOCKED" ]

MOCK_DNS='[{"id":"dns-local","type":"CNAME","name":"local.example.com","content":"local-id.cfargotunnel.com"}]'
MOCK_TUNNELS='[{"id":"local-id","name":"Tunnel local","config_src":"local"}]'
cf_route_guard_inventory "local.example.com" "current" "$inventory"
[ "$(cf_route_guard_classify "$inventory")" = "BLOCKED" ]

printf 'OK: conflitos DNS/Tunnel, decisões, transferência e rollback validados.\n'

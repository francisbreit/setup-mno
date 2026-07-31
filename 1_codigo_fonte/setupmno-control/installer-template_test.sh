#!/usr/bin/bash
set -euo pipefail

project_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
template="$project_dir/installer-template.sh"
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

CLOUDFLARE_CONNECT_TIMEOUT=10
CLOUDFLARE_MAX_TIME=30
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
exit 90
EOF
cat >"$test_dir/bin/curl" <<'EOF'
#!/usr/bin/bash
[[ " $* " == *" --connect-timeout 10 "* ]] || exit 91
[[ " $* " == *" --max-time 30 "* ]] || exit 92
case "$MOCK_CURL_MODE" in
    success)
        printf '%s\n' '{"success":true,"result":{"config":{"ingress":[]}}}'
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
chmod 0755 "$test_dir/bin/whiptail" "$test_dir/bin/curl"
PATH="$test_dir/bin:$PATH"

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

printf 'Progresso, timeout e validação do Cloudflare aprovados.\n'

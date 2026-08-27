#!/usr/bin/bash
set -euo pipefail

project_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
launcher="$project_dir/terminal-menu.sh"
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
environment_file="$test_dir/environment.json"

run_launcher() {
    SETUPMNO_TERMINAL_AUTH_SMOKE_TEST=1 \
    SETUPMNO_TERMINAL_TEST_ENVIRONMENT_FILE="$environment_file" \
        bash "$launcher" "$1"
}

printf '%s\n' '{"schemaVersion":1,"plan":"pro-master","installationType":"CLOUDFLARE_TUNNEL"}' >"$environment_file"
[ "$(run_launcher homologation)" = \
    "setupmno-terminal-authorized:pro-master:CLOUDFLARE_TUNNEL:homologation" ]
[ "$(run_launcher installer)" = \
    "setupmno-terminal-authorized:pro-master:CLOUDFLARE_TUNNEL:installer" ]
[ "$(run_launcher sre)" = \
    "setupmno-terminal-authorized:pro-master:CLOUDFLARE_TUNNEL:sre" ]
[ "$(run_launcher strix)" = \
    "setupmno-terminal-authorized:pro-master:CLOUDFLARE_TUNNEL:strix" ]

printf '%s\n' '{"schemaVersion":1,"plan":"pro","installationType":"CLOUDFLARE_TUNNEL"}' >"$environment_file"
if run_launcher homologation >/dev/null 2>&1; then
    printf 'ERRO: plano PRO acessou o terminal de homologação.\n' >&2
    exit 1
fi
if run_launcher strix >/dev/null 2>&1; then
    printf 'ERRO: plano PRO acessou a preparação do Laboratório Strix.\n' >&2
    exit 1
fi
[ "$(run_launcher installer)" = \
    "setupmno-terminal-authorized:pro:CLOUDFLARE_TUNNEL:installer" ]
[ "$(run_launcher sre)" = \
    "setupmno-terminal-authorized:pro:CLOUDFLARE_TUNNEL:sre" ]

for plan in free free1 free2 pro pro-master; do
    printf '{"schemaVersion":1,"plan":"%s","installationType":"TRADICIONAL"}\n' "$plan" >"$environment_file"
    for intent in installer settings homologation sre strix gateway; do
        if run_launcher "$intent" >/dev/null 2>&1; then
            printf 'ERRO: terminal %s foi liberado no modo TRADICIONAL para %s.\n' "$intent" "$plan" >&2
            exit 1
        fi
    done
done

printf '%s\n' '{"schemaVersion":1,"plan":"premium","installationType":"CLOUDFLARE_TUNNEL"}' >"$environment_file"
if run_launcher installer >/dev/null 2>&1; then
    printf 'ERRO: plano desconhecido foi aceito pelo terminal.\n' >&2
    exit 1
fi

printf 'Matriz de autorização PRO MASTER e bloqueio absoluto do terminal TRADICIONAL aprovados.\n'

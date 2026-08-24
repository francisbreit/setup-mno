#!/usr/bin/env bash
set -Eeuo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
gate="$script_dir/skill_supply_chain_gate.py"

show_message() {
    local title="$1" message="$2"
    if command -v whiptail >/dev/null 2>&1 && [ -t 1 ]; then
        whiptail --title "$title" --msgbox "$message" 20 78
    else
        printf '\n%s\n%s\n' "$title" "$message"
    fi
}

ask_value() {
    local title="$1" prompt="$2" initial="${3:-}" value
    if command -v whiptail >/dev/null 2>&1 && [ -t 1 ]; then
        value="$(whiptail --title "$title" --inputbox "$prompt" 12 78 "$initial" 3>&1 1>&2 2>&3)" || return 1
    else
        printf '%s\n> ' "$prompt" >&2
        IFS= read -r value
    fi
    printf '%s' "$value"
}

[ -x "$gate" ] || chmod +x "$gate"

candidate="${1:-}"
if [ -z "$candidate" ]; then
    candidate="$(ask_value "SKILL SUPPLY CHAIN GATE · BETA" "Informe a pasta da skill candidata. Ela será somente lida e nunca executada:")" || exit 0
fi
[ -d "$candidate" ] || {
    show_message "CANDIDATO INVÁLIDO" "A pasta informada não existe. Nenhuma alteração foi realizada."
    exit 2
}

review_dir="$(mktemp -d /tmp/setupmno-skill-review.XXXXXX)"
report="$review_dir/report.json"
set +e
python3 -B "$gate" --candidate "$candidate" --report "$report" >"$review_dir/summary.txt" 2>"$review_dir/error.txt"
status=$?
set -e

if [ "$status" -eq 3 ]; then
    show_message "SKILL BLOQUEADA · BETA" "$(cat "$review_dir/summary.txt")

Relatório: $report"
    exit 3
fi
if [ "$status" -ne 0 ]; then
    show_message "PACOTE INVÁLIDO · BETA" "$(cat "$review_dir/error.txt")

Nenhum arquivo foi instalado ou executado."
    exit "$status"
fi

token="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1], encoding="utf-8"))["approval"]["token"])' "$report")"
show_message "DRY-RUN CONCLUÍDO · BETA" "$(cat "$review_dir/summary.txt")

Relatório: $report

Revise o relatório. Confirmar não instala a skill; apenas registra que o candidato exato pode seguir para revisão canônica."

typed="$(ask_value "CONFIRMAÇÃO PRO MASTER · BETA" "Digite exatamente o token abaixo para aprovar somente a próxima revisão:\n\n$token")" || exit 0
if [ "$typed" != "$token" ]; then
    show_message "APROVAÇÃO CANCELADA" "O token não corresponde. O candidato permanece aguardando revisão."
    exit 4
fi

python3 -B "$gate" --candidate "$candidate" --approval-token "$typed" --report "$report" >"$review_dir/approved.txt"
show_message "REVISÃO PRO MASTER REGISTRADA · BETA" "$(cat "$review_dir/approved.txt")

Relatório: $report

A skill ainda não foi instalada, copiada, commitada ou publicada."

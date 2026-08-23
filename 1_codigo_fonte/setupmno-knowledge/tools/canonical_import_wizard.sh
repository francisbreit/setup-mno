#!/usr/bin/bash
# Assistente local do mantenedor principal. Não é distribuído no runtime.
set -Eeuo pipefail
umask 077

TOOLS_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
KNOWLEDGE_ROOT=$(cd -- "$TOOLS_DIR/.." && pwd -P)
SOURCE_ROOT=$(cd -- "$KNOWLEDGE_ROOT/.." && pwd -P)
IMPORTER="$TOOLS_DIR/import_official_seal_pack.py"
CATALOG="$SOURCE_ROOT/setupmno-control/catalog.json"
PACKAGE_DIR="$SOURCE_ROOT/setupmno-control/homologation-package"

dialog_size() {
    local axis="$1" requested="$2" available
    if [ "$axis" = "height" ]; then
        available=$(tput lines 2>/dev/null || printf '24')
    else
        available=$(tput cols 2>/dev/null || printf '80')
    fi
    available=$((available - 2))
    [ "$requested" -le "$available" ] || requested="$available"
    printf '%s' "$requested"
}

message() {
    whiptail --title "$1" --msgbox "$2" "$(dialog_size height 24)" "$(dialog_size width 104)" 1>&2
}

ask_text() {
    local title="$1" prompt="$2" default_value="${3:-}" value
    value=$(whiptail --title "$title" --inputbox "$prompt" \
        "$(dialog_size height 12)" "$(dialog_size width 104)" "$default_value" \
        3>&1 1>&2 2>&3) || return 130
    printf '%s' "$value"
}

preview_summary() {
    python3 -B - "$1" <<'PY'
import json,sys
data=json.load(open(sys.argv[1], encoding="utf-8"))
lines=[
    f"Setup: {data['setupId']}",
    f"Versão de origem: {data['sourceSetupVersion']}",
    f"Selo: {data['sealId']}",
    f"Pacote SHA-256: {data['packageSHA256']}",
    f"Proveniência: {data['provenance']}",
    f"Git limpo: {'SIM' if data['gitClean'] else 'NÃO'}",
    "",
    "DIFF PLANEJADO:",
]
for item in data["changes"]:
    lines.append(f"- {item['status'].upper():9} {item['path']}")
lines += ["", f"TOKEN: {data['confirmationToken']}", "", "Nenhum commit, tag ou release será criado automaticamente."]
print("\n".join(lines))
PY
}

main() {
    local pack imported_by imported_at temporary preview token typed result summary
    message "IMPORTADOR CANÔNICO · PRO MASTER" \
        "Este assistente recebe o release-pack exportado pela Central do Mantenedor, valida origem, hashes, selo, evidências, decisões e snapshots, e mostra o diff antes de qualquer escrita.\n\nA aplicação é transacional e possui rollback. Ela nunca cria commit, tag ou release automaticamente."
    pack=$(ask_text "1/4 · PACOTE" \
        "Informe o caminho absoluto do arquivo *-release-pack.tar.gz recebido do mantenedor PRO MASTER:" \
        "/tmp/setupmno-official-seal-inbox/") || return 0
    [ -f "$pack" ] && [ ! -L "$pack" ] || {
        message "PACOTE INVÁLIDO" "O caminho informado não é um arquivo regular seguro."
        return 2
    }
    imported_by=$(ask_text "2/4 · RESPONSÁVEL" \
        "Informe seu nome ou identificação de mantenedor principal. Não use email, token ou credencial:") || return 0
    imported_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    temporary=$(mktemp -d /tmp/setupmno-canonical-import.XXXXXX)
    trap 'rm -rf -- "$temporary"' EXIT
    preview="$temporary/preview.json"
    if ! python3 -B "$IMPORTER" \
        --pack "$pack" --root "$KNOWLEDGE_ROOT" --catalog "$CATALOG" \
        --package-dir "$PACKAGE_DIR" --imported-by "$imported_by" \
        --imported-at "$imported_at" >"$preview" 2>"$temporary/error.log"; then
        message "IMPORTAÇÃO INTERROMPIDA" "$(sed -n '1,18p' "$temporary/error.log")"
        return 2
    fi
    summary=$(preview_summary "$preview")
    message "3/4 · DRY-RUN E DIFF" "$summary"
    token=$(python3 -B -c 'import json,sys; print(json.load(open(sys.argv[1]))["confirmationToken"])' "$preview")
    if [ "$(python3 -B -c 'import json,sys; print("1" if json.load(open(sys.argv[1]))["gitClean"] else "0")' "$preview")" != "1" ]; then
        message "GIT NÃO ESTÁ LIMPO" \
            "O pacote passou na validação, mas a aplicação foi bloqueada porque existem alterações locais. Preserve-as em um commit ou stash e execute um novo dry-run."
        return 2
    fi
    typed=$(ask_text "4/4 · CONFIRMAÇÃO HUMANA" \
        "Revise o diff acima. Para importar exatamente esse delta, digite o token:\n\n$token") || return 0
    [ "$typed" = "$token" ] || {
        message "CONFIRMAÇÃO RECUSADA" "O token digitado não corresponde ao dry-run. Nada foi alterado."
        return 2
    }
    result="$temporary/result.json"
    if ! python3 -B "$IMPORTER" \
        --pack "$pack" --root "$KNOWLEDGE_ROOT" --catalog "$CATALOG" \
        --package-dir "$PACKAGE_DIR" --imported-by "$imported_by" \
        --imported-at "$imported_at" --apply --confirm "$token" \
        >"$result" 2>"$temporary/error.log"; then
        message "ROLLBACK EXECUTADO" \
            "A importação falhou e os arquivos anteriores foram restaurados.\n\n$(sed -n '1,18p' "$temporary/error.log")"
        return 2
    fi
    message "IMPORTAÇÃO CANÔNICA CONCLUÍDA" \
        "O selo foi incorporado à cópia de trabalho e todos os gates passaram.\n\nPróximo passo obrigatório: revise git diff, execute o Workflow de Produção e somente então crie commit, tag e release. Nenhuma publicação automática foi realizada."
}

if [ "${SETUPMNO_CANONICAL_IMPORT_WIZARD_SMOKE_TEST:-0}" = "1" ]; then
    printf 'setupmno-canonical-import-wizard-ok\n'
    exit 0
fi

[ -f "$IMPORTER" ] && [ ! -L "$IMPORTER" ] || {
    printf 'Importador canônico ausente ou inseguro.\n' >&2
    exit 2
}
main

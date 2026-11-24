#!/usr/bin/bash
set -Eeuo pipefail
umask 077

RUNNER_DIR="${SETUPMNO_HOMOLOGATION_PACKAGE_DIR:-/root/SetupLowCodeMno/.control/homologation-package}"
# shellcheck source=/dev/null
source "$RUNNER_DIR/maintainer_workspace.sh"

message() { whiptail --title "$1" --msgbox "$2" 22 96 1>&2; }

run_gate() {
    local title="$1"; shift
    local output status
    set +e
    output=$("$@" 2>&1)
    status=$?
    set -e
    if [ "$status" -eq 0 ]; then
        message "$title — APROVADO" "O gate terminou sem erros.\n\n$(printf '%s' "$output" | tail -c 5000)"
    else
        message "$title — REPROVADO" "O gate retornou código $status. Nenhuma publicação foi feita.\n\n$(printf '%s' "$output" | tail -c 5000)"
    fi
}

main_menu() {
    local choice tools="$SETUPMNO_MAINTAINER_KNOWLEDGE_ROOT/tools"
    while true; do
        choice=$(whiptail --title "VALIDAÇÕES PRO MASTER" --menu \
            "Escolha um gate somente leitura. Uma aprovação técnica não publica nem concede selo sozinha." \
            19 96 7 \
            "QUALITY" "Recalcular qualidade e conferir o baseline" \
            "BLUEPRINTS" "Validar contratos e pacotes de Blueprints" \
            "RUNNER" "Autoverificar registro e artefatos do Runner" \
            "EXIT" "Voltar à Central do Mantenedor" \
            3>&1 1>&2 2>&3) || return 0
        case "$choice" in
            QUALITY) run_gate "QUALIDADE" python3 -B "$tools/knowledge_quality.py" --root "$SETUPMNO_MAINTAINER_KNOWLEDGE_ROOT" --catalog "$SETUPMNO_MAINTAINER_CATALOG" --enforce-baseline ;;
            BLUEPRINTS) run_gate "BLUEPRINTS" python3 -B "$tools/blueprint_factory.py" --root "$SETUPMNO_MAINTAINER_KNOWLEDGE_ROOT" --catalog "$SETUPMNO_MAINTAINER_CATALOG" --setup-version "$SETUPMNO_MAINTAINER_SETUP_VERSION" ;;
            RUNNER) run_gate "HOMOLOGATION RUNNER" python3 -B "$RUNNER_DIR/homologation_runner.py" --package-dir "$RUNNER_DIR" list ;;
            EXIT) return 0 ;;
        esac
    done
}

setupmno_prepare_maintainer_workspace || {
    message "WORKSPACE INVÁLIDO" "A cópia de trabalho não pôde ser validada. Atualize o Setup MNO antes de continuar."
    exit 2
}
main_menu

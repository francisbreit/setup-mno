#!/usr/bin/bash
set -Eeuo pipefail
umask 077

RUNNER_DIR="${SETUPMNO_HOMOLOGATION_PACKAGE_DIR:-/root/SetupLowCodeMno/.control/homologation-package}"

dialog_size() {
    local axis="$1" requested="$2" available
    if [ "$axis" = "height" ]; then available=$(tput lines 2>/dev/null || printf '24'); else available=$(tput cols 2>/dev/null || printf '80'); fi
    available=$((available - 2))
    [ "$requested" -le "$available" ] || requested="$available"
    printf '%s' "$requested"
}

message() {
    whiptail --title "$1" --msgbox "$2" "$(dialog_size height 22)" "$(dialog_size width 92)" 1>&2
}

validate_console() {
    local file
    for file in homologation_wizard.sh certification_wizard.sh maintainer_validation_wizard.sh maintainer_workspace.sh; do
        [ -f "$RUNNER_DIR/$file" ] && [ ! -L "$RUNNER_DIR/$file" ] || {
            message "CENTRAL INDISPONÍVEL" "Componente PRO MASTER ausente ou inseguro: $file. Atualize o Setup MNO."
            return 1
        }
    done
}

main_menu() {
    local choice
    while true; do
        choice=$(whiptail --title "SETUP MNO — CENTRAL DO MANTENEDOR · PRO MASTER" --menu \
            "Execute coleta, revisão, validações e emissão do selo. Toda ação final exige confirmação humana e nunca publica uma release automaticamente." \
            "$(dialog_size height 22)" "$(dialog_size width 108)" 10 \
            "RUNNER" "Criar, continuar, verificar ou revisar uma homologação" \
            "CERTIFY" "Preparar documentação e emitir o Selo Oficial" \
            "VALIDATE" "Validar base, qualidade e Blueprints" \
            "EXPORTS" "Localizar pacotes de selo prontos para o repositório" \
            "ABOUT" "Entender o fluxo e a fronteira de confiança" \
            "EXIT" "Voltar ao Terminal Seguro" \
            3>&1 1>&2 2>&3) || return 0
        case "$choice" in
            RUNNER) /usr/bin/bash "$RUNNER_DIR/homologation_wizard.sh" || true ;;
            CERTIFY) SETUPMNO_CERTIFICATION_RUNTIME=1 /usr/bin/bash "$RUNNER_DIR/certification_wizard.sh" || true ;;
            VALIDATE) /usr/bin/bash "$RUNNER_DIR/maintainer_validation_wizard.sh" || true ;;
            EXPORTS)
                message "PACOTES PARA RELEASE" \
                    "Os pacotes emitidos ficam em:\n/root/setupmno-homologation-candidates/official-seals/\n\nEles não publicam nada sozinhos. O mantenedor principal deve importá-los no repositório, revisar o diff, executar os gates e criar a release."
                ;;
            ABOUT)
                message "COMO FUNCIONA" \
                    "1. RUNNER registra nove checks e imagens por digest.\n2. REVIEW grava uma decisão humana imutável.\n3. CERTIFY prepara a documentação da cópia de trabalho.\n4. O dry-run confere arquiteturas, artefatos, pendências e ledger.\n5. O token confirma a emissão transacional.\n6. Um pacote exportável é gerado para revisão e release.\n\nNenhuma etapa cria commit, tag, publicação, DNS ou deploy automaticamente."
                ;;
            EXIT) return 0 ;;
        esac
    done
}

if [ "${SETUPMNO_MAINTAINER_CONSOLE_SMOKE_TEST:-0}" = "1" ]; then
    printf 'setupmno-maintainer-console-ok\n'
    exit 0
fi

validate_console || exit 2
main_menu

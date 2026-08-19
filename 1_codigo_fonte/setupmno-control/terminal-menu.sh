#!/usr/bin/bash
set -Eeuo pipefail

# O ttyd pode encaminhar somente uma intenção fixa para este launcher. Nunca
# interpretamos o valor como comando, caminho ou argumento de shell.
intent="${1:-gateway}"
if [ "$#" -gt 1 ]; then
    printf 'Terminal Seguro: quantidade de argumentos inválida.\n' >&2
    exit 64
fi

case "$intent" in
    installer|settings|homologation|gateway) ;;
    *)
        printf 'Terminal Seguro: intenção recusada.\n' >&2
        exit 64
        ;;
esac

CONTROL_ENVIRONMENT_FILE="/root/SetupLowCodeMno/.control/environment.json"
if [ "${SETUPMNO_TERMINAL_AUTH_SMOKE_TEST:-0}" = "1" ]; then
    CONTROL_ENVIRONMENT_FILE="${SETUPMNO_TERMINAL_TEST_ENVIRONMENT_FILE:-$CONTROL_ENVIRONMENT_FILE}"
fi
[ -f "$CONTROL_ENVIRONMENT_FILE" ] && [ ! -L "$CONTROL_ENVIRONMENT_FILE" ] &&
    [ "$(stat -c '%s' "$CONTROL_ENVIRONMENT_FILE" 2>/dev/null || printf '0')" -le 4096 ] || {
    printf 'Terminal Seguro: estado de autorização indisponível.\n' >&2
    exit 77
}
CONTROL_INSTALLATION_TYPE=$(jq -er \
    'select(.schemaVersion == 1) | .installationType | select(. == "CLOUDFLARE_TUNNEL" or . == "TRADICIONAL")' \
    "$CONTROL_ENVIRONMENT_FILE") || {
    printf 'Terminal Seguro: tipo de instalação inválido.\n' >&2
    exit 77
}
CONTROL_PLAN=$(jq -er \
    'select(.schemaVersion == 1) | .plan | select(. == "pro-master" or . == "pro" or . == "free" or . == "free1" or . == "free2")' \
    "$CONTROL_ENVIRONMENT_FILE") || {
    printf 'Terminal Seguro: plano inválido.\n' >&2
    exit 77
}
[ "$CONTROL_INSTALLATION_TYPE" = "CLOUDFLARE_TUNNEL" ] || {
    printf 'Terminal Seguro: acesso remoto bloqueado em instalações TRADICIONAIS.\n' >&2
    exit 77
}
if [ "$intent" = "homologation" ] && [ "$CONTROL_PLAN" != "pro-master" ]; then
    printf 'Terminal Seguro: homologação exclusiva do plano PRO MASTER.\n' >&2
    exit 77
fi
if [ "${SETUPMNO_TERMINAL_AUTH_SMOKE_TEST:-0}" = "1" ]; then
    printf 'setupmno-terminal-authorized:%s:%s:%s\n' "$CONTROL_PLAN" "$CONTROL_INSTALLATION_TYPE" "$intent"
    exit 0
fi

# O navegador é apenas um cliente do terminal. A sessão tmux permanece viva
# quando o WebSocket fecha, permitindo retomar uploads, pulls e instalações
# depois de uma nova autenticação. O socket dedicado evita colisão com tmux do
# host e o ttyd continua limitando o acesso a um único cliente por vez.
if [ -z "${TMUX:-}" ] && [ "${SETUPMNO_TMUX_CHILD:-0}" != "1" ]; then
    exec tmux -L setupmno-control new-session -A \
        -s "setupmno-terminal-$intent" \
        -e SETUPMNO_TMUX_CHILD=1 \
        /usr/local/bin/setupmno-terminal-menu "$intent"
fi

export TERM="${TERM:-xterm-256color}"
export NEWT_COLORS='
root=white,black
border=lightgray,black
title=yellow,black
roottext=white,black
window=white,black
shadow=black,black
textbox=white,black
acttextbox=black,yellow
entry=white,black
disentry=gray,black
button=white,black
actbutton=black,yellow
compactbutton=white,black
listbox=white,black
actlistbox=black,yellow
actsellistbox=black,yellow
checkbox=white,black
actcheckbox=black,yellow
helpline=lightgray,black
'

dialog_height() {
    local requested="$1" available
    available=$(tput lines 2>/dev/null || printf '24')
    available=$((available - 2))
    [ "$available" -ge 5 ] || available=5
    [ "$requested" -le "$available" ] || requested="$available"
    printf '%s' "$requested"
}

dialog_width() {
    local requested="$1" available
    available=$(tput cols 2>/dev/null || printf '80')
    available=$((available - 2))
    [ "$available" -ge 10 ] || available=10
    [ "$requested" -le "$available" ] || requested="$available"
    printf '%s' "$requested"
}

case "$intent" in
    installer)
        exec /root/SetupLowCodeMno/install
        ;;
    settings)
        export SETUPMNO_TERMINAL_MODE="direct"
        exec /usr/local/bin/setupmno-control-configure
        ;;
    homologation)
        exec /usr/bin/bash \
            /root/SetupLowCodeMno/.control/homologation-package/maintainer_console.sh
        ;;
    gateway)
        ;;
esac

while true; do
    menu_height=$(dialog_height 17)
    menu_width=$(dialog_width 84)
    menu_rows=$((menu_height - 8))
    [ "$menu_rows" -ge 1 ] || menu_rows=1
    [ "$menu_rows" -le 5 ] || menu_rows=5
    menu_entries=(
        "INSTALLER" "Abrir o Instalador Setup MNO"
        "SETTINGS" "Configurar conta e provedor do Control Center"
    )
    if [ "$CONTROL_PLAN" = "pro-master" ]; then
        menu_entries+=("HOMOLOGATION" "Abrir a Central do Mantenedor · PRO MASTER")
    fi
    menu_entries+=("EXIT" "Encerrar esta sessão do terminal")
    choice=$(whiptail --title "SETUP MNO — TERMINAL SEGURO" --menu \
        "Escolha a operação. Configurações administrativas exigem nova confirmação da senha atual e nunca são executadas pelo painel web." \
        "$menu_height" "$menu_width" "$menu_rows" \
        "${menu_entries[@]}" \
        3>&1 1>&2 2>&3)
    status=$?
    [ "$status" -ne 0 ] && exit 0

    case "$choice" in
        INSTALLER)
            exec /root/SetupLowCodeMno/install
            ;;
        HOMOLOGATION)
            /usr/bin/bash \
                /root/SetupLowCodeMno/.control/homologation-package/maintainer_console.sh
            ;;
        SETTINGS)
            SETUPMNO_TERMINAL_MODE="gateway" \
                /usr/local/bin/setupmno-control-configure
            ;;
        EXIT)
            exit 0
            ;;
    esac
done

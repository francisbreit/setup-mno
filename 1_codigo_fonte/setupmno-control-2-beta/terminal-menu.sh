#!/usr/bin/bash
set -Eeuo pipefail

# O ttyd pode encaminhar somente uma intenção fixa para este launcher. Nunca
# interpretamos o valor como comando, caminho ou argumento de shell.
intent="${1:-gateway}"
if [ "$#" -gt 1 ]; then
    printf 'Terminal Seguro: quantidade de argumentos inválida.\n' >&2
    exit 64
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
        exec /usr/local/bin/setupmno-control-2-beta-configure
        ;;
    gateway)
        ;;
    *)
        printf 'Terminal Seguro: intenção recusada.\n' >&2
        exit 64
        ;;
esac

while true; do
    menu_height=$(dialog_height 17)
    menu_width=$(dialog_width 84)
    menu_rows=$((menu_height - 8))
    [ "$menu_rows" -ge 1 ] || menu_rows=1
    [ "$menu_rows" -le 4 ] || menu_rows=4
    choice=$(whiptail --title "SETUP MNO — TERMINAL SEGURO" --menu \
        "Escolha a operação. Configurações administrativas exigem nova confirmação da senha atual e nunca são executadas pelo painel web." \
        "$menu_height" "$menu_width" "$menu_rows" \
        "INSTALLER" "Abrir o Instalador Setup MNO" \
        "SETTINGS" "Configurar conta e provedor do Control Center" \
        "EXIT" "Encerrar esta sessão do terminal" \
        3>&1 1>&2 2>&3)
    status=$?
    [ "$status" -ne 0 ] && exit 0

    case "$choice" in
        INSTALLER)
            exec /root/SetupLowCodeMno/install
            ;;
        SETTINGS)
            SETUPMNO_TERMINAL_MODE="gateway" \
                /usr/local/bin/setupmno-control-2-beta-configure
            ;;
        EXIT)
            exit 0
            ;;
    esac
done

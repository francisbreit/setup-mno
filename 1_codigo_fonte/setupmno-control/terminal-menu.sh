#!/usr/bin/bash
set -u

while true; do
    choice=$(whiptail --title "SETUP MNO — TERMINAL SEGURO" --menu \
        "Escolha a operação. Configurações administrativas exigem nova confirmação da senha atual e nunca são executadas pelo painel web." \
        17 84 4 \
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
            /usr/local/bin/setupmno-control-configure
            ;;
        EXIT)
            exit 0
            ;;
    esac
done

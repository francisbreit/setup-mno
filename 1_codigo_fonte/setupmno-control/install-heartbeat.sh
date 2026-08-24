#!/usr/bin/bash

install_heartbeat_pid=""

install_heartbeat_loop() {
    local percent="$1" message="$2" started now elapsed frame=0
    local -a frames=('|' '/' '-' '\')
    trap - EXIT
    printf -v started '%(%s)T' -1
    while :; do
        printf -v now '%(%s)T' -1
        elapsed=$((now - started))
        printf 'XXX\n%s\n%s  [%s]  Processando há %02d:%02d\nXXX\n' \
            "$percent" "$message" "${frames[$frame]}" \
            "$((elapsed / 60))" "$((elapsed % 60))"
        frame=$(((frame + 1) % ${#frames[@]}))
        sleep 1
    done
}

start_install_heartbeat() {
    stop_install_heartbeat
    install_heartbeat_loop "$1" "$2" &
    install_heartbeat_pid=$!
}

stop_install_heartbeat() {
    if [ -n "$install_heartbeat_pid" ]; then
        kill "$install_heartbeat_pid" 2>/dev/null || true
        wait "$install_heartbeat_pid" 2>/dev/null || true
        install_heartbeat_pid=""
    fi
}

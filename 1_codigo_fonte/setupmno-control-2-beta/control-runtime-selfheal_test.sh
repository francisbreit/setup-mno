#!/usr/bin/bash
set -euo pipefail

project_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source_root=$(cd "$project_dir/.." && pwd)
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT

extract_function() {
    local script="$1" name="$2"
    awk -v name="$name" '
        $0 ~ "^" name "\\(\\)" { inside=1 }
        inside { print }
        inside && /^}/ { exit }
    ' "$script"
}

mkdir -p "$test_dir/bin" "$test_dir/state"
export MOCK_SELFHEAL_LOG="$test_dir/docker.log"
export MOCK_SELFHEAL_STATE="$test_dir/state"
export MOCK_SELFHEAL_AGENTS=1

cat >"$test_dir/bin/docker" <<'EOF'
#!/usr/bin/bash
if [ "$1 $2" = "service ls" ]; then
    for index in $(seq 1 "${MOCK_SELFHEAL_AGENTS:-1}"); do
        printf 'mnoctrl2abc%s-agent_mnoctrl2abc%s-agent\n' "$index" "$index"
    done
    exit 0
fi
if [ "$1 $2" = "service inspect" ]; then
    [ -f "$MOCK_SELFHEAL_STATE/mounted" ] && printf '%s\n' /runtime-control
    exit 0
fi
if [ "$1 $2" = "service update" ]; then
    printf '%s\n' "$*" >>"$MOCK_SELFHEAL_LOG"
    : >"$MOCK_SELFHEAL_STATE/mounted"
    exit 0
fi
exit 1
EOF
chmod 0755 "$test_dir/bin/docker"
PATH="$test_dir/bin:$PATH"

for architecture in x86 arm; do
    install_script="$source_root/$architecture/SetupLowCodeMno/install.sh"
    functions=""
    for name in control_center_agent_has_runtime_mount ensure_control_center_runtime_access; do
        function_source=$(extract_function "$install_script" "$name")
        [ -n "$function_source" ]
        functions+="$function_source"$'\n'
    done
    eval "$functions"
    control_center_runtime_is_valid() { return 0; }

    rm -f "$test_dir/state/mounted" "$MOCK_SELFHEAL_LOG"
    export MOCK_SELFHEAL_AGENTS=1
    ensure_control_center_runtime_access
    [ "$(wc -l <"$MOCK_SELFHEAL_LOG")" -eq 1 ]
    grep -Fq -- '--mount-add type=bind,src=/root/SetupLowCodeMno/.control,dst=/runtime-control,readonly' \
        "$MOCK_SELFHEAL_LOG"

    : >"$MOCK_SELFHEAL_LOG"
    ensure_control_center_runtime_access
    [ ! -s "$MOCK_SELFHEAL_LOG" ]

    rm -f "$test_dir/state/mounted"
    : >"$MOCK_SELFHEAL_LOG"
    export MOCK_SELFHEAL_AGENTS=2
    if ensure_control_center_runtime_access; then
        printf 'ERRO: múltiplos agentes foram alterados pelo autorreparo (%s).\n' "$architecture" >&2
        exit 1
    fi
    [ ! -s "$MOCK_SELFHEAL_LOG" ]
done

printf 'Autorreparo de runtime ausente, idempotência e bloqueio de ambiguidade aprovados.\n'

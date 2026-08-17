#!/usr/bin/bash
set -euo pipefail

project_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source_root=$(cd "$project_dir/.." && pwd)
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT

scripts=(
    "$source_root/setup-mno.sh"
    "$source_root/setup-mno-oracle.sh"
    "$source_root/x86/start_full.sh"
    "$source_root/arm/start_arm_full.sh"
    "$source_root/x86/SetupLowCodeMno/install.sh"
    "$source_root/arm/SetupLowCodeMno/install.sh"
)
functions=(
    setupmno_is_wsl
    setupmno_normalize_arch
    setupmno_wsl_docker_alert
    setupmno_docker_runtime_info
    setupmno_validate_wsl_docker
)

extract_function() {
    local script="$1" name="$2"
    awk -v name="$name" '
        $0 ~ "^" name "\\(\\)" { inside=1 }
        inside { print }
        inside && /^}/ { exit }
    ' "$script"
}

mkdir -p "$test_dir/bin" "$test_dir/no-docker"
cat >"$test_dir/bin/docker" <<'EOF'
#!/usr/bin/bash
printf '%s\n' "$*" >>"$MOCK_DOCKER_LOG"
[ "$1" = "info" ] || exit 2
[ "${MOCK_DOCKER_FAIL:-false}" != "true" ] || exit 1
printf '%s\n' "${MOCK_DOCKER_INFO:-linux|x86_64|inactive|29.0.0}"
EOF
cat >"$test_dir/bin/uname" <<'EOF'
#!/usr/bin/bash
[ "$1" = "-m" ] || exit 2
printf '%s\n' "${MOCK_HOST_ARCH:-x86_64}"
EOF
chmod 0755 "$test_dir/bin/docker" "$test_dir/bin/uname"

reference_functions=""
for name in "${functions[@]}"; do
    reference_functions+="$(extract_function "${scripts[0]}" "$name")"$'\n'
done
[ -n "$reference_functions" ]

original_path="$PATH"
for script in "${scripts[@]}"; do
    script_functions=""
    for name in "${functions[@]}"; do
        function_source=$(extract_function "$script" "$name")
        [ -n "$function_source" ] || {
            printf 'ERRO: função %s ausente em %s.\n' "$name" "$script" >&2
            exit 1
        }
        script_functions+="$function_source"$'\n'
    done
    [ "$script_functions" = "$reference_functions" ] || {
        printf 'ERRO: preflight WSL2/Docker divergente em %s.\n' "$script" >&2
        exit 1
    }
    eval "$script_functions"

    alert_log="$test_dir/alerts.log"
    docker_log="$test_dir/docker.log"
    : >"$alert_log"
    : >"$docker_log"
    export MOCK_DOCKER_LOG="$docker_log"
    setupmno_wsl_docker_alert() { printf '%s\n' "$1" >>"$alert_log"; }
    setupmno_is_wsl() { [ "${MOCK_WSL:-true}" = "true" ]; }

    export MOCK_WSL=false
    export MOCK_DOCKER_FAIL=true
    export MOCK_DOCKER_INFO='linux|x86_64|inactive|29.0.0'
    export MOCK_HOST_ARCH=x86_64
    PATH="$test_dir/no-docker"
    setupmno_validate_wsl_docker
    [ ! -s "$alert_log" ]
    [ ! -s "$docker_log" ]

    MOCK_WSL=true
    set +e
    setupmno_validate_wsl_docker
    status=$?
    set -e
    PATH="$original_path"
    [ "$status" -eq 71 ]
    grep -Fq 'cliente Docker não está disponível' "$alert_log"

    PATH="$test_dir/bin:$original_path"
    : >"$alert_log"
    MOCK_DOCKER_FAIL=true
    set +e
    setupmno_validate_wsl_docker
    status=$?
    set -e
    [ "$status" -eq 72 ]
    grep -Fq 'engine não respondeu' "$alert_log"

    MOCK_DOCKER_FAIL=false
    MOCK_DOCKER_INFO='windows|x86_64|inactive|29.0.0'
    set +e
    setupmno_validate_wsl_docker
    status=$?
    set -e
    [ "$status" -eq 73 ]

    MOCK_DOCKER_INFO='linux|aarch64|inactive|29.0.0'
    set +e
    setupmno_validate_wsl_docker
    status=$?
    set -e
    [ "$status" -eq 74 ]

    MOCK_DOCKER_INFO='linux|x86_64|pending|29.0.0'
    set +e
    setupmno_validate_wsl_docker
    status=$?
    set -e
    [ "$status" -eq 75 ]

    MOCK_DOCKER_INFO='linux|x86_64|inactive|29.0.0'
    setupmno_validate_wsl_docker
    MOCK_DOCKER_INFO='linux|amd64|active|29.0.0'
    setupmno_validate_wsl_docker

    PATH="$original_path"
done

printf 'Preflight WSL2/Docker Desktop aprovado em bootstraps, gatilhos e instaladores x86/ARM.\n'

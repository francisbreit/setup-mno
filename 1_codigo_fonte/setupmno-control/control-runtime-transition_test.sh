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

for architecture in x86 arm; do
    if [ "$architecture" = "x86" ]; then
        start_script="$source_root/x86/start_full.sh"
    else
        start_script="$source_root/arm/start_arm_full.sh"
    fi

    functions=""
    for name in valid_setup_plan write_control_environment preserve_control_runtime \
        restore_control_runtime activate_preserved_control_runtime \
        refresh_control_center_runtime_agent; do
        function_source=$(extract_function "$start_script" "$name")
        [ -n "$function_source" ] || {
            printf 'ERRO: função %s ausente em %s.\n' "$name" "$start_script" >&2
            exit 1
        }
        functions+="$function_source"$'\n'
    done
    eval "$functions"

    for previous_plan in free free1 free2; do
        case_dir="$test_dir/$architecture-$previous_plan"
        live_dir="$case_dir/SetupLowCodeMno/.control"
        hold_root="$case_dir"
        mkdir -p "$live_dir"
        printf '%s\n' "$previous_plan" >"$live_dir/runtime-marker"
        inode_before=$(stat -c '%i' "$live_dir")

        CONTROL_RUNTIME_HOLD=""
        preserve_control_runtime "$live_dir" "$hold_root"
        [ ! -e "$live_dir" ]
        rm -rf "$case_dir/SetupLowCodeMno"
        mkdir -p "$case_dir/SetupLowCodeMno"
        activate_preserved_control_runtime "$live_dir"
        inode_after=$(stat -c '%i' "$live_dir")
        [ "$inode_before" = "$inode_after" ] || {
            printf 'ERRO: inode do runtime mudou na transição %s -> pro (%s).\n' \
                "$previous_plan" "$architecture" >&2
            exit 1
        }
        [ "$(cat "$live_dir/runtime-marker")" = "$previous_plan" ]

        write_control_environment "$live_dir" pro
        jq -e '.schemaVersion == 1 and .plan == "pro" and
            (.installationType == "TRADICIONAL" or .installationType == "CLOUDFLARE_TUNNEL")' \
            "$live_dir/environment.json" >/dev/null
    done

    rollback_dir="$test_dir/$architecture-rollback"
    rollback_live="$rollback_dir/SetupLowCodeMno/.control"
    mkdir -p "$rollback_live"
    printf '%s\n' preserved >"$rollback_live/runtime-marker"
    CONTROL_RUNTIME_HOLD=""
    preserve_control_runtime "$rollback_live" "$rollback_dir"
    rm -rf "$rollback_dir/SetupLowCodeMno"
    restore_control_runtime "$rollback_live"
    [ "$(cat "$rollback_live/runtime-marker")" = "preserved" ]
done

mkdir -p "$test_dir/bin"
docker_log="$test_dir/docker.log"
export DOCKER_TEST_LOG="$docker_log"
cat >"$test_dir/bin/docker" <<'EOF'
#!/usr/bin/bash
if [ "$1 $2" = "service ls" ]; then
    printf '%s\n' \
        'mnoctrlabc1234-agent_mnoctrlabc1234-agent' \
        'mnoctrlabc1234-web_mnoctrlabc1234-web' \
        'portainer_portainer'
    exit 0
fi
if [ "$1 $2" = "service update" ]; then
    printf '%s\n' "$*" >>"$DOCKER_TEST_LOG"
    exit 0
fi
exit 1
EOF
chmod 0755 "$test_dir/bin/docker"
PATH="$test_dir/bin:$PATH"
refresh_control_center_runtime_agent
[ "$(wc -l <"$docker_log")" -eq 1 ]
grep -Fq 'service update --force --detach=true mnoctrlabc1234-agent_mnoctrlabc1234-agent' \
    "$docker_log"

printf 'Transições free/free1/free2 para pro e preservação do runtime aprovadas.\n'

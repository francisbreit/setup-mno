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
    for name in valid_setup_plan write_control_environment \
        prepare_setup_directory_preserving_control \
        reconcile_control_center_plan_services; do
        function_source=$(extract_function "$start_script" "$name")
        [ -n "$function_source" ] || {
            printf 'ERRO: função %s ausente em %s.\n' "$name" "$start_script" >&2
            exit 1
        }
        functions+="$function_source"$'\n'
    done
    eval "$functions"

    for previous_plan in free free1 free2 pro; do
      for target_plan in free free1 free2 pro; do
        case_dir="$test_dir/$architecture-$previous_plan-$target_plan"
        live_dir="$case_dir/SetupLowCodeMno/.control"
        mkdir -p "$live_dir"
        printf '%s\n' "$previous_plan" >"$live_dir/runtime-marker"
        printf '%s\n' remove >"$case_dir/SetupLowCodeMno/install"
        mkdir -p "$case_dir/SetupLowCodeMno/.hidden-old"
        printf '%s\n' remove >"$case_dir/SetupLowCodeMno/.hidden-old/file"
        inode_before=$(stat -c '%i' "$live_dir")

        prepare_setup_directory_preserving_control "$case_dir/SetupLowCodeMno"
        inode_after=$(stat -c '%i' "$live_dir")
        [ "$inode_before" = "$inode_after" ] || {
            printf 'ERRO: inode do runtime mudou na transição %s -> %s (%s).\n' \
                "$previous_plan" "$target_plan" "$architecture" >&2
            exit 1
        }
        [ "$(cat "$live_dir/runtime-marker")" = "$previous_plan" ]
        [ ! -e "$case_dir/SetupLowCodeMno/install" ]
        [ ! -e "$case_dir/SetupLowCodeMno/.hidden-old" ]

        write_control_environment "$live_dir" "$target_plan"
        jq -e --arg plan "$target_plan" '.schemaVersion == 1 and .plan == $plan and
            (.installationType == "TRADICIONAL" or .installationType == "CLOUDFLARE_TUNNEL")' \
            "$live_dir/environment.json" >/dev/null
      done
    done

    symlink_dir="$test_dir/$architecture-symlink"
    mkdir -p "$symlink_dir/SetupLowCodeMno" "$symlink_dir/target"
    ln -s "$symlink_dir/target" "$symlink_dir/SetupLowCodeMno/.control"
    if prepare_setup_directory_preserving_control "$symlink_dir/SetupLowCodeMno"; then
        printf 'ERRO: symlink em .control foi aceito (%s).\n' "$architecture" >&2
        exit 1
    fi
done

mkdir -p "$test_dir/bin"
docker_log="$test_dir/docker.log"
export DOCKER_TEST_LOG="$docker_log"
cat >"$test_dir/bin/docker" <<'EOF'
#!/usr/bin/bash
if [ "$1 $2" = "service ls" ]; then
    printf '%s\n' \
        'mnoctrlabc1234-agent_mnoctrlabc1234-agent' \
        'mnoctrlabc1234-assistant_mnoctrlabc1234-assistant' \
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
for target_plan in free free1 free2 pro; do
    : >"$docker_log"
    reconcile_control_center_plan_services "$target_plan"
    [ "$(wc -l <"$docker_log")" -eq 3 ]
    grep -Fq 'service update --mount-rm /runtime-control --detach=true mnoctrlabc1234-agent_mnoctrlabc1234-agent' "$docker_log"
    grep -Fq 'service update --mount-add type=bind,src=/root/SetupLowCodeMno/.control,dst=/runtime-control,readonly --force --detach=true mnoctrlabc1234-agent_mnoctrlabc1234-agent' "$docker_log"
    if [ "$target_plan" = "pro" ]; then
        expected_replicas="1"
    else
        expected_replicas="0"
    fi
    grep -Fq "service update --replicas $expected_replicas --detach=true mnoctrlabc1234-assistant_mnoctrlabc1234-assistant" \
        "$docker_log"
done

printf 'Matriz de planos, caminho runtime estável e remount WSL2 aprovados.\n'

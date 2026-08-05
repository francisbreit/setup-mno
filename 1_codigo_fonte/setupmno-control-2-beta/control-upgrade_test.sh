#!/usr/bin/bash
set -euo pipefail

project_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
updater="$project_dir/control-upgrade.sh"

bash -n "$updater"
grep -Fq 'mapfile -t web_services' "$updater"
grep -Fq '[ "${#web_services[@]}" -eq 1 ]' "$updater"
grep -Fq 'docker service update --rollback' "$updater"
grep -Fq 'service_has_mount_target "$service" /runtime-control' "$updater"
grep -Fq 'control_image="${prefix}-app:${target_version}"' "$updater"
grep -Fq 'terminal_image="${prefix}-terminal:${target_version}"' "$updater"
grep -Fq 'knowledgecheck' "$updater"
grep -Fq 'evalcheck' "$updater"
grep -Fq '/root/SetupLowCodeMno/install' "$updater"
grep -Fq 'changed_services=()' "$updater"

for forbidden in 'docker stack deploy' 'docker service create' 'docker secret create' \
    'docker volume rm' 'docker stack rm' 'docker service rm' '--label-rm'; do
    if grep -Fq -- "$forbidden" "$updater"; then
        printf 'ERRO: reconciliador contém operação proibida: %s.\n' "$forbidden" >&2
        exit 1
    fi
done

printf 'Reconciliação in-place, rollback e preservação da instalação aprovados.\n'

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
grep -Fq 'service_env_value "$service" ACCESS_JWT_REQUIRED' "$updater"
grep -Fq 'args+=(--env-add ACCESS_JWT_REQUIRED=false --env-add ACCESS_MFA_REQUIRED=false)' "$updater"
grep -Fq 'run_with_heartbeat 25 "CONSTRUINDO A IMAGEM DO PAINEL' "$updater"
grep -Fq 'run_with_heartbeat 45 "CONSTRUINDO A IMAGEM DO TERMINAL' "$updater"
grep -Fq 'run_with_heartbeat 66 "AGUARDANDO O AGENTE ATINGIR 1/1 RÉPLICA' "$updater"
grep -Fq 'run_with_heartbeat 88 "AGUARDANDO O PAINEL ATINGIR 1/1 RÉPLICA' "$updater"

for forbidden in 'docker stack deploy' 'docker service create' 'docker secret create' \
    'docker volume rm' 'docker stack rm' 'docker service rm' '--label-rm'; do
    if grep -Fq -- "$forbidden" "$updater"; then
        printf 'ERRO: reconciliador contém operação proibida: %s.\n' "$forbidden" >&2
        exit 1
    fi
done

test_dir=$(mktemp -d)
cleanup_test_dir() {
    rm -rf -- "$test_dir"
}
trap cleanup_test_dir EXIT
log_file="$test_dir/upgrade.log"
docker_log="$test_dir/docker.log"
: >"$log_file"
: >"$docker_log"

for function_name in progress heartbeat_loop stop_heartbeat run_with_heartbeat \
    service_has_env_key service_env_value update_web; do
    function_source=$(awk -v name="$function_name" '
        $0 ~ "^" name "\\(\\) \\{" {capture=1}
        capture {print}
        capture && /^}$/ {exit}
    ' "$updater")
    [ -n "$function_source" ] || {
        printf 'ERRO: função %s ausente no reconciliador.\n' "$function_name" >&2
        exit 1
    }
    eval "$function_source"
done

heartbeat_pid=""
heartbeat_output="$test_dir/heartbeat-gauge.log"
sleep() { command sleep 0.02; }
heartbeat_success() {
    command sleep 0.12
    printf 'comando monitorado concluído\n'
}
# O Bash 5.3 pode herdar o trap EXIT no job em background do heartbeat e
# remover o diretório do processo pai. Suspenda o trap somente enquanto o job
# monitorado estiver vivo e restaure-o imediatamente depois.
trap - EXIT
run_with_heartbeat 84 "ATUALIZANDO O PAINEL..." heartbeat_success >"$heartbeat_output"
trap cleanup_test_dir EXIT
grep -Fq '[|]' "$heartbeat_output"
grep -Fq '[/]' "$heartbeat_output"
grep -Fq '[\]' "$heartbeat_output"
grep -Fq 'Processando há 00:00' "$heartbeat_output"
grep -Fq 'comando monitorado concluído' "$log_file"
[ -z "$heartbeat_pid" ]

heartbeat_failure() {
    printf 'falha monitorada\n'
    return 37
}
set +e
trap - EXIT
run_with_heartbeat 45 "CONSTRUINDO O TERMINAL..." heartbeat_failure >"$heartbeat_output"
heartbeat_status=$?
trap cleanup_test_dir EXIT
set -e
[ "$heartbeat_status" -eq 37 ]
[ -z "$heartbeat_pid" ]
grep -Fq 'falha monitorada' "$log_file"

docker() {
    if [ "${1:-}" = "service" ] && [ "${2:-}" = "inspect" ]; then
        printf '%s\n' 'APP_VERSION=4.15.8' 'SETUPMNO_PLAN=pro' \
            'SETUPMNO_INSTALL_TYPE=CLOUDFLARE_TUNNEL'
        case "${MOCK_ACCESS_STATE:-legacy}" in
            original)
                printf '%s\n' 'ACCESS_JWT_REQUIRED=false' 'ACCESS_TEAM_DOMAIN=' \
                    'ACCESS_POLICY_AUD=' 'ACCESS_ALLOWED_EMAIL=' 'ACCESS_MFA_REQUIRED=false'
                ;;
            mfa)
                printf '%s\n' 'ACCESS_JWT_REQUIRED=true' \
                    'ACCESS_TEAM_DOMAIN=https://setupmno.cloudflareaccess.com' \
                    'ACCESS_POLICY_AUD=setupmno-test-audience' \
                    'ACCESS_ALLOWED_EMAIL=admin@example.com' 'ACCESS_MFA_REQUIRED=true'
                ;;
            partial)
                printf '%s\n' 'ACCESS_TEAM_DOMAIN=https://setupmno.cloudflareaccess.com'
                ;;
        esac
        return 0
    fi
    printf '%s\n' "$*" >>"$docker_log"
}

target_version="4.16.2"
MOCK_ACCESS_STATE=legacy
update_web "mnoctrltest-web_mnoctrltest-web" "mnoctrltest-app:4.16.2" pro
grep -Fq -- '--env-add ACCESS_JWT_REQUIRED=false --env-add ACCESS_MFA_REQUIRED=false' "$docker_log"

: >"$docker_log"
MOCK_ACCESS_STATE=original
update_web "mnoctrltest-web_mnoctrltest-web" "mnoctrltest-app:4.16.2" pro
for key in ACCESS_JWT_REQUIRED ACCESS_TEAM_DOMAIN ACCESS_POLICY_AUD ACCESS_ALLOWED_EMAIL ACCESS_MFA_REQUIRED; do
    grep -Fq -- "--env-rm $key" "$docker_log"
done
grep -Fq -- '--env-add ACCESS_JWT_REQUIRED=false --env-add ACCESS_MFA_REQUIRED=false' "$docker_log"

: >"$docker_log"
MOCK_ACCESS_STATE=mfa
update_web "mnoctrltest-web_mnoctrltest-web" "mnoctrltest-app:4.16.2" pro
! grep -Fq 'ACCESS_' "$docker_log"

: >"$docker_log"
MOCK_ACCESS_STATE=partial
if update_web "mnoctrltest-web_mnoctrltest-web" "mnoctrltest-app:4.16.2" pro; then
    printf 'ERRO: metadados Access parciais foram aceitos.\n' >&2
    exit 1
fi
[ ! -s "$docker_log" ]

printf 'Reconciliação in-place, modo original explícito, MFA preservado e rollback aprovados.\n'

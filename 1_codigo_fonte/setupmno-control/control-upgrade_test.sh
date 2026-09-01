#!/usr/bin/bash
set -euo pipefail

project_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
updater="$project_dir/control-upgrade.sh"

bash -n "$updater"
grep -Fq 'mapfile -t web_services' "$updater"
grep -Fq '[ "${#web_services[@]}" -eq 1 ]' "$updater"
grep -Fq 'docker service update --rollback' "$updater"
grep -Fq 'service_has_mount_target "$service" /runtime-control' "$updater"
grep -Fq 'agent_version_is_current "$agent_service"' "$updater"
grep -Fq 'control_image="${prefix}-app:${target_version}"' "$updater"
grep -Fq 'terminal_image="${prefix}-terminal:${target_version}"' "$updater"
grep -Fq 'strix_executor_image="${prefix}-strix-executor:${target_version}"' "$updater"
grep -Fq 'knowledgecheck' "$updater"
grep -Fq 'evalcheck' "$updater"
grep -Fq '/root/SetupLowCodeMno/install' "$updater"
grep -Fq 'changed_services=()' "$updater"
grep -Fq 'service_env_value "$service" ACCESS_JWT_REQUIRED' "$updater"
grep -Fq 'args+=(--env-add ACCESS_JWT_REQUIRED=false --env-add ACCESS_MFA_REQUIRED=false)' "$updater"
grep -Fq 'run_with_heartbeat 25 "CONSTRUINDO A IMAGEM DO PAINEL' "$updater"
grep -Fq 'run_with_heartbeat 45 "CONSTRUINDO A IMAGEM DO TERMINAL' "$updater"
grep -Fq 'build-executor.sh' "$updater"
grep -Fq 'SETUPMNO_STRIX_EXECUTOR_IMAGE' "$updater"
grep -Fq 'run_with_heartbeat 66 "AGUARDANDO O AGENTE ATINGIR 1/1 RÉPLICA' "$updater"
grep -Fq 'run_with_heartbeat 88 "AGUARDANDO O PAINEL ATINGIR 1/1 RÉPLICA' "$updater"
grep -Fq 'arm64|aarch64)' "$updater"
grep -Fq 'service_wait_attempts=100' "$updater"
grep -Fq 'record_service_diagnostics "$service" "$expected"' "$updater"
grep -Fq 'docker service ps --no-trunc' "$updater"
grep -Fq 'health={{.State.Health.Status}}' "$updater"
grep -Fq 'docker_socket_gid()' "$updater"
grep -Fq 'service_has_group "$terminal_service" "$socket_gid"' "$updater"
grep -Fq 'SETUPMNO_DOCKER_SOCKET_GID' "$updater"
grep -Fq 'schedule_terminal_update' "$updater"
grep -Fq -- '--group-add "$socket_gid"' "$updater"

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
    service_has_env_key service_env_value service_has_mount_target docker_socket_gid \
    service_has_group schedule_terminal_update update_agent \
    agent_version_is_current configure_service_wait_policy record_service_diagnostics \
    wait_service update_web; do
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
    if [ "${1:-}" = "info" ] && [ "${2:-}" = "--format" ]; then
        printf '%s\n' "${MOCK_DOCKER_ARCH:-amd64}"
        return 0
    fi
    if [ "${1:-}" = "service" ] && [ "${2:-}" = "ls" ] &&
       [ -n "${MOCK_REPLICA_FILE:-}" ]; then
        head -n1 "$MOCK_REPLICA_FILE"
        sed '1d' "$MOCK_REPLICA_FILE" >"${MOCK_REPLICA_FILE}.next"
        mv -f "${MOCK_REPLICA_FILE}.next" "$MOCK_REPLICA_FILE"
        printf '%s\n' "$*" >>"$docker_log"
        return 0
    fi
    if [ "${1:-}" = "service" ] && [ "${2:-}" = "inspect" ]; then
        [ -z "${MOCK_APP_VERSION:-}" ] || printf 'APP_VERSION=%s\n' "$MOCK_APP_VERSION"
        printf '%s\n' 'SETUPMNO_PLAN=pro' 'SETUPMNO_INSTALL_TYPE=CLOUDFLARE_TUNNEL'
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
    if [ "${1:-}" = "service" ] && [ "${2:-}" = "ps" ]; then
        printf '%s\n' 'task=test image=test-app:4.16.2 desired=Running current=Preparing error='
        printf '%s\n' "$*" >>"$docker_log"
        return 0
    fi
    if [ "${1:-}" = "ps" ] && [ "${2:-}" = "-aq" ]; then
        printf '%s\n' 'test-container-id'
        printf '%s\n' "$*" >>"$docker_log"
        return 0
    fi
    if [ "${1:-}" = "inspect" ]; then
        printf '%s\n' 'container=test image=test-app:4.16.2 status=running exitCode=0 error="" health=starting failingStreak=0'
        printf '%s\n' "$*" >>"$docker_log"
        return 0
    fi
    printf '%s\n' "$*" >>"$docker_log"
}

MOCK_DOCKER_ARCH=amd64
configure_service_wait_policy
[ "$service_wait_attempts" -eq 100 ]
[ "$service_wait_interval" -eq 3 ]

MOCK_DOCKER_ARCH=arm64
configure_service_wait_policy
[ "$service_wait_attempts" -eq 100 ]

MOCK_DOCKER_ARCH=aarch64
configure_service_wait_policy
[ "$service_wait_attempts" -eq 100 ]

service_wait_attempts=3
service_wait_interval=0
MOCK_REPLICA_FILE="$test_dir/replicas.txt"
printf '%s\n' '0/1' '1/1' >"$MOCK_REPLICA_FILE"
: >"$docker_log"
wait_service "mnoctrltest-web_mnoctrltest-web" 1
grep -Fq 'réplicas=0/1 tentativa=1/3' "$log_file"
grep -Fq 'réplicas=1/1 tentativa=2/3' "$log_file"
! grep -Fq 'service ps --no-trunc' "$docker_log"

printf '%s\n' '0/1' '0/1' '0/1' >"$MOCK_REPLICA_FILE"
: >"$docker_log"
if wait_service "mnoctrltest-web_mnoctrltest-web" 1; then
    printf 'ERRO: serviço sem convergência foi aceito.\n' >&2
    exit 1
fi
grep -Fq 'service ps --no-trunc' "$docker_log"
grep -Fq 'health=starting failingStreak=0' "$log_file"
unset MOCK_REPLICA_FILE

target_version="4.16.2"
MOCK_APP_VERSION=""
if agent_version_is_current "mnoctrltest-agent_mnoctrltest-agent"; then
    printf 'ERRO: agente sem APP_VERSION foi aceito como sincronizado.\n' >&2
    exit 1
fi
update_agent "mnoctrltest-agent_mnoctrltest-agent" "mnoctrltest-app:4.16.2"
grep -Fq -- '--env-add APP_VERSION=4.16.2' "$docker_log"
! grep -Fq -- '--env-rm APP_VERSION' "$docker_log"

: >"$docker_log"
MOCK_APP_VERSION="4.15.8"
if agent_version_is_current "mnoctrltest-agent_mnoctrltest-agent"; then
    printf 'ERRO: agente com APP_VERSION antiga foi aceito como sincronizado.\n' >&2
    exit 1
fi
update_agent "mnoctrltest-agent_mnoctrltest-agent" "mnoctrltest-app:4.16.2"
grep -Fq -- '--env-rm APP_VERSION' "$docker_log"
grep -Fq -- '--env-add APP_VERSION=4.16.2' "$docker_log"

: >"$docker_log"
MOCK_APP_VERSION="4.16.2"
agent_version_is_current "mnoctrltest-agent_mnoctrltest-agent"

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

: >"$docker_log"
terminal_service="mnoctrltest-terminal_mnoctrltest-terminal"
terminal_image="mnoctrltest-terminal:4.16.2"
control_image="mnoctrltest-app:4.16.2"
strix_executor_image="mnoctrltest-strix-executor:4.16.2"
plan="pro"
socket_gid="1001"
schedule_terminal_update
grep -Fq -- 'run -d --rm --network none --group-add 1001' "$docker_log"
grep -Fq -- '--group-add 1001' "$docker_log"
grep -Fq -- '--env-add SETUPMNO_DOCKER_SOCKET_GID=1001' "$docker_log"
grep -Fq -- '--env-add SETUPMNO_STRIX_EXECUTOR_IMAGE=mnoctrltest-strix-executor:4.16.2' "$docker_log"
grep -Fq -- '--force --detach=true mnoctrltest-terminal_mnoctrltest-terminal' "$docker_log"

printf 'Reconciliação in-place, versão do agente, modo original explícito, MFA e rollback aprovados.\n'

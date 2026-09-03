#!/usr/bin/bash
# Reconciliação in-place do Setup MNO Control Center.
# Preserva stacks, serviços, labels do Portainer, secrets, volumes e domínio.
set -uo pipefail
umask 077

source_dir="${1:?diretório de fontes ausente}"
target_version="${2:?versão de destino ausente}"
log_file="${3:?log ausente}"
error_file="${4:?arquivo de erro ausente}"
state_file="${5:?arquivo de estado ausente}"
runtime_dir="/root/SetupLowCodeMno/.control"
changed_services=()
heartbeat_pid=""
runtime_architecture="unknown"
service_wait_attempts=100
service_wait_interval=3

progress() {
    printf 'XXX\n%s\n%s\nXXX\n' "$1" "$2"
}

heartbeat_loop() {
    local percent="$1" message="$2" started now elapsed minutes seconds elapsed_text frame=0
    local -a frames=('|' '/' '-' '\')
    printf -v started '%(%s)T' -1
    while :; do
        printf -v now '%(%s)T' -1
        elapsed=$((now - started))
        minutes=$((elapsed / 60))
        seconds=$((elapsed % 60))
        printf -v elapsed_text '%02d:%02d' "$minutes" "$seconds"
        progress "$percent" "${message}  [${frames[$frame]}]  Processando há ${elapsed_text}"
        frame=$(((frame + 1) % ${#frames[@]}))
        sleep 1
    done
}

stop_heartbeat() {
    if [ -n "$heartbeat_pid" ]; then
        kill "$heartbeat_pid" 2>/dev/null || true
        wait "$heartbeat_pid" 2>/dev/null || true
        heartbeat_pid=""
    fi
}

run_with_heartbeat() {
    local percent="$1" message="$2" status
    shift 2
    stop_heartbeat
    heartbeat_loop "$percent" "$message" &
    heartbeat_pid=$!
    "$@" >>"$log_file" 2>&1
    status=$?
    stop_heartbeat
    return "$status"
}

fail_upgrade() {
    printf '%s\n' "$2" >"$error_file"
    progress 100 "$2"
    exit "$1"
}

rollback_changed_services() {
    local index
    for ((index=${#changed_services[@]}-1; index>=0; index--)); do
        docker service update --rollback --detach=true \
            "${changed_services[$index]}" >>"$log_file" 2>&1 || true
    done
}

service_has_env_key() {
    local service="$1" key="$2"
    docker service inspect --format '{{range .Spec.TaskTemplate.ContainerSpec.Env}}{{println .}}{{end}}' \
        "$service" 2>>"$log_file" | grep -Eq "^${key}="
}

service_env_value() {
    local service="$1" key="$2"
    docker service inspect --format '{{range .Spec.TaskTemplate.ContainerSpec.Env}}{{println .}}{{end}}' \
        "$service" 2>>"$log_file" | sed -n "s/^${key}=//p" | head -n1
}

service_has_mount_target() {
    local service="$1" target="$2"
    docker service inspect --format '{{range .Spec.TaskTemplate.ContainerSpec.Mounts}}{{println .Target}}{{end}}' \
        "$service" 2>>"$log_file" | grep -Fxq "$target"
}

service_image() {
    docker service inspect --format '{{.Spec.TaskTemplate.ContainerSpec.Image}}' \
        "$1" 2>>"$log_file" | sed 's/@sha256:.*$//'
}

docker_socket_gid() {
    local socket_gid
    [ -S /var/run/docker.sock ] || return 1
    socket_gid=$(stat -c '%g' /var/run/docker.sock 2>>"$log_file") || return 1
    [[ "$socket_gid" =~ ^[0-9]+$ ]] && [ "$socket_gid" -le 2147483647 ] || return 1
    printf '%s' "$socket_gid"
}

service_has_group() {
    local service="$1" expected_gid="$2"
    docker service inspect --format '{{range .Spec.TaskTemplate.ContainerSpec.Groups}}{{println .}}{{end}}' \
        "$service" 2>>"$log_file" | grep -Fxq "$expected_gid"
}

schedule_terminal_update() {
    local old_socket_gid finalizer_name has_image_env=false has_plan_env=false has_strix_env=false
    local -a args
    old_socket_gid=$(service_env_value "$terminal_service" SETUPMNO_DOCKER_SOCKET_GID)
    [ -z "$old_socket_gid" ] || [[ "$old_socket_gid" =~ ^[0-9]+$ ]] || return 1
    service_has_env_key "$terminal_service" SETUPMNO_CONTROL_IMAGE && has_image_env=true
    service_has_env_key "$terminal_service" SETUPMNO_CONTROL_PLAN && has_plan_env=true
    service_has_env_key "$terminal_service" SETUPMNO_STRIX_EXECUTOR_IMAGE && has_strix_env=true
    args=(--image "$terminal_image")
    if [ -n "$old_socket_gid" ] && [ "$old_socket_gid" != "$socket_gid" ] &&
       service_has_group "$terminal_service" "$old_socket_gid"; then
        args+=(--group-rm "$old_socket_gid")
    fi
    service_has_group "$terminal_service" "$socket_gid" || args+=(--group-add "$socket_gid")
    [ "$has_image_env" = "false" ] || args+=(--env-rm SETUPMNO_CONTROL_IMAGE)
    [ "$has_plan_env" = "false" ] || args+=(--env-rm SETUPMNO_CONTROL_PLAN)
    [ "$has_strix_env" = "false" ] || args+=(--env-rm SETUPMNO_STRIX_EXECUTOR_IMAGE)
    [ -z "$old_socket_gid" ] || args+=(--env-rm SETUPMNO_DOCKER_SOCKET_GID)
    args+=(--env-add "SETUPMNO_CONTROL_IMAGE=$control_image")
    args+=(--env-add "SETUPMNO_CONTROL_PLAN=$plan")
    args+=(--env-add "SETUPMNO_STRIX_EXECUTOR_IMAGE=$strix_executor_image")
    args+=(--env-add "SETUPMNO_DOCKER_SOCKET_GID=$socket_gid")
    args+=(--force --detach=true "$terminal_service")
    finalizer_name="${terminal_service%%_*}-reconcile-finalizer"
    docker run -d --rm --network none --group-add "$socket_gid" --name "$finalizer_name" \
        -v /var/run/docker.sock:/var/run/docker.sock --entrypoint /usr/bin/bash \
        "$terminal_image" -c 'sleep 4; docker service update "$@"' _ "${args[@]}" \
        >>"$log_file" 2>&1
}

configure_service_wait_policy() {
    runtime_architecture=$(docker info --format '{{.Architecture}}' 2>>"$log_file" |
        tr '[:upper:]' '[:lower:]' | head -n1)
    case "$runtime_architecture" in
        arm64|aarch64)
            service_wait_attempts=100
            ;;
        *)
            service_wait_attempts=100
            ;;
    esac
    service_wait_interval=3
    printf '%s política de convergência: arquitetura=%s tentativas=%s intervalo=%ss limite=%ss.\n' \
        "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${runtime_architecture:-unknown}" \
        "$service_wait_attempts" "$service_wait_interval" \
        "$((service_wait_attempts * service_wait_interval))" >>"$log_file"
}

record_service_diagnostics() {
    local service="$1" expected="$2" container_id
    {
        printf '%s diagnóstico de convergência: serviço=%s esperado=%s/%s.\n' \
            "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$service" "$expected" "$expected"
        docker service ls --filter "name=$service" \
            --format 'service={{.Name}} image={{.Image}} replicas={{.Replicas}}'
        docker service ps --no-trunc \
            --format 'task={{.ID}} image={{.Image}} desired={{.DesiredState}} current={{.CurrentState}} error={{.Error}}' \
            "$service"
        while IFS= read -r container_id; do
            [ -n "$container_id" ] || continue
            docker inspect --format \
                'container={{.Id}} image={{.Config.Image}} status={{.State.Status}} exitCode={{.State.ExitCode}} error={{json .State.Error}}{{if .State.Health}} health={{.State.Health.Status}} failingStreak={{.State.Health.FailingStreak}}{{end}}' \
                "$container_id"
        done < <(docker ps -aq \
            --filter "label=com.docker.swarm.service.name=$service" | head -n 3)
    } >>"$log_file" 2>&1 || true
}

wait_service() {
    local service="$1" expected="$2" replicas attempt last_replicas=""
    [ "$expected" = "0" ] && return 0
    for attempt in $(seq 1 "$service_wait_attempts"); do
        replicas=$(docker service ls --filter "name=$service" --format '{{.Replicas}}' \
            2>>"$log_file" | head -n1)
        replicas=${replicas:-indisponível}
        if [ "$replicas" != "$last_replicas" ]; then
            printf '%s convergência: serviço=%s réplicas=%s tentativa=%s/%s.\n' \
                "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$service" "$replicas" \
                "$attempt" "$service_wait_attempts" >>"$log_file"
            last_replicas="$replicas"
        fi
        [ "$replicas" = "${expected}/${expected}" ] && return 0
        sleep "$service_wait_interval"
    done
    record_service_diagnostics "$service" "$expected"
    return 1
}

update_agent() {
    local service="$1" image="$2" args
    args=(service update --image "$image" --detach=true)
    if ! service_has_mount_target "$service" /runtime-control; then
        args+=(--mount-add type=bind,src=/root/SetupLowCodeMno/.control,dst=/runtime-control,readonly)
    fi
    if ! service_has_mount_target "$service" /homologation-candidates; then
        args+=(--mount-add type=bind,src=/root/setupmno-homologation-candidates,dst=/homologation-candidates,readonly)
    fi
    service_has_env_key "$service" HOMOLOGATION_CANDIDATE_DIR &&
        args+=(--env-rm HOMOLOGATION_CANDIDATE_DIR)
    args+=(--env-add HOMOLOGATION_CANDIDATE_DIR=/homologation-candidates)
    service_has_env_key "$service" APP_VERSION && args+=(--env-rm APP_VERSION)
    args+=(--env-add "APP_VERSION=$target_version")
    docker "${args[@]}" "$service" >>"$log_file" 2>&1
}

agent_version_is_current() {
    local service="$1"
    [ "$(service_env_value "$service" APP_VERSION)" = "$target_version" ]
}

control_image_matches_runtime() {
    local image="$1"
    local runtime_archive_sha runtime_eval_cases runtime_setup_version image_check
    [ -z "${MOCK_DOCKER_ARCH:-}" ] || return 0
    [ -f "$runtime_dir/release.json" ] || return 0
    runtime_archive_sha=$(jq -r '.knowledgeArchiveSHA256 // empty' "$runtime_dir/release.json" 2>/dev/null)
    runtime_eval_cases=$(jq -r '.evalCaseEntries // 0' "$runtime_dir/release.json" 2>/dev/null)
    runtime_setup_version=$(jq -r '.setupVersion // empty' "$runtime_dir/release.json" 2>/dev/null)
    [ -n "$runtime_archive_sha" ] || return 0
    image_check=$(docker run --rm --entrypoint /setupmno-control "$image" knowledgecheck 2>/dev/null) || return 1
    [ "$(jq -r '.archiveSHA256 // empty' <<<"$image_check")" = "$runtime_archive_sha" ] &&
    [ "$(jq -r '.evalCaseEntries // 0' <<<"$image_check")" = "$runtime_eval_cases" ] &&
    [ "$(jq -r '.setupVersion // empty' <<<"$image_check")" = "$runtime_setup_version" ]
}

ensure_runtime_permissions() {
    if [ -d "$runtime_dir" ]; then
        chmod 0755 "$runtime_dir" 2>/dev/null || true
        find "$runtime_dir" -type d -exec chmod 0755 {} + 2>/dev/null || true
        find "$runtime_dir" -type f ! -name "mfa-state.json" ! -name "*.key" -exec chmod 0644 {} + 2>/dev/null || true
        [ -f "$runtime_dir/mfa-state.json" ] && chmod 0600 "$runtime_dir/mfa-state.json" 2>/dev/null || true
    fi
}

update_web() {
    local service="$1" image="$2" plan="$3" args key
    local access_required access_team access_aud access_email access_mfa
    args=(service update --image "$image" --detach=true)
    service_has_env_key "$service" APP_VERSION && args+=(--env-rm APP_VERSION)
    args+=(--env-add "APP_VERSION=$target_version")
    service_has_env_key "$service" SETUPMNO_PLAN && args+=(--env-rm SETUPMNO_PLAN)
    args+=(--env-add "SETUPMNO_PLAN=$plan")

    access_required=$(service_env_value "$service" ACCESS_JWT_REQUIRED)
    access_team=$(service_env_value "$service" ACCESS_TEAM_DOMAIN)
    access_aud=$(service_env_value "$service" ACCESS_POLICY_AUD)
    access_email=$(service_env_value "$service" ACCESS_ALLOWED_EMAIL)
    access_mfa=$(service_env_value "$service" ACCESS_MFA_REQUIRED)
    case "$access_required" in
        true)
            if [ -z "$access_team" ] || [ -z "$access_aud" ] || [ -z "$access_email" ]; then
                printf 'Metadados Cloudflare Access incompletos no serviço %s.\n' "$service" >>"$log_file"
                return 1
            fi
            ;;
        ""|false)
            if [ -n "$access_team" ] || [ -n "$access_aud" ] || [ -n "$access_email" ] ||
               { [ -n "$access_mfa" ] && [ "$access_mfa" != "false" ]; }; then
                printf 'Metadados Cloudflare Access inconsistentes no serviço %s.\n' "$service" >>"$log_file"
                return 1
            fi
            for key in ACCESS_JWT_REQUIRED ACCESS_TEAM_DOMAIN ACCESS_POLICY_AUD \
                ACCESS_ALLOWED_EMAIL ACCESS_MFA_REQUIRED; do
                service_has_env_key "$service" "$key" && args+=(--env-rm "$key")
            done
            args+=(--env-add ACCESS_JWT_REQUIRED=false --env-add ACCESS_MFA_REQUIRED=false)
            ;;
        *)
            printf 'ACCESS_JWT_REQUIRED inválido no serviço %s.\n' "$service" >>"$log_file"
            return 1
            ;;
    esac
    docker "${args[@]}" "$service" >>"$log_file" 2>&1
}

trap 'status=$?; stop_heartbeat; if [ "$status" -ne 0 ] && [ "${#changed_services[@]}" -gt 0 ]; then rollback_changed_services; fi' EXIT

progress 3 "VALIDANDO A INSTALAÇÃO EXISTENTE..."
for command_name in docker jq tar sha256sum stat; do
    command -v "$command_name" >/dev/null 2>&1 ||
        fail_upgrade 10 "Dependência ausente durante a reconciliação: $command_name."
done
docker info >>"$log_file" 2>&1 || fail_upgrade 11 "Docker ou Swarm indisponível."
configure_service_wait_policy

mapfile -t web_services < <(docker service ls --format '{{.Name}}' 2>>"$log_file" |
    grep -E '^mnoctrl[[:alnum:]]+-web_mnoctrl[[:alnum:]]+-web$' || true)
[ "${#web_services[@]}" -eq 1 ] ||
    fail_upgrade 12 "A reconciliação exige exatamente uma instalação do Control Center; foram encontradas ${#web_services[@]}."

web_full="${web_services[0]}"
prefix="${web_full%%-web_*}"
[[ "$prefix" =~ ^mnoctrl[[:alnum:]]+$ ]] || fail_upgrade 12 "Prefixo do Control Center inválido."
web_service="${prefix}-web_${prefix}-web"
agent_service="${prefix}-agent_${prefix}-agent"
terminal_service="${prefix}-terminal_${prefix}-terminal"
assistant_service="${prefix}-assistant_${prefix}-assistant"

for required_service in "$web_service" "$agent_service" "$terminal_service"; do
    docker service inspect "$required_service" >>"$log_file" 2>&1 ||
        fail_upgrade 13 "A instalação está incompleta: serviço $required_service ausente."
done
assistant_exists="false"
docker service inspect "$assistant_service" >>"$log_file" 2>&1 && assistant_exists="true"

plan=$(jq -er 'select(.schemaVersion == 1) | .plan |
    select(. == "pro-master" or . == "pro" or . == "free" or . == "free1" or . == "free2")' \
    "$runtime_dir/environment.json" 2>>"$log_file") ||
    fail_upgrade 14 "O plano canônico do Control Center está ausente ou inválido."
case "$plan" in
    pro-master|pro) assistant_replicas=1 ;;
    *) assistant_replicas=0 ;;
esac

control_image="${prefix}-app:${target_version}"
terminal_image="${prefix}-terminal:${target_version}"
strix_executor_image="${prefix}-strix-executor:${target_version}"
socket_gid=$(docker_socket_gid) ||
    fail_upgrade 15 "O grupo de acesso ao Docker não pôde ser identificado para o Terminal Seguro."
if [ "$(service_image "$web_service")" = "$control_image" ] &&
   [ "$(service_image "$agent_service")" = "$control_image" ] &&
   agent_version_is_current "$agent_service" &&
   control_image_matches_runtime "$control_image" &&
   [ "$(service_image "$terminal_service")" = "$terminal_image" ] &&
   docker image inspect "$strix_executor_image" >/dev/null 2>&1 &&
   [ "$(service_env_value "$terminal_service" SETUPMNO_STRIX_EXECUTOR_IMAGE)" = "$strix_executor_image" ] &&
   { [ "$assistant_exists" = "false" ] ||
     [ "$(service_image "$assistant_service")" = "$control_image" ]; }; then
    if service_has_group "$terminal_service" "$socket_gid" &&
       [ "$(service_env_value "$terminal_service" SETUPMNO_DOCKER_SOCKET_GID)" = "$socket_gid" ]; then
        ensure_runtime_permissions
        jq -n --arg plan "$plan" '{noop:true,plan:$plan}' >"$state_file"
        progress 100 "CONTROL CENTER JÁ ESTÁ SINCRONIZADO."
    else
        schedule_terminal_update ||
            fail_upgrade 46 "Falha ao agendar o reparo do acesso Docker no Terminal Seguro."
        ensure_runtime_permissions
        jq -n --arg plan "$plan" '{noop:true,plan:$plan,terminalReconciled:true}' >"$state_file"
        progress 100 "PAINEL SINCRONIZADO; ACESSO DO TERMINAL AO DOCKER PRONTO PARA REPARO."
    fi
    changed_services=()
    exit 0
fi

progress 10 "VALIDANDO O PACOTE DO CONTROL CENTER $target_version..."
install -d -m 0700 /root/setupmno-homologation-candidates ||
    fail_upgrade 20 "Não foi possível preparar o diretório privado da Central de Revisão."
for required_source in go.mod Dockerfile terminal.Dockerfile prepare-ttyd-index.sh \
    terminal-menu.sh configure-control.sh control-upgrade.sh main.go access.go knowledge.go \
    retrieval.go routing.go prompts.go sre_snapshot.go consultative_plan.go runbook_registry.go blueprint_recommendation.go evals.go \
    provider_evals.go feedback.go audit.go homologation.go web/index.html web/app.js web/assistant-route.js \
    web/styles.css web/terminal-bridge.js \
    strix-lab/upstream-lock.json strix-lab/authorization.schema.json \
    strix-lab/sanitized-report.schema.json strix-lab/validate.py strix-lab/wizard.sh \
    strix-lab/test.sh strix-lab/build-executor.sh strix-lab/executor.Dockerfile \
    strix-lab/executor.py; do
    [ -s "$source_dir/$required_source" ] && [ ! -L "$source_dir/$required_source" ] ||
        fail_upgrade 20 "Bundle incompleto ou inseguro: $required_source."
done

runtime_catalog="$runtime_dir/catalog.json"
runtime_release="$runtime_dir/release.json"
runtime_knowledge="$runtime_dir/knowledge-package"
[ -f "$runtime_catalog" ] && [ ! -L "$runtime_catalog" ] &&
[ -f "$runtime_release" ] && [ ! -L "$runtime_release" ] ||
    fail_upgrade 21 "Catálogo runtime ausente ou inseguro."
catalog_sha=$(sha256sum "$runtime_catalog" | awk '{print $1}')
expected_catalog_sha=$(jq -r '.catalogSHA256 // empty' "$runtime_release")
[ -n "$expected_catalog_sha" ] && [ "$catalog_sha" = "$expected_catalog_sha" ] ||
    fail_upgrade 21 "Catálogo runtime divergente do manifesto."
[ -f "$runtime_knowledge/manifest.json" ] && [ ! -L "$runtime_knowledge/manifest.json" ] &&
[ -f "$runtime_knowledge/knowledge-package.tar.gz" ] && [ ! -L "$runtime_knowledge/knowledge-package.tar.gz" ] ||
    fail_upgrade 22 "Pacote de conhecimento runtime ausente."
knowledge_sha=$(sha256sum "$runtime_knowledge/knowledge-package.tar.gz" | awk '{print $1}')
expected_knowledge_sha=$(jq -r '.archiveSHA256 // empty' "$runtime_knowledge/manifest.json")
[ -n "$expected_knowledge_sha" ] && [ "$knowledge_sha" = "$expected_knowledge_sha" ] &&
[ "$(jq -r '.controlVersion // empty' "$runtime_knowledge/manifest.json")" = "$target_version" ] ||
    fail_upgrade 22 "Pacote de conhecimento incompatível com o Control Center $target_version."

install -m 0644 "$runtime_catalog" "$source_dir/catalog.json"
mkdir -p "$source_dir/knowledge-package"
install -m 0644 "$runtime_knowledge/manifest.json" "$source_dir/knowledge-package/manifest.json"
install -m 0644 "$runtime_knowledge/knowledge-package.tar.gz" \
    "$source_dir/knowledge-package/knowledge-package.tar.gz"

run_with_heartbeat 25 "CONSTRUINDO A IMAGEM DO PAINEL $target_version..." \
    docker build --pull -t "$control_image" "$source_dir" ||
    fail_upgrade 30 "Falha ao construir a nova imagem do painel."
run_with_heartbeat 35 "VALIDANDO CONHECIMENTO E CATÁLOGO DO PAINEL..." \
    docker run --rm --entrypoint /setupmno-control "$control_image" knowledgecheck ||
    fail_upgrade 31 "A nova imagem recusou o conhecimento canônico."
run_with_heartbeat 40 "EXECUTANDO A SUÍTE DE QUALIDADE DO PAINEL..." \
    docker run --rm --entrypoint /setupmno-control "$control_image" evalcheck ||
    fail_upgrade 31 "A nova imagem não passou pela suíte de qualidade."

run_with_heartbeat 45 "CONSTRUINDO A IMAGEM DO TERMINAL PROTEGIDO..." \
    docker build --pull -f "$source_dir/terminal.Dockerfile" -t "$terminal_image" \
    "$source_dir" || fail_upgrade 32 "Falha ao construir o terminal protegido."
run_with_heartbeat 50 "CONSTRUINDO E VALIDANDO O EXECUTOR ISOLADO SRE-6 BETA..." \
    bash "$source_dir/strix-lab/build-executor.sh" \
    "$source_dir" "$strix_executor_image" "$log_file" ||
    fail_upgrade 32 "Falha ao construir ou validar o executor isolado SRE-6 BETA."
run_with_heartbeat 55 "VALIDANDO A COMPATIBILIDADE DO TERMINAL COM O SHC..." \
    docker run --rm --entrypoint /usr/bin/ldd -v /root:/root:ro \
    -v /usr/bin/bash:/usr/bin/bash:ro "$terminal_image" \
    /root/SetupLowCodeMno/install ||
    fail_upgrade 33 "O terminal não é compatível com o binário SHC instalado."

run_with_heartbeat 62 "ATUALIZANDO O AGENTE SEM RECRIAR A STACK..." \
    update_agent "$agent_service" "$control_image" || fail_upgrade 40 "Falha ao atualizar o agente."
changed_services+=("$agent_service")
run_with_heartbeat 66 "AGUARDANDO O AGENTE ATINGIR 1/1 RÉPLICA..." \
    wait_service "$agent_service" 1 || fail_upgrade 41 "O agente atualizado não atingiu 1/1 réplica."

if [ "$assistant_exists" = "true" ]; then
    run_with_heartbeat 72 "ATUALIZANDO O ASSISTENTE E PRESERVANDO O PLANO $plan..." \
        docker service update --image "$control_image" --replicas "$assistant_replicas" \
        --detach=true "$assistant_service" ||
        fail_upgrade 42 "Falha ao atualizar o Assistente MNO."
    changed_services+=("$assistant_service")
    run_with_heartbeat 76 "AGUARDANDO A CONVERGÊNCIA DO ASSISTENTE..." \
        wait_service "$assistant_service" "$assistant_replicas" ||
        fail_upgrade 43 "O Assistente atualizado não atingiu o estado esperado."
fi

run_with_heartbeat 84 "ATUALIZANDO O PAINEL E PRESERVANDO DOMÍNIO, SECRETS E VOLUME..." \
    update_web "$web_service" "$control_image" "$plan" || fail_upgrade 44 "Falha ao atualizar o painel web."
changed_services+=("$web_service")
run_with_heartbeat 88 "AGUARDANDO O PAINEL ATINGIR 1/1 RÉPLICA..." \
    wait_service "$web_service" 1 || fail_upgrade 45 "O painel atualizado não atingiu 1/1 réplica."

schedule_terminal_update ||
    fail_upgrade 46 "Falha ao agendar a troca protegida do terminal."
jq -n --arg plan "$plan" '{noop:true,plan:$plan,terminalReconciled:true}' >"$state_file" ||
    fail_upgrade 46 "Falha ao registrar a troca protegida do terminal."

changed_services=()
ensure_runtime_permissions
progress 100 "PAINEL SINCRONIZADO; TERMINAL PRONTO PARA TROCA CONTROLADA."
exit 0

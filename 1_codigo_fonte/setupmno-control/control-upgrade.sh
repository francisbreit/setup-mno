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

wait_service() {
    local service="$1" expected="$2" replicas
    [ "$expected" = "0" ] && return 0
    for _ in $(seq 1 40); do
        replicas=$(docker service ls --filter "name=$service" --format '{{.Replicas}}' \
            2>>"$log_file" | head -n1)
        [ "$replicas" = "${expected}/${expected}" ] && return 0
        sleep 3
    done
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
    docker "${args[@]}" "$service" >>"$log_file" 2>&1
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
if [ "$(service_image "$web_service")" = "$control_image" ] &&
   [ "$(service_image "$agent_service")" = "$control_image" ] &&
   [ "$(service_image "$terminal_service")" = "$terminal_image" ] &&
   { [ "$assistant_exists" = "false" ] ||
     [ "$(service_image "$assistant_service")" = "$control_image" ]; }; then
    jq -n --arg plan "$plan" '{noop:true,plan:$plan}' >"$state_file"
    progress 100 "CONTROL CENTER JÁ ESTÁ SINCRONIZADO."
    changed_services=()
    exit 0
fi

progress 10 "VALIDANDO O PACOTE DO CONTROL CENTER $target_version..."
install -d -m 0700 /root/setupmno-homologation-candidates ||
    fail_upgrade 20 "Não foi possível preparar o diretório privado da Central de Revisão."
for required_source in go.mod Dockerfile terminal.Dockerfile prepare-ttyd-index.sh \
    terminal-menu.sh configure-control.sh control-upgrade.sh main.go access.go knowledge.go \
    retrieval.go routing.go prompts.go blueprint_recommendation.go evals.go \
    provider_evals.go feedback.go audit.go homologation.go web/index.html web/app.js web/assistant-route.js \
    web/styles.css web/terminal-bridge.js; do
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

terminal_has_image_env=false
terminal_has_plan_env=false
service_has_env_key "$terminal_service" SETUPMNO_CONTROL_IMAGE && terminal_has_image_env=true
service_has_env_key "$terminal_service" SETUPMNO_CONTROL_PLAN && terminal_has_plan_env=true
jq -n --arg service "$terminal_service" --arg image "$terminal_image" \
    --arg control_image "$control_image" --arg plan "$plan" \
    --argjson has_image_env "$terminal_has_image_env" \
    --argjson has_plan_env "$terminal_has_plan_env" \
    '{noop:false,service:$service,image:$image,controlImage:$control_image,plan:$plan,
      hasImageEnv:$has_image_env,hasPlanEnv:$has_plan_env}' >"$state_file" ||
    fail_upgrade 46 "Falha ao preparar a troca protegida do terminal."

changed_services=()
progress 100 "PAINEL SINCRONIZADO; TERMINAL PRONTO PARA TROCA CONTROLADA."
exit 0

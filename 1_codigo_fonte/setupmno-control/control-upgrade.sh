#!/usr/bin/bash
# Atualização in-place do Setup MNO Control Center.
# Mantém stacks, serviços, secrets, volumes, domínio e propriedade no Portainer.
set -uo pipefail
umask 077

source_dir="${1:?diretório de fontes ausente}"
target_version="${2:?versão de destino ausente}"
log_file="${3:?log ausente}"
error_file="${4:?arquivo de erro ausente}"
state_file="${5:?arquivo de estado ausente}"
runtime_dir="/root/SetupLowCodeMno/.control"
changed_services=()

progress() {
    printf 'XXX\n%s\n%s\nXXX\n' "$1" "$2"
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

service_has_mount_target() {
    local service="$1" target="$2"
    docker service inspect --format '{{range .Spec.TaskTemplate.ContainerSpec.Mounts}}{{println .Target}}{{end}}' \
        "$service" 2>>"$log_file" | grep -Fxq "$target"
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
    args=(service update --image "$image" --detach=true --force)
    if service_has_mount_target "$service" /runtime-control; then
        args+=(--mount-rm /runtime-control)
    fi
    args+=(--mount-add type=bind,src=/root/SetupLowCodeMno/.control,dst=/runtime-control,readonly)
    docker "${args[@]}" "$service" >>"$log_file" 2>&1
}

update_web() {
    local service="$1" image="$2" plan="$3" args
    args=(service update --image "$image" --detach=true)
    service_has_env_key "$service" APP_VERSION && args+=(--env-rm APP_VERSION)
    args+=(--env-add "APP_VERSION=$target_version")
    service_has_env_key "$service" SETUPMNO_PLAN && args+=(--env-rm SETUPMNO_PLAN)
    args+=(--env-add "SETUPMNO_PLAN=$plan")
    docker "${args[@]}" "$service" >>"$log_file" 2>&1
}

update_assistant() {
    local service="$1" image="$2" replicas="$3"
    docker service update --image "$image" --replicas "$replicas" \
        --detach=true "$service" >>"$log_file" 2>&1
}

trap 'status=$?; if [ "$status" -ne 0 ] && [ "${#changed_services[@]}" -gt 0 ]; then rollback_changed_services; fi' EXIT

progress 3 "VALIDANDO A INSTALAÇÃO EXISTENTE..."
for command_name in docker jq tar sha256sum stat; do
    command -v "$command_name" >/dev/null 2>&1 ||
        fail_upgrade 10 "Dependência ausente durante a atualização: $command_name."
done
docker info >>"$log_file" 2>&1 || fail_upgrade 11 "Docker ou Swarm indisponível."

mapfile -t web_services < <(docker service ls --format '{{.Name}}' 2>>"$log_file" |
    grep -E '^mnoctrl[[:alnum:]]+-web_mnoctrl[[:alnum:]]+-web$' || true)
[ "${#web_services[@]}" -eq 1 ] ||
    fail_upgrade 12 "A atualização exige exatamente uma instalação identificável do Control Center; foram encontradas ${#web_services[@]}."

web_full="${web_services[0]}"
prefix="${web_full%%-web_*}"
[[ "$prefix" =~ ^mnoctrl[[:alnum:]]+$ ]] || fail_upgrade 12 "Prefixo do Control Center inválido."
web_service="${prefix}-web_${prefix}-web"
agent_service="${prefix}-agent_${prefix}-agent"
terminal_service="${prefix}-terminal_${prefix}-terminal"
assistant_service="${prefix}-assistant_${prefix}-assistant"

for required_service in "$web_service" "$agent_service" "$terminal_service"; do
    docker service inspect "$required_service" >>"$log_file" 2>&1 ||
        fail_upgrade 13 "A instalação está incompleta: serviço $required_service ausente. Nenhuma alteração foi realizada."
done
assistant_exists="false"
if docker service inspect "$assistant_service" >>"$log_file" 2>&1; then
    assistant_exists="true"
fi

plan=$(jq -er 'select(.schemaVersion == 1) | .plan |
    select(. == "pro" or . == "free" or . == "free1" or . == "free2")' \
    "$runtime_dir/environment.json" 2>>"$log_file") ||
    fail_upgrade 14 "O plano canônico do Control Center está ausente ou inválido."
case "$plan" in
    pro) assistant_replicas=1 ;;
    *) assistant_replicas=0 ;;
esac

control_image="${prefix}-app:${target_version}"
terminal_image="${prefix}-terminal:${target_version}"

progress 10 "VALIDANDO O PACOTE DA VERSÃO $target_version..."
for required_source in go.mod Dockerfile terminal.Dockerfile prepare-ttyd-index.sh \
    terminal-menu.sh configure-control.sh main.go knowledge.go retrieval.go routing.go \
    prompts.go blueprint_recommendation.go evals.go provider_evals.go feedback.go \
    web/index.html web/app.js web/assistant-route.js web/styles.css web/terminal-bridge.js; do
    [ -s "$source_dir/$required_source" ] && [ ! -L "$source_dir/$required_source" ] ||
        fail_upgrade 20 "Bundle incompleto ou inseguro: $required_source."
done

runtime_catalog="$runtime_dir/catalog.json"
runtime_release="$runtime_dir/release.json"
runtime_knowledge="$runtime_dir/knowledge-package"
[ -f "$runtime_catalog" ] && [ ! -L "$runtime_catalog" ] &&
[ -f "$runtime_release" ] && [ ! -L "$runtime_release" ] ||
    fail_upgrade 21 "Catálogo runtime ausente. Reinstale primeiro o Setup MNO v7.7.5."
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

progress 25 "CONSTRUINDO O PAINEL $target_version..."
docker build --pull -t "$control_image" "$source_dir" >>"$log_file" 2>&1 ||
    fail_upgrade 30 "Falha ao construir a nova imagem do painel."
docker run --rm --entrypoint /setupmno-control "$control_image" knowledgecheck \
    >>"$log_file" 2>&1 || fail_upgrade 31 "A nova imagem recusou o conhecimento canônico."
docker run --rm --entrypoint /setupmno-control "$control_image" evalcheck \
    >>"$log_file" 2>&1 || fail_upgrade 31 "A nova imagem não passou pela suíte canônica de qualidade."

progress 45 "CONSTRUINDO O TERMINAL PROTEGIDO $target_version..."
docker build --pull -f "$source_dir/terminal.Dockerfile" -t "$terminal_image" \
    "$source_dir" >>"$log_file" 2>&1 || fail_upgrade 32 "Falha ao construir o novo terminal protegido."
docker run --rm --entrypoint /usr/bin/ldd -v /root:/root:ro \
    -v /usr/bin/bash:/usr/bin/bash:ro "$terminal_image" \
    /root/SetupLowCodeMno/install >>"$log_file" 2>&1 ||
    fail_upgrade 33 "O novo terminal não é compatível com o binário SHC instalado."

progress 62 "ATUALIZANDO O AGENTE SEM ALTERAR SECRETS OU STACKS..."
update_agent "$agent_service" "$control_image" || fail_upgrade 40 "Falha ao atualizar o agente."
changed_services+=("$agent_service")
wait_service "$agent_service" 1 || fail_upgrade 41 "O agente atualizado não atingiu 1/1 réplica."

if [ "$assistant_exists" = "true" ]; then
    progress 72 "ATUALIZANDO O ASSISTENTE E PRESERVANDO O PLANO $plan..."
    update_assistant "$assistant_service" "$control_image" "$assistant_replicas" ||
        fail_upgrade 42 "Falha ao atualizar o Assistente MNO."
    changed_services+=("$assistant_service")
    wait_service "$assistant_service" "$assistant_replicas" ||
        fail_upgrade 43 "O Assistente atualizado não atingiu o estado esperado."
fi

progress 84 "ATUALIZANDO O PAINEL E PRESERVANDO DOMÍNIO E VOLUME..."
update_web "$web_service" "$control_image" "$plan" || fail_upgrade 44 "Falha ao atualizar o painel web."
changed_services+=("$web_service")
wait_service "$web_service" 1 || fail_upgrade 45 "O painel atualizado não atingiu 1/1 réplica."

terminal_has_image_env=false
terminal_has_plan_env=false
service_has_env_key "$terminal_service" SETUPMNO_CONTROL_IMAGE && terminal_has_image_env=true
service_has_env_key "$terminal_service" SETUPMNO_CONTROL_PLAN && terminal_has_plan_env=true
jq -n --arg service "$terminal_service" --arg image "$terminal_image" \
    --arg control_image "$control_image" --arg plan "$plan" \
    --argjson has_image_env "$terminal_has_image_env" \
    --argjson has_plan_env "$terminal_has_plan_env" \
    '{service:$service,image:$image,controlImage:$control_image,plan:$plan,
      hasImageEnv:$has_image_env,hasPlanEnv:$has_plan_env}' >"$state_file" ||
    fail_upgrade 46 "Falha ao preparar a troca protegida do terminal."

changed_services=()
progress 100 "PAINEL ATUALIZADO; TERMINAL PRONTO PARA REINÍCIO CONTROLADO."
exit 0

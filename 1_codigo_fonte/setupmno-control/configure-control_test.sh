#!/usr/bin/bash
set -euo pipefail

project_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source_file="$project_dir/configure-control.sh"
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT

extract_named_function() {
    local name="$1"
    awk -v name="$name" '
        $0 ~ "^" name "\\(\\)" { inside=1 }
        inside { print }
        inside && /^}/ { exit }
    ' "$source_file"
}

function_source=$(awk '
    /^portainer_request_ok\(\)/ { inside=1 }
    /^update_web_assistant\(\)/ { exit }
    inside { print }
' "$source_file")
[ -n "$function_source" ] || {
    printf 'ERRO: adaptador do Portainer ausente.\n' >&2
    exit 1
}
eval "$function_source"
eval "$(extract_named_function ensure_assistant_current_image)"

mkdir -p "$test_dir/bin"
cat >"$test_dir/bin/curl" <<'EOF'
#!/usr/bin/bash
set -euo pipefail
output=""
method="GET"
payload=""
url=""
form_args=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        -o) output="$2"; shift 2 ;;
        -X) method="$2"; shift 2 ;;
        --data-binary) payload="$2"; shift 2 ;;
        -F) form_args="$form_args|$2"; shift 2 ;;
        -H|-w) shift 2 ;;
        -*) shift ;;
        *) url="$1"; shift ;;
    esac
done
if [ "$payload" = "@-" ]; then
    cat >/dev/null
fi
case "$url" in
    */api/auth)
        printf '%s' '{"jwt":"test-jwt"}' >"$output"
        ;;
    */api/stacks)
        if [ "$MOCK_STACK_STATE" = "existing" ]; then
            printf '%s' '[{"Id":42,"Name":"mno-test-assistant","EndpointId":7,"Env":[{"name":"KEEP","value":"yes"}]},{"Id":40,"Name":"mno-test-web","EndpointId":7}]' >"$output"
        else
            printf '%s' '[{"Id":40,"Name":"mno-test-web","EndpointId":7}]' >"$output"
        fi
        printf '200'
        ;;
    */api/stacks/42/file)
        printf '%s' '{"StackFileContent":"version: \"3.7\"\nservices:\n  assistant:\n    image: mno-test-app:4.22.2\n    environment:\n      - ASSISTANT_PROVIDER=openrouter\n      - ASSISTANT_MODEL=google/modelo-antigo\n"}' >"$output"
        printf '200'
        ;;
    */api/stacks/42\?endpointId=7)
        if [ "$method" = "PUT" ]; then
            cp "${payload#@}" "$MOCK_CAPTURE/payload.json"
            printf '%s' '{}' >"$output"
            printf '200'
        elif [ "$method" = "DELETE" ]; then
            : >"$MOCK_CAPTURE/deleted-42"
            : >"$output"
            printf '204'
        else
            exit 71
        fi
        ;;
    */api/stacks/99\?endpointId=7)
        : >"$MOCK_CAPTURE/deleted-99"
        : >"$output"
        printf '204'
        ;;
    */api/endpoints/7/docker/swarm)
        printf '%s' '{"ID":"swarm-test"}' >"$output"
        printf '200'
        ;;
    */api/stacks/create/swarm/file)
        printf '%s' "$form_args" >"$MOCK_CAPTURE/create-form.txt"
        printf '%s' '{"Id":99}' >"$output"
        printf '201'
        ;;
    *)
        printf 'URL inesperada: %s\n' "$url" >&2
        exit 72
        ;;
esac
EOF
chmod 0755 "$test_dir/bin/curl"
PATH="$test_dir/bin:$PATH"
export PATH MOCK_CAPTURE="$test_dir/capture"
mkdir -p "$MOCK_CAPTURE"

work_dir="$test_dir/work"
mkdir -p "$work_dir"
operation_log="$work_dir/operation.log"
portainer_credentials="$test_dir/dados_portainer"
cat >"$portainer_credentials" <<'EOF'
Dominio do portainer: portainer.test
Usuario: admin
Senha: senha-somente-de-teste
EOF
assistant_stack="mno-test-assistant"
assistant_service="mno-test-assistant_mno-test-assistant"
web_service="mno-test-web_mno-test-web"
assistant_yaml="$work_dir/assistant.yaml"
printf '%s\n' 'version: new' >"$assistant_yaml"
portainer_stacks="$work_dir/portainer-stacks.json"
assistant_portainer_previous_yaml="$work_dir/assistant-previous.yaml"
assistant_portainer_previous_env="$work_dir/assistant-previous-env.json"
control_image="mno-test-app:4.33.4"
assistant_portainer_stack_id=""
assistant_portainer_endpoint_id=""
assistant_portainer_swarm_id=""
assistant_portainer_action=""
assistant_deploy_backend=""
portainer_url=""
portainer_token=""
stack_manager="portainer"
wait_service() { return 0; }
fail() { printf '%s\n' "$1" >&2; return 1; }
docker() {
    if [ "$1" = "stack" ] && [ "$2" = "config" ]; then
        return 0
    fi
    return 73
}

export MOCK_STACK_STATE="existing"
resolve_stack_manager
[ "$assistant_deploy_backend" = "portainer" ]
deploy_assistant_through_portainer
[ "$assistant_portainer_action" = "updated" ]
jq -e '.stackFileContent == "version: new\n" and .env[0].name == "KEEP" and .prune == true' \
    "$MOCK_CAPTURE/payload.json" >/dev/null
grep -Fq 'image: mno-test-app:4.33.4' "$assistant_portainer_previous_yaml"
! grep -Fq 'mno-test-app:4.22.2' "$assistant_portainer_previous_yaml"
cp "$MOCK_CAPTURE/payload.json" "$MOCK_CAPTURE/update-payload.json"
rollback_assistant_deploy true
jq -e '.stackFileContent | contains("image: mno-test-app:4.33.4")' \
    "$MOCK_CAPTURE/payload.json" >/dev/null
jq -e '.stackFileContent | contains("mno-test-app:4.22.2") | not' \
    "$MOCK_CAPTURE/payload.json" >/dev/null
jq -e '.env[0].name == "KEEP"' \
    "$MOCK_CAPTURE/payload.json" >/dev/null

multi_image_yaml="$work_dir/multi-image.yaml"
cat >"$multi_image_yaml" <<'EOF'
version: "3.7"
services:
  one:
    image: example/one:old
  two:
    image: example/two:old
EOF
if normalize_assistant_rollback_image "$multi_image_yaml"; then
    printf 'ERRO: rollback aceitou YAML ambíguo com duas imagens.\n' >&2
    exit 1
fi

assistant_portainer_action=""
remove_assistant_stack
test -f "$MOCK_CAPTURE/deleted-42"

export MOCK_STACK_STATE="new"
assistant_portainer_action=""
assistant_portainer_stack_id=""
assistant_portainer_endpoint_id=""
assistant_portainer_swarm_id=""
refresh_portainer_stacks
deploy_assistant_through_portainer
[ "$assistant_portainer_action" = "created" ]
[ "$assistant_portainer_stack_id" = "99" ]
grep -Fq '|Name=mno-test-assistant' "$MOCK_CAPTURE/create-form.txt"
grep -Fq '|SwarmID=swarm-test' "$MOCK_CAPTURE/create-form.txt"
grep -Fq '|endpointId=7' "$MOCK_CAPTURE/create-form.txt"
grep -Fq "|file=@$assistant_yaml" "$MOCK_CAPTURE/create-form.txt"

rollback_assistant_deploy
test -f "$MOCK_CAPTURE/deleted-99"

stack_manager="docker"
assistant_deploy_backend=""
resolve_stack_manager
[ "$assistant_deploy_backend" = "docker" ]

image_repair_log="$test_dir/image-repair.log"
docker() {
    if [ "$1" = "service" ] && [ "$2" = "inspect" ] && [ "${3:-}" != "--format" ]; then
        return 0
    elif [ "$1" = "service" ] && [ "$2" = "inspect" ] && [ "$3" = "--format" ]; then
        printf '%s\n' 'mno-test-app:4.22.2@sha256:old'
    elif [ "$1" = "service" ] && [ "$2" = "update" ]; then
        printf '%s\n' "$*" >>"$image_repair_log"
    else
        return 76
    fi
}
ensure_assistant_current_image
grep -Fq -- '--image mno-test-app:4.33.4' "$image_repair_log"

eval "$(extract_named_function configure_assistant_wait_policy)"
eval "$(extract_named_function assistant_spec_matches)"
eval "$(extract_named_function assistant_container_matches)"
eval "$(extract_named_function assistant_health_matches)"
eval "$(extract_named_function wait_assistant_ready)"

assistant_service="mno-test-assistant_mno-test-assistant"
agent_secret="mno-test-agent-token"
provider_secret="mno-test-llm-openrouter"
service_inspect_fixture="$test_dir/service-inspect.json"
container_inspect_fixture="$test_dir/container-inspect.json"
cat >"$service_inspect_fixture" <<EOF
[{"Spec":{"TaskTemplate":{"ContainerSpec":{"Image":"$control_image@sha256:abc","Env":["ASSISTANT_PROVIDER=openrouter","ASSISTANT_MODEL=nvidia/modelo-novo"],"Secrets":[{"SecretName":"$provider_secret","File":{"Name":"llm_api_key"}}]}}}}]
EOF
cat >"$container_inspect_fixture" <<EOF
[{"Config":{"Image":"$control_image","Env":["ASSISTANT_PROVIDER=openrouter","ASSISTANT_MODEL=nvidia/modelo-novo"]},"State":{"Status":"running","Health":{"Status":"healthy"}}}]
EOF
docker() {
    if [ "$1" = "service" ] && [ "$2" = "inspect" ] && [ "${3:-}" != "--format" ]; then
        cat "$service_inspect_fixture"
    elif [ "$1" = "ps" ]; then
        printf '%s\n' 'container-new'
    elif [ "$1" = "inspect" ]; then
        cat "$container_inspect_fixture"
    else
        return 74
    fi
}
curl() {
    local output=""
    while [ "$#" -gt 0 ]; do
        case "$1" in
            -o) output="$2"; shift 2 ;;
            *) shift ;;
        esac
    done
    printf '%s' '{"status":"ok","provider":"openrouter","model":"nvidia/modelo-novo"}' >"$output"
}
assistant_spec_matches openrouter nvidia/modelo-novo "$provider_secret"
assistant_container_matches openrouter nvidia/modelo-novo
assistant_health_matches openrouter nvidia/modelo-novo
if assistant_spec_matches openrouter google/modelo-antigo "$provider_secret"; then
    printf 'ERRO: identidade antiga foi aceita como nova especificação.\n' >&2
    exit 1
fi

readiness_attempt=0
configure_assistant_wait_policy() {
    assistant_wait_attempts=2
    assistant_wait_interval=0
}
docker() {
    if [ "$1" = "service" ] && [ "$2" = "inspect" ] && [ "$3" = "--format" ]; then
        printf '%s\n' completed
    elif [ "$1" = "service" ] && [ "$2" = "ls" ]; then
        printf '%s\n' '1/1'
    else
        return 75
    fi
}
assistant_spec_matches() {
    readiness_attempt=$((readiness_attempt + 1))
    [ "$readiness_attempt" -ge 2 ]
}
assistant_container_matches() { [ "$readiness_attempt" -ge 2 ]; }
assistant_health_matches() { [ "$readiness_attempt" -ge 2 ]; }
wait_assistant_ready openrouter nvidia/modelo-novo "$provider_secret"
[ "$readiness_attempt" -eq 2 ] || {
    printf 'ERRO: readiness não aguardou a identidade nova.\n' >&2
    exit 1
}

eval "$(extract_named_function read_control_plan)"
eval "$(extract_named_function update_web_assistant)"
control_environment_file="$test_dir/environment.json"
web_service="mno-test-web_mno-test-web"
docker_log="$test_dir/docker-service-update.log"
docker() {
    printf '%s\n' "$*" >>"$docker_log"
}
wait_service() {
    [ "$1" = "$web_service" ]
}

for restricted_plan in free free1 free2; do
    printf '{"schemaVersion":1,"plan":"%s","installationType":"TRADICIONAL"}\n' \
        "$restricted_plan" >"$control_environment_file"
    : >"$docker_log"
    if update_web_assistant openrouter openai/gpt-5.4 http://assistant:7070; then
        printf 'ERRO: plano %s ativou o Assistente com IA.\n' "$restricted_plan" >&2
        exit 1
    fi
    [ ! -s "$docker_log" ]
done

printf '%s\n' '{"schemaVersion":1,"plan":"pro","installationType":"TRADICIONAL"}' \
    >"$control_environment_file"
: >"$docker_log"
update_web_assistant openrouter openai/gpt-5.4 http://assistant:7070
grep -Fq -- '--env-rm ASSISTANT_MODE --env-add ASSISTANT_MODE=openrouter' "$docker_log"
grep -Fq -- '--env-rm ASSISTANT_MODEL --env-add ASSISTANT_MODEL=openai/gpt-5.4' "$docker_log"
grep -Fq -- '--env-rm ASSISTANT_URL --env-add ASSISTANT_URL=http://assistant:7070' "$docker_log"
grep -Fq -- '--env-rm SETUPMNO_PLAN --env-add SETUPMNO_PLAN=pro' "$docker_log"

printf '%s\n' '{"schemaVersion":1,"plan":"pro-master","installationType":"CLOUDFLARE_TUNNEL"}' \
    >"$control_environment_file"
: >"$docker_log"
update_web_assistant openrouter openai/gpt-5.4 http://assistant:7070
grep -Fq -- '--env-rm SETUPMNO_PLAN --env-add SETUPMNO_PLAN=pro-master' "$docker_log"

printf 'Identidade forte, rollback sem downgrade, Portainer e herança PRO MASTER aprovados.\n'

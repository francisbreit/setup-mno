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
        printf '%s' '{"StackFileContent":"version: old"}' >"$output"
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

export MOCK_STACK_STATE="existing"
resolve_stack_manager
[ "$assistant_deploy_backend" = "portainer" ]
deploy_assistant_through_portainer
[ "$assistant_portainer_action" = "updated" ]
jq -e '.stackFileContent == "version: new\n" and .env[0].name == "KEEP" and .prune == true' \
    "$MOCK_CAPTURE/payload.json" >/dev/null
grep -Fq 'version: old' "$assistant_portainer_previous_yaml"
cp "$MOCK_CAPTURE/payload.json" "$MOCK_CAPTURE/update-payload.json"
rollback_assistant_deploy true
jq -e '.stackFileContent == "version: old\n" and .env[0].name == "KEEP"' \
    "$MOCK_CAPTURE/payload.json" >/dev/null

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

printf 'Persistência Portainer e herança PRO do plano PRO MASTER aprovadas.\n'

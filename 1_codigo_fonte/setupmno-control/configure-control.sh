#!/usr/bin/bash
set -Eeuo pipefail
umask 077

if [ "${SETUPMNO_CONFIG_SMOKE_TEST:-0}" = "1" ]; then
    printf '%s\n' "setupmno-control-config-ok"
    exit 0
fi

title="SETUP MNO — CONFIGURAÇÕES"
work_dir=$(mktemp -d)
operation_log="$work_dir/operation.log"
assistant_yaml="$work_dir/assistant.yaml"
terminal_mode="${SETUPMNO_TERMINAL_MODE:-direct}"
control_environment_file="/root/SetupLowCodeMno/.control/environment.json"

# Tema exclusivo das Configurações Seguras. O instalador e os scripts das
# aplicações preservam seus próprios temas; aqui o item em foco é sempre
# preto sobre branco para permanecer visível no terminal de fundo preto.
export NEWT_COLORS='
root=white,black
border=lightgray,black
title=yellow,black
roottext=white,black
window=white,black
shadow=black,black
textbox=white,black
acttextbox=black,white
entry=white,black
disentry=gray,black
button=white,black
actbutton=black,white
compactbutton=white,black
listbox=white,black
actlistbox=black,white
actsellistbox=black,white
checkbox=white,black
actcheckbox=black,white
helpline=lightgray,black
'

dialog_height() {
    local requested="$1" available
    available=$(tput lines 2>/dev/null || printf '24')
    available=$((available - 2))
    [ "$available" -ge 5 ] || available=5
    [ "$requested" -le "$available" ] || requested="$available"
    printf '%s' "$requested"
}

dialog_width() {
    local requested="$1" available
    available=$(tput cols 2>/dev/null || printf '80')
    available=$((available - 2))
    [ "$available" -ge 10 ] || available=10
    [ "$requested" -le "$available" ] || requested="$available"
    printf '%s' "$requested"
}

cleanup() {
    unset current_password expected_password new_password password_confirmation llm_api_key
    rm -rf "$work_dir"
}
trap cleanup EXIT

msg() {
    local height width
    height=$(dialog_height 16)
    width=$(dialog_width 84)
    whiptail --title "$title" --msgbox "$1" "$height" "$width" 1>&2
}

fail() {
    msg "$1"
    return 1
}

required_environment=(
    SETUPMNO_CONTROL_PREFIX
    SETUPMNO_CONTROL_IMAGE
    SETUPMNO_CONTROL_WEB_SERVICE
    SETUPMNO_CONTROL_TERMINAL_SERVICE
    SETUPMNO_CONTROL_AGENT_SERVICE
    SETUPMNO_CONTROL_ASSISTANT_STACK
    SETUPMNO_CONTROL_ASSISTANT_COMPONENT
    SETUPMNO_CONTROL_AGENT_SECRET
    SETUPMNO_CONTROL_ADMIN_SECRET
    SETUPMNO_CONTROL_ADMIN_USERNAME
    ADMIN_PASSWORD_FILE
)
for variable_name in "${required_environment[@]}"; do
    [ -n "${!variable_name:-}" ] || {
        msg "Esta instalação não possui os metadados seguros necessários para reconfiguração.\n\nReinstale ou atualize o Control Center pela versão 7.2.9."
        exit 1
    }
done

control_image=$SETUPMNO_CONTROL_IMAGE
web_service=$SETUPMNO_CONTROL_WEB_SERVICE
terminal_service=$SETUPMNO_CONTROL_TERMINAL_SERVICE
assistant_stack=$SETUPMNO_CONTROL_ASSISTANT_STACK
assistant_component=$SETUPMNO_CONTROL_ASSISTANT_COMPONENT
assistant_service="${assistant_stack}_${assistant_component}"
agent_secret=$SETUPMNO_CONTROL_AGENT_SECRET
admin_secret=$SETUPMNO_CONTROL_ADMIN_SECRET
admin_username=$SETUPMNO_CONTROL_ADMIN_USERNAME
admin_password_file=$ADMIN_PASSWORD_FILE
stack_manager=${SETUPMNO_CONTROL_STACK_MANAGER:-auto}
portainer_credentials=${SETUPMNO_CONTROL_PORTAINER_CREDENTIALS:-/root/dados_portainer/dados_portainer}
portainer_url=""
portainer_token=""
portainer_stacks="$work_dir/portainer-stacks.json"
assistant_deploy_backend=""
assistant_portainer_action=""
assistant_portainer_stack_id=""
assistant_portainer_endpoint_id=""
assistant_portainer_swarm_id=""
assistant_portainer_previous_yaml="$work_dir/assistant-previous.yaml"
assistant_portainer_previous_env="$work_dir/assistant-previous-env.json"

case "$stack_manager" in
    portainer|docker|auto) ;;
    *)
        msg "O gerenciador de stacks informado pela instalação é inválido. Nenhuma alteração foi realizada."
        exit 1
        ;;
esac

for service_name in "$web_service" "$terminal_service"; do
    docker service inspect "$service_name" >/dev/null 2>&1 || {
        msg "O serviço obrigatório '$service_name' não foi encontrado. Nenhuma alteração foi realizada."
        exit 1
    }
done
[ -f "$admin_password_file" ] && [ ! -L "$admin_password_file" ] || {
    msg "A credencial administrativa não está disponível como Docker Secret regular."
    exit 1
}

ask_required() {
    local prompt="$1" default_value="${2:-}" value status height width
    height=$(dialog_height 14)
    width=$(dialog_width 84)
    while true; do
        value=$(whiptail --title "$title" --inputbox "$prompt" "$height" "$width" "$default_value" \
            3>&1 1>&2 2>&3)
        status=$?
        [ "$status" -ne 0 ] && return 130
        [ -n "$value" ] && {
            printf '%s' "$value"
            return 0
        }
        msg "Este campo é obrigatório."
    done
}

ask_secret() {
    local prompt="$1" value status height width
    height=$(dialog_height 14)
    width=$(dialog_width 84)
    while true; do
        value=$(whiptail --title "$title" --passwordbox "$prompt" "$height" "$width" \
            3>&1 1>&2 2>&3)
        status=$?
        [ "$status" -ne 0 ] && return 130
        if [ "${#value}" -ge 16 ] && [[ "$value" != *[[:space:]]* ]]; then
            printf '%s' "$value"
            return 0
        fi
        msg "A chave deve possuir pelo menos 16 caracteres e não pode conter espaços."
    done
}

authenticate_admin() {
    local entered status height width
    height=$(dialog_height 14)
    width=$(dialog_width 84)
    entered=$(whiptail --title "$title" --passwordbox \
        "Confirme a senha administrativa atual.\n\nEla será comparada localmente com o Docker Secret e não será registrada." \
        "$height" "$width" 3>&1 1>&2 2>&3)
    status=$?
    [ "$status" -ne 0 ] && return 130
    expected_password=$(<"$admin_password_file")
    if [ "${#entered}" -ne "${#expected_password}" ] || [ "$entered" != "$expected_password" ]; then
        unset entered expected_password
        msg "Senha atual incorreta. Nenhuma alteração foi realizada."
        return 1
    fi
    unset entered expected_password
}

wait_service() {
    local service_name="$1" state replicas
    for _ in $(seq 1 45); do
        state=$(docker service inspect --format \
            '{{if .UpdateStatus}}{{.UpdateStatus.State}}{{else}}completed{{end}}' \
            "$service_name" 2>/dev/null || true)
        replicas=$(docker service ls --filter "name=$service_name" \
            --format '{{.Replicas}}' 2>/dev/null | head -n1)
        if [ "$state" = "completed" ] && [ "$replicas" = "1/1" ]; then
            return 0
        fi
        case "$state" in
            paused|rollback_paused)
                return 1
                ;;
        esac
        sleep 2
    done
    return 1
}

rollback_service() {
    local service_name="$1"
    docker service rollback --detach=true "$service_name" >>"$operation_log" 2>&1 || true
    wait_service "$service_name" || true
}

portainer_request_ok() {
    local method="$1" url="$2" output_file="$3" payload_file="${4:-}" http_code
    if [ -n "$payload_file" ]; then
        http_code=$(curl -skS -o "$output_file" -w '%{http_code}' -X "$method" \
            -H "Authorization: Bearer $portainer_token" \
            -H "Content-Type: application/json" \
            --data-binary "@$payload_file" "$url" 2>>"$operation_log") || return 1
    else
        http_code=$(curl -skS -o "$output_file" -w '%{http_code}' -X "$method" \
            -H "Authorization: Bearer $portainer_token" \
            "$url" 2>>"$operation_log") || return 1
    fi
    [[ "$http_code" =~ ^2[0-9][0-9]$ ]] || {
        printf 'Portainer HTTP %s ao acessar %s.\n' "${http_code:-indisponível}" "$url" \
            >>"$operation_log"
        return 1
    }
}

portainer_authenticate() {
    local domain username password auth_file="$work_dir/portainer-auth.json"
    [ -f "$portainer_credentials" ] && [ ! -L "$portainer_credentials" ] || return 1
    domain=$(sed -n 's/^Dominio do portainer:[[:space:]]*//p' "$portainer_credentials" | head -n1)
    username=$(sed -n 's/^Usuario:[[:space:]]*//p' "$portainer_credentials" | head -n1)
    password=$(sed -n 's/^Senha:[[:space:]]*//p' "$portainer_credentials" | head -n1)
    [ -n "$domain" ] && [ -n "$username" ] && [ -n "$password" ] || {
        unset password
        return 1
    }
    case "$domain" in
        http://*|https://*) portainer_url="${domain%/}" ;;
        *) portainer_url="https://${domain%/}" ;;
    esac
    if ! printf '%s\0%s' "$username" "$password" |
        jq -Rs 'split("\u0000") | {username:.[0], password:.[1]}' |
        curl -skS -o "$auth_file" -X POST \
            -H "Content-Type: application/json" --data-binary @- \
            "$portainer_url/api/auth" 2>>"$operation_log"; then
        unset password
        return 1
    fi
    unset password
    portainer_token=$(jq -r '.jwt // empty' "$auth_file" 2>/dev/null)
    [ -n "$portainer_token" ] || return 1
    portainer_request_ok GET "$portainer_url/api/stacks" "$portainer_stacks" || return 1
    jq -e 'type == "array"' "$portainer_stacks" >/dev/null 2>&1
}

portainer_stack_field() {
    local stack_name="$1" field="$2"
    jq -r --arg name "$stack_name" --arg field "$field" \
        '.[] | select(.Name == $name) | .[$field] // empty' "$portainer_stacks" | head -n1
}

refresh_portainer_stacks() {
    portainer_request_ok GET "$portainer_url/api/stacks" "$portainer_stacks" &&
        jq -e 'type == "array"' "$portainer_stacks" >/dev/null 2>&1
}

resolve_stack_manager() {
    local web_stack existing_control_stack
    [ -n "$assistant_deploy_backend" ] && return 0
    case "$stack_manager" in
        docker)
            assistant_deploy_backend="docker"
            return 0
            ;;
        portainer)
            if ! portainer_authenticate; then
                fail "A instalação foi configurada para stacks editáveis no Portainer, mas a API não pôde ser autenticada.\n\nConfira as credenciais em $portainer_credentials. Nenhuma conversão para Docker direto foi realizada."
                return 1
            fi
            assistant_deploy_backend="portainer"
            return 0
            ;;
    esac

    # Compatibilidade com instalações anteriores à persistência explícita do modo.
    # Somente seleciona o Portainer quando uma stack deste Control Center já está
    # registrada nele; caso contrário preserva o comportamento Docker anterior.
    if portainer_authenticate; then
        web_stack=${web_service%%_*}
        existing_control_stack=$(jq -r --arg assistant "$assistant_stack" --arg web "$web_stack" \
            '.[] | select(.Name == $assistant or .Name == $web) | .Id // empty' \
            "$portainer_stacks" | head -n1)
        if [ -n "$existing_control_stack" ]; then
            assistant_deploy_backend="portainer"
            return 0
        fi
    fi
    assistant_deploy_backend="docker"
}

portainer_endpoint_and_swarm() {
    local endpoint_file="$work_dir/portainer-endpoints.json"
    local swarm_file="$work_dir/portainer-swarm.json" web_stack
    assistant_portainer_endpoint_id=$(portainer_stack_field "$assistant_stack" EndpointId)
    if [ -z "$assistant_portainer_endpoint_id" ]; then
        web_stack=${web_service%%_*}
        assistant_portainer_endpoint_id=$(portainer_stack_field "$web_stack" EndpointId)
    fi
    if [ -z "$assistant_portainer_endpoint_id" ]; then
        portainer_request_ok GET "$portainer_url/api/endpoints" "$endpoint_file" || return 1
        assistant_portainer_endpoint_id=$(jq -r '.[0].Id // empty' "$endpoint_file")
    fi
    [ -n "$assistant_portainer_endpoint_id" ] || return 1
    portainer_request_ok GET \
        "$portainer_url/api/endpoints/$assistant_portainer_endpoint_id/docker/swarm" \
        "$swarm_file" || return 1
    assistant_portainer_swarm_id=$(jq -r '.ID // empty' "$swarm_file")
    [ -n "$assistant_portainer_swarm_id" ]
}

portainer_update_stack() {
    local stack_id="$1" endpoint_id="$2" yaml_file="$3" env_file="$4"
    local payload="$work_dir/portainer-stack-update.json" response="$work_dir/portainer-stack-update-response.json"
    jq -n --rawfile stack_file "$yaml_file" --slurpfile stack_env "$env_file" \
        '{stackFileContent:$stack_file, env:$stack_env[0], prune:true, pullImage:false}' \
        >"$payload" || return 1
    portainer_request_ok PUT \
        "$portainer_url/api/stacks/$stack_id?endpointId=$endpoint_id" \
        "$response" "$payload"
}

deploy_assistant_through_portainer() {
    local stack_file_response="$work_dir/portainer-assistant-file.json"
    local create_response="$work_dir/portainer-assistant-create.json" http_code
    refresh_portainer_stacks || return 1
    assistant_portainer_stack_id=$(portainer_stack_field "$assistant_stack" Id)
    if [ -n "$assistant_portainer_stack_id" ]; then
        assistant_portainer_endpoint_id=$(portainer_stack_field "$assistant_stack" EndpointId)
        [ -n "$assistant_portainer_endpoint_id" ] || return 1
        portainer_request_ok GET \
            "$portainer_url/api/stacks/$assistant_portainer_stack_id/file" \
            "$stack_file_response" || return 1
        jq -er '.StackFileContent' "$stack_file_response" >"$assistant_portainer_previous_yaml" || return 1
        jq --arg name "$assistant_stack" \
            '[.[] | select(.Name == $name) | .Env // []][0] // []' \
            "$portainer_stacks" >"$assistant_portainer_previous_env" || return 1
        assistant_portainer_action="updated"
        portainer_update_stack "$assistant_portainer_stack_id" \
            "$assistant_portainer_endpoint_id" "$assistant_yaml" \
            "$assistant_portainer_previous_env" || return 1
        return 0
    fi

    portainer_endpoint_and_swarm || return 1
    assistant_portainer_action="created"
    http_code=$(curl -skS -o "$create_response" -w '%{http_code}' -X POST \
        -H "Authorization: Bearer $portainer_token" \
        -F "Name=$assistant_stack" \
        -F "file=@$assistant_yaml" \
        -F "SwarmID=$assistant_portainer_swarm_id" \
        -F "endpointId=$assistant_portainer_endpoint_id" \
        "$portainer_url/api/stacks/create/swarm/file" 2>>"$operation_log") || return 1
    [[ "$http_code" =~ ^2[0-9][0-9]$ ]] || return 1
    assistant_portainer_stack_id=$(jq -r '.Id // empty' "$create_response")
}

remove_assistant_stack() {
    local response="$work_dir/portainer-assistant-delete.json" stack_id endpoint_id
    resolve_stack_manager || return 1
    if [ "$assistant_deploy_backend" = "docker" ]; then
        docker stack rm "$assistant_stack" >>"$operation_log" 2>&1 || true
        return 0
    fi
    refresh_portainer_stacks || return 1
    stack_id=$(portainer_stack_field "$assistant_stack" Id)
    [ -n "$stack_id" ] || return 0
    endpoint_id=$(portainer_stack_field "$assistant_stack" EndpointId)
    [ -n "$endpoint_id" ] || return 1
    portainer_request_ok DELETE \
        "$portainer_url/api/stacks/$stack_id?endpointId=$endpoint_id" "$response"
}

rollback_assistant_deploy() {
    local previous_exists="${1:-false}" response="$work_dir/portainer-assistant-rollback.json"
    if [ "$assistant_deploy_backend" = "portainer" ]; then
        case "$assistant_portainer_action" in
            updated)
                portainer_update_stack "$assistant_portainer_stack_id" \
                    "$assistant_portainer_endpoint_id" "$assistant_portainer_previous_yaml" \
                    "$assistant_portainer_previous_env" >>"$operation_log" 2>&1 || true
                wait_service "$assistant_service" || true
                ;;
            created)
                [ -n "$assistant_portainer_stack_id" ] || {
                    refresh_portainer_stacks || true
                    assistant_portainer_stack_id=$(portainer_stack_field "$assistant_stack" Id)
                }
                [ -z "$assistant_portainer_stack_id" ] ||
                    portainer_request_ok DELETE \
                        "$portainer_url/api/stacks/$assistant_portainer_stack_id?endpointId=$assistant_portainer_endpoint_id" \
                        "$response" >>"$operation_log" 2>&1 || true
                ;;
        esac
    elif [ "$previous_exists" = "true" ]; then
        rollback_service "$assistant_service"
    else
        docker stack rm "$assistant_stack" >>"$operation_log" 2>&1 || true
    fi
}

update_web_assistant() {
    local provider="$1" model="$2" assistant_url="$3" control_plan
    control_plan=$(read_control_plan) || return 1
    [ "$control_plan" = "pro" ] || return 1
    docker service update --detach=true \
        --env-rm ASSISTANT_MODE --env-add "ASSISTANT_MODE=$provider" \
        --env-rm ASSISTANT_MODEL --env-add "ASSISTANT_MODEL=$model" \
        --env-rm ASSISTANT_URL --env-add "ASSISTANT_URL=$assistant_url" \
        --env-rm SETUPMNO_PLAN --env-add "SETUPMNO_PLAN=$control_plan" \
        "$web_service" >>"$operation_log" 2>&1 &&
        wait_service "$web_service"
}

read_control_plan() {
    jq -er \
        'select(.schemaVersion == 1) | .plan | select(. == "pro" or . == "free" or . == "free1" or . == "free2")' \
        "$control_environment_file" 2>/dev/null
}

configure_username() {
    local new_username height width
    authenticate_admin || return $?
    if ! new_username=$(ask_required \
        "Novo usuário administrador:\n\nUse de 3 a 40 caracteres: letras, números, ponto, hífen ou sublinhado." \
        "$admin_username"); then
        return 0
    fi
    if [[ ! "$new_username" =~ ^[A-Za-z0-9_.-]{3,40}$ ]]; then
        fail "Nome de usuário inválido."
        return
    fi
    [ "$new_username" != "$admin_username" ] || {
        msg "O nome informado já é o usuário atual."
        return
    }
    height=$(dialog_height 15)
    width=$(dialog_width 84)
    whiptail --title "$title" --yesno \
        "Alterar o usuário de '$admin_username' para '$new_username'?\n\nTodas as sessões serão encerradas e você precisará entrar novamente." \
        "$height" "$width" || return 0

    if ! docker service update --detach=true \
        --env-rm ADMIN_USERNAME --env-add "ADMIN_USERNAME=$new_username" \
        "$web_service" >>"$operation_log" 2>&1 ||
       ! wait_service "$web_service"; then
        rollback_service "$web_service"
        fail "A atualização do usuário falhou e a configuração anterior foi restaurada."
        return
    fi

    if ! docker service update --detach=true \
        --env-rm SETUPMNO_CONTROL_ADMIN_USERNAME \
        --env-add "SETUPMNO_CONTROL_ADMIN_USERNAME=$new_username" \
        "$terminal_service" >>"$operation_log" 2>&1; then
        rollback_service "$web_service"
        fail "O Terminal Seguro recusou a atualização. O usuário anterior foi restaurado."
        return
    fi
    msg "Usuário alterado com sucesso.\n\nNovo usuário: $new_username\n\nTodas as sessões foram encerradas e o Terminal Seguro será reiniciado."
    exit 0
}

validate_new_password() {
    local value="$1"
    [ "${#value}" -ge 12 ] || {
        msg "Senha inválida: use pelo menos 12 caracteres."
        return 1
    }
    [[ "$value" =~ [[:upper:]] ]] || {
        msg "Senha inválida: inclua pelo menos uma letra maiúscula."
        return 1
    }
    [[ "$value" =~ [[:lower:]] ]] || {
        msg "Senha inválida: inclua pelo menos uma letra minúscula."
        return 1
    }
    [[ "$value" =~ [[:digit:]] ]] || {
        msg "Senha inválida: inclua pelo menos um número."
        return 1
    }
    [[ "$value" != *[[:space:]]* ]] || {
        msg "Senha inválida: não use espaços."
        return 1
    }
    [[ "$value" =~ [^[:alnum:][:space:]] ]] || {
        msg "Senha inválida: inclua pelo menos um símbolo, como !, @, # ou %."
        return 1
    }
}

configure_password() {
    local new_secret timestamp height width confirmation_height
    height=$(dialog_height 14)
    confirmation_height=$(dialog_height 12)
    width=$(dialog_width 84)
    authenticate_admin || return $?
    while true; do
        new_password=$(whiptail --title "$title" --passwordbox \
            "Nova senha administrativa:\n\nMínimo de 12 caracteres, com maiúscula, minúscula, número e símbolo." \
            "$height" "$width" 3>&1 1>&2 2>&3) || return 0
        validate_new_password "$new_password" || continue
        password_confirmation=$(whiptail --title "$title" --passwordbox \
            "Confirme a nova senha administrativa:" "$confirmation_height" "$width" \
            3>&1 1>&2 2>&3) || return 0
        [ "$new_password" = "$password_confirmation" ] || {
            msg "As senhas não coincidem."
            continue
        }
        break
    done
    height=$(dialog_height 15)
    whiptail --title "$title" --yesno \
        "Alterar a senha administrativa?\n\nTodas as sessões serão encerradas. O secret anterior será mantido até o novo serviço ficar saudável." \
        "$height" "$width" || return 0

    timestamp=$(date +%Y%m%d%H%M%S)
    new_secret="${admin_secret%-*}-password-$timestamp"
    if ! printf '%s' "$new_password" |
        docker secret create "$new_secret" - >>"$operation_log" 2>&1; then
        unset new_password password_confirmation
        fail "Não foi possível criar o novo Docker Secret."
        return
    fi
    unset new_password password_confirmation

    if ! docker service update --detach=true \
        --secret-rm "$admin_secret" \
        --secret-add "source=$new_secret,target=admin_password" \
        "$web_service" >>"$operation_log" 2>&1 ||
       ! wait_service "$web_service"; then
        rollback_service "$web_service"
        docker secret rm "$new_secret" >>"$operation_log" 2>&1 || true
        fail "A nova senha não passou pelo healthcheck. A senha anterior foi restaurada."
        return
    fi

    if ! docker service update --detach=true \
        --secret-rm "$admin_secret" \
        --secret-add "source=$new_secret,target=admin_password" \
        --env-rm SETUPMNO_CONTROL_ADMIN_SECRET \
        --env-add "SETUPMNO_CONTROL_ADMIN_SECRET=$new_secret" \
        "$terminal_service" >>"$operation_log" 2>&1; then
        rollback_service "$web_service"
        docker secret rm "$new_secret" >>"$operation_log" 2>&1 || true
        fail "O Terminal Seguro recusou a nova credencial. A senha anterior foi restaurada."
        return
    fi
    docker secret rm "$admin_secret" >>"$operation_log" 2>&1 || true
    msg "Senha alterada com sucesso.\n\nTodas as sessões foram invalidadas e o Terminal Seguro será reiniciado."
    exit 0
}

provider_label() {
    case "$1" in
        openai) printf 'OpenAI' ;;
        openrouter) printf 'OpenRouter' ;;
        deepseek) printf 'DeepSeek' ;;
        ollama) printf 'Ollama' ;;
        *) printf 'Diagnóstico básico' ;;
    esac
}

external_provider() {
    case "$1" in
        openai|openrouter|deepseek) return 0 ;;
        *) return 1 ;;
    esac
}

deploy_assistant() {
    local provider="$1" model="$2" base_url="$3" provider_secret="$4"
    cat >"$assistant_yaml" <<EOF
version: "3.7"
services:
  $assistant_component:
    image: $control_image
    hostname: $assistant_component
    user: "65532:65532"
    read_only: true
    cap_drop:
      - ALL
    environment:
      - MODE=assistant
      - HEALTHCHECK_URL=http://127.0.1.1:7070/health
      - ASSISTANT_PROVIDER=$provider
      - ASSISTANT_MODEL=$model
      - ASSISTANT_BASE_URL=$base_url
      - KNOWLEDGE_PACKAGE_DIR=/knowledge-package
      - RETRIEVAL_SHADOW_ENABLED=true
      - RETRIEVAL_INSPECTION_ENABLED=true
      - RETRIEVAL_PROMPT_ENABLED=true
      - BLUEPRINT_HOMOLOGATION_ENABLED=true
      - AGENT_TOKEN_FILE=/run/secrets/$agent_secret
      - AGENT_URL=http://${SETUPMNO_CONTROL_AGENT_SERVICE}:9090
EOF
    if external_provider "$provider"; then
        cat >>"$assistant_yaml" <<EOF
      - LLM_API_KEY_FILE=/run/secrets/llm_api_key
EOF
    fi
    cat >>"$assistant_yaml" <<EOF
    networks:
      - interna
    secrets:
      - $agent_secret
EOF
    if external_provider "$provider"; then
        cat >>"$assistant_yaml" <<EOF
      - source: $provider_secret
        target: llm_api_key
EOF
    fi
    cat >>"$assistant_yaml" <<EOF
    healthcheck:
      test: [CMD, /setupmno-control, healthcheck]
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 15s
    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints: [node.role == manager]
      update_config:
        order: start-first
        failure_action: rollback
      rollback_config:
        order: stop-first
      resources:
        limits:
          cpus: "0.50"
          memory: 256M
networks:
  interna:
    external: true
secrets:
  $agent_secret:
    external: true
EOF
    if external_provider "$provider"; then
        cat >>"$assistant_yaml" <<EOF
  $provider_secret:
    external: true
EOF
    fi
    chmod 0600 "$assistant_yaml"
    docker stack config -c "$assistant_yaml" >/dev/null 2>>"$operation_log" || return 1
    resolve_stack_manager || return 1
    if [ "$assistant_deploy_backend" = "portainer" ]; then
        deploy_assistant_through_portainer
    else
        docker stack deploy --prune --resolve-image never \
            -c "$assistant_yaml" "$assistant_stack" >>"$operation_log" 2>&1
    fi
}

configure_provider() {
    local provider status model base_url provider_secret="" old_secret="" control_plan
    local previous_exists="false" default_model provider_name timestamp height width menu_rows
    control_plan=$(read_control_plan || printf 'free')
    if [ "$control_plan" != "pro" ]; then
        msg "O Assistente com IA é exclusivo do plano PRO.\n\nO plano $control_plan mantém o diagnóstico básico local, sem LLM, sem consumo de API e sem criação de stack de Assistente. Uma configuração antiga de provedor não será utilizada."
        return 0
    fi

    authenticate_admin || return $?

    height=$(dialog_height 21)
    width=$(dialog_width 88)
    menu_rows=$((height - 9))
    [ "$menu_rows" -ge 1 ] || menu_rows=1
    [ "$menu_rows" -le 7 ] || menu_rows=7
    provider=$(whiptail --title "$title" --default-item "OPENAI" --menu \
        "Escolha o provedor do Assistente MNO.\n\nOpenAI permanece como padrão. Chaves são armazenadas somente como Docker Secrets." \
        "$height" "$width" "$menu_rows" \
        "OPENAI" "Responses API oficial (padrão)" \
        "OPENROUTER" "Catálogo multi-modelo pela API compatível" \
        "DEEPSEEK" "Modelos oficiais DeepSeek" \
        "OLLAMA" "Endpoint Ollama já existente" \
        "BASIC" "Diagnóstico local sem LLM" \
        3>&1 1>&2 2>&3)
    status=$?
    [ "$status" -ne 0 ] && return 0
    provider=$(printf '%s' "$provider" | tr '[:upper:]' '[:lower:]')

    if [ "$provider" = "basic" ]; then
        height=$(dialog_height 15)
        width=$(dialog_width 84)
        whiptail --title "$title" --yesno \
            "Ativar somente o diagnóstico básico?\n\nA stack isolada do Assistente será removida após o painel confirmar a nova configuração.\n\nA aplicação precisará ser reiniciada. O site e o Instalador Seguro poderão ficar inacessíveis por cerca de 2 minutos." \
            "$height" "$width" || return 0
        if ! update_web_assistant "basic" "" ""; then
            rollback_service "$web_service"
            fail "O painel não aceitou o modo básico. A configuração anterior foi restaurada."
            return
        fi
        if ! remove_assistant_stack; then
            rollback_service "$web_service"
            fail "O Portainer não confirmou a remoção da stack do Assistente. A configuração anterior foi restaurada."
            return
        fi
        msg "Diagnóstico básico ativado.\n\nNenhuma chave de LLM permanece anexada ao Assistente.\n\nA aplicação foi reiniciada. O site e o Instalador Seguro poderão ficar inacessíveis por cerca de 2 minutos. Aguarde esse período antes de acessar novamente."
        return
    fi

    case "$provider" in
        openai)
            base_url="https://api.openai.com/v1"
            default_model="gpt-5.6-terra"
            ;;
        openrouter)
            base_url="https://openrouter.ai/api/v1"
            default_model="openai/gpt-5.4"
            ;;
        deepseek)
            base_url="https://api.deepseek.com"
            default_model="deepseek-v4-flash"
            ;;
        ollama)
            total_memory=$(docker info --format '{{.MemTotal}}' 2>/dev/null || printf '0')
            if [ "${total_memory:-0}" -lt $((8 * 1024 * 1024 * 1024)) ]; then
                fail "Ollama exige no mínimo 8 GB de RAM total no servidor."
                return
            fi
            if ! base_url=$(ask_required \
                "Endpoint Ollama existente (HTTP ou HTTPS):" \
                "http://ollama:11434"); then
                return 0
            fi
            base_url="${base_url%/}"
            [[ "$base_url" =~ ^https?://[^[:space:]]+$ ]] || {
                fail "Endpoint Ollama inválido."
                return
            }
            default_model="qwen3:8b"
            ;;
        *)
            fail "Provedor inválido."
            return
            ;;
    esac

    if ! model=$(ask_required \
        "Modelo exato do provedor $(provider_label "$provider"):" \
        "$default_model"); then
        return 0
    fi
    [[ "$model" =~ ^[A-Za-z0-9._:/+-]{2,160}$ ]] || {
        fail "Identificador de modelo inválido."
        return
    }

    if external_provider "$provider"; then
        if ! llm_api_key=$(ask_secret \
            "Chave da API $(provider_label "$provider"):\n\nEla será enviada diretamente ao Docker Secret e nunca será exibida ou registrada."); then
            return 0
        fi
    fi

    provider_name=$(provider_label "$provider")
    height=$(dialog_height 17)
    width=$(dialog_width 88)
    whiptail --title "$title" --yesno \
        "Aplicar o provedor $provider_name com o modelo:\n\n$model\n\nA nova stack será validada antes de substituir a configuração ativa.\n\nA aplicação precisará ser reiniciada. O site e o Instalador Seguro poderão ficar inacessíveis por cerca de 2 minutos." \
        "$height" "$width" || return 0

    if docker service inspect "$assistant_service" >/dev/null 2>&1; then
        previous_exists="true"
        old_secret=$(docker service inspect "$assistant_service" |
            jq -r '.[0].Spec.TaskTemplate.ContainerSpec.Secrets[]?
                | select(.File.Name == "llm_api_key") | .SecretName' |
            head -n1)
    fi

    if external_provider "$provider"; then
        timestamp=$(date +%Y%m%d%H%M%S)
        provider_secret="${SETUPMNO_CONTROL_PREFIX}-llm-${provider}-${timestamp}"
        if ! printf '%s' "$llm_api_key" |
            docker secret create "$provider_secret" - >>"$operation_log" 2>&1; then
            unset llm_api_key
            fail "Não foi possível proteger a chave em um Docker Secret."
            return
        fi
        unset llm_api_key
    fi

    if ! deploy_assistant "$provider" "$model" "$base_url" "$provider_secret" ||
       ! wait_service "$assistant_service" ||
       ! curl -fsS --max-time 10 "http://${assistant_service}:7070/health" \
            >/dev/null 2>>"$operation_log"; then
        rollback_assistant_deploy "$previous_exists"
        [ -z "$provider_secret" ] ||
            docker secret rm "$provider_secret" >>"$operation_log" 2>&1 || true
        fail "O provedor ou modelo não passou pela validação. A configuração anterior foi preservada."
        return
    fi

    if ! update_web_assistant "$provider" "$model" \
        "http://${assistant_service}:7070"; then
        rollback_service "$web_service"
        rollback_assistant_deploy "$previous_exists"
        [ -z "$provider_secret" ] ||
            docker secret rm "$provider_secret" >>"$operation_log" 2>&1 || true
        fail "O painel não confirmou o novo provedor. A configuração anterior foi restaurada."
        return
    fi

    if [ -n "$old_secret" ] && [ "$old_secret" != "$provider_secret" ]; then
        docker secret rm "$old_secret" >>"$operation_log" 2>&1 || true
    fi
    msg "Provedor atualizado com sucesso.\n\nProvedor: $provider_name\nModelo: $model\n\nA aplicação foi reiniciada e solicitará novo login. O site e o Instalador Seguro poderão ficar inacessíveis por cerca de 2 minutos. Aguarde esse período antes de acessar novamente."
}

while true; do
    menu_height=$(dialog_height 20)
    menu_width=$(dialog_width 88)
    menu_rows=$((menu_height - 9))
    [ "$menu_rows" -ge 1 ] || menu_rows=1
    [ "$menu_rows" -le 4 ] || menu_rows=4
    if [ "$terminal_mode" = "gateway" ]; then
        exit_code="BACK"
        exit_label="Voltar ao menu do Terminal Seguro"
    else
        exit_code="EXIT"
        exit_label="Encerrar as configurações seguras"
    fi
    choice=$(whiptail --title "$title" --menu \
        "As alterações são executadas somente neste terminal autenticado, com confirmação humana e rollback em caso de falha." \
        "$menu_height" "$menu_width" "$menu_rows" \
        "USERNAME" "Alterar nome do usuário administrador" \
        "PASSWORD" "Alterar senha administrativa" \
        "PROVIDER" "Alterar provedor e modelo do Assistente MNO" \
        "$exit_code" "$exit_label" \
        3>&1 1>&2 2>&3)
    status=$?
    [ "$status" -ne 0 ] && exit 0
    case "$choice" in
        USERNAME) configure_username ;;
        PASSWORD) configure_password ;;
        PROVIDER) configure_provider ;;
        BACK|EXIT) exit 0 ;;
    esac
done

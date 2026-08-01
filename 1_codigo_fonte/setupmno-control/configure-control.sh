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

cleanup() {
    unset current_password expected_password new_password password_confirmation llm_api_key
    rm -rf "$work_dir"
}
trap cleanup EXIT

msg() {
    whiptail --title "$title" --msgbox "$1" 16 84 1>&2
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
        msg "Esta instalação não possui os metadados seguros necessários para reconfiguração.\n\nReinstale ou atualize o Control Center pela versão 7.2.0."
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
    local prompt="$1" default_value="${2:-}" value status
    while true; do
        value=$(whiptail --title "$title" --inputbox "$prompt" 14 84 "$default_value" \
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
    local prompt="$1" value status
    while true; do
        value=$(whiptail --title "$title" --passwordbox "$prompt" 14 84 \
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
    local entered status
    entered=$(whiptail --title "$title" --passwordbox \
        "Confirme a senha administrativa atual.\n\nEla será comparada localmente com o Docker Secret e não será registrada." \
        14 84 3>&1 1>&2 2>&3)
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

update_web_assistant() {
    local provider="$1" model="$2" assistant_url="$3"
    docker service update --detach=true \
        --env-rm ASSISTANT_MODE --env-add "ASSISTANT_MODE=$provider" \
        --env-rm ASSISTANT_MODEL --env-add "ASSISTANT_MODEL=$model" \
        --env-rm ASSISTANT_URL --env-add "ASSISTANT_URL=$assistant_url" \
        "$web_service" >>"$operation_log" 2>&1 &&
        wait_service "$web_service"
}

configure_username() {
    local new_username
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
    whiptail --title "$title" --yesno \
        "Alterar o usuário de '$admin_username' para '$new_username'?\n\nTodas as sessões serão encerradas e você precisará entrar novamente." \
        15 84 || return 0

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
    local new_secret timestamp
    authenticate_admin || return $?
    while true; do
        new_password=$(whiptail --title "$title" --passwordbox \
            "Nova senha administrativa:\n\nMínimo de 12 caracteres, com maiúscula, minúscula, número e símbolo." \
            14 84 3>&1 1>&2 2>&3) || return 0
        validate_new_password "$new_password" || continue
        password_confirmation=$(whiptail --title "$title" --passwordbox \
            "Confirme a nova senha administrativa:" 12 84 \
            3>&1 1>&2 2>&3) || return 0
        [ "$new_password" = "$password_confirmation" ] || {
            msg "As senhas não coincidem."
            continue
        }
        break
    done
    whiptail --title "$title" --yesno \
        "Alterar a senha administrativa?\n\nTodas as sessões serão encerradas. O secret anterior será mantido até o novo serviço ficar saudável." \
        15 84 || return 0

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
    docker stack config -c "$assistant_yaml" >/dev/null 2>>"$operation_log" &&
        docker stack deploy --prune --resolve-image never \
            -c "$assistant_yaml" "$assistant_stack" >>"$operation_log" 2>&1
}

configure_provider() {
    local provider status model base_url provider_secret="" old_secret=""
    local previous_exists="false" default_model provider_name timestamp
    authenticate_admin || return $?

    provider=$(whiptail --title "$title" --default-item "OPENAI" --menu \
        "Escolha o provedor do Assistente MNO.\n\nOpenAI permanece como padrão. Chaves são armazenadas somente como Docker Secrets." \
        21 88 7 \
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
        whiptail --title "$title" --yesno \
            "Ativar somente o diagnóstico básico?\n\nA stack isolada do Assistente será removida após o painel confirmar a nova configuração." \
            15 84 || return 0
        if ! update_web_assistant "basic" "" ""; then
            rollback_service "$web_service"
            fail "O painel não aceitou o modo básico. A configuração anterior foi restaurada."
            return
        fi
        docker stack rm "$assistant_stack" >>"$operation_log" 2>&1 || true
        msg "Diagnóstico básico ativado.\n\nNenhuma chave de LLM permanece anexada ao Assistente."
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
    whiptail --title "$title" --yesno \
        "Aplicar o provedor $provider_name com o modelo:\n\n$model\n\nA nova stack será validada antes de substituir a configuração ativa." \
        17 88 || return 0

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
        if [ "$previous_exists" = "true" ]; then
            rollback_service "$assistant_service"
        else
            docker stack rm "$assistant_stack" >>"$operation_log" 2>&1 || true
        fi
        [ -z "$provider_secret" ] ||
            docker secret rm "$provider_secret" >>"$operation_log" 2>&1 || true
        fail "O provedor ou modelo não passou pela validação. A configuração anterior foi preservada."
        return
    fi

    if ! update_web_assistant "$provider" "$model" \
        "http://${assistant_service}:7070"; then
        rollback_service "$web_service"
        if [ "$previous_exists" = "true" ]; then
            rollback_service "$assistant_service"
        else
            docker stack rm "$assistant_stack" >>"$operation_log" 2>&1 || true
        fi
        [ -z "$provider_secret" ] ||
            docker secret rm "$provider_secret" >>"$operation_log" 2>&1 || true
        fail "O painel não confirmou o novo provedor. A configuração anterior foi restaurada."
        return
    fi

    if [ -n "$old_secret" ] && [ "$old_secret" != "$provider_secret" ]; then
        docker secret rm "$old_secret" >>"$operation_log" 2>&1 || true
    fi
    msg "Provedor atualizado com sucesso.\n\nProvedor: $provider_name\nModelo: $model\n\nO painel será reiniciado e solicitará novo login."
}

while true; do
    choice=$(whiptail --title "$title" --menu \
        "As alterações são executadas somente neste terminal autenticado, com confirmação humana e rollback em caso de falha." \
        20 88 6 \
        "USERNAME" "Alterar nome do usuário administrador" \
        "PASSWORD" "Alterar senha administrativa" \
        "PROVIDER" "Alterar provedor e modelo do Assistente MNO" \
        "BACK" "Voltar ao menu do Terminal Seguro" \
        3>&1 1>&2 2>&3)
    status=$?
    [ "$status" -ne 0 ] && exit 0
    case "$choice" in
        USERNAME) configure_username ;;
        PASSWORD) configure_password ;;
        PROVIDER) configure_provider ;;
        BACK) exit 0 ;;
    esac
done

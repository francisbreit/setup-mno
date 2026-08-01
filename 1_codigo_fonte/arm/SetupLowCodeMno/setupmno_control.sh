#!/usr/bin/bash
# SETUP MNO CONTROL CENTER — painel web oficial de deploys e monitoramento.
set -o pipefail
umask 077

CONTROL_VERSION="4.2.0"
CLOUDFLARE_CONNECT_TIMEOUT=10
CLOUDFLARE_MAX_TIME=30

if [ "${SETUPMNO_SHC_SMOKE_TEST:-0}" = "1" ]; then
    printf '%s\n' "setupmno-control-shc-ok"
    exit 0
fi

extract_control_bundle() {
    local archive="/root/SetupLowCodeMno/.control/control-source.tar.gz"
    local release="/root/SetupLowCodeMno/.control/release.json"
    local expected_sha expected_bytes actual_sha actual_bytes
    [ -f "$archive" ] && [ ! -L "$archive" ] && [ -f "$release" ] &&
    [ ! -L "$release" ] || return 1
    expected_sha=$(jq -r '.controlSourceSHA256 // empty' "$release")
    expected_bytes=$(jq -r '.controlSourceBytes // 0' "$release")
    actual_sha=$(sha256sum "$archive" | awk '{print $1}')
    actual_bytes=$(stat -c '%s' "$archive")
    [ -n "$expected_sha" ] && [ "$expected_sha" = "$actual_sha" ] &&
    [ "$expected_bytes" = "$actual_bytes" ] &&
    [ "$actual_bytes" -le $((2 * 1024 * 1024)) ] || return 1
    cat "$archive"
}

INSTALL_TYPE_FILE="/root/.cloudflared_config/installation_type"
INSTALL_TYPE="TRADICIONAL"
[ -f "$INSTALL_TYPE_FILE" ] && INSTALL_TYPE=$(cat "$INSTALL_TYPE_FILE")

if [ "$INSTALL_TYPE" = "CLOUDFLARE_TUNNEL" ]; then
    CREDENTIALS_FILE="/root/.cloudflared_config/cloudflare_credentials"
else
    CREDENTIALS_FILE="/root/.tradicional_config/tradicional_credentials"
fi
[ -f "$CREDENTIALS_FILE" ] && source "$CREDENTIALS_FILE"
criar_dns="${criar_dns:-0}"

msg() {
    # As funções de coleta são chamadas por substituição de comando. Direcionar
    # a interface para stderr mantém o Whiptail visível no terminal/ttyd.
    whiptail --title "SETUP MNO CONTROL CENTER" --msgbox "$1" 14 78 1>&2
}

ask_required() {
    local prompt="$1" value status
    while true; do
        value=$(whiptail --title "SETUP MNO CONTROL CENTER" --inputbox "$prompt" 12 78 3>&1 1>&2 2>&3)
        status=$?
        [ "$status" -ne 0 ] && return 130
        [ -n "$value" ] && {
            printf '%s' "$value"
            return
        }
        msg "Este campo é obrigatório."
    done
}

ask_with_default() {
    local prompt="$1" default_value="$2" value status
    while true; do
        value=$(whiptail --title "SETUP MNO CONTROL CENTER" --inputbox \
            "$prompt" 13 82 "$default_value" 3>&1 1>&2 2>&3)
        status=$?
        [ "$status" -ne 0 ] && return 130
        [ -n "$value" ] && {
            printf '%s' "$value"
            return
        }
        msg "Este campo é obrigatório."
    done
}

ask_llm_key() {
    local provider_name="$1" value status
    while true; do
        value=$(whiptail --title "SETUP MNO CONTROL CENTER" --passwordbox \
            "Informe a chave da API $provider_name.\n\nEla será armazenada exclusivamente como Docker Secret e nunca será exibida em logs." \
            14 82 3>&1 1>&2 2>&3)
        status=$?
        [ "$status" -ne 0 ] && return 130
        if [ "${#value}" -ge 20 ] && [[ "$value" != *[[:space:]]* ]]; then
            printf '%s' "$value"
            return
        fi
        msg "A chave informada é inválida. Verifique e tente novamente."
    done
}

ask_password() {
    local value confirmation status
    while true; do
        value=$(whiptail --title "SETUP MNO CONTROL CENTER" --passwordbox \
            "3/5 — Crie a senha administrativa:\n\nMínimo de 12 caracteres, com maiúscula, minúscula, número e símbolo." \
            14 78 3>&1 1>&2 2>&3)
        status=$?
        [ "$status" -ne 0 ] && return 130
        if [ "${#value}" -lt 12 ]; then
            msg "Senha inválida: use pelo menos 12 caracteres."
            continue
        fi
        if [[ ! "$value" =~ [[:upper:]] ]]; then
            msg "Senha inválida: inclua pelo menos uma letra maiúscula."
            continue
        fi
        if [[ ! "$value" =~ [[:lower:]] ]]; then
            msg "Senha inválida: inclua pelo menos uma letra minúscula."
            continue
        fi
        if [[ ! "$value" =~ [[:digit:]] ]]; then
            msg "Senha inválida: inclua pelo menos um número."
            continue
        fi
        if [[ "$value" =~ [[:space:]] ]]; then
            msg "Senha inválida: não use espaços."
            continue
        fi
        if [[ ! "$value" =~ [^[:alnum:][:space:]] ]]; then
            msg "Senha inválida: inclua pelo menos um símbolo, como !, @, # ou %."
            continue
        fi
        confirmation=$(whiptail --title "SETUP MNO CONTROL CENTER" --passwordbox \
            "Confirme a senha administrativa:" 11 78 3>&1 1>&2 2>&3)
        status=$?
        [ "$status" -ne 0 ] && return 130
        [ "$value" = "$confirmation" ] && {
            printf '%s' "$value"
            return
        }
        msg "As senhas não coincidem."
    done
}

check_cloudflare_route() {
    local output_file="$1" status_file error_file curl_status
    status_file=$(mktemp) || {
        msg "Não foi possível preparar a verificação segura do Cloudflare Tunnel."
        return 1
    }
    error_file=$(mktemp) || {
        rm -f "$status_file"
        msg "Não foi possível preparar a verificação segura do Cloudflare Tunnel."
        return 1
    }

    {
        echo -e "XXX\n10\nCONECTANDO À API DO CLOUDFLARE...\nXXX"
        if curl -sS \
            --connect-timeout "$CLOUDFLARE_CONNECT_TIMEOUT" \
            --max-time "$CLOUDFLARE_MAX_TIME" \
            -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
            "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/cfd_tunnel/$TUNNEL_ID/configurations" \
            >"$output_file" 2>"$error_file"; then
            printf '0\n' >"$status_file"
        else
            printf '%s\n' "$?" >"$status_file"
        fi
        echo -e "XXX\n100\nVERIFICAÇÃO DO CLOUDFLARE CONCLUÍDA\nXXX"
    } | whiptail --title "SETUP MNO CONTROL CENTER" --gauge \
        "Verificando o domínio informado..." 8 78 0

    curl_status=$(cat "$status_file" 2>/dev/null)
    rm -f "$status_file" "$error_file"
    case "$curl_status" in
        0) ;;
        6)
            msg "Não foi possível resolver api.cloudflare.com. Verifique o DNS e a conexão do servidor."
            return 1
            ;;
        7)
            msg "Não foi possível conectar à API do Cloudflare. Verifique a conexão do servidor."
            return 1
            ;;
        28)
            msg "A API do Cloudflare não respondeu em até ${CLOUDFLARE_MAX_TIME} segundos. Nenhum recurso foi alterado. Tente novamente quando a conexão estiver estável."
            return 1
            ;;
        *)
            msg "Não foi possível consultar o Cloudflare Tunnel. Nenhum recurso foi alterado. Verifique a conexão e tente novamente."
            return 1
            ;;
    esac

    if ! jq -e '.success == true and (.result.config.ingress | type == "array")' \
        "$output_file" >/dev/null 2>&1; then
        msg "A Cloudflare recusou a consulta ou retornou uma resposta inválida. Verifique as credenciais do Tunnel. Nenhum recurso foi alterado."
        return 1
    fi
}

whiptail --title "SETUP MNO CONTROL CENTER" --yesno \
    "Instalar o painel web oficial do Setup MNO?\n\nO Control Center mostra aplicações instaladas, saúde do Docker Swarm, CPU, RAM, disco, catálogo de setups, auditoria, diagnóstico local e acesso autenticado ao instalador original." \
    16 82 || exit 0

while true; do
    if ! url_control=$(ask_required "1/5 — Domínio do painel (ex.: setup.seudominio.com):"); then
        exit 0
    fi
    if [[ "$url_control" =~ ^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$ ]] &&
       [[ "$url_control" == *.* ]]; then
        break
    fi
    msg "Informe somente o domínio, sem http://, https://, barras ou caminhos."
done

if [ "$INSTALL_TYPE" = "CLOUDFLARE_TUNNEL" ]; then
    route_check=$(mktemp) || {
        msg "Não foi possível preparar a verificação segura do Cloudflare Tunnel."
        exit 1
    }
    if ! check_cloudflare_route "$route_check"; then
        rm -f "$route_check"
        exit 1
    fi
    existing_service=$(jq -r --arg host "$url_control" \
        '.result.config.ingress[]? | select(.hostname == $host) | .service' "$route_check" 2>/dev/null | head -n1)
    rm -f "$route_check"
    if [ -n "$existing_service" ] && [ "$existing_service" != "null" ]; then
        msg "Já existe uma rota para:\n\n$url_control\n\nServiço atual: $existing_service\n\nA rota será substituída pela nova instalação."
    fi
fi

while true; do
    if ! usuario_control=$(ask_required "2/5 — Usuário administrador do painel:"); then
        exit 0
    fi
    if [[ "$usuario_control" =~ ^[A-Za-z0-9_.-]{3,40}$ ]]; then
        break
    fi
    msg "Use de 3 a 40 caracteres: letras, números, ponto, hífen ou sublinhado."
done

if ! senha_control=$(ask_password); then
    exit 0
fi

mem_total_mb=$(awk '/MemTotal:/ {print int($2/1024)}' /proc/meminfo)
mem_available_mb=$(awk '/MemAvailable:/ {print int($2/1024)}' /proc/meminfo)
assistant_mode="basic"
assistant_model=""
assistant_base_url=""
llm_api_key=""

if [ "${mem_total_mb:-0}" -lt 4096 ] || [ "${mem_available_mb:-0}" -lt 1536 ]; then
    msg "O Control Center será instalado com o diagnóstico básico.\n\nMemória total: ${mem_total_mb:-0} MB\nMemória disponível: ${mem_available_mb:-0} MB\n\nO Copiloto com LLM é opcional e foi desativado para proteger este servidor. Você poderá configurá-lo futuramente após ampliar os recursos."
else
    while true; do
        assistant_choice=$(whiptail --title "4/5 — ASSISTENTE MNO" --default-item "OPENAI" --menu \
            "Escolha como o Copiloto de Infraestrutura funcionará.\n\nOpenAI é a seleção inicial. Todo conector usa uma stack isolada de 256 MB, sem acesso ao Docker ou terminal." \
            23 92 7 \
            "OPENAI" "LLM externa pela Responses API (padrão inicial)" \
            "OPENROUTER" "Catálogo multi-modelo pela API compatível" \
            "DEEPSEEK" "Modelos oficiais DeepSeek" \
            "OLLAMA" "Modelo existente em um endpoint Ollama" \
            "BASIC" "Diagnóstico local sem LLM" \
            "LATER" "Configurar o conector de IA futuramente" \
            3>&1 1>&2 2>&3)
        assistant_status=$?
        [ "$assistant_status" -ne 0 ] && exit 0
        case "$assistant_choice" in
            BASIC|LATER)
                assistant_mode="basic"
                break
                ;;
            OPENAI)
                if ! llm_api_key=$(ask_llm_key "OpenAI"); then
                    exit 0
                fi
                if ! assistant_model=$(ask_with_default \
                    "Modelo OpenAI para o Copiloto:\n\nO padrão equilibra qualidade, latência e custo. Você pode informar outro modelo compatível com a Responses API." \
                    "gpt-5.6-terra"); then
                    exit 0
                fi
                assistant_mode="openai"
                assistant_base_url="https://api.openai.com/v1"
                break
                ;;
            OPENROUTER)
                if ! llm_api_key=$(ask_llm_key "OpenRouter"); then
                    exit 0
                fi
                if ! assistant_model=$(ask_with_default \
                    "Modelo OpenRouter para o Copiloto:\n\nInforme o identificador exato no formato provedor/modelo." \
                    "openai/gpt-5.4"); then
                    exit 0
                fi
                assistant_mode="openrouter"
                assistant_base_url="https://openrouter.ai/api/v1"
                break
                ;;
            DEEPSEEK)
                if ! llm_api_key=$(ask_llm_key "DeepSeek"); then
                    exit 0
                fi
                if ! assistant_model=$(ask_with_default \
                    "Modelo DeepSeek para o Copiloto:\n\nVocê pode informar outro identificador aceito atualmente pelo provedor." \
                    "deepseek-v4-flash"); then
                    exit 0
                fi
                assistant_mode="deepseek"
                assistant_base_url="https://api.deepseek.com"
                break
                ;;
            OLLAMA)
                if [ "${mem_total_mb:-0}" -lt 8192 ] || [ "${mem_available_mb:-0}" -lt 4096 ]; then
                    msg "O modo Ollama local exige pelo menos 8 GB de RAM total e 4 GB disponíveis.\n\nUse OpenAI, mantenha o diagnóstico básico ou amplie o servidor. Esta proteção evita degradação dos setups já instalados."
                    continue
                fi
                if ! assistant_base_url=$(ask_required \
                    "Endpoint do Ollama já instalado (ex.: https://apiollama.seudominio.com):"); then
                    exit 0
                fi
                assistant_base_url="${assistant_base_url%/}"
                if [[ ! "$assistant_base_url" =~ ^https?://[^[:space:]]+$ ]]; then
                    msg "Informe uma URL HTTP ou HTTPS válida para o endpoint Ollama."
                    continue
                fi
                if ! assistant_model=$(ask_required \
                    "Nome exato do modelo já baixado no Ollama (ex.: qwen3:8b):"); then
                    exit 0
                fi
                assistant_mode="ollama"
                break
                ;;
        esac
    done
fi

while true; do
    if ! criar_portainer=$(ask_required \
        "5/5 — Criar Stack no Portainer?\n\n0 = editável no Portainer\n1 = direto no Docker"); then
        exit 0
    fi
    [[ "$criar_portainer" =~ ^[01]$ ]] && break
    msg "Digite somente 0 ou 1."
done

nome_principal="mnoctrl"
sufixo_app=$(date +%s%N | md5sum | head -c7)
nome_app="${nome_principal}${sufixo_app}"
web_stack="${nome_app}-web"
agent_stack="${nome_app}-agent"
terminal_stack="${nome_app}-terminal"
assistant_stack="${nome_app}-assistant"
web_service="${nome_app}-web"
agent_service="${nome_app}-agent"
terminal_service="${nome_app}-terminal"
assistant_service="${nome_app}-assistant"
control_image="${nome_app}-app:${CONTROL_VERSION}"
terminal_image="${nome_app}-terminal:${CONTROL_VERSION}"
admin_secret="${nome_app}-admin-password"
agent_secret="${nome_app}-agent-token"
llm_secret="${nome_app}-llm-api-key"

assistant_label="Diagnóstico básico (sem LLM)"
memory_limit="576 MB"
assistant_internal_url=""
assistant_external="false"
if [ "$assistant_mode" = "openai" ] ||
   [ "$assistant_mode" = "openrouter" ] ||
   [ "$assistant_mode" = "deepseek" ]; then
    case "$assistant_mode" in
        openai) assistant_provider_label="OpenAI" ;;
        openrouter) assistant_provider_label="OpenRouter" ;;
        deepseek) assistant_provider_label="DeepSeek" ;;
    esac
    assistant_label="$assistant_provider_label · $assistant_model"
    memory_limit="832 MB"
    assistant_internal_url="http://${assistant_stack}_${assistant_service}:7070"
    assistant_external="true"
elif [ "$assistant_mode" = "ollama" ]; then
    assistant_label="Ollama · $assistant_model"
    memory_limit="832 MB + consumo do modelo Ollama"
    assistant_internal_url="http://${assistant_stack}_${assistant_service}:7070"
fi

dns_mode="Cloudflare Tunnel"
if [ "$INSTALL_TYPE" = "TRADICIONAL" ]; then
    if [ "$criar_dns" = "0" ]; then
        dns_mode="Tradicional com DNS automático"
    else
        dns_mode="Tradicional com DNS manual"
    fi
fi

whiptail --title "CONFIRMAR INSTALAÇÃO" --yesno \
    "Setup MNO Control Center\n\nDomínio: $url_control\nAdministrador: $usuario_control\nAssistente: $assistant_label\nInstalação: $dns_mode\nDeploy: $([ "$criar_portainer" = "0" ] && echo "Portainer editável" || echo "Docker direto")\nArquiteturas: X86 e ARM\nLimite de memória do Control: $memory_limit\n\nO terminal executará o instalador original e será acessível somente após autenticação." \
    23 88 || exit 0

install_log="/tmp/${nome_app}-install.log"
error_file="/tmp/${nome_app}-error.log"
: >"$install_log"
: >"$error_file"

{
    work_dir=$(mktemp -d)
    trap 'rm -rf "$work_dir"' EXIT

    fail_install() {
        local code="$1" progress="$2" message="$3"
        printf '%s\n' "$message" >"$error_file"
        echo -e "XXX\n100\n$progress\nXXX"
        exit "$code"
    }

    echo -e "XXX\n4\nVALIDANDO AMBIENTE... \nXXX"
    for required_command in docker curl jq tar openssl; do
        command -v "$required_command" >/dev/null 2>&1 ||
            fail_install 10 "DEPENDÊNCIA NÃO ENCONTRADA" "O comando obrigatório '$required_command' não está instalado."
    done
    docker info >>"$install_log" 2>&1 ||
        fail_install 11 "DOCKER INDISPONÍVEL" "O Docker Engine ou o Swarm não está disponível."
    swarm_state=$(docker info --format '{{.Swarm.LocalNodeState}}' 2>>"$install_log")
    [ "$swarm_state" = "active" ] ||
        fail_install 11 "SWARM INATIVO" "O Docker Swarm precisa estar ativo antes de instalar o Control Center."
    docker network inspect interna >>"$install_log" 2>&1 ||
        fail_install 12 "REDE INTERNA INDISPONÍVEL" "A rede overlay 'interna' não foi encontrada."
    docker network inspect externa >>"$install_log" 2>&1 ||
        fail_install 13 "REDE EXTERNA INDISPONÍVEL" "A rede overlay 'externa' não foi encontrada."
    [ -x /root/SetupLowCodeMno/install ] ||
        fail_install 14 "INSTALADOR NÃO ENCONTRADO" "O executável /root/SetupLowCodeMno/install não foi encontrado."
    [ -s /root/SetupLowCodeMno/.control/release.json ] &&
    [ -s /root/SetupLowCodeMno/.control/catalog.json ] ||
        fail_install 14 "ESTADO DO SETUP NÃO ENCONTRADO" "Atualize o Setup MNO antes de instalar o Control Center. O manifesto ou catálogo runtime não foi encontrado."
    runtime_catalog_sha=$(sha256sum /root/SetupLowCodeMno/.control/catalog.json | awk '{print $1}')
    expected_catalog_sha=$(jq -r '.catalogSHA256 // empty' /root/SetupLowCodeMno/.control/release.json 2>>"$install_log")
    [ -n "$expected_catalog_sha" ] && [ "$runtime_catalog_sha" = "$expected_catalog_sha" ] ||
        fail_install 14 "CATÁLOGO DO SETUP INVÁLIDO" "O catálogo runtime não corresponde ao manifesto da versão instalada."
    [ -f "$CREDENTIALS_FILE" ] ||
        fail_install 15 "CREDENCIAIS NÃO ENCONTRADAS" "Arquivo de credenciais não encontrado: $CREDENTIALS_FILE"

    if [ "$INSTALL_TYPE" = "CLOUDFLARE_TUNNEL" ] ||
       { [ "$INSTALL_TYPE" = "TRADICIONAL" ] && [ "$criar_dns" = "0" ]; }; then
        if [ -z "$CLOUDFLARE_API_TOKEN" ] || [ -z "$CLOUDFLARE_ZONE_ID" ]; then
            fail_install 16 "CREDENCIAIS CLOUDFLARE INVÁLIDAS" "Token ou Zone ID do Cloudflare não encontrado."
        fi
    fi
    if [ "$INSTALL_TYPE" = "CLOUDFLARE_TUNNEL" ] &&
       { [ -z "$CLOUDFLARE_ACCOUNT_ID" ] || [ -z "$TUNNEL_ID" ]; }; then
        fail_install 17 "DADOS DO TUNNEL INVÁLIDOS" "Account ID ou Tunnel ID não encontrado."
    fi

    echo -e "XXX\n10\nEXTRAINDO O CONTROL CENTER... \nXXX"
    mkdir -p "$work_dir/source"
    if ! extract_control_bundle 2>>"$install_log" |
        tar -xzf - -C "$work_dir/source" >>"$install_log" 2>&1; then
        fail_install 20 "BUNDLE DO PAINEL INVÁLIDO" "Não foi possível validar e extrair os fontes internos do Control Center."
    fi
    runtime_catalog="/root/SetupLowCodeMno/.control/catalog.json"
    runtime_release="/root/SetupLowCodeMno/.control/release.json"
    [ -f "$runtime_catalog" ] &&
    [ ! -L "$runtime_catalog" ] &&
    [ -f "$runtime_release" ] &&
    [ ! -L "$runtime_release" ] ||
        fail_install 21 "CATÁLOGO RUNTIME AUSENTE" "Atualize o Setup MNO para receber o catálogo validado."
    runtime_catalog_sha=$(sha256sum "$runtime_catalog" | awk '{print $1}')
    expected_catalog_sha=$(jq -r '.catalogSHA256 // empty' "$runtime_release" 2>>"$install_log")
    [ -n "$expected_catalog_sha" ] &&
    [ "$runtime_catalog_sha" = "$expected_catalog_sha" ] ||
        fail_install 21 "CATÁLOGO RUNTIME INVÁLIDO" "O catálogo não corresponde ao manifesto desta release."
    install -m 0644 "$runtime_catalog" "$work_dir/source/catalog.json"
    for source_file in go.mod Dockerfile terminal.Dockerfile prepare-ttyd-index.sh \
        terminal-menu.sh configure-control.sh \
        main.go knowledge.go retrieval.go routing.go prompts.go blueprint_recommendation.go evals.go provider_evals.go feedback.go catalog.json \
        web/index.html web/app.js web/assistant-route.js web/styles.css web/terminal-bridge.js; do
        [ -s "$work_dir/source/$source_file" ] ||
            fail_install 21 "FONTE INCOMPLETO" "O arquivo interno '$source_file' não foi encontrado no bundle."
        [ ! -L "$work_dir/source/$source_file" ] ||
            fail_install 21 "FONTE INSEGURO" "O arquivo interno '$source_file' não pode ser um link simbólico."
    done

    runtime_knowledge_dir="/root/SetupLowCodeMno/.control/knowledge-package"
    [ -f "$runtime_knowledge_dir/manifest.json" ] &&
    [ ! -L "$runtime_knowledge_dir/manifest.json" ] &&
    [ -f "$runtime_knowledge_dir/knowledge-package.tar.gz" ] &&
    [ ! -L "$runtime_knowledge_dir/knowledge-package.tar.gz" ] ||
        fail_install 22 "CONHECIMENTO RUNTIME AUSENTE" "Atualize o Setup MNO para receber o pacote de conhecimento validado."
    runtime_knowledge_sha=$(sha256sum "$runtime_knowledge_dir/knowledge-package.tar.gz" | awk '{print $1}')
    expected_knowledge_sha=$(jq -r '.archiveSHA256 // empty' "$runtime_knowledge_dir/manifest.json" 2>>"$install_log")
    release_knowledge_sha=$(jq -r '.knowledgeArchiveSHA256 // empty' /root/SetupLowCodeMno/.control/release.json 2>>"$install_log")
    knowledge_setup_version=$(jq -r '.setupVersion // empty' "$runtime_knowledge_dir/manifest.json" 2>>"$install_log")
    knowledge_control_version=$(jq -r '.controlVersion // empty' "$runtime_knowledge_dir/manifest.json" 2>>"$install_log")
    knowledge_entries=$(jq -r '.documentEntries // 0' "$runtime_knowledge_dir/manifest.json" 2>>"$install_log")
    knowledge_chunks=$(jq -r '.chunkEntries // 0' "$runtime_knowledge_dir/manifest.json" 2>>"$install_log")
    knowledge_index_schema=$(jq -r '.indexSchemaVersion // 0' "$runtime_knowledge_dir/manifest.json" 2>>"$install_log")
    knowledge_retrieval_version=$(jq -r '.retrievalVersion // empty' "$runtime_knowledge_dir/manifest.json" 2>>"$install_log")
    eval_schema=$(jq -r '.evalSchemaVersion // 0' "$runtime_knowledge_dir/manifest.json" 2>>"$install_log")
    eval_dataset_version=$(jq -r '.evalDatasetVersion // empty' "$runtime_knowledge_dir/manifest.json" 2>>"$install_log")
    eval_grader_version=$(jq -r '.evalGraderVersion // empty' "$runtime_knowledge_dir/manifest.json" 2>>"$install_log")
    eval_dataset_sha=$(jq -r '.evalDatasetSHA256 // empty' "$runtime_knowledge_dir/manifest.json" 2>>"$install_log")
    eval_case_entries=$(jq -r '.evalCaseEntries // 0' "$runtime_knowledge_dir/manifest.json" 2>>"$install_log")
    release_eval_dataset_sha=$(jq -r '.evalDatasetSHA256 // empty' /root/SetupLowCodeMno/.control/release.json 2>>"$install_log")
    release_knowledge_entries=$(jq -r '.knowledgeEntries // 0' /root/SetupLowCodeMno/.control/release.json 2>>"$install_log")
    knowledge_archive_bytes=$(jq -r '.archiveBytes // 0' "$runtime_knowledge_dir/manifest.json" 2>>"$install_log")
    actual_knowledge_bytes=$(stat -c '%s' "$runtime_knowledge_dir/knowledge-package.tar.gz")
    [ -n "$expected_knowledge_sha" ] &&
    [ "$runtime_knowledge_sha" = "$expected_knowledge_sha" ] &&
    [ "$release_knowledge_sha" = "$expected_knowledge_sha" ] &&
    [ "$knowledge_setup_version" = "$(jq -r '.setupVersion' /root/SetupLowCodeMno/.control/release.json)" ] &&
    [ "$knowledge_control_version" = "$CONTROL_VERSION" ] &&
    [ "$knowledge_entries" -gt 0 ] &&
    [ "$knowledge_chunks" -gt "$knowledge_entries" ] &&
    [ "$knowledge_index_schema" = "2" ] &&
    [ "$knowledge_retrieval_version" = "1.2.0" ] &&
    [ "$eval_schema" = "1" ] &&
    [ "$eval_dataset_version" = "1.0.0" ] &&
    [ "$eval_grader_version" = "1.1.0" ] &&
    [ "${#eval_dataset_sha}" -eq 64 ] &&
    [ "$eval_dataset_sha" = "$release_eval_dataset_sha" ] &&
    [ "$eval_case_entries" = "160" ] &&
    [ "$knowledge_entries" = "$release_knowledge_entries" ] &&
    [ "$knowledge_archive_bytes" = "$actual_knowledge_bytes" ] &&
    [ "$knowledge_archive_bytes" -le $((8 * 1024 * 1024)) ] &&
    tar -tzf "$runtime_knowledge_dir/knowledge-package.tar.gz" >>"$install_log" 2>&1 &&
    tar -tvzf "$runtime_knowledge_dir/knowledge-package.tar.gz" 2>>"$install_log" |
        awk 'substr($1, 1, 1) != "-" { exit 1 }' ||
        fail_install 22 "PACOTE DE CONHECIMENTO INVÁLIDO" "O conhecimento runtime diverge do manifesto desta release."

    build_knowledge_dir="$work_dir/source/knowledge-package"
    mkdir -p "$build_knowledge_dir"
    install -m 0644 "$runtime_knowledge_dir/manifest.json" \
        "$build_knowledge_dir/manifest.json"
    install -m 0644 "$runtime_knowledge_dir/knowledge-package.tar.gz" \
        "$build_knowledge_dir/knowledge-package.tar.gz"

    echo -e "XXX\n20\nCONSTRUINDO O PAINEL WEB... \nXXX"
    if ! docker build --pull -t "$control_image" "$work_dir/source" >>"$install_log" 2>&1; then
        {
            echo "Falha ao construir a imagem do painel."
            echo
            tail -n 20 "$install_log"
        } >"$error_file"
        echo -e "XXX\n100\nERRO NO BUILD DO PAINEL\nXXX"
        exit 30
    fi
    if ! docker image inspect --format \
        'Painel: {{.Id}} | Arquitetura: {{.Architecture}} | Tamanho: {{.Size}} bytes' \
        "$control_image" >>"$install_log" 2>&1; then
        fail_install 31 "IMAGEM DO PAINEL NÃO ENCONTRADA" "O build terminou, mas a imagem do painel não foi confirmada."
    fi
    if ! docker run --rm --entrypoint /setupmno-control \
        "$control_image" knowledgecheck >>"$install_log" 2>&1; then
        fail_install 31 "CONHECIMENTO DA IMAGEM INVÁLIDO" "A imagem não validou o pacote de conhecimento somente leitura."
    fi
    if ! docker run --rm --entrypoint /setupmno-control \
        "$control_image" evalcheck >>"$install_log" 2>&1; then
        fail_install 31 "REGRESSÃO DE QUALIDADE DETECTADA" "A suíte canônica de 160 casos não atingiu os gates mínimos desta release."
    fi
    fallback_check="$work_dir/knowledge-fallback.json"
    if ! docker run --rm \
        -e KNOWLEDGE_PACKAGE_DIR=/pacote-ausente \
        --entrypoint /setupmno-control \
        "$control_image" knowledgecheck >"$fallback_check" 2>>"$install_log" ||
       [ "$(jq -r '.source // empty' "$fallback_check" 2>>"$install_log")" != "embedded-fallback" ] ||
       [ "$(jq -r '.stale // false' "$fallback_check" 2>>"$install_log")" != "true" ]; then
        fail_install 31 "FALLBACK DE CONHECIMENTO INVÁLIDO" "A imagem não confirmou a base embutida de contingência."
    fi

    echo -e "XXX\n38\nCONSTRUINDO O TERMINAL PROTEGIDO... \nXXX"
    if ! docker build --pull -f "$work_dir/source/terminal.Dockerfile" \
        -t "$terminal_image" "$work_dir/source" >>"$install_log" 2>&1; then
        {
            echo "Falha ao construir a imagem do terminal protegido."
            echo
            tail -n 20 "$install_log"
        } >"$error_file"
        echo -e "XXX\n100\nERRO NO BUILD DO TERMINAL\nXXX"
        exit 32
    fi
    if ! docker image inspect --format \
        'Terminal: {{.Id}} | Arquitetura: {{.Architecture}} | Tamanho: {{.Size}} bytes' \
        "$terminal_image" >>"$install_log" 2>&1; then
        fail_install 33 "IMAGEM DO TERMINAL NÃO ENCONTRADA" "O build terminou, mas a imagem do terminal não foi confirmada."
    fi

    echo -e "XXX\n46\nVALIDANDO COMPATIBILIDADE DO INSTALADOR... \nXXX"
    if ! docker run --rm \
        --entrypoint /usr/bin/ldd \
        -v /root:/root:ro \
        -v /usr/bin/bash:/usr/bin/bash:ro \
        "$terminal_image" \
        /root/SetupLowCodeMno/install >>"$install_log" 2>&1; then
        {
            echo "O terminal foi construído, mas sua GLIBC não é compatível com o instalador do Setup MNO."
            echo
            tail -n 16 "$install_log"
        } >"$error_file"
        echo -e "XXX\n100\nTERMINAL INCOMPATÍVEL COM O INSTALADOR\nXXX"
        exit 34
    fi

    echo -e "XXX\n51\nCRIANDO SEGREDOS DO PAINEL... \nXXX"
    if ! printf '%s' "$senha_control" |
        docker secret create "$admin_secret" - >>"$install_log" 2>&1; then
        fail_install 40 "ERRO AO CRIAR SENHA" "Não foi possível criar o segredo da senha administrativa."
    fi
    unset senha_control
    if ! openssl rand -hex 32 |
        docker secret create "$agent_secret" - >>"$install_log" 2>&1; then
        fail_install 41 "ERRO AO CRIAR TOKEN" "Não foi possível criar o token privado do agente."
    fi
    if [ "$assistant_mode" = "openai" ] ||
       [ "$assistant_mode" = "openrouter" ] ||
       [ "$assistant_mode" = "deepseek" ]; then
        if ! printf '%s' "$llm_api_key" |
            docker secret create "$llm_secret" - >>"$install_log" 2>&1; then
            fail_install 42 "ERRO AO PROTEGER CHAVE LLM" "Não foi possível armazenar a chave do provedor como Docker Secret."
        fi
    fi
    unset llm_api_key

    echo -e "XXX\n58\nGERANDO STACKS ISOLADAS... \nXXX"
    cd
    cd
    cat >"${terminal_stack}.yaml" <<EOL

version: "3.7"
services:
  $terminal_service:
    image: $terminal_image
    hostname: $terminal_service
    command:
      - -p
      - "7681"
      - -b
      - /terminal
      - -W
      - -O
      - -m
      - "1"
      - /usr/local/bin/setupmno-terminal-menu
    environment:
      - ADMIN_PASSWORD_FILE=/run/secrets/admin_password
      - SETUPMNO_CONTROL_PREFIX=$nome_app
      - SETUPMNO_CONTROL_IMAGE=$control_image
      - SETUPMNO_CONTROL_WEB_SERVICE=${web_stack}_${web_service}
      - SETUPMNO_CONTROL_TERMINAL_SERVICE=${terminal_stack}_${terminal_service}
      - SETUPMNO_CONTROL_AGENT_SERVICE=${agent_stack}_${agent_service}
      - SETUPMNO_CONTROL_ASSISTANT_STACK=$assistant_stack
      - SETUPMNO_CONTROL_ASSISTANT_COMPONENT=$assistant_service
      - SETUPMNO_CONTROL_AGENT_SECRET=$agent_secret
      - SETUPMNO_CONTROL_ADMIN_SECRET=$admin_secret
      - SETUPMNO_CONTROL_ADMIN_USERNAME=$usuario_control
    networks:
      - interna
    volumes:
      - /root:/root
      - /tmp:/tmp
      - /usr/bin/bash:/usr/bin/bash:ro
      - /var/run/docker.sock:/var/run/docker.sock
      - /etc/localtime:/etc/localtime:ro
    secrets:
      - source: $admin_secret
        target: admin_password
    healthcheck:
      test:
        - CMD
        - curl
        - -fsS
        - http://127.0.0.1:7681/terminal/
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 15s
    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
        - node.role == manager
      resources:
        limits:
          cpus: "0.50"
          memory: 256M

networks:
  interna:
    external: true

secrets:
  $admin_secret:
    external: true
EOL

    cat >"${agent_stack}.yaml" <<EOL

version: "3.7"
services:
  $agent_service:
    image: $control_image
    hostname: $agent_service
    read_only: true
    cap_drop:
      - ALL
    environment:
      - MODE=agent
      - HEALTHCHECK_URL=http://127.0.0.1:9090/health
      - AGENT_TOKEN_FILE=/run/secrets/$agent_secret
      - SETUP_STATE_DIR=/runtime-control
      - HOST_DISK_PATH=/runtime-control
    networks:
      - interna
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - /proc:/host/proc:ro
      - /root/SetupLowCodeMno/.control:/runtime-control:ro
    secrets:
      - $agent_secret
    healthcheck:
      test:
        - CMD
        - /setupmno-control
        - healthcheck
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 10s
    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
        - node.role == manager
      resources:
        limits:
          cpus: "0.25"
          memory: 128M

networks:
  interna:
    external: true

secrets:
  $agent_secret:
    external: true
EOL

    if [ "$assistant_mode" != "basic" ]; then
        cat >"${assistant_stack}.yaml" <<EOL

version: "3.7"
services:
  $assistant_service:
    image: $control_image
    hostname: $assistant_service
    user: "65532:65532"
    read_only: true
    cap_drop:
      - ALL
    environment:
      - MODE=assistant
      - HEALTHCHECK_URL=http://127.0.0.1:7070/health
      - ASSISTANT_PROVIDER=$assistant_mode
      - ASSISTANT_MODEL=$assistant_model
      - ASSISTANT_BASE_URL=$assistant_base_url
      - KNOWLEDGE_PACKAGE_DIR=/knowledge-package
      - RETRIEVAL_SHADOW_ENABLED=true
      - RETRIEVAL_INSPECTION_ENABLED=true
      - RETRIEVAL_PROMPT_ENABLED=true
      - BLUEPRINT_HOMOLOGATION_ENABLED=true
      - AGENT_TOKEN_FILE=/run/secrets/$agent_secret
      - AGENT_URL=http://${agent_stack}_${agent_service}:9090
EOL
        if [ "$assistant_external" = "true" ]; then
            cat >>"${assistant_stack}.yaml" <<EOL
      - LLM_API_KEY_FILE=/run/secrets/llm_api_key
EOL
        fi
        cat >>"${assistant_stack}.yaml" <<EOL
    networks:
      - interna
    secrets:
      - $agent_secret
EOL
        if [ "$assistant_external" = "true" ]; then
            cat >>"${assistant_stack}.yaml" <<EOL
      - source: $llm_secret
        target: llm_api_key
EOL
        fi
        cat >>"${assistant_stack}.yaml" <<EOL
    healthcheck:
      test:
        - CMD
        - /setupmno-control
        - healthcheck
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 15s
    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
        - node.role == manager
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
EOL
        if [ "$assistant_external" = "true" ]; then
            cat >>"${assistant_stack}.yaml" <<EOL
  $llm_secret:
    external: true
EOL
        fi
    fi

    cat >"${web_stack}.yaml" <<EOL

version: "3.7"
services:
  $web_service:
    image: $control_image
    hostname: $web_service
    user: "65532:65532"
    read_only: true
    cap_drop:
      - ALL
    environment:
      - MODE=web
      - APP_VERSION=$CONTROL_VERSION
      - ADMIN_USERNAME=$usuario_control
      - ADMIN_PASSWORD_FILE=/run/secrets/admin_password
      - AGENT_TOKEN_FILE=/run/secrets/$agent_secret
      - AGENT_URL=http://${agent_stack}_${agent_service}:9090
      - TERMINAL_URL=http://${terminal_stack}_${terminal_service}:7681
      - ASSISTANT_MODE=$assistant_mode
      - ASSISTANT_MODEL=$assistant_model
      - ASSISTANT_URL=$assistant_internal_url
      - FEEDBACK_STORE_PATH=/feedback/feedback.json
      - COOKIE_SECURE=true
    networks:
      - externa
      - interna
    secrets:
      - source: $admin_secret
        target: admin_password
      - $agent_secret
    volumes:
      - feedback_data:/feedback
    healthcheck:
      test:
        - CMD
        - /setupmno-control
        - healthcheck
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 10s
    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
        - node.role == manager
      resources:
        limits:
          cpus: "0.50"
          memory: 192M
EOL

    if [ "$INSTALL_TYPE" = "TRADICIONAL" ]; then
        cat >>"${web_stack}.yaml" <<EOL
      labels:
      - traefik.enable=true
      - traefik.docker.network=externa
      - traefik.http.routers.$web_service.rule=Host(\`$url_control\`)
      - traefik.http.routers.$web_service.entrypoints=websecure
      - traefik.http.routers.$web_service.priority=1
      - traefik.http.routers.$web_service.tls.certresolver=letsencryptresolver
      - traefik.http.routers.$web_service.tls=true
      - traefik.http.routers.$web_service.service=$web_service
      - traefik.http.services.$web_service.loadbalancer.server.port=8080
EOL
    fi

    cat >>"${web_stack}.yaml" <<EOL

networks:
  externa:
    external: true
  interna:
    external: true

secrets:
  $admin_secret:
    external: true
  $agent_secret:
    external: true

volumes:
  feedback_data:
EOL

    stack_files=("${terminal_stack}.yaml" "${agent_stack}.yaml")
    if [ "$assistant_mode" != "basic" ]; then
        stack_files+=("${assistant_stack}.yaml")
    fi
    stack_files+=("${web_stack}.yaml")
    for stack_file in "${stack_files[@]}"; do
        if ! docker stack config -c "/root/$stack_file" >"$work_dir/validated-$stack_file" 2>>"$install_log"; then
            {
                echo "O YAML '$stack_file' é inválido."
                echo
                tail -n 20 "$install_log"
            } >"$error_file"
            echo -e "XXX\n100\nERRO NO YAML DAS STACKS\nXXX"
            exit 50
        fi
    done

    if [ "$INSTALL_TYPE" = "CLOUDFLARE_TUNNEL" ] ||
       { [ "$INSTALL_TYPE" = "TRADICIONAL" ] && [ "$criar_dns" = "0" ]; }; then
        echo -e "XXX\n67\nCONFIGURANDO DNS DE FORMA IDEMPOTENTE... \nXXX"
        dns_lookup="$work_dir/dns-lookup.json"
        dns_response="$work_dir/dns-response.json"
        if [ "$INSTALL_TYPE" = "CLOUDFLARE_TUNNEL" ]; then
            dns_content="${TUNNEL_ID}.cfargotunnel.com"
            dns_proxied="true"
        else
            DOMINIO_PRINCIPAL=$(echo "$url_control" | cut -d'.' -f2-)
            [ -n "$nome_servidor" ] || nome_servidor=$(hostname -I | awk '{print $1}')
            dns_content="${nome_servidor}.${DOMINIO_PRINCIPAL}"
            dns_proxied="false"
        fi
        dns_payload=$(jq -nc \
            --arg name "$url_control" \
            --arg content "$dns_content" \
            --argjson proxied "$dns_proxied" \
            '{type:"CNAME",name:$name,content:$content,ttl:1,proxied:$proxied}')
        if ! curl -sS \
            --connect-timeout "$CLOUDFLARE_CONNECT_TIMEOUT" \
            --max-time "$CLOUDFLARE_MAX_TIME" \
            --get \
            "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records" \
            -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
            --data-urlencode "name=$url_control" >"$dns_lookup" 2>>"$install_log"; then
            fail_install 60 "ERRO AO CONSULTAR DNS" "Falha ao consultar o DNS $url_control no Cloudflare."
        fi
        dns_record_id=$(jq -r '.result[0].id // empty' "$dns_lookup")
        dns_record_type=$(jq -r '.result[0].type // empty' "$dns_lookup")
        if [ -n "$dns_record_id" ] && [ "$dns_record_type" != "CNAME" ]; then
            fail_install 61 "CONFLITO DE REGISTRO DNS" "Já existe um registro $dns_record_type para $url_control."
        fi
        if [ -n "$dns_record_id" ]; then
            dns_method="PUT"
            dns_url="https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records/${dns_record_id}"
        else
            dns_method="POST"
            dns_url="https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records"
        fi
        if ! curl -sS \
            --connect-timeout "$CLOUDFLARE_CONNECT_TIMEOUT" \
            --max-time "$CLOUDFLARE_MAX_TIME" \
            -X "$dns_method" "$dns_url" \
            -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
            -H "Content-Type: application/json" \
            --data "$dns_payload" >"$dns_response" 2>>"$install_log" ||
           [ "$(jq -r '.success // false' "$dns_response")" != "true" ]; then
            dns_error=$(jq -r '[.errors[]?.message] | join("; ")' "$dns_response" 2>/dev/null)
            fail_install 62 "ERRO AO CONFIGURAR DNS" "Cloudflare recusou o CNAME: ${dns_error:-resposta inválida da API}."
        fi
        echo "DNS confirmado: $url_control -> $dns_content" >>"$install_log"
    fi

    if [ "$INSTALL_TYPE" = "CLOUDFLARE_TUNNEL" ]; then
        echo -e "XXX\n73\nATUALIZANDO ROTA DO CLOUDFLARE TUNNEL... \nXXX"
        tunnel_raw="$work_dir/tunnel-raw.json"
        tunnel_payload="$work_dir/tunnel-payload.json"
        tunnel_response="$work_dir/tunnel-response.json"
        if ! curl -sS \
            --connect-timeout "$CLOUDFLARE_CONNECT_TIMEOUT" \
            --max-time "$CLOUDFLARE_MAX_TIME" \
            -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
            "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/cfd_tunnel/$TUNNEL_ID/configurations" \
            >"$tunnel_raw" 2>>"$install_log" ||
           [ "$(jq -r '.success // false' "$tunnel_raw")" != "true" ]; then
            fail_install 70 "ERRO AO CONSULTAR TUNNEL" "Não foi possível obter a configuração atual do Cloudflare Tunnel."
        fi
        if ! jq --arg host "$url_control" --arg service "http://${web_stack}_${web_service}:8080" '
            (.result.config // {}) as $cfg
            | ($cfg.ingress // [])
            | map(select(.service != "http_status:404" and .hostname != $host))
            + [{hostname:$host,service:$service,originRequest:{noTlsVerify:true,httpHostHeader:$host}},
               {service:"http_status:404"}]
            | {config:($cfg + {ingress:.})}
        ' "$tunnel_raw" >"$tunnel_payload" 2>>"$install_log"; then
            fail_install 71 "ERRO AO PREPARAR ROTA" "Falha ao preparar a nova rota do Cloudflare Tunnel."
        fi
        if ! curl -sS \
            --connect-timeout "$CLOUDFLARE_CONNECT_TIMEOUT" \
            --max-time "$CLOUDFLARE_MAX_TIME" \
            -X PUT \
            "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/cfd_tunnel/$TUNNEL_ID/configurations" \
            -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
            -H "Content-Type: application/json" \
            --data-binary @"$tunnel_payload" >"$tunnel_response" 2>>"$install_log" ||
           [ "$(jq -r '.success // false' "$tunnel_response")" != "true" ]; then
            tunnel_error=$(jq -r '[.errors[]?.message] | join("; ")' "$tunnel_response" 2>/dev/null)
            fail_install 72 "ERRO AO ATUALIZAR TUNNEL" "Cloudflare recusou a rota: ${tunnel_error:-resposta inválida da API}."
        fi
        echo "Rota confirmada: $url_control -> http://${web_stack}_${web_service}:8080" >>"$install_log"
    fi

    if [ "$assistant_mode" = "basic" ]; then
        echo -e "XXX\n80\nPREPARANDO DEPLOY DAS TRÊS STACKS... \nXXX"
    else
        echo -e "XXX\n80\nPREPARANDO DEPLOY DAS QUATRO STACKS... \nXXX"
    fi
    if [ "$criar_portainer" = "0" ]; then
        dados_file="$HOME/dados_portainer/dados_portainer"
        [ -f "$dados_file" ] ||
            fail_install 80 "CREDENCIAIS DO PORTAINER NÃO ENCONTRADAS" "Arquivo não encontrado: $dados_file"
        PORTAINER_URL=$(grep "Dominio do portainer:" "$dados_file" | cut -d':' -f2- | xargs)
        ADMIN_USERNAME=$(grep "Usuario:" "$dados_file" | cut -d':' -f2- | xargs)
        ADMIN_PASSWORD=$(grep "Senha:" "$dados_file" | cut -d':' -f2- | xargs)
        [ -n "$PORTAINER_URL" ] && [ -n "$ADMIN_USERNAME" ] && [ -n "$ADMIN_PASSWORD" ] ||
            fail_install 81 "CREDENCIAIS DO PORTAINER INVÁLIDAS" "Domínio, usuário ou senha do Portainer não encontrado."

        auth_payload="$work_dir/portainer-auth-payload.json"
        auth_response="$work_dir/portainer-auth.json"
        if ! jq -nc --arg username "$ADMIN_USERNAME" --arg password "$ADMIN_PASSWORD" \
            '{username:$username,password:$password}' >"$auth_payload"; then
            fail_install 82 "ERRO AO PREPARAR AUTENTICAÇÃO" "Não foi possível preparar a autenticação segura do Portainer."
        fi
        if ! curl -sk -X POST "https://$PORTAINER_URL/api/auth" \
            -H "Content-Type: application/json" \
            --data-binary @"$auth_payload" \
            >"$auth_response" 2>>"$install_log"; then
            fail_install 82 "ERRO DE COMUNICAÇÃO COM PORTAINER" "Não foi possível acessar a API do Portainer."
        fi
        unset ADMIN_PASSWORD
        TOKEN=$(jq -r '.jwt // empty' "$auth_response")
        [ -n "$TOKEN" ] ||
            fail_install 83 "ERRO DE AUTENTICAÇÃO NO PORTAINER" "O Portainer não retornou token válido."
        endpoint_response="$work_dir/portainer-endpoints.json"
        if ! curl -sk "https://$PORTAINER_URL/api/endpoints" \
            -H "Authorization: Bearer $TOKEN" >"$endpoint_response" 2>>"$install_log"; then
            fail_install 84 "ERRO AO CONSULTAR ENDPOINT" "Falha ao consultar endpoints do Portainer."
        fi
        ENDPOINT_ID=$(jq -r '.[0].Id // empty' "$endpoint_response")
        [ -n "$ENDPOINT_ID" ] ||
            fail_install 85 "ENDPOINT NÃO ENCONTRADO" "Nenhum endpoint foi encontrado no Portainer."
        swarm_response="$work_dir/portainer-swarm.json"
        if ! curl -sk "https://$PORTAINER_URL/api/endpoints/$ENDPOINT_ID/docker/swarm" \
            -H "Authorization: Bearer $TOKEN" >"$swarm_response" 2>>"$install_log"; then
            fail_install 86 "ERRO AO CONSULTAR SWARM" "Falha ao consultar o Swarm pelo Portainer."
        fi
        SWARM_ID=$(jq -r '.ID // empty' "$swarm_response")
        [ -n "$SWARM_ID" ] ||
            fail_install 87 "SWARM NÃO ENCONTRADO" "O Portainer não retornou um Swarm ID válido."

        for image_ref in "$control_image" "$terminal_image"; do
            image_encoded=$(printf '%s' "$image_ref" | jq -sRr @uri)
            image_http=$(curl -sk -o "$work_dir/image-check.json" -w "%{http_code}" \
                "https://$PORTAINER_URL/api/endpoints/$ENDPOINT_ID/docker/images/$image_encoded/json" \
                -H "Authorization: Bearer $TOKEN" 2>>"$install_log")
            if [ "$image_http" != "200" ]; then
                fail_install 88 "IMAGEM LOCAL NÃO VISÍVEL NO PORTAINER" \
                    "A imagem '$image_ref' existe no Docker, mas não está visível no endpoint selecionado do Portainer (HTTP $image_http). Nenhum upload foi tentado."
            fi
        done

        create_portainer_stack() {
            local stack_name="$1" stack_file="$2" response_file="$work_dir/portainer-${1}.json" http_code
            http_code=$(curl -sk -o "$response_file" -w "%{http_code}" -X POST \
                -H "Authorization: Bearer $TOKEN" \
                -F "Name=$stack_name" \
                -F "file=@/root/$stack_file" \
                -F "SwarmID=$SWARM_ID" \
                -F "endpointId=$ENDPOINT_ID" \
                "https://$PORTAINER_URL/api/stacks/create/swarm/file" 2>>"$install_log")
            if ! [[ "$http_code" =~ ^[0-9]{3}$ ]] ||
               [ "$http_code" -lt 200 ] || [ "$http_code" -ge 300 ]; then
                portainer_error=$(jq -r '.message // empty' "$response_file" 2>/dev/null)
                [ -n "$portainer_error" ] || portainer_error=$(head -c 1500 "$response_file")
                printf 'Portainer recusou a stack %s (HTTP %s): %s\n' \
                    "$stack_name" "${http_code:-indisponível}" "${portainer_error:-sem detalhes}" >"$error_file"
                return 1
            fi
            echo "Stack criada no Portainer: $stack_name (HTTP $http_code)" >>"$install_log"
        }

        echo -e "XXX\n87\nCRIANDO TERMINAL NO PORTAINER... \nXXX"
        create_portainer_stack "$terminal_stack" "${terminal_stack}.yaml" ||
            fail_install 89 "ERRO NA STACK DO TERMINAL" "$(cat "$error_file")"
        echo -e "XXX\n90\nCRIANDO AGENTE NO PORTAINER... \nXXX"
        create_portainer_stack "$agent_stack" "${agent_stack}.yaml" ||
            fail_install 90 "ERRO NA STACK DO AGENTE" "$(cat "$error_file")"
        if [ "$assistant_mode" != "basic" ]; then
            echo -e "XXX\n92\nCRIANDO ASSISTENTE NO PORTAINER... \nXXX"
            create_portainer_stack "$assistant_stack" "${assistant_stack}.yaml" ||
                fail_install 91 "ERRO NA STACK DO ASSISTENTE" "$(cat "$error_file")"
        fi
        echo -e "XXX\n93\nCRIANDO PAINEL NO PORTAINER... \nXXX"
        create_portainer_stack "$web_stack" "${web_stack}.yaml" ||
            fail_install 92 "ERRO NA STACK DO PAINEL" "$(cat "$error_file")"
    else
        echo -e "XXX\n87\nCRIANDO TERMINAL NO DOCKER... \nXXX"
        docker stack deploy --prune --resolve-image never \
            -c "/root/${terminal_stack}.yaml" "$terminal_stack" >>"$install_log" 2>&1 ||
            fail_install 92 "ERRO NA STACK DO TERMINAL" "Falha ao publicar a stack do terminal no Docker."
        echo -e "XXX\n90\nCRIANDO AGENTE NO DOCKER... \nXXX"
        docker stack deploy --prune --resolve-image never \
            -c "/root/${agent_stack}.yaml" "$agent_stack" >>"$install_log" 2>&1 ||
            fail_install 93 "ERRO NA STACK DO AGENTE" "Falha ao publicar a stack do agente no Docker."
        if [ "$assistant_mode" != "basic" ]; then
            echo -e "XXX\n92\nCRIANDO ASSISTENTE NO DOCKER... \nXXX"
            docker stack deploy --prune --resolve-image never \
                -c "/root/${assistant_stack}.yaml" "$assistant_stack" >>"$install_log" 2>&1 ||
                fail_install 94 "ERRO NA STACK DO ASSISTENTE" "Falha ao publicar a stack do assistente no Docker."
        fi
        echo -e "XXX\n93\nCRIANDO PAINEL NO DOCKER... \nXXX"
        docker stack deploy --prune --resolve-image never \
            -c "/root/${web_stack}.yaml" "$web_stack" >>"$install_log" 2>&1 ||
            fail_install 95 "ERRO NA STACK DO PAINEL" "Falha ao publicar a stack do painel no Docker."
    fi

    echo -e "XXX\n96\nAGUARDANDO OS SERVIÇOS... \nXXX"
    expected_services=(
        "${terminal_stack}_${terminal_service}"
        "${agent_stack}_${agent_service}"
    )
    if [ "$assistant_mode" != "basic" ]; then
        expected_services+=("${assistant_stack}_${assistant_service}")
    fi
    expected_services+=("${web_stack}_${web_service}")
    for service_name in "${expected_services[@]}"; do
        ready="false"
        for _ in $(seq 1 30); do
            replicas=$(docker service ls --filter "name=$service_name" \
                --format '{{.Replicas}}' 2>>"$install_log" | head -n1)
            if [ "$replicas" = "1/1" ]; then
                ready="true"
                break
            fi
            sleep 3
        done
        if [ "$ready" != "true" ]; then
            {
                echo "O serviço não atingiu 1/1 réplica: $service_name"
                echo
                docker service ps "$service_name" --no-trunc \
                    --format 'Estado: {{.CurrentState}} | Erro: {{.Error}}' 2>/dev/null | head -n 8
            } >"$error_file"
            echo -e "XXX\n100\nSERVIÇO NÃO FICOU PRONTO\nXXX"
            exit 96
        fi
        echo "Serviço confirmado: $service_name com 1/1 réplica." >>"$install_log"
    done

    echo -e "XXX\n100\nCONTROL CENTER INSTALADO COM SUCESSO\nXXX"
} 2>>"$install_log" | whiptail --title "SETUP MNO CONTROL CENTER" --gauge \
    "Preparando o painel..." 8 78 0
install_status=${PIPESTATUS[0]}
unset llm_api_key

if [ "$install_status" -ne 0 ]; then
    error_detail=$(cat "$error_file" 2>/dev/null)
    [ -n "$error_detail" ] || error_detail=$(tail -n 20 "$install_log" 2>/dev/null)
    whiptail --title "ERRO NA INSTALAÇÃO DO CONTROL CENTER" --scrolltext --msgbox \
        "A instalação foi interrompida com segurança.\n\n$error_detail\n\nLog completo: $install_log" \
        24 94
    exit "$install_status"
fi

manual_dns_note=""
if [ "$INSTALL_TYPE" = "TRADICIONAL" ] && [ "$criar_dns" = "1" ]; then
    manual_dns_note="\n\nDNS manual: aponte $url_control para o servidor antes de acessar."
fi

whiptail --title "SETUP MNO CONTROL CENTER" --msgbox \
    "Control Center instalado com sucesso.\n\nAcesse: https://$url_control\nUsuário: $usuario_control\nSenha: definida durante a instalação\nAssistente: $assistant_label\n\nStacks:\n- $web_stack\n- $agent_stack\n- $terminal_stack$([ "$assistant_mode" != "basic" ] && printf '\\n- %s' "$assistant_stack")\n\nAs imagens foram construídas localmente e validadas sem upload pelo Cloudflare.$manual_dns_note" \
    24 90

exit 0

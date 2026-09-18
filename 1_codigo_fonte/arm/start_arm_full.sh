#!/usr/bin/bash
# Gerado via Workflow MiMo - 2026-07-14 23:56:23
VERSIONSETUP="7.48.16"
EXPECTED_CATALOG_ENTRIES="157"
EXPECTED_EVAL_DATASET_VERSION="1.17.0"
EXPECTED_EVAL_GRADER_VERSION="1.9.0"
EXPECTED_EVAL_CASE_ENTRIES="877"
EXPECTED_BLUEPRINT_FACTORY_VERSION="2.1.0"
EXPECTED_BLUEPRINT_FIXTURE_ENTRIES="0"
EXPECTED_QUALITY_SCHEMA_VERSION="2"
EXPECTED_HOMOLOGATION_RUNNER_VERSION="1.3.0"
EXPECTED_CONTROL_RELEASE_SHA256="72b0600a82c6283b700fc4475bda64680824d9e01f92bd81a91171766b5f0cbb"
umask 077
# Garantir execução como root
if [ "$EUID" -ne 0 ]; then
    echo "ERRO: Este script deve ser executado como root." >&2
    exit 1
fi

setupmno_prepare_debian13_apt() {
    local root="${SETUPMNO_APT_ROOT:-}" os_release source_list keyring os_id os_version
    os_release="${root}/etc/os-release"
    source_list="${root}/etc/apt/sources.list.d/azlux.list"
    keyring="${root}/usr/share/keyrings/azlux-archive-keyring.gpg"
    [ -r "$os_release" ] || return 0
    os_id=$(sed -n 's/^ID=//p' "$os_release" | head -n1 | tr -d "\"'")
    os_version=$(sed -n 's/^VERSION_ID=//p' "$os_release" | head -n1 | tr -d "\"'")
    [ "$os_id" = "debian" ] && [[ "$os_version" == 13* ]] || return 0
    [ ! -e "$source_list" ] || { [ -f "$source_list" ] && [ ! -L "$source_list" ]; } || return 1
    [ ! -e "$keyring" ] || { [ -f "$keyring" ] && [ ! -L "$keyring" ]; } || return 1
    if [ -f "$source_list" ]; then
        grep -Fq 'packages.azlux.fr/debian' "$source_list" || return 1
        rm -f -- "$source_list" || return 1
    fi
    [ ! -f "$keyring" ] || rm -f -- "$keyring"
}

setupmno_apt() {
    env \
        DEBIAN_FRONTEND=noninteractive \
        DEBCONF_NONINTERACTIVE_SEEN=true \
        NEEDRESTART_MODE=a \
        apt-get -y \
        -o DPkg::Lock::Timeout=300 \
        -o Dpkg::Options::=--force-confold \
        "$@"
}

setupmno_prepare_debian13_apt || {
    printf 'ERRO: não foi possível remover com segurança o repositório legado Azlux no Debian 13.\n' >&2
    exit 42
}

setupmno_is_wsl() {
    grep -qi microsoft /proc/sys/kernel/osrelease 2>/dev/null ||
        grep -qi microsoft /proc/version 2>/dev/null
}

setupmno_normalize_arch() {
    case "$1" in
        x86_64|amd64) printf 'amd64\n' ;;
        aarch64|arm64) printf 'arm64\n' ;;
        *) return 1 ;;
    esac
}

setupmno_wsl_docker_alert() {
    local reason="$1" distro="${WSL_DISTRO_NAME:-Ubuntu}" message
    message="${reason}\n\nO Setup MNO foi interrompido antes de alterar a instalação.\n\n1. Abra o Docker Desktop no Windows.\n2. Ative Use WSL 2 based engine.\n3. Em Resources > WSL Integration, ative ${distro}.\n4. Clique em Apply & Restart.\n5. Confirme no Ubuntu com: docker info\n6. Execute novamente o Setup MNO.\n\nNão execute docker swarm init manualmente."
    if command -v whiptail >/dev/null 2>&1; then
        whiptail --title "DOCKER DESKTOP INDISPONÍVEL" --msgbox "$message" 22 82 1>&2
    elif command -v dialog >/dev/null 2>&1; then
        dialog --title "DOCKER DESKTOP INDISPONÍVEL" --msgbox "$message" 22 82 1>&2
    else
        printf '\nDOCKER DESKTOP INDISPONÍVEL\n%b\n' "$message" >&2
    fi
}

setupmno_docker_runtime_info() {
    if command -v timeout >/dev/null 2>&1; then
        timeout 15 docker info --format '{{.OSType}}|{{.Architecture}}|{{.Swarm.LocalNodeState}}|{{.ServerVersion}}' 2>/dev/null
    else
        docker info --format '{{.OSType}}|{{.Architecture}}|{{.Swarm.LocalNodeState}}|{{.ServerVersion}}' 2>/dev/null
    fi
}

setupmno_validate_wsl_docker() {
    local runtime_info docker_os docker_arch swarm_state server_version
    local host_arch normalized_docker_arch normalized_host_arch

    setupmno_is_wsl || return 0
    if ! command -v docker >/dev/null 2>&1; then
        setupmno_wsl_docker_alert "O cliente Docker não está disponível nesta distribuição WSL2. A integração pode estar desativada."
        return 71
    fi
    if ! runtime_info=$(setupmno_docker_runtime_info); then
        setupmno_wsl_docker_alert "O cliente Docker existe, mas o engine não respondeu. O Docker Desktop pode estar fechado ou inicializando."
        return 72
    fi
    IFS='|' read -r docker_os docker_arch swarm_state server_version <<<"$runtime_info"
    if [ "$docker_os" != "linux" ] || [ -z "$server_version" ]; then
        setupmno_wsl_docker_alert "O Docker Desktop não está disponibilizando um engine Linux válido. Selecione Linux Containers."
        return 73
    fi
    host_arch=$(uname -m 2>/dev/null) || host_arch=""
    normalized_host_arch=$(setupmno_normalize_arch "$host_arch") || normalized_host_arch=""
    normalized_docker_arch=$(setupmno_normalize_arch "$docker_arch") || normalized_docker_arch=""
    if [ -z "$normalized_host_arch" ] || [ "$normalized_host_arch" != "$normalized_docker_arch" ]; then
        setupmno_wsl_docker_alert "A arquitetura do engine Docker (${docker_arch:-desconhecida}) é incompatível com o Ubuntu WSL2 (${host_arch:-desconhecida})."
        return 74
    fi
    case "$swarm_state" in
        active|inactive) return 0 ;;
        *)
            setupmno_wsl_docker_alert "O Docker respondeu, mas o Swarm está em estado inconsistente (${swarm_state:-desconhecido})."
            return 75
            ;;
    esac
}

setupmno_validate_wsl_docker || exit $?

export NEWT_COLORS='
root=,white
window=,black
border=white,black
textbox=white,black
button=black,white
'

clear

valid_setup_plan() {
    case "$1" in
        pro-master|pro|"trial pro"|trial|free|free1|free2) return 0 ;;
        *) return 1 ;;
    esac
}

valid_setup_date() {
    local value="$1" formatted
    [[ "$value" =~ ^[0-9]{2}/[0-9]{2}/[0-9]{4}$ ]] || return 1
    formatted=$(printf '%s' "$value" | awk -F/ '{print $2 "/" $1 "/" $3}')
    date -d "$formatted" +%s >/dev/null 2>&1
}

write_trial_state() {
    local trial_dir="$1" installation_date="$2" remaining_days="$3" plan="$4"
    local trial_file="$trial_dir/trial_info" temporary_file

    valid_setup_plan "$plan" || return 1
    valid_setup_date "$installation_date" || return 1
    [[ "$remaining_days" =~ ^[0-9]+$ ]] || return 1

    mkdir -p "$trial_dir" || return 1
    temporary_file=$(mktemp "$trial_dir/trial_info.tmp.XXXXXX") || return 1
    chmod 600 "$temporary_file" || { rm -f "$temporary_file"; return 1; }
    {
        printf 'DATA_INSTALACAO=%s\n' "$installation_date"
        printf 'DAYS_TRIAL=%s\n' "$remaining_days"
        printf 'PLANO=%q\n' "$plan"
    } >"$temporary_file" || { rm -f "$temporary_file"; return 1; }
    mv -f "$temporary_file" "$trial_file"
}

write_control_environment() {
    local control_dir="$1" plan="$2" installation_type
    local public_plan temporary_file installation_type_file

    valid_setup_plan "$plan" || return 1
    case "$plan" in
        free|free1|free2) public_plan="$plan" ;;
        pro-master) public_plan="pro-master" ;;
        *) public_plan="pro" ;;
    esac

    # Uma reinstalação preserva este estado legado. Ele é a fonte de verdade
    # para o painel enquanto o dockerswarm ainda não receber uma nova escolha.
    installation_type_file="/root/.cloudflared_config/installation_type"
    if [ -e "$installation_type_file" ] || [ -L "$installation_type_file" ]; then
        [ -f "$installation_type_file" ] && [ ! -L "$installation_type_file" ] || return 1
        installation_type=$(head -n 1 "$installation_type_file" | tr -d '\r\n')
    else
        installation_type="TRADICIONAL"
    fi
    case "$installation_type" in
        CLOUDFLARE_TUNNEL|TRADICIONAL) ;;
        *) return 1 ;;
    esac

    local fleet_mode="disabled" existing_node_id="" existing_master_url="" existing_token=""
    if [ -f "$control_dir/environment.json" ] && [ ! -L "$control_dir/environment.json" ]; then
        fleet_mode=$(jq -r '.fleetMode // "disabled"' "$control_dir/environment.json" 2>/dev/null || printf 'disabled')
        existing_node_id=$(jq -r '.fleetNodeId // empty' "$control_dir/environment.json" 2>/dev/null || true)
        existing_master_url=$(jq -r '.fleetMasterUrl // empty' "$control_dir/environment.json" 2>/dev/null || true)
        existing_token=$(jq -r '.fleetToken // empty' "$control_dir/environment.json" 2>/dev/null || true)
    fi
    case "$fleet_mode" in
        disabled|master|worker) ;;
        *) fleet_mode="disabled" ;;
    esac
    if [ "$installation_type" != "CLOUDFLARE_TUNNEL" ]; then
        fleet_mode="disabled"
    fi

    mkdir -p "$control_dir" || return 1
    chmod 0755 "$control_dir" 2>/dev/null || true
    temporary_file=$(mktemp "$control_dir/environment.json.tmp.XXXXXX") || return 1
    chmod 0644 "$temporary_file" || { rm -f "$temporary_file"; return 1; }
    jq -n \
        --arg plan "$public_plan" \
        --arg installationType "$installation_type" \
        --arg fleetMode "$fleet_mode" \
        --arg fleetNodeId "$existing_node_id" \
        --arg fleetMasterUrl "$existing_master_url" \
        --arg fleetToken "$existing_token" \
        '{schemaVersion:1,plan:$plan,installationType:$installationType,fleetMode:$fleetMode} +
         (if $fleetNodeId != "" then {fleetNodeId:$fleetNodeId} else {} end) +
         (if $fleetMasterUrl != "" then {fleetMasterUrl:$fleetMasterUrl} else {} end) +
         (if $fleetToken != "" then {fleetToken:$fleetToken} else {} end)' \
        >"$temporary_file" || { rm -f "$temporary_file"; return 1; }
    mv -f "$temporary_file" "$control_dir/environment.json"
}

prepare_setup_directory_preserving_control() {
    local setup_dir="${1:-/root/SetupLowCodeMno}"
    local control_dir="$setup_dir/.control"

    if [ -L "$setup_dir" ]; then
        return 1
    fi
    if [ ! -e "$setup_dir" ]; then
        mkdir -p "$setup_dir"
        return $?
    fi
    [ -d "$setup_dir" ] || return 1
    if [ -e "$control_dir" ] || [ -L "$control_dir" ]; then
        [ -d "$control_dir" ] && [ ! -L "$control_dir" ] || return 1
    fi

    find "$setup_dir" -mindepth 1 -maxdepth 1 ! -name '.control' \
        -exec rm -rf -- {} + || return 1
    mkdir -p "$control_dir"
    chmod 0755 "$control_dir" 2>/dev/null || true
}

reconcile_control_center_plan_services() {
    local plan="$1" services service assistant_replicas running_task_status swarm_state

    valid_setup_plan "$plan" || return 1
    case "$plan" in
        free|free1|free2) assistant_replicas="0" ;;
        *) assistant_replicas="1" ;;
    esac
    command -v docker >/dev/null 2>&1 || return 0
    swarm_state=$(docker info --format '{{.Swarm.LocalNodeState}}' 2>/dev/null) || return 1
    [ "$swarm_state" = "inactive" ] && return 0
    [ "$swarm_state" = "active" ] || return 1
    services=$(docker service ls --format '{{.Name}}' 2>/dev/null) || return 1
    if [ -d "/root/SetupLowCodeMno/.control" ]; then
        chmod 0755 "/root/SetupLowCodeMno/.control" 2>/dev/null || true
        find "/root/SetupLowCodeMno/.control" -type d -exec chmod 0755 {} + 2>/dev/null || true
        find "/root/SetupLowCodeMno/.control" -type f ! -name "mfa-state.json" ! -name "*.key" -exec chmod 0644 {} + 2>/dev/null || true
        [ -f "/root/SetupLowCodeMno/.control/mfa-state.json" ] && chmod 0600 "/root/SetupLowCodeMno/.control/mfa-state.json" 2>/dev/null || true
    fi
    while IFS= read -r service; do
        case "$service" in
            mnoctrl*-agent_mnoctrl*-agent)
                [[ "$service" =~ ^mnoctrl[[:alnum:]]+-agent_mnoctrl[[:alnum:]]+-agent$ ]] || continue
                if service_has_mount_target "$service" /runtime-control; then
                    if service_has_running_task "$service"; then
                        :
                    else
                        running_task_status=$?
                        [ "$running_task_status" -eq 1 ] || return 1
                        docker service update --mount-rm /runtime-control \
                            --mount-add type=bind,src=/root/SetupLowCodeMno/.control,dst=/runtime-control,readonly \
                            --force --detach=true "$service" >/dev/null 2>&1 || return 1
                    fi
                else
                    docker service update \
                        --mount-add type=bind,src=/root/SetupLowCodeMno/.control,dst=/runtime-control,readonly \
                        --force --detach=true "$service" >/dev/null 2>&1 || return 1
                fi
                wait_for_service_mount_target "$service" /runtime-control || return 1
                ;;
            mnoctrl*-assistant_mnoctrl*-assistant)
                [[ "$service" =~ ^mnoctrl[[:alnum:]]+-assistant_mnoctrl[[:alnum:]]+-assistant$ ]] || continue
                docker service update --replicas "$assistant_replicas" --detach=true \
                    "$service" >/dev/null 2>&1 || return 1
                ;;
            mnoctrl*-web_mnoctrl*-web)
                [[ "$service" =~ ^mnoctrl[[:alnum:]]+-web_mnoctrl[[:alnum:]]+-web$ ]] || continue
                if service_has_env_key "$service" SETUPMNO_PLAN; then
                    docker service update \
                        --env-rm SETUPMNO_PLAN --env-add "SETUPMNO_PLAN=$plan" \
                        --detach=true "$service" >/dev/null 2>&1 || return 1
                else
                    docker service update --env-add "SETUPMNO_PLAN=$plan" \
                        --detach=true "$service" >/dev/null 2>&1 || return 1
                fi
                wait_for_service_env_value "$service" SETUPMNO_PLAN "$plan" || return 1
                ;;
        esac
    done <<<"$services"
}

service_has_mount_target() {
    local service="$1" target="$2"
    docker service inspect --format '{{range .Spec.TaskTemplate.ContainerSpec.Mounts}}{{println .Target}}{{end}}' \
        "$service" 2>/dev/null | grep -Fxq "$target"
}

service_has_running_task() {
    local service="$1" current_states
    current_states=$(docker service ps --filter desired-state=running \
        --format '{{.CurrentState}}' "$service" 2>/dev/null) || return 2
    grep -Eq '^Running([[:space:]]|$)' <<<"$current_states"
}

wait_for_service_mount_target() {
    local service="$1" target="$2" attempt
    for attempt in 1 2 3 4 5; do
        service_has_mount_target "$service" "$target" && return 0
        sleep 1
    done
    return 1
}

service_has_env_key() {
    local service="$1" key="$2"
    docker service inspect --format '{{range .Spec.TaskTemplate.ContainerSpec.Env}}{{println .}}{{end}}' \
        "$service" 2>/dev/null | grep -Eq "^${key}="
}

service_has_env_value() {
    local service="$1" key="$2" value="$3"
    docker service inspect --format '{{range .Spec.TaskTemplate.ContainerSpec.Env}}{{println .}}{{end}}' \
        "$service" 2>/dev/null | grep -Fxq "${key}=${value}"
}

wait_for_service_env_value() {
    local service="$1" key="$2" value="$3" attempt
    for attempt in 1 2 3 4 5; do
        service_has_env_value "$service" "$key" "$value" && return 0
        sleep 1
    done
    return 1
}

# Função para enviar HTTP POST e validar a resposta
function verificar_cliente() {
    local EMAIL="$1"
    local SENHA="$2"
    local URL="https://hook45.manualnegocioonline.com.br/webhook/valida-cliente-mno"

    # Envia o HTTP POST
    RESPOSTA=$(curl -s -X POST -H "Content-Type: application/json" \
        -d "{\"email\":\"$EMAIL\",\"senha\":\"$SENHA\"}" "$URL")


    # Verifica se houve falha no curl
    if [ $? -ne 0 ]; then
        whiptail --msgbox "Estamos com um problema temporário. Por favor, tente mais tarde. Pressione ENTER para sair" 20 78
        echo "Estamos com um problema temporário. Por favor, tente mais tarde." >&2
        exit 4
    fi

    # Extrai valores do JSON usando jq (instalado anteriormente)
    SITUACAO=$(echo "$RESPOSTA" | jq -r '.situacao_cliente')
    PLANO=$(echo "$RESPOSTA" | jq -r '.plano')
    DATAAQ=$(echo "$RESPOSTA" | jq -r '.dataaq')
    DOWNLOADS=$(echo "$RESPOSTA" | jq -r '.downloads // 0')  # Default 0 se não existir
        EMAIL=$(echo "$RESPOSTA" | jq -r '.email')
        SENHA=$(echo "$RESPOSTA" | jq -r '.senha')

    DATA_FORMATADA=$(echo "$DATAAQ" | awk -F/ '{print $2 "/" $1 "/" $3}')

    # Converter datas para timestamp
    DATAAQ_TIMESTAMP=$(date -d "$DATA_FORMATADA" +%s)
    DATAHOJE_TIMESTAMP=$(date +%s)

    # Calcular diferença em dias: hoje - data de aquisição
    DIFERENCA_SEGUNDOS=$(( DATAHOJE_TIMESTAMP - DATAAQ_TIMESTAMP ))
    DIASDECORRIDOS=$(( DIFERENCA_SEGUNDOS / 86400 ))




    case "$SITUACAO" in
    "cliente_regularizado")
        if ! valid_setup_plan "$PLANO" || ! valid_setup_date "$DATAAQ"; then
            whiptail --title "ERRO: Falha no Sistema" --msgbox "A resposta de licenciamento não trouxe um plano ou uma data válida. Nenhum estado local foi alterado. Tente novamente mais tarde." 20 78
            exit 5
        fi
        if [ "$PLANO" = "trial pro" ] || [ "$PLANO" = "trial" ]; then
        if [ "$DOWNLOADS" -ge 3 ]; then
            whiptail --title "ERRO: Número máximo de instalações atingido" --msgbox "Atenção: Você superou o número máximo de 3 instalações (downloads) da versão trial ou trial pro.\n\nEntre em contato com o nosso Suporte Técnico (apenas WhatsApp):\n\nWhatsApp: +55 (11)96816-2690.\n\nPressione ENTER para sair" 22 78
            cd /
                        cd
                        sudo rm start_full* 2>/dev/null || true
                        sudo rm start_start* 2>/dev/null || true
                        sudo rm -r SetupLowCodeMnoStart 2>/dev/null || true
                        sudo rm setup-mno.sh 2>/dev/null || true
           exit 6
        fi

        if [ "$DIASDECORRIDOS" -ge 8 ]; then
            whiptail --title "ERRO: Período de teste de 7 dias expirado!" --msgbox "Atenção: Passaram-se os 7 dias de testes da versão trial pro.\n\nEntre em contato com o nosso Suporte Técnico (apenas WhatsApp):\n\nWhatsApp: +55 (11)96816-2690.\n\nPressione ENTER para sair" 22 78
            cd /
                        cd
                        sudo rm start_full* 2>/dev/null || true
                        sudo rm start_start* 2>/dev/null || true
                        sudo rm -r SetupLowCodeMnoStart 2>/dev/null || true
                        sudo rm setup-mno.sh 2>/dev/null || true
                        exit 6
        fi
    fi

    return 0
    ;;

        "cliente_inexistente")
            whiptail --title "ERRO NO LOGIN" --msgbox "Atenção: Email e/ou senha incorretos. Pressione ENTER para sair." 20 78
            cd /
                        cd
                        sudo rm start_full* 2>/dev/null || true
                        sudo rm start_start* 2>/dev/null || true
                        sudo rm -r SetupLowCodeMnoStart 2>/dev/null || true
                        sudo rm setup-mno.sh 2>/dev/null || true
                        exit 1
            ;;
        "cliente_inadimplente")
            whiptail --title "ERRO" --msgbox "Atenção: Problema com o pagamento.\n\nEntre em contato com o nosso Suporte Técnico (apenas WhatsApp):\n\nWhatsAPP: +55 (11)96816-2690.\n\nPressione ENTER para sair" 20 78
            cd /
                        cd
                        sudo rm start_full* 2>/dev/null || true
                        sudo rm start_start* 2>/dev/null || true
                        sudo rm -r SetupLowCodeMnoStart 2>/dev/null || true
                        sudo rm setup-mno.sh 2>/dev/null || true
                        exit 2
            ;;
        "cliente_expirado")
            whiptail --title "ERRO: Conta Expirada" --msgbox "Atenção: Sua conta expirou.\n\nEntre em contato com o nosso Suporte Técnico (apenas WhatsApp):\n\nWhatsAPP: +55 (11)96816-2690.\n\nPressione ENTER para sair" 20 78
            cd /
                        cd
                        sudo rm start_full* 2>/dev/null || true
                        sudo rm start_start* 2>/dev/null || true
                        sudo rm -r SetupLowCodeMnoStart 2>/dev/null || true
                        sudo rm setup-mno.sh 2>/dev/null || true
                        exit 3
            ;;
        *)
            whiptail --title "ERRO: Falha no Sistema" --msgbox "Resposta inesperada do servidor. Tente novamente mais tarde." 20 78
            cd /
                        cd
                        sudo rm start_full* 2>/dev/null || true
                        sudo rm start_start* 2>/dev/null || true
                        sudo rm -r SetupLowCodeMnoStart 2>/dev/null || true
                        sudo rm setup-mno.sh 2>/dev/null || true
                        exit 5
            ;;
    esac
}



# Solicita email e senha
EMAIL=$(whiptail --title "1/2 - EMAIL DE ACESSO DO SETUPMNO" --inputbox "Digite seu e-mail:" 8 60 3>&1 1>&2 2>&3)
if [ $? -ne 0 ]; then exit 1; fi


SENHA=$(whiptail --title "2/2 - SENHA DE ACESSO DO SETUPMNO" --passwordbox "Digite sua senha:" 8 60 3>&1 1>&2 2>&3)
if [ $? -ne 0 ]; then exit 1; fi

# Valida o cliente antes de prosseguir
verificar_cliente "$EMAIL" "$SENHA"
unset SENHA

# Prossegue apenas se o cliente estiver regularizado

clear

control_state_error="/tmp/setupmno-control-state-error.log"
: >"$control_state_error"

{
echo -e "XXX\n5\nINSTALANDO SETUPMNO 1/8 \nXXX"

cd /usr/bin
cat > setup-mno << EOL
#!/usr/bin/bash
cd /root/SetupLowCodeMno
./install
$SHELL

EOL

chmod +x setup-mno  >/dev/null 2>&1



cd /
cd
if ! prepare_setup_directory_preserving_control "/root/SetupLowCodeMno"; then
    printf 'Não foi possível preparar a reinstalação sem remover o estado runtime do Control Center.\n' >"$control_state_error"
    exit 41
fi
echo -e "XXX\n25\nSETUPMNO: DESCOMPACTANDO ARQUIVOS 1/8 - CONCLUIDO \nXXX"
echo -e "XXX\n25\nAGUARDE: ISSO PODE LEVAR ALGUNS MINUTOS... 2/8 \nXXX"

# ------------------------------------------------------------
# INÍCIO DAS MODIFICAÇÕES PARA DEBIAN 13+
# ------------------------------------------------------------
# ------------------------------------------------------------
# GARANTIR AMBIENTE ADEQUADO (SUBSTITUI COMPLETAMENTE A SEÇÃO)
# ------------------------------------------------------------

# 1. Remover instalação antiga e garantir diretório limpo
cd /root 2>/dev/null || true
mkdir -p SetupLowCodeMno
rm -f SetupLowCodeMno.zip

echo -e "XXX\n25\nSETUPMNO: INSTALANDO DEPENDÊNCIAS... 2/8 \nXXX"

# 2. Atualizar lista de pacotes e instalar dependências essenciais
SETUPMNO_APT_LOG="/tmp/setupmno-start-apt.log"
: >"$SETUPMNO_APT_LOG"
if ! setupmno_apt update >>"$SETUPMNO_APT_LOG" 2>&1; then
    {
        echo "Falha ao atualizar a lista de pacotes sem interação."
        tail -n 20 "$SETUPMNO_APT_LOG"
    } >"$control_state_error"
    exit 42
fi
if ! setupmno_apt install sudo wget curl unzip zip jq python3 build-essential sshpass \
    >>"$SETUPMNO_APT_LOG" 2>&1; then
    {
        echo "Falha na instalação não interativa das dependências."
        tail -n 20 "$SETUPMNO_APT_LOG"
    } >"$control_state_error"
    exit 42
fi

echo -e "XXX\n30\nSETUPMNO: DEPENDÊNCIAS INSTALADAS. VERIFICANDO SHC... 2/8 \nXXX"

# 3. Instalar shc (se necessário)
if ! command -v shc &>/dev/null; then
    echo -e "XXX\n35\nSETUPMNO: COMPILANDO SHC (PODE LEVAR ALGUNS SEGUNDOS)... 2/8 \nXXX"
    cd /tmp
    wget -q https://github.com/neurobin/shc/archive/refs/tags/4.0.3.tar.gz -O shc.tar.gz
    tar xzf shc.tar.gz
    cd shc-4.0.3
    ./configure >/dev/null 2>&1
    make >/dev/null 2>&1
    make install >/dev/null 2>&1
    cd /
    rm -rf /tmp/shc-4.0.3 /tmp/shc.tar.gz
    hash -r
fi

echo -e "XXX\n45\nSETUPMNO: BAIXANDO ARQUIVOS... 2/8 \nXXX"

# 4. Download do ZIP com verificação
cd /root
wget -q -O SetupLowCodeMno.zip "https://manualnegocioonline.com.br/downloads/mno/arm/SetupLowCodeMno.zip"
if [ $? -ne 0 ] || [ ! -s SetupLowCodeMno.zip ]; then
    echo -e "XXX\n100\nERRO: FALHA NO DOWNLOAD. PRESSIONE ENTER PARA SAIR.\nXXX"
    sleep 3
    exit 1
fi

echo -e "XXX\n50\nSETUPMNO: EXTRAINDO ARQUIVOS... 2/8 \nXXX"

# 5. Extração com validação
unzip -o -P F@aioDv6740bR2021 SetupLowCodeMno.zip >/dev/null 2>&1
if [ $? -ne 0 ] || [ ! -d SetupLowCodeMno ]; then
    echo -e "XXX\n100\nERRO: FALHA NA EXTRAÇÃO. PRESSIONE ENTER PARA SAIR.\nXXX"
    sleep 3
    exit 1
fi
rm -f SetupLowCodeMno.zip

control_package="/root/SetupLowCodeMno/.control-package"
control_target="/root/SetupLowCodeMno/.control"
homologation_package="$control_package/homologation-package"
sre_engine_package="$control_package/sre-engine"
supply_chain_package="$control_package/supply-chain"
protection_boundary="$control_package/protection-boundary.json"
maintainer_runtime_files=(
    maintainer_console.sh maintainer_workspace.sh maintainer_validation_wizard.sh
    certification_wizard.sh maintainer-workspace.tar.gz
)
if [ ! -s "$control_package/release.json" ] ||
   [ -L "$control_package/release.json" ] ||
   [ ! -s "$protection_boundary" ] ||
   [ -L "$protection_boundary" ] ||
   [ ! -s "$control_package/catalog.json" ] ||
   [ ! -f "$control_package/control-source.tar.gz" ] ||
   [ -L "$control_package/control-source.tar.gz" ] ||
   [ ! -f "$control_package/knowledge-package/manifest.json" ] ||
   [ -L "$control_package/knowledge-package/manifest.json" ] ||
   [ ! -f "$control_package/knowledge-package/knowledge-package.tar.gz" ] ||
   [ -L "$control_package/knowledge-package/knowledge-package.tar.gz" ] ||
   [ ! -f "$homologation_package/manifest.json" ] ||
   [ -L "$homologation_package/manifest.json" ] ||
   [ ! -f "$homologation_package/homologation_runner.py" ] ||
   [ -L "$homologation_package/homologation_runner.py" ] ||
   [ ! -f "$homologation_package/homologation_wizard.sh" ] ||
   [ -L "$homologation_package/homologation_wizard.sh" ] ||
   [ ! -f "$homologation_package/homologation-candidate.schema.json" ] ||
   [ -L "$homologation_package/homologation-candidate.schema.json" ] ||
   [ ! -f "$homologation_package/homologation-review-decision.schema.json" ] ||
   [ -L "$homologation_package/homologation-review-decision.schema.json" ] ||
   [ ! -f "$homologation_package/homologation-review-pack.schema.json" ] ||
   [ -L "$homologation_package/homologation-review-pack.schema.json" ] ||
   [ ! -f "$homologation_package/runner-registry.json" ] ||
   [ -L "$homologation_package/runner-registry.json" ] ||
   [ ! -f "$sre_engine_package/manifest.json" ] ||
   [ -L "$sre_engine_package/manifest.json" ] ||
   [ ! -f "$supply_chain_package/manifest.json" ] ||
   [ -L "$supply_chain_package/manifest.json" ] ||
   [ ! -f "$supply_chain_package/sbom.cdx.json" ] ||
   [ -L "$supply_chain_package/sbom.cdx.json" ] ||
   [ ! -f "$supply_chain_package/image-inventory.json" ] ||
   [ -L "$supply_chain_package/image-inventory.json" ] ||
   [ ! -f "$supply_chain_package/attestation.intoto.json" ] ||
   [ -L "$supply_chain_package/attestation.intoto.json" ]; then
    printf 'O pacote não contém o catálogo, os fontes e o conhecimento runtime do Control Center.\n' >"$control_state_error"
    exit 40
fi
control_release_actual_sha=$(sha256sum "$control_package/release.json" | awk '{print $1}')
if ! [[ "$EXPECTED_CONTROL_RELEASE_SHA256" =~ ^[0-9a-f]{64}$ ]] ||
   [ "$control_release_actual_sha" != "$EXPECTED_CONTROL_RELEASE_SHA256" ]; then
    printf 'O manifesto runtime não corresponde à âncora protegida pelo SHC. Nenhum módulo externo foi promovido.\n' >"$control_state_error"
    exit 41
fi
for maintainer_file in "${maintainer_runtime_files[@]}"; do
    if [ ! -f "$homologation_package/$maintainer_file" ] ||
       [ -L "$homologation_package/$maintainer_file" ]; then
        printf 'O pacote PRO MASTER não contém o componente seguro %s.\n' "$maintainer_file" >"$control_state_error"
        exit 40
    fi
done
control_schema=$(jq -r '.schemaVersion // 0' "$control_package/release.json" 2>/dev/null)
control_version=$(jq -r '.setupVersion // empty' "$control_package/release.json" 2>/dev/null)
control_arch=$(jq -r '.architecture // empty' "$control_package/release.json" 2>/dev/null)
control_catalog_entries=$(jq -r '.catalogEntries // 0' "$control_package/release.json" 2>/dev/null)
control_expected_sha=$(jq -r '.catalogSHA256 // empty' "$control_package/release.json" 2>/dev/null)
control_actual_sha=$(sha256sum "$control_package/catalog.json" | awk '{print $1}')
control_actual_entries=$(jq -r 'length' "$control_package/catalog.json" 2>/dev/null)
control_source_archive="$control_package/control-source.tar.gz"
control_source_expected_sha=$(jq -r '.controlSourceSHA256 // empty' "$control_package/release.json" 2>/dev/null)
control_source_expected_bytes=$(jq -r '.controlSourceBytes // 0' "$control_package/release.json" 2>/dev/null)
control_source_actual_sha=$(sha256sum "$control_source_archive" | awk '{print $1}')
control_source_actual_bytes=$(stat -c '%s' "$control_source_archive" 2>/dev/null)
knowledge_manifest="$control_package/knowledge-package/manifest.json"
knowledge_archive="$control_package/knowledge-package/knowledge-package.tar.gz"
knowledge_schema=$(jq -r '.schemaVersion // 0' "$knowledge_manifest" 2>/dev/null)
knowledge_version=$(jq -r '.knowledgeVersion // empty' "$knowledge_manifest" 2>/dev/null)
knowledge_setup_version=$(jq -r '.setupVersion // empty' "$knowledge_manifest" 2>/dev/null)
knowledge_entries=$(jq -r '.documentEntries // 0' "$knowledge_manifest" 2>/dev/null)
blueprint_factory_version=$(jq -r '.blueprintFactoryVersion // empty' "$knowledge_manifest" 2>/dev/null)
blueprint_schema_version=$(jq -r '.blueprintSchemaVersion // 0' "$knowledge_manifest" 2>/dev/null)
blueprint_entries=$(jq -r '.blueprintEntries // 0' "$knowledge_manifest" 2>/dev/null)
blueprint_index_sha=$(jq -r '.blueprintIndexSHA256 // empty' "$knowledge_manifest" 2>/dev/null)
blueprint_knowledge_entries=$(jq -r '.blueprintKnowledgeEntries // 0' "$knowledge_manifest" 2>/dev/null)
blueprint_fixture_entries=$(jq -r '.blueprintFixtureEntries // 0' "$knowledge_manifest" 2>/dev/null)
eval_schema_version=$(jq -r '.evalSchemaVersion // 0' "$knowledge_manifest" 2>/dev/null)
eval_dataset_version=$(jq -r '.evalDatasetVersion // empty' "$knowledge_manifest" 2>/dev/null)
eval_grader_version=$(jq -r '.evalGraderVersion // empty' "$knowledge_manifest" 2>/dev/null)
eval_dataset_sha=$(jq -r '.evalDatasetSHA256 // empty' "$knowledge_manifest" 2>/dev/null)
eval_case_entries=$(jq -r '.evalCaseEntries // 0' "$knowledge_manifest" 2>/dev/null)
quality_schema_version=$(jq -r '.qualitySchemaVersion // 0' "$knowledge_manifest" 2>/dev/null)
quality_report_sha=$(jq -r '.qualityReportSHA256 // empty' "$knowledge_manifest" 2>/dev/null)
quality_setup_entries=$(jq -r '.qualitySummary.setupEntries // 0' "$knowledge_manifest" 2>/dev/null)
quality_structural_entries=$(jq -r '.qualitySummary.maturityLevels.structural // -1' "$knowledge_manifest" 2>/dev/null)
quality_source_reviewed_entries=$(jq -r '.qualitySummary.maturityLevels["source-reviewed"] // -1' "$knowledge_manifest" 2>/dev/null)
quality_script_reviewed_entries=$(jq -r '.qualitySummary.maturityLevels["script-reviewed"] // -1' "$knowledge_manifest" 2>/dev/null)
quality_operational_entries=$(jq -r '.qualitySummary.maturityLevels["operational-reviewed"] // -1' "$knowledge_manifest" 2>/dev/null)
quality_homologated_entries=$(jq -r '.qualitySummary.maturityLevels.homologated // -1' "$knowledge_manifest" 2>/dev/null)
quality_maturity_total=$((quality_structural_entries + quality_source_reviewed_entries + quality_script_reviewed_entries + quality_operational_entries + quality_homologated_entries))
knowledge_expected_sha=$(jq -r '.archiveSHA256 // empty' "$knowledge_manifest" 2>/dev/null)
knowledge_expected_bytes=$(jq -r '.archiveBytes // 0' "$knowledge_manifest" 2>/dev/null)
knowledge_actual_sha=$(sha256sum "$knowledge_archive" | awk '{print $1}')
knowledge_actual_bytes=$(stat -c '%s' "$knowledge_archive" 2>/dev/null)
runtime_knowledge_sha=$(jq -r '.knowledgeArchiveSHA256 // empty' "$control_package/release.json" 2>/dev/null)
runtime_knowledge_entries=$(jq -r '.knowledgeEntries // 0' "$control_package/release.json" 2>/dev/null)
runtime_blueprint_factory_version=$(jq -r '.blueprintFactoryVersion // empty' "$control_package/release.json" 2>/dev/null)
runtime_blueprint_schema_version=$(jq -r '.blueprintSchemaVersion // 0' "$control_package/release.json" 2>/dev/null)
runtime_blueprint_entries=$(jq -r '.blueprintEntries // 0' "$control_package/release.json" 2>/dev/null)
runtime_blueprint_index_sha=$(jq -r '.blueprintIndexSHA256 // empty' "$control_package/release.json" 2>/dev/null)
runtime_blueprint_knowledge_entries=$(jq -r '.blueprintKnowledgeEntries // 0' "$control_package/release.json" 2>/dev/null)
runtime_blueprint_fixture_entries=$(jq -r '.blueprintFixtureEntries // 0' "$control_package/release.json" 2>/dev/null)
runtime_eval_schema_version=$(jq -r '.evalSchemaVersion // 0' "$control_package/release.json" 2>/dev/null)
runtime_eval_dataset_version=$(jq -r '.evalDatasetVersion // empty' "$control_package/release.json" 2>/dev/null)
runtime_eval_grader_version=$(jq -r '.evalGraderVersion // empty' "$control_package/release.json" 2>/dev/null)
runtime_eval_dataset_sha=$(jq -r '.evalDatasetSHA256 // empty' "$control_package/release.json" 2>/dev/null)
runtime_eval_case_entries=$(jq -r '.evalCaseEntries // 0' "$control_package/release.json" 2>/dev/null)
runtime_quality_schema_version=$(jq -r '.qualitySchemaVersion // 0' "$control_package/release.json" 2>/dev/null)
runtime_quality_report_sha=$(jq -r '.qualityReportSHA256 // empty' "$control_package/release.json" 2>/dev/null)
runtime_quality_setup_entries=$(jq -r '.qualitySetupEntries // 0' "$control_package/release.json" 2>/dev/null)
runtime_quality_structural_entries=$(jq -r '.qualityStructuralEntries // -1' "$control_package/release.json" 2>/dev/null)
runtime_quality_source_reviewed_entries=$(jq -r '.qualitySourceReviewedEntries // -1' "$control_package/release.json" 2>/dev/null)
runtime_quality_script_reviewed_entries=$(jq -r '.qualityScriptReviewedEntries // -1' "$control_package/release.json" 2>/dev/null)
runtime_quality_operational_entries=$(jq -r '.qualityOperationalEntries // -1' "$control_package/release.json" 2>/dev/null)
runtime_quality_homologated_entries=$(jq -r '.qualityHomologatedEntries // -1' "$control_package/release.json" 2>/dev/null)
homologation_manifest="$homologation_package/manifest.json"
homologation_manifest_expected_sha=$(jq -r '.homologationPackageManifestSHA256 // empty' "$control_package/release.json" 2>/dev/null)
homologation_manifest_actual_sha=$(sha256sum "$homologation_manifest" | awk '{print $1}')
homologation_runner_version=$(jq -r '.runnerVersion // empty' "$homologation_manifest" 2>/dev/null)
homologation_runtime_runner_version=$(jq -r '.homologationRunnerVersion // empty' "$control_package/release.json" 2>/dev/null)
homologation_candidate_schema=$(jq -r '.candidateSchemaVersion // 0' "$homologation_manifest" 2>/dev/null)
homologation_runtime_candidate_schema=$(jq -r '.homologationCandidateSchemaVersion // 0' "$control_package/release.json" 2>/dev/null)
homologation_registry_entries=$(jq -r '.registryEntries // 0' "$homologation_manifest" 2>/dev/null)
homologation_runtime_registry_entries=$(jq -r '.homologationRegistryEntries // 0' "$control_package/release.json" 2>/dev/null)
homologation_setup_version=$(jq -r '.setupVersion // empty' "$homologation_manifest" 2>/dev/null)
homologation_remote_certification=$(jq -r '.remoteCertification // false' "$homologation_manifest" 2>/dev/null)
homologation_automatic_promotion=$(jq -r '
    if has("homologationAutomaticPromotion")
    then .homologationAutomaticPromotion
    else "missing"
    end
' "$control_package/release.json" 2>/dev/null)
sre_engine_manifest="$sre_engine_package/manifest.json"
sre_engine_manifest_expected_sha=$(jq -r '.sreEngineManifestSHA256 // empty' "$control_package/release.json" 2>/dev/null)
sre_engine_manifest_actual_sha=$(sha256sum "$sre_engine_manifest" | awk '{print $1}')
sre_engine_version=$(jq -r '.engineVersion // empty' "$sre_engine_manifest" 2>/dev/null)
sre_engine_runtime_version=$(jq -r '.sreEngineVersion // empty' "$control_package/release.json" 2>/dev/null)
sre_engine_maturity=$(jq -r '.maturity // empty' "$sre_engine_manifest" 2>/dev/null)
sre_engine_runtime_maturity=$(jq -r '.sreEngineMaturity // empty' "$control_package/release.json" 2>/dev/null)
sre_engine_setup_version=$(jq -r '.setupVersion // empty' "$sre_engine_manifest" 2>/dev/null)
sre_engine_files_valid="true"
while IFS=$'\t' read -r sre_path sre_sha sre_bytes; do
    case "$sre_path" in
        normalize.py|result.schema.json|run.sh|tools.json) ;;
        *) sre_engine_files_valid="false"; continue ;;
    esac
    sre_file="$sre_engine_package/$sre_path"
    if [ ! -f "$sre_file" ] || [ -L "$sre_file" ] ||
       [ "$(sha256sum "$sre_file" | awk '{print $1}')" != "$sre_sha" ] ||
       [ "$(stat -c '%s' "$sre_file" 2>/dev/null)" != "$sre_bytes" ]; then
        sre_engine_files_valid="false"
    fi
done < <(jq -r '.files[]? | [.path, .sha256, .bytes] | @tsv' "$sre_engine_manifest" 2>/dev/null)
supply_chain_manifest="$supply_chain_package/manifest.json"
supply_chain_sbom="$supply_chain_package/sbom.cdx.json"
supply_chain_inventory="$supply_chain_package/image-inventory.json"
supply_chain_attestation="$supply_chain_package/attestation.intoto.json"
supply_chain_schema=$(jq -r '.schemaVersion // 0' "$supply_chain_manifest" 2>/dev/null)
supply_chain_setup_version=$(jq -r '.setupVersion // empty' "$supply_chain_manifest" 2>/dev/null)
supply_chain_architecture=$(jq -r '.architecture // empty' "$supply_chain_manifest" 2>/dev/null)
supply_chain_generator_version=$(jq -r '.generatorVersion // empty' "$supply_chain_manifest" 2>/dev/null)
supply_chain_signature_status=$(jq -r '.attestation.signatureStatus // empty' "$supply_chain_manifest" 2>/dev/null)
supply_chain_composition=$(jq -r '.sbom.composition // empty' "$supply_chain_manifest" 2>/dev/null)
supply_chain_inventory_completeness=$(jq -r '.inventory.completeness // empty' "$supply_chain_manifest" 2>/dev/null)
supply_chain_file_entries=$(jq -r '.files | length' "$supply_chain_manifest" 2>/dev/null)
supply_chain_directory_entries=$(find "$supply_chain_package" -mindepth 1 -maxdepth 1 -printf '.' 2>/dev/null | wc -c)
supply_chain_manifest_actual_sha=$(sha256sum "$supply_chain_manifest" | awk '{print $1}')
supply_chain_manifest_expected_sha=$(jq -r '.supplyChainManifestSHA256 // empty' "$control_package/release.json" 2>/dev/null)
supply_chain_sbom_actual_sha=$(sha256sum "$supply_chain_sbom" | awk '{print $1}')
supply_chain_sbom_expected_sha=$(jq -r '.supplyChainSBOMSHA256 // empty' "$control_package/release.json" 2>/dev/null)
supply_chain_inventory_actual_sha=$(sha256sum "$supply_chain_inventory" | awk '{print $1}')
supply_chain_inventory_expected_sha=$(jq -r '.supplyChainImageInventorySHA256 // empty' "$control_package/release.json" 2>/dev/null)
supply_chain_attestation_actual_sha=$(sha256sum "$supply_chain_attestation" | awk '{print $1}')
supply_chain_attestation_expected_sha=$(jq -r '.supplyChainAttestationSHA256 // empty' "$control_package/release.json" 2>/dev/null)
supply_chain_runtime_schema=$(jq -r '.supplyChainSchemaVersion // 0' "$control_package/release.json" 2>/dev/null)
supply_chain_runtime_signature=$(jq -r '.supplyChainSignatureStatus // empty' "$control_package/release.json" 2>/dev/null)
supply_chain_runtime_complete=$(jq -r '
    if has("supplyChainCompositionComplete")
    then .supplyChainCompositionComplete
    else "missing"
    end
' "$control_package/release.json" 2>/dev/null)
supply_chain_image_references=$(jq -r '.inventory.imageReferences // -1' "$supply_chain_manifest" 2>/dev/null)
supply_chain_digest_pinned=$(jq -r '.inventory.digestPinnedImages // -1' "$supply_chain_manifest" 2>/dev/null)
supply_chain_mutable_tags=$(jq -r '.inventory.mutableTagImages // -1' "$supply_chain_manifest" 2>/dev/null)
supply_chain_high_risk_tags=$(jq -r '.inventory.highRiskMutableTagImages // -1' "$supply_chain_manifest" 2>/dev/null)
supply_chain_implicit_latest=$(jq -r '.inventory.implicitLatestImages // -1' "$supply_chain_manifest" 2>/dev/null)
supply_chain_unresolved=$(jq -r '.inventory.unresolvedExpressions // -1' "$supply_chain_manifest" 2>/dev/null)
supply_chain_runtime_image_references=$(jq -r '.supplyChainImageReferences // -2' "$control_package/release.json" 2>/dev/null)
supply_chain_runtime_digest_pinned=$(jq -r '.supplyChainDigestPinnedImages // -2' "$control_package/release.json" 2>/dev/null)
supply_chain_runtime_mutable_tags=$(jq -r '.supplyChainMutableTagImages // -2' "$control_package/release.json" 2>/dev/null)
supply_chain_runtime_high_risk_tags=$(jq -r '.supplyChainHighRiskMutableTagImages // -2' "$control_package/release.json" 2>/dev/null)
supply_chain_runtime_implicit_latest=$(jq -r '.supplyChainImplicitLatestImages // -2' "$control_package/release.json" 2>/dev/null)
supply_chain_runtime_unresolved=$(jq -r '.supplyChainUnresolvedReferences // -2' "$control_package/release.json" 2>/dev/null)
supply_chain_files_valid="true"
for supply_chain_file in sbom.cdx.json image-inventory.json attestation.intoto.json; do
    expected_sha=$(jq -r --arg path "$supply_chain_file" '.files[] | select(.path == $path) | .sha256' "$supply_chain_manifest" 2>/dev/null)
    expected_size=$(jq -r --arg path "$supply_chain_file" '.files[] | select(.path == $path) | .size' "$supply_chain_manifest" 2>/dev/null)
    actual_sha=$(sha256sum "$supply_chain_package/$supply_chain_file" | awk '{print $1}')
    actual_size=$(stat -c '%s' "$supply_chain_package/$supply_chain_file" 2>/dev/null)
    if [ "$expected_sha" != "$actual_sha" ] || [ "$expected_size" != "$actual_size" ]; then
        supply_chain_files_valid="false"
    fi
done
boundary_expected_sha=$(jq -r '.protectionBoundarySHA256 // empty' "$control_package/release.json" 2>/dev/null)
boundary_expected_bytes=$(jq -r '.protectionBoundaryBytes // 0' "$control_package/release.json" 2>/dev/null)
boundary_expected_entries=$(jq -r '.protectionBoundaryEntries // 0' "$control_package/release.json" 2>/dev/null)
boundary_actual_sha=$(sha256sum "$protection_boundary" | awk '{print $1}')
boundary_actual_bytes=$(stat -c '%s' "$protection_boundary" 2>/dev/null)
boundary_actual_entries=$(jq -r '.artifactCount // 0' "$protection_boundary" 2>/dev/null)
boundary_file_entries=$(find "$control_package" -type f ! -path "$control_package/release.json" ! -path "$protection_boundary" | wc -l)
boundary_links=$(find "$control_package" -type l -print -quit)
boundary_files_valid="true"
while IFS=$'\t' read -r boundary_path boundary_sha boundary_bytes; do
    case "$boundary_path" in
        ""|/*|../*|*/../*|*/..|release.json|protection-boundary.json) boundary_files_valid="false"; continue ;;
    esac
    boundary_file="$control_package/$boundary_path"
    if [ ! -f "$boundary_file" ] || [ -L "$boundary_file" ] ||
       [ "$(sha256sum "$boundary_file" | awk '{print $1}')" != "$boundary_sha" ] ||
       [ "$(stat -c '%s' "$boundary_file" 2>/dev/null)" != "$boundary_bytes" ]; then
        boundary_files_valid="false"
    fi
done < <(jq -r '.artifacts[]? | [.path, .sha256, .bytes] | @tsv' "$protection_boundary" 2>/dev/null)
homologation_runner_expected_sha=$(jq -r '.files[] | select(.path == "homologation_runner.py") | .sha256' "$homologation_manifest" 2>/dev/null)
homologation_runner_expected_bytes=$(jq -r '.files[] | select(.path == "homologation_runner.py") | .size' "$homologation_manifest" 2>/dev/null)
homologation_wizard_expected_sha=$(jq -r '.files[] | select(.path == "homologation_wizard.sh") | .sha256' "$homologation_manifest" 2>/dev/null)
homologation_wizard_expected_bytes=$(jq -r '.files[] | select(.path == "homologation_wizard.sh") | .size' "$homologation_manifest" 2>/dev/null)
homologation_schema_expected_sha=$(jq -r '.files[] | select(.path == "homologation-candidate.schema.json") | .sha256' "$homologation_manifest" 2>/dev/null)
homologation_schema_expected_bytes=$(jq -r '.files[] | select(.path == "homologation-candidate.schema.json") | .size' "$homologation_manifest" 2>/dev/null)
homologation_decision_schema_expected_sha=$(jq -r '.files[] | select(.path == "homologation-review-decision.schema.json") | .sha256' "$homologation_manifest" 2>/dev/null)
homologation_decision_schema_expected_bytes=$(jq -r '.files[] | select(.path == "homologation-review-decision.schema.json") | .size' "$homologation_manifest" 2>/dev/null)
homologation_review_pack_schema_expected_sha=$(jq -r '.files[] | select(.path == "homologation-review-pack.schema.json") | .sha256' "$homologation_manifest" 2>/dev/null)
homologation_review_pack_schema_expected_bytes=$(jq -r '.files[] | select(.path == "homologation-review-pack.schema.json") | .size' "$homologation_manifest" 2>/dev/null)
homologation_registry_expected_sha=$(jq -r '.files[] | select(.path == "runner-registry.json") | .sha256' "$homologation_manifest" 2>/dev/null)
homologation_registry_expected_bytes=$(jq -r '.files[] | select(.path == "runner-registry.json") | .size' "$homologation_manifest" 2>/dev/null)
homologation_runner_actual_sha=$(sha256sum "$homologation_package/homologation_runner.py" | awk '{print $1}')
homologation_runner_actual_bytes=$(stat -c '%s' "$homologation_package/homologation_runner.py" 2>/dev/null)
homologation_wizard_actual_sha=$(sha256sum "$homologation_package/homologation_wizard.sh" | awk '{print $1}')
homologation_wizard_actual_bytes=$(stat -c '%s' "$homologation_package/homologation_wizard.sh" 2>/dev/null)
homologation_schema_actual_sha=$(sha256sum "$homologation_package/homologation-candidate.schema.json" | awk '{print $1}')
homologation_schema_actual_bytes=$(stat -c '%s' "$homologation_package/homologation-candidate.schema.json" 2>/dev/null)
homologation_decision_schema_actual_sha=$(sha256sum "$homologation_package/homologation-review-decision.schema.json" | awk '{print $1}')
homologation_decision_schema_actual_bytes=$(stat -c '%s' "$homologation_package/homologation-review-decision.schema.json" 2>/dev/null)
homologation_review_pack_schema_actual_sha=$(sha256sum "$homologation_package/homologation-review-pack.schema.json" | awk '{print $1}')
homologation_review_pack_schema_actual_bytes=$(stat -c '%s' "$homologation_package/homologation-review-pack.schema.json" 2>/dev/null)
homologation_registry_actual_sha=$(sha256sum "$homologation_package/runner-registry.json" | awk '{print $1}')
homologation_registry_actual_bytes=$(stat -c '%s' "$homologation_package/runner-registry.json" 2>/dev/null)
maintainer_runtime_valid="true"
for maintainer_file in "${maintainer_runtime_files[@]}"; do
    maintainer_expected_sha=$(jq -r --arg path "$maintainer_file" '.files[] | select(.path == $path) | .sha256' "$homologation_manifest" 2>/dev/null)
    maintainer_expected_bytes=$(jq -r --arg path "$maintainer_file" '.files[] | select(.path == $path) | .size' "$homologation_manifest" 2>/dev/null)
    maintainer_actual_sha=$(sha256sum "$homologation_package/$maintainer_file" | awk '{print $1}')
    maintainer_actual_bytes=$(stat -c '%s' "$homologation_package/$maintainer_file" 2>/dev/null)
    if [ "$maintainer_expected_sha" != "$maintainer_actual_sha" ] ||
       [ "$maintainer_expected_bytes" != "$maintainer_actual_bytes" ]; then
        maintainer_runtime_valid="false"
    fi
done
if [ "$control_catalog_entries" != "$EXPECTED_CATALOG_ENTRIES" ] ||
   [ "$control_actual_entries" != "$EXPECTED_CATALOG_ENTRIES" ] ||
   [ "$quality_setup_entries" != "$EXPECTED_CATALOG_ENTRIES" ] ||
   [ "$runtime_quality_setup_entries" != "$EXPECTED_CATALOG_ENTRIES" ]; then
    printf 'A quantidade de setups do pacote diverge da release: esperado=%s, catálogo=%s/%s, conhecimento=%s, runtime=%s.\n' \
        "$EXPECTED_CATALOG_ENTRIES" "$control_catalog_entries" "${control_actual_entries:-inválido}" \
        "$quality_setup_entries" "$runtime_quality_setup_entries" >"$control_state_error"
    exit 41
fi
if [ "$homologation_automatic_promotion" != "false" ]; then
    printf 'O campo homologationAutomaticPromotion do manifesto runtime deve existir e ser false; valor encontrado: %s.\n' \
        "${homologation_automatic_promotion:-inválido}" >"$control_state_error"
    exit 41
fi
if [ "$control_schema" != "1" ] ||
   [ "$control_version" != "$VERSIONSETUP" ] ||
   [ "$control_arch" != "arm64" ] ||
   [ "$sre_engine_manifest_expected_sha" != "$sre_engine_manifest_actual_sha" ] ||
   [ "$sre_engine_version" != "1.0.0" ] ||
   [ "$sre_engine_runtime_version" != "$sre_engine_version" ] ||
   [ "$sre_engine_maturity" != "beta" ] ||
   [ "$sre_engine_runtime_maturity" != "$sre_engine_maturity" ] ||
   [ "$sre_engine_setup_version" != "$VERSIONSETUP" ] ||
   [ "$sre_engine_files_valid" != "true" ] ||
   [ "$(jq -r '.files | length' "$sre_engine_manifest" 2>/dev/null)" != "4" ] ||
   [ "$boundary_expected_sha" != "$boundary_actual_sha" ] ||
   [ "$boundary_expected_bytes" != "$boundary_actual_bytes" ] ||
   [ "$boundary_expected_entries" != "$boundary_actual_entries" ] ||
   [ "$boundary_actual_entries" != "$boundary_file_entries" ] ||
   [ "$boundary_files_valid" != "true" ] ||
   [ -n "$boundary_links" ] ||
   ! jq -e --arg version "$VERSIONSETUP" '
       .schemaVersion == 1 and .boundaryVersion == "1.0.0" and
       .maturity == "beta" and .setupVersion == $version and
       .architecture == "arm64" and .defaultForNewModules == "external-verified" and
       .trustAnchor == "shc-embedded-release-sha256" and
       (.artifactCount > 0) and (.artifactCount == (.artifacts | length)) and
       ([.artifacts[].path] | length == (unique | length)) and
       all(.artifacts[]; (.path | type == "string" and length > 0) and
           (.sha256 | test("^[0-9a-f]{64}$")) and (.bytes | type == "number" and . >= 0) and
           .mode == "verified-external")
   ' "$protection_boundary" >/dev/null 2>&1 ||
   [ -z "$control_expected_sha" ] ||
   [ "$control_expected_sha" != "$control_actual_sha" ] ||
   [ -z "$control_source_expected_sha" ] ||
   [ "$control_source_expected_sha" != "$control_source_actual_sha" ] ||
   [ "$control_source_expected_bytes" != "$control_source_actual_bytes" ] ||
   [ "$control_source_actual_bytes" -le 0 ] ||
   [ "$control_source_actual_bytes" -gt $((2 * 1024 * 1024)) ] ||
   ! tar -tzf "$control_source_archive" >/dev/null 2>&1 ||
   ! tar -tvzf "$control_source_archive" 2>/dev/null |
       awk 'substr($1, 1, 1) != "-" && substr($1, 1, 1) != "d" { exit 1 }' ||
   ! tar -tzf "$control_source_archive" 2>/dev/null |
       awk '/^\// || /(^|\/)\.\.(\/|$)/ { exit 1 }' ||
   [ "$knowledge_schema" != "1" ] ||
   [ -z "$knowledge_version" ] ||
   [ "$knowledge_setup_version" != "$VERSIONSETUP" ] ||
   [ "$knowledge_entries" -le 0 ] ||
   [ "$knowledge_entries" != "$runtime_knowledge_entries" ] ||
   [ "$blueprint_schema_version" != "2" ] ||
   [ "$blueprint_schema_version" != "$runtime_blueprint_schema_version" ] ||
   [ "$blueprint_factory_version" != "$EXPECTED_BLUEPRINT_FACTORY_VERSION" ] ||
   [ "$blueprint_factory_version" != "$runtime_blueprint_factory_version" ] ||
   [ "$blueprint_entries" -le 0 ] ||
   [ "$blueprint_entries" != "$runtime_blueprint_entries" ] ||
   [ "${#blueprint_index_sha}" -ne 64 ] ||
   [ "$blueprint_index_sha" != "$runtime_blueprint_index_sha" ] ||
   [ "$blueprint_knowledge_entries" -le 0 ] ||
   [ "$blueprint_knowledge_entries" != "$runtime_blueprint_knowledge_entries" ] ||
   [ "$blueprint_fixture_entries" != "$EXPECTED_BLUEPRINT_FIXTURE_ENTRIES" ] ||
   [ "$blueprint_fixture_entries" != "$runtime_blueprint_fixture_entries" ] ||
   [ "$eval_schema_version" != "1" ] ||
   [ "$eval_schema_version" != "$runtime_eval_schema_version" ] ||
   [ "$eval_dataset_version" != "$EXPECTED_EVAL_DATASET_VERSION" ] ||
   [ "$eval_dataset_version" != "$runtime_eval_dataset_version" ] ||
   [ "$eval_grader_version" != "$EXPECTED_EVAL_GRADER_VERSION" ] ||
   [ "$eval_grader_version" != "$runtime_eval_grader_version" ] ||
   [ "${#eval_dataset_sha}" -ne 64 ] ||
   [ "$eval_dataset_sha" != "$runtime_eval_dataset_sha" ] ||
   [ "$eval_case_entries" != "$EXPECTED_EVAL_CASE_ENTRIES" ] ||
   [ "$eval_case_entries" != "$runtime_eval_case_entries" ] ||
   [ "$quality_schema_version" != "$EXPECTED_QUALITY_SCHEMA_VERSION" ] ||
   [ "$quality_schema_version" != "$runtime_quality_schema_version" ] ||
   [ "${#quality_report_sha}" -ne 64 ] ||
   [ "$quality_report_sha" != "$runtime_quality_report_sha" ] ||
   [ "$quality_setup_entries" != "$runtime_quality_setup_entries" ] ||
   [ "$quality_setup_entries" != "$EXPECTED_CATALOG_ENTRIES" ] ||
   [ "$quality_maturity_total" != "$quality_setup_entries" ] ||
   [ "$quality_structural_entries" != "$runtime_quality_structural_entries" ] ||
   [ "$quality_source_reviewed_entries" != "$runtime_quality_source_reviewed_entries" ] ||
   [ "$quality_script_reviewed_entries" != "$runtime_quality_script_reviewed_entries" ] ||
   [ "$quality_operational_entries" != "$runtime_quality_operational_entries" ] ||
   [ "$quality_homologated_entries" != "$runtime_quality_homologated_entries" ] ||
   [ "$homologation_manifest_expected_sha" != "$homologation_manifest_actual_sha" ] ||
   [ "$homologation_runner_version" != "$EXPECTED_HOMOLOGATION_RUNNER_VERSION" ] ||
   [ "$homologation_runner_version" != "$homologation_runtime_runner_version" ] ||
   [ "$homologation_candidate_schema" != "1" ] ||
   [ "$homologation_candidate_schema" != "$homologation_runtime_candidate_schema" ] ||
   [ "$homologation_registry_entries" != "$EXPECTED_CATALOG_ENTRIES" ] ||
   [ "$homologation_registry_entries" != "$homologation_runtime_registry_entries" ] ||
   [ "$homologation_setup_version" != "$VERSIONSETUP" ] ||
   [ "$homologation_remote_certification" != "true" ] ||
   [ "$homologation_runner_expected_sha" != "$homologation_runner_actual_sha" ] ||
   [ "$homologation_runner_expected_bytes" != "$homologation_runner_actual_bytes" ] ||
   [ "$homologation_wizard_expected_sha" != "$homologation_wizard_actual_sha" ] ||
   [ "$homologation_wizard_expected_bytes" != "$homologation_wizard_actual_bytes" ] ||
   [ "$homologation_schema_expected_sha" != "$homologation_schema_actual_sha" ] ||
   [ "$homologation_schema_expected_bytes" != "$homologation_schema_actual_bytes" ] ||
   [ "$homologation_decision_schema_expected_sha" != "$homologation_decision_schema_actual_sha" ] ||
   [ "$homologation_decision_schema_expected_bytes" != "$homologation_decision_schema_actual_bytes" ] ||
   [ "$homologation_review_pack_schema_expected_sha" != "$homologation_review_pack_schema_actual_sha" ] ||
   [ "$homologation_review_pack_schema_expected_bytes" != "$homologation_review_pack_schema_actual_bytes" ] ||
   [ "$homologation_registry_expected_sha" != "$homologation_registry_actual_sha" ] ||
   [ "$homologation_registry_expected_bytes" != "$homologation_registry_actual_bytes" ] ||
   [ "$maintainer_runtime_valid" != "true" ] ||
   [ "$supply_chain_schema" != "1" ] ||
   [ "$supply_chain_runtime_schema" != "1" ] ||
   [ "$supply_chain_setup_version" != "$VERSIONSETUP" ] ||
   [ "$supply_chain_architecture" != "arm64" ] ||
   [ "$supply_chain_generator_version" != "1.0.0" ] ||
   [ "$supply_chain_signature_status" != "unsigned-sha256-bound" ] ||
   [ "$supply_chain_runtime_signature" != "$supply_chain_signature_status" ] ||
   [ "$supply_chain_runtime_complete" != "false" ] ||
   [ "$supply_chain_composition" != "incomplete" ] ||
   [ "$supply_chain_inventory_completeness" != "partial" ] ||
   [ "$supply_chain_file_entries" != "3" ] ||
   [ "$supply_chain_directory_entries" != "4" ] ||
   [ "$supply_chain_manifest_expected_sha" != "$supply_chain_manifest_actual_sha" ] ||
   [ "$supply_chain_sbom_expected_sha" != "$supply_chain_sbom_actual_sha" ] ||
   [ "$supply_chain_inventory_expected_sha" != "$supply_chain_inventory_actual_sha" ] ||
   [ "$supply_chain_attestation_expected_sha" != "$supply_chain_attestation_actual_sha" ] ||
   [ "$supply_chain_files_valid" != "true" ] ||
   [ "$supply_chain_image_references" -lt 1 ] ||
   [ "$supply_chain_image_references" != "$supply_chain_runtime_image_references" ] ||
   [ "$supply_chain_digest_pinned" != "$supply_chain_runtime_digest_pinned" ] ||
   [ "$supply_chain_mutable_tags" != "$supply_chain_runtime_mutable_tags" ] ||
   [ "$supply_chain_high_risk_tags" != "$supply_chain_runtime_high_risk_tags" ] ||
   [ "$supply_chain_implicit_latest" != "$supply_chain_runtime_implicit_latest" ] ||
   [ "$supply_chain_unresolved" != "$supply_chain_runtime_unresolved" ] ||
   [ "$(jq -r '.bomFormat // empty' "$supply_chain_sbom" 2>/dev/null)" != "CycloneDX" ] ||
   [ "$(jq -r '.specVersion // empty' "$supply_chain_sbom" 2>/dev/null)" != "1.6" ] ||
   [ "$(jq -r '._type // empty' "$supply_chain_attestation" 2>/dev/null)" != "https://in-toto.io/Statement/v1" ] ||
   [ "$(jq -r '.predicateType // empty' "$supply_chain_attestation" 2>/dev/null)" != "https://slsa.dev/provenance/v1" ] ||
   [ "$knowledge_expected_sha" != "$knowledge_actual_sha" ] ||
   [ "$knowledge_expected_sha" != "$runtime_knowledge_sha" ] ||
   [ "$knowledge_expected_bytes" != "$knowledge_actual_bytes" ] ||
   [ "$knowledge_actual_bytes" -gt $((8 * 1024 * 1024)) ] ||
   ! tar -tzf "$knowledge_archive" >/dev/null 2>&1 ||
   ! tar -tvzf "$knowledge_archive" 2>/dev/null |
       awk 'substr($1, 1, 1) != "-" { exit 1 }'; then
    printf 'O manifesto runtime do Control Center é inválido ou não corresponde ao Setup MNO v%s (arm64).\n' \
        "$VERSIONSETUP" >"$control_state_error"
    exit 41
fi
mkdir -p "$control_target" "$control_target/knowledge-package" \
    "$control_target/homologation-package" "$control_target/sre-engine" \
    "$control_target/supply-chain"
install -m 0644 "$protection_boundary" "$control_target/protection-boundary.json.tmp"
install -m 0644 "$control_package/catalog.json" "$control_target/catalog.json.tmp"
install -m 0644 "$control_package/release.json" "$control_target/release.json.tmp"
install -m 0644 "$control_source_archive" "$control_target/control-source.tar.gz.tmp"
install -m 0644 "$knowledge_archive" \
    "$control_target/knowledge-package/knowledge-package.tar.gz.tmp"
install -m 0644 "$knowledge_manifest" \
    "$control_target/knowledge-package/manifest.json.tmp"
install -m 0644 "$homologation_package/manifest.json" \
    "$control_target/homologation-package/manifest.json.tmp"
install -m 0644 "$homologation_package/homologation_runner.py" \
    "$control_target/homologation-package/homologation_runner.py.tmp"
install -m 0755 "$homologation_package/homologation_wizard.sh" \
    "$control_target/homologation-package/homologation_wizard.sh.tmp"
install -m 0644 "$homologation_package/homologation-candidate.schema.json" \
    "$control_target/homologation-package/homologation-candidate.schema.json.tmp"
install -m 0644 "$homologation_package/homologation-review-decision.schema.json" \
    "$control_target/homologation-package/homologation-review-decision.schema.json.tmp"
install -m 0644 "$homologation_package/homologation-review-pack.schema.json" \
    "$control_target/homologation-package/homologation-review-pack.schema.json.tmp"
install -m 0644 "$homologation_package/runner-registry.json" \
    "$control_target/homologation-package/runner-registry.json.tmp"
install -m 0644 "$sre_engine_package/manifest.json" "$control_target/sre-engine/manifest.json.tmp"
install -m 0755 "$sre_engine_package/run.sh" "$control_target/sre-engine/run.sh.tmp"
install -m 0755 "$sre_engine_package/normalize.py" "$control_target/sre-engine/normalize.py.tmp"
install -m 0644 "$sre_engine_package/tools.json" "$control_target/sre-engine/tools.json.tmp"
install -m 0644 "$sre_engine_package/result.schema.json" "$control_target/sre-engine/result.schema.json.tmp"
for maintainer_file in "${maintainer_runtime_files[@]}"; do
    maintainer_mode=0644
    case "$maintainer_file" in
        maintainer_console.sh|maintainer_validation_wizard.sh|certification_wizard.sh) maintainer_mode=0755 ;;
    esac
    install -m "$maintainer_mode" "$homologation_package/$maintainer_file" \
        "$control_target/homologation-package/$maintainer_file.tmp"
done
for supply_chain_file in manifest.json sbom.cdx.json image-inventory.json attestation.intoto.json; do
    install -m 0644 "$supply_chain_package/$supply_chain_file" \
        "$control_target/supply-chain/$supply_chain_file.tmp"
done
mv -f "$control_target/catalog.json.tmp" "$control_target/catalog.json"
mv -f "$control_target/protection-boundary.json.tmp" "$control_target/protection-boundary.json"
mv -f "$control_target/control-source.tar.gz.tmp" "$control_target/control-source.tar.gz"
mv -f "$control_target/knowledge-package/knowledge-package.tar.gz.tmp" \
    "$control_target/knowledge-package/knowledge-package.tar.gz"
mv -f "$control_target/knowledge-package/manifest.json.tmp" \
    "$control_target/knowledge-package/manifest.json"
mv -f "$control_target/homologation-package/manifest.json.tmp" \
    "$control_target/homologation-package/manifest.json"
mv -f "$control_target/homologation-package/homologation_runner.py.tmp" \
    "$control_target/homologation-package/homologation_runner.py"
mv -f "$control_target/homologation-package/homologation_wizard.sh.tmp" \
    "$control_target/homologation-package/homologation_wizard.sh"
mv -f "$control_target/homologation-package/homologation-candidate.schema.json.tmp" \
    "$control_target/homologation-package/homologation-candidate.schema.json"
mv -f "$control_target/homologation-package/homologation-review-decision.schema.json.tmp" \
    "$control_target/homologation-package/homologation-review-decision.schema.json"
mv -f "$control_target/homologation-package/homologation-review-pack.schema.json.tmp" \
    "$control_target/homologation-package/homologation-review-pack.schema.json"
mv -f "$control_target/homologation-package/runner-registry.json.tmp" \
    "$control_target/homologation-package/runner-registry.json"
for sre_engine_file in manifest.json run.sh normalize.py tools.json result.schema.json; do
    mv -f "$control_target/sre-engine/$sre_engine_file.tmp" \
        "$control_target/sre-engine/$sre_engine_file"
done
for maintainer_file in "${maintainer_runtime_files[@]}"; do
    mv -f "$control_target/homologation-package/$maintainer_file.tmp" \
        "$control_target/homologation-package/$maintainer_file"
done
for supply_chain_file in manifest.json sbom.cdx.json image-inventory.json attestation.intoto.json; do
    mv -f "$control_target/supply-chain/$supply_chain_file.tmp" \
        "$control_target/supply-chain/$supply_chain_file"
done
if [ "$PLANO" != "pro-master" ]; then
    rm -f -- \
        "$control_target/homologation-package/manifest.json" \
        "$control_target/homologation-package/homologation_runner.py" \
        "$control_target/homologation-package/homologation_wizard.sh" \
        "$control_target/homologation-package/homologation-candidate.schema.json" \
        "$control_target/homologation-package/homologation-review-decision.schema.json" \
        "$control_target/homologation-package/homologation-review-pack.schema.json" \
        "$control_target/homologation-package/runner-registry.json" \
        "$control_target/homologation-package/maintainer_console.sh" \
        "$control_target/homologation-package/maintainer_workspace.sh" \
        "$control_target/homologation-package/maintainer_validation_wizard.sh" \
        "$control_target/homologation-package/certification_wizard.sh" \
        "$control_target/homologation-package/maintainer-workspace.tar.gz"
    rmdir -- "$control_target/homologation-package" 2>/dev/null || true
fi
mv -f "$control_target/release.json.tmp" "$control_target/release.json"
rm -rf "$control_package"
chmod 0755 "$control_target" 2>/dev/null || true
find "$control_target" -type d -exec chmod 0755 {} + 2>/dev/null || true
find "$control_target" -type f ! -name "mfa-state.json" ! -name "*.key" -exec chmod 0644 {} + 2>/dev/null || true
[ -f "$control_target/mfa-state.json" ] && chmod 0600 "$control_target/mfa-state.json" 2>/dev/null || true

cd SetupLowCodeMno || exit 1

echo -e "XXX\n50\nINSTALANDO SETUPMNO 2/8 - CONCLUÍDO \nXXX"
TRIAL_DIR="/root/SetupLowCodeMno/.meu_app_trial"
TRIAL_FILE="$TRIAL_DIR/trial_info"


# Calcular dias restantes do trial
DATA_FORMATADA=$(echo "$DATAAQ" | awk -F/ '{print $2 "/" $1 "/" $3}')
DATAAQ_TIMESTAMP=$(date -d "$DATA_FORMATADA" +%s)
DATAHOJE_TIMESTAMP=$(date +%s)

DIFERENCA_SEGUNDOS=$(( DATAAQ_TIMESTAMP + 7*86400 - DATAHOJE_TIMESTAMP ))
#DAYS_TRIAL=$(( DIFERENCA_SEGUNDOS / 86400 ))
DAYS_TRIAL=$(( (DIFERENCA_SEGUNDOS / 86400) + 1 ))

# Garante que não mostre negativo
if [ "$DAYS_TRIAL" -lt 0 ]; then
    DAYS_TRIAL=0
fi


previous_control_plan=""
if [ -f /root/SetupLowCodeMno/.control/environment.json ] &&
   [ ! -L /root/SetupLowCodeMno/.control/environment.json ]; then
    previous_control_plan=$(jq -r '.plan // empty' \
        /root/SetupLowCodeMno/.control/environment.json 2>/dev/null || true)
    valid_setup_plan "$previous_control_plan" || previous_control_plan=""
fi

if ! write_trial_state "$TRIAL_DIR" "$DATAAQ" "$DAYS_TRIAL" "$PLANO"; then
    printf 'Não foi possível persistir de forma segura o plano validado. Nenhuma instalação foi iniciada.\n' >"$control_state_error"
    exit 41
fi

if ! write_control_environment "/root/SetupLowCodeMno/.control" "$PLANO"; then
    printf 'Não foi possível publicar o plano e o tipo de instalação para o Control Center.\n' >"$control_state_error"
    exit 41
fi
if ! reconcile_control_center_plan_services "$PLANO"; then
    if [ -n "$previous_control_plan" ]; then
        write_control_environment "/root/SetupLowCodeMno/.control" \
            "$previous_control_plan" >/dev/null 2>&1 || true
        reconcile_control_center_plan_services "$previous_control_plan" \
            >/dev/null 2>&1 || true
    fi
    printf 'Os serviços existentes do Control Center não puderam ser reconciliados com o novo acesso. O estado anterior do painel foi restaurado quando disponível.\n' >"$control_state_error"
    exit 41
fi


if [ "$PLANO" = "pro-master" ] || [ "$PLANO" = "pro" ] || [ "$PLANO" == "free" ] || [ "$PLANO" == "free1" ] || [ "$PLANO" == "free2" ] ; then
data_expiracao=$(date +'%d/%m/%Y' -d "+7 days")
else
data_expiracao=$(date -d "$(echo $DATAAQ | awk -F/ '{print $2 "/" $1 "/" $3}') +8 days" +'%d/%m/%Y')
fi

msg_expiracao="$msg_expiracao"
shc -r -e $data_expiracao -m "$msg_expiracao" -o affine -f affine.sh
rm affine.sh
rm affine.sh.x.c
if [ "$PLANO" == "free" ]; then
rm affine
fi
if [[ ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm affine
fi

echo -e "XXX\n51\nINSTALANDO SETUPMNO 3/8 \nXXX"
shc -r -e $data_expiracao -m "$msg_expiracao" -o anythingllm -f anythingllm.sh
rm anythingllm.sh
rm anythingllm.sh.x.c
if [[ ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm anythingllm
fi
echo -e "XXX\n52\nINSTALANDO SETUPMNO 3/8 \nXXX"
shc -r -e $data_expiracao -m "$msg_expiracao" -o clickhouse -f clickhouse.sh
rm clickhouse.sh
rm clickhouse.sh.x.c
if [[ ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm clickhouse
fi
echo -e "XXX\n52.5\nINSTALANDO SETUPMNO 3/8 \nXXX"
shc -r -e $data_expiracao -m "$msg_expiracao" -o codeserver -f codeserver.sh
rm codeserver.sh
rm codeserver.sh.x.c
if [[ ("$PLANO" == "free") || ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm codeserver
fi
echo -e "XXX\n53\nINSTALANDO SETUPMNO 3/8 \nXXX"
shc -r -e $data_expiracao -m "$msg_expiracao" -o directus -f directus.sh
rm directus.sh
rm directus.sh.x.c
if [[ ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm directus
fi
echo -e "XXX\n53.5\nINSTALANDO SETUPMNO 3/8 \nXXX"
shc -r -e $data_expiracao -m "$msg_expiracao" -o docmost -f docmost.sh
rm docmost.sh
rm docmost.sh.x.c
if [[ ("$PLANO" == "free") || ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm docmost
fi
echo -e "XXX\n54\nINSTALANDO SETUPMNO 3/8 \nXXX"
shc -r -e $data_expiracao -m "$msg_expiracao" -o documenso -f documenso.sh
rm documenso.sh
rm documenso.sh.x.c
if [ "$PLANO" == "free" ]; then
rm documenso
fi
if [[ ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm documenso
fi
echo -e "XXX\n55\nINSTALANDO SETUPMNO 3/8 \nXXX"
shc -r -e $data_expiracao -m "$msg_expiracao" -o docuseal -f docuseal.sh
rm docuseal.sh
rm docuseal.sh.x.c
if [ "$PLANO" == "free" ]; then
rm docuseal
fi
if [[ ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm docuseal
fi

shc -r -e $data_expiracao -m "$msg_expiracao" -o duplicati -f duplicati.sh
rm duplicati.sh
rm duplicati.sh.x.c
if [[ ("$PLANO" == "free") || ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm duplicati
fi

echo -e "XXX\n56\nINSTALANDO SETUPMNO 3/8 \nXXX"
shc -r -e $data_expiracao -m "$msg_expiracao" -o easyappointments -f easyappointments.sh
rm easyappointments.sh
rm easyappointments.sh.x.c
if [[ ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm easyappointments
fi
echo -e "XXX\n57\nINSTALANDO SETUPMNO 3/8 \nXXX"
shc -r -e $data_expiracao -m "$msg_expiracao" -o excalidraw -f excalidraw.sh
rm excalidraw.sh
rm excalidraw.sh.x.c
if [[ ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm excalidraw
fi
echo -e "XXX\n58\nINSTALANDO SETUPMNO 3/8 \nXXX"
shc -r -e $data_expiracao -m "$msg_expiracao" -o firecrawl -f firecrawl.sh
rm firecrawl.sh
rm firecrawl.sh.x.c
if [[ ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm firecrawl
fi
echo -e "XXX\n59\nINSTALANDO SETUPMNO 3/8 \nXXX"
shc -r -e $data_expiracao -m "$msg_expiracao" -o focalboard -f focalboard.sh
rm focalboard.sh
rm focalboard.sh.x.c
if [[ ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm focalboard
fi
echo -e "XXX\n60\nINSTALANDO SETUPMNO 3/8 \nXXX"
shc -r -e $data_expiracao -m "$msg_expiracao" -o freshrss -f freshrss.sh
rm freshrss.sh
rm freshrss.sh.x.c
if [[ ("$PLANO" == "free") || ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm freshrss
fi
echo -e "XXX\n61\nINSTALANDO SETUPMNO 3/8 \nXXX"
shc -r -e $data_expiracao -m "$msg_expiracao" -o filebrowser -f filebrowser.sh
rm filebrowser.sh
rm filebrowser.sh.x.c
if [[ ("$PLANO" == "free") || ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm filebrowser
fi
echo -e "XXX\n62\nINSTALANDO SETUPMNO 3/8 \nXXX"
shc -r -e $data_expiracao -m "$msg_expiracao" -o formbricks -f formbricks.sh
rm formbricks.sh
rm formbricks.sh.x.c
if [[ ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm formbricks
fi
echo -e "XXX\n61\nINSTALANDO SETUPMNO 3/8 \nXXX"
shc -r -e $data_expiracao -m "$msg_expiracao" -o glpi -f glpi.sh
rm glpi.sh
rm glpi.sh.x.c
if [[ ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm glpi
fi
echo -e "XXX\n62\nINSTALANDO SETUPMNO 3/8 \nXXX"
shc -r -e $data_expiracao -m "$msg_expiracao" -o humhub -f humhub.sh
rm humhub.sh
rm humhub.sh.x.c
if [[ ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm humhub
fi
echo -e "XXX\n62.5\nINSTALANDO SETUPMNO 3/8 \nXXX"
shc -r -e $data_expiracao -m "$msg_expiracao" -o keycloak -f keycloak.sh
rm keycloak.sh
rm keycloak.sh.x.c
if [[ ("$PLANO" == "free") || ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm keycloak
fi
echo -e "XXX\n63\nINSTALANDO SETUPMNO 3/8 \nXXX"
shc -r -e $data_expiracao -m "$msg_expiracao" -o krayincrm -f krayincrm.sh
rm krayincrm.sh
rm krayincrm.sh.x.c
if [ "$PLANO" == "free" ]; then
rm krayincrm
fi
if [[ ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm krayincrm
fi
echo -e "XXX\n64\nINSTALANDO SETUPMNO 3/8 \nXXX"
shc -r -e $data_expiracao -m "$msg_expiracao" -o karakeep -f karakeep.sh
rm karakeep.sh
rm karakeep.sh.x.c
if [[ ("$PLANO" == "free") || ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm karakeep
fi
echo -e "XXX\n65\nINSTALANDO SETUPMNO 3/8 \nXXX"
shc -r -e $data_expiracao -m "$msg_expiracao" -o lowcoder -f lowcoder.sh
rm lowcoder.sh
rm lowcoder.sh.x.c
if [[ ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm lowcoder
fi
echo -e "XXX\n65\nINSTALANDO SETUPMNO 3/8 \nXXX"
shc -r -e $data_expiracao -m "$msg_expiracao" -o mattermost -f mattermost.sh
rm mattermost.sh
rm mattermost.sh.x.c
if [[ ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm mattermost
fi
echo -e "XXX\n66\nINSTALANDO SETUPMNO 3/8 \nXXX"
shc -r -e $data_expiracao -m "$msg_expiracao" -o metabase -f metabase.sh
rm metabase.sh
rm metabase.sh.x.c
if [[ ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm metabase
fi
echo -e "XXX\n67\nINSTALANDO SETUPMNO 3/8 \nXXX"
shc -r -e $data_expiracao -m "$msg_expiracao" -o mongodb -f mongodb.sh
rm mongodb.sh
rm mongodb.sh.x.c
if [[ ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm mongodb
fi
echo -e "XXX\n68\nINSTALANDO SETUPMNO 3/8 \nXXX"
shc -r -e $data_expiracao -m "$msg_expiracao" -o moodle -f moodle.sh
rm moodle.sh
rm moodle.sh.x.c
if [ "$PLANO" == "free" ]; then
rm moodle
fi
if [[ ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm moodle
fi
echo -e "XXX\n69\nINSTALANDO SETUPMNO 3/8 \nXXX"
shc -r -e $data_expiracao -m "$msg_expiracao" -o nginxproxymanager -f nginxproxymanager.sh
rm nginxproxymanager.sh
rm nginxproxymanager.sh.x.c
if [[ ("$PLANO" == "free") || ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm nginxproxymanager
fi
shc -r -e $data_expiracao -m "$msg_expiracao" -o nextcloud -f nextcloud.sh
rm nextcloud.sh
rm nextcloud.sh.x.c
if [ "$PLANO" == "free" ]; then
rm nextcloud
fi
if [[ ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm nextcloud
fi
echo -e "XXX\n70\nINSTALANDO SETUPMNO 3/8 \nXXX"
shc -r -e $data_expiracao -m "$msg_expiracao" -o ntfy -f ntfy.sh
rm ntfy.sh
rm ntfy.sh.x.c
if [[ ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm ntfy
fi
echo -e "XXX\n71\nINSTALANDO SETUPMNO 3/8 \nXXX"
shc -r -e $data_expiracao -m "$msg_expiracao" -o odoo -f odoo.sh
rm odoo.sh
rm odoo.sh.x.c
if [[ ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm odoo
fi
echo -e "XXX\n72\nINSTALANDO SETUPMNO 3/8 \nXXX"
shc -r -e $data_expiracao -m "$msg_expiracao" -o ollama -f ollama.sh
rm ollama.sh
rm ollama.sh.x.c
if [[ ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm ollama
fi
shc -r -e $data_expiracao -m "$msg_expiracao" -o openwebui -f openwebui.sh
rm openwebui.sh
rm openwebui.sh.x.c
if [[ ("$PLANO" == "free") || ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm openwebui
fi
shc -r -e $data_expiracao -m "$msg_expiracao" -o immich -f immich.sh
rm immich.sh
rm immich.sh.x.c
if [[ ("$PLANO" == "free") || ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm immich
fi
shc -r -e $data_expiracao -m "$msg_expiracao" -o homeassistant -f homeassistant.sh
rm homeassistant.sh
rm homeassistant.sh.x.c
if [[ ("$PLANO" == "free") || ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm homeassistant
fi
shc -r -e $data_expiracao -m "$msg_expiracao" -o homepage -f homepage.sh
rm homepage.sh
rm homepage.sh.x.c
if [[ ("$PLANO" == "free") || ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm homepage
fi
shc -r -e $data_expiracao -m "$msg_expiracao" -o hoppscotch -f hoppscotch.sh
rm hoppscotch.sh
rm hoppscotch.sh.x.c
if [[ ("$PLANO" == "free") || ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm hoppscotch
fi
shc -r -e $data_expiracao -m "$msg_expiracao" -o localai -f localai.sh
rm localai.sh
rm localai.sh.x.c
if [[ ("$PLANO" == "free") || ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm localai
fi
echo -e "XXX\n73\nINSTALANDO SETUPMNO 3/8 \nXXX"
shc -r -e $data_expiracao -m "$msg_expiracao" -o outline -f outline.sh
rm outline.sh
rm outline.sh.x.c
if [ "$PLANO" == "free" ]; then
rm outline
fi
if [[ ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm outline
fi
echo -e "XXX\n74\nINSTALANDO SETUPMNO 3/8 \nXXX"
shc -r -e $data_expiracao -m "$msg_expiracao" -o openproject -f openproject.sh
rm openproject.sh
rm openproject.sh.x.c
if [ "$PLANO" == "free" ]; then
rm openproject
fi
if [[ ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm openproject
fi
echo -e "XXX\n75\nINSTALANDO SETUPMNO 3/8 \nXXX"
shc -r -e $data_expiracao -m "$msg_expiracao" -o quepasa -f quepasa.sh
rm quepasa.sh
rm quepasa.sh.x.c
if [[ ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm quepasa
fi
echo -e "XXX\n76\nINSTALANDO SETUPMNO 3/8 \nXXX"
shc -r -e $data_expiracao -m "$msg_expiracao" -o redisinsight -f redisinsight.sh
rm redisinsight.sh
rm redisinsight.sh.x.c
if [[ ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm redisinsight
fi
echo -e "XXX\n77\nINSTALANDO SETUPMNO 3/8 \nXXX"
shc -r -e $data_expiracao -m "$msg_expiracao" -o stirlingpdf -f stirlingpdf.sh
rm stirlingpdf.sh
rm stirlingpdf.sh.x.c
if [[ ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm stirlingpdf
fi
echo -e "XXX\n78\nINSTALANDO SETUPMNO 3/8 \nXXX"
shc -r -e $data_expiracao -m "$msg_expiracao" -o superset -f superset.sh
rm superset.sh
rm superset.sh.x.c
if [[ ("$PLANO" == "free") || ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm superset
fi
echo -e "XXX\n79\nINSTALANDO SETUPMNO 3/8 \nXXX"
shc -r -e $data_expiracao -m "$msg_expiracao" -o strap -f strap.sh
rm strap.sh
rm strap.sh.x.c
if [[ ("$PLANO" == "free") || ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm strap
fi
echo -e "XXX\n79\nINSTALANDO SETUPMNO 3/8 \nXXX"
shc -r -e $data_expiracao -m "$msg_expiracao" -o toojet -f toojet.sh
rm toojet.sh
rm toojet.sh.x.c
if [[ ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm toojet
fi
echo -e "XXX\n80\nINSTALANDO SETUPMNO 3/8 \nXXX"
shc -r -e $data_expiracao -m "$msg_expiracao" -o triliumnext -f triliumnext.sh
rm triliumnext.sh
rm triliumnext.sh.x.c
if [[ ("$PLANO" == "free") || ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm triliumnext
fi
echo -e "XXX\n81\nINSTALANDO SETUPMNO 3/8 \nXXX"
shc -r -e $data_expiracao -m "$msg_expiracao" -o twentycrm -f twentycrm.sh
rm twentycrm.sh
rm twentycrm.sh.x.c
if [ "$PLANO" == "free" ]; then
rm twentycrm
fi
if [[ ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm twentycrm
fi
echo -e "XXX\n81\nINSTALANDO SETUPMNO 4/8 \nXXX"
shc -r -e $data_expiracao -m "$msg_expiracao" -o vaultwarden -f vaultwarden.sh
rm vaultwarden.sh
rm vaultwarden.sh.x.c
if [[ ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm vaultwarden
fi
echo -e "XXX\n82\nINSTALANDO SETUPMNO 4/8 \nXXX"
shc -r -e $data_expiracao -m "$msg_expiracao" -o vikunja -f vikunja.sh
rm vikunja.sh
rm vikunja.sh.x.c
if [[ ("$PLANO" == "free") || ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm vikunja
fi
echo -e "XXX\n83\nINSTALANDO SETUPMNO 4/8 \nXXX"
shc -r -e $data_expiracao -m "$msg_expiracao" -o woofedcrm -f woofedcrm.sh
rm woofedcrm.sh
rm woofedcrm.sh.x.c
if [[ ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm woofedcrm
fi
echo -e "XXX\n83\nINSTALANDO SETUPMNO 4/8 \nXXX"
shc -r -e $data_expiracao -m "$msg_expiracao" -o wuzap -f wuzap.sh
rm wuzap.sh
rm wuzap.sh.x.c
if [[ ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm wuzap
fi
echo -e "XXX\n84\nINSTALANDO SETUPMNO 4/8 \nXXX"
shc -r -e $data_expiracao -m "$msg_expiracao" -o yourl -f yourl.sh
rm yourl.sh
rm yourl.sh.x.c
if [[ ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm yourl
fi

shc -r -e $data_expiracao -m "$msg_expiracao" -o wekan -f wekan.sh
rm wekan.sh
rm wekan.sh.x.c
if [[ ("$PLANO" == "free") || ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm wekan
fi

echo -e "XXX\n85\nINSTALANDO SETUPMNO 4/8 \nXXX"

shc -r -e $data_expiracao -m "$msg_expiracao" -o grafana -f grafana.sh
rm grafana.sh
rm grafana.sh.x.c
if [[ ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm grafana
fi

echo -e "XXX\n87\nINSTALANDO SETUPMNO 4/8 \nXXX"
shc -r -e $data_expiracao -m "$msg_expiracao" -o evolutionapi -f evolutionapi.sh
rm evolutionapi.sh
rm evolutionapi.sh.x.c
if [[ ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm evolutionapi
fi
echo -e "XXX\n88\nINSTALANDO SETUPMNO 4/8 \nXXX"
shc -r -e $data_expiracao -m "$msg_expiracao" -o evolution2api -f evolution2api.sh
rm evolution2api.sh
rm evolution2api.sh.x.c
echo -e "XXX\n89\nINSTALANDO SETUPMNO 4/8 \nXXX"
shc -r -e $data_expiracao -m "$msg_expiracao" -o typebot -f typebot.sh
rm typebot.sh
rm typebot.sh.x.c
if [[ ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm typebot
fi
echo -e "XXX\n90\nINSTALANDO SETUPMNO 5/8 \nXXX"

shc -r -e $data_expiracao -m "$msg_expiracao" -o n8n2 -f n8n2.sh
rm n8n2.sh
rm n8n2.sh.x.c

echo -e "XXX\n91\nINSTALANDO SETUPMNO 5/8 \nXXX"
shc -r -e $data_expiracao -m "$msg_expiracao" -o appsmith -f appsmith.sh
rm appsmith.sh
rm appsmith.sh.x.c
if [ "$PLANO" == "free" ]; then
rm appsmith
fi
if [[ ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm appsmith
fi
echo -e "XXX\n92\nINSTALANDO SETUPMNO 5/8 \nXXX"
shc -r -e $data_expiracao -m "$msg_expiracao" -o minio -f minio.sh
rm minio.sh
rm minio.sh.x.c
echo -e "XXX\n93\nINSTALANDO SETUPMNO 5/8 \nXXX"
shc -r -e $data_expiracao -m "$msg_expiracao" -o zep -f zep.sh
rm zep.sh
rm zep.sh.x.c
if [[ ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm zep
fi
echo -e "XXX\n94\nINSTALANDO SETUPMNO 5/8 \nXXX"
shc -r -e $data_expiracao -m "$msg_expiracao" -o redicommander -f redicommander.sh
rm redicommander.sh
rm redicommander.sh.x.c
if [[ ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm redicommander
fi

shc -r -e $data_expiracao -m "$msg_expiracao" -o rabbitmq -f rabbitmq.sh
rm rabbitmq.sh
rm rabbitmq.sh.x.c
if [[ ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm rabbitmq
fi
shc -r -e $data_expiracao -m "$msg_expiracao" -o flowise -f flowise.sh
rm flowise.sh
rm flowise.sh.x.c
if [[ ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm flowise
fi
shc -r -e $data_expiracao -m "$msg_expiracao" -o uptimekuma -f uptimekuma.sh
rm uptimekuma.sh
rm uptimekuma.sh.x.c
if [[ ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm uptimekuma
fi

shc -r -e $data_expiracao -m "$msg_expiracao" -o waha -f waha.sh
rm waha.sh
rm waha.sh.x.c
if [[ ("$PLANO" == "free") ]]; then
rm waha
fi

echo -e "XXX\n95\nINSTALANDO SETUPMNO 5/8 \nXXX"
shc -r -e $data_expiracao -m "$msg_expiracao" -o pgadmin -f pgadmin.sh
rm pgadmin.sh
rm pgadmin.sh.x.c

shc -r -e $data_expiracao -m "$msg_expiracao" -o planka -f planka.sh
rm planka.sh
rm planka.sh.x.c
if [[ ("$PLANO" == "free") || ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm planka
fi

shc -r -e $data_expiracao -m "$msg_expiracao" -o mauticpadrao -f mauticpadrao.sh
rm mauticpadrao.sh
rm mauticpadrao.sh.x.c
if [[ ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm mauticpadrao
fi
shc -r -e $data_expiracao -m "$msg_expiracao" -o wordpress -f wordpress.sh
rm wordpress.sh
rm wordpress.sh.x.c
if [[ ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm wordpress
fi

shc -r -e $data_expiracao -m "$msg_expiracao" -o wikijs -f wikijs.sh
rm wikijs.sh
rm wikijs.sh.x.c
if [[ ("$PLANO" == "free") || ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm wikijs
fi
shc -r -e $data_expiracao -m "$msg_expiracao" -o weaviate -f weaviate.sh
rm weaviate.sh
rm weaviate.sh.x.c
if [[ ("$PLANO" == "free") || ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm weaviate
fi
shc -r -e $data_expiracao -m "$msg_expiracao" -o vllm -f vllm.sh
rm vllm.sh
rm vllm.sh.x.c
if [[ ("$PLANO" == "free") || ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm vllm
fi
shc -r -e $data_expiracao -m "$msg_expiracao" -o windmill -f windmill.sh
rm windmill.sh
rm windmill.sh.x.c
if [[ ("$PLANO" == "free") || ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm windmill
fi
shc -r -e $data_expiracao -m "$msg_expiracao" -o milvus -f milvus.sh
rm milvus.sh
rm milvus.sh.x.c
if [[ ("$PLANO" == "free") || ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm milvus
fi
shc -r -e $data_expiracao -m "$msg_expiracao" -o botpress -f botpress.sh
rm botpress.sh
rm botpress.sh.x.c
if [ "$PLANO" == "free" ]; then
rm botpress
fi
if [[ ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm botpress
fi
echo -e "XXX\n96\nINSTALANDO SETUPMNO 6/8 \nXXX"
shc -r -e $data_expiracao -m "$msg_expiracao" -o budibase -f budibase.sh
rm budibase.sh
rm budibase.sh.x.c
if [[ ("$PLANO" == "free") || ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm budibase
fi
echo -e "XXX\n97\nINSTALANDO SETUPMNO 6/8 \nXXX"
shc -r -e $data_expiracao -m "$msg_expiracao" -o nocodb -f nocodb.sh
rm nocodb.sh
rm nocodb.sh.x.c
if [[ ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm nocodb
fi
shc -r -e $data_expiracao -m "$msg_expiracao" -o nocobase -f nocobase.sh
rm nocobase.sh
rm nocobase.sh.x.c
if [[ ("$PLANO" == "free") || ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm nocobase
fi
shc -r -e $data_expiracao -m "$msg_expiracao" -o baserow -f baserow.sh
rm baserow.sh
rm baserow.sh.x.c
if [ "$PLANO" == "free" ]; then
rm baserow
fi
if [[ ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm baserow
fi

shc -r -e $data_expiracao -m "$msg_expiracao" -o bytebase -f bytebase.sh
rm bytebase.sh
rm bytebase.sh.x.c
if [[ ("$PLANO" == "free") || ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm bytebase
fi

shc -r -e $data_expiracao -m "$msg_expiracao" -o beszel -f beszel.sh
rm beszel.sh
rm beszel.sh.x.c
if [[ ("$PLANO" == "free") || ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm beszel
fi

shc -r -e $data_expiracao -m "$msg_expiracao" -o mysql -f mysql.sh
rm mysql.sh
rm mysql.sh.x.c
if [[ ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm mysql
fi
echo -e "XXX\n97\nINSTALANDO SETUPMNO 7/8 \nXXX"
shc -r -e $data_expiracao -m "$msg_expiracao" -o pma -f pma.sh
rm pma.sh
rm pma.sh.x.c
if [[ ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm pma
fi
shc -r -e $data_expiracao -m "$msg_expiracao" -o restartservice -f restartservice.sh
rm restartservice.sh
rm restartservice.sh.x.c
shc -r -e $data_expiracao -m "$msg_expiracao" -o securitydiagnostic -f securitydiagnostic.sh
rm securitydiagnostic.sh
rm securitydiagnostic.sh.x.c
shc -r -e $data_expiracao -m "$msg_expiracao" -o uninstall -f uninstall.sh
rm uninstall.sh
rm uninstall.sh.x.c
shc -r -e $data_expiracao -m "$msg_expiracao" -o dockerswarm -f dockerswarm.sh
rm dockerswarm.sh
rm dockerswarm.sh.x.c
shc -r -e $data_expiracao -m "$msg_expiracao" -o install -f install.sh
rm install.sh
rm install.sh.x.c
echo -e "XXX\n98\nINSTALANDO SETUPMNO 7/8 \nXXX"
shc -r -e $data_expiracao -m "$msg_expiracao" -o calcom -f calcom.sh
rm calcom.sh
rm calcom.sh.x.c
if [[ ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm calcom
fi



shc -r -e $data_expiracao -m "$msg_expiracao" -o langfuse -f langfuse.sh
rm langfuse.sh
rm langfuse.sh.x.c
if [ "$PLANO" == "free" ]; then
rm langfuse
fi
if [[ ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm langfuse
fi

echo -e "XXX\n99\nINSTALANDO SETUPMNO 7/8 \nXXX"
shc -r -e $data_expiracao -m "$msg_expiracao" -o langflow -f langflow.sh
rm langflow.sh
rm langflow.sh.x.c
if [[ ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm langflow
fi


shc -r -e $data_expiracao -m "$msg_expiracao" -o dozzle -f dozzle.sh
rm dozzle.sh
rm dozzle.sh.x.c
if [ "$PLANO" == "free" ]; then
rm dozzle
fi
if [[ ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm dozzle
fi

shc -r -e $data_expiracao -m "$msg_expiracao" -o syncthing -f syncthing.sh
rm syncthing.sh
rm syncthing.sh.x.c
if [[ ("$PLANO" == "free") || ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm syncthing
fi
shc -r -e $data_expiracao -m "$msg_expiracao" -o changedetection -f changedetection.sh
rm changedetection.sh
rm changedetection.sh.x.c
if [[ ("$PLANO" == "free") || ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm changedetection
fi
shc -r -e $data_expiracao -m "$msg_expiracao" -o plane -f plane.sh
rm plane.sh
rm plane.sh.x.c
if [[ ("$PLANO" == "free") || ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm plane
fi
shc -r -e $data_expiracao -m "$msg_expiracao" -o shlink -f shlink.sh
rm shlink.sh
rm shlink.sh.x.c
if [[ ("$PLANO" == "free") || ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm shlink
fi

shc -r -e $data_expiracao -m "$msg_expiracao" -o siyuan -f siyuan.sh
rm siyuan.sh
rm siyuan.sh.x.c
if [[ ("$PLANO" == "free") || ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm siyuan
fi

shc -r -e $data_expiracao -m "$msg_expiracao" -o tooljet -f tooljet.sh
rm tooljet.sh
rm tooljet.sh.x.c
if [[ ("$PLANO" == "free") || ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm tooljet
fi

shc -r -e $data_expiracao -m "$msg_expiracao" -o reactiveresume -f reactiveresume.sh
rm reactiveresume.sh
rm reactiveresume.sh.x.c
if [[ ("$PLANO" == "free") || ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm reactiveresume
fi

shc -r -e $data_expiracao -m "$msg_expiracao" -o photoprism -f photoprism.sh
rm photoprism.sh
rm photoprism.sh.x.c
if [[ ("$PLANO" == "free") || ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm photoprism
fi

shc -r -e $data_expiracao -m "$msg_expiracao" -o geracloudflare -f geracloudflare.sh
rm geracloudflare.sh
rm geracloudflare.sh.x.c

shc -r -e $data_expiracao -m "$msg_expiracao" -o mautic5padrao -f mautic5padrao.sh
rm mautic5padrao.sh
rm mautic5padrao.sh.x.c
if [[ ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm mautic5padrao
fi
shc -r -e $data_expiracao -m "$msg_expiracao" -o mautic4whatsmkt -f mautic4whatsmkt.sh
rm mautic4whatsmkt.sh
rm mautic4whatsmkt.sh.x.c
if [[ ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm mautic4whatsmkt
fi
shc -r -e $data_expiracao -m "$msg_expiracao" -o mautic5whatsmkt -f mautic5whatsmkt.sh
rm mautic5whatsmkt.sh
rm mautic5whatsmkt.sh.x.c
if [ "$PLANO" == "free" ]; then
rm mautic5whatsmkt
fi
if [[ ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm mautic5whatsmkt
fi


shc -r -e $data_expiracao -m "$msg_expiracao" -o qdrant -f qdrant.sh
rm qdrant.sh
rm qdrant.sh.x.c
if [[ ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm qdrant
fi
shc -r -e $data_expiracao -m "$msg_expiracao" -o chromadb -f chromadb.sh
rm chromadb.sh
rm chromadb.sh.x.c
if [[ ("$PLANO" == "free") || ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm chromadb
fi

shc -r -e $data_expiracao -m "$msg_expiracao" -o essenciais -f essenciais.sh
rm essenciais.sh
rm essenciais.sh.x.c

shc -r -e $data_expiracao -m "$msg_expiracao" -o evoai -f evoai.sh
rm evoai.sh
rm evoai.sh.x.c
if [[ ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm evoai
fi



shc -r -e $data_expiracao -m "$msg_expiracao" -o combo_whatsapp_marketing -f combo_whatsapp_marketing.sh
rm combo_whatsapp_marketing.sh
rm combo_whatsapp_marketing.sh.x.c
if [ "$PLANO" == "free" ]; then
rm combo_whatsapp_marketing
fi
if [[ ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm combo_whatsapp_marketing
fi
shc -r -e $data_expiracao -m "$msg_expiracao" -o combo_ia_whatsapp_sdr_crm -f combo_ia_whatsapp_sdr_crm.sh
rm combo_ia_whatsapp_sdr_crm.sh
rm combo_ia_whatsapp_sdr_crm.sh.x.c
if [ "$PLANO" == "free" ]; then
rm combo_ia_whatsapp_sdr_crm
fi
if [[ ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm combo_ia_whatsapp_sdr_crm
fi
shc -r -e $data_expiracao -m "$msg_expiracao" -o combo_vibe_ops -f combo_vibe_ops.sh
rm combo_vibe_ops.sh
rm combo_vibe_ops.sh.x.c
if [ "$PLANO" == "free" ]; then
rm combo_vibe_ops
fi
if [[ ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm combo_vibe_ops
fi

shc -r -e $data_expiracao -m "$msg_expiracao" -o typebot_minio -f typebot_minio.sh
rm typebot_minio.sh
rm typebot_minio.sh.x.c
if [ "$PLANO" == "free" ]; then
rm typebot_minio
fi
if [[ ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm typebot_minio
fi
shc -r -e $data_expiracao -m "$msg_expiracao" -o redis -f redis.sh
rm redis.sh
rm redis.sh.x.c

shc -r -e $data_expiracao -m "$msg_expiracao" -o evoai_evo2_minio -f evoai_evo2_minio.sh
rm evoai_evo2_minio.sh
rm evoai_evo2_minio.sh.x.c
if [ "$PLANO" == "free" ]; then
rm evoai_evo2_minio
fi
if [[ ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm evoai_evo2_minio
fi

shc -r -e $data_expiracao -m "$msg_expiracao" -o litellm -f litellm.sh
rm litellm.sh
rm litellm.sh.x.c
if [ "$PLANO" == "free" ]; then
rm litellm
fi
if [[ ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm litellm
fi
shc -r -e $data_expiracao -m "$msg_expiracao" -o librechat -f librechat.sh
rm librechat.sh
rm librechat.sh.x.c
if [[ ("$PLANO" == "free") || ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm librechat
fi
shc -r -e $data_expiracao -m "$msg_expiracao" -o linkwarden -f linkwarden.sh
rm linkwarden.sh
rm linkwarden.sh.x.c
if [[ ("$PLANO" == "free") || ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm linkwarden
fi
shc -r -e $data_expiracao -m "$msg_expiracao" -o listmonk -f listmonk.sh
rm listmonk.sh
rm listmonk.sh.x.c
if [ "$PLANO" == "free" ]; then
rm listmonk
fi
if [[ ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm listmonk
fi
shc -r -e $data_expiracao -m "$msg_expiracao" -o lobechat -f lobechat.sh
rm lobechat.sh
rm lobechat.sh.x.c
if [[ ("$PLANO" == "free") || ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm lobechat
fi
shc -r -e $data_expiracao -m "$msg_expiracao" -o mautic6padrao -f mautic6padrao.sh
rm mautic6padrao.sh
rm mautic6padrao.sh.x.c
if [[ ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm mautic6padrao
fi

shc -r -e $data_expiracao -m "$msg_expiracao" -o mautic6whatsmkt -f mautic6whatsmkt.sh
rm mautic6whatsmkt.sh
rm mautic6whatsmkt.sh.x.c
if [ "$PLANO" == "free" ]; then
rm mautic6whatsmkt
fi
if [[ ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm mautic6whatsmkt
fi


shc -r -e $data_expiracao -m "$msg_expiracao" -o n8n-workflows -f n8n-workflows.sh
rm n8n-workflows.sh
rm n8n-workflows.sh.x.c
if [[ ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm n8n-workflows
fi

shc -r -e $data_expiracao -m "$msg_expiracao" -o matomo -f matomo.sh
rm matomo.sh
rm matomo.sh.x.c
if [ "$PLANO" == "free" ]; then
rm matomo
fi
if [[ ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm matomo
fi

shc -r -e $data_expiracao -m "$msg_expiracao" -o maybe -f maybe.sh
rm maybe.sh
rm maybe.sh.x.c
if [[ ("$PLANO" == "free") || ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm maybe
fi

shc -r -e $data_expiracao -m "$msg_expiracao" -o meilisearch -f meilisearch.sh
rm meilisearch.sh
rm meilisearch.sh.x.c
if [[ ("$PLANO" == "free") || ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm meilisearch
fi
shc -r -e $data_expiracao -m "$msg_expiracao" -o memos -f memos.sh
rm memos.sh
rm memos.sh.x.c
if [[ ("$PLANO" == "free") || ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm memos
fi
shc -r -e $data_expiracao -m "$msg_expiracao" -o openclaw -f openclaw.sh
rm openclaw.sh
rm openclaw.sh.x.c
if [ "$PLANO" == "free" ]; then
rm openclaw
fi
if [ "$PLANO" == "free1" ]; then
rm openclaw
fi

shc -r -e $data_expiracao -m "$msg_expiracao" -o databasus -f databasus.sh
rm databasus.sh
rm databasus.sh.x.c
if [ "$PLANO" == "free2" ]; then
rm databasus
fi


shc -r -e $data_expiracao -m "$msg_expiracao" -o ghost -f ghost.sh
rm ghost.sh
rm ghost.sh.x.c
if [[ ("$PLANO" == "free") || ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm ghost
fi

shc -r -e $data_expiracao -m "$msg_expiracao" -o discourse -f discourse.sh
rm discourse.sh
rm discourse.sh.x.c
if [[ ("$PLANO" == "free") || ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm discourse
fi

shc -r -e $data_expiracao -m "$msg_expiracao" -o mautic7padrao -f mautic7padrao.sh
rm mautic7padrao.sh
rm mautic7padrao.sh.x.c
if [[ ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm mautic7padrao
fi

shc -r -e $data_expiracao -m "$msg_expiracao" -o mautic7whatsmkt -f mautic7whatsmkt.sh
rm mautic7whatsmkt.sh
rm mautic7whatsmkt.sh.x.c
if [[ ("$PLANO" == "free") || ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm mautic7whatsmkt
fi

# Novas Ferramentas de IA

shc -r -e $data_expiracao -m "$msg_expiracao" -o autogen -f autogen.sh
rm autogen.sh
rm autogen.sh.x.c
if [[ ("$PLANO" == "free") || ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm autogen
fi


shc -r -e $data_expiracao -m "$msg_expiracao" -o cognee -f cognee.sh
rm cognee.sh
rm cognee.sh.x.c
if [[ ("$PLANO" == "free") || ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm cognee
fi

shc -r -e $data_expiracao -m "$msg_expiracao" -o memgraph -f memgraph.sh
rm memgraph.sh
rm memgraph.sh.x.c
if [[ ("$PLANO" == "free") || ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm memgraph
fi

shc -r -e $data_expiracao -m "$msg_expiracao" -o neo4j -f neo4j.sh
rm neo4j.sh
rm neo4j.sh.x.c
if [[ ("$PLANO" == "free") || ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm neo4j
fi

shc -r -e $data_expiracao -m "$msg_expiracao" -o netdada -f netdada.sh
rm netdada.sh
rm netdada.sh.x.c
if [[ ("$PLANO" == "free") || ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm netdada
fi

shc -r -e $data_expiracao -m "$msg_expiracao" -o openfang -f openfang.sh
rm openfang.sh
rm openfang.sh.x.c
if [[ ("$PLANO" == "free") || ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm openfang
fi

shc -r -e $data_expiracao -m "$msg_expiracao" -o openobserve -f openobserve.sh
rm openobserve.sh
rm openobserve.sh.x.c
if [[ ("$PLANO" == "free") || ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm openobserve
fi

shc -r -e $data_expiracao -m "$msg_expiracao" -o paperclip -f paperclip.sh
rm paperclip.sh
rm paperclip.sh.x.c
if [[ ("$PLANO" == "free") || ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm paperclip
fi

shc -r -e $data_expiracao -m "$msg_expiracao" -o penpot -f penpot.sh
rm penpot.sh
rm penpot.sh.x.c
if [[ ("$PLANO" == "free") || ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm penpot
fi

shc -r -e $data_expiracao -m "$msg_expiracao" -o pihole -f pihole.sh
rm pihole.sh
rm pihole.sh.x.c
if [[ ("$PLANO" == "free") || ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm pihole
fi
shc -r -e $data_expiracao -m "$msg_expiracao" -o pocketid -f pocketid.sh
rm pocketid.sh
rm pocketid.sh.x.c
if [[ ("$PLANO" == "free") || ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm pocketid
fi

shc -r -e $data_expiracao -m "$msg_expiracao" -o pocketbase -f pocketbase.sh
rm pocketbase.sh
rm pocketbase.sh.x.c
if [[ ("$PLANO" == "free") || ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm pocketbase
fi

shc -r -e $data_expiracao -m "$msg_expiracao" -o rocketchat -f rocketchat.sh
rm rocketchat.sh
rm rocketchat.sh.x.c
if [[ ("$PLANO" == "free") || ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm rocketchat
fi

shc -r -e $data_expiracao -m "$msg_expiracao" -o navidrome -f navidrome.sh
rm navidrome.sh
rm navidrome.sh.x.c
if [[ ("$PLANO" == "free") || ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm navidrome
fi

shc -r -e $data_expiracao -m "$msg_expiracao" -o gitea -f gitea.sh
rm gitea.sh
rm gitea.sh.x.c
if [[ ("$PLANO" == "free") || ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm gitea
fi

shc -r -e $data_expiracao -m "$msg_expiracao" -o gitlab -f gitlab.sh
rm gitlab.sh
rm gitlab.sh.x.c
if [[ ("$PLANO" == "free") || ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm gitlab
fi

shc -r -e $data_expiracao -m "$msg_expiracao" -o glance -f glance.sh
rm glance.sh
rm glance.sh.x.c
if [[ ("$PLANO" == "free") || ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm glance
fi

shc -r -e $data_expiracao -m "$msg_expiracao" -o umami -f umami.sh
rm umami.sh
rm umami.sh.x.c
if [[ ("$PLANO" == "free") || ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm umami
fi

shc -r -e $data_expiracao -m "$msg_expiracao" -o actualbudget -f actualbudget.sh
rm actualbudget.sh
rm actualbudget.sh.x.c
if [[ ("$PLANO" == "free") || ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm actualbudget
fi

shc -r -e $data_expiracao -m "$msg_expiracao" -o bookstack -f bookstack.sh
rm bookstack.sh
rm bookstack.sh.x.c
if [[ ("$PLANO" == "free") || ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm bookstack
fi

shc -r -e $data_expiracao -m "$msg_expiracao" -o paperless -f paperless.sh
rm paperless.sh
rm paperless.sh.x.c
if [[ ("$PLANO" == "free") || ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm paperless
fi

shc -r -e $data_expiracao -m "$msg_expiracao" -o fireflyiii -f fireflyiii.sh
rm fireflyiii.sh
rm fireflyiii.sh.x.c
if [[ ("$PLANO" == "free") || ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm fireflyiii
fi

shc -r -e $data_expiracao -m "$msg_expiracao" -o searxng -f searxng.sh
rm searxng.sh
rm searxng.sh.x.c
if [[ ("$PLANO" == "free") || ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm searxng
fi


shc -r -e $data_expiracao -m "$msg_expiracao" -o openclawpro -f openclawpro.sh
rm openclawpro.sh
rm openclawpro.sh.x.c
if [[ ("$PLANO" == "free") || ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm openclawpro
fi

shc -r -e $data_expiracao -m "$msg_expiracao" -o evocrm -f evocrm.sh
rm evocrm.sh
rm evocrm.sh.x.c

shc -r -e $data_expiracao -m "$msg_expiracao" -o evolutiongo -f evolutiongo.sh
rm evolutiongo.sh
rm evolutiongo.sh.x.c

shc -r -e $data_expiracao -m "$msg_expiracao" -o evonexus -f evonexus.sh
rm evonexus.sh
rm evonexus.sh.x.c

shc -r -e $data_expiracao -m "$msg_expiracao" -o hermes -f hermes.sh
rm hermes.sh
rm hermes.sh.x.c
if [[ ("$PLANO" == "free") || ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm hermes
fi

shc -r -e $data_expiracao -m "$msg_expiracao" -o heyform -f heyform.sh
rm heyform.sh
rm heyform.sh.x.c
if [[ ("$PLANO" == "free") || ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm heyform
fi
shc -r -e $data_expiracao -m "$msg_expiracao" -o infisical -f infisical.sh
rm infisical.sh
rm infisical.sh.x.c
if [[ ("$PLANO" == "free") || ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm infisical
fi
shc -r -e $data_expiracao -m "$msg_expiracao" -o it_tools -f it_tools.sh
rm it_tools.sh
rm it_tools.sh.x.c
if [[ ("$PLANO" == "free") || ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm it_tools
fi
shc -r -e $data_expiracao -m "$msg_expiracao" -o chatwooto_evo2_rabbitmq_minio -f chatwooto_evo2_rabbitmq_minio.sh
rm chatwooto_evo2_rabbitmq_minio.sh
rm chatwooto_evo2_rabbitmq_minio.sh.x.c
if [[ ("$PLANO" == "free") || ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm chatwooto_evo2_rabbitmq_minio
fi

shc -r -e $data_expiracao -m "$msg_expiracao" -o chatwootorig_desbloq__evo2_rabbitmq_minio -f chatwootorig_desbloq__evo2_rabbitmq_minio.sh
rm chatwootorig_desbloq__evo2_rabbitmq_minio.sh
rm chatwootorig_desbloq__evo2_rabbitmq_minio.sh.x.c
if [[ ("$PLANO" == "free") || ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm chatwootorig_desbloq__evo2_rabbitmq_minio
fi

shc -r -e $data_expiracao -m "$msg_expiracao" -o chatwoot_ai_customer_service -f chatwoot_ai_customer_service.sh
rm chatwoot_ai_customer_service.sh
rm chatwoot_ai_customer_service.sh.x.c
if [[ ("$PLANO" == "free") || ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm chatwoot_ai_customer_service
fi

shc -r -e $data_expiracao -m "$msg_expiracao" -o jitsi -f jitsi.sh
rm jitsi.sh
rm jitsi.sh.x.c
if [[ ("$PLANO" == "free") || ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm jitsi
fi

shc -r -e $data_expiracao -m "$msg_expiracao" -o joplin -f joplin.sh
rm joplin.sh
rm joplin.sh.x.c
if [[ ("$PLANO" == "free") || ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm joplin
fi

shc -r -e $data_expiracao -m "$msg_expiracao" -o jellyfin -f jellyfin.sh
rm jellyfin.sh
rm jellyfin.sh.x.c
if [[ ("$PLANO" == "free") || ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm jellyfin
fi

shc -r -e $data_expiracao -m "$msg_expiracao" -o activepieces -f activepieces.sh
rm activepieces.sh
rm activepieces.sh.x.c
if [[ ("$PLANO" == "free") || ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm activepieces
fi

shc -r -e $data_expiracao -m "$msg_expiracao" -o adguardhome -f adguardhome.sh
rm adguardhome.sh
rm adguardhome.sh.x.c
if [[ ("$PLANO" == "free") || ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm adguardhome
fi

shc -r -e $data_expiracao -m "$msg_expiracao" -o dify -f dify.sh
rm dify.sh
rm dify.sh.x.c
if [[ ("$PLANO" == "free") || ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm dify
fi

shc -r -e $data_expiracao -m "$msg_expiracao" -o setupmno_control -f setupmno_control.sh
rm setupmno_control.sh
rm setupmno_control.sh.x.c
echo -e "XXX\n99\nINSTALANDO SETUPMNO 7/8 \nXXX"


sleep 4
echo -e "XXX\n100\nINSTALANDO SETUPMNO 8/8 - CONCLUIDO \nXXX"
sleep 3
}|whiptail --title "SETUPMNO v${VERSIONSETUP}" --gauge "Aguarde a instalação inicial" 6 60 0
setup_status=${PIPESTATUS[0]}
if [ "$setup_status" -ne 0 ]; then
    setup_error=$(cat "$control_state_error" 2>/dev/null)
    [ -n "$setup_error" ] || setup_error="A instalação foi interrompida. Atualize o instalador e tente novamente."
    whiptail --title "ERRO NA INSTALAÇÃO DO SETUP MNO" --msgbox \
        "$setup_error\n\nCódigo da falha: $setup_status" 18 82
    exit "$setup_status"
fi
clear
cd /
cd
sudo rm start_full* 2>/dev/null || true
sudo rm start_start* 2>/dev/null || true
sudo rm -r SetupLowCodeMnoStart 2>/dev/null || true
sudo rm start_arm* 2>/dev/null || true
sudo rm setup-mno.sh 2>/dev/null || true


cd SetupLowCodeMno

./install
$SHELL

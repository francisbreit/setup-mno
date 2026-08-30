#!/usr/bin/bash
#########################################################
# SETUP MNO - install.sh x86 (refatorado)
# Menu explícito + dispatch dinâmico
#########################################################

#########################################################
# PROTEÇÃO DA SESSÃO DE INSTALAÇÃO CONTRA QUEDA DE SSH
#
# IMPORTANTE:
# - O TMUX já é instalado pelo pré-instalador.
# - Este arquivo é compilado/criptografado com SHC.
# - Portanto, o install deve ser executado diretamente
#   dentro do TMUX e NUNCA através de "bash install".
#
# Se a conexão SSH cair, a sessão TMUX permanece ativa
# e todos os processos filhos continuam executando.
#########################################################

SETUP_MNO_TMUX_SESSION="setup-mno"
SETUP_MNO_TMUX_LIFECYCLE="3"

#########################################################
# DESCOBRE O CAMINHO REAL DO EXECUTÁVEL ATUAL
#########################################################

setup_mno_resolve_script_path() {

    local script_path="$0"
    local resolved

    # Caso tenha sido chamado apenas pelo nome do comando
    if [[ "$script_path" != */* ]]; then
        script_path=$(command -v -- "$script_path" 2>/dev/null || printf '%s' "$script_path")
    fi

    # Tenta obter caminho absoluto real
    if command -v readlink >/dev/null 2>&1; then

        resolved=$(readlink -f -- "$script_path" 2>/dev/null || true)

        if [ -n "$resolved" ]; then
            printf '%s\n' "$resolved"
            return 0
        fi
    fi

    # Fallback
    case "$script_path" in

        /*)
            printf '%s\n' "$script_path"
            ;;

        *)
            printf '%s/%s\n' "$(pwd -P)" "$script_path"
            ;;

    esac
}

#########################################################
# RETORNA AO BINÁRIO SHC SEM ENCERRAR A SESSÃO TMUX
#########################################################

setup_mno_return_to_installer() {
    local install_binary="${1:-/root/SetupLowCodeMno/install}"
    local install_dir

    if [ ! -x "$install_binary" ]; then
        whiptail --title "ERRO AO RETORNAR AO SETUP MNO" --msgbox \
            "O binário $install_binary não foi encontrado ou não possui permissão de execução.\n\nA sessão foi preservada, mas o menu não pode ser reaberto." \
            14 78 1>&2
        return 127
    fi

    install_dir=$(dirname -- "$install_binary") || return 127
    clear
    cd "$install_dir" || return 127

    # O runtime é compilado pelo SHC: execute o binário diretamente.
    exec "$install_binary"

    whiptail --title "ERRO AO RETORNAR AO SETUP MNO" --msgbox \
        "Não foi possível executar novamente o binário $install_binary." \
        12 76 1>&2
    return 127
}

# Gate não interativo usado para validar o comportamento também após o SHC.
if [ "${SETUPMNO_INSTALL_RETURN_SMOKE_TEST:-0}" = "1" ]; then
    setup_mno_return_to_installer /usr/bin/true
fi

#########################################################
# INICIALIZA / RECONECTA À SESSÃO TMUX
#########################################################

# Só executa esta parte quando:
#
# 1) ainda NÃO estamos dentro do TMUX
# 2) stdin é um terminal
# 3) stdout é um terminal
#
# Quando o install for relançado dentro do TMUX,
# a variável TMUX estará definida e este bloco será
# automaticamente ignorado, evitando recursão.

if [ -z "${TMUX:-}" ] && [ -t 0 ] && [ -t 1 ]; then

    #####################################################
    # VERIFICA SE O TMUX ESTÁ DISPONÍVEL
    #####################################################

    if command -v tmux >/dev/null 2>&1; then

        #################################################
        # JÁ EXISTE UMA SESSÃO SETUP-MNO
        #################################################

        if tmux has-session -t "$SETUP_MNO_TMUX_SESSION" 2>/dev/null; then

            SETUP_MNO_EXISTING_LIFECYCLE=$(tmux show-options -v \
                -t "$SETUP_MNO_TMUX_SESSION" \
                @setup_mno_lifecycle 2>/dev/null || true)

            # Sessões criadas por versões antigas não possuem controle de
            # ciclo de vida e podem conservar variáveis de outra instalação.
            # Elas são removidas uma única vez durante a migração.
            if [ "$SETUP_MNO_EXISTING_LIFECYCLE" != "$SETUP_MNO_TMUX_LIFECYCLE" ]; then
                tmux kill-session -t "$SETUP_MNO_TMUX_SESSION" >/dev/null 2>&1 || true
            else

                # Reconecta à instalação ainda em andamento.
                #
                # O parâmetro -d desconecta uma sessão SSH antiga
                # eventualmente presa e conecta o terminal atual.

                tmux attach-session -d -t "$SETUP_MNO_TMUX_SESSION"

                TMUX_STATUS=$?

                # Encerra somente esta instância externa do install.
                # O controle retorna ao processo que chamou o install.
                exit "$TMUX_STATUS"
            fi
        fi

        #################################################
        # NÃO EXISTE SESSÃO: CRIA UMA NOVA
        #################################################

        SETUP_MNO_INSTALL_SCRIPT=$(setup_mno_resolve_script_path)

        clear

        #################################################
        # IMPORTANTE PARA SHC
        #
        # NÃO USAR:
        #
        # bash "$SETUP_MNO_INSTALL_SCRIPT"
        #
        # O arquivo gerado pelo SHC é um executável binário.
        # Ele deve ser executado diretamente.
        #################################################

        # O wrapper aguarda o binário SHC terminar e então remove somente a
        # sessão do Setup MNO. Uma queda de SSH apenas desanexa o cliente e
        # não alcança esta limpeza enquanto a instalação estiver em curso.
        tmux new-session -d \
            -s "$SETUP_MNO_TMUX_SESSION" \
            "\"$SETUP_MNO_INSTALL_SCRIPT\"; setup_mno_status=\$?; tmux kill-session -t \"$SETUP_MNO_TMUX_SESSION\" >/dev/null 2>&1 || true; exit \$setup_mno_status"

        TMUX_STATUS=$?

        if [ "$TMUX_STATUS" -ne 0 ]; then
            exit "$TMUX_STATUS"
        fi

        tmux set-option -t "$SETUP_MNO_TMUX_SESSION" \
            @setup_mno_lifecycle "$SETUP_MNO_TMUX_LIFECYCLE"

        tmux attach-session -t "$SETUP_MNO_TMUX_SESSION"

        TMUX_STATUS=$?

        # Quando a sessão TMUX terminar ou for desconectada,
        # não continua executando uma segunda cópia do install
        # fora do TMUX.
        exit "$TMUX_STATUS"

    else

        #################################################
        # FALLBACK
        #
        # O pré-instalador deveria ter instalado o TMUX.
        # Se por algum motivo ele não existir, não abortamos
        # o Setup MNO. A instalação continua sem proteção.
        #################################################

        clear

        echo "AVISO: TMUX não encontrado."
        echo "O Setup MNO continuará normalmente, porém sem"
        echo "proteção contra queda da conexão SSH."
        echo

        sleep 3
    fi

fi

#########################################################
# FIM DA PROTEÇÃO TMUX
#########################################################

clear
VERSIONSETUP="7.42.2"
umask 077
CONTATO_WP="+55 (11) 96816-2690"
CONTATO_EMAIL="francisbreit@gmail.com"
CONTATO_GITHUB="github.com/francisbreit"

# Perfis multidomínio são uma camada aditiva. Se o arquivo não existir em uma
# instalação antiga, todo o comportamento legado permanece inalterado.
DOMAIN_PROFILES_LIB="/root/SetupLowCodeMno/domain_profiles.sh"
if [ -f "$DOMAIN_PROFILES_LIB" ] && [ ! -L "$DOMAIN_PROFILES_LIB" ] &&
   [ "$(stat -c '%s' "$DOMAIN_PROFILES_LIB" 2>/dev/null || printf '999999')" -le 131072 ] &&
   [ "$(stat -c '%u' "$DOMAIN_PROFILES_LIB" 2>/dev/null || printf '999999')" = "0" ] &&
   [ $((8#$(stat -c '%a' "$DOMAIN_PROFILES_LIB" 2>/dev/null || printf '777') & 022)) -eq 0 ]; then
    # shellcheck disable=SC1090
    source "$DOMAIN_PROFILES_LIB"
fi

amarelo="\e[33m"
branco="\e[97m"
reset="\e[0m"

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

phases=(
    '1/4 - Checando Networks...'
    '2/4 - Checando se possui Docker Swarm...'
    '3/4 - Checando se possui Portainer...'
    '4/4 - Checando se possui Traefik...'
)

export NEWT_COLORS='
root=,white
border=black,gray
title=white,gray
roottext=red,gray
window=red,gray
textbox=white,gray
button=white,green
compactbutton=white,black
listbox=black,white
actlistbox=black,white
actsellistbox=white,green
checkbox=green,black
actcheckbox=white,green
'
{
  tput reset 2>/dev/null
  exec 0</dev/tty 1>/dev/tty 2>&1
  sleep 0.01
  clear
} || true

# --- VERIFICAR TIPO DE INSTALAÇÃO ---
INSTALL_TYPE_FILE="/root/.cloudflared_config/installation_type"
if [ -f "$INSTALL_TYPE_FILE" ]; then
    INSTALL_TYPE=$(cat "$INSTALL_TYPE_FILE")
else
    INSTALL_TYPE="TRADICIONAL"
fi

# --- LOADING BAR ---
for i in $(seq 1 100); do
    sleep 0.05
    if [ $i -eq 100 ]; then
        echo -e "XXX\n100\nConcluido!\nXXX"
    elif [ $(($i % 25)) -eq 0 ]; then
        let "phase = $i / 25"
        echo -e "XXX\n$i\n${phases[phase]}\nXXX"
    else
        echo $i
    fi
done | whiptail --title 'CHECANDO SERVIDOR' --gauge "${phases[0]}" 6 60 0
clear

# --- TRIAL ---
TRIAL_DIR="/root/SetupLowCodeMno/.meu_app_trial"
TRIAL_FILE="$TRIAL_DIR/trial_info"

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
    local temporary_file
    temporary_file=$(mktemp "$TRIAL_DIR/trial_info.tmp.XXXXXX") || return 1
    chmod 600 "$temporary_file" || { rm -f "$temporary_file"; return 1; }
    {
        printf 'DATA_INSTALACAO=%s\n' "$DATA_INSTALACAO"
        printf 'DAYS_TRIAL=%s\n' "$DIAS_RESTANTES"
        printf 'PLANO=%q\n' "$PLANO"
    } >"$temporary_file" || { rm -f "$temporary_file"; return 1; }
    mv -f "$temporary_file" "$TRIAL_FILE"
}

if [ ! -f "$TRIAL_FILE" ] || [ -L "$TRIAL_FILE" ] ||
   [ "$(stat -c '%s' "$TRIAL_FILE" 2>/dev/null || printf '0')" -gt 1024 ]; then
    whiptail --title "ESTADO DE LICENÇA INVÁLIDO" --msgbox \
        "O estado local do plano está ausente ou inseguro. Execute novamente o instalador oficial do Setup MNO para autenticar e reparar a instalação." 14 76
    exit 41
fi

# shellcheck disable=SC1090
source "$TRIAL_FILE"
if ! valid_setup_plan "$PLANO" || ! valid_setup_date "$DATA_INSTALACAO"; then
    whiptail --title "ESTADO DE LICENÇA INVÁLIDO" --msgbox \
        "O plano salvo está vazio ou inválido. Execute novamente o instalador oficial do Setup MNO. O estado atual não será sobrescrito." 14 76
    exit 41
fi

DATA_FORMATADA=$(echo "$DATA_INSTALACAO" | awk -F/ '{print $2 "/" $1 "/" $3}')
DATA_INSTALACAO_TIMESTAMP=$(date -d "$DATA_FORMATADA" +%s)
DATA_ATUAL_TIMESTAMP=$(date +%s)
DIFERENCA_SEGUNDOS=$(( DATA_INSTALACAO_TIMESTAMP + 7*86400 - DATA_ATUAL_TIMESTAMP ))
DIAS_RESTANTES=$(( (DIFERENCA_SEGUNDOS / 86400) + 1 ))
[ "$DIAS_RESTANTES" -lt 0 ] && DIAS_RESTANTES=0

if ! write_trial_state; then
    whiptail --title "ERRO AO SALVAR O PLANO" --msgbox \
        "Não foi possível atualizar o estado local do plano com segurança. O menu não será aberto para evitar uma sessão inconsistente." 12 76
    exit 41
fi

# --- REBRANDING POR PLANO ---
if [ "$PLANO" = "free1" ]; then
    CONTATO_WP="+55 (19) 99398-4964"
    CONTATO_EMAIL="contato@marciocalicchio.com.br"
    CONTATO_GITHUB="github.com/marciocalicchio"
fi

# --- DOCKER CHECKS ---
if command -v docker > /dev/null 2>&1; then
    network_id_agent_network=$(docker network ls --filter name=agent_network --format "{{.ID}}")
    network_id_externa=$(docker network ls --filter name=externa --format "{{.ID}}")
    network_id_interna=$(docker network ls --filter name=interna --format "{{.ID}}")
    traefik_container=$(docker ps -qf name=traefik)
    portainer_container=$(docker ps -qf name=portainer)
    postgres_container=$(docker ps -qf name=postgres)
    redis_container=$(docker ps -qf name=redis)
    pgbouncer_container=$(docker ps -qf name=pgbouncer)
    langfuse_container=$(docker ps -qf name=langfuse)
    dify_container=$(docker ps -qf name=dify)
    mysql_container=$(docker ps -qf name=mysql)
    flowise_container=$(docker ps -qf name=flowise)
    minio_container=$(docker ps -qf name=minio)
    pgadmin4_container=$(docker ps -qf name=pgadmin4)
    pma_container=$(docker ps -qf name=pmadmin)
    zepdb_container=$(docker ps -qf name=zepdb)
    zep_container=$(docker ps -qf name=zep)
    redicommander_container=$(docker ps -qf name=redicommander)
    calcom_container=$(docker ps -qf name=calcom)
else
    network_id_agent_network=""
    network_id_externa=""
    network_id_interna=""
    traefik_container=""
    portainer_container=""
    postgres_container=""
    redis_container=""
    pgbouncer_container=""
    langfuse_container=""
    dify_container=""
    mysql_container=""
    flowise_container=""
    minio_container=""
    pgadmin4_container=""
    pma_container=""
    zepdb_container=""
    zep_container=""
    redicommander_container=""
    calcom_container=""
fi

if [[ ("$traefik_container" == "") || ("$portainer_container" == "") || ("$postgres_container" == "") || ("$redis_container" == "") || ("$pgbouncer_container" == "") || ("$network_id_agent_network" == "") || ("$network_id_externa" == "") || ("$network_id_interna" == "") ]]; then
    clear
    cd && cd SetupLowCodeMno && ./dockerswarm
fi

# --- DISPATCH DINÂMICO (substitui 240+ case blocks) ---
run_app() {
    local script="$1"
    local domain_selection_status
    if [ "$script" = "setupmno_control" ] && control_center_installed; then
        whiptail --title "SETUP MNO CONTROL CENTER" --msgbox \
            "Já existe um Setup MNO Control Center neste servidor.\n\nSomente uma instalação é permitida por servidor." 12 72
        return 0
    fi
    if declare -F setupmno_domain_select_for_app >/dev/null 2>&1; then
        setupmno_domain_select_for_app "$script"
        domain_selection_status=$?
        if [ "$domain_selection_status" -ne 0 ]; then
            setupmno_domain_clear_selection
            clear
            return 0
        fi
    fi
    clear
    cd && cd SetupLowCodeMno && ./"$script"
    if declare -F setupmno_domain_clear_selection >/dev/null 2>&1; then
        setupmno_domain_clear_selection
    fi
    # O Control Center é executado como processo filho. Ao concluir, cancelar ou
    # falhar, preserve o laço atual do menu em vez de substituir o processo SHC.
    if [ "$script" = "setupmno_control" ]; then
        cd /root/SetupLowCodeMno 2>/dev/null || true
        clear
        return 0
    fi

    # Todos os fluxos de saída retornam a uma instância limpa do binário SHC
    # dentro da mesma sessão tmux. Nunca invoque install.sh nem use bash aqui.
    setup_mno_return_to_installer
}

manage_cloudflare_domains() {
    if ! declare -F setupmno_domain_manage >/dev/null 2>&1; then
        whiptail --title "GERENCIAR DOMÍNIOS CLOUDFLARE" --msgbox \
            "O componente multidomínio não foi encontrado. Atualize ou reinstale o Setup MNO e tente novamente." 12 78
        return 0
    fi
    setupmno_domain_manage || true
    setupmno_domain_clear_selection
    cd /root/SetupLowCodeMno 2>/dev/null || true
    clear
}

warn_heavy() {
    local app_name="$1"
    local ram_needed="$2"
    local response
    response=$(whiptail --title "⚠️ ALERTA DE RECURSOS" --yesno "⚠️ ATENÇÃO: O $app_name consome aproximadamente $ram_needed de RAM.\n\nAntes de prosseguir, verifique se existem recursos suficientes disponíveis, caso contrário, você precisará fazer upgrade de servidor ou deletar outras aplicações.\n\nDeseja prosseguir com a instalação?" --fb 16 70 3>&1 1>&2 2>&3)
    if [[ $? -ne 0 ]]; then
        return 1
    fi
    return 0
}

# --- TÍTULO ---
export NEWT_COLORS='
root=,white
border=black,gray
title=white,blue
roottext=red,gray
window=red,gray
textbox=white,gray
button=white,green
compactbutton=white,black
listbox=black,white
actlistbox=black,white
actsellistbox=white,green
checkbox=green,black
actcheckbox=white,green
'

if [ "$PLANO" == "trial pro" ]; then
    TITULO="SETUP MNO v${VERSIONSETUP} - Plano: $PLANO 7 Dias - Restam: $DIAS_RESTANTES dias"
else
    TITULO="SETUP MNO v${VERSIONSETUP} - Plano: $PLANO - Instalação: $INSTALL_TYPE"
fi

# --- FUNÇÕES DE VALIDAÇÃO ---
check_already_installed() {
    local c=""
    case "$1" in
        "MYSQL")                           c="$mysql_container" ;;
        "FLOWISE")                         c="$flowise_container" ;;
        "MINIO")                           c="$minio_container" ;;
        "PGADMIN4")                        c="$pgadmin4_container" ;;
        "PHPMYADMIN")                      c="$pma_container" ;;
        "REDIS COMMANDER")                 c="$redicommander_container" ;;
        "CAL.COM")                         c="$calcom_container" ;;
        "LANGFUSE + MINIO + CLICKHOUSE*") c="$langfuse_container" ;;
        "DIFY")                            c="$dify_container" ;;
        *) return 1 ;;
    esac
    [ -n "$c" ]
}

control_center_installed() {
    command -v docker >/dev/null 2>&1 || return 1
    docker service ls --format '{{.Name}}' 2>/dev/null |
        grep -Eq '^mnoctrl[[:alnum:]]+-(web|agent|terminal|assistant)_'
}

CONTROL_MFA_STATE_FILE="/root/SetupLowCodeMno/.control/mfa-state.json"

control_mfa_state_valid() {
    [ -f "$CONTROL_MFA_STATE_FILE" ] && [ ! -L "$CONTROL_MFA_STATE_FILE" ] &&
    [ "$(stat -c '%s' "$CONTROL_MFA_STATE_FILE" 2>/dev/null || printf '0')" -le 2048 ] &&
    jq -e '.schemaVersion == 1 and .decisionRecorded == true and
        (.desiredMFA | type == "boolean") and (.effectiveMFA | type == "boolean") and
        (.activationPromptPending | type == "boolean") and
        (.source | type == "string" and length > 0) and
        ((.desiredMFA == false and .effectiveMFA == false and .activationPromptPending == false) or
         (.desiredMFA == true and .effectiveMFA == true and .activationPromptPending == false) or
         (.desiredMFA == true and .effectiveMFA == false))' \
        "$CONTROL_MFA_STATE_FILE" >/dev/null 2>&1
}

write_control_mfa_state() {
    local desired="$1" effective="$2" pending="$3" source="$4" state_dir temporary_file
    case "$desired:$effective:$pending" in
        true:true:false|true:false:true|true:false:false|false:false:false) ;;
        *) return 1 ;;
    esac
    [[ "$source" =~ ^[a-z0-9-]{3,40}$ ]] || return 1
    state_dir=$(dirname "$CONTROL_MFA_STATE_FILE")
    [ ! -L "$state_dir" ] || return 1
    mkdir -p "$state_dir" || return 1
    [ ! -e "$CONTROL_MFA_STATE_FILE" ] ||
        { [ -f "$CONTROL_MFA_STATE_FILE" ] && [ ! -L "$CONTROL_MFA_STATE_FILE" ]; } || return 1
    temporary_file=$(mktemp "$state_dir/mfa-state.json.tmp.XXXXXX") || return 1
    chmod 0600 "$temporary_file" || { rm -f "$temporary_file"; return 1; }
    jq -n --argjson desired "$desired" --argjson effective "$effective" \
        --argjson pending "$pending" --arg source "$source" \
        --arg updatedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        '{schemaVersion:1,decisionRecorded:true,desiredMFA:$desired,
          effectiveMFA:$effective,activationPromptPending:$pending,
          source:$source,updatedAt:$updatedAt}' >"$temporary_file" || {
        rm -f "$temporary_file"
        return 1
    }
    mv -f "$temporary_file" "$CONTROL_MFA_STATE_FILE"
}

show_control_mfa_instructions() {
    whiptail --title "COMO PREPARAR O MFA" --msgbox \
        "O MFA opcional protege o Control Center por Cloudflare Access. No Zero Trust, habilite Access controls > Access settings > Allow multi-factor authentication (MFA) e permita TOTP, biometria ou chave de segurança. O token precisa de Access: Apps and Policies Write e Access: Organizations Read. Nenhuma credencial ou e-mail é salvo neste arquivo de preferência." \
        18 90
}

choose_control_mfa_preference() {
    local choice
    while true; do
        choice=$(whiptail --title "SEGURANÇA DO CONTROL CENTER" --default-item "MFA" --menu \
            "Esta instalação antiga ainda não registrou uma decisão. Escolha uma vez; a preferência será preservada nas próximas atualizações:" \
            19 94 3 \
            "MFA" "Ativar Cloudflare Access + segundo fator (RECOMENDADO)" \
            "SEM_MFA" "Manter todos os acessos no modo original" \
            "INSTRUCOES" "Ver instruções antes de escolher" \
            3>&1 1>&2 2>&3) || return 130
        case "$choice" in
            MFA) write_control_mfa_state true false true legacy-upgrade; return $? ;;
            SEM_MFA) write_control_mfa_state false false false legacy-upgrade; return $? ;;
            INSTRUCOES) show_control_mfa_instructions ;;
        esac
    done
}

control_center_effective_mfa() {
    local service environment
    service=$(docker service ls --format '{{.Name}}' 2>/dev/null |
        grep -E '^mnoctrl[[:alnum:]]+-web_mnoctrl[[:alnum:]]+-web$')
    [ "$(printf '%s\n' "$service" | sed '/^$/d' | wc -l)" -eq 1 ] || return 1
    environment=$(docker service inspect --format \
        '{{range .Spec.TaskTemplate.ContainerSpec.Env}}{{println .}}{{end}}' \
        "$service" 2>/dev/null) || return 1
    grep -Fxq 'ACCESS_JWT_REQUIRED=true' <<<"$environment" &&
    grep -Fxq 'ACCESS_MFA_REQUIRED=true' <<<"$environment"
}

ensure_control_mfa_decision() {
    control_mfa_state_valid && return 0
    if [ "$INSTALL_TYPE" != "CLOUDFLARE_TUNNEL" ]; then
        write_control_mfa_state false false false traditional
        return $?
    fi
    if control_center_effective_mfa; then
        write_control_mfa_state true true false legacy-detected
        return $?
    fi
    choose_control_mfa_preference
}

configure_control_center_mfa() {
    if ! control_center_installed; then
        whiptail --title "CONFIGURAR MFA CONTROL CENTER" --msgbox \
            "Instale primeiro o Setup MNO Control Center. Sua preferência continuará registrada e será aplicada durante a instalação do painel." 13 82
        return 0
    fi
    if [ ! -x /root/SetupLowCodeMno/setupmno_control ]; then
        whiptail --title "CONFIGURAR MFA CONTROL CENTER" --msgbox \
            "O binário protegido setupmno_control não foi encontrado. Reinstale ou atualize o Setup MNO e tente novamente." \
            13 80
        return 0
    fi
    clear
    /root/SetupLowCodeMno/setupmno_control --configure-access-mfa || true
    cd /root/SetupLowCodeMno 2>/dev/null || true
    clear
    return 0
}

control_center_agent_has_runtime_mount() {
    local service="$1"
    docker service inspect --format \
        '{{range .Spec.TaskTemplate.ContainerSpec.Mounts}}{{println .Target}}{{end}}' \
        "$service" 2>/dev/null | grep -Fxq /runtime-control
}

control_center_runtime_is_valid() {
    [ -d /root/SetupLowCodeMno/.control ] &&
    [ ! -L /root/SetupLowCodeMno/.control ] &&
    [ -f /root/SetupLowCodeMno/.control/catalog.json ] &&
    [ ! -L /root/SetupLowCodeMno/.control/catalog.json ] &&
    [ -f /root/SetupLowCodeMno/.control/release.json ] &&
    [ ! -L /root/SetupLowCodeMno/.control/release.json ]
}

ensure_control_center_runtime_access() {
    local services service
    command -v docker >/dev/null 2>&1 || return 1
    control_center_runtime_is_valid || return 1
    services=$(docker service ls --format '{{.Name}}' 2>/dev/null |
        grep -E '^mnoctrl[[:alnum:]]+-agent_mnoctrl[[:alnum:]]+-agent$' || true)
    [ "$(grep -c . <<<"$services")" -eq 1 ] || return 1
    service="$services"
    control_center_agent_has_runtime_mount "$service" && return 0
    docker service update \
        --mount-add type=bind,src=/root/SetupLowCodeMno/.control,dst=/runtime-control,readonly \
        --force --detach=true "$service" >/dev/null 2>&1 || return 1
    control_center_agent_has_runtime_mount "$service"
}

reconcile_control_center_release() {
    [ -x /root/SetupLowCodeMno/setupmno_control ] || return 1
    /root/SetupLowCodeMno/setupmno_control --reconcile-existing
}

if ! ensure_control_mfa_decision; then
    whiptail --title "PREFERÊNCIA DE MFA NÃO REGISTRADA" --msgbox \
        "A escolha foi cancelada ou não pôde ser salva. Nenhuma configuração de acesso foi alterada. Execute setup-mno novamente para continuar." 14 84
    exit 0
fi

if control_center_installed; then
    if ! reconcile_control_center_release; then
        whiptail --title "SETUP MNO CONTROL CENTER" --msgbox \
            "A instalação existente foi preservada, mas o Control Center não pôde ser sincronizado agora.\n\nO menu principal continuará disponível para instalar e administrar as demais aplicações. Consulte o log informado antes de usar Catálogo, Blueprints ou Assistente." \
            16 84
    elif ! ensure_control_center_runtime_access; then
        whiptail --title "SETUP MNO CONTROL CENTER" --msgbox \
            "O Control Center foi preservado, mas o acesso somente leitura ao catálogo runtime não pôde ser confirmado.\n\nO menu principal continuará disponível. Reinstale o Setup MNO ou consulte o suporte antes de usar Catálogo, Blueprints ou Assistente." \
            16 82
    fi
    if control_mfa_state_valid &&
       [ "$(jq -r '.desiredMFA' "$CONTROL_MFA_STATE_FILE")" = "true" ] &&
       [ "$(jq -r '.effectiveMFA' "$CONTROL_MFA_STATE_FILE")" = "false" ] &&
       [ "$(jq -r '.activationPromptPending' "$CONTROL_MFA_STATE_FILE")" = "true" ]; then
        if write_control_mfa_state true false false activation-offered; then
            configure_control_center_mfa
        fi
    fi
fi

# --- SAIR ---
do_exit() {
    clear
    echo -e "\033[1;36m"
    echo "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓"
    echo -e "\033[1;33m"
    echo "  ███╗   ███╗███╗   ██╗ ██████╗"
    echo "  ████╗ ████║████╗  ██║██╔═══██╗"
    echo "  ██╔████╔██║██╔██╗ ██║██║   ██║"
    echo "  ██║╚██╔╝██║██║╚██╗██║██║   ██║"
    echo "  ██║ ╚═╝ ██║██║ ╚████║╚██████╔╝"
    echo "  ╚═╝     ╚═╝╚═╝  ╚═══╝ ╚═════╝"
    echo -e "\033[1;36m"
    echo "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓"
    echo -e "\033[0m"
    echo -e "\033[1;32m"
    echo "  SETUP MNO FINALIZADO COM ÊXITO!"
    echo "  P/ INICIAR: SEMPRE DIGITE 'setup-mno' NO TERMINAL"
    echo ""
    echo -e "   \033[1;35m🚀 COMANDO DE REATIVAÇÃO:\033[1;37m setup-mno"
    echo -e "   \033[1;35m📡 CANAIS DE SUPORTE:"
    echo -e "      \033[1;36m● WhatsApp: $CONTATO_WP"
    echo -e "      \033[1;36m● Email: $CONTATO_EMAIL"
    echo -e "      \033[1;36m● GitHub: $CONTATO_GITHUB"
    echo -e "   \033[1;33m⚠️  SISTEMA PRONTO PARA OPERAÇÃO"
    echo -e "\033[0m"
    sleep 1
    exit 0
}

# ===================== LOOP PRINCIPAL =====================
while true; do

CONTROL_CENTER_MENU=()
CONTROL_CENTER_FREE_MENU=()
CONTROL_CENTER_MFA_MENU=("CONFIGURAR MFA CONTROL CENTER" "")
if ! control_center_installed; then
    CONTROL_CENTER_MENU=("SETUP MNO CONTROL CENTER" "")
    CONTROL_CENTER_FREE_MENU=("SETUP MNO CONTROL CENTER" "")
fi

if [[ ! "$PLANO" = *free* ]]; then

CHOICE=$(
whiptail --title "$TITULO" --menu "Selecione um App: Use as setas do teclado e pressione ENTER" 20 70 10 \
    "ACTIVEPIECES" "" \
    "ADGUARDHOME" "" \
    "AFFINE" "" \
    "ACTUAL BUDGET" "" \
    "APPSMITH" "" \
    "AUTOGEN STUDIO" "" \
    "BASEROW" "" \
    "BESZEL" "" \
    "BOOKSTACK" "" \
    "BOTPRESS" "" \
    "BUDIBASE" "" \
    "BYTEBASE" "" \
    "CAL.COM" ""  \
    "CHATWOOTN + EVOLUTIONN 2.0 + RABBITMQ*" ""   \
    "CHATWOOTN + EVOLUTIONN 2.0 + RABBITMQ + MINIO*" ""   \
    "CHATWOOTORIG + EVOLUTIONN 2.0 + RABBITMQ + MINIO*" ""   \
    "CHATWOOTORIG (DESBLOQUEADO) + EVOLUTIONN 2.0 + RABBITMQ + MINIO*" ""   \
    "CHATWOOT AI CUSTOMER SERVICE*" ""   \
    "CHANGEDETECTION.IO" ""   \
    "CHROMADB" ""   \
    "CLICKHOUSE" ""   \
    "CODE SERVER" ""   \
    "COGNEE" ""   \
    "DATABASUS" ""   \
    "DIFY" ""   \
    "DIRECTUS" "" \
    "DISCOURSE" "" \
    "DUPLICATI" "" \
    "DOCMOST" "" \
    "DOCUMENSO" "" \
    "DOCUSEAL" "" \
    "DOZZLE" "" \
    "EVOAI" ""  \
    "EVOAI + EVOLUTION 2.0 + MINIO*" ""  \
    "EVOLUTION 1.0 API PADRÃO" ""  \
    "EVOLUTION 2.0 API PADRÃO" ""  \
    "EVOLUTION CRM" ""  \
    "EVOLUTION GO" ""  \
    "EVO NEXUS" ""  \
    "EXCALIDRAW" "" \
    "FIRECRAWL" "" \
    "FLOWISE" "" \
    "FOCALBOARD" "" \
    "FRESHRSS" "" \
    "FILEBROWSER" "" \
    "FIREFLY III" "" \
    "FORMBRICKS" "" \
    "GHOST" "" \
    "GITEA" "" \
    "GITLAB" "" \
    "GLANCE" "" \
    "GLPI" "" \
    "GRAFANA/PROMETHEUS MONITOR" ""   \
    "HERMES AGENT" "" \
    "HEYFORM" "" \
    "HOME ASSISTANT" "" \
    "HOMEPAGE" "" \
    "HOPPSCOTCH" "" \
    "HUMHUB" "" \
    "IMMICH" "" \
    "INFISICAL" "" \
    "IT-TOOLS" "" \
    "JITSI MEET" "" \
    "JELLYFIN" "" \
    "JOPLIN" "" \
    "KEYCLOAK" "" \
    "KRAYIN CRM" "" \
    "KARAKEEP" "" \
    "LANGFLOW" "" \
    "LANGFUSE + MINIO + CLICKHOUSE*" "" \
    "LIBRECHAT" "" \
    "LINKWARDEN" "" \
    "LISTMONK" "" \
    "LITELLM" "" \
    "LOBECHAT" "" \
    "LOCALAI" "" \
    "MATTERMOST" "" \
    "MATOMO" "" \
    "MAYBE" "" \
    "MEILISEARCH" "" \
    "MILVUS + ATTU*" "" \
    "MEMOS" "" \
    "MAUTIC 4 PADRÃO" "" \
    "MAUTIC 6 PADRÃO" "" \
    "MAUTIC 7 PADRÃO" "" \
    "MAUTIC 4 WHATSAPP MKT" "" \
    "MAUTIC 6 WHATSAPP MKT" "" \
    "MAUTIC 7 WHATSAPP MKT" "" \
    "MEMGRAPH" "" \
    "METABASE" "" \
    "MINIO" "" \
    "MONGODB" "" \
    "MYSQL" "" \
    "N8N V1 - SEM FILA (MAIN)" "" \
    "N8N V1 - FILA (QUEUE)" "" \
    "N8N V2 - FILA (QUEUE)" "" \
    "N8N TEMPLATES FREE - + DE 2000 WORKFLOWS" "" \
    "NAVIDROME" "" \
    "NEO4J" "" \
    "NETDADA" "" \
    "NEXTCLOUD" "" \
    "NGINXPROXYMANAGER" "" \
    "NOCODB" "" \
    "NOCOBASE" "" \
    "NTFY" "" \
    "ODOO" "" \
    "OLLAMA + OPENWEBUI*" "" \
    "OPEN WEBUI" "" \
    "OPENCLAW" "" \
    "OPENCLAW + QDRANT + NEO4J + COGNEE + SEARXNG*" "" \
    "OPENFANG" "" \
    "OPENOBSERVE" "" \
    "OPEN PROJECT" "" \
    "OUTLINE" "" \
    "PAPERCLIP" "" \
    "PAPERLESS" "" \
    "PENPOT" "" \
    "PI-HOLE" "" \
    "POCKET ID" "" \
    "POCKETBASE" "" \
    "PGADMIN4" "" \
    "PHOTOPRISM" "" \
    "PHPMYADMIN" "" \
    "PLANE" "" \
    "PLANKA" "" \
    "QDRANT" "" \
    "RABBITMQ" "" \
    "REACTIVE RESUME" "" \
    "REDIS" "" \
    "REDIS COMMANDER" "" \
    "REDISINSIGHT" "" \
    "ROCKET.CHAT" "" \
    "SEARXNG" "" \
    "${CONTROL_CENTER_MENU[@]}" \
    "SYNCTHING" "" \
    "SHLINK" "" \
    "SIYUAN" "" \
    "STRAPI" "" \
    "STIRLING PDF" "" \
    "TOOLJET" "" \
    "SUPERSET" "" \
    "TRILIUMNEXT" "" \
    "TWENTY CRM" "" \
    "TYPEBOT" "" \
    "UMAMI" "" \
    "TYPEBOT + MINIO*" "" \
    "UPTIMEKUMA" "" \
    "WAHA API" "" \
    "VAULTWARDEN" "" \
    "VIKUNJA" "" \
    "VLLM" "" \
    "WEAVIATE" "" \
    "WINDMILL" "" \
    "WOOFED CRM" "" \
    "WORDPRESS" "" \
    "WIKI.JS" "" \
    "WUZAP" "" \
    "WEKAN" "" \
    "${CONTROL_CENTER_MFA_MENU[@]}" \
    "REINICIAR APPS/SERVIÇOS" "" \
    "DELETAR APPS/STACKS" "" \
    "GERENCIAR DOMÍNIOS CLOUDFLARE" "" \
    "GERADOR DE REGISTROS DNS" "" \
    "ESSENCIAIS EDITÁVEIS NO PORTAINER" "" \
    "DIAGNÓSTICO DE SEGURANÇA DO SERVIDOR" "" \
    "SAIR" ""  3>&2 2>&1 1>&3
)

[ -z "$CHOICE" ] && do_exit

case "$CHOICE" in
    "STRAPI") run_app strap ;;
    "CONFIGURAR MFA CONTROL CENTER") configure_control_center_mfa ;;
    "REINICIAR APPS/SERVIÇOS")  run_app restartservice ;;
    "DELETAR APPS/STACKS")      run_app uninstall ;;
    "GERENCIAR DOMÍNIOS CLOUDFLARE") manage_cloudflare_domains ;;
    "GERADOR DE REGISTROS DNS") run_app geracloudflare ;;
    "ESSENCIAIS EDITÁVEIS NO PORTAINER") run_app essenciais ;;
    "DIAGNÓSTICO DE SEGURANÇA DO SERVIDOR") run_app securitydiagnostic ;;
    "SAIR") do_exit ;;
    *)
        if check_already_installed "$CHOICE"; then
            whiptail --msgbox "Aviso: ${CHOICE} já está instalado. Não é permitido instalar mais de uma instância.\n\nDigite ENTER para voltar ao Menu Principal." 12 70
            continue
        fi
        # Mapeamento nome -> script
        case "$CHOICE" in
            "ACTIVEPIECES")                                           run_app activepieces ;;
            "ADGUARDHOME")                                          run_app adguardhome ;;
            "AFFINE")                                                run_app affine ;;
            "ACTUAL BUDGET")                                          run_app actualbudget ;;
            "APPSMITH")                                              run_app appsmith ;;
            "AUTOGEN STUDIO")                                        run_app autogen ;;
            "BASEROW")                                               run_app baserow ;;
            "BESZEL")                                               run_app beszel ;;
            "BOOKSTACK")                                               run_app bookstack ;;
            "BOTPRESS")                                              run_app botpress ;;
            "BUDIBASE")                                              run_app budibase ;;
            "BYTEBASE")                                              run_app bytebase ;;
            "CAL.COM")                                               run_app calcom ;;
            "CHATWOOTN + EVOLUTIONN 2.0 + RABBITMQ*")               warn_heavy "Chatwoot + Evolution 2.0 + RabbitMQ" "4GB" && run_app chatwootn_evo2_rabbitmq_redisevo ;;
            "CHATWOOTN + EVOLUTIONN 2.0 + RABBITMQ + MINIO*")       warn_heavy "Chatwoot + Evolution 2.0 + RabbitMQ + MinIO" "4GB" && run_app chatwootn_evo2_rabbitmq_minio ;;
            "CHATWOOTORIG + EVOLUTIONN 2.0 + RABBITMQ + MINIO*")    warn_heavy "Chatwoot Original + Evolution 2.0 + RabbitMQ + MinIO" "4GB" && run_app chatwooto_evo2_rabbitmq_minio ;;
            "CHATWOOTORIG (DESBLOQUEADO) + EVOLUTIONN 2.0 + RABBITMQ + MINIO*") warn_heavy "Chatwoot Desbloqueado + Evolution 2.0 + RabbitMQ + MinIO" "4GB" && run_app chatwootorig_desbloq__evo2_rabbitmq_minio ;;
            "CHATWOOT AI CUSTOMER SERVICE*") warn_heavy "Chatwoot AI Customer Service" "10GB" && run_app chatwoot_ai_customer_service ;;
            "CLICKHOUSE")                                            run_app clickhouse ;;
            "CHANGEDETECTION.IO")                                     run_app changedetection ;;
            "CODE SERVER")                                           run_app codeserver ;;
            "COGNEE")                                                run_app cognee ;;
            "DATABASUS")                                             run_app databasus ;;
            "DIFY")                                                  warn_heavy "Dify" "4GB" && run_app dify ;;
            "DIRECTUS")                                              run_app directus ;;
            "DUPLICATI")                                             run_app duplicati ;;
            "DISCOURSE")                                             run_app discourse ;;
            "DOCMOST")                                               run_app docmost ;;
            "DOCUMENSO")                                             run_app documenso ;;
            "DOCUSEAL")                                              run_app docuseal ;;
            "DOZZLE")                                                run_app dozzle ;;
            "EVOAI")                                                 run_app evoai ;;
            "EVOAI + EVOLUTION 2.0 + MINIO*")                       run_app evoai_evo2_minio ;;
            "EVOLUTION 1.0 API PADRÃO")                             run_app evolutionapi ;;
            "EVOLUTION 2.0 API PADRÃO")                             run_app evolution2api ;;
            "EVOLUTION CRM")                                         warn_heavy "Evolution CRM" "10GB" && run_app evocrm ;;
            "EVOLUTION GO")                                          run_app evolutiongo ;;
            "EVO NEXUS")                                             run_app evonexus ;;
            "EXCALIDRAW")                                            run_app excalidraw ;;
            "FIRECRAWL")                                             run_app firecrawl ;;
            "FLOWISE")                                               run_app flowise ;;
            "FOCALBOARD")                                            run_app focalboard ;;
            "FRESHRSS")                                              run_app freshrss ;;
            "FILEBROWSER")                                          run_app filebrowser ;;
            "FIREFLY III")                                              run_app fireflyiii ;;
            "FORMBRICKS")                                            run_app formbricks ;;
            "GHOST")                                                 run_app ghost ;;
            "GITEA")                                                 run_app gitea ;;
            "GITLAB")                                                warn_heavy "GitLab" "4GB" && run_app gitlab ;;
            "GLANCE")                                                run_app glance ;;
            "GLPI")                                                  run_app glpi ;;
            "GRAFANA/PROMETHEUS MONITOR")                            run_app grafana ;;
            "HERMES AGENT")                                          run_app hermes ;;
            "HEYFORM")                                               run_app heyform ;;
            "HOME ASSISTANT")                                        run_app homeassistant ;;
            "HOMEPAGE")                                              run_app homepage ;;
            "HOPPSCOTCH")                                            run_app hoppscotch ;;
            "HUMHUB")                                                run_app humhub ;;
            "IMMICH")                                                warn_heavy "Immich" "6GB" && run_app immich ;;
            "INFISICAL")                                            run_app infisical ;;
            "IT-TOOLS")                                             run_app it_tools ;;
            "JITSI MEET")                                            warn_heavy "Jitsi Meet" "5GB" && run_app jitsi ;;
            "JELLYFIN")                                             run_app jellyfin ;;
            "JOPLIN")                                               run_app joplin ;;
            "KEYCLOAK")                                              run_app keycloak ;;
            "KRAYIN CRM")                                            run_app krayincrm ;;
            "KARAKEEP")                                              run_app karakeep ;;
            "LANGFLOW")                                              run_app langflow ;;
            "LANGFUSE + MINIO + CLICKHOUSE*")                       warn_heavy "Langfuse + MinIO + ClickHouse" "8GB" && run_app langfuse ;;
            "LITELLM")                                               run_app litellm ;;
            "LOCALAI")                                                run_app localai ;;
            "LIBRECHAT")                                             run_app librechat ;;
            "LINKWARDEN")                                           warn_heavy "Linkwarden" "4GB" && run_app linkwarden ;;
            "LISTMONK")                                              run_app listmonk ;;
            "LOBECHAT")                                              run_app lobechat ;;
            "MATTERMOST")                                            run_app mattermost ;;
            "MATOMO")                                                run_app matomo ;;
            "MAYBE")                                                run_app maybe ;;
            "MEILISEARCH")                                           run_app meilisearch ;;
            "MILVUS + ATTU*")                                        warn_heavy "Milvus + Attu" "4GB" && run_app milvus ;;
            "MEMOS")                                                run_app memos ;;
            "MAUTIC 4 PADRÃO")                                       warn_heavy "Mautic 4" "4.5GB" && run_app mauticpadrao ;;
            "MAUTIC 6 PADRÃO")                                       warn_heavy "Mautic 6" "6GB" && run_app mautic6padrao ;;
            "MAUTIC 7 PADRÃO")                                       warn_heavy "Mautic 7" "6GB" && run_app mautic7padrao ;;
            "MAUTIC 4 WHATSAPP MKT")                                 warn_heavy "Mautic 4 WhatsApp" "4.5GB" && run_app mautic4whatsmkt ;;
            "MAUTIC 6 WHATSAPP MKT")                                 warn_heavy "Mautic 6 WhatsApp" "6GB" && run_app mautic6whatsmkt ;;
            "MAUTIC 7 WHATSAPP MKT")                                 warn_heavy "Mautic 7 WhatsApp" "6GB" && run_app mautic7whatsmkt ;;
            "MEMGRAPH")                                              run_app memgraph ;;
            "METABASE")                                              run_app metabase ;;
            "MINIO")                                                 run_app minio ;;
            "MONGODB")                                               run_app mongodb ;;
            "MYSQL")                                                 run_app mysql ;;
            "N8N V1 - SEM FILA (MAIN)")                              run_app n8nmain ;;
            "N8N V1 - FILA (QUEUE)")                                 warn_heavy "N8N (Fila)" "8GB" && run_app n8n ;;
            "N8N V2 - FILA (QUEUE)")                                 warn_heavy "N8N V2 (Fila)" "7GB" && run_app n8n2 ;;
            "N8N TEMPLATES FREE - + DE 2000 WORKFLOWS")              run_app n8n-workflows ;;
            "NAVIDROME")                                                 run_app navidrome ;;
            "NEO4J")                                                 run_app neo4j ;;
            "NETDADA")                                              run_app netdada ;;
            "NEXTCLOUD")                                             run_app nextcloud ;;
            "NGINXPROXYMANAGER")                                   run_app nginxproxymanager ;;
            "NOCODB")                                                run_app nocodb ;;
            "NOCOBASE")                                             run_app nocobase ;;
            "NTFY")                                                  run_app ntfy ;;
            "ODOO")                                                  run_app odoo ;;
            "OLLAMA + OPENWEBUI*")                                   warn_heavy "Ollama" "8GB+" && run_app ollama ;;
            "OPEN WEBUI")                                            run_app openwebui ;;
            "OPENCLAW")                                              run_app openclaw ;;
            "OPENCLAW + QDRANT + NEO4J + COGNEE + SEARXNG*")        run_app openclawpro ;;
            "OUTLINE")                                               run_app outline ;;
            "OPENFANG")                                              run_app openfang ;;
            "OPENOBSERVE")                                          warn_heavy "OpenObserve" "4GB" && run_app openobserve ;;
            "OPEN PROJECT")                                          run_app openproject ;;
            "PAPERCLIP")                                             run_app paperclip ;;
            "PAPERLESS")                                               run_app paperless ;;
            "PENPOT")                                                warn_heavy "Penpot" "4GB" && run_app penpot ;;
            "PI-HOLE")                                               run_app pihole ;;
            "POCKET ID")                                           run_app pocketid ;;
            "POCKETBASE")                                           run_app pocketbase ;;
            "ROCKET.CHAT")                                           run_app rocketchat ;;
            "PGADMIN4")                                              run_app pgadmin ;;
            "PHOTOPRISM")                                           warn_heavy "PhotoPrism" "2GB" && run_app photoprism ;;
            "PLANKA")                                               run_app planka ;;
            "PLANE")                                                run_app plane ;;
            "PHPMYADMIN")                                            run_app pma ;;
            "QDRANT")                                                run_app qdrant ;;
            "CHROMADB")                                              run_app chromadb ;;
            "RABBITMQ")                                              run_app rabbitmq ;;
            "REACTIVE RESUME")                                      run_app reactiveresume ;;
            "TOOLJET")                                              warn_heavy "ToolJet" "2GB" && run_app tooljet ;;
            "REDIS")                                                 run_app redis ;;
            "REDIS COMMANDER")                                       run_app redicommander ;;
            "REDISINSIGHT")                                          run_app redisinsight ;;
            "SEARXNG")                                               run_app searxng ;;
            "SETUP MNO CONTROL CENTER")                              run_app setupmno_control ;;
            "SYNCTHING")                                             run_app syncthing ;;
            "SHLINK")                                                run_app shlink ;;
            "SIYUAN")                                                run_app siyuan ;;
            "STIRLING PDF")                                          run_app stirlingpdf ;;
            "SUPERSET")                                             run_app superset ;;
            "TRILIUMNEXT")                                           run_app triliumnext ;;
            "TWENTY CRM")                                            warn_heavy "Twenty CRM" "5GB" && run_app twentycrm ;;
            "TYPEBOT")                                               run_app typebot ;;
            "UMAMI")                                                 run_app umami ;;
            "TYPEBOT + MINIO*")                                      run_app typebot_minio ;;
            "UPTIMEKUMA")                                            run_app uptimekuma ;;
            "WAHA API")                                             run_app waha ;;
            "VAULTWARDEN")                                           run_app vaultwarden ;;
            "VIKUNJA")                                               run_app vikunja ;;
            "VLLM")                                                  run_app vllm ;;
            "WEAVIATE")                                             run_app weaviate ;;
            "WINDMILL")                                             run_app windmill ;;
            "WOOFED CRM")                                            run_app woofedcrm ;;
            "WORDPRESS")                                             run_app wordpress ;;
            "WIKI.JS")                                               run_app wikijs ;;
            "WUZAP")                                                 run_app wuzap ;;
            "WEKAN")                                                 run_app wekan ;;
        esac
        ;;
esac

fi

if [ "$PLANO" == "free" ]; then
CHOICE=$(
whiptail --title "$TITULO" --menu "Selecione um App: Use as setas do teclado e pressione ENTER" 20 70 10 \
    "CHATWOOTN + EVOLUTIONN 2.0 + RABBITMQ*" ""   \
    "CLICKHOUSE" ""   \
    "DATABASUS" ""   \
    "DIRECTUS" "" \
    "DUPLICATI" "" \
    "EVOAI" ""  \
    "EVOLUTION 1.0 API PADRÃO" ""  \
    "EVOLUTION 2.0 API PADRÃO" ""  \
    "EVOLUTION CRM" ""  \
    "EVOLUTION GO" ""  \
    "EVO NEXUS" ""  \
    "FLOWISE" "" \
    "GRAFANA/PROMETHEUS MONITOR" ""   \
    "MAUTIC 6 PADRÃO" "" \
    "MAUTIC 7 PADRÃO" "" \
    "MINIO" "" \
    "MONGODB" "" \
    "MYSQL" "" \
    "N8N V1 - SEM FILA (MAIN)" "" \
    "N8N V1 - FILA (QUEUE)" "" \
    "N8N V2 - FILA (QUEUE)" "" \
    "N8N TEMPLATES FREE - + DE 2000 WORKFLOWS" "" \
    "NOCODB" "" \
    "NOCOBASE" "" \
    "NTFY" "" \
    "OLLAMA + OPENWEBUI*" "" \
    "PGADMIN4" "" \
    "PHPMYADMIN" "" \
    "PLANKA" "" \
    "QDRANT" "" \
    "RABBITMQ" "" \
    "REDIS" "" \
    "REDIS COMMANDER" "" \
    "REDISINSIGHT" "" \
    "${CONTROL_CENTER_FREE_MENU[@]}" \
    "SHLINK" "" \
    "STRAPI" "" \
    "STIRLING PDF" "" \
    "SUPERSET" "" \
    "TYPEBOT" "" \
    "UMAMI" "" \
    "UPTIMEKUMA" "" \
    "WAHA API" "" \
    "VAULTWARDEN" "" \
    "WORDPRESS" "" \
    "WIKI.JS" "" \
    "WUZAP" "" \
    "WEKAN" "" \
    "─────────────────────────" "" \
    "ACTIVEPIECES" "PRO" \
    "ADGUARDHOME" "PRO" \
    "AFFINE" "PRO" \
    "ACTUAL BUDGET" "PRO" \
    "APPSMITH" "PRO" \
    "AUTOGEN STUDIO" "PRO" \
    "BASEROW" "PRO" \
    "BESZEL" "PRO" \
    "BOOKSTACK" "PRO" \
    "BOTPRESS" "PRO" \
    "BUDIBASE" "PRO" \
    "BYTEBASE" "PRO" \
    "CAL.COM" "PRO"  \
    "CHATWOOTN + EVOLUTIONN 2.0 + RABBITMQ + MINIO*" "PRO"   \
    "CHATWOOTORIG + EVOLUTIONN 2.0 + RABBITMQ + MINIO*" "PRO"   \
    "CHATWOOTORIG (DESBLOQUEADO) + EVOLUTIONN 2.0 + RABBITMQ + MINIO*" "PRO"   \
    "CHATWOOT AI CUSTOMER SERVICE*" "PRO"   \
    "CHANGEDETECTION.IO" "PRO"   \
    "CODE SERVER" "PRO"   \
    "COGNEE" "PRO"   \
    "DIFY" "PRO"   \
    "DISCOURSE" "PRO" \
    "DOCMOST" "PRO" \
    "DUPLICATI" "PRO" \
    "DOCUMENSO" "PRO" \
    "DOCUSEAL" "PRO" \
    "DOZZLE" "PRO" \
    "EVOAI + EVOLUTION 2.0 + MINIO*" "PRO"  \
    "EXCALIDRAW" "PRO" \
    "FIRECRAWL" "PRO" \
    "FOCALBOARD" "PRO" \
    "FRESHRSS" "PRO" \
    "FILEBROWSER" "PRO" \
    "FIREFLY III" "PRO" \
    "FORMBRICKS" "PRO" \
    "GHOST" "PRO" \
    "GITEA" "PRO" \
    "GITLAB" "PRO" \
    "GLANCE" "PRO" \
    "GLPI" "PRO" \
    "HERMES AGENT" "PRO" \
    "HEYFORM" "PRO" \
    "HOME ASSISTANT" "PRO" \
    "HOMEPAGE" "PRO" \
    "HOPPSCOTCH" "PRO" \
    "HUMHUB" "PRO" \
    "IMMICH" "PRO" \
    "INFISICAL" "PRO" \
    "IT-TOOLS" "PRO" \
    "JITSI MEET" "PRO" \
    "JELLYFIN" "PRO" \
    "JOPLIN" "PRO" \
    "KEYCLOAK" "PRO" \
    "KRAYIN CRM" "PRO" \
    "KARAKEEP" "PRO" \
    "LANGFLOW" "PRO" \
    "LANGFUSE + MINIO + CLICKHOUSE*" "PRO" \
    "LIBRECHAT" "PRO" \
    "LINKWARDEN" "PRO" \
    "LISTMONK" "PRO" \
    "LITELLM" "PRO" \
    "LOBECHAT" "PRO" \
    "LOCALAI" "PRO" \
    "MATTERMOST" "PRO" \
    "MATOMO" "PRO" \
    "MAYBE" "PRO" \
    "MEILISEARCH" "PRO" \
    "MILVUS + ATTU*" "PRO" \
    "MEMOS" "PRO" \
    "MAUTIC 4 PADRÃO" "PRO" \
    "MAUTIC 4 WHATSAPP MKT" "PRO" \
    "MAUTIC 6 WHATSAPP MKT" "PRO" \
    "MAUTIC 7 WHATSAPP MKT" "PRO" \
    "MEMGRAPH" "PRO" \
    "METABASE" "PRO" \
    "NAVIDROME" "PRO" \
    "NEO4J" "PRO" \
    "NETDADA" "PRO" \
    "NEXTCLOUD" "PRO" \
    "NGINXPROXYMANAGER" "PRO" \
    "ODOO" "PRO" \
    "OPEN WEBUI" "PRO" \
    "OPENCLAW" "PRO" \
    "OPENCLAW + QDRANT + NEO4J + COGNEE + SEARXNG*" "PRO" \
    "OPENFANG" "PRO" \
    "OPENOBSERVE" "PRO" \
    "OPEN PROJECT" "PRO" \
    "OUTLINE" "PRO" \
    "PAPERCLIP" "PRO" \
    "PAPERLESS" "PRO" \
    "PENPOT" "PRO" \
    "PI-HOLE" "PRO" \
    "POCKET ID" "PRO" \
    "POCKETBASE" "PRO" \
    "PGADMIN4" "PRO" \
    "PHOTOPRISM" "PRO" \
    "REACTIVE RESUME" "PRO" \
    "ROCKET.CHAT" "PRO" \
    "SEARXNG" "PRO" \
    "SYNCTHING" "PRO" \
    "SIYUAN" "PRO" \
    "TRILIUMNEXT" "PRO" \
    "TOOLJET" "PRO" \
    "TWENTY CRM" "PRO" \
    "TYPEBOT + MINIO*" "PRO" \
    "PLANE" "PRO" \
    "PLANKA" "PRO" \
    "WEAVIATE" "PRO" \
    "WINDMILL" "PRO" \
    "WOOFED CRM" "PRO" \
    "WIKI.JS" "PRO" \
    "${CONTROL_CENTER_MFA_MENU[@]}" \
    "REINICIAR APPS/SERVIÇOS" "" \
    "DELETAR APPS/STACKS" "" \
    "GERENCIAR DOMÍNIOS CLOUDFLARE" "" \
    "GERADOR DE REGISTROS DNS" "" \
    "ESSENCIAIS EDITÁVEIS NO PORTAINER" "" \
    "DIAGNÓSTICO DE SEGURANÇA DO SERVIDOR" "" \
    "SAIR" ""  3>&2 2>&1 1>&3
)

[ -z "$CHOICE" ] && do_exit

case "$CHOICE" in
    "STRAPI") run_app strap ;;
    "CONFIGURAR MFA CONTROL CENTER") configure_control_center_mfa ;;
    "REINICIAR APPS/SERVIÇOS")  run_app restartservice ;;
    "DELETAR APPS/STACKS")      run_app uninstall ;;
    "GERENCIAR DOMÍNIOS CLOUDFLARE") manage_cloudflare_domains ;;
    "GERADOR DE REGISTROS DNS") run_app geracloudflare ;;
    "ESSENCIAIS EDITÁVEIS NO PORTAINER") run_app essenciais ;;
    "DIAGNÓSTICO DE SEGURANÇA DO SERVIDOR") run_app securitydiagnostic ;;
    "SAIR") do_exit ;;
    *)
        if check_already_installed "$CHOICE"; then
            whiptail --msgbox "Aviso: ${CHOICE} já está instalado. Não é permitido instalar mais de uma instância.\n\nDigite ENTER para voltar ao Menu Principal." 12 70
            continue
        fi
        if [ "$CHOICE" != "SETUP MNO CONTROL CENTER" ] && [[ ("$CHOICE" == "AFFINE") || ("$CHOICE" == "APPSMITH") || ("$CHOICE" == "AUTOGEN STUDIO") || ("$CHOICE" == "BASEROW") || ("$CHOICE" == "BYTEBASE") || ("$CHOICE" == "BOTPRESS") || ("$CHOICE" == "CAL.COM") || ("$CHOICE" == "CHATWOOTN + EVOLUTIONN 2.0 + RABBITMQ + MINIO*") || ("$CHOICE" == "DOCUMENSO") || ("$CHOICE" == "DOCUSEAL") || ("$CHOICE" == "DOZZLE") || ("$CHOICE" == "EVOAI + EVOLUTION 2.0 + MINIO*") || ("$CHOICE" == "IMMICH") || ("$CHOICE" == "HOME ASSISTANT") || ("$CHOICE" == "HOMEPAGE") || ("$CHOICE" == "HOPPSCOTCH") || ("$CHOICE" == "HUMHUB") || ("$CHOICE" == "KRAYIN CRM") || ("$CHOICE" == "LANGFUSE + MINIO + CLICKHOUSE*") || ("$CHOICE" == "LITELLM") || ("$CHOICE" == "LINKWARDEN") || ("$CHOICE" == "MAUTIC 4 WHATSAPP MKT") || ("$CHOICE" == "MAUTIC 6 WHATSAPP MKT") || ("$CHOICE" == "MAUTIC 7 WHATSAPP MKT") || ("$CHOICE" == "MATOMO") || ("$CHOICE" == "NEXTCLOUD") || ("$CHOICE" == "OPEN PROJECT") || ("$CHOICE" == "TWENTY CRM") || ("$CHOICE" == "TYPEBOT + MINIO*") || ("$CHOICE" == "OPENCLAW") || ("$CHOICE" == "DISCOURSE") || ("$CHOICE" == "GHOST") || ("$CHOICE" == "GLANCE") || ("$CHOICE" == "IT-TOOLS") || ("$CHOICE" == "COGNEE") || ("$CHOICE" == "MEMGRAPH") || ("$CHOICE" == "NEO4J") || ("$CHOICE" == "NETDADA") || ("$CHOICE" == "OPENFANG") || ("$CHOICE" == "OPENOBSERVE") || ("$CHOICE" == "PAPERCLIP") || ("$CHOICE" == "NAVIDROME") || ("$CHOICE" == "SEARXNG") || ("$CHOICE" == "SYNCTHING") || ("$CHOICE" == "OPENCLAW + QDRANT + NEO4J + COGNEE + SEARXNG*") || ("$CHOICE" == "HERMES AGENT") || ("$CHOICE" == "CHATWOOTORIG + EVOLUTIONN 2.0 + RABBITMQ + MINIO*") || ("$CHOICE" == "CHATWOOTORIG (DESBLOQUEADO) + EVOLUTIONN 2.0 + RABBITMQ + MINIO*") || ("$CHOICE" == "CHATWOOT AI CUSTOMER SERVICE*") || ("\$CHOICE" == "DIFY") || ("\$CHOICE" == "CHANGEDETECTION.IO") ]]; then
            whiptail --msgbox "A ferramenta ${CHOICE} não está disponível no plano free.\n\nEntre em contato conosco:\n- WhatsApp: $CONTATO_WP e adquira o plano PRO.\n\nPressione ENTER para voltar ao Menu Principal." 12 70
            continue
        fi
        case "$CHOICE" in
            "AFFINE")                                                run_app affine ;;
            "ACTUAL BUDGET")                                          run_app actualbudget ;;
            "APPSMITH")                                              run_app appsmith ;;
            "AUTOGEN STUDIO")                                        run_app autogen ;;
            "BASEROW")                                               run_app baserow ;;
            "BESZEL")                                               run_app beszel ;;
            "BOOKSTACK")                                               run_app bookstack ;;
            "BOTPRESS")                                              run_app botpress ;;
            "BUDIBASE")                                              run_app budibase ;;
            "BYTEBASE")                                              run_app bytebase ;;
            "CAL.COM")                                               run_app calcom ;;
            "CHATWOOTN + EVOLUTIONN 2.0 + RABBITMQ*")               warn_heavy "Chatwoot + Evolution 2.0 + RabbitMQ" "4GB" && run_app chatwootn_evo2_rabbitmq_redisevo ;;
            "CHATWOOTN + EVOLUTIONN 2.0 + RABBITMQ + MINIO*")       warn_heavy "Chatwoot + Evolution 2.0 + RabbitMQ + MinIO" "4GB" && run_app chatwootn_evo2_rabbitmq_minio ;;
            "CHATWOOTORIG + EVOLUTIONN 2.0 + RABBITMQ + MINIO*")    warn_heavy "Chatwoot Original + Evolution 2.0 + RabbitMQ + MinIO" "4GB" && run_app chatwooto_evo2_rabbitmq_minio ;;
            "CHATWOOTORIG (DESBLOQUEADO) + EVOLUTIONN 2.0 + RABBITMQ + MINIO*") warn_heavy "Chatwoot Desbloqueado + Evolution 2.0 + RabbitMQ + MinIO" "4GB" && run_app chatwootorig_desbloq__evo2_rabbitmq_minio ;;
            "CHATWOOT AI CUSTOMER SERVICE*") warn_heavy "Chatwoot AI Customer Service" "10GB" && run_app chatwoot_ai_customer_service ;;
            "CHANGEDETECTION.IO")                                     run_app changedetection ;;
            "CLICKHOUSE")                                            run_app clickhouse ;;
            "CODE SERVER")                                           run_app codeserver ;;
            "COGNEE")                                                run_app cognee ;;
            "DATABASUS")                                             run_app databasus ;;
            "DIFY")                                                  warn_heavy "Dify" "4GB" && run_app dify ;;
            "DIRECTUS")                                              run_app directus ;;
            "DUPLICATI")                                             run_app duplicati ;;
            "DISCOURSE")                                             run_app discourse ;;
            "DOCMOST")                                               run_app docmost ;;
            "DOCUMENSO")                                             run_app documenso ;;
            "DOCUSEAL")                                              run_app docuseal ;;
            "DOZZLE")                                                run_app dozzle ;;
            "EVOAI")                                                 run_app evoai ;;
            "EVOAI + EVOLUTION 2.0 + MINIO*")                       run_app evoai_evo2_minio ;;
            "EVOLUTION 1.0 API PADRÃO")                             run_app evolutionapi ;;
            "EVOLUTION 2.0 API PADRÃO")                             run_app evolution2api ;;
            "EVOLUTION CRM")                                         warn_heavy "Evolution CRM" "10GB" && run_app evocrm ;;
            "EVOLUTION GO")                                          run_app evolutiongo ;;
            "EVO NEXUS")                                             run_app evonexus ;;
            "EXCALIDRAW")                                            run_app excalidraw ;;
            "FIRECRAWL")                                             run_app firecrawl ;;
            "FLOWISE")                                               run_app flowise ;;
            "FOCALBOARD")                                            run_app focalboard ;;
            "FRESHRSS")                                              run_app freshrss ;;
            "FILEBROWSER")                                          run_app filebrowser ;;
            "FIREFLY III")                                              run_app fireflyiii ;;
            "FORMBRICKS")                                            run_app formbricks ;;
            "GHOST")                                                 run_app ghost ;;
            "GITEA")                                                 run_app gitea ;;
            "GITLAB")                                                warn_heavy "GitLab" "4GB" && run_app gitlab ;;
            "GLANCE")                                                run_app glance ;;
            "GLPI")                                                  run_app glpi ;;
            "GRAFANA/PROMETHEUS MONITOR")                            run_app grafana ;;
            "HERMES AGENT")                                          run_app hermes ;;
            "HEYFORM")                                               run_app heyform ;;
            "HOME ASSISTANT")                                        run_app homeassistant ;;
            "HOMEPAGE")                                              run_app homepage ;;
            "HOPPSCOTCH")                                            run_app hoppscotch ;;
            "HUMHUB")                                                run_app humhub ;;
            "IMMICH")                                                warn_heavy "Immich" "6GB" && run_app immich ;;
            "INFISICAL")                                            run_app infisical ;;
            "IT-TOOLS")                                             run_app it_tools ;;
            "JITSI MEET")                                            warn_heavy "Jitsi Meet" "5GB" && run_app jitsi ;;
            "JELLYFIN")                                             run_app jellyfin ;;
            "JOPLIN")                                               run_app joplin ;;
            "KEYCLOAK")                                              run_app keycloak ;;
            "KRAYIN CRM")                                            run_app krayincrm ;;
            "KARAKEEP")                                              run_app karakeep ;;
            "LANGFLOW")                                              run_app langflow ;;
            "LANGFUSE + MINIO + CLICKHOUSE*")                       warn_heavy "Langfuse + MinIO + ClickHouse" "8GB" && run_app langfuse ;;
            "LITELLM")                                               run_app litellm ;;
            "LOCALAI")                                                run_app localai ;;
            "LIBRECHAT")                                             run_app librechat ;;
            "LINKWARDEN")                                           warn_heavy "Linkwarden" "4GB" && run_app linkwarden ;;
            "LISTMONK")                                              run_app listmonk ;;
            "LOBECHAT")                                              run_app lobechat ;;
            "MATTERMOST")                                            run_app mattermost ;;
            "MATOMO")                                                run_app matomo ;;
            "MAYBE")                                                run_app maybe ;;
            "MEILISEARCH")                                           run_app meilisearch ;;
            "MILVUS + ATTU*")                                        warn_heavy "Milvus + Attu" "4GB" && run_app milvus ;;
            "MEMOS")                                                run_app memos ;;
            "MAUTIC 4 PADRÃO")                                       warn_heavy "Mautic 4" "4.5GB" && run_app mauticpadrao ;;
            "MAUTIC 6 PADRÃO")                                       warn_heavy "Mautic 6" "6GB" && run_app mautic6padrao ;;
            "MAUTIC 7 PADRÃO")                                       warn_heavy "Mautic 7" "6GB" && run_app mautic7padrao ;;
            "MAUTIC 4 WHATSAPP MKT")                                 warn_heavy "Mautic 4 WhatsApp" "4.5GB" && run_app mautic4whatsmkt ;;
            "MAUTIC 6 WHATSAPP MKT")                                 warn_heavy "Mautic 6 WhatsApp" "6GB" && run_app mautic6whatsmkt ;;
            "MAUTIC 7 WHATSAPP MKT")                                 warn_heavy "Mautic 7 WhatsApp" "6GB" && run_app mautic7whatsmkt ;;
            "MEMGRAPH")                                              run_app memgraph ;;
            "METABASE")                                              run_app metabase ;;
            "MINIO")                                                 run_app minio ;;
            "MONGODB")                                               run_app mongodb ;;
            "MYSQL")                                                 run_app mysql ;;
            "N8N V1 - SEM FILA (MAIN)")                              run_app n8nmain ;;
            "N8N V1 - FILA (QUEUE)")                                 warn_heavy "N8N (Fila)" "8GB" && run_app n8n ;;
            "N8N V2 - FILA (QUEUE)")                                 warn_heavy "N8N V2 (Fila)" "7GB" && run_app n8n2 ;;
            "N8N TEMPLATES FREE - + DE 2000 WORKFLOWS")              run_app n8n-workflows ;;
            "NAVIDROME")                                                 run_app navidrome ;;
            "NEO4J")                                                 run_app neo4j ;;
            "NETDADA")                                              run_app netdada ;;
            "NEXTCLOUD")                                             run_app nextcloud ;;
            "NGINXPROXYMANAGER")                                   run_app nginxproxymanager ;;
            "NOCODB")                                                run_app nocodb ;;
            "NOCOBASE")                                             run_app nocobase ;;
            "NTFY")                                                  run_app ntfy ;;
            "ODOO")                                                  run_app odoo ;;
            "OLLAMA + OPENWEBUI*")                                   warn_heavy "Ollama" "8GB+" && run_app ollama ;;
            "OPEN WEBUI")                                            run_app openwebui ;;
            "OPENCLAW")                                              run_app openclaw ;;
            "OPENCLAW + QDRANT + NEO4J + COGNEE + SEARXNG*")        run_app openclawpro ;;
            "OUTLINE")                                               run_app outline ;;
            "OPENFANG")                                              run_app openfang ;;
            "OPENOBSERVE")                                          warn_heavy "OpenObserve" "4GB" && run_app openobserve ;;
            "OPEN PROJECT")                                          run_app openproject ;;
            "PAPERCLIP")                                             run_app paperclip ;;
            "PAPERLESS")                                               run_app paperless ;;
            "PENPOT")                                                warn_heavy "Penpot" "4GB" && run_app penpot ;;
            "PI-HOLE")                                               run_app pihole ;;
            "POCKET ID")                                           run_app pocketid ;;
            "POCKETBASE")                                           run_app pocketbase ;;
            "ROCKET.CHAT")                                           run_app rocketchat ;;
            "PGADMIN4")                                              run_app pgadmin ;;
            "PHOTOPRISM")                                           warn_heavy "PhotoPrism" "2GB" && run_app photoprism ;;
            "PLANKA")                                               run_app planka ;;
            "PLANE")                                                run_app plane ;;
            "PHPMYADMIN")                                            run_app pma ;;
            "QDRANT")                                                run_app qdrant ;;
            "CHROMADB")                                              run_app chromadb ;;
            "RABBITMQ")                                              run_app rabbitmq ;;
            "REACTIVE RESUME")                                      run_app reactiveresume ;;
            "TOOLJET")                                              warn_heavy "ToolJet" "2GB" && run_app tooljet ;;
            "REDIS")                                                 run_app redis ;;
            "REDIS COMMANDER")                                       run_app redicommander ;;
            "REDISINSIGHT")                                          run_app redisinsight ;;
            "SEARXNG")                                               run_app searxng ;;
            "SETUP MNO CONTROL CENTER")                              run_app setupmno_control ;;
            "SYNCTHING")                                             run_app syncthing ;;
            "SHLINK")                                                run_app shlink ;;
            "SIYUAN")                                                run_app siyuan ;;
            "STIRLING PDF")                                          run_app stirlingpdf ;;
            "SUPERSET")                                             run_app superset ;;
            "TRILIUMNEXT")                                           run_app triliumnext ;;
            "TWENTY CRM")                                            warn_heavy "Twenty CRM" "5GB" && run_app twentycrm ;;
            "TYPEBOT")                                               run_app typebot ;;
            "UMAMI")                                                 run_app umami ;;
            "TYPEBOT + MINIO*")                                      run_app typebot_minio ;;
            "UPTIMEKUMA")                                            run_app uptimekuma ;;
            "WAHA API")                                             run_app waha ;;
            "VAULTWARDEN")                                           run_app vaultwarden ;;
            "VIKUNJA")                                               run_app vikunja ;;
            "VLLM")                                                  run_app vllm ;;
            "WEAVIATE")                                             run_app weaviate ;;
            "WINDMILL")                                             run_app windmill ;;
            "WOOFED CRM")                                            run_app woofedcrm ;;
            "WORDPRESS")                                             run_app wordpress ;;
            "WIKI.JS")                                               run_app wikijs ;;
            "WUZAP")                                                 run_app wuzap ;;
            "WEKAN")                                                 run_app wekan ;;
        esac
        ;;
esac

fi

if [ "$PLANO" == "free1" ]; then
CHOICE=$(
whiptail --title "$TITULO" --menu "Selecione um App: Use as setas do teclado e pressione ENTER" 20 70 10 \
    "DATABASUS" ""   \
    "EVOLUTION 2.0 API PADRÃO" ""  \
    "EVOLUTION CRM" ""  \
    "EVOLUTION GO" ""  \
    "EVO NEXUS" ""  \
    "MINIO" "" \
    "N8N V1 - SEM FILA (MAIN)" "" \
    "N8N V1 - FILA (QUEUE)" "" \
    "N8N V2 - FILA (QUEUE)" "" \
    "PGADMIN4" "" \
    "REDIS" "" \
    "${CONTROL_CENTER_FREE_MENU[@]}" \
    "WAHA API" "" \
    "─────────────────────────" "" \
    "ACTIVEPIECES" "PRO" \
    "ADGUARDHOME" "PRO" \
    "AFFINE" "PRO" \
    "ACTUAL BUDGET" "PRO" \
    "APPSMITH" "PRO" \
    "AUTOGEN STUDIO" "PRO" \
    "BASEROW" "PRO" \
    "BESZEL" "PRO" \
    "BOOKSTACK" "PRO" \
    "BOTPRESS" "PRO" \
    "BUDIBASE" "PRO" \
    "BYTEBASE" "PRO" \
    "CAL.COM" "PRO"  \
    "CHATWOOTN + EVOLUTIONN 2.0 + RABBITMQ*" "PRO"   \
    "CHATWOOTN + EVOLUTIONN 2.0 + RABBITMQ + MINIO*" "PRO"   \
    "CHATWOOTORIG + EVOLUTIONN 2.0 + RABBITMQ + MINIO*" "PRO"   \
    "CHATWOOTORIG (DESBLOQUEADO) + EVOLUTIONN 2.0 + RABBITMQ + MINIO*" "PRO"   \
    "CHATWOOT AI CUSTOMER SERVICE*" "PRO"   \
    "CHANGEDETECTION.IO" "PRO"   \
    "CHROMADB" "PRO"   \
    "CLICKHOUSE" "PRO"   \
    "CODE SERVER" "PRO"   \
    "COGNEE" "PRO"   \
    "DIFY" "PRO"   \
    "DIRECTUS" "PRO" \
    "DISCOURSE" "PRO" \
    "DOCMOST" "PRO" \
    "DUPLICATI" "PRO" \
    "DOCUMENSO" "PRO" \
    "DOCUSEAL" "PRO" \
    "DOZZLE" "PRO" \
    "EVOAI" "PRO"  \
    "EVOAI + EVOLUTION 2.0 + MINIO*" "PRO"  \
    "EVOLUTION 1.0 API PADRÃO" "PRO"  \
    "EXCALIDRAW" "PRO" \
    "FIRECRAWL" "PRO" \
    "FLOWISE" "PRO" \
    "FOCALBOARD" "PRO" \
    "FIREFLY III" "PRO" \
    "FORMBRICKS" "PRO" \
    "GHOST" "PRO" \
    "GLANCE" "PRO" \
    "GLPI" "PRO" \
    "GRAFANA/PROMETHEUS MONITOR" "PRO"   \
    "HERMES AGENT" "PRO" \
    "HEYFORM" "PRO" \
    "HOME ASSISTANT" "PRO" \
    "HOMEPAGE" "PRO" \
    "HOPPSCOTCH" "PRO" \
    "HUMHUB" "PRO" \
    "IMMICH" "PRO" \
    "INFISICAL" "PRO" \
    "IT-TOOLS" "PRO" \
    "JITSI MEET" "PRO" \
    "JELLYFIN" "PRO" \
    "JOPLIN" "PRO" \
    "KEYCLOAK" "PRO" \
    "KRAYIN CRM" "PRO" \
    "KARAKEEP" "PRO" \
    "LANGFLOW" "PRO" \
    "LANGFUSE + MINIO + CLICKHOUSE*" "PRO" \
    "LIBRECHAT" "PRO" \
    "LINKWARDEN" "PRO" \
    "LISTMONK" "PRO" \
    "LITELLM" "PRO" \
    "LOBECHAT" "PRO" \
    "MATTERMOST" "PRO" \
    "MATOMO" "PRO" \
    "MAYBE" "PRO" \
    "MEILISEARCH" "PRO" \
    "MILVUS + ATTU*" "PRO" \
    "MEMOS" "PRO" \
    "MAUTIC 4 PADRÃO" "PRO" \
    "MAUTIC 6 PADRÃO" "PRO" \
    "MAUTIC 7 PADRÃO" "PRO" \
    "MAUTIC 4 WHATSAPP MKT" "PRO" \
    "MAUTIC 6 WHATSAPP MKT" "PRO" \
    "MAUTIC 7 WHATSAPP MKT" "PRO" \
    "MEMGRAPH" "PRO" \
    "METABASE" "PRO" \
    "MONGODB" "PRO" \
    "MYSQL" "PRO" \
    "N8N TEMPLATES FREE - + DE 2000 WORKFLOWS" "PRO" \
    "NAVIDROME" "PRO" \
    "NEO4J" "PRO" \
    "NETDADA" "PRO" \
    "NEXTCLOUD" "PRO" \
    "NGINXPROXYMANAGER" "PRO" \
    "NOCODB" "PRO" \
    "NOCOBASE" "PRO" \
    "NTFY" "PRO" \
    "ODOO" "PRO" \
    "OLLAMA + OPENWEBUI*" "PRO" \
    "OPEN WEBUI" "PRO" \
    "OPENCLAW" "PRO" \
    "OPENCLAW + QDRANT + NEO4J + COGNEE + SEARXNG*" "PRO" \
    "OPENFANG" "PRO" \
    "OPENOBSERVE" "PRO" \
    "OPEN PROJECT" "PRO" \
    "PAPERCLIP" "PRO" \
    "PAPERLESS" "PRO" \
    "PENPOT" "PRO" \
    "PHOTOPRISM" "PRO" \
    "PI-HOLE" "PRO" \
    "POCKET ID" "PRO" \
    "POCKETBASE" "PRO" \
    "PHPMYADMIN" "PRO" \
    "PLANE" "PRO" \
    "PLANKA" "PRO" \
    "QDRANT" "PRO" \
    "RABBITMQ" "PRO" \
    "REACTIVE RESUME" "PRO" \
    "REDIS COMMANDER" "PRO" \
    "REDISINSIGHT" "PRO" \
    "SEARXNG" "PRO" \
    "SYNCTHING" "PRO" \
    "SHLINK" "PRO" \
    "SIYUAN" "PRO" \
    "STRAPI" "PRO" \
    "STIRLING PDF" "PRO" \
    "TOOLJET" "PRO" \
    "SUPERSET" "PRO" \
    "TRILIUMNEXT" "PRO" \
    "TWENTY CRM" "PRO" \
    "TYPEBOT" "PRO" \
    "UMAMI" "PRO" \
    "TYPEBOT + MINIO*" "PRO" \
    "UPTIMEKUMA" "PRO" \
    "VAULTWARDEN" "PRO" \
    "VIKUNJA" "PRO" \
    "VLLM" "PRO" \
    "WEAVIATE" "PRO" \
    "WINDMILL" "PRO" \
    "WOOFED CRM" "PRO" \
    "WORDPRESS" "PRO" \
    "WIKI.JS" "PRO" \
    "WUZAP" "PRO" \
    "WEKAN" "PRO" \
    "${CONTROL_CENTER_MFA_MENU[@]}" \
    "REINICIAR APPS/SERVIÇOS" "" \
    "DELETAR APPS/STACKS" "" \
    "GERENCIAR DOMÍNIOS CLOUDFLARE" "" \
    "GERADOR DE REGISTROS DNS" "" \
    "ESSENCIAIS EDITÁVEIS NO PORTAINER" "" \
    "DIAGNÓSTICO DE SEGURANÇA DO SERVIDOR" "" \
    "SAIR" ""  3>&2 2>&1 1>&3
)

[ -z "$CHOICE" ] && do_exit

case "$CHOICE" in
    "STRAPI") run_app strap ;;
    "CONFIGURAR MFA CONTROL CENTER") configure_control_center_mfa ;;
    "REINICIAR APPS/SERVIÇOS")  run_app restartservice ;;
    "DELETAR APPS/STACKS")      run_app uninstall ;;
    "GERENCIAR DOMÍNIOS CLOUDFLARE") manage_cloudflare_domains ;;
    "GERADOR DE REGISTROS DNS") run_app geracloudflare ;;
    "ESSENCIAIS EDITÁVEIS NO PORTAINER") run_app essenciais ;;
    "DIAGNÓSTICO DE SEGURANÇA DO SERVIDOR") run_app securitydiagnostic ;;
    "SAIR") do_exit ;;
    *)
        if check_already_installed "$CHOICE"; then
            whiptail --msgbox "Aviso: ${CHOICE} já está instalado. Não é permitido instalar mais de uma instância.\n\nDigite ENTER para voltar ao Menu Principal." 12 70
            continue
        fi
        if [ "$CHOICE" != "SETUP MNO CONTROL CENTER" ] && [[ ("$CHOICE" != "DATABASUS") && ("$CHOICE" != "EVOLUTION 2.0 API PADRÃO") && ("$CHOICE" != "N8N V1 - SEM FILA (MAIN)") && ("$CHOICE" != "N8N V1 - FILA (QUEUE)") && ("$CHOICE" != "N8N V2 - FILA (QUEUE)") && ("$CHOICE" != "PGADMIN4") && ("$CHOICE" != "MINIO") && ("$CHOICE" != "REDIS") && ("$CHOICE" != "EVOLUTION CRM") && ("$CHOICE" != "EVOLUTION GO") && ("$CHOICE" != "EVO NEXUS") && ("$CHOICE" != "WAHA API") ]]; then
            whiptail --msgbox "A ferramenta ${CHOICE} não está disponível no plano free1.\n\nEntre em contato conosco:\n- WhatsApp: $CONTATO_WP e adquira o plano PRO.\n\nPressione ENTER para voltar ao Menu Principal." 12 70
            continue
        fi
        case "$CHOICE" in
            "AFFINE")                                                run_app affine ;;
            "ACTUAL BUDGET")                                          run_app actualbudget ;;
            "APPSMITH")                                              run_app appsmith ;;
            "AUTOGEN STUDIO")                                        run_app autogen ;;
            "BASEROW")                                               run_app baserow ;;
            "BESZEL")                                               run_app beszel ;;
            "BOOKSTACK")                                               run_app bookstack ;;
            "BOTPRESS")                                              run_app botpress ;;
            "BUDIBASE")                                              run_app budibase ;;
            "BYTEBASE")                                              run_app bytebase ;;
            "CAL.COM")                                               run_app calcom ;;
            "CHATWOOTN + EVOLUTIONN 2.0 + RABBITMQ*")               warn_heavy "Chatwoot + Evolution 2.0 + RabbitMQ" "4GB" && run_app chatwootn_evo2_rabbitmq_redisevo ;;
            "CHATWOOTN + EVOLUTIONN 2.0 + RABBITMQ + MINIO*")       warn_heavy "Chatwoot + Evolution 2.0 + RabbitMQ + MinIO" "4GB" && run_app chatwootn_evo2_rabbitmq_minio ;;
            "CHATWOOTORIG + EVOLUTIONN 2.0 + RABBITMQ + MINIO*")    warn_heavy "Chatwoot Original + Evolution 2.0 + RabbitMQ + MinIO" "4GB" && run_app chatwooto_evo2_rabbitmq_minio ;;
             "CHANGEDETECTION.IO")                                     run_app changedetection ;;
             "CHATWOOTORIG (DESBLOQUEADO) + EVOLUTIONN 2.0 + RABBITMQ + MINIO*") warn_heavy "Chatwoot Desbloqueado + Evolution 2.0 + RabbitMQ + MinIO" "4GB" && run_app chatwootorig_desbloq__evo2_rabbitmq_minio ;;
             "CHATWOOT AI CUSTOMER SERVICE*") warn_heavy "Chatwoot AI Customer Service" "10GB" && run_app chatwoot_ai_customer_service ;;
             "CLICKHOUSE")                                            run_app clickhouse ;;
             "CODE SERVER")                                           run_app codeserver ;;
             "COGNEE")                                                run_app cognee ;;
             "DATABASUS")                                             run_app databasus ;;
             "DIFY")                                                  warn_heavy "Dify" "4GB" && run_app dify ;;
             "DIRECTUS")                                              run_app directus ;;
            "DUPLICATI")                                             run_app duplicati ;;
            "DISCOURSE")                                             run_app discourse ;;
            "DOCMOST")                                               run_app docmost ;;
            "DOCUMENSO")                                             run_app documenso ;;
            "DOCUSEAL")                                              run_app docuseal ;;
            "DOZZLE")                                                run_app dozzle ;;
            "EVOAI")                                                 run_app evoai ;;
            "EVOAI + EVOLUTION 2.0 + MINIO*")                       run_app evoai_evo2_minio ;;
            "EVOLUTION 1.0 API PADRÃO")                             run_app evolutionapi ;;
            "EVOLUTION 2.0 API PADRÃO")                             run_app evolution2api ;;
            "EVOLUTION CRM")                                         warn_heavy "Evolution CRM" "10GB" && run_app evocrm ;;
            "EVOLUTION GO")                                          run_app evolutiongo ;;
            "EVO NEXUS")                                             run_app evonexus ;;
            "EXCALIDRAW")                                            run_app excalidraw ;;
            "FIRECRAWL")                                             run_app firecrawl ;;
            "FLOWISE")                                               run_app flowise ;;
            "FOCALBOARD")                                            run_app focalboard ;;
            "FRESHRSS")                                              run_app freshrss ;;
            "FILEBROWSER")                                          run_app filebrowser ;;
            "FIREFLY III")                                              run_app fireflyiii ;;
            "FORMBRICKS")                                            run_app formbricks ;;
            "GHOST")                                                 run_app ghost ;;
            "GITEA")                                                 run_app gitea ;;
            "GITLAB")                                                warn_heavy "GitLab" "4GB" && run_app gitlab ;;
            "GLANCE")                                                run_app glance ;;
            "GLPI")                                                  run_app glpi ;;
            "GRAFANA/PROMETHEUS MONITOR")                            run_app grafana ;;
            "HERMES AGENT")                                          run_app hermes ;;
            "HEYFORM")                                               run_app heyform ;;
            "HOME ASSISTANT")                                        run_app homeassistant ;;
            "HOMEPAGE")                                              run_app homepage ;;
            "HOPPSCOTCH")                                            run_app hoppscotch ;;
            "HUMHUB")                                                run_app humhub ;;
            "IMMICH")                                                warn_heavy "Immich" "6GB" && run_app immich ;;
            "INFISICAL")                                            run_app infisical ;;
            "IT-TOOLS")                                             run_app it_tools ;;
            "JITSI MEET")                                            warn_heavy "Jitsi Meet" "5GB" && run_app jitsi ;;
            "JELLYFIN")                                             run_app jellyfin ;;
            "JOPLIN")                                               run_app joplin ;;
            "KEYCLOAK")                                              run_app keycloak ;;
            "KRAYIN CRM")                                            run_app krayincrm ;;
            "KARAKEEP")                                              run_app karakeep ;;
            "LANGFLOW")                                              run_app langflow ;;
            "LANGFUSE + MINIO + CLICKHOUSE*")                       warn_heavy "Langfuse + MinIO + ClickHouse" "8GB" && run_app langfuse ;;
            "LITELLM")                                               run_app litellm ;;
            "LOCALAI")                                                run_app localai ;;
            "LIBRECHAT")                                             run_app librechat ;;
            "LINKWARDEN")                                           warn_heavy "Linkwarden" "4GB" && run_app linkwarden ;;
            "LISTMONK")                                              run_app listmonk ;;
            "LOBECHAT")                                              run_app lobechat ;;
            "MATTERMOST")                                            run_app mattermost ;;
            "MATOMO")                                                run_app matomo ;;
            "MAYBE")                                                run_app maybe ;;
            "MEILISEARCH")                                           run_app meilisearch ;;
            "MILVUS + ATTU*")                                        warn_heavy "Milvus + Attu" "4GB" && run_app milvus ;;
            "MEMOS")                                                run_app memos ;;
            "MAUTIC 4 PADRÃO")                                       warn_heavy "Mautic 4" "4.5GB" && run_app mauticpadrao ;;
            "MAUTIC 6 PADRÃO")                                       warn_heavy "Mautic 6" "6GB" && run_app mautic6padrao ;;
            "MAUTIC 7 PADRÃO")                                       warn_heavy "Mautic 7" "6GB" && run_app mautic7padrao ;;
            "MAUTIC 4 WHATSAPP MKT")                                 warn_heavy "Mautic 4 WhatsApp" "4.5GB" && run_app mautic4whatsmkt ;;
            "MAUTIC 6 WHATSAPP MKT")                                 warn_heavy "Mautic 6 WhatsApp" "6GB" && run_app mautic6whatsmkt ;;
            "MAUTIC 7 WHATSAPP MKT")                                 warn_heavy "Mautic 7 WhatsApp" "6GB" && run_app mautic7whatsmkt ;;
            "MEMGRAPH")                                              run_app memgraph ;;
            "METABASE")                                              run_app metabase ;;
            "MINIO")                                                 run_app minio ;;
            "MONGODB")                                               run_app mongodb ;;
            "MYSQL")                                                 run_app mysql ;;
            "N8N V1 - SEM FILA (MAIN)")                              run_app n8nmain ;;
            "N8N V1 - FILA (QUEUE)")                                 warn_heavy "N8N (Fila)" "8GB" && run_app n8n ;;
            "N8N V2 - FILA (QUEUE)")                                 warn_heavy "N8N V2 (Fila)" "7GB" && run_app n8n2 ;;
            "N8N TEMPLATES FREE - + DE 2000 WORKFLOWS")              run_app n8n-workflows ;;
            "NAVIDROME")                                                 run_app navidrome ;;
            "NEO4J")                                                 run_app neo4j ;;
            "NETDADA")                                              run_app netdada ;;
            "NEXTCLOUD")                                             run_app nextcloud ;;
            "NGINXPROXYMANAGER")                                   run_app nginxproxymanager ;;
            "NOCODB")                                                run_app nocodb ;;
            "NOCOBASE")                                             run_app nocobase ;;
            "NTFY")                                                  run_app ntfy ;;
            "ODOO")                                                  run_app odoo ;;
            "OLLAMA + OPENWEBUI*")                                   warn_heavy "Ollama" "8GB+" && run_app ollama ;;
            "OPEN WEBUI")                                            run_app openwebui ;;
            "OPENCLAW")                                              run_app openclaw ;;
            "OPENCLAW + QDRANT + NEO4J + COGNEE + SEARXNG*")        run_app openclawpro ;;
            "OUTLINE")                                               run_app outline ;;
            "OPENFANG")                                              run_app openfang ;;
            "OPENOBSERVE")                                          warn_heavy "OpenObserve" "4GB" && run_app openobserve ;;
            "OPEN PROJECT")                                          run_app openproject ;;
            "PAPERCLIP")                                             run_app paperclip ;;
            "PAPERLESS")                                               run_app paperless ;;
            "PENPOT")                                                warn_heavy "Penpot" "4GB" && run_app penpot ;;
            "PI-HOLE")                                               run_app pihole ;;
            "POCKET ID")                                           run_app pocketid ;;
            "POCKETBASE")                                           run_app pocketbase ;;
            "ROCKET.CHAT")                                           run_app rocketchat ;;
            "PGADMIN4")                                              run_app pgadmin ;;
            "PHOTOPRISM")                                           warn_heavy "PhotoPrism" "2GB" && run_app photoprism ;;
            "PLANKA")                                               run_app planka ;;
            "PLANE")                                                run_app plane ;;
            "PHPMYADMIN")                                            run_app pma ;;
            "QDRANT")                                                run_app qdrant ;;
            "CHROMADB")                                              run_app chromadb ;;
            "RABBITMQ")                                              run_app rabbitmq ;;
            "REACTIVE RESUME")                                      run_app reactiveresume ;;
            "TOOLJET")                                              warn_heavy "ToolJet" "2GB" && run_app tooljet ;;
            "REDIS")                                                 run_app redis ;;
            "REDIS COMMANDER")                                       run_app redicommander ;;
            "REDISINSIGHT")                                          run_app redisinsight ;;
            "SEARXNG")                                               run_app searxng ;;
            "SETUP MNO CONTROL CENTER")                              run_app setupmno_control ;;
            "SYNCTHING")                                             run_app syncthing ;;
            "SHLINK")                                                run_app shlink ;;
            "SIYUAN")                                                run_app siyuan ;;
            "STIRLING PDF")                                          run_app stirlingpdf ;;
            "SUPERSET")                                             run_app superset ;;
            "TRILIUMNEXT")                                           run_app triliumnext ;;
            "TWENTY CRM")                                            warn_heavy "Twenty CRM" "5GB" && run_app twentycrm ;;
            "TYPEBOT")                                               run_app typebot ;;
            "UMAMI")                                                 run_app umami ;;
            "TYPEBOT + MINIO*")                                      run_app typebot_minio ;;
            "UPTIMEKUMA")                                            run_app uptimekuma ;;
            "WAHA API")                                             run_app waha ;;
            "VAULTWARDEN")                                           run_app vaultwarden ;;
            "VIKUNJA")                                               run_app vikunja ;;
            "VLLM")                                                  run_app vllm ;;
            "WEAVIATE")                                             run_app weaviate ;;
            "WINDMILL")                                             run_app windmill ;;
            "WOOFED CRM")                                            run_app woofedcrm ;;
            "WORDPRESS")                                             run_app wordpress ;;
            "WIKI.JS")                                               run_app wikijs ;;
            "WUZAP")                                                 run_app wuzap ;;
            "WEKAN")                                                 run_app wekan ;;
        esac
        ;;
esac

fi

if [ "$PLANO" == "free2" ]; then
CHOICE=$(
whiptail --title "$TITULO" --menu "Selecione um App: Use as setas do teclado e pressione ENTER" 20 70 10 \
    "EVOLUTION 2.0 API PADRÃO" ""  \
    "EVOLUTION CRM" ""  \
    "EVOLUTION GO" ""  \
    "EVO NEXUS" ""  \
    "MINIO" "" \
    "N8N V1 - SEM FILA (MAIN)" "" \
    "N8N V1 - FILA (QUEUE)" "" \
    "N8N V2 - FILA (QUEUE)" "" \
    "OPENCLAW" "" \
    "PGADMIN4" "" \
    "REDIS" "" \
    "${CONTROL_CENTER_FREE_MENU[@]}" \
    "WAHA API" "" \
    "─────────────────────────" "" \
    "ACTIVEPIECES" "PRO" \
    "ADGUARDHOME" "PRO" \
    "AFFINE" "PRO" \
    "ACTUAL BUDGET" "PRO" \
    "APPSMITH" "PRO" \
    "AUTOGEN STUDIO" "PRO" \
    "BASEROW" "PRO" \
    "BESZEL" "PRO" \
    "BOOKSTACK" "PRO" \
    "BOTPRESS" "PRO" \
    "BUDIBASE" "PRO" \
    "BYTEBASE" "PRO" \
    "CAL.COM" "PRO"  \
    "CHATWOOTN + EVOLUTIONN 2.0 + RABBITMQ*" "PRO"   \
    "CHATWOOTN + EVOLUTIONN 2.0 + RABBITMQ + MINIO*" "PRO"   \
    "CHATWOOTORIG + EVOLUTIONN 2.0 + RABBITMQ + MINIO*" "PRO"   \
    "CHATWOOTORIG (DESBLOQUEADO) + EVOLUTIONN 2.0 + RABBITMQ + MINIO*" "PRO"   \
    "CHATWOOT AI CUSTOMER SERVICE*" "PRO"   \
    "CHANGEDETECTION.IO" "PRO"   \
    "CHROMADB" "PRO"   \
    "CLICKHOUSE" "PRO"   \
    "CODE SERVER" "PRO"   \
    "COGNEE" "PRO"   \
    "DATABASUS" "PRO"   \
    "DIFY" "PRO"   \
    "DIRECTUS" "PRO" \
    "DISCOURSE" "PRO" \
    "DOCMOST" "PRO" \
    "DUPLICATI" "PRO" \
    "DOCUMENSO" "PRO" \
    "DOCUSEAL" "PRO" \
    "DOZZLE" "PRO" \
    "EVOAI" "PRO"  \
    "EVOAI + EVOLUTION 2.0 + MINIO*" "PRO"  \
    "EVOLUTION 1.0 API PADRÃO" "PRO"  \
    "EXCALIDRAW" "PRO" \
    "FIRECRAWL" "PRO" \
    "FLOWISE" "PRO" \
    "FOCALBOARD" "PRO" \
    "FIREFLY III" "PRO" \
    "FORMBRICKS" "PRO" \
    "GHOST" "PRO" \
    "GLANCE" "PRO" \
    "GLPI" "PRO" \
    "GRAFANA/PROMETHEUS MONITOR" "PRO"   \
    "HERMES AGENT" "PRO" \
    "HEYFORM" "PRO" \
    "HOME ASSISTANT" "PRO" \
    "HOMEPAGE" "PRO" \
    "HOPPSCOTCH" "PRO" \
    "HUMHUB" "PRO" \
    "IMMICH" "PRO" \
    "INFISICAL" "PRO" \
    "IT-TOOLS" "PRO" \
    "JITSI MEET" "PRO" \
    "JELLYFIN" "PRO" \
    "JOPLIN" "PRO" \
    "KEYCLOAK" "PRO" \
    "KRAYIN CRM" "PRO" \
    "KARAKEEP" "PRO" \
    "LANGFLOW" "PRO" \
    "LANGFUSE + MINIO + CLICKHOUSE*" "PRO" \
    "LIBRECHAT" "PRO" \
    "LINKWARDEN" "PRO" \
    "LISTMONK" "PRO" \
    "LITELLM" "PRO" \
    "LOBECHAT" "PRO" \
    "MATTERMOST" "PRO" \
    "MATOMO" "PRO" \
    "MAYBE" "PRO" \
    "MEILISEARCH" "PRO" \
    "MILVUS + ATTU*" "PRO" \
    "MEMOS" "PRO" \
    "MAUTIC 4 PADRÃO" "PRO" \
    "MAUTIC 6 PADRÃO" "PRO" \
    "MAUTIC 7 PADRÃO" "PRO" \
    "MAUTIC 4 WHATSAPP MKT" "PRO" \
    "MAUTIC 6 WHATSAPP MKT" "PRO" \
    "MAUTIC 7 WHATSAPP MKT" "PRO" \
    "MEMGRAPH" "PRO" \
    "METABASE" "PRO" \
    "MONGODB" "PRO" \
    "MYSQL" "PRO" \
    "N8N TEMPLATES FREE - + DE 2000 WORKFLOWS" "PRO" \
    "NAVIDROME" "PRO" \
    "NEO4J" "PRO" \
    "NETDADA" "PRO" \
    "NEXTCLOUD" "PRO" \
    "NGINXPROXYMANAGER" "PRO" \
    "NOCODB" "PRO" \
    "NOCOBASE" "PRO" \
    "NTFY" "PRO" \
    "ODOO" "PRO" \
    "OLLAMA + OPENWEBUI*" "PRO" \
    "OPEN WEBUI" "PRO" \
    "OPENCLAW + QDRANT + NEO4J + COGNEE + SEARXNG*" "PRO" \
    "OPENFANG" "PRO" \
    "OPENOBSERVE" "PRO" \
    "OPEN PROJECT" "PRO" \
    "PAPERCLIP" "PRO" \
    "PAPERLESS" "PRO" \
    "PENPOT" "PRO" \
    "PHOTOPRISM" "PRO" \
    "PI-HOLE" "PRO" \
    "POCKET ID" "PRO" \
    "POCKETBASE" "PRO" \
    "PLANE" "PRO" \
    "PHPMYADMIN" "PRO" \
    "PLANKA" "PRO" \
    "QDRANT" "PRO" \
    "RABBITMQ" "PRO" \
    "REACTIVE RESUME" "PRO" \
    "REDIS COMMANDER" "PRO" \
    "REDISINSIGHT" "PRO" \
    "SEARXNG" "PRO" \
    "SYNCTHING" "PRO" \
    "SHLINK" "PRO" \
    "SIYUAN" "PRO" \
    "STRAPI" "PRO" \
    "STIRLING PDF" "PRO" \
    "TOOLJET" "PRO" \
    "SUPERSET" "PRO" \
    "TRILIUMNEXT" "PRO" \
    "TWENTY CRM" "PRO" \
    "TYPEBOT" "PRO" \
    "UMAMI" "PRO" \
    "TYPEBOT + MINIO*" "PRO" \
    "UPTIMEKUMA" "PRO" \
    "VAULTWARDEN" "PRO" \
    "VIKUNJA" "PRO" \
    "VLLM" "PRO" \
    "WEAVIATE" "PRO" \
    "WINDMILL" "PRO" \
    "WOOFED CRM" "PRO" \
    "WORDPRESS" "PRO" \
    "WIKI.JS" "PRO" \
    "WUZAP" "PRO" \
    "WEKAN" "PRO" \
    "${CONTROL_CENTER_MFA_MENU[@]}" \
    "REINICIAR APPS/SERVIÇOS" "" \
    "DELETAR APPS/STACKS" "" \
    "GERENCIAR DOMÍNIOS CLOUDFLARE" "" \
    "GERADOR DE REGISTROS DNS" "" \
    "ESSENCIAIS EDITÁVEIS NO PORTAINER" "" \
    "DIAGNÓSTICO DE SEGURANÇA DO SERVIDOR" "" \
    "SAIR" ""  3>&2 2>&1 1>&3
)

[ -z "$CHOICE" ] && do_exit

case "$CHOICE" in
    "STRAPI") run_app strap ;;
    "CONFIGURAR MFA CONTROL CENTER") configure_control_center_mfa ;;
    "REINICIAR APPS/SERVIÇOS")  run_app restartservice ;;
    "DELETAR APPS/STACKS")      run_app uninstall ;;
    "GERENCIAR DOMÍNIOS CLOUDFLARE") manage_cloudflare_domains ;;
    "GERADOR DE REGISTROS DNS") run_app geracloudflare ;;
    "ESSENCIAIS EDITÁVEIS NO PORTAINER") run_app essenciais ;;
    "DIAGNÓSTICO DE SEGURANÇA DO SERVIDOR") run_app securitydiagnostic ;;
    "SAIR") do_exit ;;
    *)
        if check_already_installed "$CHOICE"; then
            whiptail --msgbox "Aviso: ${CHOICE} já está instalado. Não é permitido instalar mais de uma instância.\n\nDigite ENTER para voltar ao Menu Principal." 12 70
            continue
        fi
        if [ "$CHOICE" != "SETUP MNO CONTROL CENTER" ] && [[ ("$CHOICE" != "OPENCLAW") && ("$CHOICE" != "EVOLUTION 2.0 API PADRÃO") && ("$CHOICE" != "N8N V1 - SEM FILA (MAIN)") && ("$CHOICE" != "N8N V1 - FILA (QUEUE)") && ("$CHOICE" != "N8N V2 - FILA (QUEUE)") && ("$CHOICE" != "PGADMIN4") && ("$CHOICE" != "MINIO") && ("$CHOICE" != "REDIS") && ("$CHOICE" != "EVOLUTION CRM") && ("$CHOICE" != "EVOLUTION GO") && ("$CHOICE" != "EVO NEXUS") && ("$CHOICE" != "WAHA API") ]]; then
            whiptail --msgbox "A ferramenta ${CHOICE} não está disponível no plano free2.\n\nEntre em contato conosco:\n- WhatsApp: $CONTATO_WP e adquira o plano PRO.\n\nPressione ENTER para voltar ao Menu Principal." 12 70
            continue
        fi
        case "$CHOICE" in
            "AFFINE")                                                run_app affine ;;
            "ACTUAL BUDGET")                                          run_app actualbudget ;;
            "APPSMITH")                                              run_app appsmith ;;
            "AUTOGEN STUDIO")                                        run_app autogen ;;
            "BASEROW")                                               run_app baserow ;;
            "BESZEL")                                               run_app beszel ;;
            "BOOKSTACK")                                               run_app bookstack ;;
            "BOTPRESS")                                              run_app botpress ;;
            "BUDIBASE")                                              run_app budibase ;;
            "BYTEBASE")                                              run_app bytebase ;;
            "CAL.COM")                                               run_app calcom ;;
            "CHATWOOTN + EVOLUTIONN 2.0 + RABBITMQ*")               warn_heavy "Chatwoot + Evolution 2.0 + RabbitMQ" "4GB" && run_app chatwootn_evo2_rabbitmq_redisevo ;;
             "CHANGEDETECTION.IO")                                     run_app changedetection ;;
             "CHATWOOTN + EVOLUTIONN 2.0 + RABBITMQ + MINIO*")       warn_heavy "Chatwoot + Evolution 2.0 + RabbitMQ + MinIO" "4GB" && run_app chatwootn_evo2_rabbitmq_minio ;;
             "CHATWOOTORIG + EVOLUTIONN 2.0 + RABBITMQ + MINIO*")    warn_heavy "Chatwoot Original + Evolution 2.0 + RabbitMQ + MinIO" "4GB" && run_app chatwooto_evo2_rabbitmq_minio ;;
             "CHATWOOTORIG (DESBLOQUEADO) + EVOLUTIONN 2.0 + RABBITMQ + MINIO*") warn_heavy "Chatwoot Desbloqueado + Evolution 2.0 + RabbitMQ + MinIO" "4GB" && run_app chatwootorig_desbloq__evo2_rabbitmq_minio ;;
             "CHATWOOT AI CUSTOMER SERVICE*") warn_heavy "Chatwoot AI Customer Service" "10GB" && run_app chatwoot_ai_customer_service ;;
             "CLICKHOUSE")                                            run_app clickhouse ;;
             "CODE SERVER")                                           run_app codeserver ;;
             "COGNEE")                                                run_app cognee ;;
             "DATABASUS")                                             run_app databasus ;;
             "DIFY")                                                  warn_heavy "Dify" "4GB" && run_app dify ;;
             "DIRECTUS")                                              run_app directus ;;
            "DUPLICATI")                                             run_app duplicati ;;
            "DISCOURSE")                                             run_app discourse ;;
            "DOCMOST")                                               run_app docmost ;;
            "DOCUMENSO")                                             run_app documenso ;;
            "DOCUSEAL")                                              run_app docuseal ;;
            "DOZZLE")                                                run_app dozzle ;;
            "EVOAI")                                                 run_app evoai ;;
            "EVOAI + EVOLUTION 2.0 + MINIO*")                       run_app evoai_evo2_minio ;;
            "EVOLUTION 1.0 API PADRÃO")                             run_app evolutionapi ;;
            "EVOLUTION 2.0 API PADRÃO")                             run_app evolution2api ;;
            "EVOLUTION CRM")                                         warn_heavy "Evolution CRM" "10GB" && run_app evocrm ;;
            "EVOLUTION GO")                                          run_app evolutiongo ;;
            "EVO NEXUS")                                             run_app evonexus ;;
            "EXCALIDRAW")                                            run_app excalidraw ;;
            "FIRECRAWL")                                             run_app firecrawl ;;
            "FLOWISE")                                               run_app flowise ;;
            "FOCALBOARD")                                            run_app focalboard ;;
            "FRESHRSS")                                              run_app freshrss ;;
            "FILEBROWSER")                                          run_app filebrowser ;;
            "FIREFLY III")                                              run_app fireflyiii ;;
            "FORMBRICKS")                                            run_app formbricks ;;
            "GHOST")                                                 run_app ghost ;;
            "GITEA")                                                 run_app gitea ;;
            "GITLAB")                                                warn_heavy "GitLab" "4GB" && run_app gitlab ;;
            "GLANCE")                                                run_app glance ;;
            "GLPI")                                                  run_app glpi ;;
            "GRAFANA/PROMETHEUS MONITOR")                            run_app grafana ;;
            "HERMES AGENT")                                          run_app hermes ;;
            "HEYFORM")                                               run_app heyform ;;
            "HOME ASSISTANT")                                        run_app homeassistant ;;
            "HOMEPAGE")                                              run_app homepage ;;
            "HOPPSCOTCH")                                            run_app hoppscotch ;;
            "HUMHUB")                                                run_app humhub ;;
            "IMMICH")                                                warn_heavy "Immich" "6GB" && run_app immich ;;
            "INFISICAL")                                            run_app infisical ;;
            "IT-TOOLS")                                             run_app it_tools ;;
            "JITSI MEET")                                            warn_heavy "Jitsi Meet" "5GB" && run_app jitsi ;;
            "JELLYFIN")                                             run_app jellyfin ;;
            "JOPLIN")                                               run_app joplin ;;
            "KEYCLOAK")                                              run_app keycloak ;;
            "KRAYIN CRM")                                            run_app krayincrm ;;
            "KARAKEEP")                                              run_app karakeep ;;
            "LANGFLOW")                                              run_app langflow ;;
            "LANGFUSE + MINIO + CLICKHOUSE*")                       warn_heavy "Langfuse + MinIO + ClickHouse" "8GB" && run_app langfuse ;;
            "LITELLM")                                               run_app litellm ;;
            "LOCALAI")                                                run_app localai ;;
            "LIBRECHAT")                                             run_app librechat ;;
            "LINKWARDEN")                                           warn_heavy "Linkwarden" "4GB" && run_app linkwarden ;;
            "LISTMONK")                                              run_app listmonk ;;
            "LOBECHAT")                                              run_app lobechat ;;
            "MATTERMOST")                                            run_app mattermost ;;
            "MATOMO")                                                run_app matomo ;;
            "MAYBE")                                                run_app maybe ;;
            "MEILISEARCH")                                           run_app meilisearch ;;
            "MILVUS + ATTU*")                                        warn_heavy "Milvus + Attu" "4GB" && run_app milvus ;;
            "MEMOS")                                                run_app memos ;;
            "MAUTIC 4 PADRÃO")                                       warn_heavy "Mautic 4" "4.5GB" && run_app mauticpadrao ;;
            "MAUTIC 6 PADRÃO")                                       warn_heavy "Mautic 6" "6GB" && run_app mautic6padrao ;;
            "MAUTIC 7 PADRÃO")                                       warn_heavy "Mautic 7" "6GB" && run_app mautic7padrao ;;
            "MAUTIC 4 WHATSAPP MKT")                                 warn_heavy "Mautic 4 WhatsApp" "4.5GB" && run_app mautic4whatsmkt ;;
            "MAUTIC 6 WHATSAPP MKT")                                 warn_heavy "Mautic 6 WhatsApp" "6GB" && run_app mautic6whatsmkt ;;
            "MAUTIC 7 WHATSAPP MKT")                                 warn_heavy "Mautic 7 WhatsApp" "6GB" && run_app mautic7whatsmkt ;;
            "MEMGRAPH")                                              run_app memgraph ;;
            "METABASE")                                              run_app metabase ;;
            "MINIO")                                                 run_app minio ;;
            "MONGODB")                                               run_app mongodb ;;
            "MYSQL")                                                 run_app mysql ;;
            "N8N V1 - SEM FILA (MAIN)")                              run_app n8nmain ;;
            "N8N V1 - FILA (QUEUE)")                                 warn_heavy "N8N (Fila)" "8GB" && run_app n8n ;;
            "N8N V2 - FILA (QUEUE)")                                 warn_heavy "N8N V2 (Fila)" "7GB" && run_app n8n2 ;;
            "N8N TEMPLATES FREE - + DE 2000 WORKFLOWS")              run_app n8n-workflows ;;
            "NAVIDROME")                                                 run_app navidrome ;;
            "NEO4J")                                                 run_app neo4j ;;
            "NETDADA")                                              run_app netdada ;;
            "NEXTCLOUD")                                             run_app nextcloud ;;
            "NGINXPROXYMANAGER")                                   run_app nginxproxymanager ;;
            "NOCODB")                                                run_app nocodb ;;
            "NOCOBASE")                                             run_app nocobase ;;
            "NTFY")                                                  run_app ntfy ;;
            "ODOO")                                                  run_app odoo ;;
            "OLLAMA + OPENWEBUI*")                                   warn_heavy "Ollama" "8GB+" && run_app ollama ;;
            "OPEN WEBUI")                                            run_app openwebui ;;
            "OPENCLAW")                                              run_app openclaw ;;
            "OPENCLAW + QDRANT + NEO4J + COGNEE + SEARXNG*")        run_app openclawpro ;;
            "OUTLINE")                                               run_app outline ;;
            "OPENFANG")                                              run_app openfang ;;
            "OPENOBSERVE")                                          warn_heavy "OpenObserve" "4GB" && run_app openobserve ;;
            "OPEN PROJECT")                                          run_app openproject ;;
            "PAPERCLIP")                                             run_app paperclip ;;
            "PAPERLESS")                                               run_app paperless ;;
            "PENPOT")                                                warn_heavy "Penpot" "4GB" && run_app penpot ;;
            "PI-HOLE")                                               run_app pihole ;;
            "POCKET ID")                                           run_app pocketid ;;
            "POCKETBASE")                                           run_app pocketbase ;;
            "ROCKET.CHAT")                                           run_app rocketchat ;;
            "PGADMIN4")                                              run_app pgadmin ;;
            "PHOTOPRISM")                                           warn_heavy "PhotoPrism" "2GB" && run_app photoprism ;;
            "PLANKA")                                               run_app planka ;;
            "PLANE")                                                run_app plane ;;
            "PHPMYADMIN")                                            run_app pma ;;
            "QDRANT")                                                run_app qdrant ;;
            "CHROMADB")                                              run_app chromadb ;;
            "RABBITMQ")                                              run_app rabbitmq ;;
            "REACTIVE RESUME")                                      run_app reactiveresume ;;
            "TOOLJET")                                              warn_heavy "ToolJet" "2GB" && run_app tooljet ;;
            "REDIS")                                                 run_app redis ;;
            "REDIS COMMANDER")                                       run_app redicommander ;;
            "REDISINSIGHT")                                          run_app redisinsight ;;
            "SEARXNG")                                               run_app searxng ;;
            "SETUP MNO CONTROL CENTER")                              run_app setupmno_control ;;
            "SYNCTHING")                                             run_app syncthing ;;
            "SHLINK")                                                run_app shlink ;;
            "SIYUAN")                                                run_app siyuan ;;
            "STIRLING PDF")                                          run_app stirlingpdf ;;
            "SUPERSET")                                             run_app superset ;;
            "TRILIUMNEXT")                                           run_app triliumnext ;;
            "TWENTY CRM")                                            warn_heavy "Twenty CRM" "5GB" && run_app twentycrm ;;
            "TYPEBOT")                                               run_app typebot ;;
            "UMAMI")                                                 run_app umami ;;
            "TYPEBOT + MINIO*")                                      run_app typebot_minio ;;
            "UPTIMEKUMA")                                            run_app uptimekuma ;;
            "WAHA API")                                             run_app waha ;;
            "VAULTWARDEN")                                           run_app vaultwarden ;;
            "VIKUNJA")                                               run_app vikunja ;;
            "VLLM")                                                  run_app vllm ;;
            "WEAVIATE")                                             run_app weaviate ;;
            "WINDMILL")                                             run_app windmill ;;
            "WOOFED CRM")                                            run_app woofedcrm ;;
            "WORDPRESS")                                             run_app wordpress ;;
            "WIKI.JS")                                               run_app wikijs ;;
            "WUZAP")                                                 run_app wuzap ;;
            "WEKAN")                                                 run_app wekan ;;
        esac
        ;;
esac

fi

done

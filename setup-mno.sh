#!/bin/bash
# ==============================================================================
# SETUP MNO OPEN-SOURCE - INSTALADOR OFICIAL EM BASH PURO (SEM SHC)
# Compatível com Debian, Ubuntu, Oracle Linux e WSL2 (x86_64 e aarch64)
# ==============================================================================
set -e

VERSIONSETUP="7.49.0"

# Cores
amarelo="\e[33m"
verde="\e[32m"
branco="\e[97m"
bege="\e[93m"
vermelho="\e[91m"
azul="\e[36m"
reset="\e[0m"

INSTALL_TYPE_FILE="/root/.cloudflared_config/installation_type"
TARGET_DIR="/root/SetupLowCodeMno"
SETUP_MNO_TMUX_SESSION_PREFIX="setup-mno"

# ------------------------------------------------------------------------------
# 1. FUNÇÕES DE DETECÇÃO DE SISTEMA, DISTRO E VIRTUALIZAÇÃO
# ------------------------------------------------------------------------------

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

setupmno_prepare_debian13_apt() {
    local root="${SETUPMNO_APT_ROOT:-}" os_release source_list keyring os_id os_version
    os_release="${root}/etc/os-release"
    source_list="${root}/etc/apt/sources.list.d/azlux.list"
    keyring="${root}/usr/share/keyrings/azlux-archive-keyring.gpg"
    [ -r "$os_release" ] || return 0
    os_id=$(sed -n 's/^ID=//p' "$os_release" | head -n1 | tr -d "\"'")
    os_version=$(sed -n 's/^VERSION_ID=//p' "$os_release" | head -n1 | tr -d "\"'")
    case "$os_id" in
        debian|ubuntu|linuxmint|pop|raspbian|armbian|kali) ;;
        *)
            local id_like
            id_like=$(sed -n 's/^ID_LIKE=//p' "$os_release" | head -n1 | tr -d "\"'" | tr '[:upper:]' '[:lower:]')
            case "$id_like" in
                *debian*|*ubuntu*) ;;
                *) return 0 ;;
            esac
            ;;
    esac
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

configure_wsl_ipv4() {
    if setupmno_is_wsl; then
        echo -e "${bege}⚠️  WSL2 detectado. Aplicando ajuste de rede no APT...${reset}"
        mkdir -p /etc/apt/apt.conf.d 2>/dev/null || true
        if [ ! -f /etc/apt/apt.conf.d/99force-ipv4 ] || ! grep -q 'Acquire::ForceIPv4 "true";' /etc/apt/apt.conf.d/99force-ipv4 2>/dev/null; then
            cat > /etc/apt/apt.conf.d/99force-ipv4 <<'EOF'
Acquire::ForceIPv4 "true";
EOF
            echo -e "${verde}✅ Fix IPv4 aplicado com sucesso.${reset}"
        else
            echo -e "${verde}✅ Fix IPv4 já estava configurado.${reset}"
        fi
        sleep 1
    fi
}

fix_wsl_clock() {
    if setupmno_is_wsl; then
        echo -e "${amarelo}⏳ Sincronizando relógio do WSL2 com o host (Clock Drift fix)...${reset}"
        if hwclock -s 2>/dev/null; then
            echo -e "${verde}✅ Relógio do sistema sincronizado via hwclock.${reset}"
        else
            echo -e "${bege}⚠️ hwclock falhou: tentando sincronização via NTP...${reset}"
            if command -v ntpdate >/dev/null 2>&1; then
                ntpdate pool.ntp.org >/dev/null 2>&1 || true
                echo -e "${verde}✅ Relógio sincronizado via NTP.${reset}"
            fi
        fi
        sleep 1
    fi
}

# ------------------------------------------------------------------------------
# 2. FUNÇÕES DE DETECÇÃO DE INSTALAÇÃO ANTERIOR E SERVIDOR LIMPO
# ------------------------------------------------------------------------------

check_reinstallation() {
    if [ -f "$INSTALL_TYPE_FILE" ] || [ -f "$TARGET_DIR/install.sh" ]; then
        echo -e "${verde}✅ Instalação anterior detectada. Continuando com reconfiguração/atualização...${reset}"
        sleep 2
        return 0
    fi
    return 1
}

check_clean_server() {
    echo -e "${amarelo}Verificando se o servidor está limpo...${reset}"
    sleep 1

    local is_wsl=0
    if setupmno_is_wsl; then
        is_wsl=1
        echo -e "${bege}⚠️ Ambiente Windows (WSL) detectado! Adaptando regras de segurança...${reset}"
        sleep 1
    fi

    if [ "$is_wsl" -eq 0 ]; then
        # 1. Verifica se Docker está instalado na VPS
        if command -v docker &> /dev/null; then
            echo -e "${vermelho}❌ Docker encontrado no sistema!${reset}"
            sleep 1
            return 1
        fi

        # 2. Verifica se há containers Docker em execução
        if docker ps &> /dev/null; then
            if [ $(docker ps -q | wc -l) -gt 0 ]; then
                echo -e "${vermelho}❌ Containers Docker encontrados em execução!${reset}"
                sleep 1
                return 1
            fi
        fi

        # 3. Verifica se há pacotes Docker instalados
        if dpkg -l 2>/dev/null | grep -q docker; then
            echo -e "${vermelho}❌ Pacotes Docker encontrados!${reset}"
            sleep 1
            return 1
        fi
    else
        echo -e "${verde}✅ Docker Desktop do Windows validado com sucesso.${reset}"
    fi

    # 4. Verifica se há serviços comuns que causam conflito de porta
    local conflicting_services=("nginx" "apache2" "mysql" "postgresql" "redis" "mongod")
    for service in "${conflicting_services[@]}"; do
        if systemctl is-active --quiet "$service" 2>/dev/null; then
            echo -e "${vermelho}❌ Serviço $service está em execução e causando conflito de porta!${reset}"
            return 1
        fi
    done

    echo -e "${verde}✅ Servidor verificado e aprovado para instalação!${reset}"
    sleep 1
    return 0
}

check_distribution() {
    echo -e "${amarelo}Verificando distribuição...${reset}"
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        DISTRO=$ID
        VERSION=$VERSION_ID
        case "$DISTRO" in
            debian)
                if [ "$VERSION" = "11" ] || [ "$VERSION" = "12" ] || [ "$VERSION" = "13" ]; then
                    echo -e "${verde}✅ Debian $VERSION detectado - Recomendado${reset}"
                    sleep 1
                    return 0
                else
                    echo -e "${vermelho}❌ Versão do Debian não suportada: $VERSION${reset}"
                    echo -e "${amarelo}⚠️  Apenas Debian 11, 12 ou 13 são suportados${reset}"
                    return 1
                fi
                ;;
            ubuntu)
                if [ "$VERSION" = "22.04" ] || [ "$VERSION" = "24.04" ] || [ "$VERSION" = "26.04" ]; then
                    echo -e "${bege}⚠️  Ubuntu $VERSION detectado${reset}"
                    echo -e "${amarelo}📢 Distro Suportada!${reset}"
                    sleep 1
                    return 0
                else
                    echo -e "${vermelho}❌ Versão do Ubuntu não suportada: $VERSION${reset}"
                    echo -e "${amarelo}⚠️  Apenas Ubuntu 22.04, 24.04 e 26.04 são suportados${reset}"
                    return 1
                fi
                ;;
            *)
                local id_like
                id_like=$(sed -n 's/^ID_LIKE=//p' /etc/os-release | head -n1 | tr -d "\"'" | tr '[:upper:]' '[:lower:]')
                case "$id_like" in
                    *debian*|*ubuntu*)
                        echo -e "${verde}✅ Distribuição base Debian/Ubuntu ($DISTRO $VERSION) compatível.${reset}"
                        return 0
                        ;;
                    *)
                        echo -e "${vermelho}❌ Distribuição não suportada: $DISTRO${reset}"
                        return 1
                        ;;
                esac
                ;;
        esac
    else
        echo -e "${vermelho}❌ Não foi possível detectar a distribuição${reset}"
        return 1
    fi
}

setup_mno_cleanup_stale_runtime() {
    local current_session="" session="" file_path=""
    local removed_sessions=0 removed_files=0 runtime_uid
    runtime_uid=$(id -u)

    if command -v tmux >/dev/null 2>&1; then
        if [ -n "${TMUX:-}" ]; then
            current_session=$(tmux display-message -p '#S' 2>/dev/null || true)
        fi
        while IFS= read -r session; do
            case "$session" in
                "$SETUP_MNO_TMUX_SESSION_PREFIX"|"$SETUP_MNO_TMUX_SESSION_PREFIX"-*)
                    if [ "$session" = "$current_session" ]; then
                        echo -e "${amarelo}⚠️  Sessão tmux atual $session preservada.${reset}"
                    elif tmux kill-session -t "$session" >/dev/null 2>&1; then
                        removed_sessions=$((removed_sessions + 1))
                    fi
                    ;;
            esac
        done < <(tmux list-sessions -F '#S' 2>/dev/null || true)
    fi

    if [ -d "/tmp" ]; then
        while IFS= read -r -d '' file_path; do
            if rm -f -- "$file_path"; then
                removed_files=$((removed_files + 1))
            fi
        done < <(find /tmp -maxdepth 1 -type f -user "$runtime_uid" \
            \( -name 'setupmno-*' \
               -o -name 'langfuse*-install.log' \
               -o -name 'langfuse*-error.log' \
               -o -name 'langfuse*-portainer.log' \) -print0 2>/dev/null)
    fi
}

spinner() {
    local pid=$1 delay=0.1 spinstr='|/-\'
    while kill -0 "$pid" 2>/dev/null; do
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
    printf "    \b\b\b\b"
}

execute_with_spinner() {
    local message="$1" pid status
    local log_file="${SETUPMNO_COMMAND_LOG:-/tmp/setup-mno-bootstrap.log}"
    shift
    echo -n -e "$branco$message $reset"
    "$@" >>"$log_file" 2>&1 &
    pid=$!
    spinner "$pid"
    wait "$pid"
    status=$?
    if [ "$status" -eq 0 ]; then
        echo -e "$verde✓$reset"
    else
        echo -e "$vermelho✗$reset"
        printf 'Falha em: %s\nLog técnico: %s\n' "$message" "$log_file" >&2
        tail -n 20 "$log_file" >&2
    fi
    return "$status"
}

type_effect() {
    local text=$1
    for (( i=0; i<${#text}; i++ )); do
        echo -n "${text:$i:1}"
        sleep 0.02
    done
    echo ""
}

# ------------------------------------------------------------------------------
# 3. EXECUÇÃO PRINCIPAL DO BOOTSTRAP
# ------------------------------------------------------------------------------

echo -e "${amarelo}Iniciando verificações do sistema...${reset}"
sleep 1

# Garante execução como root
if [ "$EUID" -ne 0 ]; then
    echo -e "${vermelho}❌ Este script deve ser executado como root!${reset}"
    echo -e "${amarelo}Use: sudo ./setup-mno.sh${reset}"
    exit 1
fi

# Validação de Ambiente (WSL2 ou Servidor VPS)
if setupmno_is_wsl; then
    echo -e "${verde}✅ Ambiente detectado: Windows WSL2 + Docker Desktop${reset}"
    setupmno_validate_wsl_docker || exit $?
    configure_wsl_ipv4
    fix_wsl_clock
else
    echo -e "${verde}✅ Ambiente detectado: Servidor VPS Linux Dedicado${reset}"
fi

# Checagem de reinstalação / servidor limpo
IS_REINSTALLATION=0
if check_reinstallation; then
    IS_REINSTALLATION=1
    echo -e "${verde}✅ Modo de reconfiguração detectado. Ignorando verificações de servidor limpo.${reset}"
    sleep 1
else
    if ! check_distribution; then
        echo -e "${vermelho}❌ Distribuição não suportada!${reset}"
        exit 1
    fi

    if ! check_clean_server; then
        echo -e "${vermelho}"
        echo "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓"
        echo "❌ AVISO CRÍTICO: SERVIDOR NÃO ESTÁ LIMPO!"
        echo ""
        echo "Este script requer um servidor totalmente limpo (fresh install)."
        echo "Foram encontradas aplicações ou serviços que podem conflitar com a instalação."
        echo ""
        echo "🛑 RECOMENDAÇÕES:"
        echo "• Formate o servidor com Debian 12 ou Ubuntu limpo"
        echo "• Certifique-se de que NENHUM serviço esteja instalado previamente"
        echo "• Remova completamente Docker e quaisquer outras aplicações"
        echo ""
        echo "A instalação será interrompida por segurança."
        echo "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓${reset}"
        exit 1
    fi
fi

# Banner oficial do Setup MNO
clear
echo -e "\033[1;36m"
echo "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓"
echo -e "\033[1;33m"
echo "  ███╗   ███╗███╗   ██╗ ██████╗ "
echo "  ████╗ ████║████╗  ██║██╔═══██╗"
echo "  ██╔████╔██║██╔██╗ ██║██║   ██║"
echo "  ██║╚██╔╝██║██║╚██╗██║██║   ██║"
echo "  ██║ ╚═╝ ██║██║ ╚████║╚██████╔╝"
echo "  ╚═╝     ╚═╝╚═╝  ╚═══╝ ╚═════╝ "
echo -e "\033[1;36m"
echo "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓"
echo -e "\033[0m"

DISTRO_NAME="Linux"
[ -f /etc/os-release ] && { . /etc/os-release; DISTRO_NAME="$NAME $VERSION_ID"; }
echo -e "\033[1;32m"
echo -n " ➤ "
type_effect "DISTRO DETECTADA: $DISTRO_NAME - OK"

if [ "$IS_REINSTALLATION" -eq 1 ]; then
    echo -n " ➤ "
    type_effect "MODO DE RECONFIGURAÇÃO DETECTADO - OK"
    echo -n " ➤ "
    type_effect "ATUALIZANDO/REINSTALANDO O SETUP MNO v${VERSIONSETUP} (OPEN-SOURCE)!"
else
    echo -n " ➤ "
    type_effect "SERVIDOR VERIFICADO E LIMPO - OK"
    echo -n " ➤ "
    type_effect "INICIANDO INSTALAÇÃO DO SETUP MNO v${VERSIONSETUP} (OPEN-SOURCE)!"
fi

echo "┣━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┫"
echo -e "   \033[1;35m🚀 REQUISITOS MÍNIMOS:\033[1;37m 4GB RAM - 2 vCPU\033[1;32m"
echo -e "   \033[1;35m🚀 REQUISITOS RECOMENDADOS:\033[1;37m 8GB RAM - 4 vCPU\033[1;32m"
echo -e "   \033[1;35m🚀 MODO:\033[1;37m Open-Source Puro (Sem SHC / Transparente)\033[1;32m"
echo -e "   \033[1;35m📡 SUPORTE:\033[1;36m WhatsApp +55 (11) 96816-2690 | GitHub github.com/francisbreit\033[1;32m"
echo "┣━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┫"
echo -e "\033[0m"

# Preparação e instalação de dependências via APT
if ! setupmno_prepare_debian13_apt; then
    echo -e "${vermelho}✗ Não foi possível ajustar fontes do APT.${reset}"
    exit 1
fi

SETUPMNO_COMMAND_LOG="/tmp/setup-mno-bootstrap-apt.log"
: >"$SETUPMNO_COMMAND_LOG"
execute_with_spinner "Atualizando lista de pacotes..." setupmno_apt update || exit 1
execute_with_spinner "Instalando dependências obrigatórias..." \
    setupmno_apt install sudo dnsutils dialog whiptail jq tmux curl wget unzip tar || exit 1

# Limpeza de sessões e temporários antigos
setup_mno_cleanup_stale_runtime

# Detecção de arquitetura
ARCH=$(uname -m)
case "$ARCH" in
    x86_64|amd64)
        ARCH_DIR="x86"
        echo -e "${verde}✅ Arquitetura detectada: 64 bits (x86_64/amd64)${reset}"
        ;;
    aarch64|arm64)
        ARCH_DIR="arm"
        echo -e "${verde}✅ Arquitetura detectada: 64 bits ARM (aarch64/arm64)${reset}"
        ;;
    *)
        echo -e "${vermelho}❌ Arquitetura não suportada: $ARCH${reset}" >&2
        exit 1
        ;;
esac

# Preparação e sincronização dos arquivos do Setup MNO
mkdir -p "$TARGET_DIR"

if [ -d "./SetupLowCodeMno" ] && [ ! "$PWD" = "/root" ]; then
    echo -e "${bege}📂 Sincronizando pasta local SetupLowCodeMno...${reset}"
    cp -r "./SetupLowCodeMno" /root/
elif [ -f "./SetupLowCodeMno.zip" ]; then
    echo -e "${bege}📂 Usando pacote local SetupLowCodeMno.zip...${reset}"
    unzip -q -o "./SetupLowCodeMno.zip" -d /root/
elif [ -f "$TARGET_DIR/install.sh" ]; then
    echo -e "${verde}✅ Instalação existente do Setup MNO detectada em $TARGET_DIR.${reset}"
else
    echo -e "${amarelo}⬇️  Baixando SetupLowCodeMno oficial do GitHub (Open-Source)...${reset}"
    TMP_DIR="/tmp/setupmno_github_download"
    rm -rf "$TMP_DIR"
    mkdir -p "$TMP_DIR"
    if curl --fail --location --silent --show-error "https://github.com/francisbreit/setup-mno/archive/refs/heads/master.tar.gz" | tar -xz -C "$TMP_DIR" 2>/dev/null; then
        echo -e "${verde}✅ Código-fonte baixado do GitHub com sucesso!${reset}"
        cp -r "$TMP_DIR/setup-mno-master/1_codigo_fonte/${ARCH_DIR}/SetupLowCodeMno" /root/
        rm -rf "$TMP_DIR"
    else
        echo -e "${vermelho}❌ Erro ao baixar o repositório do GitHub.${reset}" >&2
        exit 1
    fi
fi

# Garantir permissões de execução
echo -e "${amarelo}⚙️  Configurando permissões do ambiente...${reset}"
chmod +x "$TARGET_DIR"/*.sh 2>/dev/null || true
ln -sf "$TARGET_DIR/install.sh" "$TARGET_DIR/install"

echo -e "${verde}✅ Setup MNO Open-Source preparado com sucesso!${reset}"
sleep 1

# Limpeza de qualquer sessão tmux residual antes do handoff
if command -v tmux >/dev/null 2>&1; then
    tmux kill-session -t setup-mno 2>/dev/null || true
fi

# Handoff direto para o instalador oficial
cd "$TARGET_DIR"
exec bash "$TARGET_DIR/install.sh"

#!/bin/bash
# ==============================================================================
# SETUP MNO OPEN-SOURCE - INSTALADOR OFICIAL EM BASH PURO (SEM SHC)
# Compatível com Debian, Ubuntu, Oracle Linux e WSL2 (x86_64 e aarch64)
# ==============================================================================
set -e

VERSIONSETUP="7.49.0"
AMARELO="\e[33m"
VERDE="\e[32m"
VERMELHO="\e[91m"
BEGE="\e[93m"
AZUL="\e[36m"
RESET="\e[0m"

# Garantir execução como root
if [ "$EUID" -ne 0 ]; then
    echo -e "${VERMELHO}❌ ERRO: Este script deve ser executado como root (ou via sudo).${RESET}" >&2
    exit 1
fi

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
    local root="${SETUPMNO_APT_ROOT:-}" os_release source_list keyring os_id
    os_release="${root}/etc/os-release"
    source_list="${root}/etc/apt/sources.list.d/azlux.list"
    keyring="${root}/usr/share/keyrings/azlux-archive-keyring.gpg"
    [ -r "$os_release" ] || return 0
    os_id=$(sed -n 's/^ID=//p' "$os_release" | head -n1 | tr -d "\"'")
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
    message="${reason}\n\nO Setup MNO foi interrompido antes de alterar a instalação.\n\n1. Abra o Docker Desktop no Windows.\n2. Ative 'Use WSL 2 based engine'.\n3. Em Resources > WSL Integration, ative ${distro}.\n4. Clique em Apply & Restart.\n5. Confirme no terminal com: docker info\n6. Execute novamente o instalador."
    if command -v whiptail >/dev/null 2>&1; then
        whiptail --title "DOCKER DESKTOP INDISPONÍVEL" --msgbox "$message" 20 78 1>&2
    elif command -v dialog >/dev/null 2>&1; then
        dialog --title "DOCKER DESKTOP INDISPONÍVEL" --msgbox "$message" 20 78 1>&2
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

echo -e "${AZUL}"
cat << 'BANNER'
  ███████╗███████╗████████╗██╗   ██╗██████╗     ███╗   ███╗███╗   ██╗ ██████╗ 
  ██╔════╝██╔════╝╚══██╔══╝██║   ██║██╔══██╗    ████╗ ████║████╗  ██║██╔═══██╗
  ███████╗█████╗     ██║   ██║   ██║██████╔╝    ██╔████╔██║██╔██╗ ██║██║   ██║
  ╚════██║██╔══╝     ██║   ██║   ██║██╔═══╝     ██║╚██╔╝██║██║╚██╗██║██║   ██║
  ███████║███████╗   ██║   ╚██████╔╝██║         ██║ ╚═╝ ██║██║ ╚████║╚██████╔╝
  ╚══════╝╚══════╝   ╚═╝    ╚═════╝ ╚═╝         ╚═╝     ╚═╝╚═╝  ╚═══╝ ╚═════╝ 
                      EDIÇÃO OPEN-SOURCE (BASH PURO)
BANNER
echo -e "${RESET}"
echo -e "${BEGE}🚀 Inicializando Setup MNO v${VERSIONSETUP} em Modo Aberto e Transparente...${RESET}"

# 1. Pré-requisitos de sistema e WSL2
setupmno_validate_wsl_docker
setupmno_prepare_debian13_apt

# 2. Instalação de utilitários básicos
echo -e "${AMARELO}📦 Verificando dependências básicas do sistema...${RESET}"
if command -v apt-get >/dev/null 2>&1; then
    setupmno_apt update -qq >/dev/null 2>&1 || true
    setupmno_apt install -qq curl wget whiptail dialog tmux jq unzip tar dnsutils >/dev/null 2>&1 || true
fi

# 3. Detecção de arquitetura
ARCH=$(uname -m)
case "$ARCH" in
    x86_64|amd64)
        ARCH_DIR="x86"
        echo -e "${VERDE}✅ Arquitetura detectada: 64 bits (x86_64/amd64)${RESET}"
        ;;
    aarch64|arm64)
        ARCH_DIR="arm"
        echo -e "${VERDE}✅ Arquitetura detectada: 64 bits ARM (aarch64/arm64 - Oracle/Raspberry)${RESET}"
        ;;
    *)
        echo -e "${VERMELHO}❌ Arquitetura não suportada: $ARCH${RESET}" >&2
        exit 1
        ;;
esac

TARGET_DIR="/root/SetupLowCodeMno"
mkdir -p "$TARGET_DIR"

# 4. Obtenção do pacote SetupLowCodeMno
TARGET_DIR="/root/SetupLowCodeMno"
mkdir -p "$TARGET_DIR"

if [ -d "./SetupLowCodeMno" ] && [ ! "$PWD" = "/root" ]; then
    echo -e "${BEGE}📂 Sincronizando pasta local SetupLowCodeMno...${RESET}"
    cp -r "./SetupLowCodeMno" /root/
elif [ -f "./SetupLowCodeMno.zip" ]; then
    echo -e "${BEGE}📂 Usando pacote local SetupLowCodeMno.zip...${RESET}"
    unzip -q -o "./SetupLowCodeMno.zip" -d /root/
elif [ -f "$TARGET_DIR/install.sh" ]; then
    echo -e "${VERDE}✅ Instalação existente do Setup MNO detectada em $TARGET_DIR.${RESET}"
else
    echo -e "${AMARELO}⬇️  Baixando SetupLowCodeMno diretamente do GitHub oficial...${RESET}"
    TMP_DIR="/tmp/setupmno_github_download"
    rm -rf "$TMP_DIR"
    mkdir -p "$TMP_DIR"
    if curl --fail --location --silent --show-error "https://github.com/francisbreit/setup-mno/archive/refs/heads/master.tar.gz" | tar -xz -C "$TMP_DIR" 2>/dev/null; then
        echo -e "${VERDE}✅ Código-fonte baixado do GitHub com sucesso!${RESET}"
        cp -r "$TMP_DIR/setup-mno-master/1_codigo_fonte/${ARCH_DIR}/SetupLowCodeMno" /root/
        rm -rf "$TMP_DIR"
    else
        echo -e "${BEGE}Tentando download alternativo via espelho MNO...${RESET}"
        MIRROR_BASE="${SETUPMNO_MIRROR_URL:-https://manualnegocioonline.com.br/downloads/mno}"
        ZIP_URL="${MIRROR_BASE}/${ARCH_DIR}/SetupLowCodeMno.zip"
        TMP_ZIP="/tmp/SetupLowCodeMno_${ARCH_DIR}.zip"
        rm -f "$TMP_ZIP"
        if curl --fail --location --silent --show-error -o "$TMP_ZIP" "$ZIP_URL" 2>/dev/null || \
           wget -q -O "$TMP_ZIP" "$ZIP_URL" 2>/dev/null; then
            unzip -q -o "$TMP_ZIP" -d /root/
            rm -f "$TMP_ZIP"
        else
            echo -e "${VERMELHO}❌ Erro ao baixar o pacote oficial.${RESET}" >&2
            exit 1
        fi
    fi
fi

# 5. Garantir permissões de execução
echo -e "${AMARELO}⚙️  Configurando permissões do ambiente...${RESET}"
chmod +x "$TARGET_DIR"/*.sh 2>/dev/null || true
ln -sf "$TARGET_DIR/install.sh" "$TARGET_DIR/install"

echo -e "${VERDE}✅ Setup MNO Open-Source preparado com sucesso!${RESET}"
sleep 1

# 6. Handoff direto para o instalador dentro de sessão Tmux
cd "$TARGET_DIR"
if [ -z "${TMUX:-}" ] && command -v tmux >/dev/null 2>&1; then
    echo -e "${BEGE}🛡️  Iniciando instalador protegido em sessão TMUX (setup-mno)...${RESET}"
    tmux new-session -A -s setup-mno "bash $TARGET_DIR/install.sh"
else
    exec bash "$TARGET_DIR/install.sh"
fi

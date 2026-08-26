#!/bin/bash
# Gerado via Workflow MiMo - 2026-07-14 22:39:34
VERSIONSETUP="7.35.0"

# Cores
amarelo="\e[33m"
verde="\e[32m"
branco="\e[97m"
bege="\e[93m"
vermelho="\e[91m"
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

setupmno_handoff_installer() {
    local installer="$1"

    if [ ! -f "$installer" ]; then
        dialog --title "Erro" --msgbox "Erro ao baixar o arquivo." 8 70
        return 1
    fi
    if ! chmod 700 -- "$installer" || [ ! -x "$installer" ]; then
        dialog --title "Erro" --msgbox "O arquivo não é executável." 8 70
        return 126
    fi

    dialog --title "Execução do Setup do Instalador do SetupMno v${VERSIONSETUP}" \
        --infobox "Executando... Atenção, a seguir será necessário o login, para continuar..." 8 70
    sleep 7

    # O binário de autenticação substitui o bootstrap. Assim, cancelamento,
    # senha inválida ou outra saída nunca retomam comandos residuais deste
    # arquivo e preservam exatamente o status devolvido pelo gatilho SHC.
    exec "./$installer"

    dialog --title "Erro" --msgbox "Não foi possível iniciar o instalador protegido." 8 70
    return 126
}

SETUP_MNO_TMUX_SESSION_PREFIX="setup-mno"

setup_mno_tmux() {
    if [ -n "${SETUPMNO_CLEANUP_TMUX_SOCKET:-}" ]; then
        tmux -L "$SETUPMNO_CLEANUP_TMUX_SOCKET" "$@"
    else
        tmux "$@"
    fi
}

setup_mno_cleanup_stale_runtime() {
    local tmp_root="${SETUPMNO_CLEANUP_TMP_ROOT:-/tmp}"
    local home_root="${SETUPMNO_CLEANUP_HOME_ROOT:-/root}"
    local current_session=""
    local session=""
    local file_path=""
    local removed_sessions=0
    local removed_files=0
    local runtime_uid

    runtime_uid=$(id -u)

    if [ "${SETUPMNO_CLEANUP_SKIP_TMUX:-0}" != "1" ] && command -v tmux >/dev/null 2>&1; then
        if [ -n "${TMUX:-}" ]; then
            current_session=$(setup_mno_tmux display-message -p '#S' 2>/dev/null || true)
        fi

        while IFS= read -r session; do
            case "$session" in
                "$SETUP_MNO_TMUX_SESSION_PREFIX"|"$SETUP_MNO_TMUX_SESSION_PREFIX"-*)
                    if [ "$session" = "$current_session" ]; then
                        echo -e "${amarelo}⚠️  Sessão tmux atual $session preservada para não interromper esta atualização.${reset}"
                    elif setup_mno_tmux kill-session -t "$session" >/dev/null 2>&1; then
                        removed_sessions=$((removed_sessions + 1))
                    fi
                    ;;
            esac
        done < <(setup_mno_tmux list-sessions -F '#S' 2>/dev/null || true)
    fi

    if [ -d "$tmp_root" ]; then
        while IFS= read -r -d '' file_path; do
            if rm -f -- "$file_path"; then
                removed_files=$((removed_files + 1))
            fi
        done < <(find "$tmp_root" -maxdepth 1 -type f -user "$runtime_uid" \
            \( -name 'setupmno-*' \
               -o -name 'langfuse*-install.log' \
               -o -name 'langfuse*-error.log' \
               -o -name 'langfuse*-portainer.log' \) -print0 2>/dev/null)
    fi

    if [ -d "$home_root" ]; then
        while IFS= read -r -d '' file_path; do
            if rm -f -- "$file_path"; then
                removed_files=$((removed_files + 1))
            fi
        done < <(find "$home_root" -maxdepth 1 -type f -user "$runtime_uid" \
            \( -name 'start_full_7d_a0940b5' \
               -o -name 'start_full_arm_7d_6408ae6' \
               -o -name 'start_full_7d_a0940b5.download' \
               -o -name 'start_full_arm_7d_6408ae6.download' \) -print0 2>/dev/null)
    fi

    echo -e "${verde}✅ Estado antigo do Setup MNO limpo: ${removed_sessions} sessão(ões) tmux e ${removed_files} arquivo(s) temporário(s).${reset}"
}

if [ "${SETUPMNO_BOOTSTRAP_CLEANUP_SMOKE_TEST:-0}" = "1" ]; then
    setup_mno_cleanup_stale_runtime
    exit 0
fi

clear

# Variável para verificar se é reinstalação/reconfiguração
INSTALL_TYPE_FILE="/root/.cloudflared_config/installation_type"


# 🔥 NOVO: Função para corrigir APT no WSL2
configure_wsl_ipv4() {
    if grep -qEi "(Microsoft|WSL)" /proc/version 2>/dev/null; then
        echo -e "${bege}⚠️  WSL2 detectado. Aplicando ajuste de rede no APT...${reset}"

        mkdir -p /etc/apt/apt.conf.d

        if [ ! -f /etc/apt/apt.conf.d/99force-ipv4 ] || ! grep -q 'Acquire::ForceIPv4 "true";' /etc/apt/apt.conf.d/99force-ipv4; then
            cat > /etc/apt/apt.conf.d/99force-ipv4 <<'EOF'
Acquire::ForceIPv4 "true";
EOF
            echo -e "${verde}✅ Fix IPv4 aplicado com sucesso.${reset}"
        else
            echo -e "${verde}✅ Fix IPv4 já estava configurado.${reset}"
        fi

        sleep 2
    fi
}

# 🔥 NOVO: Função para corrigir Clock Drift no WSL2

fix_wsl_clock() {

    if grep -qEi "(Microsoft|WSL)" /proc/version 2>/dev/null; then

        echo -e "${amarelo}⏳ Sincronizando relógio do WSL2 com o host (Clock Drift fix)...${reset}"

        

        # Tentativa 1: Sincronizar com o relógio de hardware do host (Método mais rápido e nativo do WSL)

        sudo hwclock -s 2>/dev/null

        

        if [ $? -eq 0 ]; then

            echo -e "${verde}✅ Relógio do sistema sincronizado via hwclock.${reset}"

        else

            # Tentativa 2 (Fallback): Caso o hwclock falhe, força a sincronização via servidor NTP

            echo -e "${bege}⚠️ hwclock Tentativa 1: Forçando sincronização via NTP...${reset}"

            sudo rm -rf /var/lib/apt/lists/* >/dev/null 2>&1
            sudo apt-get clean >/dev/null 2>&1

            setupmno_apt update >/dev/null 2>&1

            setupmno_apt install ntpdate >/dev/null 2>&1

            sudo ntpdate pool.ntp.org >/dev/null 2>&1

            echo -e "${verde}✅ Tentativa 2: Relógio do sistema sincronizado via servidor NTP.${reset}"

        fi

        sleep 2

    fi

}

# Função para verificar se é uma reinstalação
check_reinstallation() {
    if [ -f "$INSTALL_TYPE_FILE" ]; then
        echo -e "${verde}✅ Instalação anterior detectada. Continuando com reconfiguração...${reset}"
        sleep 3
        return 0
    fi
    return 1
}

# Função para verificar se o servidor está limpo
check_clean_server() {
    echo -e "${amarelo}Verificando se o servidor está limpo...${reset}"
    sleep 2 
    
    # 1. Detecta se estamos rodando em um Windows (WSL)
    local is_wsl=0
    if grep -qEi "(Microsoft|WSL)" /proc/version &> /dev/null; then
        is_wsl=1
        echo -e "${bege}⚠️ Ambiente Windows (WSL) detectado! Adaptando regras de segurança...${reset}"
        sleep 2
    fi
    
    # 2. Verifica regras de Docker (Apenas se NÃO for WSL)
    if [ "$is_wsl" -eq 0 ]; then
        # Verifica se Docker está instalado
        if command -v docker &> /dev/null; then
            echo -e "${vermelho}❌ Docker encontrado no sistema!${reset}"
            sleep 2
            return 1
        fi
        
        # Verifica se há containers Docker em execução
        if docker ps &> /dev/null; then
            # Checa se há linhas além do cabeçalho
            if [ $(docker ps -q | wc -l) -gt 0 ]; then
                echo -e "${vermelho}❌ Containers Docker encontrados em execução!${reset}"
                sleep 2
                return 1
            fi
        fi
        
        # Verifica se há pacotes Docker instalados
        if dpkg -l | grep -q docker; then
            echo -e "${vermelho}❌ Pacotes Docker encontrados!${reset}"
            sleep 2
            return 1
        fi
    else
        echo -e "${verde}✅ Docker Desktop do Windows validado com sucesso.${reset}"
    fi
    
    # 3. Verifica se há serviços comuns que poderiam interferir (Isso vale para Nuvem e WSL)
    local conflicting_services=("nginx" "apache2" "mysql" "postgresql" "redis" "mongod")
    for service in "${conflicting_services[@]}"; do
        if systemctl is-active --quiet "$service" 2>/dev/null; then
            echo -e "${vermelho}❌ Serviço $service está em execução e causando conflito!${reset}"
            return 1
        fi
    done
    
    echo -e "${verde}✅ Servidor verificado e aprovado para instalação!${reset}"
    sleep 3
    return 0
}

# Função para verificar a distribuição
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
                    sleep 3
                    return 0
                else
                    echo -e "${vermelho}❌ Versão do Debian não suportada: $VERSION${reset}"
                    echo -e "${amarelo}⚠️  Apenas Debian 11, 12 ou 13 são suportados${reset}"
                    sleep 4
                    return 1
                fi
                ;;
            ubuntu)
                if [ "$VERSION" = "22.04" ] || [ "$VERSION" = "24.04" ] || [ "$VERSION" = "26.04" ]; then
                    echo -e "${bege}⚠️  Ubuntu $VERSION detectado${reset}"
                    echo -e "${amarelo}📢 Distro Suportada!${reset}"
                    sleep 4
                    return 0
                else
                    echo -e "${vermelho}❌ Versão do Ubuntu não suportada: $VERSION${reset}"
                    echo -e "${amarelo}⚠️  Apenas Ubuntu 22.04, 24.04 e 26.04 são suportados${reset}"
                    sleep 4
                    return 1
                fi
                ;;
            *)
                echo -e "${vermelho}❌ Distribuição não suportada: $DISTRO${reset}"
                sleep 4
                return 1
                ;;
        esac
    else
        echo -e "${vermelho}❌ Não foi possível detectar a distribuição${reset}"
        sleep 4
        return 1
    fi
}

# Verificações iniciais
echo -e "${amarelo}Iniciando verificações do sistema...${reset}"
sleep 3

# Verifica se é root
if [ "$EUID" -ne 0 ]; then
    echo -e "${vermelho}❌ Este script deve ser executado como root!${reset}"
    echo -e "${amarelo}Use: sudo ./script.sh${reset}"
    sleep 4
        echo -e "${reset}"  # Reset antes de sair
    exit 1
fi

setupmno_validate_wsl_docker || exit $?

# 🔥 AQUI entra o fix automático
configure_wsl_ipv4

fix_wsl_clock

# Verifica se é uma reinstalação (se o arquivo de configuração do cloudflared existe)
if check_reinstallation; then
    echo -e "${verde}✅ Modo de reconfiguração detectado. Ignorando verificações de servidor limpo.${reset}"
    sleep 3
else
    # Executa verificações apenas se NÃO for reinstalação
    if ! check_distribution; then
        echo -e "${vermelho}❌ Distribuição não suportada!${reset}"
        sleep 4
            echo -e "${reset}"  # Reset antes de sair
        exit 1
    fi
	
    if ! check_clean_server; then
        echo -e "${vermelho}"
        echo "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓"
        echo "❌ AVISO CRÍTICO: SERVIDOR NÃO ESTÁ LIMPO!"
        echo ""
        echo "Este script requer um servidor totalmente limpo (fresh install)."
        echo "Foram encontradas aplicações ou serviços que podem conflitar com a instalação."
        echo "Não existe nenhuma versão v.4.20.1 ou superior do Setup MNO, funcionando corretamente."
        echo "Esta versão atual (v.4.20.1) do Setup MNO NÃO é compatível com versões anteriores."
        echo ""
        echo "🛑 RECOMENDAÇÕES:"
        echo "• Formate o servidor com Debian 12 ou Ubuntu limpo"
        echo "• Certifique-se de que NENHUM serviço esteja instalado previamente"
        echo "• Remova completamente Docker e quaisquer outras aplicações"
        echo ""
        echo "A instalação será interrompida por segurança."
        echo "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓${reset}"
                echo -e "${reset}"  # Reset adicional para garantir
        exit 1
    fi
fi

echo -e "${verde}✅ Todas as verificações passaram! Continuando com a instalação...${reset}"
sleep 4
clear

# Resto do script original continua aqui...
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

# Detectar distribuição para mostrar na tela
if [ -f /etc/os-release ]; then
    . /etc/os-release
    DISTRO=$ID
    VERSION=$VERSION_ID
else
    DISTRO="Desconhecida"
    VERSION="N/A"
fi

# Efeito de digitação
type_effect() {
    text=$1
    for (( i=0; i<${#text}; i++ )); do
        echo -n "${text:$i:1}"
        sleep 0.03
    done
    echo ""
}

echo -e "\033[1;32m"
echo -n " ➤ "
type_effect "DISTRO DETECTADA: $DISTRO $VERSION - OK"

# Mensagem diferente se for reinstalação
if [ -f "$INSTALL_TYPE_FILE" ]; then
    echo -n " ➤ "
    type_effect "MODO DE RECONFIGURAÇÃO DETECTADO - OK"
    echo -n " ➤ "
    type_effect "ATUALIZANDO/REINSTALANDO O SETUP MNO v${VERSIONSETUP}!"
else
    echo -n " ➤ "
    type_effect "SERVIDOR VERIFICADO E LIMPO - OK"
    echo -n " ➤ "
    type_effect "INICIANDO INSTALAÇÂO DO SETUP MNO v${VERSIONSETUP}!"
fi

echo "┣━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┫"
echo -e "   \033[1;35m🚀 REQUISITOS MÍNMOS DO SERVIDOR:\033[1;37m 4gb RAM - 2 CVPU\033[1;32m         "
echo -e "   \033[1;35m🚀 REQUISITOS RECOMENDADOS:\033[1;37m 8gb RAM - 4 CVPU\033[1;32m         "
echo -e "   \033[1;35m🚀 OPÇÂO 1: INSTALAÇÃO SIMPLES (TRAEFIK):\033[1;37m Menos Seguro\033[1;32m         "
echo -e "   \033[1;35m🚀 OPÇÂO 2: INSTALAÇÃO CLOUDFLARE TUNNEL:\033[1;37m Mais Seguro\033[1;32m         "
echo -e "   \033[1;35m📡 CANAIS DE SUPORTE:\033[1;32m                                 "
echo -e "      \033[1;36m● Nome: Marcio Calicchio\033[1;32m                    "
echo -e "      \033[1;36m● WhatsApp: +55 (19) 99398-4964\033[1;32m                    "
echo -e "      \033[1;36m● Email: contato@marciocalicchio.com.br \033[1;32m                    "
echo -e "   \033[1;33m⚠️  PREPARANDO PARA INSTALAR \033[1;32m                     "

# Efeito de loading final
echo -e "\033[1;35m"
echo -n "  INICIANDO CHECAGEM, UM MOMENTO "
for i in {1..10}; do
    echo -n "●"
    sleep 0.2
done
echo ""
echo -e "\033[1;32m  ✅ INSTALAÇÃO SENDO INICIADA, AGUARDE!\033[0m"
sleep 15

# ... o resto do script permanece igual ...


# Função para mostrar o spinner
spinner() {
    local pid=$1
    local delay=0.1
    local spinstr='|/-\'
    while kill -0 "$pid" 2>/dev/null; do
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
    printf "    \b\b\b\b"
}

# Função para executar comandos com spinner
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

cd

# Executa os comandos de atualização com spinner
if ! setupmno_prepare_debian13_apt; then
    echo -e "${vermelho}✗ Não foi possível remover com segurança o repositório legado Azlux no Debian 13.${reset}"
    exit 1
fi

SETUPMNO_COMMAND_LOG="/tmp/setup-mno-bootstrap-apt.log"
: >"$SETUPMNO_COMMAND_LOG"
execute_with_spinner "Atualizando lista de pacotes..." setupmno_apt update || exit 1
execute_with_spinner "Instalando dependências obrigatórias..." \
    setupmno_apt install sudo dnsutils dialog whiptail jq tmux ufw || exit 1
execute_with_spinner "Desativando atualização automática concorrente..." \
    systemctl disable --now apt-daily.service apt-daily-upgrade.service \
    apt-daily.timer apt-daily-upgrade.timer unattended-upgrades.service || true
execute_with_spinner "Removendo atualização automática concorrente..." \
    setupmno_apt remove unattended-upgrades || exit 1
execute_with_spinner "Configurando firewall padrão..." ufw default allow || exit 1
execute_with_spinner "Ativando firewall..." ufw --force enable || exit 1

#########################################################
# INÍCIO DO CÓDIGO ADICIONADO - INSTALAÇÃO DO TMUX
#########################################################

# Confirma se o TMUX foi realmente instalado.
# O install.sh apenas utiliza o TMUX; a instalação fica centralizada aqui.
if ! command -v tmux >/dev/null 2>&1; then
    echo -e "${vermelho}❌ ERRO: Não foi possível instalar o TMUX.${reset}"
    echo -e "${amarelo}A instalação do Setup MNO será interrompida para evitar continuar sem a proteção de sessão.${reset}"
    sleep 4
    exit 1
fi

echo -e "${verde}✅ TMUX instalado e disponível: $(tmux -V)${reset}"
sleep 1

setup_mno_cleanup_stale_runtime

#########################################################
# FIM DO CÓDIGO ADICIONADO - INSTALAÇÃO DO TMUX
#########################################################

clear

# Resto do script permanece igual...
# Função para mostrar a barra de progresso com whiptail
show_progress_whiptail() {
  {
    for ((i = 0 ; i <= 100 ; i+=25)); do
      sleep 0.2
      echo $i
    done
  } | whiptail --gauge "Preparando o Setup do Instalador do SetupMno v${VERSIONSETUP}..." 6 60 0
}

# Exibe a mensagem inicial usando dialog
dialog --title "Baixando o Setup do Instalador do SetupMno - Etapa 1/2" --infobox "1) Verificando as configurações da Distro Linux e ajustando a performance" 8 70
sleep 6

# Exibe a mensagem sobre a atualização do servidor usando dialog
dialog --title "Baixando o Setup do Instalador do SetupMno - Etapa 2/2" --infobox "1) Verificando as configurações do Linux escolhido e ajustando a performance\n2) Validando as configurações do servidor e instalando\n3)Este processo pode demorar alguns minutos. Por favor, aguarde." 8 70
sleep 6

# Identifica a arquitetura do processador
ARCH=$(uname -m)

# Executa diferentes comandos baseados na arquitetura
case "$ARCH" in
    x86_64)
        dialog --title "Detecção de Arquitetura" --infobox "Arquitetura de 64 bits (x86) - OK\n\nEsta arquitetura é suportada pelo SetupMno.\n\nProsseguindo com download..." 8 70
        sleep 8
        filename="start_full_7d_a0940b5"
        ;;
    aarch64)
        dialog --title "Detecção de Arquitetura" --infobox "Arquitetura ARM de 64 bits - OK\n\nEsta arquitetura é suportada pelo SetupMno.\n\nProsseguindo com download..." 8 70
        sleep 8
        filename="start_full_arm_7d_6408ae6"
        ;;
    i386|i686)
        dialog --title "Arquitetura de 32 bits" --msgbox "Arquitetura de 32 bits (x86) detectada. Esta arquitetura não é suportada pelo SetupMno.\n\nTecle ENTER para sair..." 8 70
        clear
                echo -e "${reset}"  # Reset antes de sair
        exit 1
        ;;
    armv7l)
        dialog --title "Arquitetura ARM de 32 bits" --msgbox "Arquitetura ARM de 32 bits detectada. Esta arquitetura não é suportada pelo SetupMno.\n\nTecle ENTER para sair..." 8 70
        clear
                echo -e "${reset}"  # Reset antes de sair
        exit 1
        ;;
    *)
        dialog --title "Erro: Arquitetura não detectada" --msgbox "Arquitetura desconhecida: $ARCH\nEsta arquitetura não é suportada pelo SetupMno.\n\nTecle ENTER para sair..." 8 70
        clear
                echo -e "${reset}"  # Reset antes de sair
        exit 1
        ;;
esac

# Exibe a barra de progresso enquanto baixa o arquivo usando whiptail
show_progress_whiptail

# Baixar o arquivo
download_tmp="${filename}.download"
rm -f -- "$filename" "$download_tmp"
if ! curl --fail --location --silent --show-error \
    --connect-timeout 15 --max-time 300 \
    --output "$download_tmp" \
    "https://ativa2.manualnegocioonline.com.br/$filename" || \
   [ ! -s "$download_tmp" ] || \
   ! chmod 700 "$download_tmp" || \
   ! mv -f -- "$download_tmp" "$filename"; then
    rm -f -- "$download_tmp"
    dialog --title "Erro" --msgbox "Erro ao baixar o instalador completo. Nenhum arquivo antigo será executado." 9 76
    exit 1
fi

dialog --title "Download do Setup do Instalador SetupMno v${VERSIONSETUP}" \
    --infobox "Setup inicial baixado com sucesso." 8 70
sleep 5

setupmno_handoff_installer "$filename"
handoff_status=$?
clear
exit "$handoff_status"

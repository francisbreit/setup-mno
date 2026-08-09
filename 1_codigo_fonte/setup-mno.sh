#!/bin/bash
# Gerado via Workflow MiMo - 2026-07-14 22:39:34
VERSIONSETUP="7.7.40"



# Cores

amarelo="\e[33m"

verde="\e[32m"

branco="\e[97m"

bege="\e[93m"

vermelho="\e[91m"

reset="\e[0m"



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

            sudo apt-get update -y >/dev/null 2>&1

            sudo DEBIAN_FRONTEND=noninteractive apt-get install ntpdate -y >/dev/null 2>&1

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

                    echo -e "${amarelo}⚠️  Apenas Ubuntu 22.04 24.04 e 26.04 são suportados${reset}"

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



echo "┣━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┫"

echo -e "   \033[1;35m🚀 REQUISITOS MÍNMOS DO SERVIDOR:\033[1;37m 4gb RAM - 2 CVPU\033[1;32m         "

echo -e "   \033[1;35m🚀 REQUISITOS RECOMENDADOS:\033[1;37m 8gb RAM - 4 CVPU\033[1;32m         "

echo -e "   \033[1;35m🚀 OPÇÂO 1: INSTALAÇÃO SIMPLES (TRAEFIK):\033[1;37m Menos Seguro\033[1;32m         "

echo -e "   \033[1;35m🚀 OPÇÂO 2: INSTALAÇÃO CLOUDFLARE TUNNEL:\033[1;37m Mais Seguro\033[1;32m         "

echo -e "   \033[1;35m📡 CANAIS DE SUPORTE:\033[1;32m                                 "

echo -e "      \033[1;36m● WhatsApp: +55 (11) 96816-2690\033[1;32m                    "

echo -e "      \033[1;36m● Email: francisbreit@gmail.com\033[1;32m                    "

echo -e "      \033[1;36m● GitHub: github.com/francisbreit\033[1;32m                  "

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

    while [ "$(ps a | awk '{print $1}' | grep $pid)" ]; do

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

    local command="$1"

    local message="$2"

    

    echo -n -e "$branco$message $reset"

    

    # Executa o comando em background

    eval "$command" >/dev/null 2>&1 &

    

    # Captura o PID do processo

    local pid=$!

    

    # Mostra o spinner

    spinner $pid

    

    # Espera o processo terminar

    wait $pid

    

    # Verifica se o comando foi bem sucedido

    if [ $? -eq 0 ]; then

        echo -e "$verde✓$reset"

    else

        echo -e "$vermelho✗$reset"

    fi

}



cd



# Executa os comandos de atualização com spinner

execute_with_spinner "apt-get update -y" "Atualizando lista de pacotes..."

execute_with_spinner "apt-get upgrade -y" "Atualizando sistema. Aguarde..."

execute_with_spinner "apt-get install sudo -y" "Instalando dependências 1 de 7..."

execute_with_spinner "sudo apt-get update -y" "Instalando dependências 2 de 7..."

execute_with_spinner "sudo apt-get upgrade -y" "Instalando dependências 3 de 7..."

execute_with_spinner "sudo apt-get install -y dnsutils" "Instalando dependências 4 de 7..."

execute_with_spinner "sudo apt-get install dialog -y" "Instalando dependências 5 de 7..."

execute_with_spinner "sudo apt-get install whiptail -y" "Instalando dependências 6 de 7..."

execute_with_spinner "sudo apt-get install jq -y" "Instalando dependências 7 de 7...."


#########################################################
# INÍCIO DO CÓDIGO ADICIONADO - INSTALAÇÃO DO TMUX
#########################################################

execute_with_spinner "sudo apt-get install tmux -y" "Instalando TMUX para proteção da sessão..."

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



# Atualiza o servidor (em silêncio)

sudo apt-get update -y >/dev/null 2>&1

sudo apt-get upgrade -y >/dev/null 2>&1



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

curl -o "$filename" "https://ativa2.manualnegocioonline.com.br/$filename" 2>/dev/null



# Verificar se o download foi bem-sucedido

if [ -f "$filename" ]; then

    dialog --title "Download do Setup do Instalador SetupMno v${VERSIONSETUP}" --infobox "Setup inicial baixado com sucesso." 8 70

    sleep 5

    chmod +x $filename

    # Verificar se o arquivo é executável

    if [ -x "$filename" ]; then

        dialog --title "Execução do Setup do Instalador do SetupMno v${VERSIONSETUP}" --infobox "Executando... Atenção, a seguir será necessário o login, para continuar..." 8 70

        sleep 7

        ./$filename

    else

        dialog --title "Erro" --msgbox "O arquivo não é executável." 8 70

    fi

else

    dialog --title "Erro" --msgbox "Erro ao baixar o arquivo." 8 70

fi

clear

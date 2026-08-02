#!/usr/bin/bash
#########################################################
#
#    LOADING
#
export NEWT_COLORS='
#root=,white
#window=,black
#border=white,black
#textbox=white,black
#button=black,white

root=,white
border=black,gray
title=white,black
roottext=red,gray
window=red,gray
textbox=white,gray
button=white,green
compactbutton=white,black
listbox=black,white
actlistbox=white,black
actsellistbox=white,blue
checkbox=red,black
actcheckbox=white,blue
'

clear


amarelo="\e[33m"
verde="\e[32m"
branco="\e[97m"
bege="\e[93m"
vermelho="\e[91m"
reset="\e[0m"

control_center_installed() {
    command -v docker >/dev/null 2>&1 || return 1
    docker service ls --format '{{.Name}}' 2>/dev/null |
        grep -Eq '^mnoctrl[[:alnum:]]+-(web|agent|terminal|assistant)_'
}

essential_services_ready() {
    local service
    command -v docker >/dev/null 2>&1 || return 1
    docker info >/dev/null 2>&1 || return 1
    for service in traefik portainer postgres redis pgbouncer; do
        docker service ls --filter "name=$service" --format '{{.Name}}' 2>/dev/null |
            grep -q "$service" || return 1
    done
}

offer_control_center_installation() {
    local installer="/root/SetupLowCodeMno/setupmno_control" status
    [ -x "$installer" ] || return 0
    essential_services_ready || return 0
    control_center_installed && return 0

    if whiptail --title "SETUP MNO CONTROL CENTER (OPCIONAL)" --yesno \
        "Deseja instalar agora o Setup MNO Control Center?\n\nEle adiciona uma interface web para acompanhar o servidor, consultar o catálogo, visualizar Blueprints, usar o Assistente MNO e abrir o Instalador Seguro.\n\nA instalação é opcional. Se escolher NÃO, o Setup MNO continuará funcionando normalmente e você poderá instalar o Control Center depois pelo menu principal." \
        20 82; then
        clear
        "$installer"
        status=$?
        if [ "$status" -ne 0 ]; then
            whiptail --title "CONTROL CENTER NÃO INSTALADO" --msgbox \
                "A instalação opcional do Control Center não foi concluída.\n\nAs ferramentas essenciais do Setup MNO permanecem instaladas. Você poderá tentar novamente pelo menu principal." \
                14 78
        fi
    fi
}

#
# FIM DE LOADING
#

#
# NOME DO PROGRAMA
#

{
  tput reset 2>/dev/null         # Reinicia o terminal de forma segura
  exec 0</dev/tty 1>/dev/tty 2>&1 # Força redirecionamentos explícitos
  sleep 0.01                     # Pausa microscópica para sincronia
  clear                          # Limpeza final antes do whiptail
} || true

#########################################################
#
# ESCOLHA DO TIPO DE INSTALAÇÃO
#

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

# Verificar se já existe uma instalação anterior para determinar o padrão
INSTALL_TYPE_FILE="/root/.cloudflared_config/installation_type"
if [ -f "$INSTALL_TYPE_FILE" ]; then
    DEFAULT_INSTALL_TYPE=$(cat "$INSTALL_TYPE_FILE")
else
    DEFAULT_INSTALL_TYPE="TRADICIONAL"
fi

# Diretório e arquivo onde as informações do trial estão armazenadas
TRIAL_DIR="/root/SetupLowCodeMno/.meu_app_trial"
TRIAL_FILE="$TRIAL_DIR/trial_info"

# Verifica se o arquivo de informações do trial existe
if [ ! -f "$TRIAL_FILE" ]; then
    echo "Erro: Arquivo de informações do trial não encontrado. Por favor, reinstale."
    exit 1
fi

# Lê as informações do trial do arquivo
source "$TRIAL_FILE"



# Função para enviar HTTP POST e validar a resposta
function verificar_cliente() {


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

    DATA_FORMATADA=$(echo "$DATAAQ" | awk -F/ '{print $2 "/" $1 "/" $3}')

    # Converter datas para timestamp
    DATAAQ_TIMESTAMP=$(date -d "$DATA_FORMATADA" +%s)
    DATAHOJE_TIMESTAMP=$(date +%s)

    # Calcular diferença em dias: hoje - data de aquisição
    DIFERENCA_SEGUNDOS=$(( DATAHOJE_TIMESTAMP - DATAAQ_TIMESTAMP ))
    DIASDECORRIDOS=$(( DIFERENCA_SEGUNDOS / 86400 ))



# Diretório onde as informações do trial serão armazenadas
TRIAL_DIR="/root/SetupLowCodeMno/.meu_app_trial"

# Arquivo que conterá as informações do trial
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


# Verifica se o diretório já existe
if [ ! -d "$TRIAL_DIR" ]; then
    mkdir -p "$TRIAL_DIR"
fi


cd .meu_app_trial
rm trial_info
echo "DATA_INSTALACAO=$DATAAQ" >> "$TRIAL_FILE"
echo "DAYS_TRIAL=$DAYS_TRIAL" >> "$TRIAL_FILE"
echo "PLANO=\"$PLANO\"" >> "$TRIAL_FILE"


}

# Valida o cliente antes de prosseguir
verificar_cliente "$EMAIL" "$SENHA"

# 🚀 DETECÇÃO DE AMBIENTE (WSL2 vs NUVEM)
IS_WSL=0
if grep -qEi "(Microsoft|WSL)" /proc/version &> /dev/null; then
    IS_WSL=1
fi

if [ "$IS_WSL" -eq 1 ]; then
    # Se for WSL2, força Cloudflare Tunnel e avisa o usuário
    whiptail --title "AMBIENTE LOCAL DETECTADO" --msgbox "⚠️ AMBIENTE WINDOWS/MAC (WSL2) DETECTADO!\n\nPara garantir que suas automações funcionem perfeitamente na sua máquina local e consigam furar o bloqueio do seu roteador de internet, o modo TRADICIONAL foi desabilitado.\n\nA instalação prosseguirá obrigatoriamente usando CLOUDFLARE TUNNEL." 15 70
    INSTALL_CHOICE="CLOUDFLARE_TUNNEL"
    
    # Trava de segurança: Cloudflare Tunnel exige plano PRO
    if [ "$PLANO" == "free" ]; then
        whiptail --title "ACESSO NEGADO" --msgbox "ERRO: A instalação local (WSL2) exige o uso do Cloudflare Tunnel, que está disponível apenas no Plano PRO ou superior.\n\nPor favor, faça o upgrade do seu plano ou utilize uma VPS em nuvem para usar a versão Gratuita." 12 70
        exit 1
    fi
else
    # Se for VPS na Nuvem, exibe o menu normal
    if [ "$PLANO" != "free" ]; then
        INSTALL_CHOICE=$(
        whiptail --title "TIPO DE INSTALAÇÃO" --menu "Escolha o tipo de configuração do proxy reverso:" 15 70 3 \
            "TRADICIONAL" "Apenas Traefik (Menos Seguro)" \
            "CLOUDFLARE_TUNNEL" "Cloudflare Tunnel + Traefik (Mais Seguro)" \
            "SAIR" "Abortar a instalação" 3>&2 2>&1 1>&3
        )
    else
        INSTALL_CHOICE=$(
        whiptail --title "TIPO DE INSTALAÇÃO" --menu "Escolha o tipo de configuração do proxy reverso:" 15 70 3 \
            "TRADICIONAL" "Apenas Traefik (Menos Seguro)" \
            "CLOUDFLARE_TUNNEL" "APENAS NO PLANO PRO" \
            "SAIR" "Abortar a instalação" 3>&2 2>&1 1>&3
        )
    fi
fi

if [ $? -ne 0 ]; then
    exit 1
fi
if [[ ("$INSTALL_CHOICE" = "CLOUDFLARE_TUNNEL") && ("$PLANO" == "free") ]]; then


 whiptail --msgbox "A Opção de Instalação com Cloudflare Tunnel está disponível apenas no Plano PRO\nDigite ENTER para voltar." 10 70
 {
  tput reset 2>/dev/null         # Reinicia o terminal de forma segura
  exec 0</dev/tty 1>/dev/tty 2>&1 # Força redirecionamentos explícitos
  sleep 0.01                     # Pausa microscópica para sincronia
  clear                          # Limpeza final antes do whiptail
} || true
 cd
 cd SetupLowCodeMno
 ./dockerswarm

fi

if [ "$INSTALL_CHOICE" = "SAIR" ]; then

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
    type_effect "INSTALAÇÃO DO SETUP MNO INTERROMPIDA!"
    echo -n " ➤ "
    type_effect "P/ A INSTALAÇÃO RECOMENDAMOS LINUX DEBIAN 12 LIMPO E ZERADO"
      echo -n " ➤ "
    type_effect "P/ RETOMAR A INSTALAÇÃO: DIGITE 'setup-mno' NO TERMINAL"
    echo "┣━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┫"
    echo -e "   \033[1;35m🚀 REQUISITOS MÍNMOS DO SERVIDOR:\033[1;37m 4gb RAM - 2 CVPU\033[1;32m         "
    echo -e "   \033[1;35m🚀 REQUISITOS RECOMENDADOS:\033[1;37m 8gb RAM - 4 CVPU\033[1;32m         "
    echo -e "   \033[1;35m🚀 ANTES DE INSTALAR:\033[1;37m Apontar registros DNS do Portainer\033[1;32m         "
    echo -e "   \033[1;35m📡 CANAIS DE SUPORTE:\033[1;32m                                 "
    echo -e "      \033[1;36m● WhatsApp: +55 (11) 96816-2690\033[1;32m                    "
    echo -e "      \033[1;36m● Email: francisbreit@gmail.com\033[1;32m                    "
    echo -e "      \033[1;36m● GitHub: github.com/francisbreit\033[1;32m                  "
    echo -e "   \033[1;33m⚠️  INSTALAÇÃO INCOMPLETA \033[1;32m                     "
    # Efeito de loading final
    echo -e "\033[1;35m"
    echo -n "  INICIANDO SEQUÊNCIA DE SAÍDA "
    for i in {1..10}; do
        echo -n "●"
        sleep 0.2
    done
    echo ""
    echo -e "\033[1;32m  ✅ SISTEMA ENCERRADO - ATÉ A PRÓXIMA!\033[0m"
        cd /
        cd
    sleep 3

    $SHELL


fi

# Registrar tipo de instalação
mkdir -p "/root/.cloudflared_config"
echo "$INSTALL_CHOICE" > "$INSTALL_TYPE_FILE"

# Se for Cloudflare Tunnel, coletar credenciais
if [[ ("$INSTALL_CHOICE" = "CLOUDFLARE_TUNNEL") && ("$PLANO" != "free") ]]; then
    # Coletar credenciais do Cloudflare
    while true; do
        CLOUDFLARE_API_TOKEN=$(whiptail --title "Cloudflare API Token" --inputbox "Digite seu Cloudflare API Token (com permissões: Cloudflare Tunnel Edit / Account: Read e, se for criar registros DNS via API, Zone.DNS Edit):" 12 80 3>&1 1>&2 2>&3)
        if [ $? -ne 0 ]; then
            exit 1
        fi
        if [ -z "$CLOUDFLARE_API_TOKEN" ]; then
            whiptail --msgbox "O Cloudflare API Token é obrigatório para configuração do Tunnel." 10 70
        else
            break
        fi
    done

    while true; do
        CLOUDFLARE_ACCOUNT_ID=$(whiptail --title "Cloudflare Account ID" --inputbox "Digite seu Cloudflare Account ID (encontre em: Cloudflare Dashboard > Overview > Account ID):" 12 80 3>&1 1>&2 2>&3)
        if [ $? -ne 0 ]; then
            exit 1
        fi
        if [ -z "$CLOUDFLARE_ACCOUNT_ID" ]; then
            whiptail --msgbox "O Cloudflare Account ID é obrigatório." 10 70
        else
            break
        fi
    done

    while true; do
        CLOUDFLARE_ZONE_ID=$(whiptail --title "Cloudflare Zone ID" --inputbox "Digite seu Cloudflare Zone ID (encontre em: Cloudflare Dashboard > Seu site > Overview > Zone ID):" 12 80 3>&1 1>&2 2>&3)
        if [ $? -ne 0 ]; then
            exit 1
        fi
        if [ -z "$CLOUDFLARE_ZONE_ID" ]; then
            whiptail --msgbox "O Cloudflare Zone ID é obrigatório." 10 70
        else
            break
        fi
    done

        while true; do
        TUNNEL_ID=$(whiptail --title "Tunnel ID" --inputbox "Digite Tunnel ID (encontre em: Cloudflare Dashboard > Seu site > Overview > Tunnel ID):" 12 80 3>&1 1>&2 2>&3)
        if [ $? -ne 0 ]; then
            exit 1
        fi
        if [ -z "$TUNNEL_ID" ]; then
            whiptail --msgbox "O Tunnel ID é obrigatório." 10 70
        else
            break
        fi
    done

    whiptail --msgbox "Credenciais iniciais do Cloudflare salvas! A rota do Tunnel será criada automaticamente durante a instalação (via API).\n\nTecle ENTER para continuar." 10 70
fi

# FIM DA ESCOLHA DO TIPO DE INSTALAÇÃO

function msg() {
                msg=$1
                whiptail --title "PARTE INICIAL: INSTALAÇÃO OBRIGATÓRIA DO DOCKER SWARM + ESSENCIAIS (TRAEFIK, PORTAINER, POSTGRES, PGBOUNCER E REDIS)" --msgbox "$msg" --fb 10 70;
        }

  while true; do
CHOICE=$(
whiptail --title "PARTE INICIAL: INSTALAÇÃO OBRIGATÓRIA DO DOCKER SWARM + ESSENCIAIS (TRAEFIK, PORTAINER, POSTGRES, PGBOUNCER E REDIS)" --menu "Use setas para navegar, Enter para selecionar e TAB para navegar\nINSTALAR: Instala o Docker Swarm e Apps essenciais\nGERADOR DE REGISTROS DE DNS: Gera aponstamentos DNS e exporta para um arquivo\nATENÇÃO: Antes de instalar, crie registros DNS p/ o Portainer. Use o nosso GERADOR DE REGISTROS DE DNS. Apontamentos:\nRECORD A: Dê um nome para seu servidor (exemplo: manager1.seudominio.com.br) e aponte para o IP do seu servidor\nRECORD CNAME: Crie um subdominio para o Portainer (exemplo: painel.seudominio.com.br) a aponte para o nome do servidor criado (exemplo: manager1.seudominio.com.br) " 20 70 3 \
  "INSTALAR" "" \
  "GERADOR DE REGISTROS DNS" "" \
  "SAIR" ""  3>&2 2>&1 1>&3
)


case $CHOICE in

        "INSTALAR")
                clear
        break
        ;;
   "GERADOR DE REGISTROS DNS")
          clear
        cd && cd SetupLowCodeMno && ./geracloudflare
    ;;

"SAIR")
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
    type_effect "INSTALAÇÃO DO SETUP MNO INTERROMPIDA!"
    echo -n " ➤ "
    type_effect "P/ A INSTALAÇÃO RECOMENDAMOS LINUX DEBIAN 12 LIMPO E ZERADO"
      echo -n " ➤ "
    type_effect "P/ RETOMAR A INSTALAÇÃO: DIGITE 'setup-mno' NO TERMINAL"
    echo "┣━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┫"
    echo -e "   \033[1;35m🚀 REQUISITOS MÍNMOS DO SERVIDOR:\033[1;37m 4gb RAM - 2 CVPU\033[1;32m         "
    echo -e "   \033[1;35m🚀 REQUISITOS RECOMENDADOS:\033[1;37m 8gb RAM - 4 CVPU\033[1;32m         "
    echo -e "   \033[1;35m🚀 ANTES DE INSTALAR:\033[1;37m Apontar registros DNS do Portainer\033[1;32m         "
    echo -e "   \033[1;35m📡 CANAIS DE SUPORTE:\033[1;32m                                 "
    echo -e "      \033[1;36m● WhatsApp: +55 (11) 96816-2690\033[1;32m                    "
    echo -e "      \033[1;36m● Email: francisbreit@gmail.com\033[1;32m                    "
    echo -e "      \033[1;36m● GitHub: github.com/francisbreit\033[1;32m                  "
    echo -e "   \033[1;33m⚠️  INSTALAÇÃO INCOMPLETA \033[1;32m                     "
    # Efeito de loading final
    echo -e "\033[1;35m"
    echo -n "  INICIANDO SEQUÊNCIA DE SAÍDA "
    for i in {1..10}; do
        echo -n "●"
        sleep 0.2
    done
    echo ""
    echo -e "\033[1;32m  ✅ SISTEMA ENCERRADO - ATÉ A PRÓXIMA!\033[0m"
        cd /
        cd
    sleep 3
    $SHELL
    ;;
esac
done

if command -v docker > /dev/null 2>&1; then
network_id_agent_network=$(docker network ls --filter name=agent_network --format "{{.ID}}")
network_id_externa=$(docker network ls --filter name=externa --format "{{.ID}}")
network_id_interna=$(docker network ls --filter name=interna --format "{{.ID}}")
traefik_container=$(docker ps -qf name=traefik)
portainer_container=$(docker ps -qf name=portainer)
postgres_container=$(docker ps -qf name=postgres)
redis_container=$(docker ps -qf name=redis)
pgbouncer_container=$(docker ps -qf name=pgbouncer)

else
network_id_agent_network=""
network_id_externa=""
network_id_interna=""
traefik_container=""
portainer_container=""
postgres_container=""
redis_container=""
pgbouncer_container=""


fi

    if [[ ("$portainer_container" == "") ]]; then
    while true ; do
                dominio=$(whiptail --title "URL do Portainer" --inputbox "Digite seu dominio para acessar o Portainer (Sem https://  ex: admin.dominio.com):" --fb 12 60 3>&1 1>&2 2>&3) ; saida=$?
                if [[ $saida -eq '0' ]] ; then
                        if [[ -z $dominio ]] ; then msg "Digite o link do Portainer para poder continuar" ; continue ; else break; fi
                else
                        echo $dominio ; echo "saindo..."  &  exit 0 ;
                fi
        done

# Verificar se URL já existe no Cloudflare Tunnel
if [ "$INSTALL_CHOICE" = "CLOUDFLARE_TUNNEL" ]; then
    CHECK_RESPONSE=$(curl -sS -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
      "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/cfd_tunnel/$TUNNEL_ID/configurations")
    EXISTING_HOST=$(echo "$CHECK_RESPONSE" | jq -r --arg h "$dominio" '.result.config.ingress[] | select(.hostname == $h) | .hostname' 2>/dev/null)
    if [[ -n "$EXISTING_HOST" ]]; then
        EXISTING_SERVICE=$(echo "$CHECK_RESPONSE" | jq -r --arg h "$dominio" '.result.config.ingress[] | select(.hostname == $h) | .service' 2>/dev/null)
        whiptail --title "Rota Existente" --msgbox "Já existe uma rota configurada para:\n\nURL: $dominio\nServiço: $EXISTING_SERVICE\n\nA rota será substituída pela nova aplicação." --fb 14 70
    fi
fi

    while true ; do
                usuariopt=$(whiptail --title "Crie o Usuário do Portainer" --inputbox "Digite o Usuario do Portainer(ex: Nome):" --fb 12 60 3>&1 1>&2 2>&3) ; saida=$?
                if [[ $saida -eq '0' ]] ; then
                if [[ (-z $usuariopt) || ("$usuariopt" =~ [^a-zA-Z0-9]) || (${#usuariopt} -gt 16) ]] ; then msg "Digite o usuário do Portainer, sem caracteres especiais e até 16 digitos para poder continuar" ; continue ; else break; fi
    else
                        echo $usuariomq ; echo "saindo..."  &  exit 0 ;
                fi
        done

    while true ; do
    senhapt=$(whiptail --title "Criar senha do Portainer" --inputbox "Crie Senha do Portainer (mínimo 12 caracteres, máximo 16, sem caracteres especiais):" --fb 12 60 3>&1 1>&2 2>&3)
    saida=$?

    if [[ $saida -eq '0' ]]; then
        # Verificações em cascata
        if [[ -z $senhapt ]]; then
            msg "A senha não pode estar vazia! Digite uma senha válida."
            continue
        elif [[ "${#senhapt}" -lt 12 ]]; then
            msg "A senha deve ter no mínimo 12 caracteres! Tente novamente."
            continue
        elif [[ "${#senhapt}" -gt 16 ]]; then
            msg "A senha não pode ultrapassar 16 caracteres! Tente novamente."
            continue
        elif [[ "$senhapt" =~ [^a-zA-Z0-9] ]]; then
            msg "Caracteres especiais não são permitidos! Use apenas letras e números."
            continue
        else
            break
        fi
    else
        echo "Operação cancelada pelo usuário."
        exit 0
    fi
done

    fi

     if [[ ("$traefik_container" == "") ]]; then
      while true ; do
                mail=$(whiptail --title "Seu Email" --inputbox "Digite seu email (ex: contato@dominio.com | sera usado no proxy reverso):" --fb 12 60 3>&1 1>&2 2>&3) ; saida=$?
                if [[ $saida -eq '0' ]] ; then
                        if [[ -z $mail ]] ; then msg "Digite o email para poder continuar" ; continue ; else break; fi
                else
                        echo $mail ; echo "saindo..."  &  exit 0 ;
                fi
        done
    fi

    if [[ ("$postgres_container" == "") ]]; then
     while true ; do
                postgres_senha=$(whiptail --title "Senha do Postgres" --inputbox "Crie a senha do Postgres (obs: use senha segura):" --fb 12 60 3>&1 1>&2 2>&3) ; saida=$?
                if [[ $saida -eq '0' ]] ; then
                if [[ (-z $postgres_senha) || ("$postgres_senha" =~ [^a-zA-Z0-9]) || (${#postgres_senha} -gt 16) ]] ; then msg "Crie a senha do Postgres, sem caracteres especiais e até 16 digitos para poder continuar" ; continue ; else break; fi
    else
                        echo $postgres_senha ; echo "saindo..."  &  exit 0 ;
                fi
        done
    fi

if [ "$INSTALL_CHOICE" = "TRADICIONAL" ]; then
 # Perguntar ao usuário se deseja criar a stack no Portainer

 while true ; do
                criar_dns=$(whiptail --title "DNS automaticamente na Cloudflare? - 0 ou 1 (Precisa estar com Conta e Dominio Ativo na Cloudflare)" --inputbox "Digite 0 para habilitar DNS automático ou 1 para não habilitar" --fb 12 60 3>&1 1>&2 2>&3) ; saida=$?
                if [[ $saida -eq '0' ]] ; then
                if [[ "$criar_dns" != "0" && "$criar_dns" != "1" ]] ; then msg "Digite apenas o número 0 ou o número 1, para poder continuar. Digite 0 para habilitar DNS automático ou 1 para não habilitar" ; continue ; else break; fi
    else
                        echo $criar_dns ; echo "saindo..."  &  exit 0 ;
                fi
        done


if [ "$criar_dns" = "0" ]; then


     while true ; do
                nome_servidor=$(whiptail --title "Nomw do Servidor" --inputbox "Crie o nome do servidor c/ letras minúsculas, sem acento e sem o dominio (exemplo: manager1, server02, etc):" --fb 12 60 3>&1 1>&2 2>&3) ; saida=$?
                if [[ $saida -eq '0' ]] ; then
                if [[ (-z $nome_servidor) || ("$nome_servidor" =~ [^a-zA-Z0-9]) || (${#nome_servidor} -gt 16) ]] ; then msg "Crie a nome do servidor, sem caracteres especiais e até 16 digitos para poder continuar" ; continue ; else break; fi
    else
                        echo $nome_servidor ; echo "saindo..."  &  exit 0 ;
                fi
        done


 # Coletar credenciais do Cloudflare
    while true; do
        CLOUDFLARE_API_TOKEN2=$(whiptail --title "Cloudflare API Token" --inputbox "Digite seu Cloudflare API Token (com permissões: Cloudflare Tunnel Edit / Account: Read e, se for criar registros DNS via API, Zone.DNS Edit):" 12 80 3>&1 1>&2 2>&3)
        if [ $? -ne 0 ]; then
            exit 1
        fi
        if [ -z "$CLOUDFLARE_API_TOKEN2" ]; then
            whiptail --msgbox "O Cloudflare API Token é obrigatório para configuração do Tunnel." 10 70
        else
            break
        fi
    done


    while true; do
        CLOUDFLARE_ZONE_ID2=$(whiptail --title "Cloudflare Zone ID" --inputbox "Digite seu Cloudflare Zone ID (encontre em: Cloudflare Dashboard > Seu site > Overview > Zone ID):" 12 80 3>&1 1>&2 2>&3)
        if [ $? -ne 0 ]; then
            exit 1
        fi
        if [ -z "$CLOUDFLARE_ZONE_ID2" ]; then
            whiptail --msgbox "O Cloudflare Zone ID é obrigatório." 10 70
        else
            break
        fi
    done

fi

fi

clear


# FIM DAS PERGUNTAS PARA VARIAVEIS

# VERIFICAÇÃO DE DADOS

clear

while true; do
    # Exibe as informações formatadas com mais espaço na tela
    if [[ ("$INSTALL_CHOICE" = "CLOUDFLARE_TUNNEL") && ("$PLANO" != "free") ]]; then
        whiptail --title "Dados Fornecidos" \
        --msgbox "TIPO DE INSTALAÇÃO: CLOUDFLARE TUNNEL\n\nDados Preenchidos:\n\n1) Dominio Portainer: $dominio\n2) Usuário do Portainer: $usuariopt\n3) Senha do Portainer: $senhapt\n4) Seu Email: $mail\n5) Senha do Postgres: $postgres_senha\n\nDados Cloudflare:\n- Account ID: ${CLOUDFLARE_ACCOUNT_ID:0:8}...\n- Zone ID: ${CLOUDFLARE_ZONE_ID:0:8}...\n- Tunnel ID: $TUNNEL_ID\n\nConfira e Tecle Enter para continuar. Na próxima etapa você poderá confirmar os dados ou corrigir, se necessário." \
        --fb 22 80
    else
    if [ "$criar_dns" = "0" ]; then
        whiptail --title "Dados Fornecidos" \
        --msgbox "TIPO DE INSTALAÇÃO: TRADICIONAL\n\nDados Preenchidos:\n\n1) Dominio Portainer: $dominio\n2) Usuário do Portainer: $usuariopt\n3) Senha do Portainer: $senhapt\n4) Seu Email: $mail\n5) Senha do Postgres: $postgres_senha\n\nDados Cloudflare:\n- Cloudflare Api Token: ${CLOUDFLARE_API_TOKEN2:0:8}...\n- Zone ID: ${CLOUDFLARE_ZONE_ID2:0:8}...\n\nConfira e Tecle Enter para continuar. Na próxima etapa você poderá confirmar os dados ou corrigir, se necessário." \
        --fb 22 80
    else

       whiptail --title "Dados Fornecidos" \
        --msgbox "TIPO DE INSTALAÇÃO: TRADICIONAL\n\nDados Preenchidos:\n\n1) Dominio Portainer: $dominio\n2) Usuário do Portainer: $usuariopt\n3) Senha do Portainer: $senhapt\n4) Seu Email: $mail\n5) Senha do Postgres: $postgres_senha\n\nConfira e Tecle Enter para continuar. Na próxima etapa você poderá confirmar os dados ou corrigir, se necessário." \
        --fb 22 80

    fi
    fi

    # Solicita confirmação com inputbox
    confirma1=$(whiptail --title "Confirmação" \
    --inputbox "Informações estavam corretas? Digite 'y' para confirmar e continuar a instalação ou 'n' para voltar e corrigir:" \
    --fb 10 60 3>&1 1>&2 2>&3)

 # Se o usuário digitou "y" ou "Y", continue
    if [[ "$confirma1" =~ ^[yY]$ ]]; then
        break
    elif [[ "$confirma1" =~ ^[nN]$ ]]; then
        # Se o usuário digitou "n" ou "N", saia do script
        msg "Você digitou N e não confirmou os dados preenchidos. Tecle Enter para sair da instalação."
        exit 0
    else
        # Qualquer outra entrada, mostre uma mensagem de erro e repita
        msg "Entrada inválida! Por favor, use apenas 'y' para sim ou 'n' para não. Digite Enter para continuar"
    fi
done

# FIM DE VERIFICAÇÃO DE DADOS

#  INSTALANDO AS DEPENDENCIAS E DOCKER SWARM

export NEWT_COLORS='
root=,white
window=,black
border=white,black
textbox=white,black
button=black,white
'

clear
{

# Função para verificar o domínio


    if [[ ("$INSTALL_CHOICE" = "CLOUDFLARE_TUNNEL") && ("$PLANO" != "free") ]]; then

      # 1. Obtendo Tunnel_token
   echo -e "XXX\n1\nOBTENDO TUNNEL_TOKEN\nXXX"
 TUNNEL_TOKEN=$(curl -s -X GET \
  "https://api.cloudflare.com/client/v4/accounts/${CLOUDFLARE_ACCOUNT_ID}/cfd_tunnel/${TUNNEL_ID}/token" \
  -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
  -H "Content-Type: application/json" | jq -r '.result')

if [[ ${TUNNEL_TOKEN} == ey* ]]; then
  echo -e "XXX\n2\nTUNNEL TOKEN OBTIDO COM SUCESSO\nXXX"
  sleep 2
else
  echo -e "XXX\n3\nERRO AO TENTAR OBTER O TUNNEL TOKEN\nXXX"
  sleep 3
  return 1
fi

    # Salvar credenciais iniciais (serão atualizadas com id/token após criar tunnel via API)
    mkdir -p /root/.cloudflared_config
  cat > /root/.cloudflared_config/cloudflare_credentials << EOL
CLOUDFLARE_API_TOKEN=$CLOUDFLARE_API_TOKEN
CLOUDFLARE_ACCOUNT_ID=$CLOUDFLARE_ACCOUNT_ID
CLOUDFLARE_ZONE_ID=$CLOUDFLARE_ZONE_ID
TUNNEL_NAME=$TUNNEL_NAME
TUNNEL_ID=$TUNNEL_ID
# NÃO salvar TUNNEL_TOKEN em texto claro se você preferir segurança; aqui salvo para uso interno
TUNNEL_TOKEN=$TUNNEL_TOKEN
EOL
  chmod 600 /root/.cloudflared_config/cloudflare_credentials


else


    mkdir -p /root/.tradicional_config
  cat > /root/.tradicional_config/tradicional_credentials << EOL
nome_servidor=$nome_servidor
criar_dns=$criar_dns
CLOUDFLARE_API_TOKEN=$CLOUDFLARE_API_TOKEN2
CLOUDFLARE_ZONE_ID=$CLOUDFLARE_ZONE_ID2

EOL
  chmod 600 /root/.tradicional_config/tradicional_credentials

        # Verificação tradicional (com IP)

if [ "$criar_dns" = "1" ]; then
   ip_servidor=$(curl -s --max-time 10 ipinfo.io/ip)
    echo -e "XXX\n3\nVERIFICANDO SUBDOMÍNIO: $dominio \nXXX"
   sleep 3
    # Verifica apenas se o domínio está apontando para o IP correto
    dns_ip=$(timeout 10 nslookup $dominio | grep "Address" | tail -n1 | awk '{print $2}')
    if [[ "$dns_ip" != "$ip_servidor" ]]; then
        echo -e "XXX\n10\nERRO: SUBDOMÍNIO NÃO APONTA PARA O IP DO SERVIDOR ($ip_servidor) \nXXX"
    sleep 3
        echo -e "XXX\n18\nERRO: REGISTROS DNS NÃO ENCONTRADOS \nXXX"
        sleep 3
        exit 1
    fi

    echo -e "XXX\n15\nDOMÍNIO VERIFICADO COM SUCESSO \nXXX"
sleep 4

fi

fi

####### fim de verificando dominio
estado=$(docker info --format '{{.Swarm.LocalNodeState}}' 2>/dev/null)

if [ "$estado" != "active" ] && [ "$estado" != "pending" ]; then



echo -e "XXX\n16\nATUALIZANDO PACOTES DO SERVIDOR 1/4 \nXXX"


# --- Início: detecção de distro / validação de versão ---
. /etc/os-release

OS_ID="${ID,,}"                       # 'debian' ou 'ubuntu' (força lowercase)
VERSION_ID_RAW="${VERSION_ID}"        # por exemplo "11" ou "22.04"
VERSION_CODENAME="${VERSION_CODENAME:-$(lsb_release -cs 2>/dev/null || true)}"

# Normaliza VERSION_ID (remove aspas se houver)
VERSION_ID=$(echo "$VERSION_ID_RAW" | tr -d '"')

# Verifica se distro suportada
supported=false
if [ "$OS_ID" = "debian" ]; then
  case "$VERSION_ID" in
    11|12|13) supported=true ;;
  esac
elif [ "$OS_ID" = "ubuntu" ]; then
  case "$VERSION_ID" in
    22.04|24.04|26.04) supported=true ;;
  esac
fi

if [ "$supported" != "true" ]; then
  echo -e "XXX\n16\nERRO: Distribuição ou versão não suportada: $OS_ID $VERSION_ID\nXXX"
  sleep 4
  echo "Suportado: debian 11,12,13 e ubuntu 22.04,24.04,26.04"
  echo -e "XXX\n17\nSuportado: debian 11,12,13 e ubuntu 22.04,24.04,26.04\nXXX"
  sleep 4
  exit 1
fi

  echo -e "XXX\n17\nDistribuição detectada: $OS_ID $VERSION_ID ($VERSION_CODENAME) - AGUARDE\nXXX"
  sleep 2
# --- Fim da detecção ---


cd /
cd

# Pacotes base
apt-get install sudo -y >/dev/null 2>&1
sudo apt-get update -y >/dev/null 2>&1
sudo apt upgrade -y >/dev/null 2>&1
sudo apt-get install -y apt-utils >/dev/null 2>&1
sudo apt-get install -y apparmor-utils >/dev/null 2>&1
# sudo DEBIAN_FRONTEND=noninteractive apt install -y dnsutils >/dev/null 2>&1
apt install -y sudo gnupg2 wget ca-certificates apt-transport-https curl gnupg nano htop lsb-release >/dev/null 2>&1
sudo install -m 0755 -d /etc/apt/keyrings >/dev/null 2>&1
sudo apt-get install jq -y >/dev/null 2>&1
sudo apt-get install git -y >/dev/null 2>&1

# Preparar repositório Docker (usa caminho apropriado para debian/ubuntu)
sudo apt-get update -y >/dev/null 2>&1
sudo apt-get install -y ca-certificates curl gnupg lsb-release >/dev/null 2>&1
sudo install -m 0755 -d /etc/apt/keyrings >/dev/null 2>&1

# Baixa a chave e cria keyring no local recomendado
curl -fsSL "https://download.docker.com/linux/${OS_ID}/gpg" \
| sudo gpg --batch --yes --dearmor -o /etc/apt/keyrings/docker.gpg >/dev/null 2>&1

sudo chmod a+r /etc/apt/keyrings/docker.gpg >/dev/null 2>&1

echo \
"deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/${OS_ID} \
${VERSION_CODENAME} stable" \
| sudo tee /etc/apt/sources.list.d/docker.list >/dev/null 2>&1


sudo apt-get update -y >/dev/null 2>&1


# Instala o Docker (Se for VPS) ou Pula (Se for WSL2)
echo -e "XXX\n25\nATUALIZANDO PACOTES DO SERVIDOR 1/4 - CONCLUIDO \nXXX"

if [ "$IS_WSL" -eq 0 ]; then
    # --- INSTALAÇÃO NA NUVEM (VPS) ---
    echo -e "XXX\n25\nINSTALANDO DOCKER ENGINE 2/4 \nXXX"
    sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin >/dev/null 2>&1

    # 🔧 CORREÇÃO PARA COMPATIBILIDADE DA API DOCKER
    echo -e "XXX\n28\nCONFIGURANDO COMPATIBILIDADE DA API DOCKER\nXXX"
    sudo mkdir -p /etc/systemd/system/docker.service.d >/dev/null 2>&1
    sudo tee /etc/systemd/system/docker.service.d/override.conf >/dev/null <<EOF
[Service]
Environment=DOCKER_MIN_API_VERSION=1.24
EOF

    sudo systemctl daemon-reexec >/dev/null 2>&1
    sudo systemctl daemon-reload >/dev/null 2>&1
    sudo systemctl restart docker >/dev/null 2>&1
    sleep 3
    # 🔧 FIM DA CORREÇÃO

    sudo systemctl enable docker.service >/dev/null 2>&1
    sudo systemctl enable containerd.service >/dev/null 2>&1
    
    # Pega o IP real da placa de rede da VPS
    ip=$(hostname -I | cut -d' ' -f1)

else
    # --- INSTALAÇÃO LOCAL (WSL2) ---
    echo -e "XXX\n25\nAMBIENTE WSL: USANDO DOCKER DESKTOP EXISTENTE 2/4 \nXXX"
    sleep 2
    
    # Força o Swarm a usar o localhost para nunca dar erro ao reiniciar o Windows
    ip="127.0.0.1"
fi

sudo timedatectl set-timezone America/Sao_Paulo >/dev/null 2>&1
sudo apt-get install -y postgresql-client >/dev/null 2>&1

sleep 5


max_attempts=3
attempt=0

while [ $attempt -le $max_attempts ]; do
   sudo docker swarm init --advertise-addr $ip > /dev/null 2>&1
    if [ $? -eq 0 ]; then
        echo -e "XXX\n32\nINICIANDO SWARM - OK \nXXX"
        break
    else
        echo -e "XXX\n35\nINICIANDO SWARM - ERRO \nXXX"
        sleep 2
        echo -e "XXX\n35\nERRO: TENTATIVA $attempt de $max_attempts  \nXXX"
        attempt=$((attempt + 1))
        sleep 3
    fi
done

if [ $attempt -gt $max_attempts ]; then
   echo -e "XXX\n35\nERRO: NÃO FOI POSSÍVEL INICIAR O SWARM APÓS $max_attempts TENTATIVAS \nXXX"
   sleep 3
   echo -e "XXX\n36\nERRO: FORMATE O VPS\nXXX"
   sleep 3
   echo -e "XXX\n37\nERRO: USE VPS VAZIA\nXXX"
   sleep 4
fi

docker network create --driver=overlay agent_network >/dev/null 2>&1
docker network create --driver=overlay externa >/dev/null 2>&1
docker network create --driver=overlay interna >/dev/null 2>&1


sudo apt install -y ca-certificates curl gnupg >/dev/null 2>&1

curl -fsSL https://azlux.fr/repo.gpg.key \
| sudo gpg --batch --yes --dearmor -o /usr/share/keyrings/azlux-archive-keyring.gpg >/dev/null 2>&1

# 🔴 SEM usar ubuntu/noble (causa 404)
# 🔴 Sempre usar debian stable (funciona em Debian e Ubuntu)

echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/azlux-archive-keyring.gpg] \
http://packages.azlux.fr/debian stable main" \
| sudo tee /etc/apt/sources.list.d/azlux.list >/dev/null 2>&1

sudo apt update -y >/dev/null 2>&1
sudo apt install -y docker-ctop >/dev/null 2>&1 || true
sudo apt install -y btop >/dev/null 2>&1
cd
cd


echo -e "XXX\n50\nINSTALANDO DOCKER 2/4 - CONCLUIDO \nXXX"
sleep 3
echo -e "XXX\n51\nINSTALANDO TRAEFIK E PORTAINER 3/4 \nXXX"
sleep 3

fi
#
# FIM DE INSTALANDO AS DEPENDENCIAS E DOCKER SWARM

#  INSTALANDO O TRAEFIK
#
cd
cd

if [[ ("$traefik_container" == "") ]]; then

if [ "$INSTALL_CHOICE" = "TRADICIONAL" ]; then
    # CONFIGURAÇÃO TRADICIONAL (com portas)
    cat > traefik.yaml << EOL

version: '3.7'
services:
    traefik:
        image: traefik:v2.11.2
        command:
            - "--providers.docker=true"
            - "--providers.docker.swarmMode=true"
            - "--providers.docker.endpoint=unix:///var/run/docker.sock"
            - "--providers.docker.exposedbydefault=false"
            - "--providers.docker.network=externa"
            - "--entrypoints.web.address=:80"
            - "--entrypoints.web.http.redirections.entryPoint.to=websecure"
            - "--entrypoints.web.http.redirections.entryPoint.scheme=https"
            - "--entrypoints.web.http.redirections.entrypoint.permanent=true"
            - "--entrypoints.websecure.address=:443"
            - "--certificatesresolvers.letsencryptresolver.acme.httpchallenge=true"
            - "--certificatesresolvers.letsencryptresolver.acme.httpchallenge.entrypoint=web"
            - "--certificatesresolvers.letsencryptresolver.acme.email=$mail"
            - "--certificatesresolvers.letsencryptresolver.acme.storage=/etc/traefik/letsencrypt/acme.json"
            - "--log.level=DEBUG"
            - "--log.format=common"
            - "--log.filePath=/var/log/traefik/traefik.log"
            - "--accesslog=true"
            - "--accesslog.filepath=/var/log/traefik/access-log"
        deploy:
            placement:
                constraints:
                    - node.role == manager
            labels:
                - "traefik.enable=true"
                - "traefik.http.middlewares.redirect-https.redirectscheme.scheme=https"
                - "traefik.http.middlewares.redirect-https.redirectscheme.permanent=true"
                - "traefik.http.routers.http-catchall.rule=hostregexp(\`{host:.+}\`)"
                - "traefik.http.routers.http-catchall.entrypoints=web"
                - "traefik.http.routers.http-catchall.middlewares=redirect-https@docker"
                - "traefik.http.routers.http-catchall.priority=1"
        volumes:
            - "/var/run/docker.sock:/var/run/docker.sock:ro"
            - "vol_certificates:/etc/traefik/letsencrypt"
        ports:
            - target: 80
              published: 80
              mode: host
            - target: 443
              published: 443
              mode: host

        networks:
            - externa
volumes:
    vol_shared:
        external: true
        name: volume_swarm_shared
    vol_certificates:
        external: true
        name: volume_swarm_certificates
networks:
    externa:
        external: true

EOL

else
    # CONFIGURAÇÃO CLOUDFLARE TUNNEL (sem portas)
    cat > traefik.yaml << EOL

version: '3.7'
services:
    traefik:
        image: traefik:v2.11.2
        command:
            - "--providers.docker=true"
            - "--providers.docker.swarmMode=true"
            - "--providers.docker.endpoint=unix:///var/run/docker.sock"
            - "--providers.docker.exposedbydefault=false"
            - "--providers.docker.network=externa"
            - "--entrypoints.web.address=:80"
            - "--entrypoints.web.http.redirections.entryPoint.to=websecure"
            - "--entrypoints.web.http.redirections.entryPoint.scheme=https"
            - "--entrypoints.web.http.redirections.entrypoint.permanent=true"
            - "--entrypoints.websecure.address=:443"
            - "--certificatesresolvers.letsencryptresolver.acme.httpchallenge=true"
            - "--certificatesresolvers.letsencryptresolver.acme.httpchallenge.entrypoint=web"
            - "--certificatesresolvers.letsencryptresolver.acme.email=$mail"
            - "--certificatesresolvers.letsencryptresolver.acme.storage=/etc/traefik/letsencrypt/acme.json"
            - "--log.level=DEBUG"
            - "--log.format=common"
            - "--log.filePath=/var/log/traefik/traefik.log"
            - "--accesslog=true"
            - "--accesslog.filepath=/var/log/traefik/access-log"
        deploy:
            placement:
                constraints:
                    - node.role == manager
            labels:
                - "traefik.enable=true"
                - "traefik.http.middlewares.redirect-https.redirectscheme.scheme=https"
                - "traefik.http.middlewares.redirect-https.redirectscheme.permanent=true"
                - "traefik.http.routers.http-catchall.rule=hostregexp(\`{host:.+}\`)"
                - "traefik.http.routers.http-catchall.entrypoints=web"
                - "traefik.http.routers.http-catchall.middlewares=redirect-https@docker"
                - "traefik.http.routers.http-catchall.priority=1"
        volumes:
            - "/var/run/docker.sock:/var/run/docker.sock:ro"
            - "vol_certificates:/etc/traefik/letsencrypt"

        networks:
            - externa
volumes:
    vol_shared:
        external: true
        name: volume_swarm_shared
    vol_certificates:
        external: true
        name: volume_swarm_certificates
networks:
    externa:
        external: true

EOL
fi

docker stack deploy --prune --resolve-image always -c traefik.yaml traefik >/dev/null 2>&1
fi

# FIM DE INSTALANDO O TRAEFIK
#
#  INSTALANDO ROTA CLOUDFLARED TUNNEL (se necessário)
#
if [[ "$INSTALL_CHOICE" = "CLOUDFLARE_TUNNEL" ]]; then
  echo -e "XXX\n55\nCRIANDO SERVIÇO E ROTA CLOUDFLARE TUNNEL \nXXX"
  sleep 3

NEW_SERVICE="http://portainer:9000"
DOMINIO_PRINCIPAL=$(echo "$dominio" | cut -d'.' -f2-)
FORCE_VERSION=3   # deixe vazio "" se não quiser forçar


# ----------- sanity checks ------------
command -v curl >/dev/null 2>&1 || { echo "curl required"; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "jq required"; exit 2; }

# ----------- temp files ------------
TIMESTAMP=$(date -u +%Y%m%dT%H%M%SZ)
TMPDIR=$(mktemp -d)
BACKUP_RAW="$TMPDIR/backup_raw.$TIMESTAMP.json"
TO_PUT="$TMPDIR/to_put.$TIMESTAMP.json"

# echo "[*] tmpdir: $TMPDIR"

# ----------- 1) GET current configuration (backup) ------------
echo "[1] GET current configuration (saving full API response) -> $BACKUP_RAW"
curl -sS -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
  "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/cfd_tunnel/$TUNNEL_ID/configurations" \
  | jq '.' > "$BACKUP_RAW"

# quick check success
if ! jq -e '.success == true' "$BACKUP_RAW" >/dev/null 2>&1; then

 # echo "ERROR: GET did not return success=true. See $BACKUP_RAW"
  jq '.' "$BACKUP_RAW"

fi

echo "[1b] Backup saved. Preview ingress (if any):"
jq '.result.config.ingress // []' "$BACKUP_RAW"

# ----------- 2) build safe payload (preserve existing, avoid duplicates, one catch-all) ------------


jq --arg host "$dominio" --arg service "$NEW_SERVICE" '
  (.result.config // {}) as $cfg
  | ($cfg.ingress // []) as $ing
  # remove any existing catch-all entries in the middle
  | ($ing | map(select(.service != "http_status:404"))) as $clean
  # gather existing hostnames for dedupe (empty string for entries that have no hostname)
  
  # if new host already present, do not append duplicate; else append new route
  | ($clean | map(select(.hostname != $host))) as $filtered
      | ($filtered + [ { hostname: $host, service: $service, originRequest: { noTlsVerify: true, httpHostHeader: $host } } ]) as $merged
  # append exactly one catch-all
  | ($merged + [{ service: "http_status:404" }]) as $final_ing
  # construct new config object, preserve other keys in config (warp-routing, etc.)
  | ($cfg + { ingress: $final_ing }) as $newcfg
  | { config: $newcfg }
' "$BACKUP_RAW" > "$TO_PUT"

# optionally force version:
if [[ -n "${FORCE_VERSION:-}" ]]; then
  jq --argjson v "$FORCE_VERSION" '.config.version = $v' "$TO_PUT" > "${TO_PUT}.v" && mv "${TO_PUT}.v" "$TO_PUT"
fi

# echo "[2b] Payload built. Ingress summary:"
jq '.config.ingress' "$TO_PUT"

# Safety: show first lines of full payload
# echo "[2c] Full payload preview (first 200 lines):"
jq '.' "$TO_PUT" | sed -n '1,200p'



# ----------- 3) PUT apply ------------
echo -e "XXX\n56\nATUALIZANDO CONFIGURAÇÕES DO TUNNEL 1 \nXXX"
#echo "[3] Applying PUT to update tunnel configuration..."
curl -sS -X PUT "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/cfd_tunnel/$TUNNEL_ID/configurations" \
  -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
  -H "Content-Type: application/json" \
  --data-binary @"$TO_PUT" | jq '.'
sleep 3
# ----------- 4) verify ------------
#echo "[4] Verifying applied configuration (GET)..."
echo -e "XXX\n57\nATUALIZANDO CONFIGURAÇÕES DO TUNNEL 2 \nXXX"
curl -sS -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
  "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/cfd_tunnel/$TUNNEL_ID/configurations" | jq '.result.config.ingress'


sleep 3
# ----------- 5) criar o registro DNS CNAME ------------
#echo ""
echo -e "XXX\n57\nVERIFICANDO E CRIANDO REGISTRO DNS CNAME... \nXXX"
# Extrair apenas o subdomínio (parte antes do domínio principal)
SUBDOMINIO=${dominio%%.$DOMINIO_PRINCIPAL}

# Verificar registros A ou CNAME existentes
#echo "[5.2] Verificando se já existe algum registro A ou CNAME para $dominio..."
EXISTING_RECORDS=$(curl -s -X GET \
  "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records?name=${dominio}" \
  -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
  -H "Content-Type: application/json")

# Contar registros encontrados
COUNT=$(echo "$EXISTING_RECORDS" | jq '.result | length')

if [[ "$COUNT" -gt 0 ]]; then
  #echo ""S
  #echo "⚠️  Foram encontrados $COUNT registro(s) existentes para $dominio:"
 # echo "---------------------------------------------------------------"
  echo "$EXISTING_RECORDS" | jq -r '.result[] | "ID: \(.id)\tTipo: \(.type)\tConteúdo: \(.content)"'
  #echo "---------------------------------------------------------------"
  #read -p "Deseja APAGAR esses registros antes de criar o novo CNAME? (y/N): " DELETE_CONFIRM


    #echo ""
    #echo "[5.3] Removendo registros antigos..."
    echo "$EXISTING_RECORDS" | jq -r '.result[].id' | while read -r REC_ID; do
      [[ -z "$REC_ID" ]] && continue
      curl -s -X DELETE \
        "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records/${REC_ID}" \
        -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
        -H "Content-Type: application/json" | jq '.'
done


else
echo -e "XXX\n58\nVERIFICANDO...ISSO PODE DEMORAR UM POUCO \nXXX"
 # echo "✅ Nenhum registro existente encontrado. Prosseguindo com a criação do novo CNAME..."
fi

# Criar o novo registro CNAME
#secho "[5.4] Criando registro CNAME..."
DNS_RESPONSE=$(curl -s -X POST \
  "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records" \
  -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
  -H "Content-Type: application/json" \
  --data "{\"type\":\"CNAME\",\"name\":\"${dominio}\",\"content\":\"${TUNNEL_ID}.cfargotunnel.com\",\"ttl\":1,\"proxied\":true}")

if echo "$DNS_RESPONSE" | grep -q '"success":true'; then
#  echo ""
echo -e "XXX\n59\n✅ REGISTRO DNS CNAME CRIADO COM SUCESSO! \nXXX"
 # echo "✅ REGISTRO DNS CNAME CRIADO COM SUCESSO!"
#  echo "→ Host: $dominio"
#  echo "→ Aponta para: ${TUNNEL_ID}.cfargotunnel.com"

else
 # echo ""
 echo -e "XXX\n59\n❌ ERRO AO CRIAR REGISTRO DNS CNAME \nXXX"
 # echo "❌ ERRO AO CRIAR REGISTRO DNS CNAME"
#  echo "Resposta: $DNS_RESPONSE"
  exit 1

fi


# Implantar serviço cloudflared no Docker Swarm
  cat > cloudflared.yaml << EOL

version: '3.7'
services:
    cloudflared:
        image: cloudflare/cloudflared
        command: tunnel run
        environment:
            - TUNNEL_TOKEN=$TUNNEL_TOKEN
        networks:
            - externa
        deploy:
            mode: replicated
            replicas: 1
            placement:
                constraints:
                    - node.role == manager

networks:
    externa:
        external: true

EOL

  docker stack deploy --prune --resolve-image always -c cloudflared.yaml cloudflared >/dev/null 2>&1
  echo -e "XXX\n58\nCLOUDFLARE TUNNEL IMPLANTADO \nXXX"
  sleep 3

  # Configurar DNS e rotas via API Cloudflare

fi


#fim2 tradicional inicio

if [ "$INSTALL_CHOICE" = "TRADICIONAL" ] && [ "$criar_dns" = "0" ] ; then
DOMINIO_PRINCIPAL=$(echo "$dominio" | cut -d'.' -f2-)

# ----------- 5) criar o registro DNS CNAME ------------

echo -e "XXX\n55\nVERIFICANDO E CRIANDO REGISTRO DNS CNAME.. \nXXX"

# Extrair apenas o subdomínio (parte antes do domínio principal)
SUBDOMINIO=${dominio%%.$DOMINIO_PRINCIPAL}

# Verificar registros A ou CNAME existentes
echo -e "XXX\n56\nVERIFICANDO...ISSO PODE DEMORAR UM POUCO \nXXX"
EXISTING_RECORDS=$(curl -s -X GET \
  "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID2}/dns_records?name=${dominio}" \
  -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN2}" \
  -H "Content-Type: application/json")

# Contar registros encontrados
COUNT=$(echo "$EXISTING_RECORDS" | jq '.result | length')

if [[ "$COUNT" -gt 0 ]]; then



  echo "$EXISTING_RECORDS" | jq -r '.result[] | "ID: \(.id)\tTipo: \(.type)\tConteúdo: \(.content)"'




echo -e "XXX\n56\nRemovendo registros antigos... \nXXX"
    echo "$EXISTING_RECORDS" | jq -r '.result[].id' | while read -r REC_ID; do
      [[ -z "$REC_ID" ]] && continue
      curl -s -X DELETE \
        "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID2}/dns_records/${REC_ID}" \
        -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN2}" \
        -H "Content-Type: application/json" | jq '.'
done


else
  echo -e "XXX\n56\Criando registro CNAME (Isso pode demorar um pouco) \nXXX"
fi

# Criar o novo registro CNAME
  echo -e "XXX\n57\Criando registro CNAME... \nXXX"

CNAME_RESPONSE=$(curl -s -X POST \
  "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID2}/dns_records" \
  -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN2}" \
  -H "Content-Type: application/json" \
  --data '{"type":"CNAME","name":"'${dominio}'","content":"'${nome_servidor}'.'${DOMINIO_PRINCIPAL}'","ttl":1,"proxied":false}')

if echo "$CNAME_RESPONSE" | grep -q '"success":true'; then
  echo -e "XXX\n58\REGISTRO DNS CNAME CRIADO COM SUCESSO! \nXXX"
  echo "→ Host: $dominio"
  echo "→ Aponta para: ${nome_servidor}.${DOMINIO_PRINCIPAL}"
else
 echo -e "XXX\n58\ERRO AO CRIAR REGISTRO DNS CNAME \nXXX"
  echo "Resposta: $CNAME_RESPONSE"
  exit 1
fi


# Criar o novo registro A
  echo -e "XXX\n58\Criando registro A... \nXXX"
ip_servidor=$(curl -s --max-time 10 ipinfo.io/ip)
A_RESPONSE=$(curl -s -X POST \
  "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID2}/dns_records" \
  -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN2}" \
  -H "Content-Type: application/json" \
  --data '{"type":"A","name":"'${nome_servidor}'","content":"'${ip_servidor}'","ttl":1,"proxied":false}')

if echo "$A_RESPONSE" | grep -q '"success":true'; then
  echo -e "XXX\n58\✅ REGISTRO DNS A CRIADO COM SUCESSO! \nXXX"
  echo "→ Host: $nome_servidor"
  echo "→ Aponta para: $ip_servidor"
else

  echo -e "XXX\n58\❌ ERRO AO CRIAR REGISTRO DNS A \nXXX"
  echo "Resposta: $A_RESPONSE"
  exit 1
fi



fi
#fim2 tradicional fim


#
#  INSTALANDO O PORTAINER
#
if [[ ("$portainer_container" == "") ]]; then
cd
rm -r dados_portainer >/dev/null 2>&1
mkdir dados_portainer >/dev/null 2>&1
cd dados_portainer >/dev/null 2>&1
cat > dados_portainer <<EOL
[ PORTAINER ]

Dominio do portainer: $dominio

Usuario: $usuariopt

Senha: $senhapt
EOL

cd

# VERIFICAR TIPO DE INSTALAÇÃO
INSTALL_TYPE_FILE="/root/.cloudflared_config/installation_type"
if [ -f "$INSTALL_TYPE_FILE" ]; then
    INSTALL_TYPE=$(cat "$INSTALL_TYPE_FILE")
else
    INSTALL_TYPE="TRADICIONAL"
fi

cat > portainer.yaml << EOL

version: "3.7"

services:

  agent:
    image: portainer/agent:2.41.1-alpine
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - /var/lib/docker/volumes:/var/lib/docker/volumes

    networks:
      - agent_network
      - externa
    deploy:
      mode: global
      placement:
        constraints: [node.platform.os == linux]

  portainer:
    image: portainer/portainer-ce:2.41.1-alpine
    command: -H tcp://tasks.agent:9001 --tlsskipverify
    volumes:
      - portainer_data:/data
    networks:
      - agent_network
      - externa
    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints: [node.role == manager]
EOL
# Adicionar as labels apenas se for instalação tradicional
if [ "$INSTALL_TYPE" = "TRADICIONAL" ]; then
cat >> portainer.yaml << EOL
      labels:
        - "traefik.enable=true"
        - "traefik.docker.network=externa"
        - "traefik.http.routers.portainer.rule=Host(\`$dominio\`)"
        - "traefik.http.routers.portainer.entrypoints=websecure"
        - "traefik.http.routers.portainer.priority=1"
        - "traefik.http.routers.portainer.tls.certresolver=letsencryptresolver"
        - "traefik.http.routers.portainer.service=portainer"
        - "traefik.http.services.portainer.loadbalancer.server.port=9000"
EOL
fi
cat >> portainer.yaml << EOL

networks:
  externa:
    external: true
  agent_network:
    external: true

volumes:
  portainer_data:
    external: true
    name: portainer_data


EOL

docker stack deploy --prune --resolve-image always -c portainer.yaml portainer >/dev/null 2>&1
## espera Portainer rodar
max_wait_time=300  #ajuste do tempo máximo de espera
wait_interval=60
elapsed_time=0

while [ $elapsed_time -lt $max_wait_time ]; do
        CONTAINER_ID=$(docker ps -qf name=portainer)
        if [ -n "$CONTAINER_ID" ]; then
                break
        fi
        sleep $wait_interval
        elapsed_time=$((elapsed_time + wait_interval))
done

if [ -z "$CONTAINER_ID" ]; then
        echo "O container no foi encontrado após $max_wait_time segundos."
        exit 1
fi



## VERIFICAÇÃO ESPECÍFICA PARA CLOUDFLARE TUNNEL
if [[ ("$INSTALL_CHOICE" = "CLOUDFLARE_TUNNEL") && ("$PLANO" != "free") ]]; then
    echo -e "XXX\n63\nAGUARDANDO CLOUDFLARE TUNNEL FICAR ATIVO\nXXX"

    # Verificação mais robusta do estado dos serviços
    echo "Verificando estado dos serviços Docker..."
    docker service ls | grep -E "(portainer|cloudflared|traefik)"

    # Aguarda um pouco mais para o tunnel estabilizar
    sleep 8

    echo "Verificando se o Cloudflare Tunnel está funcionando..."

    # Verifica se o serviço cloudflared está rodando
    if docker service ls | grep -q "cloudflared"; then
        echo -e "XXX\n64\nCLOUDFLARE TUNNEL ATIVO - VERIFICANDO ACESSO\nXXX"
    else
        echo -e "XXX\n64\nAVISO: SERVIÇO CLOUDFLARED NÃO ENCONTRADO\nXXX"
        sleep 8
    fi


fi


## cria senha no portaoner

# Configurações
PORTAINER_URL="https://$dominio/api"

# Função para verificar se o Portainer está pronto

wait_for_portainer() {
    echo -e "XXX\n64\nAGUARDANDO PORTAINER INICIALIZAR \nXXX"

    local max_attempts=30
    local attempt=1

    while [ $attempt -le $max_attempts ]; do
        STATUS=$(curl -sS --connect-timeout 10 --max-time 15 -o /dev/null -w "%{http_code}" "$PORTAINER_URL/status")

        if [ "$STATUS" -eq 200 ]; then
            echo -e "XXX\n65\nPORTAINER INICIALIZADO COM SUCESSO \nXXX"
            break
        fi

        echo -e "XXX\n64\nTENTATIVA $attempt/$max_attempts - STATUS: $STATUS \nXXX"
        sleep 5
        attempt=$((attempt + 1))
    done

    if [ "$STATUS" -ne 200 ]; then
        echo -e "XXX\n65\nERRO: PORTAINER NÃO RESPONDEU APÓS $max_attempts TENTATIVAS \nXXX"
        return 1
    fi

    return 0
}
sleep 12
# Função para verificar se o usuário administrador já existe
check_admin_user() {
    echo -e "XXX\n66\nVERIFICANDO USUÁRIO ADMIN \nXXX"
    RESPONSE=$(curl -sS -o /dev/null -w "%{http_code}" -X GET "$PORTAINER_URL/users")
    if [ "$RESPONSE" -eq 401 ]; then
        echo -e "XXX\n67\nUSUÁRIO ADMIN AINDA NÃO CONFIGURADO \nXXX"
        return 1
    elif [ "$RESPONSE" -eq 200 ]; then
        echo -e "XXX\n68\nUSUÁRIO ADMINISTRADOR JÁ CONFIGURADO \nXXX"
        return 0
    else
        echo -e "XXX\n68\nERRO AO VERIFICAR USUÁRIO ADMIN \nXXX"
        exit 1
    fi
}

# Função para criar o usuário admin
create_admin_user() {
    echo -e "XXX\n69\nCRIANDO USUÁRIO ADMIN NO PORTAINER... \nXXX"
    RESPONSE=$(curl -sS -X POST "$PORTAINER_URL/users/admin/init" \
        -H "Content-Type: application/json" \
        -d "{\"Username\": \"$usuariopt\", \"Password\": \"$senhapt\"}")

    # Verificar se a criação foi bem-sucedida
    if echo "$RESPONSE" | grep -q '"Username":"'"$usuariopt"'"'; then
        echo -e "XXX\n70\nUSUÁRIO ADMIN CRIADO COM SUCESSO \nXXX"
    else
    echo -e "XXX\n71\nERRO AO CRIAR USUÁRIO ADMIN \nXXX"
    fi
}

# Executar as funções
wait_for_portainer
if ! check_admin_user; then
    create_admin_user
fi



fi
sleep 3
echo -e "XXX\n72\nINSTALANDO TRAEFIK E PORTAINER 3/4 - CONCLUIDO \nXXX"
echo -e "XXX\n73\nINSTALANDO REDIS, POSTGRES E PGBOUNCER 4/4 \nXXX"

# FIM DE INSTALANDO O PORTAINER

#  INSTALANDO O POSTGRES - pgvector
#
if [[ ("$postgres_container" == "") ]]; then
cat > postgres.yaml << EOL

version: "3.7"

services:
  postgres:
    image: pgvector/pgvector:pg16
    environment:
      - POSTGRES_PASSWORD=$postgres_senha
    command: >
      postgres -c max_connections=1000
    networks:
      - interna
    ports:
      - 5432:5432
    volumes:
      - postgres_data:/var/lib/postgresql/data
    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
          - node.role == manager
          #- node.hostname == worker1
      resources:
       limits:
         cpus: "2"
         memory: 2048M

volumes:
  postgres_data:
    external: true
    name: postgres_data

networks:
  interna:
    external: true



EOL

docker stack deploy --prune --resolve-image always -c postgres.yaml postgres >/dev/null 2>&1
fi

# FIM DE INSTALANDO O POSTGRES

#  INSTALANDO O REDIS

if [[ ("$redis_container" == "") ]]; then
cat > redis.yaml << EOL

version: "3.7"

services:
  redis:
    image: redis:7.2.4
    command: [
        "redis-server",
        "--appendonly",
        "yes",
        "--port",
        "6379"
      ]
    volumes:
      - redis_data:/data
    networks:
      - interna
    deploy:
      placement:
        constraints:
          - node.role == manager
     # resources:
      #  limits:
        #  cpus: "0.5"
        #  memory: 1024M

volumes:
  redis_data:
    external: true
    name: redis_data

networks:
  interna:
    external: true


EOL

docker stack deploy --prune --resolve-image always -c redis.yaml redis >/dev/null 2>&1
fi

# FIM DE INSTALANDO O REDIS

#  INSTALANDO O PGBOUNCER
#
if [[ ("$pgbouncer_container" == "") ]]; then
    # Criar diretório de configuração
    mkdir -p /etc/pgbouncer

    # Criar pgbouncer.ini
    cat > /etc/pgbouncer/pgbouncer.ini << EOL

[databases]
* = host=postgres port=5432 user=postgres password=$postgres_senha

[pgbouncer]
listen_addr = *
listen_port = 6432
auth_type = md5
auth_file = /etc/pgbouncer/userlist.txt
admin_users = postgres,admin
pool_mode = transaction
max_client_conn = 1000
default_pool_size = 100
reserve_pool_size = 100
reserve_pool_timeout = 1
server_idle_timeout = 60
server_lifetime = 3600
server_connect_timeout = 5
query_timeout = 30
client_idle_timeout = 60
ignore_startup_parameters = extra_float_digits
log_connections = 1
log_disconnections = 1
log_pooler_errors = 1
stats_period = 60

EOL

    # Gerar userlist.txt com hash SCRAM-SHA-256
echo -n "$postgres_senhapostgres" | md5sum | awk '{print "\"postgres\" \"md5" substr($1,1,32) "\""}' > /etc/pgbouncer/userlist.txt

    # Garantir permissões corretas
    chown -R 70:70 /etc/pgbouncer
    chmod 644 /etc/pgbouncer/*
    chmod 600 /etc/pgbouncer/userlist.txt



cat > pgbouncer.yaml << EOL

version: "3.7"

services:
  pgbouncer:
    # Imagem do Serviço
    # https://hub.docker.com/r/edoburu/pgbouncer
    image: edoburu/pgbouncer:v1.23.1-p0
    networks:
      - interna
    # Configura a porta do Serviço para acesso externo
    #ports:
    #  - 6432:6432
    environment:
      - DB_USER=postgres
      - DB_PASSWORD=$postgres_senha
      - DB_HOST=postgres
      - POOL_MODE=transaction  # Modo obrigatório para Rails
      - AUTH_TYPE=scram-sha-256
      - DB_PORT=5432
      - ADMIN_USERS=postgres,admin
      - MAX_CLIENT_CONN=1000
      - DEFAULT_POOL_SIZE=100
      - RESERVE_POOL_SIZE=100
      - RESERVE_POOL_TIMEOUT=1
    volumes:
      - /etc/pgbouncer/pgbouncer.ini:/etc/pgbouncer/pgbouncer.ini:ro
      - /etc/pgbouncer/userlist.txt:/etc/pgbouncer/userlist.txt:ro

      # Bancos de dados que deve atuar (vazio para todos)
      #- DB_NAME=db1,db2
    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
          - node.role == manager # Rodar serviço no Manager
      resources:
        limits:
          cpus: "2"
          memory: 2048M

networks:
  interna:
    external: true


EOL

docker stack deploy --prune --resolve-image always -c pgbouncer.yaml pgbouncer >/dev/null 2>&1
fi

# FIM DE INSTALANDO O PGBOuNCER

#
# MENSAGEM DE INSTALADO + DADOS
#
sleep 5
echo -e "XXX\n76\nINSTALANDO REDIS, POSTGRES E PGBOUNCER 4/4 - CONCLUIDO \nXXX"
#}|whiptail --title "SETUP MNO - FERRAMENTAS ESSENCIAIS" --gauge "Aguarde a instalação dos ítens necessários" 6 60 0



clear



if command -v docker > /dev/null 2>&1; then

echo -e "XXX\n76\nAGUARDE: CHECANDO TODOS SERVIÇOS \nXXX"

# VERIFICA SERVIÇO TRAEFIK
sleep 1

echo -e "XXX\n75\nAGUARDE: CHECANDO TRAEFIK \nXXX"
while true; do
    # Verifica se o serviço traefik está ativo
    if docker service ls --filter "name=traefik" | grep "traefik"; then
        sleep 10
        break
    fi

    sleep 1
done

echo -e "XXX\n80\nAGUARDE: TRAEFIK OK \nXXX"
sleep 1

#######################################################################
# VERIFICA SERVIÇO PORTAINER
sleep 1
echo -e "XXX\n84\nAGUARDE: CHECANDO PORTAINER \nXXX"
while true; do
    # Verifica se o serviço portainer está ativo
    if docker service ls --filter "name=portainer" | grep "portainer"; then
        sleep 10
        break
    fi

    sleep 1
done
echo -e "XXX\n88\nAGUARDE: PORTAINER OK \nXXX"

sleep 1


# VERIFICA SERVIÇO POSTGRES
sleep 1
echo -e "XXX\n90\nAGUARDE: CHECANDO POSTGRES \nXXX"
while true; do
    # Verifica se o serviço postgres está ativo
    if docker service ls --filter "name=postgres" | grep "postgres"; then
        sleep 10
        break
    fi

    sleep 1
done
echo -e "XXX\n93\nAGUARDE: POSTGRES OK \nXXX"

sleep 1


# VERIFICA SERVIÇO REDIS

sleep 1
echo -e "XXX\n96\nAGUARDE: CHECANDO REDIS \nXXX"
while true; do
    # Verifica se o serviço redis está ativo
    if docker service ls --filter "name=redis" | grep "redis"; then
        sleep 10
        break
    fi

    sleep 1
done
echo -e "XXX\n97\nAGUARDE: REDIS OK \nXXX"

# VERIFICA SERVIÇO TRAEFIK
sleep 1

echo -e "XXX\n98\nAGUARDE: CHECANDO PGBOUNCER \nXXX"
while true; do
    # Verifica se o serviço traefik está ativo
    if docker service ls --filter "name=pgbouncer" | grep "pgbouncer"; then
        sleep 10
        break
    fi

    sleep 1
done

echo -e "XXX\n99\nAGUARDE: PGBOUNCER OK \nXXX"
sleep 1
echo -e "XXX\n100\nCONCLUÍDO: INICIANDO SETUP MNO \nXXX"

#######################################################################

else

    echo -e "XXX\n76\nERRO: Não foi possível iniciar o Docker \nXXX"
    sleep 5
    echo -e "XXX\n76\nERRO: formate a VPS e tente novamente \nXXX"
    sleep 5
    echo -e "XXX\n80\nERRO: Obrigatório o uso de VPS vazia \nXXX"
    sleep 10

    $SHELL

fi
}|whiptail --title "SETUP MNO - FERRAMENTAS ESSENCIAIS" --gauge "Aguarde a instalação dos ítens necessários" 6 60 0

offer_control_center_installation

if [[ "$INSTALL_CHOICE" = "TRADICIONAL" && "$criar_dns" == "0" ]] ; then
{
  tput reset 2>/dev/null
  exec 0</dev/tty 1>/dev/tty 2>&1
  sleep 0.01
  clear
} || true
clear
whiptail --title "INSTALAÇÃO CONCLUÍDA" --msgbox "
INSTALAÇÃO DAS FERRAMENTAS ESSENCIAIS CONCLUÍDA!
O SERVIDOR PRECISA SER REINICIADO. DIGITE ENTER PARA REINICIAR
PARA USAR O SETUP MNO NOVAMENTE SIGA AS INSTRUÇÕES ABAIXO

⚠️  INSTRUÇÕES
🚀 1 - AGUARDE 2-3 MINUTOS APÓS O REINÍCIO
🚀 2 - ACESSE ESTE SERVIDOR VIA SSH NOVAMENTE
🚀 3 - DIGITE 'setup-mno' E TECLE ENTER
📡 CANAIS DE SUPORTE:
   ● WhatsApp: +55 (11) 96816-2690
   ● Email: francisbreit@gmail.com
   ● GitHub: github.com/francisbreit

📡 DIGITE ENTER PARA REINICIAR:
" 20 70
reboot
else
    cd /root/SetupLowCodeMno
    sleep 5
    ./install
fi


# Verificação final de DNS
if [ "$INSTALL_CHOICE" = "TRADICIONAL" ]; then
    ip_servidor=$(curl -s --max-time 10 ipinfo.io/ip)
    dns_ip=$(timeout 10 nslookup $dominio | grep "Address" | tail -n1 | awk '{print $2}')

    if [[ "$dns_ip" != "$ip_servidor" ]]; then
        whiptail --title "Mensagem" --msgbox "Não foi possivel acessar o dominio do Portainer ($dominio). A instalação foi cancelada. Por favor, verifique se os apontamentos DNS estão corretos e propagados! Pressione ENTER para sair. Digite setup-mno e enter sempre que quiser iniciar o instalador." 20 78
        $SHELL
    else
    exit 0
    fi
else
    # Para Cloudflare Tunnel, apenas verificar se o domínio resolve
    if ! nslookup "$dominio" >/dev/null 2>&1; then
        whiptail --title "Mensagem" --msgbox "Não foi possivel resolver o dominio do Portainer ($dominio). Verifique se o domínio está configurado no Cloudflare. Pressione ENTER para sair." 20 78
        $SHELL
    else
        exit 0
    fi
fi

# FIM DE MENSAGEM DE INSTALADO + DADOS

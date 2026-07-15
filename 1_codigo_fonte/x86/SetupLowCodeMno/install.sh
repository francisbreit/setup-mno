#!/usr/bin/bash
#########################################################
# SETUP MNO - install.sh (refatorado)
# Menu unificado com dispatch dinamico para todos os planos
#########################################################

clear
VERSION="4.20.2"
CONTATO_WP="+55 (11) 96816-2690"
CONTATO_EMAIL="francisbreit@gmail.com"
CONTATO_GITHUB="github.com/francisbreit"

amarelo="\e[33m"
branco="\e[97m"
reset="\e[0m"

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

# --- VERIFICAR TIPO DE INSTALACAO ---
INSTALL_TYPE_FILE="/root/.cloudflared_config/installation_type"
if [ -f "$INSTALL_TYPE_FILE" ]; then
    INSTALL_TYPE=$(cat "$INSTALL_TYPE_FILE")
else
    INSTALL_TYPE="TRADICIONAL"
fi

# --- LOADING BAR (checks reais, sem sleep fake) ---
{
  steps=("Redes Docker" "Docker Swarm" "Portainer" "Traefik")
  for i in "${!steps[@]}"; do
    pct=$(( (i + 1) * 100 / ${#steps[@]} ))
    echo -e "XXX\n$pct\n$((i+1))/${#steps[@]} - Checando ${steps[$i]}...\nXXX"
  done
  echo -e "XXX\n100\nConcluido!\nXXX"
} | whiptail --title 'CHECANDO SERVIDOR' --gauge "Iniciando..." 6 60 0
clear

# --- TRIAL ---
TRIAL_DIR="/root/SetupLowCodeMno/.meu_app_trial"
TRIAL_FILE="$TRIAL_DIR/trial_info"

if [ ! -f "$TRIAL_FILE" ]; then
    echo "Erro: Arquivo de informations do trial nao encontrado. Por favor, reinstale."
    exit 1
fi

source "$TRIAL_FILE"

DATA_FORMATADA=$(echo "$DATA_INSTALACAO" | awk -F/ '{print $2 "/" $1 "/" $3}')
DATA_INSTALACAO_TIMESTAMP=$(date -d "$DATA_FORMATADA" +%s)
DATA_ATUAL_TIMESTAMP=$(date +%s)
DIFERENCA_SEGUNDOS=$(( DATA_INSTALACAO_TIMESTAMP + 7*86400 - DATA_ATUAL_TIMESTAMP ))
DIAS_RESTANTES=$(( (DIFERENCA_SEGUNDOS / 86400) + 1 ))
[ "$DIAS_RESTANTES" -lt 0 ] && DIAS_RESTANTES=0

cat > "$TRIAL_FILE" <<EOF
DATA_INSTALACAO=$DATA_INSTALACAO
DAYS_TRIAL=$DIAS_RESTANTES
PLANO="$PLANO"
EMAIL="$EMAIL"
SENHA="$SENHA"
EOF

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
    supabase_container=$(docker ps -qf name=supabase)
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
    supabase_container=""
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
    exit 0
fi

# --- REGISTRO DE APPS (flat arrays: nome_display -> script) ---
APP_NAMES=(
    "AFFINE"
    "APPSMITH"
    "AUTOGEN STUDIO"
    "BASEROW"
    "BOTPRESS"
    "CAL.COM"
    "CHATWOOTN + EVOLUTIONN 2.0 + RABBITMQ*"
    "CHATWOOTN + EVOLUTIONN 2.0 + RABBITMQ + MINIO*"
    "CHATWOOTORIG + EVOLUTIONN 2.0 + RABBITMQ + MINIO*"
    "CHATWOOTORIG (DESBLOQUEADO) + EVOLUTIONN 2.0 + RABBITMQ + MINIO*"
    "CLICKHOUSE"
    "COGNEE"
    "DATABASUS"
    "DIRECTUS"
    "DISCOURSE"
    "DOCUMENSO"
    "DOCUSEAL"
    "DOZZLE"
    "EVOAI"
    "EVOAI + EVOLUTION 2.0 + MINIO*"
    "EVOLUTION 1.0 API PADRAO"
    "EVOLUTION 2.0 API PADRAO"
    "EVOLUTION CRM"
    "EVOLUTION GO"
    "EVO NEXUS"
    "EXCALIDRAW"
    "FIRECRAWL"
    "FLOWISE"
    "FOCALBOARD"
    "FORMBRICKS"
    "GHOST"
    "GLPI"
    "GRAFANA/PROMETHEUS MONITOR"
    "HERMES AGENT"
    "HUMHUB"
    "KRAYIN CRM"
    "LANGFLOW"
    "LANGFUSE + MINIO + CLICKHOUSE*"
    "LITELLM"
    "MATTERMOST"
    "MATOMO"
    "MAUTIC 4 PADRAO"
    "MAUTIC 6 PADRAO"
    "MAUTIC 7 PADRAO"
    "MAUTIC 4 WHATSAPP MKT"
    "MAUTIC 6 WHATSAPP MKT"
    "MAUTIC 7 WHATSAPP MKT"
    "MEMGRAPH"
    "METABASE"
    "MINIO"
    "MONGODB"
    "MYSQL"
    "N8N V1 - SEM FILA (MAIN)"
    "N8N V1 - FILA (QUEUE)"
    "N8N V2 - FILA (QUEUE)"
    "N8N TEMPLATES FREE - + DE 2000 WORKFLOWS"
    "NEO4J"
    "NEXTCLOUD"
    "NOCODB"
    "NTFY"
    "ODOO"
    "OLLAMA + OPENWEBUI*"
    "OPENCLAW"
    "OPENCLAW + QDRANT + NEO4J + COGNEE + SEARXNG*"
    "OPENFANG"
    "OPEN PROJECT"
    "PAPERCLIP"
    "PGADMIN4"
    "PHPMYADMIN"
    "QDRANT"
    "RABBITMQ"
    "REDIS"
    "REDIS COMMANDER"
    "REDISINSIGHT"
    "SEARXNG"
    "SHLINK"
    "STIRLING PDF"
    "TWENTY CRM"
    "TYPEBOT"
    "TYPEBOT + MINIO*"
    "UPTIMEKUMA"
    "VAULTWARDEN"
    "WOOFED CRM"
    "WORDPRESS"
    "WUZAP"
)

APP_SCRIPTS=(
    "affine"
    "appsmith"
    "autogen"
    "baserow"
    "botpress"
    "calcom"
    "chatwootn_evo2_rabbitmq_redisevo"
    "chatwootn_evo2_rabbitmq_minio"
    "chatwooto_evo2_rabbitmq_minio"
    "chatwootorig_desbloq__evo2_rabbitmq_minio"
    "clickhouse"
    "cognee"
    "databasus"
    "directus"
    "discourse"
    "documenso"
    "docuseal"
    "dozzle"
    "evoai"
    "evoai_evo2_minio"
    "evolutionapi"
    "evolution2api"
    "evocrm"
    "evolutiongo"
    "evonexus"
    "excalidraw"
    "firecrawl"
    "flowise"
    "focalboard"
    "formbricks"
    "ghost"
    "glpi"
    "grafana"
    "hermes"
    "humhub"
    "krayincrm"
    "langflow"
    "langfuse"
    "litellm"
    "mattermost"
    "matomo"
    "mauticpadrao"
    "mautic6padrao"
    "mautic7padrao"
    "mautic4whatsmkt"
    "mautic6whatsmkt"
    "mautic7whatsmkt"
    "memgraph"
    "metabase"
    "minio"
    "mongodb"
    "mysql"
    "n8nmain"
    "n8n"
    "n8n2"
    "n8n-workflows"
    "neo4j"
    "nextcloud"
    "nocodb"
    "ntfy"
    "odoo"
    "ollama"
    "openclaw"
    "openclawpro"
    "openfang"
    "openproject"
    "paperclip"
    "pgadmin"
    "pma"
    "qdrant"
    "rabbitmq"
    "redis"
    "redicommander"
    "redisinsight"
    "searxng"
    "shlink"
    "stirlingpdf"
    "twentycrm"
    "typebot"
    "typebot_minio"
    "uptimekuma"
    "vaultwarden"
    "woofedcrm"
    "wordpress"
    "wuzap"
)

# Apps restritos ao plano PRO (usado para marcar com tag no menu free)
PRO_APPS=(
    "AFFINE" "APPSMITH" "AUTOGEN STUDIO" "BASEROW" "BOTPRESS" "CAL.COM"
    "CHATWOOTN + EVOLUTIONN 2.0 + RABBITMQ + MINIO*"
    "CHATWOOTORIG + EVOLUTIONN 2.0 + RABBITMQ + MINIO*"
    "CHATWOOTORIG (DESBLOQUEADO) + EVOLUTIONN 2.0 + RABBITMQ + MINIO*"
    "COGNEE" "DISCOURSE" "DOCUMENSO" "DOCUSEAL" "DOZZLE"
    "EVOAI + EVOLUTION 2.0 + MINIO*" "EXCALIDRAW" "FIRECRAWL" "FOCALBOARD"
    "FORMBRICKS" "GHOST" "GLPI" "HERMES AGENT" "HUMHUB" "KRAYIN CRM"
    "LANGFUSE + MINIO + CLICKHOUSE*" "LITELLM" "MATOMO"
    "MAUTIC 4 WHATSAPP MKT" "MAUTIC 6 WHATSAPP MKT" "MAUTIC 7 WHATSAPP MKT"
    "MEMGRAPH" "METABASE" "NEO4J" "NEXTCLOUD" "NOCODB" "NTFY" "ODOO"
    "OPENCLAW" "OPENCLAW + QDRANT + NEO4J + COGNEE + SEARXNG*"
    "OPENFANG" "OPEN PROJECT" "PAPERCLIP" "PHPMYADMIN" "QDRANT"
    "RABBITMQ" "REDIS COMMANDER" "REDISINSIGHT" "SEARXNG" "SHLINK"
    "STIRLING PDF" "TWENTY CRM" "TYPEBOT + MINIO*" "UPTIMEKUMA"
    "VAULTWARDEN" "WOOFED CRM" "WORDPRESS" "WUZAP"
)

# --- DISPATCH ---
dispatch_app() {
    local choice="$1"
    for i in "${!APP_NAMES[@]}"; do
        if [ "$choice" = "${APP_NAMES[$i]}" ]; then
            clear
            cd && cd SetupLowCodeMno && ./"${APP_SCRIPTS[$i]}"
            return
        fi
    done
}

# --- TITULO ---
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
    TITULO="SETUP MNO v${VERSION} - Plano: $PLANO 7 Dias - Restam: $DIAS_RESTANTES dias"
else
    TITULO="SETUP MNO v${VERSION} - Plano: $PLANO - Instalacao: $INSTALL_TYPE"
fi

# --- APPS JA INSTALADOS (single-instance) ---
check_already_installed() {
    local choice="$1"
    local container_var=""
    case "$choice" in
        "MYSQL")                     container_var="$mysql_container" ;;
        "FLOWISE")                   container_var="$flowise_container" ;;
        "MINIO")                     container_var="$minio_container" ;;
        "PGADMIN4")                  container_var="$pgadmin4_container" ;;
        "PHPMYADMIN")                container_var="$pma_container" ;;
        "REDIS COMMANDER")           container_var="$redicommander_container" ;;
        "CAL.COM")                   container_var="$calcom_container" ;;
        "LANGFUSE + MINIO + CLICKHOUSE*") container_var="$langfuse_container" ;;
        "ZEP VECTOR STORE")          container_var="${zepdb_container}${zep_container}" ;;
        "DIFY")                      container_var="$dify_container" ;;
        "SUPABASE")                  container_var="$supabase_container" ;;
        *) return 1 ;;
    esac
    [ -n "$container_var" ]
}

# --- VALIDACAO PRO ---
is_pro_only() {
    local choice="$1"
    for p in "${PRO_APPS[@]}"; do
        [ "$choice" = "$p" ] && return 0
    done
    return 1
}

# --- SAIR ---
do_exit() {
    clear
    echo -e "\033[1;36m"
    echo "============================================="
    echo -e "\033[1;33m"
    echo "  ███╗   ███╗███╗   ██╗ ██████╗"
    echo "  ████╗ ████║████╗  ██║██╔═══██╗"
    echo "  ██╔████╔██║██╔██╗ ██║██║   ██║"
    echo "  ██║╚██╔╝██║██║╚██╗██║██║   ██║"
    echo "  ██║ ╚═╝ ██║██║ ╚████║╚██████╔╝"
    echo "  ╚═╝     ╚═╝╚═╝  ╚═══╝ ╚═════╝"
    echo -e "\033[1;36m"
    echo "============================================="
    echo -e "\033[0m"
    echo -e "\033[1;32m"
    echo "  SETUP MNO FINALIZADO COM EXITO!"
    echo "  P/ INICIAR: SEMPRE DIGITE 'setup-mno' NO TERMINAL"
    echo ""
    echo -e "   \033[1;35mCOMANDO DE REATIVACAO:\033[1;37m setup-mno"
    echo -e "   \033[1;35mCANAIS DE SUPORTE:"
    echo -e "      \033[1;36m* WhatsApp: $CONTATO_WP"
    echo -e "      \033[1;36m* Email: $CONTATO_EMAIL"
    echo -e "      \033[1;36m* GitHub: $CONTATO_GITHUB"
    echo -e "   \033[1;33mSISTEMA PRONTO PARA OPERACAO"
    echo -e "\033[0m"
    sleep 1
    exit 0
}

# ===================== LOOP PRINCIPAL =====================
while true; do

# --- MONTAR MENU ---
MENU_ITEMS=()
for i in "${!APP_NAMES[@]}"; do
    app="${APP_NAMES[$i]}"
    if [[ "$PLANO" = *free* ]]; then
        tag=""
        for p in "${PRO_APPS[@]}"; do
            [ "$app" = "$p" ] && tag="PRO" && break
        done
        MENU_ITEMS+=("$app" "$tag")
    else
        MENU_ITEMS+=("$app" "")
    fi
done

# Itens de utilidade (sempre disponiveis)
MENU_ITEMS+=(
    "-------- UTILITARIOS --------" ""
    "REINICIAR APPS/SERVICOS" ""
    "DELETAR APPS/STACKS" ""
    "GERADOR DE REGISTROS DNS" ""
    "ESSENCIAIS EDITAVEIS NO PORTAINER" ""
    "SAIR" ""
)

CHOICE=$(
whiptail --title "$TITULO" --menu "Selecione um App: Use as setas do teclado e pressione ENTER" 24 78 16 \
    "${MENU_ITEMS[@]}" 3>&2 2>&1 1>&3
)

# Sair do whiptail (ESC/CANCEL)
[ -z "$CHOICE" ] && do_exit

case "$CHOICE" in

    # --- UTILITARIOS ---
    "REINICIAR APPS/SERVICOS")
        clear
        cd && cd SetupLowCodeMno && ./restartservice
        ;;

    "DELETAR APPS/STACKS")
        clear
        cd && cd SetupLowCodeMno && ./uninstall
        ;;

    "GERADOR DE REGISTROS DNS")
        clear
        cd && cd SetupLowCodeMno && ./geracloudflare
        ;;

    "ESSENCIAIS EDITAVEIS NO PORTAINER")
        clear
        cd && cd SetupLowCodeMno && ./essenciais
        ;;

    "SAIR")
        do_exit
        ;;

    # --- SEPARADOR (ignorar) ---
    "-------- UTILITARIOS --------")
        ;;

    # --- APPS (dispatch dinamico) *)
    *)
        # Ja instalado?
        if check_already_installed "$CHOICE"; then
            whiptail --msgbox "Aviso: ${CHOICE} ja esta instalado. Nao e permitido instalar mais de uma instancia.\n\nDigite ENTER para voltar ao Menu Principal." 12 70
            continue
        fi

        # Somente free: bloquear PRO
        if [[ "$PLANO" == "free" ]] && is_pro_only "$CHOICE"; then
            whiptail --msgbox "A ferramenta ${CHOICE} nao esta disponivel no plano free.\n\nEntre em contato conosco:\n- WhatsApp: $CONTATO_WP e adquira o plano PRO.\n\nPressione ENTER para voltar ao Menu Principal." 12 70
            continue
        fi

        # free1: so permite apps da whitelist
        if [ "$PLANO" == "free1" ]; then
            allowed=false
            case "$CHOICE" in
                "DATABASUS"|"EVOLUTION 2.0 API PADRAO"|"N8N V1 - SEM FILA (MAIN)"|"N8N V1 - FILA (QUEUE)"|"N8N V2 - FILA (QUEUE)"|"PGADMIN4"|"MINIO"|"REDIS"|"EVOLUTION CRM"|"EVOLUTION GO"|"EVO NEXUS")
                    allowed=true ;;
            esac
            if ! $allowed; then
                whiptail --msgbox "A ferramenta ${CHOICE} nao esta disponivel no plano free1.\n\nEntre em contato conosco:\n- WhatsApp: $CONTATO_WP e adquira o plano PRO.\n\nPressione ENTER para voltar ao Menu Principal." 12 70
                continue
            fi
        fi

        # free2: so permite apps da whitelist
        if [ "$PLANO" == "free2" ]; then
            allowed=false
            case "$CHOICE" in
                "OPENCLAW"|"EVOLUTION 2.0 API PADRAO"|"N8N V1 - SEM FILA (MAIN)"|"N8N V1 - FILA (QUEUE)"|"N8N V2 - FILA (QUEUE)"|"PGADMIN4"|"MINIO"|"REDIS"|"EVOLUTION CRM"|"EVOLUTION GO"|"EVO NEXUS")
                    allowed=true ;;
            esac
            if ! $allowed; then
                whiptail --msgbox "A ferramenta ${CHOICE} nao esta disponivel no plano free2.\n\nEntre em contato conosco:\n- WhatsApp: $CONTATO_WP e adquira o plano PRO.\n\nPressione ENTER para voltar ao Menu Principal." 12 70
                continue
            fi
        fi

        # Confirmar instalacao
        if ! whiptail --yesno "Deseja instalar ${CHOICE}?" 10 60; then
            continue
        fi

        # Despachar
        dispatch_app "$CHOICE"
        ;;

esac

done

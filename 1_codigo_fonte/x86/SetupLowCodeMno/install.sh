#!/usr/bin/bash
#########################################################
# SETUP MNO - install.sh x86 (refatorado)
# Menu explícito + dispatch dinâmico
#########################################################

clear
VERSIONSETUP="4.32.0"
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

if [ ! -f "$TRIAL_FILE" ]; then
    echo "Erro: Arquivo de informações do trial não encontrado. Por favor, reinstale."
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

# --- DISPATCH DINÂMICO (substitui 240+ case blocks) ---
run_app() {
    local script="$1"
    clear
    cd && cd SetupLowCodeMno && ./"$script"
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
        "SUPABASE")                        c="$supabase_container" ;;
        *) return 1 ;;
    esac
    [ -n "$c" ]
}

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

if [[ ! "$PLANO" = *free* ]]; then

CHOICE=$(
whiptail --title "$TITULO" --menu "Selecione um App: Use as setas do teclado e pressione ENTER" 20 70 10 \
    "ACTIVEPIECES" "" \
    "AFFINE" "" \
    "APPSMITH" "" \
    "AUTOGEN STUDIO" "" \
    "BASEROW" "" \
    "BOTPRESS" "" \
    "CAL.COM" ""  \
    "CHATWOOTN + EVOLUTIONN 2.0 + RABBITMQ*" ""   \
    "CHATWOOTN + EVOLUTIONN 2.0 + RABBITMQ + MINIO*" ""   \
    "CHATWOOTORIG + EVOLUTIONN 2.0 + RABBITMQ + MINIO*" ""   \
    "CHATWOOTORIG (DESBLOQUEADO) + EVOLUTIONN 2.0 + RABBITMQ + MINIO*" ""   \
    "CHATWOOT AI CUSTOMER SERVICE*" ""   \
    "CLICKHOUSE" ""   \
    "CODE SERVER" ""   \
    "COGNEE" ""   \
    "DATABASUS" ""   \
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
    "FORMBRICKS" "" \
    "GHOST" "" \
    "GLPI" "" \
    "GRAFANA/PROMETHEUS MONITOR" ""   \
    "HERMES AGENT" "" \
    "HEYFORM" "" \
    "HUMHUB" "" \
    "JITSI MEET" "" \
    "KEYCLOAK" "" \
    "KRAYIN CRM" "" \
    "LANGFLOW" "" \
    "LANGFUSE + MINIO + CLICKHOUSE*" "" \
    "LITELLM" "" \
    "MATTERMOST" "" \
    "MATOMO" "" \
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
    "NEO4J" "" \
    "NEXTCLOUD" "" \
    "NOCODB" "" \
    "NTFY" "" \
    "ODOO" "" \
    "OLLAMA + OPENWEBUI*" "" \
    "OPENCLAW" "" \
    "OPENCLAW + QDRANT + NEO4J + COGNEE + SEARXNG*" "" \
    "OPENFANG" "" \
    "OPEN PROJECT" "" \
    "PAPERCLIP" "" \
    "PGADMIN4" "" \
    "PHPMYADMIN" "" \
    "PLANKA" "" \
    "QDRANT" "" \
    "RABBITMQ" "" \
    "REDIS" "" \
    "REDIS COMMANDER" "" \
    "REDISINSIGHT" "" \
    "SEARXNG" "" \
    "SHLINK" "" \
    "STIRLING PDF" "" \
    "TWENTY CRM" "" \
    "TYPEBOT" "" \
    "TYPEBOT + MINIO*" "" \
    "UPTIMEKUMA" "" \
    "VAULTWARDEN" "" \
    "WOOFED CRM" "" \
    "WORDPRESS" "" \
    "WIKI.JS" "" \
    "WUZAP" "" \
    "WEKAN" "" \
    "REINICIAR APPS/SERVIÇOS" "" \
    "DELETAR APPS/STACKS" "" \
    "GERADOR DE REGISTROS DNS" "" \
    "ESSENCIAIS EDITÁVEIS NO PORTAINER" "" \
    "SAIR" ""  3>&2 2>&1 1>&3
)

[ -z "$CHOICE" ] && do_exit

case "$CHOICE" in
    "REINICIAR APPS/SERVIÇOS")  run_app restartservice ;;
    "DELETAR APPS/STACKS")      run_app uninstall ;;
    "GERADOR DE REGISTROS DNS") run_app geracloudflare ;;
    "ESSENCIAIS EDITÁVEIS NO PORTAINER") run_app essenciais ;;
    "SAIR") do_exit ;;
    *)
        if check_already_installed "$CHOICE"; then
            whiptail --msgbox "Aviso: ${CHOICE} já está instalado. Não é permitido instalar mais de uma instância.\n\nDigite ENTER para voltar ao Menu Principal." 12 70
            continue
        fi
        # Mapeamento nome -> script
        case "$CHOICE" in
            "ACTIVEPIECES")                                           run_app activepieces ;;
            "AFFINE")                                                run_app affine ;;
            "APPSMITH")                                              run_app appsmith ;;
            "AUTOGEN STUDIO")                                        run_app autogen ;;
            "BASEROW")                                               run_app baserow ;;
            "BOTPRESS")                                              run_app botpress ;;
            "CAL.COM")                                               run_app calcom ;;
            "CHATWOOTN + EVOLUTIONN 2.0 + RABBITMQ*")               run_app chatwootn_evo2_rabbitmq_redisevo ;;
            "CHATWOOTN + EVOLUTIONN 2.0 + RABBITMQ + MINIO*")       run_app chatwootn_evo2_rabbitmq_minio ;;
            "CHATWOOTORIG + EVOLUTIONN 2.0 + RABBITMQ + MINIO*")    run_app chatwooto_evo2_rabbitmq_minio ;;
            "CHATWOOTORIG (DESBLOQUEADO) + EVOLUTIONN 2.0 + RABBITMQ + MINIO*") run_app chatwootorig_desbloq__evo2_rabbitmq_minio ;;
            "CHATWOOT AI CUSTOMER SERVICE*") run_app chatwoot_ai_customer_service ;;
            "CLICKHOUSE")                                            run_app clickhouse ;;
            "CODE SERVER")                                           run_app codeserver ;;
            "COGNEE")                                                run_app cognee ;;
            "DATABASUS")                                             run_app databasus ;;
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
            "EVOLUTION CRM")                                         run_app evocrm ;;
            "EVOLUTION GO")                                          run_app evolutiongo ;;
            "EVO NEXUS")                                             run_app evonexus ;;
            "EXCALIDRAW")                                            run_app excalidraw ;;
            "FIRECRAWL")                                             run_app firecrawl ;;
            "FLOWISE")                                               run_app flowise ;;
            "FOCALBOARD")                                            run_app focalboard ;;
            "FORMBRICKS")                                            run_app formbricks ;;
            "GHOST")                                                 run_app ghost ;;
            "GLPI")                                                  run_app glpi ;;
            "GRAFANA/PROMETHEUS MONITOR")                            run_app grafana ;;
            "HERMES AGENT")                                          run_app hermes ;;
            "HEYFORM")                                               run_app heyform ;;
            "HUMHUB")                                                run_app humhub ;;
            "JITSI MEET")                                            run_app jitsi ;;
            "KEYCLOAK")                                              run_app keycloak ;;
            "KRAYIN CRM")                                            run_app krayincrm ;;
            "LANGFLOW")                                              run_app langflow ;;
            "LANGFUSE + MINIO + CLICKHOUSE*")                       run_app langfuse ;;
            "LITELLM")                                               run_app litellm ;;
            "MATTERMOST")                                            run_app mattermost ;;
            "MATOMO")                                                run_app matomo ;;
            "MAUTIC 4 PADRÃO")                                       run_app mauticpadrao ;;
            "MAUTIC 6 PADRÃO")                                       run_app mautic6padrao ;;
            "MAUTIC 7 PADRÃO")                                       run_app mautic7padrao ;;
            "MAUTIC 4 WHATSAPP MKT")                                 run_app mautic4whatsmkt ;;
            "MAUTIC 6 WHATSAPP MKT")                                 run_app mautic6whatsmkt ;;
            "MAUTIC 7 WHATSAPP MKT")                                 run_app mautic7whatsmkt ;;
            "MEMGRAPH")                                              run_app memgraph ;;
            "METABASE")                                              run_app metabase ;;
            "MINIO")                                                 run_app minio ;;
            "MONGODB")                                               run_app mongodb ;;
            "MYSQL")                                                 run_app mysql ;;
            "N8N V1 - SEM FILA (MAIN)")                              run_app n8nmain ;;
            "N8N V1 - FILA (QUEUE)")                                 run_app n8n ;;
            "N8N V2 - FILA (QUEUE)")                                 run_app n8n2 ;;
            "N8N TEMPLATES FREE - + DE 2000 WORKFLOWS")              run_app n8n-workflows ;;
            "NEO4J")                                                 run_app neo4j ;;
            "NEXTCLOUD")                                             run_app nextcloud ;;
            "NOCODB")                                                run_app nocodb ;;
            "NTFY")                                                  run_app ntfy ;;
            "ODOO")                                                  run_app odoo ;;
            "OLLAMA + OPENWEBUI*")                                   run_app ollama ;;
            "OPENCLAW")                                              run_app openclaw ;;
            "OPENCLAW + QDRANT + NEO4J + COGNEE + SEARXNG*")        run_app openclawpro ;;
            "OPENFANG")                                              run_app openfang ;;
            "OPEN PROJECT")                                          run_app openproject ;;
            "PAPERCLIP")                                             run_app paperclip ;;
            "PGADMIN4")                                              run_app pgadmin ;;
            "PLANKA")                                               run_app planka ;;
            "PHPMYADMIN")                                            run_app pma ;;
            "QDRANT")                                                run_app qdrant ;;
            "RABBITMQ")                                              run_app rabbitmq ;;
            "REDIS")                                                 run_app redis ;;
            "REDIS COMMANDER")                                       run_app redicommander ;;
            "REDISINSIGHT")                                          run_app redisinsight ;;
            "SEARXNG")                                               run_app searxng ;;
            "SHLINK")                                                run_app shlink ;;
            "STIRLING PDF")                                          run_app stirlingpdf ;;
            "TWENTY CRM")                                            run_app twentycrm ;;
            "TYPEBOT")                                               run_app typebot ;;
            "TYPEBOT + MINIO*")                                      run_app typebot_minio ;;
            "UPTIMEKUMA")                                            run_app uptimekuma ;;
            "VAULTWARDEN")                                           run_app vaultwarden ;;
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
    "SHLINK" "" \
    "STIRLING PDF" "" \
    "TYPEBOT" "" \
    "UPTIMEKUMA" "" \
    "VAULTWARDEN" "" \
    "WORDPRESS" "" \
    "WIKI.JS" "" \
    "WUZAP" "" \
    "WEKAN" "" \
    "─────────────────────────" "" \
    "ACTIVEPIECES" "PRO" \
    "AFFINE" "PRO" \
    "APPSMITH" "PRO" \
    "AUTOGEN STUDIO" "PRO" \
    "BASEROW" "PRO" \
    "BOTPRESS" "PRO" \
    "CAL.COM" "PRO"  \
    "CHATWOOTN + EVOLUTIONN 2.0 + RABBITMQ + MINIO*" "PRO"   \
    "CHATWOOTORIG + EVOLUTIONN 2.0 + RABBITMQ + MINIO*" "PRO"   \
    "CHATWOOTORIG (DESBLOQUEADO) + EVOLUTIONN 2.0 + RABBITMQ + MINIO*" "PRO"   \
    "CHATWOOT AI CUSTOMER SERVICE*" "PRO"   \
    "CODE SERVER" "PRO"   \
    "COGNEE" "PRO"   \
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
    "FORMBRICKS" "PRO" \
    "GHOST" "PRO" \
    "GLPI" "PRO" \
    "HERMES AGENT" "PRO" \
    "HEYFORM" "PRO" \
    "HUMHUB" "PRO" \
    "JITSI MEET" "PRO" \
    "KEYCLOAK" "PRO" \
    "KRAYIN CRM" "PRO" \
    "LANGFLOW" "PRO" \
    "LANGFUSE + MINIO + CLICKHOUSE*" "PRO" \
    "LITELLM" "PRO" \
    "MATTERMOST" "PRO" \
    "MATOMO" "PRO" \
    "MAUTIC 4 PADRÃO" "PRO" \
    "MAUTIC 4 WHATSAPP MKT" "PRO" \
    "MAUTIC 6 WHATSAPP MKT" "PRO" \
    "MAUTIC 7 WHATSAPP MKT" "PRO" \
    "MEMGRAPH" "PRO" \
    "METABASE" "PRO" \
    "NEO4J" "PRO" \
    "NEXTCLOUD" "PRO" \
    "ODOO" "PRO" \
    "OPENCLAW" "PRO" \
    "OPENCLAW + QDRANT + NEO4J + COGNEE + SEARXNG*" "PRO" \
    "OPENFANG" "PRO" \
    "OPEN PROJECT" "PRO" \
    "PAPERCLIP" "PRO" \
    "SEARXNG" "PRO" \
    "TWENTY CRM" "PRO" \
    "TYPEBOT + MINIO*" "PRO" \
    "PLANKA" "PRO" \
    "WOOFED CRM" "PRO" \
    "WIKI.JS" "PRO" \
    "REINICIAR APPS/SERVIÇOS" "" \
    "DELETAR APPS/STACKS" "" \
    "GERADOR DE REGISTROS DNS" "" \
    "ESSENCIAIS EDITÁVEIS NO PORTAINER" "" \
    "SAIR" ""  3>&2 2>&1 1>&3
)

[ -z "$CHOICE" ] && do_exit

case "$CHOICE" in
    "REINICIAR APPS/SERVIÇOS")  run_app restartservice ;;
    "DELETAR APPS/STACKS")      run_app uninstall ;;
    "GERADOR DE REGISTROS DNS") run_app geracloudflare ;;
    "ESSENCIAIS EDITÁVEIS NO PORTAINER") run_app essenciais ;;
    "SAIR") do_exit ;;
    *)
        if check_already_installed "$CHOICE"; then
            whiptail --msgbox "Aviso: ${CHOICE} já está instalado. Não é permitido instalar mais de uma instância.\n\nDigite ENTER para voltar ao Menu Principal." 12 70
            continue
        fi
        if [[ ("$CHOICE" == "AFFINE") || ("$CHOICE" == "APPSMITH") || ("$CHOICE" == "AUTOGEN STUDIO") || ("$CHOICE" == "BASEROW") || ("$CHOICE" == "BOTPRESS") || ("$CHOICE" == "CAL.COM") || ("$CHOICE" == "CHATWOOTN + EVOLUTIONN 2.0 + RABBITMQ + MINIO*") || ("$CHOICE" == "DOCUMENSO") || ("$CHOICE" == "DOCUSEAL") || ("$CHOICE" == "DOZZLE") || ("$CHOICE" == "EVOAI + EVOLUTION 2.0 + MINIO*") || ("$CHOICE" == "HUMHUB") || ("$CHOICE" == "KRAYIN CRM") || ("$CHOICE" == "LANGFUSE + MINIO + CLICKHOUSE*") || ("$CHOICE" == "LITELLM") || ("$CHOICE" == "MAUTIC 4 WHATSAPP MKT") || ("$CHOICE" == "MAUTIC 6 WHATSAPP MKT") || ("$CHOICE" == "MAUTIC 7 WHATSAPP MKT") || ("$CHOICE" == "MATOMO") || ("$CHOICE" == "NEXTCLOUD") || ("$CHOICE" == "OPEN PROJECT") || ("$CHOICE" == "TWENTY CRM") || ("$CHOICE" == "TYPEBOT + MINIO*") || ("$CHOICE" == "OPENCLAW") || ("$CHOICE" == "DISCOURSE") || ("$CHOICE" == "GHOST") || ("$CHOICE" == "COGNEE") || ("$CHOICE" == "MEMGRAPH") || ("$CHOICE" == "NEO4J") || ("$CHOICE" == "OPENFANG") || ("$CHOICE" == "PAPERCLIP") || ("$CHOICE" == "SEARXNG") || ("$CHOICE" == "OPENCLAW + QDRANT + NEO4J + COGNEE + SEARXNG*") || ("$CHOICE" == "HERMES AGENT") || ("$CHOICE" == "CHATWOOTORIG + EVOLUTIONN 2.0 + RABBITMQ + MINIO*") || ("$CHOICE" == "CHATWOOTORIG (DESBLOQUEADO) + EVOLUTIONN 2.0 + RABBITMQ + MINIO*") || ("$CHOICE" == "CHATWOOT AI CUSTOMER SERVICE*") ]]; then
            whiptail --msgbox "A ferramenta ${CHOICE} não está disponível no plano free.\n\nEntre em contato conosco:\n- WhatsApp: $CONTATO_WP e adquira o plano PRO.\n\nPressione ENTER para voltar ao Menu Principal." 12 70
            continue
        fi
        case "$CHOICE" in
            "AFFINE")                                                run_app affine ;;
            "APPSMITH")                                              run_app appsmith ;;
            "AUTOGEN STUDIO")                                        run_app autogen ;;
            "BASEROW")                                               run_app baserow ;;
            "BOTPRESS")                                              run_app botpress ;;
            "CAL.COM")                                               run_app calcom ;;
            "CHATWOOTN + EVOLUTIONN 2.0 + RABBITMQ*")               run_app chatwootn_evo2_rabbitmq_redisevo ;;
            "CHATWOOTN + EVOLUTIONN 2.0 + RABBITMQ + MINIO*")       run_app chatwootn_evo2_rabbitmq_minio ;;
            "CHATWOOTORIG + EVOLUTIONN 2.0 + RABBITMQ + MINIO*")    run_app chatwooto_evo2_rabbitmq_minio ;;
            "CHATWOOTORIG (DESBLOQUEADO) + EVOLUTIONN 2.0 + RABBITMQ + MINIO*") run_app chatwootorig_desbloq__evo2_rabbitmq_minio ;;
            "CHATWOOT AI CUSTOMER SERVICE*") run_app chatwoot_ai_customer_service ;;
            "CLICKHOUSE")                                            run_app clickhouse ;;
            "CODE SERVER")                                           run_app codeserver ;;
            "COGNEE")                                                run_app cognee ;;
            "DATABASUS")                                             run_app databasus ;;
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
            "EVOLUTION CRM")                                         run_app evocrm ;;
            "EVOLUTION GO")                                          run_app evolutiongo ;;
            "EVO NEXUS")                                             run_app evonexus ;;
            "EXCALIDRAW")                                            run_app excalidraw ;;
            "FIRECRAWL")                                             run_app firecrawl ;;
            "FLOWISE")                                               run_app flowise ;;
            "FOCALBOARD")                                            run_app focalboard ;;
            "FORMBRICKS")                                            run_app formbricks ;;
            "GHOST")                                                 run_app ghost ;;
            "GLPI")                                                  run_app glpi ;;
            "GRAFANA/PROMETHEUS MONITOR")                            run_app grafana ;;
            "HERMES AGENT")                                          run_app hermes ;;
            "HEYFORM")                                               run_app heyform ;;
            "HUMHUB")                                                run_app humhub ;;
            "JITSI MEET")                                            run_app jitsi ;;
            "KEYCLOAK")                                              run_app keycloak ;;
            "KRAYIN CRM")                                            run_app krayincrm ;;
            "LANGFLOW")                                              run_app langflow ;;
            "LANGFUSE + MINIO + CLICKHOUSE*")                       run_app langfuse ;;
            "LITELLM")                                               run_app litellm ;;
            "MATTERMOST")                                            run_app mattermost ;;
            "MATOMO")                                                run_app matomo ;;
            "MAUTIC 4 PADRÃO")                                       run_app mauticpadrao ;;
            "MAUTIC 6 PADRÃO")                                       run_app mautic6padrao ;;
            "MAUTIC 7 PADRÃO")                                       run_app mautic7padrao ;;
            "MAUTIC 4 WHATSAPP MKT")                                 run_app mautic4whatsmkt ;;
            "MAUTIC 6 WHATSAPP MKT")                                 run_app mautic6whatsmkt ;;
            "MAUTIC 7 WHATSAPP MKT")                                 run_app mautic7whatsmkt ;;
            "MEMGRAPH")                                              run_app memgraph ;;
            "METABASE")                                              run_app metabase ;;
            "MINIO")                                                 run_app minio ;;
            "MONGODB")                                               run_app mongodb ;;
            "MYSQL")                                                 run_app mysql ;;
            "N8N V1 - SEM FILA (MAIN)")                              run_app n8nmain ;;
            "N8N V1 - FILA (QUEUE)")                                 run_app n8n ;;
            "N8N V2 - FILA (QUEUE)")                                 run_app n8n2 ;;
            "N8N TEMPLATES FREE - + DE 2000 WORKFLOWS")              run_app n8n-workflows ;;
            "NEO4J")                                                 run_app neo4j ;;
            "NEXTCLOUD")                                             run_app nextcloud ;;
            "NOCODB")                                                run_app nocodb ;;
            "NTFY")                                                  run_app ntfy ;;
            "ODOO")                                                  run_app odoo ;;
            "OLLAMA + OPENWEBUI*")                                   run_app ollama ;;
            "OPENCLAW")                                              run_app openclaw ;;
            "OPENCLAW + QDRANT + NEO4J + COGNEE + SEARXNG*")        run_app openclawpro ;;
            "OPENFANG")                                              run_app openfang ;;
            "OPEN PROJECT")                                          run_app openproject ;;
            "PAPERCLIP")                                             run_app paperclip ;;
            "PGADMIN4")                                              run_app pgadmin ;;
            "PLANKA")                                               run_app planka ;;
            "PHPMYADMIN")                                            run_app pma ;;
            "QDRANT")                                                run_app qdrant ;;
            "RABBITMQ")                                              run_app rabbitmq ;;
            "REDIS")                                                 run_app redis ;;
            "REDIS COMMANDER")                                       run_app redicommander ;;
            "REDISINSIGHT")                                          run_app redisinsight ;;
            "SEARXNG")                                               run_app searxng ;;
            "SHLINK")                                                run_app shlink ;;
            "STIRLING PDF")                                          run_app stirlingpdf ;;
            "TWENTY CRM")                                            run_app twentycrm ;;
            "TYPEBOT")                                               run_app typebot ;;
            "TYPEBOT + MINIO*")                                      run_app typebot_minio ;;
            "UPTIMEKUMA")                                            run_app uptimekuma ;;
            "VAULTWARDEN")                                           run_app vaultwarden ;;
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
    "─────────────────────────" "" \
    "ACTIVEPIECES" "PRO" \
    "AFFINE" "PRO" \
    "APPSMITH" "PRO" \
    "AUTOGEN STUDIO" "PRO" \
    "BASEROW" "PRO" \
    "BOTPRESS" "PRO" \
    "CAL.COM" "PRO"  \
    "CHATWOOTN + EVOLUTIONN 2.0 + RABBITMQ*" "PRO"   \
    "CHATWOOTN + EVOLUTIONN 2.0 + RABBITMQ + MINIO*" "PRO"   \
    "CHATWOOTORIG + EVOLUTIONN 2.0 + RABBITMQ + MINIO*" "PRO"   \
    "CHATWOOTORIG (DESBLOQUEADO) + EVOLUTIONN 2.0 + RABBITMQ + MINIO*" "PRO"   \
    "CHATWOOT AI CUSTOMER SERVICE*" "PRO"   \
    "CLICKHOUSE" "PRO"   \
    "CODE SERVER" "PRO"   \
    "COGNEE" "PRO"   \
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
    "FORMBRICKS" "PRO" \
    "GHOST" "PRO" \
    "GLPI" "PRO" \
    "GRAFANA/PROMETHEUS MONITOR" "PRO"   \
    "HERMES AGENT" "PRO" \
    "HEYFORM" "PRO" \
    "HUMHUB" "PRO" \
    "JITSI MEET" "PRO" \
    "KEYCLOAK" "PRO" \
    "KRAYIN CRM" "PRO" \
    "LANGFLOW" "PRO" \
    "LANGFUSE + MINIO + CLICKHOUSE*" "PRO" \
    "LITELLM" "PRO" \
    "MATTERMOST" "PRO" \
    "MATOMO" "PRO" \
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
    "NEO4J" "PRO" \
    "NEXTCLOUD" "PRO" \
    "NOCODB" "PRO" \
    "NTFY" "PRO" \
    "ODOO" "PRO" \
    "OLLAMA + OPENWEBUI*" "PRO" \
    "OPENCLAW" "PRO" \
    "OPENCLAW + QDRANT + NEO4J + COGNEE + SEARXNG*" "PRO" \
    "OPENFANG" "PRO" \
    "OPEN PROJECT" "PRO" \
    "PAPERCLIP" "PRO" \
    "PHPMYADMIN" "PRO" \
    "PLANKA" "PRO" \
    "QDRANT" "PRO" \
    "RABBITMQ" "PRO" \
    "REDIS COMMANDER" "PRO" \
    "REDISINSIGHT" "PRO" \
    "SEARXNG" "PRO" \
    "SHLINK" "PRO" \
    "STIRLING PDF" "PRO" \
    "TWENTY CRM" "PRO" \
    "TYPEBOT" "PRO" \
    "TYPEBOT + MINIO*" "PRO" \
    "UPTIMEKUMA" "PRO" \
    "VAULTWARDEN" "PRO" \
    "WOOFED CRM" "PRO" \
    "WORDPRESS" "PRO" \
    "WIKI.JS" "PRO" \
    "WUZAP" "PRO" \
    "WEKAN" "PRO" \
    "REINICIAR APPS/SERVIÇOS" "" \
    "DELETAR APPS/STACKS" "" \
    "GERADOR DE REGISTROS DNS" "" \
    "ESSENCIAIS EDITÁVEIS NO PORTAINER" "" \
    "SAIR" ""  3>&2 2>&1 1>&3
)

[ -z "$CHOICE" ] && do_exit

case "$CHOICE" in
    "REINICIAR APPS/SERVIÇOS")  run_app restartservice ;;
    "DELETAR APPS/STACKS")      run_app uninstall ;;
    "GERADOR DE REGISTROS DNS") run_app geracloudflare ;;
    "ESSENCIAIS EDITÁVEIS NO PORTAINER") run_app essenciais ;;
    "SAIR") do_exit ;;
    *)
        if check_already_installed "$CHOICE"; then
            whiptail --msgbox "Aviso: ${CHOICE} já está instalado. Não é permitido instalar mais de uma instância.\n\nDigite ENTER para voltar ao Menu Principal." 12 70
            continue
        fi
        if [[ ("$CHOICE" != "DATABASUS") && ("$CHOICE" != "EVOLUTION 2.0 API PADRÃO") && ("$CHOICE" != "N8N V1 - SEM FILA (MAIN)") && ("$CHOICE" != "N8N V1 - FILA (QUEUE)") && ("$CHOICE" != "N8N V2 - FILA (QUEUE)") && ("$CHOICE" != "PGADMIN4") && ("$CHOICE" != "MINIO") && ("$CHOICE" != "REDIS") && ("$CHOICE" != "EVOLUTION CRM") && ("$CHOICE" != "EVOLUTION GO") && ("$CHOICE" != "EVO NEXUS") ]]; then
            whiptail --msgbox "A ferramenta ${CHOICE} não está disponível no plano free1.\n\nEntre em contato conosco:\n- WhatsApp: $CONTATO_WP e adquira o plano PRO.\n\nPressione ENTER para voltar ao Menu Principal." 12 70
            continue
        fi
        case "$CHOICE" in
            "AFFINE")                                                run_app affine ;;
            "APPSMITH")                                              run_app appsmith ;;
            "AUTOGEN STUDIO")                                        run_app autogen ;;
            "BASEROW")                                               run_app baserow ;;
            "BOTPRESS")                                              run_app botpress ;;
            "CAL.COM")                                               run_app calcom ;;
            "CHATWOOTN + EVOLUTIONN 2.0 + RABBITMQ*")               run_app chatwootn_evo2_rabbitmq_redisevo ;;
            "CHATWOOTN + EVOLUTIONN 2.0 + RABBITMQ + MINIO*")       run_app chatwootn_evo2_rabbitmq_minio ;;
            "CHATWOOTORIG + EVOLUTIONN 2.0 + RABBITMQ + MINIO*")    run_app chatwooto_evo2_rabbitmq_minio ;;
            "CHATWOOTORIG (DESBLOQUEADO) + EVOLUTIONN 2.0 + RABBITMQ + MINIO*") run_app chatwootorig_desbloq__evo2_rabbitmq_minio ;;
            "CHATWOOT AI CUSTOMER SERVICE*") run_app chatwoot_ai_customer_service ;;
            "CLICKHOUSE")                                            run_app clickhouse ;;
            "CODE SERVER")                                           run_app codeserver ;;
            "COGNEE")                                                run_app cognee ;;
            "DATABASUS")                                             run_app databasus ;;
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
            "EVOLUTION CRM")                                         run_app evocrm ;;
            "EVOLUTION GO")                                          run_app evolutiongo ;;
            "EVO NEXUS")                                             run_app evonexus ;;
            "EXCALIDRAW")                                            run_app excalidraw ;;
            "FIRECRAWL")                                             run_app firecrawl ;;
            "FLOWISE")                                               run_app flowise ;;
            "FOCALBOARD")                                            run_app focalboard ;;
            "FORMBRICKS")                                            run_app formbricks ;;
            "GHOST")                                                 run_app ghost ;;
            "GLPI")                                                  run_app glpi ;;
            "GRAFANA/PROMETHEUS MONITOR")                            run_app grafana ;;
            "HERMES AGENT")                                          run_app hermes ;;
            "HEYFORM")                                               run_app heyform ;;
            "HUMHUB")                                                run_app humhub ;;
            "JITSI MEET")                                            run_app jitsi ;;
            "KEYCLOAK")                                              run_app keycloak ;;
            "KRAYIN CRM")                                            run_app krayincrm ;;
            "LANGFLOW")                                              run_app langflow ;;
            "LANGFUSE + MINIO + CLICKHOUSE*")                       run_app langfuse ;;
            "LITELLM")                                               run_app litellm ;;
            "MATTERMOST")                                            run_app mattermost ;;
            "MATOMO")                                                run_app matomo ;;
            "MAUTIC 4 PADRÃO")                                       run_app mauticpadrao ;;
            "MAUTIC 6 PADRÃO")                                       run_app mautic6padrao ;;
            "MAUTIC 7 PADRÃO")                                       run_app mautic7padrao ;;
            "MAUTIC 4 WHATSAPP MKT")                                 run_app mautic4whatsmkt ;;
            "MAUTIC 6 WHATSAPP MKT")                                 run_app mautic6whatsmkt ;;
            "MAUTIC 7 WHATSAPP MKT")                                 run_app mautic7whatsmkt ;;
            "MEMGRAPH")                                              run_app memgraph ;;
            "METABASE")                                              run_app metabase ;;
            "MINIO")                                                 run_app minio ;;
            "MONGODB")                                               run_app mongodb ;;
            "MYSQL")                                                 run_app mysql ;;
            "N8N V1 - SEM FILA (MAIN)")                              run_app n8nmain ;;
            "N8N V1 - FILA (QUEUE)")                                 run_app n8n ;;
            "N8N V2 - FILA (QUEUE)")                                 run_app n8n2 ;;
            "N8N TEMPLATES FREE - + DE 2000 WORKFLOWS")              run_app n8n-workflows ;;
            "NEO4J")                                                 run_app neo4j ;;
            "NEXTCLOUD")                                             run_app nextcloud ;;
            "NOCODB")                                                run_app nocodb ;;
            "NTFY")                                                  run_app ntfy ;;
            "ODOO")                                                  run_app odoo ;;
            "OLLAMA + OPENWEBUI*")                                   run_app ollama ;;
            "OPENCLAW")                                              run_app openclaw ;;
            "OPENCLAW + QDRANT + NEO4J + COGNEE + SEARXNG*")        run_app openclawpro ;;
            "OPENFANG")                                              run_app openfang ;;
            "OPEN PROJECT")                                          run_app openproject ;;
            "PAPERCLIP")                                             run_app paperclip ;;
            "PGADMIN4")                                              run_app pgadmin ;;
            "PLANKA")                                               run_app planka ;;
            "PHPMYADMIN")                                            run_app pma ;;
            "QDRANT")                                                run_app qdrant ;;
            "RABBITMQ")                                              run_app rabbitmq ;;
            "REDIS")                                                 run_app redis ;;
            "REDIS COMMANDER")                                       run_app redicommander ;;
            "REDISINSIGHT")                                          run_app redisinsight ;;
            "SEARXNG")                                               run_app searxng ;;
            "SHLINK")                                                run_app shlink ;;
            "STIRLING PDF")                                          run_app stirlingpdf ;;
            "TWENTY CRM")                                            run_app twentycrm ;;
            "TYPEBOT")                                               run_app typebot ;;
            "TYPEBOT + MINIO*")                                      run_app typebot_minio ;;
            "UPTIMEKUMA")                                            run_app uptimekuma ;;
            "VAULTWARDEN")                                           run_app vaultwarden ;;
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
    "─────────────────────────" "" \
    "ACTIVEPIECES" "PRO" \
    "AFFINE" "PRO" \
    "APPSMITH" "PRO" \
    "AUTOGEN STUDIO" "PRO" \
    "BASEROW" "PRO" \
    "BOTPRESS" "PRO" \
    "CAL.COM" "PRO"  \
    "CHATWOOTN + EVOLUTIONN 2.0 + RABBITMQ*" "PRO"   \
    "CHATWOOTN + EVOLUTIONN 2.0 + RABBITMQ + MINIO*" "PRO"   \
    "CHATWOOTORIG + EVOLUTIONN 2.0 + RABBITMQ + MINIO*" "PRO"   \
    "CHATWOOTORIG (DESBLOQUEADO) + EVOLUTIONN 2.0 + RABBITMQ + MINIO*" "PRO"   \
    "CHATWOOT AI CUSTOMER SERVICE*" "PRO"   \
    "CLICKHOUSE" "PRO"   \
    "CODE SERVER" "PRO"   \
    "COGNEE" "PRO"   \
    "DATABASUS" "PRO"   \
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
    "FORMBRICKS" "PRO" \
    "GHOST" "PRO" \
    "GLPI" "PRO" \
    "GRAFANA/PROMETHEUS MONITOR" "PRO"   \
    "HERMES AGENT" "PRO" \
    "HEYFORM" "PRO" \
    "HUMHUB" "PRO" \
    "JITSI MEET" "PRO" \
    "KEYCLOAK" "PRO" \
    "KRAYIN CRM" "PRO" \
    "LANGFLOW" "PRO" \
    "LANGFUSE + MINIO + CLICKHOUSE*" "PRO" \
    "LITELLM" "PRO" \
    "MATTERMOST" "PRO" \
    "MATOMO" "PRO" \
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
    "NEO4J" "PRO" \
    "NEXTCLOUD" "PRO" \
    "NOCODB" "PRO" \
    "NTFY" "PRO" \
    "ODOO" "PRO" \
    "OLLAMA + OPENWEBUI*" "PRO" \
    "OPENCLAW + QDRANT + NEO4J + COGNEE + SEARXNG*" "PRO" \
    "OPENFANG" "PRO" \
    "OPEN PROJECT" "PRO" \
    "PAPERCLIP" "PRO" \
    "PHPMYADMIN" "PRO" \
    "PLANKA" "PRO" \
    "QDRANT" "PRO" \
    "RABBITMQ" "PRO" \
    "REDIS COMMANDER" "PRO" \
    "REDISINSIGHT" "PRO" \
    "SEARXNG" "PRO" \
    "SHLINK" "PRO" \
    "STIRLING PDF" "PRO" \
    "TWENTY CRM" "PRO" \
    "TYPEBOT" "PRO" \
    "TYPEBOT + MINIO*" "PRO" \
    "UPTIMEKUMA" "PRO" \
    "VAULTWARDEN" "PRO" \
    "WOOFED CRM" "PRO" \
    "WORDPRESS" "PRO" \
    "WIKI.JS" "PRO" \
    "WUZAP" "PRO" \
    "WEKAN" "PRO" \
    "REINICIAR APPS/SERVIÇOS" "" \
    "DELETAR APPS/STACKS" "" \
    "GERADOR DE REGISTROS DNS" "" \
    "ESSENCIAIS EDITÁVEIS NO PORTAINER" "" \
    "SAIR" ""  3>&2 2>&1 1>&3
)

[ -z "$CHOICE" ] && do_exit

case "$CHOICE" in
    "REINICIAR APPS/SERVIÇOS")  run_app restartservice ;;
    "DELETAR APPS/STACKS")      run_app uninstall ;;
    "GERADOR DE REGISTROS DNS") run_app geracloudflare ;;
    "ESSENCIAIS EDITÁVEIS NO PORTAINER") run_app essenciais ;;
    "SAIR") do_exit ;;
    *)
        if check_already_installed "$CHOICE"; then
            whiptail --msgbox "Aviso: ${CHOICE} já está instalado. Não é permitido instalar mais de uma instância.\n\nDigite ENTER para voltar ao Menu Principal." 12 70
            continue
        fi
        if [[ ("$CHOICE" != "OPENCLAW") && ("$CHOICE" != "EVOLUTION 2.0 API PADRÃO") && ("$CHOICE" != "N8N V1 - SEM FILA (MAIN)") && ("$CHOICE" != "N8N V1 - FILA (QUEUE)") && ("$CHOICE" != "N8N V2 - FILA (QUEUE)") && ("$CHOICE" != "PGADMIN4") && ("$CHOICE" != "MINIO") && ("$CHOICE" != "REDIS") && ("$CHOICE" != "EVOLUTION CRM") && ("$CHOICE" != "EVOLUTION GO") && ("$CHOICE" != "EVO NEXUS") ]]; then
            whiptail --msgbox "A ferramenta ${CHOICE} não está disponível no plano free2.\n\nEntre em contato conosco:\n- WhatsApp: $CONTATO_WP e adquira o plano PRO.\n\nPressione ENTER para voltar ao Menu Principal." 12 70
            continue
        fi
        case "$CHOICE" in
            "AFFINE")                                                run_app affine ;;
            "APPSMITH")                                              run_app appsmith ;;
            "AUTOGEN STUDIO")                                        run_app autogen ;;
            "BASEROW")                                               run_app baserow ;;
            "BOTPRESS")                                              run_app botpress ;;
            "CAL.COM")                                               run_app calcom ;;
            "CHATWOOTN + EVOLUTIONN 2.0 + RABBITMQ*")               run_app chatwootn_evo2_rabbitmq_redisevo ;;
            "CHATWOOTN + EVOLUTIONN 2.0 + RABBITMQ + MINIO*")       run_app chatwootn_evo2_rabbitmq_minio ;;
            "CHATWOOTORIG + EVOLUTIONN 2.0 + RABBITMQ + MINIO*")    run_app chatwooto_evo2_rabbitmq_minio ;;
            "CHATWOOTORIG (DESBLOQUEADO) + EVOLUTIONN 2.0 + RABBITMQ + MINIO*") run_app chatwootorig_desbloq__evo2_rabbitmq_minio ;;
            "CHATWOOT AI CUSTOMER SERVICE*") run_app chatwoot_ai_customer_service ;;
            "CLICKHOUSE")                                            run_app clickhouse ;;
            "CODE SERVER")                                           run_app codeserver ;;
            "COGNEE")                                                run_app cognee ;;
            "DATABASUS")                                             run_app databasus ;;
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
            "EVOLUTION CRM")                                         run_app evocrm ;;
            "EVOLUTION GO")                                          run_app evolutiongo ;;
            "EVO NEXUS")                                             run_app evonexus ;;
            "EXCALIDRAW")                                            run_app excalidraw ;;
            "FIRECRAWL")                                             run_app firecrawl ;;
            "FLOWISE")                                               run_app flowise ;;
            "FOCALBOARD")                                            run_app focalboard ;;
            "FORMBRICKS")                                            run_app formbricks ;;
            "GHOST")                                                 run_app ghost ;;
            "GLPI")                                                  run_app glpi ;;
            "GRAFANA/PROMETHEUS MONITOR")                            run_app grafana ;;
            "HERMES AGENT")                                          run_app hermes ;;
            "HEYFORM")                                               run_app heyform ;;
            "HUMHUB")                                                run_app humhub ;;
            "JITSI MEET")                                            run_app jitsi ;;
            "KEYCLOAK")                                              run_app keycloak ;;
            "KRAYIN CRM")                                            run_app krayincrm ;;
            "LANGFLOW")                                              run_app langflow ;;
            "LANGFUSE + MINIO + CLICKHOUSE*")                       run_app langfuse ;;
            "LITELLM")                                               run_app litellm ;;
            "MATTERMOST")                                            run_app mattermost ;;
            "MATOMO")                                                run_app matomo ;;
            "MAUTIC 4 PADRÃO")                                       run_app mauticpadrao ;;
            "MAUTIC 6 PADRÃO")                                       run_app mautic6padrao ;;
            "MAUTIC 7 PADRÃO")                                       run_app mautic7padrao ;;
            "MAUTIC 4 WHATSAPP MKT")                                 run_app mautic4whatsmkt ;;
            "MAUTIC 6 WHATSAPP MKT")                                 run_app mautic6whatsmkt ;;
            "MAUTIC 7 WHATSAPP MKT")                                 run_app mautic7whatsmkt ;;
            "MEMGRAPH")                                              run_app memgraph ;;
            "METABASE")                                              run_app metabase ;;
            "MINIO")                                                 run_app minio ;;
            "MONGODB")                                               run_app mongodb ;;
            "MYSQL")                                                 run_app mysql ;;
            "N8N V1 - SEM FILA (MAIN)")                              run_app n8nmain ;;
            "N8N V1 - FILA (QUEUE)")                                 run_app n8n ;;
            "N8N V2 - FILA (QUEUE)")                                 run_app n8n2 ;;
            "N8N TEMPLATES FREE - + DE 2000 WORKFLOWS")              run_app n8n-workflows ;;
            "NEO4J")                                                 run_app neo4j ;;
            "NEXTCLOUD")                                             run_app nextcloud ;;
            "NOCODB")                                                run_app nocodb ;;
            "NTFY")                                                  run_app ntfy ;;
            "ODOO")                                                  run_app odoo ;;
            "OLLAMA + OPENWEBUI*")                                   run_app ollama ;;
            "OPENCLAW")                                              run_app openclaw ;;
            "OPENCLAW + QDRANT + NEO4J + COGNEE + SEARXNG*")        run_app openclawpro ;;
            "OPENFANG")                                              run_app openfang ;;
            "OPEN PROJECT")                                          run_app openproject ;;
            "PAPERCLIP")                                             run_app paperclip ;;
            "PGADMIN4")                                              run_app pgadmin ;;
            "PLANKA")                                               run_app planka ;;
            "PHPMYADMIN")                                            run_app pma ;;
            "QDRANT")                                                run_app qdrant ;;
            "RABBITMQ")                                              run_app rabbitmq ;;
            "REDIS")                                                 run_app redis ;;
            "REDIS COMMANDER")                                       run_app redicommander ;;
            "REDISINSIGHT")                                          run_app redisinsight ;;
            "SEARXNG")                                               run_app searxng ;;
            "SHLINK")                                                run_app shlink ;;
            "STIRLING PDF")                                          run_app stirlingpdf ;;
            "TWENTY CRM")                                            run_app twentycrm ;;
            "TYPEBOT")                                               run_app typebot ;;
            "TYPEBOT + MINIO*")                                      run_app typebot_minio ;;
            "UPTIMEKUMA")                                            run_app uptimekuma ;;
            "VAULTWARDEN")                                           run_app vaultwarden ;;
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

#!/usr/bin/bash
#########################################################
#
# CARREGANDO LOADING E CORES
#
clear
amarelo="\e[33m"   # Amarelo
branco="\e[97m"    # Branco
reset="\e[0m"      # Reseta

phases=(
    '1/4 - Checando Networks...'
    '2/4 - Checando se possui Docker Swarm...'
    '3/4 - Checando se possui Portainer...'
    '4/4 - Checando se possui Traefik...'
)

export NEWT_COLORS='
#root=,white
#window=,black
#border=white,black
#textbox=white,black
#button=black,white

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
  tput reset 2>/dev/null         # Reinicia o terminal de forma segura
  exec 0</dev/tty 1>/dev/tty 2>&1 # Força redirecionamentos explícitos
  sleep 0.01                     # Pausa microscópica para sincronia
  clear                          # Limpeza final antes do whiptail
} || true

# VERIFICAR TIPO DE INSTALAÇÃO
INSTALL_TYPE_FILE="/root/.cloudflared_config/installation_type"
if [ -f "$INSTALL_TYPE_FILE" ]; then
    INSTALL_TYPE=$(cat "$INSTALL_TYPE_FILE")
else
    INSTALL_TYPE="TRADICIONAL"
fi

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

# Recalcula os dias restantes baseado na data atual
DATA_FORMATADA=$(echo "$DATA_INSTALACAO" | awk -F/ '{print $2 "/" $1 "/" $3}')
DATA_INSTALACAO_TIMESTAMP=$(date -d "$DATA_FORMATADA" +%s)
DATA_ATUAL_TIMESTAMP=$(date +%s)

DIFERENCA_SEGUNDOS=$(( DATA_INSTALACAO_TIMESTAMP + 7*86400 - DATA_ATUAL_TIMESTAMP ))
#DIAS_RESTANTES=$(( DIFERENCA_SEGUNDOS / 86400 ))
DIAS_RESTANTES=$(( (DIFERENCA_SEGUNDOS / 86400) + 1 ))

# Garante que não mostre negativo
if [ "$DIAS_RESTANTES" -lt 0 ]; then
    DIAS_RESTANTES=0
fi

# Atualiza o arquivo trial_info com os novos dias calculados
cd
cd SetupLowCodeMno
cd .meu_app_trial
rm trial_info
#nano trial_info

echo "DATA_INSTALACAO=$DATA_INSTALACAO" > "$TRIAL_FILE"
echo "DAYS_TRIAL=$DIAS_RESTANTES" >> "$TRIAL_FILE"
echo "PLANO=\"$PLANO\"" >> "$TRIAL_FILE"
echo "EMAIL=\"$EMAIL\"" >> "$TRIAL_FILE"
echo "SENHA=\"$SENHA\"" >> "$TRIAL_FILE"

#
# FIM DE CARREGANDO LOADING E CORES
# CHECA SE TEM DOCKER, APPS ESSENCIAS E NETWORK_PUBLIC
if command -v docker > /dev/null 2>&1; then
network_id_agent_network=$(docker network ls --filter name=agent_network --format "{{.ID}}")
network_id_externa=$(docker network ls --filter name=externa --format "{{.ID}}")
network_id_interna=$(docker network ls --filter name=interna --format "{{.ID}}")
traefik_container=$(docker ps -qf name=traefik)
portainer_container=$(docker ps -qf name=portainer)
postgres_container=$(docker ps -qf name=postgres)
redis_container=$(docker ps -qf name=redis)
pgbouncer_container=$(docker ps -qf name=pgbouncer)
#mongodb_container=$(docker ps -qf name=mongodb)

# CHECA SE EXISTEM APPS LIMITADOS À UMA INSTALAÇÃO APENAS
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

# FIM DE CHECA SE TEM DOCKER
# MENSAGEM DO MENU

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

# Defina o título com base no tipo de plano
if [ "$PLANO" == "trial pro" ]; then
    TITULO="SETUP MNO v4.20.2 - Plano: $PLANO 7 Dias - Restam: $DIAS_RESTANTES dias"
elif [ "$PLANO" == "pro" ]; then
    TITULO="SETUP MNO v4.20.2 - Plano: $PLANO - Instalação: $INSTALL_TYPE"
else
    TITULO="SETUP MNO v4.20.2 - Plano: $PLANO - Instalação: $INSTALL_TYPE"
fi

# 65 APPS

while true; do
if [[ ! "$PLANO" = *free* ]]; then

CHOICE=$(
whiptail --title "$TITULO" --menu "Selecione um App: Use as setas do seu teclado e pressione ENTER" 20 70 10 \
    "AFFINE" "" \
    "APPSMITH" "" \
    "AUTOGEN STUDIO" "" \
    "BASEROW" "" \
    "CHATWOOTN + EVOLUTIONN 2.0 + RABBITMQ*" ""   \
    "CHATWOOTN + EVOLUTIONN 2.0 + RABBITMQ + MINIO*" ""   \
    "CHATWOOTORIG + EVOLUTIONN 2.0 + RABBITMQ + MINIO*" ""   \
    "CHATWOOTORIG (DESBLOQUEADO) + EVOLUTIONN 2.0 + RABBITMQ + MINIO*" ""   \
    "CLICKHOUSE" ""   \
    "COGNEE" ""   \
    "DATABASUS" ""   \
    "DIRECTUS" "" \
    "DISCOURSE" "" \
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
    "FLOWISE" "" \
    "GHOST" "" \
    "GRAFANA/PROMETHEUS MONITOR" ""   \
    "HERMES AGENT" "" \
    "KRAYIN CRM" "" \
    "LANGFUSE + MINIO + CLICKHOUSE*" "" \
    "LITELLM" "" \
    "MATOMO" "" \
    "MAUTIC 6 PADRÃO" "" \
    "MAUTIC 6 WHATSAPP MKT" "" \
    "MAUTIC 7 PADRÃO" "" \
    "MAUTIC 7 WHATSAPP MKT" "" \
    "MEMGRAPH" "" \
    "MINIO" "" \
    "MONGODB" "" \
    "MOODLE" "" \
    "MYSQL" "" \
    "N8N V1 - SEM FILA (MAIN)" "" \
    "N8N V1 - FILA (QUEUE)" "" \
    "N8N V2 - FILA (QUEUE)" "" \
    "N8N TEMPLATES FREE - + DE 2000 WORKFLOWS" "" \
    "NEMOCLAW" "EM BREVE" \
    "NEO4J" "" \
    "NEXTCLOUD" "" \
    "NOCODB" "" \
    "NTFY" "" \
    "OLLAMA + OPENWEBUI*" "" \
    "OPENCLAW" "" \
    "OPENCLAW + QDRANT + NEO4J + COGNEE + SEARXNG*" "" \
    "OPENFANG" "" \
    "OPEN PROJECT" "" \
    "PGADMIN4" "" \
    "PHPMYADMIN" "" \
    "QDRANT" "" \
    "RABBITMQ" "" \
    "REDIS" "" \
    "REDIS COMMANDER" "" \
    "REDISINSIGHT" "" \
    "SEARXNG" "" \
    "SHLINK" "" \
    "STIRLING PDF" "" \
    "TYPEBOT" "" \
    "TYPEBOT + MINIO*" "" \
    "UPTIMEKUMA" "" \
    "VAULTWARDEN" "" \
    "WORDPRESS" "" \
    "WUZAP" "" \
    "REINICIAR APPS/SERVIÇOS" "" \
    "DELETAR APPS/STACKS" "" \
    "GERADOR DE REGISTROS DNS" "" \
    "ESSENCIAIS EDITÁVEIS NO PORTAINER" "" \
        "SAIR" ""  3>&2 2>&1 1>&3
)

case $CHOICE in

  "AFFINE")
                clear
        cd && cd SetupLowCodeMno && ./affine
        ;;

    "APPSMITH")
          clear
        cd && cd SetupLowCodeMno && ./appsmith
    ;;

     "AUTOGEN STUDIO")
          clear
        cd && cd SetupLowCodeMno && ./autogen
    ;;

    "BASEROW")
                clear
        cd && cd SetupLowCodeMno && ./baserow
    ;;

    "CHATWOOTN + EVOLUTIONN 2.0 + RABBITMQ*")
                clear
        cd && cd SetupLowCodeMno && ./chatwootn_evo2_rabbitmq_redisevo
        ;;

    "CHATWOOTN + EVOLUTIONN 2.0 + RABBITMQ + MINIO*")
                clear
        cd && cd SetupLowCodeMno && ./chatwootn_evo2_rabbitmq_minio
        ;;

    "CHATWOOTORIG + EVOLUTIONN 2.0 + RABBITMQ + MINIO*")
                clear
        cd && cd SetupLowCodeMno && ./chatwooto_evo2_rabbitmq_minio
        ;;

    "CHATWOOTORIG (DESBLOQUEADO) + EVOLUTIONN 2.0 + RABBITMQ + MINIO*")
                clear
        cd && cd SetupLowCodeMno && ./chatwootorig_desbloq__evo2_rabbitmq_minio
        ;;

    "CLICKHOUSE")
             clear
        cd && cd SetupLowCodeMno && ./clickhouse
    ;;

    "COGNEE")
             clear
        cd && cd SetupLowCodeMno && ./cognee
    ;;

    "DATABASUS")
             clear
        cd && cd SetupLowCodeMno && ./databasus
    ;;

    "DIRECTUS")
                clear
        cd && cd SetupLowCodeMno && ./directus
        ;;

   "DISCOURSE")
                clear
        cd && cd SetupLowCodeMno && ./discourse
        ;;

    "DOCUMENSO")
                clear
        cd && cd SetupLowCodeMno && ./documenso
        ;;

    "DOCUSEAL")
                clear
        cd && cd SetupLowCodeMno && ./docuseal
        ;;

    "DOZZLE")
                clear
        cd && cd SetupLowCodeMno && ./dozzle
        ;;

    "EVOAI")
              clear
        cd && cd SetupLowCodeMno && ./evoai
        ;;

    "EVOAI + EVOLUTION 2.0 + MINIO*")
              clear
        cd && cd SetupLowCodeMno && ./evoai_evo2_minio
        ;;

    "EVOLUTION 1.0 API PADRÃO")
            clear
        cd && cd SetupLowCodeMno && ./evolutionapi
        ;;

    "EVOLUTION 2.0 API PADRÃO")
              clear
        cd && cd SetupLowCodeMno && ./evolution2api
        ;;

    "EVOLUTION CRM")
              clear
        cd && cd SetupLowCodeMno && ./evocrm
        ;;

    "EVOLUTION GO")
              clear
        cd && cd SetupLowCodeMno && ./evolutiongo
        ;;

    "EVO NEXUS")
              clear
        cd && cd SetupLowCodeMno && ./evonexus
        ;;

    "FLOWISE")
                 if [[ ("$flowise_container" != "") ]];
    then
                clear
    else
        clear
        cd && cd SetupLowCodeMno && ./flowise
    fi
    ;;

    "GHOST")
                clear
        cd && cd SetupLowCodeMno && ./ghost
        ;;

    "GRAFANA/PROMETHEUS MONITOR")
                clear
        cd && cd SetupLowCodeMno && ./grafana
        ;;

    "HERMES AGENT")
                clear
        cd && cd SetupLowCodeMno && ./hermes
        ;;

    "KRAYIN CRM")
                clear
        cd && cd SetupLowCodeMno && ./krayincrm
        ;;

    "LANGFUSE + MINIO + CLICKHOUSE*")
             clear
        cd && cd SetupLowCodeMno && ./langfuse
    ;;

    "LITELLM")
             clear
        cd && cd SetupLowCodeMno && ./litellm
    ;;

    "MATOMO")
                clear
        cd && cd SetupLowCodeMno && ./matomo
        ;;

    "MAUTIC 6 PADRÃO")
                clear
        cd && cd SetupLowCodeMno && ./mautic6padrao
    ;;

    "MAUTIC 6 WHATSAPP MKT")
                clear
        cd && cd SetupLowCodeMno && ./mautic6whatsmkt
    ;;


    "MAUTIC 7 PADRÃO")
                clear
        cd && cd SetupLowCodeMno && ./mautic7padrao
    ;;

    "MAUTIC 7 WHATSAPP MKT")
                clear
        cd && cd SetupLowCodeMno && ./mautic7whatsmkt
    ;;

    "MEMGRAPH")
                clear
        cd && cd SetupLowCodeMno && ./memgraph
    ;;

     "MINIO")
        if [[ ("$minio_container" != "") ]];
    then
                clear
    else
        clear
        cd && cd SetupLowCodeMno && ./minio
    fi
    ;;

    "MONGODB")
                clear
        cd && cd SetupLowCodeMno && ./mongodb
    ;;

    "MOODLE")
                clear
        cd && cd SetupLowCodeMno && ./moodle
    ;;

    "MYSQL")
    if [[ ("$mysql_container" != "") ]];
    then
                clear
    else
        clear
        cd && cd SetupLowCodeMno && ./mysql
    fi
    ;;

    "N8N V1 - SEM FILA (MAIN)")
            clear
        cd && cd SetupLowCodeMno && ./n8nmain
    ;;

    "N8N V1 - FILA (QUEUE)")
            clear
        cd && cd SetupLowCodeMno && ./n8n
    ;;

    "N8N V2 - FILA (QUEUE)")
            clear
        cd && cd SetupLowCodeMno && ./n8n2
    ;;

    "N8N TEMPLATES FREE - + DE 2000 WORKFLOWS")
            clear
        cd && cd SetupLowCodeMno && ./n8n-workflows
    ;;

 

    "NEO4J")
            clear
        cd && cd SetupLowCodeMno && ./neo4j
    ;;

    "NEXTCLOUD")
            clear
        cd && cd SetupLowCodeMno && ./nextcloud
    ;;

    "NOCODB")
                clear
        cd && cd SetupLowCodeMno && ./nocodb
    ;;

    "NTFY")
                clear
        cd && cd SetupLowCodeMno && ./ntfy
    ;;

    "OLLAMA + OPENWEBUI*")
                clear
        cd && cd SetupLowCodeMno && ./ollama
    ;;

    "OPENCLAW")
                clear
        cd && cd SetupLowCodeMno && ./openclaw
    ;;

    "OPENCLAW + QDRANT + NEO4J + COGNEE + SEARXNG*")
                clear
        cd && cd SetupLowCodeMno && ./openclawpro
    ;;

    "OPENFANG")
                clear
        cd && cd SetupLowCodeMno && ./openfang
    ;;

    "OPEN PROJECT")
                clear
        cd && cd SetupLowCodeMno && ./openproject
    ;;

    "PGADMIN4")
                if [[ ("$pgadmin4_container" != "") ]];
    then
                clear
    else
        clear
        cd && cd SetupLowCodeMno && ./pgadmin
    fi
    ;;

    "PHPMYADMIN")
    if [[ ("$pma_container" != "") ]];
    then
                clear
    else
        clear
        cd && cd SetupLowCodeMno && ./pma
    fi
    ;;

    "QDRANT")
                clear
        cd && cd SetupLowCodeMno && ./qdrant
    ;;

    "RABBITMQ")
                clear
        cd && cd SetupLowCodeMno && ./rabbitmq
    ;;

    "REDIS")
                clear
        cd && cd SetupLowCodeMno && ./redis
    ;;

    "REDIS COMMANDER")
    if [[ ("$redicommander_container" != "") ]];
    then
                clear
    else
        clear
        cd && cd SetupLowCodeMno && ./redicommander
    fi
    ;;

    "REDISINSIGHT")
                clear
        cd && cd SetupLowCodeMno && ./redisinsight
    ;;

    "SEARXNG")
                clear
        cd && cd SetupLowCodeMno && ./searxng
    ;;

    "SHLINK")
                clear
        cd && cd SetupLowCodeMno && ./shlink
    ;;

    "STIRLING PDF")
                clear
        cd && cd SetupLowCodeMno && ./stirlingpdf
    ;;

    "TYPEBOT")
            clear
        cd && cd SetupLowCodeMno && ./typebot
    ;;

    "TYPEBOT + MINIO*")
            clear
        cd && cd SetupLowCodeMno && ./typebot_minio
    ;;

     "UPTIMEKUMA")
                clear
        cd && cd SetupLowCodeMno && ./uptimekuma
    ;;

    "VAULTWARDEN")
                clear
        cd && cd SetupLowCodeMno && ./vaultwarden
    ;;

    "WORDPRESS")
                clear
        cd && cd SetupLowCodeMno && ./wordpress
    ;;

    "WUZAP")
                clear
        cd && cd SetupLowCodeMno && ./wuzap
    ;;

     "REINICIAR APPS/SERVIÇOS")
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

    "ESSENCIAIS EDITÁVEIS NO PORTAINER")
          clear
        cd && cd SetupLowCodeMno && ./essenciais
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
    type_effect "SETUP MNO FINALIZADO COM ÊXITO!"
    echo -n " ➤ "
    type_effect "P/ INICIAR: SEMPRE DIGITE 'setup-mno' NO TERMINAL"
    echo "┣━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┫"
    echo -e "   \033[1;35m🚀 COMANDO DE REATIVAÇÃO:\033[1;37m setup-mno\033[1;32m         "
    echo -e "   \033[1;35m📡 CANAIS DE SUPORTE:\033[1;32m                                 "
    echo -e "      \033[1;36m● WhatsApp: +55 (11) 96816-2690\033[1;32m                    "
    echo -e "      \033[1;36m● Email: francisbreit@gmail.com\033[1;32m                    "
    echo -e "      \033[1;36m● GitHub: github.com/francisbreit\033[1;32m                  "
    echo -e "   \033[1;33m⚠️  SISTEMA PRONTO PARA OPERAÇÃO \033[1;32m                     "
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
fi
if [ "$PLANO" == "free" ]; then
CHOICE=$(
whiptail --title "$TITULO" --menu "Selecione um App: Use as setas do seu teclado e pressione ENTER" 20 70 10 \
    "AFFINE" "PRO" \
    "APPSMITH" "PRO" \
    "AUTOGEN STUDIO" "PRO" \
    "BASEROW" "PRO" \
    "CHATWOOTN + EVOLUTIONN 2.0 + RABBITMQ*" ""   \
    "CHATWOOTN + EVOLUTIONN 2.0 + RABBITMQ + MINIO*" "PRO"   \
    "CHATWOOTORIG + EVOLUTIONN 2.0 + RABBITMQ + MINIO*" "PRO"   \
    "CHATWOOTORIG (DESBLOQUEADO) + EVOLUTIONN 2.0 + RABBITMQ + MINIO*" "PRO"   \
    "CLICKHOUSE" ""   \
    "COGNEE" "PRO"   \
    "DATABASUS" ""   \
    "DIRECTUS" "" \
    "DISCOURSE" "PRO" \
    "DOCUMENSO" "PRO" \
    "DOCUSEAL" "PRO" \
    "DOZZLE" "PRO" \
    "EVOAI" ""  \
    "EVOAI + EVOLUTION 2.0 + MINIO*" "PRO"  \
    "EVOLUTION 1.0 API PADRÃO" ""  \
    "EVOLUTION 2.0 API PADRÃO" ""  \
    "EVOLUTION CRM" ""  \
    "EVOLUTION GO" ""  \
    "EVO NEXUS" ""  \
    "FLOWISE" "" \
    "GHOST" "PRO" \
    "GRAFANA/PROMETHEUS MONITOR" ""   \
    "HERMES AGENT" "PRO" \
    "KRAYIN CRM" "PRO" \
    "LANGFUSE + MINIO + CLICKHOUSE*" "PRO" \
    "LITELLM" "PRO" \
    "MATOMO" "PRO" \
    "MAUTIC 6 PADRÃO" "" \
    "MAUTIC 6 WHATSAPP MKT" "PRO" \
    "MAUTIC 7 PADRÃO" "" \
    "MAUTIC 7 WHATSAPP MKT" "PRO" \
    "MEMGRAPH" "PRO" \
    "MINIO" "" \
    "MONGODB" "" \
    "MOODLE" "PRO" \
    "MYSQL" "" \
    "N8N V1 - SEM FILA (MAIN)" "" \
    "N8N V1 - FILA (QUEUE)" "" \
    "N8N V2 - FILA (QUEUE)" "" \
    "N8N TEMPLATES FREE - + DE 2000 WORKFLOWS" "" \
    "NEMOCLAW" "EM BREVE" \
    "NEO4J" "PRO" \
    "NEXTCLOUD" "PRO" \
    "NOCODB" "" \
    "NTFY" "" \
    "OLLAMA + OPENWEBUI*" "" \
    "OPENCLAW" "PRO" \
    "OPENCLAW + QDRANT + NEO4J + COGNEE + SEARXNG*" "PRO" \
    "OPENFANG" "PRO" \
    "OPEN PROJECT" "PRO" \
    "PGADMIN4" "" \
    "PHPMYADMIN" "" \
    "QDRANT" "" \
    "RABBITMQ" "" \
    "REDIS" "" \
    "REDIS COMMANDER" "" \
    "REDISINSIGHT" "" \
    "SEARXNG" "PRO" \
    "SHLINK" "" \
    "STIRLING PDF" "" \
    "TYPEBOT" "" \
    "TYPEBOT + MINIO*" "PRO" \
    "UPTIMEKUMA" "" \
    "VAULTWARDEN" "" \
    "WORDPRESS" "" \
    "WUZAP" "" \
    "REINICIAR APPS/SERVIÇOS" "" \
    "DELETAR APPS/STACKS" "" \
    "GERADOR DE REGISTROS DNS" "" \
    "ESSENCIAIS EDITÁVEIS NO PORTAINER" "" \
        "SAIR" ""  3>&2 2>&1 1>&3
)

case $CHOICE in

  "AFFINE")
                clear
        cd && cd SetupLowCodeMno && ./affine
        ;;

    "APPSMITH")
          clear
          cd && cd SetupLowCodeMno && ./appsmith
    ;;

     "AUTOGEN STUDIO")
          clear
        cd && cd SetupLowCodeMno && ./autogen
    ;;

    "BASEROW")
                clear
        cd && cd SetupLowCodeMno && ./baserow
    ;;

    "CHATWOOTN + EVOLUTIONN 2.0 + RABBITMQ*")
                clear
        cd && cd SetupLowCodeMno && ./chatwootn_evo2_rabbitmq_redisevo
        ;;

    "CHATWOOTN + EVOLUTIONN 2.0 + RABBITMQ + MINIO*")
                clear
        cd && cd SetupLowCodeMno && ./chatwootn_evo2_rabbitmq_minio
        ;;

    "CHATWOOTORIG + EVOLUTIONN 2.0 + RABBITMQ + MINIO*")
                clear
        cd && cd SetupLowCodeMno && ./chatwooto_evo2_rabbitmq_minio
        ;;

    "CHATWOOTORIG (DESBLOQUEADO) + EVOLUTIONN 2.0 + RABBITMQ + MINIO*")
                clear
        cd && cd SetupLowCodeMno && ./chatwootorig_desbloq__evo2_rabbitmq_minio
        ;;

    "CLICKHOUSE")
             clear
        cd && cd SetupLowCodeMno && ./clickhouse
    ;;

    "COGNEE")
             clear
        cd && cd SetupLowCodeMno && ./cognee
    ;;

   "DATABASUS")
             clear
        cd && cd SetupLowCodeMno && ./databasus
    ;;

    "DIRECTUS")
                clear
        cd && cd SetupLowCodeMno && ./directus
        ;;

    "DISCOURSE")
                clear
        cd && cd SetupLowCodeMno && ./discourse
        ;;

    "DOCUMENSO")
                clear
        cd && cd SetupLowCodeMno && ./documenso
        ;;

    "DOCUSEAL")
                clear
        cd && cd SetupLowCodeMno && ./docuseal
        ;;

    "DOZZLE")
                clear
        cd && cd SetupLowCodeMno && ./dozzle
        ;;

    "EVOAI")
              clear
        cd && cd SetupLowCodeMno && ./evoai
        ;;

    "EVOAI + EVOLUTION 2.0 + MINIO*")
              clear
        cd && cd SetupLowCodeMno && ./evoai_evo2_minio
        ;;

    "EVOLUTION 1.0 API PADRÃO")
            clear
        cd && cd SetupLowCodeMno && ./evolutionapi
        ;;

    "EVOLUTION 2.0 API PADRÃO")
              clear
        cd && cd SetupLowCodeMno && ./evolution2api
        ;;

    "EVOLUTION CRM")
              clear
        cd && cd SetupLowCodeMno && ./evocrm
        ;;

    "EVOLUTION GO")
              clear
        cd && cd SetupLowCodeMno && ./evolutiongo
        ;;

    "EVO NEXUS")
              clear
        cd && cd SetupLowCodeMno && ./evonexus
        ;;

    "FLOWISE")
                 if [[ ("$flowise_container" != "") ]];
    then
                clear
    else
        clear
        cd && cd SetupLowCodeMno && ./flowise
    fi
    ;;

    "GHOST")
                clear
        cd && cd SetupLowCodeMno && ./ghost
        ;;


    "GRAFANA/PROMETHEUS MONITOR")
                clear
        cd && cd SetupLowCodeMno && ./grafana
        ;;

    "HERMES AGENT")
                clear
        cd && cd SetupLowCodeMno && ./hermes
        ;;

    "KRAYIN CRM")
                clear
        cd && cd SetupLowCodeMno && ./krayincrm
        ;;

    "LANGFUSE + MINIO + CLICKHOUSE*")
             clear
        cd && cd SetupLowCodeMno && ./langfuse
    ;;

    "LITELLM")
             clear
        cd && cd SetupLowCodeMno && ./litellm
    ;;

    "MATOMO")
                clear
        cd && cd SetupLowCodeMno && ./matomo
        ;;

    "MAUTIC 6 PADRÃO")
                clear
        cd && cd SetupLowCodeMno && ./mautic6padrao
    ;;

    "MAUTIC 6 WHATSAPP MKT")
                clear
        cd && cd SetupLowCodeMno && ./mautic6whatsmkt
    ;;

    "MAUTIC 7 PADRÃO")
                clear
        cd && cd SetupLowCodeMno && ./mautic7padrao
    ;;

    "MAUTIC 7 WHATSAPP MKT")
                clear
        cd && cd SetupLowCodeMno && ./mautic7whatsmkt
    ;;  

    "MEMGRAPH")
                clear
        cd && cd SetupLowCodeMno && ./memgraph
    ;;

     "MINIO")
        if [[ ("$minio_container" != "") ]];
    then
                clear
    else
        clear
        cd && cd SetupLowCodeMno && ./minio
    fi
    ;;

    "MONGODB")
                clear
        cd && cd SetupLowCodeMno && ./mongodb
    ;;

    "MOODLE")
                clear
        cd && cd SetupLowCodeMno && ./moodle
    ;;

    "MYSQL")
    if [[ ("$mysql_container" != "") ]];
    then
                clear
    else
        clear
        cd && cd SetupLowCodeMno && ./mysql
    fi
    ;;

    "N8N V1 - SEM FILA (MAIN)")
            clear
        cd && cd SetupLowCodeMno && ./n8nmain
    ;;

    "N8N V1 - FILA (QUEUE)")
            clear
        cd && cd SetupLowCodeMno && ./n8n
    ;;

    "N8N V2 - FILA (QUEUE)")
            clear
        cd && cd SetupLowCodeMno && ./n8n2
    ;;

    "N8N TEMPLATES FREE - + DE 2000 WORKFLOWS")
            clear
        cd && cd SetupLowCodeMno && ./n8n-workflows
    ;;

 


    "NEO4J")
            clear
        cd && cd SetupLowCodeMno && ./neo4j
    ;;

    "NEXTCLOUD")
            clear
        cd && cd SetupLowCodeMno && ./nextcloud
    ;;

    "NOCODB")
                clear
        cd && cd SetupLowCodeMno && ./nocodb
    ;;

    "NTFY")
                clear
        cd && cd SetupLowCodeMno && ./ntfy
    ;;

    "OLLAMA + OPENWEBUI*")
                clear
        cd && cd SetupLowCodeMno && ./ollama
    ;;

    "OPENCLAW")
                clear
        cd && cd SetupLowCodeMno && ./openclaw
    ;;

    "OPENCLAW + QDRANT + NEO4J + COGNEE + SEARXNG*")
                clear
        cd && cd SetupLowCodeMno && ./openclawpro
    ;;


    "OPENFANG")
                clear
        cd && cd SetupLowCodeMno && ./openfang
    ;;

    "OPEN PROJECT")
                clear
        cd && cd SetupLowCodeMno && ./openproject
    ;;

    "PGADMIN4")
                if [[ ("$pgadmin4_container" != "") ]];
    then
                clear
    else
        clear
        cd && cd SetupLowCodeMno && ./pgadmin
    fi
    ;;

    "PHPMYADMIN")
    if [[ ("$pma_container" != "") ]];
    then
                clear
    else
        clear
        cd && cd SetupLowCodeMno && ./pma
    fi
    ;;

    "QDRANT")
                clear
        cd && cd SetupLowCodeMno && ./qdrant
    ;;

    "RABBITMQ")
                clear
        cd && cd SetupLowCodeMno && ./rabbitmq
    ;;

    "REDIS")
                clear
        cd && cd SetupLowCodeMno && ./redis
    ;;

    "REDIS COMMANDER")
    if [[ ("$redicommander_container" != "") ]];
    then
                clear
    else
        clear
        cd && cd SetupLowCodeMno && ./redicommander
    fi
    ;;

    "REDISINSIGHT")
                clear
        cd && cd SetupLowCodeMno && ./redisinsight
    ;;

    "SEARXNG")
                clear
        cd && cd SetupLowCodeMno && ./searxng
    ;;

    "SHLINK")
                clear
        cd && cd SetupLowCodeMno && ./shlink
    ;;

    "STIRLING PDF")
                clear
        cd && cd SetupLowCodeMno && ./stirlingpdf
    ;;

    "TYPEBOT")
            clear
        cd && cd SetupLowCodeMno && ./typebot
    ;;

    "TYPEBOT + MINIO*")
            clear
        cd && cd SetupLowCodeMno && ./typebot_minio
    ;;

     "UPTIMEKUMA")
                clear
        cd && cd SetupLowCodeMno && ./uptimekuma
    ;;

    "VAULTWARDEN")
                clear
        cd && cd SetupLowCodeMno && ./vaultwarden
    ;;

    "WORDPRESS")
                clear
        cd && cd SetupLowCodeMno && ./wordpress
    ;;

    "WUZAP")
                clear
        cd && cd SetupLowCodeMno && ./wuzap
    ;;

     "REINICIAR APPS/SERVIÇOS")
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

    "ESSENCIAIS EDITÁVEIS NO PORTAINER")
          clear
        cd && cd SetupLowCodeMno && ./essenciais
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
    type_effect "SETUP MNO FINALIZADO COM ÊXITO!"
    echo -n " ➤ "
    type_effect "P/ INICIAR: SEMPRE DIGITE 'setup-mno' NO TERMINAL"
    echo "┣━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┫"
    echo -e "   \033[1;35m🚀 COMANDO DE REATIVAÇÃO:\033[1;37m setup-mno\033[1;32m         "
    echo -e "   \033[1;35m📡 CANAIS DE SUPORTE:\033[1;32m                                 "
    echo -e "      \033[1;36m● WhatsApp: +55 (11) 96816-2690\033[1;32m                    "
    echo -e "      \033[1;36m● Email: francisbreit@gmail.com\033[1;32m                    "
    echo -e "      \033[1;36m● GitHub: github.com/francisbreit\033[1;32m                  "
    echo -e "   \033[1;33m⚠️  SISTEMA PRONTO PARA OPERAÇÃO \033[1;32m                     "
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
fi
if [ "$PLANO" == "free1" ]; then
CHOICE=$(
whiptail --title "$TITULO" --menu "Selecione um App: Use as setas do seu teclado e pressione ENTER" 20 70 10 \
    "DATABASUS" ""   \
    "EVOLUTION 2.0 API PADRÃO" ""  \
    "EVOLUTION CRM" ""  \
    "EVOLUTION GO" ""  \
    "EVO NEXUS" ""  \
    "N8N V1 - SEM FILA (MAIN)" "" \
    "N8N V1 - FILA (QUEUE)" "" \
    "N8N V2 - FILA (QUEUE)" "" \
    "PGADMIN4" "" \
    "MINIO" "" \
    "REDIS" "" \
    "AFFINE" "PRO" \
    "APPSMITH" "PRO" \
    "AUTOGEN STUDIO" "PRO" \
    "BASEROW" "PRO" \
    "CHATWOOTN + EVOLUTIONN 2.0 + RABBITMQ*" "PRO"   \
    "CHATWOOTN + EVOLUTIONN 2.0 + RABBITMQ + MINIO*" "PRO"   \
    "CHATWOOTORIG + EVOLUTIONN 2.0 + RABBITMQ + MINIO*" "PRO"   \
    "CHATWOOTORIG (DESBLOQUEADO) + EVOLUTIONN 2.0 + RABBITMQ + MINIO*" "PRO"   \
    "CLICKHOUSE" "PRO"   \
    "COGNEE" "PRO"   \
    "DIRECTUS" "PRO" \
    "DISCOURSE" "PRO" \
    "DOCUMENSO" "PRO" \
    "DOCUSEAL" "PRO" \
    "DOZZLE" "PRO" \
    "EVOAI" "PRO"  \
    "EVOAI + EVOLUTION 2.0 + MINIO*" "PRO"  \
    "EVOLUTION 1.0 API PADRÃO" "PRO"  \
    "FLOWISE" "PRO" \
    "GHOST" "PRO" \
    "GRAFANA/PROMETHEUS MONITOR" "PRO"   \
    "HERMES AGENT" "PRO" \
    "KRAYIN CRM" "PRO" \
    "LANGFUSE + MINIO + CLICKHOUSE*" "PRO" \
    "LITELLM" "PRO" \
    "MATOMO" "PRO" \
    "MAUTIC 6 PADRÃO" "PRO" \
    "MAUTIC 6 WHATSAPP MKT" "PRO" \
    "MAUTIC 7 PADRÃO" "PRO" \
    "MAUTIC 7 WHATSAPP MKT" "PRO" \
    "MEMGRAPH" "PRO" \
    "MONGODB" "" \
    "MOODLE" "PRO" \
    "MYSQL" "" \
    "N8N TEMPLATES FREE - + DE 2000 WORKFLOWS" "" \
    "NEMOCLAW" "EM BREVE" \
    "NEO4J" "PRO" \
    "NEXTCLOUD" "PRO" \
    "NOCODB" "" \
    "NTFY" "" \
    "OLLAMA + OPENWEBUI*" "" \
    "OPENCLAW" "PRO" \
    "OPENCLAW + QDRANT + NEO4J + COGNEE + SEARXNG*" "PRO" \
    "OPENFANG" "PRO" \
    "OPEN PROJECT" "PRO" \
    "PHPMYADMIN" "" \
    "QDRANT" "" \
    "RABBITMQ" "" \
    "REDIS COMMANDER" "" \
    "REDISINSIGHT" "" \
    "SEARXNG" "PRO" \
    "SHLINK" "" \
    "STIRLING PDF" "" \
    "TYPEBOT" "" \
    "TYPEBOT + MINIO*" "PRO" \
    "UPTIMEKUMA" "" \
    "VAULTWARDEN" "" \
    "WORDPRESS" "" \
    "WUZAP" "" \
    "REINICIAR APPS/SERVIÇOS" "" \
    "DELETAR APPS/STACKS" "" \
    "GERADOR DE REGISTROS DNS" "" \
    "ESSENCIAIS EDITÁVEIS NO PORTAINER" "" \
        "SAIR" ""  3>&2 2>&1 1>&3
)

case $CHOICE in

  "AFFINE")
                clear
        cd && cd SetupLowCodeMno && ./affine
        ;;

    "APPSMITH")
          clear
          cd && cd SetupLowCodeMno && ./appsmith
    ;;

     "AUTOGEN STUDIO")
          clear
        cd && cd SetupLowCodeMno && ./autogen
    ;;

    "BASEROW")
                clear
        cd && cd SetupLowCodeMno && ./baserow
    ;;

    "CHATWOOTN + EVOLUTIONN 2.0 + RABBITMQ*")
                clear
        cd && cd SetupLowCodeMno && ./chatwootn_evo2_rabbitmq_redisevo
        ;;

    "CHATWOOTN + EVOLUTIONN 2.0 + RABBITMQ + MINIO*")
                clear
        cd && cd SetupLowCodeMno && ./chatwootn_evo2_rabbitmq_minio
        ;;

    "CHATWOOTORIG + EVOLUTIONN 2.0 + RABBITMQ + MINIO*")
                clear
        cd && cd SetupLowCodeMno && ./chatwooto_evo2_rabbitmq_minio
        ;;

    "CHATWOOTORIG (DESBLOQUEADO) + EVOLUTIONN 2.0 + RABBITMQ + MINIO*")
                clear
        cd && cd SetupLowCodeMno && ./chatwootorig_desbloq__evo2_rabbitmq_minio
        ;;

    "CLICKHOUSE")
             clear
        cd && cd SetupLowCodeMno && ./clickhouse
    ;;

    "COGNEE")
             clear
        cd && cd SetupLowCodeMno && ./cognee
    ;;

    "DATABASUS")
             clear
        cd && cd SetupLowCodeMno && ./databasus
    ;;

    "DIRECTUS")
                clear
        cd && cd SetupLowCodeMno && ./directus
        ;;

   "DISCOURSE")
                clear
        cd && cd SetupLowCodeMno && ./discourse
        ;;

    "DOCUMENSO")
                clear
        cd && cd SetupLowCodeMno && ./documenso
        ;;

    "DOCUSEAL")
                clear
        cd && cd SetupLowCodeMno && ./docuseal
        ;;

    "DOZZLE")
                clear
        cd && cd SetupLowCodeMno && ./dozzle
        ;;

    "EVOAI")
              clear
        cd && cd SetupLowCodeMno && ./evoai
        ;;

    "EVOAI + EVOLUTION 2.0 + MINIO*")
              clear
        cd && cd SetupLowCodeMno && ./evoai_evo2_minio
        ;;

    "EVOLUTION 1.0 API PADRÃO")
            clear
        cd && cd SetupLowCodeMno && ./evolutionapi
        ;;

    "EVOLUTION 2.0 API PADRÃO")
              clear
        cd && cd SetupLowCodeMno && ./evolution2api
        ;;

    "EVOLUTION CRM")
              clear
        cd && cd SetupLowCodeMno && ./evocrm
        ;;

    "EVOLUTION GO")
              clear
        cd && cd SetupLowCodeMno && ./evolutiongo
        ;;

    "EVO NEXUS")
              clear
        cd && cd SetupLowCodeMno && ./evonexus
        ;;

    "FLOWISE")
                 if [[ ("$flowise_container" != "") ]];
    then
                clear
    else
        clear
        cd && cd SetupLowCodeMno && ./flowise
    fi
    ;;

    "GHOST")
                clear
        cd && cd SetupLowCodeMno && ./ghost
        ;;

    "GRAFANA/PROMETHEUS MONITOR")
                clear
        cd && cd SetupLowCodeMno && ./grafana
        ;;

    "HERMES AGENT")
                clear
        cd && cd SetupLowCodeMno && ./hermes
        ;;

    "KRAYIN CRM")
                clear
        cd && cd SetupLowCodeMno && ./krayincrm
        ;;

    "LANGFUSE + MINIO + CLICKHOUSE*")
             clear
        cd && cd SetupLowCodeMno && ./langfuse
    ;;

    "LITELLM")
             clear
        cd && cd SetupLowCodeMno && ./litellm
    ;;

    "MATOMO")
                clear
        cd && cd SetupLowCodeMno && ./matomo
        ;;

    "MAUTIC 6 PADRÃO")
                clear
        cd && cd SetupLowCodeMno && ./mautic6padrao
    ;;

    "MAUTIC 6 WHATSAPP MKT")
                clear
        cd && cd SetupLowCodeMno && ./mautic6whatsmkt
    ;;

    "MAUTIC 7 PADRÃO")
                clear
        cd && cd SetupLowCodeMno && ./mautic7padrao
    ;;

    "MAUTIC 7 WHATSAPP MKT")
                clear
        cd && cd SetupLowCodeMno && ./mautic7whatsmkt
    ;;

    "MEMGRAPH")
                clear
        cd && cd SetupLowCodeMno && ./memgraph
    ;;

     "MINIO")
        if [[ ("$minio_container" != "") ]];
    then
                clear
    else
        clear
        cd && cd SetupLowCodeMno && ./minio
    fi
    ;;

    "MONGODB")
                clear
        cd && cd SetupLowCodeMno && ./mongodb
    ;;

    "MOODLE")
                clear
        cd && cd SetupLowCodeMno && ./moodle
    ;;

    "MYSQL")
    if [[ ("$mysql_container" != "") ]];
    then
                clear
    else
        clear
        cd && cd SetupLowCodeMno && ./mysql
    fi
    ;;

    "N8N V1 - SEM FILA (MAIN)")
            clear
        cd && cd SetupLowCodeMno && ./n8nmain
    ;;

    "N8N V1 - FILA (QUEUE)")
            clear
        cd && cd SetupLowCodeMno && ./n8n
    ;;

    "N8N V2 - FILA (QUEUE)")
            clear
        cd && cd SetupLowCodeMno && ./n8n2
    ;;

    "N8N TEMPLATES FREE - + DE 2000 WORKFLOWS")
            clear
        cd && cd SetupLowCodeMno && ./n8n-workflows
    ;;

 


    "NEO4J")
            clear
        cd && cd SetupLowCodeMno && ./neo4j
    ;;

    "NEXTCLOUD")
            clear
        cd && cd SetupLowCodeMno && ./nextcloud
    ;;

    "NOCODB")
                clear
        cd && cd SetupLowCodeMno && ./nocodb
    ;;

    "NTFY")
                clear
        cd && cd SetupLowCodeMno && ./ntfy
    ;;

    "OLLAMA + OPENWEBUI*")
                clear
        cd && cd SetupLowCodeMno && ./ollama
    ;;

    "OPENCLAW")
                clear
        cd && cd SetupLowCodeMno && ./openclaw
    ;;

    "OPENCLAW + QDRANT + NEO4J + COGNEE + SEARXNG*")
                clear
        cd && cd SetupLowCodeMno && ./openclawpro
    ;;


    "OPENFANG")
                clear
        cd && cd SetupLowCodeMno && ./openfang
    ;;

    "OPEN PROJECT")
                clear
        cd && cd SetupLowCodeMno && ./openproject
    ;;

    "PGADMIN4")
                if [[ ("$pgadmin4_container" != "") ]];
    then
                clear
    else
        clear
        cd && cd SetupLowCodeMno && ./pgadmin
    fi
    ;;

    "PHPMYADMIN")
    if [[ ("$pma_container" != "") ]];
    then
                clear
    else
        clear
        cd && cd SetupLowCodeMno && ./pma
    fi
    ;;

    "QDRANT")
                clear
        cd && cd SetupLowCodeMno && ./qdrant
    ;;

    "RABBITMQ")
                clear
        cd && cd SetupLowCodeMno && ./rabbitmq
    ;;

    "REDIS")
                clear
        cd && cd SetupLowCodeMno && ./redis
    ;;

    "REDIS COMMANDER")
    if [[ ("$redicommander_container" != "") ]];
    then
                clear
    else
        clear
        cd && cd SetupLowCodeMno && ./redicommander
    fi
    ;;

    "REDISINSIGHT")
                clear
        cd && cd SetupLowCodeMno && ./redisinsight
    ;;

    "SEARXNG")
                clear
        cd && cd SetupLowCodeMno && ./searxng
    ;;

    "SHLINK")
                clear
        cd && cd SetupLowCodeMno && ./shlink
    ;;

    "STIRLING PDF")
                clear
        cd && cd SetupLowCodeMno && ./stirlingpdf
    ;;

    "TYPEBOT")
            clear
        cd && cd SetupLowCodeMno && ./typebot
    ;;

    "TYPEBOT + MINIO*")
            clear
        cd && cd SetupLowCodeMno && ./typebot_minio
    ;;

     "UPTIMEKUMA")
                clear
        cd && cd SetupLowCodeMno && ./uptimekuma
    ;;

    "VAULTWARDEN")
                clear
        cd && cd SetupLowCodeMno && ./vaultwarden
    ;;

    "WORDPRESS")
                clear
        cd && cd SetupLowCodeMno && ./wordpress
    ;;

    "WUZAP")
                clear
        cd && cd SetupLowCodeMno && ./wuzap
    ;;

     "REINICIAR APPS/SERVIÇOS")
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

    "ESSENCIAIS EDITÁVEIS NO PORTAINER")
          clear
        cd && cd SetupLowCodeMno && ./essenciais
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
    type_effect "SETUP MNO FINALIZADO COM ÊXITO!"
   echo -n " ➤ "
    type_effect "P/ INICIAR: SEMPRE DIGITE 'setup-mno' NO TERMINAL"
    echo "┣━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┫"
    echo -e "   \033[1;35m🚀 COMANDO DE REATIVAÇÃO:\033[1;37m setup-mno\033[1;32m         "
    echo -e "   \033[1;35m📡 CANAIS DE SUPORTE:\033[1;32m                                 "
    echo -e "      \033[1;36m● WhatsApp: +55 (19) 99398-4964\033[1;32m                    "
    echo -e "      \033[1;36m● Email: contato@marciocalicchio.com.br\033[1;32m                    "
    echo -e "   \033[1;33m⚠️  SISTEMA PRONTO PARA OPERAÇÃO \033[1;32m                     "
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

fi


if [ "$PLANO" == "free2" ]; then
CHOICE=$(
whiptail --title "$TITULO" --menu "Selecione um App: Use as setas do seu teclado e pressione ENTER" 20 70 10 \
    "OPENCLAW" "" \
    "EVOLUTION 2.0 API PADRÃO" ""  \
    "EVOLUTION CRM" ""  \
    "EVOLUTION GO" ""  \
    "EVO NEXUS" ""  \
    "N8N V1 - SEM FILA (MAIN)" "" \
    "N8N V1 - FILA (QUEUE)" "" \
    "N8N V2 - FILA (QUEUE)" "" \
    "PGADMIN4" "" \
    "MINIO" "" \
    "REDIS" "" \
    "AFFINE" "PRO" \
    "APPSMITH" "PRO" \
    "AUTOGEN STUDIO" "PRO" \
    "BASEROW" "PRO" \
    "CHATWOOTN + EVOLUTIONN 2.0 + RABBITMQ*" "PRO"   \
    "CHATWOOTN + EVOLUTIONN 2.0 + RABBITMQ + MINIO*" "PRO"   \
    "CHATWOOTORIG + EVOLUTIONN 2.0 + RABBITMQ + MINIO*" "PRO"   \
    "CHATWOOTORIG (DESBLOQUEADO) + EVOLUTIONN 2.0 + RABBITMQ + MINIO*" "PRO"   \
    "CLICKHOUSE" "PRO"   \
    "COGNEE" "PRO"   \
    "DATABASUS" "PRO"   \
    "DIRECTUS" "PRO" \
    "DISCOURSE" "PRO" \
    "DOCUMENSO" "PRO" \
    "DOCUSEAL" "PRO" \
    "DOZZLE" "PRO" \
    "EVOAI" "PRO"  \
    "EVOAI + EVOLUTION 2.0 + MINIO*" "PRO"  \
    "EVOLUTION 1.0 API PADRÃO" "PRO"  \
    "FLOWISE" "PRO" \
    "GHOST" "PRO" \
    "GRAFANA/PROMETHEUS MONITOR" "PRO"   \
    "HERMES AGENT" "PRO" \
    "KRAYIN CRM" "PRO" \
    "LANGFUSE + MINIO + CLICKHOUSE*" "PRO" \
    "LITELLM" "PRO" \
    "MATOMO" "PRO" \
    "MAUTIC 6 PADRÃO" "PRO" \
    "MAUTIC 6 WHATSAPP MKT" "PRO" \
    "MAUTIC 7 PADRÃO" "PRO" \
    "MAUTIC 7 WHATSAPP MKT" "PRO" \
    "MEMGRAPH" "PRO" \
    "MONGODB" "" \
    "MOODLE" "PRO" \
    "MYSQL" "" \
    "N8N TEMPLATES FREE - + DE 2000 WORKFLOWS" "" \
    "NEMOCLAW" "EM BREVE" \
    "NEO4J" "PRO" \
    "NEXTCLOUD" "PRO" \
    "NOCODB" "" \
    "NTFY" "" \
    "OLLAMA + OPENWEBUI*" "" \
    "OPENFANG" "PRO" \
    "OPENCLAW + QDRANT + NEO4J + COGNEE + SEARXNG*" "PRO" \
    "OPEN PROJECT" "PRO" \
    "PHPMYADMIN" "" \
    "QDRANT" "" \
    "RABBITMQ" "" \
    "REDIS COMMANDER" "" \
    "REDISINSIGHT" "" \
    "SEARXNG" "PRO" \
    "SHLINK" "" \
    "STIRLING PDF" "" \
    "TYPEBOT" "" \
    "TYPEBOT + MINIO*" "PRO" \
    "UPTIMEKUMA" "" \
    "VAULTWARDEN" "" \
    "WORDPRESS" "" \
    "WUZAP" "" \
    "REINICIAR APPS/SERVIÇOS" "" \
    "DELETAR APPS/STACKS" "" \
    "GERADOR DE REGISTROS DNS" "" \
    "ESSENCIAIS EDITÁVEIS NO PORTAINER" "" \
        "SAIR" ""  3>&2 2>&1 1>&3
)

case $CHOICE in

  "AFFINE")
                clear
        cd && cd SetupLowCodeMno && ./affine
        ;;

    "APPSMITH")
          clear
          cd && cd SetupLowCodeMno && ./appsmith
    ;;

     "AUTOGEN STUDIO")
          clear
        cd && cd SetupLowCodeMno && ./autogen
    ;;

    "BASEROW")
                clear
        cd && cd SetupLowCodeMno && ./baserow
    ;;

    "CHATWOOTN + EVOLUTIONN 2.0 + RABBITMQ*")
                clear
        cd && cd SetupLowCodeMno && ./chatwootn_evo2_rabbitmq_redisevo
        ;;

    "CHATWOOTN + EVOLUTIONN 2.0 + RABBITMQ + MINIO*")
                clear
        cd && cd SetupLowCodeMno && ./chatwootn_evo2_rabbitmq_minio
        ;;

    "CHATWOOTORIG + EVOLUTIONN 2.0 + RABBITMQ + MINIO*")
                clear
        cd && cd SetupLowCodeMno && ./chatwooto_evo2_rabbitmq_minio
        ;;

    "CHATWOOTORIG (DESBLOQUEADO) + EVOLUTIONN 2.0 + RABBITMQ + MINIO*")
                clear
        cd && cd SetupLowCodeMno && ./chatwootorig_desbloq__evo2_rabbitmq_minio
        ;;

    "CLICKHOUSE")
             clear
        cd && cd SetupLowCodeMno && ./clickhouse
    ;;

    "COGNEE")
             clear
        cd && cd SetupLowCodeMno && ./cognee
    ;;

    "DATABASUS")
             clear
        cd && cd SetupLowCodeMno && ./databasus
    ;;

    "DIRECTUS")
                clear
        cd && cd SetupLowCodeMno && ./directus
        ;;

    "DISCOURSE")
                clear
        cd && cd SetupLowCodeMno && ./discourse
        ;;

    "DOCUMENSO")
                clear
        cd && cd SetupLowCodeMno && ./documenso
        ;;

    "DOCUSEAL")
                clear
        cd && cd SetupLowCodeMno && ./docuseal
        ;;

    "DOZZLE")
                clear
        cd && cd SetupLowCodeMno && ./dozzle
        ;;

    "EVOAI")
              clear
        cd && cd SetupLowCodeMno && ./evoai
        ;;

    "EVOAI + EVOLUTION 2.0 + MINIO*")
              clear
        cd && cd SetupLowCodeMno && ./evoai_evo2_minio
        ;;

    "EVOLUTION 1.0 API PADRÃO")
            clear
        cd && cd SetupLowCodeMno && ./evolutionapi
        ;;

    "EVOLUTION 2.0 API PADRÃO")
              clear
        cd && cd SetupLowCodeMno && ./evolution2api
        ;;

    "EVOLUTION CRM")
              clear
        cd && cd SetupLowCodeMno && ./evocrm
        ;;

    "EVOLUTION GO")
              clear
        cd && cd SetupLowCodeMno && ./evolutiongo
        ;;

    "EVO NEXUS")
              clear
        cd && cd SetupLowCodeMno && ./evonexus
        ;;

    "FLOWISE")
                 if [[ ("$flowise_container" != "") ]];
    then
                clear
    else
        clear
        cd && cd SetupLowCodeMno && ./flowise
    fi
    ;;

    "GHOST")
                clear
        cd && cd SetupLowCodeMno && ./ghost
        ;;

    "GRAFANA/PROMETHEUS MONITOR")
                clear
        cd && cd SetupLowCodeMno && ./grafana
        ;;

    "HERMES AGENT")
                clear
        cd && cd SetupLowCodeMno && ./hermes
        ;;

    "KRAYIN CRM")
                clear
        cd && cd SetupLowCodeMno && ./krayincrm
        ;;

    "LANGFUSE + MINIO + CLICKHOUSE*")
             clear
        cd && cd SetupLowCodeMno && ./langfuse
    ;;

    "LITELLM")
             clear
        cd && cd SetupLowCodeMno && ./litellm
    ;;

    "MATOMO")
                clear
        cd && cd SetupLowCodeMno && ./matomo
        ;;

    "MAUTIC 6 PADRÃO")
                clear
        cd && cd SetupLowCodeMno && ./mautic6padrao
    ;;

    "MAUTIC 6 WHATSAPP MKT")
                clear
        cd && cd SetupLowCodeMno && ./mautic6whatsmkt
    ;;


    "MAUTIC 7 PADRÃO")
                clear
        cd && cd SetupLowCodeMno && ./mautic7padrao
    ;;

    "MAUTIC 7 WHATSAPP MKT")
                clear
        cd && cd SetupLowCodeMno && ./mautic7whatsmkt
    ;;

    "MEMGRAPH")
                clear
        cd && cd SetupLowCodeMno && ./memgraph
    ;;

     "MINIO")
        if [[ ("$minio_container" != "") ]];
    then
                clear
    else
        clear
        cd && cd SetupLowCodeMno && ./minio
    fi
    ;;

    "MONGODB")
                clear
        cd && cd SetupLowCodeMno && ./mongodb
    ;;

    "MOODLE")
                clear
        cd && cd SetupLowCodeMno && ./moodle
    ;;

    "MYSQL")
    if [[ ("$mysql_container" != "") ]];
    then
                clear
    else
        clear
        cd && cd SetupLowCodeMno && ./mysql
    fi
    ;;

    "N8N V1 - SEM FILA (MAIN)")
            clear
        cd && cd SetupLowCodeMno && ./n8nmain
    ;;

    "N8N V1 - FILA (QUEUE)")
            clear
        cd && cd SetupLowCodeMno && ./n8n
    ;;

    "N8N V2 - FILA (QUEUE)")
            clear
        cd && cd SetupLowCodeMno && ./n8n2
    ;;

    "N8N TEMPLATES FREE - + DE 2000 WORKFLOWS")
            clear
        cd && cd SetupLowCodeMno && ./n8n-workflows
    ;;

 


    "NEO4J")
            clear
        cd && cd SetupLowCodeMno && ./neo4j
    ;;

    "NEXTCLOUD")
            clear
        cd && cd SetupLowCodeMno && ./nextcloud
    ;;

    "NOCODB")
                clear
        cd && cd SetupLowCodeMno && ./nocodb
    ;;

    "NTFY")
                clear
        cd && cd SetupLowCodeMno && ./ntfy
    ;;

    "OLLAMA + OPENWEBUI*")
                clear
        cd && cd SetupLowCodeMno && ./ollama
    ;;

    "OPENCLAW")
                clear
        cd && cd SetupLowCodeMno && ./openclaw
    ;;

    "OPENCLAW + QDRANT + NEO4J + COGNEE + SEARXNG*")
                clear
        cd && cd SetupLowCodeMno && ./openclawpro
    ;;


    "OPENFANG")
                clear
        cd && cd SetupLowCodeMno && ./openfang
    ;;

    "OPEN PROJECT")
                clear
        cd && cd SetupLowCodeMno && ./openproject
    ;;

    "PGADMIN4")
                if [[ ("$pgadmin4_container" != "") ]];
    then
                clear
    else
        clear
        cd && cd SetupLowCodeMno && ./pgadmin
    fi
    ;;

    "PHPMYADMIN")
    if [[ ("$pma_container" != "") ]];
    then
                clear
    else
        clear
        cd && cd SetupLowCodeMno && ./pma
    fi
    ;;

    "QDRANT")
                clear
        cd && cd SetupLowCodeMno && ./qdrant
    ;;

    "RABBITMQ")
                clear
        cd && cd SetupLowCodeMno && ./rabbitmq
    ;;

    "REDIS")
                clear
        cd && cd SetupLowCodeMno && ./redis
    ;;

    "REDIS COMMANDER")
    if [[ ("$redicommander_container" != "") ]];
    then
                clear
    else
        clear
        cd && cd SetupLowCodeMno && ./redicommander
    fi
    ;;

    "REDISINSIGHT")
                clear
        cd && cd SetupLowCodeMno && ./redisinsight
    ;;

    "SEARXNG")
                clear
        cd && cd SetupLowCodeMno && ./searxng
    ;;

    "SHLINK")
                clear
        cd && cd SetupLowCodeMno && ./shlink
    ;;

    "STIRLING PDF")
                clear
        cd && cd SetupLowCodeMno && ./stirlingpdf
    ;;

    "TYPEBOT")
            clear
        cd && cd SetupLowCodeMno && ./typebot
    ;;

    "TYPEBOT + MINIO*")
            clear
        cd && cd SetupLowCodeMno && ./typebot_minio
    ;;

     "UPTIMEKUMA")
                clear
        cd && cd SetupLowCodeMno && ./uptimekuma
    ;;

    "VAULTWARDEN")
                clear
        cd && cd SetupLowCodeMno && ./vaultwarden
    ;;

    "WORDPRESS")
                clear
        cd && cd SetupLowCodeMno && ./wordpress
    ;;

    "WUZAP")
                clear
        cd && cd SetupLowCodeMno && ./wuzap
    ;;

     "REINICIAR APPS/SERVIÇOS")
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

    "ESSENCIAIS EDITÁVEIS NO PORTAINER")
          clear
        cd && cd SetupLowCodeMno && ./essenciais
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
    type_effect "SETUP MNO FINALIZADO COM ÊXITO!"
    echo -n " ➤ "
    type_effect "P/ INICIAR: SEMPRE DIGITE 'setup-mno' NO TERMINAL"
    echo "┣━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┫"
    echo -e "   \033[1;35m🚀 COMANDO DE REATIVAÇÃO:\033[1;37m setup-mno\033[1;32m         "
    echo -e "   \033[1;35m📡 CANAIS DE SUPORTE:\033[1;32m                                 "
    echo -e "      \033[1;36m● WhatsApp: +55 (11) 96816-2690\033[1;32m                    "
    echo -e "      \033[1;36m● Email: francisbreit@gmail.com\033[1;32m                    "
    echo -e "      \033[1;36m● GitHub: github.com/francisbreit\033[1;32m                  "
    echo -e "   \033[1;33m⚠️  SISTEMA PRONTO PARA OPERAÇÃO \033[1;32m                     "
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

fi



#mensagem apps já instalados
if [[ ("$mysql_container" != "") && ("$CHOICE" == "MYSQL") || ("$flowise_container" != "") && ("$CHOICE" == "FLOWISE") || ("$minio_container" != "") && ("$CHOICE" == "MINIO") || ("$pgadmin4_container" != "") && ("$CHOICE" == "PGADMIN4") || ("$pma_container" != "") && ("$CHOICE" == "PHPMYADMIN") || ("$zepdb_container" != "") && ("$CHOICE" == "ZEP VECTOR STORE") || ("$zep_container" != "") && ("$CHOICE" == "ZEP VECTOR STORE") || ("$redicommander_container" != "") && ("$CHOICE" == "REDIS COMMANDER") || ("$calcom_container" != "") && ("$CHOICE" == "CAL.COM") || ("$langfuse_container" != "") && ("$CHOICE" == "LANGFUSE") || ("$dify_container" != "") && ("$CHOICE" == "DIFY") || ("$supabase_container" != "") && ("$CHOICE" == "SUPABASE")]];
then
 whiptail --msgbox "Aviso: ${CHOICE} já está instalado. Não é permitido instalar mais de uma instancia de ${CHOICE}. Digite ENTER para voltar ao Menu Principal." 20 78
fi

if [ "$PLANO" == "free" ]; then

#mensagem apps pro

if [[ ("$CHOICE" == "AFFINE") || ("$CHOICE" == "APPSMITH") || ("$CHOICE" == "BASEROW") || ("$CHOICE" == "BOTPRESS") || ("$CHOICE" == "CAL.COM") || ("$CHOICE" == "CHATWOOTN + EVOLUTIONN 2.0 + RABBITMQ + MINIO*") || ("$CHOICE" == "DOCUMENSO") || ("$CHOICE" == "DOCUSEAL") || ("$CHOICE" == "DOZZLE") || ("$CHOICE" == "EASY APPOINTMENTS") || ("$CHOICE" == "EVOAI + EVOLUTION 2.0 + MINIO*") || ("$CHOICE" == "HUMHUB") || ("$CHOICE" == "KRAYIN CRM") || ("$CHOICE" == "LANGFUSE + MINIO + CLICKHOUSE*") || ("$CHOICE" == "LITELLM") || ("$CHOICE" == "MAUTIC 4 WHATSAPP MKT") || ("$CHOICE" == "MAUTIC 5 WHATSAPP MKT") || ("$CHOICE" == "MAUTIC 6 WHATSAPP MKT") || ("$CHOICE" == "MOODLE") || ("$CHOICE" == "NEXTCLOUD") || ("$CHOICE" == "OPEN PROJECT") || ("$CHOICE" == "OUTLINE") || ("$CHOICE" == "TWENTY CRM") || ("$CHOICE" == "TYPEBOT + MINIO*") || ("$CHOICE" == "MATOMO") || ("$CHOICE" == "OPENCLAW") || ("$CHOICE" == "DISCOURSE") || ("$CHOICE" == "GHOST") || ("$CHOICE" == "MAUTIC 7 WHATSAPP MKT") || ("$CHOICE" == "AUTOGEN STUDIO") || ("$CHOICE" == "COGNEE") || ("$CHOICE" == "MEMGRAPH") || ("$CHOICE" == "NEO4J") || ("$CHOICE" == "OPENFANG") || ("$CHOICE" == "PAPERCLIP") || ("$CHOICE" == "SEARXNG") || ("$CHOICE" == "OPENCLAW + QDRANT + NEO4J + COGNEE + SEARXNG*") || ("$CHOICE" == "HERMES AGENT") || ("$CHOICE" == "CHATWOOTORIG + EVOLUTIONN 2.0 + RABBITMQ + MINIO*") || ("$CHOICE" == "CHATWOOTORIG (DESBLOQUEADO) + EVOLUTIONN 2.0 + RABBITMQ + MINIO*") ]]; then
whiptail --msgbox "A ferramenta ${CHOICE} não está disponível no plano free.\n\nEntre em contato conosco:\n- WhatsApp: +55 (11)96816-2690 e adquira o plano PRO.\n\nPressione ENTER para voltar ao Menu Principal." 20 78
fi


fi


if [ "$PLANO" == "free1" ]; then

#mensagem apps pro
if [[ ("$CHOICE" != "DATABASUS") && ("$CHOICE" != "EVOLUTION 2.0 API PADRÃO") && ("$CHOICE" != "N8N V1 - SEM FILA (MAIN)") && ("$CHOICE" != "N8N V1 - FILA (QUEUE)") && ("$CHOICE" != "N8N V2 - FILA (QUEUE)") && ("$CHOICE" != "PGADMIN4") && ("$CHOICE" != "MINIO") && ("$CHOICE" != "REDIS") && ("$CHOICE" != "EVOLUTION CRM") && ("$CHOICE" != "EVOLUTION GO") && ("$CHOICE" != "EVO NEXUS")  ]]; then
whiptail --msgbox "A ferramenta ${CHOICE} não está disponível no plano free1.\n\nEntre em contato conosco:\n- WhatsApp: +55 (19) 99398-4964 e adquira o plano PRO.\n\nPressione ENTER para voltar ao Menu Principal." 20 78
fi


fi

if [ "$PLANO" == "free2" ]; then

#mensagem apps pro
if [[ ("$CHOICE" != "OPENCLAW") && ("$CHOICE" != "EVOLUTION 2.0 API PADRÃO") && ("$CHOICE" != "N8N V1 - SEM FILA (MAIN)") && ("$CHOICE" != "N8N V1 - FILA (QUEUE)") && ("$CHOICE" != "N8N V2 - FILA (QUEUE)") && ("$CHOICE" != "PGADMIN4") && ("$CHOICE" != "MINIO") && ("$CHOICE" != "REDIS") && ("$CHOICE" != "EVOLUTION CRM") && ("$CHOICE" != "EVOLUTION GO") && ("$CHOICE" != "EVO NEXUS")  ]]; then
whiptail --msgbox "A ferramenta ${CHOICE} não está disponível no plano free2.\n\nEntre em contato conosco:\n- WhatsApp: +55 (11)96816-2690 e adquira o plano PRO.\n\nPressione ENTER para voltar ao Menu Principal." 20 78
fi


fi



#mensagem apps EM BREVE
if [[ ("$CHOICE" == "NEMOCLAW")  ]]; then
whiptail --msgbox "A ferramenta ${CHOICE} não está disponível atualmente.\n\nEstamos fazendo ajustes e, em breve, estará liberada para instalação.\n\nPressione ENTER para voltar ao Menu Principal." 20 78
fi


done
#exit 0

#
# FIM DAS OPÕES
#

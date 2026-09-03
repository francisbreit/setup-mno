#!/usr/bin/bash
#########################################################
# Setup MNO — Combo Blueprint #001: WhatsApp Marketing Completo
# Ecossistema: Chatwoot + Evolution API v2 + RabbitMQ + MinIO + Mautic 7 + n8n v2 (Fila) + Typebot
#########################################################
export NEWT_COLORS='
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

{
  tput reset 2>/dev/null
  exec 0</dev/tty 1>/dev/tty 2>&1
  sleep 0.01
  clear
} || true

INSTALL_TYPE_FILE="/root/.cloudflared_config/installation_type"
if [ -f "$INSTALL_TYPE_FILE" ]; then
    INSTALL_TYPE=$(cat "$INSTALL_TYPE_FILE")
else
    INSTALL_TYPE="TRADICIONAL"
fi

if [ "$INSTALL_TYPE" = "CLOUDFLARE_TUNNEL" ]; then
    if [ -f "${SETUPMNO_CLOUDFLARE_CREDENTIALS_FILE:-/root/.cloudflared_config/cloudflare_credentials}" ]; then
        source "${SETUPMNO_CLOUDFLARE_CREDENTIALS_FILE:-/root/.cloudflared_config/cloudflare_credentials}"
    fi
else
    if [ -f "${SETUPMNO_TRADITIONAL_CREDENTIALS_FILE:-/root/.tradicional_config/tradicional_credentials}" ]; then
        source "${SETUPMNO_TRADITIONAL_CREDENTIALS_FILE:-/root/.tradicional_config/tradicional_credentials}"
    fi
fi

check_service_running() {
    local pattern="$1"
    docker service ls --format '{{.Name}}' 2>/dev/null | grep -Ei "$pattern" | head -n1
}

run_step_with_check() {
    local step_title="$1"
    local app_binary="$2"
    local pattern="$3"
    local app_desc="$4"
    local is_guided="${5:-0}"

    local existing_svc=""
    if [ -n "$pattern" ]; then
        existing_svc=$(check_service_running "$pattern")
    fi

    if [ -n "$existing_svc" ]; then
        if whiptail --title "APLICAÇÃO DETECTADA: $app_desc" \
            --yes-button "Usar Existente" \
            --no-button "Reinstalar / Atualizar" \
            --yesno "Detectamos que '$app_desc' já está instalado e ativo nesta VPS!\n\nServiço identificado no Swarm: $existing_svc\n\nDeseja UTILIZAR A INSTALAÇÃO EXISTENTE (recomendado) ou deseja REINSTALAR / ATUALIZAR?" 13 72; then
            whiptail --title "INSTALAÇÃO PRESERVADA" --msgbox "Utilizando a instalação existente de '$app_desc'. Avançando para a próxima etapa..." 10 65
            return 0
        fi
    fi

    if [ "$is_guided" = "1" ]; then
        whiptail --title "$step_title" --msgbox \
            "Iniciaremos agora o provisionamento de: $app_desc.\n\nApós concluir esta etapa, você retornará automaticamente para o fluxo." 12 70
    fi

    if [ -f "/root/SetupLowCodeMno/$app_binary" ]; then
        "/root/SetupLowCodeMno/$app_binary"
    fi
}

while true; do
CHOICE=$(
whiptail --title "BLUEPRINT #001: COMBO WHATSAPP MARKETING COMPLETO" --menu \
"Bem-vindo ao Combo do Blueprint #001: WhatsApp Marketing Completo!\n\nEste ecossistema integra 7 ferramentas profissionais para automação, campanhas, filas anti-bloqueio, chatbots e atendimento humano.\n\nTIPO DE INSTALAÇÃO: $INSTALL_TYPE\nREQUISITO RECOMENDADO: 8 GB a 12 GB de RAM\n\nEscolha uma opção (Utilize as setas e Enter):" 22 76 6 \
  "1)" "INSTALAÇÃO GUIADA COMPLETA (4 ETAPAS COM DETECÇÃO)" \
  "2)" "Etapa 1: Chatwoot (Desbloqueado) + Evolution 2.0 + RabbitMQ + MinIO" \
  "3)" "Etapa 2: Mautic 7 WhatsApp Mkt" \
  "4)" "Etapa 3: n8n v2 - Modo Fila (Queue)" \
  "5)" "Etapa 4: Typebot + MinIO" \
  "6)" "SAIR PARA O MENU PRINCIPAL" 3>&2 2>&1 1>&3
)

case $CHOICE in
  "1)")
    run_step_with_check "PASSO 1 DE 4 — COMUNICAÇÃO E ATENDIMENTO" "chatwootorig_desbloq__evo2_rabbitmq_minio" "chatwoot" "Chatwoot (Desbloqueado) + Evolution 2.0 + RabbitMQ + MinIO" 1
    run_step_with_check "PASSO 2 DE 4 — GESTÃO DE MARKETING" "mautic7whatsmkt" "mautic" "Mautic 7 WhatsApp Mkt" 1
    run_step_with_check "PASSO 3 DE 4 — MOTOR DE AUTOMAÇÃO" "n8n2" "n8n" "n8n v2 - Modo Fila (Queue)" 1
    run_step_with_check "PASSO 4 DE 4 — FLUXOS CONVERSACIONAIS" "typebot_minio" "typebot" "Typebot + MinIO" 1

    whiptail --title "PARABÉNS! INSTALAÇÃO DO COMBO CONCLUÍDA!" --msgbox \
      "Todas as 4 ferramentas do Blueprint #001 foram configuradas com sucesso!\n\nConsulte o arquivo LEIA_ME.txt ou o Control Center na aba Blueprints para obter os arquivos de workflow do n8n, templates do Typebot e configurações de campanha do Mautic." 14 72
    break
  ;;

  "2)")
    run_step_with_check "ETAPA 1 — COMUNICAÇÃO E ATENDIMENTO" "chatwootorig_desbloq__evo2_rabbitmq_minio" "chatwoot" "Chatwoot (Desbloqueado) + Evolution 2.0 + RabbitMQ + MinIO" 0
  ;;

  "3)")
    run_step_with_check "ETAPA 2 — GESTÃO DE MARKETING" "mautic7whatsmkt" "mautic" "Mautic 7 WhatsApp Mkt" 0
  ;;

  "4)")
    run_step_with_check "ETAPA 3 — MOTOR DE AUTOMAÇÃO" "n8n2" "n8n" "n8n v2 - Modo Fila (Queue)" 0
  ;;

  "5)")
    run_step_with_check "ETAPA 4 — FLUXOS CONVERSACIONAIS" "typebot_minio" "typebot" "Typebot + MinIO" 0
  ;;

  "6)")
    cd /
    cd
    exit 0
  ;;
esac
done

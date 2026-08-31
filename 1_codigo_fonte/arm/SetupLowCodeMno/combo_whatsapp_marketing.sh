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

while true; do
CHOICE=$(
whiptail --title "BLUEPRINT #001: COMBO WHATSAPP MARKETING COMPLETO" --menu \
"Bem-vindo ao Combo do Blueprint #001: WhatsApp Marketing Completo!\n\nEste ecossistema integra 7 ferramentas profissionais para automação, campanhas, filas anti-bloqueio, chatbots e atendimento humano.\n\nTIPO DE INSTALAÇÃO: $INSTALL_TYPE\nREQUISITO RECOMENDADO: 8 GB a 12 GB de RAM\n\nEscolha uma opção (Utilize as setas e Enter):" 22 76 6 \
  "1)" "INSTALAÇÃO GUIADA COMPLETA (4 ETAPAS)" \
  "2)" "Etapa 1: Chatwoot + Evolution 2.0 + RabbitMQ + MinIO" \
  "3)" "Etapa 2: Mautic 7 WhatsApp Mkt" \
  "4)" "Etapa 3: n8n v2 - Modo Fila (Queue)" \
  "5)" "Etapa 4: Typebot + MinIO" \
  "6)" "SAIR PARA O MENU PRINCIPAL" 3>&2 2>&1 1>&3
)

case $CHOICE in
  "1)")
    whiptail --title "PASSO 1 DE 4 — COMUNICAÇÃO E ATENDIMENTO" --msgbox \
      "Iniciaremos agora a Etapa 1: Provisionamento do Combo CHATWOOT + EVOLUTION API v2 + RABBITMQ + MINIO.\n\nApós concluir esta etapa, você retornará automaticamente para a próxima." 12 70
    if [ -f /root/SetupLowCodeMno/chatwootn_evo2_rabbitmq_minio ]; then
      /root/SetupLowCodeMno/chatwootn_evo2_rabbitmq_minio
    fi

    whiptail --title "PASSO 2 DE 4 — GESTÃO DE MARKETING" --msgbox \
      "Iniciaremos agora a Etapa 2: Provisionamento do MAUTIC 7 WHATSAPP MKT.\n\nApós concluir esta etapa, você retornará automaticamente para a próxima." 12 70
    if [ -f /root/SetupLowCodeMno/mautic7whatsmkt ]; then
      /root/SetupLowCodeMno/mautic7whatsmkt
    fi

    whiptail --title "PASSO 3 DE 4 — MOTOR DE AUTOMAÇÃO" --msgbox \
      "Iniciaremos agora a Etapa 3: Provisionamento do N8N V2 - MODO FILA (QUEUE).\n\nApós concluir esta etapa, você retornará automaticamente para a próxima." 12 70
    if [ -f /root/SetupLowCodeMno/n8n2 ]; then
      /root/SetupLowCodeMno/n8n2
    fi

    whiptail --title "PASSO 4 DE 4 — FLUXOS CONVERSACIONAIS" --msgbox \
      "Iniciaremos agora a Etapa 4: Provisionamento do TYPEBOT + MINIO.\n\nApós concluir esta etapa, seu ecossistema estará pronto para receber os workflows e templates!" 12 70
    if [ -f /root/SetupLowCodeMno/typebot_minio ]; then
      /root/SetupLowCodeMno/typebot_minio
    fi

    whiptail --title "PARABÉNS! INSTALAÇÃO DO COMBO CONCLUÍDA!" --msgbox \
      "Todas as 4 ferramentas do Blueprint #001 foram provisionadas com sucesso!\n\nConsulte o arquivo LEIA_ME.txt ou o Control Center na aba Blueprints para obter os arquivos de workflow do n8n, templates do Typebot e configurações de campanha do Mautic." 14 72
    break
  ;;

  "2)")
    if [ -f /root/SetupLowCodeMno/chatwootn_evo2_rabbitmq_minio ]; then
      /root/SetupLowCodeMno/chatwootn_evo2_rabbitmq_minio
    fi
  ;;

  "3)")
    if [ -f /root/SetupLowCodeMno/mautic7whatsmkt ]; then
      /root/SetupLowCodeMno/mautic7whatsmkt
    fi
  ;;

  "4)")
    if [ -f /root/SetupLowCodeMno/n8n2 ]; then
      /root/SetupLowCodeMno/n8n2
    fi
  ;;

  "5)")
    if [ -f /root/SetupLowCodeMno/typebot_minio ]; then
      /root/SetupLowCodeMno/typebot_minio
    fi
  ;;

  "6)")
    cd /
    cd
    exit 0
  ;;
esac
done

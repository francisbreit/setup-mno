#!/usr/bin/bash
#########################################################
# Setup MNO — Combo Blueprint #006: Vibe Ops
# Ecossistema: Hermes Agent + n8n v2 (Fila) + MNO Fleet Hub & Sentinel
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
whiptail --title "BLUEPRINT #006: COMBO VIBE OPS (HERMES AGENT + N8N)" --menu \
"Bem-vindo ao Combo do Blueprint #006: Vibe Ops com Hermes Agent e n8n!\n\nEste ecossistema integra o Agente de IA Autônomo com o motor de automações n8n, conectado ao MNO Fleet Hub e Sentinel para operação de servidores em linguagem natural.\n\nTIPO DE INSTALAÇÃO: $INSTALL_TYPE\nREQUISITO RECOMENDADO: ~3 GB de RAM\n\nEscolha uma opção (Utilize as setas e Enter):" 22 76 5 \
  "1)" "INSTALAÇÃO GUIADA COMPLETA (2 ETAPAS COM DETECÇÃO)" \
  "2)" "Etapa 1: Hermes Agent (Comandante SRE de IA)" \
  "3)" "Etapa 2: n8n v2 - Modo Fila (Queue)" \
  "4)" "Guia: Workflows de Vibe Ops e Tool Calling" \
  "5)" "SAIR PARA O MENU PRINCIPAL" 3>&2 2>&1 1>&3
)

case $CHOICE in
  "1)")
    run_step_with_check "PASSO 1 DE 2 — COMANDANTE SRE DE IA" "hermes" "hermes" "Hermes Agent" 1
    run_step_with_check "PASSO 2 DE 2 — MOTOR DE AUTOMAÇÃO" "n8n2" "n8n" "n8n v2 - Modo Fila (Queue)" 1

    whiptail --title "PARABÉNS! INSTALAÇÃO DO COMBO CONCLUÍDA!" --msgbox \
      "As ferramentas do Combo Vibe Ops foram provisionadas com sucesso!\n\nPara ativar o Tool Calling da frota no n8n:\n1. Acesse seu n8n e importe os workflows do Blueprint #006;\n2. No Control Center, configure o MNO Sentinel para enviar alertas para o n8n;\n3. Converse com o Hermes Agent pelo Telegram ou WhatsApp!" 15 74
    break
  ;;

  "2)")
    run_step_with_check "ETAPA 1 — COMANDANTE SRE DE IA" "hermes" "hermes" "Hermes Agent" 0
  ;;

  "3)")
    run_step_with_check "ETAPA 2 — MOTOR DE AUTOMAÇÃO" "n8n2" "n8n" "n8n v2 - Modo Fila (Queue)" 0
  ;;

  "4)")
    whiptail --title "GUIA: WORKFLOWS VIBE OPS" --msgbox \
      "Os arquivos oficiais de workflow e prompts do Blueprint #006 estão disponíveis na pasta:\n\n6_BluePrints_exemplos/Blueprint#006_Vibe_Ops_Hermes_Agent_Fleet_Hub/\n\nWorkflows inclusos:\n- 01_Workflow_Hermes_Vibe_Ops_Fleet_Orchestrator.json\n- 02_Workflow_Sentinel_Webhook_Triagem_IA.json\n\nConsulte o arquivo LEIA_ME_VIBE_OPS.txt para o guia passo a passo." 16 74
  ;;

  "5)")
    cd /
    cd
    exit 0
  ;;
esac
done

#!/bin/bash
# ==============================================================================
# SETUP MNO - AVISO DE DESCONTINUAÇÃO E BLOQUEIO DE SEGURANÇA
# ==============================================================================
CREDENTIALS_FILE="${SETUPMNO_CLOUDFLARE_CREDENTIALS_FILE:-/root/.cloudflared_config/cloudflare_credentials}"

whiptail --title "⚠️ APLICAÇÃO DESCONTINUADA POR MOTIVO DE SEGURANÇA ⚠️" \
    --msgbox "O GLPI foi descontinuado e removido do Setup MNO devido a vulnerabilidades críticas de segurança upstream no PHP (CVE-2026-109618 / PHP2Shell) e ausência de imagens atualizadas mantidas pela comunidade oficial.\n\nPor proteção à integridade da sua infraestrutura e dos seus dados, a instalação desta aplicação foi bloqueada permanentemente.\n\nRecomendamos o uso de ferramentas seguras e ativamente homologadas no ecossistema Setup MNO." 14 78
exit 1

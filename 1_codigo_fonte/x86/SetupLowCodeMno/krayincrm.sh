#!/bin/bash
# ==============================================================================
# SETUP MNO - AVISO DE DESCONTINUAÇÃO E BLOQUEIO DE SEGURANÇA
# ==============================================================================
CREDENTIALS_FILE="${SETUPMNO_CLOUDFLARE_CREDENTIALS_FILE:-/root/.cloudflared_config/cloudflare_credentials}"

whiptail --title "⚠️ APLICAÇÃO DESCONTINUADA POR MOTIVO DE SEGURANÇA ⚠️" \
    --msgbox "O Krayin CRM foi descontinuado e removido do Setup MNO devido a vulnerabilidades críticas de segurança upstream no PHP (CVE-2026-109618 / PHP2Shell).\n\nPara automação, CRM e marketing com segurança blindada, utilize o Mautic 7 Padrão (PHP 8.3.36) ou outras ferramentas homologadas do ecossistema Setup MNO.\n\nPor proteção à integridade da sua infraestrutura e dos seus dados, a instalação desta aplicação foi bloqueada permanentemente." 14 78
exit 1

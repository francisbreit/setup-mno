#!/usr/bin/bash
set -Eeuo pipefail

LAB_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
python3 "$LAB_DIR/validate.py" lock >/dev/null || {
    printf 'SRE-6 BETA: manifesto upstream inválido; preparação bloqueada.\n' >&2
    exit 41
}

if [ "${SETUPMNO_STRIX_SMOKE_TEST:-0}" = "1" ]; then
    printf 'setupmno-strix-lab-ready:blocked-pending-homologation:1.5.3\n'
    exit 0
fi

whiptail --title "SRE-6 — LABORATÓRIO STRIX · BETA" --msgbox \
    "Preparação segura validada.\n\nO Strix 1.5.3 e seus hashes oficiais estão fixados, mas o executor isolado ainda NÃO foi homologado no WSL2 e na VPS. Por isso nenhum alvo será solicitado e nenhum pentest será iniciado nesta candidata.\n\nNenhum executor Strix foi criado. Portanto, o Strix não recebeu Docker da produção, /root, alvos, credenciais ou achados brutos.\n\nPróxima etapa: homologar uma imagem sandbox por digest, com rede, tempo, CPU, RAM e orçamento de LLM limitados." \
    22 86

whiptail --title "SRE-6 — PREPARAÇÃO CONCLUÍDA · BETA" --msgbox \
    "Estado: bloqueado até homologação do executor isolado.\nVersão upstream fixada: 1.5.3.\nPlano exigido: PRO MASTER.\nExecução automática: não.\nCorreção automática: não.\nAcesso ao Docker da produção: proibido." \
    16 78

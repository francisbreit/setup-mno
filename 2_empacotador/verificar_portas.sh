#!/bin/bash
# ==============================================================================
# VERIFICADOR DE CONFLITO DE PORTAS - SETUP MNO
# Consulta a Lista Telefônica Universal de Aplicações e Portas
# Uso: ./verificar_portas.sh [porta]
# ==============================================================================

BASE_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
REGISTRY_JSON="$BASE_DIR/1_codigo_fonte/x86/SetupLowCodeMno/mno_universal_ports.json"
REGISTRY_SCRIPT="$BASE_DIR/1_codigo_fonte/x86/SetupLowCodeMno/mno-port-registry.sh"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=================================================================${NC}"
echo -e "${BLUE}  VERIFICADOR DE PORTAS DA LISTA TELEFÔNICA UNIVERSAL SETUP MNO  ${NC}"
echo -e "${BLUE}=================================================================${NC}"
echo ""

# Se porta foi fornecida, verificar conflito
if [[ -n "${1:-}" ]]; then
    TARGET_PORT="$1"
    if [ -f "$REGISTRY_JSON" ] && command -v jq >/dev/null 2>&1; then
        matches=$(jq -r --argjson p "$TARGET_PORT" '
            .ports | to_entries | map(select(.value.port == $p)) | map(.key) | join(", ")
        ' "$REGISTRY_JSON" 2>/dev/null || true)

        count=$(jq -r --argjson p "$TARGET_PORT" '
            .ports | to_entries | map(select(.value.port == $p)) | length
        ' "$REGISTRY_JSON" 2>/dev/null || echo "0")

        if [[ "$count" -gt 0 ]]; then
            echo -e "${YELLOW}ℹ️  Porta $TARGET_PORT em uso por $count aplicação(ões):${NC}"
            echo -e "   Apps: ${RED}$matches${NC}"
            exit 1
        else
            echo -e "${GREEN}✅ Porta $TARGET_PORT 100% LIVRE na Lista Telefônica Universal!${NC}"
            exit 0
        fi
    else
        echo "Arquivo de registro JSON não encontrado ou jq ausente."
        exit 1
    fi
fi

# Exibir visão geral de portas e aplicações
if [ -x "$REGISTRY_SCRIPT" ]; then
    "$REGISTRY_SCRIPT" list
fi

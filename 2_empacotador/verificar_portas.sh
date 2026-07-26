#!/bin/bash
# ==============================================================================
# VERIFICADOR DE CONFLITO DE PORTAS - SETUP MNO
# Uso: ./verificar_portas.sh [porta]
# ==============================================================================

BASE_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SCRIPTS_DIR="$BASE_DIR/1_codigo_fonte/x86/SetupLowCodeMno"

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

echo "=========================================="
echo "  VERIFICADOR DE PORTAS - SETUP MNO"
echo "=========================================="
echo ""

# Gerar arquivo temporário com portas e apps
TMPFILE=$(mktemp)
for script in "$SCRIPTS_DIR"/*.sh; do
    app=$(basename "$script" .sh)
    grep -oP '"[0-9]+:[0-9]+"' "$script" 2>/dev/null | sed 's/"//g' | while IFS=: read -r host_port container_port; do
        echo "$host_port $app"
    done
done | sort -n > "$TMPFILE"

# Se porta foi fornecida, verificar conflito
if [[ -n "$1" ]]; then
    TARGET_PORT=$1
    matches=$(awk -v p="$TARGET_PORT" '$1 == p {print $2}' "$TMPFILE" | tr '\n' ', ' | sed 's/,$//')
    count=$(awk -v p="$TARGET_PORT" '$1 == p' "$TMPFILE" | wc -l)
    if [[ $count -gt 1 ]]; then
        echo -e "${RED}⚠️  CONFLITO na porta $TARGET_PORT:${NC}"
        echo "   Apps: $matches"
        rm -f "$TMPFILE"
        exit 1
    else
        echo -e "${GREEN}✅ Porta $TARGET_PORT livre (${matches:-nenhum})${NC}"
        rm -f "$TMPFILE"
        exit 0
    fi
fi

# Exibir portas com conflito
echo "PORTA | APPS | STATUS"
echo "------|------|-------"
awk '{
    if (prev == $1) {
        if (!printed) { printf "⚠️  %s | %s, %s | CONFLITO\n", $1, prev_app, $2; printed=1 }
        else { printf "   | %s |\n", $2 }
    } else {
        if (prev != "") printf "✅ %s | %s | OK\n", prev, prev_app
        prev=$1; prev_app=$2; printed=0
    }
} END { if (prev != "") printf "✅ %s | %s | OK\n", prev, prev_app }' "$TMPFILE"

conflicts=$(awk '{if (prev == $1) c++; prev=$1} END {print c+0}' "$TMPFILE")
total=$(awk '{print $1}' "$TMPFILE" | sort -n -u | wc -l)
rm -f "$TMPFILE"

echo ""
echo "Portas únicas: $total | Conflitos: $conflicts"
[[ $conflicts -gt 0 ]] && echo -e "${RED}⚠️  $conflicts portas com conflito!${NC}" || echo -e "${GREEN}✅ Nenhum conflito.${NC}"

#!/bin/bash
# ==============================================================================
# EMPACOTADOR SETUP MNO - GERAÇÃO DA DISTRIBUIÇÃO OPEN-SOURCE (BASH PURO / SEM SHC)
# ==============================================================================
set -euo pipefail

# Cores para o terminal
verde="\e[32m"
amarelo="\e[33m"
azul="\e[36m"
vermelho="\e[31m"
reset="\e[0m"

BASE_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
DIST_DIR="$BASE_DIR/3B_distribuicao_opensource"

echo -e "${azul}=================================================================${reset}"
echo -e "${azul}     EMPACOTADOR SETUP MNO - DISTRIBUIÇÃO OPEN-SOURCE (BASH)     ${reset}"
echo -e "${azul}=================================================================${reset}"
echo -e "${amarelo}🚀 Iniciando empacotamento da versão de CÓDIGO ABERTO...${reset}"

# 0. Backup do conteúdo atual antes de limpar
BACKUP_DIR="$DIST_DIR/backup"
mkdir -p "$BACKUP_DIR"
if ls "$DIST_DIR/"* 1>/dev/null 2>&1; then
    echo "💾 Criando backup do empacotamento anterior..."
    rm -rf "$BACKUP_DIR"/*
    find "$DIST_DIR/" -maxdepth 1 -mindepth 1 ! -name 'backup' -exec cp -r {} "$BACKUP_DIR/" \; 2>/dev/null || true
    echo "💾 Backup salvo em 3B_distribuicao_opensource/backup/"
fi

# 1. Limpeza do ambiente de distribuição
echo "🧹 Limpando a pasta 3B_distribuicao_opensource..."
find "$DIST_DIR/" -maxdepth 1 -mindepth 1 ! -name 'backup' -exec rm -rf {} + 2>/dev/null || true
mkdir -p "$DIST_DIR/x86"
mkdir -p "$DIST_DIR/arm"

# 2. Sincronização e Validação do Control Center e Manifestos Runtime
echo -e "${amarelo}⚙️  Sincronizando Control Center e manifestos runtime...${reset}"
bash "$BASE_DIR/1_codigo_fonte/setupmno-control/generate-installers.sh" || {
    echo -e "${vermelho}❌ ERRO CRÍTICO: Falha na validação dos manifestos. Abortando empacotamento!${reset}" >&2
    exit 1
}

# 3. Copiar os instaladores de entrada em texto puro
echo "📄 Copiando scripts de inicialização open-source..."
cp "$BASE_DIR/1_codigo_fonte/setup-mno-open.sh" "$DIST_DIR/setup-mno-open.sh"
cp "$BASE_DIR/1_codigo_fonte/setup-mno-open.sh" "$DIST_DIR/install.sh"
chmod +x "$DIST_DIR/setup-mno-open.sh" "$DIST_DIR/install.sh"

# 4. Copiar o catálogo e a identidade visual pública
echo "📄 Copiando ferramentas.html e logo..."
cp "$BASE_DIR/1_codigo_fonte/ferramentas.html" "$DIST_DIR/"
cp "$BASE_DIR/1_codigo_fonte/setup-mno-logo.svg" "$DIST_DIR/"

# 5. Compactar os arquivos x86 (SEM SENHA - Código Aberto Puro)
echo -e "${amarelo}📦 Compactando arquivos x86 (sem senha)...${reset}"
cd "$BASE_DIR/1_codigo_fonte/x86"
# Criação dos symlinks essenciais dentro da pasta antes de zipar
(cd SetupLowCodeMno && ln -sf install.sh install && ln -sf setupmno_control.sh setupmno_control)
zip -q -r "$DIST_DIR/x86/SetupLowCodeMno.zip" SetupLowCodeMno
tar -czf "$DIST_DIR/x86/SetupLowCodeMno.tar.gz" SetupLowCodeMno
cd "$BASE_DIR/2_empacotador"

# 6. Compactar os arquivos ARM (SEM SENHA - Código Aberto Puro)
echo -e "${amarelo}📦 Compactando arquivos ARM (sem senha)...${reset}"
cd "$BASE_DIR/1_codigo_fonte/arm"
# Criação dos symlinks essenciais dentro da pasta antes de zipar
(cd SetupLowCodeMno && ln -sf install.sh install && ln -sf setupmno_control.sh setupmno_control)
zip -q -r "$DIST_DIR/arm/SetupLowCodeMno.zip" SetupLowCodeMno
tar -czf "$DIST_DIR/arm/SetupLowCodeMno.tar.gz" SetupLowCodeMno
cd "$BASE_DIR/2_empacotador"

# 7. Gerar hashes de integridade SHA256 para auditoria pública
echo -e "${amarelo}🔐 Gerando hashes de integridade SHA256 públicos...${reset}"
cd "$DIST_DIR"
find . -type f ! -name 'SHA256SUMS.txt' ! -path '*/backup/*' -exec sha256sum {} + > SHA256SUMS.txt
cd "$BASE_DIR/2_empacotador"

echo -e "${verde}=================================================================${reset}"
echo -e "${verde}✅ DISTRIBUIÇÃO OPEN-SOURCE GERADA COM SUCESSO!${reset}"
echo -e "${verde}=================================================================${reset}"
echo -e "Os pacotes abertos estão prontos na pasta '3B_distribuicao_opensource':"
echo -e " - ${azul}3B_distribuicao_opensource/setup-mno-open.sh${reset} (Instalador rápido)"
echo -e " - ${azul}3B_distribuicao_opensource/install.sh${reset} (Alias curl | bash)"
echo -e " - ${azul}3B_distribuicao_opensource/x86/SetupLowCodeMno.zip${reset} (Pacote x86 sem senha)"
echo -e " - ${azul}3B_distribuicao_opensource/arm/SetupLowCodeMno.zip${reset} (Pacote ARM sem senha)"
echo -e " - ${azul}3B_distribuicao_opensource/SHA256SUMS.txt${reset} (Hashes de auditoria)"
echo -e "${amarelo}💡 Zero chamadas a compiladores SHC. Zero data de expiração.${reset}"

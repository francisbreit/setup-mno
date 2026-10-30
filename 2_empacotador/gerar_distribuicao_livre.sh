#!/bin/bash
# ==============================================================================
# EMPACOTADOR SETUP MNO - GERAÇÃO DA DISTRIBUIÇÃO LIVRE (ACESSO PRO LIBERADO)
# ==============================================================================

# Cores para o terminal
verde="\e[32m"
amarelo="\e[33m"
reset="\e[0m"

# Define a pasta raiz do projeto de forma absoluta e robusta
BASE_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

echo -e "${amarelo}🚀 Iniciando empacotamento da versão LIVRE (Setup MNO - Distribuição Livre)...${reset}"

# 0. Backup do conteúdo atual de 3A_distribuicao_livre antes de limpar
BACKUP_DIR="$BASE_DIR/3A_distribuicao_livre/backup"
mkdir -p "$BACKUP_DIR"
if ls "$BASE_DIR/3A_distribuicao_livre/"* 1>/dev/null 2>&1; then
    echo "💾 Criando backup do empacotamento livre anterior..."
    rm -rf "$BACKUP_DIR"/*
    find "$BASE_DIR/3A_distribuicao_livre/" -maxdepth 1 -mindepth 1 ! -name 'backup' -exec cp -r {} "$BACKUP_DIR/" \;
    echo "💾 Backup salvo em 3A_distribuicao_livre/backup/"
fi

# 1. Limpeza da pasta 3A_distribuicao_livre (preservando pasta backup)
echo "🧹 Limpando a pasta 3A_distribuicao_livre..."
find "$BASE_DIR/3A_distribuicao_livre/" -maxdepth 1 -mindepth 1 ! -name 'backup' -exec rm -rf {} +
mkdir -p "$BASE_DIR/3A_distribuicao_livre/x86"
mkdir -p "$BASE_DIR/3A_distribuicao_livre/arm"

# 2. Copiar os setup-mno.sh e setup-mno-oracle.sh (Texto puro)
echo "📄 Copiando setup-mno.sh e setup-mno-oracle.sh..."
cp "$BASE_DIR/1_codigo_fonte/setup-mno.sh" "$BASE_DIR/3A_distribuicao_livre/"
cp "$BASE_DIR/1_codigo_fonte/setup-mno-oracle.sh" "$BASE_DIR/3A_distribuicao_livre/"

# 3. Copiar o catálogo e a identidade visual
echo "📄 Copiando ferramentas.html (catálogo atual)..."
cp "$BASE_DIR/1_codigo_fonte/ferramentas.html" "$BASE_DIR/3A_distribuicao_livre/"

echo "🎨 Copiando a identidade visual pública do Setup MNO..."
cp "$BASE_DIR/1_codigo_fonte/setup-mno-logo.svg" "$BASE_DIR/3A_distribuicao_livre/"

# 3.1 Sincronização e Validação do Control Center e Manifestos Runtime
echo -e "${amarelo}⚙️  Sincronizando Control Center, manifestos runtime e ancoragens SHC...${reset}"
bash "$BASE_DIR/1_codigo_fonte/setupmno-control/generate-installers.sh" || {
    echo -e "\e[31m❌ ERRO CRÍTICO: Falha na geração dos manifestos e instaladores do Control Center. Abortando empacotamento livre!\e[0m" >&2
    exit 1
}

# 3.2 Ancoragem das releases aos scripts de distribuição livre
echo -e "${amarelo}⚓ Vinculando âncoras de integridade aos scripts de distribuição livre...${reset}"
python3 -B "$BASE_DIR/1_codigo_fonte/setupmno-control/shc_boundary.py" bind \
    --start-script "$BASE_DIR/1_codigo_fonte/distribuicao_livre/start_full.sh" \
    --release "$BASE_DIR/1_codigo_fonte/x86/SetupLowCodeMno/.control-package/release.json" >/dev/null
python3 -B "$BASE_DIR/1_codigo_fonte/setupmno-control/shc_boundary.py" bind \
    --start-script "$BASE_DIR/1_codigo_fonte/distribuicao_livre/start_arm_full.sh" \
    --release "$BASE_DIR/1_codigo_fonte/arm/SetupLowCodeMno/.control-package/release.json" >/dev/null

# 4. Zipar os ficheiros x86 com senha
echo -e "${amarelo}📦 Compactando arquivos x86...${reset}"
cd "$BASE_DIR/1_codigo_fonte/x86"
zip -q -P "F@aioDv6740bR2021" -r "$BASE_DIR/3A_distribuicao_livre/x86/SetupLowCodeMno.zip" SetupLowCodeMno
cd "$BASE_DIR/2_empacotador"

# 5. Zipar os ficheiros ARM com senha
echo -e "${amarelo}📦 Compactando arquivos ARM...${reset}"
cd "$BASE_DIR/1_codigo_fonte/arm"
zip -q -P "F@aioDv6740bR2021" -r "$BASE_DIR/3A_distribuicao_livre/arm/SetupLowCodeMno.zip" SetupLowCodeMno
cd "$BASE_DIR/2_empacotador"

data_expiracao=$(date +'%d/%m/%Y' -d "+365 days")

# 6. Compilar os Gatilhos Livres (start_full da distribuição livre) com SHC
echo -e "${amarelo}🔐 Compilando binário start_full_7d_a0940b5 LIVRE (x86 - estático)...${reset}"
LDFLAGS="-static" shc -r -e $data_expiracao -m "Este instalador expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o "$BASE_DIR/3A_distribuicao_livre/start_full_7d_a0940b5" -f "$BASE_DIR/1_codigo_fonte/distribuicao_livre/start_full.sh"

echo -e "${amarelo}🔐 Compilando binário start_full_arm_7d_6408ae6 LIVRE (ARM - Cross Compile - estático)...${reset}"
LDFLAGS="-static" CC=aarch64-linux-gnu-gcc shc -r -e $data_expiracao -m "Este instalador expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o "$BASE_DIR/3A_distribuicao_livre/start_full_arm_7d_6408ae6" -f "$BASE_DIR/1_codigo_fonte/distribuicao_livre/start_arm_full.sh"

# Garante permissões de execução
chmod +x "$BASE_DIR/3A_distribuicao_livre/start_full_7d_a0940b5" "$BASE_DIR/3A_distribuicao_livre/start_full_arm_7d_6408ae6"

# Limpeza dos ficheiros lixo .x.c gerados pelo SHC
rm -f "$BASE_DIR/1_codigo_fonte/distribuicao_livre/"*.x.c

echo -e "${verde}✅ Distribuição LIVRE gerada com sucesso!${reset}"
echo -e "Acesse a pasta '3A_distribuicao_livre' para verificar ou disponibilizar os arquivos."

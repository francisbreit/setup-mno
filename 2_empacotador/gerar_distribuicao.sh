#!/bin/bash
# ==============================================================================
# EMPACOTADOR SETUP MNO - GERAÇÃO DA DISTRIBUIÇÃO AUTOMÁTICA
# ==============================================================================

# Cores para o terminal
verde="\e[32m"
amarelo="\e[33m"
reset="\e[0m"

# Define a pasta raiz do projeto de forma absoluta e robusta
BASE_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

echo -e "${amarelo}🚀 Iniciando empacotamento da versão (Setup MNO)...${reset}"

# 0. Backup do conteúdo atual antes de limpar
BACKUP_DIR="$BASE_DIR/3_distribuicao/backup"
mkdir -p "$BACKUP_DIR"
if ls "$BASE_DIR/3_distribuicao/"* 1>/dev/null 2>&1; then
    echo "💾 Criando backup do empacotamento anterior..."
    rm -rf "$BACKUP_DIR"/*
    # Copiar tudo EXCETO a pasta backup
    find "$BASE_DIR/3_distribuicao/" -maxdepth 1 -mindepth 1 ! -name 'backup' -exec cp -r {} "$BACKUP_DIR/" \;
    echo "💾 Backup salvo em 3_distribuicao/backup/"
fi

# 1. Limpeza do ambiente de distribuição (preservando pasta backup)
echo "🧹 Limpando a pasta 3_distribuicao..."
find "$BASE_DIR/3_distribuicao/" -maxdepth 1 -mindepth 1 ! -name 'backup' -exec rm -rf {} +
mkdir -p "$BASE_DIR/3_distribuicao/x86"
mkdir -p "$BASE_DIR/3_distribuicao/arm"

# 2. Copiar os setup-mno.sh e setup-mno-oracle.sh (Texto puro)
echo "📄 Copiando setup-mno.sh e setup-mno-oracle.sh..."

# Usa o caminho absoluto garantido
cp "$BASE_DIR/1_codigo_fonte/setup-mno.sh" "$BASE_DIR/3_distribuicao/"
cp "$BASE_DIR/1_codigo_fonte/setup-mno-oracle.sh" "$BASE_DIR/3_distribuicao/"

# 3. Copiar ferramentas.html para 3_distribuicao
echo "📄 Copiando ferramentas.html..."
cp "$BASE_DIR/ferramentas.html" "$BASE_DIR/3_distribuicao/"
echo "📄 Copiando ferramentas2.html..."
cp "$BASE_DIR/1_codigo_fonte/ferramentas2.html" "$BASE_DIR/3_distribuicao/"

# 4. Zipar os ficheiros x86 com senha
echo -e "${amarelo}📦 Compactando arquivos x86...${reset}"
cd "$BASE_DIR/1_codigo_fonte/x86"
zip -q -P "F@aioDv6740bR2021" -r "$BASE_DIR/3_distribuicao/x86/SetupLowCodeMno.zip" SetupLowCodeMno
cd "$BASE_DIR/2_empacotador"

# 5. Zipar os ficheiros ARM com senha
echo -e "${amarelo}📦 Compactando arquivos ARM...${reset}"
cd "$BASE_DIR/1_codigo_fonte/arm"
zip -q -P "F@aioDv6740bR2021" -r "$BASE_DIR/3_distribuicao/arm/SetupLowCodeMno.zip" SetupLowCodeMno
cd "$BASE_DIR/2_empacotador"

data_expiracao=$(date +'%d/%m/%Y' -d "+365 days")

# 6. Compilar os Gatilhos (start_full) com SHC
echo -e "${amarelo}🔐 Compilando binário start_full_7d_a0940b5 (x86 - estático)...${reset}"
LDFLAGS="-static" shc -r -e $data_expiracao -m "Este instalador expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o "$BASE_DIR/3_distribuicao/start_full_7d_a0940b5" -f "$BASE_DIR/1_codigo_fonte/x86/start_full.sh"

echo -e "${amarelo}🔐 Compilando binário start_full_arm_7d_6408ae6 (ARM - Cross Compile - estático)...${reset}"
# Usa o compilador cruzado para garantir que o binário gerado rode em processadores Ampere/Raspberry
LDFLAGS="-static" CC=aarch64-linux-gnu-gcc shc -r -e $data_expiracao -m "Este instalador expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o "$BASE_DIR/3_distribuicao/start_full_arm_7d_6408ae6" -f "$BASE_DIR/1_codigo_fonte/arm/start_arm_full.sh"

# Limpeza dos ficheiros lixo .x.c gerados pelo SHC
rm -f "$BASE_DIR/1_codigo_fonte/x86/"*.x.c
rm -f "$BASE_DIR/1_codigo_fonte/arm/"*.x.c

echo -e "${verde}✅ Distribuição gerada com sucesso!${reset}"
echo -e "Acesse a pasta '3_distribuicao' para fazer o upload dos arquivos para o servidor ativa2."

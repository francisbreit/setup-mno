#!/usr/bin/bash
# Gerado via Workflow MiMo - 2026-07-14 23:56:23
VERSIONSETUP="4.93.0"
umask 077
# Garantir execução como root
if [ "$EUID" -ne 0 ]; then
    echo "ERRO: Este script deve ser executado como root." >&2
    exit 1
fi

export NEWT_COLORS='
root=,white
window=,black
border=white,black
textbox=white,black
button=black,white
'

clear

# Função para enviar HTTP POST e validar a resposta
function verificar_cliente() {
    local EMAIL="$1"
    local SENHA="$2"
    local URL="https://hook45.manualnegocioonline.com.br/webhook/valida-cliente-mno"

    # Envia o HTTP POST
    RESPOSTA=$(curl -s -X POST -H "Content-Type: application/json" \
        -d "{\"email\":\"$EMAIL\",\"senha\":\"$SENHA\"}" "$URL")

    # Verifica se houve falha no curl
    if [ $? -ne 0 ]; then
        whiptail --msgbox "Estamos com um problema temporário. Por favor, tente mais tarde. Pressione ENTER para sair" 20 78
        echo "Estamos com um problema temporário. Por favor, tente mais tarde." >&2
        exit 4
    fi

    # Extrai valores do JSON usando jq (instalado anteriormente)
    SITUACAO=$(echo "$RESPOSTA" | jq -r '.situacao_cliente')
    PLANO=$(echo "$RESPOSTA" | jq -r '.plano')
    DATAAQ=$(echo "$RESPOSTA" | jq -r '.dataaq')
    DOWNLOADS=$(echo "$RESPOSTA" | jq -r '.downloads // 0')  # Default 0 se não existir
    EMAIL=$(echo "$RESPOSTA" | jq -r '.email')
    SENHA=$(echo "$RESPOSTA" | jq -r '.senha')

    DATA_FORMATADA=$(echo "$DATAAQ" | awk -F/ '{print $2 "/" $1 "/" $3}')

    # Converter datas para timestamp
    DATAAQ_TIMESTAMP=$(date -d "$DATA_FORMATADA" +%s)
    DATAHOJE_TIMESTAMP=$(date +%s)

    # Calcular diferença em dias: hoje - data de aquisição
    DIFERENCA_SEGUNDOS=$(( DATAHOJE_TIMESTAMP - DATAAQ_TIMESTAMP ))
    DIASDECORRIDOS=$(( DIFERENCA_SEGUNDOS / 86400 ))

    case "$SITUACAO" in
    "cliente_regularizado")
        if [ "$PLANO" = "trial pro" ] || [ "$PLANO" = "trial" ]; then
            if [ "$DOWNLOADS" -ge 3 ]; then
                whiptail --title "ERRO: Número máximo de instalações atingido" --msgbox "Atenção: Você superou o número máximo de 3 instalações (downloads) da versão trial ou trial pro.\n\nEntre em contato com o nosso Suporte Técnico (apenas WhatsApp):\n\nWhatsApp: +55 (11)96816-2690.\n\nPressione ENTER para sair" 22 78
                cd /
                cd
                sudo rm start_full* 2>/dev/null || true
                sudo rm start_start* 2>/dev/null || true
                sudo rm -r SetupLowCodeMnoStart 2>/dev/null || true
                sudo rm setup-mno.sh 2>/dev/null || true
                exit 6
            fi

            if [ "$DIASDECORRIDOS" -ge 8 ]; then
                whiptail --title "ERRO: Período de teste de 7 dias expirado!" --msgbox "Atenção: Passaram-se os 7 dias de testes da versão trial pro.\n\nEntre em contato com o nosso Suporte Técnico (apenas WhatsApp):\n\nWhatsApp: +55 (11)96816-2690.\n\nPressione ENTER para sair" 22 78
                cd /
                cd
                sudo rm start_full* 2>/dev/null || true
                sudo rm start_start* 2>/dev/null || true
                sudo rm -r SetupLowCodeMnoStart 2>/dev/null || true
                sudo rm setup-mno.sh 2>/dev/null || true
                exit 6
            fi
        fi
        return 0
        ;;
    "cliente_inexistente")
        whiptail --title "ERRO NO LOGIN" --msgbox "Atenção: Email e/ou senha incorretos. Pressione ENTER para sair." 20 78
        cd /
        cd
        sudo rm start_full* 2>/dev/null || true
        sudo rm start_start* 2>/dev/null || true
        sudo rm -r SetupLowCodeMnoStart 2>/dev/null || true
        sudo rm setup-mno.sh 2>/dev/null || true
        exit 1
        ;;
    "cliente_inadimplente")
        whiptail --title "ERRO" --msgbox "Atenção: Problema com o pagamento.\n\nEntre em contato com o nosso Suporte Técnico (apenas WhatsApp):\n\nWhatsAPP: +55 (11)96816-2690.\n\nPressione ENTER para sair" 20 78
        cd /
        cd
        sudo rm start_full* 2>/dev/null || true
        sudo rm start_start* 2>/dev/null || true
        sudo rm -r SetupLowCodeMnoStart 2>/dev/null || true
        sudo rm setup-mno.sh 2>/dev/null || true
        exit 2
        ;;
    "cliente_expirado")
        whiptail --title "ERRO: Conta Expirada" --msgbox "Atenção: Sua conta expirou.\n\nEntre em contato com o nosso Suporte Técnico (apenas WhatsApp):\n\nWhatsAPP: +55 (11)96816-2690.\n\nPressione ENTER para sair" 20 78
        cd /
        cd
        sudo rm start_full* 2>/dev/null || true
        sudo rm start_start* 2>/dev/null || true
        sudo rm -r SetupLowCodeMnoStart 2>/dev/null || true
        sudo rm setup-mno.sh 2>/dev/null || true
        exit 3
        ;;
    *)
        whiptail --title "ERRO: Falha no Sistema" --msgbox "Resposta inesperada do servidor. Tente novamente mais tarde." 20 78
        cd /
        cd
        sudo rm start_full* 2>/dev/null || true
        sudo rm start_start* 2>/dev/null || true
        sudo rm -r SetupLowCodeMnoStart 2>/dev/null || true
        sudo rm setup-mno.sh 2>/dev/null || true
        exit 5
        ;;
    esac
}

# Solicita email e senha
EMAIL=$(whiptail --title "1/2 - EMAIL DE ACESSO DO SETUPMNO" --inputbox "Digite seu e-mail:" 8 60 3>&1 1>&2 2>&3)
if [ $? -ne 0 ]; then exit 1; fi

SENHA=$(whiptail --title "2/2 - SENHA DE ACESSO DO SETUPMNO" --passwordbox "Digite sua senha:" 8 60 3>&1 1>&2 2>&3)
if [ $? -ne 0 ]; then exit 1; fi

# Valida o cliente antes de prosseguir
verificar_cliente "$EMAIL" "$SENHA"
unset SENHA

# Prossegue apenas se o cliente estiver regularizado
clear

control_state_error="/tmp/setupmno-control-state-error.log"
: >"$control_state_error"

{
echo -e "XXX\n5\nINSTALANDO SETUPMNO 1/8 \nXXX"

cd /usr/bin
cat > setup-mno << EOL
#!/usr/bin/bash
cd /root/SetupLowCodeMno
./install
$SHELL
EOL

chmod +x setup-mno  >/dev/null 2>&1

cd /
cd
sudo rm -r SetupLowCodeMno >/dev/null 2>&1
apt-get install sudo -y >/dev/null 2>&1
sudo apt-get update -y >/dev/null 2>&1
sudo apt-get upgrade -y >/dev/null 2>&1
echo -e "XXX\n25\nSETUPMNO: DESCOMPACTANDO ARQUIVOS 1/8 - CONCLUIDO \nXXX"
echo -e "XXX\n25\nAGUARDE: ISSO PODE LEVAR ALGUNS MINUTOS... 2/8 \nXXX"

# ------------------------------------------------------------
# INÍCIO DAS MODIFICAÇÕES PARA DEBIAN 13+
# ------------------------------------------------------------
# ------------------------------------------------------------
# GARANTIR AMBIENTE ADEQUADO (SUBSTITUI COMPLETAMENTE A SEÇÃO)
# ------------------------------------------------------------

# 1. Remover instalação antiga e garantir diretório limpo
cd /root 2>/dev/null || true
rm -rf SetupLowCodeMno
rm -f SetupLowCodeMno.zip

echo -e "XXX\n25\nSETUPMNO: INSTALANDO DEPENDÊNCIAS... 2/8 \nXXX"

# 2. Atualizar lista de pacotes e instalar dependências essenciais
apt-get update -y >/dev/null 2>&1
apt-get install -y wget curl unzip zip jq build-essential >/dev/null 2>&1
if [ $? -ne 0 ]; then
    echo "Falha na instalação das dependências." >&2
    exit 1
fi

echo -e "XXX\n30\nSETUPMNO: DEPENDÊNCIAS INSTALADAS. VERIFICANDO SHC... 2/8 \nXXX"

# 3. Instalar shc (se necessário)
if ! command -v shc &>/dev/null; then
    echo -e "XXX\n35\nSETUPMNO: COMPILANDO SHC (PODE LEVAR ALGUNS SEGUNDOS)... 2/8 \nXXX"
    cd /tmp
    wget -q https://github.com/neurobin/shc/archive/refs/tags/4.0.3.tar.gz -O shc.tar.gz
    tar xzf shc.tar.gz
    cd shc-4.0.3
    ./configure >/dev/null 2>&1
    make >/dev/null 2>&1
    make install >/dev/null 2>&1
    cd /
    rm -rf /tmp/shc-4.0.3 /tmp/shc.tar.gz
    hash -r
fi

echo -e "XXX\n45\nSETUPMNO: BAIXANDO ARQUIVOS... 2/8 \nXXX"

# 4. Download do ZIP com verificação
cd /root
wget -q -O SetupLowCodeMno.zip "https://manualnegocioonline.com.br/downloads/mno/x86/SetupLowCodeMno.zip"
if [ $? -ne 0 ] || [ ! -s SetupLowCodeMno.zip ]; then
    echo -e "XXX\n100\nERRO: FALHA NO DOWNLOAD. PRESSIONE ENTER PARA SAIR.\nXXX"
    sleep 3
    exit 1
fi

echo -e "XXX\n50\nSETUPMNO: EXTRAINDO ARQUIVOS... 2/8 \nXXX"

# 5. Extração com validação
unzip -o -P F@aioDv6740bR2021 SetupLowCodeMno.zip >/dev/null 2>&1
if [ $? -ne 0 ] || [ ! -d SetupLowCodeMno ]; then
    echo -e "XXX\n100\nERRO: FALHA NA EXTRAÇÃO. PRESSIONE ENTER PARA SAIR.\nXXX"
    sleep 3
    exit 1
fi
rm -f SetupLowCodeMno.zip

control_package="/root/SetupLowCodeMno/.control-package"
control_target="/root/SetupLowCodeMno/.control"
if [ ! -s "$control_package/release.json" ] ||
   [ ! -s "$control_package/catalog.json" ]; then
    printf 'O pacote não contém o manifesto e o catálogo runtime do Control Center.\n' >"$control_state_error"
    exit 40
fi
control_schema=$(jq -r '.schemaVersion // 0' "$control_package/release.json" 2>/dev/null)
control_version=$(jq -r '.setupVersion // empty' "$control_package/release.json" 2>/dev/null)
control_arch=$(jq -r '.architecture // empty' "$control_package/release.json" 2>/dev/null)
control_expected_sha=$(jq -r '.catalogSHA256 // empty' "$control_package/release.json" 2>/dev/null)
control_actual_sha=$(sha256sum "$control_package/catalog.json" | awk '{print $1}')
if [ "$control_schema" != "1" ] ||
   [ "$control_version" != "$VERSIONSETUP" ] ||
   [ "$control_arch" != "amd64" ] ||
   [ -z "$control_expected_sha" ] ||
   [ "$control_expected_sha" != "$control_actual_sha" ]; then
    printf 'O manifesto runtime do Control Center é inválido ou não corresponde ao Setup MNO v%s (amd64).\n' \
        "$VERSIONSETUP" >"$control_state_error"
    exit 41
fi
mkdir -p "$control_target"
install -m 0644 "$control_package/catalog.json" "$control_target/catalog.json.tmp"
install -m 0644 "$control_package/release.json" "$control_target/release.json.tmp"
mv -f "$control_target/catalog.json.tmp" "$control_target/catalog.json"
mv -f "$control_target/release.json.tmp" "$control_target/release.json"
rm -rf "$control_package"

cd SetupLowCodeMno || exit 1

echo -e "XXX\n50\nINSTALANDO SETUPMNO 2/8 - CONCLUÍDO \nXXX"
# ------------------------------------------------------------
# FIM DAS MODIFICAÇÕES
# ------------------------------------------------------------

# ... (o restante do script permanece inalterado)

# Diretório onde as informações do trial serão armazenadas
TRIAL_DIR="/root/SetupLowCodeMno/.meu_app_trial"

# Arquivo que conterá as informações do trial
TRIAL_FILE="$TRIAL_DIR/trial_info"


# Calcular dias restantes do trial
DATA_FORMATADA=$(echo "$DATAAQ" | awk -F/ '{print $2 "/" $1 "/" $3}')
DATAAQ_TIMESTAMP=$(date -d "$DATA_FORMATADA" +%s)
DATAHOJE_TIMESTAMP=$(date +%s)

DIFERENCA_SEGUNDOS=$(( DATAAQ_TIMESTAMP + 7*86400 - DATAHOJE_TIMESTAMP ))
#DAYS_TRIAL=$(( DIFERENCA_SEGUNDOS / 86400 ))
DAYS_TRIAL=$(( (DIFERENCA_SEGUNDOS / 86400) + 1 ))

# Garante que não mostre negativo
if [ "$DAYS_TRIAL" -lt 0 ]; then
    DAYS_TRIAL=0
fi


# Verifica se o diretório já existe
if [ ! -d "$TRIAL_DIR" ]; then
    mkdir -p "$TRIAL_DIR"
fi

# Grava a data de instalação e o período de trial no arquivo
#echo "DATA_INSTALACAO=$(date +%Y-%m-%d)" > "$TRIAL_FILE"
echo "DATA_INSTALACAO=$DATAAQ" >> "$TRIAL_FILE"
echo "DAYS_TRIAL=$DAYS_TRIAL" >> "$TRIAL_FILE"
echo "PLANO=\"$PLANO\"" >> "$TRIAL_FILE"


if [ "$PLANO" = "pro" ] || [ "$PLANO" == "free" ] || [ "$PLANO" == "free1" ] || [ "$PLANO" == "free2" ] ; then

data_expiracao=$(date +'%d/%m/%Y' -d "+7 days")
    else
data_expiracao=$(date -d "$(echo $DATAAQ | awk -F/ '{print $2 "/" $1 "/" $3}') +8 days" +'%d/%m/%Y')
    fi

#data_expiracao=$(date +'%d/%m/%Y' -d "+7 days")
#data_expiracao=$(date -d "$(echo $DATAAQ | awk -F/ '{print $2 "/" $1 "/" $3}') +8 days" +'%d/%m/%Y')

shc -e $data_expiracao -m "Seu periodo de uso desta versão do SetupMno expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o affine -f affine.sh
rm affine.sh
rm affine.sh.x.c
if [ "$PLANO" == "free" ]; then
rm affine
fi
if [[ ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm affine
fi
echo -e "XXX\n51\nINSTALANDO SETUPMNO 3/8 \nXXX"
shc -e $data_expiracao -m "Seu periodo de uso desta versão do SetupMno expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o anythingllm -f anythingllm.sh
rm anythingllm.sh
rm anythingllm.sh.x.c
if [[ ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm anythingllm
fi
echo -e "XXX\n52\nINSTALANDO SETUPMNO 3/8 \nXXX"
shc -e $data_expiracao -m "Seu periodo de uso desta versão do SetupMno expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o clickhouse -f clickhouse.sh
rm clickhouse.sh
rm clickhouse.sh.x.c
if [[ ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm clickhouse
fi
echo -e "XXX\n52.5\nINSTALANDO SETUPMNO 3/8 \nXXX"
shc -e $data_expiracao -m "Seu periodo de uso desta versão do SetupMno expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o codeserver -f codeserver.sh
rm codeserver.sh
rm codeserver.sh.x.c
if [[ ("$PLANO" == "free") || ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm codeserver
fi
echo -e "XXX\n53\nINSTALANDO SETUPMNO 3/8 \nXXX"
shc -e $data_expiracao -m "Seu periodo de uso desta versão do SetupMno expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o directus -f directus.sh
rm directus.sh
rm directus.sh.x.c
if [[ ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm directus
fi
echo -e "XXX\n53.5\nINSTALANDO SETUPMNO 3/8 \nXXX"
shc -e $data_expiracao -m "Seu periodo de uso desta versão do SetupMno expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o docmost -f docmost.sh
rm docmost.sh
rm docmost.sh.x.c
if [[ ("$PLANO" == "free") || ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm docmost
fi
echo -e "XXX\n54\nINSTALANDO SETUPMNO 3/8 \nXXX"
shc -e $data_expiracao -m "Seu periodo de uso desta versão do SetupMno expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o documenso -f documenso.sh
rm documenso.sh
rm documenso.sh.x.c
if [[ ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm documenso
fi
if [ "$PLANO" == "free" ]; then
rm documenso
fi
echo -e "XXX\n55\nINSTALANDO SETUPMNO 3/8 \nXXX"
shc -e $data_expiracao -m "Seu periodo de uso desta versão do SetupMno expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o docuseal -f docuseal.sh
rm docuseal.sh
rm docuseal.sh.x.c
if [ "$PLANO" == "free" ]; then
rm docuseal
fi
if [[ ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm docuseal
fi

shc -e $data_expiracao -m "Seu periodo de uso desta versão do SetupMno expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o duplicati -f duplicati.sh
rm duplicati.sh
rm duplicati.sh.x.c
if [[ ("$PLANO" == "free") || ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm duplicati
fi

echo -e "XXX\n56\nINSTALANDO SETUPMNO 3/8 \nXXX"
shc -e $data_expiracao -m "Seu periodo de uso desta versão do SetupMno expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o easyappointments -f easyappointments.sh
rm easyappointments.sh
rm easyappointments.sh.x.c
if [ "$PLANO" == "free" ]; then
rm easyappointments
fi
if [[ ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm easyappointments
fi
echo -e "XXX\n57\nINSTALANDO SETUPMNO 3/8 \nXXX"
shc -e $data_expiracao -m "Seu periodo de uso desta versão do SetupMno expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o excalidraw -f excalidraw.sh
rm excalidraw.sh
rm excalidraw.sh.x.c
if [[ ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm excalidraw
fi
echo -e "XXX\n58\nINSTALANDO SETUPMNO 3/8 \nXXX"
shc -e $data_expiracao -m "Seu periodo de uso desta versão do SetupMno expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o firecrawl -f firecrawl.sh
rm firecrawl.sh
rm firecrawl.sh.x.c
if [[ ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm firecrawl
fi
echo -e "XXX\n59\nINSTALANDO SETUPMNO 3/8 \nXXX"
shc -e $data_expiracao -m "Seu periodo de uso desta versão do SetupMno expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o focalboard -f focalboard.sh
rm focalboard.sh
rm focalboard.sh.x.c
if [[ ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm focalboard
fi
echo -e "XXX\n60\nINSTALANDO SETUPMNO 3/8 \nXXX"
shc -e $data_expiracao -m "Seu periodo de uso desta versão do SetupMno expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o freshrss -f freshrss.sh
rm freshrss.sh
rm freshrss.sh.x.c
if [[ ("$PLANO" == "free") || ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm freshrss
fi
echo -e "XXX\n61\nINSTALANDO SETUPMNO 3/8 \nXXX"
shc -e $data_expiracao -m "Seu periodo de uso desta versão do SetupMno expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o filebrowser -f filebrowser.sh
rm filebrowser.sh
rm filebrowser.sh.x.c
if [[ ("$PLANO" == "free") || ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm filebrowser
fi
echo -e "XXX\n62\nINSTALANDO SETUPMNO 3/8 \nXXX"
shc -e $data_expiracao -m "Seu periodo de uso desta versão do SetupMno expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o formbricks -f formbricks.sh
rm formbricks.sh
rm formbricks.sh.x.c
if [[ ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm formbricks
fi
echo -e "XXX\n61\nINSTALANDO SETUPMNO 3/8 \nXXX"
shc -e $data_expiracao -m "Seu periodo de uso desta versão do SetupMno expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o glpi -f glpi.sh
rm glpi.sh
rm glpi.sh.x.c
if [[ ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm glpi
fi
echo -e "XXX\n62\nINSTALANDO SETUPMNO 3/8 \nXXX"
shc -e $data_expiracao -m "Seu periodo de uso desta versão do SetupMno expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o humhub -f humhub.sh
rm humhub.sh
rm humhub.sh.x.c
if [ "$PLANO" == "free" ]; then
rm humhub
fi
if [[ ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm humhub
fi
echo -e "XXX\n62.5\nINSTALANDO SETUPMNO 3/8 \nXXX"
shc -e $data_expiracao -m "Seu periodo de uso desta versão do SetupMno expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o keycloak -f keycloak.sh
rm keycloak.sh
rm keycloak.sh.x.c
if [[ ("$PLANO" == "free") || ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm keycloak
fi
echo -e "XXX\n63\nINSTALANDO SETUPMNO 3/8 \nXXX"
shc -e $data_expiracao -m "Seu periodo de uso desta versão do SetupMno expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o krayincrm -f krayincrm.sh
rm krayincrm.sh
rm krayincrm.sh.x.c
if [ "$PLANO" == "free" ]; then
rm krayincrm
fi
if [[ ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm krayincrm
fi
echo -e "XXX\n64\nINSTALANDO SETUPMNO 3/8 \nXXX"
shc -e $data_expiracao -m "Seu periodo de uso desta versão do SetupMno expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o karakeep -f karakeep.sh
rm karakeep.sh
rm karakeep.sh.x.c
if [[ ("$PLANO" == "free") || ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm karakeep
fi
echo -e "XXX\n65\nINSTALANDO SETUPMNO 3/8 \nXXX"
shc -e $data_expiracao -m "Seu periodo de uso desta versão do SetupMno expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o lowcoder -f lowcoder.sh
rm lowcoder.sh
rm lowcoder.sh.x.c
if [[ ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm lowcoder
fi
echo -e "XXX\n65\nINSTALANDO SETUPMNO 3/8 \nXXX"
shc -e $data_expiracao -m "Seu periodo de uso desta versão do SetupMno expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o mattermost -f mattermost.sh
rm mattermost.sh
rm mattermost.sh.x.c
if [[ ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm mattermost
fi
echo -e "XXX\n66\nINSTALANDO SETUPMNO 3/8 \nXXX"
shc -e $data_expiracao -m "Seu periodo de uso desta versão do SetupMno expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o metabase -f metabase.sh
rm metabase.sh
rm metabase.sh.x.c
if [[ ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm metabase
fi
echo -e "XXX\n67\nINSTALANDO SETUPMNO 3/8 \nXXX"
shc -e $data_expiracao -m "Seu periodo de uso desta versão do SetupMno expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o mongodb -f mongodb.sh
rm mongodb.sh
rm mongodb.sh.x.c
if [[ ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm mongodb
fi
echo -e "XXX\n68\nINSTALANDO SETUPMNO 3/8 \nXXX"
shc -e $data_expiracao -m "Seu periodo de uso desta versão do SetupMno expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o moodle -f moodle.sh
rm moodle.sh
rm moodle.sh.x.c
if [ "$PLANO" == "free" ]; then
rm moodle
fi
if [[ ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm moodle
fi
echo -e "XXX\n69\nINSTALANDO SETUPMNO 3/8 \nXXX"
shc -e $data_expiracao -m "Seu periodo de uso desta versão do SetupMno expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o nginxproxymanager -f nginxproxymanager.sh
rm nginxproxymanager.sh
rm nginxproxymanager.sh.x.c
if [[ ("$PLANO" == "free") || ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm nginxproxymanager
fi
shc -e $data_expiracao -m "Seu periodo de uso desta versão do SetupMno expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o nextcloud -f nextcloud.sh
rm nextcloud.sh
rm nextcloud.sh.x.c
if [ "$PLANO" == "free" ]; then
rm nextcloud
fi
if [[ ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm nextcloud
fi
echo -e "XXX\n70\nINSTALANDO SETUPMNO 3/8 \nXXX"
shc -e $data_expiracao -m "Seu periodo de uso desta versão do SetupMno expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o ntfy -f ntfy.sh
rm ntfy.sh
rm ntfy.sh.x.c
if [[ ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm ntfy
fi
echo -e "XXX\n71\nINSTALANDO SETUPMNO 3/8 \nXXX"
shc -e $data_expiracao -m "Seu periodo de uso desta versão do SetupMno expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o odoo -f odoo.sh
rm odoo.sh
rm odoo.sh.x.c
if [[ ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm odoo
fi
echo -e "XXX\n72\nINSTALANDO SETUPMNO 3/8 \nXXX"
shc -e $data_expiracao -m "Seu periodo de uso desta versão do SetupMno expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o ollama -f ollama.sh
rm ollama.sh
rm ollama.sh.x.c
if [[ ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm ollama
fi
shc -e $data_expiracao -m "Seu periodo de uso desta versão do SetupMno expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o openwebui -f openwebui.sh
rm openwebui.sh
rm openwebui.sh.x.c
if [[ ("$PLANO" == "free") || ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm openwebui
fi
shc -e $data_expiracao -m "Seu periodo de uso desta versão do SetupMno expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o immich -f immich.sh
rm immich.sh
rm immich.sh.x.c
if [[ ("$PLANO" == "free") || ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm immich
fi
shc -e $data_expiracao -m "Seu periodo de uso desta versão do SetupMno expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o homeassistant -f homeassistant.sh
rm homeassistant.sh
rm homeassistant.sh.x.c
if [[ ("$PLANO" == "free") || ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm homeassistant
fi
shc -e $data_expiracao -m "Seu periodo de uso desta versão do SetupMno expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o hoppscotch -f hoppscotch.sh
rm hoppscotch.sh
rm hoppscotch.sh.x.c
if [[ ("$PLANO" == "free") || ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm hoppscotch
fi
shc -e $data_expiracao -m "Seu periodo de uso desta versão do SetupMno expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o localai -f localai.sh
rm localai.sh
rm localai.sh.x.c
if [[ ("$PLANO" == "free") || ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm localai
fi
echo -e "XXX\n73\nINSTALANDO SETUPMNO 3/8 \nXXX"
shc -e $data_expiracao -m "Seu periodo de uso desta versão do SetupMno expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o outline -f outline.sh
rm outline.sh
rm outline.sh.x.c
if [ "$PLANO" == "free" ]; then
rm outline
fi
if [[ ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm outline
fi
echo -e "XXX\n74\nINSTALANDO SETUPMNO 3/8 \nXXX"
shc -e $data_expiracao -m "Seu periodo de uso desta versão do SetupMno expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o openproject -f openproject.sh
rm openproject.sh
rm openproject.sh.x.c
if [ "$PLANO" == "free" ]; then
rm openproject
fi
if [[ ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm openproject
fi
echo -e "XXX\n75\nINSTALANDO SETUPMNO 3/8 \nXXX"
shc -e $data_expiracao -m "Seu periodo de uso desta versão do SetupMno expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o quepasa -f quepasa.sh
rm quepasa.sh
rm quepasa.sh.x.c
if [[ ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm quepasa
fi
echo -e "XXX\n76\nINSTALANDO SETUPMNO 3/8 \nXXX"
shc -e $data_expiracao -m "Seu periodo de uso desta versão do SetupMno expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o redisinsight -f redisinsight.sh
rm redisinsight.sh
rm redisinsight.sh.x.c
if [[ ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm redisinsight
fi
echo -e "XXX\n77\nINSTALANDO SETUPMNO 3/8 \nXXX"
shc -e $data_expiracao -m "Seu periodo de uso desta versão do SetupMno expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o stirlingpdf -f stirlingpdf.sh
rm stirlingpdf.sh
rm stirlingpdf.sh.x.c
if [[ ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm stirlingpdf
fi
echo -e "XXX\n78\nINSTALANDO SETUPMNO 3/8 \nXXX"
shc -e $data_expiracao -m "Seu periodo de uso desta versão do SetupMno expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o superset -f superset.sh
rm superset.sh
rm superset.sh.x.c
if [[ ("$PLANO" == "free") || ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm superset
fi
echo -e "XXX\n79\nINSTALANDO SETUPMNO 3/8 \nXXX"
shc -e $data_expiracao -m "Seu periodo de uso desta versão do SetupMno expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o strap -f strap.sh
rm strap.sh
rm strap.sh.x.c
if [[ ("$PLANO" == "free") || ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm strap
fi
echo -e "XXX\n79\nINSTALANDO SETUPMNO 3/8 \nXXX"
shc -e $data_expiracao -m "Seu periodo de uso desta versão do SetupMno expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o toojet -f toojet.sh
rm toojet.sh
rm toojet.sh.x.c
if [[ ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm toojet
fi
echo -e "XXX\n80\nINSTALANDO SETUPMNO 3/8 \nXXX"
shc -e $data_expiracao -m "Seu periodo de uso desta versão do SetupMno expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o triliumnext -f triliumnext.sh
rm triliumnext.sh
rm triliumnext.sh.x.c
if [[ ("$PLANO" == "free") || ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm triliumnext
fi
echo -e "XXX\n81\nINSTALANDO SETUPMNO 3/8 \nXXX"
shc -e $data_expiracao -m "Seu periodo de uso desta versão do SetupMno expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o twentycrm -f twentycrm.sh
rm twentycrm.sh
rm twentycrm.sh.x.c
if [ "$PLANO" == "free" ]; then
rm twentycrm
fi
if [[ ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm twentycrm
fi
echo -e "XXX\n81\nINSTALANDO SETUPMNO 4/8 \nXXX"
shc -e $data_expiracao -m "Seu periodo de uso desta versão do SetupMno expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o vaultwarden -f vaultwarden.sh
rm vaultwarden.sh
rm vaultwarden.sh.x.c
if [[ ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm vaultwarden
fi
echo -e "XXX\n82\nINSTALANDO SETUPMNO 4/8 \nXXX"
shc -e $data_expiracao -m "Seu periodo de uso desta versão do SetupMno expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o vikunja -f vikunja.sh
rm vikunja.sh
rm vikunja.sh.x.c
if [[ ("$PLANO" == "free") || ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm vikunja
fi
echo -e "XXX\n83\nINSTALANDO SETUPMNO 4/8 \nXXX"
shc -e $data_expiracao -m "Seu periodo de uso desta versão do SetupMno expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o woofedcrm -f woofedcrm.sh
rm woofedcrm.sh
rm woofedcrm.sh.x.c
if [[ ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm woofedcrm
fi
echo -e "XXX\n83\nINSTALANDO SETUPMNO 4/8 \nXXX"
shc -e $data_expiracao -m "Seu periodo de uso desta versão do SetupMno expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o wuzap -f wuzap.sh
rm wuzap.sh
rm wuzap.sh.x.c
if [[ ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm wuzap
fi
echo -e "XXX\n84\nINSTALANDO SETUPMNO 4/8 \nXXX"
shc -e $data_expiracao -m "Seu periodo de uso desta versão do SetupMno expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o yourl -f yourl.sh
rm yourl.sh
rm yourl.sh.x.c
if [[ ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm yourl
fi

shc -e $data_expiracao -m "Seu periodo de uso desta versão do SetupMno expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o wekan -f wekan.sh
rm wekan.sh
rm wekan.sh.x.c
if [[ ("$PLANO" == "free") || ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm wekan
fi

echo -e "XXX\n85\nINSTALANDO SETUPMNO 4/8 \nXXX"

shc -e $data_expiracao -m "Seu periodo de uso desta versão do SetupMno expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o grafana -f grafana.sh
rm grafana.sh
rm grafana.sh.x.c
if [[ ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm grafana
fi
echo -e "XXX\n86\nINSTALANDO SETUPMNO 4/8 \nXXX"
shc -e $data_expiracao -m "Seu periodo de uso desta versão do SetupMno expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o chatwoot -f chatwoot.sh
rm chatwoot.sh
rm chatwoot.sh.x.c
if [[ ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm chatwoot
fi
echo -e "XXX\n87\nINSTALANDO SETUPMNO 4/8 \nXXX"
shc -e $data_expiracao -m "Seu periodo de uso desta versão do SetupMno expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o evolutionapi -f evolutionapi.sh
rm evolutionapi.sh
rm evolutionapi.sh.x.c
if [[ ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm evolutionapi
fi
echo -e "XXX\n88\nINSTALANDO SETUPMNO 4/8 \nXXX"
shc -e $data_expiracao -m "Seu periodo de uso desta versão do SetupMno expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o evolution2api -f evolution2api.sh
rm evolution2api.sh
rm evolution2api.sh.x.c
echo -e "XXX\n89\nINSTALANDO SETUPMNO 4/8 \nXXX"
shc -e $data_expiracao -m "Seu periodo de uso desta versão do SetupMno expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o typebot -f typebot.sh
rm typebot.sh
rm typebot.sh.x.c
if [[ ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm typebot
fi
echo -e "XXX\n90\nINSTALANDO SETUPMNO 5/8 \nXXX"
shc -e $data_expiracao -m "Seu periodo de uso desta versão do SetupMno expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o n8n -f n8n.sh
rm n8n.sh
rm n8n.sh.x.c

shc -e $data_expiracao -m "Seu periodo de uso desta versão do SetupMno expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o n8n2 -f n8n2.sh
rm n8n2.sh
rm n8n2.sh.x.c
echo -e "XXX\n91\nINSTALANDO SETUPMNO 5/8 \nXXX"
shc -e $data_expiracao -m "Seu periodo de uso desta versão do SetupMno expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o appsmith -f appsmith.sh
rm appsmith.sh
rm appsmith.sh.x.c
if [ "$PLANO" == "free" ]; then
rm appsmith
fi
if [[ ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm appsmith
fi
echo -e "XXX\n92\nINSTALANDO SETUPMNO 5/8 \nXXX"
shc -e $data_expiracao -m "Seu periodo de uso desta versão do SetupMno expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o minio -f minio.sh
rm minio.sh
rm minio.sh.x.c
echo -e "XXX\n93\nINSTALANDO SETUPMNO 5/8 \nXXX"
shc -e $data_expiracao -m "Seu periodo de uso desta versão do SetupMno expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o zep -f zep.sh
rm zep.sh
rm zep.sh.x.c
if [[ ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm zep
fi
echo -e "XXX\n94\nINSTALANDO SETUPMNO 5/8 \nXXX"
shc -e $data_expiracao -m "Seu periodo de uso desta versão do SetupMno expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o redicommander -f redicommander.sh
rm redicommander.sh
rm redicommander.sh.x.c
if [[ ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm redicommander
fi
shc -e $data_expiracao -m "Seu periodo de uso desta versão do SetupMno expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o rabbitmq -f rabbitmq.sh
rm rabbitmq.sh
rm rabbitmq.sh.x.c
if [[ ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm rabbitmq
fi
shc -e $data_expiracao -m "Seu periodo de uso desta versão do SetupMno expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o flowise -f flowise.sh
rm flowise.sh
rm flowise.sh.x.c
if [[ ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm flowise
fi
shc -e $data_expiracao -m "Seu periodo de uso desta versão do SetupMno expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o uptimekuma -f uptimekuma.sh
rm uptimekuma.sh
rm uptimekuma.sh.x.c
if [[ ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm uptimekuma
fi

shc -e $data_expiracao -m "Seu periodo de uso desta versão do SetupMno expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o waha -f waha.sh
rm waha.sh
rm waha.sh.x.c
if [[ ("$PLANO" == "free") ]]; then
rm waha
fi

echo -e "XXX\n95\nINSTALANDO SETUPMNO 5/8 \nXXX"
shc -e $data_expiracao -m "Seu periodo de uso desta versão do SetupMno expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o pgadmin -f pgadmin.sh
rm pgadmin.sh
rm pgadmin.sh.x.c

shc -e $data_expiracao -m "Seu periodo de uso desta versão do SetupMno expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o planka -f planka.sh
rm planka.sh
rm planka.sh.x.c
if [[ ("$PLANO" == "free") || ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm planka
fi

shc -e $data_expiracao -m "Seu periodo de uso desta versão do SetupMno expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o mauticpadrao -f mauticpadrao.sh
rm mauticpadrao.sh
rm mauticpadrao.sh.x.c
if [[ ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm mauticpadrao
fi
shc -e $data_expiracao -m "Seu periodo de uso desta versão do SetupMno expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o wordpress -f wordpress.sh
rm wordpress.sh
rm wordpress.sh.x.c
if [[ ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm wordpress
fi

shc -e $data_expiracao -m "Seu periodo de uso desta versão do SetupMno expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o wikijs -f wikijs.sh
rm wikijs.sh
rm wikijs.sh.x.c
if [[ ("$PLANO" == "free") || ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm wikijs
fi
shc -e $data_expiracao -m "Seu periodo de uso desta versão do SetupMno expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o weaviate -f weaviate.sh
rm weaviate.sh
rm weaviate.sh.x.c
if [[ ("$PLANO" == "free") || ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm weaviate
fi
shc -e $data_expiracao -m "Seu periodo de uso desta versão do SetupMno expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o vllm -f vllm.sh
rm vllm.sh
rm vllm.sh.x.c
if [[ ("$PLANO" == "free") || ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm vllm
fi
shc -e $data_expiracao -m "Seu periodo de uso desta versão do SetupMno expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o windmill -f windmill.sh
rm windmill.sh
rm windmill.sh.x.c
if [[ ("$PLANO" == "free") || ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm windmill
fi
shc -e $data_expiracao -m "Seu periodo de uso desta versão do SetupMno expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o milvus -f milvus.sh
rm milvus.sh
rm milvus.sh.x.c
if [[ ("$PLANO" == "free") || ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm milvus
fi
shc -e $data_expiracao -m "Seu periodo de uso desta versão do SetupMno expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o botpress -f botpress.sh
rm botpress.sh
rm botpress.sh.x.c
if [ "$PLANO" == "free" ]; then
rm botpress
fi
if [[ ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm botpress
fi
echo -e "XXX\n96\nINSTALANDO SETUPMNO 6/8 \nXXX"
shc -e $data_expiracao -m "Seu periodo de uso desta versão do SetupMno expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o budibase -f budibase.sh
rm budibase.sh
rm budibase.sh.x.c
if [[ ("$PLANO" == "free") || ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm budibase
fi
echo -e "XXX\n97\nINSTALANDO SETUPMNO 6/8 \nXXX"
shc -e $data_expiracao -m "Seu periodo de uso desta versão do SetupMno expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o nocodb -f nocodb.sh
rm nocodb.sh
rm nocodb.sh.x.c
if [[ ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm nocodb
fi
shc -e $data_expiracao -m "Seu periodo de uso desta versão do SetupMno expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o nocobase -f nocobase.sh
rm nocobase.sh
rm nocobase.sh.x.c
if [[ ("$PLANO" == "free") || ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm nocobase
fi
shc -e $data_expiracao -m "Seu periodo de uso desta versão do SetupMno expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o baserow -f baserow.sh
rm baserow.sh
rm baserow.sh.x.c
if [ "$PLANO" == "free" ]; then
rm baserow
fi
if [[ ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm baserow
fi
shc -e $data_expiracao -m "Seu periodo de uso desta versão do SetupMno expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o beszel -f beszel.sh
rm beszel.sh
rm beszel.sh.x.c
if [[ ("$PLANO" == "free") || ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm beszel
fi
shc -e $data_expiracao -m "Seu periodo de uso desta versão do SetupMno expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o mysql -f mysql.sh
rm mysql.sh
rm mysql.sh.x.c
if [[ ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm mysql
fi
echo -e "XXX\n97\nINSTALANDO SETUPMNO 7/8 \nXXX"
shc -e $data_expiracao -m "Seu periodo de uso desta versão do SetupMno expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o pma -f pma.sh
rm pma.sh
rm pma.sh.x.c
if [[ ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm pma
fi
shc -e $data_expiracao -m "Seu periodo de uso desta versão do SetupMno expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o restartservice -f restartservice.sh
rm restartservice.sh
rm restartservice.sh.x.c
shc -e $data_expiracao -m "Seu periodo de uso desta versão do SetupMno expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o uninstall -f uninstall.sh
rm uninstall.sh
rm uninstall.sh.x.c
shc -e $data_expiracao -m "Seu periodo de uso desta versão do SetupMno expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o dockerswarm -f dockerswarm.sh
rm dockerswarm.sh
rm dockerswarm.sh.x.c
shc -e $data_expiracao -m "Seu periodo de uso desta versão do SetupMno expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o install -f install.sh
rm install.sh
rm install.sh.x.c
echo -e "XXX\n98\nINSTALANDO SETUPMNO 7/8 \nXXX"
shc -e $data_expiracao -m "Seu periodo de uso desta versão do SetupMno expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o calcom -f calcom.sh
rm calcom.sh
rm calcom.sh.x.c
if [ "$PLANO" == "free" ]; then
rm calcom
fi
if [[ ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm calcom
fi
shc -e $data_expiracao -m "Seu periodo de uso desta versão do SetupMno expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o chatwootn_evon_rabbitmq -f chatwootn_evon_rabbitmq.sh
rm chatwootn_evon_rabbitmq.sh
rm chatwootn_evon_rabbitmq.sh.x.c
if [[ ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm chatwootn_evon_rabbitmq
fi

shc -e $data_expiracao -m "Seu periodo de uso desta versão do SetupMno expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o   chatwootn_evo2_rabbitmq_redisevo -f     chatwootn_evo2_rabbitmq_redisevo.sh
rm      chatwootn_evo2_rabbitmq_redisevo.sh
rm      chatwootn_evo2_rabbitmq_redisevo.sh.x.c
if [[ ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm chatwootn_evo2_rabbitmq_redisevo
fi

shc -e $data_expiracao -m "Seu periodo de uso desta versão do SetupMno expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o langfuse -f langfuse.sh
rm langfuse.sh
rm langfuse.sh.x.c
if [ "$PLANO" == "free" ]; then
rm langfuse
fi
if [[ ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm langfuse
fi
echo -e "XXX\n99\nINSTALANDO SETUPMNO 7/8 \nXXX"
shc -e $data_expiracao -m "Seu periodo de uso desta versão do SetupMno expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o langflow -f langflow.sh
rm langflow.sh
rm langflow.sh.x.c
if [[ ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm langflow
fi
shc -e $data_expiracao -m "Seu periodo de uso desta versão do SetupMno expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o dozzle -f dozzle.sh
rm dozzle.sh
rm dozzle.sh.x.c
if [ "$PLANO" == "free" ]; then
rm dozzle
fi
if [[ ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm dozzle
fi
shc -e $data_expiracao -m "Seu periodo de uso desta versão do SetupMno expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o syncthing -f syncthing.sh
rm syncthing.sh
rm syncthing.sh.x.c
if [[ ("$PLANO" == "free") || ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm syncthing
fi
shc -e $data_expiracao -m "Seu periodo de uso desta versão do SetupMno expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o changedetection -f changedetection.sh
rm changedetection.sh
rm changedetection.sh.x.c
if [[ ("$PLANO" == "free") || ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm changedetection
fi
shc -e $data_expiracao -m "Seu periodo de uso desta versão do SetupMno expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o plane -f plane.sh
rm plane.sh
rm plane.sh.x.c
if [[ ("$PLANO" == "free") || ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm plane
fi
shc -e $data_expiracao -m "Seu periodo de uso desta versão do SetupMno expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o shlink -f shlink.sh
rm shlink.sh
rm shlink.sh.x.c
if [[ ("$PLANO" == "free") || ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm shlink
fi
shc -e $data_expiracao -m "Seu periodo de uso desta versão do SetupMno expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o siyuan -f siyuan.sh
rm siyuan.sh
rm siyuan.sh.x.c
if [[ ("$PLANO" == "free") || ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm siyuan
fi
shc -e $data_expiracao -m "Seu periodo de uso desta versão do SetupMno expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o tooljet -f tooljet.sh
rm tooljet.sh
rm tooljet.sh.x.c
if [[ ("$PLANO" == "free") || ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm tooljet
fi

shc -e $data_expiracao -m "Seu periodo de uso desta versão do SetupMno expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o reactiveresume -f reactiveresume.sh
rm reactiveresume.sh
rm reactiveresume.sh.x.c
if [[ ("$PLANO" == "free") || ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm reactiveresume
fi
shc -e $data_expiracao -m "Seu periodo de uso desta versão do SetupMno expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o photoprism -f photoprism.sh
rm photoprism.sh
rm photoprism.sh.x.c
if [[ ("$PLANO" == "free") || ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm photoprism
fi
shc -e $data_expiracao -m "Seu periodo de uso desta versão do SetupMno expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o geracloudflare -f geracloudflare.sh
rm geracloudflare.sh
rm geracloudflare.sh.x.c

shc -e $data_expiracao -m "Seu periodo de uso desta versão do SetupMno expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o mautic5padrao -f mautic5padrao.sh
rm mautic5padrao.sh
rm mautic5padrao.sh.x.c
if [[ ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm mautic5padrao
fi
shc -e $data_expiracao -m "Seu periodo de uso desta versão do SetupMno expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o mautic4whatsmkt -f mautic4whatsmkt.sh
rm mautic4whatsmkt.sh
rm mautic4whatsmkt.sh.x.c
if [ "$PLANO" == "free" ]; then
rm mautic4whatsmkt
fi
if [[ ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm mautic4whatsmkt
fi
shc -e $data_expiracao -m "Seu periodo de uso desta versão do SetupMno expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o mautic5whatsmkt -f mautic5whatsmkt.sh
rm mautic5whatsmkt.sh
rm mautic5whatsmkt.sh.x.c
if [ "$PLANO" == "free" ]; then
rm mautic5whatsmkt
fi
if [[ ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm mautic5whatsmkt
fi
shc -e $data_expiracao -m "Seu periodo de uso desta versão do SetupMno expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o n8nmain -f n8nmain.sh
rm n8nmain.sh
rm n8nmain.sh.x.c

shc -e $data_expiracao -m "Seu periodo de uso desta versão do SetupMno expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o qdrant -f qdrant.sh
rm qdrant.sh
rm qdrant.sh.x.c
if [[ ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm qdrant
fi
shc -e $data_expiracao -m "Seu periodo de uso desta versão do SetupMno expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o chromadb -f chromadb.sh
rm chromadb.sh
rm chromadb.sh.x.c
if [[ ("$PLANO" == "free") || ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm chromadb
fi
shc -e $data_expiracao -m "Seu periodo de uso desta versão do SetupMno expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o essenciais -f essenciais.sh
rm essenciais.sh
rm essenciais.sh.x.c

shc -e $data_expiracao -m "Seu periodo de uso desta versão do SetupMno expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o evoai -f evoai.sh
rm evoai.sh
rm evoai.sh.x.c
if [[ ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm evoai
fi

shc -e $data_expiracao -m "Seu periodo de uso desta versão do SetupMno expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o chatwootn_evo2_rabbitmq_minio -f chatwootn_evo2_rabbitmq_minio.sh
rm chatwootn_evo2_rabbitmq_minio.sh
rm chatwootn_evo2_rabbitmq_minio.sh.x.c
if [ "$PLANO" == "free" ]; then
rm chatwootn_evo2_rabbitmq_minio
fi
if [[ ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm chatwootn_evo2_rabbitmq_minio
fi
shc -e $data_expiracao -m "Seu periodo de uso desta versão do SetupMno expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o typebot_minio -f typebot_minio.sh
rm typebot_minio.sh
rm typebot_minio.sh.x.c
if [ "$PLANO" == "free" ]; then
rm typebot_minio
fi
if [[ ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm typebot_minio
fi
shc -e $data_expiracao -m "Seu periodo de uso desta versão do SetupMno expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o redis -f redis.sh
rm redis.sh
rm redis.sh.x.c

shc -e $data_expiracao -m "Seu periodo de uso desta versão do SetupMno expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o evoai_evo2_minio -f evoai_evo2_minio.sh
rm evoai_evo2_minio.sh
rm evoai_evo2_minio.sh.x.c
if [ "$PLANO" == "free" ]; then
rm evoai_evo2_minio
fi
if [[ ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm evoai_evo2_minio
fi
shc -e $data_expiracao -m "Seu periodo de uso desta versão do SetupMno expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o litellm -f litellm.sh
rm litellm.sh
rm litellm.sh.x.c
if [ "$PLANO" == "free" ]; then
rm litellm
fi
if [[ ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm litellm
fi
shc -e $data_expiracao -m "Seu periodo de uso desta versão do SetupMno expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o librechat -f librechat.sh
rm librechat.sh
rm librechat.sh.x.c
if [[ ("$PLANO" == "free") || ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm librechat
fi
shc -e $data_expiracao -m "Seu periodo de uso desta versão do SetupMno expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o listmonk -f listmonk.sh
rm listmonk.sh
rm listmonk.sh.x.c
if [ "$PLANO" == "free" ]; then
rm listmonk
fi
if [[ ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm listmonk
fi
shc -e $data_expiracao -m "Seu periodo de uso desta versão do SetupMno expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o lobechat -f lobechat.sh
rm lobechat.sh
rm lobechat.sh.x.c
if [[ ("$PLANO" == "free") || ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm lobechat
fi
shc -e $data_expiracao -m "Seu periodo de uso desta versão do SetupMno expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o mautic6padrao -f mautic6padrao.sh
rm mautic6padrao.sh
rm mautic6padrao.sh.x.c
if [[ ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm mautic6padrao
fi
shc -e $data_expiracao -m "Seu periodo de uso desta versão do SetupMno expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o mautic6whatsmkt -f mautic6whatsmkt.sh
rm mautic6whatsmkt.sh
rm mautic6whatsmkt.sh.x.c
if [ "$PLANO" == "free" ]; then
rm mautic6whatsmkt
fi
if [[ ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm mautic6whatsmkt
fi

shc -e $data_expiracao -m "Seu periodo de uso desta versão do SetupMno expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o n8n-workflows -f n8n-workflows.sh
rm n8n-workflows.sh
rm n8n-workflows.sh.x.c
if [[ ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm n8n-workflows
fi

shc -e $data_expiracao -m "Seu periodo de uso desta versão do SetupMno expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o matomo -f matomo.sh
rm matomo.sh
rm matomo.sh.x.c
if [ "$PLANO" == "free" ]; then
rm matomo
fi
if [[ ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm matomo
fi

shc -e $data_expiracao -m "Seu periodo de uso desta versão do SetupMno expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o maybe -f maybe.sh
rm maybe.sh
rm maybe.sh.x.c
if [[ ("$PLANO" == "free") || ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm maybe
fi

shc -e $data_expiracao -m "Seu periodo de uso desta versão do SetupMno expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o meilisearch -f meilisearch.sh
rm meilisearch.sh
rm meilisearch.sh.x.c
if [[ ("$PLANO" == "free") || ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm meilisearch
fi
shc -e $data_expiracao -m "Seu periodo de uso desta versão do SetupMno expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o memos -f memos.sh
rm memos.sh
rm memos.sh.x.c
if [[ ("$PLANO" == "free") || ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm memos
fi
shc -e $data_expiracao -m "Seu periodo de uso desta versão do SetupMno expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o openclaw -f openclaw.sh
rm openclaw.sh
rm openclaw.sh.x.c
if [ "$PLANO" == "free" ]; then
rm openclaw
fi
if [ "$PLANO" == "free1" ]; then
rm openclaw
fi


shc -e $data_expiracao -m "Seu periodo de uso desta versão do SetupMno expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o databasus -f databasus.sh
rm databasus.sh
rm databasus.sh.x.c
if [ "$PLANO" == "free2" ]; then
rm databasus
fi



shc -e $data_expiracao -m "Seu periodo de uso desta versão do SetupMno expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o ghost -f ghost.sh
rm ghost.sh
rm ghost.sh.x.c
if [[ ("$PLANO" == "free") || ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm ghost
fi

shc -e $data_expiracao -m "Seu periodo de uso desta versão do SetupMno expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o discourse -f discourse.sh
rm discourse.sh
rm discourse.sh.x.c
if [[ ("$PLANO" == "free") || ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm discourse
fi

shc -e $data_expiracao -m "Seu periodo de uso desta versão do SetupMno expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o mautic7padrao -f mautic7padrao.sh
rm mautic7padrao.sh
rm mautic7padrao.sh.x.c
if [[ ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm mautic7padrao
fi

shc -e $data_expiracao -m "Seu periodo de uso desta versão do SetupMno expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o mautic7whatsmkt -f mautic7whatsmkt.sh
rm mautic7whatsmkt.sh
rm mautic7whatsmkt.sh.x.c
if [[ ("$PLANO" == "free") || ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm mautic7whatsmkt
fi


# Novas Ferramentas de IA

shc -e $data_expiracao -m "Seu periodo de uso desta versão do SetupMno expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o autogen -f autogen.sh
rm autogen.sh
rm autogen.sh.x.c
if [[ ("$PLANO" == "free") || ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm autogen
fi


shc -e $data_expiracao -m "Seu periodo de uso desta versão do SetupMno expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o cognee -f cognee.sh
rm cognee.sh
rm cognee.sh.x.c
if [[ ("$PLANO" == "free") || ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm cognee
fi

shc -e $data_expiracao -m "Seu periodo de uso desta versão do SetupMno expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o memgraph -f memgraph.sh
rm memgraph.sh
rm memgraph.sh.x.c
if [[ ("$PLANO" == "free") || ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm memgraph
fi

shc -e $data_expiracao -m "Seu periodo de uso desta versão do SetupMno expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o neo4j -f neo4j.sh
rm neo4j.sh
rm neo4j.sh.x.c
if [[ ("$PLANO" == "free") || ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm neo4j
fi

shc -e $data_expiracao -m "Seu periodo de uso desta versão do SetupMno expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o openfang -f openfang.sh
rm openfang.sh
rm openfang.sh.x.c
if [[ ("$PLANO" == "free") || ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm openfang
fi

shc -e $data_expiracao -m "Seu periodo de uso desta versão do SetupMno expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o paperclip -f paperclip.sh
rm paperclip.sh
rm paperclip.sh.x.c
if [[ ("$PLANO" == "free") || ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm paperclip
fi

shc -e $data_expiracao -m "Seu periodo de uso desta versão do SetupMno expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o penpot -f penpot.sh
rm penpot.sh
rm penpot.sh.x.c
if [[ ("$PLANO" == "free") || ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm penpot
fi

shc -e $data_expiracao -m "Seu periodo de uso desta versão do SetupMno expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o pihole -f pihole.sh
rm pihole.sh
rm pihole.sh.x.c
if [[ ("$PLANO" == "free") || ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm pihole
fi
shc -e $data_expiracao -m "Seu periodo de uso desta versão do SetupMno expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o pocketbase -f pocketbase.sh
rm pocketbase.sh
rm pocketbase.sh.x.c
if [[ ("$PLANO" == "free") || ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm pocketbase
fi

shc -e $data_expiracao -m "Seu periodo de uso desta versão do SetupMno expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o rocketchat -f rocketchat.sh
rm rocketchat.sh
rm rocketchat.sh.x.c
if [[ ("$PLANO" == "free") || ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm rocketchat
fi

shc -e $data_expiracao -m "Seu periodo de uso desta versão do SetupMno expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o gitea -f gitea.sh
rm gitea.sh
rm gitea.sh.x.c
if [[ ("$PLANO" == "free") || ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm gitea
fi

shc -e $data_expiracao -m "Seu periodo de uso desta versão do SetupMno expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o gitlab -f gitlab.sh
rm gitlab.sh
rm gitlab.sh.x.c
if [[ ("$PLANO" == "free") || ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm gitlab
fi

shc -e $data_expiracao -m "Seu periodo de uso desta versão do SetupMno expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o glance -f glance.sh
rm glance.sh
rm glance.sh.x.c
if [[ ("$PLANO" == "free") || ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm glance
fi

shc -e $data_expiracao -m "Seu periodo de uso desta versão do SetupMno expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o umami -f umami.sh
rm umami.sh
rm umami.sh.x.c
if [[ ("$PLANO" == "free") || ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm umami
fi

shc -e $data_expiracao -m "Seu periodo de uso desta versão do SetupMno expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o actualbudget -f actualbudget.sh
rm actualbudget.sh
rm actualbudget.sh.x.c
if [[ ("$PLANO" == "free") || ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm actualbudget
fi

shc -e $data_expiracao -m "Seu periodo de uso desta versão do SetupMno expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o bookstack -f bookstack.sh
rm bookstack.sh
rm bookstack.sh.x.c
if [[ ("$PLANO" == "free") || ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm bookstack
fi

shc -e $data_expiracao -m "Seu periodo de uso desta versão do SetupMno expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o paperless -f paperless.sh
rm paperless.sh
rm paperless.sh.x.c
if [[ ("$PLANO" == "free") || ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm paperless
fi

shc -e $data_expiracao -m "Seu periodo de uso desta versão do SetupMno expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o fireflyiii -f fireflyiii.sh
rm fireflyiii.sh
rm fireflyiii.sh.x.c
if [[ ("$PLANO" == "free") || ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm fireflyiii
fi

shc -e $data_expiracao -m "Seu periodo de uso desta versão do SetupMno expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o searxng -f searxng.sh
rm searxng.sh
rm searxng.sh.x.c
if [[ ("$PLANO" == "free") || ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm searxng
fi

shc -e $data_expiracao -m "Seu periodo de uso desta versão do SetupMno expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o openclawpro -f openclawpro.sh
rm openclawpro.sh
rm openclawpro.sh.x.c
if [[ ("$PLANO" == "free") || ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm openclawpro
fi

shc -e $data_expiracao -m "Seu periodo de uso desta versão do SetupMno expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o evocrm -f evocrm.sh
rm evocrm.sh
rm evocrm.sh.x.c

shc -e $data_expiracao -m "Seu periodo de uso desta versão do SetupMno expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o evolutiongo -f evolutiongo.sh
rm evolutiongo.sh
rm evolutiongo.sh.x.c

shc -e $data_expiracao -m "Seu periodo de uso desta versão do SetupMno expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o evonexus -f evonexus.sh
rm evonexus.sh
rm evonexus.sh.x.c

shc -e $data_expiracao -m "Seu periodo de uso desta versão do SetupMno expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o hermes -f hermes.sh
rm hermes.sh
rm hermes.sh.x.c
if [[ ("$PLANO" == "free") || ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm hermes
fi

shc -e $data_expiracao -m "Seu periodo de uso desta versão do SetupMno expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o heyform -f heyform.sh
rm heyform.sh
rm heyform.sh.x.c
if [[ ("$PLANO" == "free") || ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm heyform
fi
shc -e $data_expiracao -m "Seu periodo de uso desta versão do SetupMno expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o infisical -f infisical.sh
rm infisical.sh
rm infisical.sh.x.c
if [[ ("$PLANO" == "free") || ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm infisical
fi
shc -e $data_expiracao -m "Seu periodo de uso desta versão do SetupMno expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o it_tools -f it_tools.sh
rm it_tools.sh
rm it_tools.sh.x.c
if [[ ("$PLANO" == "free") || ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm it_tools
fi
shc -e $data_expiracao -m "Seu periodo de uso desta versão do SetupMno expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o chatwooto_evo2_rabbitmq_minio -f chatwooto_evo2_rabbitmq_minio.sh
rm chatwooto_evo2_rabbitmq_minio.sh
rm chatwooto_evo2_rabbitmq_minio.sh.x.c
if [[ ("$PLANO" == "free") || ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm chatwooto_evo2_rabbitmq_minio
fi

shc -e $data_expiracao -m "Seu periodo de uso desta versão do SetupMno expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o chatwootorig_desbloq__evo2_rabbitmq_minio -f chatwootorig_desbloq__evo2_rabbitmq_minio.sh
rm chatwootorig_desbloq__evo2_rabbitmq_minio.sh
rm chatwootorig_desbloq__evo2_rabbitmq_minio.sh.x.c
if [[ ("$PLANO" == "free") || ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm chatwootorig_desbloq__evo2_rabbitmq_minio
fi

shc -e $data_expiracao -m "Seu periodo de uso desta versão do SetupMno expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o chatwoot_ai_customer_service -f chatwoot_ai_customer_service.sh
rm chatwoot_ai_customer_service.sh
rm chatwoot_ai_customer_service.sh.x.c
if [[ ("$PLANO" == "free") || ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm chatwoot_ai_customer_service
fi

shc -e $data_expiracao -m "Seu periodo de uso desta versão do SetupMno expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o jitsi -f jitsi.sh
rm jitsi.sh
rm jitsi.sh.x.c
if [[ ("$PLANO" == "free") || ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm jitsi
fi

shc -e $data_expiracao -m "Seu periodo de uso desta versão do SetupMno expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o joplin -f joplin.sh
rm joplin.sh
rm joplin.sh.x.c
if [[ ("$PLANO" == "free") || ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm joplin
fi

shc -e $data_expiracao -m "Seu periodo de uso desta versão do SetupMno expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o jellyfin -f jellyfin.sh
rm jellyfin.sh
rm jellyfin.sh.x.c
if [[ ("$PLANO" == "free") || ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm jellyfin
fi

shc -e $data_expiracao -m "Seu periodo de uso desta versão do SetupMno expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o activepieces -f activepieces.sh
rm activepieces.sh
rm activepieces.sh.x.c
if [[ ("$PLANO" == "free") || ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm activepieces
fi
shc -e $data_expiracao -m "Seu periodo de uso desta versão do SetupMno expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o adguardhome -f adguardhome.sh
rm adguardhome.sh
rm adguardhome.sh.x.c
if [[ ("$PLANO" == "free") || ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm adguardhome
fi

shc -e $data_expiracao -m "Seu periodo de uso desta versão do SetupMno expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o dify -f dify.sh
rm dify.sh
rm dify.sh.x.c
if [[ ("$PLANO" == "free") || ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm dify
fi

shc -e $data_expiracao -m "Seu periodo de uso desta versão do SetupMno expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o setupmno_control -f setupmno_control.sh
rm setupmno_control.sh
rm setupmno_control.sh.x.c
if [[ ("$PLANO" == "free") || ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
rm setupmno_control
fi

echo -e "XXX\n99\nINSTALANDO SETUPMNO 7/8 \nXXX"


sleep 4
echo -e "XXX\n100\nINSTALANDO SETUPMNO 8/8 - CONCLUIDO \nXXX"
sleep 3
}|whiptail --title "SETUPMNO v${VERSIONSETUP}" --gauge "Aguarde a instalação inicial" 6 60 0
setup_status=${PIPESTATUS[0]}
if [ "$setup_status" -ne 0 ]; then
    setup_error=$(cat "$control_state_error" 2>/dev/null)
    [ -n "$setup_error" ] || setup_error="A instalação foi interrompida. Atualize o instalador e tente novamente."
    whiptail --title "ERRO NA INSTALAÇÃO DO SETUP MNO" --scrolltext --msgbox \
        "$setup_error\n\nCódigo da falha: $setup_status" 18 82
    exit "$setup_status"
fi
clear
cd /
cd
sudo rm start_full* 2>/dev/null || true
sudo rm start_start* 2>/dev/null || true
sudo rm -r SetupLowCodeMnoStart 2>/dev/null || true

sudo rm setup-mno.sh 2>/dev/null || true


cd SetupLowCodeMno

./install
$SHELL

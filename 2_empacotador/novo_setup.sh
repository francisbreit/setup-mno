#!/bin/bash
# ==============================================================================
# CRIADOR DE NOVOS SETUPS - SETUP MNO
# Adiciona a nova ferramenta na Lista Telefônica Universal e gera o esqueleto
# canônico compatível com Traefik, Cloudflare Tunnel e MNO Fleet Hub.
# Uso: ./novo_setup.sh <nome_app> <porta> [categoria] [imagem_docker]
# Exemplo: ./novo_setup.sh libretranslate 5000 tradutor libretranslate/libretranslate:latest
# ==============================================================================
set -euo pipefail

BASE_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
REGISTRY_SCRIPT="$BASE_DIR/1_codigo_fonte/x86/SetupLowCodeMno/mno-port-registry.sh"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=================================================================${NC}"
echo -e "${BLUE}     GERADOR CANÔNICO DE NOVOS SETUPS - SETUP MNO               ${NC}"
echo -e "${BLUE}=================================================================${NC}"

if [ $# -lt 2 ]; then
    echo -e "${YELLOW}Uso:${NC} $0 <nome_app> <porta> [categoria] [imagem_docker]"
    echo -e "Exemplo: $0 libretranslate 5000 tradutor libretranslate/libretranslate:latest"
    exit 1
fi

APP_NAME=$(echo "$1" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9_' '_')
PORT="$2"
CATEGORY="${3:-geral}"
DOCKER_IMAGE="${4:-${APP_NAME}/${APP_NAME}:latest}"
SERVICE_NAME="${APP_NAME}_app"

echo -e "[1/4] 🔍 Verificando porta ${YELLOW}$PORT${NC} na Lista Telefônica Universal..."
if [ -x "$REGISTRY_SCRIPT" ]; then
    check_res=$("$REGISTRY_SCRIPT" check "$PORT" || true)
    echo "      $check_res"
fi

echo -e "[2/4] 📝 Registrando ${GREEN}$APP_NAME${NC} (Porta: ${GREEN}$PORT${NC}) na Lista Telefônica Universal..."
# Registra no x86
bash "$BASE_DIR/1_codigo_fonte/x86/SetupLowCodeMno/mno-port-registry.sh" register "$APP_NAME" "$PORT" "$SERVICE_NAME" "$CATEGORY"
# Sincroniza para ARM
cp "$BASE_DIR/1_codigo_fonte/x86/SetupLowCodeMno/mno_universal_ports.json" "$BASE_DIR/1_codigo_fonte/arm/SetupLowCodeMno/mno_universal_ports.json"
echo -e "      ✅ Lista Telefônica Universal sincronizada em x86 e ARM."

TARGET_X86="$BASE_DIR/1_codigo_fonte/x86/SetupLowCodeMno/${APP_NAME}.sh"
TARGET_ARM="$BASE_DIR/1_codigo_fonte/arm/SetupLowCodeMno/${APP_NAME}.sh"

echo -e "[3/4] 🚀 Gerando script instalador canônico padronizado..."

cat > "$TARGET_X86" << 'EOF_OUTER'
#!/usr/bin/bash
#########################################################
#
# LOADING & THEME
#
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

# VERIFICAR TIPO DE INSTALAÇÃO
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
EOF_OUTER

# Injeta variáveis dinâmicas no script
cat >> "$TARGET_X86" << EOF_MIDDLE

nome_app="$APP_NAME"
porta_app="$PORT"
imagem_docker="$DOCKER_IMAGE"

EOF_MIDDLE

cat >> "$TARGET_X86" << 'EOF_REST'
dominio=$(whiptail --title "INSTALADOR SETUP MNO - $nome_app" --inputbox \
"Digite o domínio ou subdomínio para $nome_app (ex: $nome_app.seudominio.com):" 10 70 3>&1 1>&2 2>&3) || exit 1

[ -z "$dominio" ] && exit 1

echo -e "${amarelo}⚙️  Configurando infraestrutura para $nome_app ($dominio)...${reset}"

# Rota no Cloudflare Tunnel se aplicável
if [ "$INSTALL_TYPE" = "CLOUDFLARE_TUNNEL" ]; then
    NEW_SERVICE="http://${nome_app}_app:${porta_app}"
    CONFIG_FILE="/root/.cloudflared_config/config.yml"
    if [ -f "$CONFIG_FILE" ]; then
        python3 -c "
import yaml
with open('$CONFIG_FILE', 'r') as f:
    config = yaml.safe_load(f)
ingress = config.get('ingress', [])
ingress.insert(0, {'hostname': '$dominio', 'service': '$NEW_SERVICE'})
config['ingress'] = ingress
with open('$CONFIG_FILE', 'w') as f:
    yaml.dump(config, f, default_flow_style=False)
" 2>/dev/null || true
        systemctl restart cloudflared 2>/dev/null || true
    fi
fi

# Gerar YAML Canônico Padronizado
cat > "/root/SetupLowCodeMno/${nome_app}.yaml" << EOL
version: "3.8"

networks:
  rede_publica:
    external: true
  interna:
    external: true

services:
  ${nome_app}_app:
    image: ${imagem_docker}
    environment:
      - WEB_DOMAIN=${dominio}
      - APP_URL=https://${dominio}
    networks:
      - rede_publica
      - interna
    deploy:
      replicas: 1
      restart_policy:
        condition: on-failure
      labels:
        - "traefik.enable=$([ "$INSTALL_TYPE" = "TRADICIONAL" ] && echo "1" || echo "0")"
        - "traefik.http.routers.${nome_app}.rule=Host(\`${dominio}\`)"
        - "traefik.http.routers.${nome_app}.service=${nome_app}"
        - "traefik.http.services.${nome_app}.loadbalancer.server.port=${porta_app}"
        - "traefik.http.services.${nome_app}.loadbalancer.passHostHeader=1"
EOL

if [ "$INSTALL_TYPE" = "TRADICIONAL" ]; then
cat >> "/root/SetupLowCodeMno/${nome_app}.yaml" << EOL
        - "traefik.http.routers.${nome_app}.entrypoints=websecure"
        - "traefik.http.routers.${nome_app}.priority=1"
        - "traefik.http.routers.${nome_app}.tls.certresolver=letsencryptresolver"
EOL
fi

echo -e "${amarelo}🚀 Realizando deploy da stack $nome_app no Docker Swarm...${reset}"
docker stack deploy -c "/root/SetupLowCodeMno/${nome_app}.yaml" "$nome_app"

# Gravação Padronizada de Manifesto Canônico
if [ -x "/root/SetupLowCodeMno/mno-manifest-writer.sh" ]; then
    /root/SetupLowCodeMno/mno-manifest-writer.sh \
        "$nome_app" "$nome_app" "" "" "none" "" "" "" "$dominio" "" "$porta_app"
fi

whiptail --title "SUCESSO" --msgbox "A aplicação $nome_app foi instalada com sucesso!\nAcesse: https://$dominio" 10 70
EOF_REST

# Espelha para ARM
cp "$TARGET_X86" "$TARGET_ARM"
chmod +x "$TARGET_X86" "$TARGET_ARM"

echo -e "[4/4] ✅ Arquivos criados com sucesso e com 100% de paridade x86/ARM:"
echo -e "      📄 $TARGET_X86"
echo -e "      📄 $TARGET_ARM"
echo ""
echo -e "${GREEN}Próximos passos para homologar o setup:${NC}"
echo -e "  1. Ajuste as variáveis de ambiente em: ${YELLOW}${TARGET_X86}${NC}"
echo -e "  2. Adicione a chamada no menu de ${YELLOW}install.sh${NC} se for disponibilizar na interface."
echo -e "  3. Execute os gates: ${GREEN}generate-installers.sh${NC} e ${GREEN}./2_empacotador/gerar_distribuicao.sh${NC}"
echo ""

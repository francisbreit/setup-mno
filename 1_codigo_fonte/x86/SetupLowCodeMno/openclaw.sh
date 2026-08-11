#!/usr/bin/bash
#########################################################
# # cloudflare tunnel - records automáticos
#   LOADING
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

#
# FIM DE LOADING
#

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

# CARREGAR CREDENCIAIS CONFORME TIPO DE INSTALAÇÃO
if [ "$INSTALL_TYPE" = "CLOUDFLARE_TUNNEL" ]; then
    if [ -f "${SETUPMNO_CLOUDFLARE_CREDENTIALS_FILE:-/root/.cloudflared_config/cloudflare_credentials}" ]; then
        source "${SETUPMNO_CLOUDFLARE_CREDENTIALS_FILE:-/root/.cloudflared_config/cloudflare_credentials}"
    fi
else
    if [ -f "${SETUPMNO_TRADITIONAL_CREDENTIALS_FILE:-/root/.tradicional_config/tradicional_credentials}" ]; then
        source "${SETUPMNO_TRADITIONAL_CREDENTIALS_FILE:-/root/.tradicional_config/tradicional_credentials}"
    fi
fi

function msg() {
    msg=$1
    whiptail --title "INSTALAÇÃO DO OPENCLAW" --msgbox "$msg" --fb 10 70
}

while true; do
CHOICE=$(
whiptail --title "INSTALAÇÃO DO OPENCLAW" --menu "Aperte ENTER para iniciar a instalação do OpenClaw ou selecione SAIR (Utilize setas e Enter)\n\nTIPO DE INSTALAÇÃO DETECTADA: $INSTALL_TYPE\n\nINSTRUÇÕES:\nAntes de prosseguir, verifique os registros DNS conforme seu tipo de instalação:" 20 70 2 \
    "1)" "CONTINUAR"   \
    "2)" "SAIR"  3>&2 2>&1 1>&3    
)

case $CHOICE in
    "1)")   
        clear
        break
    ;;
    
    "2)") 
        cd /
        cd
        exit 0
        ;; 
esac
done

# SOLICITAR URL DO OPENCLAW
while true; do
    urlopenclaw=$(whiptail --title "URL do OpenClaw" --inputbox "Digite o Link do OpenClaw (ex: openclaw.seudominio.com):" --fb 12 60 3>&1 1>&2 2>&3)
    saida=$?
    if [[ $saida -eq '0' ]]; then
        if [[ -z $urlopenclaw ]]; then 
            msg "Digite o link do OpenClaw para poder continuar"
            continue
        else 
            break
        fi
    else
        echo $urlopenclaw
        echo "saindo..."
        exit 0
    fi
done

chave_hexadecimal=$(openssl rand -hex 16)
while true ; do
    key=$(whiptail --title "Gateway Token" --inputbox "Digite o Gateway Token (sugestão gerada aleatoriamente: $chave_hexadecimal):" --fb 12 60 3>&1 1>&2 2>&3) ; saida=$?
    if [[ $saida -eq '0' ]] ; then
        if [[ -z $key ]] ; then msg "Crie um Gateway Token para o OpenClaw, para poder continuar" ; continue ; else break; fi
    else
        echo $key ; echo "saindo..."  &  exit 0 ;
    fi
done

# SOLICITAR ASSISTENTE SYSADMIN (nativeSkills)
while true; do
    SYSADMIN_CHOICE=$(whiptail --title "Assistente Sysadmin Autônomo (Segurança)" --menu "O OpenClaw pode funcionar como um 'Assistente de Sistema', permitindo que a IA vasculhe e altere arquivos da própria instalação.\n\n⚠️ RISCO: Se você vai usar esse robô para atender clientes no WhatsApp, pessoas mal-intencionadas podem enganar a IA para vazar ou apagar informações. Além disso, a IA pode tentar rodar vários comandos e gastar seus créditos rapidamente.\n\nRecomendamos fortemente manter DESLIGADO." 22 75 2 \
        "DESLIGADO" "(Recomendado) Maior segurança e foco no atendimento" \
        "LIGADO" "(Avançado) Uso apenas em WhatsApp privado para testes" 3>&1 1>&2 2>&3)
    
    saida=$?
    if [[ $saida -eq '0' ]]; then
        if [[ "$SYSADMIN_CHOICE" == "DESLIGADO" ]]; then
            NATIVE_SKILLS="false"
        else
            NATIVE_SKILLS="\"auto\""
        fi
        break
    else
        echo "saindo..."
        exit 0
    fi
done

# SOLICITAR SE CRIA STACK NO PORTAINER
while true; do
    criar_portainer=$(whiptail --title "Criar Stack no Portainer? - 0 ou 1" --inputbox "Digite 0 para poder editar stack no portainer ou 1 para não poder editar" --fb 12 60 3>&1 1>&2 2>&3)
    saida=$?
    if [[ $saida -eq '0' ]]; then
        if [[ "$criar_portainer" != "0" && "$criar_portainer" != "1" ]]; then 
            msg "Digite apenas o número 0 ou o número 1, para poder continuar. Digite 0 para poder editar stack no portainer ou 1 para não poder editar"
            continue
        else 
            break
        fi
    else
        echo $criar_portainer
        echo "saindo..."
        exit 0
    fi
done

#########################################################
# VERIFICAÇÃO DE DADOS
#########################################################

nome_principal="openclaw"
sufixo_app=$(date | md5sum | head -c7)
nome_app=$nome_principal$sufixo_app

{
  tput reset 2>/dev/null
  exec 0</dev/tty 1>/dev/tty 2>&1
  sleep 0.01
  clear
} || true

whiptail --title "Dados Fornecidos" \
 --msgbox "TIPO DE INSTALAÇÃO: $INSTALL_TYPE\n\nDados Preenchidos:\n\n1) Url do OpenClaw: $urlopenclaw\n2) Gateway Token: $key\n3) Assistente Sysadmin: $SYSADMIN_CHOICE\n4) Criar Stack no Portainer: $([ "$criar_portainer" == "0" ] && echo "0 (Editável)" || echo "1 (Não editável)")\n\nConfira e Tecle Enter para continuar." \
 --fb 22 80

while true; do
    confirma1=$(whiptail --title "Confirmação" \
    --inputbox "Informações estão corretas? Digite 'y' para confirmar e instalar ou 'n' para voltar e corrigir:" \
    --fb 10 60 3>&1 1>&2 2>&3)
    
    if [[ "$confirma1" =~ ^[yY]$ ]]; then
        break
    elif [[ "$confirma1" =~ ^[nN]$ ]]; then
        msg "Você digitou N. Tecle Enter para sair da instalação"
        exit 0
    else
        msg "Entrada inválida! Por favor, use apenas 'y' ou 'n'."
    fi
done

# =====================================================================
# CONFIGURAÇÃO DO PROVEDOR DE IA (LLM) E TELEGRAM
# =====================================================================
PROVIDER=""
API_KEY=""
MODEL=""

if whiptail --title "Configurar LLM" --yesno "Deseja configurar o provedor de IA (LLM) OpenRouter Gratuito? Isso permitirá que o OpenClaw já funcione no Chat, mas você precisa ter conta em https://openrouter.ai e gerar api key. Você pode pular e configurar depois manualmente. Use setas e enter para Yes ou No" 12 70; then
    while true; do
        PROVIDER_CHOICE=$(whiptail --title "Selecione o Provedor Openrouter" --menu "Escolha o provedor de IA OpenRouter ou selecione skip para configurar depois:" 18 60 6 \
            "openrouter" "OpenRouter (Modelos Gratuitos e Pagos)" \
            "skip" "Pular configuração" 3>&1 1>&2 2>&3)
        
        exit_status=$?
        if [ $exit_status != 0 ] || [ "$PROVIDER_CHOICE" = "skip" ]; then
            PROVIDER=""
            break
        fi

        API_KEY=$(whiptail --title "Chave da API" --inputbox "Digite sua chave de API para $PROVIDER_CHOICE:" 10 60 3>&1 1>&2 2>&3)
        if [ -z "$API_KEY" ]; then
            whiptail --msgbox "Chave não pode ser vazia. Tente novamente." 8 50
            continue
        fi


# Logica de seleção de modelos baseada no provedor
        if [ "$PROVIDER_CHOICE" = "openrouter" ]; then
            
            # Menu curado com modelos que comprovadamente suportam Tool Use no OpenClaw
            MODEL=$(whiptail --title "Modelos OpenRouter (Suporte a Tools)" --menu "Selecione um modelo testado e compatível:" 22 85 8 \
                "google/gemini-2.5-flash" "Gemini 2.5 Flash (Custo-Benefício, Rápido)" \
                "meta-llama/llama-3.3-70b-instruct:free" "Llama 3.3 70B (Gratuito, Alta Qualidade)" \
                "meta-llama/llama-3.1-8b-instruct:free" "Llama 3.1 8B (Gratuito, Rápido)" \
                "google/gemini-2.0-flash-exp:free" "Gemini 2.0 Flash Exp (Gratuito, Alta Velocidade)" \
                "anthropic/claude-3.5-sonnet" "Claude 3.5 Sonnet (Premium, O Melhor para Agentes)" \
                "MANUAL" ">>> Digitar ID de um modelo específico <<<" 3>&1 1>&2 2>&3)
            
            if [ -z "$MODEL" ]; then continue; fi

            # Opção de fuga para usuários avançados que querem testar outros modelos
            if [ "$MODEL" = "MANUAL" ]; then
                MODEL=$(whiptail --title "ID do Modelo" --inputbox "Digite o ID exato do modelo no OpenRouter (ex: openai/gpt-4o):" 10 60 3>&1 1>&2 2>&3)
                if [ -z "$MODEL" ]; then continue; fi
            fi
            

        else
            # Menus fixos e curados para os outros provedores
            case $PROVIDER_CHOICE in

                google)
                    MODEL=$(whiptail --title "Modelos Google Gemini" --menu "Selecione o modelo do Google:" 18 75 6 \
                        "gemini-2.5-flash" "Mais rápido e atual (Recomendado)" \
                        "gemini-2.5-pro" "Mais inteligente para tarefas complexas" \
                        "gemini-2.0-flash-exp" "Versão experimental de alta performance" \
                        "gemini-1.5-pro" "Modelo legado muito potente" \
                        "gemini-1.5-flash" "Modelo legado rápido e barato" \
                        "MANUAL" ">>> Digitar ID manualmente <<<" 3>&1 1>&2 2>&3)
                    DEFAULT_MODEL="gemini-2.5-flash"
                    ;;
            esac

            # Se o usuário cancelar no menu, volta para a tela inicial do LLM
            if [ -z "$MODEL" ]; then continue; fi

            # Se ele escolheu "MANUAL", abre a caixa de texto

        fi

        PROVIDER="$PROVIDER_CHOICE"
        break
    done
fi

if [ -z "$PROVIDER" ]; then
    PROVIDER="google"
    API_KEY="00000000000000000000"
    MODEL="gemini-2.5-flash"
fi

# =====================================================================
# CONFIGURAÇÃO DO TELEGRAM
# =====================================================================
TELEGRAM_ENABLED="false"
TELEGRAM_BOT_TOKEN=""
TELEGRAM_ALLOWED_ID=""

if whiptail --title "Configurar Telegram" --yesno "Deseja habilitar o bot do Telegram no OpenClaw agora?" 10 60; then
    TELEGRAM_ENABLED="true"
    
    # Solicitar o Token do Bot
    while true; do
        TELEGRAM_BOT_TOKEN=$(whiptail --title "Telegram Bot Token" --inputbox "Digite o Token do seu Bot do Telegram (obtido no @BotFather):" 10 70 3>&1 1>&2 2>&3)
        if [ -n "$TELEGRAM_BOT_TOKEN" ]; then
            break
        else
            whiptail --msgbox "O Token não pode estar vazio. Por favor, insira o Token fornecido pelo @BotFather." 8 60
        fi
    done

    # Solicitar o ID do Usuário
    while true; do
        TELEGRAM_ALLOWED_ID=$(whiptail --title "Telegram ID" --inputbox "Digite o seu ID do Telegram (apenas os números, ex: 123456789) para permissão de acesso:" 10 60 3>&1 1>&2 2>&3)
        if [[ "$TELEGRAM_ALLOWED_ID" =~ ^[0-9]+$ ]]; then
            break
        else
            whiptail --msgbox "Por favor, digite um ID numérico válido. Você pode obter isso com bots como @userinfobot." 8 60
        fi
    done
fi

#########################################################
# CRIAÇÃO DE DNS E ROTAS CLOUDFLARE TUNNEL
#########################################################
clear

export NEWT_COLORS='
root=,white
window=,black
border=white,black
textbox=white,black
button=black,white
'  

clear

{
echo -e "XXX\n5\nVERIFICANDO CONFIGURAÇÃO... \nXXX"

if [ "$INSTALL_TYPE" = "TRADICIONAL" ] && [ "$criar_dns" = "0" ]; then
    echo -e "XXX\n10\nCONFIGURANDO DNS AUTOMÁTICO (TRADICIONAL)... \nXXX"
    DOMINIO_PRINCIPAL=$(echo "$urlopenclaw" | cut -d'.' -f2-)
    
    EXISTING_RECORDS=$(curl -s -X GET \
        "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records?name=${urlopenclaw}" \
        -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
        -H "Content-Type: application/json")

    COUNT=$(echo "$EXISTING_RECORDS" | jq '.result | length')
    if [[ "$COUNT" -gt 0 ]]; then
        echo -e "XXX\n20\nREMOVENDO REGISTROS ANTIGOS... \nXXX"
        echo "$EXISTING_RECORDS" | jq -r '.result[].id' | while read -r REC_ID; do
            [[ -z "$REC_ID" ]] && continue
            curl -s -X DELETE \
                "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records/${REC_ID}" \
                -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
                -H "Content-Type: application/json" >/dev/null 2>&1
        done
    fi

    echo -e "XXX\n25\nCRIANDO REGISTRO CNAME... \nXXX"
    CNAME_RESPONSE=$(curl -s -X POST \
        "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records" \
        -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
        -H "Content-Type: application/json" \
        --data '{"type":"CNAME","name":"'${urlopenclaw}'","content":"'${nome_servidor}'.'${DOMINIO_PRINCIPAL}'","ttl":1,"proxied":false}')

    if echo "$CNAME_RESPONSE" | grep -q '"success":true'; then
        echo -e "XXX\n30\nREGISTRO CNAME CRIADO COM SUCESSO! \nXXX"
    else
        echo -e "XXX\n30\nAVISO: ERRO AO CRIAR REGISTRO CNAME \nXXX"
    fi

elif [ "$INSTALL_TYPE" = "CLOUDFLARE_TUNNEL" ]; then
    echo -e "XXX\n10\nCONFIGURANDO CLOUDFLARE TUNNEL (DNS + ROTAS)... \nXXX"
    
    EXISTING_RECORDS=$(curl -s -X GET \
        "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records?name=${urlopenclaw}" \
        -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
        -H "Content-Type: application/json")

    COUNT=$(echo "$EXISTING_RECORDS" | jq '.result | length')
    if [[ "$COUNT" -gt 0 ]]; then
        echo "$EXISTING_RECORDS" | jq -r '.result[].id' | while read -r REC_ID; do
            [[ -z "$REC_ID" ]] && continue
            curl -s -X DELETE \
                "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records/${REC_ID}" \
                -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
                -H "Content-Type: application/json" >/dev/null 2>&1
        done
    fi

    DNS_RESPONSE=$(curl -s -X POST \
        "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records" \
        -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
        -H "Content-Type: application/json" \
        --data "{\"type\":\"CNAME\",\"name\":\"${urlopenclaw}\",\"content\":\"${TUNNEL_ID}.cfargotunnel.com\",\"ttl\":1,\"proxied\":true}")

    echo -e "XXX\n35\nATUALIZANDO CONFIGURAÇÃO DO TUNNEL... \nXXX"
    NEW_SERVICE="http://${nome_app}-gateway:18789"
    
    TIMESTAMP=$(date -u +%Y%m%dT%H%M%SZ)
    TMPDIR=$(mktemp -d)
    BACKUP_RAW="$TMPDIR/backup_raw.$TIMESTAMP.json"
    TO_PUT="$TMPDIR/to_put.$TIMESTAMP.json"

    curl -sS -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
      "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/cfd_tunnel/$TUNNEL_ID/configurations" \
      | jq '.' > "$BACKUP_RAW"

    jq --arg host "$urlopenclaw" --arg service "$NEW_SERVICE" '
      (.result.config // {}) as $cfg
      | ($cfg.ingress // []) as $ing
      | ($ing | map(select(.service != "http_status:404"))) as $clean
      
      | ($clean | map(select(.hostname != $host))) as $filtered
      | ($filtered + [ { hostname: $host, service: $service, originRequest: { noTlsVerify: true, httpHostHeader: $host } } ]) as $merged
      | ($merged + [{ service: "http_status:404" }]) as $final_ing
      | ($cfg + { ingress: $final_ing }) as $newcfg
      | { config: $newcfg }
    ' "$BACKUP_RAW" > "$TO_PUT"

    APPLY_RESPONSE=$(curl -sS -X PUT "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/cfd_tunnel/$TUNNEL_ID/configurations" \
      -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
      -H "Content-Type: application/json" \
      --data-binary @"$TO_PUT")

    rm -rf "$TMPDIR"

else
    echo -e "XXX\n10\nVERIFICANDO CONFIGURAÇÃO (TRADICIONAL SEM AUTOMAÇÃO)... \nXXX"
    if ! nslookup "$urlopenclaw" >/dev/null 2>&1; then
        echo -e "XXX\n15\nAVISO: VERIFIQUE A CONFIGURAÇÃO DNS \nXXX"
    fi
fi

if [ "$INSTALL_TYPE" = "TRADICIONAL" ] && [ "$criar_dns" = "1" ]; then
    ip_servidor=$(curl -s --max-time 10 ipinfo.io/ip)
    echo -e "XXX\n3\nVERIFICANDO SUBDOMÍNIO: $urlopenclaw \nXXX"
    sleep 3

    tentativas=5
    tentativa_atual=1
    sucesso=0

    while [ $tentativa_atual -le $tentativas ]; do
        echo -e "XXX\n$(( (tentativa_atual * 12) / tentativas + 3 ))\nTentativa $tentativa_atual de $tentativas...\nXXX"
        dns_ip=$(timeout 10 nslookup -type=A "$urlopenclaw" | grep -E "Address: [0-9]+\." | awk '{print $2}' | head -n1)
        if [[ -n "$dns_ip" && "$dns_ip" == "$ip_servidor" ]]; then
            sucesso=1
            break
        fi
        sleep 1
        ((tentativa_atual++))
    done

    if [ $sucesso -eq 0 ]; then
        echo -e "XXX\n10\nERRO: SUBDOMÍNIO NÃO APONTA PARA O IP ($ip_servidor) \nXXX"
        sleep 3
        exit 1
    fi
fi


#######################################################
# GERANDO OPENCLAW.JSON E PREPARANDO VOLUMES
#######################################################
echo -e "XXX\n85\nCONFIGURANDO OPENCLAW.JSON... \nXXX"

# CRIAÇÃO DO JSON BASE (Seu código original de criação do TMP_JSON e jq vem aqui)
TMP_JSON=$(mktemp)
cat > "$TMP_JSON" << EOF
{
  "logging": { "level": "info" },
  "commands": { "native": "auto", "nativeSkills": $NATIVE_SKILLS, "restart": true, "ownerDisplay": "raw" },
  "channels": {
    "whatsapp": { "enabled": false, "dmPolicy": "pairing", "allowFrom": [], "groupPolicy": "allowlist", "groups": {"*": {"requireMention": true}}, "debounceMs": 0, "mediaMaxMb": 50 }
  },
  "gateway": {
    "port": 18789,
    "mode": "local",
    "bind": "lan",
    "controlUi": {
      "enabled": true,
      "dangerouslyDisableDeviceAuth": true,
      "allowedOrigins": [ "https://$urlopenclaw" ]
    },
    "auth": { "mode": "token", "token": "$key" },
    "trustedProxies": [ "127.0.0.1", "10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16" ],
    "tailscale": { "mode": "off", "resetOnExit": false },
    "remote": { "url": "ws://$nome_app-gateway:18789" }
  },
  "plugins": {
    "entries": { "whatsapp": { "enabled": false }, "telegram": { "enabled": false } }
  },
  "auth": { "profiles": {} },
  "models": { "providers": {} },
  "agents": {
     "defaults": { "models": {}, "workspace": "/home/node/.openclaw/workspace" }
  }
}
EOF

# [AQUI VEM O SEU CÓDIGO ORIGINAL DO JQ PARA INJETAR O PROVIDER DE IA E O TELEGRAM]
# ...
# INJETANDO PROVEDOR DE IA COM JQ
if [ -n "$PROVIDER" ]; then
    FINAL_JSON=$(mktemp)
    if [ "$PROVIDER" = "google" ]; then
        jq --arg key "$API_KEY" --arg model "$MODEL" '
            .auth.profiles["google:default"] = {"provider": "google", "mode": "api_key"} |
            .models.providers.google = {"apiKey": $key, "baseUrl": "https://generativelanguage.googleapis.com/v1beta", "api": "google-generative-ai", "models": [{"id": $model, "name": "Google \($model)", "input": ["text", "image"], "contextWindow": 1000000}]} |
            .agents.defaults.model.primary = "google/\($model)" |
            .agents.defaults.models["google/\($model)"] = {}
        ' "$TMP_JSON" > "$FINAL_JSON"
    elif [ "$PROVIDER" = "openrouter" ]; then
        jq --arg key "$API_KEY" --arg model "$MODEL" '
            .auth.profiles["openrouter:default"] = {"provider": "openrouter", "mode": "api_key"} |
            .models.providers.openrouter = {"apiKey": $key, "baseUrl": "https://openrouter.ai/api/v1", "api": "openai-responses", "models": [{"id": $model, "name": "OpenRouter \($model)", "input": ["text", "image"], "contextWindow": 128000}]} |
            .agents.defaults.model.primary = "openrouter/\($model)" |
            .agents.defaults.models["openrouter/\($model)"] = {}
        ' "$TMP_JSON" > "$FINAL_JSON"
    fi
    mv "$FINAL_JSON" "$TMP_JSON"
fi

# INJETANDO TELEGRAM COM JQ SE ATIVADO
if [ "$TELEGRAM_ENABLED" = "true" ]; then
    FINAL_JSON=$(mktemp)
    jq --arg tg_id "$TELEGRAM_ALLOWED_ID" --arg tg_token "$TELEGRAM_BOT_TOKEN" '
        .plugins.entries.telegram.enabled = true |
        .channels.telegram = {
            "enabled": true,
            "botToken": $tg_token,
            "dmPolicy": "pairing",
            "allowFrom": [$tg_id],
            "groupPolicy": "allowlist",
            "streaming": "partial"
        }
    ' "$TMP_JSON" > "$FINAL_JSON"
    mv "$FINAL_JSON" "$TMP_JSON"
fi

echo -e "XXX\n90\nINJETANDO CONFIGURAÇÕES NO VOLUME... \nXXX"

# CRIA O VOLUME DOCKER ANTES DO DEPLOY
docker volume create $nome_app-data >/dev/null 2>&1

# USA UM CONTÊINER TEMPORÁRIO PARA COPIAR O ARQUIVO PARA O VOLUME COM AS PERMISSÕES CORRETAS
docker run --rm -v $nome_app-data:/data -v "$TMP_JSON":/tmp/config.json alpine sh -c "cp /tmp/config.json /data/openclaw.json && chown -R 1000:1000 /data && chmod 644 /data/openclaw.json"

rm -f "$TMP_JSON"



#######################################################
#  INSTALAÇÃO DO OPENCLAW
#######################################################
echo -e "XXX\n65\nCRIANDO STACK DO OPENCLAW... \nXXX"
cd ~/

cat > $nome_app.yaml << EOL
version: "3.9"

services:
  $nome_app-gateway:
    image: openclaw/openclaw:latest
    hostname: $nome_app-gateway
    container_name: $nome_app-gateway
    init: true
    restart: unless-stopped
    command: >
      sh -c "if [ ! -d '/home/node/.openclaw/extensions/whatsapp' ]; then openclaw plugins install clawhub:@openclaw/whatsapp; fi && exec openclaw gateway --bind lan --port 18789"
    networks:
      - externa
      - interna
    volumes:
      - $nome_app-data:/home/node/.openclaw
      - $nome_app-workspace:/home/node/.openclaw/workspace
    ports:
      - "18789:18789"
    environment:
      - HOME=/home/node
      - TERM=xterm-256color
      - OPENCLAW_CONFIG=/home/node/.openclaw/openclaw.json
      - OPENCLAW_GATEWAY_TOKEN=$key
      - OPENCLAW_GATEWAY_MODE=local
      - OPENCLAW_GATEWAY_TRUSTED_PROXIES=127.0.0.1
      - OPENCLAW__GATEWAY__CONTROLUI__DANGEROUSLYALLOWHOSTHEADERORIGINFALLBACK=true

    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
          - node.role == manager
EOL

if [ "$INSTALL_TYPE" = "TRADICIONAL" ]; then
cat >> $nome_app.yaml << EOL
      labels:
        - traefik.enable=true
        - traefik.docker.network=externa
        - traefik.http.routers.$nome_app-gateway.rule=Host(\`$urlopenclaw\`)
        - traefik.http.routers.$nome_app-gateway.entrypoints=websecure
        - traefik.http.routers.$nome_app-gateway.priority=1
        - traefik.http.routers.$nome_app-gateway.tls.certresolver=letsencryptresolver
        - traefik.http.routers.$nome_app-gateway.service=$nome_app-gateway
        - traefik.http.routers.$nome_app-gateway.middlewares=websocket-headers@docker
        - traefik.http.services.$nome_app-gateway.loadbalancer.server.port=18789
        - traefik.http.services.$nome_app-gateway.loadbalancer.passHostHeader=true
        - traefik.http.middlewares.redirect-to-secure.redirectscheme.scheme=https
        - traefik.http.middlewares.websocket-headers.headers.customrequestheaders.X-Forwarded-Proto=https
        - traefik.http.middlewares.websocket-headers.headers.customrequestheaders.X-Forwarded-Port=443
EOL
fi

cat >> $nome_app.yaml << EOL

volumes:
  $nome_app-data:
    external: true
    name: $nome_app-data
  $nome_app-workspace:
    external: true
    name: $nome_app-workspace

networks:
  externa:
    external: true
  interna:
    external: true
EOL

echo -e "XXX\n70\nIMPLANTANDO OPENCLAW... \nXXX"

if [[ "$criar_portainer" == "0" ]]; then
    echo -e "XXX\n76\nCRIANDO STACK NO PORTAINER 3/4  \nXXX"
    dados_file="$HOME/dados_portainer/dados_portainer"
    
    if [[ -f "$dados_file" ]]; then
        PORTAINER_URL=$(grep "Dominio do portainer:" "$dados_file" | cut -d':' -f2 | xargs)
        ADMIN_USERNAME=$(grep "Usuario:" "$dados_file" | cut -d':' -f2 | xargs)
        ADMIN_PASSWORD=$(grep "Senha:" "$dados_file" | cut -d':' -f2 | xargs)
        STACK_NAME=$nome_app
        STACK_FILE_PATH="/root/$nome_app.yaml"
    else
        docker stack deploy --prune --resolve-image always -c $nome_app.yaml $nome_app >/dev/null 2>&1
    fi

    get_auth_token() {
        RESPONSE=$(curl -sS -X POST "https://$PORTAINER_URL/api/auth" -H "Content-Type: application/json" -d "{\"username\": \"$ADMIN_USERNAME\", \"password\": \"$ADMIN_PASSWORD\"}")
        TOKEN=$(echo "$RESPONSE" | jq -r '.jwt')
        if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]; then
            docker stack deploy --prune --resolve-image always -c $nome_app.yaml $nome_app >/dev/null 2>&1
            return 1
        fi
    }

    get_endpoint_id() {
        RESPONSE=$(curl -sS -X GET "https://$PORTAINER_URL/api/endpoints" -H "Authorization: Bearer $TOKEN")
        ENDPOINT_ID=$(echo "$RESPONSE" | jq -r '.[0].Id')
    }

    get_swarm_id() {
        RESPONSE=$(curl -sS -X GET "https://$PORTAINER_URL/api/endpoints/$ENDPOINT_ID/docker/swarm" -H "Authorization: Bearer $TOKEN")
        SWARM_ID=$(echo "$RESPONSE" | jq -r '.ID')
    }

    create_stack() {
        response_output=$(mktemp)
        erro_output=$(mktemp)
        http_code=$(curl -s -o "$response_output" -w "%{http_code}"  -X POST \
            -H "Authorization: Bearer $TOKEN" \
            -F "Name=$STACK_NAME" -F "file=@$STACK_FILE_PATH" \
            -F "SwarmID=$SWARM_ID" -F "endpointId=$ENDPOINT_ID" \
            "https://$PORTAINER_URL/api/stacks/create/swarm/file" 2> "$erro_output")
        rm -f "$response_output" "$erro_output"
        
        if [ "$http_code" -ne 200 ]; then
            docker stack deploy --prune --resolve-image always -c $nome_app.yaml $nome_app >/dev/null 2>&1
        fi
    }

    if [[ -f "$dados_file" ]]; then
        get_auth_token && get_endpoint_id && get_swarm_id && create_stack
    fi

elif [[ "$criar_portainer" == "1" ]]; then
    docker stack deploy --prune --resolve-image always -c $nome_app.yaml $nome_app >/dev/null 2>&1
else
    docker stack deploy --prune --resolve-image always -c $nome_app.yaml $nome_app >/dev/null 2>&1
fi


echo -e "XXX\n100\nINSTALAÇÃO DO OPENCLAW CONCLUÍDA! \nXXX"
sleep 3

}|whiptail --title "OPENCLAW - PROGRESSO DA INSTALAÇÃO" --gauge "Aguarde a instalação do OpenClaw" 6 60 0

#######################################################
# VERIFICAÇÃO FINAL
#######################################################

if [ "$INSTALL_TYPE" = "TRADICIONAL" ]; then
    ip_servidor=$(curl -s --max-time 10 ipinfo.io/ip)
    dns_ip=$(timeout 10 nslookup "$urlopenclaw" | grep "Address" | tail -n1 | awk '{print $2}' 2>/dev/null)

    if [[ "$dns_ip" != "$ip_servidor" ]]; then
        whiptail --title "Mensagem" --msgbox "Não foi possivel acessar o dominio do OpenClaw ($urlopenclaw). A instalação foi cancelada. Por favor, verifique se os apontamentos DNS estão corretos e propagados!. Depois, instale novamente. Pressione ENTER para voltar ao Menu Principal" 20 78
    else
        whiptail --title "Mensagem" --msgbox "Parabéns, OpenClaw foi instalado com sucesso!\n\nAcesse: https://$urlopenclaw\nSalve o seu Gateway Token: $key\n\nPressione ENTER para voltar ao Menu Principal" 20 78
    fi
else
    if timeout 10 nslookup "$urlopenclaw" >/dev/null 2>&1; then
        whiptail --title "Mensagem" --msgbox "Parabéns, OpenClaw foi instalado com sucesso!\n\nAcesse: https://$urlopenclaw\n\nConfiguração Cloudflare Tunnel concluída com rotas e DNS.\nSalve o seu Gateway Token: $key\n\nPressione ENTER para voltar ao Menu Principal" 20 78
    else
        whiptail --title "Mensagem" --msgbox "AVISO: O domínio do OpenClaw ($urlopenclaw) não está resolvendo.\nVerifique a configuração do Cloudflare Tunnel.\n\nA instalação foi concluída, mas o acesso pode não funcionar até que o DNS esteja configurado corretamente.\n\nPressione ENTER para voltar ao Menu Principal" 20 78
    fi
fi

exit 0

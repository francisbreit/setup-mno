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
    if [ -f "/root/.cloudflared_config/cloudflare_credentials" ]; then
        source "/root/.cloudflared_config/cloudflare_credentials"
    fi
else
    if [ -f "/root/.tradicional_config/tradicional_credentials" ]; then
        source "/root/.tradicional_config/tradicional_credentials"
    fi
fi

function msg() {
    msg=$1
    whiptail --title "SETUP OPENCLAW + QDRANT + NEO4J + COGNEE + SEARXNG" --msgbox "$msg" --fb 10 70
}

while true; do
CHOICE=$(
whiptail --title "SETUP OPENCLAW + QDRANT + NEO4J + COGNEE + SEARXNG" --menu "Aperte ENTER para iniciar a instalação do OPENCLAW COMBO PRO BLINDADO ou selecione SAIR (Utilize setas e Enter)\n\nTIPO DE INSTALAÇÃO DETECTADA: $INSTALL_TYPE\n\nINSTRUÇÕES:\nAntes de prosseguir, verifique os registros DNS conforme seu tipo de instalação:" 20 70 2 \
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
    urlopenclaw=$(whiptail --title "1/10 - URL do OpenClaw" --inputbox "Digite o Link do OpenClaw (ex: openclaw.seudominio.com):" --fb 12 60 3>&1 1>&2 2>&3)
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
    key=$(whiptail --title "2/10 - Gateway Token OpenClaw" --inputbox "Digite o Gateway Token do OpenClaw (sugestão gerada aleatoriamente: $chave_hexadecimal):" --fb 12 60 "$chave_hexadecimal" 3>&1 1>&2 2>&3) ; saida=$?
    if [[ $saida -eq '0' ]] ; then
        if [[ -z $key ]] ; then msg "Crie um Gateway Token para o OpenClaw, para poder continuar" ; continue ; else break; fi
    else
        echo $key ; echo "saindo..."  &  exit 0 ;
    fi
done

# SOLICITAR ASSISTENTE SYSADMIN (nativeSkills)
while true; do
    SYSADMIN_CHOICE=$(whiptail --title "3/10 - Assistente Sysadmin Autônomo (Segurança)" --menu "O OpenClaw pode funcionar como um 'Assistente de Sistema', permitindo que a IA vasculhe e altere arquivos da própria instalação.\n\n⚠️ RISCO: Se você vai usar esse robô para atender clientes no WhatsApp, pessoas mal-intencionadas podem enganar a IA para vazar ou apagar informações. Além disso, a IA pode tentar rodar vários comandos e gastar seus créditos rapidamente.\n\nRecomendamos fortemente manter DESLIGADO." 22 75 2 \
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


# SOLICITAR URL DO NEO4J LAB
while true; do
    urlneo4j=$(whiptail --title "4/10 - URL do NEO4J Browser" --inputbox "Digite o Link de acesso visual do NEO4J (ex: grafos.seudominio.com):" --fb 12 60 3>&1 1>&2 2>&3)
    saida=$?
    if [[ $saida -eq '0' ]]; then
        if [[ -z $urlneo4j ]]; then 
            msg "Digite o link para poder continuar"
            continue
        else 
            break
        fi
    else
        echo $urlneo4j
        echo "saindo..."
        exit 0
    fi
done


admin_password_hex=$(openssl rand -hex 12)
while true ; do
    admin_password=$(whiptail --title "5/10 - Senha do Neo4j" --inputbox "Crie uma senha forte para o banco Neo4j (Usuário padrão será 'neo4j').\n\nSugestão gerada: $admin_password_hex" --fb 12 75 "$admin_password_hex" 3>&1 1>&2 2>&3) ; saida=$?
    if [[ $saida -eq '0' ]] ; then
        if [[ -z $admin_password ]] ; then msg "Crie uma senha para continuar" ; continue ; else break; fi
    else
        echo $admin_password ; echo "saindo..."  &  exit 0 ;
    fi
done



# SOLICITAR URL DO QDRANT
while true; do
    urlqdrant=$(whiptail --title "6/10 - URL do Qdrant" --inputbox "Digite o Link de acesso ao Qdrant (ex: vetor.seudominio.com):" --fb 12 60 3>&1 1>&2 2>&3)
    saida=$?
    if [[ $saida -eq '0' ]]; then
        if [[ -z $urlqdrant ]]; then 
            msg "Digite o link para poder continuar"
            continue
        else 
            break
        fi
    else
        echo $urlqdrant
        echo "saindo..."
        exit 0
    fi
done

api_key_qd=$(openssl rand -hex 32)
while true ; do
    auth_secretqd=$(whiptail --title "7/10 - API Key do Qdrant" --inputbox "Digite uma chave de API, do Qdrant,  para proteger seu Banco Vetorial (sugestão gerada aleatoriamente: $api_key_qd):" --fb 12 75 "$api_key_qd" 3>&1 1>&2 2>&3) ; saida=$?
    if [[ $saida -eq '0' ]] ; then
        if [[ -z $auth_secretqd ]] ; then msg "Crie uma API Key para continuar" ; continue ; else break; fi
    else
        echo $auth_secretqd ; echo "saindo..."  &  exit 0 ;
    fi
done


# SOLICITAR URL DO COGNEE
while true; do
    urlcognee=$(whiptail --title "8/10 - URL do Cognee" --inputbox "Digite o Link de acesso da API do Cognee (ex: memoria.seudominio.com):" --fb 12 60 3>&1 1>&2 2>&3)
    saida=$?
    if [[ $saida -eq '0' ]]; then
        if [[ -z $urlcognee ]]; then 
            msg "Digite o link para poder continuar"
            continue
        else 
            break
        fi
    else
        echo $urlcognee
        echo "saindo..."
        exit 0
    fi
done

auth_secret_hex_sear=$(openssl rand -hex 32)
while true ; do
    auth_secret_sear=$(whiptail --title "9/10 - Auth Secret SearXng" --inputbox "Digite uma chave secreta do SearXng para criptografia interna do buscador (sugestão gerada aleatoriamente: $auth_secret_hex_sear):" --fb  12 75 "$auth_secret_hex_sear" 3>&1 1>&2 2>&3) ; saida=$?
    if [[ $saida -eq '0' ]] ; then
        if [[ -z $auth_secret_sear ]] ; then msg "Crie um Auth Secret SearXng para continuar" ; continue ; else break; fi
    else
        echo $auth_secret_sear ; echo "saindo..."  &  exit 0 ;
    fi
done


# SOLICITAR SE CRIA STACK NO PORTAINER
while true; do
    criar_portainer=$(whiptail --title "10/10 - Criar Stack no Portainer? - 0 ou 1" --inputbox "Digite 0 para poder editar stack no portainer ou 1 para não poder editar" --fb 12 60 3>&1 1>&2 2>&3)
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

nome_openclaw="openclaw"
sufixo_app=$(date | md5sum | head -c7)
nome_app_openclaw=$nome_openclaw$sufixo_app

nome_neo4j="neo4j"
nome_app_neo4j=$nome_neo4j$sufixo_app

nome_qdrant="qdrant"
nome_app_qdrant=$nome_qdrant$sufixo_app

nome_cognee="cognee"
nome_app_cognee=$nome_cognee$sufixo_app

nome_searxng="searxng"
nome_app_searxng=$nome_searxng$sufixo_app


{
  tput reset 2>/dev/null
  exec 0</dev/tty 1>/dev/tty 2>&1
  sleep 0.01
  clear
} || true

whiptail --title "Dados Fornecidos" \
 --msgbox "TIPO DE INSTALAÇÃO: $INSTALL_TYPE\n\nDados Preenchidos:\n\n1) Url do OpenClaw: $url$urlopenclaw\n2) Gateway Token: $key\n3) Assistente Sysadmin: $SYSADMIN_CHOICE\n4) Url do NEO4J: $urlneo4j\n5) Senha do NEO4J: $admin_password\n6) Url do Qdrant: $urlqdrant\n7) API Key Qdrant: $auth_secretqd\n8) URL Cognee: $urlcognee\n9) Auth Secret SearXng: $auth_secret_sear\n10) Criar Stack no Portainer: $([ "$criar_portainer" == "0" ] && echo "0 (Editável)" || echo "1 (Não editável)")\n\nConfira e Tecle Enter para continuar." \
 --fb 26 80

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

if whiptail --title "Configurar LLM" --yesno "Deseja configurar o provedor de IA (LLM)? Recomendamos a OpenAI (GPT-4.1-mini) para máxima estabilidade no uso das ferramentas de busca." 10 70; then

    whiptail --title "Aviso sobre Provedores de IA" --msgbox "Antes de escolher, entenda as opções:\n\n1. OpenAI (Pago): Recomendado. Use o GPT-4.1-mini. É o rei do custo-benefício, obedece rigorosamente às ferramentas e custa frações de centavos.\n2. Anthropic (Pago): Claude 3.5. Excelente escrita e raciocínio lógico avançado, porém com custo um pouco maior.\n3. xAI/Grok (Pago): Modelos sem filtros rígidos e super rápidos.\n4. Google Gemini (Grátis/Pago): 2.5 Flash. Excelente para testes pois tem plano 100% gratuito (AI Studio), mas a obediência a regras estritas pode variar.\n\nFique tranquilo: Você poderá testar e trocar o provedor e a chave de API a qualquer momento depois da instalação direto no painel do OpenClaw!" 22 75

    while true; do
        PROVIDER_CHOICE=$(whiptail --title "Selecione o Provedor de IA principal" --menu "Escolha o cérebro do seu robô:" 18 70 6 \
            "openai" "OpenAI (Recomendado - gpt-4.1-mini)" \
            "google" "Google Gemini (Plano Gratuito disponível)" \
            "anthropic" "Anthropic (Claude 3 / 3.5)" \
            "xai" "xAI (Grok-2)" \
            "openrouter" "OpenRouter (Múltiplos modelos gratuitos e pagos)" \
            "skip" "Pular configuração" 3>&1 1>&2 2>&3)

        exit_status=$?
        if [ $exit_status != 0 ] || [ "$PROVIDER_CHOICE" = "skip" ]; then
            PROVIDER=""
            break
        fi

        API_KEY=$(whiptail --title "Chave da API" --inputbox "Digite sua chave de API para $PROVIDER_CHOICE:" 10 70 3>&1 1>&2 2>&3)
        if [ -z "$API_KEY" ]; then
            whiptail --msgbox "Chave não pode ser vazia. Tente novamente." 8 50
            continue
        fi

        case $PROVIDER_CHOICE in
            openai)
                MODEL=$(whiptail --title "Modelos OpenAI" --menu "Selecione o modelo:" 15 65 3 \
                    "gpt-4.1-mini" "Muito rápido e barato (Recomendado)" \
                    "gpt-4o" "Mais inteligente, porém mais caro" \
                    "MANUAL" ">>> Digitar ID manualmente <<<" 3>&1 1>&2 2>&3)
                ;;
            anthropic)
                MODEL=$(whiptail --title "Modelos Anthropic" --menu "Selecione o modelo:" 15 65 3 \
                    "claude-3-haiku-20240307" "Rápido e barato" \
                    "claude-3-5-sonnet-latest" "Poderoso e inteligente (Recomendado)" \
                    "MANUAL" ">>> Digitar ID manualmente <<<" 3>&1 1>&2 2>&3)
                ;;
            xai)
                MODEL=$(whiptail --title "Modelos xAI" --menu "Selecione o modelo:" 15 65 3 \
                    "grok-beta" "Versão beta rápida" \
                    "grok-2-latest" "Versão final (Recomendado)" \
                    "MANUAL" ">>> Digitar ID manualmente <<<" 3>&1 1>&2 2>&3)
                ;;
            google)
                MODEL=$(whiptail --title "Modelos Google Gemini" --menu "Selecione o modelo:" 18 75 5 \
                    "gemini-2.5-flash" "Mais rápido e atual (Recomendado)" \
                    "gemini-2.5-pro" "Mais inteligente para tarefas complexas" \
                    "gemini-1.5-flash" "Modelo legado rápido e barato" \
                    "MANUAL" ">>> Digitar ID manualmente <<<" 3>&1 1>&2 2>&3)
                ;;
            openrouter)
                whiptail --infobox "Buscando modelos gratuitos no OpenRouter via API...\nPor favor, aguarde." 8 60
                models_raw=$(curl -s https://openrouter.ai/api/v1/models | jq -r '.data[] | select(.pricing != null and (.pricing.prompt == "0" or .pricing.prompt == "0.0") and (.pricing.completion == "0" or .pricing.completion == "0.0")) | "\(.id)|\(.name)"' | head -n 20)
                if [ -z "$models_raw" ]; then
                    whiptail --msgbox "Não foi possível carregar a lista do OpenRouter agora.\nUsaremos um modelo padrão de fallback." 8 60
                    MODEL="meta-llama/llama-3.1-8b-instruct:free"
                else
                    unset MENU_OPTIONS
                    declare -a MENU_OPTIONS
                    while IFS="|" read -r id name; do
                        clean_name=$(echo "$name" | cut -c 1-45)
                        MENU_OPTIONS+=("$id" "$clean_name")
                    done <<< "$models_raw"
                    MENU_OPTIONS+=("MANUAL" ">>> Digitar ID manualmente <<<")
                    MODEL=$(whiptail --title "Modelos OpenRouter (Gratuitos)" --menu "Selecione um modelo:" 22 85 12 "${MENU_OPTIONS[@]}" 3>&1 1>&2 2>&3)
                fi
                ;;
        esac

        if [ "$MODEL" = "MANUAL" ]; then
            MODEL=$(whiptail --title "Modelo Manual" --inputbox "Digite o ID exato do modelo:" 10 60 3>&1 1>&2 2>&3)
        fi

        if [ -z "$MODEL" ]; then continue; fi

        PROVIDER="$PROVIDER_CHOICE"
        break
    done
fi

if [ -z "$PROVIDER" ]; then
    PROVIDER="openai"
    API_KEY="00000000000000000000"
    MODEL="gpt-4.1-mini"
fi

# =====================================================================
# CONFIGURAÇÃO DO TELEGRAM
# =====================================================================
TELEGRAM_ENABLED="false"
TELEGRAM_BOT_TOKEN=""
TELEGRAM_ALLOWED_ID=""

if whiptail --title "Configurar Telegram" --yesno "Deseja habilitar o bot do Telegram no OpenClaw agora?" 10 60; then
    TELEGRAM_ENABLED="true"
    
    while true; do
        TELEGRAM_BOT_TOKEN=$(whiptail --title "Telegram Bot Token" --inputbox "Digite o Token do seu Bot do Telegram (obtido no @BotFather):" 10 70 3>&1 1>&2 2>&3)
        if [ -n "$TELEGRAM_BOT_TOKEN" ]; then
            break
        else
            whiptail --msgbox "O Token não pode estar vazio. Por favor, insira o Token fornecido pelo @BotFather." 8 60
        fi
    done

    while true; do
        TELEGRAM_ALLOWED_ID=$(whiptail --title "Telegram ID" --inputbox "Digite o seu ID do Telegram (apenas os números, ex: 123456789) para permissão de acesso:" 10 60 3>&1 1>&2 2>&3)
        if [[ "$TELEGRAM_ALLOWED_ID" =~ ^[0-9]+$ ]]; then
            break
        else
            whiptail --msgbox "Por favor, digite um ID numérico válido. Você pode obter isso com bots como @userinfobot." 8 60
        fi
    done
fi

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

#########################################################
# CRIAÇÃO DE DNS E ROTAS CLOUDFLARE TUNNEL NEO4J
#########################################################

echo -e "XXX\n5\nVERIFICANDO CONFIGURAÇÃO... \nXXX"

if [ "$INSTALL_TYPE" = "TRADICIONAL" ] && [ "$criar_dns" = "0" ]; then
    echo -e "XXX\n2\nCONFIGURANDO DNS AUTOMÁTICO (TRADICIONAL)... \nXXX"
    DOMINIO_PRINCIPAL=$(echo "$urlneo4j" | cut -d'.' -f2-)
    
    EXISTING_RECORDS=$(curl -s -X GET \
        "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records?name=${urlneo4j}" \
        -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
        -H "Content-Type: application/json")

    COUNT=$(echo "$EXISTING_RECORDS" | jq '.result | length')
    if [[ "$COUNT" -gt 0 ]]; then
        echo -e "XXX\n3\nREMOVENDO REGISTROS ANTIGOS... \nXXX"
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
        --data '{"type":"CNAME","name":"'${urlneo4j}'","content":"'${nome_servidor}'.'${DOMINIO_PRINCIPAL}'","ttl":1,"proxied":false}')

    if echo "$CNAME_RESPONSE" | grep -q '"success":true'; then
        echo -e "XXX\n5\nREGISTRO CNAME CRIADO COM SUCESSO! \nXXX"
    else
        echo -e "XXX\n5\nAVISO: ERRO AO CRIAR REGISTRO CNAME \nXXX"
    fi

elif [ "$INSTALL_TYPE" = "CLOUDFLARE_TUNNEL" ]; then
    echo -e "XXX\n10\nCONFIGURANDO CLOUDFLARE TUNNEL (DNS + ROTAS)... \nXXX"
    
    EXISTING_RECORDS=$(curl -s -X GET \
        "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records?name=${urlneo4j}" \
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
        --data "{\"type\":\"CNAME\",\"name\":\"${urlneo4j}\",\"content\":\"${TUNNEL_ID}.cfargotunnel.com\",\"ttl\":1,\"proxied\":true}")

    echo -e "XXX\n14\nATUALIZANDO CONFIGURAÇÃO DO TUNNEL... \nXXX"
    # A porta 3000 é a interface visual do NEO4J Lab
    NEW_SERVICE="http://${nome_app_neo4j}-web:7474"
    
    TIMESTAMP=$(date -u +%Y%m%dT%H%M%SZ)
    TMPDIR=$(mktemp -d)
    BACKUP_RAW="$TMPDIR/backup_raw.$TIMESTAMP.json"
    TO_PUT="$TMPDIR/to_put.$TIMESTAMP.json"

    curl -sS -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
      "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/cfd_tunnel/$TUNNEL_ID/configurations" \
      | jq '.' > "$BACKUP_RAW"

    jq --arg host "$urlneo4j" --arg service "$NEW_SERVICE" '
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
    echo -e "XXX\n19\nVERIFICANDO CONFIGURAÇÃO (TRADICIONAL SEM AUTOMAÇÃO)... \nXXX"
    if ! nslookup "$urlneo4j" >/dev/null 2>&1; then
        echo -e "XXX\n20\nAVISO: VERIFIQUE A CONFIGURAÇÃO DNS \nXXX"
    fi
fi

if [ "$INSTALL_TYPE" = "TRADICIONAL" ] && [ "$criar_dns" = "1" ]; then
    ip_servidor=$(curl -s --max-time 10 ipinfo.io/ip)
    echo -e "XXX\n23\nVERIFICANDO SUBDOMÍNIO: $urlneo4j \nXXX"
    sleep 3

    tentativas=5
    tentativa_atual=1
    sucesso=0

    while [ $tentativa_atual -le $tentativas ]; do
        echo -e "XXX\n$(( (tentativa_atual * 12) / tentativas + 3 ))\nTentativa $tentativa_atual de $tentativas...\nXXX"
        dns_ip1=$(timeout 10 nslookup -type=A "$urlneo4j" | grep -E "Address: [0-9]+\." | awk '{print $2}' | head -n1)
        if [[ -n "$dns_ip1" && "$dns_ip1" == "$ip_servidor" ]]; then
            sucesso=1
            break
        fi
        sleep 1
        ((tentativa_atual++))
    done

    if [ $sucesso -eq 0 ]; then
        echo -e "XXX\n25\nERRO: SUBDOMÍNIO NÃO APONTA PARA O IP ($ip_servidor) \nXXX"
        sleep 3
        exit 1
    fi
fi

#######################################################
#  INSTALAÇÃO DO NEO4J 
#######################################################
echo -e "XXX\n25\nCRIANDO STACK DO NEO4J... \nXXX"
cd ~/

cat > $nome_app_neo4j.yaml << EOL
version: "3.9"

services:

  ${nome_app_neo4j}-web:
    image: neo4j:latest
    hostname: ${nome_app_neo4j}-web
    container_name: ${nome_app_neo4j}-web
    init: true
    restart: unless-stopped
    networks:
      - externa
      - interna
    volumes:
      - ${nome_app_neo4j}-data:/data
      - ${nome_app_neo4j}-logs:/logs
    ports:
      - "7474:7474"
      - "7687:7687"
    environment:
      - NEO4J_AUTH=neo4j/${admin_password}
      - NEO4J_server_default__listen__address=0.0.0.0
      - NEO4J_PLUGINS=["apoc"]
    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
          - node.role == manager
EOL

if [ "$INSTALL_TYPE" = "TRADICIONAL" ]; then
cat >> $nome_app_neo4j.yaml << EOL
      labels:
        - traefik.enable=true
        - traefik.docker.network=externa
        - traefik.http.routers.${nome_app_neo4j}-web.rule=Host(\`${urlneo4j}\`)
        - traefik.http.routers.${nome_app_neo4j}-web.entrypoints=websecure
        - traefik.http.routers.${nome_app_neo4j}-web.priority=1
        - traefik.http.routers.${nome_app_neo4j}-web.tls.certresolver=letsencryptresolver
        - traefik.http.routers.${nome_app_neo4j}-web.service=${nome_app_neo4j}-web
        - traefik.http.routers.${nome_app_neo4j}-web.middlewares=websocket-headers@docker
        - traefik.http.services.${nome_app_neo4j}-web.loadbalancer.server.port=7474
        - traefik.http.services.${nome_app_neo4j}-web.loadbalancer.passHostHeader=true
        - traefik.http.middlewares.redirect-to-secure.redirectscheme.scheme=https
        - traefik.http.middlewares.websocket-headers.headers.customrequestheaders.X-Forwarded-Proto=https
        - traefik.http.middlewares.websocket-headers.headers.customrequestheaders.X-Forwarded-Port=443
EOL
fi

cat >> $nome_app_neo4j.yaml << EOL

volumes:
  ${nome_app_neo4j}-data:
    external: true
    name: ${nome_app_neo4j}-data
  ${nome_app_neo4j}-logs:
    external: true
    name: ${nome_app_neo4j}-logs

networks:
  externa:
    external: true
  interna:
    external: true
EOL


echo -e "XXX\n26\nIMPLANTANDO NEO4J... \nXXX"

if [[ "$criar_portainer" == "0" ]]; then
    echo -e "XXX\n27\nCRIANDO STACK NO PORTAINER 3/4  \nXXX"
    dados_file="$HOME/dados_portainer/dados_portainer"
    
    if [[ -f "$dados_file" ]]; then
        PORTAINER_URL=$(grep "Dominio do portainer:" "$dados_file" | cut -d':' -f2 | xargs)
        ADMIN_USERNAME=$(grep "Usuario:" "$dados_file" | cut -d':' -f2 | xargs)
        ADMIN_PASSWORD=$(grep "Senha:" "$dados_file" | cut -d':' -f2 | xargs)
        STACK_NAME=$nome_app_neo4j
        STACK_FILE_PATH="/root/$nome_app_neo4j.yaml"
    else
        docker stack deploy --prune --resolve-image always -c $nome_app_neo4j.yaml $nome_app_neo4j >/dev/null 2>&1
    fi

    get_auth_token() {
        RESPONSE=$(curl -sS -X POST "https://$PORTAINER_URL/api/auth" -H "Content-Type: application/json" -d "{\"username\": \"$ADMIN_USERNAME\", \"password\": \"$ADMIN_PASSWORD\"}")
        TOKEN=$(echo "$RESPONSE" | jq -r '.jwt')
        if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]; then
            docker stack deploy --prune --resolve-image always -c $nome_app_neo4j.yaml $nome_app_neo4j >/dev/null 2>&1
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
            docker stack deploy --prune --resolve-image always -c $nome_app_neo4j.yaml $nome_app_neo4j >/dev/null 2>&1
        fi
    }

    if [[ -f "$dados_file" ]]; then
        get_auth_token && get_endpoint_id && get_swarm_id && create_stack
    fi

elif [[ "$criar_portainer" == "1" ]]; then
    docker stack deploy --prune --resolve-image always -c $nome_app_neo4j.yaml $nome_app_neo4j >/dev/null 2>&1
else
    docker stack deploy --prune --resolve-image always -c $nome_app_neo4j.yaml $nome_app_neo4j >/dev/null 2>&1
fi

#######################################################
# FINALIZANDO INSTALAÇÃO DO NEO4J
#######################################################

echo -e "XXX\n85\nAGUARDANDO INICIALIZAÇÃO DOS CONTAINERS... \nXXX"
max_wait_time=300
wait_interval=5
elapsed_time=0

while [ $elapsed_time -lt $max_wait_time ]; do
    CONTAINER_ID=$(docker ps -qf name=${nome_app_neo4j}-web)
    if [ -n "$CONTAINER_ID" ]; then break; fi
    sleep $wait_interval
    elapsed_time=$((elapsed_time + wait_interval))
done

if [ -z "$CONTAINER_ID" ]; then
    echo "O container não foi encontrado após $max_wait_time segundos."
    exit 1
fi

echo -e "XXX\n28\nFINALIZANDO CONFIGURAÇÕES... \nXXX"
sleep 5

echo -e "XXX\n29\nCONFIGURAÇÃO CONCLUÍDA... \nXXX"
echo -e "XXX\n30\nINSTALAÇÃO DO NEO4J CONCLUÍDA! \nXXX"
sleep 3


#########################################################
# CRIAÇÃO DE DNS E ROTAS CLOUDFLARE TUNNEL QDRANT
#########################################################

echo -e "XXX\n31\nVERIFICANDO CONFIGURAÇÃO... \nXXX"

if [ "$INSTALL_TYPE" = "TRADICIONAL" ] && [ "$criar_dns" = "0" ]; then
    echo -e "XXX\n32\nCONFIGURANDO DNS AUTOMÁTICO (TRADICIONAL)... \nXXX"
    DOMINIO_PRINCIPAL=$(echo "$urlqdrant" | cut -d'.' -f2-)
    
    EXISTING_RECORDS=$(curl -s -X GET \
        "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records?name=${urlqdrant}" \
        -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
        -H "Content-Type: application/json")

    COUNT=$(echo "$EXISTING_RECORDS" | jq '.result | length')
    if [[ "$COUNT" -gt 0 ]]; then
        echo -e "XXX\n33\nREMOVENDO REGISTROS ANTIGOS... \nXXX"
        echo "$EXISTING_RECORDS" | jq -r '.result[].id' | while read -r REC_ID; do
            [[ -z "$REC_ID" ]] && continue
            curl -s -X DELETE \
                "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records/${REC_ID}" \
                -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
                -H "Content-Type: application/json" >/dev/null 2>&1
        done
    fi

    echo -e "XXX\n34\nCRIANDO REGISTRO CNAME... \nXXX"
    CNAME_RESPONSE=$(curl -s -X POST \
        "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records" \
        -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
        -H "Content-Type: application/json" \
        --data '{"type":"CNAME","name":"'${urlqdrant}'","content":"'${nome_servidor}'.'${DOMINIO_PRINCIPAL}'","ttl":1,"proxied":false}')

    if echo "$CNAME_RESPONSE" | grep -q '"success":true'; then
        echo -e "XXX\n35\nREGISTRO CNAME CRIADO COM SUCESSO! \nXXX"
    else
        echo -e "XXX\n36\nAVISO: ERRO AO CRIAR REGISTRO CNAME \nXXX"
    fi

elif [ "$INSTALL_TYPE" = "CLOUDFLARE_TUNNEL" ]; then
    echo -e "XXX\n37\nCONFIGURANDO CLOUDFLARE TUNNEL (DNS + ROTAS)... \nXXX"
    
    EXISTING_RECORDS=$(curl -s -X GET \
        "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records?name=${urlqdrant}" \
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
        --data "{\"type\":\"CNAME\",\"name\":\"${urlqdrant}\",\"content\":\"${TUNNEL_ID}.cfargotunnel.com\",\"ttl\":1,\"proxied\":true}")

    echo -e "XXX\n35\nATUALIZANDO CONFIGURAÇÃO DO TUNNEL... \nXXX"
    NEW_SERVICE="http://${nome_app_qdrant}-web:6333"
    
    TIMESTAMP=$(date -u +%Y%m%dT%H%M%SZ)
    TMPDIR=$(mktemp -d)
    BACKUP_RAW="$TMPDIR/backup_raw.$TIMESTAMP.json"
    TO_PUT="$TMPDIR/to_put.$TIMESTAMP.json"

    curl -sS -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
      "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/cfd_tunnel/$TUNNEL_ID/configurations" \
      | jq '.' > "$BACKUP_RAW"

    jq --arg host "$urlqdrant" --arg service "$NEW_SERVICE" '
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
    echo -e "XXX\n38\nVERIFICANDO CONFIGURAÇÃO (TRADICIONAL SEM AUTOMAÇÃO)... \nXXX"
    if ! nslookup "$urlqdrant" >/dev/null 2>&1; then
        echo -e "XXX\n39\nAVISO: VERIFIQUE A CONFIGURAÇÃO DNS \nXXX"
    fi
fi

if [ "$INSTALL_TYPE" = "TRADICIONAL" ] && [ "$criar_dns" = "1" ]; then
    ip_servidor=$(curl -s --max-time 10 ipinfo.io/ip)
    echo -e "XXX\n40\nVERIFICANDO SUBDOMÍNIO: $urlqdrant \nXXX"
    sleep 3

    tentativas=5
    tentativa_atual=1
    sucesso=0

    while [ $tentativa_atual -le $tentativas ]; do
        echo -e "XXX\n$(( (tentativa_atual * 12) / tentativas + 3 ))\nTentativa $tentativa_atual de $tentativas...\nXXX"
        dns_ip2=$(timeout 10 nslookup -type=A "$urlqdrant" | grep -E "Address: [0-9]+\." | awk '{print $2}' | head -n1)
        if [[ -n "$dns_ip2" && "$dns_ip2" == "$ip_servidor" ]]; then
            sucesso=1
            break
        fi
        sleep 1
        ((tentativa_atual++))
    done

    if [ $sucesso -eq 0 ]; then
        echo -e "XXX\n41\nERRO: SUBDOMÍNIO NÃO APONTA PARA O IP ($ip_servidor) \nXXX"
        sleep 3
        exit 1
    fi
fi

#######################################################
#  INSTALAÇÃO DO QDRANT
#######################################################
echo -e "XXX\n42\nCRIANDO STACK DO QDRANT... \nXXX"
cd ~/

cat > $nome_app_qdrant.yaml << EOL
version: "3.9"

services:

  ${nome_app_qdrant}-web:
    image: qdrant/qdrant:latest
    hostname: ${nome_app_qdrant}-web
    container_name: ${nome_app_qdrant}-web
    restart: unless-stopped
    networks:
      - externa
      - interna
    volumes:
      - ${nome_app_qdrant}-data:/qdrant/storage
    ports:
      - "6333:6333"
      - "6334:6334"
    environment:
      - QDRANT__SERVICE__API_KEY=${auth_secretqd}
    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
          - node.role == manager
EOL

if [ "$INSTALL_TYPE" = "TRADICIONAL" ]; then
cat >> $nome_app_qdrant.yaml << EOL
      labels:
        - traefik.enable=true
        - traefik.docker.network=externa
        - traefik.http.routers.${nome_app_qdrant}-web.rule=Host(\`${urlqdrant}\`)
        - traefik.http.routers.${nome_app_qdrant}-web.entrypoints=websecure
        - traefik.http.routers.${nome_app_qdrant}-web.priority=1
        - traefik.http.routers.${nome_app_qdrant}-web.tls.certresolver=letsencryptresolver
        - traefik.http.routers.${nome_app_qdrant}-web.service=${nome_app_qdrant}-web
        - traefik.http.routers.${nome_app_qdrant}-web.middlewares=websocket-headers@docker
        - traefik.http.services.${nome_app_qdrant}-web.loadbalancer.server.port=6333
        - traefik.http.services.${nome_app_qdrant}-web.loadbalancer.passHostHeader=true
        - traefik.http.middlewares.redirect-to-secure.redirectscheme.scheme=https
        - traefik.http.middlewares.websocket-headers.headers.customrequestheaders.X-Forwarded-Proto=https
        - traefik.http.middlewares.websocket-headers.headers.customrequestheaders.X-Forwarded-Port=443
EOL
fi

cat >> $nome_app_qdrant.yaml << EOL

volumes:
  ${nome_app_qdrant}-data:
    external: true
    name: ${nome_app_qdrant}-data

networks:
  externa:
    external: true
  interna:
    external: true
EOL

echo -e "XXX\n43\nIMPLANTANDO QDRANT... \nXXX"

if [[ "$criar_portainer" == "0" ]]; then
    echo -e "XXX\n44\nCRIANDO STACK NO PORTAINER 3/4  \nXXX"
    dados_file="$HOME/dados_portainer/dados_portainer"
    
    if [[ -f "$dados_file" ]]; then
        PORTAINER_URL=$(grep "Dominio do portainer:" "$dados_file" | cut -d':' -f2 | xargs)
        ADMIN_USERNAME=$(grep "Usuario:" "$dados_file" | cut -d':' -f2 | xargs)
        ADMIN_PASSWORD=$(grep "Senha:" "$dados_file" | cut -d':' -f2 | xargs)
        STACK_NAME=$nome_app_qdrant
        STACK_FILE_PATH="/root/$nome_app_qdrant.yaml"
    else
        docker stack deploy --prune --resolve-image always -c $nome_app_qdrant.yaml $nome_app_qdrant >/dev/null 2>&1
    fi

    get_auth_token() {
        RESPONSE=$(curl -sS -X POST "https://$PORTAINER_URL/api/auth" -H "Content-Type: application/json" -d "{\"username\": \"$ADMIN_USERNAME\", \"password\": \"$ADMIN_PASSWORD\"}")
        TOKEN=$(echo "$RESPONSE" | jq -r '.jwt')
        if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]; then
            docker stack deploy --prune --resolve-image always -c $nome_app_qdrant.yaml $nome_app_qdrant >/dev/null 2>&1
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
            docker stack deploy --prune --resolve-image always -c $nome_app_qdrant.yaml $nome_app_qdrant >/dev/null 2>&1
        fi
    }

    if [[ -f "$dados_file" ]]; then
        get_auth_token && get_endpoint_id && get_swarm_id && create_stack
    fi

elif [[ "$criar_portainer" == "1" ]]; then
    docker stack deploy --prune --resolve-image always -c $nome_app_qdrant.yaml $nome_app_qdrant >/dev/null 2>&1
else
    docker stack deploy --prune --resolve-image always -c $nome_app_qdrant.yaml $nome_app_qdrant >/dev/null 2>&1
fi

#######################################################
# FINALIZANDO INSTALAÇÃO DO QDRANT
#######################################################

echo -e "XXX\n45\nAGUARDANDO INICIALIZAÇÃO DOS CONTAINERS... \nXXX"
max_wait_time=300
wait_interval=5
elapsed_time=0

while [ $elapsed_time -lt $max_wait_time ]; do
    CONTAINER_ID=$(docker ps -qf name=${nome_app_qdrant}-web)
    if [ -n "$CONTAINER_ID" ]; then break; fi
    sleep $wait_interval
    elapsed_time=$((elapsed_time + wait_interval))
done

if [ -z "$CONTAINER_ID" ]; then
    echo "O container não foi encontrado após $max_wait_time segundos."
    exit 1
fi

echo -e "XXX\n46\nFINALIZANDO CONFIGURAÇÕES... \nXXX"
sleep 5

echo -e "XXX\n47\nCONFIGURAÇÃO CONCLUÍDA... \nXXX"
echo -e "XXX\n48\nINSTALAÇÃO DO QDRANT CONCLUÍDA! \nXXX"
sleep 3



#########################################################
# CRIAÇÃO DE DNS E ROTAS CLOUDFLARE TUNNEL COGNEE
#########################################################

echo -e "XXX\n49\nVERIFICANDO CONFIGURAÇÃO... \nXXX"

if [ "$INSTALL_TYPE" = "TRADICIONAL" ] && [ "$criar_dns" = "0" ]; then
    echo -e "XXX\n50\nCONFIGURANDO DNS AUTOMÁTICO (TRADICIONAL)... \nXXX"
    DOMINIO_PRINCIPAL=$(echo "$urlcognee" | cut -d'.' -f2-)
    
    EXISTING_RECORDS=$(curl -s -X GET \
        "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records?name=${urlcognee}" \
        -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
        -H "Content-Type: application/json")

    COUNT=$(echo "$EXISTING_RECORDS" | jq '.result | length')
    if [[ "$COUNT" -gt 0 ]]; then
        echo -e "XXX\n51\nREMOVENDO REGISTROS ANTIGOS... \nXXX"
        echo "$EXISTING_RECORDS" | jq -r '.result[].id' | while read -r REC_ID; do
            [[ -z "$REC_ID" ]] && continue
            curl -s -X DELETE \
                "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records/${REC_ID}" \
                -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
                -H "Content-Type: application/json" >/dev/null 2>&1
        done
    fi

    echo -e "XXX\n52\nCRIANDO REGISTRO CNAME... \nXXX"
    CNAME_RESPONSE=$(curl -s -X POST \
        "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records" \
        -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
        -H "Content-Type: application/json" \
        --data '{"type":"CNAME","name":"'${urlcognee}'","content":"'${nome_servidor}'.'${DOMINIO_PRINCIPAL}'","ttl":1,"proxied":false}')

    if echo "$CNAME_RESPONSE" | grep -q '"success":true'; then
        echo -e "XXX\n53\nREGISTRO CNAME CRIADO COM SUCESSO! \nXXX"
    else
        echo -e "XXX\n54\nAVISO: ERRO AO CRIAR REGISTRO CNAME \nXXX"
    fi

elif [ "$INSTALL_TYPE" = "CLOUDFLARE_TUNNEL" ]; then
    echo -e "XXX\n55\nCONFIGURANDO CLOUDFLARE TUNNEL (DNS + ROTAS)... \nXXX"
    
    EXISTING_RECORDS=$(curl -s -X GET \
        "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records?name=${urlcognee}" \
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
        --data "{\"type\":\"CNAME\",\"name\":\"${urlcognee}\",\"content\":\"${TUNNEL_ID}.cfargotunnel.com\",\"ttl\":1,\"proxied\":true}")

    echo -e "XXX\n56\nATUALIZANDO CONFIGURAÇÃO DO TUNNEL... \nXXX"
    NEW_SERVICE="http://${nome_app_cognee}-web:8000"
    
    TIMESTAMP=$(date -u +%Y%m%dT%H%M%SZ)
    TMPDIR=$(mktemp -d)
    BACKUP_RAW="$TMPDIR/backup_raw.$TIMESTAMP.json"
    TO_PUT="$TMPDIR/to_put.$TIMESTAMP.json"

    curl -sS -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
      "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/cfd_tunnel/$TUNNEL_ID/configurations" \
      | jq '.' > "$BACKUP_RAW"

    jq --arg host "$urlcognee" --arg service "$NEW_SERVICE" '
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
    echo -e "XXX\n57\nVERIFICANDO CONFIGURAÇÃO (TRADICIONAL SEM AUTOMAÇÃO)... \nXXX"
    if ! nslookup "$urlcognee" >/dev/null 2>&1; then
        echo -e "XXX\n58\nAVISO: VERIFIQUE A CONFIGURAÇÃO DNS \nXXX"
    fi
fi

if [ "$INSTALL_TYPE" = "TRADICIONAL" ] && [ "$criar_dns" = "1" ]; then
    ip_servidor=$(curl -s --max-time 10 ipinfo.io/ip)
    echo -e "XXX\n59\nVERIFICANDO SUBDOMÍNIO: $urlcognee \nXXX"
    sleep 3

    tentativas=5
    tentativa_atual=1
    sucesso=0

    while [ $tentativa_atual -le $tentativas ]; do
        echo -e "XXX\n$(( (tentativa_atual * 12) / tentativas + 3 ))\nTentativa $tentativa_atual de $tentativas...\nXXX"
        dns_ip3=$(timeout 10 nslookup -type=A "$urlcognee" | grep -E "Address: [0-9]+\." | awk '{print $2}' | head -n1)
        if [[ -n "$dns_ip3" && "$dns_ip3" == "$ip_servidor" ]]; then
            sucesso=1
            break
        fi
        sleep 1
        ((tentativa_atual++))
    done

    if [ $sucesso -eq 0 ]; then
        echo -e "XXX\n60\nERRO: SUBDOMÍNIO NÃO APONTA PARA O IP ($ip_servidor) \nXXX"
        sleep 3
        exit 1
    fi
fi

#######################################################
#  INSTALAÇÃO DO COGNEE
#######################################################


echo -e "XXX\n61\nCRIANDO STACK DO COGNEE... \nXXX"
cd ~/

postgres_password=$(grep -oP '(?<=POSTGRES_PASSWORD=).+' /root/postgres.yaml)

cat > $nome_app_cognee.yaml << EOL
version: "3.9"

services:

  ${nome_app_cognee}-web:
    image: cognee/cognee:latest # <--- Imagem oficial que existe
    hostname: ${nome_app_cognee}-web
    container_name: ${nome_app_cognee}-web
    user: root
    init: true
    restart: unless-stopped
    networks:
      - externa
      - interna
    volumes:
      - ${nome_app_cognee}-data:/app/cognee
    ports:
      - "8001:8000"
    # ✅ CORREÇÃO PRINCIPAL: NÃO apagar .cognee_system
    command: >
      bash -c "/app/.venv/bin/python3 -m cognee.api.v1.server"
    environment:
      - ENV=prod
      # Desativa o controle de acesso para o primeiro boot
      - ENABLE_BACKEND_ACCESS_CONTROL=false
      - COGNEE_ENABLE_BACKEND_ACCESS_CONTROL=false
EOL


# =================================================================
# INJETANDO CREDENCIAIS NO COGNEE (NEO4J, QDRANT E IA)
# =================================================================
cat >> $nome_app_cognee.yaml << EOL

      # --- BANCO RELACIONAL (Metadata - Redundância Total) ---
      - DB_PROVIDER=postgres
      - DB_HOST=postgres
      - DB_PORT=5432
      - DB_USERNAME=postgres
      - DB_PASSWORD=$postgres_password
      - DB_NAME=postgres
      
      - COGNEE_DB_PROVIDER=postgres
      - COGNEE_DB_HOST=postgres
      - COGNEE_DB_USER=postgres
      - COGNEE_DB_PASSWORD=$postgres_password
      - COGNEE_DB_NAME=postgres

      # --- BANCO DE VETORES (PGVector) ---
      - VECTOR_DB_PROVIDER=pgvector
      - VECTOR_DB_HOST=postgres
      - VECTOR_DB_PORT=5432
      - VECTOR_DB_USERNAME=postgres
      - VECTOR_DB_PASSWORD=$postgres_password
      - VECTOR_DB_NAME=postgres
      - COGNEE_VECTOR_DB_PROVIDER=pgvector

      # --- VARIÁVEIS DE "CURA" DO HEALTH CHECK ---
      - LLM_MODEL=${MODEL}
      - GRAPH_DATABASE_PORT=7687

      # --- IA E GRAFOS ---
      - LLM_PROVIDER=${PROVIDER}
      - OPENAI_API_KEY=${API_KEY}
      - LLM_API_KEY=${API_KEY}
      - GRAPH_DATABASE_PROVIDER=neo4j
      - GRAPH_DB_PROVIDER=neo4j
      - GRAPH_DATABASE_URL=bolt://${nome_app_neo4j}-web:7687
      - GRAPH_DATABASE_NAME=neo4j
      - GRAPH_DATABASE_USERNAME=neo4j
      - GRAPH_DATABASE_PASSWORD=$admin_password
EOL

cat >> $nome_app_cognee.yaml << EOL
    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
          - node.role == manager
EOL

if [ "$INSTALL_TYPE" = "TRADICIONAL" ]; then
cat >> $nome_app_cognee.yaml << EOL
      labels:
        - traefik.enable=true
        - traefik.docker.network=externa
        - traefik.http.routers.${nome_app_cognee}-web.rule=Host(\`${urlcognee}\`)
        - traefik.http.routers.${nome_app_cognee}-web.entrypoints=websecure
        - traefik.http.routers.${nome_app_cognee}-web.priority=1
        - traefik.http.routers.${nome_app_cognee}-web.tls.certresolver=letsencryptresolver
        - traefik.http.routers.${nome_app_cognee}-web.service=${nome_app_cognee}-web
        - traefik.http.routers.${nome_app_cognee}-web.middlewares=websocket-headers@docker
        - traefik.http.services.${nome_app_cognee}-web.loadbalancer.server.port=8000
        - traefik.http.services.${nome_app_cognee}-web.loadbalancer.passHostHeader=true
        - traefik.http.middlewares.redirect-to-secure.redirectscheme.scheme=https
        - traefik.http.middlewares.websocket-headers.headers.customrequestheaders.X-Forwarded-Proto=https
        - traefik.http.middlewares.websocket-headers.headers.customrequestheaders.X-Forwarded-Port=443
EOL
fi

cat >> $nome_app_cognee.yaml << EOL

volumes:
  ${nome_app_cognee}-data:
    external: true
    name: ${nome_app_cognee}-data

networks:
  externa:
    external: true
  interna:
    external: true
EOL

echo -e "XXX\n70\nIMPLANTANDO COGNEE... \nXXX"

if [[ "$criar_portainer" == "0" ]]; then
    echo -e "XXX\n62\nCRIANDO STACK NO PORTAINER 3/4  \nXXX"
    dados_file="$HOME/dados_portainer/dados_portainer"
    
    if [[ -f "$dados_file" ]]; then
        PORTAINER_URL=$(grep "Dominio do portainer:" "$dados_file" | cut -d':' -f2 | xargs)
        ADMIN_USERNAME=$(grep "Usuario:" "$dados_file" | cut -d':' -f2 | xargs)
        ADMIN_PASSWORD=$(grep "Senha:" "$dados_file" | cut -d':' -f2 | xargs)
        STACK_NAME=$nome_app_cognee
        STACK_FILE_PATH="/root/$nome_app_cognee.yaml"
    else
        docker stack deploy --prune --resolve-image always -c $nome_app_cognee.yaml $nome_app_cognee >/dev/null 2>&1
    fi

    get_auth_token() {
        RESPONSE=$(curl -sS -X POST "https://$PORTAINER_URL/api/auth" -H "Content-Type: application/json" -d "{\"username\": \"$ADMIN_USERNAME\", \"password\": \"$ADMIN_PASSWORD\"}")
        TOKEN=$(echo "$RESPONSE" | jq -r '.jwt')
        if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]; then
            docker stack deploy --prune --resolve-image always -c $nome_app_cognee.yaml $nome_app_cognee >/dev/null 2>&1
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
            docker stack deploy --prune --resolve-image always -c $nome_app_cognee.yaml $nome_app_cognee >/dev/null 2>&1
        fi
    }

    if [[ -f "$dados_file" ]]; then
        get_auth_token && get_endpoint_id && get_swarm_id && create_stack
    fi

elif [[ "$criar_portainer" == "1" ]]; then
    docker stack deploy --prune --resolve-image always -c $nome_app_cognee.yaml $nome_app_cognee >/dev/null 2>&1
else
    docker stack deploy --prune --resolve-image always -c $nome_app_cognee.yaml $nome_app_cognee >/dev/null 2>&1
fi

#######################################################
# FINALIZANDO INSTALAÇÃO DO COGNEE
#######################################################

echo -e "XXX\n63\nBAIXANDO E INSTALANDO PACOTES (Isso leva cerca de 1 a 2 minutos)... \nXXX"
max_wait_time=300
wait_interval=5
elapsed_time=0

while [ $elapsed_time -lt $max_wait_time ]; do
    CONTAINER_ID=$(docker ps -qf name=${nome_app_cognee}-web)
    if [ -n "$CONTAINER_ID" ]; then break; fi
    sleep $wait_interval
    elapsed_time=$((elapsed_time + wait_interval))
done

if [ -z "$CONTAINER_ID" ]; then
    echo "O container não foi encontrado após $max_wait_time segundos."
    exit 1
fi

docker exec $CONTAINER_ID mkdir -p /root/.cognee/db
docker exec $CONTAINER_ID chown -R 1000:1000 /root/.cognee/db


echo -e "XXX\n64\nFINALIZANDO CONFIGURAÇÕES... \nXXX"
sleep 15 # Dá um tempo extra pro pip install terminar dentro do container recém-criado

echo -e "XXX\n65\nCONFIGURAÇÃO CONCLUÍDA... \nXXX"
echo -e "XXX\n66\nINSTALAÇÃO DO COGNEE CONCLUÍDA! \nXXX"
sleep 3

#######################################################
#  INSTALAÇÃO DO SEARXNG (REDUZIDA, APENAS REDE INTERNA)
#######################################################
echo -e "XXX\n77\nCRIANDO STACK DO SEARXNG (REDE INTERNA BLINDADA)... \nXXX"
cd ~/

# Cria a pasta física no servidor do aluno
mkdir -p /root/searxng_data

# Cria o arquivo settings.yml avisando para herdar o padrão e liberar o JSON
cat > /root/searxng_data/settings.yml << EOF
use_default_settings: true

search:
  formats:
    - html
    - json
EOF

cat > $nome_app_searxng.yaml << EOL
version: "3.9"

services:

  ${nome_app_searxng}-redis:
    image: redis:alpine
    hostname: ${nome_app_searxng}-redis
    container_name: ${nome_app_searxng}-redis
    restart: unless-stopped
    networks:
      - interna
    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
          - node.role == manager

  ${nome_app_searxng}-web:
    image: searxng/searxng:latest
    hostname: ${nome_app_searxng}-web
    container_name: ${nome_app_searxng}-web
    init: true
    restart: unless-stopped
    networks:
      - externa
      - interna
    volumes:
      - /root/searxng_data:/etc/searxng
    environment:
      # Não precisamos mais do Base URL público, a comunicação será apenas interna
      - SEARXNG_SECRET=${auth_secret_sear}
      - SEARXNG_REDIS_URL=redis://${nome_app_searxng}-redis:6379/0
    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
          - node.role == manager

networks:
  externa:
    external: true
  interna:
    external: true
EOL

echo -e "XXX\n78\nIMPLANTANDO SEARXNG... \nXXX"

if [[ "$criar_portainer" == "0" ]]; then
    echo -e "XXX\n79\nCRIANDO STACK NO PORTAINER 3/4  \nXXX"
    dados_file="$HOME/dados_portainer/dados_portainer"
    
    if [[ -f "$dados_file" ]]; then
        PORTAINER_URL=$(grep "Dominio do portainer:" "$dados_file" | cut -d':' -f2 | xargs)
        ADMIN_USERNAME=$(grep "Usuario:" "$dados_file" | cut -d':' -f2 | xargs)
        ADMIN_PASSWORD=$(grep "Senha:" "$dados_file" | cut -d':' -f2 | xargs)
        STACK_NAME=$nome_app_searxng
        STACK_FILE_PATH="/root/$nome_app_searxng.yaml"
    else
        docker stack deploy --prune --resolve-image always -c $nome_app_searxng.yaml $nome_app_searxng >/dev/null 2>&1
    fi

    get_auth_token() {
        RESPONSE=$(curl -sS -X POST "https://$PORTAINER_URL/api/auth" -H "Content-Type: application/json" -d "{\"username\": \"$ADMIN_USERNAME\", \"password\": \"$ADMIN_PASSWORD\"}")
        TOKEN=$(echo "$RESPONSE" | jq -r '.jwt')
        if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]; then
            docker stack deploy --prune --resolve-image always -c $nome_app_searxng.yaml $nome_app_searxng >/dev/null 2>&1
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
            docker stack deploy --prune --resolve-image always -c $nome_app_searxng.yaml $nome_app_searxng >/dev/null 2>&1
        fi
    }

    if [[ -f "$dados_file" ]]; then
        get_auth_token && get_endpoint_id && get_swarm_id && create_stack
    fi

elif [[ "$criar_portainer" == "1" ]]; then
    docker stack deploy --prune --resolve-image always -c $nome_app_searxng.yaml $nome_app_searxng >/dev/null 2>&1
else
    docker stack deploy --prune --resolve-image always -c $nome_app_searxng.yaml $nome_app_searxng >/dev/null 2>&1
fi

#######################################################
# FINALIZANDO INSTALAÇÃO DO SEARXNG
#######################################################

echo -e "XXX\n80\nAGUARDANDO INICIALIZAÇÃO DOS CONTAINERS... \nXXX"
max_wait_time=300
wait_interval=5
elapsed_time=0

while [ $elapsed_time -lt $max_wait_time ]; do
    CONTAINER_ID=$(docker ps -qf name=${nome_app_searxng}-web)
    if [ -n "$CONTAINER_ID" ]; then break; fi
    sleep $wait_interval
    elapsed_time=$((elapsed_time + wait_interval))
done

if [ -z "$CONTAINER_ID" ]; then
    echo "O container não foi encontrado após $max_wait_time segundos."
    exit 1
fi

echo -e "XXX\n81\nFINALIZANDO CONFIGURAÇÕES... \nXXX"

# Ajuste do SearXNG para aceitar JSON (Evita erro 403 no OpenClaw)
docker exec -u 0 $CONTAINER_ID sed -i 's/- html/- html\n    - json/g' /etc/searxng/settings.yml
docker restart $CONTAINER_ID

sleep 5

echo -e "XXX\n82\nCONFIGURAÇÃO CONCLUÍDA... \nXXX"
echo -e "XXX\n83\nINSTALAÇÃO DO SEARXNG CONCLUÍDA! \nXXX"
sleep 3



#########################################################
# CRIAÇÃO DE DNS E ROTAS CLOUDFLARE TUNNEL OPENCLAW
#########################################################

echo -e "XXX\n84\nVERIFICANDO CONFIGURAÇÃO... \nXXX"

if [ "$INSTALL_TYPE" = "TRADICIONAL" ] && [ "$criar_dns" = "0" ]; then
    echo -e "XXX\n85\nCONFIGURANDO DNS AUTOMÁTICO (TRADICIONAL)... \nXXX"
    DOMINIO_PRINCIPAL=$(echo "$urlopenclaw" | cut -d'.' -f2-)
    
    EXISTING_RECORDS=$(curl -s -X GET \
        "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records?name=${urlopenclaw}" \
        -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
        -H "Content-Type: application/json")

    COUNT=$(echo "$EXISTING_RECORDS" | jq '.result | length')
    if [[ "$COUNT" -gt 0 ]]; then
        echo -e "XXX\n86\nREMOVENDO REGISTROS ANTIGOS... \nXXX"
        echo "$EXISTING_RECORDS" | jq -r '.result[].id' | while read -r REC_ID; do
            [[ -z "$REC_ID" ]] && continue
            curl -s -X DELETE \
                "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records/${REC_ID}" \
                -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
                -H "Content-Type: application/json" >/dev/null 2>&1
        done
    fi

    echo -e "XXX\n87\nCRIANDO REGISTRO CNAME... \nXXX"
    CNAME_RESPONSE=$(curl -s -X POST \
        "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records" \
        -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
        -H "Content-Type: application/json" \
        --data '{"type":"CNAME","name":"'${urlopenclaw}'","content":"'${nome_servidor}'.'${DOMINIO_PRINCIPAL}'","ttl":1,"proxied":false}')

    if echo "$CNAME_RESPONSE" | grep -q '"success":true'; then
        echo -e "XXX\n88\nREGISTRO CNAME CRIADO COM SUCESSO! \nXXX"
    else
        echo -e "XXX\n89\nAVISO: ERRO AO CRIAR REGISTRO CNAME \nXXX"
    fi

elif [ "$INSTALL_TYPE" = "CLOUDFLARE_TUNNEL" ]; then
    echo -e "XXX\n90\nCONFIGURANDO CLOUDFLARE TUNNEL (DNS + ROTAS)... \nXXX"
    
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
    NEW_SERVICE="http://${nome_app_openclaw}-gateway:18789"
    
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
    echo -e "XXX\n91\nVERIFICANDO CONFIGURAÇÃO (TRADICIONAL SEM AUTOMAÇÃO)... \nXXX"
    if ! nslookup "$urlopenclaw" >/dev/null 2>&1; then
        echo -e "XXX\n92\nAVISO: VERIFIQUE A CONFIGURAÇÃO DNS \nXXX"
    fi
fi

if [ "$INSTALL_TYPE" = "TRADICIONAL" ] && [ "$criar_dns" = "1" ]; then
    ip_servidor=$(curl -s --max-time 10 ipinfo.io/ip)
    echo -e "XXX\n93\nVERIFICANDO SUBDOMÍNIO: $urlopenclaw \nXXX"
    sleep 3

    tentativas=5
    tentativa_atual=1
    sucesso=0

    while [ $tentativa_atual -le $tentativas ]; do
        echo -e "XXX\n$(( (tentativa_atual * 12) / tentativas + 3 ))\nTentativa $tentativa_atual de $tentativas...\nXXX"
        dns_ip5=$(timeout 10 nslookup -type=A "$urlopenclaw" | grep -E "Address: [0-9]+\." | awk '{print $2}' | head -n1)
        if [[ -n "$dns_ip5" && "$dns_ip5" == "$ip_servidor" ]]; then
            sucesso=1
            break
        fi
        sleep 1
        ((tentativa_atual++))
    done

    if [ $sucesso -eq 0 ]; then
        echo -e "XXX\n94\nERRO: SUBDOMÍNIO NÃO APONTA PARA O IP ($ip_servidor) \nXXX"
        sleep 3
        exit 1
    fi
fi

echo -e "XXX\n95\nREDE E DNS CONFIGURADOS! \nXXX"
sleep 2
}|whiptail --title "CONFIGURAÇÃO DE REDE" --gauge "Aguarde a configuração do DNS e Rotas" 6 60 0


#######################################################
# CONSTRUÇÃO DA STACK DO OPENCLAW - VERSÃO CORRIGIDA
#######################################################
{
echo -e "XXX\n96\nCRIANDO STACK DO DOCKER... \nXXX"
cd ~/

# fixar imagem aqui:

imagem_openclaw="alpine/openclaw:2026.4.1" 

# 1. OpenClaw Gateway (porta 18789 REMOVIDA - Traefik cuida)
cat > $nome_app_openclaw.yaml << EOL
version: "3.9"
services:
  $nome_app_openclaw-gateway:
    image: $imagem_openclaw
    hostname: $nome_app_openclaw-gateway
    container_name: $nome_app_openclaw-gateway
    init: true
    restart: unless-stopped
    command:
      - sh
      - -c
      - |
        if [ ! -d "/home/node/.openclaw/extensions/cognee-openclaw" ]; then
          echo "Instalando Cognee..."
          openclaw plugins install @cognee/cognee-openclaw
        fi

        echo "Iniciando gateway..."

        openclaw gateway --allow-unconfigured &

        sleep 10

        while true; do
          openclaw cognee index
          sleep 180
        done

    networks:
      - externa
      - interna
    volumes:
      - $nome_app_openclaw-data:/home/node/.openclaw
      - $nome_app_openclaw-workspace:/home/node/.openclaw/workspace
    environment:
      - HOME=/home/node
      - TERM=xterm-256color
      - OPENCLAW_CONFIG=/home/node/.openclaw/openclaw.json
      - OPENCLAW_GATEWAY_TOKEN=$key
      - OPENCLAW_GATEWAY_MODE=local
      #- OPENCLAW_GATEWAY_TRUSTED_PROXIES=127.0.0.1
      #- OPENCLAW__GATEWAY__CONTROLUI__DANGEROUSLYALLOWHOSTHEADERORIGINFALLBACK=true
      - SEARXNG_BASE_URL=http://${nome_app_searxng}-web:8080
      - COGNEE_API_URL=http://${nome_app_cognee}-web:8000
      - BRAVE_SEARCH_API_KEY=chave_falsa_para_liberar_searxng_123
      - BRAVE_API_KEY=chave_falsa_para_liberar_searxng_123
      - VECTOR_DB=qdrant
      - QDRANT_URL=http://${nome_app_qdrant}-web:6333
      - QDRANT_API_KEY=${auth_secretqd}
    healthcheck:
      test: ["CMD", "wget", "-q", "--spider", "http://localhost:18789/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 90s
    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
          - node.role == manager
EOL

# Traefik labels (apenas para OpenClaw)
if [ "$INSTALL_TYPE" = "TRADICIONAL" ]; then
cat >> $nome_app_openclaw.yaml << EOL
      labels:
        - traefik.enable=true
        - traefik.docker.network=externa
        - traefik.http.routers.$nome_app_openclaw-gateway.rule=Host(\`$urlopenclaw\`)
        - traefik.http.routers.$nome_app_openclaw-gateway.entrypoints=websecure
        - traefik.http.routers.$nome_app_openclaw-gateway.priority=1
        - traefik.http.routers.$nome_app_openclaw-gateway.tls.certresolver=letsencryptresolver
        - traefik.http.routers.$nome_app_openclaw-gateway.service=$nome_app_openclaw-gateway
        - traefik.http.routers.$nome_app_openclaw-gateway.middlewares=websocket-headers@docker
        - traefik.http.services.$nome_app_openclaw-gateway.loadbalancer.server.port=18789
        - traefik.http.services.$nome_app_openclaw-gateway.loadbalancer.passHostHeader=true
EOL
fi

cat >> $nome_app_openclaw.yaml << EOL

volumes:
  $nome_app_openclaw-data:
    external: true
    name: $nome_app_openclaw-data
  $nome_app_openclaw-workspace:
    external: true
    name: $nome_app_openclaw-workspace

networks:
  externa:
    external: true
  interna:
    external: true
EOL

echo -e "XXX\n97\nIMPLANTANDO STACK NO DOCKER... \nXXX"


# =====================================================================
# LÓGICA DE DEPLOY 
# =====================================================================
if [[ "$criar_portainer" == "0" ]]; then
    echo -e "XXX\n90\nCRIANDO STACK NO PORTAINER...  \nXXX"
    dados_file="$HOME/dados_portainer/dados_portainer"
    
    if [[ -f "$dados_file" ]]; then
    # Coleta as informações do arquivo
PORTAINER_URL=$(grep "Dominio do portainer:" "$dados_file" | cut -d':' -f2 | xargs)
ADMIN_USERNAME=$(grep "Usuario:" "$dados_file" | cut -d':' -f2 | xargs)
ADMIN_PASSWORD=$(grep "Senha:" "$dados_file" | cut -d':' -f2 | xargs)
STACK_NAME=$nome_app_openclaw
STACK_FILE_PATH="/root/$nome_app_openclaw.yaml"
    else
        echo -e "XXX\n90\nSEM DADOS DO PORTAINER. REVERTENDO PARA SERVIDOR... \nXXX"
        docker stack deploy --prune --resolve-image always -c $nome_app_openclaw.yaml $nome_app_openclaw >/dev/null 2>&1
        sleep 3
    fi

    # Função para autenticação
    get_auth_token() {
        echo -e "XXX\n91\nAUTENTICANDO NO PORTAINER... \nXXX"
        RESPONSE=$(curl -sS -X POST "https://$PORTAINER_URL/api/auth" \
            -H "Content-Type: application/json" \
            -d "{\"username\": \"$ADMIN_USERNAME\", \"password\": \"$ADMIN_PASSWORD\"}")
        TOKEN=$(echo "$RESPONSE" | jq -r '.jwt')
        
        if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]; then
            echo -e "XXX\n91\nFALHA NA AUTENTICAÇÃO. REVERTENDO PARA SERVIDOR... \nXXX"
            docker stack deploy --prune --resolve-image always -c $nome_app_openclaw.yaml $nome_app_openclaw >/dev/null 2>&1
            sleep 3
            return 1 # Usamos return em vez de exit para não abortar a configuração do json
        fi
        echo -e "XXX\n92\n[SUCESSO] AUTENTICAÇÃO OK \nXXX"
    }

    # Função para obter o EndpointID
    get_endpoint_id() {
        echo -e "XXX\n93\n[INFO] OBTENDO ENDPOINTID... \nXXX"
    RESPONSE=$(curl -sS -X GET "https://$PORTAINER_URL/api/endpoints" \
            -H "Authorization: Bearer $TOKEN")
        ENDPOINT_ID=$(echo "$RESPONSE" | jq -r '.[0].Id')
        
        if [ -z "$ENDPOINT_ID" ] || [ "$ENDPOINT_ID" = "null" ]; then
            echo -e "XXX\n94\n[ERRO] ENDPOINTID NÃO ENCONTRADO. REVERTENDO... \nXXX"
            docker stack deploy --prune --resolve-image always -c $nome_app_openclaw.yaml $nome_app_openclaw >/dev/null 2>&1
            return 1
        fi
        echo -e "XXX\n95\n[SUCESSO] ENDPOINTID OBTIDO: $ENDPOINT_ID \nXXX"
    }

    # Função para obter o SwarmID
    get_swarm_id() {
        echo -e "XXX\n95\n[INFO] OBTENDO SWARMID... \nXXX"
    RESPONSE=$(curl -sS -X GET "https://$PORTAINER_URL/api/endpoints/$ENDPOINT_ID/docker/swarm" \
            -H "Authorization: Bearer $TOKEN")
        SWARM_ID=$(echo "$RESPONSE" | jq -r '.ID')
        
        if [ -z "$SWARM_ID" ] || [ "$SWARM_ID" = "null" ]; then
            echo -e "XXX\n95\n[ERRO] SWARMID NÃO ENCONTRADO. REVERTENDO... \nXXX"
            docker stack deploy --prune --resolve-image always -c $nome_app_openclaw.yaml $nome_app_openclaw >/dev/null 2>&1
            return 1
        fi
        echo -e "XXX\n95\n[SUCESSO] SWARMID OBTIDO: $SWARM_ID \nXXX"
    }

    # Função para criar a stack
    create_stack() {
        echo -e "XXX\n96\n[INFO] VERIFICANDO YAML... \nXXX"
        if [ ! -f "$STACK_FILE_PATH" ]; then
            echo -e "XXX\n53\n[ERRO] ARQUIVO NÃO ENCONTRADO. REVERTENDO... \nXXX"
            docker stack deploy --prune --resolve-image always -c $nome_app_openclaw.yaml $nome_app_openclaw >/dev/null 2>&1
            return 1
        fi

        echo -e "XXX\n96\n[INFO] CRIANDO STACK NO PORTAINER... \nXXX"
        response_output=$(mktemp)
        erro_output=$(mktemp)

        http_code=$(curl -s -o "$response_output" -w "%{http_code}"  -X POST \
            -H "Authorization: Bearer $TOKEN" \
            -F "Name=$STACK_NAME" \
            -F "file=@$STACK_FILE_PATH" \
            -F "SwarmID=$SWARM_ID" \
            -F "endpointId=$ENDPOINT_ID" \
        "https://$PORTAINER_URL/api/stacks/create/swarm/file" 2> "$erro_output")

        rm -f "$response_output" "$erro_output"

        if [ "$http_code" -ne 200 ]; then
            echo -e "XXX\n96\n[ERRO] FALHA AO CRIAR STACK. REVERTENDO PARA SERVIDOR... \nXXX"
            docker stack deploy --prune --resolve-image always -c $nome_app_openclaw.yaml $nome_app_openclaw >/dev/null 2>&1
            return 1
        fi

        echo -e "XXX\n96\n[SUCESSO] STACK CRIADA NO PORTAINER COM SUCESSO! \nXXX"
    }

    if [[ -f "$dados_file" ]]; then
        get_auth_token && get_endpoint_id && get_swarm_id && create_stack
    fi

elif [[ "$criar_portainer" == "1" ]]; then
    echo -e "XXX\n96\nCRIANDO STACK DIRETAMENTE NO DOCKER... \nXXX"
    docker stack deploy --prune --resolve-image always -c $nome_app_openclaw.yaml $nome_app_openclaw >/dev/null 2>&1
else
    echo -e "XXX\n96\nCRIANDO STACK DIRETAMENTE NO DOCKER... \nXXX"
    docker stack deploy --prune --resolve-image always -c $nome_app_openclaw.yaml $nome_app_openclaw >/dev/null 2>&1
fi
# =====================================================================


echo -e "XXX\n96\nAGUARDANDO INICIALIZAÇÃO... \nXXX"
max_wait_time=800
wait_interval=60
elapsed_time=0

while [ $elapsed_time -lt $max_wait_time ]; do
    CONTAINER_ID=$(docker ps -qf name=$nome_app_openclaw-gateway)
    if [ -n "$CONTAINER_ID" ]; then break; fi
    sleep $wait_interval
    elapsed_time=$((elapsed_time + wait_interval))
done

if [ -z "$CONTAINER_ID" ]; then
    echo "O container não foi encontrado após $max_wait_time segundos."
    exit 1
fi


echo -e "XXX\n97\nCONFIGURANDO OPENCLAW.JSON... \nXXX"

TMP_JSON=$(mktemp)
cat > "$TMP_JSON" << EOF
{
  "logging": { "level": "info" },
  "commands": { "native": "auto", "nativeSkills": $NATIVE_SKILLS, "restart": true, "ownerDisplay": "raw" },
  "channels": {
    "whatsapp": { "enabled": true, "dmPolicy": "pairing", "allowFrom": [], "groupPolicy": "allowlist", "groups": {"*": {"requireMention": true}}, "debounceMs": 0, "mediaMaxMb": 50 }
  },
  "gateway": {
    "port": 18789,
    "mode": "local",
    "bind": "lan",
    "http": {
      "endpoints": {
        "chatCompletions": {
          "enabled": true
        }
      }
    },
    "controlUi": {
      "enabled": true,
      "dangerouslyDisableDeviceAuth": true,
      "allowedOrigins": [ "https://$urlopenclaw" ]
    },
    "auth": { "mode": "token", "token": "$key" },
    "trustedProxies": [ "127.0.0.1", "10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16" ],
    "tailscale": { "mode": "off", "resetOnExit": false },
    "remote": { "url": "ws://$nome_app_openclaw-gateway:18789" }
  },
"plugins": {
  "allow": ["cognee-openclaw"],
  "entries": {
    "whatsapp": { "enabled": true },
    "telegram": { "enabled": false }
  }
},
  "auth": { "profiles": {} },
  "models": { "providers": {} },
  "agents": {
     "defaults": { "models": {}, "workspace": "/home/node/.openclaw/workspace" }
  }
}
EOF



# =================================================================
# FUNDINDO A CONFIGURAÇÃO DE IA COM O JSON PRINCIPAL
# =================================================================
FINAL_JSON=$(mktemp)

if [ -n "$PROVIDER" ]; then
    if [ "$PROVIDER" = "openai" ]; then
cat > /tmp/ai_config.json << EOF
{
  "auth": { "profiles": { "openai:default": { "provider": "openai", "mode": "api_key" } } },
  "models": { "providers": { "openai": { "apiKey": "$API_KEY", "baseUrl": "https://api.openai.com/v1", "api": "openai-responses", "models": [ { "id": "$MODEL", "name": "OpenAI $MODEL", "input": [ "text", "image" ], "contextWindow": 128000 } ] } } },
  "agents": { "defaults": { "models": { "openai/$MODEL": {} }, "workspace": "/home/node/.openclaw/workspace", "model": { "primary": "openai/$MODEL" } } }
}
EOF
    elif [ "$PROVIDER" = "google" ]; then
cat > /tmp/ai_config.json << EOF
{
  "auth": { "profiles": { "google:default": { "provider": "google", "mode": "api_key" } } },
  "models": { "providers": { "google": { "apiKey": "$API_KEY", "baseUrl": "https://generativelanguage.googleapis.com/v1beta", "api": "google-generative-ai", "models": [ { "id": "$MODEL", "name": "Google $MODEL", "input": [ "text", "image" ], "contextWindow": 1000000 } ] } } },
  "agents": { "defaults": { "models": { "google/$MODEL": {} }, "workspace": "/home/node/.openclaw/workspace", "model": { "primary": "google/$MODEL" } } }
}
EOF
   elif [ "$PROVIDER" = "anthropic" ]; then
cat > /tmp/ai_config.json << EOF
{
  "auth": { "profiles": { "anthropic:default": { "provider": "anthropic", "mode": "api_key" } } },
  "models": { "providers": { "anthropic": { "apiKey": "$API_KEY", "baseUrl": "https://api.anthropic.com/v1", "api": "anthropic-messages", "models": [ { "id": "$MODEL", "name": "Anthropic $MODEL", "input": [ "text", "image" ], "contextWindow": 200000 } ] } } },
  "agents": { "defaults": { "models": { "anthropic/$MODEL": {} }, "workspace": "/home/node/.openclaw/workspace", "model": { "primary": "anthropic/$MODEL" } } }
}
EOF
    elif [ "$PROVIDER" = "xai" ]; then
cat > /tmp/ai_config.json << EOF
{
  "auth": { "profiles": { "xai:default": { "provider": "xai", "mode": "api_key" } } },
  "models": { "providers": { "xai": { "apiKey": "$API_KEY", "baseUrl": "https://api.x.ai/v1", "api": "openai", "models": [ { "id": "$MODEL", "name": "xAI $MODEL", "input": [ "text", "image" ], "contextWindow": 128000 } ] } } },
  "agents": { "defaults": { "models": { "xai/$MODEL": {} }, "workspace": "/home/node/.openclaw/workspace", "model": { "primary": "xai/$MODEL" } } }
}
EOF
    elif [ "$PROVIDER" = "openrouter" ]; then
cat > /tmp/ai_config.json << EOF
{
  "auth": { "profiles": { "openrouter:default": { "provider": "openrouter", "mode": "api_key" } } },
  "models": { "providers": { "openrouter": { "apiKey": "$API_KEY", "baseUrl": "https://openrouter.ai/api/v1", "api": "openai-responses", "models": [ { "id": "$MODEL", "name": "OpenRouter $MODEL", "input": [ "text", "image" ], "contextWindow": 128000 } ] } } },
  "agents": { "defaults": { "models": { "openrouter/$MODEL": {} }, "workspace": "/home/node/.openclaw/workspace", "model": { "primary": "openrouter/$MODEL" } } }
}
EOF
    fi



if [ -f /tmp/ai_config.json ]; then
        jq -s '.[0] * .[1] |
            .tools.web.search = {"enabled": false} |
            .plugins.entries["cognee-openclaw"] = {"enabled": true, "config": {"baseUrl": "http://'${nome_app_cognee}'-web:8000"}} |
            .channels.whatsapp.groupPolicy = "open"
        ' "$TMP_JSON" /tmp/ai_config.json > "$FINAL_JSON"
        rm -f /tmp/ai_config.json
    fi
else
    # Sem IA definida (apenas liga ferramentas básicas)
    jq '
        .tools.web.search = {"enabled": false} |
        .plugins.entries["cognee-openclaw"] = {"enabled": true, "config": {"baseUrl": "http://'${nome_app_cognee}'-web:8000"}} |
        .channels.whatsapp.groupPolicy = "open"
    ' "$TMP_JSON" > "$FINAL_JSON"
fi

mv "$FINAL_JSON" "$TMP_JSON"
# =================================================================

# =================================================================
# INJEÇÃO DO TELEGRAM (SE ATIVADO)
# =================================================================
if [ "$TELEGRAM_ENABLED" = "true" ]; then
    TEMP_TG=$(mktemp)
    jq --arg tg_id "$TELEGRAM_ALLOWED_ID" --arg tg_token "$TELEGRAM_BOT_TOKEN" '
        .plugins.entries.telegram.enabled = true |
        .channels.telegram = {
            "enabled": true,
            "botToken": $tg_token,
            "dmPolicy": "allowlist",
            "allowFrom": [$tg_id],
            "groupPolicy": "allowlist",
            "streaming": "partial"
        }
    ' "$TMP_JSON" > "$TEMP_TG"
    mv "$TEMP_TG" "$TMP_JSON"
fi


# =================================================================

# =================================================================
# CRIANDO OS ARQUIVOS DE IDENTIDADE E FERRAMENTAS (ROOT)
# =================================================================
echo -e "XXX\n98\nATUALIZANDO INFRA - (AGUARDE - ISSO PODE DEMORAR) \nXXX"

# 1. ARQUIVO DE IDENTIDADE (PERSONALIDADE E REGRAS DE NEGÓCIO) DEPENDENDO DO MODELO

if [[ "$MODEL" == *"mini"* || "$MODEL" == *"haiku"* || "$MODEL" == *"flash"* || "$MODEL" == *"8b"* ]]; then
# PROMPT RESTRITIVO (MILITAR) PARA MODELOS MENORES
cat > /root/IDENTITY.md << EOF
Você é um Especialista em Atendimento e Vendas de Alta Conversão. O seu objetivo é conduzir o cliente, tirar dúvidas e mapear oportunidades de negócios.
Seu nome é Marcos.
Fale sempre em português brasileiro.

**🛑 DIRETRIZ TÉCNICA DE SISTEMA (CRÍTICA E INVIOLÁVEL) 🛑**
Você opera dentro de um servidor Linux headless.
- PROIBIDO acionar a ferramenta \`browser\`.
- Sempre que precisar de informações externas da internet, consulte estritamente o seu manual de ferramentas (TOOLS) para ver os endpoints permitidos.

**🧠 GESTÃO DE MEMÓRIA E CRM (COGNEE - OBRIGATÓRIO):**
Você atua como o CRM da empresa. Você possui uma ferramenta de sistema nativa para escrever na memória (ex: escrever no arquivo MEMORY.md ou acionar a tool de memória). Você DEVE USAR esta ferramenta IMEDIATAMENTE e de forma proativa sempre que identificar os seguintes gatilhos na fala do cliente:
1. **Dados Pessoais/Profissionais:** Nome, cargo, empresa, cidade, telefone.
2. **Dores e Reclamações:** Qualquer insatisfação com o cenário atual, críticas a concorrentes ou problemas que ele precisa resolver.
3. **Desejos e Interesses:** Interesse explícito em algum produto/serviço, orçamentos, ou objetivos de negócio.
4. **Objeções:** O que está impedindo ele de comprar (ex: "Achei caro", "Não tenho tempo").
5. **Comando do Chefe:** Se o Francis pedir para salvar algo na Memória longa, sempre acione a tool de memória e salve imediatamente.

**Como agir:** Quando o cliente soltar uma dessas informações, responda naturalmente no chat mantendo a empatia, mas, NOS BASTIDORES, acione a sua ferramenta de escrita na memória registrando o fato de forma clara e direta.

**🌍 REGRA ESTRITA DE BUSCA NA INTERNET:**
Quando o usuário perguntar sobre eventos, shows, cotações, notícias ou dados em tempo real, você é OBRIGADO a usar a sua ferramenta nativa chamada \`search\`. 
- NUNCA use a ferramenta \`web_fetch\` para tentar adivinhar URLs. 
- NUNCA diga que está sem acesso. 
- Use APENAS a ferramenta \`search\`, leia os resumos que ela retornar e responda ao cliente.

**🤫 REGRA DE OURO DO ATENDIMENTO INVISÍVEL (CRÍTICO):**
- NUNCA narre as suas ações ou pensamentos.
- NUNCA diga frases como "Vou pesquisar", "Deixe-me consultar", "Não tenho acesso a X", ou mencione nomes de ferramentas (como Brave Search, SearXNG, APIs, etc).
- O cliente NÃO PODE saber que você usa ferramentas ou motores de busca.
- Apenas EXECUTE a busca em silêncio nos bastidores e entregue a resposta final de forma natural, direta e imediata.
EOF

else
# PROMPT CONSULTIVO PARA MODELOS PRO
cat > /root/IDENTITY.md << EOF
Você é um Especialista em Atendimento e Vendas de Alta Conversão. O seu objetivo é conduzir o cliente, tirar dúvidas e mapear oportunidades de negócios.
Seu nome é Marcos.
Fale sempre em português brasileiro.

**🛑 DIRETRIZ TÉCNICA DE SISTEMA (CRÍTICA E INVIOLÁVEL) 🛑**
Você opera dentro de um servidor Linux headless.
- PROIBIDO acionar a ferramenta \`browser\`.
- Sempre que precisar de informações externas da internet, consulte estritamente o seu manual de ferramentas (TOOLS) para ver os endpoints permitidos.

**🧠 GESTÃO DE MEMÓRIA E CRM (COGNEE - OBRIGATÓRIO):**
Você atua como o CRM da empresa. Você possui uma ferramenta de sistema nativa para escrever na memória (ex: escrever no arquivo MEMORY.md ou acionar a tool de memória). Você DEVE USAR esta ferramenta IMEDIATAMENTE e de forma proativa sempre que identificar os seguintes gatilhos na fala do cliente:
1. **Dados Pessoais/Profissionais:** Nome, cargo, empresa, cidade, telefone.
2. **Dores e Reclamações:** Qualquer insatisfação com o cenário atual, críticas a concorrentes ou problemas que ele precisa resolver.
3. **Desejos e Interesses:** Interesse explícito em algum produto/serviço, orçamentos, ou objetivos de negócio.
4. **Objeções:** O que está impedindo ele de comprar (ex: "Achei caro", "Não tenho tempo").
5. **Comando do Chefe:** Se o Francis pedir para salvar algo na Memória longa, sempre acione a tool de memória e salve imediatamente.

**Como agir:** Quando o cliente soltar uma dessas informações, responda naturalmente no chat mantendo a empatia, mas, NOS BASTIDORES, acione a sua ferramenta de escrita na memória registrando o fato de forma clara e direta (Ex: "O cliente João reclamou que o sistema atual dele é lento", ou "A Maria tem interesse na consultoria premium").

**🔍 REGRA ABSOLUTA DE PESQUISA (LEIA COM ATENÇÃO):**
1. Para responder sobre eventos, shows, cotações, ou notícias, PROIBIDO usar \`web_fetch\`.
2. Use EXCLUSIVAMENTE a sua ferramenta de requisição web apontando para o seu Motor de Busca Privado (conforme detalhado no arquivo TOOLS.md).
3. SOB NENHUMA HIPÓTESE diga "Não consegui acessar" ou mande o cliente ir ao site oficial.

**🤫 REGRA DE OURO DO ATENDIMENTO INVISÍVEL (CRÍTICO):**
- NUNCA narre as suas ações ou pensamentos.
- NUNCA diga frases como "Vou pesquisar", "Deixe-me consultar", "Não tenho acesso a X", ou mencione nomes de ferramentas (como Brave Search, SearXNG, APIs, etc).
- O cliente NÃO PODE saber que você usa ferramentas ou motores de busca.
- Apenas EXECUTE a busca em silêncio nos bastidores e entregue a resposta final de forma natural, direta e imediata.
EOF
fi

# 2. ARQUIVO DE FERRAMENTAS (MAPA DA INFRAESTRUTURA)
cat > /root/TOOLS.md << EOF
# TOOLS.md - Manual de Infraestrutura Interna do Megazord

Você é um agente autônomo corporativo. Seu nome é Marcos. Para interagir com o mundo externo, buscar dados e salvar informações no CRM da empresa, você DEVE utilizar OBRIGATORIAMENTE suas ferramentas descritas abaixo.
Seu chefe é Francis.
---

### 🧠 Memória de Longo Prazo e CRM (Cognee)
Você tem acesso a uma ferramenta de sistema para escrever em arquivos (geralmente documentada nas suas tools nativas como \`Write to MEMORY.md\` ou similar). 
- **Obrigação:** Sempre que o usuário mencionar dados pessoais, interesses de compra, reclamações ou objeções, VOCÊ DEVE usar essa ferramenta para gravar a informação. 
- **Ordem do Chefe:** Sempre que o Francis solicitar para você salvar na memória de longo prazo (memória longa) VOCÊ DEVE usar essa ferramenta para gravar as informações solicitadas.
- **Formato:** Grave a informação como uma afirmação direta para o banco de grafos processar. (Ex: "O prospect demonstrou interesse em automatizar o WhatsApp").

---

### 🔍 2. Motor de Busca Privado (SearXNG)
Você não possui uma ferramenta nativa de busca habilitada. Sempre que o usuário pedir informações atualizadas da internet (notícias, cotações, dados em tempo real, pesquisas), você deve fazer um GET na nossa API de busca interna.
- **Endpoint:** \`http://${nome_app_searxng}-web:8080/search\`
- **Regras de Uso:** 1. Passe o parâmetro \`q\` com a sua pesquisa.
  2. Passe OBRIGATORIAMENTE o parâmetro \`format=json\` para que a resposta seja estruturada para você ler.
- **Exemplo de uso:** Faça uma requisição web para \`http://${nome_app_searxng}-web:8080/search?q=cotacao+do+dolar+hoje&format=json\`

EOF

# =================================================================


# Aplica o JSON no container e ajusta permissões
docker exec -u 0 $CONTAINER_ID mkdir -p /home/node/.openclaw
docker cp "$TMP_JSON" $CONTAINER_ID:/home/node/.openclaw/openclaw.json
docker exec -u 0 $CONTAINER_ID chown -R 1000:1000 /home/node/.openclaw


# docker service update
#docker service update --force --with-registry-auth --image $imagem_openclaw ${nome_app_openclaw}_${nome_app_openclaw}-gateway >/dev/null 2>&1

#docker service update  ${nome_app_openclaw}_${nome_app_openclaw}-gateway >/dev/null 2>&1


rm -f "$TMP_JSON"
docker service update --force ${nome_app_openclaw}_${nome_app_openclaw}-gateway >/dev/null 2>&1
echo -e "XXX\n100\nINSTALAÇÃO DO OPENCLAW CONCLUÍDA! \nXXX"
sleep 3

}|whiptail --title "OPENCLAW COMBO PRO - PROGRESSO DA INSTALAÇÃO" --gauge "Aguarde a instalação do OPENCLAW COMBO PRO" 6 60 0

# VERIFICAÇÃO FINAL - Versão Corrigida (SearXNG Removido da checagem)
if [ "$INSTALL_TYPE" = "CLOUDFLARE_TUNNEL" ]; then
    failed_domains=0
    domains_to_check="$urlneo4j $urlqdrant $urlcognee $urlopenclaw"

    for domain in $domains_to_check; do
        if ! nslookup "$domain" >/dev/null 2>&1; then
            ((failed_domains++))
        elif ! nslookup "$domain" | grep -q "${TUNNEL_ID}.cfargotunnel.com"; then
            : # DNS pode estar em propagação
        else
            : # Domínio configurado
        fi
    done

    if [ $failed_domains -eq 0 ]; then

        whiptail --title "Mensagem" --msgbox "Parabéns, OpenClaw Combo Pro instalado com sucesso!\n\n🌐 Acesse: https://$urlopenclaw\n🔑 Salve o seu Gateway Token: $key\n\n🧠 ATENÇÃO: Foram gerados dois arquivos essenciais no seu servidor:\n\n1) /root/IDENTITY.md (Cole no IDENTITY.md)\n2) /root/TOOLS.md (Cole na aba TOOLS.md)\n\nCopie o conteúdo deles para o painel do OpenClaw para garantir a integração do SearXNG e Cognee.\n\nPressione ENTER para voltar ao Menu Principal" 22 78
    else
        whiptail --title "Aviso" --msgbox "Instalação concluída, mas $failed_domains domínio(s) podem precisar de ajustes no DNS.\n\nIsso é normal logo após a criação - o DNS pode levar alguns minutos para propagar.\n\nSe o problema persistir, verifique:\n1. Os registros CNAME no Cloudflare\n2. A configuração do Tunnel\n3. As rotas no Cloudflare Tunnel\n\nPressione ENTER para voltar ao Menu Principal" 20 78

    fi
else
    ip_servidor=$(curl -s --max-time 10 ipinfo.io/ip)
    status=0
    
    dns_ip1=$(timeout 10 nslookup "$urlneo4j" 2>/dev/null | grep "Address" | tail -n1 | awk '{print $2}')
    dns_ip2=$(timeout 10 nslookup "$urlqdrant" 2>/dev/null | grep "Address" | tail -n1 | awk '{print $2}')
    dns_ip3=$(timeout 10 nslookup "$urlcognee" 2>/dev/null | grep "Address" | tail -n1 | awk '{print $2}')
    dns_ip5=$(timeout 10 nslookup "$urlopenclaw" 2>/dev/null | grep "Address" | tail -n1 | awk '{print $2}')
    [[ "$dns_ip1" != "$ip_servidor" ]] && status=1
    [[ "$dns_ip2" != "$ip_servidor" ]] && status=1
    [[ "$dns_ip3" != "$ip_servidor" ]] && status=1
    [[ "$dns_ip5" != "$ip_servidor" ]] && status=1

    if [[ $status -eq 1 ]]; then

        whiptail --title "Erro" --msgbox "Não foi possível acessar um ou mais subdomínios. Verifique os apontamentos de DNS." 20 78
    else
        whiptail --title "Sucesso" --msgbox "Instalação concluída com sucesso!\n\nForam gerados os arquivos de configuração:\n1) /root/IDENTITY.md\n2) /root/TOOLS.md\n\nCole o conteúdo deles no painel do OpenClaw.\nTecle enter para continuar." 20 78

    fi
fi

exit 0

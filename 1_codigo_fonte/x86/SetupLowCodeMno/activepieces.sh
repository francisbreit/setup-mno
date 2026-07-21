#!/usr/bin/bash
#########################################################
#
# LOADING
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

#
# NOME DO PROGRAMA
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

# CARREGAR SENHA DO POSTGRES
if [ -f "/root/.postgres_config/postgres_password" ]; then
    source "/root/.postgres_config/postgres_password"
fi
postgres_password=$(grep -oP '(?<=POSTGRES_PASSWORD=).+' /root/postgres.yaml)

function msg() {
    msg=$1
    whiptail --title "INSTALAÇÃO DO ACTIVEPIECES" --msgbox "$msg" --fb 10 70;
}

while true; do
CHOICE=$(
whiptail --title "INSTALAÇÃO DO ACTIVEPIECES" --menu "Aperte ENTER para iniciar a instalação ou selecione SAIR (Utilize setas e Enter)\n\nTIPO DE INSTALAÇÃO DETECTADA: $INSTALL_TYPE\n\nINSTRUÇÕES:\nAntes de prosseguir, verifique os registros DNS conforme seu tipo de instalação:" 20 70 2 \
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


while true ; do
    url_activepieces=$(whiptail --title "1/2 - URL do ActivePieces" --inputbox "Digite o dominio para acessar o ActivePieces (ex: activepieces.dominio.com):" --fb 12 60 3>&1 1>&2 2>&3) ; saida=$?
    if [[ $saida -eq '0' ]] ; then
        if [[ -z $url_activepieces ]] ; then msg "Digite o link do ACTIVEPIECES para poder continuar" ; continue ; else break; fi
    else
        echo $url_activepieces ; echo "saindo..."  &  exit 0 ;
    fi
done

# Verificar se URL já existe no Cloudflare Tunnel (ANTES do gauge)
if [ "$INSTALL_TYPE" = "CLOUDFLARE_TUNNEL" ]; then
    CHECK_RESPONSE=$(curl -sS -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
      "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/cfd_tunnel/$TUNNEL_ID/configurations")
    EXISTING_HOST=$(echo "$CHECK_RESPONSE" | jq -r --arg h "$url_activepieces" '.result.config.ingress[] | select(.hostname == $h) | .hostname' 2>/dev/null)
    if [[ -n "$EXISTING_HOST" ]]; then
        EXISTING_SERVICE=$(echo "$CHECK_RESPONSE" | jq -r --arg h "$url_activepieces" '.result.config.ingress[] | select(.hostname == $h) | .service' 2>/dev/null)
        whiptail --title "Rota Existente" --msgbox "Já existe uma rota configurada para:\n\nURL: $url_activepieces\nServiço atual: $EXISTING_SERVICE\n\nA rota será substituída pela nova aplicação." --fb 14 70
    fi
fi

while true ; do
    criar_portainer=$(whiptail --title "2/2 - Criar Stack no Portainer?" --inputbox "Digite 0 para criar stack editável no Portainer ou 1 para criar direto no Docker:" --fb 12 60 3>&1 1>&2 2>&3) ; saida=$?
    if [[ $saida -eq '0' ]] ; then
        if [[ "$criar_portainer" != "0" && "$criar_portainer" != "1" ]] ; then msg "Digite apenas 0 ou 1" ; continue ; else break; fi
    else
        echo $criar_portainer ; echo "saindo..."  &  exit 0 ;
    fi
done

    # Exibe as informações formatadas
    whiptail --title "Dados Fornecidos" \
    --msgbox "TIPO DE INSTALAÇÃO: $INSTALL_TYPE\n\nDados Preenchidos:\n\n1) Dominio do ActivePieces: $url_activepieces\n2) Criar Stack no Portainer: $([ "$criar_portainer" == "0" ] && echo "0 (Editável)" || echo "1 (Não editável)")\n\nConfira e Tecle Enter para continuar." \
    --fb 16 70

# Solicita confirmação dentro de um loop
while true; do
{
  tput reset 2>/dev/null
  exec 0</dev/tty 1>/dev/tty 2>&1
  sleep 0.01
  clear
} || true
    confirma1=$(whiptail --title "Confirmação" \
    --inputbox "Informações estavam corretas? Digite 'y' para confirmar e instalar ou 'n' para voltar e corrigir:" \
    --fb 10 60 3>&1 1>&2 2>&3)
    if [[ "$confirma1" =~ ^[yY]$ ]]; then
        break
    elif [[ "$confirma1" =~ ^[nN]$ ]]; then
        msg "Você digitou N e não confirmou os dados preenchidos. Tecle Enter para sair da instalação"
        exit 0
    else
        msg "Entrada inválida! Por favor, use apenas 'y' para sim ou 'n' para não."
    fi
done

#
# FIM DE VERIFICAÇÃO DE DADOS
#
#########################################################
#
# MENSAGEM DE INSTALANDO
#
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

# Verificar se variáveis do Cloudflare estão definidas
if [ -z "$CLOUDFLARE_API_TOKEN" ] || [ -z "$CLOUDFLARE_ZONE_ID" ]; then
    echo -e "XXX\n8\nAVISO: CREDENCIAIS DO CLOUDFLARE NÃO ENCONTRADAS \nXXX"
    sleep 3
fi

# GERAR SUFIXO ÚNICO (como keycloak.sh)
nome_principal="activepieces"
sufixo_app=$(date | md5sum | head -c7)
nome_app=$nome_principal$sufixo_app

if [ "$INSTALL_TYPE" = "TRADICIONAL" ]; then
    # CONFIGURAÇÃO TRADICIONAL COM DNS AUTOMÁTICO
    echo -e "XXX\n10\nCONFIGURANDO DNS AUTOMÁTICO (TRADICIONAL)... \nXXX"

    DOMINIO_PRINCIPAL=$(echo "$url_activepieces" | cut -d'.' -f2-)
    SUBDOMINIO=${url_activepieces%%.$DOMINIO_PRINCIPAL}

    # Verificar se nome_servidor está definido
    if [ -z "$nome_servidor" ]; then
        echo -e "XXX\n12\nAVISO: nome_servidor NÃO DEFINIDO - Usando IP do servidor \nXXX"
        nome_servidor=$(hostname -I | awk '{print $1}')
    fi

    echo -e "XXX\n15\nVERIFICANDO REGISTROS EXISTENTES... \nXXX"
    EXISTING_RECORDS=$(curl -s -X GET \
        "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records?name=${url_activepieces}" \
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
        --data '{"type":"CNAME","name":"'${url_activepieces}'","content":"'${nome_servidor}'.'${DOMINIO_PRINCIPAL}'","ttl":1,"proxied":false}')

    if echo "$CNAME_RESPONSE" | grep -q '"success":true'; then
        echo -e "XXX\n30\nREGISTRO CNAME CRIADO COM SUCESSO! \nXXX"
    else
        echo -e "XXX\n30\nAVISO: ERRO AO CRIAR REGISTRO CNAME \nXXX"
        echo "$CNAME_RESPONSE" | jq -r '.errors[].message' 2>/dev/null
    fi

elif [ "$INSTALL_TYPE" = "CLOUDFLARE_TUNNEL" ]; then
    # CONFIGURAÇÃO CLOUDFLARE TUNNEL - DNS E ROTAS (API)
    echo -e "XXX\n10\nCONFIGURANDO CLOUDFLARE TUNNEL (DNS + ROTAS)... \nXXX"

    DOMINIO_PRINCIPAL=$(echo "$url_activepieces" | cut -d'.' -f2-)
    SUBDOMINIO=${url_activepieces%%.$DOMINIO_PRINCIPAL}

    echo -e "XXX\n15\nCONFIGURANDO REGISTRO DNS... \nXXX"

    EXISTING_RECORDS=$(curl -s -X GET \
        "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records?name=${url_activepieces}" \
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

    CNAME_RESPONSE=$(curl -s -X POST \
        "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records" \
        -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
        -H "Content-Type: application/json" \
        --data '{"type":"CNAME","name":"'${url_activepieces}'","content":"'${TUNNEL_ID}'.cfargotunnel.com","ttl":1,"proxied":true}')

    if echo "$CNAME_RESPONSE" | grep -q '"success":true'; then
        echo -e "XXX\n20\nREGISTRO DNS CRIADO COM SUCESSO! \nXXX"
    else
        echo -e "XXX\n20\nAVISO: ERRO AO CRIAR REGISTRO DNS \nXXX"
    fi

    echo -e "XXX\n25\nATUALIZANDO CONFIGURAÇÃO DO TUNNEL... \nXXX"

    NEW_SERVICE="http://${nome_app}:80"

    TIMESTAMP=$(date -u +%Y%m%dT%H%M%SZ)
    TMPDIR=$(mktemp -d)
    BACKUP_RAW="$TMPDIR/backup_raw.$TIMESTAMP.json"
    TO_PUT="$TMPDIR/to_put.$TIMESTAMP.json"

    echo -e "XXX\n30\nOBTENDO CONFIGURAÇÃO ATUAL DO TUNNEL... \nXXX"
    curl -sS -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
      "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/cfd_tunnel/$TUNNEL_ID/configurations" \
      | jq '.' > "$BACKUP_RAW"

    if ! jq -e '.success == true' "$BACKUP_RAW" >/dev/null 2>&1; then
        echo -e "XXX\n35\nERRO: FALHA AO OBTER CONFIGURAÇÃO DO TUNNEL \nXXX"
        sleep 3
    else
        echo -e "XXX\n35\nCONFIGURAÇÃO OBTIDA COM SUCESSO \nXXX"
    fi

    echo -e "XXX\n40\nCONFIGURANDO NOVAS ROTAS... \nXXX"

    jq --arg host "$url_activepieces" --arg service "$NEW_SERVICE" '
      (.result.config // {}) as $cfg
      | ($cfg.ingress // []) as $ing
      | ($ing | map(select(.service != "http_status:404"))) as $clean
      
      | ($clean | map(select(.hostname != $host))) as $filtered
      | ($filtered + [ { hostname: $host, service: $service, originRequest: { noTlsVerify: true, httpHostHeader: $host } } ]) as $merged
      | ($merged + [{ service: "http_status:404" }]) as $final_ing
      | ($cfg + { ingress: $final_ing }) as $newcfg
      | { config: $newcfg }
    ' "$BACKUP_RAW" > "$TO_PUT"

    echo -e "XXX\n45\nAPLICANDO NOVA CONFIGURAÇÃO DO TUNNEL... \nXXX"
    APPLY_RESPONSE=$(curl -sS -X PUT "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/cfd_tunnel/$TUNNEL_ID/configurations" \
      -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
      -H "Content-Type: application/json" \
      --data-binary @"$TO_PUT")

    if echo "$APPLY_RESPONSE" | grep -q '"success":true'; then
        echo -e "XXX\n50\nTUNNEL CONFIGURADO COM SUCESSO! \nXXX"
    else
        echo -e "XXX\n50\nAVISO: ERRO AO CONFIGURAR TUNNEL \nXXX"
    fi

    rm -rf "$TMPDIR"

else
    # TRADICIONAL COM DNS MANUAL
    echo -e "XXX\n10\nMODO DNS MANUAL - Verificando subdomínio... \nXXX"

    ip_servidor=$(curl -s --max-time 10 ipinfo.io/ip)

    echo -e "XXX\n15\nVERIFICANDO SUBDOMÍNIO: $url_activepieces \nXXX"
    sleep 3

    tentativas=5
    tentativa_atual=1
    sucesso=0

    while [ $tentativa_atual -le $tentativas ]; do
        echo -e "XXX\n$(( (tentativa_atual * 12) / tentativas + 3 ))\nTentativa $tentativa_atual de $tentativas...\nXXX"

        dns_ip=$(timeout 10 nslookup -type=A "$url_activepieces" | grep -E "Address: [0-9]+\." | awk '{print $2}' | head -n1)

        if [[ -n "$dns_ip" && "$dns_ip" == "$ip_servidor" ]]; then
            sucesso=1
        fi

        sleep 1
        ((tentativa_atual++))
    done

    if [ $sucesso -eq 0 ]; then
        echo -e "XXX\n10\nERRO: SUBDOMÍNIO NÃO APONTA PARA O IP ($ip_servidor) \nXXX"
        sleep 3
        echo -e "XXX\n18\nERRO: DNS NÃO CONFIGURADO CORRETAMENTE \nXXX"
        sleep 3
        exit 1
    fi
    echo -e "XXX\n18\nDOMÍNIO VERIFICADO COM SUCESSO \nXXX"
    sleep 4
fi


echo -e "XXX\n55\nVERIFICANDO POSTGRES... \nXXX"
sleep 1

# Verificar se PostgreSQL está rodando
if ! docker ps --format '{{.Names}}' | grep -q postgres; then
    echo -e "XXX\n60\nPOSTGRES NÃO ENCONTRADO - ERRO \nXXX"
    sleep 3
    msg "PostgreSQL não está rodando. Instale o PostgreSQL primeiro."
    exit 1
fi

echo -e "XXX\n62\nPOSTGRES VERIFICADO! \nXXX"
sleep 1

echo -e "XXX\n64\nCRIANDO BANCO DE DADOS... \nXXX"
sleep 1

# Criar banco de dados para ActivePieces (com sufixo)
POSTGRES_CONTAINER=$(docker ps --filter "name=postgres" --format "{{.Names}}" | head -1)
docker exec -t "$POSTGRES_CONTAINER" psql -U postgres -c "CREATE DATABASE $nome_app;" > /dev/null 2>&1

echo -e "XXX\n66\nBANCO DE DADOS $nome_app CRIADO! \nXXX"
sleep 1

echo -e "XXX\n68\nCRIANDO STACK DO ACTIVEPIECES... \nXXX"
sleep 1

cd
cd

# Gerar secrets aleatórios
apikey_activepieces=$(openssl rand -hex 16)
encryptionkey_activepieces=$(openssl rand -hex 16)
jwtsecret_activepieces=$(openssl rand -hex 16)

# Criar o docker-compose.yml (com sufixo no nome)
cat > $nome_app.yaml << EOL

version: "3.7"
services:

  $nome_app:
    image: activepieces/activepieces:latest

    volumes:
      - ${nome_app}_cache:/usr/src/app/cache

    networks:
      - externa
      - interna

    environment:
      - AP_ENVIRONMENT=prod
      - AP_FRONTEND_URL=https://$url_activepieces
      - AP_TEMPLATES_SOURCE_URL=https://cloud.activepieces.com/api/v1/flow-templates
      - AP_API_KEY=$apikey_activepieces
      - AP_ENCRYPTION_KEY=$encryptionkey_activepieces
      - AP_JWT_SECRET=$jwtsecret_activepieces
      - AP_POSTGRES_HOST=postgres
      - AP_POSTGRES_PORT=5432
      - AP_POSTGRES_DATABASE=$nome_app
      - AP_POSTGRES_USERNAME=postgres
      - AP_POSTGRES_PASSWORD=$postgres_password
      - AP_REDIS_HOST=${nome_app}_redis
      - AP_REDIS_PORT=6379
      - AP_ENGINE_EXECUTABLE_PATH=dist/packages/engine/main.js
      - AP_EXECUTION_MODE=UNSANDBOXED
      - AP_FLOW_TIMEOUT_SECONDS=600
      - AP_TRIGGER_DEFAULT_POLL_INTERVAL=5
      - AP_WEBHOOK_TIMEOUT_SECONDS=30
      - AP_TELEMETRY_ENABLED=false

    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
          - node.role == manager
      resources:
        limits:
          cpus: "1"
          memory: 1024M
EOL
# Adicionar as labels apenas se for instalação tradicional
if [ "$INSTALL_TYPE" = "TRADICIONAL" ]; then
cat >> $nome_app.yaml << EOL
      labels:
      - traefik.enable=true
      - traefik.docker.network=externa
      - traefik.http.routers.$nome_app.rule=Host(\`$url_activepieces\`)
      - traefik.http.routers.$nome_app.entrypoints=websecure
      - traefik.http.routers.$nome_app.priority=1
      - traefik.http.routers.$nome_app.tls.certresolver=letsencryptresolver
      - traefik.http.routers.$nome_app.tls=true
      - traefik.http.routers.$nome_app.service=$nome_app
      - traefik.http.services.$nome_app.loadbalancer.server.port=80
EOL
fi
cat >> $nome_app.yaml << EOL

  ${nome_app}_redis:
    image: redis:latest
    command: [
        "redis-server",
        "--appendonly",
        "yes",
        "--port",
        "6379"
      ]

    volumes:
      - ${nome_app}_redis:/data

    networks:
      - externa
      - interna

    deploy:
      placement:
        constraints:
          - node.role == manager
      resources:
        limits:
          cpus: "1"
          memory: 2048M

volumes:
  ${nome_app}_cache:
    external: true
    name: ${nome_app}_cache
  ${nome_app}_redis:
    external: true
    name: ${nome_app}_redis

networks:
  externa:
    external: true
  interna:
    external: true


EOL

echo -e "XXX\n70\nSTACK DO ACTIVEPIECES $nome_app CRIADA! \nXXX"
sleep 1

echo -e "XXX\n72\nCRIANDO VOLUMES EXTERNOS... \nXXX"
sleep 1

# Criar volumes externos (com sufixo)
for vol in ${nome_app}_cache ${nome_app}_redis; do
    docker volume create --name $vol > /dev/null 2>&1
done

echo -e "XXX\n74\nVOLUMES CRIADOS! \nXXX"
sleep 1

echo -e "XXX\n76\nFAZENDO DEPLOY DA STACK... \nXXX"
sleep 1

# Deploy da stack
if [ "$criar_portainer" = "0" ]; then
    # Criar stack via Portainer API
    STACK_NAME=$nome_app
    STACK_FILE_PATH="/root/$nome_app.yaml"
    
    # Ler credenciais do Portainer
    dados_file="$HOME/dados_portainer/dados_portainer"
    if [[ -f "$dados_file" ]]; then
        PORTAINER_URL=$(grep "Dominio do portainer:" "$dados_file" | cut -d':' -f2- | xargs)
        ADMIN_USERNAME=$(grep "Usuario:" "$dados_file" | cut -d':' -f2 | xargs)
        ADMIN_PASSWORD=$(grep "Senha:" "$dados_file" | cut -d':' -f2 | xargs)
        
        echo -e "XXX\n78\nCONECTANDO AO PORTAINER: $PORTAINER_URL \nXXX"
        
        # Autenticar no Portainer
        RESPONSE=$(curl -sk -X POST "https://$PORTAINER_URL/api/auth" \
            -H "Content-Type: application/json" \
            -d "{\"username\": \"$ADMIN_USERNAME\", \"password\": \"$ADMIN_PASSWORD\"}")
        TOKEN=$(echo "$RESPONSE" | jq -r '.jwt')
        
        if [ -n "$TOKEN" ] && [ "$TOKEN" != "null" ]; then
            echo -e "XXX\n79\nAUTENTICAÇÃO OK - OBTENDO ENDPOINTS... \nXXX"
            
            # Obter EndpointID
            RESPONSE=$(curl -sk -X GET "https://$PORTAINER_URL/api/endpoints" \
                -H "Authorization: Bearer $TOKEN")
            ENDPOINT_ID=$(echo "$RESPONSE" | jq -r '.[0].Id')
            
            # Obter SwarmID
            RESPONSE=$(curl -sk -X GET "https://$PORTAINER_URL/api/endpoints/$ENDPOINT_ID/docker/swarm" \
                -H "Authorization: Bearer $TOKEN")
            SWARM_ID=$(echo "$RESPONSE" | jq -r '.ID')
            
            echo -e "XXX\n80\nCRIANDO STACK $STACK_NAME NO PORTAINER... \nXXX"
            
            # Criar stack
            http_code=$(curl -s -o /dev/null -w "%{http_code}" -k -X POST \
                -H "Authorization: Bearer $TOKEN" \
                -F "Name=$STACK_NAME" \
                -F "file=@$STACK_FILE_PATH" \
                -F "SwarmID=$SWARM_ID" \
                -F "endpointId=$ENDPOINT_ID" \
                "https://$PORTAINER_URL/api/stacks/create/swarm/file")
            
            if [ "$http_code" = "200" ]; then
                echo -e "XXX\n82\n✅ STACK CRIADA NO PORTAINER COM SUCESSO! \nXXX"
            else
                echo -e "XXX\n82\n⚠️ ERRO HTTP $http_code AO CRIAR STACK - Usando docker deploy... \nXXX"
                docker stack deploy --prune --resolve-image always -c $nome_app.yaml $nome_app > /dev/null 2>&1
            fi
        else
            echo -e "XXX\n82\n⚠️ ERRO NA AUTENTICAÇÃO DO PORTAINER - Usando docker deploy... \nXXX"
            docker stack deploy --prune --resolve-image always -c $nome_app.yaml $nome_app > /dev/null 2>&1
        fi
    else
        echo -e "XXX\n82\n⚠️ ARQUIVO dados_portainer NÃO ENCONTRADO - Usando docker deploy... \nXXX"
        docker stack deploy --prune --resolve-image always -c $nome_app.yaml $nome_app > /dev/null 2>&1
    fi
else
    # Criar stack direto no Docker
    echo -e "XXX\n78\nCRIANDO STACK DIRETO NO DOCKER... \nXXX"
    docker stack deploy --prune --resolve-image always -c $nome_app.yaml $nome_app > /dev/null 2>&1
    echo -e "XXX\n82\n✅ STACK CRIADA COM SUCESSO! \nXXX"
fi

echo -e "XXX\n84\nSTACK EM DEPLOY... \nXXX"
sleep 3

echo -e "XXX\n86\nAGUARDANDO SERVIÇOS... \nXXX"

# Aguardar serviços ficarem prontos
for i in $(seq 1 60); do
    if docker service ls --filter "name=${nome_app}" --format "{{.Replicas}}" | grep -q "1/1"; then
        break
    fi
    sleep 5
    echo -e "XXX\n$((86 + (i * 5)/60))\nAGUARDANDO SERVIÇOS... ($i/60)\nXXX"
done

echo -e "XXX\n95\nINSTALAÇÃO CONCLUIDA! \nXXX"
sleep 1

}|whiptail --title "SETUPMNO" --gauge "Aguarde a instalação do ActivePieces" 6 60 0

clear

# Exibir dados finais
whiptail --title "ACTIVEPIECES INSTALADO COM SUCESSO!" \
--msgbox "✅ ACTIVEPIECES INSTALADO!\n\n📌 ACESSO: https://$url_activepieces\n\n👤 USUARIO: Crie no primeiro acesso\n🔑 SENHA: Crie no primeiro acesso\n\n⚠️ Ao acessar pela primeira vez, crie sua conta de administrador." \
--fb 14 70

cd /
cd

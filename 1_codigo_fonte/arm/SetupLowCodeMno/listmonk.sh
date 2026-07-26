#!/usr/bin/bash
# ============================================================
# INSTALAÇÃO DO LISTMONK (Newsletter/Mailing)
# ============================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'
msg() { echo -e "${RED}$1${NC}"; }

# DETECÇÃO DO TIPO DE INSTALAÇÃO
INSTALL_TYPE_FILE="/root/.cloudflared_config/installation_type"
if [ -f "$INSTALL_TYPE_FILE" ]; then
    INSTALL_TYPE=$(cat "$INSTALL_TYPE_FILE")
else
    INSTALL_TYPE="TRADICIONAL"
fi

# CARREGAMENTO DE CREDENCIAIS
if [ "$INSTALL_TYPE" = "CLOUDFLARE_TUNNEL" ]; then
    source "/root/.cloudflared_config/cloudflare_credentials"
else
    source "/root/.tradicional_config/tradicional_credentials"
fi

# MENU INICIAL
while true; do
    opcao=$(whiptail --title "INSTALAÇÃO DO LISTMONK" --menu "O que deseja fazer?" --fb 12 60 2 \
        "1" "Instalar Listmonk" \
        "2" "Sair" 3>&1 1>&2 2>&3)
    case $opcao in
        "1") break ;;
        "2") exit 0 ;;
        *) msg "Opção inválida" ;;
    esac
done

# COLETA DE DADOS
while true; do
    url_listmonk=$(whiptail --title "1/4 - URL do Listmonk" --inputbox "Digite o domínio (ex: mail.dominio.com):" --fb 12 60 3>&1 1>&2 2>&3) ; saida=$?
    if [[ $saida -eq '0' ]]; then
        [[ -z $url_listmonk ]] && { msg "Digite o link"; continue; } || break
    else
        echo $url_listmonk; echo "saindo..." & exit 0
    fi
done

while true; do
    admin_user=$(whiptail --title "2/4 - Usuário Admin" --inputbox "Digite o email do admin:" --fb 12 60 3>&1 1>&2 2>&3) ; saida=$?
    if [[ $saida -eq '0' ]]; then
        [[ -z $admin_user ]] && { msg "Preencha o email"; continue; } || break
    else exit 0; fi
done

while true; do
    admin_pass=$(whiptail --title "3/4 - Senha Admin" --passwordbox "Digite a senha do admin:" --fb 12 60 3>&1 1>&2 2>&3) ; saida=$?
    if [[ $saida -eq '0' ]]; then
        [[ -z $admin_pass ]] && { msg "Preencha a senha"; continue; } || break
    else exit 0; fi
done

# Pergunta Portainer
while true; do
    criar_portainer=$(whiptail --title "4/4 - Criar Stack no Portainer?" --inputbox "Digite 0 para criar stack editável no Portainer ou 1 para criar direto no Docker:" --fb 12 60 3>&1 1>&2 2>&3) ; saida=$?
    if [[ $saida -eq '0' ]]; then
        if [[ "$criar_portainer" != "0" && "$criar_portainer" != "1" ]]; then msg "Digite apenas 0 ou 1"; continue; else break; fi
    else
        echo $criar_portainer; echo "saindo..." & exit 0
    fi
done

# GERAR SENHA E SUFIXO
listmonk_db_pass=$(openssl rand -hex 32)
nome_principal="listmonk"
sufixo_app=$(date | md5sum | head -c7)
nome_app=$nome_principal$sufixo_app

# CRIAR USUARIO E BANCO NO POSTGRESQL COMPARTILHADO
container_id=$(docker ps -qf name=postgres)
docker exec $container_id psql -U postgres -d postgres -c "DROP DATABASE IF EXISTS listmonk;" >/dev/null 2>&1
docker exec $container_id psql -U postgres -d postgres -c "DROP USER IF EXISTS listmonk;" >/dev/null 2>&1
docker exec $container_id psql -U postgres -d postgres -c "CREATE USER listmonk WITH PASSWORD '${listmonk_db_pass}';" >/dev/null 2>&1
docker exec $container_id psql -U postgres -d postgres -c "CREATE DATABASE listmonk OWNER listmonk;" >/dev/null 2>&1
docker exec $container_id psql -U postgres -d postgres -c "GRANT ALL PRIVILEGES ON DATABASE listmonk TO listmonk;" >/dev/null 2>&1
docker exec $container_id psql -U postgres -d listmonk -c "GRANT ALL ON SCHEMA public TO listmonk;" >/dev/null 2>&1

# TELA DE CONFIRMAÇÃO
clear
{
    tput reset 2>/dev/null
    exec 0</dev/tty 1>/dev/tty 2>&1
    sleep 0.01
    clear
} || true

whiptail --title "Dados Fornecidos" \
    --msgbox "TIPO DE INSTALAÇÃO: $INSTALL_TYPE\n\n1) URL: $url_listmonk\n2) Admin: $admin_user\n3) Portainer: $([ "$criar_portainer" == "0" ] && echo "0 (Editável)" || echo "1 (Não editável)")\n\nTecle Enter." \
    --fb 14 70

while true; do
    {
        tput reset 2>/dev/null
        exec 0</dev/tty 1>/dev/tty 2>&1
        sleep 0.01
        clear
    } || true
    confirma1=$(whiptail --title "Confirmação" \
        --inputbox "Confirmar? (y/n):" --fb 10 60 3>&1 1>&2 2>&3)
    if [[ $confirma1 =~ ^[yY]$ ]]; then
        break
    elif [[ $confirma1 =~ ^[nN]$ ]]; then
        msg "Saindo..."; exit 0
    else
        msg "Use 'y' ou 'n'"
    fi
done

# MENSAGEM DE INSTALANDO
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

if [ "$INSTALL_TYPE" = "TRADICIONAL" ]; then
    echo -e "XXX\n10\nCONFIGURANDO DNS AUTOMÁTICO... \nXXX"
    DOMINIO_PRINCIPAL=$(echo "$url_listmonk" | cut -d'.' -f2-)

    EXISTING_RECORDS=$(curl -s -X GET \
        "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records?name=${url_listmonk}" \
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
        --data '{"type":"CNAME","name":"'${url_listmonk}'","content":"'${nome_servidor}'.'${DOMINIO_PRINCIPAL}'","ttl":1,"proxied":false}')

elif [ "$INSTALL_TYPE" = "CLOUDFLARE_TUNNEL" ]; then
    echo -e "XXX\n10\nCONFIGURANDO CLOUDFLARE TUNNEL... \nXXX"
    DOMINIO_PRINCIPAL=$(echo "$url_listmonk" | cut -d'.' -f2-)

    EXISTING_RECORDS=$(curl -s -X GET \
        "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records?name=${url_listmonk}" \
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

    curl -s -X POST \
        "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records" \
        -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
        -H "Content-Type: application/json" \
        --data "{\"type\":\"CNAME\",\"name\":\"${url_listmonk}\",\"content\":\"${TUNNEL_ID}.cfargotunnel.com\",\"ttl\":1,\"proxied\":true}" >/dev/null 2>&1

    NEW_SERVICE="http://${nome_app}:9000"
    TIMESTAMP=$(date -u +%Y%m%dT%H%M%SZ)
    TMPDIR=$(mktemp -d)
    BACKUP_RAW="$TMPDIR/backup_raw.$TIMESTAMP.json"
    TO_PUT="$TMPDIR/to_put.$TIMESTAMP.json"

    curl -sS -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
        "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/cfd_tunnel/$TUNNEL_ID/configurations" \
        | jq '.' > "$BACKUP_RAW"

    jq --arg host "$url_listmonk" --arg service "$NEW_SERVICE" '
        (.result.config // {}) as $cfg
        | ($cfg.ingress // []) as $ing
        | ($ing | map(select(.service != "http_status:404"))) as $clean
        | ($clean | map(select(.hostname != $host))) as $filtered
        | ($filtered + [ { hostname: $host, service: $service, originRequest: { noTlsVerify: true, httpHostHeader: $host } } ]) as $merged
        | ($merged + [{ service: "http_status:404" }]) as $final_ing
        | ($cfg + { ingress: $final_ing }) as $newcfg
        | { config: $newcfg }
    ' "$BACKUP_RAW" > "$TO_PUT"

    curl -sS -X PUT "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/cfd_tunnel/$TUNNEL_ID/configurations" \
        -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
        -H "Content-Type: application/json" \
        --data-binary @"$TO_PUT" >/dev/null 2>&1
    rm -rf "$TMPDIR"
fi

echo -e "XXX\n50\nCRIANDO STACK DO LISTMONK... \nXXX"

cd
cd

cat > $nome_app.yaml << EOL

version: "3.7"
services:
  ${nome_app}:
    image: listmonk/listmonk:latest
    hostname: ${nome_app}
    networks:
      - externa
      - interna
    command: [sh, -c, "./listmonk --install --idempotent --yes --config '' && ./listmonk --upgrade --yes --config '' && ./listmonk --config ''"]
    environment:
      - LISTMONK_app__address=0.0.0.0:9000
      - LISTMONK_db__user=listmonk
      - LISTMONK_db__password=${listmonk_db_pass}
      - LISTMONK_db__database=listmonk
      - LISTMONK_db__host=postgres
      - LISTMONK_db__port=5432
      - LISTMONK_db__ssl_mode=disable
      - LISTMONK_db__max_open=25
      - LISTMONK_db__max_idle=25
      - LISTMONK_db__max_lifetime=300s
      - LISTMONK_ADMIN_USER=${admin_user}
      - LISTMONK_ADMIN_PASSWORD=${admin_pass}
      - TZ=America/Sao_Paulo
    volumes:
      - ${nome_app}_uploads:/listmonk/uploads
    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
        - node.role == manager
      resources:
        limits:
          cpus: "1"
          memory: 512M
EOL

if [ "$INSTALL_TYPE" = "TRADICIONAL" ]; then
cat >> $nome_app.yaml << EOL
      labels:
      - traefik.enable=true
      - traefik.docker.network=externa
      - traefik.http.routers.${nome_app}.rule=Host(\`${url_listmonk}\`)
      - traefik.http.routers.${nome_app}.entrypoints=websecure
      - traefik.http.routers.${nome_app}.priority=1
      - traefik.http.routers.${nome_app}.tls.certresolver=letsencryptresolver
      - traefik.http.routers.${nome_app}.tls=true
      - traefik.http.routers.${nome_app}.service=${nome_app}
      - traefik.http.services.${nome_app}.loadbalancer.server.port=9000
EOL
fi

cat >> $nome_app.yaml << EOL

networks:
  externa:
    external: true
  interna:
    external: true

volumes:
  ${nome_app}_uploads:
    external: true
    name: ${nome_app}_uploads
EOL

# DEPLOY
if [[ "$criar_portainer" == "0" ]]; then
    dados_file="$HOME/dados_portainer/dados_portainer"
    if [[ -f "$dados_file" ]]; then
        PORTAINER_URL=$(grep "Dominio do portainer:" "$dados_file" | cut -d':' -f2 | xargs)
        ADMIN_USERNAME=$(grep "Usuario:" "$dados_file" | cut -d':' -f2 | xargs)
        ADMIN_PASSWORD=$(grep "Senha:" "$dados_file" | cut -d':' -f2 | xargs)
        STACK_NAME=$nome_app
        STACK_FILE_PATH="/root/$nome_app.yaml"
    else
        docker stack deploy --prune --resolve-image always -c $nome_app.yaml $nome_app >/dev/null 2>&1
        exit 1
    fi

    get_auth_token() {
        RESPONSE=$(curl -sk -X POST "https://$PORTAINER_URL/api/auth" \
            -H "Content-Type: application/json" \
            -d "{\"username\": \"$ADMIN_USERNAME\", \"password\": \"$ADMIN_PASSWORD\"}")
        TOKEN=$(echo "$RESPONSE" | jq -r '.jwt')
        if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]; then
            docker stack deploy --prune --resolve-image always -c $nome_app.yaml $nome_app >/dev/null 2>&1
            exit 1
        fi
    }

    get_endpoint_id() {
        RESPONSE=$(curl -sk -X GET "https://$PORTAINER_URL/api/endpoints" \
            -H "Authorization: Bearer $TOKEN")
        ENDPOINT_ID=$(echo "$RESPONSE" | jq -r '.[0].Id')
        if [ -z "$ENDPOINT_ID" ] || [ "$ENDPOINT_ID" = "null" ]; then
            docker stack deploy --prune --resolve-image always -c $nome_app.yaml $nome_app >/dev/null 2>&1
            exit 1
        fi
    }

    get_swarm_id() {
        RESPONSE=$(curl -sk -X GET "https://$PORTAINER_URL/api/endpoints/$ENDPOINT_ID/docker/swarm" \
            -H "Authorization: Bearer $TOKEN")
        SWARM_ID=$(echo "$RESPONSE" | jq -r '.ID')
        if [ -z "$SWARM_ID" ] || [ "$SWARM_ID" = "null" ]; then
            docker stack deploy --prune --resolve-image always -c $nome_app.yaml $nome_app >/dev/null 2>&1
            exit 1
        fi
    }

    create_stack() {
        if [ ! -f "$STACK_FILE_PATH" ]; then
            docker stack deploy --prune --resolve-image always -c $nome_app.yaml $nome_app >/dev/null 2>&1
            exit 1
        fi
        response_output=$(mktemp)
        erro_output=$(mktemp)
        http_code=$(curl -s -o "$response_output" -w "%{http_code}" -k -X POST \
            -H "Authorization: Bearer $TOKEN" \
            -F "Name=$STACK_NAME" \
            -F "file=@$STACK_FILE_PATH" \
            -F "SwarmID=$SWARM_ID" \
            -F "endpointId=$ENDPOINT_ID" \
            "https://$PORTAINER_URL/api/stacks/create/swarm/file" 2> "$erro_output")
        response=$(cat "$response_output")
        rm -f "$response_output" "$erro_output"
        if [ "$http_code" -ne 200 ]; then
            docker stack deploy --prune --resolve-image always -c $nome_app.yaml $nome_app >/dev/null 2>&1
            exit 1
        fi
    }

    get_auth_token || exit 1
    get_endpoint_id || exit 1
    get_swarm_id || exit 1
    create_stack || exit 1

elif [[ "$criar_portainer" == "1" ]]; then
    docker stack deploy --prune --resolve-image always -c $nome_app.yaml $nome_app >/dev/null 2>&1
else
    docker stack deploy --prune --resolve-image always -c $nome_app.yaml $nome_app >/dev/null 2>&1
    exit 1
fi

echo -e "XXX\n90\nFINALIZANDO... \nXXX"
sleep 12
echo -e "XXX\n100\nINSTALAÇÃO CONCLUÍDA! \nXXX"
sleep 3

}|whiptail --title "LISTMONK - PROGRESSO DA INSTALAÇÃO" --gauge "Aguarde a instalação dos itens necessários" 6 60 0

# VERIFICAÇÃO FINAL
if [ "$INSTALL_TYPE" = "TRADICIONAL" ]; then
    ip_servidor=$(curl -s --max-time 10 ipinfo.io/ip)
    dns_ip=$(timeout 10 nslookup "$url_listmonk" | grep "Address" | tail -n1 | awk '{print $2}' 2>/dev/null)
    if [[ "$dns_ip" != "$ip_servidor" ]]; then
        whiptail --title "Mensagem" --msgbox "Não foi possível acessar $url_listmonk. Verifique o DNS.\n\nPressione ENTER." 20 78
    else
        whiptail --title "Mensagem" --msgbox "Listmonk instalado com sucesso!\n\nAcesse: https://$url_listmonk\nLogin: $admin_user\n\nPressione ENTER." 20 78
    fi
else
    if nslookup "$url_listmonk" >/dev/null 2>&1; then
        whiptail --title "Mensagem" --msgbox "Listmonk instalado com sucesso!\n\nAcesse: https://$url_listmonk\nLogin: $admin_user\n\nPressione ENTER." 20 78
    else
        whiptail --title "Mensagem" --msgbox "AVISO: $url_listmonk não está resolvendo.\nVerifique o Cloudflare Tunnel.\n\nPressione ENTER." 20 78
    fi
fi

exit 0

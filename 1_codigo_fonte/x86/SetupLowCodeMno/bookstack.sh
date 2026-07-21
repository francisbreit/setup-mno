#!/usr/bin/bash
#########################################################
# BOOKSTACK - SETUP MNO
# Wiki/documentação open-source (alternativa ao Confluence)
# Usa MySQL 8.0 compartilhado
#########################################################

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
    whiptail --title "INSTALAÇÃO DO BOOKSTACK: WIKI" --msgbox "$msg" --fb 10 70;
}

while true; do
CHOICE=$(
whiptail --title "INSTALAÇÃO DO BOOKSTACK: WIKI" --menu "Aperte ENTER para iniciar a instalação ou selecione SAIR (Utilize setas e Enter)\n\nTIPO DE INSTALAÇÃO DETECTADA: $INSTALL_TYPE\n\nINSTRUÇÕES:\nAntes de prosseguir, verifique os registros DNS conforme seu tipo de instalação:" 20 70 2 \
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
    url_bookstack=$(whiptail --title "1/3 - URL do BookStack" --inputbox "Digite o dominio para acessar o BookStack (ex: wiki.dominio.com):" --fb 12 60 3>&1 1>&2 2>&3) ; saida=$?
    if [[ $saida -eq '0' ]] ; then
        if [[ -z $url_bookstack ]] ; then msg "Digite o link do BOOKSTACK para poder continuar" ; continue ; else break; fi
    else
        echo $url_bookstack ; echo "saindo..."  &  exit 0 ;
    fi
done

while true ; do
    criar_portainer=$(whiptail --title "2/3 - Criar Stack no Portainer?" --inputbox "Digite 0 para criar stack editável no Portainer ou 1 para criar direto no Docker:" --fb 12 60 3>&1 1>&2 2>&3) ; saida=$?
    if [[ $saida -eq '0' ]] ; then
        if [[ "$criar_portainer" != "0" && "$criar_portainer" != "1" ]] ; then msg "Digite apenas 0 ou 1" ; continue ; else break; fi
    else
        echo $criar_portainer ; echo "saindo..."  &  exit 0 ;
    fi
done

clear

#
# VERIFICAÇÃO DE DADOS
#

nome_principal="bookstack"
sufixo_app=$(date | md5sum | head -c7)
nome_app=$nome_principal$sufixo_app

{
  tput reset 2>/dev/null
  exec 0</dev/tty 1>/dev/tty 2>&1
  sleep 0.01
  clear
} || true

    whiptail --title "Dados Fornecidos" \
    --msgbox "TIPO DE INSTALAÇÃO: $INSTALL_TYPE\n\nDados Preenchidos:\n\n1) Dominio do BookStack: $url_bookstack\n2) Criar Stack no Portainer: $([ "$criar_portainer" == "0" ] && echo "0 (Editável)" || echo "1 (Não editável)")\n\nConfira e Tecle Enter para continuar." \
    --fb 16 80

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

if [ "$INSTALL_TYPE" = "TRADICIONAL" ]; then
    echo -e "XXX\n10\nCONFIGURANDO DNS AUTOMÁTICO (TRADICIONAL)... \nXXX"

    DOMINIO_PRINCIPAL=$(echo "$url_bookstack" | cut -d'.' -f2-)

    echo -e "XXX\n15\nVERIFICANDO REGISTROS EXISTENTES... \nXXX"
    EXISTING_RECORDS=$(curl -s -X GET \
        "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records?name=${url_bookstack}" \
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
        --data '{"type":"CNAME","name":"'${url_bookstack}'","content":"'${nome_servidor}'.'${DOMINIO_PRINCIPAL}'","ttl":1,"proxied":false}')

    if echo "$CNAME_RESPONSE" | grep -q '"success":true'; then
        echo -e "XXX\n30\nREGISTRO CNAME CRIADO COM SUCESSO! \nXXX"
    else
        echo -e "XXX\n30\nAVISO: ERRO AO CRIAR REGISTRO CNAME \nXXX"
    fi

elif [ "$INSTALL_TYPE" = "CLOUDFLARE_TUNNEL" ]; then
    echo -e "XXX\n10\nCONFIGURANDO CLOUDFLARE TUNNEL (DNS + ROTAS)... \nXXX"

    DOMINIO_PRINCIPAL=$(echo "$url_bookstack" | cut -d'.' -f2-)

    echo -e "XXX\n15\nCONFIGURANDO REGISTRO DNS... \nXXX"

    EXISTING_RECORDS=$(curl -s -X GET \
        "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records?name=${url_bookstack}" \
        -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
        -H "Content-Type: application/json")

    COUNT=$(echo "$EXISTING_RECORDS" | jq '.result | length')
    if [[ "$COUNT" -gt 0 ]]; then
        echo -e "XXX\n20\nREMOVENDO REGISTROS DNS ANTIGOS... \nXXX"
        echo "$EXISTING_RECORDS" | jq -r '.result[].id' | while read -r REC_ID; do
            [[ -z "$REC_ID" ]] && continue
            curl -s -X DELETE \
                "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records/${REC_ID}" \
                -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
                -H "Content-Type: application/json" >/dev/null 2>&1
        done
    fi

    echo -e "XXX\n25\nCRIANDO REGISTRO CNAME PARA TUNNEL... \nXXX"
    DNS_RESPONSE=$(curl -s -X POST \
        "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records" \
        -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
        -H "Content-Type: application/json" \
        --data "{\"type\":\"CNAME\",\"name\":\"${url_bookstack}\",\"content\":\"${TUNNEL_ID}.cfargotunnel.com\",\"ttl\":1,\"proxied\":true}")

    if echo "$DNS_RESPONSE" | grep -q '"success":true'; then
        echo -e "XXX\n30\nREGISTRO DNS CRIADO COM SUCESSO! \nXXX"
    else
        echo -e "XXX\n30\nAVISO: ERRO AO CRIAR REGISTRO DNS \nXXX"
    fi

    echo -e "XXX\n35\nATUALIZANDO CONFIGURAÇÃO DO TUNNEL... \nXXX"

    NEW_SERVICE="http://${nome_app}:80"

    TIMESTAMP=$(date -u +%Y%m%dT%H%M%SZ)
    TMPDIR=$(mktemp -d)
    BACKUP_RAW="$TMPDIR/backup_raw.$TIMESTAMP.json"
    TO_PUT="$TMPDIR/to_put.$TIMESTAMP.json"

    echo -e "XXX\n40\nOBTENDO CONFIGURAÇÃO ATUAL DO TUNNEL... \nXXX"
    curl -sS -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
      "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/cfd_tunnel/$TUNNEL_ID/configurations" \
      | jq '.' > "$BACKUP_RAW"

    if ! jq -e '.success == true' "$BACKUP_RAW" >/dev/null 2>&1; then
        echo -e "XXX\n45\nERRO: FALHA AO OBTER CONFIGURAÇÃO DO TUNNEL \nXXX"
        sleep 3
    else
        echo -e "XXX\n45\nCONFIGURAÇÃO OBTIDA COM SUCESSO \nXXX"
    fi

    echo -e "XXX\n50\nCONFIGURANDO NOVAS ROTAS... \nXXX"

    jq --arg host "$url_bookstack" --arg service "$NEW_SERVICE" '
      (.result.config // {}) as $cfg
      | ($cfg.ingress // []) as $ing
      | ($ing | map(select(.service != "http_status:404"))) as $clean
      | ($clean | map(select(.hostname != $host))) as $filtered
      | ($filtered + [ { hostname: $host, service: $service, originRequest: { noTlsVerify: true, httpHostHeader: $host } } ]) as $merged
      | ($merged + [{ service: "http_status:404" }]) as $final_ing
      | ($cfg + { ingress: $final_ing }) as $newcfg
      | { config: $newcfg }
    ' "$BACKUP_RAW" > "$TO_PUT"

    echo -e "XXX\n55\nAPLICANDO NOVA CONFIGURAÇÃO DO TUNNEL... \nXXX"
    APPLY_RESPONSE=$(curl -sS -X PUT "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/cfd_tunnel/$TUNNEL_ID/configurations" \
      -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
      -H "Content-Type: application/json" \
      --data-binary @"$TO_PUT")

    if echo "$APPLY_RESPONSE" | grep -q '"success":true'; then
        echo -e "XXX\n60\nTUNNEL CONFIGURADO COM SUCESSO! \nXXX"
    else
        echo -e "XXX\n60\nAVISO: ERRO AO CONFIGURAR TUNNEL \nXXX"
    fi

    rm -rf "$TMPDIR"

else
    echo -e "XXX\n10\nVERIFICANDO CONFIGURAÇÃO (TRADICIONAL SEM AUTOMAÇÃO)... \nXXX"
    if nslookup "$url_bookstack" >/dev/null 2>&1; then
        echo -e "XXX\n15\nDNS CONFIGURADO \nXXX"
    else
        echo -e "XXX\n15\nAVISO: VERIFIQUE A CONFIGURAÇÃO DNS \nXXX"
    fi
fi


echo -e "XXX\n21\nCRIANDO STACK DO BOOKSTACK 1/3 \nXXX"
sleep 1
echo -e "XXX\n30\nVERIFICANDO MYSQL 2/3 \nXXX"
sleep 1

echo -e "XXX\n50\nMYSQL CONFIGURADO \nXXX"


# FIM DE MENSAGEM DE INSTALANDO
#
#######################################################
#
#  INSTALANDO O BOOKSTACK
#

cd

cd

# Verificar se MySQL ja existe
if docker stack ls 2>/dev/null | grep -q "mysql "; then
    senha_mysql=$(grep -oP '(?<=MYSQL_ROOT_PASSWORD=).+' /root/mysql.yaml)
else
    senha_mysql=$(openssl rand -hex 8)
    cat > mysql.yaml << EOL
version: '3.7'
services:
    mysql:
        image: percona/percona-server:8.0
        environment:
            - MYSQL_ROOT_PASSWORD=$senha_mysql
            - TZ=America/Sao_Paulo
        networks:
            - interna
        volumes:
            - mysql_data:/var/lib/mysql
        command:
            --character-set-server=utf8mb4 --collation-server=utf8mb4_general_ci --sql-mode="" --default-authentication-plugin=mysql_native_password --port=3306 --max-allowed-packet=512MB
        deploy:
            placement:
                constraints: [node.role == manager]
volumes:
    mysql_data:
networks:
    interna:
        external: true
        name: interna
EOL

    docker stack deploy --prune --resolve-image always -c mysql.yaml mysql >/dev/null 2>&1
    sleep 15
fi

senha_mysql=$(grep -oP '(?<=MYSQL_ROOT_PASSWORD=).+' /root/mysql.yaml)

# Gerar APP_KEY para BookStack (base64 32 bytes)
bookstack_app_key=$(openssl rand -base64 32)

# Criar banco de dados
container_id2=$(docker ps --format "{{.Names}}" | grep -q "^mysql$" && docker ps -qf name=mysql)
if [ -n "$container_id2" ]; then
    docker exec -i $container_id2 bash -c "MYSQL_PWD=\"$senha_mysql\" mysql -u root -e \"CREATE DATABASE bookstack;\"" >/dev/null 2>&1
fi

cat > $nome_app.yaml << EOL

version: "3.7"
services:
  $nome_app:
    image: lscr.io/linuxserver/bookstack:latest
    hostname: $nome_app
    networks:
      - externa
      - interna
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=America/Sao_Paulo
      - APP_URL=https://${url_bookstack}
      - APP_KEY=base64:${bookstack_app_key}
      - DB_HOST=mysql
      - DB_PORT=3306
      - DB_DATABASE=bookstack
      - DB_USERNAME=root
      - DB_PASSWORD=${senha_mysql}
    volumes:
      - ${nome_app}_config:/config
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
if [ "$INSTALL_TYPE" = "TRADICIONAL" ]; then
cat >> $nome_app.yaml << EOL
      labels:
      - traefik.enable=true
      - traefik.docker.network=externa
      - traefik.http.routers.$nome_app.rule=Host(\`$url_bookstack\`)
      - traefik.http.routers.$nome_app.entrypoints=websecure
      - traefik.http.routers.$nome_app.priority=1
      - traefik.http.routers.$nome_app.tls.certresolver=letsencryptresolver
      - traefik.http.routers.$nome_app.tls=true
      - traefik.http.routers.$nome_app.service=$nome_app
      - traefik.http.services.$nome_app.loadbalancer.server.port=80
      - traefik.http.services.$nome_app.loadbalancer.passHostHeader=1
EOL
fi
cat >> $nome_app.yaml << EOL

networks:
  externa:
    external: true
  interna:
    external: true

volumes:
  ${nome_app}_config:
    external: true
    name: ${nome_app}_config

EOL


if [[ "$criar_portainer" == "0" ]]; then
    echo -e "XXX\n76\nCRIANDO STACK NO PORTAINER 3/3  \nXXX"

dados_file="$HOME/dados_portainer/dados_portainer"

if [[ -f "$dados_file" ]]; then
PORTAINER_URL=$(grep "Dominio do portainer:" "$dados_file" | cut -d':' -f2 | xargs)
ADMIN_USERNAME=$(grep "Usuario:" "$dados_file" | cut -d':' -f2 | xargs)
ADMIN_PASSWORD=$(grep "Senha:" "$dados_file" | cut -d':' -f2 | xargs)
STACK_NAME=$nome_app
STACK_FILE_PATH="/root/$nome_app.yaml"

else
    sleep 5
echo -e "XXX\n77\nSEM ARQUIVO DE DADOS DO PORTAINER 3/3  \nXXX"
docker stack deploy --prune --resolve-image always -c $nome_app.yaml $nome_app >/dev/null 2>&1
sleep 5
    exit 1
fi

get_auth_token() {
    echo -e "XXX\n77\nAUTENTICANDO NO PORTAINER... 3/3  \nXXX"
    RESPONSE=$(curl -sk -X POST "https://$PORTAINER_URL/api/auth" \
        -H "Content-Type: application/json" \
        -d "{\"username\": \"$ADMIN_USERNAME\", \"password\": \"$ADMIN_PASSWORD\"}")
    TOKEN=$(echo "$RESPONSE" | jq -r '.jwt')
    if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]; then
        echo -e "XXX\n77\nFALHA NA AUTENTICAÇÃO.. 3/3  \nXXX"
sleep 5
echo -e "XXX\n78\nREVERTENDO E CRIANDO STACK PELO SERVIDOR 3/3  \nXXX"
docker stack deploy --prune --resolve-image always -c $nome_app.yaml $nome_app >/dev/null 2>&1
sleep 5
        exit 1
    fi
 echo -e "XXX\n79\n[SUCESSO] AUTENTICAÇÃO OK 3/3  \nXXX"
}

get_endpoint_id() {
    echo -e "XXX\n80\n[INFO] OBTENDO ENDPOINTID 3/3  \nXXX"
    RESPONSE=$(curl -sk -X GET "https://$PORTAINER_URL/api/endpoints" \
        -H "Authorization: Bearer $TOKEN")
    ENDPOINT_ID=$(echo "$RESPONSE" | jq -r '.[0].Id')
    if [ -z "$ENDPOINT_ID" ] || [ "$ENDPOINT_ID" = "null" ]; then
        echo -e "XXX\n81\n[ERRO] ENDPOINTID NÃO ENCONTRADO 3/3  \nXXX"
        docker stack deploy --prune --resolve-image always -c $nome_app.yaml $nome_app >/dev/null 2>&1
        exit 1
    fi
     echo -e "XXX\n82\n[SUCESSO] ENDPOINTID OBTIDO: $ENDPOINT_ID  3/3  \nXXX"
}

get_swarm_id() {
    echo -e "XXX\n83\n[INFO] OBTENDO SWARMID  3/3  \nXXX"
    RESPONSE=$(curl -sk -X GET "https://$PORTAINER_URL/api/endpoints/$ENDPOINT_ID/docker/swarm" \
        -H "Authorization: Bearer $TOKEN")
    SWARM_ID=$(echo "$RESPONSE" | jq -r '.ID')
    if [ -z "$SWARM_ID" ] || [ "$SWARM_ID" = "null" ]; then
        echo -e "XXX\n84\n[ERRO] SWARMID NÃO ENCONTRADO 3/3  \nXXX"
        docker stack deploy --prune --resolve-image always -c $nome_app.yaml $nome_app >/dev/null 2>&1
        exit 1
    fi
    echo -e "XXX\n85\n[SUCESSO] SWARMID OBTIDO: $SWARM_ID  3/3  \nXXX"
}

create_stack() {
    echo -e "XXX\n86\n[INFO] VERIFICANDO SE YAML EXISTE 3/3  \nXXX"
    if [ ! -f "$STACK_FILE_PATH" ]; then
        echo -e "XXX\n87\n[ERRO] ARQUIVO $STACK_FILE_PATH NÃO ENCONTRADO 3/3  \nXXX"
        docker stack deploy --prune --resolve-image always -c $nome_app.yaml $nome_app >/dev/null 2>&1
        exit 1
    fi

     echo -e "XXX\n88\n[INFO] CRIANDO STACK $STACK_NAME NO PORTAINER 3/3  \nXXX"
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
        echo -e "XXX\n89\n[ERRO] ERRO AO CRIAR STACK 3/3  \nXXX"
        docker stack deploy --prune --resolve-image always -c $nome_app.yaml $nome_app >/dev/null 2>&1
        exit 1
    fi

    echo -e "XXX\n90\n[SUCESSO] STACK $STACK_NAME  CRIADA COM SUCESSO 3/3  \nXXX"
}

get_auth_token || exit 1
get_endpoint_id || exit 1
get_swarm_id || exit 1
create_stack || exit 1



elif [[ "$criar_portainer" == "1" ]]; then
    echo "Criando a stack diretamente no Docker (não editável no Portainer)."
    docker stack deploy --prune --resolve-image always -c $nome_app.yaml $nome_app >/dev/null 2>&1
else
    echo -e "XXX\n91\n[ERRO] ERRO INESPERADO PARA CRIAR STACK NO PORTAINER 3/3  \nXXX"
    sleep 5
    echo -e "XXX\n92\nREVERTENDO E CRIANDO STACK PELO SERVIDOR 3/3  \nXXX"
docker stack deploy --prune --resolve-image always -c $nome_app.yaml $nome_app >/dev/null 2>&1
sleep 5

    exit 1
fi


echo -e "XXX\n95\nFINALIZANDO BUILD DO BOOKSTACK 3/3  \nXXX"

sleep 12

echo -e "XXX\n100\nFINALIZANDO BUILD DO BOOKSTACK 3/3 - CONCLUIDO  \nXXX"

sleep 3

}|whiptail --title "BOOKSTACK - PROGRESSO DA INSTALAÇÃO" --gauge "Aguarde a instalação dos ítens necessários" 6 60 0


#######################################################
#
# VERIFICAÇÃO FINAL
#

if [ "$INSTALL_TYPE" = "TRADICIONAL" ]; then
    ip_servidor=$(curl -s --max-time 10 ipinfo.io/ip)
    dns_ip=$(timeout 10 nslookup "$url_bookstack" | grep "Address" | tail -n1 | awk '{print $2}' 2>/dev/null)

    if [[ "$dns_ip" != "$ip_servidor" ]]; then
        whiptail --title "Mensagem" --msgbox "Não foi possivel acessar o dominio do BookStack ($url_bookstack). Verifique os apontamentos DNS. Pressione ENTER para voltar ao Menu Principal" 20 78
    else
        whiptail --title "Mensagem" --msgbox "Parabéns, BookStack foi instalado com sucesso!\n\nAcesse: https://$url_bookstack\nUsuário: admin@admin.com\nSenha: password\n\n⚠️ Altere a senha após o primeiro login.\n\nPressione ENTER para voltar ao Menu Principal" 22 78
    fi
else
    if nslookup "$url_bookstack" >/dev/null 2>&1; then
        whiptail --title "Mensagem" --msgbox "Parabéns, BookStack foi instalado com sucesso!\n\nAcesse: https://$url_bookstack\nUsuário: admin@admin.com\nSenha: password\n\n⚠️ Altere a senha após o primeiro login.\n\nPressione ENTER para voltar ao Menu Principal" 22 78
    else
        whiptail --title "Mensagem" --msgbox "AVISO: O domínio do BookStack ($url_bookstack) não está resolvendo.\nVerifique a configuração do Cloudflare Tunnel.\n\nPressione ENTER para voltar ao Menu Principal" 20 78
    fi
fi

exit 0

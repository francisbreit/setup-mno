#!/usr/bin/bash
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

INSTALL_TYPE_FILE="/root/.cloudflared_config/installation_type"
if [ -f "$INSTALL_TYPE_FILE" ]; then
    INSTALL_TYPE=$(cat "$INSTALL_TYPE_FILE")
else
    INSTALL_TYPE="TRADICIONAL"
fi

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
    whiptail --title "PLANE: GESTÃO DE PROJETOS (ALTERNATIVA JIRA/LINEAR)" --msgbox "$msg" --fb 10 70
}

while true; do
CHOICE=$(
whiptail --title "PLANE: GESTÃO DE PROJETOS (ALTERNATIVA JIRA/LINEAR)" --menu "Aperte ENTER para iniciar a instalação do PLANE ou selecione SAIR (Utilize setas e Enter)\n\nTIPO DE INSTALAÇÃO DETECTADA: $INSTALL_TYPE\n\nINSTRUÇÕES:\nAntes de prosseguir, verifique os registros DNS conforme seu tipo de instalação:" 20 70 2 \
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
    url_plane=$(whiptail --title "URL DO PLANE" --inputbox "Digite o dominio para acessar o Plane (ex: plane.seudominio.com):" --fb 12 60 3>&1 1>&2 2>&3) ; saida=$?
    if [[ $saida -eq '0' ]] ; then
        if [[ -z $url_plane ]] ; then msg "Digite o link do Plane para poder continuar" ; continue ; else break; fi
    else
        echo $url_plane ; echo "saindo..."  &  exit 0 ;
    fi
done

while true ; do
    email_plane=$(whiptail --title "EMAIL ADMIN" --inputbox "Digite seu email para admin do Plane (ex: admin@dominio.com):" --fb 12 60 3>&1 1>&2 2>&3) ; saida=$?
    if [[ $saida -eq '0' ]] ; then
        if [[ -z $email_plane ]] ; then msg "Digite o email admin para poder continuar" ; continue ; else break; fi
    else
        echo $email_plane ; echo "saindo..."  &  exit 0 ;
    fi
done

rabbit_user="plane_mq_user"
rabbit_pass=$(openssl rand -hex 16)
rabbit_vhost="plane"
secret_key=$(openssl rand -hex 32)

########################################################
# VERIFICAR SE MINIO JÁ EXISTE
########################################################
minio_container=$(docker ps -qf "name=minio")

if [[ ("$minio_container" == "") ]]; then
    msg "Minio não encontrado no servidor. Vamos instalar um Minio compartilhado.\n\nVocê precisará fornecer URLs e credenciais para o Minio."

    while true ; do
        painel=$(whiptail --title "Dominio do Painel do Minio" --inputbox "Digite o Dominio do Painel do Minio (ex: admins3.seudominio.com):" --fb 12 60 3>&1 1>&2 2>&3)
        saida=$?
        if [[ $saida -eq '0' ]]; then
            if [[ -z $painel ]]; then msg "Digite o dominio do painel do Minio para poder continuar" ; continue ; else break; fi
        else
            echo "$painel"; echo "Saindo..."; exit 0
        fi
    done

    while true ; do
        publico=$(whiptail --title "Dominio Público do Minio" --inputbox "Digite o dominio Público (ex: s3.seudominio.com):" --fb 12 60 3>&1 1>&2 2>&3)
        saida=$?
        if [[ $saida -eq '0' ]]; then
            if [[ -z $publico ]]; then msg "Digite o dominio público do Minio para poder continuar" ; continue ; else break; fi
        else
            echo "$publico"; echo "Saindo..."; exit 0
        fi
    done

    while true ; do
        usuariominio=$(whiptail --title "Usuário do Minio" --inputbox "Digite o Usuário do Minio (ex: SeuNome):" --fb 12 60 3>&1 1>&2 2>&3)
        saida=$?
        if [[ $saida -eq '0' ]]; then
            if [[ (-z $usuariominio) || ("$usuariominio" =~ [^a-zA-Z0-9]) || (${#usuariominio} -gt 16) ]]; then
                msg "Digite o nome do usuário do Minio, sem caracteres especiais e até 16 dígitos para poder continuar"
                continue
            else break; fi
        else
            echo "$usuariominio"; echo "Saindo..."; exit 0
        fi
    done

    while true ; do
        senhaminio=$(whiptail --title "Senha do Minio" --inputbox "Crie sua Senha do Minio (ex: senha de acesso. Use uma senha de 8 a 16 dígitos, sem caracteres especiais):" --fb 12 60 3>&1 1>&2 2>&3)
        saida=$?
        if [[ $saida -eq '0' ]]; then
            if [[ (-z $senhaminio) || ("$senhaminio" =~ [^a-zA-Z0-9]) || (${#senhaminio} -lt 8) || (${#senhaminio} -gt 16) ]]; then
                msg "Digite a senha do Minio, sem caracteres especiais e de 8 até 16 dígitos para poder continuar"
                continue
            else break; fi
        else
            echo "$senhaminio"; echo "Saindo..."; exit 0
        fi
    done
fi

while true ; do
    criar_portainer=$(whiptail --title "Criar Stack no Portainer? - 0 ou 1" --inputbox "Digite 0 para poder editar stacks no portainer ou 1 para não poder editar" --fb 12 60 3>&1 1>&2 2>&3) ; saida=$?
    if [[ $saida -eq '0' ]] ; then
        if [[ "$criar_portainer" != "0" && "$criar_portainer" != "1" ]] ; then msg "Digite apenas o número 0 ou o número 1" ; continue ; else break; fi
    else
        echo $criar_portainer ; echo "saindo..."  &  exit 0 ;
    fi
done

nome_principal="plane"
sufixo_app=$(date | md5sum | head -c7 | tr '[:upper:]' '[:lower:]')
nome_app=$nome_principal$sufixo_app
nome_redis="${nome_app}_redis"
nome_mq="${nome_app}_mq"
postgres_password=$(grep -oP '(?<=POSTGRES_PASSWORD=).+' /root/postgres.yaml)

{
  tput reset 2>/dev/null
  exec 0</dev/tty 1>/dev/tty 2>&1
  sleep 0.01
  clear
} || true

whiptail --title "Dados Fornecidos" \
--msgbox "TIPO DE INSTALAÇÃO: $INSTALL_TYPE\n\nDados Preenchidos:\n\n1) URL do Plane: $url_plane\n2) Email Admin: $email_plane\n3) Minio: $([ "$minio_container" != "" ] && echo "Já existente (compartilhado)" || echo "Será instalado")\n4) Criar Stack no Portainer: $([ "$criar_portainer" == "0" ] && echo "0 (Editável)" || echo "1 (Não editável)")\n\nConfira e Tecle Enter para continuar." \
--fb 20 80

while true; do
    confirma1=$(whiptail --title "Confirmação" \
    --inputbox "Informações estavam corretas? Digite 'y' para confirmar e instalar ou 'n' para voltar e corrigir:" \
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

export NEWT_COLORS='
root=,white
window=,black
border=white,black
textbox=white,black
button=black,white
'

clear

{

echo -e "XXX\n5\nVERIFICANDO CONFIGURAÇÃO DE DOMÍNIO... \nXXX"

if [ "$INSTALL_TYPE" = "TRADICIONAL" ] && [ "$criar_dns" = "0" ]; then
    echo -e "XXX\n10\nCONFIGURANDO DNS AUTOMÁTICO (TRADICIONAL)... \nXXX"
    DOMINIO_PRINCIPAL=$(echo "$url_plane" | cut -d'.' -f2-)

    EXISTING_RECORDS=$(curl -s -X GET \
        "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records?name=${url_plane}" \
        -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" -H "Content-Type: application/json")

    COUNT=$(echo "$EXISTING_RECORDS" | jq '.result | length')
    if [[ "$COUNT" -gt 0 ]]; then
        echo -e "XXX\n15\nREMOVENDO REGISTROS ANTIGOS... \nXXX"
        echo "$EXISTING_RECORDS" | jq -r '.result[].id' | while read -r REC_ID; do
            [[ -z "$REC_ID" ]] && continue
            curl -s -X DELETE \
                "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records/${REC_ID}" \
                -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" -H "Content-Type: application/json" >/dev/null 2>&1
        done
    fi

    echo -e "XXX\n20\nCRIANDO REGISTRO CNAME... \nXXX"
    CNAME_RESPONSE=$(curl -s -X POST \
        "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records" \
        -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" -H "Content-Type: application/json" \
        --data '{"type":"CNAME","name":"'${url_plane}'","content":"'${nome_servidor}'.'${DOMINIO_PRINCIPAL}'","ttl":1,"proxied":false}')

    if echo "$CNAME_RESPONSE" | grep -q '"success":true'; then
        echo -e "XXX\n25\nREGISTRO CNAME CRIADO COM SUCESSO! \nXXX"
    else
        echo -e "XXX\n25\nAVISO: ERRO AO CRIAR REGISTRO CNAME \nXXX"
    fi

elif [ "$INSTALL_TYPE" = "CLOUDFLARE_TUNNEL" ]; then
    echo -e "XXX\n10\nCONFIGURANDO CLOUDFLARE TUNNEL (DNS + ROTAS)... \nXXX"

    DOMINIO_PRINCIPAL=$(echo "$url_plane" | cut -d'.' -f2-)

    EXISTING_RECORDS=$(curl -s -X GET \
        "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records?name=${url_plane}" \
        -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" -H "Content-Type: application/json")

    COUNT=$(echo "$EXISTING_RECORDS" | jq '.result | length')
    if [[ "$COUNT" -gt 0 ]]; then
        echo -e "XXX\n15\nREMOVENDO REGISTROS DNS ANTIGOS... \nXXX"
        echo "$EXISTING_RECORDS" | jq -r '.result[].id' | while read -r REC_ID; do
            [[ -z "$REC_ID" ]] && continue
            curl -s -X DELETE \
                "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records/${REC_ID}" \
                -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" -H "Content-Type: application/json" >/dev/null 2>&1
        done
    fi

    echo -e "XXX\n20\nCRIANDO REGISTRO CNAME PARA TUNNEL... \nXXX"
    DNS_RESPONSE=$(curl -s -X POST \
        "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records" \
        -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" -H "Content-Type: application/json" \
        --data "{\"type\":\"CNAME\",\"name\":\"${url_plane}\",\"content\":\"${TUNNEL_ID}.cfargotunnel.com\",\"ttl\":1,\"proxied\":true}")

    echo -e "XXX\n25\nATUALIZANDO CONFIGURAÇÃO DO TUNNEL... \nXXX"
    NEW_SERVICE="http://${nome_app}:80"

    TIMESTAMP=$(date -u +%Y%m%dT%H%M%SZ)
    TMPDIR=$(mktemp -d)
    BACKUP_RAW="$TMPDIR/backup_raw.$TIMESTAMP.json"
    TO_PUT="$TMPDIR/to_put.$TIMESTAMP.json"

    curl -sS -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
      "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/cfd_tunnel/$TUNNEL_ID/configurations" \
      | jq '.' > "$BACKUP_RAW"

    jq --arg host "$url_plane" --arg service "$NEW_SERVICE" '
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
      -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" -H "Content-Type: application/json" \
      --data-binary @"$TO_PUT" >/dev/null 2>&1

    rm -rf "$TMPDIR"

else
    echo -e "XXX\n10\nVERIFICANDO CONFIGURAÇÃO (TRADICIONAL SEM AUTOMAÇÃO)... \nXXX"
    if nslookup "$url_plane" >/dev/null 2>&1; then
        echo -e "XXX\n15\nDNS CONFIGURADO \nXXX"
    else
        echo -e "XXX\n15\nAVISO: VERIFIQUE A CONFIGURAÇÃO DNS \nXXX"
    fi
fi

if [ "$INSTALL_TYPE" = "TRADICIONAL" ] && [ "$criar_dns" = "1" ]; then
    ip_servidor=$(curl -s --max-time 10 ipinfo.io/ip)
    echo -e "XXX\n3\nVERIFICANDO SUBDOMÍNIO: $url_plane \nXXX"
    sleep 3

    tentativas=5
    tentativa_atual=1
    sucesso=0

    while [ $tentativa_atual -le $tentativas ]; do
        echo -e "XXX\n$(( (tentativa_atual * 12) / tentativas + 3 ))\nTentativa $tentativa_atual de $tentativas...\nXXX"
        dns_ip=$(timeout 10 nslookup -type=A "$url_plane" | grep -E "Address: [0-9]+\." | awk '{print $2}' | head -n1)
        if [[ -n "$dns_ip" && "$dns_ip" == "$ip_servidor" ]]; then
            sucesso=1
        fi
        sleep 1
        ((tentativa_atual++))
    done

    if [ $sucesso -eq 0 ]; then
        echo -e "XXX\n10\nERRO: SUBDOMÍNIO NÃO APONTA PARA O IP ($ip_servidor) \nXXX"
        sleep 3
        exit 1
    fi

    echo -e "XXX\n15\nDOMÍNIO VERIFICADO COM SUCESSO \nXXX"
    sleep 2
fi

echo -e "XXX\n30\nCRIANDO BANCO DE DADOS NO POSTGRESQL... \nXXX"
container_id=$(docker ps -qf name=postgres)
docker exec -it $container_id psql -U postgres -d postgres -c "CREATE DATABASE $nome_app;" >/dev/null 2>&1

echo -e "XXX\n35\nCRIANDO VOLUMES EXTERNOS... \nXXX"
docker volume create ${nome_app}_redis_data 2>/dev/null || true
docker volume create ${nome_app}_mq_data 2>/dev/null || true
docker volume create ${nome_app}_uploads 2>/dev/null || true

#######################################################
# MINIO - VERIFICAR OU INSTALAR
#######################################################
if [[ ("$minio_container" == "") ]]; then
    echo -e "XXX\n40\nINSTALANDO MINIO COMPARTILHADO... \nXXX"
    nome_principal2="minio"
    nome_app2=$nome_principal2$sufixo_app

    cd
    mkdir -p ~/dados_minio
    echo "MINIO_USER: $usuariominio" > ~/dados_minio/dados_minio
    echo "MINIO_PASSWORD: $senhaminio" >> ~/dados_minio/dados_minio
    echo "MINIO_PUBLIC_URL: $publico" >> ~/dados_minio/dados_minio
    echo "MINIO_ADMIN_URL: $painel" >> ~/dados_minio/dados_minio

    docker volume create ${nome_app2}-data 2>/dev/null || true

    cd
    cd

    cat > $nome_app2.yaml << EOL
version: "3.7"

services:
  $nome_app2:
    image: quay.io/minio/minio:RELEASE.2025-04-08T15-41-24Z
    command: server /data --console-address ":9001"
    networks:
      - interna
      - externa
    volumes:
      - ${nome_app2}-data:/data
    environment:
      - MINIO_ROOT_USER=$usuariominio
      - MINIO_ROOT_PASSWORD=$senhaminio
      - MINIO_BROWSER_REDIRECT_URL=https://$painel
      - MINIO_SERVER_URL=https://$publico
    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
          - node.role == manager
EOL

if [ "$INSTALL_TYPE" = "TRADICIONAL" ]; then
    cat >> $nome_app2.yaml << EOL
      labels:
        - traefik.enable=true
        - traefik.http.routers.${nome_app2}_public.rule=Host(\`$publico\`)
        - traefik.http.routers.${nome_app2}_public.entrypoints=websecure
        - traefik.http.routers.${nome_app2}_public.tls.certresolver=letsencryptresolver
        - traefik.http.services.${nome_app2}_public.loadbalancer.server.port=9000
        - traefik.http.services.${nome_app2}_public.loadbalancer.passHostHeader=true
        - traefik.http.routers.${nome_app2}_public.service=${nome_app2}_public
        - traefik.http.routers.${nome_app2}_console.rule=Host(\`$painel\`)
        - traefik.http.routers.${nome_app2}_console.entrypoints=websecure
        - traefik.http.routers.${nome_app2}_console.tls.certresolver=letsencryptresolver
        - traefik.http.services.${nome_app2}_console.loadbalancer.server.port=9001
        - traefik.http.services.${nome_app2}_console.loadbalancer.passHostHeader=true
        - traefik.http.routers.${nome_app2}_console.service=${nome_app2}_console
EOL
fi

cat >> $nome_app2.yaml << EOL
volumes:
  ${nome_app2}-data:
    external: true
    name: ${nome_app2}-data

networks:
  interna:
    external: true
  externa:
    external: true
EOL

    echo -e "XXX\n41\nCONFIGURANDO DNS/ROTAS DO MINIO... \nXXX"

    DOMINIO_PRINCIPAL=$(echo "$url_plane" | cut -d'.' -f2-)

    if [ "$INSTALL_TYPE" = "TRADICIONAL" ] && [ "$criar_dns" = "0" ]; then
        for minio_url in "$painel" "$publico"; do
            EXISTING=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records?name=${minio_url}" \
                -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" -H "Content-Type: application/json")
            echo "$EXISTING" | jq -r '.result[].id' | while read -r REC_ID; do
                [[ -z "$REC_ID" ]] && continue
                curl -s -X DELETE "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records/${REC_ID}" \
                    -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" -H "Content-Type: application/json" >/dev/null 2>&1
            done
            curl -s -X POST "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records" \
                -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" -H "Content-Type: application/json" \
                --data '{"type":"CNAME","name":"'"$minio_url"'","content":"'"$nome_servidor"'.'"$DOMINIO_PRINCIPAL"'","ttl":1,"proxied":false}' >/dev/null 2>&1
        done
    elif [ "$INSTALL_TYPE" = "CLOUDFLARE_TUNNEL" ]; then
        TIMESTAMP=$(date -u +%Y%m%dT%H%M%SZ)
        TMPDIR=$(mktemp -d)
        BACKUP_RAW="$TMPDIR/backup_raw.$TIMESTAMP.json"
        TO_PUT="$TMPDIR/to_put.$TIMESTAMP.json"

        curl -sS -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
            "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/cfd_tunnel/$TUNNEL_ID/configurations" \
            | jq '.' > "$BACKUP_RAW"

        for minio_url in "$painel" "$publico"; do
            DNS_RESPONSE=$(curl -s -X POST "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records" \
                -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" -H "Content-Type: application/json" \
                --data "{\"type\":\"CNAME\",\"name\":\"${minio_url}\",\"content\":\"${TUNNEL_ID}.cfargotunnel.com\",\"ttl\":1,\"proxied\":true}")
        done

        jq --arg host_admin "$painel" --arg host_public "$publico" --arg service_admin "http://${nome_app2}:9001" --arg service_public "http://${nome_app2}:9000" '
          (.result.config // {}) as $cfg
          | ($cfg.ingress // []) as $ing
          | ($ing | map(select(.service != "http_status:404"))) as $clean
          | ($clean | map(select(.hostname != $host_admin and .hostname != $host_public))) as $filtered
          | ($filtered + [
              { hostname: $host_admin, service: $service_admin, originRequest: { noTlsVerify: true, httpHostHeader: $host_admin } },
              { hostname: $host_public, service: $service_public, originRequest: { noTlsVerify: true, httpHostHeader: $host_public } }
            ]) as $merged
          | ($merged + [{ service: "http_status:404" }]) as $final_ing
          | ($cfg + { ingress: $final_ing }) as $newcfg
          | { config: $newcfg }
        ' "$BACKUP_RAW" > "$TO_PUT"

        curl -sS -X PUT "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/cfd_tunnel/$TUNNEL_ID/configurations" \
            -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" -H "Content-Type: application/json" \
            --data-binary @"$TO_PUT" >/dev/null 2>&1

        rm -rf "$TMPDIR"
    elif [ "$INSTALL_TYPE" = "TRADICIONAL" ] && [ "$criar_dns" = "1" ]; then
        ip_servidor=$(curl -s --max-time 10 ipinfo.io/ip)
        for minio_url in "$painel" "$publico"; do
            tentativas=5
            tentativa_atual=1
            sucesso=0
            while [ $tentativa_atual -le $tentativas ]; do
                dns_ip=$(timeout 10 nslookup -type=A "$minio_url" | grep -E "Address: [0-9]+\." | awk '{print $2}' | head -n1)
                if [[ -n "$dns_ip" && "$dns_ip" == "$ip_servidor" ]]; then
                    sucesso=1
                fi
                sleep 1
                ((tentativa_atual++))
            done
        done
    fi

    if [[ "$criar_portainer" == "0" ]]; then
        echo -e "XXX\n42\nCRIANDO STACK MINIO NO PORTAINER... \nXXX"
        dados_file="$HOME/dados_portainer/dados_portainer"
        if [[ -f "$dados_file" ]]; then
            PORTAINER_URL=$(grep "Dominio do portainer:" "$dados_file" | cut -d':' -f2 | xargs)
            ADMIN_USERNAME=$(grep "Usuario:" "$dados_file" | cut -d':' -f2 | xargs)
            ADMIN_PASSWORD=$(grep "Senha:" "$dados_file" | cut -d':' -f2 | xargs)
            STACK_NAME=$nome_app2
            STACK_FILE_PATH="/root/$nome_app2.yaml"

            get_auth_token() {
                echo -e "XXX\n43\nAUTENTICANDO NO PORTAINER... \nXXX"
                RESPONSE=$(curl -sk -X POST "https://$PORTAINER_URL/api/auth" -H "Content-Type: application/json" -d "{\"username\": \"$ADMIN_USERNAME\", \"password\": \"$ADMIN_PASSWORD\"}")
                TOKEN=$(echo "$RESPONSE" | jq -r '.jwt')
                if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]; then
                    echo -e "XXX\n44\nFALHA NA AUTENTICAÇÃO, USANDO DOCKER... \nXXX"
                    docker stack deploy --prune --resolve-image always -c $nome_app2.yaml $nome_app2 >/dev/null 2>&1
                    exit 1
                fi
                echo -e "XXX\n44\nAUTENTICAÇÃO OK \nXXX"
            }
            get_endpoint_id() {
                echo -e "XXX\n45\nOBTENDO ENDPOINT ID... \nXXX"
                RESPONSE=$(curl -sk -X GET "https://$PORTAINER_URL/api/endpoints" -H "Authorization: Bearer $TOKEN")
                ENDPOINT_ID=$(echo "$RESPONSE" | jq -r '.[0].Id')
                if [ -z "$ENDPOINT_ID" ] || [ "$ENDPOINT_ID" = "null" ]; then
                    echo -e "XXX\n46\nERRO: ENDPOINT ID NÃO ENCONTRADO \nXXX"
                    docker stack deploy --prune --resolve-image always -c $nome_app2.yaml $nome_app2 >/dev/null 2>&1
                    exit 1
                fi
                echo -e "XXX\n46\nENDPOINT ID OBTIDO \nXXX"
            }
            get_swarm_id() {
                echo -e "XXX\n47\nOBTENDO SWARM ID... \nXXX"
                RESPONSE=$(curl -sk -X GET "https://$PORTAINER_URL/api/endpoints/$ENDPOINT_ID/docker/swarm" -H "Authorization: Bearer $TOKEN")
                SWARM_ID=$(echo "$RESPONSE" | jq -r '.ID')
                if [ -z "$SWARM_ID" ] || [ "$SWARM_ID" = "null" ]; then
                    echo -e "XXX\n48\nERRO: SWARM ID NÃO ENCONTRADO \nXXX"
                    docker stack deploy --prune --resolve-image always -c $nome_app2.yaml $nome_app2 >/dev/null 2>&1
                    exit 1
                fi
                echo -e "XXX\n48\nSWARM ID OBTIDO \nXXX"
            }
            create_stack() {
                echo -e "XXX\n49\nCRIANDO STACK $STACK_NAME NO PORTAINER... \nXXX"
                if [ ! -f "$STACK_FILE_PATH" ]; then
                    echo -e "XXX\n50\nARQUIVO YAML NÃO ENCONTRADO \nXXX"
                    docker stack deploy --prune --resolve-image always -c $nome_app2.yaml $nome_app2 >/dev/null 2>&1
                    exit 1
                fi
                response_output=$(mktemp)
                erro_output=$(mktemp)
                http_code=$(curl -s -o "$response_output" -w "%{http_code}" -k -X POST \
                    -H "Authorization: Bearer $TOKEN" -F "Name=$STACK_NAME" -F "file=@$STACK_FILE_PATH" \
                    -F "SwarmID=$SWARM_ID" -F "endpointId=$ENDPOINT_ID" \
                    "https://$PORTAINER_URL/api/stacks/create/swarm/file" 2> "$erro_output")
                rm -f "$response_output" "$erro_output"
                if [ "$http_code" -ne 200 ]; then
                    echo -e "XXX\n51\nERRO AO CRIAR STACK, USANDO DOCKER... \nXXX"
                    docker stack deploy --prune --resolve-image always -c $nome_app2.yaml $nome_app2 >/dev/null 2>&1
                    exit 1
                fi
                echo -e "XXX\n51\nSTACK $STACK_NAME CRIADA COM SUCESSO \nXXX"
            }
            get_auth_token || exit 1
            get_endpoint_id || exit 1
            get_swarm_id || exit 1
            create_stack || exit 1
        else
            docker stack deploy --prune --resolve-image always -c $nome_app2.yaml $nome_app2 >/dev/null 2>&1
        fi
    else
        docker stack deploy --prune --resolve-image always -c $nome_app2.yaml $nome_app2 >/dev/null 2>&1
    fi

    echo -e "XXX\n52\nAGUARDANDO MINIO INICIAR... \nXXX"
    sleep 15
fi

#######################################################
# CRIAR BUCKET + SERVICE ACCOUNT NO MINIO
#######################################################
echo -e "XXX\n55\nCRIANDO BUCKET E CREDENCIAIS NO MINIO... \nXXX"

if [[ ("$minio_container" != "") ]]; then
    minio_service=$(docker service ls --format "{{.Name}}" 2>/dev/null | grep "minio" | head -1)
    if [[ -n "$minio_service" ]]; then
        MINIO_HOST=$minio_service
    else
        minio_container_name=$(docker ps --format "{{.Names}}" | grep "minio" | head -1)
        MINIO_HOST=$(echo $minio_container_name | cut -d'.' -f1)
    fi
    dados_minio_file="$HOME/dados_minio/dados_minio"
    if [[ -f "$dados_minio_file" ]]; then
        MINIO_USER=$(grep "MINIO_USER:" "$dados_minio_file" | awk '{print $2}')
        MINIO_PASSWORD=$(grep "MINIO_PASSWORD:" "$dados_minio_file" | awk '{print $2}')
        MINIO_PUBLIC_URL=$(grep "MINIO_PUBLIC_URL:" "$dados_minio_file" | awk '{print $2}')
    fi
    MINIO_ADDRESS="${MINIO_HOST}:9000"
else
    MINIO_HOST=$nome_app2
    MINIO_ADDRESS="${MINIO_HOST}:9000"
    MINIO_USER=$usuariominio
    MINIO_PASSWORD=$senhaminio
    MINIO_PUBLIC_URL=$publico
fi

bucket_name="$nome_app"

# Usar docker exec no container do MinIO (mc vem embutido na imagem)
# Evita "network interna not manually attachable" do docker run
MINIO_CONTAINER=$(docker ps --format "{{.Names}}" | grep "minio\." | head -1)
if [[ -z "$MINIO_CONTAINER" ]]; then
    MINIO_CONTAINER=$(docker ps --format "{{.Names}}" | grep "minio" | head -1)
fi

echo -e "XXX\n56\nAGUARDANDO MINIO FICAR PRONTO... \nXXX"
for i in $(seq 1 30); do
    docker exec $MINIO_CONTAINER mc alias set minio http://localhost:9000 ${MINIO_USER} ${MINIO_PASSWORD} --api S3v4 >/dev/null 2>&1 && break
    sleep 5
done

echo -e "XXX\n57\nCRIANDO BUCKET NO MINIO... \nXXX"
docker exec $MINIO_CONTAINER mc mb minio/$bucket_name >/dev/null 2>&1 || true
docker exec $MINIO_CONTAINER mc anonymous set public minio/$bucket_name >/dev/null 2>&1 || true

plane_s3_access_key="$nome_app"
plane_s3_secret_key=$(openssl rand -hex 16)
echo -e "XXX\n58\nCRIANDO SERVICE ACCOUNT... \nXXX"
credentials=$(docker exec $MINIO_CONTAINER mc admin user svcacct add minio ${MINIO_USER} \
    --access-key "$plane_s3_access_key" \
    --secret-key "$plane_s3_secret_key" \
    --json 2>&1)

if echo "$credentials" | jq -e '.accessKey' >/dev/null 2>&1; then
    access_key_final=$(echo "$credentials" | jq -r '.accessKey')
    secret_key_final=$(echo "$credentials" | jq -r '.secretKey')
else
    access_key_final="$plane_s3_access_key"
    secret_key_final="$plane_s3_secret_key"
fi

echo -e "XXX\n58\nBUCKET: $bucket_name | ACCESS KEY CRIADA \nXXX"
sleep 2

#######################################################
# CRIAR NGINX CONFIG PARA O PROXY
#######################################################
echo -e "XXX\n60\nCRIANDO CONFIG DO PROXY... \nXXX"

cat > /root/${nome_app}_proxy.conf << 'NGINXCONF'
server {
    listen 80;
    client_max_body_size 100M;

    location /api/ {
        proxy_pass http://NGINX_APP_API:8000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    location /auth/ {
        proxy_pass http://NGINX_APP_API:8000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    location /god-mode/ {
        proxy_pass http://NGINX_APP_ADMIN:3000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    location /spaces/ {
        proxy_pass http://NGINX_APP_SPACE:3000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    location / {
        proxy_pass http://NGINX_APP_WEB:3000/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
NGINXCONF

sed -i "s/NGINX_APP_API/${nome_app}_api/g" /root/${nome_app}_proxy.conf
sed -i "s/NGINX_APP_ADMIN/${nome_app}_admin/g" /root/${nome_app}_proxy.conf
sed -i "s/NGINX_APP_SPACE/${nome_app}_space/g" /root/${nome_app}_proxy.conf
sed -i "s/NGINX_APP_WEB/${nome_app}_web/g" /root/${nome_app}_proxy.conf

#######################################################
# CRIAR YAML DO REDIS DEDICADO
#######################################################
echo -e "XXX\n62\nCRIANDO STACK REDIS DEDICADO... \nXXX"

cd
cd

cat > ${nome_app}-redis.yaml << EOL
version: "3.7"

services:
  ${nome_app}_redis:
    image: redis:7-alpine
    command: redis-server --appendonly yes --port 6379
    hostname: ${nome_app}_redis
    networks:
      - interna
    volumes:
      - ${nome_app}_redis_data:/data
    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
          - node.role == manager
      resources:
        limits:
          memory: 512M

volumes:
  ${nome_app}_redis_data:
    external: true
    name: ${nome_app}_redis_data

networks:
  interna:
    external: true
    name: interna
EOL

if [[ "$criar_portainer" == "0" ]]; then
    echo -e "XXX\n64\nCRIANDO STACK REDIS NO PORTAINER... \nXXX"
    dados_file="$HOME/dados_portainer/dados_portainer"
    if [[ -f "$dados_file" ]]; then
        PORTAINER_URL=$(grep "Dominio do portainer:" "$dados_file" | cut -d':' -f2 | xargs)
        ADMIN_USERNAME=$(grep "Usuario:" "$dados_file" | cut -d':' -f2 | xargs)
        ADMIN_PASSWORD=$(grep "Senha:" "$dados_file" | cut -d':' -f2 | xargs)
        STACK_NAME="${nome_app}-redis"
        STACK_FILE_PATH="/root/${nome_app}-redis.yaml"

        get_auth_token() {
            echo -e "XXX\n65\nAUTENTICANDO NO PORTAINER... \nXXX"
            RESPONSE=$(curl -sk -X POST "https://$PORTAINER_URL/api/auth" -H "Content-Type: application/json" -d "{\"username\": \"$ADMIN_USERNAME\", \"password\": \"$ADMIN_PASSWORD\"}")
            TOKEN=$(echo "$RESPONSE" | jq -r '.jwt')
            if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]; then
                echo -e "XXX\n66\nFALHA NA AUTENTICAÇÃO, USANDO DOCKER... \nXXX"
                docker stack deploy --prune --resolve-image always -c ${nome_app}-redis.yaml ${nome_app}-redis >/dev/null 2>&1
                exit 1
            fi
            echo -e "XXX\n66\nAUTENTICAÇÃO OK \nXXX"
        }
        get_endpoint_id() {
            echo -e "XXX\n67\nOBTENDO ENDPOINT ID... \nXXX"
            RESPONSE=$(curl -sk -X GET "https://$PORTAINER_URL/api/endpoints" -H "Authorization: Bearer $TOKEN")
            ENDPOINT_ID=$(echo "$RESPONSE" | jq -r '.[0].Id')
            if [ -z "$ENDPOINT_ID" ] || [ "$ENDPOINT_ID" = "null" ]; then
                echo -e "XXX\n68\nERRO: ENDPOINT ID NÃO ENCONTRADO \nXXX"
                docker stack deploy --prune --resolve-image always -c ${nome_app}-redis.yaml ${nome_app}-redis >/dev/null 2>&1
                exit 1
            fi
            echo -e "XXX\n68\nENDPOINT ID OBTIDO \nXXX"
        }
        get_swarm_id() {
            echo -e "XXX\n69\nOBTENDO SWARM ID... \nXXX"
            RESPONSE=$(curl -sk -X GET "https://$PORTAINER_URL/api/endpoints/$ENDPOINT_ID/docker/swarm" -H "Authorization: Bearer $TOKEN")
            SWARM_ID=$(echo "$RESPONSE" | jq -r '.ID')
            if [ -z "$SWARM_ID" ] || [ "$SWARM_ID" = "null" ]; then
                echo -e "XXX\n70\nERRO: SWARM ID NÃO ENCONTRADO \nXXX"
                docker stack deploy --prune --resolve-image always -c ${nome_app}-redis.yaml ${nome_app}-redis >/dev/null 2>&1
                exit 1
            fi
            echo -e "XXX\n70\nSWARM ID OBTIDO \nXXX"
        }
        create_stack() {
            echo -e "XXX\n71\nCRIANDO STACK $STACK_NAME NO PORTAINER... \nXXX"
            if [ ! -f "$STACK_FILE_PATH" ]; then
                echo -e "XXX\n72\nARQUIVO YAML NÃO ENCONTRADO \nXXX"
                docker stack deploy --prune --resolve-image always -c ${nome_app}-redis.yaml ${nome_app}-redis >/dev/null 2>&1
                exit 1
            fi
            response_output=$(mktemp)
            erro_output=$(mktemp)
            http_code=$(curl -s -o "$response_output" -w "%{http_code}" -k -X POST \
                -H "Authorization: Bearer $TOKEN" -F "Name=$STACK_NAME" -F "file=@$STACK_FILE_PATH" \
                -F "SwarmID=$SWARM_ID" -F "endpointId=$ENDPOINT_ID" \
                "https://$PORTAINER_URL/api/stacks/create/swarm/file" 2> "$erro_output")
            rm -f "$response_output" "$erro_output"
            if [ "$http_code" -ne 200 ]; then
                echo -e "XXX\n73\nERRO AO CRIAR STACK, USANDO DOCKER... \nXXX"
                docker stack deploy --prune --resolve-image always -c ${nome_app}-redis.yaml ${nome_app}-redis >/dev/null 2>&1
                exit 1
            fi
            echo -e "XXX\n73\nSTACK $STACK_NAME CRIADA COM SUCESSO \nXXX"
        }
        get_auth_token || exit 1
        get_endpoint_id || exit 1
        get_swarm_id || exit 1
        create_stack || exit 1
    else
        docker stack deploy --prune --resolve-image always -c ${nome_app}-redis.yaml ${nome_app}-redis >/dev/null 2>&1
    fi
else
    docker stack deploy --prune --resolve-image always -c ${nome_app}-redis.yaml ${nome_app}-redis >/dev/null 2>&1
fi

echo -e "XXX\n74\nAGUARDANDO REDIS INICIAR... \nXXX"
sleep 10

#######################################################
# CRIAR YAML DO RABBITMQ DEDICADO
#######################################################
echo -e "XXX\n75\nCRIANDO STACK RABBITMQ DEDICADO... \nXXX"

cd
cd

cat > ${nome_app}-mq.yaml << EOL
version: "3.7"

services:
  ${nome_app}_mq:
    image: rabbitmq:3.13.6-management-alpine
    hostname: ${nome_app}_mq
    networks:
      - interna
    volumes:
      - ${nome_app}_mq_data:/var/lib/rabbitmq
    environment:
      - RABBITMQ_DEFAULT_USER=$rabbit_user
      - RABBITMQ_DEFAULT_PASS=$rabbit_pass
      - RABBITMQ_DEFAULT_VHOST=$rabbit_vhost
    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
          - node.role == manager
      resources:
        limits:
          memory: 256M

volumes:
  ${nome_app}_mq_data:
    external: true
    name: ${nome_app}_mq_data

networks:
  interna:
    external: true
    name: interna
EOL

if [[ "$criar_portainer" == "0" ]]; then
    echo -e "XXX\n76\nCRIANDO STACK RABBITMQ NO PORTAINER... \nXXX"
    dados_file="$HOME/dados_portainer/dados_portainer"
    if [[ -f "$dados_file" ]]; then
        PORTAINER_URL=$(grep "Dominio do portainer:" "$dados_file" | cut -d':' -f2 | xargs)
        ADMIN_USERNAME=$(grep "Usuario:" "$dados_file" | cut -d':' -f2 | xargs)
        ADMIN_PASSWORD=$(grep "Senha:" "$dados_file" | cut -d':' -f2 | xargs)
        STACK_NAME="${nome_app}-mq"
        STACK_FILE_PATH="/root/${nome_app}-mq.yaml"

        get_auth_token() {
            echo -e "XXX\n77\nAUTENTICANDO NO PORTAINER... \nXXX"
            RESPONSE=$(curl -sk -X POST "https://$PORTAINER_URL/api/auth" -H "Content-Type: application/json" -d "{\"username\": \"$ADMIN_USERNAME\", \"password\": \"$ADMIN_PASSWORD\"}")
            TOKEN=$(echo "$RESPONSE" | jq -r '.jwt')
            if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]; then
                echo -e "XXX\n78\nFALHA NA AUTENTICAÇÃO, USANDO DOCKER... \nXXX"
                docker stack deploy --prune --resolve-image always -c ${nome_app}-mq.yaml ${nome_app}-mq >/dev/null 2>&1
                exit 1
            fi
            echo -e "XXX\n78\nAUTENTICAÇÃO OK \nXXX"
        }
        get_endpoint_id() {
            echo -e "XXX\n79\nOBTENDO ENDPOINT ID... \nXXX"
            RESPONSE=$(curl -sk -X GET "https://$PORTAINER_URL/api/endpoints" -H "Authorization: Bearer $TOKEN")
            ENDPOINT_ID=$(echo "$RESPONSE" | jq -r '.[0].Id')
            if [ -z "$ENDPOINT_ID" ] || [ "$ENDPOINT_ID" = "null" ]; then
                echo -e "XXX\n80\nERRO: ENDPOINT ID NÃO ENCONTRADO \nXXX"
                docker stack deploy --prune --resolve-image always -c ${nome_app}-mq.yaml ${nome_app}-mq >/dev/null 2>&1
                exit 1
            fi
            echo -e "XXX\n80\nENDPOINT ID OBTIDO \nXXX"
        }
        get_swarm_id() {
            echo -e "XXX\n81\nOBTENDO SWARM ID... \nXXX"
            RESPONSE=$(curl -sk -X GET "https://$PORTAINER_URL/api/endpoints/$ENDPOINT_ID/docker/swarm" -H "Authorization: Bearer $TOKEN")
            SWARM_ID=$(echo "$RESPONSE" | jq -r '.ID')
            if [ -z "$SWARM_ID" ] || [ "$SWARM_ID" = "null" ]; then
                echo -e "XXX\n82\nERRO: SWARM ID NÃO ENCONTRADO \nXXX"
                docker stack deploy --prune --resolve-image always -c ${nome_app}-mq.yaml ${nome_app}-mq >/dev/null 2>&1
                exit 1
            fi
            echo -e "XXX\n82\nSWARM ID OBTIDO \nXXX"
        }
        create_stack() {
            echo -e "XXX\n83\nCRIANDO STACK $STACK_NAME NO PORTAINER... \nXXX"
            if [ ! -f "$STACK_FILE_PATH" ]; then
                echo -e "XXX\n84\nARQUIVO YAML NÃO ENCONTRADO \nXXX"
                docker stack deploy --prune --resolve-image always -c ${nome_app}-mq.yaml ${nome_app}-mq >/dev/null 2>&1
                exit 1
            fi
            response_output=$(mktemp)
            erro_output=$(mktemp)
            http_code=$(curl -s -o "$response_output" -w "%{http_code}" -k -X POST \
                -H "Authorization: Bearer $TOKEN" -F "Name=$STACK_NAME" -F "file=@$STACK_FILE_PATH" \
                -F "SwarmID=$SWARM_ID" -F "endpointId=$ENDPOINT_ID" \
                "https://$PORTAINER_URL/api/stacks/create/swarm/file" 2> "$erro_output")
            rm -f "$response_output" "$erro_output"
            if [ "$http_code" -ne 200 ]; then
                echo -e "XXX\n85\nERRO AO CRIAR STACK, USANDO DOCKER... \nXXX"
                docker stack deploy --prune --resolve-image always -c ${nome_app}-mq.yaml ${nome_app}-mq >/dev/null 2>&1
                exit 1
            fi
            echo -e "XXX\n85\nSTACK $STACK_NAME CRIADA COM SUCESSO \nXXX"
        }
        get_auth_token || exit 1
        get_endpoint_id || exit 1
        get_swarm_id || exit 1
        create_stack || exit 1
    else
        docker stack deploy --prune --resolve-image always -c ${nome_app}-mq.yaml ${nome_app}-mq >/dev/null 2>&1
    fi
else
    docker stack deploy --prune --resolve-image always -c ${nome_app}-mq.yaml ${nome_app}-mq >/dev/null 2>&1
fi

echo -e "XXX\n86\nAGUARDANDO RABBITMQ INICIAR... \nXXX"
sleep 10

#######################################################
# CRIAR YAML PRINCIPAL DO PLANE
#######################################################
echo -e "XXX\n87\nCRIANDO STACK PRINCIPAL DO PLANE... \nXXX"

cd
cd

S3_ENDPOINT="https://${MINIO_PUBLIC_URL}"
CORS_ALLOWED="https://${url_plane}"

cat > $nome_app.yaml << EOL
version: "3.7"

services:

  ${nome_app}_api:
    image: makeplane/plane-backend:stable
    hostname: ${nome_app}_api
    networks:
      - interna
    environment:
      - DATABASE_URL=postgresql://postgres:${postgres_password}@postgres:5432/${nome_app}
      - REDIS_URL=redis://${nome_app}_redis:6379
      - RABBITMQ_USER=$rabbit_user
      - RABBITMQ_PASSWORD=$rabbit_pass
      - RABBITMQ_VHOST=$rabbit_vhost
      - RABBITMQ_HOST=${nome_app}_mq
      - SECRET_KEY=$secret_key
      - AWS_ACCESS_KEY_ID=$access_key_final
      - AWS_SECRET_ACCESS_KEY=$secret_key_final
      - AWS_S3_BUCKET_NAME=$bucket_name
      - AWS_S3_ENDPOINT_URL=$S3_ENDPOINT
      - AWS_REGION=us-east-1
      - WEB_URL=https://${url_plane}
      - SPACE_URL=https://${url_plane}/spaces
      - ADMIN_URL=https://${url_plane}/god-mode
      - CORS_ALLOWED_ORIGINS=$CORS_ALLOWED
      - GUNICORN_WORKERS=2
      - FILE_SIZE_LIMIT=5242880
    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
          - node.role == manager
      resources:
        limits:
          memory: 1024M

  ${nome_app}_worker:
    image: makeplane/plane-backend:stable
    hostname: ${nome_app}_worker
    networks:
      - interna
    environment:
      - DATABASE_URL=postgresql://postgres:${postgres_password}@postgres:5432/${nome_app}
      - REDIS_URL=redis://${nome_app}_redis:6379
      - RABBITMQ_USER=$rabbit_user
      - RABBITMQ_PASSWORD=$rabbit_pass
      - RABBITMQ_VHOST=$rabbit_vhost
      - RABBITMQ_HOST=${nome_app}_mq
      - SECRET_KEY=$secret_key
      - AWS_ACCESS_KEY_ID=$access_key_final
      - AWS_SECRET_ACCESS_KEY=$secret_key_final
      - AWS_S3_BUCKET_NAME=$bucket_name
      - AWS_S3_ENDPOINT_URL=$S3_ENDPOINT
      - AWS_REGION=us-east-1
      - WEB_URL=https://${url_plane}
      - CORS_ALLOWED_ORIGINS=$CORS_ALLOWED
      - GUNICORN_WORKERS=2
      - FILE_SIZE_LIMIT=5242880
    command: ./bin/docker-entrypoint-worker.sh
    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
          - node.role == manager
      resources:
        limits:
          memory: 512M

  ${nome_app}_beat:
    image: makeplane/plane-backend:stable
    hostname: ${nome_app}_beat
    networks:
      - interna
    environment:
      - DATABASE_URL=postgresql://postgres:${postgres_password}@postgres:5432/${nome_app}
      - REDIS_URL=redis://${nome_app}_redis:6379
      - RABBITMQ_USER=$rabbit_user
      - RABBITMQ_PASSWORD=$rabbit_pass
      - RABBITMQ_VHOST=$rabbit_vhost
      - RABBITMQ_HOST=${nome_app}_mq
      - SECRET_KEY=$secret_key
      - AWS_ACCESS_KEY_ID=$access_key_final
      - AWS_SECRET_ACCESS_KEY=$secret_key_final
      - AWS_S3_BUCKET_NAME=$bucket_name
      - AWS_S3_ENDPOINT_URL=$S3_ENDPOINT
      - AWS_REGION=us-east-1
      - WEB_URL=https://${url_plane}
      - CORS_ALLOWED_ORIGINS=$CORS_ALLOWED
      - FILE_SIZE_LIMIT=5242880
    command: ./bin/docker-entrypoint-beat.sh
    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
          - node.role == manager
      resources:
        limits:
          memory: 256M

  ${nome_app}_web:
    image: makeplane/plane-frontend:stable
    hostname: ${nome_app}_web
    networks:
      - interna
    environment:
      - NEXT_PUBLIC_API_BASE_URL=https://${url_plane}/api
      - NEXT_PUBLIC_DEPLOY_URL=https://${url_plane}
    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
          - node.role == manager
      resources:
        limits:
          memory: 512M

  ${nome_app}_admin:
    image: makeplane/plane-admin:stable
    hostname: ${nome_app}_admin
    networks:
      - interna
    environment:
      - NEXT_PUBLIC_API_BASE_URL=https://${url_plane}/api
      - NEXT_PUBLIC_DEPLOY_URL=https://${url_plane}
    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
          - node.role == manager
      resources:
        limits:
          memory: 256M

  ${nome_app}_space:
    image: makeplane/plane-space:stable
    hostname: ${nome_app}_space
    networks:
      - interna
    environment:
      - NEXT_PUBLIC_API_BASE_URL=https://${url_plane}/api
      - NEXT_PUBLIC_DEPLOY_URL=https://${url_plane}
    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
          - node.role == manager
      resources:
        limits:
          memory: 256M

  ${nome_app}:
    image: nginx:alpine
    hostname: ${nome_app}
    networks:
      - externa
      - interna
    volumes:
      - /root/${nome_app}_proxy.conf:/etc/nginx/conf.d/default.conf
    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
          - node.role == manager
      resources:
        limits:
          memory: 128M
EOL

if [ "$INSTALL_TYPE" = "TRADICIONAL" ]; then
cat >> $nome_app.yaml << EOL

      labels:
        - traefik.enable=true
        - traefik.docker.network=externa
        - traefik.http.routers.${nome_app}.rule=Host(\`${url_plane}\`)
        - traefik.http.routers.${nome_app}.entrypoints=websecure
        - traefik.http.routers.${nome_app}.priority=1
        - traefik.http.routers.${nome_app}.tls.certresolver=letsencryptresolver
        - traefik.http.services.${nome_app}.loadbalancer.server.port=80
EOL
fi

cat >> $nome_app.yaml << EOL

volumes:
  ${nome_app}_uploads:
    external: true
    name: ${nome_app}_uploads

networks:
  externa:
    external: true
  interna:
    external: true
EOL

#######################################################
# RODAR MIGRATIONS
#######################################################
echo -e "XXX\n88\nRODANDO MIGRAÇÕES DO BANCO DE DADOS... \nXXX"

docker service create \
    --name ${nome_app}_migrate \
    --network interna \
    --restart-condition none \
    -e DATABASE_URL="postgresql://postgres:${postgres_password}@postgres:5432/${nome_app}" \
    -e REDIS_URL="redis://${nome_app}_redis:6379" \
    -e SECRET_KEY="$secret_key" \
    -e AWS_ACCESS_KEY_ID="$access_key_final" \
    -e AWS_SECRET_ACCESS_KEY="$secret_key_final" \
    -e AWS_S3_BUCKET_NAME="$bucket_name" \
    -e AWS_S3_ENDPOINT_URL="$S3_ENDPOINT" \
    -e AWS_REGION="us-east-1" \
    -e WEB_URL="https://${url_plane}" \
    -e CORS_ALLOWED_ORIGINS="$CORS_ALLOWED" \
    -e FILE_SIZE_LIMIT="5242880" \
    -e GUNICORN_WORKERS="2" \
    -e DJANGO_SETTINGS_MODULE="plane.settings.production" \
    makeplane/plane-backend:stable \
    python manage.py migrate >/dev/null 2>&1 || true

sleep 5
for i in $(seq 1 30); do
    state=$(docker service ps ${nome_app}_migrate --format '{{.CurrentState}}' 2>/dev/null | head -1)
    if echo "$state" | grep -q "Complete"; then
        echo -e "XXX\n89\nMIGRAÇÕES CONCLUÍDAS! \nXXX"
        break
    fi
    if echo "$state" | grep -q "Failed"; then
        echo -e "XXX\n89\nERRO NAS MIGRAÇÕES! \nXXX"
        break
    fi
    sleep 5
done

docker service rm ${nome_app}_migrate >/dev/null 2>&1 || true

echo -e "XXX\n90\nCRIANDO STACK PRINCIPAL DO PLANE... \nXXX"

if [[ "$criar_portainer" == "0" ]]; then
    echo -e "XXX\n91\nCRIANDO STACK PRINCIPAL NO PORTAINER... \nXXX"
    dados_file="$HOME/dados_portainer/dados_portainer"
    if [[ -f "$dados_file" ]]; then
        PORTAINER_URL=$(grep "Dominio do portainer:" "$dados_file" | cut -d':' -f2 | xargs)
        ADMIN_USERNAME=$(grep "Usuario:" "$dados_file" | cut -d':' -f2 | xargs)
        ADMIN_PASSWORD=$(grep "Senha:" "$dados_file" | cut -d':' -f2 | xargs)
        STACK_NAME=$nome_app
        STACK_FILE_PATH="/root/$nome_app.yaml"

        get_auth_token() {
            echo -e "XXX\n92\nAUTENTICANDO NO PORTAINER... \nXXX"
            RESPONSE=$(curl -sk -X POST "https://$PORTAINER_URL/api/auth" -H "Content-Type: application/json" \
                -d "{\"username\": \"$ADMIN_USERNAME\", \"password\": \"$ADMIN_PASSWORD\"}")
            TOKEN=$(echo "$RESPONSE" | jq -r '.jwt')
            if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]; then
                echo -e "XXX\n93\nFALHA NA AUTENTICAÇÃO, USANDO DOCKER... \nXXX"
                docker stack deploy --prune --resolve-image always -c $nome_app.yaml $nome_app >/dev/null 2>&1
                exit 1
            fi
            echo -e "XXX\n93\nAUTENTICAÇÃO OK \nXXX"
        }
        get_endpoint_id() {
            echo -e "XXX\n94\nOBTENDO ENDPOINT ID... \nXXX"
            RESPONSE=$(curl -sk -X GET "https://$PORTAINER_URL/api/endpoints" -H "Authorization: Bearer $TOKEN")
            ENDPOINT_ID=$(echo "$RESPONSE" | jq -r '.[0].Id')
            if [ -z "$ENDPOINT_ID" ] || [ "$ENDPOINT_ID" = "null" ]; then
                echo -e "XXX\n95\nERRO: ENDPOINT ID NÃO ENCONTRADO \nXXX"
                docker stack deploy --prune --resolve-image always -c $nome_app.yaml $nome_app >/dev/null 2>&1
                exit 1
            fi
            echo -e "XXX\n95\nENDPOINT ID OBTIDO \nXXX"
        }
        get_swarm_id() {
            echo -e "XXX\n96\nOBTENDO SWARM ID... \nXXX"
            RESPONSE=$(curl -sk -X GET "https://$PORTAINER_URL/api/endpoints/$ENDPOINT_ID/docker/swarm" -H "Authorization: Bearer $TOKEN")
            SWARM_ID=$(echo "$RESPONSE" | jq -r '.ID')
            if [ -z "$SWARM_ID" ] || [ "$SWARM_ID" = "null" ]; then
                echo -e "XXX\n97\nERRO: SWARM ID NÃO ENCONTRADO \nXXX"
                docker stack deploy --prune --resolve-image always -c $nome_app.yaml $nome_app >/dev/null 2>&1
                exit 1
            fi
            echo -e "XXX\n97\nSWARM ID OBTIDO \nXXX"
        }
        create_stack() {
            echo -e "XXX\n98\nCRIANDO STACK $STACK_NAME NO PORTAINER... \nXXX"
            if [ ! -f "$STACK_FILE_PATH" ]; then
                echo -e "XXX\n99\nARQUIVO YAML NÃO ENCONTRADO \nXXX"
                docker stack deploy --prune --resolve-image always -c $nome_app.yaml $nome_app >/dev/null 2>&1
                exit 1
            fi
            response_output=$(mktemp)
            erro_output=$(mktemp)
            http_code=$(curl -s -o "$response_output" -w "%{http_code}" -k -X POST \
                -H "Authorization: Bearer $TOKEN" -F "Name=$STACK_NAME" -F "file=@$STACK_FILE_PATH" \
                -F "SwarmID=$SWARM_ID" -F "endpointId=$ENDPOINT_ID" \
                "https://$PORTAINER_URL/api/stacks/create/swarm/file" 2> "$erro_output")
            rm -f "$response_output" "$erro_output"
            if [ "$http_code" -ne 200 ]; then
                echo -e "XXX\n100\nERRO AO CRIAR STACK, USANDO DOCKER... \nXXX"
                docker stack deploy --prune --resolve-image always -c $nome_app.yaml $nome_app >/dev/null 2>&1
                exit 1
            fi
            echo -e "XXX\n100\nSTACK $STACK_NAME CRIADA COM SUCESSO \nXXX"
        }
        get_auth_token || exit 1
        get_endpoint_id || exit 1
        get_swarm_id || exit 1
        create_stack || exit 1
    else
        docker stack deploy --prune --resolve-image always -c $nome_app.yaml $nome_app >/dev/null 2>&1
    fi
else
    docker stack deploy --prune --resolve-image always -c $nome_app.yaml $nome_app >/dev/null 2>&1
fi

echo -e "XXX\n100\nINSTALAÇÃO CONCLUÍDA! \nXXX"
sleep 2

} | whiptail --title "INSTALANDO PLANE" --gauge "AGUARDE..." 8 70 0

clear

whiptail --title "PLANE INSTALADO COM SUCESSO!" \
--msgbox "✅ Plane instalado com sucesso!\n\nStacks criadas:\n- ${nome_app} (App principal)\n- ${nome_app}-redis (Redis dedicado)\n- ${nome_app}-mq (RabbitMQ dedicado)\n\n📌 ACESSO:\nhttps://$url_plane\n\n📧 Email admin: $email_plane\n\n🗄️ PostgreSQL: Compartilhado\n💾 Redis: Dedicado (stack: ${nome_app}-redis)\n📎 MinIO: Compartilhado (bucket: $bucket_name)\n\n⚠️ Crie sua conta no primeiro acesso.\n\nPressione Enter para finalizar." \
--fb 18 70

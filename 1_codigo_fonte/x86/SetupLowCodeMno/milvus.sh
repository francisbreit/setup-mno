#!/usr/bin/bash
########################################################
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
    whiptail --title "INSTALAÇÃO DO MILVUS + ATTU" --msgbox "$msg" --fb 10 70
}

while true; do
CHOICE=$(
whiptail --title "INSTALAÇÃO DO MILVUS + ATTU" --menu "Aperte ENTER para iniciar a instalação ou selecione SAIR (Utilize setas e Enter)\n\nTIPO DE INSTALAÇÃO DETECTADA: $INSTALL_TYPE\n\nINSTRUÇÕES:\nAntes de prosseguir, verifique os registros DNS conforme seu tipo de instalação:" 20 70 2 \
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

# SOLICITAR URL DO MILVUS (ATTU WEB UI)
while true; do
    urlmilvus=$(whiptail --title "URL do Milvus" --inputbox "Digite o Link de acesso (ex: milvus.seudominio.com):" --fb 12 60 3>&1 1>&2 2>&3)
    saida=$?
    if [[ $saida -eq '0' ]]; then
        if [[ -z $urlmilvus ]]; then 
            msg "Digite o link para poder continuar"
            continue
        else 
            break
        fi
    else
        echo $urlmilvus
        echo "saindo..."
        exit 0
    fi
done

########################################################
# VERIFICAR SE MINIO JÁ EXISTE
########################################################
minio_container=$(docker ps -qf "name=minio")

if [[ ("$minio_container" == "") ]]; then
    # MINIO NÃO EXISTE - SOLICITAR DADOS
    msg "Minio não encontrado no servidor. Vamos instalar um Minio compartilhado junto com o Milvus.\n\nVocê precisará fornecer URLs e credenciais para o Minio."

    while true ; do
        painel=$(whiptail --title "Dominio do Painel do Minio" --inputbox "Digite o Dominio do Painel do Minio (ex: admins3.seudominio.com):" --fb 12 60 3>&1 1>&2 2>&3) 
        saida=$?
        if [[ $saida -eq '0' ]]; then
            if [[ -z $painel ]]; then 
                msg "Digite o dominio do painel do Minio para poder continuar" 
                continue 
            else 
                break
            fi
        else
            echo "$painel"; echo "Saindo..."; exit 0
        fi
    done

    while true ; do
        publico=$(whiptail --title "Dominio Pública do Minio" --inputbox "Digite o dominio Público (ex: s3.seudominio.com):" --fb 12 60 3>&1 1>&2 2>&3) 
        saida=$?
        if [[ $saida -eq '0' ]]; then
            if [[ -z $publico ]]; then 
                msg "Digite o dominio público do Minio para poder continuar" 
                continue 
            else 
                break
            fi
        else
            echo "$publico"; echo "Saindo..."; exit 0
        fi
    done

    while true ; do
        usuariominio=$(whiptail --title "Nome do Usuário do Minio" --inputbox "Digite o Usuário do Minio (ex: SeuNome):" --fb 12 60 3>&1 1>&2 2>&3) 
        saida=$?
        if [[ $saida -eq '0' ]]; then
            if [[ (-z $usuariominio) || ("$usuariominio" =~ [^a-zA-Z0-9]) || (${#usuariominio} -gt 16) ]]; then 
                msg "Digite o nome do usuário do Minio, sem caracteres especiais e até 16 dígitos para poder continuar" 
                continue 
            else 
                break
            fi
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
            else 
                break
            fi
        else
            echo "$senhaminio"; echo "Saindo..."; exit 0
        fi
    done
fi

# SOLICITAR SE CRIA STACK NO PORTAINER
while true; do
    criar_portainer=$(whiptail --title "Criar Stack no Portainer? - 0 ou 1" --inputbox "Digite 0 para poder editar stack no portainer ou 1 para não poder editar" --fb 12 60 3>&1 1>&2 2>&3)
    saida=$?
    if [[ $saida -eq '0' ]]; then
        if [[ "$criar_portainer" != "0" && "$criar_portainer" != "1" ]]; then 
            msg "Digite apenas o número 0 ou o número 1, para poder continuar."
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

########################################################
# VERIFICAÇÃO DE DADOS
########################################################

nome_principal="milvus"
sufixo_app=$(date | md5sum | head -c7)
nome_app=$nome_principal$sufixo_app

# Se minio não existe, gerar nome para ele também
if [[ ("$minio_container" == "") ]]; then
    nome_principal2="minio"
    nome_app2=$nome_principal2$sufixo_app
fi

{
  tput reset 2>/dev/null
  exec 0</dev/tty 1>/dev/tty 2>&1
  sleep 0.01
  clear
} || true

if [[ ("$minio_container" == "") ]]; then
    whiptail --title "Dados Fornecidos" \
     --msgbox "TIPO DE INSTALAÇÃO: $INSTALL_TYPE\n\nDados Preenchidos:\n\n1) Url: $urlmilvus\n2) Link do Painel Minio: $painel\n3) Link Público Minio: $publico\n4) Usuário do Minio: $usuariominio\n5) Senha do Minio: $senhaminio\n6) Criar Stack no Portainer: $([ "$criar_portainer" == "0" ] && echo "0 (Editável)" || echo "1 (Não editável)")\n\nConfira e Tecle Enter para continuar." \
     --fb 22 80
else
    whiptail --title "Dados Fornecidos" \
     --msgbox "TIPO DE INSTALAÇÃO: $INSTALL_TYPE\n\nDados Preenchidos:\n\n1) Url: $urlmilvus\n2) Minio já existente no servidor - será reutilizado\n3) Criar Stack no Portainer: $([ "$criar_portainer" == "0" ] && echo "0 (Editável)" || echo "1 (Não editável)")\n\nConfira e Tecle Enter para continuar." \
     --fb 22 80
fi

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

########################################################
# CRIAÇÃO DE DNS E ROTAS CLOUDFLARE TUNNEL
########################################################
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
    DOMINIO_PRINCIPAL=$(echo "$urlmilvus" | cut -d'.' -f2-)
    
    EXISTING_RECORDS=$(curl -s -X GET \
        "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records?name=${urlmilvus}" \
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
        --data '{"type":"CNAME","name":"'${urlmilvus}'","content":"'${nome_servidor}'.'${DOMINIO_PRINCIPAL}'","ttl":1,"proxied":false}')

    if echo "$CNAME_RESPONSE" | grep -q '"success":true'; then
        echo -e "XXX\n30\nREGISTRO CNAME CRIADO COM SUCESSO! \nXXX"
    else
        echo -e "XXX\n30\nAVISO: ERRO AO CRIAR REGISTRO CNAME \nXXX"
    fi

elif [ "$INSTALL_TYPE" = "CLOUDFLARE_TUNNEL" ]; then
    echo -e "XXX\n10\nCONFIGURANDO CLOUDFLARE TUNNEL (DNS + ROTAS)... \nXXX"
    
    EXISTING_RECORDS=$(curl -s -X GET \
        "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records?name=${urlmilvus}" \
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
        --data "{\"type\":\"CNAME\",\"name\":\"${urlmilvus}\",\"content\":\"${TUNNEL_ID}.cfargotunnel.com\",\"ttl\":1,\"proxied\":true}")

    echo -e "XXX\n15\nATUALIZANDO CONFIGURAÇÃO DO TUNNEL (ATTU)... \nXXX"
    NEW_SERVICE="http://${nome_app}_attu:3000"
    
    TIMESTAMP=$(date -u +%Y%m%dT%H%M%SZ)
    TMPDIR=$(mktemp -d)
    BACKUP_RAW="$TMPDIR/backup_raw.$TIMESTAMP.json"
    TO_PUT="$TMPDIR/to_put.$TIMESTAMP.json"

    curl -sS -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
      "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/cfd_tunnel/$TUNNEL_ID/configurations" \
      | jq '.' > "$BACKUP_RAW"

    jq --arg host "$urlmilvus" --arg service "$NEW_SERVICE" '
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
fi

if [ "$INSTALL_TYPE" = "TRADICIONAL" ] && [ "$criar_dns" = "1" ]; then
    ip_servidor=$(curl -s --max-time 10 ipinfo.io/ip)
    echo -e "XXX\n3\nVERIFICANDO SUBDOMÍNIO: $urlmilvus \nXXX"
    sleep 3

    tentativas=5
    tentativa_atual=1
    sucesso=0

    while [ $tentativa_atual -le $tentativas ]; do
        echo -e "XXX\n$(( (tentativa_atual * 12) / tentativas + 3 ))\nTentativa $tentativa_atual de $tentativas...\nXXX"
        dns_ip=$(timeout 10 nslookup -type=A "$urlmilvus" | grep -E "Address: [0-9]+\\." | awk '{print $2}' | head -n1)
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
# DNS DO MINIO (via tradicional)
#######################################################
if [[ ("$minio_container" == "") ]] && [ "$INSTALL_TYPE" = "TRADICIONAL" ]; then
    if [ "$criar_dns" = "0" ]; then
        echo -e "XXX\n30\nCONFIGURANDO DNS DO MINIO (TRADICIONAL)... \nXXX"
        DOMINIO_PRINCIPAL=$(echo "$urlmilvus" | cut -d'.' -f2-)
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
    elif [ "$criar_dns" = "1" ]; then
        echo -e "XXX\n30\nVERIFICANDO DNS DO MINIO... \nXXX"
        ip_servidor=$(curl -s --max-time 10 ipinfo.io/ip)
        for minio_url in "$painel" "$publico"; do
            tentativas=5
            tentativa_atual=1
            sucesso=0
            while [ $tentativa_atual -le $tentativas ]; do
                dns_ip=$(timeout 10 nslookup -type=A "$minio_url" | grep -E "Address: [0-9]+\." | awk '{print $2}' | head -n1)
                if [[ -n "$dns_ip" && "$dns_ip" == "$ip_servidor" ]]; then
                    sucesso=1
                    break
                fi
                sleep 1
                ((tentativa_atual++))
            done
        done
    fi
fi

#######################################################
# DNS DO MINIO (via tunnel)
#######################################################
if [[ ("$minio_container" == "") ]] && [ "$INSTALL_TYPE" = "CLOUDFLARE_TUNNEL" ]; then
    echo -e "XXX\n35\nCONFIGURANDO DNS DO MINIO NO TUNNEL... \nXXX"

    DNS_RESPONSE=$(curl -s -X POST \
        "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records" \
        -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
        -H "Content-Type: application/json" \
        --data "{\"type\":\"CNAME\",\"name\":\"${painel}\",\"content\":\"${TUNNEL_ID}.cfargotunnel.com\",\"ttl\":1,\"proxied\":true}")

    DNS_RESPONSE2=$(curl -s -X POST \
        "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records" \
        -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
        -H "Content-Type: application/json" \
        --data "{\"type\":\"CNAME\",\"name\":\"${publico}\",\"content\":\"${TUNNEL_ID}.cfargotunnel.com\",\"ttl\":1,\"proxied\":true}")

    TIMESTAMP=$(date -u +%Y%m%dT%H%M%SZ)
    TMPDIR2=$(mktemp -d)
    BACKUP_RAW2="$TMPDIR2/backup_raw.$TIMESTAMP.json"
    TO_PUT2="$TMPDIR2/to_put.$TIMESTAMP.json"

    curl -sS -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
      "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/cfd_tunnel/$TUNNEL_ID/configurations" \
      | jq '.' > "$BACKUP_RAW2"

    jq --arg host "$painel" --arg service "http://${nome_app2}:9001" '
      (.result.config // {}) as $cfg
      | ($cfg.ingress // []) as $ing
      | ($ing | map(select(.service != "http_status:404"))) as $clean
      | ($clean | map(select(.hostname != $host))) as $filtered
      | ($filtered + [ { hostname: $host, service: $service, originRequest: { noTlsVerify: true, httpHostHeader: $host } } ]) as $merged
      | ($merged + [{ service: "http_status:404" }]) as $final_ing
      | ($cfg + { ingress: $final_ing }) as $newcfg
      | { config: $newcfg }
    ' "$BACKUP_RAW2" > "$TO_PUT2"

    curl -sS -X PUT "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/cfd_tunnel/$TUNNEL_ID/configurations" \
      -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
      -H "Content-Type: application/json" \
      --data-binary @"$TO_PUT2" >/dev/null 2>&1

    curl -sS -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
      "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/cfd_tunnel/$TUNNEL_ID/configurations" \
      | jq '.' > "$BACKUP_RAW2"

    jq --arg host "$publico" --arg service "http://${nome_app2}:9000" '
      (.result.config // {}) as $cfg
      | ($cfg.ingress // []) as $ing
      | ($ing | map(select(.service != "http_status:404"))) as $clean
      | ($clean | map(select(.hostname != $host))) as $filtered
      | ($filtered + [ { hostname: $host, service: $service, originRequest: { noTlsVerify: true, httpHostHeader: $host } } ]) as $merged
      | ($merged + [{ service: "http_status:404" }]) as $final_ing
      | ($cfg + { ingress: $final_ing }) as $newcfg
      | { config: $newcfg }
    ' "$BACKUP_RAW2" > "$TO_PUT2"

    curl -sS -X PUT "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/cfd_tunnel/$TUNNEL_ID/configurations" \
      -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
      -H "Content-Type: application/json" \
      --data-binary @"$TO_PUT2" >/dev/null 2>&1

    rm -rf "$TMPDIR2"
fi

#######################################################
# 1) DEPLOY DO MINIO (SE NOVO)
#######################################################
echo -e "XXX\n40\nCRIANDO VOLUMES EXTERNOS... \nXXX"

docker volume create ${nome_app}_etcd 2>/dev/null || true
docker volume create ${nome_app}_data 2>/dev/null || true

if [[ ("$minio_container" == "") ]]; then
    docker volume create ${nome_app2}-data 2>/dev/null || true
fi

# DETERMINAR O HOSTNAME DO MINIO
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
    else
        msg "Minio instalado, mas os dados de acesso não foram encontrados em ~/dados_minio/dados_minio.\nAbortando instalação."
        exit 0
    fi
    MINIO_ADDRESS="${MINIO_HOST}:9000"
else
    MINIO_HOST=$nome_app2
    MINIO_ADDRESS="${MINIO_HOST}:9000"
    MINIO_USER=$usuariominio
    MINIO_PASSWORD=$senhaminio
    MINIO_PUBLIC_URL=$publico

    echo -e "XXX\n45\nCRIANDO STACK DO MINIO COMPARTILHADO... \nXXX"

    cd
    mkdir -p ~/dados_minio
    echo "MINIO_USER: $usuariominio" > ~/dados_minio/dados_minio
    echo "MINIO_PASSWORD: $senhaminio" >> ~/dados_minio/dados_minio
    echo "MINIO_PUBLIC_URL: $publico" >> ~/dados_minio/dados_minio
    echo "MINIO_ADMIN_URL: $painel" >> ~/dados_minio/dados_minio

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
      - $nome_app2-data:/data
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
  $nome_app2-data:
    external: true
    name: $nome_app2-data

networks: 
  interna: 
    external: true
  externa: 
    external: true
EOL

    if [[ "$criar_portainer" == "0" ]] && [[ -f "$HOME/dados_portainer/dados_portainer" ]]; then
        dados_file="$HOME/dados_portainer/dados_portainer"
        PORTAINER_URL=$(grep "Dominio do portainer:" "$dados_file" | cut -d':' -f2 | xargs)
        ADMIN_USERNAME=$(grep "Usuario:" "$dados_file" | cut -d':' -f2 | xargs)
        ADMIN_PASSWORD=$(grep "Senha:" "$dados_file" | cut -d':' -f2 | xargs)
        STACK_NAME=$nome_app2
        STACK_FILE_PATH="/root/$nome_app2.yaml"

        get_auth_token_minio() {
            RESPONSE=$(curl -sS -X POST "https://$PORTAINER_URL/api/auth" -H "Content-Type: application/json" -d "{\"username\": \"$ADMIN_USERNAME\", \"password\": \"$ADMIN_PASSWORD\"}")
            TOKEN=$(echo "$RESPONSE" | jq -r '.jwt')
            [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ] && return 1
        }
        get_endpoint_id_minio() {
            RESPONSE=$(curl -sS -X GET "https://$PORTAINER_URL/api/endpoints" -H "Authorization: Bearer $TOKEN")
            ENDPOINT_ID=$(echo "$RESPONSE" | jq -r '.[0].Id')
        }
        get_swarm_id_minio() {
            RESPONSE=$(curl -sS -X GET "https://$PORTAINER_URL/api/endpoints/$ENDPOINT_ID/docker/swarm" -H "Authorization: Bearer $TOKEN")
            SWARM_ID=$(echo "$RESPONSE" | jq -r '.ID')
        }
        create_stack_minio() {
            response_output=$(mktemp)
            erro_output=$(mktemp)
            http_code=$(curl -s -o "$response_output" -w "%{http_code}"  -X POST \
                -H "Authorization: Bearer $TOKEN" -F "Name=$STACK_NAME" -F "file=@$STACK_FILE_PATH" \
                -F "SwarmID=$SWARM_ID" -F "endpointId=$ENDPOINT_ID" \
                "https://$PORTAINER_URL/api/stacks/create/swarm/file" 2> "$erro_output")
            rm -f "$response_output" "$erro_output"
            [ "$http_code" -ne 200 ] && return 1
        }
        get_auth_token_minio && get_endpoint_id_minio && get_swarm_id_minio && create_stack_minio || \
            docker stack deploy --prune --resolve-image always -c $nome_app2.yaml $nome_app2 >/dev/null 2>&1
    else
        docker stack deploy --prune --resolve-image always -c $nome_app2.yaml $nome_app2 >/dev/null 2>&1
    fi

    echo -e "XXX\n50\nAGUARDANDO MINIO INICIAR... \nXXX"
    sleep 15
fi

#######################################################
# 2) CRIAR BUCKET + SERVICE ACCOUNT (via container Docker)
#######################################################
# Usamos docker run --rm --network interna com a imagem minio/mc
# para que o mc consiga resolver o hostname do Minio na rede Docker.
# O host não resolve nomes de serviços Docker (ex: minio3a7f2b1).

echo -e "XXX\n55\nCRIANDO BUCKET E CREDENCIAIS NO MINIO... \nXXX"

# Gerar credenciais para o service account
access_key="$nome_app"
secret_key=$(openssl rand -hex 16)
bucket_name="$nome_app"

# Criar bucket
MC_RUN="docker run --rm --network interna minio/mc:latest"
MC_ALIAS="http://${MINIO_HOST}:9000 ${MINIO_USER} ${MINIO_PASSWORD}"

$MC_RUN alias set minio $MC_ALIAS --api S3v4 2>/dev/null || true
sleep 2
$MC_RUN mb minio/$bucket_name 2>/dev/null || true
$MC_RUN anonymous set public minio/$bucket_name 2>/dev/null || true

# Criar service account (credenciais restritas para o Milvus)
credentials=$($MC_RUN admin user svcacct add minio ${MINIO_USER} \
    --access-key "$access_key" \
    --secret-key "$secret_key" \
    --json 2>&1)

# Extrair as credenciais geradas
if echo "$credentials" | jq -e '.accessKey' >/dev/null 2>&1; then
    access_key_final=$(echo "$credentials" | jq -r '.accessKey')
    secret_key_final=$(echo "$credentials" | jq -r '.secretKey')
else
    # Fallback: usar as credenciais geradas localmente
    access_key_final="$access_key"
    secret_key_final="$secret_key"
fi

echo -e "XXX\n70\nBUCKET: $bucket_name | ACCESS KEY CRIADA \nXXX"
sleep 2

#######################################################
# 3) CRIAR YAML DO MILVUS COM AS CREDENCIAIS
#######################################################
echo -e "XXX\n75\nCRIANDO STACK DO MILVUS + ATTU... \nXXX"
cd ~/
cd

cat > $nome_app.yaml << EOL
version: "3.9"

services:

  ${nome_app}_etcd:
    image: quay.io/coreos/etcd:v3.5.25
    hostname: ${nome_app}_etcd
    networks:
      - interna
    environment:
      - ETCD_AUTO_COMPACTION_MODE=revision
      - ETCD_AUTO_COMPACTION_RETENTION=1000
      - ETCD_QUOTA_BACKEND_BYTES=4294967296
      - ETCD_SNAPSHOT_COUNT=50000
    volumes:
      - ${nome_app}_etcd:/etcd
    command: ["etcd", "-advertise-client-urls=http://0.0.0.0:2379", "-listen-client-urls", "http://0.0.0.0:2379", "--data-dir", "/etcd"]
    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
          - node.role == manager
      resources:
        limits:
          memory: 1024M
        reservations:
          memory: 256M

  ${nome_app}_milvus:
    image: milvusdb/milvus:v2.4.16
    command: ["milvus", "run", "standalone"]
    hostname: ${nome_app}_milvus
    networks:
      - externa
      - interna
    environment:
      - ETCD_ENDPOINTS=${nome_app}_etcd:2379
      - MINIO_ADDRESS=${MINIO_ADDRESS}
      - MINIO_ACCESS_KEY=${access_key_final}
      - MINIO_SECRET_KEY=${secret_key_final}
    volumes:
      - ${nome_app}_data:/var/lib/milvus
    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
          - node.role == manager
      resources:
        limits:
          cpus: "2"
          memory: 4096M
        reservations:
          cpus: "1"
          memory: 1024M
    depends_on:
      - ${nome_app}_etcd

  ${nome_app}_attu:
    image: zilliz/attu:v3.0.0-beta.6
    hostname: ${nome_app}_attu
    networks:
      - externa
      - interna
    environment:
      - MILVUS_ADDRESS=${nome_app}_milvus:19530
    depends_on:
      - ${nome_app}_milvus
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
        - traefik.http.routers.${nome_app}_attu.rule=Host(\`${urlmilvus}\`)
        - traefik.http.routers.${nome_app}_attu.entrypoints=websecure
        - traefik.http.routers.${nome_app}_attu.priority=1
        - traefik.http.routers.${nome_app}_attu.tls.certresolver=letsencryptresolver
        - traefik.http.routers.${nome_app}_attu.service=${nome_app}_attu
        - traefik.http.services.${nome_app}_attu.loadbalancer.server.port=3000
EOL
fi

cat >> $nome_app.yaml << EOL

volumes:
  ${nome_app}_etcd:
    external: true
    name: ${nome_app}_etcd
  ${nome_app}_data:
    external: true
    name: ${nome_app}_data

networks:
  externa:
    external: true
  interna:
    external: true
EOL

#######################################################
# 4) DEPLOY DO MILVUS + ATTU
#######################################################
echo -e "XXX\n80\nIMPLANTANDO MILVUS + ATTU... \nXXX"

if [[ "$criar_portainer" == "0" ]]; then
    echo -e "XXX\n83\nCRIANDO STACK NO PORTAINER 3/4  \nXXX"
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

#######################################################
# 5) AGUARDAR ATTU
#######################################################
echo -e "XXX\n90\nAGUARDANDO INICIALIZAÇÃO DOS CONTAINERS... \nXXX"
max_wait_time=300
wait_interval=5
elapsed_time=0

while [ $elapsed_time -lt $max_wait_time ]; do
    CONTAINER_ID=$(docker ps -qf name=${nome_app}_attu)
    if [ -n "$CONTAINER_ID" ]; then break; fi
    sleep $wait_interval
    elapsed_time=$((elapsed_time + wait_interval))
done

if [ -z "$CONTAINER_ID" ]; then
    echo "O container do Attu não foi encontrado após $max_wait_time segundos."
    exit 1
fi

echo -e "XXX\n95\nFINALIZANDO CONFIGURAÇÕES... \nXXX"
sleep 5

echo -e "XXX\n98\nCONFIGURAÇÃO CONCLUÍDA... \nXXX"
echo -e "XXX\n100\nINSTALAÇÃO DO MILVUS + ATTU CONCLUÍDA! \nXXX"
sleep 3

}|whiptail --title "MILVUS + ATTU - PROGRESSO DA INSTALAÇÃO" --gauge "Aguarde a instalação" 6 60 0

#######################################################
# VERIFICAÇÃO FINAL E INSTRUÇÕES DE SETUP
#######################################################

TEXTO_ACESSO="👉 Acesse Attu (Web UI): https://$urlmilvus\n\n👉 Milvus API (interno): ${nome_app}_milvus:19530\n\n👉 etcd interno: ${nome_app}_etcd:2379\n👉 MinIO Bucket: $bucket_name\n👉 MinIO Access Key: $access_key_final\n👉 MinIO Secret Key: $secret_key_final\n👉 MinIO Endpoint: $MINIO_ADDRESS"

if [[ ("$minio_container" == "") ]]; then
    TEXTO_ACESSO="$TEXTO_ACESSO\n\n👉 Minio Console: https://$painel\n👉 Minio S3: https://$publico\n👉 Minio User: $MINIO_USER\n👉 Minio Password: $MINIO_PASSWORD"
fi

if [ "$INSTALL_TYPE" = "TRADICIONAL" ]; then
    ip_servidor=$(curl -s --max-time 10 ipinfo.io/ip)
    dns_ip=$(timeout 10 nslookup "$urlmilvus" | grep "Address" | tail -n1 | awk '{print $2}' 2>/dev/null)

    if [[ "$dns_ip" != "$ip_servidor" ]]; then
        whiptail --title "Mensagem" --msgbox "Não foi possivel acessar o dominio ($urlmilvus). A instalação foi cancelada. Por favor, verifique se os apontamentos DNS estão corretos e propagados!. Depois, instale novamente. Pressione ENTER para voltar ao Menu Principal" 20 78
    else
        whiptail --title "Instalação Concluída" --msgbox "Parabéns, Milvus + Attu foi instalado com sucesso!\n\n$TEXTO_ACESSO\n\nPressione ENTER para voltar ao Menu Principal" 24 85
    fi
else
    if timeout 10 nslookup "$urlmilvus" >/dev/null 2>&1; then
        whiptail --title "Instalação Concluída" --msgbox "Parabéns, Milvus + Attu foi instalado com sucesso!\n\nConfiguração Cloudflare Tunnel concluída com rotas e DNS.\n\n$TEXTO_ACESSO\n\nPressione ENTER para voltar ao Menu Principal" 24 85
    else
        whiptail --title "Mensagem" --msgbox "AVISO: O domínio ($urlmilvus) não está resolvendo.\nVerifique a configuração do Cloudflare Tunnel.\n\nA instalação foi concluída, mas o acesso pode não funcionar até que o DNS esteja configurado corretamente.\n\n$TEXTO_ACESSO\n\nPressione ENTER para voltar ao Menu Principal" 24 85
    fi
fi

exit 0

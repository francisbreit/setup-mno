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
    whiptail --title "INSTALAÇÃO DO DIFY" --msgbox "$msg" --fb 10 70
}

while true; do
CHOICE=$(
whiptail --title "INSTALAÇÃO DO DIFY" --menu "INSTRUÇÕES\n1 - Dify é uma plataforma AI workflow (149k★ GitHub).\n2 - Serão instalados: API, Worker, Web, Sandbox e Weaviate.\n3 - Redis dedicado será criado automaticamente.\n4 - Utilize domínios apontados para o servidor.\n5 - Aperte ENTER para iniciar ou selecione SAIR." 20 70 2 \
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
    url_dify=$(whiptail --title "1/5 - URL Web do Dify" --inputbox "Digite o link da Web do Dify (ex: dify.seudominio.com):" --fb 12 60 3>&1 1>&2 2>&3) ; saida=$?
    if [[ $saida -eq '0' ]] ; then
        if [[ -z $url_dify ]] ; then msg "Digite o link da Web do Dify para continuar" ; continue ; else break; fi
    else
        echo "saindo..." & exit 0
    fi
done

while true ; do
    url_api_dify=$(whiptail --title "2/5 - URL da API do Dify" --inputbox "Digite o link da API do Dify (ex: apidify.seudominio.com):" --fb 12 60 3>&1 1>&2 2>&3) ; saida=$?
    if [[ $saida -eq '0' ]] ; then
        if [[ -z $url_api_dify ]] ; then msg "Digite o link da API do Dify para continuar" ; continue ; else break; fi
    else
        echo "saindo..." & exit 0
    fi
done

while true ; do
    email=$(whiptail --title "3/5 - Email Admin do Dify" --inputbox "Digite o email do administrador (ex: admin@dominio.com):" --fb 12 60 3>&1 1>&2 2>&3) ; saida=$?
    if [[ $saida -eq '0' ]] ; then
        if [[ -z $email ]] ; then msg "Digite o email do administrador para continuar" ; continue ; else break; fi
    else
        echo "saindo..." & exit 0
    fi
done

usersmtp=$(whiptail --title "4/5 - Usuário SMTP (opcional)" --inputbox "Pressione ENTER para configurar depois, ou digite o usuário SMTP:" --fb 12 60 3>&1 1>&2 2>&3) || usersmtp=""
if [[ -z $usersmtp ]] ; then usersmtp=usuario_smtp ; fi

senhasmtp=$(whiptail --title "5/5 - Senha SMTP (opcional)" --passwordbox "Pressione ENTER para configurar depois, ou digite a senha SMTP:" 12 60 3>&1 1>&2 2>&3) || senhasmtp=""
if [[ -z $senhasmtp ]] ; then senhasmtp=senha_smtp ; fi

smtphost=$(whiptail --title "Host SMTP (opcional)" --inputbox "Pressione ENTER para configurar depois, ou digite o Host SMTP (ex: smtp.hostinger.com):" --fb 12 60 3>&1 1>&2 2>&3) || smtphost=""
if [[ -z $smtphost ]] ; then smtphost=smtp.site.com ; fi

portasmtp=$(whiptail --title "Porta SMTP (opcional)" --inputbox "Pressione ENTER para configurar depois, ou digite a Porta SMTP (ex: 465):" --fb 12 60 3>&1 1>&2 2>&3) || portasmtp=""
if [[ -z $portasmtp ]] ; then portasmtp=465 ; fi

# --- MINIO SHARED - DETECTAR E PERGUNTAR ---
minio_container=$(docker ps -qf "name=minio")
if [[ ("$minio_container" == "") ]]; then
    while true ; do
        painel=$(whiptail --title "Dominio do Painel do Minio" --inputbox "Digite o Dominio do Painel do Minio (ex: admins3.seudominio.com):" --fb 12 60 3>&1 1>&2 2>&3) ; saida=$?
        if [[ $saida -eq '0' ]]; then
            if [[ -z $painel ]]; then msg "Digite o dominio do painel do Minio para continuar" ; continue ; else break; fi
        else
            echo "$painel"; echo "Saindo..."; exit 0
        fi
    done
    while true ; do
        publico=$(whiptail --title "Dominio Público do Minio" --inputbox "Digite o dominio Público (ex: s3.seudominio.com):" --fb 12 60 3>&1 1>&2 2>&3) ; saida=$?
        if [[ $saida -eq '0' ]]; then
            if [[ -z $publico ]]; then msg "Digite o dominio público do Minio para continuar" ; continue ; else break; fi
        else
            echo "$publico"; echo "Saindo..."; exit 0
        fi
    done
    while true ; do
        usuariominio=$(whiptail --title "Nome do Usuário do Minio" --inputbox "Digite o Usuário do Minio (ex: SeuNome):" --fb 12 60 3>&1 1>&2 2>&3) ; saida=$?
        if [[ $saida -eq '0' ]]; then
            if [[ (-z $usuariominio) || ("$usuariominio" =~ [^a-zA-Z0-9]) || (${#usuariominio} -gt 16) ]]; then
                msg "Digite o nome do usuário do Minio, sem caracteres especiais e até 16 dígitos" ; continue
            else break; fi
        else
            echo "$usuariominio"; echo "Saindo..."; exit 0
        fi
    done
    while true ; do
        senhaminio=$(whiptail --title "Senha do Minio" --inputbox "Crie sua Senha do Minio (8 a 16 dígitos, sem caracteres especiais):" --fb 12 60 3>&1 1>&2 2>&3) ; saida=$?
        if [[ $saida -eq '0' ]]; then
            if [[ (-z $senhaminio) || ("$senhaminio" =~ [^a-zA-Z0-9]) || (${#senhaminio} -lt 8) || (${#senhaminio} -gt 16) ]]; then
                msg "Digite a senha do Minio, sem caracteres especiais e de 8 até 16 dígitos" ; continue
            else break; fi
        else
            echo "$senhaminio"; echo "Saindo..."; exit 0
        fi
    done
    mkdir -p ~/dados_minio
    echo "MINIO_USER: $usuariominio" > ~/dados_minio/dados_minio
    echo "MINIO_PASSWORD: $senhaminio" >> ~/dados_minio/dados_minio
    echo "MINIO_PUBLIC_URL: $publico" >> ~/dados_minio/dados_minio
    echo "MINIO_ADMIN_URL: $painel" >> ~/dados_minio/dados_minio
fi

while true ; do
    criar_portainer=$(whiptail --title "Criar Stack no Portainer? - 0 ou 1" --inputbox "Digite 0 para editar stack no portainer ou 1 para não editar" --fb 12 60 3>&1 1>&2 2>&3) ; saida=$?
    if [[ $saida -eq '0' ]] ; then
        if [[ "$criar_portainer" != "0" && "$criar_portainer" != "1" ]] ; then msg "Digite 0 ou 1" ; continue ; else break; fi
    else
        echo "saindo..." & exit 0
    fi
done

nome_principal="dify"
sufixo_app=$(date | md5sum | head -c7)
nome_app=$nome_principal$sufixo_app
postgres_password=$(grep -oP '(?<=POSTGRES_PASSWORD=).+' /root/postgres.yaml)
container_id=$(docker ps -qf name=postgres)

{
  tput reset 2>/dev/null
  exec 0</dev/tty 1>/dev/tty 2>&1
  sleep 0.01
  clear
} || true

whiptail --title "Dados Fornecidos" \
--msgbox "TIPO DE INSTALAÇÃO: $INSTALL_TYPE\n\nDados:\n1) Web: $url_dify\n2) API: $url_api_dify\n3) Email: $email\n4) SMTP: $usersmtp / $senhasmtp\n5) Host SMTP: $smtphost:$portasmtp\n6) Minio: $([ "$minio_container" != "" ] && echo "Já existente (compartilhado)" || echo "Será instalado")\n7) Portainer: $([ "$criar_portainer" == "0" ] && echo "0 (Editável)" || echo "1 (Não editável)")\n\nConfirme e tecle Enter." --fb 20 80

while true; do
{
  tput reset 2>/dev/null
  exec 0</dev/tty 1>/dev/tty 2>&1
  sleep 0.01
  clear
} || true
    confirma1=$(whiptail --title "Confirmação" --inputbox "Informações corretas? Digite 'y' para instalar ou 'n' para sair:" --fb 10 60 3>&1 1>&2 2>&3)
    if [[ "$confirma1" =~ ^[yY]$ ]]; then
        break
    elif [[ "$confirma1" =~ ^[nN]$ ]]; then
        msg "Instalação cancelada."
        exit 0
    else
        msg "Use 'y' ou 'n'"
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

# --- VARIÁVEIS ---
secret_key=$(openssl rand -hex 32)
sandbox_key=$(openssl rand -hex 32)
weaviate_key=$(openssl rand -hex 16)

# Fallback nome_servidor
if [ -z "$nome_servidor" ]; then
    nome_servidor=$(hostname -I | awk '{print $1}')
fi

echo -e "XXX\n5\nVERIFICANDO CONFIGURAÇÃO URL WEB... \nXXX"

# --- DNS URL WEB ---
if [ "$INSTALL_TYPE" = "TRADICIONAL" ] && [ -n "$CLOUDFLARE_API_TOKEN" ] && [ -n "$CLOUDFLARE_ZONE_ID" ]; then
    echo -e "XXX\n10\nCONFIGURANDO DNS WEB (TRADICIONAL)... \nXXX"
    DOMINIO_PRINCIPAL=$(echo "$url_dify" | cut -d'.' -f2-)
    EXISTING_RECORDS=$(curl -s -X GET \
        "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records?name=${url_dify}" \
        -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
        -H "Content-Type: application/json")
    COUNT=$(echo "$EXISTING_RECORDS" | jq '.result | length')
    if [[ "$COUNT" -gt 0 ]]; then
        echo -e "XXX\n15\nREMOVENDO REGISTROS WEB ANTIGOS... \nXXX"
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
        --data '{"type":"CNAME","name":"'${url_dify}'","content":"'${nome_servidor}'.'${DOMINIO_PRINCIPAL}'","ttl":1,"proxied":false}')
    if echo "$CNAME_RESPONSE" | grep -q '"success":true'; then echo -e "XXX\n20\nREGISTRO WEB CRIADO! \nXXX"; fi

elif [ "$INSTALL_TYPE" = "CLOUDFLARE_TUNNEL" ]; then
    echo -e "XXX\n10\nCONFIGURANDO DNS WEB (TUNNEL)... \nXXX"
    DOMINIO_PRINCIPAL=$(echo "$url_dify" | cut -d'.' -f2-)
    EXISTING_RECORDS=$(curl -s -X GET \
        "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records?name=${url_dify}" \
        -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
        -H "Content-Type: application/json")
    COUNT=$(echo "$EXISTING_RECORDS" | jq '.result | length')
    if [[ "$COUNT" -gt 0 ]]; then
        echo -e "XXX\n15\nREMOVENDO REGISTROS WEB ANTIGOS... \nXXX"
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
        --data "{\"type\":\"CNAME\",\"name\":\"${url_dify}\",\"content\":\"${TUNNEL_ID}.cfargotunnel.com\",\"ttl\":1,\"proxied\":true}")
    if echo "$DNS_RESPONSE" | grep -q '"success":true'; then echo -e "XXX\n20\nREGISTRO WEB CRIADO! \nXXX"; fi
fi

echo -e "XXX\n22\nCONFIGURANDO URL API... \nXXX"

# --- DNS URL API ---
if [ "$INSTALL_TYPE" = "TRADICIONAL" ] && [ -n "$CLOUDFLARE_API_TOKEN" ] && [ -n "$CLOUDFLARE_ZONE_ID" ]; then
    echo -e "XXX\n25\nCONFIGURANDO DNS API (TRADICIONAL)... \nXXX"
    DOMINIO_PRINCIPAL=$(echo "$url_api_dify" | cut -d'.' -f2-)
    EXISTING_RECORDS=$(curl -s -X GET \
        "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records?name=${url_api_dify}" \
        -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
        -H "Content-Type: application/json")
    COUNT=$(echo "$EXISTING_RECORDS" | jq '.result | length')
    if [[ "$COUNT" -gt 0 ]]; then
        echo -e "XXX\n30\nREMOVENDO REGISTROS API ANTIGOS... \nXXX"
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
        --data '{"type":"CNAME","name":"'${url_api_dify}'","content":"'${nome_servidor}'.'${DOMINIO_PRINCIPAL}'","ttl":1,"proxied":false}')
    if echo "$CNAME_RESPONSE" | grep -q '"success":true'; then echo -e "XXX\n35\nREGISTRO API CRIADO! \nXXX"; fi

elif [ "$INSTALL_TYPE" = "CLOUDFLARE_TUNNEL" ]; then
    echo -e "XXX\n25\nCONFIGURANDO DNS API (TUNNEL)... \nXXX"
    DOMINIO_PRINCIPAL=$(echo "$url_api_dify" | cut -d'.' -f2-)
    EXISTING_RECORDS=$(curl -s -X GET \
        "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records?name=${url_api_dify}" \
        -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
        -H "Content-Type: application/json")
    COUNT=$(echo "$EXISTING_RECORDS" | jq '.result | length')
    if [[ "$COUNT" -gt 0 ]]; then
        echo -e "XXX\n30\nREMOVENDO REGISTROS API ANTIGOS... \nXXX"
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
        --data "{\"type\":\"CNAME\",\"name\":\"${url_api_dify}\",\"content\":\"${TUNNEL_ID}.cfargotunnel.com\",\"ttl\":1,\"proxied\":true}")
    if echo "$DNS_RESPONSE" | grep -q '"success":true'; then echo -e "XXX\n35\nREGISTRO API CRIADO! \nXXX"; fi
fi

# --- TUNNEL ROTAS (se Cloudflare Tunnel) ---
if [ "$INSTALL_TYPE" = "CLOUDFLARE_TUNNEL" ] && [ -n "$CLOUDFLARE_ACCOUNT_ID" ] && [ -n "$TUNNEL_ID" ]; then
    echo -e "XXX\n40\nCONFIGURANDO ROTAS DO TUNNEL... \nXXX"

    for entry in "$url_dify:$nome_app-web:3000" "$url_api_dify:$nome_app-api:5001"; do
        host=$(echo "$entry" | cut -d: -f1)
        service_name=$(echo "$entry" | cut -d: -f2)
        port=$(echo "$entry" | cut -d: -f3)
        NEW_SERVICE="http://${service_name}:${port}"

        TIMESTAMP=$(date -u +%Y%m%dT%H%M%SZ)
        TMPDIR=$(mktemp -d)
        BACKUP_RAW="$TMPDIR/backup_raw.$TIMESTAMP.json"
        TO_PUT="$TMPDIR/to_put.$TIMESTAMP.json"

        curl -sS -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
          "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/cfd_tunnel/$TUNNEL_ID/configurations" \
          | jq '.' > "$BACKUP_RAW"

        jq --arg host "$host" --arg service "$NEW_SERVICE" '
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
    done
    echo -e "XXX\n45\nROTAS DO TUNNEL CONFIGURADAS! \nXXX"
fi

# --- MINIO - CARREGAR CREDENCIAIS ---
dados_minio_file="$HOME/dados_minio/dados_minio"
if [[ -f "$dados_minio_file" ]]; then
    MINIO_USER=$(grep "MINIO_USER:" "$dados_minio_file" | awk '{print $2}')
    MINIO_PASSWORD=$(grep "MINIO_PASSWORD:" "$dados_minio_file" | awk '{print $2}')
    MINIO_PUBLIC_URL=$(grep "MINIO_PUBLIC_URL:" "$dados_minio_file" | awk '{print $2}')
    MINIO_ADMIN_URL=$(grep "MINIO_ADMIN_URL:" "$dados_minio_file" | awk '{print $2}')
fi

# --- DNS/ROTAS DO MINIO ---
if [[ ("$minio_container" == "") ]]; then
    nome_principal2="minio"
    nome_app2=$nome_principal2$sufixo_app

    DOMINIO_PRINCIPAL=$(echo "$url_dify" | cut -d'.' -f2-)

    if [ "$INSTALL_TYPE" = "TRADICIONAL" ] && [ -n "$CLOUDFLARE_API_TOKEN" ] && [ -n "$CLOUDFLARE_ZONE_ID" ]; then
        echo -e "XXX\n48\nCONFIGURANDO DNS DO MINIO (TRADICIONAL)... \nXXX"
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
    elif [ "$INSTALL_TYPE" = "CLOUDFLARE_TUNNEL" ] && [ -n "$CLOUDFLARE_ACCOUNT_ID" ] && [ -n "$TUNNEL_ID" ]; then
        echo -e "XXX\n48\nCONFIGURANDO DNS/ROTAS DO MINIO (TUNNEL)... \nXXX"
        for minio_url in "$painel" "$publico"; do
            DNS_RESPONSE=$(curl -s -X POST "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records" \
                -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" -H "Content-Type: application/json" \
                --data "{\"type\":\"CNAME\",\"name\":\"${minio_url}\",\"content\":\"${TUNNEL_ID}.cfargotunnel.com\",\"ttl\":1,\"proxied\":true}")
        done
        TIMESTAMP=$(date -u +%Y%m%dT%H%M%SZ)
        TMPDIR=$(mktemp -d)
        BACKUP_RAW="$TMPDIR/backup_raw.$TIMESTAMP.json"
        TO_PUT="$TMPDIR/to_put.$TIMESTAMP.json"
        curl -sS -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
            "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/cfd_tunnel/$TUNNEL_ID/configurations" \
            | jq '.' > "$BACKUP_RAW"
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
    fi
fi

# --- VERIFICAÇÃO DNS TRADICIONAL ---
if [ "$INSTALL_TYPE" = "TRADICIONAL" ] && { [ -z "$CLOUDFLARE_API_TOKEN" ] || [ -z "$CLOUDFLARE_ZONE_ID" ]; }; then
    echo -e "XXX\n48\nVERIFICANDO DNS... \nXXX"
    ip_servidor=$(curl -s --max-time 10 ipinfo.io/ip)
    for dom in "$url_dify" "$url_api_dify"; do
        dns_ip=$(timeout 10 nslookup "$dom" | grep "Address" | tail -n1 | awk '{print $2}')
        if [[ "$dns_ip" != "$ip_servidor" ]]; then
            echo -e "XXX\n50\nAVISO: $dom não aponta para $ip_servidor \nXXX"
            sleep 3
        fi
    done
fi

# --- CRIAR BANCO DE DADOS ---
echo -e "XXX\n52\nCRIANDO BANCO DE DADOS... \nXXX"
docker exec $container_id psql -U postgres -d postgres -c "CREATE DATABASE $nome_app;" >/dev/null 2>&1

# --- MINIO - INSTALAR SE NECESSÁRIO ---
if [[ ("$minio_container" == "") ]]; then
    echo -e "XXX\n54\nINSTALANDO MINIO COMPARTILHADO... \nXXX"

    docker volume create ${nome_app2}-data >/dev/null 2>&1 || true

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

    if [[ "$criar_portainer" == "0" ]]; then
        dados_file="$HOME/dados_portainer/dados_portainer"
        if [[ -f "$dados_file" ]]; then
            PORTAINER_URL=$(grep "Dominio do portainer:" "$dados_file" | cut -d':' -f2 | xargs)
            ADMIN_USERNAME=$(grep "Usuario:" "$dados_file" | cut -d':' -f2 | xargs)
            ADMIN_PASSWORD=$(grep "Senha:" "$dados_file" | cut -d':' -f2 | xargs)
            RESPONSE=$(curl -sk -X POST "https://$PORTAINER_URL/api/auth" -H "Content-Type: application/json" -d "{\"username\": \"$ADMIN_USERNAME\", \"password\": \"$ADMIN_PASSWORD\"}")
            TOKEN=$(echo "$RESPONSE" | jq -r '.jwt')
            if [ -n "$TOKEN" ] && [ "$TOKEN" != "null" ]; then
                RESPONSE=$(curl -sk -X GET "https://$PORTAINER_URL/api/endpoints" -H "Authorization: Bearer $TOKEN")
                ENDPOINT_ID=$(echo "$RESPONSE" | jq -r '.[0].Id')
                if [ -n "$ENDPOINT_ID" ] && [ "$ENDPOINT_ID" != "null" ]; then
                    RESPONSE=$(curl -sk -X GET "https://$PORTAINER_URL/api/endpoints/$ENDPOINT_ID/docker/swarm" -H "Authorization: Bearer $TOKEN")
                    SWARM_ID=$(echo "$RESPONSE" | jq -r '.ID')
                    if [ -n "$SWARM_ID" ] && [ "$SWARM_ID" != "null" ] && [ -f "/root/$nome_app2.yaml" ]; then
                        http_code=$(curl -s -o /dev/null -w "%{http_code}" -k -X POST \
                            -H "Authorization: Bearer $TOKEN" -F "Name=$nome_app2" -F "file=@/root/$nome_app2.yaml" \
                            -F "SwarmID=$SWARM_ID" -F "endpointId=$ENDPOINT_ID" \
                            "https://$PORTAINER_URL/api/stacks/create/swarm/file" 2>/dev/null)
                    fi
                fi
            fi
        fi
    else
        docker stack deploy --prune --resolve-image always -c $nome_app2.yaml $nome_app2 >/dev/null 2>&1
    fi

    echo -e "XXX\n56\nAGUARDANDO MINIO INICIAR... \nXXX"
    sleep 20
fi

echo -e "XXX\n58\nCRIANDO BUCKET E CREDENCIAIS NO MINIO... \nXXX"

minio_host=""
if [[ ("$minio_container" != "") ]]; then
    minio_service=$(docker service ls --format "{{.Name}}" 2>/dev/null | grep "minio" | head -1)
    if [[ -n "$minio_service" ]]; then
        minio_host=$minio_service
    else
        minio_container_name=$(docker ps --format "{{.Names}}" | grep "minio" | head -1)
        minio_host=$(echo $minio_container_name | cut -d'.' -f1)
    fi
else
    minio_host=$nome_app2
fi

if ! command -v mc &> /dev/null; then
    ARCH=$(uname -m)
    if [[ "$ARCH" == "x86_64" ]]; then
        wget https://dl.min.io/client/mc/release/linux-amd64/mc -O /usr/local/bin/mc >/dev/null 2>&1
    elif [[ "$ARCH" == "aarch64" ]] || [[ "$ARCH" == "armv7l" ]]; then
        wget https://dl.min.io/client/mc/release/linux-arm64/mc -O /usr/local/bin/mc >/dev/null 2>&1
    fi
    chmod +x /usr/local/bin/mc
fi

if ! command -v jq &> /dev/null; then
    apt-get install -y jq >/dev/null 2>&1
fi

# Usar docker exec no container do MinIO (mc vem embutido na imagem)
# Evita "network interna not manually attachable" do docker run
MINIO_CONTAINER=$(docker ps --format "{{.Names}}" | grep "minio\." | head -1)
if [[ -z "$MINIO_CONTAINER" ]]; then
    MINIO_CONTAINER=$(docker ps --format "{{.Names}}" | grep "minio" | head -1)
fi

echo -e "XXX\n59\nAGUARDANDO MINIO FICAR PRONTO... \nXXX"
for i in $(seq 1 30); do
    docker exec $MINIO_CONTAINER mc alias set minio http://localhost:9000 ${MINIO_USER} ${MINIO_PASSWORD} --api S3v4 >/dev/null 2>&1 && break
    sleep 5
done

echo -e "XXX\n60\nCRIANDO BUCKET NO MINIO... \nXXX"
bucket_name="$nome_app"
docker exec $MINIO_CONTAINER mc mb minio/$bucket_name >/dev/null 2>&1 || true
docker exec $MINIO_CONTAINER mc anonymous set public minio/$bucket_name >/dev/null 2>&1 || true

echo -e "XXX\n61\nCRIANDO SERVICE ACCOUNT... \nXXX"
s3_access_key=$(openssl rand -hex 16)
s3_secret_key=$(openssl rand -hex 32)

# Detectar usuário do MinIO se vazio
if [[ -z "$MINIO_USER" ]]; then
    MINIO_USER=$(docker exec $MINIO_CONTAINER printenv MINIO_ROOT_USER 2>/dev/null)
    MINIO_PASSWORD=$(docker exec $MINIO_CONTAINER printenv MINIO_ROOT_PASSWORD 2>/dev/null)
fi

# Criar service account (tenta svcacct add, fallback user add)
svcacct_ok=false
if docker exec $MINIO_CONTAINER mc admin user svcacct add minio "$MINIO_USER" --access-key "$s3_access_key" --secret-key "$s3_secret_key" >/dev/null 2>&1; then
    svcacct_ok=true
elif command -v mc &>/dev/null && mc admin user svcacct add minio "$MINIO_USER" --access-key "$s3_access_key" --secret-key "$s3_secret_key" >/dev/null 2>&1; then
    svcacct_ok=true
fi
if ! $svcacct_ok; then
    echo -e "XXX\n61\nTENTANDO CRIAR USUARIO DIRETO... \nXXX"
    if docker exec $MINIO_CONTAINER mc admin user add minio "$s3_access_key" "$s3_secret_key" >/dev/null 2>&1; then
        docker exec $MINIO_CONTAINER mc admin policy set minio readwrite user="$s3_access_key" >/dev/null 2>&1 || true
        svcacct_ok=true
    elif command -v mc &>/dev/null && mc admin user add minio "$s3_access_key" "$s3_secret_key" >/dev/null 2>&1; then
        mc admin policy set minio readwrite user="$s3_access_key" >/dev/null 2>&1 || true
        svcacct_ok=true
    fi
fi
if ! $svcacct_ok; then
    echo -e "XXX\n61\nAVISO: service account nao criado - chaves pre-geradas podem nao funcionar \nXXX"
fi

# --- CRIAR VOLUMES ---
echo -e "XXX\n62\nCRIANDO VOLUMES... \nXXX"
docker volume create ${nome_app}-storage >/dev/null 2>&1
docker volume create ${nome_app}-weaviate >/dev/null 2>&1
docker volume create ${nome_app}-redis >/dev/null 2>&1

# --- APAGAR STACKS ANTIGAS ---
echo -e "XXX\n58\nREMOVENDO STACKS ANTIGAS... \nXXX"
docker stack rm ${nome_app}-redis >/dev/null 2>&1
docker stack rm ${nome_app}-weaviate >/dev/null 2>&1
docker stack rm ${nome_app} >/dev/null 2>&1
sleep 10

cd
cd

# --- REDIS DEDICADO ---
echo -e "XXX\n60\nCRIANDO REDIS DEDICADO... \nXXX"

cat > ${nome_app}-redis.yaml << EOL

version: "3.7"
services:
  ${nome_app}_redis:
    image: redis:7-alpine
    command: redis-server --maxmemory 256mb --maxmemory-policy allkeys-lru
    hostname: ${nome_app}_redis
    networks:
      - interna
    volumes:
      - ${nome_app}-redis:/data
    deploy:
      placement:
        constraints:
          - node.role == manager
volumes:
  ${nome_app}-redis:
    external: true
    name: ${nome_app}-redis
networks:
  interna:
    external: true
    name: interna
EOL

redis_deployed=false
if [[ "$criar_portainer" == "0" ]]; then
    dados_file="$HOME/dados_portainer/dados_portainer"
    if [[ -f "$dados_file" ]]; then
        PORTAINER_URL=$(grep "Dominio do portainer:" "$dados_file" | cut -d':' -f2 | xargs)
        ADMIN_USERNAME=$(grep "Usuario:" "$dados_file" | cut -d':' -f2 | xargs)
        ADMIN_PASSWORD=$(grep "Senha:" "$dados_file" | cut -d':' -f2 | xargs)
        REDIS_STACK_NAME="${nome_app}-redis"
        REDIS_STACK_FILE="/root/${nome_app}-redis.yaml"

        RESPONSE=$(curl -sk -X POST "https://$PORTAINER_URL/api/auth" \
            -H "Content-Type: application/json" \
            -d "{\"username\": \"$ADMIN_USERNAME\", \"password\": \"$ADMIN_PASSWORD\"}")
        TOKEN=$(echo "$RESPONSE" | jq -r '.jwt')
        if [ -n "$TOKEN" ] && [ "$TOKEN" != "null" ]; then
            RESPONSE=$(curl -sk -X GET "https://$PORTAINER_URL/api/endpoints" -H "Authorization: Bearer $TOKEN")
            ENDPOINT_ID=$(echo "$RESPONSE" | jq -r '.[0].Id')
            if [ -n "$ENDPOINT_ID" ] && [ "$ENDPOINT_ID" != "null" ]; then
                RESPONSE=$(curl -sk -X GET "https://$PORTAINER_URL/api/endpoints/$ENDPOINT_ID/docker/swarm" -H "Authorization: Bearer $TOKEN")
                SWARM_ID=$(echo "$RESPONSE" | jq -r '.ID')
                if [ -n "$SWARM_ID" ] && [ "$SWARM_ID" != "null" ] && [ -f "$REDIS_STACK_FILE" ]; then
                    http_code=$(curl -s -o /dev/null -w "%{http_code}" -k -X POST \
                        -H "Authorization: Bearer $TOKEN" \
                        -F "Name=$REDIS_STACK_NAME" \
                        -F "file=@$REDIS_STACK_FILE" \
                        -F "SwarmID=$SWARM_ID" \
                        -F "endpointId=$ENDPOINT_ID" \
                        "https://$PORTAINER_URL/api/stacks/create/swarm/file" 2>/dev/null)
                    if [ "$http_code" = "200" ]; then redis_deployed=true; fi
                fi
            fi
        fi
    fi
fi
if ! $redis_deployed; then
    docker stack deploy --prune --resolve-image always -c ${nome_app}-redis.yaml ${nome_app}-redis >/dev/null 2>&1
fi

echo -e "XXX\n65\nREDIS CRIADO! \nXXX"

# --- WEAVIATE DEDICADO ---
echo -e "XXX\n68\nCRIANDO WEAVIATE DEDICADO... \nXXX"

cat > ${nome_app}-weaviate.yaml << EOL

version: "3.7"
services:
  ${nome_app}_weaviate:
    image: semitechnologies/weaviate:latest
    hostname: ${nome_app}_weaviate
    networks:
      - interna
    volumes:
      - ${nome_app}-weaviate:/var/lib/weaviate
    environment:
      - QUERY_DEFAULTS_LIMIT=25
      - AUTHENTICATION_ANONYMOUS_ACCESS_ENABLED=false
      - PERSISTENCE_DATA_PATH=/var/lib/weaviate
      - DEFAULT_VECTORIZER_MODULE=none
      - CLUSTER_HOSTNAME=node1
      - AUTHENTICATION_APIKEY_ENABLED=true
      - AUTHENTICATION_APIKEY_ALLOWED_KEYS=$weaviate_key
      - AUTHENTICATION_APIKEY_USERS=admin@dify.local
      - AUTHORIZATION_ADMINLIST_ENABLED=true
      - AUTHORIZATION_ADMINLIST_USERS=admin@dify.local
      - DISABLE_TELEMETRY=true
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
volumes:
  ${nome_app}-weaviate:
    external: true
    name: ${nome_app}-weaviate
networks:
  interna:
    external: true
    name: interna
EOL

weaviate_deployed=false
if [[ "$criar_portainer" == "0" ]] && [ -n "$TOKEN" ] && [ "$TOKEN" != "null" ]; then
    WEAVIATE_STACK_NAME="${nome_app}-weaviate"
    WEAVIATE_STACK_FILE="/root/${nome_app}-weaviate.yaml"
    if [ -f "$WEAVIATE_STACK_FILE" ]; then
        http_code=$(curl -s -o /dev/null -w "%{http_code}" -k -X POST \
            -H "Authorization: Bearer $TOKEN" \
            -F "Name=$WEAVIATE_STACK_NAME" \
            -F "file=@$WEAVIATE_STACK_FILE" \
            -F "SwarmID=$SWARM_ID" \
            -F "endpointId=$ENDPOINT_ID" \
            "https://$PORTAINER_URL/api/stacks/create/swarm/file" 2>/dev/null)
        if [ "$http_code" = "200" ]; then weaviate_deployed=true; fi
    fi
fi
if ! $weaviate_deployed; then
    docker stack deploy --prune --resolve-image always -c ${nome_app}-weaviate.yaml ${nome_app}-weaviate >/dev/null 2>&1
fi

echo -e "XXX\n72\nWEAVIATE CRIADO! \nXXX"

# --- APP YAML ---
echo -e "XXX\n75\nCRIANDO YAML DA APLICAÇÃO... \nXXX"

REDIS_URL="redis://${nome_app}_redis:6379"

cat > $nome_app.yaml << EOL

version: "3.7"
services:

  ${nome_app}-api:
    image: langgenius/dify-api:latest
    hostname: ${nome_app}-api
    volumes:
      - ${nome_app}-storage:/app/api/storage
    networks:
      - externa
      - interna
    environment:
      - MODE=api
      - LOG_LEVEL=INFO
      - SECRET_KEY=$secret_key
      - CONSOLE_WEB_URL=https://$url_dify
      - CONSOLE_API_URL=https://$url_api_dify
      - SERVICE_API_URL=https://$url_api_dify
      - APP_WEB_URL=https://$url_dify
      - APP_API_URL=https://$url_api_dify
      - FILES_URL=https://$url_api_dify
      - MIGRATION_ENABLED=true
      - DB_USERNAME=postgres
      - DB_PASSWORD=$postgres_password
      - DB_HOST=postgres
      - DB_PORT=5432
      - DB_DATABASE=$nome_app
      - REDIS_HOST=${nome_app}_redis
      - REDIS_PORT=6379
      - REDIS_USERNAME=
      - REDIS_PASSWORD=
      - REDIS_USE_SSL=false
      - REDIS_DB=0
      - CELERY_BROKER_URL=${REDIS_URL}/1
      - WEB_API_CORS_ALLOW_ORIGINS=*
      - CONSOLE_CORS_ALLOW_ORIGINS=*
      - STORAGE_TYPE=s3
      - S3_ENDPOINT=https://$MINIO_PUBLIC_URL
      - S3_BUCKET_NAME=$bucket_name
      - S3_ACCESS_KEY=$s3_access_key
      - S3_SECRET_KEY=$s3_secret_key
      - CODE_EXECUTION_ENDPOINT=http://${nome_app}-sandbox:8194
      - CODE_EXECUTION_API_KEY=$sandbox_key
      - CODE_MAX_NUMBER=9223372036854775807
      - CODE_MIN_NUMBER=-9223372036854775808
      - CODE_MAX_STRING_LENGTH=80000
      - TEMPLATE_TRANSFORM_MAX_LENGTH=80000
      - CODE_MAX_STRING_ARRAY_LENGTH=30
      - CODE_MAX_OBJECT_ARRAY_LENGTH=30
      - CODE_MAX_NUMBER_ARRAY_LENGTH=1000
      - VECTOR_STORE=weaviate
      - WEAVIATE_ENDPOINT=http://${nome_app}_weaviate:8080
      - WEAVIATE_API_KEY=$weaviate_key
      - MAIL_TYPE=smtp
      - MAIL_DEFAULT_SEND_FROM=no-reply@$email
      - SMTP_SERVER=$smtphost
      - SMTP_PORT=$portasmtp
      - SMTP_USERNAME=$usersmtp
      - SMTP_PASSWORD=$senhasmtp
      - INIT_PASSWORD=
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
      restart_policy:
        condition: any
        delay: 10s
        max_attempts: 3
        window: 120s

  ${nome_app}-worker:
    image: langgenius/dify-api:latest
    hostname: ${nome_app}-worker
    volumes:
      - ${nome_app}-storage:/app/api/storage
    networks:
      - externa
      - interna
    environment:
      - MODE=worker
      - LOG_LEVEL=INFO
      - SECRET_KEY=$secret_key
      - DB_USERNAME=postgres
      - DB_PASSWORD=$postgres_password
      - DB_HOST=postgres
      - DB_PORT=5432
      - DB_DATABASE=$nome_app
      - REDIS_HOST=${nome_app}_redis
      - REDIS_PORT=6379
      - REDIS_USERNAME=
      - REDIS_PASSWORD=
      - REDIS_USE_SSL=false
      - REDIS_DB=0
      - CELERY_BROKER_URL=${REDIS_URL}/1
      - STORAGE_TYPE=s3
      - S3_ENDPOINT=https://$MINIO_PUBLIC_URL
      - S3_BUCKET_NAME=$bucket_name
      - S3_ACCESS_KEY=$s3_access_key
      - S3_SECRET_KEY=$s3_secret_key
      - VECTOR_STORE=weaviate
      - WEAVIATE_ENDPOINT=http://${nome_app}_weaviate:8080
      - WEAVIATE_API_KEY=$weaviate_key
      - MAIL_TYPE=smtp
      - MAIL_DEFAULT_SEND_FROM=no-reply@$email
      - SMTP_SERVER=$smtphost
      - SMTP_PORT=$portasmtp
      - SMTP_USERNAME=$usersmtp
      - SMTP_PASSWORD=$senhasmtp
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
      restart_policy:
        condition: any
        delay: 10s
        max_attempts: 3
        window: 120s

  ${nome_app}-worker-beat:
    image: langgenius/dify-api:latest
    hostname: ${nome_app}-worker-beat
    volumes:
      - ${nome_app}-storage:/app/api/storage
    networks:
      - externa
      - interna
    environment:
      - MODE=beat
      - LOG_LEVEL=INFO
      - SECRET_KEY=$secret_key
      - DB_USERNAME=postgres
      - DB_PASSWORD=$postgres_password
      - DB_HOST=postgres
      - DB_PORT=5432
      - DB_DATABASE=$nome_app
      - REDIS_HOST=${nome_app}_redis
      - REDIS_PORT=6379
      - REDIS_USERNAME=
      - REDIS_PASSWORD=
      - REDIS_USE_SSL=false
      - REDIS_DB=0
      - CELERY_BROKER_URL=${REDIS_URL}/1
    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
          - node.role == manager
      resources:
        limits:
          cpus: "0.5"
          memory: 256M
      restart_policy:
        condition: any
        delay: 10s
        max_attempts: 3
        window: 120s

  ${nome_app}-web:
    image: langgenius/dify-web:latest
    hostname: ${nome_app}-web
    networks:
      - externa
      - interna
    environment:
      - EDITION=SELF_HOSTED
      - CONSOLE_API_URL=https://$url_api_dify
      - APP_API_URL=https://$url_api_dify
      - SENTRY_DSN=
    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
          - node.role == manager
      resources:
        limits:
          cpus: "0.5"
          memory: 512M
      restart_policy:
        condition: any
        delay: 10s
        max_attempts: 3
        window: 120s

  ${nome_app}-sandbox:
    image: langgenius/dify-sandbox:latest
    hostname: ${nome_app}-sandbox
    networks:
      - externa
      - interna
    environment:
      - API_KEY=$sandbox_key
      - GIN_MODE=release
      - WORKER_TIMEOUT=15
    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
          - node.role == manager
      resources:
        limits:
          cpus: "0.5"
          memory: 256M
      restart_policy:
        condition: any
        delay: 10s
        max_attempts: 3
        window: 120s
EOL

if [ "$INSTALL_TYPE" = "TRADICIONAL" ]; then
cat >> $nome_app.yaml << EOL

      labels:
        - traefik.enable=true
        - traefik.docker.network=externa
        - traefik.http.routers.${nome_app}-api.rule=Host(\`$url_api_dify\`)
        - traefik.http.routers.${nome_app}-api.entrypoints=websecure
        - traefik.http.routers.${nome_app}-api.priority=1
        - traefik.http.routers.${nome_app}-api.tls.certresolver=letsencryptresolver
        - traefik.http.routers.${nome_app}-api.tls=true
        - traefik.http.routers.${nome_app}-api.service=${nome_app}-api
        - traefik.http.services.${nome_app}-api.loadbalancer.server.port=5001

  ${nome_app}-web:
    labels:
      - traefik.enable=true
      - traefik.docker.network=externa
      - traefik.http.routers.${nome_app}-web.rule=Host(\`$url_dify\`)
      - traefik.http.routers.${nome_app}-web.entrypoints=websecure
      - traefik.http.routers.${nome_app}-web.priority=1
      - traefik.http.routers.${nome_app}-web.tls.certresolver=letsencryptresolver
      - traefik.http.routers.${nome_app}-web.tls=true
      - traefik.http.routers.${nome_app}-web.service=${nome_app}-web
      - traefik.http.services.${nome_app}-web.loadbalancer.server.port=3000
EOL
fi

cat >> $nome_app.yaml << EOL

networks:
  externa:
    external: true
  interna:
    external: true

volumes:
  ${nome_app}-storage:
    external: true
    name: ${nome_app}-storage
EOL

echo -e "XXX\n80\nYAML CRIADO! \nXXX"

# --- DEPLOY ---
echo -e "XXX\n85\nFAZENDO DEPLOY DO DIFY... \nXXX"

if [[ "$criar_portainer" == "0" ]] && [ -n "$TOKEN" ] && [ "$TOKEN" != "null" ]; then
    STACK_NAME=$nome_app
    STACK_FILE_PATH="/root/$nome_app.yaml"
    if [ -f "$STACK_FILE_PATH" ]; then
        http_code=$(curl -s -o /dev/null -w "%{http_code}" -k -X POST \
            -H "Authorization: Bearer $TOKEN" \
            -F "Name=$STACK_NAME" \
            -F "file=@$STACK_FILE_PATH" \
            -F "SwarmID=$SWARM_ID" \
            -F "endpointId=$ENDPOINT_ID" \
            "https://$PORTAINER_URL/api/stacks/create/swarm/file" 2>/dev/null)
        if [ "$http_code" -ne 200 ]; then
            echo -e "XXX\n88\nERRO NO PORTAINER - USANDO DOCKER... \nXXX"
            docker stack deploy --prune --resolve-image always -c $nome_app.yaml $nome_app >/dev/null 2>&1
        fi
    else
        docker stack deploy --prune --resolve-image always -c $nome_app.yaml $nome_app >/dev/null 2>&1
    fi
else
    docker stack deploy --prune --resolve-image always -c $nome_app.yaml $nome_app >/dev/null 2>&1
fi

echo -e "XXX\n92\nAGUARDANDO SERVIÇOS INICIAREM... \nXXX"
sleep 15

echo -e "XXX\n95\nVERIFICANDO SERVIÇOS... \nXXX"
docker stack services $nome_app --format "{{.Name}}: {{.Replicas}}" 2>/dev/null || true
sleep 5

echo -e "XXX\n100\nINSTALAÇÃO CONCLUÍDA! \nXXX"

} | whiptail --title "INSTALANDO DIFY" --gauge "AGUARDE..." 8 70 0

if [ "$INSTALL_TYPE" = "CLOUDFLARE_TUNNEL" ]; then
    whiptail --title "Sucesso" --msgbox "Instalação concluída!\n\nAcessos:\n- Dify Web: https://$url_dify\n- Dify API: https://$url_api_dify\n\nEmail admin: $email\nSenha: (será solicitada no primeiro acesso)\n\nPressione ENTER para voltar." 20 78
else
    ip_servidor=$(curl -s --max-time 10 ipinfo.io/ip)
    whiptail --title "Sucesso" --msgbox "Instalação concluída!\n\nAcessos:\n- Dify Web: https://$url_dify\n- Dify API: https://$url_api_dify\n\nIP do servidor: $ip_servidor\n\nPressione ENTER para voltar." 20 78
fi

exit 0

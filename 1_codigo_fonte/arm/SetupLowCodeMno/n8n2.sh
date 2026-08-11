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
  tput reset 2>/dev/null         # Reinicia o terminal de forma segura
  exec 0</dev/tty 1>/dev/tty 2>&1 # Força redirecionamentos explícitos
  sleep 0.01                     # Pausa microscópica para sincronia
  clear                          # Limpeza final antes do whiptail
} || true
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

function msg() {
		msg=$1
		whiptail --title "INSTALAÇÃO DO N8N V2 MODO FILA: PLATAFORMA DE AUTOMAÇÃO" --msgbox "$msg" --fb 10 70;
	}

  while true; do
CHOICE=$(
whiptail --title "INSTALAÇÃO DO N8N V2 MODO FILA: PLATAFORMA DE AUTOMAÇÃO" --menu "Aperte ENTER para iniciar a instalação do N8N modo fila ou selecione SAIR (Utilize setas e Enter)\n\nTIPO DE INSTALAÇÃO DETECTADA: $INSTALL_TYPE\n\nINSTRUÇÕES:\nAntes de prosseguir, verifique os registros DNS conforme seu tipo de instalação:" 20 70 2 \
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
		dominioadmin=$(whiptail --title "1/2 - URL do Admin" --inputbox "Digite o dominio para acessar o admin N8N (ex: apiadmin.dominio.com):" --fb 12 60 3>&1 1>&2 2>&3) ; saida=$?
		if [[ $saida -eq '0' ]] ; then
			if [[ -z $dominioadmin ]] ; then msg "Digite o link do admin do N8N para poder continuar" ; continue ; else break; fi
		else
			echo $dominioadmin ; echo "saindo..."  &  exit 0 ;
		fi
	done

      while true ; do
		dominiowebhook=$(whiptail --title "2/2 - URL do Webhook" --inputbox "Digite o dominio do Webhook do N8N (ex: webhook.dominio.com):" --fb 12 60 3>&1 1>&2 2>&3) ; saida=$?
		if [[ $saida -eq '0' ]] ; then
			if [[ -z $dominiowebhook ]] ; then msg "Digite o link do webhook do N8N para poder continuar" ; continue ; else break; fi
		else
			echo $dominiowebhook ; echo "saindo..."  &  exit 0 ;
		fi
	done

  user_smtp=$(whiptail --title "Usuário do SMTP" --inputbox "Pressione ENTER para configurar depois, ou digite o usuário do smtp." --fb 12 60 3>&1 1>&2 2>&3) ; saida=$?
		if [[ $saida -eq '0' ]] ; then if [[ -z $user_smtp ]] ; then user_smtp=usuario_do_smtp ; fi else echo "saindo..." ; exit ; fi

     email_smtp=$(whiptail --title "Email Remetente do SMTP" --inputbox "Pressione ENTER para configurar depois, ou digite o email do smtp." --fb 12 60 3>&1 1>&2 2>&3) ; saida=$?
		if [[ $saida -eq '0' ]] ; then if [[ -z $email_smtp ]] ; then email_smtp=email_do_smtp ; fi else echo "saindo..." ; exit ; fi

    senha=$(whiptail --title "Senha do Email SMTP" --inputbox "Pressione ENTER para configurar depois, ou digite o senha do seu email." --fb 12 60 3>&1 1>&2 2>&3) ; saida=$?
		if [[ $saida -eq '0' ]] ; then if [[ -z $senha ]] ; then senha=senha_do_email ; fi else echo "saindo..." ; exit ; fi

    smtp=$(whiptail --title "Host do SMTP do Email" --inputbox "Pressione ENTER para configurar depois, ou digite o Host SMTP do seu email (ex: smtp.hostinger.com):" --fb 12 60 3>&1 1>&2 2>&3) ; saida=$?
		if [[ $saida -eq '0' ]] ; then if [[ -z $smtp ]] ; then smtp=smtp.site.com ; fi else echo "saindo..." ; exit ; fi


    portasmtp=$(whiptail --title "Porta do SMTP" --inputbox "Pressione ENTER para configurar depois, ou digite digite a Porta SMTP (ex: 465):" --fb 12 60 3>&1 1>&2 2>&3) ; saida=$?
		if [[ $saida -eq '0' ]] ; then if [[ -z $portasmtp ]] ; then portasmtp=465 ; fi else echo "saindo..." ; exit ; fi

    if [ "$portasmtp" -eq 465 ]; then
    SECURE=false
    else
    SECURE=true
    fi      

 while true ; do
		criar_portainer=$(whiptail --title "Criar Stack no Portainer? - 0 ou 1" --inputbox "Digite 0 para poder editar stack no portainer ou 1 para não poder editar" --fb 12 60 3>&1 1>&2 2>&3) ; saida=$?
		if [[ $saida -eq '0' ]] ; then
		if [[ "$criar_portainer" != "0" && "$criar_portainer" != "1" ]] ; then msg "Digite apenas o número 0 ou o número 1, para poder continuar. Digite 0 para poder editar stack no portainer ou 1 para não poder editar" ; continue ; else break; fi
    else
			echo $criar_portainer ; echo "saindo..."  &  exit 0 ;
		fi
	done    
clear
nome_editor="n8n_editor"  #nome do app
nome_webhook="n8n_webhook"
nome_worker="n8n_worker"
nome_mcp_api="n8n_mcp_api"
nome_runner="n8n_runner"

nome_databse="n8n"
sufixo_app=$(date | md5sum | head -c7)
nome_app_editor=$nome_editor$sufixo_app
nome_app_webhook=$nome_webhook$sufixo_app
nome_app_worker=$nome_worker$sufixo_app
nome_app_mcp_api=$nome_mcp_api$sufixo_app
nome_app_runner=$nome_runner$sufixo_app
nome_app_database=$nome_databse$sufixo_app
postgres_password=$(grep -oP '(?<=POSTGRES_PASSWORD=).+' /root/postgres.yaml)
container_id=$(docker ps -qf name=postgres)
docker exec -it $container_id psql -U postgres -d postgres -c "CREATE  DATABASE $nome_app_database;" 
{
  tput reset 2>/dev/null         # Reinicia o terminal de forma segura
  exec 0</dev/tty 1>/dev/tty 2>&1 # Força redirecionamentos explícitos
  sleep 0.01                     # Pausa microscópica para sincronia
  clear                          # Limpeza final antes do whiptail
} || true
    whiptail --title "Dados Fornecidos" \
    --msgbox "TIPO DE INSTALAÇÃO: $INSTALL_TYPE\n\nDados Preenchidos:\n\n1) Link do Admin do N8N: $dominioadmin\n2) Link do Webhook do N8N: $dominiowebhook\n3) Usuário do SMTP: $user_smtp\n4) Email Remetente do SMTP: $email_smtp\n5) Senha do Email SMTP: $senha\n5)Host do SMTP: $smtp\n6) Criar Stack no Portainer: $([ "$criar_portainer" == "0" ] && echo "0 (Editável)" || echo "1 (Não editável)")\n\nConfira e Tecle Enter para continuar. Na próxima etapa você poderá confirmar os dados ou corrigir, se necessário." \
    --fb 22 80
while true; do
{
  tput reset 2>/dev/null         # Reinicia o terminal de forma segura
  exec 0</dev/tty 1>/dev/tty 2>&1 # Força redirecionamentos explícitos
  sleep 0.01                     # Pausa microscópica para sincronia
  clear                          # Limpeza final antes do whiptail
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
        msg "Entrada inválida! Por favor, use apenas 'y' para sim ou 'n' para não. Digite Enter para continuar"
    fi
done

export NEWT_COLORS='
root=,white
window=,black
border=white,black
textbox=white,black
button=black,white
'  

{

echo -e "XXX\n5\nVERIFICANDO CONFIGURAÇÃO N8N EDITOR (ADMIN)... \nXXX"

if [ "$INSTALL_TYPE" = "TRADICIONAL" ] && [ "$criar_dns" = "0" ]; then
    echo -e "XXX\n10\nCONFIGURANDO DNS AUTOMÁTICO (TRADICIONAL)... \nXXX"
    
    DOMINIO_PRINCIPAL=$(echo "$dominioadmin" | cut -d'.' -f2-)
    SUBDOMINIO=${dominioadmin%%.$DOMINIO_PRINCIPAL}
    echo -e "XXX\n15\nVERIFICANDO REGISTROS EXISTENTES... \nXXX"
    EXISTING_RECORDS=$(curl -s -X GET \
        "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records?name=${dominioadmin}" \
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
        --data '{"type":"CNAME","name":"'${dominioadmin}'","content":"'${nome_servidor}'.'${DOMINIO_PRINCIPAL}'","ttl":1,"proxied":false}')

    if echo "$CNAME_RESPONSE" | grep -q '"success":true'; then
        echo -e "XXX\n30\nREGISTRO CNAME CRIADO COM SUCESSO! \nXXX"
    else
        echo -e "XXX\n30\nAVISO: ERRO AO CRIAR REGISTRO CNAME \nXXX"
    fi

elif [ "$INSTALL_TYPE" = "CLOUDFLARE_TUNNEL" ]; then
    echo -e "XXX\n10\nCONFIGURANDO CLOUDFLARE TUNNEL (DNS + ROTAS)... \nXXX"
    
    DOMINIO_PRINCIPAL=$(echo "$dominioadmin" | cut -d'.' -f2-)
    SUBDOMINIO=${dominioadmin%%.$DOMINIO_PRINCIPAL}
    echo -e "XXX\n15\nCONFIGURANDO REGISTRO DNS... \nXXX"
    EXISTING_RECORDS=$(curl -s -X GET \
        "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records?name=${dominioadmin}" \
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
        --data "{\"type\":\"CNAME\",\"name\":\"${dominioadmin}\",\"content\":\"${TUNNEL_ID}.cfargotunnel.com\",\"ttl\":1,\"proxied\":true}")

    if echo "$DNS_RESPONSE" | grep -q '"success":true'; then
        echo -e "XXX\n30\nREGISTRO DNS CRIADO COM SUCESSO! \nXXX"
    else
        echo -e "XXX\n30\nAVISO: ERRO AO CRIAR REGISTRO DNS \nXXX"
    fi
    echo -e "XXX\n35\nATUALIZANDO CONFIGURAÇÃO DO TUNNEL... \nXXX"
    NEW_SERVICE="http://${nome_app_editor}:5678"
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
    
    jq --arg host "$dominioadmin" --arg service "$NEW_SERVICE" '
      (.result.config // {}) as $cfg
      | ($cfg.ingress // []) as $ing
      # Remover entradas catch-all existentes no meio
      | ($ing | map(select(.service != "http_status:404"))) as $clean
      # Coletar hostnames existentes para evitar duplicatas
      
      # Se o novo host já existe, não adicionar duplicata; senão adicionar nova rota
      | ($clean | map(select(.hostname != $host))) as $filtered
      | ($filtered + [ { hostname: $host, service: $service, originRequest: { noTlsVerify: true, httpHostHeader: $host } } ]) as $merged
      # Adicionar exatamente um catch-all
      | ($merged + [{ service: "http_status:404" }]) as $final_ing
      # Construir novo objeto de configuração, preservando outras chaves
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
    if nslookup "$dominioadmin" >/dev/null 2>&1; then
        echo -e "XXX\n15\nDNS CONFIGURADO \nXXX"
    else
        echo -e "XXX\n15\nAVISO: VERIFIQUE A CONFIGURAÇÃO DNS \nXXX"
    fi
fi


if [ "$INSTALL_TYPE" = "TRADICIONAL" ] && [ "$criar_dns" = "1" ]; then

ip_servidor=$(curl -s --max-time 10 ipinfo.io/ip)

echo -e "XXX\n3\nVERIFICANDO SUBDOMÍNIO: $dominioadmin \nXXX"
sleep 3
tentativas=5
tentativa_atual=1
sucesso=0
while [ $tentativa_atual -le $tentativas ]; do
    echo -e "XXX\n$(( (tentativa_atual * 12) / tentativas + 3 ))\nTentativa $tentativa_atual de $tentativas...\nXXX"
    
    dns_ip1=$(timeout 10 nslookup -type=A "$dominioadmin" | grep -E "Address: [0-9]+\." | awk '{print $2}' | head -n1)
    
    if [[ -n "$dns_ip1" && "$dns_ip1" == "$ip_servidor" ]]; then
        sucesso=1
    fi
  sleep 1
    ((tentativa_atual++))
done
if [ $sucesso -eq 0 ]; then
    echo -e "XXX\n10\nERRO: SUBDOMÍNIO DO N8N Editor NÃO APONTA PARA O IP ($ip_servidor) \nXXX"
    sleep 3
    echo -e "XXX\n18\nERRO: DNS NÃO CONFIGURADO CORRETAMENTE \nXXX"
    sleep 3
    exit 1
fi
    echo -e "XXX\n18\nDOMÍNIO N8N Editor VERIFICADO COM SUCESSO \nXXX"
sleep 4
fi
echo -e "XXX\n5\nVERIFICANDO CONFIGURAÇÃO N8N Webhook... \nXXX"
if [ "$INSTALL_TYPE" = "TRADICIONAL" ] && [ "$criar_dns" = "0" ]; then
    echo -e "XXX\n10\nCONFIGURANDO DNS AUTOMÁTICO (TRADICIONAL)... \nXXX"   
    DOMINIO_PRINCIPAL=$(echo "$dominiowebhook" | cut -d'.' -f2-)
    SUBDOMINIO=${dominiowebhook%%.$DOMINIO_PRINCIPAL}
    echo -e "XXX\n15\nVERIFICANDO REGISTROS EXISTENTES... \nXXX"
    EXISTING_RECORDS=$(curl -s -X GET \
        "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records?name=${dominiowebhook}" \
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
        --data '{"type":"CNAME","name":"'${dominiowebhook}'","content":"'${nome_servidor}'.'${DOMINIO_PRINCIPAL}'","ttl":1,"proxied":false}')
    if echo "$CNAME_RESPONSE" | grep -q '"success":true'; then
        echo -e "XXX\n30\nREGISTRO CNAME CRIADO COM SUCESSO! \nXXX"
    else
        echo -e "XXX\n30\nAVISO: ERRO AO CRIAR REGISTRO CNAME \nXXX"
    fi

elif [ "$INSTALL_TYPE" = "CLOUDFLARE_TUNNEL" ]; then
    echo -e "XXX\n10\nCONFIGURANDO CLOUDFLARE TUNNEL (DNS + ROTAS)... \nXXX"   
    DOMINIO_PRINCIPAL=$(echo "$dominiowebhook" | cut -d'.' -f2-)
    SUBDOMINIO=${dominiowebhook%%.$DOMINIO_PRINCIPAL}
    echo -e "XXX\n15\nCONFIGURANDO REGISTRO DNS... \nXXX"
    EXISTING_RECORDS=$(curl -s -X GET \
        "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records?name=${dominiowebhook}" \
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
    --data "{\"type\":\"CNAME\",\"name\":\"${dominiowebhook}\",\"content\":\"${TUNNEL_ID}.cfargotunnel.com\",\"ttl\":1,\"proxied\":true}")

    if echo "$DNS_RESPONSE" | grep -q '"success":true'; then
        echo -e "XXX\n30\nREGISTRO DNS CRIADO COM SUCESSO! \nXXX"
    else
        echo -e "XXX\n30\nAVISO: ERRO AO CRIAR REGISTRO DNS \nXXX"
    fi
    echo -e "XXX\n35\nATUALIZANDO CONFIGURAÇÃO DO TUNNEL... \nXXX"
    NEW_SERVICE="http://${nome_app_webhook}:5678"
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
    jq --arg host "$dominiowebhook" --arg service "$NEW_SERVICE" '
      (.result.config // {}) as $cfg
      | ($cfg.ingress // []) as $ing
      # Remover entradas catch-all existentes no meio
      | ($ing | map(select(.service != "http_status:404"))) as $clean
      # Coletar hostnames existentes para evitar duplicatas
      
      # Se o novo host já existe, não adicionar duplicata; senão adicionar nova rota
      | ($clean | map(select(.hostname != $host))) as $filtered
      | ($filtered + [ { hostname: $host, service: $service, originRequest: { noTlsVerify: true, httpHostHeader: $host } } ]) as $merged
      # Adicionar exatamente um catch-all
      | ($merged + [{ service: "http_status:404" }]) as $final_ing
      # Construir novo objeto de configuração, preservando outras chaves
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
    echo -e "XXX\n65\nCONFIGURANDO ROTA MCP NO CLOUDFLARE TUNNEL... \nXXX"
    NEW_SERVICE_MCP="http://${nome_app_mcp_api}:5678"
    TIMESTAMP_MCP=$(date -u +%Y%m%dT%H%M%SZ)
    TMPDIR_MCP=$(mktemp -d)
    BACKUP_RAW_MCP="$TMPDIR_MCP/backup_raw_mcp.$TIMESTAMP_MCP.json"
    TO_PUT_MCP="$TMPDIR_MCP/to_put_mcp.$TIMESTAMP_MCP.json"
    echo -e "XXX\n67\nOBTENDO CONFIGURAÇÃO ATUAL DO TUNNEL PARA MCP... \nXXX"
    curl -sS -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
      "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/cfd_tunnel/$TUNNEL_ID/configurations" \
      | jq '.' > "$BACKUP_RAW_MCP"
    echo -e "XXX\n70\nCONFIGURANDO ROTA MCP... \nXXX"
    jq --arg host "$dominiowebhook" --arg service_mcp "$NEW_SERVICE_MCP" '
      (.result.config // {}) as $cfg
      | ($cfg.ingress // []) as $ing
      # Remover entradas catch-all existentes
      | ($ing | map(select(.service != "http_status:404"))) as $clean
      # Coletar hostnames e paths existentes para evitar duplicatas
      | ($clean | map("\(.hostname // "")|\(.path // "")")) as $existing_routes
      # Se a rota MCP já existe, não adicionar duplicata
      | (if ($existing_routes | index("\($host)|/mcp/*")) then $clean else 
          ($clean + [ 
            {
              hostname: $host,
              path: "/mcp/*",
              service: $service_mcp,
              originRequest: { 
                noTlsVerify: true, 
                httpHostHeader: $host
              }
            }
          ]) 
        end) as $with_mcp
      # Adicionar catch-all no final
      | ($with_mcp + [{ service: "http_status:404" }]) as $final_ing
      # Construir novo objeto de configuração
      | ($cfg + { ingress: $final_ing }) as $newcfg
      | { config: $newcfg }
    ' "$BACKUP_RAW_MCP" > "$TO_PUT_MCP"
    echo -e "XXX\n73\nAPLICANDO CONFIGURAÇÃO MCP NO TUNNEL... \nXXX"
    APPLY_RESPONSE_MCP=$(curl -sS -X PUT "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/cfd_tunnel/$TUNNEL_ID/configurations" \
      -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
      -H "Content-Type: application/json" \
      --data-binary @"$TO_PUT_MCP")

    if echo "$APPLY_RESPONSE_MCP" | grep -q '"success":true'; then
        echo -e "XXX\n75\nROTA MCP CONFIGURADA COM SUCESSO! \nXXX"
    else
        echo -e "XXX\n75\nAVISO: ERRO AO CONFIGURAR ROTA MCP \nXXX"
    fi
    rm -rf "$TMPDIR_MCP"
 else
    echo -e "XXX\n10\nVERIFICANDO CONFIGURAÇÃO (TRADICIONAL SEM AUTOMAÇÃO)... \nXXX"
    if nslookup "$dominiowebhook" >/dev/null 2>&1; then
        echo -e "XXX\n15\nDNS CONFIGURADO \nXXX"
    else
        echo -e "XXX\n15\nAVISO: VERIFIQUE A CONFIGURAÇÃO DNS \nXXX"
    fi
fi
if [ "$INSTALL_TYPE" = "TRADICIONAL" ] && [ "$criar_dns" = "1" ]; then
ip_servidor=$(curl -s --max-time 10 ipinfo.io/ip)
echo -e "XXX\n3\nVERIFICANDO SUBDOMÍNIO: $dominiowebhook \nXXX"
sleep 3
tentativas=5
tentativa_atual=1
sucesso=0
while [ $tentativa_atual -le $tentativas ]; do
    echo -e "XXX\n$(( (tentativa_atual * 12) / tentativas + 3 ))\nTentativa $tentativa_atual de $tentativas...\nXXX"
    dns_ip2=$(timeout 10 nslookup -type=A "$dominiowebhook" | grep -E "Address: [0-9]+\." | awk '{print $2}' | head -n1)
    if [[ -n "$dns_ip2" && "$dns_ip2" == "$ip_servidor" ]]; then
        sucesso=1
    fi
  sleep 1
    ((tentativa_atual++))
done

if [ $sucesso -eq 0 ]; then

    echo -e "XXX\n10\nERRO: SUBDOMÍNIO DO N8N Webhook NÃO APONTA PARA O IP ($ip_servidor) \nXXX"
    sleep 3
    echo -e "XXX\n18\nERRO: DNS NÃO CONFIGURADO CORRETAMENTE \nXXX"
    sleep 3
    exit 1
fi
    echo -e "XXX\n18\nDOMÍNIO DO N8N Webhook VERIFICADO COM SUCESSO \nXXX"
sleep 4
fi


echo -e "XXX\n23\nCRIANDO STACKS DO N8N e REDIS 1/4 \nXXX"
sleep 1
cd
cd
clear

cat > $nome_app_database-redis.yaml << EOL

version: "3.7"

services:
  $nome_app_database-redis:
    image: redis:latest
    command: [
        "redis-server",
        "--appendonly",
        "yes",
        "--port",
        "6379"
      ]
    volumes:
      - $nome_app_database-redis-data:/data

    networks: 
      - externa
      - interna
    deploy:
      placement:
        constraints:
          - node.role == manager
     # resources:
      #  limits:
        #  cpus: "0.5"
        #  memory: 1024M

volumes:
  $nome_app_database-redis-data:
    external: true
    name: $nome_app_database-redis-data


networks: 
  externa: 
    external: true
  interna: 
    external: true


EOL
if [[ "$criar_portainer" == "0" ]]; then
    echo -e "XXX\n26\nCRIANDO STACK NO PORTAINER 3/4  \nXXX"
dados_file="$HOME/dados_portainer/dados_portainer"
if [[ -f "$dados_file" ]]; then
PORTAINER_URL=$(grep "Dominio do portainer:" "$dados_file" | cut -d':' -f2 | xargs)
ADMIN_USERNAME=$(grep "Usuario:" "$dados_file" | cut -d':' -f2 | xargs)
ADMIN_PASSWORD=$(grep "Senha:" "$dados_file" | cut -d':' -f2 | xargs)
STACK_NAME=$nome_app_database-redis
STACK_FILE_PATH="/root/$nome_app_database-redis.yaml"

else
    sleep 5
echo -e "XXX\n27\nSEM ARQUIVO DE DADOS DO PORTAINER 3/4  \nXXX"
docker stack deploy --prune --resolve-image always -c $nome_app_database-redis.yaml $nome_app_database-redis >/dev/null 2>&1
sleep 5
    exit 1
fi
get_auth_token() {
    echo -e "XXX\n28\nAUTENTICANDO NO PORTAINER... 3/4  \nXXX"
    RESPONSE=$(curl -sS -X POST "https://$PORTAINER_URL/api/auth" \
        -H "Content-Type: application/json" \
        -d "{\"username\": \"$ADMIN_USERNAME\", \"password\": \"$ADMIN_PASSWORD\"}")
    TOKEN=$(echo "$RESPONSE" | jq -r '.jwt')
    if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]; then
        echo -e "XXX\n29\nFALHA NA AUTENTICAÇÃO.. 3/4  \nXXX"
sleep 5
echo -e "XXX\n30\nREVERTENDO E CRIANDO STACK PELO SERVIDOR 3/4  \nXXX"
docker stack deploy --prune --resolve-image always -c $nome_app_database-redis.yaml $nome_app_database-redis >/dev/null 2>&1
sleep 5
        exit 1
    fi
 echo -e "XXX\n31\n[SUCESSO] AUTENTICAÇÃO OK 3/4  \nXXX"
}
get_endpoint_id() {
    echo -e "XXX\n32\n[INFO] OBTENDO ENDPOINTID 3/4  \nXXX"
    RESPONSE=$(curl -sS -X GET "https://$PORTAINER_URL/api/endpoints" \
        -H "Authorization: Bearer $TOKEN")
    ENDPOINT_ID=$(echo "$RESPONSE" | jq -r '.[0].Id')
    if [ -z "$ENDPOINT_ID" ] || [ "$ENDPOINT_ID" = "null" ]; then
        echo -e "XXX\n33\n[ERRO] ENDPOINTID NÃO ENCONTRADO 3/4  \nXXX"
        docker stack deploy --prune --resolve-image always -c $nome_app_database-redis.yaml $nome_app_database-redis >/dev/null 2>&1
        exit 1
    fi
     echo -e "XXX\n34\n[SUCESSO] ENDPOINTID OBTIDO: $ENDPOINT_ID  3/4  \nXXX"
}
get_swarm_id() {
    echo -e "XXX\n35\n[INFO] OBTENDO SWARMID  3/4  \nXXX"
    RESPONSE=$(curl -sS -X GET "https://$PORTAINER_URL/api/endpoints/$ENDPOINT_ID/docker/swarm" \
        -H "Authorization: Bearer $TOKEN")
    SWARM_ID=$(echo "$RESPONSE" | jq -r '.ID')
    if [ -z "$SWARM_ID" ] || [ "$SWARM_ID" = "null" ]; then
        echo -e "XXX\n36\n[ERRO] SWARMID NÃO ENCONTRADO 3/4  \nXXX"
        docker stack deploy --prune --resolve-image always -c $nome_app_database-redis.yaml $nome_app_database-redis >/dev/null 2>&1
        exit 1
    fi
    echo -e "XXX\n37\n[SUCESSO] SWARMID OBTIDO: $SWARM_ID  3/4  \nXXX"
}
create_stack() {
    echo -e "XXX\n38\n[INFO] VERIFICANDO SE YAML EXISTE 3/4  \nXXX"
    if [ ! -f "$STACK_FILE_PATH" ]; then
        echo -e "XXX\n39\n[ERRO] ARQUIVO $STACK_FILE_PATH NÃO ENCONTRADO 3/4  \nXXX"
        docker stack deploy --prune --resolve-image always -c $nome_app_database-redis.yaml $nome_app_database-redis >/dev/null 2>&1
        exit 1
    fi
     echo -e "XXX\n40\n[INFO] CRIANDO STACK $STACK_NAME NO PORTAINER 3/4  \nXXX"
    response_output=$(mktemp)
    erro_output=$(mktemp)
    http_code=$(curl -s -o "$response_output" -w "%{http_code}"  -X POST \
        -H "Authorization: Bearer $TOKEN" \
        -F "Name=$STACK_NAME" \
        -F "file=@$STACK_FILE_PATH" \
        -F "SwarmID=$SWARM_ID" \
        -F "endpointId=$ENDPOINT_ID" \
        "https://$PORTAINER_URL/api/stacks/create/swarm/file" 2> "$erro_output")
    response=$(cat "$response_output")
    rm -f "$response_output" "$erro_output"
    if [ "$http_code" -ne 200 ]; then
        echo -e "XXX\n41\n[ERRO] ERRO AO CRIAR STACK 3/4  \nXXX"
        docker stack deploy --prune --resolve-image always -c $nome_app_database-redis.yaml $nome_app_database-redis >/dev/null 2>&1
        exit 1
    fi
    echo -e "XXX\n42\n[SUCESSO] STACK $STACK_NAME  CRIADA COM SUCESSO 3/4  \nXXX"
}
get_auth_token || exit 1
get_endpoint_id || exit 1
get_swarm_id || exit 1
create_stack || exit 1
elif [[ "$criar_portainer" == "1" ]]; then
    echo "Criando a stack diretamente no Docker (não editável no Portainer)."
    docker stack deploy --prune --resolve-image always -c $nome_app_database-redis.yaml $nome_app_database-redis >/dev/null 2>&1
else
    echo -e "XXX\n43\n[ERRO] ERRO INESPERADO PARA CRIAR STACK NO PORTAINER 3/4  \nXXX"
    sleep 5
    echo -e "XXX\n44\nREVERTENDO E CRIANDO STACK PELO SERVIDOR 3/4  \nXXX"
docker stack deploy --prune --resolve-image always -c $nome_app_database-redis.yaml $nome_app_database-redis >/dev/null 2>&1
sleep 5

    exit 1
fi
echo -e "XXX\n25\nFAZENDO O BUILD DOS STACKS DO N8N 2/4 \nXXX"
sleep 1
echo -e "XXX\n26\nFAZENDO O BUILD DOS STACKS DO N8N 2/4 - CONCLUIDO \nXXX"
sleep 1
echo -e "XXX\n27\nCRIANDO BANCO DE DADOS DO N8N 3/4 \nXXX"
sleep 1
echo -e "XXX\n28\nCRIANDO BANCO DE DADOS DO N8N 3/4 - CONCLUIDO \nXXX"
cd
cd
encryption_key=$(openssl rand -hex 16)
encryption_key2=$(openssl rand -hex 16)
cat > $nome_app_editor.yaml << EOL

version: "3.7"
# Definição dos Serviços
services:
  # Definição do Serviço do Editor
  $nome_app_editor:
    # imagem do docker
    image: n8nio/n8n:2.9.2
    # Define o hotname do container
    hostname: "$nome_app_editor"
    # comando padrão para subir o servidor web do editor
    command: start
    # configura a rede do serviço
    networks:
      - traefik_public
      - app_network
      - interna
      - externa
    # configura as variáveis de ambiente
    environment:
      #########################################################
      # Documentação de Variáveis de Ambiente do N8N ##########
      # https://docs.n8n.io/hosting/environment-variables/environment-variables/
 
      # Configuração Gerais do N8N ############################
     
      # Gere uma nova chave aqui https://www.avast.com/random-password-generator#mac
      - N8N_ENCRYPTION_KEY=$encryption_key
      # Configura o ambiente de execução do N8N
      - NODE_ENV=production
      # Habilita a Página de Métricas Públicas do N8N
      - N8N_METRICS=true
      # Habilita o envio de diagnósticos para o N8N
      - N8N_DIAGNOSTICS_ENABLED=false
      # Configura o Tamanho do Payload aceito pelo N8N (em MB)
      - N8N_PAYLOAD_SIZE_MAX=16
      # Configura o nível de log do N8N
      - N8N_LOG_LEVEL=info
      # Configura o Timezone do N8N
      - GENERIC_TIMEZONE=America/Sao_Paulo
      # Configura a Permissão do Arquivo de Configuração
      - N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS=true
      # Configuração de Execução dos Workflows ################
      - N8N_RUNNERS_ENABLED=true
      # Habilita o modo de execução externa
      - N8N_RUNNERS_MODE=external
      # Configura o endereço do broker para ouvir de qualquer
      # endereço na rede do swarm
      - N8N_RUNNERS_BROKER_LISTEN_ADDRESS=0.0.0.0
      # Configura o token de autenticação
      - N8N_RUNNERS_AUTH_TOKEN=$encryption_key2
      # Habilita o uso do Python nativo
      - N8N_NATIVE_PYTHON_RUNNER=true
      # Envia as execuções de teste para os workers
      - OFFLOAD_MANUAL_EXECUTIONS_TO_WORKERS=true
      # Configuração do Banco de Dados ########################
      # Define o Tipo de Banco de Dados para Postgres
      - DB_TYPE=postgresdb
      # Configura o Nome do Banco de Dados
      - DB_POSTGRESDB_DATABASE=$nome_app_database
      # Configura o Host do Banco de Dados
      - DB_POSTGRESDB_HOST=postgres
      # Configura a Porta do Banco de Dados
      - DB_POSTGRESDB_PORT=5432
      # Configura o Usuário do Banco de Dados
      - DB_POSTGRESDB_USER=postgres
      # Configura a Senha do Banco de Dados
      - DB_POSTGRESDB_PASSWORD=$postgres_password
      # Configuração do Endereço do N8N #######################
      # Define a Porta http para o N8N (padrão: 5678)
      - N8N_PORT=5678
      # Configura o Host do Editor do N8N
      - N8N_HOST=$dominioadmin
      # Configura o Endereço competo do Editor (tem que deixar / no final)
      - N8N_EDITOR_BASE_URL=https://$dominioadmin/
      # Força o uso de SSL nas URL internas do N8N
      - N8N_PROTOCOL=https
      # Configura o Endereço do Webhook
      # Pode ser subdomínio ou outro domínio
      - WEBHOOK_URL=https://$dominiowebhook/
      # Configura o Caminho do Webhook
      - N8N_ENDPOINT_WEBHOOK=webhook
      # Configuração da Modo de Execução do N8N (fila) ########
      - EXECUTIONS_MODE=queue
      # Configura o host do Redis
      - QUEUE_BULL_REDIS_HOST=$nome_app_database-redis
      # Configura a porta do Redis
      - QUEUE_BULL_REDIS_PORT=6379
      # Configura o indice do banco de dados do Redis
      - QUEUE_BULL_REDIS_DB=2
      # Configura a senha do Redis (caso você use senha no redis)
      # - QUEUE_BULL_REDIS_PASSWORD=SENHA
      # Configura o tempo sugerido de execução de um Job na fila (-1 para ficar sem limite)
      - EXECUTIONS_TIMEOUT=3600 # (1 hora)
      # Configura o tempo máximo de execução de um Job na fila (-1 para ficar sem limite)
      - EXECUTIONS_TIMEOUT_MAX=7200 # (2 horas)
      # Configuração da Interface do N8N ######################
      # Habilita as notificações de novas versões do N8N
      - N8N_VERSION_NOTIFICATIONS_ENABLED=true
      # Configura o N8N para exibir a documentação da API Pública
      - N8N_PUBLIC_API_SWAGGERUI_DISABLED=false
      # Habilita os Templates na Interface do N8N
      - N8N_TEMPLATES_ENABLED=true
      # Habilita dicas de integração ao criar um novo fluxo de trabalho (true = desabilitado)
      - N8N_ONBOARDING_FLOW_DISABLED=true
      # Desabilita o recurso de tags de workflows (false = habilitado)
      - N8N_WORKFLOW_TAGS_DISABLED=false
      # Oculta a Tela de Informações de Uso do N8N
      - N8N_HIDE_USAGE_PAGE=false
      # Configuração da Manutenção e Limpeza do N8N ###########
      # https://docs.n8n.io/hosting/scaling/execution-data/
      # Configura a limpeza dos dados de execução
      - EXECUTIONS_DATA_PRUNE=true
      # Configura o tempo máximo de armazenamento dos dados de execução
      - EXECUTIONS_DATA_MAX_AGE=336 # 2 semanas
      # Com que frequência (minutos) os dados de execução devem ser excluídos permanentemente.
      - EXECUTIONS_DATA_PRUNE_HARD_DELETE_INTERVAL=15
      # Com que frequência (minutos) os dados de execução devem ser excluídos de forma reversível.
      - EXECUTIONS_DATA_PRUNE_SOFT_DELETE_INTERVAL=60
      # Quantidade de Execuções para armazenar antes de excluir
      - EXECUTIONS_DATA_PRUNE_MAX_COUNT=10000
      ######################## opcional #######################
      # Salvar execuções que terminam em erros (all = salvar, none = não salvar)
      - EXECUTIONS_DATA_SAVE_ON_ERROR=all
      # Salve execuções bem-sucedidas (all = salvar, none = não salvar)
      - EXECUTIONS_DATA_SAVE_ON_SUCCESS=all
      # Não salve o progresso do nó para cada execução (true = savar, false = não salvar)
      - EXECUTIONS_DATA_SAVE_ON_PROGRESS=true
      # Não salve execuções iniciadas manualmente (true = savar, false = não salvar)
      - EXECUTIONS_DATA_SAVE_MANUAL_EXECUTIONS=true
      # Configuração de Bibliotecas do N8N ####################
      # Configura quais bibliotecas nativas podem ser importardas no node Code
      - NODE_FUNCTION_ALLOW_BUILTIN=*
      # Configura as bibliotecas externas que serão utilizadas
      - NODE_FUNCTION_ALLOW_EXTERNAL=lodash
      # Habilita o uso de pacotes da comunidade
      - N8N_COMMUNITY_PACKAGES_ENABLED=true
      # Reinstalar os Community Nodes
      - N8N_REINSTALL_MISSING_PACKAGES=true
      # Configura o caminho dos nodes customizados
      - N8N_NODE_PATH=/home/node/.n8n/nodes

      # Configuração de IA ####################################

      # Configura quais bibliotecas nativas podem ser importardas no node Code
      - N8N_AI_ENABLED=false
      # Configura as bibliotecas externas que serão utilizadas
      - N8N_AI_PROVIDER=openai
      # Habilita o uso de pacotes da comunidade
      - N8N_AI_OPENAI_API_KEY=

      # Configuração dos E-mails (Multi-user) #################

      # Modo de envio de e-mail
      - N8N_EMAIL_MODE=smtp
      # Configura o Host do SMTP
      - N8N_SMTP_HOST=$smtp
      # Configura a Porta do SMTP
      - N8N_SMTP_PORT=$portasmtp
      # Configura o Usuário do SMTP
      - N8N_SMTP_USER=$user_smtp
      # Configura a Senha do SMTP
      - N8N_SMTP_PASS=$senha
      # Configura o E-mail de envio
      - N8N_SMTP_SENDER=$email_smtp
      # Configura o SSL do SMTP
      - N8N_SMTP_SSL=$SECURE
      # Report de Erros Sentry
      # - N8N_SENTRY_DSN=
      # - N8N_FRONTEND_SENTRY_DSN=
      #########################################################
      # Mudanças da versão 2.0
      #########################################################
      #########################################################
      # Desabilita o acesso a variáveis de ambiente dentro dos nodes (true = desabilitado, false = habilitado)
      - N8N_BLOCK_ENV_ACCESS_IN_NODE=false
      # Configira um array com os nodes a serem removidos do n8n
      - NODES_EXCLUDE="[]"
      # Permitir acesso sem autenticação para endpoints de retorno de chamada OAuth
      - N8N_SKIP_AUTH_ON_OAUTH_CALLBACK=false
      # Local padrão para acesso a arquivos sem restrição
      - N8N_RESTRICT_FILE_ACCESS_TO=~/.n8n-files
      # Modo de armazenamento de dados binários
      - N8N_DEFAULT_BINARY_DATA_MODE=default
    deploy:
      # O editor será executado no modo de replicação
      mode: replicated
      # Vamos ter apenas uma instância do editor
      replicas: 1
      # Configura o local de execução
      placement:
        constraints:
          # Você pode rodar o Editor no Manager mesmo pois usa poucos recursos
          - node.role == manager
          # - node.hostname == worker1
          # - node.labels.app == http # nome do label: app, valor do label: http
      # Limitação
      resources:
        # Definição dos Limites de Recursos deste Serviço
        limits:
          # Define a quantidade de CPU para o N8N para evitar travamento do Host
          cpus: "1"
          # Define a quantidade de RAM para o N8N para evitar travamento do Host
          memory: 1024M
      # Define os Labels do Serviço
EOL
if [ "$INSTALL_TYPE" = "TRADICIONAL" ]; then
cat >> $nome_app_editor.yaml << EOL
      labels:
        # Configura o Roteamento do Traefik
        - traefik.enable=true
        # Define o enderço do Editor do N8N
        - traefik.http.routers.$nome_app_editor.rule=Host(\`$dominioadmin\`)
        # Redireciona o endereço para HTTPS
        - traefik.http.routers.$nome_app_editor.entrypoints=websecure
        # Define o certificado SSL
        - traefik.http.routers.$nome_app_editor.tls.certresolver=letsencryptresolver
        # Define o serviço do Editor
        - traefik.http.routers.$nome_app_editor.service=$nome_app_editor
        # Define a porta do serviço do Editor
        - traefik.http.services.$nome_app_editor.loadbalancer.server.port=5678
        # Define o uso do Host Header
        - traefik.http.services.$nome_app_editor.loadbalancer.passHostHeader=true
        
EOL
fi
cat >> $nome_app_editor.yaml << EOL
      # Configura o modo de atualização do serviço
      update_config:
        # Configura o paralelismo de atualização
        parallelism: 1
        # Configura o tempo de espera entre as atualizações
        delay: 30s
        # Configura a ação em caso de falha
        order: start-first
        # Configura a ação em caso de falha
        failure_action: rollback

    
networks:
  traefik_public:
    external: true
    name: externa
  app_network:
    external: true
    name: interna


  interna:
    external: true
  externa:
    external: true
    
EOL
if [[ "$criar_portainer" == "0" ]]; then
    echo -e "XXX\n29\nCRIANDO STACK NO PORTAINER 3/4  \nXXX"
dados_file="$HOME/dados_portainer/dados_portainer"
if [[ -f "$dados_file" ]]; then
PORTAINER_URL=$(grep "Dominio do portainer:" "$dados_file" | cut -d':' -f2 | xargs)
ADMIN_USERNAME=$(grep "Usuario:" "$dados_file" | cut -d':' -f2 | xargs)
ADMIN_PASSWORD=$(grep "Senha:" "$dados_file" | cut -d':' -f2 | xargs)
STACK_NAME=$nome_app_editor
STACK_FILE_PATH="/root/$nome_app_editor.yaml"

else
    sleep 5
echo -e "XXX\n30\nSEM ARQUIVO DE DADOS DO PORTAINER 3/4  \nXXX"
docker stack deploy --prune --resolve-image always -c $nome_app_editor.yaml $nome_app_editor >/dev/null 2>&1
sleep 5
    exit 1
fi
get_auth_token() {
    echo -e "XXX\n31\nAUTENTICANDO NO PORTAINER... 3/4  \nXXX"
    RESPONSE=$(curl -sS -X POST "https://$PORTAINER_URL/api/auth" \
        -H "Content-Type: application/json" \
        -d "{\"username\": \"$ADMIN_USERNAME\", \"password\": \"$ADMIN_PASSWORD\"}")
    TOKEN=$(echo "$RESPONSE" | jq -r '.jwt')
    if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]; then
        echo -e "XXX\n32\nFALHA NA AUTENTICAÇÃO.. 3/4  \nXXX"
sleep 5
echo -e "XXX\n33\nREVERTENDO E CRIANDO STACK PELO SERVIDOR 3/4  \nXXX"
docker stack deploy --prune --resolve-image always -c $nome_app_editor.yaml $nome_app_editor >/dev/null 2>&1
sleep 5
        exit 1
    fi
 echo -e "XXX\n34\n[SUCESSO] AUTENTICAÇÃO OK 3/4  \nXXX"
}
get_endpoint_id() {
    echo -e "XXX\n35\n[INFO] OBTENDO ENDPOINTID 3/4  \nXXX"
    RESPONSE=$(curl -sS -X GET "https://$PORTAINER_URL/api/endpoints" \
        -H "Authorization: Bearer $TOKEN")
    ENDPOINT_ID=$(echo "$RESPONSE" | jq -r '.[0].Id')
    if [ -z "$ENDPOINT_ID" ] || [ "$ENDPOINT_ID" = "null" ]; then
        echo -e "XXX\n36\n[ERRO] ENDPOINTID NÃO ENCONTRADO 3/4  \nXXX"
        docker stack deploy --prune --resolve-image always -c $nome_app_editor.yaml $nome_app_editor >/dev/null 2>&1
        exit 1
    fi
     echo -e "XXX\n37\n[SUCESSO] ENDPOINTID OBTIDO: $ENDPOINT_ID  3/4  \nXXX"
}
get_swarm_id() {
    echo -e "XXX\n38\n[INFO] OBTENDO SWARMID  3/4  \nXXX"
    RESPONSE=$(curl -sS -X GET "https://$PORTAINER_URL/api/endpoints/$ENDPOINT_ID/docker/swarm" \
        -H "Authorization: Bearer $TOKEN")
    SWARM_ID=$(echo "$RESPONSE" | jq -r '.ID')
    if [ -z "$SWARM_ID" ] || [ "$SWARM_ID" = "null" ]; then
        echo -e "XXX\n39\n[ERRO] SWARMID NÃO ENCONTRADO 3/4  \nXXX"
        docker stack deploy --prune --resolve-image always -c $nome_app_editor.yaml $nome_app_editor >/dev/null 2>&1
        exit 1
    fi
    echo -e "XXX\n40\n[SUCESSO] SWARMID OBTIDO: $SWARM_ID  3/4  \nXXX"
}
create_stack() {
    echo -e "XXX\n41\n[INFO] VERIFICANDO SE YAML EXISTE 3/4  \nXXX"
    if [ ! -f "$STACK_FILE_PATH" ]; then
        echo -e "XXX\n42\n[ERRO] ARQUIVO $STACK_FILE_PATH NÃO ENCONTRADO 3/4  \nXXX"
        docker stack deploy --prune --resolve-image always -c $nome_app_editor.yaml $nome_app_editor >/dev/null 2>&1
        exit 1
    fi
     echo -e "XXX\n43\n[INFO] CRIANDO STACK $STACK_NAME NO PORTAINER 3/4  \nXXX"
    response_output=$(mktemp)
    erro_output=$(mktemp)

    http_code=$(curl -s -o "$response_output" -w "%{http_code}"  -X POST \
        -H "Authorization: Bearer $TOKEN" \
        -F "Name=$STACK_NAME" \
        -F "file=@$STACK_FILE_PATH" \
        -F "SwarmID=$SWARM_ID" \
        -F "endpointId=$ENDPOINT_ID" \
        "https://$PORTAINER_URL/api/stacks/create/swarm/file" 2> "$erro_output")

    response=$(cat "$response_output")
    rm -f "$response_output" "$erro_output"
    if [ "$http_code" -ne 200 ]; then
        echo -e "XXX\n44\n[ERRO] ERRO AO CRIAR STACK 3/4  \nXXX"
        docker stack deploy --prune --resolve-image always -c $nome_app_editor.yaml $nome_app_editor >/dev/null 2>&1
        exit 1
    fi
    echo -e "XXX\n45\n[SUCESSO] STACK $STACK_NAME  CRIADA COM SUCESSO 3/4  \nXXX"
}
get_auth_token || exit 1
get_endpoint_id || exit 1
get_swarm_id || exit 1
create_stack || exit 1
elif [[ "$criar_portainer" == "1" ]]; then
    echo "Criando a stack diretamente no Docker (não editável no Portainer)."
    docker stack deploy --prune --resolve-image always -c $nome_app_editor.yaml $nome_app_editor >/dev/null 2>&1
else
    echo -e "XXX\n46\n[ERRO] ERRO INESPERADO PARA CRIAR STACK NO PORTAINER 3/4  \nXXX"
    sleep 5
    echo -e "XXX\n47\nREVERTENDO E CRIANDO STACK PELO SERVIDOR 3/4  \nXXX"
docker stack deploy --prune --resolve-image always -c $nome_app_editor.yaml $nome_app_editor >/dev/null 2>&1
sleep 5

    exit 1
fi
clear

cd

cd
clear

cat > $nome_app_webhook.yaml << EOL

version: "3.7"
# Definição dos Serviços
services:
  # Definição do Serviço do Worker
  $nome_app_webhook:
    # imagem do docker
    image: n8nio/n8n:2.9.2
    # Define o hotname do container
    hostname: "$nome_app_webhook"
    # comando padrão para subir o servidor web
    command: webhook
    # configura a rede do serviço
    networks:
      - traefik_public
      - app_network
      - interna
      - externa
    # configura as variáveis de ambiente
    environment:
      #########################################################
      # Documentação de Variáveis de Ambiente do N8N ##########
      # https://docs.n8n.io/hosting/environment-variables/environment-variables/
 
      # Configuração Gerais do N8N ############################
     
      # Gere uma nova chave aqui https://www.avast.com/random-password-generator#mac
      - N8N_ENCRYPTION_KEY=$encryption_key
      # Configura o ambiente de execução do N8N
      - NODE_ENV=production
      # Habilita a Página de Métricas Públicas do N8N
      - N8N_METRICS=true
      # Habilita o envio de diagnósticos para o N8N
      - N8N_DIAGNOSTICS_ENABLED=false
      # Configura o Tamanho do Payload aceito pelo N8N (em MB)
      - N8N_PAYLOAD_SIZE_MAX=16
      # Configura o nível de log do N8N
      - N8N_LOG_LEVEL=info
      # Configura o Timezone do N8N
      - GENERIC_TIMEZONE=America/Sao_Paulo
      # Configura a Permissão do Arquivo de Configuração
      - N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS=true

      # Configuração de Execução dos Workflows ################

      - N8N_RUNNERS_ENABLED=true
      # Habilita o modo de execução externa
      - N8N_RUNNERS_MODE=external
      # Configura o endereço do broker para ouvir de qualquer
      # endereço na rede do swarm
      - N8N_RUNNERS_BROKER_LISTEN_ADDRESS=0.0.0.0
      # Configura o token de autenticação
      - N8N_RUNNERS_AUTH_TOKEN=$encryption_key2
      # Habilita o uso do Python nativo
      - N8N_NATIVE_PYTHON_RUNNER=true
      # Envia as execuções de teste para os workers
      - OFFLOAD_MANUAL_EXECUTIONS_TO_WORKERS=true

      # Configuração do Banco de Dados ########################

      # Define o Tipo de Banco de Dados para Postgres
      - DB_TYPE=postgresdb
      # Configura o Nome do Banco de Dados
      - DB_POSTGRESDB_DATABASE=$nome_app_database
      # Configura o Host do Banco de Dados
      - DB_POSTGRESDB_HOST=postgres
      # Configura a Porta do Banco de Dados
      - DB_POSTGRESDB_PORT=5432
      # Configura o Usuário do Banco de Dados
      - DB_POSTGRESDB_USER=postgres
      # Configura a Senha do Banco de Dados
      - DB_POSTGRESDB_PASSWORD=$postgres_password

      # Configuração do Endereço do N8N #######################

      # Define a Porta http para o N8N (padrão: 5678)
      - N8N_PORT=5678
      # Configura o Host do Editor do N8N
      - N8N_HOST=$dominioadmin
      # Configura o Endereço competo do Editor (tem que deixar / no final)
      - N8N_EDITOR_BASE_URL=https://$dominioadmin/
      # Força o uso de SSL nas URL internas do N8N
      - N8N_PROTOCOL=https
      # Configura o Endereço do Webhook
      # Pode ser subdomínio ou outro domínio
      - WEBHOOK_URL=https://$dominiowebhook/
      # Configura o Caminho do Webhook
      - N8N_ENDPOINT_WEBHOOK=webhook

      # Configuração da Modo de Execução do N8N (fila) ########

      - EXECUTIONS_MODE=queue
      # Configura o host do Redis
      - QUEUE_BULL_REDIS_HOST=$nome_app_database-redis
      # Configura a porta do Redis
      - QUEUE_BULL_REDIS_PORT=6379
      # Configura o indice do banco de dados do Redis
      - QUEUE_BULL_REDIS_DB=2
      # Configura a senha do Redis (caso você use senha no redis)
      # - QUEUE_BULL_REDIS_PASSWORD=SENHA
      # Configura o tempo sugerido de execução de um Job na fila (-1 para ficar sem limite)
      - EXECUTIONS_TIMEOUT=3600 # (1 hora)
      # Configura o tempo máximo de execução de um Job na fila (-1 para ficar sem limite)
      - EXECUTIONS_TIMEOUT_MAX=7200 # (2 horas)

      # Configuração da Interface do N8N ######################

      # Habilita as notificações de novas versões do N8N
      - N8N_VERSION_NOTIFICATIONS_ENABLED=true
      # Configura o N8N para exibir a documentação da API Pública
      - N8N_PUBLIC_API_SWAGGERUI_DISABLED=false
      # Habilita os Templates na Interface do N8N
      - N8N_TEMPLATES_ENABLED=true
      # Habilita dicas de integração ao criar um novo fluxo de trabalho (true = desabilitado)
      - N8N_ONBOARDING_FLOW_DISABLED=true
      # Desabilita o recurso de tags de workflows (false = habilitado)
      - N8N_WORKFLOW_TAGS_DISABLED=false
      # Oculta a Tela de Informações de Uso do N8N
      - N8N_HIDE_USAGE_PAGE=false

      # Configuração da Manutenção e Limpeza do N8N ###########
      # https://docs.n8n.io/hosting/scaling/execution-data/

      # Configura a limpeza dos dados de execução
      - EXECUTIONS_DATA_PRUNE=true
      # Configura o tempo máximo de armazenamento dos dados de execução
      - EXECUTIONS_DATA_MAX_AGE=336 # 2 semanas
      # Com que frequência (minutos) os dados de execução devem ser excluídos permanentemente.
      - EXECUTIONS_DATA_PRUNE_HARD_DELETE_INTERVAL=15
      # Com que frequência (minutos) os dados de execução devem ser excluídos de forma reversível.
      - EXECUTIONS_DATA_PRUNE_SOFT_DELETE_INTERVAL=60
      # Quantidade de Execuções para armazenar antes de excluir
      - EXECUTIONS_DATA_PRUNE_MAX_COUNT=10000
      ######################## opcional #######################
      # Salvar execuções que terminam em erros (all = salvar, none = não salvar)
      - EXECUTIONS_DATA_SAVE_ON_ERROR=all
      # Salve execuções bem-sucedidas (all = salvar, none = não salvar)
      - EXECUTIONS_DATA_SAVE_ON_SUCCESS=all
      # Não salve o progresso do nó para cada execução (true = savar, false = não salvar)
      - EXECUTIONS_DATA_SAVE_ON_PROGRESS=true
      # Não salve execuções iniciadas manualmente (true = savar, false = não salvar)
      - EXECUTIONS_DATA_SAVE_MANUAL_EXECUTIONS=true

      # Configuração de Bibliotecas do N8N ####################

      # Configura quais bibliotecas nativas podem ser importardas no node Code
      - NODE_FUNCTION_ALLOW_BUILTIN=*
      # Configura as bibliotecas externas que serão utilizadas
      - NODE_FUNCTION_ALLOW_EXTERNAL=lodash
      # Habilita o uso de pacotes da comunidade
      - N8N_COMMUNITY_PACKAGES_ENABLED=true
      # Reinstalar os Community Nodes
      - N8N_REINSTALL_MISSING_PACKAGES=true
      # Configura o caminho dos nodes customizados
      - N8N_NODE_PATH=/home/node/.n8n/nodes

      # Configuração de IA ####################################

      # Configura quais bibliotecas nativas podem ser importardas no node Code
      - N8N_AI_ENABLED=false
      # Configura as bibliotecas externas que serão utilizadas
      - N8N_AI_PROVIDER=openai
      # Habilita o uso de pacotes da comunidade
      - N8N_AI_OPENAI_API_KEY=

      # Configuração dos E-mails (Multi-user) #################

      # Modo de envio de e-mail
      - N8N_EMAIL_MODE=smtp
      # Configura o Host do SMTP
      - N8N_SMTP_HOST=$smtp
      # Configura a Porta do SMTP
      - N8N_SMTP_PORT=$portasmtp
      # Configura o Usuário do SMTP
      - N8N_SMTP_USER=$user_smtp
      # Configura a Senha do SMTP
      - N8N_SMTP_PASS=$senha
      # Configura o E-mail de envio
      - N8N_SMTP_SENDER=$email_smtp
      # Configura o SSL do SMTP
      - N8N_SMTP_SSL=$SECURE
      # Report de Erros Sentry
      # - N8N_SENTRY_DSN=
      # - N8N_FRONTEND_SENTRY_DSN=
      #########################################################
      # Mudanças da versão 2.0
      #########################################################
      #########################################################
      # Desabilita o acesso a variáveis de ambiente dentro dos nodes (true = desabilitado, false = habilitado)
      - N8N_BLOCK_ENV_ACCESS_IN_NODE=false
      # Configira um array com os nodes a serem removidos do n8n
      - NODES_EXCLUDE="[]"
      # Permitir acesso sem autenticação para endpoints de retorno de chamada OAuth
      - N8N_SKIP_AUTH_ON_OAUTH_CALLBACK=false
      # Local padrão para acesso a arquivos sem restrição
      - N8N_RESTRICT_FILE_ACCESS_TO=~/.n8n-files
      # Modo de armazenamento de dados binários
      - N8N_DEFAULT_BINARY_DATA_MODE=default

    # Configura o Modo de Deploy da Aplicação
    deploy:
      # O editor será executado no modo de replicação
      mode: replicated
      # Vamos ter apenas uma instância do editor
      replicas: 2
      # Configura o local de execução
      placement:
        # Você pode rodar o Editor no Manager mesmo pois usa poucos recursos
        constraints:
          - node.role == manager
          # - node.hostname == worker1
          # - node.labels.app == workers # nome do label: app, valor do label: workers
      resources:
        # Definição dos Limites de Recursos deste Serviço
        limits:
          # Define a quantidade de CPU para o N8N para evitar travamento do Host
          cpus: "1"
          # Define a quantidade de RAM para o N8N para evitar travamento do Host
          memory: 1024M
      # Define os Labels do Serviço
EOL
if [ "$INSTALL_TYPE" = "TRADICIONAL" ]; then
cat >> $nome_app_webhook.yaml << EOL
      labels:
        # Configura o Roteamento do Traefik
        - traefik.enable=true
        # Define o enderço do Webhook do N8N
        - traefik.http.routers.$nome_app_webhook.rule=Host(\`$dominiowebhook\`)
        # Redireciona o endereço para HTTPS
        - traefik.http.routers.$nome_app_webhook.entrypoints=websecure
        # Define o certificado SSL
        - traefik.http.routers.$nome_app_webhook.tls.certresolver=letsencryptresolver
        # Define o serviço do Webhook
        - traefik.http.routers.$nome_app_webhook.service=$nome_app_webhook
        # Define a porta do serviço do Webhook
        - traefik.http.services.$nome_app_webhook.loadbalancer.server.port=5678
        # Define o uso do Host Header
        - traefik.http.services.$nome_app_webhook.loadbalancer.passHostHeader=true
        
EOL
fi
cat >> $nome_app_webhook.yaml << EOL
      # Configura o modo de atualização do serviço
      update_config:
        # Configura o paralelismo de atualização
        parallelism: 1
        # Configura o tempo de espera entre as atualizações
        delay: 30s
        # Configura a ação em caso de falha
        order: start-first
        # Configura a ação em caso de falha
        failure_action: rollback

networks:
  traefik_public:
    external: true
    name: externa
  app_network:
    external: true
    name: interna


  interna:
    external: true
  externa:
    external: true

EOL
if [[ "$criar_portainer" == "0" ]]; then
    echo -e "XXX\n48\nCRIANDO STACK NO PORTAINER 3/4  \nXXX"
dados_file="$HOME/dados_portainer/dados_portainer"
if [[ -f "$dados_file" ]]; then
PORTAINER_URL=$(grep "Dominio do portainer:" "$dados_file" | cut -d':' -f2 | xargs)
ADMIN_USERNAME=$(grep "Usuario:" "$dados_file" | cut -d':' -f2 | xargs)
ADMIN_PASSWORD=$(grep "Senha:" "$dados_file" | cut -d':' -f2 | xargs)
STACK_NAME=$nome_app_webhook
STACK_FILE_PATH="/root/$nome_app_webhook.yaml"
else
    sleep 5
echo -e "XXX\n49\nSEM ARQUIVO DE DADOS DO PORTAINER 3/4  \nXXX"
docker stack deploy --prune --resolve-image always -c $nome_app_webhook.yaml $nome_app_webhook >/dev/null 2>&1
sleep 5
    exit 1
fi
get_auth_token() {
    echo -e "XXX\n50\nAUTENTICANDO NO PORTAINER... 3/4  \nXXX"
    RESPONSE=$(curl -sS -X POST "https://$PORTAINER_URL/api/auth" \
        -H "Content-Type: application/json" \
        -d "{\"username\": \"$ADMIN_USERNAME\", \"password\": \"$ADMIN_PASSWORD\"}")
    TOKEN=$(echo "$RESPONSE" | jq -r '.jwt')
    if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]; then
        echo -e "XXX\n51\nFALHA NA AUTENTICAÇÃO.. 3/4  \nXXX"
sleep 5
echo -e "XXX\n52\nREVERTENDO E CRIANDO STACK PELO SERVIDOR 3/4  \nXXX"
docker stack deploy --prune --resolve-image always -c $nome_app_webhook.yaml $nome_app_webhook >/dev/null 2>&1
sleep 5
        exit 1
    fi
 echo -e "XXX\n53\n[SUCESSO] AUTENTICAÇÃO OK 3/4  \nXXX"
}
get_endpoint_id() {
    echo -e "XXX\n54\n[INFO] OBTENDO ENDPOINTID 3/4  \nXXX"
    RESPONSE=$(curl -sS -X GET "https://$PORTAINER_URL/api/endpoints" \
        -H "Authorization: Bearer $TOKEN")
    ENDPOINT_ID=$(echo "$RESPONSE" | jq -r '.[0].Id')
    if [ -z "$ENDPOINT_ID" ] || [ "$ENDPOINT_ID" = "null" ]; then
        echo -e "XXX\n55\n[ERRO] ENDPOINTID NÃO ENCONTRADO 3/4  \nXXX"
        docker stack deploy --prune --resolve-image always -c $nome_app_webhook.yaml $nome_app_webhook >/dev/null 2>&1
        exit 1
    fi
     echo -e "XXX\n56\n[SUCESSO] ENDPOINTID OBTIDO: $ENDPOINT_ID  3/4  \nXXX"
}
get_swarm_id() {
    echo -e "XXX\n57\n[INFO] OBTENDO SWARMID  3/4  \nXXX"
    RESPONSE=$(curl -sS -X GET "https://$PORTAINER_URL/api/endpoints/$ENDPOINT_ID/docker/swarm" \
        -H "Authorization: Bearer $TOKEN")
    SWARM_ID=$(echo "$RESPONSE" | jq -r '.ID')
    if [ -z "$SWARM_ID" ] || [ "$SWARM_ID" = "null" ]; then
        echo -e "XXX\n58\n[ERRO] SWARMID NÃO ENCONTRADO 3/4  \nXXX"
        docker stack deploy --prune --resolve-image always -c $nome_app_webhook.yaml $nome_app_webhook >/dev/null 2>&1
        exit 1
    fi
    echo -e "XXX\n59\n[SUCESSO] SWARMID OBTIDO: $SWARM_ID  3/4  \nXXX"
}
create_stack() {
    echo -e "XXX\n60\n[INFO] VERIFICANDO SE YAML EXISTE 3/4  \nXXX"
    if [ ! -f "$STACK_FILE_PATH" ]; then
        echo -e "XXX\n61\n[ERRO] ARQUIVO $STACK_FILE_PATH NÃO ENCONTRADO 3/4  \nXXX"
        docker stack deploy --prune --resolve-image always -c $nome_app_webhook.yaml $nome_app_webhook >/dev/null 2>&1
        exit 1
    fi
     echo -e "XXX\n62\n[INFO] CRIANDO STACK $STACK_NAME NO PORTAINER 3/4  \nXXX"
    response_output=$(mktemp)
    erro_output=$(mktemp)

    http_code=$(curl -s -o "$response_output" -w "%{http_code}"  -X POST \
        -H "Authorization: Bearer $TOKEN" \
        -F "Name=$STACK_NAME" \
        -F "file=@$STACK_FILE_PATH" \
        -F "SwarmID=$SWARM_ID" \
        -F "endpointId=$ENDPOINT_ID" \
        "https://$PORTAINER_URL/api/stacks/create/swarm/file" 2> "$erro_output")

    response=$(cat "$response_output")
    rm -f "$response_output" "$erro_output"
    if [ "$http_code" -ne 200 ]; then
        echo -e "XXX\n63\n[ERRO] ERRO AO CRIAR STACK 3/4  \nXXX"
        docker stack deploy --prune --resolve-image always -c $nome_app_webhook.yaml $nome_app_webhook >/dev/null 2>&1
        exit 1
    fi
    echo -e "XXX\n64\n[SUCESSO] STACK $STACK_NAME  CRIADA COM SUCESSO 3/4  \nXXX"
}
get_auth_token || exit 1
get_endpoint_id || exit 1
get_swarm_id || exit 1
create_stack || exit 1
elif [[ "$criar_portainer" == "1" ]]; then
    echo "Criando a stack diretamente no Docker (não editável no Portainer)."
    docker stack deploy --prune --resolve-image always -c $nome_app_webhook.yaml $nome_app_webhook >/dev/null 2>&1
else
    echo -e "XXX\n65\n[ERRO] ERRO INESPERADO PARA CRIAR STACK NO PORTAINER 3/4  \nXXX"
    sleep 5
    echo -e "XXX\n66\nREVERTENDO E CRIANDO STACK PELO SERVIDOR 3/4  \nXXX"
docker stack deploy --prune --resolve-image always -c $nome_app_webhook.yaml $nome_app_webhook >/dev/null 2>&1
sleep 5

    exit 1
fi
clear
cd
cd
clear
cat > $nome_app_mcp_api.yaml << EOL

version: "3.7"
# Definição dos Serviços
services:
  # Definição do Serviço do Editor
  $nome_app_mcp_api:
    # imagem do docker
    # MCP está disponível da versão 1.88 em diante
    image: n8nio/n8n:2.9.2
    # Define o hotname do container
    hostname: "$nome_app_mcp_api"
    # comando padrão para subir o servidor web do editor
    command: webhook
    # configura a rede do serviço  
    networks:
      - traefik_public
      - app_network
      - interna
      - externa
    # configura as variáveis de ambiente
    environment:
      #########################################################
      # Documentação de Variáveis de Ambiente do N8N ##########
      # https://docs.n8n.io/hosting/environment-variables/environment-variables/
 
      # Configuração Gerais do N8N ############################
     
      # Gere uma nova chave aqui https://www.avast.com/random-password-generator#mac
      - N8N_ENCRYPTION_KEY=$encryption_key
      # Configura o ambiente de execução do N8N
      - NODE_ENV=production
      # Habilita a Página de Métricas Públicas do N8N
      - N8N_METRICS=true
      # Habilita o envio de diagnósticos para o N8N
      - N8N_DIAGNOSTICS_ENABLED=false
      # Configura o Tamanho do Payload aceito pelo N8N (em MB)
      - N8N_PAYLOAD_SIZE_MAX=16
      # Configura o nível de log do N8N
      - N8N_LOG_LEVEL=info
      # Configura o Timezone do N8N
      - GENERIC_TIMEZONE=America/Sao_Paulo
      # Configura a Permissão do Arquivo de Configuração
      - N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS=true

      # Configuração de Execução dos Workflows ################

      - N8N_RUNNERS_ENABLED=true
      # Habilita o modo de execução externa
      - N8N_RUNNERS_MODE=external
      # Configura o endereço do broker para ouvir de qualquer
      # endereço na rede do swarm
      - N8N_RUNNERS_BROKER_LISTEN_ADDRESS=0.0.0.0
      # Configura o token de autenticação
      - N8N_RUNNERS_AUTH_TOKEN=$encryption_key2
      # Habilita o uso do Python nativo
      - N8N_NATIVE_PYTHON_RUNNER=true
      # Envia as execuções de teste para os workers
      - OFFLOAD_MANUAL_EXECUTIONS_TO_WORKERS=true

      # Configuração do Banco de Dados ########################

      # Define o Tipo de Banco de Dados para Postgres
      - DB_TYPE=postgresdb
      # Configura o Nome do Banco de Dados
      - DB_POSTGRESDB_DATABASE=$nome_app_database
      # Configura o Host do Banco de Dados
      - DB_POSTGRESDB_HOST=postgres
      # Configura a Porta do Banco de Dados
      - DB_POSTGRESDB_PORT=5432
      # Configura o Usuário do Banco de Dados
      - DB_POSTGRESDB_USER=postgres
      # Configura a Senha do Banco de Dados
      - DB_POSTGRESDB_PASSWORD=$postgres_password

      # Configuração do Endereço do N8N #######################

      # Define a Porta http para o N8N (padrão: 5678)
      - N8N_PORT=5678
      # Configura o Host do Editor do N8N
      - N8N_HOST=$dominioadmin
      # Configura o Endereço competo do Editor (tem que deixar / no final)
      - N8N_EDITOR_BASE_URL=https://$dominioadmin/
      # Força o uso de SSL nas URL internas do N8N
      - N8N_PROTOCOL=https
      # Configura o Endereço do Webhook
      # Pode ser subdomínio ou outro domínio
      - WEBHOOK_URL=https://$dominiowebhook/
      # Configura o Caminho do Webhook
      - N8N_ENDPOINT_WEBHOOK=webhook

      # Configuração da Modo de Execução do N8N (fila) ########

      - EXECUTIONS_MODE=queue
      # Configura o host do Redis
      - QUEUE_BULL_REDIS_HOST=$nome_app_database-redis
      # Configura a porta do Redis
      - QUEUE_BULL_REDIS_PORT=6379
      # Configura o indice do banco de dados do Redis
      - QUEUE_BULL_REDIS_DB=2
      # Configura a senha do Redis (caso você use senha no redis)
      # - QUEUE_BULL_REDIS_PASSWORD=SENHA
      # Configura o tempo sugerido de execução de um Job na fila (-1 para ficar sem limite)
      - EXECUTIONS_TIMEOUT=3600 # (1 hora)
      # Configura o tempo máximo de execução de um Job na fila (-1 para ficar sem limite)
      - EXECUTIONS_TIMEOUT_MAX=7200 # (2 horas)

      # Configuração da Interface do N8N ######################

      # Habilita as notificações de novas versões do N8N
      - N8N_VERSION_NOTIFICATIONS_ENABLED=true
      # Configura o N8N para exibir a documentação da API Pública
      - N8N_PUBLIC_API_SWAGGERUI_DISABLED=false
      # Habilita os Templates na Interface do N8N
      - N8N_TEMPLATES_ENABLED=true
      # Habilita dicas de integração ao criar um novo fluxo de trabalho (true = desabilitado)
      - N8N_ONBOARDING_FLOW_DISABLED=true
      # Desabilita o recurso de tags de workflows (false = habilitado)
      - N8N_WORKFLOW_TAGS_DISABLED=false
      # Oculta a Tela de Informações de Uso do N8N
      - N8N_HIDE_USAGE_PAGE=false

      # Configuração da Manutenção e Limpeza do N8N ###########
      # https://docs.n8n.io/hosting/scaling/execution-data/

      # Configura a limpeza dos dados de execução
      - EXECUTIONS_DATA_PRUNE=true
      # Configura o tempo máximo de armazenamento dos dados de execução
      - EXECUTIONS_DATA_MAX_AGE=336 # 2 semanas
      # Com que frequência (minutos) os dados de execução devem ser excluídos permanentemente.
      - EXECUTIONS_DATA_PRUNE_HARD_DELETE_INTERVAL=15
      # Com que frequência (minutos) os dados de execução devem ser excluídos de forma reversível.
      - EXECUTIONS_DATA_PRUNE_SOFT_DELETE_INTERVAL=60
      # Quantidade de Execuções para armazenar antes de excluir
      - EXECUTIONS_DATA_PRUNE_MAX_COUNT=10000
      ######################## opcional #######################
      # Salvar execuções que terminam em erros (all = salvar, none = não salvar)
      - EXECUTIONS_DATA_SAVE_ON_ERROR=all
      # Salve execuções bem-sucedidas (all = salvar, none = não salvar)
      - EXECUTIONS_DATA_SAVE_ON_SUCCESS=all
      # Não salve o progresso do nó para cada execução (true = savar, false = não salvar)
      - EXECUTIONS_DATA_SAVE_ON_PROGRESS=true
      # Não salve execuções iniciadas manualmente (true = savar, false = não salvar)
      - EXECUTIONS_DATA_SAVE_MANUAL_EXECUTIONS=true

      # Configuração de Bibliotecas do N8N ####################

      # Configura quais bibliotecas nativas podem ser importardas no node Code
      - NODE_FUNCTION_ALLOW_BUILTIN=*
      # Configura as bibliotecas externas que serão utilizadas
      - NODE_FUNCTION_ALLOW_EXTERNAL=lodash
      # Habilita o uso de pacotes da comunidade
      - N8N_COMMUNITY_PACKAGES_ENABLED=true
      # Reinstalar os Community Nodes
      - N8N_REINSTALL_MISSING_PACKAGES=true
      # Configura o caminho dos nodes customizados
      - N8N_NODE_PATH=/home/node/.n8n/nodes

      # Configuração de IA ####################################

      # Configura quais bibliotecas nativas podem ser importardas no node Code
      - N8N_AI_ENABLED=false
      # Configura as bibliotecas externas que serão utilizadas
      - N8N_AI_PROVIDER=openai
      # Habilita o uso de pacotes da comunidade
      - N8N_AI_OPENAI_API_KEY=

      # Configuração dos E-mails (Multi-user) #################

      # Modo de envio de e-mail
      - N8N_EMAIL_MODE=smtp
      # Configura o Host do SMTP
      - N8N_SMTP_HOST=$smtp
      # Configura a Porta do SMTP
      - N8N_SMTP_PORT=$portasmtp
      # Configura o Usuário do SMTP
      - N8N_SMTP_USER=$user_smtp
      # Configura a Senha do SMTP
      - N8N_SMTP_PASS=$senha
      # Configura o E-mail de envio
      - N8N_SMTP_SENDER=$email_smtp
      # Configura o SSL do SMTP
      - N8N_SMTP_SSL=$SECURE
      # Report de Erros Sentry
      # - N8N_SENTRY_DSN=
      # - N8N_FRONTEND_SENTRY_DSN=
      #########################################################
      # Mudanças da versão 2.0
      #########################################################
      #########################################################
      # Desabilita o acesso a variáveis de ambiente dentro dos nodes (true = desabilitado, false = habilitado)
      - N8N_BLOCK_ENV_ACCESS_IN_NODE=false
      # Configira um array com os nodes a serem removidos do n8n
      - NODES_EXCLUDE="[]"
      # Permitir acesso sem autenticação para endpoints de retorno de chamada OAuth
      - N8N_SKIP_AUTH_ON_OAUTH_CALLBACK=false
      # Local padrão para acesso a arquivos sem restrição
      - N8N_RESTRICT_FILE_ACCESS_TO=~/.n8n-files
      # Modo de armazenamento de dados binários
      - N8N_DEFAULT_BINARY_DATA_MODE=default

    # Configura o Modo de Deploy da Aplicação
    deploy:
      # O editor será executado no modo de replicação
      mode: replicated
      # Vamos ter apenas uma instância do servidor MCP
      replicas: 1
      # Configura o local de execução
      placement:
        constraints:
          # Você pode rodar o Editor no Manager mesmo pois usa poucos recursos
          - node.role == manager
          # - node.hostname == worker1
          # - node.labels.app == http # nome do label: app, valor do label: http
      # Limitação
      resources:
        # Definição dos Limites de Recursos deste Serviço
        limits:
          # Define a quantidade de CPU para o N8N para evitar travamento do Host
          cpus: "1"
          # Define a quantidade de RAM para o N8N para evitar travamento do Host
          memory: 2048M
      # Define os Labels do Serviço
EOL
if [ "$INSTALL_TYPE" = "TRADICIONAL" ]; then
cat >> $nome_app_mcp_api.yaml << EOL
      labels:
        # Habilita o Traefik para este serviço
        - traefik.enable=true
        #############################################################
        # Configura o Roteamento do Traefik para o MCP
        #############################################################
        # Define o enderço do Webhook do N8N para receber somente o prefixo /mcp
        - traefik.http.routers.$nome_app_mcp_api.rule=Host(\`$dominiowebhook\`) && PathPrefix(\`/mcp\`)
        # Redireciona o endereço para HTTPS
        - traefik.http.routers.$nome_app_mcp_api.entrypoints=websecure
        # Define o certificado SSL
        - traefik.http.routers.$nome_app_mcp_api.tls.certresolver=letsencryptresolver
        # Define o serviço do Editor
        - traefik.http.routers.$nome_app_mcp_api.service=$nome_app_mcp_api
        # Define a porta do serviço do Editor
        - traefik.http.services.$nome_app_mcp_api.loadbalancer.server.port=5678
        # Define o uso do Host Header
        - traefik.http.services.$nome_app_mcp_api.loadbalancer.passHostHeader=true
EOL
fi
cat >> $nome_app_mcp_api.yaml << EOL

      update_config:
        parallelism: 1
        delay: 30s
        order: start-first
        failure_action: rollback
networks:
  traefik_public:
    external: true
    name: externa
  app_network:
    external: true
    name: interna


  interna:
    external: true
  externa:
    external: true


EOL
if [[ "$criar_portainer" == "0" ]]; then
    echo -e "XXX\n48\nCRIANDO STACK NO PORTAINER 3/4  \nXXX"
dados_file="$HOME/dados_portainer/dados_portainer"
if [[ -f "$dados_file" ]]; then
PORTAINER_URL=$(grep "Dominio do portainer:" "$dados_file" | cut -d':' -f2 | xargs)
ADMIN_USERNAME=$(grep "Usuario:" "$dados_file" | cut -d':' -f2 | xargs)
ADMIN_PASSWORD=$(grep "Senha:" "$dados_file" | cut -d':' -f2 | xargs)
STACK_NAME=$nome_app_mcp_api
STACK_FILE_PATH="/root/$nome_app_mcp_api.yaml"
else
    sleep 5
echo -e "XXX\n49\nSEM ARQUIVO DE DADOS DO PORTAINER 3/4  \nXXX"
docker stack deploy --prune --resolve-image always -c $nome_app_mcp_api.yaml $nome_app_mcp_api >/dev/null 2>&1
sleep 5
    exit 1
fi
get_auth_token() {
    echo -e "XXX\n50\nAUTENTICANDO NO PORTAINER... 3/4  \nXXX"
    RESPONSE=$(curl -sS -X POST "https://$PORTAINER_URL/api/auth" \
        -H "Content-Type: application/json" \
        -d "{\"username\": \"$ADMIN_USERNAME\", \"password\": \"$ADMIN_PASSWORD\"}")
    TOKEN=$(echo "$RESPONSE" | jq -r '.jwt')
    if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]; then
        echo -e "XXX\n51\nFALHA NA AUTENTICAÇÃO.. 3/4  \nXXX"
sleep 5
echo -e "XXX\n52\nREVERTENDO E CRIANDO STACK PELO SERVIDOR 3/4  \nXXX"
docker stack deploy --prune --resolve-image always -c $nome_app_mcp_api.yaml $nome_app_mcp_api >/dev/null 2>&1
sleep 5
        exit 1
    fi
 echo -e "XXX\n53\n[SUCESSO] AUTENTICAÇÃO OK 3/4  \nXXX"
}
get_endpoint_id() {
    echo -e "XXX\n54\n[INFO] OBTENDO ENDPOINTID 3/4  \nXXX"
    RESPONSE=$(curl -sS -X GET "https://$PORTAINER_URL/api/endpoints" \
        -H "Authorization: Bearer $TOKEN")
    ENDPOINT_ID=$(echo "$RESPONSE" | jq -r '.[0].Id')
    if [ -z "$ENDPOINT_ID" ] || [ "$ENDPOINT_ID" = "null" ]; then
        echo -e "XXX\n55\n[ERRO] ENDPOINTID NÃO ENCONTRADO 3/4  \nXXX"
        docker stack deploy --prune --resolve-image always -c $nome_app_mcp_api.yaml $nome_app_mcp_api >/dev/null 2>&1
        exit 1
    fi
     echo -e "XXX\n56\n[SUCESSO] ENDPOINTID OBTIDO: $ENDPOINT_ID  3/4  \nXXX"
}
get_swarm_id() {
    echo -e "XXX\n57\n[INFO] OBTENDO SWARMID  3/4  \nXXX"
    RESPONSE=$(curl -sS -X GET "https://$PORTAINER_URL/api/endpoints/$ENDPOINT_ID/docker/swarm" \
        -H "Authorization: Bearer $TOKEN")
    SWARM_ID=$(echo "$RESPONSE" | jq -r '.ID')
    if [ -z "$SWARM_ID" ] || [ "$SWARM_ID" = "null" ]; then
        echo -e "XXX\n58\n[ERRO] SWARMID NÃO ENCONTRADO 3/4  \nXXX"
        docker stack deploy --prune --resolve-image always -c $nome_app_mcp_api.yaml $nome_app_mcp_api >/dev/null 2>&1
        exit 1
    fi
    echo -e "XXX\n59\n[SUCESSO] SWARMID OBTIDO: $SWARM_ID  3/4  \nXXX"
}
create_stack() {
    echo -e "XXX\n60\n[INFO] VERIFICANDO SE YAML EXISTE 3/4  \nXXX"
    if [ ! -f "$STACK_FILE_PATH" ]; then
        echo -e "XXX\n61\n[ERRO] ARQUIVO $STACK_FILE_PATH NÃO ENCONTRADO 3/4  \nXXX"
        docker stack deploy --prune --resolve-image always -c $nome_app_mcp_api.yaml $nome_app_mcp_api >/dev/null 2>&1
        exit 1
    fi
     echo -e "XXX\n62\n[INFO] CRIANDO STACK $STACK_NAME NO PORTAINER 3/4  \nXXX"
    response_output=$(mktemp)
    erro_output=$(mktemp)
    http_code=$(curl -s -o "$response_output" -w "%{http_code}"  -X POST \
        -H "Authorization: Bearer $TOKEN" \
        -F "Name=$STACK_NAME" \
        -F "file=@$STACK_FILE_PATH" \
        -F "SwarmID=$SWARM_ID" \
        -F "endpointId=$ENDPOINT_ID" \
        "https://$PORTAINER_URL/api/stacks/create/swarm/file" 2> "$erro_output")
    response=$(cat "$response_output")
    rm -f "$response_output" "$erro_output"
    if [ "$http_code" -ne 200 ]; then
        echo -e "XXX\n63\n[ERRO] ERRO AO CRIAR STACK 3/4  \nXXX"
        docker stack deploy --prune --resolve-image always -c $nome_app_mcp_api.yaml $nome_app_mcp_api >/dev/null 2>&1
        exit 1
    fi
    echo -e "XXX\n64\n[SUCESSO] STACK $STACK_NAME  CRIADA COM SUCESSO 3/4  \nXXX"
}
get_auth_token || exit 1
get_endpoint_id || exit 1
get_swarm_id || exit 1
create_stack || exit 1
elif [[ "$criar_portainer" == "1" ]]; then
    echo "Criando a stack diretamente no Docker (não editável no Portainer)."
    docker stack deploy --prune --resolve-image always -c $nome_app_mcp_api.yaml $nome_app_mcp_api >/dev/null 2>&1
else
    echo -e "XXX\n65\n[ERRO] ERRO INESPERADO PARA CRIAR STACK NO PORTAINER 3/4  \nXXX"
    sleep 5
    echo -e "XXX\n66\nREVERTENDO E CRIANDO STACK PELO SERVIDOR 3/4  \nXXX"
docker stack deploy --prune --resolve-image always -c $nome_app_mcp_api.yaml $nome_app_mcp_api >/dev/null 2>&1
sleep 5
    exit 1
fi
cd
cd
clear
cat > $nome_app_worker.yaml << EOL

version: "3.7"
# Definição dos Serviços
services:
  # Definição do Serviço do Worker
  $nome_app_worker:
    # imagem do docker
    image: n8nio/n8n:2.9.2
    # Define o hotname do container
    hostname: "$nome_app_worker"
    # comando padrão para subir o servidor web
    command: worker --concurrency=10
    # configura a rede do serviço
    networks:
      - traefik_public
      - app_network
      - interna
      - externa
    # configura as variáveis de ambiente
    environment:
      #########################################################
      # Documentação de Variáveis de Ambiente do N8N ##########
      # https://docs.n8n.io/hosting/environment-variables/environment-variables/
 
      # Configuração Gerais do N8N ############################
     
      # Gere uma nova chave aqui https://www.avast.com/random-password-generator#mac
      - N8N_ENCRYPTION_KEY=$encryption_key
      # Configura o ambiente de execução do N8N
      - NODE_ENV=production
      # Habilita a Página de Métricas Públicas do N8N
      - N8N_METRICS=true
      # Habilita o envio de diagnósticos para o N8N
      - N8N_DIAGNOSTICS_ENABLED=false
      # Configura o Tamanho do Payload aceito pelo N8N (em MB)
      - N8N_PAYLOAD_SIZE_MAX=16
      # Configura o nível de log do N8N
      - N8N_LOG_LEVEL=info
      # Configura o Timezone do N8N
      - GENERIC_TIMEZONE=America/Sao_Paulo
      # Configura a Permissão do Arquivo de Configuração
      - N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS=true

      # Configuração de Execução dos Workflows ################

      - N8N_RUNNERS_ENABLED=true
      # Habilita o modo de execução externa
      - N8N_RUNNERS_MODE=external
      # Configura o endereço do broker para ouvir de qualquer
      # endereço na rede do swarm
      - N8N_RUNNERS_BROKER_LISTEN_ADDRESS=0.0.0.0
      # Configura o token de autenticação
      - N8N_RUNNERS_AUTH_TOKEN=$encryption_key2
      # Habilita o uso do Python nativo
      - N8N_NATIVE_PYTHON_RUNNER=true
      # Envia as execuções de teste para os workers
      - OFFLOAD_MANUAL_EXECUTIONS_TO_WORKERS=true

      # Configuração do Banco de Dados ########################

      # Define o Tipo de Banco de Dados para Postgres
      - DB_TYPE=postgresdb
      # Configura o Nome do Banco de Dados
      - DB_POSTGRESDB_DATABASE=$nome_app_database
      # Configura o Host do Banco de Dados
      - DB_POSTGRESDB_HOST=postgres
      # Configura a Porta do Banco de Dados
      - DB_POSTGRESDB_PORT=5432
      # Configura o Usuário do Banco de Dados
      - DB_POSTGRESDB_USER=postgres
      # Configura a Senha do Banco de Dados
      - DB_POSTGRESDB_PASSWORD=$postgres_password

      # Configuração do Endereço do N8N #######################

      # Define a Porta http para o N8N (padrão: 5678)
      - N8N_PORT=5678
      # Configura o Host do Editor do N8N
      - N8N_HOST=$dominioadmin
      # Configura o Endereço competo do Editor (tem que deixar / no final)
      - N8N_EDITOR_BASE_URL=https://$dominioadmin/
      # Força o uso de SSL nas URL internas do N8N
      - N8N_PROTOCOL=https
      # Configura o Endereço do Webhook
      # Pode ser subdomínio ou outro domínio
      - WEBHOOK_URL=https://$dominiowebhook/
      # Configura o Caminho do Webhook
      - N8N_ENDPOINT_WEBHOOK=webhook

      # Configuração da Modo de Execução do N8N (fila) ########

      - EXECUTIONS_MODE=queue
      # Configura o host do Redis
      - QUEUE_BULL_REDIS_HOST=$nome_app_database-redis
      # Configura a porta do Redis
      - QUEUE_BULL_REDIS_PORT=6379
      # Configura o indice do banco de dados do Redis
      - QUEUE_BULL_REDIS_DB=2
      # Configura a senha do Redis (caso você use senha no redis)
      # - QUEUE_BULL_REDIS_PASSWORD=SENHA
      # Configura o tempo sugerido de execução de um Job na fila (-1 para ficar sem limite)
      - EXECUTIONS_TIMEOUT=3600 # (1 hora)
      # Configura o tempo máximo de execução de um Job na fila (-1 para ficar sem limite)
      - EXECUTIONS_TIMEOUT_MAX=7200 # (2 horas)

      # Configuração da Interface do N8N ######################

      # Habilita as notificações de novas versões do N8N
      - N8N_VERSION_NOTIFICATIONS_ENABLED=true
      # Configura o N8N para exibir a documentação da API Pública
      - N8N_PUBLIC_API_SWAGGERUI_DISABLED=false
      # Habilita os Templates na Interface do N8N
      - N8N_TEMPLATES_ENABLED=true
      # Habilita dicas de integração ao criar um novo fluxo de trabalho (true = desabilitado)
      - N8N_ONBOARDING_FLOW_DISABLED=true
      # Desabilita o recurso de tags de workflows (false = habilitado)
      - N8N_WORKFLOW_TAGS_DISABLED=false
      # Oculta a Tela de Informações de Uso do N8N
      - N8N_HIDE_USAGE_PAGE=false

      # Configuração da Manutenção e Limpeza do N8N ###########
      # https://docs.n8n.io/hosting/scaling/execution-data/

      # Configura a limpeza dos dados de execução
      - EXECUTIONS_DATA_PRUNE=true
      # Configura o tempo máximo de armazenamento dos dados de execução
      - EXECUTIONS_DATA_MAX_AGE=336 # 2 semanas
      # Com que frequência (minutos) os dados de execução devem ser excluídos permanentemente.
      - EXECUTIONS_DATA_PRUNE_HARD_DELETE_INTERVAL=15
      # Com que frequência (minutos) os dados de execução devem ser excluídos de forma reversível.
      - EXECUTIONS_DATA_PRUNE_SOFT_DELETE_INTERVAL=60
      # Quantidade de Execuções para armazenar antes de excluir
      - EXECUTIONS_DATA_PRUNE_MAX_COUNT=10000
      ######################## opcional #######################
      # Salvar execuções que terminam em erros (all = salvar, none = não salvar)
      - EXECUTIONS_DATA_SAVE_ON_ERROR=all
      # Salve execuções bem-sucedidas (all = salvar, none = não salvar)
      - EXECUTIONS_DATA_SAVE_ON_SUCCESS=all
      # Não salve o progresso do nó para cada execução (true = savar, false = não salvar)
      - EXECUTIONS_DATA_SAVE_ON_PROGRESS=true
      # Não salve execuções iniciadas manualmente (true = savar, false = não salvar)
      - EXECUTIONS_DATA_SAVE_MANUAL_EXECUTIONS=true

      # Configuração de Bibliotecas do N8N ####################

      # Configura quais bibliotecas nativas podem ser importardas no node Code
      - NODE_FUNCTION_ALLOW_BUILTIN=*
      # Configura as bibliotecas externas que serão utilizadas
      - NODE_FUNCTION_ALLOW_EXTERNAL=lodash
      # Habilita o uso de pacotes da comunidade
      - N8N_COMMUNITY_PACKAGES_ENABLED=true
      # Reinstalar os Community Nodes
      - N8N_REINSTALL_MISSING_PACKAGES=true
      # Configura o caminho dos nodes customizados
      - N8N_NODE_PATH=/home/node/.n8n/nodes

      # Configuração de IA ####################################

      # Configura quais bibliotecas nativas podem ser importardas no node Code
      - N8N_AI_ENABLED=false
      # Configura as bibliotecas externas que serão utilizadas
      - N8N_AI_PROVIDER=openai
      # Habilita o uso de pacotes da comunidade
      - N8N_AI_OPENAI_API_KEY=

      # Configuração dos E-mails (Multi-user) #################

      # Modo de envio de e-mail
      - N8N_EMAIL_MODE=smtp
      # Configura o Host do SMTP
      - N8N_SMTP_HOST=$smtp
      # Configura a Porta do SMTP
      - N8N_SMTP_PORT=$portasmtp
      # Configura o Usuário do SMTP
      - N8N_SMTP_USER=$user_smtp
      # Configura a Senha do SMTP
      - N8N_SMTP_PASS=$senha
      # Configura o E-mail de envio
      - N8N_SMTP_SENDER=$email_smtp
      # Configura o SSL do SMTP
      - N8N_SMTP_SSL=$SECURE
      # Report de Erros Sentry
      # - N8N_SENTRY_DSN=
      # - N8N_FRONTEND_SENTRY_DSN=
      #########################################################
      # Mudanças da versão 2.0
      #########################################################
      #########################################################
      # Desabilita o acesso a variáveis de ambiente dentro dos nodes (true = desabilitado, false = habilitado)
      - N8N_BLOCK_ENV_ACCESS_IN_NODE=false
      # Configira um array com os nodes a serem removidos do n8n
      - NODES_EXCLUDE="[]"
      # Permitir acesso sem autenticação para endpoints de retorno de chamada OAuth
      - N8N_SKIP_AUTH_ON_OAUTH_CALLBACK=false
      # Local padrão para acesso a arquivos sem restrição
      - N8N_RESTRICT_FILE_ACCESS_TO=~/.n8n-files
      # Modo de armazenamento de dados binários
      - N8N_DEFAULT_BINARY_DATA_MODE=default

    # Configura o Modo de Deploy da Aplicação
    deploy:
      # O editor será executado no modo de replicação
      mode: replicated
      # Vamos ter apenas uma instância do editor
      replicas: 1
      # Configura o local de execução
      placement:
        # Você pode rodar o Editor no Manager mesmo pois usa poucos recursos
        constraints:
          - node.role == manager
          # - node.hostname == worker1
          # - node.labels.app == webhooks # nome do label: app, valor do label: webhooks
      resources:
        # Definição dos Limites de Recursos deste Serviço
        limits:
          # Define a quantidade de CPU para o N8N para evitar travamento do Host
          cpus: "1"
          # Define a quantidade de RAM para o N8N para evitar travamento do Host
          memory: 1024M
      # Configura o modo de atualização do serviço
      update_config:
        # Configura o paralelismo de atualização
        parallelism: 1
        # Configura o tempo de espera entre as atualizações
        delay: 30s
        # Configura a ação em caso de falha
        order: start-first
        # Configura a ação em caso de falha
        failure_action: rollback 
networks:
  traefik_public:
    external: true
    name: externa
  app_network:
    external: true
    name: interna


  interna:
    external: true
  externa:
    external: true

EOL
if [[ "$criar_portainer" == "0" ]]; then
    echo -e "XXX\n76\nCRIANDO STACK NO PORTAINER 3/4  \nXXX"
dados_file="$HOME/dados_portainer/dados_portainer"
if [[ -f "$dados_file" ]]; then
PORTAINER_URL=$(grep "Dominio do portainer:" "$dados_file" | cut -d':' -f2 | xargs)
ADMIN_USERNAME=$(grep "Usuario:" "$dados_file" | cut -d':' -f2 | xargs)
ADMIN_PASSWORD=$(grep "Senha:" "$dados_file" | cut -d':' -f2 | xargs)
STACK_NAME=$nome_app_worker
STACK_FILE_PATH="/root/$nome_app_worker.yaml"
else
    sleep 5
echo -e "XXX\n77\nSEM ARQUIVO DE DADOS DO PORTAINER 3/4  \nXXX"
docker stack deploy --prune --resolve-image always -c $nome_app_worker.yaml $nome_app_worker >/dev/null 2>&1
sleep 5
    exit 1
fi
get_auth_token() {
    echo -e "XXX\n77\nAUTENTICANDO NO PORTAINER... 3/4  \nXXX"
    RESPONSE=$(curl -sS -X POST "https://$PORTAINER_URL/api/auth" \
        -H "Content-Type: application/json" \
        -d "{\"username\": \"$ADMIN_USERNAME\", \"password\": \"$ADMIN_PASSWORD\"}")
    TOKEN=$(echo "$RESPONSE" | jq -r '.jwt')
    if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]; then
        echo -e "XXX\n77\nFALHA NA AUTENTICAÇÃO.. 3/4  \nXXX"
sleep 5
echo -e "XXX\n78\nREVERTENDO E CRIANDO STACK PELO SERVIDOR 3/4  \nXXX"
docker stack deploy --prune --resolve-image always -c $nome_app_worker.yaml $nome_app_worker >/dev/null 2>&1
sleep 5
        exit 1
    fi
 echo -e "XXX\n79\n[SUCESSO] AUTENTICAÇÃO OK 3/4  \nXXX"
}
get_endpoint_id() {
    echo -e "XXX\n80\n[INFO] OBTENDO ENDPOINTID 3/4  \nXXX"
    RESPONSE=$(curl -sS -X GET "https://$PORTAINER_URL/api/endpoints" \
        -H "Authorization: Bearer $TOKEN")
    ENDPOINT_ID=$(echo "$RESPONSE" | jq -r '.[0].Id')
    if [ -z "$ENDPOINT_ID" ] || [ "$ENDPOINT_ID" = "null" ]; then
        echo -e "XXX\n81\n[ERRO] ENDPOINTID NÃO ENCONTRADO 3/4  \nXXX"
        docker stack deploy --prune --resolve-image always -c $nome_app_worker.yaml $nome_app_worker >/dev/null 2>&1
        exit 1
    fi
     echo -e "XXX\n82\n[SUCESSO] ENDPOINTID OBTIDO: $ENDPOINT_ID  3/4  \nXXX"
}
get_swarm_id() {
    echo -e "XXX\n83\n[INFO] OBTENDO SWARMID  3/4  \nXXX"
    RESPONSE=$(curl -sS -X GET "https://$PORTAINER_URL/api/endpoints/$ENDPOINT_ID/docker/swarm" \
        -H "Authorization: Bearer $TOKEN")
    SWARM_ID=$(echo "$RESPONSE" | jq -r '.ID')
    if [ -z "$SWARM_ID" ] || [ "$SWARM_ID" = "null" ]; then
        echo -e "XXX\n84\n[ERRO] SWARMID NÃO ENCONTRADO 3/4  \nXXX"
        docker stack deploy --prune --resolve-image always -c $nome_app_worker.yaml $nome_app_worker >/dev/null 2>&1
        exit 1
    fi
    echo -e "XXX\n85\n[SUCESSO] SWARMID OBTIDO: $SWARM_ID  3/4  \nXXX"
}
create_stack() {
    echo -e "XXX\n86\n[INFO] VERIFICANDO SE YAML EXISTE 3/4  \nXXX"
    if [ ! -f "$STACK_FILE_PATH" ]; then
        echo -e "XXX\n87\n[ERRO] ARQUIVO $STACK_FILE_PATH NÃO ENCONTRADO 3/4  \nXXX"
        docker stack deploy --prune --resolve-image always -c $nome_app_worker.yaml $nome_app_worker >/dev/null 2>&1
        exit 1
    fi
     echo -e "XXX\n88\n[INFO] CRIANDO STACK $STACK_NAME NO PORTAINER 3/4  \nXXX"
    response_output=$(mktemp)
    erro_output=$(mktemp)
    http_code=$(curl -s -o "$response_output" -w "%{http_code}"  -X POST \
        -H "Authorization: Bearer $TOKEN" \
        -F "Name=$STACK_NAME" \
        -F "file=@$STACK_FILE_PATH" \
        -F "SwarmID=$SWARM_ID" \
        -F "endpointId=$ENDPOINT_ID" \
        "https://$PORTAINER_URL/api/stacks/create/swarm/file" 2> "$erro_output")
    response=$(cat "$response_output")
    rm -f "$response_output" "$erro_output"
    if [ "$http_code" -ne 200 ]; then
        echo -e "XXX\n89\n[ERRO] ERRO AO CRIAR STACK 3/4  \nXXX"
        docker stack deploy --prune --resolve-image always -c $nome_app_worker.yaml $nome_app_worker >/dev/null 2>&1
        exit 1
    fi
    echo -e "XXX\n90\n[SUCESSO] STACK $STACK_NAME  CRIADA COM SUCESSO 3/4  \nXXX"
}
get_auth_token || exit 1
get_endpoint_id || exit 1
get_swarm_id || exit 1
create_stack || exit 1
elif [[ "$criar_portainer" == "1" ]]; then
    echo "Criando a stack diretamente no Docker (não editável no Portainer)."
    docker stack deploy --prune --resolve-image always -c $nome_app_worker.yaml $nome_app_worker >/dev/null 2>&1
else
    echo -e "XXX\n91\n[ERRO] ERRO INESPERADO PARA CRIAR STACK NO PORTAINER 3/4  \nXXX"
    sleep 5
    echo -e "XXX\n92\nREVERTENDO E CRIANDO STACK PELO SERVIDOR 3/4  \nXXX"
docker stack deploy --prune --resolve-image always -c $nome_app_worker.yaml $nome_app_worker >/dev/null 2>&1
sleep 5
    exit 1
fi
cd
cd
clear
cat > $nome_app_runner.yaml << EOL

version: "3.7"
# Definição dos Serviços
services:
  # Definição do Serviço do Worker
  $nome_app_runner:
    # imagem do docker
    image: n8nio/runners:2.9.2
    # Define o hotname do container
    hostname: "$nome_app_runner"
    # comando padrão para subir os runners
    command: ["javascript", "python"]
    # configura a rede do serviço
    networks:
      - traefik_public
      - app_network
      - interna
      - externa
    # configura as variáveis de ambiente
    environment:
      # O endereço do broker é o endereço do n8n editor na rede interna do swarm
      - N8N_RUNNERS_TASK_BROKER_URI=http://$nome_app_worker:5679
      # O token é o mesmo que você configurou no n8n editor
      - N8N_RUNNERS_AUTH_TOKEN=$encryption_key2
    # Configura o Modo de Deploy da Aplicação
    deploy:
      # O editor será executado no modo de replicação
      mode: replicated
      # Vamos ter apenas uma instância do editor
      replicas: 1
      # Configura o local de execução
      placement:
        # Você pode rodar o Editor no Manager mesmo pois usa poucos recursos
        constraints:
          - node.role == manager
          # - node.hostname == worker1
          # - node.labels.app == webhooks # nome do label: app, valor do label: webhooks
      resources:
        # Definição dos Limites de Recursos deste Serviço
        limits:
          # Define a quantidade de CPU para o N8N para evitar travamento do Host
          cpus: "1"
          # Define a quantidade de RAM para o N8N para evitar travamento do Host
          memory: 1024M
      # Configura o modo de atualização do serviço
      update_config:
        # Configura o paralelismo de atualização
        parallelism: 1
        # Configura o tempo de espera entre as atualizações
        delay: 30s
        # Configura a ação em caso de falha
        order: start-first
        # Configura a ação em caso de falha
        failure_action: rollback
networks:
  traefik_public:
    external: true
    name: externa
  app_network:
    external: true
    name: interna


  interna:
    external: true
  externa:
    external: true

EOL

if [[ "$criar_portainer" == "0" ]]; then
    echo -e "XXX\n76\nCRIANDO STACK NO PORTAINER 3/4  \nXXX"
dados_file="$HOME/dados_portainer/dados_portainer"
if [[ -f "$dados_file" ]]; then
PORTAINER_URL=$(grep "Dominio do portainer:" "$dados_file" | cut -d':' -f2 | xargs)
ADMIN_USERNAME=$(grep "Usuario:" "$dados_file" | cut -d':' -f2 | xargs)
ADMIN_PASSWORD=$(grep "Senha:" "$dados_file" | cut -d':' -f2 | xargs)
STACK_NAME=$nome_app_runner
STACK_FILE_PATH="/root/$nome_app_runner.yaml"
else
    sleep 5
echo -e "XXX\n77\nSEM ARQUIVO DE DADOS DO PORTAINER 3/4  \nXXX"
docker stack deploy --prune --resolve-image always -c $nome_app_runner.yaml $nome_app_runner >/dev/null 2>&1
sleep 5
    exit 1
fi
get_auth_token() {
    echo -e "XXX\n77\nAUTENTICANDO NO PORTAINER... 3/4  \nXXX"
    RESPONSE=$(curl -sS -X POST "https://$PORTAINER_URL/api/auth" \
        -H "Content-Type: application/json" \
        -d "{\"username\": \"$ADMIN_USERNAME\", \"password\": \"$ADMIN_PASSWORD\"}")
    TOKEN=$(echo "$RESPONSE" | jq -r '.jwt')
    if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]; then
        echo -e "XXX\n77\nFALHA NA AUTENTICAÇÃO.. 3/4  \nXXX"
sleep 5
echo -e "XXX\n78\nREVERTENDO E CRIANDO STACK PELO SERVIDOR 3/4  \nXXX"
docker stack deploy --prune --resolve-image always -c $nome_app_runner.yaml $nome_app_runner >/dev/null 2>&1
sleep 5
        exit 1
    fi
 echo -e "XXX\n79\n[SUCESSO] AUTENTICAÇÃO OK 3/4  \nXXX"
}
get_endpoint_id() {
    echo -e "XXX\n80\n[INFO] OBTENDO ENDPOINTID 3/4  \nXXX"
    RESPONSE=$(curl -sS -X GET "https://$PORTAINER_URL/api/endpoints" \
        -H "Authorization: Bearer $TOKEN")
    ENDPOINT_ID=$(echo "$RESPONSE" | jq -r '.[0].Id')
    if [ -z "$ENDPOINT_ID" ] || [ "$ENDPOINT_ID" = "null" ]; then
        echo -e "XXX\n81\n[ERRO] ENDPOINTID NÃO ENCONTRADO 3/4  \nXXX"
        docker stack deploy --prune --resolve-image always -c $nome_app_runner.yaml $nome_app_runner >/dev/null 2>&1
        exit 1
    fi
     echo -e "XXX\n82\n[SUCESSO] ENDPOINTID OBTIDO: $ENDPOINT_ID  3/4  \nXXX"
}
get_swarm_id() {
    echo -e "XXX\n83\n[INFO] OBTENDO SWARMID  3/4  \nXXX"
    RESPONSE=$(curl -sS -X GET "https://$PORTAINER_URL/api/endpoints/$ENDPOINT_ID/docker/swarm" \
        -H "Authorization: Bearer $TOKEN")
    SWARM_ID=$(echo "$RESPONSE" | jq -r '.ID')
    if [ -z "$SWARM_ID" ] || [ "$SWARM_ID" = "null" ]; then
        echo -e "XXX\n84\n[ERRO] SWARMID NÃO ENCONTRADO 3/4  \nXXX"
        docker stack deploy --prune --resolve-image always -c $nome_app_runner.yaml $nome_app_runner >/dev/null 2>&1
        exit 1
    fi
    echo -e "XXX\n85\n[SUCESSO] SWARMID OBTIDO: $SWARM_ID  3/4  \nXXX"
}

create_stack() {
    echo -e "XXX\n86\n[INFO] VERIFICANDO SE YAML EXISTE 3/4  \nXXX"
    if [ ! -f "$STACK_FILE_PATH" ]; then
        echo -e "XXX\n87\n[ERRO] ARQUIVO $STACK_FILE_PATH NÃO ENCONTRADO 3/4  \nXXX"
        docker stack deploy --prune --resolve-image always -c $nome_app_runner.yaml $nome_app_runner >/dev/null 2>&1
        exit 1
    fi
     echo -e "XXX\n88\n[INFO] CRIANDO STACK $STACK_NAME NO PORTAINER 3/4  \nXXX"
    response_output=$(mktemp)
    erro_output=$(mktemp)
    http_code=$(curl -s -o "$response_output" -w "%{http_code}"  -X POST \
        -H "Authorization: Bearer $TOKEN" \
        -F "Name=$STACK_NAME" \
        -F "file=@$STACK_FILE_PATH" \
        -F "SwarmID=$SWARM_ID" \
        -F "endpointId=$ENDPOINT_ID" \
        "https://$PORTAINER_URL/api/stacks/create/swarm/file" 2> "$erro_output")
    response=$(cat "$response_output")
    rm -f "$response_output" "$erro_output"
    if [ "$http_code" -ne 200 ]; then
        echo -e "XXX\n89\n[ERRO] ERRO AO CRIAR STACK 3/4  \nXXX"
        docker stack deploy --prune --resolve-image always -c $nome_app_runner.yaml $nome_app_runner >/dev/null 2>&1
        exit 1
    fi
    echo -e "XXX\n90\n[SUCESSO] STACK $STACK_NAME  CRIADA COM SUCESSO 3/4  \nXXX"
}
get_auth_token || exit 1
get_endpoint_id || exit 1
get_swarm_id || exit 1
create_stack || exit 1
elif [[ "$criar_portainer" == "1" ]]; then
    echo "Criando a stack diretamente no Docker (não editável no Portainer)."
    docker stack deploy --prune --resolve-image always -c $nome_app_runner.yaml $nome_app_runner >/dev/null 2>&1
else
    echo -e "XXX\n91\n[ERRO] ERRO INESPERADO PARA CRIAR STACK NO PORTAINER 3/4  \nXXX"
    sleep 5
    echo -e "XXX\n92\nREVERTENDO E CRIANDO STACK PELO SERVIDOR 3/4  \nXXX"
docker stack deploy --prune --resolve-image always -c $nome_app_runner.yaml $nome_app_runner >/dev/null 2>&1
sleep 5
    exit 1
fi
echo -e "XXX\n93\nFINALIZANDO BUILD DO N8N 4/4  \nXXX"
sleep 12
echo -e "XXX\n100\nFINALIZANDO BUILD DO N8N 4/4 - CONCLUIDO  \nXXX"
sleep 3
}|whiptail --title "N8N V2 - PROGRESSO DA INSTALAÇÃO" --gauge "Aguarde a instalação dos ítens necessrios" 6 60 0
if [ "$INSTALL_TYPE" = "CLOUDFLARE_TUNNEL" ]; then
    failed_domains=0
    domains_to_check=""
        domains_to_check="$dominioadmin $dominiowebhook"
    for domain in $domains_to_check; do
        if ! nslookup "$domain" >/dev/null 2>&1; then
            ((failed_domains++))
        elif ! nslookup "$domain" | grep -q "${TUNNEL_ID}.cfargotunnel.com"; then
            :
        else
            :
        fi
    done
    if [ $failed_domains -eq 0 ]; then
        whiptail --title "Sucesso" --msgbox "Instalação concluída com sucesso! Cloudflare Tunnel configurado.\n\nAcessos:\n- N8N Admin: https://$dominioadmin\n- N8N Webhooks: https://$dominiowebhook\n\nPressione ENTER para voltar ao Menu Principal" 20 78
    else
        whiptail --title "Aviso" --msgbox "Instalação concluída, mas $failed_domains domínio(s) podem precisar de ajustes no DNS.\n\nIsso é normal logo após a criação - o DNS pode levar alguns minutos para propagar.\n\nSe o problema persistir, verifique:\n1. Os registros CNAME no Cloudflare\n2. A configuração do Tunnel\n3. As rotas no Cloudflare Tunnel\n\nPressione ENTER para voltar ao Menu Principal" 20 78
    fi
else
    # [Mantém o código existente para INSTALAÇÃO TRADICIONAL]
    ip_servidor=$(curl -s --max-time 10 ipinfo.io/ip)
    status=0
    dns_ip1=$(timeout 10 nslookup "$dominioadmin" 2>/dev/null | grep "Address" | tail -n1 | awk '{print $2}')
    dns_ip2=$(timeout 10 nslookup "$dominiowebhook" 2>/dev/null | grep "Address" | tail -n1 | awk '{print $2}')
    [[ "$dns_ip1" != "$ip_servidor" ]] && status=1
    [[ "$dns_ip2" != "$ip_servidor" ]] && status=1

    if [[ $status -eq 1 ]]; then
        whiptail --title "Erro" --msgbox "Não foi possível acessar um ou mais subdomínios. Verifique os apontamentos de DNS." 20 78
    else
        whiptail --title "Sucesso" --msgbox "Instalação concluída com sucesso! Tecle enter para continuar." 20 78
    fi
fi
exit 0

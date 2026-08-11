#!/usr/bin/bash
#########################################################
# # cloudflare tunnel - records automáticos
#    LOADING
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
  tput reset 2>/dev/null         # Reinicia o terminal de forma segura
  exec 0</dev/tty 1>/dev/tty 2>&1 # Força redirecionamentos explícitos
  sleep 0.01                     # Pausa microscópica para sincronia
  clear                          # Limpeza final antes do whiptail
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
		whiptail --title "INSTALAÇÃO DO N8N V1 MODO FILA: PLATAFORMA DE AUTOMAÇÃO" --msgbox "$msg" --fb 10 70;
	}

  while true; do
CHOICE=$(
whiptail --title "INSTALAÇÃO DO N8N V1 MODO FILA: PLATAFORMA DE AUTOMAÇÃO" --menu "Aperte ENTER para iniciar a instalação do N8N modo fila ou selecione SAIR (Utilize setas e Enter)\n\nTIPO DE INSTALAÇÃO DETECTADA: $INSTALL_TYPE\n\nINSTRUÇÕES:\nAntes de prosseguir, verifique os registros DNS conforme seu tipo de instalação:" 20 70 2 \
	"1)" "CONTINUAR"   \
	"2)" "SAIR"  3>&2 2>&1 1>&3	
)

case $CHOICE in
	"1)")   
		clear
        break
	;;
	
	"2)") 
       # sleep 1
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


    
 ## Verifica se a porta é 465, se sim deixa o ssl true, se não, deixa false 
    if [ "$portasmtp" -eq 465 ]; then
    SECURE=false
    else
    SECURE=true
    fi      

# Perguntar ao usuário se deseja criar a stack no Portainer

 while true ; do
		criar_portainer=$(whiptail --title "Criar Stack no Portainer? - 0 ou 1" --inputbox "Digite 0 para poder editar stack no portainer ou 1 para não poder editar" --fb 12 60 3>&1 1>&2 2>&3) ; saida=$?
		if [[ $saida -eq '0' ]] ; then
		#	if [[ -z $senhamautic ]] ; then msg "Digite a senha do Mautic, para poder continuar" ; continue ; else break; fi
		if [[ "$criar_portainer" != "0" && "$criar_portainer" != "1" ]] ; then msg "Digite apenas o número 0 ou o número 1, para poder continuar. Digite 0 para poder editar stack no portainer ou 1 para não poder editar" ; continue ; else break; fi
    else
			echo $criar_portainer ; echo "saindo..."  &  exit 0 ;
		fi
	done
     
     
clear



#
# FIM DE PERGUNTAS PARA VARIAVEIS
#
#########################################################
#
# VERIFICAÇÃO DE DADOS
#

nome_editor="n8n_editor"  #nome do app
nome_webhook="n8n_webhook"
nome_worker="n8n_worker"
nome_mcp_api="n8n_mcp_api"

nome_databse="n8n"
sufixo_app=$(date | md5sum | head -c7)
nome_app_editor=$nome_editor$sufixo_app
nome_app_webhook=$nome_webhook$sufixo_app
nome_app_worker=$nome_worker$sufixo_app
nome_app_mcp_api=$nome_mcp_api$sufixo_app
nome_app_database=$nome_databse$sufixo_app
postgres_password=$(grep -oP '(?<=POSTGRES_PASSWORD=).+' /root/postgres.yaml)
container_id=$(docker ps -qf name=postgres)
docker exec -it $container_id psql -U postgres -d postgres -c "CREATE  DATABASE $nome_app_database;" 

# Ajuste do terminal para garantir compatibilidade
{
  tput reset 2>/dev/null         # Reinicia o terminal de forma segura
  exec 0</dev/tty 1>/dev/tty 2>&1 # Força redirecionamentos explícitos
  sleep 0.01                     # Pausa microscópica para sincronia
  clear                          # Limpeza final antes do whiptail
} || true

    # Exibe as informações formatadas com mais espaço na tela
    whiptail --title "Dados Fornecidos" \
    --msgbox "TIPO DE INSTALAÇÃO: $INSTALL_TYPE\n\nDados Preenchidos:\n\n1) Link do Admin do N8N: $dominioadmin\n2) Link do Webhook do N8N: $dominiowebhook\n3) Usuário do SMTP: $user_smtp\n4) Email Remetente do SMTP: $email_smtp\n5) Senha do Email SMTP: $senha\n5)Host do SMTP: $smtp\n6) Criar Stack no Portainer: $([ "$criar_portainer" == "0" ] && echo "0 (Editável)" || echo "1 (Não editável)")\n\nConfira e Tecle Enter para continuar. Na próxima etapa você poderá confirmar os dados ou corrigir, se necessário." \
    --fb 22 80

# Solicita confirmação dentro de um loop
while true; do
# Ajuste do terminal para garantir compatibilidade
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

{

# Função para verificar o domínio
#VERIFICANDO CONFIGURAÇÃO N8N EDITOR (ADMIN)

echo -e "XXX\n5\nVERIFICANDO CONFIGURAÇÃO N8N EDITOR (ADMIN)... \nXXX"

if [ "$INSTALL_TYPE" = "TRADICIONAL" ] && [ "$criar_dns" = "0" ]; then
    # CONFIGURAÇÃO TRADICIONAL COM DNS AUTOMÁTICO
    echo -e "XXX\n10\nCONFIGURANDO DNS AUTOMÁTICO (TRADICIONAL)... \nXXX"
    
    DOMINIO_PRINCIPAL=$(echo "$dominioadmin" | cut -d'.' -f2-)
    SUBDOMINIO=${dominioadmin%%.$DOMINIO_PRINCIPAL}

    # Verificar e remover registros existentes
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

    # Criar registro CNAME
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
    # CONFIGURAÇÃO CLOUDFLARE TUNNEL - DNS E ROTAS
    echo -e "XXX\n10\nCONFIGURANDO CLOUDFLARE TUNNEL (DNS + ROTAS)... \nXXX"
    
    DOMINIO_PRINCIPAL=$(echo "$dominioadmin" | cut -d'.' -f2-)
    SUBDOMINIO=${dominioadmin%%.$DOMINIO_PRINCIPAL}

    # 1. PRIMEIRO CONFIGURAR O DNS
    echo -e "XXX\n15\nCONFIGURANDO REGISTRO DNS... \nXXX"
    
    # Verificar e remover registros existentes
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

    # Criar registro CNAME para o tunnel
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

    # 2. AGORA ATUALIZAR AS ROTAS DO TUNNEL
    echo -e "XXX\n35\nATUALIZANDO CONFIGURAÇÃO DO TUNNEL... \nXXX"

    # Configuração do novo serviço para o Rabbitmq
    NEW_SERVICE="http://${nome_app_editor}:5678"
    
    # Arquivos temporários
    TIMESTAMP=$(date -u +%Y%m%dT%H%M%SZ)
    TMPDIR=$(mktemp -d)
    BACKUP_RAW="$TMPDIR/backup_raw.$TIMESTAMP.json"
    TO_PUT="$TMPDIR/to_put.$TIMESTAMP.json"

    # 1) Obter configuração atual do tunnel
    echo -e "XXX\n40\nOBTENDO CONFIGURAÇÃO ATUAL DO TUNNEL... \nXXX"
    curl -sS -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
      "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/cfd_tunnel/$TUNNEL_ID/configurations" \
      | jq '.' > "$BACKUP_RAW"

    # Verificar se obteve sucesso
    if ! jq -e '.success == true' "$BACKUP_RAW" >/dev/null 2>&1; then
        echo -e "XXX\n45\nERRO: FALHA AO OBTER CONFIGURAÇÃO DO TUNNEL \nXXX"
        sleep 3
    else
        echo -e "XXX\n45\nCONFIGURAÇÃO OBTIDA COM SUCESSO \nXXX"
    fi

    # 2) Construir novo payload
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

    # 3) Aplicar nova configuração
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

    # Limpeza
    rm -rf "$TMPDIR"

 else
    # INSTALAÇÃO TRADICIONAL SEM DNS AUTOMÁTICO
    echo -e "XXX\n10\nVERIFICANDO CONFIGURAÇÃO (TRADICIONAL SEM AUTOMAÇÃO)... \nXXX"
    # Verificação básica de DNS
    if nslookup "$dominioadmin" >/dev/null 2>&1; then
        echo -e "XXX\n15\nDNS CONFIGURADO \nXXX"
    else
        echo -e "XXX\n15\nAVISO: VERIFIQUE A CONFIGURAÇÃO DNS \nXXX"
    fi
fi


if [ "$INSTALL_TYPE" = "TRADICIONAL" ] && [ "$criar_dns" = "1" ]; then


# Função para verificar o domínio quando fora do cloudflare

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
       # break
    fi
    
  #  sleep $((tentativa_atual * 2))
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


#VERIFICANDO CONFIGURAÇÃO N8N Webhook

echo -e "XXX\n5\nVERIFICANDO CONFIGURAÇÃO N8N Webhook... \nXXX"

if [ "$INSTALL_TYPE" = "TRADICIONAL" ] && [ "$criar_dns" = "0" ]; then
    # CONFIGURAÇÃO TRADICIONAL COM DNS AUTOMÁTICO
    echo -e "XXX\n10\nCONFIGURANDO DNS AUTOMÁTICO (TRADICIONAL)... \nXXX"
    
    DOMINIO_PRINCIPAL=$(echo "$dominiowebhook" | cut -d'.' -f2-)
    SUBDOMINIO=${dominiowebhook%%.$DOMINIO_PRINCIPAL}

    # Verificar e remover registros existentes
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

    # Criar registro CNAME
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
    # CONFIGURAÇÃO CLOUDFLARE TUNNEL - DNS E ROTAS
    echo -e "XXX\n10\nCONFIGURANDO CLOUDFLARE TUNNEL (DNS + ROTAS)... \nXXX"
    
    DOMINIO_PRINCIPAL=$(echo "$dominiowebhook" | cut -d'.' -f2-)
    SUBDOMINIO=${dominiowebhook%%.$DOMINIO_PRINCIPAL}

    # 1. PRIMEIRO CONFIGURAR O DNS
    echo -e "XXX\n15\nCONFIGURANDO REGISTRO DNS... \nXXX"
    
    # Verificar e remover registros existentes
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

    # Criar registro CNAME para o tunnel
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

    # 2. AGORA ATUALIZAR AS ROTAS DO TUNNEL
    echo -e "XXX\n35\nATUALIZANDO CONFIGURAÇÃO DO TUNNEL... \nXXX"

    # Configuração do novo serviço
  #  NEW_SERVICE="http://${$nome_app_chatwoot-app}:3000" errado
    NEW_SERVICE="http://${nome_app_webhook}:5678"
    
    # Arquivos temporários
    TIMESTAMP=$(date -u +%Y%m%dT%H%M%SZ)
    TMPDIR=$(mktemp -d)
    BACKUP_RAW="$TMPDIR/backup_raw.$TIMESTAMP.json"
    TO_PUT="$TMPDIR/to_put.$TIMESTAMP.json"

    # 1) Obter configuração atual do tunnel
    echo -e "XXX\n40\nOBTENDO CONFIGURAÇÃO ATUAL DO TUNNEL... \nXXX"
    curl -sS -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
      "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/cfd_tunnel/$TUNNEL_ID/configurations" \
      | jq '.' > "$BACKUP_RAW"

    # Verificar se obteve sucesso
    if ! jq -e '.success == true' "$BACKUP_RAW" >/dev/null 2>&1; then
        echo -e "XXX\n45\nERRO: FALHA AO OBTER CONFIGURAÇÃO DO TUNNEL \nXXX"
        sleep 3
    else
        echo -e "XXX\n45\nCONFIGURAÇÃO OBTIDA COM SUCESSO \nXXX"
    fi

    # 2) Construir novo payload
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

    # 3) Aplicar nova configuração
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

    # Limpeza
    rm -rf "$TMPDIR"


    # >>> INICIO DO CÓDIGO DO MCP PARA CLOUDFLARE TUNNEL <<<
    
    # 3. CONFIGURAR A ROTA MCP NO TUNNEL
    echo -e "XXX\n65\nCONFIGURANDO ROTA MCP NO CLOUDFLARE TUNNEL... \nXXX"

    # Configuração do serviço MCP
    NEW_SERVICE_MCP="http://${nome_app_mcp_api}:5678"

    # Arquivos temporários para MCP
    TIMESTAMP_MCP=$(date -u +%Y%m%dT%H%M%SZ)
    TMPDIR_MCP=$(mktemp -d)
    BACKUP_RAW_MCP="$TMPDIR_MCP/backup_raw_mcp.$TIMESTAMP_MCP.json"
    TO_PUT_MCP="$TMPDIR_MCP/to_put_mcp.$TIMESTAMP_MCP.json"

    # 1) Obter configuração atual do tunnel
    echo -e "XXX\n67\nOBTENDO CONFIGURAÇÃO ATUAL DO TUNNEL PARA MCP... \nXXX"
    curl -sS -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
      "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/cfd_tunnel/$TUNNEL_ID/configurations" \
      | jq '.' > "$BACKUP_RAW_MCP"

    # 2) Construir novo payload incluindo a rota MCP
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

    # 3) Aplicar nova configuração
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

    # Limpeza
    rm -rf "$TMPDIR_MCP"

  # >>> FIM DO CÓDIGO DO MCP PARA CLOUDFLARE TUNNEL <<<

 else
    # INSTALAÇÃO TRADICIONAL SEM DNS AUTOMÁTICO
    echo -e "XXX\n10\nVERIFICANDO CONFIGURAÇÃO (TRADICIONAL SEM AUTOMAÇÃO)... \nXXX"
    # Verificação básica de DNS
    if nslookup "$dominiowebhook" >/dev/null 2>&1; then
        echo -e "XXX\n15\nDNS CONFIGURADO \nXXX"
    else
        echo -e "XXX\n15\nAVISO: VERIFIQUE A CONFIGURAÇÃO DNS \nXXX"
    fi
fi


if [ "$INSTALL_TYPE" = "TRADICIONAL" ] && [ "$criar_dns" = "1" ]; then


# Função para verificar o domínio quando fora do cloudflare
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
       # break
    fi
    
  #  sleep $((tentativa_atual * 2))
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





####### fim de verificando dominio 

echo -e "XXX\n23\nCRIANDO STACKS DO N8N 1/4 \nXXX"
sleep 1
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

cat > $nome_app_editor.yaml << EOL

version: "3.7"
services:
  $nome_app_editor:
    image: n8nio/n8n:1.121.3
    command: start
    networks:
      - traefik_public
      - app_network
      - interna
      - externa
    environment:
      # Habilita o Uso de Pacotes da Comunidade
      - N8N_COMMUNITY_PACKAGES_ENABLED=true
      - N8N_COMMUNITY_PACKAGES_ALLOW_TOOL_USAGE=true
      # novas variáveis implementadas 25/03/2025
      - N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS=true
      - N8N_RUNNERS_ENABLED=false
      - N8N_RUNNERS_MODE=internal
      - OFFLOAD_MANUAL_EXECUTIONS_TO_WORKERS=false
      - N8N_NODE_PATH=/home/node/.n8n/nodes
      # Reinstala os Pacotes após um Upgrade
      - N8N_REINSTALL_MISSING_PACKAGES=true
      - DB_TYPE=postgresdb
      - DB_POSTGRESDB_DATABASE=$nome_app_database
      - DB_POSTGRESDB_HOST=postgres
      - DB_POSTGRESDB_PORT=5432
      - DB_POSTGRESDB_USER=postgres
      - DB_POSTGRESDB_PASSWORD=$postgres_password
      - N8N_ENCRYPTION_KEY=$encryption_key
      - N8N_HOST=$dominioadmin
      - N8N_EDITOR_BASE_URL=https://$dominioadmin/
      - N8N_PROTOCOL=https
      - NODE_ENV=production
      - WEBHOOK_URL=https://$dominiowebhook/
      - EXECUTIONS_MODE=queue
      - QUEUE_BULL_REDIS_HOST=redis
      - QUEUE_BULL_REDIS_PORT=6379
      - QUEUE_BULL_REDIS_DB=11
      #- QUEUE_BULL_REDIS_PASSWORD=prww4IsPPswMuaNQ
      #- NODE_FUNCTION_ALLOW_EXTERNAL=moment,lodash,moment-with-locales,axios,form-data,dayjs
      - NODE_FUNCTION_ALLOW_EXTERNAL=*
      - NODE_FUNCTION_ALLOW_BUILTIN=*
      - N8N_PAYLOAD_SIZE_MAX=512
      - EXECUTIONS_DATA_PRUNE=true
      - EXECUTIONS_DATA_MAX_AGE=336 # 2 semanas
      - N8N_VERSION_NOTIFICATIONS_ENABLED=true
      - N8N_PUBLIC_API_SWAGGERUI_DISABLED=false
      - N8N_EMAIL_MODE=smtp
      - N8N_SMTP_HOST=$smtp
      - N8N_SMTP_PORT=$portasmtp
      - N8N_SMTP_USER=$user_smtp
      - N8N_SMTP_PASS=$senha
      - N8N_SMTP_SENDER=$email_smtp
      - N8N_SMTP_SSL=$SECURE
      # Configuracao de IA (ajuda nos node code)
      - N8N_AI_ENABLED=false
      - N8N_AI_PROVIDER=openai
      - N8N_AI_OPENAI_API_KE=
      # Armazenamento S3
      #- N8N_EXTERNAL_STORAGE_S3_HOST=s3.seusite.com.br
      #- N8N_EXTERNAL_STORAGE_S3_BUCKET_NAME=n8n
      #- N8N_EXTERNAL_STORAGE_S3_BUCKET_REGION=eu-south 
      #- N8N_EXTERNAL_STORAGE_S3_ACCESS_KEY= 
      #- N8N_EXTERNAL_STORAGE_S3_ACCESS_SECRET=
    volumes:
    - $nome_app_database-data:/data/backup
    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
          - node.role == manager
          # - node.hostname == worker1
          # - node.labels.app == http # nome do label: app, valor do label: http
     # resources:
      #  limits:
          # cpus: "4"
          # memory: 2048M
EOL
# Adicionar as labels apenas se for instalação tradicional
if [ "$INSTALL_TYPE" = "TRADICIONAL" ]; then
cat >> $nome_app_editor.yaml << EOL
      labels:
        - traefik.enable=true
        - traefik.http.routers.$nome_app_editor.rule=Host(\`$dominioadmin\`)
        - traefik.http.routers.$nome_app_editor.entrypoints=websecure
        - traefik.http.routers.$nome_app_editor.tls.certresolver=letsencryptresolver
        - traefik.http.routers.$nome_app_editor.service=$nome_app_editor
        - traefik.http.services.$nome_app_editor.loadbalancer.server.port=5678
        - traefik.http.services.$nome_app_editor.loadbalancer.passHostHeader=true
EOL
fi
cat >> $nome_app_editor.yaml << EOL
volumes:
  $nome_app_database-data:
    external: true
    name: $nome_app_database-datad

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

#docker stack deploy --prune --resolve-image always -c $nome_app_editor.yaml $nome_app_editor >/dev/null 2>&1

if [[ "$criar_portainer" == "0" ]]; then
    # A stack será criada no Portainer
    echo -e "XXX\n29\nCRIANDO STACK NO PORTAINER 3/4  \nXXX"

# Configurações

# Caminho para o arquivo de dados
dados_file="$HOME/dados_portainer/dados_portainer"

# Verifica se o arquivo existe
if [[ -f "$dados_file" ]]; then
    # Coleta as informações do arquivo
PORTAINER_URL=$(grep "Dominio do portainer:" "$dados_file" | cut -d':' -f2 | xargs)
ADMIN_USERNAME=$(grep "Usuario:" "$dados_file" | cut -d':' -f2 | xargs)
ADMIN_PASSWORD=$(grep "Senha:" "$dados_file" | cut -d':' -f2 | xargs)
STACK_NAME=$nome_app_editor
STACK_FILE_PATH="/root/$nome_app_editor.yaml"

else
   # echo "Erro: Arquivo de dados não encontrado em $dados_file."
    sleep 5
echo -e "XXX\n30\nSEM ARQUIVO DE DADOS DO PORTAINER 3/4  \nXXX"
docker stack deploy --prune --resolve-image always -c $nome_app_editor.yaml $nome_app_editor >/dev/null 2>&1
sleep 5
    exit 1
fi

# Função para autenticação
get_auth_token() {
    #echo "[INFO] Autenticando no Portainer..."
    echo -e "XXX\n31\nAUTENTICANDO NO PORTAINER... 3/4  \nXXX"
    RESPONSE=$(curl -sS -X POST "https://$PORTAINER_URL/api/auth" \
        -H "Content-Type: application/json" \
        -d "{\"username\": \"$ADMIN_USERNAME\", \"password\": \"$ADMIN_PASSWORD\"}")
    TOKEN=$(echo "$RESPONSE" | jq -r '.jwt')
    if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]; then
        # echo "[ERRO] Falha na autenticação."
        echo -e "XXX\n32\nFALHA NA AUTENTICAÇÃO.. 3/4  \nXXX"
sleep 5
echo -e "XXX\n33\nREVERTENDO E CRIANDO STACK PELO SERVIDOR 3/4  \nXXX"
docker stack deploy --prune --resolve-image always -c $nome_app_editor.yaml $nome_app_editor >/dev/null 2>&1
sleep 5
        exit 1
    fi
  #  echo "[SUCESSO] Autenticação realizada com sucesso. Token obtido."
 echo -e "XXX\n34\n[SUCESSO] AUTENTICAÇÃO OK 3/4  \nXXX"
}

# Função para obter o EndpointID
get_endpoint_id() {
   # echo "[INFO] Obtendo EndpointID..."
    echo -e "XXX\n35\n[INFO] OBTENDO ENDPOINTID 3/4  \nXXX"
    RESPONSE=$(curl -sS -X GET "https://$PORTAINER_URL/api/endpoints" \
        -H "Authorization: Bearer $TOKEN")
    ENDPOINT_ID=$(echo "$RESPONSE" | jq -r '.[0].Id')
    if [ -z "$ENDPOINT_ID" ] || [ "$ENDPOINT_ID" = "null" ]; then
        # echo "[ERRO] EndpointID não encontrado! Resposta: $RESPONSE"
        echo -e "XXX\n36\n[ERRO] ENDPOINTID NÃO ENCONTRADO 3/4  \nXXX"
        docker stack deploy --prune --resolve-image always -c $nome_app_editor.yaml $nome_app_editor >/dev/null 2>&1
        exit 1
    fi
     echo -e "XXX\n37\n[SUCESSO] ENDPOINTID OBTIDO: $ENDPOINT_ID  3/4  \nXXX"
    #echo "[SUCESSO] EndpointID obtido: $ENDPOINT_ID"
}

# Função para obter o SwarmID
get_swarm_id() {
   # echo "[INFO] Obtendo SwarmID..."
    echo -e "XXX\n38\n[INFO] OBTENDO SWARMID  3/4  \nXXX"
    RESPONSE=$(curl -sS -X GET "https://$PORTAINER_URL/api/endpoints/$ENDPOINT_ID/docker/swarm" \
        -H "Authorization: Bearer $TOKEN")
    SWARM_ID=$(echo "$RESPONSE" | jq -r '.ID')
    if [ -z "$SWARM_ID" ] || [ "$SWARM_ID" = "null" ]; then
        #echo "[ERRO] SwarmID não encontrado! Resposta: $RESPONSE"
        echo -e "XXX\n39\n[ERRO] SWARMID NÃO ENCONTRADO 3/4  \nXXX"
        docker stack deploy --prune --resolve-image always -c $nome_app_editor.yaml $nome_app_editor >/dev/null 2>&1
        exit 1
    fi
    #echo "[SUCESSO] SwarmID obtido: $SWARM_ID"
    echo -e "XXX\n40\n[SUCESSO] SWARMID OBTIDO: $SWARM_ID  3/4  \nXXX"
}

# Função para criar a stack
create_stack() {
    #echo "[INFO] Verificando existência do arquivo YAML..."
    echo -e "XXX\n41\n[INFO] VERIFICANDO SE YAML EXISTE 3/4  \nXXX"
    if [ ! -f "$STACK_FILE_PATH" ]; then
        #echo "[ERRO] Arquivo $STACK_FILE_PATH não encontrado!"
        echo -e "XXX\n42\n[ERRO] ARQUIVO $STACK_FILE_PATH NÃO ENCONTRADO 3/4  \nXXX"
        docker stack deploy --prune --resolve-image always -c $nome_app_editor.yaml $nome_app_editor >/dev/null 2>&1
        exit 1
    fi

    #echo "[INFO] Criando stack '$STACK_NAME' no Portainer..."
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

   # echo "[DEBUG] Resposta da criação da stack: $response"
   # echo "[DEBUG] Código HTTP: $http_code"

    if [ "$http_code" -ne 200 ]; then
       # echo "[ERRO] Erro ao criar a stack. Código HTTP: $http_code. Resposta: $response"
        echo -e "XXX\n44\n[ERRO] ERRO AO CRIAR STACK 3/4  \nXXX"
        docker stack deploy --prune --resolve-image always -c $nome_app_editor.yaml $nome_app_editor >/dev/null 2>&1
        exit 1
    fi

   # echo "[SUCESSO] Stack '$STACK_NAME' criada com sucesso!"
    echo -e "XXX\n45\n[SUCESSO] STACK $STACK_NAME  CRIADA COM SUCESSO 3/4  \nXXX"
}

# Fluxo de execução principal
# echo "[INFO] Iniciando processo de criação da stack..."
get_auth_token || exit 1
get_endpoint_id || exit 1
get_swarm_id || exit 1
create_stack || exit 1
# echo "[SUCESSO] Processo concluído."




elif [[ "$criar_portainer" == "1" ]]; then
    # A stack será criada diretamente no Docker
    echo "Criando a stack diretamente no Docker (não editável no Portainer)."
    docker stack deploy --prune --resolve-image always -c $nome_app_editor.yaml $nome_app_editor >/dev/null 2>&1
else
    # Caso inesperado (não deve ocorrer devido à validação anterior no while loop)
   # echo "Erro: valor inesperado para criar_portainer. Encerrando..."
    echo -e "XXX\n46\n[ERRO] ERRO INESPERADO PARA CRIAR STACK NO PORTAINER 3/4  \nXXX"
    sleep 5
    echo -e "XXX\n47\nREVERTENDO E CRIANDO STACK PELO SERVIDOR 3/4  \nXXX"
docker stack deploy --prune --resolve-image always -c $nome_app_editor.yaml $nome_app_editor >/dev/null 2>&1
sleep 5

    exit 1
fi


clear

# FIM DE INSTALANDO O n8n_editor
#
#######################################################

#######################################################
#
#  INSTALANDO O n8n_webhook
#

cd

cd
clear

cat > $nome_app_webhook.yaml << EOL

version: "3.7"
services:
  $nome_app_webhook:
    image: n8nio/n8n:1.121.3
    command: webhook
    networks:
      - traefik_public
      - app_network
      - interna
      - externa
    environment:
      # Habilita o Uso de Pacotes da Comunidade
      - N8N_COMMUNITY_PACKAGES_ENABLED=true
      - N8N_COMMUNITY_PACKAGES_ALLOW_TOOL_USAGE=true
      # novas variáveis implementadas 25/03/2025
      - N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS=true
      - N8N_RUNNERS_ENABLED=false
      - N8N_RUNNERS_MODE=internal
      - OFFLOAD_MANUAL_EXECUTIONS_TO_WORKERS=false
      - N8N_NODE_PATH=/home/node/.n8n/nodes
      # Reinstala os Pacotes aps um Upgrade
      - N8N_REINSTALL_MISSING_PACKAGES=true
      - DB_TYPE=postgresdb
      - DB_POSTGRESDB_DATABASE=$nome_app_database
      - DB_POSTGRESDB_HOST=postgres
      - DB_POSTGRESDB_PORT=5432
      - DB_POSTGRESDB_USER=postgres
      - DB_POSTGRESDB_PASSWORD=$postgres_password
      - N8N_ENCRYPTION_KEY=$encryption_key
      - N8N_HOST=$dominioadmin
      - N8N_EDITOR_BASE_URL=https://$dominioadmin/
      - N8N_PROTOCOL=https
      - NODE_ENV=production
      - WEBHOOK_URL=https://$dominiowebhook/
      - EXECUTIONS_MODE=queue
      - QUEUE_BULL_REDIS_HOST=redis
      - QUEUE_BULL_REDIS_PORT=6379
      - QUEUE_BULL_REDIS_DB=11
      #- QUEUE_BULL_REDIS_PASSWORD=prww4IsPPswMuaNQ
      #- NODE_FUNCTION_ALLOW_EXTERNAL=moment,lodash,moment-with-locales,axios
      - NODE_FUNCTION_ALLOW_EXTERNAL=*
      - NODE_FUNCTION_ALLOW_BUILTIN=*
      - N8N_PAYLOAD_SIZE_MAX=512
      - EXECUTIONS_DATA_PRUNE=true
      - EXECUTIONS_DATA_MAX_AGE=336 # 2 semanas
      - N8N_VERSION_NOTIFICATIONS_ENABLED=true
      - N8N_PUBLIC_API_SWAGGERUI_DISABLED=false
      - N8N_EMAIL_MODE=smtp
      - N8N_SMTP_HOST=$smtp
      - N8N_SMTP_PORT=$portasmtp
      - N8N_SMTP_USER=$user_smtp
      - N8N_SMTP_PASS=$senha
      - N8N_SMTP_SENDER=$email_smtp
      - N8N_SMTP_SSL=$SECURE
      # Configuracao de IA (ajuda nos node code)
      - N8N_AI_ENABLED=false
      - N8N_AI_PROVIDER=openai
      - N8N_AI_OPENAI_API_KE=
      # Armazenamento S3
      #- N8N_EXTERNAL_STORAGE_S3_HOST=s3.seusite.com.br
      #- N8N_EXTERNAL_STORAGE_S3_BUCKET_NAME=n8n
      #- N8N_EXTERNAL_STORAGE_S3_BUCKET_REGION=eu-south 
      #- N8N_EXTERNAL_STORAGE_S3_ACCESS_KEY= 
      #- N8N_EXTERNAL_STORAGE_S3_ACCESS_SECRET=
    deploy:
      mode: replicated
      replicas: 2
      placement:
        constraints:
          - node.role == manager
          # - node.hostname == worker1
          # - node.labels.app == workers # nome do label: app, valor do label: workers
     # resources:
       # limits:
        #  cpus: "1"
         # memory: 2048M
EOL
# Adicionar as labels apenas se for instalação tradicional
if [ "$INSTALL_TYPE" = "TRADICIONAL" ]; then
cat >> $nome_app_webhook.yaml << EOL
      labels:
        - traefik.enable=true
        - traefik.http.routers.$nome_app_webhook.rule=Host(\`$dominiowebhook\`)
        - traefik.http.routers.$nome_app_webhook.entrypoints=websecure
        - traefik.http.routers.$nome_app_webhook.tls.certresolver=letsencryptresolver
        - traefik.http.routers.$nome_app_webhook.service=$nome_app_webhook
        - traefik.http.services.$nome_app_webhook.loadbalancer.server.port=5678
        - traefik.http.services.$nome_app_webhook.loadbalancer.passHostHeader=true
EOL
fi
cat >> $nome_app_webhook.yaml << EOL
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

#docker stack deploy --prune --resolve-image always -c $nome_app_webhook.yaml $nome_app_webhook >/dev/null 2>&1


if [[ "$criar_portainer" == "0" ]]; then
    # A stack será criada no Portainer
    echo -e "XXX\n48\nCRIANDO STACK NO PORTAINER 3/4  \nXXX"


# Configurações

# Caminho para o arquivo de dados
dados_file="$HOME/dados_portainer/dados_portainer"

# Verifica se o arquivo existe
if [[ -f "$dados_file" ]]; then
    # Coleta as informações do arquivo
PORTAINER_URL=$(grep "Dominio do portainer:" "$dados_file" | cut -d':' -f2 | xargs)
ADMIN_USERNAME=$(grep "Usuario:" "$dados_file" | cut -d':' -f2 | xargs)
ADMIN_PASSWORD=$(grep "Senha:" "$dados_file" | cut -d':' -f2 | xargs)
STACK_NAME=$nome_app_webhook
STACK_FILE_PATH="/root/$nome_app_webhook.yaml"

else
   # echo "Erro: Arquivo de dados não encontrado em $dados_file."
    sleep 5
echo -e "XXX\n49\nSEM ARQUIVO DE DADOS DO PORTAINER 3/4  \nXXX"
docker stack deploy --prune --resolve-image always -c $nome_app_webhook.yaml $nome_app_webhook >/dev/null 2>&1
sleep 5
    exit 1
fi

# Função para autenticação
get_auth_token() {
    #echo "[INFO] Autenticando no Portainer..."
    echo -e "XXX\n50\nAUTENTICANDO NO PORTAINER... 3/4  \nXXX"
    RESPONSE=$(curl -sS -X POST "https://$PORTAINER_URL/api/auth" \
        -H "Content-Type: application/json" \
        -d "{\"username\": \"$ADMIN_USERNAME\", \"password\": \"$ADMIN_PASSWORD\"}")
    TOKEN=$(echo "$RESPONSE" | jq -r '.jwt')
    if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]; then
        # echo "[ERRO] Falha na autenticação."
        echo -e "XXX\n51\nFALHA NA AUTENTICAÇÃO.. 3/4  \nXXX"
sleep 5
echo -e "XXX\n52\nREVERTENDO E CRIANDO STACK PELO SERVIDOR 3/4  \nXXX"
docker stack deploy --prune --resolve-image always -c $nome_app_webhook.yaml $nome_app_webhook >/dev/null 2>&1
sleep 5
        exit 1
    fi
  #  echo "[SUCESSO] Autenticação realizada com sucesso. Token obtido."
 echo -e "XXX\n53\n[SUCESSO] AUTENTICAÇÃO OK 3/4  \nXXX"
}

# Função para obter o EndpointID
get_endpoint_id() {
   # echo "[INFO] Obtendo EndpointID..."
    echo -e "XXX\n54\n[INFO] OBTENDO ENDPOINTID 3/4  \nXXX"
    RESPONSE=$(curl -sS -X GET "https://$PORTAINER_URL/api/endpoints" \
        -H "Authorization: Bearer $TOKEN")
    ENDPOINT_ID=$(echo "$RESPONSE" | jq -r '.[0].Id')
    if [ -z "$ENDPOINT_ID" ] || [ "$ENDPOINT_ID" = "null" ]; then
        # echo "[ERRO] EndpointID não encontrado! Resposta: $RESPONSE"
        echo -e "XXX\n55\n[ERRO] ENDPOINTID NÃO ENCONTRADO 3/4  \nXXX"
        docker stack deploy --prune --resolve-image always -c $nome_app_webhook.yaml $nome_app_webhook >/dev/null 2>&1
        exit 1
    fi
     echo -e "XXX\n56\n[SUCESSO] ENDPOINTID OBTIDO: $ENDPOINT_ID  3/4  \nXXX"
    #echo "[SUCESSO] EndpointID obtido: $ENDPOINT_ID"
}

# Função para obter o SwarmID
get_swarm_id() {
   # echo "[INFO] Obtendo SwarmID..."
    echo -e "XXX\n57\n[INFO] OBTENDO SWARMID  3/4  \nXXX"
    RESPONSE=$(curl -sS -X GET "https://$PORTAINER_URL/api/endpoints/$ENDPOINT_ID/docker/swarm" \
        -H "Authorization: Bearer $TOKEN")
    SWARM_ID=$(echo "$RESPONSE" | jq -r '.ID')
    if [ -z "$SWARM_ID" ] || [ "$SWARM_ID" = "null" ]; then
        #echo "[ERRO] SwarmID não encontrado! Resposta: $RESPONSE"
        echo -e "XXX\n58\n[ERRO] SWARMID NÃO ENCONTRADO 3/4  \nXXX"
        docker stack deploy --prune --resolve-image always -c $nome_app_webhook.yaml $nome_app_webhook >/dev/null 2>&1
        exit 1
    fi
    #echo "[SUCESSO] SwarmID obtido: $SWARM_ID"
    echo -e "XXX\n59\n[SUCESSO] SWARMID OBTIDO: $SWARM_ID  3/4  \nXXX"
}

# Função para criar a stack
create_stack() {
    #echo "[INFO] Verificando existência do arquivo YAML..."
    echo -e "XXX\n60\n[INFO] VERIFICANDO SE YAML EXISTE 3/4  \nXXX"
    if [ ! -f "$STACK_FILE_PATH" ]; then
        #echo "[ERRO] Arquivo $STACK_FILE_PATH não encontrado!"
        echo -e "XXX\n61\n[ERRO] ARQUIVO $STACK_FILE_PATH NÃO ENCONTRADO 3/4  \nXXX"
        docker stack deploy --prune --resolve-image always -c $nome_app_webhook.yaml $nome_app_webhook >/dev/null 2>&1
        exit 1
    fi

    #echo "[INFO] Criando stack '$STACK_NAME' no Portainer..."
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

   # echo "[DEBUG] Resposta da criação da stack: $response"
   # echo "[DEBUG] Código HTTP: $http_code"

    if [ "$http_code" -ne 200 ]; then
       # echo "[ERRO] Erro ao criar a stack. Código HTTP: $http_code. Resposta: $response"
        echo -e "XXX\n63\n[ERRO] ERRO AO CRIAR STACK 3/4  \nXXX"
        docker stack deploy --prune --resolve-image always -c $nome_app_webhook.yaml $nome_app_webhook >/dev/null 2>&1
        exit 1
    fi

   # echo "[SUCESSO] Stack '$STACK_NAME' criada com sucesso!"
    echo -e "XXX\n64\n[SUCESSO] STACK $STACK_NAME  CRIADA COM SUCESSO 3/4  \nXXX"
}

# Fluxo de execução principal
# echo "[INFO] Iniciando processo de criação da stack..."
get_auth_token || exit 1
get_endpoint_id || exit 1
get_swarm_id || exit 1
create_stack || exit 1
# echo "[SUCESSO] Processo concluído."




elif [[ "$criar_portainer" == "1" ]]; then
    # A stack será criada diretamente no Docker
    echo "Criando a stack diretamente no Docker (não editável no Portainer)."
    docker stack deploy --prune --resolve-image always -c $nome_app_webhook.yaml $nome_app_webhook >/dev/null 2>&1
else
    # Caso inesperado (não deve ocorrer devido à validação anterior no while loop)
   # echo "Erro: valor inesperado para criar_portainer. Encerrando..."
    echo -e "XXX\n65\n[ERRO] ERRO INESPERADO PARA CRIAR STACK NO PORTAINER 3/4  \nXXX"
    sleep 5
    echo -e "XXX\n66\nREVERTENDO E CRIANDO STACK PELO SERVIDOR 3/4  \nXXX"
docker stack deploy --prune --resolve-image always -c $nome_app_webhook.yaml $nome_app_webhook >/dev/null 2>&1
sleep 5

    exit 1
fi


clear

# FIM DE INSTALANDO O n8n_webhook
#
#######################################################


#######################################################
#
#  INSTALANDO O n8n_mcp_api
#

cd

cd
clear

cat > $nome_app_mcp_api.yaml << EOL

version: "3.7"
services:
  $nome_app_mcp_api:
    image: n8nio/n8n:1.121.3
    command: webhook
    networks:
      - traefik_public
      - app_network
      - interna
      - externa
    environment:
      # Habilita o Uso de Pacotes da Comunidade
      - N8N_COMMUNITY_PACKAGES_ENABLED=true
      - N8N_COMMUNITY_PACKAGES_ALLOW_TOOL_USAGE=true
      # novas variáveis implementadas 25/03/2025
      - N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS=true
      - N8N_RUNNERS_ENABLED=false
      - N8N_RUNNERS_MODE=internal
      - OFFLOAD_MANUAL_EXECUTIONS_TO_WORKERS=false
      - N8N_NODE_PATH=/home/node/.n8n/nodes
      # Reinstala os Pacotes aps um Upgrade
      - N8N_REINSTALL_MISSING_PACKAGES=true
      - DB_TYPE=postgresdb
      - DB_POSTGRESDB_DATABASE=$nome_app_database
      - DB_POSTGRESDB_HOST=postgres
      - DB_POSTGRESDB_PORT=5432
      - DB_POSTGRESDB_USER=postgres
      - DB_POSTGRESDB_PASSWORD=$postgres_password
      - N8N_ENCRYPTION_KEY=$encryption_key
      - N8N_HOST=$dominioadmin
      - N8N_EDITOR_BASE_URL=https://$dominioadmin/
      - N8N_PROTOCOL=https
      - NODE_ENV=production
      - WEBHOOK_URL=https://$dominiowebhook/
      - EXECUTIONS_MODE=queue
      - QUEUE_BULL_REDIS_HOST=redis
      - QUEUE_BULL_REDIS_PORT=6379
      - QUEUE_BULL_REDIS_DB=11
      #- QUEUE_BULL_REDIS_PASSWORD=prww4IsPPswMuaNQ
      #- NODE_FUNCTION_ALLOW_EXTERNAL=moment,lodash,moment-with-locales,axios
      - NODE_FUNCTION_ALLOW_EXTERNAL=*
      - NODE_FUNCTION_ALLOW_BUILTIN=*
      - N8N_PAYLOAD_SIZE_MAX=512
      - EXECUTIONS_DATA_PRUNE=true
      - EXECUTIONS_DATA_MAX_AGE=336 # 2 semanas
      - N8N_VERSION_NOTIFICATIONS_ENABLED=true
      - N8N_PUBLIC_API_SWAGGERUI_DISABLED=false
      - N8N_EMAIL_MODE=smtp
      - N8N_SMTP_HOST=$smtp
      - N8N_SMTP_PORT=$portasmtp
      - N8N_SMTP_USER=$user_smtp
      - N8N_SMTP_PASS=$senha
      - N8N_SMTP_SENDER=$email_smtp
      - N8N_SMTP_SSL=$SECURE
      # Configuracao de IA (ajuda nos node code)
      - N8N_AI_ENABLED=false
      - N8N_AI_PROVIDER=openai
      - N8N_AI_OPENAI_API_KE=
      # Armazenamento S3
      #- N8N_EXTERNAL_STORAGE_S3_HOST=s3.seusite.com.br
      #- N8N_EXTERNAL_STORAGE_S3_BUCKET_NAME=n8n
      #- N8N_EXTERNAL_STORAGE_S3_BUCKET_REGION=eu-south 
      #- N8N_EXTERNAL_STORAGE_S3_ACCESS_KEY= 
      #- N8N_EXTERNAL_STORAGE_S3_ACCESS_SECRET=
    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
          - node.role == manager
          # - node.hostname == worker1
          # - node.labels.app == workers # nome do label: app, valor do label: workers
     # resources:
       # limits:
        #  cpus: "1"
         # memory: 2048M
EOL
# Adicionar as labels apenas se for instalação tradicional
if [ "$INSTALL_TYPE" = "TRADICIONAL" ]; then
cat >> $nome_app_mcp_api.yaml << EOL
      labels:
        - traefik.enable=true
        - traefik.http.middlewares.nogzip.headers.customResponseHeaders.Content-Encoding=""
        - traefik.http.routers.$nome_app_mcp_api.rule=Host(\`$dominiowebhook\`) && PathPrefix(\`/mcp\`)
        - traefik.http.routers.$nome_app_mcp_api.entrypoints=websecure
        - traefik.http.routers.$nome_app_mcp_api.tls.certresolver=letsencryptresolver
        - traefik.http.routers.$nome_app_mcp_api.service=$nome_app_mcp_api
        - traefik.http.services.$nome_app_mcp_api.loadbalancer.server.port=5678
        - traefik.http.services.$nome_app_mcp_api.loadbalancer.passHostHeader=true
        - traefik.http.routers.$nome_app_mcp_api.middlewares=nogzip   
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

#docker stack deploy --prune --resolve-image always -c $nome_app_mcp_api.yaml $nome_app_mcp_api >/dev/null 2>&1


if [[ "$criar_portainer" == "0" ]]; then
    # A stack será criada no Portainer
    echo -e "XXX\n48\nCRIANDO STACK NO PORTAINER 3/4  \nXXX"

# Configurações

# Caminho para o arquivo de dados
dados_file="$HOME/dados_portainer/dados_portainer"

# Verifica se o arquivo existe
if [[ -f "$dados_file" ]]; then
    # Coleta as informações do arquivo
PORTAINER_URL=$(grep "Dominio do portainer:" "$dados_file" | cut -d':' -f2 | xargs)
ADMIN_USERNAME=$(grep "Usuario:" "$dados_file" | cut -d':' -f2 | xargs)
ADMIN_PASSWORD=$(grep "Senha:" "$dados_file" | cut -d':' -f2 | xargs)
STACK_NAME=$nome_app_mcp_api
STACK_FILE_PATH="/root/$nome_app_mcp_api.yaml"

else
   # echo "Erro: Arquivo de dados não encontrado em $dados_file."
    sleep 5
echo -e "XXX\n49\nSEM ARQUIVO DE DADOS DO PORTAINER 3/4  \nXXX"
docker stack deploy --prune --resolve-image always -c $nome_app_mcp_api.yaml $nome_app_mcp_api >/dev/null 2>&1
sleep 5
    exit 1
fi

# Função para autenticação
get_auth_token() {
    #echo "[INFO] Autenticando no Portainer..."
    echo -e "XXX\n50\nAUTENTICANDO NO PORTAINER... 3/4  \nXXX"
    RESPONSE=$(curl -sS -X POST "https://$PORTAINER_URL/api/auth" \
        -H "Content-Type: application/json" \
        -d "{\"username\": \"$ADMIN_USERNAME\", \"password\": \"$ADMIN_PASSWORD\"}")
    TOKEN=$(echo "$RESPONSE" | jq -r '.jwt')
    if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]; then
        # echo "[ERRO] Falha na autenticação."
        echo -e "XXX\n51\nFALHA NA AUTENTICAÇÃO.. 3/4  \nXXX"
sleep 5
echo -e "XXX\n52\nREVERTENDO E CRIANDO STACK PELO SERVIDOR 3/4  \nXXX"
docker stack deploy --prune --resolve-image always -c $nome_app_mcp_api.yaml $nome_app_mcp_api >/dev/null 2>&1
sleep 5
        exit 1
    fi
  #  echo "[SUCESSO] Autenticação realizada com sucesso. Token obtido."
 echo -e "XXX\n53\n[SUCESSO] AUTENTICAÇÃO OK 3/4  \nXXX"
}

# Função para obter o EndpointID
get_endpoint_id() {
   # echo "[INFO] Obtendo EndpointID..."
    echo -e "XXX\n54\n[INFO] OBTENDO ENDPOINTID 3/4  \nXXX"
    RESPONSE=$(curl -sS -X GET "https://$PORTAINER_URL/api/endpoints" \
        -H "Authorization: Bearer $TOKEN")
    ENDPOINT_ID=$(echo "$RESPONSE" | jq -r '.[0].Id')
    if [ -z "$ENDPOINT_ID" ] || [ "$ENDPOINT_ID" = "null" ]; then
        # echo "[ERRO] EndpointID não encontrado! Resposta: $RESPONSE"
        echo -e "XXX\n55\n[ERRO] ENDPOINTID NÃO ENCONTRADO 3/4  \nXXX"
        docker stack deploy --prune --resolve-image always -c $nome_app_mcp_api.yaml $nome_app_mcp_api >/dev/null 2>&1
        exit 1
    fi
     echo -e "XXX\n56\n[SUCESSO] ENDPOINTID OBTIDO: $ENDPOINT_ID  3/4  \nXXX"
    #echo "[SUCESSO] EndpointID obtido: $ENDPOINT_ID"
}

# Função para obter o SwarmID
get_swarm_id() {
   # echo "[INFO] Obtendo SwarmID..."
    echo -e "XXX\n57\n[INFO] OBTENDO SWARMID  3/4  \nXXX"
    RESPONSE=$(curl -sS -X GET "https://$PORTAINER_URL/api/endpoints/$ENDPOINT_ID/docker/swarm" \
        -H "Authorization: Bearer $TOKEN")
    SWARM_ID=$(echo "$RESPONSE" | jq -r '.ID')
    if [ -z "$SWARM_ID" ] || [ "$SWARM_ID" = "null" ]; then
        #echo "[ERRO] SwarmID não encontrado! Resposta: $RESPONSE"
        echo -e "XXX\n58\n[ERRO] SWARMID NÃO ENCONTRADO 3/4  \nXXX"
        docker stack deploy --prune --resolve-image always -c $nome_app_mcp_api.yaml $nome_app_mcp_api >/dev/null 2>&1
        exit 1
    fi
    #echo "[SUCESSO] SwarmID obtido: $SWARM_ID"
    echo -e "XXX\n59\n[SUCESSO] SWARMID OBTIDO: $SWARM_ID  3/4  \nXXX"
}

# Função para criar a stack
create_stack() {
    #echo "[INFO] Verificando existência do arquivo YAML..."
    echo -e "XXX\n60\n[INFO] VERIFICANDO SE YAML EXISTE 3/4  \nXXX"
    if [ ! -f "$STACK_FILE_PATH" ]; then
        #echo "[ERRO] Arquivo $STACK_FILE_PATH não encontrado!"
        echo -e "XXX\n61\n[ERRO] ARQUIVO $STACK_FILE_PATH NÃO ENCONTRADO 3/4  \nXXX"
        docker stack deploy --prune --resolve-image always -c $nome_app_mcp_api.yaml $nome_app_mcp_api >/dev/null 2>&1
        exit 1
    fi

    #echo "[INFO] Criando stack '$STACK_NAME' no Portainer..."
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

   # echo "[DEBUG] Resposta da criação da stack: $response"
   # echo "[DEBUG] Código HTTP: $http_code"

    if [ "$http_code" -ne 200 ]; then
       # echo "[ERRO] Erro ao criar a stack. Código HTTP: $http_code. Resposta: $response"
        echo -e "XXX\n63\n[ERRO] ERRO AO CRIAR STACK 3/4  \nXXX"
        docker stack deploy --prune --resolve-image always -c $nome_app_mcp_api.yaml $nome_app_mcp_api >/dev/null 2>&1
        exit 1
    fi

   # echo "[SUCESSO] Stack '$STACK_NAME' criada com sucesso!"
    echo -e "XXX\n64\n[SUCESSO] STACK $STACK_NAME  CRIADA COM SUCESSO 3/4  \nXXX"
}

# Fluxo de execução principal
# echo "[INFO] Iniciando processo de criação da stack..."
get_auth_token || exit 1
get_endpoint_id || exit 1
get_swarm_id || exit 1
create_stack || exit 1
# echo "[SUCESSO] Processo concluído."




elif [[ "$criar_portainer" == "1" ]]; then
    # A stack será criada diretamente no Docker
    echo "Criando a stack diretamente no Docker (não editável no Portainer)."
    docker stack deploy --prune --resolve-image always -c $nome_app_mcp_api.yaml $nome_app_mcp_api >/dev/null 2>&1
else
    # Caso inesperado (não deve ocorrer devido à validação anterior no while loop)
   # echo "Erro: valor inesperado para criar_portainer. Encerrando..."
    echo -e "XXX\n65\n[ERRO] ERRO INESPERADO PARA CRIAR STACK NO PORTAINER 3/4  \nXXX"
    sleep 5
    echo -e "XXX\n66\nREVERTENDO E CRIANDO STACK PELO SERVIDOR 3/4  \nXXX"
docker stack deploy --prune --resolve-image always -c $nome_app_mcp_api.yaml $nome_app_mcp_api >/dev/null 2>&1
sleep 5

    exit 1
fi




# FIM DE INSTALANDO O n8n_mcp_api
#
#######################################################


#######################################################



#######################################################
#
#  INSTALANDO O n8n_worker
#

cd

cd
clear


cat > $nome_app_worker.yaml << EOL

version: "3.7"
services:
  $nome_app_worker:
    image: n8nio/n8n:1.121.3
    command: worker --concurrency=10
    networks:
      - traefik_public
      - app_network
      - interna
      - externa
    environment:
      # Habilita o Uso de Pacotes da Comunidade
      - N8N_COMMUNITY_PACKAGES_ENABLED=true
      - N8N_COMMUNITY_PACKAGES_ALLOW_TOOL_USAGE=true
      # novas variáveis implementadas 25/03/2025
      - N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS=true
      - N8N_RUNNERS_ENABLED=false
      - N8N_RUNNERS_MODE=internal
      - OFFLOAD_MANUAL_EXECUTIONS_TO_WORKERS=false
      - N8N_NODE_PATH=/home/node/.n8n/nodes
      # Reinstala os Pacotes após um Upgrade
      - N8N_REINSTALL_MISSING_PACKAGES=true
      - DB_TYPE=postgresdb
      - DB_POSTGRESDB_DATABASE=$nome_app_database
      - DB_POSTGRESDB_HOST=postgres
      - DB_POSTGRESDB_PORT=5432
      - DB_POSTGRESDB_USER=postgres
      - DB_POSTGRESDB_PASSWORD=$postgres_password
      - N8N_ENCRYPTION_KEY=$encryption_key
      - N8N_HOST=$dominioadmin
      - N8N_EDITOR_BASE_URL=https://$dominioadmin/
      - N8N_PROTOCOL=https
      - NODE_ENV=production
      - WEBHOOK_URL=https://$dominiowebhook/
      - EXECUTIONS_MODE=queue
      - QUEUE_BULL_REDIS_HOST=redis
      - QUEUE_BULL_REDIS_PORT=6379
      - QUEUE_BULL_REDIS_DB=11
      #- QUEUE_BULL_REDIS_PASSWORD=prww4IsPPswMuaNQ
      #- NODE_FUNCTION_ALLOW_EXTERNAL=moment,lodash,moment-with-locales,axios
      - NODE_FUNCTION_ALLOW_EXTERNAL=*
      - NODE_FUNCTION_ALLOW_BUILTIN=*
      - N8N_PAYLOAD_SIZE_MAX=512
      - EXECUTIONS_DATA_PRUNE=true
      - EXECUTIONS_DATA_MAX_AGE=336 # 2 semanas
      - N8N_VERSION_NOTIFICATIONS_ENABLED=true
      - N8N_PUBLIC_API_SWAGGERUI_DISABLED=false
      - N8N_EMAIL_MODE=smtp
      - N8N_SMTP_HOST=$smtp
      - N8N_SMTP_PORT=$portasmtp
      - N8N_SMTP_USER=$user_smtp
      - N8N_SMTP_PASS=$senha
      - N8N_SMTP_SENDER=$email_smtp
      - N8N_SMTP_SSL=$SECURE
      # Configuracao de IA (ajuda nos node code)
      - N8N_AI_ENABLED=false
      - N8N_AI_PROVIDER=openai
      - N8N_AI_OPENAI_API_KE=
      # Armazenamento S3
      #- N8N_EXTERNAL_STORAGE_S3_HOST=s3.seusite.com.br
      #- N8N_EXTERNAL_STORAGE_S3_BUCKET_NAME=n8n
      #- N8N_EXTERNAL_STORAGE_S3_BUCKET_REGION=eu-south 
      #- N8N_EXTERNAL_STORAGE_S3_ACCESS_KEY= 
      #- N8N_EXTERNAL_STORAGE_S3_ACCESS_SECRET=
    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
          - node.role == manager
          # - node.hostname == worker1
          # - node.labels.app == webhooks # nome do label: app, valor do label: webhooks
     # resources:
      #  limits:
       #   cpus: "1"
       #   memory: 2048M
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

#docker stack deploy --prune --resolve-image always -c $nome_app_worker.yaml $nome_app_worker >/dev/null 2>&1


if [[ "$criar_portainer" == "0" ]]; then
    # A stack será criada no Portainer
    echo -e "XXX\n76\nCRIANDO STACK NO PORTAINER 3/4  \nXXX"

# Configurações

# Caminho para o arquivo de dados
dados_file="$HOME/dados_portainer/dados_portainer"

# Verifica se o arquivo existe
if [[ -f "$dados_file" ]]; then
    # Coleta as informações do arquivo
PORTAINER_URL=$(grep "Dominio do portainer:" "$dados_file" | cut -d':' -f2 | xargs)
ADMIN_USERNAME=$(grep "Usuario:" "$dados_file" | cut -d':' -f2 | xargs)
ADMIN_PASSWORD=$(grep "Senha:" "$dados_file" | cut -d':' -f2 | xargs)
STACK_NAME=$nome_app_worker
STACK_FILE_PATH="/root/$nome_app_worker.yaml"

else
   # echo "Erro: Arquivo de dados não encontrado em $dados_file."
    sleep 5
echo -e "XXX\n77\nSEM ARQUIVO DE DADOS DO PORTAINER 3/4  \nXXX"
docker stack deploy --prune --resolve-image always -c $nome_app_worker.yaml $nome_app_worker >/dev/null 2>&1
sleep 5
    exit 1
fi

# Função para autenticação
get_auth_token() {
    #echo "[INFO] Autenticando no Portainer..."
    echo -e "XXX\n77\nAUTENTICANDO NO PORTAINER... 3/4  \nXXX"
    RESPONSE=$(curl -sS -X POST "https://$PORTAINER_URL/api/auth" \
        -H "Content-Type: application/json" \
        -d "{\"username\": \"$ADMIN_USERNAME\", \"password\": \"$ADMIN_PASSWORD\"}")
    TOKEN=$(echo "$RESPONSE" | jq -r '.jwt')
    if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]; then
        # echo "[ERRO] Falha na autenticação."
        echo -e "XXX\n77\nFALHA NA AUTENTICAÇÃO.. 3/4  \nXXX"
sleep 5
echo -e "XXX\n78\nREVERTENDO E CRIANDO STACK PELO SERVIDOR 3/4  \nXXX"
docker stack deploy --prune --resolve-image always -c $nome_app_worker.yaml $nome_app_worker >/dev/null 2>&1
sleep 5
        exit 1
    fi
  #  echo "[SUCESSO] Autenticação realizada com sucesso. Token obtido."
 echo -e "XXX\n79\n[SUCESSO] AUTENTICAÇÃO OK 3/4  \nXXX"
}

# Função para obter o EndpointID
get_endpoint_id() {
   # echo "[INFO] Obtendo EndpointID..."
    echo -e "XXX\n80\n[INFO] OBTENDO ENDPOINTID 3/4  \nXXX"
    RESPONSE=$(curl -sS -X GET "https://$PORTAINER_URL/api/endpoints" \
        -H "Authorization: Bearer $TOKEN")
    ENDPOINT_ID=$(echo "$RESPONSE" | jq -r '.[0].Id')
    if [ -z "$ENDPOINT_ID" ] || [ "$ENDPOINT_ID" = "null" ]; then
        # echo "[ERRO] EndpointID não encontrado! Resposta: $RESPONSE"
        echo -e "XXX\n81\n[ERRO] ENDPOINTID NÃO ENCONTRADO 3/4  \nXXX"
        docker stack deploy --prune --resolve-image always -c $nome_app_worker.yaml $nome_app_worker >/dev/null 2>&1
        exit 1
    fi
     echo -e "XXX\n82\n[SUCESSO] ENDPOINTID OBTIDO: $ENDPOINT_ID  3/4  \nXXX"
    #echo "[SUCESSO] EndpointID obtido: $ENDPOINT_ID"
}

# Função para obter o SwarmID
get_swarm_id() {
   # echo "[INFO] Obtendo SwarmID..."
    echo -e "XXX\n83\n[INFO] OBTENDO SWARMID  3/4  \nXXX"
    RESPONSE=$(curl -sS -X GET "https://$PORTAINER_URL/api/endpoints/$ENDPOINT_ID/docker/swarm" \
        -H "Authorization: Bearer $TOKEN")
    SWARM_ID=$(echo "$RESPONSE" | jq -r '.ID')
    if [ -z "$SWARM_ID" ] || [ "$SWARM_ID" = "null" ]; then
        #echo "[ERRO] SwarmID não encontrado! Resposta: $RESPONSE"
        echo -e "XXX\n84\n[ERRO] SWARMID NÃO ENCONTRADO 3/4  \nXXX"
        docker stack deploy --prune --resolve-image always -c $nome_app_worker.yaml $nome_app_worker >/dev/null 2>&1
        exit 1
    fi
    #echo "[SUCESSO] SwarmID obtido: $SWARM_ID"
    echo -e "XXX\n85\n[SUCESSO] SWARMID OBTIDO: $SWARM_ID  3/4  \nXXX"
}

# Função para criar a stack
create_stack() {
    #echo "[INFO] Verificando existência do arquivo YAML..."
    echo -e "XXX\n86\n[INFO] VERIFICANDO SE YAML EXISTE 3/4  \nXXX"
    if [ ! -f "$STACK_FILE_PATH" ]; then
        #echo "[ERRO] Arquivo $STACK_FILE_PATH não encontrado!"
        echo -e "XXX\n87\n[ERRO] ARQUIVO $STACK_FILE_PATH NÃO ENCONTRADO 3/4  \nXXX"
        docker stack deploy --prune --resolve-image always -c $nome_app_worker.yaml $nome_app_worker >/dev/null 2>&1
        exit 1
    fi

    #echo "[INFO] Criando stack '$STACK_NAME' no Portainer..."
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

   # echo "[DEBUG] Resposta da criação da stack: $response"
   # echo "[DEBUG] Código HTTP: $http_code"

    if [ "$http_code" -ne 200 ]; then
       # echo "[ERRO] Erro ao criar a stack. Código HTTP: $http_code. Resposta: $response"
        echo -e "XXX\n89\n[ERRO] ERRO AO CRIAR STACK 3/4  \nXXX"
        docker stack deploy --prune --resolve-image always -c $nome_app_worker.yaml $nome_app_worker >/dev/null 2>&1
        exit 1
    fi

   # echo "[SUCESSO] Stack '$STACK_NAME' criada com sucesso!"
    echo -e "XXX\n90\n[SUCESSO] STACK $STACK_NAME  CRIADA COM SUCESSO 3/4  \nXXX"
}

# Fluxo de execução principal
# echo "[INFO] Iniciando processo de criação da stack..."
get_auth_token || exit 1
get_endpoint_id || exit 1
get_swarm_id || exit 1
create_stack || exit 1
# echo "[SUCESSO] Processo concluído."




elif [[ "$criar_portainer" == "1" ]]; then
    # A stack será criada diretamente no Docker
    echo "Criando a stack diretamente no Docker (não editável no Portainer)."
    docker stack deploy --prune --resolve-image always -c $nome_app_worker.yaml $nome_app_worker >/dev/null 2>&1
else
    # Caso inesperado (não deve ocorrer devido à validação anterior no while loop)
   # echo "Erro: valor inesperado para criar_portainer. Encerrando..."
    echo -e "XXX\n91\n[ERRO] ERRO INESPERADO PARA CRIAR STACK NO PORTAINER 3/4  \nXXX"
    sleep 5
    echo -e "XXX\n92\nREVERTENDO E CRIANDO STACK PELO SERVIDOR 3/4  \nXXX"
docker stack deploy --prune --resolve-image always -c $nome_app_worker.yaml $nome_app_worker >/dev/null 2>&1
sleep 5

    exit 1
fi


# FIM DE INSTALANDO O n8n_worker
#
#######################################################


echo -e "XXX\n93\nFINALIZANDO BUILD DO N8N 4/4  \nXXX"

sleep 12

echo -e "XXX\n100\nFINALIZANDO BUILD DO N8N 4/4 - CONCLUIDO  \nXXX"

sleep 3

}|whiptail --title "N8N V1 - PROGRESSO DA INSTALAÇÃO" --gauge "Aguarde a instalação dos ítens necessrios" 6 60 0

# VERIFICAÇÃO FINAL - Versão Corrigida
if [ "$INSTALL_TYPE" = "CLOUDFLARE_TUNNEL" ]; then
    failed_domains=0
    domains_to_check=""
    

        domains_to_check="$dominioadmin $dominiowebhook"


    for domain in $domains_to_check; do
        if ! nslookup "$domain" >/dev/null 2>&1; then
            ((failed_domains++))
        elif ! nslookup "$domain" | grep -q "${TUNNEL_ID}.cfargotunnel.com"; then
            # Não contar como falha imediatamente - DNS pode estar em propagação
            :
        else
            # Domínio configurado corretamente
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

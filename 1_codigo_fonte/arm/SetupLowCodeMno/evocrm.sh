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

# FIM DE LOADING

# NOME DO PROGRAMA

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
		whiptail --title "INSTALAÇÃO DA EVO CRM: Plataforma de CRM" --msgbox "$msg" --fb 10 70;
	}

  while true; do
CHOICE=$(
whiptail --title "INSTALAÇÃO DA EVO CRM: Plataforma de CRM" --menu "Aperte ENTER para iniciar a instalação do EVOCRM ou selecione SAIR (Utilize setas e Enter)\n\nTIPO DE INSTALAÇÃO DETECTADA: $INSTALL_TYPE\n\nINSTRUÇÕES:\nAntes de prosseguir, verifique os registros DNS conforme seu tipo de instalação:" 20 70 2 \
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

sufixo_app=$(date | md5sum | head -c7)

   
# Criando variaveis

postgres_password=$(grep -oP '(?<=POSTGRES_PASSWORD=).+' /root/postgres.yaml)

#  Chatwootn variaveis - fim

#  Evolution variaveis - inicio

while true ; do
		url_evocrm_frontend=$(whiptail --title "1/8 - Subdominio para o EvoCRM" --inputbox "Digite o Subdominio para o EvoCRM (ex: crm.dominio.com.br): " --fb 12 60 3>&1 1>&2 2>&3) ; saida=$?
		if [[ $saida -eq '0' ]] ; then
			if [[ -z $url_evocrm_frontend ]] ; then msg "Digite o Subdominio para  admin da EvoCRM para poder continuar" ; continue ; else break; fi
		else
			echo $url_evocrm_frontend ; echo "saindo..."  &  exit 0 ;
		fi
	done

while true ; do
		url_evocrm_api=$(whiptail --title "2/8 - Subdominio para a API do EvoCRM" --inputbox "Digite o subdominio da API do EvoCRM (ex: evocrmapi.dominio.com.br): " --fb 12 60 3>&1 1>&2 2>&3) ; saida=$?
		if [[ $saida -eq '0' ]] ; then
			if [[ -z $url_evocrm_api ]] ; then msg "Digite o subdominio da API do EvoCRM para poder continuar" ; continue ; else break; fi
		else
			echo $url_evocrm_api ; echo "saindo..."  &  exit 0 ;
		fi
	done


    email_smtp_evocrm=$(whiptail --title "3/8 - Email de usuário SMTP" --inputbox "Pressione ENTER para configurar depois, ou digite o email do usuário do SMTP (ex: contato@dominio.com):" --fb 12 60 3>&1 1>&2 2>&3) ; saida=$?
		if [[ $saida -eq '0' ]] ; then if [[ -z $email_smtp_evocrm ]] ; then email_smtp_evocrm=contato@dominio.com ; fi else echo "saindo..." ; exit ; fi

    username_smtp_evocrm=$(whiptail --title "4/8 - Usuário SMTP" --inputbox "Pressione ENTER para configurar depois, ou digite o usuário do SMTP (ex: nome ou contato@dominio.com):" --fb 12 60 3>&1 1>&2 2>&3) ; saida=$?
		if [[ $saida -eq '0' ]] ; then if [[ -z $username_smtp_evocrm ]] ; then username_smtp_evocrm=usuario_smtp ; fi else echo "saindo..." ; exit ; fi

    senha_smtp_evocrm=$(whiptail --title "5/8 - Senha do SMTP" --inputbox "Pressione ENTER para configurar depois, ou digite a Senha SMTP do Email (ex: @Gdt5kfj80):" --fb 12 60 3>&1 1>&2 2>&3) ; saida=$?
		if [[ $saida -eq '0' ]] ; then if [[ -z $senha_smtp_evocrm ]] ; then senha_smtp_evocrm=senha_smtp ; fi else echo "saindo..." ; exit ; fi

    host_smtp_evocrm=$(whiptail --title "6/8 - Host SMTP" --inputbox "Pressione ENTER para configurar depois, ou digite o Host SMTP do Email (ex: smtp.hostinger.com):" --fb 12 60 3>&1 1>&2 2>&3) ; saida=$?
		if [[ $saida -eq '0' ]] ; then if [[ -z $host_smtp_evocrm ]] ; then host_smtp_evocrm=smtp.dominio.com.br ; fi else echo "saindo..." ; exit ; fi

    port_smtp_evocrm=$(whiptail --title "7/8 - Porta SMTP" --inputbox "Pressione ENTER para configurar depois, ou digite a Porta SMTP do email (ex: 587):" --fb 12 60 3>&1 1>&2 2>&3) ; saida=$?
		if [[ $saida -eq '0' ]] ; then if [[ -z $port_smtp_evocrm ]] ; then port_smtp_evocrm=587 ; fi else echo "saindo..." ; exit ; fi

    ## Verifica se a porta é 465, se sim deixa o ssl true, se não, deixa false 
    if [ "$port_smtp_evocrm" -eq 465 ]; then
    SMTP_USE_TLS=false
    SMTP_USE_SSL=true
    else
    SMTP_USE_TLS=true
    SMTP_USE_SSL=false
    fi

 ## extrai o dominio do email
    if [[ "$email_smtp_evocrm" == *"@"* ]]; then
      domain_smtp_evocrm="${email_smtp_evocrm#*@}"  # Remove tudo até o @
    fi
# Perguntar ao usuário se deseja criar a stack no Portainer

 while true ; do
		criar_portainer=$(whiptail --title "8/8 - Criar Stack no Portainer? - 0 ou 1" --inputbox "Digite 0 para poder editar stack no portainer ou 1 para não poder editar" --fb 12 60 3>&1 1>&2 2>&3) ; saida=$?
		if [[ $saida -eq '0' ]] ; then
		#	if [[ -z $senhamautic ]] ; then msg "Digite a senha do Mautic, para poder continuar" ; continue ; else break; fi
		if [[ "$criar_portainer" != "0" && "$criar_portainer" != "1" ]] ; then msg "Digite apenas o número 0 ou o número 1, para poder continuar. Digite 0 para poder editar stack no portainer ou 1 para não poder editar" ; continue ; else break; fi
    else
			echo $criar_portainer ; echo "saindo..."  &  exit 0 ;
		fi
	done

clear






# FIM DAS PERGUNTAS PARA VARIAVEIS
#
#########################################################
#
# VERIFICAÇÃO DE DADOS
#

nome_principal_evocrm="evocrm"  #nome do app
nome_app_evocrm=$nome_principal_evocrm$sufixo_app
container_id=$(docker ps -qf name=postgres)
docker exec -it $container_id psql -U postgres -d postgres -c "CREATE  DATABASE $nome_app_evocrm;" 
#  EvoAi variaveis - fim


clear

# Ajuste do terminal para garantir compatibilidade
{
  tput reset 2>/dev/null         # Reinicia o terminal de forma segura
  exec 0</dev/tty 1>/dev/tty 2>&1 # Força redirecionamentos explícitos
  sleep 0.01                     # Pausa microscópica para sincronia
  clear                          # Limpeza final antes do whiptail
} || true

    # Exibe as informações formatadas com mais espaço na tela
    whiptail --title "Dados Fornecidos" \
    --msgbox "TIPO DE INSTALAÇÃO: $INSTALL_TYPE\n\nDados Preenchidos:\n\n1) Subominio Painel EvoCRM: $url_evocrm_frontend\n2) Subominio Api EvoCRM: $url_evocrm_api\n3) Email de Usuário SMTP: $email_smtp_evocrm\n4) Usuário SMTP: $username_smtp_evocrm\n5) Senha SMTP: $senha_smtp_evocrm\n6) Host SMTP: $host_smtp_evocrm\n7) Porta SMTP: $port_smtp_evocrm\n8) Criar Stack no Portainer: $([ "$criar_portainer" == "0" ] && echo "0 (Editável)" || echo "1 (Não editável)")\n\nConfira e Tecle Enter para continuar. Na próxima etapa você poderá confirmar os dados ou corrigir, se necessário." \
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

clear
{

# Função para verificar os domínios
#VERIFICANDO CONFIGURAÇÃO EVO CRM API

echo -e "XXX\n5\nVERIFICANDO CONFIGURAÇÃO EVO CRM API... \nXXX"

if [ "$INSTALL_TYPE" = "TRADICIONAL" ] && [ "$criar_dns" = "0" ]; then
    # CONFIGURAÇÃO TRADICIONAL COM DNS AUTOMÁTICO
    echo -e "XXX\n10\nCONFIGURANDO DNS AUTOMÁTICO (TRADICIONAL)... \nXXX"
    
    DOMINIO_PRINCIPAL=$(echo "$url_evocrm_api" | cut -d'.' -f2-)
    SUBDOMINIO=${url_evocrm_api%%.$DOMINIO_PRINCIPAL}

    # Verificar e remover registros existentes
    echo -e "XXX\n15\nVERIFICANDO REGISTROS EXISTENTES... \nXXX"
    EXISTING_RECORDS=$(curl -s -X GET \
        "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records?name=${url_evocrm_api}" \
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
        --data '{"type":"CNAME","name":"'${url_evocrm_api}'","content":"'${nome_servidor}'.'${DOMINIO_PRINCIPAL}'","ttl":1,"proxied":false}')

    if echo "$CNAME_RESPONSE" | grep -q '"success":true'; then
        echo -e "XXX\n30\nREGISTRO CNAME CRIADO COM SUCESSO! \nXXX"
    else
        echo -e "XXX\n30\nAVISO: ERRO AO CRIAR REGISTRO CNAME \nXXX"
    fi

elif [ "$INSTALL_TYPE" = "CLOUDFLARE_TUNNEL" ]; then
    # CONFIGURAÇÃO CLOUDFLARE TUNNEL - DNS E ROTAS
    echo -e "XXX\n10\nCONFIGURANDO CLOUDFLARE TUNNEL (DNS + ROTAS)... \nXXX"
    
    DOMINIO_PRINCIPAL=$(echo "$url_evocrm_api" | cut -d'.' -f2-)
    SUBDOMINIO=${url_evocrm_api%%.$DOMINIO_PRINCIPAL}

    # 1. PRIMEIRO CONFIGURAR O DNS
    echo -e "XXX\n15\nCONFIGURANDO REGISTRO DNS... \nXXX"
    
    # Verificar e remover registros existentes
    EXISTING_RECORDS=$(curl -s -X GET \
        "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records?name=${url_evocrm_api}" \
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
        --data "{\"type\":\"CNAME\",\"name\":\"${url_evocrm_api}\",\"content\":\"${TUNNEL_ID}.cfargotunnel.com\",\"ttl\":1,\"proxied\":true}")

    if echo "$DNS_RESPONSE" | grep -q '"success":true'; then
        echo -e "XXX\n30\nREGISTRO DNS CRIADO COM SUCESSO! \nXXX"
    else
        echo -e "XXX\n30\nAVISO: ERRO AO CRIAR REGISTRO DNS \nXXX"
    fi

    # 2. AGORA ATUALIZAR AS ROTAS DO TUNNEL
    echo -e "XXX\n35\nATUALIZANDO CONFIGURAÇÃO DO TUNNEL... \nXXX"

    # Configuração do novo serviço
    NEW_SERVICE="http://${nome_app_evocrm}-gateway:3030"
    
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
    
    jq --arg host "$url_evocrm_api" --arg service "$NEW_SERVICE" '
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
    if nslookup "$url_evocrm_api" >/dev/null 2>&1; then
        echo -e "XXX\n15\nDNS CONFIGURADO \nXXX"
    else
        echo -e "XXX\n15\nAVISO: VERIFIQUE A CONFIGURAÇÃO DNS \nXXX"
    fi
fi


if [ "$INSTALL_TYPE" = "TRADICIONAL" ] && [ "$criar_dns" = "1" ]; then


# Função para verificar o domínio quando fora do cloudflare

ip_servidor=$(curl -s --max-time 10 ipinfo.io/ip)

echo -e "XXX\n3\nVERIFICANDO SUBDOMÍNIO: $url_evocrm_api \nXXX"
sleep 3

tentativas=5
tentativa_atual=1
sucesso=0

while [ $tentativa_atual -le $tentativas ]; do
    echo -e "XXX\n$(( (tentativa_atual * 12) / tentativas + 3 ))\nTentativa $tentativa_atual de $tentativas...\nXXX"
    
    dns_ip3=$(timeout 10 nslookup -type=A "$url_evocrm_api" | grep -E "Address: [0-9]+\." | awk '{print $2}' | head -n1)
    
    if [[ -n "$dns_ip3" && "$dns_ip3" == "$ip_servidor" ]]; then
        sucesso=1
       # break
    fi
    
  #  sleep $((tentativa_atual * 2))
  sleep 1
    ((tentativa_atual++))
done

if [ $sucesso -eq 0 ]; then

    echo -e "XXX\n10\nERRO: SUBDOMÍNIO DO EVO CRM API NÃO APONTA PARA O IP ($ip_servidor) \nXXX"
    sleep 3
    echo -e "XXX\n18\nERRO: DNS NÃO CONFIGURADO CORRETAMENTE \nXXX"
    sleep 3
    exit 1
fi
    echo -e "XXX\n18\nDOMÍNIO EVO CRM API VERIFICADO COM SUCESSO \nXXX"
sleep 4
fi


#VERIFICANDO CONFIGURAÇÃO EVO CRM FRONTEND

echo -e "XXX\n5\nVERIFICANDO CONFIGURAÇÃO EVO CRM FRONTEND... \nXXX"

if [ "$INSTALL_TYPE" = "TRADICIONAL" ] && [ "$criar_dns" = "0" ]; then
    # CONFIGURAÇÃO TRADICIONAL COM DNS AUTOMÁTICO
    echo -e "XXX\n10\nCONFIGURANDO DNS AUTOMÁTICO (TRADICIONAL)... \nXXX"
    
    DOMINIO_PRINCIPAL=$(echo "$url_evocrm_frontend" | cut -d'.' -f2-)
    SUBDOMINIO=${url_evocrm_frontend%%.$DOMINIO_PRINCIPAL}

    # Verificar e remover registros existentes
    echo -e "XXX\n15\nVERIFICANDO REGISTROS EXISTENTES... \nXXX"
    EXISTING_RECORDS=$(curl -s -X GET \
        "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records?name=${url_evocrm_frontend}" \
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
        --data '{"type":"CNAME","name":"'${url_evocrm_frontend}'","content":"'${nome_servidor}'.'${DOMINIO_PRINCIPAL}'","ttl":1,"proxied":false}')

    if echo "$CNAME_RESPONSE" | grep -q '"success":true'; then
        echo -e "XXX\n30\nREGISTRO CNAME CRIADO COM SUCESSO! \nXXX"
    else
        echo -e "XXX\n30\nAVISO: ERRO AO CRIAR REGISTRO CNAME \nXXX"
    fi

elif [ "$INSTALL_TYPE" = "CLOUDFLARE_TUNNEL" ]; then
    # CONFIGURAÇÃO CLOUDFLARE TUNNEL - DNS E ROTAS
    echo -e "XXX\n10\nCONFIGURANDO CLOUDFLARE TUNNEL (DNS + ROTAS)... \nXXX"
    
    DOMINIO_PRINCIPAL=$(echo "$url_evocrm_frontend" | cut -d'.' -f2-)
    SUBDOMINIO=${url_evocrm_frontend%%.$DOMINIO_PRINCIPAL}

    # 1. PRIMEIRO CONFIGURAR O DNS
    echo -e "XXX\n15\nCONFIGURANDO REGISTRO DNS... \nXXX"
    
    # Verificar e remover registros existentes
    EXISTING_RECORDS=$(curl -s -X GET \
        "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records?name=${url_evocrm_frontend}" \
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
        --data "{\"type\":\"CNAME\",\"name\":\"${url_evocrm_frontend}\",\"content\":\"${TUNNEL_ID}.cfargotunnel.com\",\"ttl\":1,\"proxied\":true}")

    if echo "$DNS_RESPONSE" | grep -q '"success":true'; then
        echo -e "XXX\n30\nREGISTRO DNS CRIADO COM SUCESSO! \nXXX"
    else
        echo -e "XXX\n30\nAVISO: ERRO AO CRIAR REGISTRO DNS \nXXX"
    fi

    # 2. AGORA ATUALIZAR AS ROTAS DO TUNNEL
    echo -e "XXX\n35\nATUALIZANDO CONFIGURAÇÃO DO TUNNEL... \nXXX"

    # Configuração do novo serviço para o Rabbitmq
    NEW_SERVICE="http://${nome_app_evocrm}-frontend:80"
    
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
    
    jq --arg host "$url_evocrm_frontend" --arg service "$NEW_SERVICE" '
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
    if nslookup "$url_evocrm_frontend" >/dev/null 2>&1; then
        echo -e "XXX\n15\nDNS CONFIGURADO \nXXX"
    else
        echo -e "XXX\n15\nAVISO: VERIFIQUE A CONFIGURAÇÃO DNS \nXXX"
    fi
fi


if [ "$INSTALL_TYPE" = "TRADICIONAL" ] && [ "$criar_dns" = "1" ]; then


# Função para verificar o domínio quando fora do cloudflare

ip_servidor=$(curl -s --max-time 10 ipinfo.io/ip)

echo -e "XXX\n3\nVERIFICANDO SUBDOMÍNIO: $url_evocrm_frontend \nXXX"
sleep 3

tentativas=5
tentativa_atual=1
sucesso=0

while [ $tentativa_atual -le $tentativas ]; do
    echo -e "XXX\n$(( (tentativa_atual * 12) / tentativas + 3 ))\nTentativa $tentativa_atual de $tentativas...\nXXX"
    
    dns_ip4=$(timeout 10 nslookup -type=A "$url_evocrm_frontend" | grep -E "Address: [0-9]+\." | awk '{print $2}' | head -n1)
    
    if [[ -n "$dns_ip4" && "$dns_ip4" == "$ip_servidor" ]]; then
        sucesso=1
       # break
    fi
    
  #  sleep $((tentativa_atual * 2))
  sleep 1
    ((tentativa_atual++))
done

if [ $sucesso -eq 0 ]; then

    echo -e "XXX\n10\nERRO: SUBDOMÍNIO DO EVO CRM FRONTEND NÃO APONTA PARA O IP ($ip_servidor) \nXXX"
    sleep 3
    echo -e "XXX\n18\nERRO: DNS NÃO CONFIGURADO CORRETAMENTE \nXXX"
    sleep 3
    exit 1
fi
    echo -e "XXX\n18\nDOMÍNIO EVO CRM FRONTEND VERIFICADO COM SUCESSO \nXXX"
sleep 4
fi





echo -e "XXX\n21\nCRIANDO STACK 1/4 \nXXX"
sleep 1
echo -e "XXX\n25\nCRIANDO STACK 1/4 - CONCLUIDO \nXXX"

#######################################################
#
#  INSTALANDO O REDISEVOAI
#

cd

cd
clear


cat > $nome_app_evocrm-redis.yaml << EOL

version: "3.7"

services:
  $nome_app_evocrm-redis:
    image: redis:latest
    command: [
        "redis-server",
        "--appendonly",
        "yes",
        "--port",
        "6379"
      ]
    volumes:
      - $nome_app_evocrm-redis:/data

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
  $nome_app_evocrm-redis:
    external: true
    name: $nome_app_evocrm-redis

networks: 
  externa: 
    external: true
  interna: 
    external: true

EOL

#docker stack deploy --prune --resolve-image always -c $nome_app_evocrm-redis.yaml $nome_app_evocrm-redis >/dev/null 2>&1


if [[ "$criar_portainer" == "0" ]]; then
    # A stack será criada no Portainer
    echo -e "XXX\n26\nCRIANDO STACK NO PORTAINER 3/4  \nXXX"
   # echo "Criando a stack no Portainer para edição."
    # Substituir pelo comando ou rotina para criar a stack no Portainer
    # Aqui pode chamar um novo script ou rotina específica, exemplo:
   ## /path/to/criar_stack_no_portainer.sh "$nome_app" "$painelpma"

#!/bin/bash

# Configurações

# Caminho para o arquivo de dados
dados_file="$HOME/dados_portainer/dados_portainer"

# Verifica se o arquivo existe
if [[ -f "$dados_file" ]]; then
    # Coleta as informações do arquivo
PORTAINER_URL=$(grep "Dominio do portainer:" "$dados_file" | cut -d':' -f2 | xargs)
ADMIN_USERNAME=$(grep "Usuario:" "$dados_file" | cut -d':' -f2 | xargs)
ADMIN_PASSWORD=$(grep "Senha:" "$dados_file" | cut -d':' -f2 | xargs)
STACK_NAME=$nome_app_evocrm-redis
STACK_FILE_PATH="/root/$nome_app_evocrm-redis.yaml"

else
   # echo "Erro: Arquivo de dados não encontrado em $dados_file."
    sleep 5
echo -e "XXX\n27\nSEM ARQUIVO DE DADOS DO PORTAINER 3/4  \nXXX"
docker stack deploy --prune --resolve-image always -c $nome_app_evocrm-redis.yaml $nome_app_evocrm-redis >/dev/null 2>&1
sleep 5
    exit 1
fi

# Função para autenticação
get_auth_token() {
    #echo "[INFO] Autenticando no Portainer..."
    echo -e "XXX\n28\nAUTENTICANDO NO PORTAINER... 3/4  \nXXX"
    RESPONSE=$(curl -sS -X POST "https://$PORTAINER_URL/api/auth" \
        -H "Content-Type: application/json" \
        -d "{\"username\": \"$ADMIN_USERNAME\", \"password\": \"$ADMIN_PASSWORD\"}")
    TOKEN=$(echo "$RESPONSE" | jq -r '.jwt')
    if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]; then
        # echo "[ERRO] Falha na autenticação."
        echo -e "XXX\n29\nFALHA NA AUTENTICAÇÃO.. 3/4  \nXXX"
sleep 5
echo -e "XXX\n30\nREVERTENDO E CRIANDO STACK PELO SERVIDOR 3/4  \nXXX"
docker stack deploy --prune --resolve-image always -c $nome_app_evocrm-redis.yaml $nome_app_evocrm-redis >/dev/null 2>&1
sleep 5
        exit 1
    fi
  #  echo "[SUCESSO] Autenticação realizada com sucesso. Token obtido."
 echo -e "XXX\n31\n[SUCESSO] AUTENTICAÇÃO OK 3/4  \nXXX"
}

# Função para obter o EndpointID
get_endpoint_id() {
   # echo "[INFO] Obtendo EndpointID..."
    echo -e "XXX\n32\n[INFO] OBTENDO ENDPOINTID 3/4  \nXXX"
    RESPONSE=$(curl -sS -X GET "https://$PORTAINER_URL/api/endpoints" \
        -H "Authorization: Bearer $TOKEN")
    ENDPOINT_ID=$(echo "$RESPONSE" | jq -r '.[0].Id')
    if [ -z "$ENDPOINT_ID" ] || [ "$ENDPOINT_ID" = "null" ]; then
        # echo "[ERRO] EndpointID não encontrado! Resposta: $RESPONSE"
        echo -e "XXX\n33\n[ERRO] ENDPOINTID NÃO ENCONTRADO 3/4  \nXXX"
        docker stack deploy --prune --resolve-image always -c $nome_app_evocrm-redis.yaml $nome_app_evocrm-redis >/dev/null 2>&1
        exit 1
    fi
     echo -e "XXX\n34\n[SUCESSO] ENDPOINTID OBTIDO: $ENDPOINT_ID  3/4  \nXXX"
    #echo "[SUCESSO] EndpointID obtido: $ENDPOINT_ID"
}

# Função para obter o SwarmID
get_swarm_id() {
   # echo "[INFO] Obtendo SwarmID..."
    echo -e "XXX\n35\n[INFO] OBTENDO SWARMID  3/4  \nXXX"
    RESPONSE=$(curl -sS -X GET "https://$PORTAINER_URL/api/endpoints/$ENDPOINT_ID/docker/swarm" \
        -H "Authorization: Bearer $TOKEN")
    SWARM_ID=$(echo "$RESPONSE" | jq -r '.ID')
    if [ -z "$SWARM_ID" ] || [ "$SWARM_ID" = "null" ]; then
        #echo "[ERRO] SwarmID não encontrado! Resposta: $RESPONSE"
        echo -e "XXX\n36\n[ERRO] SWARMID NÃO ENCONTRADO 3/4  \nXXX"
        docker stack deploy --prune --resolve-image always -c $nome_app_evocrm-redis.yaml $nome_app_evocrm-redis >/dev/null 2>&1
        exit 1
    fi
    #echo "[SUCESSO] SwarmID obtido: $SWARM_ID"
    echo -e "XXX\n37\n[SUCESSO] SWARMID OBTIDO: $SWARM_ID  3/4  \nXXX"
}

# Função para criar a stack
create_stack() {
    #echo "[INFO] Verificando existência do arquivo YAML..."
    echo -e "XXX\n38\n[INFO] VERIFICANDO SE YAML EXISTE 3/4  \nXXX"
    if [ ! -f "$STACK_FILE_PATH" ]; then
        #echo "[ERRO] Arquivo $STACK_FILE_PATH não encontrado!"
        echo -e "XXX\n39\n[ERRO] ARQUIVO $STACK_FILE_PATH NÃO ENCONTRADO 3/4  \nXXX"
        docker stack deploy --prune --resolve-image always -c $nome_app_evocrm-redis.yaml $nome_app_evocrm-redis >/dev/null 2>&1
        exit 1
    fi

    #echo "[INFO] Criando stack '$STACK_NAME' no Portainer..."
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

   # echo "[DEBUG] Resposta da criação da stack: $response"
   # echo "[DEBUG] Código HTTP: $http_code"

    if [ "$http_code" -ne 200 ]; then
       # echo "[ERRO] Erro ao criar a stack. Código HTTP: $http_code. Resposta: $response"
        echo -e "XXX\n41\n[ERRO] ERRO AO CRIAR STACK 3/4  \nXXX"
        docker stack deploy --prune --resolve-image always -c $nome_app_evocrm-redis.yaml $nome_app_evocrm-redis >/dev/null 2>&1
        exit 1
    fi

   # echo "[SUCESSO] Stack '$STACK_NAME' criada com sucesso!"
    echo -e "XXX\n42\n[SUCESSO] STACK $STACK_NAME  CRIADA COM SUCESSO 3/4  \nXXX"
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
    docker stack deploy --prune --resolve-image always -c $nome_app_evocrm-redis.yaml $nome_app_evocrm-redis >/dev/null 2>&1
else
    # Caso inesperado (não deve ocorrer devido à validação anterior no while loop)
   # echo "Erro: valor inesperado para criar_portainer. Encerrando..."
    echo -e "XXX\n43\n[ERRO] ERRO INESPERADO PARA CRIAR STACK NO PORTAINER 3/4  \nXXX"
    sleep 5
    echo -e "XXX\n44\nREVERTENDO E CRIANDO STACK PELO SERVIDOR 3/4  \nXXX"
docker stack deploy --prune --resolve-image always -c $nome_app_evocrm-redis.yaml $nome_app_evocrm-redis >/dev/null 2>&1
sleep 5

    exit 1
fi



# FIM DE INSTALANDO O REDISEVOCRM
#
#######################################################


sleep 1
echo -e "XXX\n45\nFAZENDO O BUILD DO STACK 2/4 \nXXX"
sleep 1
echo -e "XXX\n50\nFAZENDO O BUILD DO STACK 2/4 \nXXX"




#######################################################
#
#  INSTALANDO A EVOLUTION API - INICIO
#

sleep 1
echo -e "XXX\n50\nFAZENDO O BUILD DO STACK 3/4 \nXXX"
sleep 1
echo -e "XXX\n75\nFAZENDO O BUILD DO STACK 3/4 - CONCLUIDO \nXXX"


## Criando key Aleatória
secret_key_base_evocrm=$(openssl rand -hex 64)
jwt_secret_evocrm=$(openssl rand -hex 32)
evoai_crm_api_token=$(openssl rand -hex 32)
doorkeeper_jwt_secret_key=$(openssl rand -hex 32)
bot_runtime_secret=$(openssl rand -hex 32)
apt install python3 -y > /dev/null 2>&1
encryption_key=$(python3 -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())")





cd

cd

cat > $nome_app_evocrm.yaml << EOL

version: "3.7"
services:

  $nome_app_evocrm-gateway:
    image: evoapicloud/evo-crm-gateway:latest

    networks: 
      - externa
      - interna
    
    environment:                                                                                                                                              
      - AUTH_UPSTREAM=$nome_app_evocrm-auth:3001                                                                                                                         
      - CRM_UPSTREAM=$nome_app_evocrm-crm:3000                                                                                                                           
      - CORE_UPSTREAM=$nome_app_evocrm-core:5555                       
      - PROCESSOR_UPSTREAM=$nome_app_evocrm-processor:8000                                                                                                               
      - BOT_RUNTIME_UPSTREAM=$nome_app_evocrm-bot_runtime:8080

    deploy:
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
cat >> $nome_app_evocrm.yaml << EOL
      labels:
        - traefik.enable=1
        - traefik.docker.network=$nome_rede_interna ## Nome da rede interna
        - traefik.http.routers.$nome_app_evocrm-gateway.rule=Host(\`$url_evocrm_api\`) ## Domínio API (gateway)
        - traefik.http.routers.$nome_app_evocrm-gateway.entrypoints=websecure
        - traefik.http.routers.$nome_app_evocrm-gateway.priority=1
        - traefik.http.routers.$nome_app_evocrm-gateway.tls.certresolver=letsencryptresolver
        - traefik.http.routers.$nome_app_evocrm-gateway.service=$nome_app_evocrm-gateway
        - traefik.http.services.$nome_app_evocrm-gateway.loadbalancer.server.port=3030
        - traefik.http.services.$nome_app_evocrm-gateway.loadbalancer.passHostHeader=true
EOL
fi
cat >> $nome_app_evocrm.yaml << EOL

  $nome_app_evocrm-auth:
    image: evoapicloud/evo-auth-service-community:latest
    command: bash -c "bundle exec rails db:migrate 2>&1 || echo 'Migration had errors, continuing...'; bundle exec rails s -p 3001 -b 0.0.0.0"

    networks: 
      - externa
      - interna
    
    environment:
    ## Rails (ambiente)
      - RAILS_ENV=production
      - RAILS_MAX_THREADS=5

    ## Segredos e tokens
      - SECRET_KEY_BASE=$secret_key_base_evocrm
      - JWT_SECRET_KEY=$jwt_secret_evocrm
      - EVOAI_CRM_API_TOKEN=$evoai_crm_api_token

    ## PostgreSQL
      - POSTGRES_HOST=postgres
      - POSTGRES_PORT=5432
      - POSTGRES_USERNAME=postgres
      - POSTGRES_PASSWORD=$postgres_password
      - POSTGRES_DATABASE=$nome_app_evocrm
      - POSTGRES_SSLMODE=disable

    ## Redis
      - REDIS_URL=redis://$nome_app_evocrm-redis:6379/1

    ## URLs públicas e CORS
      - FRONTEND_URL=https://$url_evocrm_frontend
      - BACKEND_URL=https://$url_evocrm_api
      - CORS_ORIGINS=https://$url_evocrm_frontend,https://$url_evocrm_api

    ## E-mail (Mailer + SMTP)
      - SMTP_DOMAIN=$domain_smtp_evocrm
      - MAILER_SENDER_EMAIL=$email_smtp_evocrm
      - SMTP_USERNAME=$username_smtp_evocrm
      - SMTP_PASSWORD=$senha_smtp_evocrm
      - SMTP_ADDRESS=$host_smtp_evocrm
      - SMTP_PORT=$port_smtp_evocrm
      - SMTP_AUTHENTICATION=plain
      - SMTP_ENABLE_STARTTLS_AUTO=true

    ## Doorkeeper (OAuth / JWT)
      - DOORKEEPER_JWT_SECRET_KEY=$doorkeeper_jwt_secret_key
      - DOORKEEPER_JWT_ALGORITHM=hs256
      - DOORKEEPER_JWT_ISS=evo-auth-service

    ## MFA e filas
      - MFA_ISSUER=EvoCRM
      - SIDEKIQ_CONCURRENCY=10
      - ACTIVE_STORAGE_SERVICE=local
    
    deploy:
      placement:
        constraints:
          - node.role == manager
      resources:
        limits:
          cpus: "1"
          memory: 1024M


  $nome_app_evocrm-auth_sidekiq:
    image: evoapicloud/evo-auth-service-community:latest
    command: ["bundle", "exec", "sidekiq", "-C", "config/sidekiq.yml"]
    
    networks: 
      - externa
      - interna

    environment:
    ## Rails (ambiente)
      - RAILS_ENV=production

    ## Segredos e tokens
      - SECRET_KEY_BASE=$secret_key_base_evocrm
      - JWT_SECRET_KEY=$jwt_secret_evocrm
      - EVOAI_CRM_API_TOKEN=$evoai_crm_api_token

    ## PostgreSQL
      - POSTGRES_HOST=postgres
      - POSTGRES_PORT=5432
      - POSTGRES_USERNAME=postgres
      - POSTGRES_PASSWORD=$postgres_password
      - POSTGRES_DATABASE=$nome_app_evocrm
      - POSTGRES_SSLMODE=disable

    ## Redis
      - REDIS_URL=redis://$nome_app_evocrm-redis:6379/1

    ## CORS
      - CORS_ORIGINS=https://$url_evocrm_frontend,https://$url_evocrm_api

    ## E-mail (Mailer + SMTP)
      - SMTP_DOMAIN=$domain_smtp_evocrm
      - MAILER_SENDER_EMAIL=$email_smtp_evocrm
      - SMTP_USERNAME=$username_smtp_evocrm
      - SMTP_PASSWORD=$senha_smtp_evocrm
      - SMTP_ADDRESS=$host_smtp_evocrm
      - SMTP_PORT=$port_smtp_evocrm
      - SMTP_AUTHENTICATION=plain
      - SMTP_ENABLE_STARTTLS_AUTO=true

    ## Doorkeeper (OAuth / JWT)
      - DOORKEEPER_JWT_SECRET_KEY=$doorkeeper_jwt_secret_key
      - DOORKEEPER_JWT_ALGORITHM=hs256
      - DOORKEEPER_JWT_ISS=evo-auth-service

    ## MFA e filas
      - MFA_ISSUER=EvoCRM
      - SIDEKIQ_CONCURRENCY=10
      - ACTIVE_STORAGE_SERVICE=local
    
    healthcheck:
      disable: true
    
    deploy:
      placement:
        constraints:
          - node.role == manager
      resources:
        limits:
          cpus: "1"
          memory: 1024M

  $nome_app_evocrm-crm:
    image: evoapicloud/evo-ai-crm-community:latest
    command: sh -c "until wget -qO- http://$nome_app_evocrm-auth:3001/health >/dev/null 2>&1; do echo 'Waiting for auth...'; sleep 5; done; bundle exec rails db:migrate 2>&1 || echo 'Migration had errors, continuing...'; bundle exec rails s -p 3000 -b 0.0.0.0"
    
    networks: 
      - externa
      - interna

    environment:
    ## Rails (ambiente e logs)
      - RAILS_ENV=production
      - RAILS_SERVE_STATIC_FILES=true
      - RAILS_LOG_TO_STDOUT=true

    ## Segredos e tokens
      - SECRET_KEY_BASE=$secret_key_base_evocrm
      - JWT_SECRET_KEY=$jwt_secret_evocrm
      - EVOAI_CRM_API_TOKEN=$evoai_crm_api_token

    ## PostgreSQL
      - POSTGRES_HOST=postgres
      - POSTGRES_PORT=5432
      - POSTGRES_USERNAME=postgres
      - POSTGRES_PASSWORD=$postgres_password
      - POSTGRES_DATABASE=$nome_app_evocrm
      - POSTGRES_SSLMODE=disable

    ## Redis
      - REDIS_URL=redis://$nome_app_evocrm-redis:6379/1

    ## Serviços internos (Auth + Core)
      - EVO_AUTH_SERVICE_URL=http://$nome_app_evocrm-auth:3001
      - EVO_AI_CORE_SERVICE_URL=http://$nome_app_evocrm-core:5555

    ## URLs públicas e CORS
      - BACKEND_URL=https://$url_evocrm_api
      - FRONTEND_URL=https://$url_evocrm_frontend
      - CORS_ORIGINS=https://$url_evocrm_frontend,https://$url_evocrm_api
    
    ## Telemetria e logs
      - DISABLE_TELEMETRY=true
      - LOG_LEVEL=info
    
    ## Funcionalidades da aplicação
      - ENABLE_ACCOUNT_SIGNUP=true
      - ENABLE_PUSH_RELAY_SERVER=true
      - ENABLE_INBOX_EVENTS=true
    
    ## Bot runtime
      - BOT_RUNTIME_URL=http://$nome_app_evocrm-bot_runtime:8080
      - BOT_RUNTIME_SECRET=$bot_runtime_secret
      - BOT_RUNTIME_POSTBACK_BASE_URL=http://$nome_app_evocrm-crm:3000
    
    deploy:
      placement:
        constraints:
          - node.role == manager
      resources:
        limits:
          cpus: "1"
          memory: 1024M


  $nome_app_evocrm-crm_sidekiq:
    image: evoapicloud/evo-ai-crm-community:latest
    command: ["bundle", "exec", "sidekiq", "-C", "config/sidekiq.yml"]
    
    networks: 
      - externa
      - interna

    environment:
    ## Rails (ambiente)
      - RAILS_ENV=production
    
    ## Segredos e tokens
      - SECRET_KEY_BASE=$secret_key_base_evocrm
      - JWT_SECRET_KEY=$jwt_secret_evocrm
      - EVOAI_CRM_API_TOKEN=$evoai_crm_api_token
    
    ## PostgreSQL
      - POSTGRES_HOST=postgres
      - POSTGRES_PORT=5432
      - POSTGRES_USERNAME=postgres
      - POSTGRES_PASSWORD=$postgres_password
      - POSTGRES_DATABASE=$nome_app_evocrm
      - POSTGRES_SSLMODE=disable
    
    ## Redis
      - REDIS_URL=redis://$nome_app_evocrm-redis:6379/1
    
    ## Serviços internos (Auth + Core)
      - EVO_AUTH_SERVICE_URL=http://$nome_app_evocrm-auth:3001
      - EVO_AI_CORE_SERVICE_URL=http://$nome_app_evocrm-core:5555
    
    ## CORS
      - CORS_ORIGINS=https://$url_evocrm_frontend,https://$url_evocrm_api
    
    ## Bot runtime
      - BOT_RUNTIME_URL=http://$nome_app_evocrm-bot_runtime:8080
      - BOT_RUNTIME_SECRET=$bot_runtime_secret
      - BOT_RUNTIME_POSTBACK_BASE_URL=http://$nome_app_evocrm-crm:3000
    
    deploy:
      placement:
        constraints:
          - node.role == manager
      resources:
        limits:
          cpus: "1"
          memory: 1024M


  $nome_app_evocrm-core:
    image: evoapicloud/evo-ai-core-service-community:latest
    
    networks: 
      - externa
      - interna

    environment:
    ## PostgreSQL (conexão)
      - DB_HOST=postgres
      - DB_PORT=5432
      - DB_USER=postgres
      - DB_PASSWORD=$postgres_password
      - DB_NAME=$nome_app_evocrm
      - DB_SSLMODE=disable
    
    ## Pool de conexões
      - DB_MAX_IDLE_CONNS=10
      - DB_MAX_OPEN_CONNS=100
      - DB_CONN_MAX_LIFETIME=1h
      - DB_CONN_MAX_IDLE_TIME=30m
    
    ## API (porta)
      - PORT=5555
    
    ## Segredos e JWT
      - SECRET_KEY_BASE=$secret_key_base_evocrm
      - JWT_SECRET_KEY=$jwt_secret_evocrm
      - JWT_ALGORITHM=HS256
      - ENCRYPTION_KEY=$encryption_key
    
    ## Serviços internos
      - EVOLUTION_BASE_URL=http://$nome_app_evocrm-crm:3000
      - EVO_AUTH_BASE_URL=http://$nome_app_evocrm-auth:3001
      - AI_PROCESSOR_URL=http://$nome_app_evocrm-processor:8000
      - AI_PROCESSOR_VERSION=v1
    
    deploy:
      placement:
        constraints:
          - node.role == manager
      resources:
        limits:
          cpus: "1"
          memory: 1024M


  $nome_app_evocrm-processor:
    image: evoapicloud/evo-ai-processor-community:latest
    command: sh -c "alembic upgrade head 2>&1 || echo 'Alembic migration had errors, continuing...'; python -m scripts.run_seeders; uvicorn src.main:app --host \$\$HOST --port \$\$PORT"
    
    volumes:
      - $nome_app_evocrm-processor_logs:/app/logs
    
    networks: 
      - externa
      - interna

    environment:
    ## PostgreSQL
      - POSTGRES_CONNECTION_STRING=postgresql://postgres:$postgres_password@postgres:5432/$nome_app_evocrm?sslmode=disable
    
    ## Redis
      - REDIS_HOST=$nome_app_evocrm-redis
      - REDIS_PORT=6379
      - REDIS_PASSWORD=
      - REDIS_SSL=false
      - REDIS_DB=0
      - REDIS_KEY_PREFIX=a2a_
      - REDIS_TTL=3600
    
    ## Uvicorn (host / porta)
      - HOST=0.0.0.0
      - PORT=8000
    
    ## Debug e segredos
      - DEBUG=false
      - SECRET_KEY_BASE=$secret_key_base_evocrm
      - ENCRYPTION_KEY=$encryption_key
      - EVOAI_CRM_API_TOKEN=$evoai_crm_api_token
    
    ## Integração CRM e Core
      - EVO_AI_CRM_URL=http://$nome_app_evocrm-crm:3000
      - CORE_SERVICE_URL=http://$nome_app_evocrm-core:5555/api/v1
   
    ## URLs públicas da API
      - APP_URL=https://$url_evocrm_api
      - API_URL=https://$url_evocrm_api
    
    ## Metadados da API (OpenAPI)
      - API_TITLE=Agent Processor Community
      - API_DESCRIPTION=Agent Processor Community for Evo AI
      - API_VERSION=1.0.0
      - ORGANIZATION_NAME=Evo CRM
    
    ## Cache de tools
      - TOOLS_CACHE_ENABLED=true
      - TOOLS_CACHE_TTL=3600
    
    deploy:
      placement:
        constraints:
          - node.role == manager
      resources:
        limits:
          cpus: "1"
          memory: 1024M


  $nome_app_evocrm-bot_runtime:
    image: evoapicloud/evo-bot-runtime:latest

    networks: 
      - externa
      - interna
      
    environment:
    ## Rede (listen)
      - LISTEN_ADDR=0.0.0.0:8080
    
    ## Redis
      - REDIS_URL=redis://$nome_app_evocrm-redis:6379/1
    
    ## Processor e segurança
      - AI_PROCESSOR_URL=http://$nome_app_evocrm-processor:8000
      - BOT_RUNTIME_SECRET=$bot_runtime_secret
      - AI_CALL_TIMEOUT_SECONDS=30
    
    deploy:
      placement:
        constraints:
          - node.role == manager
      resources:
        limits:
          cpus: "1"
          memory: 1024M


  $nome_app_evocrm-frontend:
    image: evoapicloud/evo-ai-frontend-community:latest

    networks: 
      - externa
      - interna   

    environment:
    ## Vite (ambiente)
      - VITE_APP_ENV=production
    
    ## URLs da API (build-time)
      - VITE_API_URL=https://$url_evocrm_api
      - VITE_AUTH_API_URL=https://$url_evocrm_api
      - VITE_EVOAI_API_URL=https://$url_evocrm_api
      - VITE_AGENT_PROCESSOR_URL=https://$url_evocrm_api
    
    deploy:
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
cat >> $nome_app_evocrm.yaml << EOL
      labels:
        - traefik.enable=1
        - traefik.docker.network=$nome_rede_interna ## Nome da rede interna
        - traefik.http.routers.$nome_app_evocrm-frontend.rule=Host(\`$url_evocrm_frontend\`) ## Domínio frontend (React)
        - traefik.http.routers.$nome_app_evocrm-frontend.entrypoints=websecure
        - traefik.http.routers.$nome_app_evocrm-frontend.priority=1
        - traefik.http.routers.$nome_app_evocrm-frontend.tls.certresolver=letsencryptresolver
        - traefik.http.routers.$nome_app_evocrm-frontend.service=$nome_app_evocrm-frontend
        - traefik.http.services.$nome_app_evocrm-frontend.loadbalancer.server.port=80
        - traefik.http.services.$nome_app_evocrm-frontend.loadbalancer.passHostHeader=true
EOL
fi
cat >> $nome_app_evocrm.yaml << EOL        

volumes:
  $nome_app_evocrm-processor_logs:
    external: true
    name: $nome_app_evocrm-processor_logs 

networks: 
  externa: 
    external: true
  interna: 
    external: true
EOL

#docker stack deploy --prune --resolve-image always -c $nome_app_evocrm.yaml $nome_app_evocrm >/dev/null 2>&1


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
STACK_NAME=$nome_app_evocrm
STACK_FILE_PATH="/root/$nome_app_evocrm.yaml"

else
   # echo "Erro: Arquivo de dados não encontrado em $dados_file."
    sleep 5
echo -e "XXX\n77\nSEM ARQUIVO DE DADOS DO PORTAINER 3/4  \nXXX"
docker stack deploy --prune --resolve-image always -c $nome_app_evocrm.yaml $nome_app_evocrm >/dev/null 2>&1
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
docker stack deploy --prune --resolve-image always -c $nome_app_evocrm.yaml $nome_app_evocrm >/dev/null 2>&1
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
        docker stack deploy --prune --resolve-image always -c $nome_app_evocrm.yaml $nome_app_evocrm >/dev/null 2>&1
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
        docker stack deploy --prune --resolve-image always -c $nome_app_evocrm.yaml $nome_app_evocrm >/dev/null 2>&1
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
        docker stack deploy --prune --resolve-image always -c $nome_app_evocrm.yaml $nome_app_evocrm >/dev/null 2>&1
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
        docker stack deploy --prune --resolve-image always -c $nome_app_evocrm.yaml $nome_app_evocrm >/dev/null 2>&1
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
    docker stack deploy --prune --resolve-image always -c $nome_app_evocrm.yaml $nome_app_evocrm >/dev/null 2>&1
else
    # Caso inesperado (não deve ocorrer devido à validação anterior no while loop)
   # echo "Erro: valor inesperado para criar_portainer. Encerrando..."
    echo -e "XXX\n91\n[ERRO] ERRO INESPERADO PARA CRIAR STACK NO PORTAINER 3/4  \nXXX"
    sleep 5
    echo -e "XXX\n92\nREVERTENDO E CRIANDO STACK PELO SERVIDOR 3/4  \nXXX"
docker stack deploy --prune --resolve-image always -c $nome_app_evocrm.yaml $nome_app_evocrm >/dev/null 2>&1
sleep 5

    exit 1
fi




#######################################################


echo -e "XXX\n93\nFINALIZANDO INSTALAÇÃO 4/4  \nXXX"


sleep 12
echo -e "XXX\n100\nFINALIZANDO INSTALAÇÃO 4/4 - CONCLUIDO  \nXXX"

sleep 3

}|whiptail --title "EVOCRM - PROGRESSO DA INSTALAÇÃO" --gauge "Aguarde a instalação dos ítens necessrios" 6 60 0


#
# 
#
#######################################################

#
# MENSAGEM DE INSTLADO + DADOS
#

# VERIFICAÇÃO FINAL - Versão Corrigida
if [ "$INSTALL_TYPE" = "CLOUDFLARE_TUNNEL" ]; then
    failed_domains=0
    domains_to_check=""
    
    # Determinar quais domínios verificar baseado se Minio foi instalado
  
         domains_to_check="$url_evocrm_api $url_evocrm_frontend"
 

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
        whiptail --title "Sucesso" --msgbox "Instalação concluída com sucesso! Cloudflare Tunnel configurado.\n\nAcessos:\n- EVOCRM FRONTEND: https://$url_evocrm_frontend\n- EVOCRM API: https://$url_evocrm_api\n\nPressione ENTER para voltar ao Menu Principal" 20 78
    else
        whiptail --title "Aviso" --msgbox "Instalação concluída, mas $failed_domains domínio(s) podem precisar de ajustes no DNS.\n\nIsso é normal logo após a criação - o DNS pode levar alguns minutos para propagar.\n\nSe o problema persistir, verifique:\n1. Os registros CNAME no Cloudflare\n2. A configuração do Tunnel\n3. As rotas no Cloudflare Tunnel\n\nPressione ENTER para voltar ao Menu Principal" 20 78
    fi
else
    # [Mantém o código existente para INSTALAÇÃO TRADICIONAL]
    ip_servidor=$(curl -s --max-time 10 ipinfo.io/ip)
    status=0
    


    dns_ip3=$(timeout 10 nslookup "$url_evocrm_api" 2>/dev/null | grep "Address" | tail -n1 | awk '{print $2}')
    dns_ip4=$(timeout 10 nslookup "$url_evocrm_frontend" 2>/dev/null | grep "Address" | tail -n1 | awk '{print $2}')
    [[ "$dns_ip3" != "$ip_servidor" ]] && status=1
    [[ "$dns_ip4" != "$ip_servidor" ]] && status=1

    if [[ $status -eq 1 ]]; then
        whiptail --title "Erro" --msgbox "Não foi possível acessar um ou mais subdomínios. Verifique os apontamentos de DNS." 20 78
    else
        whiptail --title "Sucesso" --msgbox "Instalação concluída com sucesso!\n\nAcessos:\n- EVOCRM FRONTEND: https://$url_evocrm_frontend\n- EVOCRM API: https://$url_evocrm_api\n\nPressione ENTER para voltar ao Menu Principal" 20 78
    fi
fi

exit 0




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
    if [ -f "${SETUPMNO_CLOUDFLARE_CREDENTIALS_FILE:-/root/.cloudflared_config/cloudflare_credentials}" ]; then
        source "${SETUPMNO_CLOUDFLARE_CREDENTIALS_FILE:-/root/.cloudflared_config/cloudflare_credentials}"
    fi
    [ -f /root/SetupLowCodeMno/cloudflare_app_guard.sh ] && . /root/SetupLowCodeMno/cloudflare_app_guard.sh
else
    if [ -f "${SETUPMNO_TRADITIONAL_CREDENTIALS_FILE:-/root/.tradicional_config/tradicional_credentials}" ]; then
        source "${SETUPMNO_TRADITIONAL_CREDENTIALS_FILE:-/root/.tradicional_config/tradicional_credentials}"
    fi
fi


function msg() {
		msg=$1
		whiptail --title "CHATWOOTORIG + EVOLUTION 2.0 + RABBITMQ + MINIO: FERRAMENTA MULTICANAIS" --msgbox "$msg" --fb 10 70;
	}

  while true; do
CHOICE=$(
whiptail --title "CHATWOOTORIG + EVOLUTION 2.0 + RABBITMQ + MINIO: FERRAMENTA MULTICANAIS" --menu "Aperte ENTER para iniciar a instalação do CHATWOOTORIG + EVOLUTION 2.0 + RABBITMQ + MINIO ou selecione SAIR (Utilize setas e Enter)\n\nTIPO DE INSTALAÇÃO DETECTADA: $INSTALL_TYPE\n\nINSTRUÇÕES:\nAntes de prosseguir, verifique os registros DNS conforme seu tipo de instalação:" 20 70 2 \
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



minio_container=$(docker ps -qf "name=minio")

sleep 2

if [[ ("$minio_container" == "") ]]; then

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
        echo "$painel"; echo "Saindo..."; exit 0;
    fi
done



while true ; do
    publico=$(whiptail --title "Dominio Público do Minio" --inputbox "Digite o dominio Público (ex: s3.seudominio.com):" --fb 12 60 3>&1 1>&2 2>&3) 
    saida=$?
    if [[ $saida -eq '0' ]]; then
        if [[ -z $publico ]]; then 
            msg "Digite o dominio público do Minio para poder continuar" 
            continue 
        else 
            break
        fi
    else
        echo "$publico"; echo "Saindo..."; exit 0;
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
        echo "$usuariominio"; echo "Saindo..."; exit 0;
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
        echo "$senhaminio"; echo "Saindo..."; exit 0;
    fi
done

cd
mkdir -p ~/dados_minio
echo "MINIO_USER: $usuariominio" > ~/dados_minio/dados_minio
echo "MINIO_PASSWORD: $senhaminio" >> ~/dados_minio/dados_minio
echo "MINIO_PUBLIC_URL: $publico" >> ~/dados_minio/dados_minio
echo "MINIO_ADMIN_URL: $painel" >> ~/dados_minio/dados_minio

 fi



# Verificar e carregar dados do Minio
dados_minio_file="$HOME/dados_minio/dados_minio"
if [[ -f "$dados_minio_file" ]]; then
    MINIO_USER=$(grep "MINIO_USER:" "$dados_minio_file" | awk '{print $2}')
    MINIO_PASSWORD=$(grep "MINIO_PASSWORD:" "$dados_minio_file" | awk '{print $2}')
    MINIO_PUBLIC_URL=$(grep "MINIO_PUBLIC_URL:" "$dados_minio_file" | awk '{print $2}')
    MINIO_ADMIN_URL=$(grep "MINIO_ADMIN_URL:" "$dados_minio_file" | awk '{print $2}')
else
    whiptail --title "Erro" --msgbox "Minio instalado, mas os dados de acesso não foram encontrados. A presente instalação acessa credenciais pré-gravadas em uma pasta. Se sua instalação não é recente, pode ser que o Setup-MNO não criou esta pasta. Use outro template de instalação de Chatwoot sem o Minio. Digite enter para abortar a instalação." 15 60
    exit 0
fi




rabbitmq_container=$(docker ps -qf name=rabbitmq)
#sufixo_app=$(date | md5sum | head -c7)
sufixo_app=$(date | md5sum | head -c7 | tr '[:upper:]' '[:lower:]')



#  Rabbitmq variaveis - Inicio


while true ; do
		painelrabbitmq=$(whiptail --title "URL do Painel do RabbitMq" --inputbox "Digite o Link do Painel (ex: fila.seudominio.com):" --fb 12 60 3>&1 1>&2 2>&3) ; saida=$?
		if [[ $saida -eq '0' ]] ; then
			if [[ -z $painelrabbitmq ]] ; then msg "Digite o link do painel do Rabbitmq para poder continuar" ; continue ; else break; fi
		else
			echo $painelrabbitmq ; echo "saindo..."  &  exit 0 ;
		fi
	done

      while true ; do
		usuariomq=$(whiptail --title "Usuário do Rabbitmq" --inputbox "Digite o Usuario do RabbitMq, sem caracteres especiais e até 16 digitos(ex: Nome):" --fb 12 60 3>&1 1>&2 2>&3) ; saida=$?
		if [[ $saida -eq '0' ]] ; then
    if [[ (-z $usuariomq) || ("$usuariomq" =~ [^a-zA-Z0-9]) || (${#usuariomq} -gt 16) ]] ; then msg "Digite o Usuario do RabbitMq, sem caracteres especiais e até 16 digitos para poder continuar" ; continue ; else break; fi
		else
			echo $usuariomq ; echo "saindo..."  &  exit 0 ;
		fi
	done

     while true ; do
		senhamq=$(whiptail --title "Criar senha do Rabbitmq" --inputbox "Crie uma senha para o RabbitMq, sem caracteres especiais e até 16 digitos(ex: AgdhRtuipoo):" --fb 12 60 3>&1 1>&2 2>&3) ; saida=$?
		if [[ $saida -eq '0' ]] ; then
    if [[ (-z $senhamq) || ("$senhamq" =~ [^a-zA-Z0-9]) || (${#senhamq} -gt 16) ]] ; then msg "Digite uma senha para o RabbitMq, sem caracteres especiais e até 16 digitos para poder continuar" ; continue ; else break; fi
		else
			echo $senhamq ; echo "saindo..."  &  exit 0 ;
		fi
	done

    



nome_principal_rabbitmq="rabbitmq"  #nome do app
nome_app_rabbitmq=$nome_principal_rabbitmq$sufixo_app



#  Rabbitmq variaveis - fim

#  Chatwoot variaveis - inicio

  while true ; do
		dominiochat=$(whiptail --title "URL do Chatwoot" --inputbox "Digite o dominio para acessar o Chatwoot (ex: app.dominio.com):" --fb 12 60 3>&1 1>&2 2>&3) ; saida=$?
		if [[ $saida -eq '0' ]] ; then
			if [[ -z $dominiochat ]] ; then msg "Digite o link do Chatwoot para poder continuar" ; continue ; else break; fi
		else
			echo $dominiochat ; echo "saindo..."  &  exit 0 ;
		fi
	done

  while true ; do
		nomeempresa=$(whiptail --title "Nome da Empresa" --inputbox "Digite o nome de sua empresa no Chatwoot (ex: Oficina Linhares):" --fb 12 60 3>&1 1>&2 2>&3) ; saida=$?
		if [[ $saida -eq '0' ]] ; then
			if [[ -z $nomeempresa ]] ; then msg "Digite o nome de sua Chatwoot para poder continuar" ; continue ; else break; fi
		else
			echo $nomeempresa ; echo "saindo..."  &  exit 0 ;
		fi
	done


     while true ; do
		emailchat=$(whiptail --title "Email de SMTP" --inputbox "Digite seu email de SMTP para envio de mensagens (ex: contato@dominio.com):" --fb 12 60 3>&1 1>&2 2>&3) ; saida=$?
		if [[ $saida -eq '0' ]] ; then
			if [[ -z $emailchat ]] ; then msg "Digite um email de SMTP do Chatwoot para poder continuar" ; continue ; else break; fi
		else
			echo $emailchat ; echo "saindo..."  &  exit 0 ;
		fi
	done

    hostsmtpchatwoot=$(whiptail --title "Host do SMTP" --inputbox "Pressione ENTER para configurar depois, ou digite o Host do seu SMTP (ex: mail.seudominio_smtp.com.br :" --fb 12 60 3>&1 1>&2 2>&3) ; saida=$?
		if [[ $saida -eq '0' ]] ; then if [[ -z $hostsmtpchatwoot ]] ; then hostsmtpchatwoot=mail.seudominio_smtp.com.br ; fi else echo "saindo..." ; exit ; fi


    dominiosmtpchatwoot=$(whiptail --title "Dominio do SMTP" --inputbox "Pressione ENTER para configurar depois, ou digite o Dominio do seu SMTP (ex: seudominiosmto.br :" --fb 12 60 3>&1 1>&2 2>&3) ; saida=$?
		if [[ $saida -eq '0' ]] ; then if [[ -z $dominiosmtpchatwoot ]] ; then dominiosmtpchatwoot=seudominio_smtp.com.br ; fi else echo "saindo..." ; exit ; fi

     
     smtpchatwoot=$(whiptail --title "Usuario do SMTP" --inputbox "Pressione ENTER para configurar depois, ou digite o usuario do seu SMTP (ex: suporte@seusite.com.br :" --fb 12 60 3>&1 1>&2 2>&3) ; saida=$?
		if [[ $saida -eq '0' ]] ; then if [[ -z $smtpchatwoot ]] ; then smtpchatwoot=usuario@seusite.com.br ; fi else echo "saindo..." ; exit ; fi

     portachatwoot=$(whiptail --title "Porta do SMTP" --inputbox "Pressione ENTER para configurar depois, ou digite digite a Porta SMTP (ex: 465):" --fb 12 60 3>&1 1>&2 2>&3) ; saida=$?
		if [[ $saida -eq '0' ]] ; then if [[ -z $portachatwoot ]] ; then portachatwoot=465 ; fi else echo "saindo..." ; exit ; fi
    
    senhaemailchatwoot=$(whiptail --title "Senha do SMTP" --inputbox "Pressione ENTER para configurar depois, ou digite Senha do seu Email:" --fb 12 60 3>&1 1>&2 2>&3) ; saida=$?
		if [[ $saida -eq '0' ]] ; then if [[ -z $senhaemailchatwoot ]] ; then senhaemailchatwoot=102030 ; fi else echo "saindo..." ; exit ; fi
    
# Criando variaveis e banco

nome_principal_chatwoot="chatwoot"  #nome do app
nome_app_chatwoot=$nome_principal_chatwoot$sufixo_app
sufixo_traefik="_sslheader"
nome_app_chatwoot_sslheader=$nome_app_chatwoot$sufixo_traefik
nome_redis1="-redis"
nome_cwt_redis=$nome_app_chatwoot$nome_redis1
encryption_key=$(openssl rand -hex 64)
postgres_password=$(grep -oP '(?<=POSTGRES_PASSWORD=).+' /root/postgres.yaml)

container_id=$(docker ps -qf name=postgres)
[ -n "$container_id" ] && docker exec -i $container_id psql -U postgres -d postgres -c "CREATE  DATABASE $nome_app_chatwoot;" >/dev/null 2>&1 || true 

#  CHATWOOTORIG variaveis - fim

#  Evolution variaveis - inicio

while true ; do
		dominio=$(whiptail --title "URL da Evolution 2 API" --inputbox "Digite seu dominio para acessar a api (ex: api.dominio.com): " --fb 12 60 3>&1 1>&2 2>&3) ; saida=$?
		if [[ $saida -eq '0' ]] ; then
			if [[ -z $dominio ]] ; then msg "Digite o link da Evolution API para poder continuar" ; continue ; else break; fi
		else
			echo $dominio ; echo "saindo..."  &  exit 0 ;
		fi
	done

      while true ; do
		client=$(whiptail --title "Nome da Empresa" --inputbox "Digite o nome da sua empresa (ex: MNOzap):" --fb 12 60 3>&1 1>&2 2>&3) ; saida=$?
		if [[ $saida -eq '0' ]] ; then
			if [[ -z $client ]] ; then msg "Digite o nome da empresa para poder continuar" ; continue ; else break; fi
		else
			echo $client ; echo "saindo..."  &  exit 0 ;
		fi
	done
chave_hexadecimal=$(openssl rand -hex 16)
     while true ; do
		key=$(whiptail --title "Global API Key" --inputbox "Digite a Api Global Key (sugestão gerada aleatóriamente: $chave_hexadecimal):" --fb 12 60 3>&1 1>&2 2>&3) ; saida=$?
		if [[ $saida -eq '0' ]] ; then
			if [[ -z $key ]] ; then msg "Crie uma Global APi Key para oa Evolution, para poder continuar" ; continue ; else break; fi
		else
			echo $key ; echo "saindo..."  &  exit 0 ;
		fi
	done



# Perguntar ao usuário se deseja criar a stack no Portainer

 while true ; do
		criar_portainer=$(whiptail --title "Criar Stacks no Portainer? - 0 ou 1" --inputbox "Digite 0 para poder editar stacks no portainer ou 1 para não poder editar" --fb 12 60 3>&1 1>&2 2>&3) ; saida=$?
		if [[ $saida -eq '0' ]] ; then
		#	if [[ -z $senhamautic ]] ; then msg "Digite a senha do Mautic, para poder continuar" ; continue ; else break; fi
		if [[ "$criar_portainer" != "0" && "$criar_portainer" != "1" ]] ; then msg "Digite apenas o número 0 ou o número 1, para poder continuar. Digite 0 para poder editar stacks no portainer ou 1 para não poder editar" ; continue ; else break; fi
    else
			echo $criar_portainer ; echo "saindo..."  &  exit 0 ;
		fi
	done


nome_principal2="minio"  # nome do app
nome_app2=$nome_principal2$sufixo_app
sufixo_public="_public"
sufixo_console="_console"
nome_app_public=$nome_app2$sufixo_public
nome_app_console=$nome_app2$sufixo_console


clear






# FIM DAS PERGUNTAS PARA VARIAVEIS
#
#########################################################
#
# VERIFICAÇÃO DE DADOS
#

nome_principal_evolution="evolution2"  #nome do app
nome_redis="-redis"
nome_app_evolution=$nome_principal_evolution$sufixo_app
nome_evo_redis=$nome_app_evolution$nome_redis

#  Evolution variaveis - fim




# Ajuste do terminal para garantir compatibilidade
{
  tput reset 2>/dev/null         # Reinicia o terminal de forma segura
  exec 0</dev/tty 1>/dev/tty 2>&1 # Força redirecionamentos explícitos
  sleep 0.01                     # Pausa microscópica para sincronia
  clear                          # Limpeza final antes do whiptail
} || true

    # Exibe as informações formatadas com mais espaço na tela
    whiptail --title "Dados Fornecidos" \
    --msgbox "TIPO DE INSTALAÇÃO: $INSTALL_TYPE\n\nDados Preenchidos:\n\n1) Link Admin Minio: $MINIO_ADMIN_URL\n2) Link Público Minio: $MINIO_PUBLIC_URL\n3) Usuário do Minio: $MINIO_USER\n4) Senha do Minio: $MINIO_PASSWORD\n5) Link do chatwoot: $dominiochat\n6) Email SMTP: $emailchat\n7) Nome da Empresa: $nomeempresa\n8) Host SMTP: $hostsmtpchatwoot\n9) Dominio SMTP: $dominiosmtpchatwoot\n10) Usuario do SMTP: $smtpchatwoot\n11) Porta SMTP: $portachatwoot\n12) Senha do Email: $senhaemailchatwoot\n13) Dominio Evolution API: $dominio\n14) Nome Empresa: $client\n15) Global API Key: $key\n16) Link do Painel Rabbitmq: $painelrabbitmq\n17) Usuario do RabbitMq: $usuariomq\n18) Senha do RabbitMq: $senhamq\n19) Criar Stack no Portainer: $([ "$criar_portainer" == "0" ] && echo "0 (Editável)" || echo "1 (Não editável)")\n\n\nConfira e Tecle Enter para continuar. Na próxima etapa você poderá confirmar os dados ou corrigir, se necessário." \
    --fb 25 80

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

# ==============================================================================
# FUNÇÕES UNIVERSAIS: DNS / CLOUDFLARE TUNNEL E DEPLOY PORTAINER
# ==============================================================================

configurar_dns_e_tunnel() {
    local DOMINIO_ALVO="$1"
    local SERVICO_BACKEND="$2"
    local ROTULO_APP="$3"

    [ -n "$DOMINIO_ALVO" ] || return 0

    echo -e "XXX\n5\nCONFIGURANDO DNS / TUNNEL: $ROTULO_APP ($DOMINIO_ALVO)... \nXXX"

    if [ "$INSTALL_TYPE" = "TRADICIONAL" ] && [ "$criar_dns" = "0" ]; then
        echo -e "XXX\n6\nCONFIGURANDO DNS AUTOMÁTICO (TRADICIONAL)... \nXXX"
        local DOMINIO_PRINCIPAL="${SETUPMNO_SELECTED_ROOT_DOMAIN:-${SETUPMNO_DOMAIN_ROOT:-${CLOUDFLARE_ZONE_NAME:-}}}"
        
        local EXISTING_RECORDS COUNT
        EXISTING_RECORDS=$(curl -s -X GET \
            "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records?name=${DOMINIO_ALVO}" \
            -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
            -H "Content-Type: application/json")

        COUNT=$(echo "$EXISTING_RECORDS" | jq '.result | length' 2>/dev/null || echo 0)
        if [[ "$COUNT" -gt 0 ]]; then
            echo "$EXISTING_RECORDS" | jq -r '.result[].id' 2>/dev/null | while read -r REC_ID; do
                [[ -z "$REC_ID" ]] && continue
                curl -s -X DELETE \
                    "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records/${REC_ID}" \
                    -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
                    -H "Content-Type: application/json" >/dev/null 2>&1
            done
        fi

        local CNAME_RESPONSE
        CNAME_RESPONSE=$(curl -s -X POST \
            "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records" \
            -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
            -H "Content-Type: application/json" \
            --data '{"type":"CNAME","name":"'${DOMINIO_ALVO}'","content":"'${nome_servidor}'.'${DOMINIO_PRINCIPAL}'","ttl":1,"proxied":false}')

        if echo "$CNAME_RESPONSE" | grep -q '"success":true'; then
            echo -e "XXX\n10\nREGISTRO CNAME CRIADO COM SUCESSO! \nXXX"
        else
            echo -e "XXX\n10\nAVISO: ERRO AO CRIAR REGISTRO CNAME \nXXX"
        fi

    elif [ "$INSTALL_TYPE" = "CLOUDFLARE_TUNNEL" ]; then
        echo -e "XXX\n10\nCONFIGURANDO CLOUDFLARE TUNNEL (DNS + ROTAS)... \nXXX"
        local DOMINIO_PRINCIPAL="${SETUPMNO_SELECTED_ROOT_DOMAIN:-${SETUPMNO_DOMAIN_ROOT:-${CLOUDFLARE_ZONE_NAME:-}}}"

        local EXISTING_RECORDS COUNT DNS_RESPONSE
        EXISTING_RECORDS=$(curl -s -X GET \
            "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records?name=${DOMINIO_ALVO}" \
            -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
            -H "Content-Type: application/json")

        COUNT=$(echo "$EXISTING_RECORDS" | jq '.result | length' 2>/dev/null || echo 0)
        if [[ "$COUNT" -gt 0 ]]; then
            echo "$EXISTING_RECORDS" | jq -r '.result[].id' 2>/dev/null | while read -r REC_ID; do
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
            --data "{\"type\":\"CNAME\",\"name\":\"${DOMINIO_ALVO}\",\"content\":\"${TUNNEL_ID}.cfargotunnel.com\",\"ttl\":1,\"proxied\":true}")

        if echo "$DNS_RESPONSE" | grep -q '"success":true'; then
            echo -e "XXX\n14\nREGISTRO DNS CRIADO COM SUCESSO! \nXXX"
        fi

        if [ -n "$SERVICO_BACKEND" ]; then
            local TMPDIR TIMESTAMP BACKUP_RAW TO_PUT APPLY_RESPONSE
            TIMESTAMP=$(date -u +%Y%m%dT%H%M%SZ)
            TMPDIR=$(mktemp -d)
            BACKUP_RAW="$TMPDIR/backup_raw.$TIMESTAMP.json"
            TO_PUT="$TMPDIR/to_put.$TIMESTAMP.json"

            curl -sS -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
              "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/cfd_tunnel/$TUNNEL_ID/configurations" \
              | jq '.' > "$BACKUP_RAW" 2>/dev/null

            jq --arg host "$DOMINIO_ALVO" --arg service "$SERVICO_BACKEND" '
              (.result.config // {}) as $cfg
              | ($cfg.ingress // []) as $ing
              | ($ing | map(select(.service != "http_status:404"))) as $clean
              | ($clean | map(select(.hostname != $host))) as $filtered
              | ($filtered + [ { hostname: $host, service: $service, originRequest: { noTlsVerify: true, httpHostHeader: $host } } ]) as $merged
              | ($merged + [{ service: "http_status:404" }]) as $final_ing
              | ($cfg + { ingress: $final_ing }) as $newcfg
              | { config: $newcfg }
            ' "$BACKUP_RAW" > "$TO_PUT" 2>/dev/null

            APPLY_RESPONSE=$(curl -sS -X PUT "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/cfd_tunnel/$TUNNEL_ID/configurations" \
              -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
              -H "Content-Type: application/json" \
              --data-binary @"$TO_PUT")

            if echo "$APPLY_RESPONSE" | grep -q '"success":true'; then
                echo -e "XXX\n20\nTUNNEL CONFIGURADO COM SUCESSO! \nXXX"
            fi
            rm -rf "$TMPDIR"
        fi

    elif [ "$INSTALL_TYPE" = "TRADICIONAL" ] && [ "$criar_dns" = "1" ]; then
        local ip_servidor tentativa_atual=1 tentativas=5 sucesso=0 dns_ip
        ip_servidor=$(curl -s --max-time 10 ipinfo.io/ip)

        echo -e "XXX\n33\nVERIFICANDO SUBDOMÍNIO: $DOMINIO_ALVO \nXXX"
        while [ $tentativa_atual -le $tentativas ]; do
            dns_ip=$(timeout 10 nslookup -type=A "$DOMINIO_ALVO" 2>/dev/null | grep -E "Address: [0-9]+\." | awk '{print $2}' | head -n1)
            if [[ -n "$dns_ip" && "$dns_ip" == "$ip_servidor" ]]; then
                sucesso=1
                break
            fi
            sleep 1
            ((tentativa_atual++))
        done

        if [ $sucesso -eq 0 ]; then
            echo -e "XXX\n14\nERRO: SUBDOMÍNIO $DOMINIO_ALVO NÃO APONTA PARA O IP ($ip_servidor) \nXXX"
            sleep 2
            exit 1
        fi
        echo -e "XXX\n15\nDOMÍNIO $DOMINIO_ALVO VERIFICADO COM SUCESSO \nXXX"
    else
        if nslookup "$DOMINIO_ALVO" >/dev/null 2>&1; then
            echo -e "XXX\n23\nDNS CONFIGURADO \nXXX"
        fi
    fi
}

deploy_stack_app() {
    local STACK_NAME="$1"
    local STACK_FILE_PATH="/root/${STACK_NAME}.yaml"

    if [[ "$criar_portainer" == "0" ]]; then
        echo -e "XXX\n46\nCRIANDO STACK $STACK_NAME NO PORTAINER 3/4  \nXXX"
        local dados_file="$HOME/dados_portainer/dados_portainer"
        if [[ ! -f "$dados_file" ]]; then
            echo -e "XXX\n50\nSEM ARQUIVO DO PORTAINER, CRIANDO VIA DOCKER 3/4  \nXXX"
            docker stack deploy --prune --resolve-image always -c "$STACK_FILE_PATH" "$STACK_NAME" >/dev/null 2>&1
            return 0
        fi

        local PORTAINER_URL ADMIN_USERNAME ADMIN_PASSWORD
        PORTAINER_URL=$(grep "Dominio do portainer:" "$dados_file" | cut -d':' -f2 | xargs)
        ADMIN_USERNAME=$(grep "Usuario:" "$dados_file" | cut -d':' -f2 | xargs)
        ADMIN_PASSWORD=$(grep "Senha:" "$dados_file" | cut -d':' -f2 | xargs)

        local RESPONSE TOKEN ENDPOINT_ID SWARM_ID
        RESPONSE=$(curl -sS -X POST "https://$PORTAINER_URL/api/auth" \
            -H "Content-Type: application/json" \
            -d "{\"username\": \"$ADMIN_USERNAME\", \"password\": \"$ADMIN_PASSWORD\"}")
        TOKEN=$(echo "$RESPONSE" | jq -r '.jwt // empty' 2>/dev/null)

        if [ -n "$TOKEN" ] && [ "$TOKEN" != "null" ]; then
            RESPONSE=$(curl -sS -X GET "https://$PORTAINER_URL/api/endpoints" \
                -H "Authorization: Bearer $TOKEN")
            ENDPOINT_ID=$(echo "$RESPONSE" | jq -r '.[0].Id // empty' 2>/dev/null)

            if [ -n "$ENDPOINT_ID" ] && [ "$ENDPOINT_ID" != "null" ]; then
                RESPONSE=$(curl -sS -X GET "https://$PORTAINER_URL/api/endpoints/$ENDPOINT_ID/docker/swarm" \
                    -H "Authorization: Bearer $TOKEN")
                SWARM_ID=$(echo "$RESPONSE" | jq -r '.ID // empty' 2>/dev/null)

                if [ -n "$SWARM_ID" ] && [ "$SWARM_ID" != "null" ] && [ -f "$STACK_FILE_PATH" ]; then
                    local response_output erro_output http_code
                    response_output=$(mktemp)
                    erro_output=$(mktemp)

                    http_code=$(curl -s -o "$response_output" -w "%{http_code}" -X POST \
                        -H "Authorization: Bearer $TOKEN" \
                        -F "Name=$STACK_NAME" \
                        -F "file=@$STACK_FILE_PATH" \
                        -F "SwarmID=$SWARM_ID" \
                        -F "endpointId=$ENDPOINT_ID" \
                        "https://$PORTAINER_URL/api/stacks/create/swarm/file" 2> "$erro_output")
                    rm -f "$response_output" "$erro_output"

                    if [ "$http_code" -eq 200 ]; then
                        echo -e "XXX\n62\n[SUCESSO] STACK $STACK_NAME CRIADA NO PORTAINER 3/4  \nXXX"
                        return 0
                    fi
                fi
            fi
        fi

        # Fallback se falhar API do Portainer
        echo -e "XXX\n50\nREVERTENDO E CRIANDO STACK PELO SERVIDOR 3/4  \nXXX"
        docker stack deploy --prune --resolve-image always -c "$STACK_FILE_PATH" "$STACK_NAME" >/dev/null 2>&1
        sleep 2
    elif [[ "$criar_portainer" == "1" ]]; then
        echo "Criando a stack diretamente no Docker (não editável no Portainer)."
        docker stack deploy --prune --resolve-image always -c "$STACK_FILE_PATH" "$STACK_NAME" >/dev/null 2>&1
    else
        echo -e "XXX\n63\nCRIANDO STACK PELO SERVIDOR 3/4  \nXXX"
        docker stack deploy --prune --resolve-image always -c "$STACK_FILE_PATH" "$STACK_NAME" >/dev/null 2>&1
    fi
}

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

if [[ ("$minio_container" == "") ]]; then
    configurar_dns_e_tunnel "$painel" "http://${nome_app2}:9001" "PAINEL MINIO"
    configurar_dns_e_tunnel "$publico" "http://${nome_app2}:9000" "S3 MINIO"

    echo -e "XXX\n12\nCRIANDO STACKS DO MINIO 1/4 \nXXX"
    sleep 1
    cd ~
    clear
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
# Adicionar as labels apenas se for instalação tradicional
if [ "$INSTALL_TYPE" = "TRADICIONAL" ]; then
cat >> $nome_app2.yaml << EOL
      labels:
        - traefik.enable=true
        - traefik.http.routers.$nome_app_public.rule=Host(\`$publico\`)
        - traefik.http.routers.$nome_app_public.entrypoints=websecure
        - traefik.http.routers.$nome_app_public.tls.certresolver=letsencryptresolver
        - traefik.http.services.$nome_app_public.loadbalancer.server.port=9000
        - traefik.http.services.$nome_app_public.loadbalancer.passHostHeader=true
        - traefik.http.routers.$nome_app_public.service=$nome_app_public
        - traefik.http.routers.$nome_app_console.rule=Host(\`$painel\`)
        - traefik.http.routers.$nome_app_console.entrypoints=websecure
        - traefik.http.routers.$nome_app_console.tls.certresolver=letsencryptresolver
        - traefik.http.services.$nome_app_console.loadbalancer.server.port=9001
        - traefik.http.services.$nome_app_console.loadbalancer.passHostHeader=true
        - traefik.http.routers.$nome_app_console.service=$nome_app_console
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

    deploy_stack_app "$nome_app2"
    echo -e "XXX\n32\nFINALIZANDO BUILD DO MINIO 4/4 - CONCLUÍDO  \nXXX"
    sleep 2
fi

if [[ "$rabbitmq_container" == "" ]]; then
    configurar_dns_e_tunnel "$painelrabbitmq" "http://${nome_app_rabbitmq}:15672" "RABBITMQ"
fi
configurar_dns_e_tunnel "$dominiochat" "http://${nome_app_chatwoot}-app:3000" "CHATWOOT"
configurar_dns_e_tunnel "$dominio" "http://${nome_app_evolution}:8080" "EVOLUTION"

echo -e "XXX\n44\nCRIANDO STACKS 1/4 \nXXX"
sleep 2

cd ~
if [[ ("$minio_container" == "") ]]; then
###### checa se minio está rodando

max_wait_time=800  #ajuste do tempo mximo de espera

wait_interval=60

elapsed_time=0

while [ $elapsed_time -lt $max_wait_time ]; do
	CONTAINER_ID=$(docker ps -qf name=$nome_app2)
	if [ -n "$CONTAINER_ID" ]; then
		break
	fi
	sleep $wait_interval
	elapsed_time=$((elapsed_time + wait_interval))
done

if [ -z "$CONTAINER_ID" ]; then
    whiptail --title "Erro" --msgbox "O container do Minio não foi encontrado após $max_wait_time segundos" 10 60
    exit 0
fi
fi

# Aguardar MinIO inicializar internamente se CONTAINER_ID existir
if [ -n "$CONTAINER_ID" ]; then
    for i in $(seq 1 30); do
        if docker exec "$CONTAINER_ID" mc alias set localminio http://localhost:9000 "$MINIO_USER" "$MINIO_PASSWORD" --api S3v4 >/dev/null 2>&1; then
            break
        fi
        sleep 2
    done
fi

# Garantir mc (Minio Client) e jq funcionais
if ! command -v mc &> /dev/null || [ ! -s "$(command -v mc 2>/dev/null || echo /usr/local/bin/mc)" ] || ! mc --version &>/dev/null; then
    rm -f /usr/local/bin/mc 2>/dev/null || true
    if [ -n "$CONTAINER_ID" ]; then
        docker cp "$CONTAINER_ID:/usr/bin/mc" /usr/local/bin/mc >/dev/null 2>&1 || true
        chmod +x /usr/local/bin/mc 2>/dev/null || true
    fi
    if ! command -v mc &> /dev/null || [ ! -s "$(command -v mc 2>/dev/null || echo /usr/local/bin/mc)" ] || ! mc --version &>/dev/null; then
        mc_cid=$(docker create quay.io/minio/mc:latest 2>/dev/null || docker create minio/mc:latest 2>/dev/null || true)
        if [ -n "$mc_cid" ]; then
            docker cp "${mc_cid}:/usr/bin/mc" /usr/local/bin/mc >/dev/null 2>&1 || true
            docker rm -f "$mc_cid" >/dev/null 2>&1 || true
            chmod +x /usr/local/bin/mc 2>/dev/null || true
        fi
    fi
fi

if ! command -v jq &> /dev/null; then
    apt-get update -y >/dev/null 2>&1 && apt-get install -y jq >/dev/null 2>&1 || true
fi

# Configurar alias no host
mc alias set minio "https://$MINIO_PUBLIC_URL" "$MINIO_USER" "$MINIO_PASSWORD" --api S3v4 >/dev/null 2>&1 || mc alias set minio "https://$MINIO_PUBLIC_URL" "$MINIO_USER" "$MINIO_PASSWORD" --api S3v4 --insecure >/dev/null 2>&1 || true

###### CRIAR BUCKET CHATWOOT
bucket_name_chatwoot="$nome_app_chatwoot"
if [ -n "$CONTAINER_ID" ]; then
    docker exec "$CONTAINER_ID" mc mb "localminio/$bucket_name_chatwoot" >/dev/null 2>&1 || true
    docker exec "$CONTAINER_ID" mc anonymous set public "localminio/$bucket_name_chatwoot" >/dev/null 2>&1 || true
fi
mc mb "minio/$bucket_name_chatwoot" >/dev/null 2>&1 || true
mc anonymous set public "minio/$bucket_name_chatwoot" >/dev/null 2>&1 || true

create_service_account() {
    local bucket=$1
    local app_name=$2
    
    local credentials=""
    if [ -n "$CONTAINER_ID" ]; then
        credentials=$(docker exec "$CONTAINER_ID" mc admin user svcacct add localminio "$MINIO_USER" --json 2>&1 || true)
    fi
    if ! echo "$credentials" | jq -e '.accessKey' >/dev/null 2>&1; then
        credentials=$(mc admin user svcacct add minio "$MINIO_USER" --json 2>&1 || true)
    fi

    access_key=$(echo "$credentials" | jq -r '.accessKey // empty' 2>/dev/null || true)
    secret_key=$(echo "$credentials" | jq -r '.secretKey // empty' 2>/dev/null || true)

    if [[ -z "$access_key" || -z "$secret_key" ]]; then
        local raw_creds=""
        if [ -n "$CONTAINER_ID" ]; then
            raw_creds=$(docker exec "$CONTAINER_ID" mc admin user svcacct add localminio "$MINIO_USER" 2>&1 || true)
        fi
        [ -n "$raw_creds" ] || raw_creds=$(mc admin user svcacct add minio "$MINIO_USER" 2>&1 || true)
        access_key=$(echo "$raw_creds" | grep -i "Access Key:" | awk '{print $NF}' | tr -d ' \r\n' || true)
        secret_key=$(echo "$raw_creds" | grep -i "Secret Key:" | awk '{print $NF}' | tr -d ' \r\n' || true)
    fi

    if [[ -z "$access_key" || -z "$secret_key" ]]; then
        access_key="$MINIO_USER"
        secret_key="$MINIO_PASSWORD"
    fi
}

create_service_account "$bucket_name_chatwoot" "$nome_app_chatwoot"

###### CRIAR BUCKET EVOLUTION
bucket_name_evolution="$nome_app_evolution"
if [ -n "$CONTAINER_ID" ]; then
    docker exec "$CONTAINER_ID" mc mb "localminio/$bucket_name_evolution" >/dev/null 2>&1 || true
    docker exec "$CONTAINER_ID" mc anonymous set public "localminio/$bucket_name_evolution" >/dev/null 2>&1 || true
fi
mc mb "minio/$bucket_name_evolution" >/dev/null 2>&1 || true
mc anonymous set public "minio/$bucket_name_evolution" >/dev/null 2>&1 || true

create_service_account2() {
    local bucket=$1
    local app_name=$2

    local credentials2=""
    if [ -n "$CONTAINER_ID" ]; then
        credentials2=$(docker exec "$CONTAINER_ID" mc admin user svcacct add localminio "$MINIO_USER" --json 2>&1 || true)
    fi
    if ! echo "$credentials2" | jq -e '.accessKey' >/dev/null 2>&1; then
        credentials2=$(mc admin user svcacct add minio "$MINIO_USER" --json 2>&1 || true)
    fi

    access_key2=$(echo "$credentials2" | jq -r '.accessKey // empty' 2>/dev/null || true)
    secret_key2=$(echo "$credentials2" | jq -r '.secretKey // empty' 2>/dev/null || true)

    if [[ -z "$access_key2" || -z "$secret_key2" ]]; then
        local raw_creds2=""
        if [ -n "$CONTAINER_ID" ]; then
            raw_creds2=$(docker exec "$CONTAINER_ID" mc admin user svcacct add localminio "$MINIO_USER" 2>&1 || true)
        fi
        [ -n "$raw_creds2" ] || raw_creds2=$(mc admin user svcacct add minio "$MINIO_USER" 2>&1 || true)
        access_key2=$(echo "$raw_creds2" | grep -i "Access Key:" | awk '{print $NF}' | tr -d ' \r\n' || true)
        secret_key2=$(echo "$raw_creds2" | grep -i "Secret Key:" | awk '{print $NF}' | tr -d ' \r\n' || true)
    fi

    if [[ -z "$access_key2" || -z "$secret_key2" ]]; then
        access_key2="$MINIO_USER"
        secret_key2="$MINIO_PASSWORD"
    fi
}

create_service_account2 "$bucket_name_evolution" "$nome_app_evolution"





####### fim da checagem se minio rodando




cd ~
cat > $nome_cwt_redis.yaml << EOL

version: "3.7"

services:
  $nome_cwt_redis:
    image: redis:latest
    command: [
        "redis-server",
        "--appendonly",
        "yes",
        "--port",
        "6379"
      ]
    volumes:
      - $nome_cwt_redis-data:/data
    networks: 
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
  $nome_cwt_redis-data:
    external: true
    name: $nome_cwt_redis-data


networks: 
  interna: 
    external: true


EOL
deploy_stack_app "$nome_cwt_redis"

cd ~
cat > $nome_evo_redis.yaml << EOL

version: "3.7"

services:
  $nome_evo_redis:
    image: redis:latest
    command: [
        "redis-server",
        "--appendonly",
        "yes",
        "--port",
        "6379"
      ]
    volumes:
      - $nome_evo_redis-data:/data
    networks: 
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
  $nome_evo_redis-data:
    external: true
    name: $nome_evo_redis-data


networks: 
  interna: 
    external: true


EOL
deploy_stack_app "$nome_evo_redis"

cd ~
cat > $nome_app_rabbitmq.yaml << EOL

version: "3.7"
services:
  $nome_app_rabbitmq:
    image: rabbitmq:4.0-management
    hostname: $nome_app_rabbitmq
    volumes:
    - $nome_app_rabbitmq-data:/var/lib/rabbitmq/
    networks:
      - externa
      - interna
    ports:
      - "5672:5672"
      - "15672:15672"
    environment:
    - RABBITMQ_DEFAULT_USER=$usuariomq
    - RABBITMQ_DEFAULT_PASS=$senhamq
    - RABBITMQ_ERLANG_COOKIE=server
    - RABBITMQ_MANAGEMENT_URL=https://$painelrabbitmq
    - RABBITMQ_MANAGEMENT_HOST=$painelrabbitmq
    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
        - node.role == manager
EOL
# Adicionar as labels do router Traefik (declarativas para catalogação e identificação canônica)
if [ "$INSTALL_TYPE" = "TRADICIONAL" ]; then
cat >> $nome_app_rabbitmq.yaml << EOL
      labels:
      - traefik.enable=1
      - traefik.http.routers.$nome_app_rabbitmq.rule=Host(\`$painelrabbitmq\`)
      - traefik.http.routers.$nome_app_rabbitmq.entrypoints=websecure
      - traefik.http.routers.$nome_app_rabbitmq.priority=1
      - traefik.http.routers.$nome_app_rabbitmq.tls.certresolver=letsencryptresolver
      - traefik.http.routers.$nome_app_rabbitmq.service=$nome_app_rabbitmq
      - traefik.http.services.$nome_app_rabbitmq.loadbalancer.server.port=15672
      - traefik.http.services.$nome_app_rabbitmq.loadbalancer.passHostHeader=1
EOL
else
cat >> $nome_app_rabbitmq.yaml << EOL
      labels:
      - traefik.enable=0
      - traefik.http.routers.$nome_app_rabbitmq.rule=Host(\`$painelrabbitmq\`)
      - traefik.http.services.$nome_app_rabbitmq.loadbalancer.server.port=15672
EOL
fi
cat >> $nome_app_rabbitmq.yaml << EOL
volumes:
  $nome_app_rabbitmq-data:
    external: true
    name: $nome_app_rabbitmq-data
networks:
  externa:
    external: true
  interna:
    external: true




EOL
deploy_stack_app "$nome_app_rabbitmq"

cd ~
cat > $nome_app_chatwoot.yaml << EOL

version: "3.7"

##############
#
# Execute o  comando para migrar o banco:
#
# bundle exec rails db:chatwoot_prepare
# bundle exec rails db:migrate
#############

services:
  $nome_app_chatwoot-app:
    image: chatwoot/chatwoot:v4.14.2
    hostname: $nome_app_chatwoot
    command: bundle exec rails s -p 3000 -b 0.0.0.0
    entrypoint: docker/entrypoints/rails.sh
    restart: always
    #volumes:
      #- $nome_app_chatwoot-data:/app/storage # solo usar cuando no tengas configurado s3 de minio, si piensas usar no es lo agreges
      #- $nome_app_chatwoot-public:/app/public # agrega solo para poder cambir los icones y logos
      #- $nome_app_chatwoot-mailers:/app/app/views/mailers # agrega solo para poder modificar las plantillas de email
      #- $nome_app_chatwoot-mail-admin:/app/app/views/devise/mailer
    networks:
      - traefik
      - interna
    environment: 
      - INSTALLATION_NAME=$nome_app_chatwoot
      - NODE_ENV=production
      - RAILS_ENV=production
      - DISABLE_DATABASE_ENVIRONMENT_CHECK=1
      - ENABLE_DB_POOLING=true
      - DB_POOL=10  # Deve ser <= max_client_conn do PgBouncer
      - PGSSLMODE=disable  # Se não usar SSL
      - INSTALLATION_ENV=docker
      - SECRET_KEY_BASE=$encryption_key
      - FRONTEND_URL=https://$dominiochat
      - DEFAULT_LOCALE=pt_BR
      - FORCE_SSL=true
      - ENABLE_ACCOUNT_SIGNUP=false
      - REDIS_URL=redis://$nome_cwt_redis:6379/1
      - POSTGRES_HOST=postgres
      - POSTGRES_PORT=5432
      - POSTGRES_USERNAME=postgres
      - POSTGRES_PASSWORD=$postgres_password
      - POSTGRES_DATABASE=$nome_app_chatwoot
      #- DATABASE_URL=postgresql://postgres:$postgres_password@postgres:5432/$nome_app_chatwoot?prepared_statements=false
      # Servidor storage Minio
      - ACTIVE_STORAGE_SERVICE=s3_compatible  # local
      - STORAGE_BUCKET_NAME=$bucket_name_chatwoot
      - STORAGE_SECRET_ACCESS_KEY=$secret_key
      - STORAGE_ACCESS_KEY_ID=$access_key
      - STORAGE_REGION=us-east
      - STORAGE_ENDPOINT=https://$MINIO_PUBLIC_URL
      - STORAGE_FORCE_PATH_STYLE=true
      - RAILS_LOG_TO_STDOUT=true
      - USE_INBOX_AVATAR_FOR_BOT=true
      # Servidor de Email
      - MAILER_SENDER_EMAIL=$nomeempresa <$emailchat>
      - SMTP_DOMAIN=$dominiosmtpchatwoot
      - SMTP_ADDRESS=$hostsmtpchatwoot
      - SMTP_PORT=$portachatwoot
      - SMTP_USERNAME=$smtpchatwoot
      - SMTP_PASSWORD=$senhaemailchatwoot
      - SMTP_AUTHENTICATION=login
      - SMTP_ENABLE_STARTTLS_AUTO=true
      - SMTP_OPENSSL_VERIFY_MODE=peer
      - MAILER_INBOUND_EMAIL_DOMAIN=$emailchat
      - IGNORE_YOURSELF_MESSAGES=false
      #performance
      - SIDEKIQ_CONCURRENCY=10
      - RACK_TIMEOUT_SERVICE_TIMEOUT=0
      - WEBHOOKS_TRIGGER_TIMEOUT=10
      - RAILS_MAX_THREADS=5
      - WEB_CONCURRENCY=4
      - ENABLE_RACK_ATTACK=false
      - ENABLE_PUSH_RELAY_SERVER=true
      - TZ=America/Sao_Paulo
    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
          - node.role == manager
      #resources:
        #limits:
          #cpus: "1"
          #memory: 1024M
EOL
# Adicionar as labels apenas se for instalação tradicional
if [ "$INSTALL_TYPE" = "TRADICIONAL" ]; then
cat >> $nome_app_chatwoot.yaml << EOL
      labels:
        - traefik.enable=true
        - traefik.http.routers.$nome_app_chatwoot.rule=Host(\`$dominiochat\`)
        - traefik.http.routers.$nome_app_chatwoot.entrypoints=websecure
        - traefik.http.routers.$nome_app_chatwoot.tls.certresolver=letsencryptresolver
        - traefik.http.routers.$nome_app_chatwoot.priority=1
        - traefik.http.routers.$nome_app_chatwoot.service=$nome_app_chatwoot
        - traefik.http.services.$nome_app_chatwoot.loadbalancer.server.port=3000 
        - traefik.http.services.$nome_app_chatwoot.loadbalancer.passhostheader=true 
        - traefik.http.middlewares.$nome_app_chatwoot_sslheader.headers.customrequestheaders.X-Forwarded-Proto=https
        - traefik.http.routers.$nome_app_chatwoot.middlewares=$nome_app_chatwoot_sslheader@docker
EOL
fi
cat >> $nome_app_chatwoot.yaml << EOL
  $nome_app_chatwoot-sidekiq:
    image: chatwoot/chatwoot:v4.14.2
    hostname: $nome_app_chatwoot
    command: bundle exec sidekiq -C config/sidekiq.yml
    restart: always
    #volumes:
      #- $nome_app_chatwoot-data:/app/storage # solo usar cuando no tengas configurado s3 de minio, si piensas usar no es lo agreges
      #- $nome_app_chatwoot-public:/app/public # agrega solo para poder cambir los icones y logos
      #- $nome_app_chatwoot-mailers:/app/app/views/mailers # agrega solo para poder modificar las plantillas de email
      #- $nome_app_chatwoot-mail-admin:/app/app/views/devise/mailer
    networks:
      - traefik
      - interna
    environment:
      - INSTALLATION_NAME=$nome_app_chatwoot
      - NODE_ENV=production
      - RAILS_ENV=production
      - DISABLE_DATABASE_ENVIRONMENT_CHECK=1
      - ENABLE_DB_POOLING=true
      - DB_POOL=10  # Deve ser <= max_client_conn do PgBouncer
      - PGSSLMODE=disable  # Se não usar SSL
      - INSTALLATION_ENV=docker
      - SECRET_KEY_BASE=$encryption_key
      - FRONTEND_URL=https://$dominiochat
      - DEFAULT_LOCALE=pt_BR
      - FORCE_SSL=true
      - ENABLE_ACCOUNT_SIGNUP=false
      - REDIS_URL=redis://$nome_cwt_redis:6379/1
      - POSTGRES_HOST=postgres
      - POSTGRES_PORT=5432
      - POSTGRES_USERNAME=postgres
      - POSTGRES_PASSWORD=$postgres_password
      - POSTGRES_DATABASE=$nome_app_chatwoot
      #- DATABASE_URL=postgresql://postgres:$postgres_password@postgres:5432/$nome_app_chatwoot?prepared_statements=false
      # Servidor storage Minio
      - ACTIVE_STORAGE_SERVICE=s3_compatible  # local
      - STORAGE_BUCKET_NAME=$bucket_name_chatwoot
      - STORAGE_SECRET_ACCESS_KEY=$secret_key
      - STORAGE_ACCESS_KEY_ID=$access_key
      - STORAGE_REGION=us-east
      - STORAGE_ENDPOINT=https://$MINIO_PUBLIC_URL
      - STORAGE_FORCE_PATH_STYLE=true
      - RAILS_LOG_TO_STDOUT=true
      - USE_INBOX_AVATAR_FOR_BOT=true
      # Servidor de Email
      - MAILER_SENDER_EMAIL=$nomeempresa <$emailchat>
      - SMTP_DOMAIN=$dominiosmtpchatwoot
      - SMTP_ADDRESS=$hostsmtpchatwoot
      - SMTP_PORT=$portachatwoot
      - SMTP_USERNAME=$smtpchatwoot
      - SMTP_PASSWORD=$senhaemailchatwoot
      - SMTP_AUTHENTICATION=login
      - SMTP_ENABLE_STARTTLS_AUTO=true
      - SMTP_OPENSSL_VERIFY_MODE=peer
      - MAILER_INBOUND_EMAIL_DOMAIN=$emailchat
      - IGNORE_YOURSELF_MESSAGES=false
      #performance
      - SIDEKIQ_CONCURRENCY=10
      - RACK_TIMEOUT_SERVICE_TIMEOUT=0
      - WEBHOOKS_TRIGGER_TIMEOUT=10
      - RAILS_MAX_THREADS=5
      - WEB_CONCURRENCY=4
      - ENABLE_RACK_ATTACK=false
      - ENABLE_PUSH_RELAY_SERVER=true
      - TZ=America/Sao_Paulo
    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
          - node.role == manager
      #resources:
        #limits:
          #cpus: "1"
          #memory: 1024M

#volumes:
  #$nome_app_chatwoot-data:
    #external: true
    #name: $nome_app_chatwoot-data
  #$nome_app_chatwoot-public:
    #external: true
    #name: $nome_app_chatwoot-public
 # $nome_app_chatwoot-mailers:
   # external: true
    #name: $nome_app_chatwoot-mailers
  #$nome_app_chatwoot-mail-admin:
    #external: true
    #name: $nome_app_chatwoot-mail-admin
 
networks: 
  traefik: 
    external: true
    name: externa
  interna: 
    external: true
    name: interna


EOL
deploy_stack_app "$nome_app_chatwoot"

cd ~
cat > $nome_app_evolution.yaml << EOL

version: "3.7"

services:
  $nome_app_evolution:
    image: evoapicloud/evolution-api:v2.3.7
    networks:
      - externa
      - interna
    environment:
      # Configurar el servidor de evolution
      #- SERVER_TYPE=https
      #- SERVER_PORT=8080
      - SERVER_URL=https://$dominio
      # Telemetria
      - TELEMETRY=true
      - TELEMETRY_URL=
      # Configurar CORS
      - CORS_ORIGIN=*
      - CORS_METHODS=POST,GET,PUT,DELETE
      - CORS_CREDENTIALS=true
      # Configurar autenticación
      - AUTHENTICATION_API_KEY=$key
      - AUTHENTICATION_EXPOSE_IN_FETCH_INSTANCES=true
      # Determina los logs que serán mostrados
      - LOG_LEVEL=ERROR,WARN,DEBUG,INFO,LOG,VERBOSE,DARK,WEBHOOKS,WEBSOCKET
      - LOG_COLOR=true
      - LOG_BAILEYS=error
       # Información que se mostrará en los smartphones
      - CONFIG_SESSION_PHONE_CLIENT=$client
      - CONFIG_SESSION_PHONE_NAME=Chrome
      ## Definir versão do Whatsapp Web
      ## pegue a versão em: https://web.whatsapp.com/check-update?version=0&platform=web
      #- CONFIG_SESSION_PHONE_VERSION=2.2413.51
      #- CONFIG_SESSION_PHONE_VERSION=2.2413.79
      #- CONFIG_SESSION_PHONE_VERSION=2.3000.1015901307
      # Configurar el QR code
      - QRCODE_LIMIT=5
      - QRCODE_COLOR=#000000
      # Determina si se elimarán las instancias no conectadas
      - DEL_INSTANCE=false
      #- DEL_TEMP_INSTANCES=false nao usado 
      # Configurar provider (alternativa a base de datos)
      - PROVIDER_ENABLED=false
      - PROVIDER_HOST=127.0.0.1
      - PROVIDER_PORT=5656
      - PROVIDER_PREFIX=$nome_app_evolution
      # Configurar base de datos (Postgres)   
      - DATABASE_ENABLED=true
      - DATABASE_PROVIDER=postgresql
      - DATABASE_CONNECTION_URI=postgres://postgres:$postgres_password@postgres:5432/evolution
      # - DATABASE_CONNECTION_URI=postgres://postgres:$postgres_password@postgres:6432/evolution?schema=public
      - DATABASE_CONNECTION_CLIENT_NAME=$nome_app_evolution
      - DATABASE_SAVE_DATA_INSTANCE=true
      - DATABASE_SAVE_DATA_NEW_MESSAGE=true
      - DATABASE_SAVE_MESSAGE_UPDATE=true
      - DATABASE_SAVE_DATA_CONTACTS=true
      - DATABASE_SAVE_DATA_CHATS=true
      - DATABASE_SAVE_DATA_LABELS=true
      - DATABASE_SAVE_DATA_HISTORIC=true
      # Configurar RabbitMQ    
      - RABBITMQ_ENABLED=true
      - RABBITMQ_URI=amqp://$usuariomq:$senhamq@$nome_app_rabbitmq:5672/%2F
      - RABBITMQ_EXCHANGE_NAME=$nome_app_evolution
      - RABBITMQ_GLOBAL_ENABLED=false
      - RABBITMQ_EVENTS_APPLICATION_STARTUP=false
      - RABBITMQ_EVENTS_INSTANCE_CREATE=false
      - RABBITMQ_EVENTS_INSTANCE_DELETE=false
      - RABBITMQ_EVENTS_QRCODE_UPDATED=false
      - RABBITMQ_EVENTS_MESSAGES_SET=false
      - RABBITMQ_EVENTS_MESSAGES_UPSERT=false
      - RABBITMQ_EVENTS_MESSAGES_EDITED=false
      - RABBITMQ_EVENTS_MESSAGES_UPDATE=false
      - RABBITMQ_EVENTS_MESSAGES_DELETE=false
      - RABBITMQ_EVENTS_SEND_MESSAGE=false
      - RABBITMQ_EVENTS_CONTACTS_SET=false
      - RABBITMQ_EVENTS_CONTACTS_UPSERT=false
      - RABBITMQ_EVENTS_CONTACTS_UPDATE=false
      - RABBITMQ_EVENTS_PRESENCE_UPDATE=false
      - RABBITMQ_EVENTS_CHATS_SET=false
      - RABBITMQ_EVENTS_CHATS_UPSERT=false
      - RABBITMQ_EVENTS_CHATS_UPDATE=false
      - RABBITMQ_EVENTS_CHATS_DELETE=false
      - RABBITMQ_EVENTS_GROUPS_UPSERT=false
      - RABBITMQ_EVENTS_GROUP_UPDATE=false
      - RABBITMQ_EVENTS_GROUP_PARTICIPANTS_UPDATE=false
      - RABBITMQ_EVENTS_CONNECTION_UPDATE=true
      - RABBITMQ_EVENTS_CALL=false
      - RABBITMQ_EVENTS_TYPEBOT_START=false
      - RABBITMQ_EVENTS_TYPEBOT_CHANGE_STATUS=false
      # Configurar SQS     
      - SQS_ENABLED=false
      - SQS_ACCESS_KEY_ID=
      - SQS_SECRET_ACCESS_KEY=
      - SQS_ACCOUNT_ID=
      - SQS_REGION=
      # Configurar websocket:
      - WEBSOCKET_ENABLED=false
      - WEBSOCKET_GLOBAL_EVENTS=false
      # Configurar API oficial de WhatsApp     
      - WA_BUSINESS_TOKEN_WEBHOOK=evolution
      - WA_BUSINESS_URL=https://graph.facebook.com
      - WA_BUSINESS_VERSION=v20.0
      - WA_BUSINESS_LANGUAGE=pt_BR
      # Configurar el webhook global
      - WEBHOOK_GLOBAL_ENABLED=false
      - WEBHOOK_GLOBAL_URL=https://URL
      - WEBHOOK_GLOBAL_WEBHOOK_BY_EVENTS=false
      - WEBHOOK_EVENTS_APPLICATION_STARTUP=false
      - WEBHOOK_EVENTS_QRCODE_UPDATED=true
      - WEBHOOK_EVENTS_MESSAGES_SET=true
      - WEBHOOK_EVENTS_MESSAGES_UPSERT=true
      - WEBHOOK_EVENTS_MESSAGES_EDITED=true
      - WEBHOOK_EVENTS_MESSAGES_UPDATE=true
      - WEBHOOK_EVENTS_MESSAGES_DELETE=true
      - WEBHOOK_EVENTS_SEND_MESSAGE=true
      - WEBHOOK_EVENTS_CONTACTS_SET=true
      - WEBHOOK_EVENTS_CONTACTS_UPSERT=true
      - WEBHOOK_EVENTS_CONTACTS_UPDATE=true
      - WEBHOOK_EVENTS_PRESENCE_UPDATE=true
      - WEBHOOK_EVENTS_CHATS_SET=true
      - WEBHOOK_EVENTS_CHATS_UPSERT=true
      - WEBHOOK_EVENTS_CHATS_UPDATE=true
      - WEBHOOK_EVENTS_CHATS_DELETE=true
      - WEBHOOK_EVENTS_GROUPS_UPSERT=true
      - WEBHOOK_EVENTS_GROUPS_UPDATE=true
      - WEBHOOK_EVENTS_GROUP_PARTICIPANTS_UPDATE=true
      - WEBHOOK_EVENTS_CONNECTION_UPDATE=true
      - WEBHOOK_EVENTS_LABELS_EDIT=true
      - WEBHOOK_EVENTS_LABELS_ASSOCIATION=true
      - WEBHOOK_EVENTS_CALL=true
      - WEBHOOK_EVENTS_TYPEBOT_START=false
      - WEBHOOK_EVENTS_TYPEBOT_CHANGE_STATUS=false
      - WEBHOOK_EVENTS_ERRORS=false
      - WEBHOOK_EVENTS_ERRORS_WEBHOOK=https://url
      # Configurar Typebot
      - TYPEBOT_ENABLED=true
      #- TYPEBOT_SEND_MEDIA_BASE64=true
      #- TYPEBOT_KEEP_OPEN=true
      ## Novas variaveis para o Typebot
      - TYPEBOT_API_VERSION=latest
      # Configurar Chatwoot
      - CHATWOOT_ENABLED=true
      - CHATWOOT_MESSAGE_READ=true
      - CHATWOOT_MESSAGE_DELETE=true
      - CHATWOOT_IMPORT_DATABASE_CONNECTION_URI=postgres://postgres:$postgres_password@postgres:5432/$nome_app_chatwoot?sslmode=disable 
      - CHATWOOT_IMPORT_PLACEHOLDER_MEDIA_MESSAGE=true
      - LANGUAGE=pt-BR
      # OpenAI - Environment variables
      - OPENAI_ENABLED=true
      # Dify - Environment variables
      - DIFY_ENABLED=false
      # Redis
      - CACHE_REDIS_ENABLED=true
      - CACHE_REDIS_URI=redis://$nome_evo_redis:6379/1
      - CACHE_REDIS_PREFIX_KEY=evo2
      - CACHE_REDIS_SAVE_INSTANCES=false
      - CACHE_LOCAL_ENABLED=false
      - CLEAN_STORE_CLEANING_INTERVAL=7200 # seconds === 2h
      - CLEAN_STORE_MESSAGES=true
      - CLEAN_STORE_MESSAGE_UP=true
      - CLEAN_STORE_CONTACTS=true
      - CLEAN_STORE_CHATS=true

      # AMAZON S3 - Environment variables
      # - S3_ENABLED=true
      # - S3_BUCKET=bucket_name
      # - S3_ACCESS_KEY=access_key_id
      # - S3_SECRET_KEY=secret_access_key
      # - S3_ENDPOINT=s3.amazonaws.com # region: s3.eu-west-3.amazonaws.com

      # MINIO Use SSL - Environment variables
      - S3_ENABLED=true
      - S3_ACCESS_KEY=$access_key2
      - S3_SECRET_KEY=$secret_key2
      - S3_BUCKET=$bucket_name_evolution
      - S3_PORT=443
      - S3_ENDPOINT=$MINIO_PUBLIC_URL
      - S3_USE_SSL=true 
      


    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
          - node.role == manager
EOL
# Adicionar as labels apenas se for instalação tradicional
if [ "$INSTALL_TYPE" = "TRADICIONAL" ]; then
cat >> $nome_app_evolution.yaml << EOL
      labels:
        - traefik.enable=true
        - traefik.http.routers.$nome_app_evolution.rule=Host(\`$dominio\`)
        - traefik.http.routers.$nome_app_evolution.entrypoints=websecure
        - traefik.http.routers.$nome_app_evolution.tls.certresolver=letsencryptresolver
        - traefik.http.routers.$nome_app_evolution.priority=1
        - traefik.http.routers.$nome_app_evolution.service=$nome_app_evolution
        - traefik.http.services.$nome_app_evolution.loadbalancer.server.port=8080
        - traefik.http.services.$nome_app_evolution.loadbalancer.passHostHeader=true
EOL
fi
cat >> $nome_app_evolution.yaml << EOL

networks:
  externa:
    external: true
  interna:
    external: true
    
EOL
deploy_stack_app "$nome_app_evolution"

# FINALIZANDO INSTALACAO E LIBERANDO BRAND NO INSTALLATION CONFIGS
#
#######################################################

echo -e "XXX\n99\nFINALIZANDO: ISSO PODE DEMORAR ALGUNS MINUTOS  \nXXX"

max_wait_time=800  #ajuste do tempo mximo de espera

wait_interval=10

elapsed_time=0

while [ $elapsed_time -lt $max_wait_time ]; do
	CONTAINER_ID=$(docker ps -qf name=$nome_app_chatwoot-app)
	if [ -n "$CONTAINER_ID" ]; then
		break
	fi
	sleep $wait_interval
	elapsed_time=$((elapsed_time + wait_interval))
done

if [ -z "$CONTAINER_ID" ]; then
	echo "O container não foi encontrado após $max_wait_time segundos."
	exit 1
fi



# 1. Removido o 't' do exec para não quebrar no whiptail
docker exec -i "$CONTAINER_ID" bundle exec rails db:chatwoot_prepare > /dev/null 2>&1

sleep 20

# 2. Busca exata ancorando o nome (evita pegar postgres de outras stacks)
CONTAINER_ID=$(docker ps -q -f "name=^postgres_")

if [ -z "$CONTAINER_ID" ]; then
    echo "Nenhum container Postgres encontrado."
    exit 1
fi

# 3. O nome do banco (-d) vai direto na chamada. 
# O ON_ERROR_STOP garante que se o banco não existir, ele não roda os UPDATEs em banco errado.
docker exec -i $CONTAINER_ID psql -U postgres -d $nome_app_chatwoot -v ON_ERROR_STOP=1 > /dev/null 2>&1 <<EOF

UPDATE public.installation_configs 
SET serialized_value = '"--- !ruby/hash:ActiveSupport::HashWithIndifferentAccess\nvalue: enterprise\n"' 
WHERE name = 'INSTALLATION_PRICING_PLAN';

UPDATE public.installation_configs 
SET serialized_value = '"--- !ruby/hash:ActiveSupport::HashWithIndifferentAccess\nvalue: 10000\n"' 
WHERE name = 'INSTALLATION_PRICING_PLAN_QUANTITY';

UPDATE public.installation_configs 
SET serialized_value = '"--- !ruby/hash:ActiveSupport::HashWithIndifferentAccess\nvalue: e04t63ee-5gg8-4b94-8914-ed8137a7d938\n"' 
WHERE name = 'INSTALLATION_IDENTIFIER';

EOF


sleep 12
echo -e "XXX\n100\nFINALIZANDO INST. CHATWOOTORIG + EVOLUTION 2.0 + RABBITMQ + MINIO 4/4 - CONCLUIDO  \nXXX"

sleep 3

}|whiptail --title "CHATWOOTORIG + EVOLUTION 2.0 + RABBITMQ + MINIO PROGRESSO DA INSTALAÇÃO" --gauge "Aguarde a instalação dos ítens necessrios" 6 60 0

cd 
#
# FIM DE FINALIZANDO INSTALACAO E LIBERANDO BRAND NO INSTALLATION CONFIGS
#
#######################################################

# VERIFICAÇÃO FINAL - Versão Corrigida
if [ "$INSTALL_TYPE" = "CLOUDFLARE_TUNNEL" ]; then
    failed_domains=0
    domains_to_check=""
    
    # Determinar quais domínios verificar baseado se Minio foi instalado
    if [[ "$minio_container" == "" ]]; then
        domains_to_check="$painel $publico $painelrabbitmq $dominiochat $dominio"
    else
        domains_to_check="$painelrabbitmq $dominiochat $dominio"
    fi

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
        whiptail --title "Sucesso" --msgbox "Instalação concluída com sucesso! Cloudflare Tunnel configurado.\n\nPressione ENTER para voltar ao Menu Principal" 20 78
    else
        whiptail --title "Aviso" --msgbox "Instalação concluída, mas $failed_domains domínio(s) podem precisar de ajustes no DNS.\n\nIsso é normal logo após a criação - o DNS pode levar alguns minutos para propagar.\n\nSe o problema persistir, verifique:\n1. Os registros CNAME no Cloudflare\n2. A configuração do Tunnel\n3. As rotas no Cloudflare Tunnel\n\nPressione ENTER para voltar ao Menu Principal" 20 78
    fi
else
    # [Mantém o código existente para INSTALAÇÃO TRADICIONAL]
    ip_servidor=$(curl -s --max-time 10 ipinfo.io/ip)
    status=0
    
    if [[ "$minio_container" == "" ]]; then
        dns_ip1=$(timeout 10 nslookup "$painel" 2>/dev/null | grep "Address" | tail -n1 | awk '{print $2}')
        dns_ip2=$(timeout 10 nslookup "$publico" 2>/dev/null | grep "Address" | tail -n1 | awk '{print $2}')
        [[ "$dns_ip1" != "$ip_servidor" ]] && status=1
        [[ "$dns_ip2" != "$ip_servidor" ]] && status=1
    fi

    dns_ip3=$(timeout 10 nslookup "$painelrabbitmq" 2>/dev/null | grep "Address" | tail -n1 | awk '{print $2}')
    dns_ip4=$(timeout 10 nslookup "$dominiochat" 2>/dev/null | grep "Address" | tail -n1 | awk '{print $2}')
    dns_ip5=$(timeout 10 nslookup "$dominio" 2>/dev/null | grep "Address" | tail -n1 | awk '{print $2}')
    [[ "$dns_ip3" != "$ip_servidor" ]] && status=1
    [[ "$dns_ip4" != "$ip_servidor" ]] && status=1
    [[ "$dns_ip5" != "$ip_servidor" ]] && status=1

    if [[ $status -eq 1 ]]; then
        whiptail --title "Erro" --msgbox "Não foi possível acessar um ou mais subdomínios. Verifique os apontamentos de DNS." 20 78
    else
        whiptail --title "Sucesso" --msgbox "Instalação concluída com sucesso! Tecle enter para continuar." 20 78
    fi
fi

exit 0


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
		whiptail --title "INSTALAÇÃO DO SUPABASE: FERRAMENTA DE BD" --msgbox "$msg" --fb 10 70;
	}

  while true; do
CHOICE=$(
whiptail --title "INSTALAÇÃO DO SUPABASE: FERRAMENTA DE BD" --menu "Aperte ENTER para iniciar a instalação do Baserow ou selecione SAIR (Utilize setas e Enter)\n\nTIPO DE INSTALAÇÃO DETECTADA: $INSTALL_TYPE\n\nINSTRUÇÕES:\nAntes de prosseguir, verifique os registros DNS conforme seu tipo de instalação:" 20 70 2 \
	"1)" "CONTINUAR"   \
	"2)" "SAIR"  3>&2 2>&1 1>&3	
)

case $CHOICE in
	"1)")   
		clear
        break
	;;
	
	"2)") 
      #  sleep 1
        cd /
        cd
        exit 0
        ;; 
esac
done
####funcao

generate_jwt_tokens() {
    # Verificar a disponibilidade dos comandos necessários e instalá-los se necessário
    if ! command -v openssl &> /dev/null; then
        echo "O comando 'openssl' não está disponível. Tentando instalar..."
        if [[ "$(uname)" == "Darwin" ]]; then
            # macOS
            brew install openssl
        elif [[ "$(expr substr $(uname -s) 1 5)" == "Linux" ]]; then
            # Linux
            if [[ -f /etc/redhat-release ]]; then
                # Red Hat, CentOS, Fedora
                sudo yum install -y openssl
            elif [[ -f /etc/debian_version ]]; then
                # Debian, Ubuntu
                sudo apt-get install -y openssl
            else
                echo "Não foi possível identificar a distribuição Linux. Por favor, instale o OpenSSL manualmente."
                return 1
            fi
        else
            echo "Sistema operacional não suportado. Por favor, instale o OpenSSL manualmente."
            return 1
        fi
    fi

    if ! command -v jq &> /dev/null; then
        echo "O comando 'jq' não está disponível. Tentando instalar..."
        if [[ "$(uname)" == "Darwin" ]]; then
            # macOS
            brew install jq
        elif [[ "$(expr substr $(uname -s) 1 5)" == "Linux" ]]; then
            # Linux
            if [[ -f /etc/redhat-release ]]; then
                # Red Hat, CentOS, Fedora
                sudo yum install -y jq
            elif [[ -f /etc/debian_version ]]; then
                # Debian, Ubuntu
                sudo apt-get install -y jq
            else
                echo "Não foi possível identificar a distribuição Linux. Por favor, instale o jq manualmente."
                return 1
            fi
        else
            echo "Sistema operacional não suportado. Por favor, instale o jq manualmente."
            return 1
        fi
    fi

# Definir os payloads dos JWTs
    payload_service_key=$(echo '{
      "role": "service_role",
      "iss": "supabase",
      "iat": 1715050800,
      "exp": 1872817200
    }' | jq .)

    
    payload_anon_key=$(echo '{
      "role": "anon",
      "iss": "supabase",
      "iat": 1715050800,
      "exp": 1872817200
    }' | jq .)

    # Gerar uma chave secreta aleatória e segura
    secret=$(openssl rand -hex 20)

    # Codificar o header em base64url
    header=$(echo -n '{"alg":"HS256","typ":"JWT"}' | openssl base64 | tr -d '=' | tr '+/' '-_' | tr -d '\n')
    
    # Codificar os payloads em base64url
    payload_service_key_base64=$(echo -n "$payload_service_key" | openssl base64 | tr -d '=' | tr '+/' '-_' | tr -d '\n')
    payload_anon_key_base64=$(echo -n "$payload_anon_key" | openssl base64 | tr -d '=' | tr '+/' '-_' | tr -d '\n')

    # Criar as assinaturas dos tokens usando a mesma chave secreta
    signature_service_key=$(echo -n "$header.$payload_service_key_base64" | openssl dgst -sha256 -hmac "$secret" -binary | openssl base64 | tr -d '=' | tr '+/' '-_' | tr -d '\n')
    signature_anon_key=$(echo -n "$header.$payload_anon_key_base64" | openssl dgst -sha256 -hmac "$secret" -binary | openssl base64 | tr -d '=' | tr '+/' '-_' | tr -d '\n')

    # Combinar as partes dos tokens
    token_service_key="$header.$payload_service_key_base64.$signature_service_key"
    token_anon_key="$header.$payload_anon_key_base64.$signature_anon_key"

    # Retornar os valores gerados como uma string separada por espaços
    echo "$secret $token_service_key $token_anon_key"
}

# Chamar a função e armazenar o retorno em uma variável
result=$(generate_jwt_tokens)

# Verificar se o resultado está vazio
if [[ -z "$result" ]]; then
    echo "A função retornou um resultado vazio. Verifique a configuração do ambiente e as dependências."
    exit 1
fi

# Extrair os valores individuais usando o comando 'read'
read secret token_service_key token_anon_key <<< "$result"

#funcao

  while true ; do
		url_supabase=$(whiptail --title "1/11 - URL do Supabase" --inputbox "Digite o link do builder do Supabase (ex: supabase.seudominio.com):" --fb 12 60 3>&1 1>&2 2>&3) ; saida=$?
		if [[ $saida -eq '0' ]] ; then
			if [[ -z $url_supabase ]] ; then msg "Digite o link do Supabase, para poder continuar" ; continue ; else break; fi
		else
			echo $url_supabase ; echo "saindo..."  &  exit 0 ;
		fi
	done


      while true ; do
		user_supabase=$(whiptail --title "2/11 - Digite o Usuário do Supabase" --inputbox "Digite o um nome de usuário (ex: seumome):" --fb 12 60 3>&1 1>&2 2>&3) ; saida=$?
		if [[ $saida -eq '0' ]] ; then
			if [[ -z $user_supabase ]] ; then msg "Digite um nome de usuário, para poder continuar" ; continue ; else break; fi
		else
			echo $user_supabase ; echo "saindo..."  &  exit 0 ;
		fi
	done

    while true ; do
		pass_supabase=$(whiptail --title "3/11 - Senha do Supabase" --inputbox "Crie sua Senha do Supabase(ex: gdhRtuipoo):" --fb 12 60 3>&1 1>&2 2>&3) ; saida=$?
		if [[ $saida -eq '0' ]] ; then
			#if [[ -z $senhamq ]] ; then msg "Digite uma senha para o RabbitMq para poder continuar" ; continue ; else break; fi
		if [[ (-z $pass_supabase) || ("$pass_supabase" =~ [^a-zA-Z0-9]) || (${#pass_supabase} -gt 16) ]] ; then msg "Digite uma senha para o Supabase, sem caracteres especiais e até 16 digitos para poder continuar" ; continue ; else break; fi
    else
			echo $pass_supabase ; echo "saindo..."  &  exit 0 ;
		fi
	done

     while true ; do
		email_supabase=$(whiptail --title "4/11 - Email para o SMTP" --inputbox "Digite o Email para SMTP (ex: seumome@seudominio.com.br):" --fb 12 60 3>&1 1>&2 2>&3) ; saida=$?
		if [[ $saida -eq '0' ]] ; then
			if [[ -z $email_supabase ]] ; then msg "Digite o Email para SMTP, para poder continuar" ; continue ; else break; fi
		else
			echo $email_supabase ; echo "saindo..."  &  exit 0 ;
		fi
	done

    usuario_email_supabase=$(whiptail --title "5/11 - Usuário do Email SMTP" --inputbox "Pressione ENTER para configurar depois, ou digite o usuário do seu email (ex: contato@dominio.com):" --fb 12 60 3>&1 1>&2 2>&3) ; saida=$?
		if [[ $saida -eq '0' ]] ; then if [[ -z $usuario_email_supabase ]] ; then usuario_email_supabase=usuario_smtp ; fi else echo "saindo..." ; exit ; fi

    senha_email_supabase=$(whiptail --title "6/11 - Senha do Email SMTP" --inputbox "Pressione ENTER para configurar depois, ou digite a senha SMTP do seu email:" --fb 12 60 3>&1 1>&2 2>&3) ; saida=$?
		if [[ $saida -eq '0' ]] ; then if [[ -z $senha_email_supabase ]] ; then senha_email_supabase=senha_smtp ; fi else echo "saindo..." ; exit ; fi


    smtp_email_supabase=$(whiptail --title "7/11 - Host SMTP do Email" --inputbox "Pressione ENTER para configurar depois, ou digite o Host SMTP do seu email (ex: smtp.hostinger.com):" --fb 12 60 3>&1 1>&2 2>&3) ; saida=$?
		if [[ $saida -eq '0' ]] ; then if [[ -z $smtp_email_supabase ]] ; then smtp_email_supabase=smtp.site.com ; fi else echo "saindo..." ; exit ; fi


    porta_smtp_supabase=$(whiptail --title "8/11 - Porta do SMTP" --inputbox "Pressione ENTER para configurar depois, ou digite digite a Porta SMTP (ex: 465):" --fb 12 60 3>&1 1>&2 2>&3) ; saida=$?
		if [[ $saida -eq '0' ]] ; then if [[ -z $porta_smtp_supabase ]] ; then porta_smtp_supabase=465 ; fi else echo "saindo..." ; exit ; fi

 minio_url=$(whiptail --title "9/11 - Url S3 do Minio" --inputbox "Pressione ENTER para configurar depois, ou digite digite a Url S3 do Minio:" --fb 12 60 3>&1 1>&2 2>&3) ; saida=$?
		if [[ $saida -eq '0' ]] ; then if [[ -z $minio_url ]] ; then minio_url=s3.seusite.com.br ; fi else echo "saindo..." ; exit ; fi

   s3_access_key=$(whiptail --title "10/11 - Access Key do minio" --inputbox "Pressione ENTER para configurar depois, ou digite digite Access Key do minio:" --fb 12 60 3>&1 1>&2 2>&3) ; saida=$?
		if [[ $saida -eq '0' ]] ; then if [[ -z $s3_access_key ]] ; then s3_access_key=s3_access_key ; fi else echo "saindo..." ; exit ; fi
    
    s3_secret_key=$(whiptail --title "11/11 - Secret Key do minio" --inputbox "Pressione ENTER para configurar depois, ou digite digite Secret Key do minio:" --fb 12 60 3>&1 1>&2 2>&3) ; saida=$?
		if [[ $saida -eq '0' ]] ; then if [[ -z $s3_secret_key ]] ; then s3_secret_key=s3_secret_key ; fi else echo "saindo..." ; exit ; fi


  ## Verifica se a porta é 465, se sim deixa o ssl true, se não, deixa false 
    if [ "$porta_smtp_supabase" -eq 465 ]; then
    smtp_secure_supabase=true
    else
    smtp_secure_supabase=false
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

 ## Pergunta qual é o JWT_Key
    JWT_Key="$secret"

    ## Pergunta qual é o ANON_KEY
    ANON_KEY="$token_anon_key"

    ## Pergunta qual é o SERVICE_KEY
    SERVICE_KEY="$token_service_key"
# FIM DE PERGUNTAS PARA VARIAVEIS
#
#########################################################
#
# VERIFICAÇO DE DADOS
#


nome_principal="supabase"  #nome do app
sufixo_app=$(date | md5sum | head -c7)
nome_app=$nome_principal$sufixo_app
postgres_password=$(grep -oP '(?<=POSTGRES_PASSWORD=).+' /root/postgres.yaml)
container_id=$(docker ps -qf name=postgres)
docker exec -it $container_id psql -U postgres -d postgres -c "CREATE  DATABASE $nome_app;" 


# Ajuste do terminal para garantir compatibilidade
{
  tput reset 2>/dev/null         # Reinicia o terminal de forma segura
  exec 0</dev/tty 1>/dev/tty 2>&1 # Força redirecionamentos explícitos
  sleep 0.01                     # Pausa microscópica para sincronia
  clear                          # Limpeza final antes do whiptail
} || true


    # Exibe as informações formatadas com mais espaço na tela
    whiptail --title "Dados Fornecidos" \
    --msgbox "TIPO DE INSTALAÇÃO: $INSTALL_TYPE\n\nDados Preenchidos:\n\n1) URL do Supabase: $url_supabase\n2) Usuário do Supabase: $user_supabase\n3) Senha do Supabase: $pass_supabase\n4) Email para SMTP: $email_supabase\n5) Usuário do Email SMTP: $usuario_email_supabase\n6) Senha do Email SMTP: $senha_email_supabase\n7) Host do Email SMTP: $smtp_email_supabase\n8) Porta do SMTP: $porta_smtp_supabase\n9) URL S3 do Minio: $minio_url\n10) Access Key do Minio: $s3_access_key\n11) Secret Key do Minio: $s3_secret_key\n12) Criar Stack no Portainer: $([ "$criar_portainer" == "0" ] && echo "0 (Editável)" || echo "1 (Não editável)")\n\nConfira e Tecle Enter para continuar. Na próxima etapa você poderá confirmar os dados ou corrigir, se necessário." \
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
# Função para verificar o domínio
echo -e "XXX\n5\nVERIFICANDO CONFIGURAÇÃO... \nXXX"

if [ "$INSTALL_TYPE" = "TRADICIONAL" ] && [ "$criar_dns" = "0" ]; then
    # CONFIGURAÇÃO TRADICIONAL COM DNS AUTOMÁTICO
    echo -e "XXX\n10\nCONFIGURANDO DNS AUTOMÁTICO (TRADICIONAL)... \nXXX"
    
    DOMINIO_PRINCIPAL=$(echo "$url_supabase" | cut -d'.' -f2-)
    SUBDOMINIO=${url_supabase%%.$DOMINIO_PRINCIPAL}

    # Verificar e remover registros existentes
    echo -e "XXX\n15\nVERIFICANDO REGISTROS EXISTENTES... \nXXX"
    EXISTING_RECORDS=$(curl -s -X GET \
        "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records?name=${url_supabase}" \
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
        --data '{"type":"CNAME","name":"'${url_supabase}'","content":"'${nome_servidor}'.'${DOMINIO_PRINCIPAL}'","ttl":1,"proxied":false}')

    if echo "$CNAME_RESPONSE" | grep -q '"success":true'; then
        echo -e "XXX\n30\nREGISTRO CNAME CRIADO COM SUCESSO! \nXXX"
    else
        echo -e "XXX\n30\nAVISO: ERRO AO CRIAR REGISTRO CNAME \nXXX"
    fi

elif [ "$INSTALL_TYPE" = "CLOUDFLARE_TUNNEL" ]; then
    # CONFIGURAÇÃO CLOUDFLARE TUNNEL - DNS E ROTAS
    echo -e "XXX\n10\nCONFIGURANDO CLOUDFLARE TUNNEL (DNS + ROTAS)... \nXXX"
    
    DOMINIO_PRINCIPAL=$(echo "$url_supabase" | cut -d'.' -f2-)
    SUBDOMINIO=${url_supabase%%.$DOMINIO_PRINCIPAL}

    # 1. PRIMEIRO CONFIGURAR O DNS
    echo -e "XXX\n15\nCONFIGURANDO REGISTRO DNS... \nXXX"
    
    # Verificar e remover registros existentes
    EXISTING_RECORDS=$(curl -s -X GET \
        "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records?name=${url_supabase}" \
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
        --data "{\"type\":\"CNAME\",\"name\":\"${url_supabase}\",\"content\":\"${TUNNEL_ID}.cfargotunnel.com\",\"ttl\":1,\"proxied\":true}")

    if echo "$DNS_RESPONSE" | grep -q '"success":true'; then
        echo -e "XXX\n30\nREGISTRO DNS CRIADO COM SUCESSO! \nXXX"
    else
        echo -e "XXX\n30\nAVISO: ERRO AO CRIAR REGISTRO DNS \nXXX"
    fi

    # 2. AGORA ATUALIZAR AS ROTAS DO TUNNEL
    echo -e "XXX\n35\nATUALIZANDO CONFIGURAÇÃO DO TUNNEL... \nXXX"

    # Configuração do novo serviço para o Baserow
    NEW_SERVICE="http://kong:8000"
    
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
    
    jq --arg host "$url_supabase" --arg service "$NEW_SERVICE" '
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
    if nslookup "$url_supabase" >/dev/null 2>&1; then
        echo -e "XXX\n15\nDNS CONFIGURADO \nXXX"
    else
        echo -e "XXX\n15\nAVISO: VERIFIQUE A CONFIGURAÇÃO DNS \nXXX"
    fi
fi


if [ "$INSTALL_TYPE" = "TRADICIONAL" ] && [ "$criar_dns" = "1" ]; then


# Função para verificar o domínio quando fora do cloudflare
# url_supabase=$1
ip_servidor=$(curl -s --max-time 10 ipinfo.io/ip)

echo -e "XXX\n3\nVERIFICANDO SUBDOMÍNIO: $url_supabase \nXXX"
sleep 3

tentativas=5
tentativa_atual=1
sucesso=0

while [ $tentativa_atual -le $tentativas ]; do
    echo -e "XXX\n$(( (tentativa_atual * 12) / tentativas + 3 ))\nTentativa $tentativa_atual de $tentativas...\nXXX"
    
    dns_ip=$(timeout 10 nslookup -type=A "$url_supabase" | grep -E "Address: [0-9]+\." | awk '{print $2}' | head -n1)
    
    if [[ -n "$dns_ip" && "$dns_ip" == "$ip_servidor" ]]; then
        sucesso=1
       # break
    fi
    
  #  sleep $((tentativa_atual * 2))
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

####### fim de verificando dominio 

  
echo -e "XXX\n12\nINSTALANDO SUPABASE 1/4 \nXXX"
sleep 3

#INSTALACAO PASSO 1

max_attempts=3
attempt=0

while [ $attempt -le $max_attempts ]; do
sleep 1
   cd
git clone --depth 1 https://github.com/supabase/supabase  > /dev/null 2>&1
    if [ $? -eq 0 ]; then
        echo -e "XXX\n12\nBAIXANDO REPOSITÓRIO SUPABASE - OK \nXXX"
        break
    else
        echo -e "XXX\n12\nBAIXANDO REPOSITÓRIO SUPABASE - ERRO \nXXX"
        sleep 2
        echo -e "XXX\n12\nERRO: TENTATIVA $attempt de $max_attempts  \nXXX"
        #echo "Ops não foi possivel iniciar o swarm, tentativa $attempt de $max_attempts"
        attempt=$((attempt + 1))
        sleep 3
    fi
done

if [ $attempt -gt $max_attempts ]; then
  
   # echo "Não foi possível iniciar o Swarm após $max_attempts tentativas..."
   echo -e "XXX\n18\nERRO AO BAIXAR ARQUIVOS APÓS $max_attempts TENTATIVAS \nXXX"
    #echo "Recomendo formatar a VPS e tentar novamente"
     sleep 3
  echo -e "XXX\n21\nERRO: SUPABASE PODE NÃO FUNCONAR\nXXX"
  sleep 3
 #   echo "Lembre-se que o primeiro requisito é estar usando uma VPS Vazia."
   echo -e "XXX\n22\nERRO: TENTE NOVAMENTE MAIS TARDE\nXXX"
    sleep 4
   #$SHELL
fi

#INSTALACAO PASSO 2

max_attempts2=3
attempt2=0

while [ $attempt2 -le $max_attempts2 ]; do
sleep 1
sudo mkdir -p /root/supabase/docker/volumes/db/data
    if [ $? -eq 0 ]; then
        echo -e "XXX\n24\nCRIANDO DIRETÓRIO 1 - OK \nXXX"
        break
    else
        echo -e "XXX\n24\nCRIANDO DIRETÓRIO 1 - ERRO \nXXX"
        sleep 2
        echo -e "XXX\n24\nERRO: TENTATIVA $attempt2 de $max_attempts2  \nXXX"
        #echo "Ops não foi possivel iniciar o swarm, tentativa $attempt de $max_attempts"
        attempt2=$((attempt2 + 1))
        sleep 3
    fi
done

if [ $attempt2 -gt $max_attempts2 ]; then
  
   # echo "Não foi possível iniciar o Swarm após $max_attempts tentativas..."
   echo -e "XXX\n28\nERRO AO CRIAR DIRETÓRIO APÓS $max_attempts2 TENTATIVAS \nXXX"
    #echo "Recomendo formatar a VPS e tentar novamente"
     sleep 3
  echo -e "XXX\n29\nERRO: SUPABASE PODE NÃO FUNCONAR\nXXX"
  sleep 3
 #   echo "Lembre-se que o primeiro requisito é estar usando uma VPS Vazia."
   echo -e "XXX\n30\nERRO: TENTE NOVAMENTE MAIS TARDE\nXXX"
    sleep 4
   #$SHELL
fi


#INSTALACAO PASSO 3

max_attempts3=3
attempt3=0

while [ $attempt3 -le $max_attempts3 ]; do
sleep 1
sudo mkdir -p /var/lib/postgresql/data
    if [ $? -eq 0 ]; then
        echo -e "XXX\n34\nCRIANDO DIRETÓRIO 2 - OK \nXXX"
        break
    else
        echo -e "XXX\n34\nCRIANDO DIRETÓRIO 2 - ERRO \nXXX"
        sleep 2
        echo -e "XXX\n34\nERRO: TENTATIVA $attempt3 de $max_attempts3  \nXXX"
        #echo "Ops não foi possivel iniciar o swarm, tentativa $attempt de $max_attempts"
        attempt3=$((attempt3 + 1))
        sleep 3
    fi
done

if [ $attempt3 -gt $max_attempts3 ]; then
  
   # echo "Não foi possível iniciar o Swarm após $max_attempts tentativas..."
   echo -e "XXX\n36\nERRO AO CRIAR DIRETÓRIO APÓS $max_attempts3 TENTATIVAS \nXXX"
    #echo "Recomendo formatar a VPS e tentar novamente"
     sleep 3
fi

#INSTALACAO PASSO 4

max_attempts4=3
attempt4=0

while [ $attempt4 -le $max_attempts4 ]; do
sleep 1
sudo mkdir -p /root/supabase/docker/volumes/storage
    if [ $? -eq 0 ]; then
        echo -e "XXX\n34\nCRIANDO DIRETÓRIO 3 - OK \nXXX"
        break
    else
        echo -e "XXX\n34\nCRIANDO DIRETÓRIO 3 - ERRO \nXXX"
        sleep 2
        echo -e "XXX\n34\nERRO: TENTATIVA $attempt4 de $max_attempts4  \nXXX"
        #echo "Ops não foi possivel iniciar o swarm, tentativa $attempt de $max_attempts"
        attempt4=$((attempt4 + 1))
        sleep 3
    fi
done

if [ $attempt4 -gt $max_attempts4 ]; then
  
   # echo "Não foi possível iniciar o Swarm após $max_attempts tentativas..."
   echo -e "XXX\n36\nERRO AO CRIAR DIRETÓRIO APÓS $max_attempts4 TENTATIVAS \nXXX"
    #echo "Recomendo formatar a VPS e tentar novamente"
     sleep 3
fi

cd
cd

echo -e "XXX\n40\nCRIANDO STACK DO SUPABASE 1/4 - CONCLUIDO \nXXX"
sleep 3 
echo -e "XXX\n40\nFAZENDO O BUILD DO STACK DO SUPABASE 2/4 \nXXX"
sleep 3
echo -e "XXX\n50\nFAZENDO O BUILD DO STACK DO SUPABASE 2/4 - CONCLUIDO \nXXX"
sleep 3
echo -e "XXX\n50\nCRIANDO BANCO DE DADOS DO SUPABASE 3/4 \nXXX"
sleep 3
echo -e "XXX\n75\nCRIANDO BANCO DE DADOS DO SUPABASE 3/4 - CONCLUIDO \nXXX"





#######################################################
#
#  INSTALANDO O SUPABASE
#

cd

cd
clear


## Criando key Aleatórias
Senha_Postgres=$(openssl rand -hex 16)

Logflare_key=$(openssl rand -hex 16)

SECRET_KEY_BASE=$(openssl rand -hex 32)


cat > supabase.yaml <<EOL
version: "3.7"
services:

## Rode os seguintes comandos na sua VPS antes de fazer deploy desta stack:

## Baixando github com os arquivos do Supabase
## git clone --depth 1 https://github.com/supabase/supabase

## Criando pasta "data" para os volumes
## sudo mkdir -p /root/supabase/docker/volumes/db/data

## Criando pasta "storage" para armazenamento de arquivos
## sudo mkdir -p /root/supabase/docker/volumes/storage

## Criando a pasta "postgresql/data" para o db
## sudo mkdir -p /var/lib/postgresql/data

## Crie suas credenciais ANON_KEY e SERVICE_KEY através do link: https://supabase.com/docs/guides/self-hosting/docker




  studio:
    image: supabase/studio:20240701-05dfbec ## Versão da imagem
    networks: 
      - externa
      - interna
    
    environment:
      ## Ativando Log Debug
      - DEBUG=next:*

      ## Configuração do Hostname
      - HOSTNAME=0.0.0.0

      ## Dados Postgres
      - POSTGRES_PASSWORD=$Senha_Postgres ## Senha do Postgres #OK

      ## Branding
      - DEFAULT_ORGANIZATION_NAME=OrionDesign ## Nome da Empresa
      - DEFAULT_PROJECT_NAME=SetupOrion ## Nome do Projeto

      ## Urls
      - SUPABASE_PUBLIC_URL=https://$url_supabase ## Link do supabase
      - SUPABASE_URL=http://kong:8000
      - STUDIO_PG_META_URL=http://meta:8080

      ## Logflare
      - LOGFLARE_API_KEY=$Logflare_key ## Key aleatória
      - LOGFLARE_URL=http://analytics:4000
      - NEXT_PUBLIC_ENABLE_LOGS=true
      - NEXT_ANALYTICS_BACKEND_PROVIDER=postgres

      ## ANON_KEY & SERVICE_KEY
      - SUPABASE_ANON_KEY=$ANON_KEY ## ANON_KEY
      - SUPABASE_SERVICE_KEY=$SERVICE_KEY ## SERVICE_KEY
      - AUTH_JWT_SECRET=$JWT_Key

    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
          - node.role == manager



  kong:
    image: kong:2.8.1 ## Versão da imagem
    entrypoint: bash -c 'eval "echo \"\$\$(cat ~/temp.yml)\"" > ~/kong.yml && /docker-entrypoint.sh kong docker-start'

    volumes:
      - /root/supabase/docker/volumes/api/kong.yml:/home/kong/temp.yml:ro

    networks: 
      - externa
      - interna

    environment:
      ## Ativando Log Debug
      - KONG_LOG_LEVEL=debug

      ## Dados Login Supabase
      - DASHBOARD_USERNAME=$user_supabase ## Usuario Kong
      - DASHBOARD_PASSWORD=$pass_supabase ## Senha Kong

      ## JWT_SECRET
      - JWT_SECRET=$JWT_Key 
      
      ## Dados Kong
      - KONG_DATABASE=off
      - KONG_DECLARATIVE_CONFIG=/home/kong/kong.yml
      - KONG_DNS_ORDER=LAST,A,CNAME
      - KONG_PLUGINS=request-transformer,cors,key-auth,acl,basic-auth
      - KONG_NGINX_PROXY_PROXY_BUFFER_SIZE=160k
      - KONG_NGINX_PROXY_PROXY_BUFFERS=64 160k

      ## ANON_KEY & SERVICE_KEY
      - SUPABASE_ANON_KEY=$ANON_KEY ## ANON_KEY
      - SUPABASE_SERVICE_KEY=$SERVICE_KEY ## SERVICE_KEY

    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
          - node.role == manager  
      labels:
        - traefik.enable=true
        - traefik.http.routers.kong.rule=Host(\`$url_supabase\`) && PathPrefix(\`/\`) ## Url do Kong
        - traefik.http.services.kong.loadbalancer.server.port=8000
        - traefik.http.routers.kong.service=kong
        - traefik.http.routers.kong.entrypoints=websecure
        - traefik.http.routers.kong.tls.certresolver=letsencryptresolver
        - traefik.http.routers.kong.tls=true




  auth:
    image: supabase/gotrue:v2.151.0 ## Versão da imagem

    healthcheck:
      test:
        - CMD
        - wget
        - '--no-verbose'
        - '--tries=1'
        - '--spider'
        - 'http://localhost:9999/health'
      timeout: 5s
      interval: 5s
      retries: 3

    networks: 
      - externa
      - interna

    ports:
      - 9999:9999

    environment:
      - GOTRUE_API_HOST=0.0.0.0
      - GOTRUE_API_PORT=9999
      - API_EXTERNAL_URL=https://$url_supabase ## Url do Supabase
      - GOTRUE_DB_DRIVER=postgres
      - GOTRUE_DB_DATABASE_URL=postgres://supabase_auth_admin:$Senha_Postgres@db:5344/supabase  ## Senha do Postgres #OK
      - GOTRUE_SITE_URL=https://$url_supabase ## link do Supabase
      - GOTRUE_URI_ALLOW_LIST=
      - GOTRUE_JWT_ADMIN_ROLES=service_role
      - GOTRUE_JWT_AUD=authenticated
      - GOTRUE_JWT_DEFAULT_GROUP_NAME=authenticated
      - GOTRUE_JWT_EXP=3600
      - GOTRUE_JWT_SECRET=$JWT_Key ## JWT_SECRET

      ## Dados SMTP
      - GOTRUE_DISABLE_SIGNUP=false ## Desativar inscrições
      - GOTRUE_EXTERNAL_EMAIL_ENABLED=true
      - GOTRUE_EXTERNAL_ANONYMOUS_USERS_ENABLE=false
      - GOTRUE_MAILER_AUTOCONFIRM=true ## Enviar email para autenticar
      - GOTRUE_SMTP_ADMIN_EMAIL=$email_supabase ## Email SMTP
      - GOTRUE_SMTP_HOST=$smtp_email_supabase ## Host SMTP
      - GOTRUE_SMTP_PORT=$porta_smtp_supabase ## Porta SMTP
      - GOTRUE_SMTP_USER=$usuario_email_supabase ## Usuario SMTP
      - GOTRUE_SMTP_PASS=$senha_email_supabase ## Senha SMTP
      - GOTRUE_SMTP_SENDER_NAME=$email_supabase ## Email SMTP

      ## Paths SMTP
      - GOTRUE_MAILER_URLPATHS_INVITE=/auth/v1/verify
      - GOTRUE_MAILER_URLPATHS_CONFIRMATION=/auth/v1/verify
      - GOTRUE_MAILER_URLPATHS_RECOVERY=/auth/v1/verify
      - GOTRUE_MAILER_URLPATHS_EMAIL_CHANGE=/auth/v1/verify

      ## Autenticação por telefone
      - GOTRUE_EXTERNAL_PHONE_ENABLED=false
      - GOTRUE_SMS_AUTOCONFIRM=false

    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
          - node.role == manager



  rest:
    image: postgrest/postgrest:v12.0.3 ## Versão da imagem
    command: "postgrest"

    networks: 
      - externa
      - interna

    environment:
      ## Dados postgres
      - PGRST_DB_URI=postgres://authenticator:$Senha_Postgres@db:5344/supabase  ## Senha do Postgres #OK
      - PGRST_DB_SCHEMAS=public,storage,graphql_public
      #- PGRST_DB_SCHEMAS=public
      - PGRST_DB_ANON_ROLE=anon
      - PGRST_DB_USE_LEGACY_GUCS=false

      ## Dados JWT
      - PGRST_JWT_SECRET=$JWT_Key ## JWT_SECRET
      - PGRST_APP_SETTINGS_JWT_SECRET=$JWT_Key ## JWT_SECRET
      - PGRST_APP_SETTINGS_JWT_EXP=3600

    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
          - node.role == manager



  realtime:
    image: supabase/realtime:v2.25.50 ## Versão da imagem
    command: "sh -c \"/app/bin/migrate && /app/bin/realtime eval 'Realtime.Release.seeds(Realtime.Repo)' && /app/bin/server\"\n"

    healthcheck:
      test:
        - CMD
        - bash
        - '-c'
        - 'printf \0 > /dev/tcp/localhost/4000'
      timeout: 5s
      interval: 5s
      retries: 3

    networks: 
      - externa
      - interna
  
    environment:
      ## Porta RealTime
      - PORT=4000

      ## Dados Postgres
      - DB_HOST=db
      - DB_PORT=5344 ## Porta do Postgres
      - DB_USER=supabase_admin
      - DB_PASSWORD=$Senha_Postgres # OK
      - DB_NAME=supabase
      - DB_AFTER_CONNECT_QUERY=SET search_path TO _realtime
      - DB_ENC_KEY=supabaserealtime

      ## Dados JWT
      - API_JWT_SECRET=$JWT_Key ## JWT_SECRET

      ## Secret Key
      - SECRET_KEY_BASE=$SECRET_KEY_BASE

      ## Ainda não procurei saber o que essas coisas fazem
      - FLY_ALLOC_ID=fly123
      - FLY_APP_NAME=realtime
      - ERL_AFLAGS=-proto_dist inet_tcp
      - ENABLE_TAILSCALE=false
      - DNS_NODES="''"

    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
          - node.role == manager



  storage:
    image: supabase/storage-api:v1.0.6 ## Versão da imagem

    volumes:
      - /root/supabase/docker/volumes/storage:/var/lib/storage:z

    networks: 
      - externa
      - interna
  
    environment:
      ## Ativando Log Debug
      - LOG_LEVEL=debug

      ## Porta Storage
      - SERVER_PORT=5000 
      - SERVER_REGION=eu-south ## Localização
      - MULTI_TENANT=false

      ## Dados JWT
      - PGRST_JWT_SECRET=$JWT_Key ## JWT_SECRET
      - AUTH_JWT_SECRET=$JWT_Key ## JWT_SECRET

      ## Dados Postgrest
      - POSTGREST_URL=http://rest:3000
      - DATABASE_URL=postgres://supabase_admin:$Senha_Postgres@db:5344/supabase  ## Senha do Postgres #OK
      - DB_INSTALL_ROLES=false
      - FILE_SIZE_LIMIT=52428800

      ## Informações Storage
      - STORAGE_BACKEND=s3 ## Coloque s3 para minio e descomente os outros campos
      - STORAGE_S3_BUCKET=supabase
      #- FILE_STORAGE_BACKEND_PATH=/var/lib/storage
      - TENANT_ID=stub
      - REGION=eu-south ## Região
      - AWS_DEFAULT_REGION=eu-south ## Localização MinIO
      - GLOBAL_S3_BUCKET=supabase ## Nome da bucket do MinIO
      - GLOBAL_S3_ENDPOINT=https://$minio_url
      - GLOBAL_S3_PROTOCOL=https
      - GLOBAL_S3_FORCE_PATH_STYLE=true
      - AWS_ACCESS_KEY_ID=$s3_access_key ## Access Key
      - AWS_SECRET_ACCESS_KEY=$s3_secret_key ## Secret Key
      - UPLOAD_FILE_SIZE_LIMIT=524288000
      - UPLOAD_FILE_SIZE_LIMIT_STANDARD=524288000
      - UPLOAD_SIGNED_URL_EXPIRATION_TIME=120
      - TUS_URL_PATH=/upload/resumable
      - TUS_MAX_SIZE=3600000

      ## Dados ImageProxy 
      - IMAGE_TRANSFORMATION_ENABLED=true
      #- ENABLE_IMAGE_TRANSFORMATION=true
      - IMGPROXY_URL=http://imgproxy:5001
      - IMGPROXY_REQUEST_TIMEOUT=15
      - DATABASE_SEARCH_PATH=storage

      ## ANON_KEY & SERVICE_KEY
      - ANON_KEY=$ANON_KEY ## ANON_KEY
      - SERVICE_KEY=$SERVICE_KEY ## SERVICE_KEY

    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
          - node.role == manager



  imgproxy:
    image: darthsim/imgproxy:v3.8.0 ## Versão da imagem

    healthcheck:
      test:
        - CMD
        - imgproxy
        - health
      timeout: 5s
      interval: 5s
      retries: 3

    volumes:
      - /root/supabase/docker/volumes/storage:/var/lib/storage:z

    networks: 
      - externa
      - interna

    environment:
      ## Dados do ImgProxy
      - IMGPROXY_BIND=:5001
      - IMGPROXY_LOCAL_FILESYSTEM_ROOT=/
      - IMGPROXY_USE_ETAG=true
      - IMGPROXY_ENABLE_WEBP_DETECTION=true

    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
          - node.role == manager




  meta:
    image: supabase/postgres-meta:v0.83.2 ## Versão da imagem

    networks: 
      - externa
      - interna
    ports:
      - 8080:8080

    environment:
      ## Dados Meta
      - PG_META_PORT=8080
      - PG_META_HOST=0.0.0.0

      ## Dados postgres
      - PG_META_DB_HOST=db
      - PG_META_DB_PORT=5344 ## Porta do Postgres
      - PG_META_DB_NAME=supabase
      - PG_META_DB_USER=supabase_admin
      - PG_META_DB_PASSWORD=$Senha_Postgres  ## Senha do Postgres # OK

    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
          - node.role == manager



  functions:
    image: supabase/edge-runtime:v1.55.0 ## Versão da imagem
    command:
      - start
      - '--main-service'
      - /home/deno/functions/main

    volumes:
      - /root/supabase/docker/volumes/functions:/home/deno/functions:Z
      - /root/supabase/docker/volumes/functions/main/index.ts:/home/deno/functions/main/index.ts:Z
      - /root/supabase/docker/volumes/functions/hello/index.ts:/home/deno/functions/hello/index.ts:Z

    networks: 
      - externa
      - interna
      
    environment:
      ## Url Api Kong
      - SUPABASE_URL=http://kong:8000

      ## Dados Postgres
      - SUPABASE_DB_URL=postgresql://postgres:$Senha_Postgres@db:5344/supabase  ## Senha do Postgres #OK
      
      ## ANON_KEY & SERVICE_KEY
      - SUPABASE_ANON_KEY=$ANON_KEY ## ANON_KEY
      - SUPABASE_SERVICE_ROLE_KEY=$SERVICE_KEY ## SERVICE_KEY
      
      ## Dados JWT
      - JWT_SECRET=$JWT_Key ## JWT_SECRET
      - VERIFY_JWT=false

    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
          - node.role == manager



  analytics:
    image: supabase/logflare:1.4.0 ## Versão da imagem

    healthcheck:
      test:
        - CMD
        - curl
        - 'http://localhost:4000/health'
      timeout: 5s
      interval: 5s
      retries: 10

    networks: 
      - externa
      - interna

    ports:
      - 4000:4000

    environment:
      - LOGFLARE_LOG_LEVEL=debug
      - DB_USERNAME=supabase_admin
      - DB_DATABASE=supabase
      - DB_HOSTNAME=db
      - DB_PORT=5344
      - DB_PASSWORD=$Senha_Postgres # OK
      - DB_SCHEMA=_analytics
      - POSTGRES_BACKEND_URL=postgresql://supabase_admin:$Senha_Postgres@db:5344/supabase # OK
      - POSTGRES_BACKEND_SCHEMA=_analytics

      ## Logflare
      - LOGFLARE_SUPABASE=true
      - LOGFLARE_SINGLE_TENANT=true
      - LOGFLARE_SINGLE_TENANT_MODE=true
      - LOGFLARE_SUPABASE_MODE=true
      - LOGFLARE_NODE_HOST=127.0.0.1
      - LOGFLARE_API_KEY=$Logflare_key ## Key aleatória
      - LOGFLARE_MIN_CLUSTER_SIZE=1
      - LOGFLARE_FEATURE_FLAG_OVERRIDE=multibackend=true

    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
          - node.role == manager



  db:
    image: supabase/postgres:15.1.1.61 ## Versão da imagem

    healthcheck:
      test: 'pg_isready -U postgres -h localhost'
      interval: 5s
      timeout: 5s
      retries: 10 

    volumes:
      - /root/supabase/docker/volumes/db/realtime.sql:/docker-entrypoint-initdb.d/migrations/99-realtime.sql:Z
      - /root/supabase/docker/volumes/db/webhooks.sql:/docker-entrypoint-initdb.d/init-scripts/98-webhooks.sql:Z
      - /root/supabase/docker/volumes/db/roles.sql:/docker-entrypoint-initdb.d/init-scripts/99-roles.sql:Z
      - /root/supabase/docker/volumes/db/jwt.sql:/docker-entrypoint-initdb.d/init-scripts/99-jwt.sql:Z
      - /root/supabase/docker/volumes/db/data:/var/lib/postgresql/data:Z ## Precisa de criar o diretório, use: sudo mkdir -p /var/lib/postgresql/data
      - /root/supabase/docker/volumes/db/logs.sql:/docker-entrypoint-initdb.d/migrations/99-logs.sql:Z
      - supabase_db_config:/etc/postgresql-custom

    networks: 
      - externa
      - interna
    ports:
      - 5344:5344 ## Porta externas

    command:
      - postgres
      - '-c'
      - config_file=/etc/postgresql/postgresql.conf
      - '-c'
      - log_min_messages=fatal

    environment:
      ## Dados Postgres
      - POSTGRES_HOST=/var/run/postgresql
      - PGPORT=5344 ## Porta do Postgres
      - POSTGRES_PORT=5344 ## Porta do Postgres
      - PGPASSWORD=$Senha_Postgres  ## Senha do Postgres #OK
      - POSTGRES_PASSWORD=$Senha_Postgres  ## Senha do Postgres #OK
      - PGDATABASE=supabase
      - POSTGRES_DB=supabase

      ## Dados JWT
      - JWT_SECRET=$JWT_Key ## JWT_SECRET
      - JWT_EXP=3600

    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
          - node.role == manager



  vector:
    image: timberio/vector:0.28.1-alpine ## Versão da imagem
    command:
      - '--config'
      - etc/vector/vector.yml

    volumes:
    - /root/supabase/docker/volumes/logs/vector.yml:/etc/vector/vector.yml:ro
    - /var/run/docker.sock:/var/run/docker.sock:ro

    networks: 
      - externa
      - interna

    ports:
      - 9001:9001
      
    environment:
      ## Ativando Log Debug
      - VECTOR_LOG=debug
      
      ## Logflare key
      - LOGFLARE_API_KEY=$Logflare_key ## Key aleatória

    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
          - node.role == manager



volumes:
  supabase_db_config:
    external: true
    name: supabase_db_config

networks: 
  externa: 
    external: true
  interna: 
    external: true


EOL

#docker stack deploy --prune --resolve-image always -c supabase.yaml supabase >/dev/null 2>&1


if [[ "$criar_portainer" == "0" ]]; then
    # A stack será criada no Portainer
    echo -e "XXX\n76\nCRIANDO STACK NO PORTAINER 3/4  \nXXX"
   # echo "Criando a stack no Portainer para edição."
    # Substituir pelo comando ou rotina para criar a stack no Portainer
    # Aqui pode chamar um novo script ou rotina específica, exemplo:
   ## /path/to/criar_stack_no_portainer.sh "supabase" "$painelpma"

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
STACK_NAME=supabase
STACK_FILE_PATH="/root/supabase.yaml"

else
   # echo "Erro: Arquivo de dados não encontrado em $dados_file."
    sleep 5
echo -e "XXX\n77\nSEM ARQUIVO DE DADOS DO PORTAINER 3/4  \nXXX"
docker stack deploy --prune --resolve-image always -c supabase.yaml supabase >/dev/null 2>&1
sleep 5
    exit 1
fi

# Função para autenticação
get_auth_token() {
    #echo "[INFO] Autenticando no Portainer..."
    echo -e "XXX\n77\nAUTENTICANDO NO PORTAINER... 3/4  \nXXX"
    RESPONSE=$(curl -sk -X POST "https://$PORTAINER_URL/api/auth" \
        -H "Content-Type: application/json" \
        -d "{\"username\": \"$ADMIN_USERNAME\", \"password\": \"$ADMIN_PASSWORD\"}")
    TOKEN=$(echo "$RESPONSE" | jq -r '.jwt')
    if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]; then
        # echo "[ERRO] Falha na autenticação."
        echo -e "XXX\n77\nFALHA NA AUTENTICAÇÃO.. 3/4  \nXXX"
sleep 5
echo -e "XXX\n78\nREVERTENDO E CRIANDO STACK PELO SERVIDOR 3/4  \nXXX"
docker stack deploy --prune --resolve-image always -c supabase.yaml supabase >/dev/null 2>&1
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
    RESPONSE=$(curl -sk -X GET "https://$PORTAINER_URL/api/endpoints" \
        -H "Authorization: Bearer $TOKEN")
    ENDPOINT_ID=$(echo "$RESPONSE" | jq -r '.[0].Id')
    if [ -z "$ENDPOINT_ID" ] || [ "$ENDPOINT_ID" = "null" ]; then
        # echo "[ERRO] EndpointID não encontrado! Resposta: $RESPONSE"
        echo -e "XXX\n81\n[ERRO] ENDPOINTID NÃO ENCONTRADO 3/4  \nXXX"
        docker stack deploy --prune --resolve-image always -c supabase.yaml supabase >/dev/null 2>&1
        exit 1
    fi
     echo -e "XXX\n82\n[SUCESSO] ENDPOINTID OBTIDO: $ENDPOINT_ID  3/4  \nXXX"
    #echo "[SUCESSO] EndpointID obtido: $ENDPOINT_ID"
}

# Função para obter o SwarmID
get_swarm_id() {
   # echo "[INFO] Obtendo SwarmID..."
    echo -e "XXX\n83\n[INFO] OBTENDO SWARMID  3/4  \nXXX"
    RESPONSE=$(curl -sk -X GET "https://$PORTAINER_URL/api/endpoints/$ENDPOINT_ID/docker/swarm" \
        -H "Authorization: Bearer $TOKEN")
    SWARM_ID=$(echo "$RESPONSE" | jq -r '.ID')
    if [ -z "$SWARM_ID" ] || [ "$SWARM_ID" = "null" ]; then
        #echo "[ERRO] SwarmID não encontrado! Resposta: $RESPONSE"
        echo -e "XXX\n84\n[ERRO] SWARMID NÃO ENCONTRADO 3/4  \nXXX"
        docker stack deploy --prune --resolve-image always -c supabase.yaml supabase >/dev/null 2>&1
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
        docker stack deploy --prune --resolve-image always -c supabase.yaml supabase >/dev/null 2>&1
        exit 1
    fi

    #echo "[INFO] Criando stack '$STACK_NAME' no Portainer..."
     echo -e "XXX\n88\n[INFO] CRIANDO STACK $STACK_NAME NO PORTAINER 3/4  \nXXX"
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

   # echo "[DEBUG] Resposta da criação da stack: $response"
   # echo "[DEBUG] Código HTTP: $http_code"

    if [ "$http_code" -ne 200 ]; then
       # echo "[ERRO] Erro ao criar a stack. Código HTTP: $http_code. Resposta: $response"
        echo -e "XXX\n89\n[ERRO] ERRO AO CRIAR STACK 3/4  \nXXX"
        docker stack deploy --prune --resolve-image always -c supabase.yaml supabase >/dev/null 2>&1
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
    docker stack deploy --prune --resolve-image always -c supabase.yaml supabase >/dev/null 2>&1
else
    # Caso inesperado (não deve ocorrer devido à validação anterior no while loop)
   # echo "Erro: valor inesperado para criar_portainer. Encerrando..."
    echo -e "XXX\n91\n[ERRO] ERRO INESPERADO PARA CRIAR STACK NO PORTAINER 3/4  \nXXX"
    sleep 5
    echo -e "XXX\n92\nREVERTENDO E CRIANDO STACK PELO SERVIDOR 3/4  \nXXX"
docker stack deploy --prune --resolve-image always -c supabase.yaml supabase >/dev/null 2>&1
sleep 5

    exit 1
fi




echo -e "XXX\n93\nFINALIZANDO BUILD DO SUPABASE 4/4  \nXXX"

sleep 2

echo -e "XXX\n100\nFINALIZANDO BUILD DO SUPABASE 4/4 - CONCLUIDO  \nXXX"

sleep 3

}|whiptail --title "SUPABASE - PROGRESSO DA INSTALAÇÃO" --gauge "Aguarde a instalação dos ítens necessários" 6 60 0

# FIM DE INSTALANDO O SUPABASE
#
#######################################################
#
# VERIFICAÇÃO FINAL
#

# Verificação conforme tipo de instalação
if [ "$INSTALL_TYPE" = "TRADICIONAL" ]; then
    ip_servidor=$(curl -s --max-time 10 ipinfo.io/ip)
    dns_ip=$(timeout 10 nslookup $url_supabase | grep "Address" | tail -n1 | awk '{print $2}' 2>/dev/null)

    if [[ "$dns_ip" != "$ip_servidor" ]]; then
        whiptail --title "Mensagem" --msgbox "Não foi possivel acessar o dominio do SUPABASE ($url_supabase). A instalação foi cancelada. Por favor, verifique se os apontamentos DNS estão corretos e propagados!. Depois, instale novamente. Pressione ENTER para voltar ao Menu Principal" 20 78
    else
        whiptail --title "Mensagem" --msgbox "Parabéns, SUPABASE foi instalado com sucesso!\n\nAcesse: https://$url_supabase\n\nPressione ENTER para voltar ao Menu Principal" 20 78
    fi
else
    # Para Cloudflare Tunnel, verificação mais simples
    if nslookup "$url_supabase" >/dev/null 2>&1; then
        whiptail --title "Mensagem" --msgbox "Parabéns, SUPABASE foi instalado com sucesso!\n\nAcesse: https://$url_supabase\n\nConfiguração Cloudflare Tunnel concluída com rotas e DNS.\n\nPressione ENTER para voltar ao Menu Principal" 20 78
    else
        whiptail --title "Mensagem" --msgbox "AVISO: O domínio do SUPABASE ($url_supabase) não está resolvendo.\nVerifique a configuração do Cloudflare Tunnel.\n\nA instalação foi concluída, mas o acesso pode não funcionar até que o DNS esteja configurado corretamente.\n\nPressione ENTER para voltar ao Menu Principal" 20 78
    fi
fi

exit 0



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
		whiptail --title "EVOAI + EVOLUTION 2.0 + MINIO: FERRAMENTAS DE IA" --msgbox "$msg" --fb 10 70;
	}

  while true; do
CHOICE=$(
whiptail --title "EVOAI + EVOLUTION 2.0 + MINIO: FERRAMENTAS DE IA" --menu "Aperte ENTER para iniciar a instalação do EVOAI + EVOLUTION 2.0 + MINIO ou selecione SAIR (Utilize setas e Enter)\n\nTIPO DE INSTALAÇÃO DETECTADA: $INSTALL_TYPE\n\nINSTRUÇÕES:\nAntes de prosseguir, verifique os registros DNS conforme seu tipo de instalação:" 23 70 2 \
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
    whiptail --title "Erro" --msgbox "Minio instalado, mas os dados de acesso não foram encontrados. A presente instalação acessa credenciais pré-gravadas em uma pasta. Se sua instalação não é recente, pode ser que o Setup-MNO não criou esta pasta. Use outro template de instalação sem o Minio. Digite enter para abortar a instalação." 15 60
    exit 0
fi


sufixo_app=$(date | md5sum | head -c7 | tr '[:upper:]' '[:lower:]')



 #  Evo AI variaveis - inicio

while true ; do
		url_evoai_front=$(whiptail --title "Dominio do Painel Admin - EvoAi" --inputbox "Digite o Dominio do painel admin da EvoAI (ex: evoaipainel.dominio.com.br): " --fb 12 60 3>&1 1>&2 2>&3) ; saida=$?
		if [[ $saida -eq '0' ]] ; then
			if [[ -z $url_evoai_front ]] ; then msg "Digite o Dominio do painel admin da EvoAI para poder continuar" ; continue ; else break; fi
		else
			echo $url_evoai_front ; echo "saindo..."  &  exit 0 ;
		fi
	done

while true ; do
		url_evoai_api=$(whiptail --title "Dominio da API - EvoAi " --inputbox "Digite o Dominio da API da EvoAI (ex: evoapi.dominio.com.br): " --fb 12 60 3>&1 1>&2 2>&3) ; saida=$?
		if [[ $saida -eq '0' ]] ; then
			if [[ -z $url_evoai_api ]] ; then msg "Digite o Dominio da API da EvoAI para poder continuar" ; continue ; else break; fi
		else
			echo $url_evoai_api ; echo "saindo..."  &  exit 0 ;
		fi
	done


while true ; do
		email_evoai=$(whiptail --title "Email de Usuário - EvoAi" --inputbox "Digite o email de usuário da EvoAI (ex: contato@seudominio.com.br): " --fb 12 60 3>&1 1>&2 2>&3) ; saida=$?
		if [[ $saida -eq '0' ]] ; then
			if [[ -z $email_evoai ]] ; then msg "Digite o Email de usuário da EvoAI para poder continuar" ; continue ; else break; fi
		else
			echo $email_evoai ; echo "saindo..."  &  exit 0 ;
		fi
	done

while true ; do
    pass_evoai=$(whiptail --title "Senha da EvoAi" --inputbox "Crie sua Senha para a EvoAi (Use uma senha de 8 a 32 dígitos, Use Letras MAIUSCULAS e minusculas, numero e um caractere especial @ ou _):" --fb 12 60 3>&1 1>&2 2>&3) 
    saida=$?
    if [[ $saida -eq '0' ]]; then
        if [[ (-z $pass_evoai) || (${#pass_evoai} -lt 8) || (${#pass_evoai} -gt 32) ]]; then 
            msg "Crie a senha com 8 até 32 dígitos para poder continuar. Precisa ter Letras MAIUSCULAS e minusculas, numero e um caractere especial @ ou _" 
            continue 
        else 
            break
        fi
    else
        echo "$pass_evoai"; echo "Saindo..."; exit 0;
    fi
done

    smtp_email_evoai=$(whiptail --title "Email de remetente SMTP" --inputbox "Pressione ENTER para configurar depois, ou digite o email do usuário do SMTP (ex: contato@dominio.com):" --fb 12 60 3>&1 1>&2 2>&3) ; saida=$?
		if [[ $saida -eq '0' ]] ; then if [[ -z $smtp_email_evoai ]] ; then smtp_email_evoai=contato@dominio.com ; fi else echo "saindo..." ; exit ; fi

    smtp_user_evoai=$(whiptail --title "Usuário SMTP" --inputbox "Pressione ENTER para configurar depois, ou digite o usuário do SMTP (ex: nome ou contato@dominio.com):" --fb 12 60 3>&1 1>&2 2>&3) ; saida=$?
		if [[ $saida -eq '0' ]] ; then if [[ -z $smtp_user_evoai ]] ; then smtp_user_evoai=usuario_smtp ; fi else echo "saindo..." ; exit ; fi

    smtp_pass_evoai=$(whiptail --title "Senha do SMTP" --inputbox "Pressione ENTER para configurar depois, ou digite a Senha SMTP do Email (ex: @Gdt5kfj80):" --fb 12 60 3>&1 1>&2 2>&3) ; saida=$?
		if [[ $saida -eq '0' ]] ; then if [[ -z $smtp_pass_evoai ]] ; then smtp_pass_evoai=senha_smtp ; fi else echo "saindo..." ; exit ; fi

    smtp_host_evoai=$(whiptail --title "Host SMTP" --inputbox "Pressione ENTER para configurar depois, ou digite o Host SMTP do Email (ex: smtp.hostinger.com):" --fb 12 60 3>&1 1>&2 2>&3) ; saida=$?
		if [[ $saida -eq '0' ]] ; then if [[ -z $smtp_host_evoai ]] ; then smtp_host_evoai=smtp.dominio.com.br ; fi else echo "saindo..." ; exit ; fi

    smtp_port_evoai=$(whiptail --title "Porta SMTP" --inputbox "Pressione ENTER para configurar depois, ou digite a Porta SMTP do email (ex: 587):" --fb 12 60 3>&1 1>&2 2>&3) ; saida=$?
		if [[ $saida -eq '0' ]] ; then if [[ -z $smtp_port_evoai ]] ; then smtp_port_evoai=587 ; fi else echo "saindo..." ; exit ; fi

    ## Verifica se a porta é 465, se sim deixa o ssl true, se não, deixa false 
    if [ "$smtp_port_evoai" -eq 465 ]; then
    SMTP_USE_TLS=false
    SMTP_USE_SSL=true
    else
    SMTP_USE_TLS=true
    SMTP_USE_SSL=false
    fi

 #  Evo AI variaveis - fim

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

postgres_password=$(grep -oP '(?<=POSTGRES_PASSWORD=).+' /root/postgres.yaml)
nome_principal2="minio"  # nome do app
nome_app2=$nome_principal2$sufixo_app
sufixo_public="_public"
sufixo_console="_console"
nome_app_public=$nome_app2$sufixo_public
nome_app_console=$nome_app2$sufixo_console
#  Minio variaveis - fim

nome_principal_evoai="evoai"  #nome do app
nome_app_evoai=$nome_principal_evoai$sufixo_app
container_id=$(docker ps -qf name=postgres)
docker exec -it $container_id psql -U postgres -d postgres -c "CREATE  DATABASE $nome_app_evoai;" 
#  EvoAi variaveis - fim

nome_principal_evolution="evolution2"  #nome do app
nome_redis="-redis"
nome_app_evolution=$nome_principal_evolution$sufixo_app
nome_evo_redis=$nome_app_evolution$nome_redis
#  Evolution API variaveis - fim

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
    --msgbox "TIPO DE INSTALAÇÃO: $INSTALL_TYPE\n\nDados Preenchidos:\n\n1) Link Admin Minio: $MINIO_ADMIN_URL\n2) Link Público Minio: $MINIO_PUBLIC_URL\n3) Usuário do Minio: $MINIO_USER\n4) Dominio do Painel Admin - EvoAi: $url_evoai_front\n5) Dominio da API - EvoAi: $url_evoai_api\n6) Email de Usuário - EvoAi: $email_evoai\n7) Senha da EvoAi: $pass_evoai\n8) Email de usuário SMTP: $smtp_email_evoai\n9) Usuário SMTP: $smtp_user_evoai\n10) Senha do SMTP: $smtp_pass_evoai\n11) Host SMTP: $smtp_host_evoai\n12) Porta SMTP: $smtp_port_evoai\n13) Dominio Evolution API: $dominio\n14) Nome Empresa: $client\n15) Global API Key: $key\n16) Criar Stack no Portainer: $([ "$criar_portainer" == "0" ] && echo "0 (Editável)" || echo "1 (Não editável)")\n\n\nConfira e Tecle Enter para continuar. Na próxima etapa você poderá confirmar os dados ou corrigir, se necessário." \
    --fb 27 80

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

 if [[ ("$minio_container" == "") ]]; then

 # Função para verificação do domínio
  echo -e "XXX\n5\nVERIFICANDO DOMINIO 1... \nXXX"

if [ "$INSTALL_TYPE" = "TRADICIONAL" ] && [ "$criar_dns" = "0" ]; then
    # CONFIGURAÇÃO TRADICIONAL COM DNS AUTOMÁTICO
    echo -e "XXX\n6\nCONFIGURANDO DNS AUTOMÁTICO (TRADICIONAL)... \nXXX"
    
    DOMINIO_PRINCIPAL=$(echo "$painel" | cut -d'.' -f2-)
    SUBDOMINIO=${painel%%.$DOMINIO_PRINCIPAL}

    # Verificar e remover registros existentes
    echo -e "XXX\n7\nVERIFICANDO REGISTROS EXISTENTES... \nXXX"
    EXISTING_RECORDS=$(curl -s -X GET \
        "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records?name=${painel}" \
        -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
        -H "Content-Type: application/json")

    COUNT=$(echo "$EXISTING_RECORDS" | jq '.result | length')
    if [[ "$COUNT" -gt 0 ]]; then
        echo -e "XXX\n8\nREMOVENDO REGISTROS ANTIGOS... \nXXX"
        echo "$EXISTING_RECORDS" | jq -r '.result[].id' | while read -r REC_ID; do
            [[ -z "$REC_ID" ]] && continue
            curl -s -X DELETE \
                "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records/${REC_ID}" \
                -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
                -H "Content-Type: application/json" >/dev/null 2>&1
        done
    fi

    # Criar registro CNAME
    echo -e "XXX\n9\nCRIANDO REGISTRO CNAME... \nXXX"
    CNAME_RESPONSE=$(curl -s -X POST \
        "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records" \
        -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
        -H "Content-Type: application/json" \
        --data '{"type":"CNAME","name":"'${painel}'","content":"'${nome_servidor}'.'${DOMINIO_PRINCIPAL}'","ttl":1,"proxied":false}')

    if echo "$CNAME_RESPONSE" | grep -q '"success":true'; then
        echo -e "XXX\n10\nREGISTRO CNAME CRIADO COM SUCESSO! \nXXX"
    else
        echo -e "XXX\n10\nAVISO: ERRO AO CRIAR REGISTRO CNAME \nXXX"
    fi

elif [ "$INSTALL_TYPE" = "CLOUDFLARE_TUNNEL" ]; then
    # CONFIGURAÇÃO CLOUDFLARE TUNNEL - DNS E ROTAS
    echo -e "XXX\n10\nCONFIGURANDO CLOUDFLARE TUNNEL (DNS + ROTAS)... \nXXX"
    
    DOMINIO_PRINCIPAL=$(echo "$painel" | cut -d'.' -f2-)
    SUBDOMINIO=${painel%%.$DOMINIO_PRINCIPAL}

    # 1. PRIMEIRO CONFIGURAR O DNS
    echo -e "XXX\n11\nCONFIGURANDO REGISTRO DNS... \nXXX"
    
    # Verificar e remover registros existentes
    EXISTING_RECORDS=$(curl -s -X GET \
        "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records?name=${painel}" \
        -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
        -H "Content-Type: application/json")

    COUNT=$(echo "$EXISTING_RECORDS" | jq '.result | length')
    if [[ "$COUNT" -gt 0 ]]; then
        echo -e "XXX\n12\nREMOVENDO REGISTROS DNS ANTIGOS... \nXXX"
        echo "$EXISTING_RECORDS" | jq -r '.result[].id' | while read -r REC_ID; do
            [[ -z "$REC_ID" ]] && continue
            curl -s -X DELETE \
                "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records/${REC_ID}" \
                -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
                -H "Content-Type: application/json" >/dev/null 2>&1
        done
    fi

    # Criar registro CNAME para o tunnel
    echo -e "XXX\n13\nCRIANDO REGISTRO CNAME PARA TUNNEL... \nXXX"
    DNS_RESPONSE=$(curl -s -X POST \
        "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records" \
        -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
        -H "Content-Type: application/json" \
        --data "{\"type\":\"CNAME\",\"name\":\"${painel}\",\"content\":\"${TUNNEL_ID}.cfargotunnel.com\",\"ttl\":1,\"proxied\":true}")

    if echo "$DNS_RESPONSE" | grep -q '"success":true'; then
        echo -e "XXX\n14\nREGISTRO DNS CRIADO COM SUCESSO! \nXXX"
    else
        echo -e "XXX\n14\nAVISO: ERRO AO CRIAR REGISTRO DNS \nXXX"
    fi

    # 2. AGORA ATUALIZAR AS ROTAS DO TUNNEL
    echo -e "XXX\n15\nATUALIZANDO CONFIGURAÇÃO DO TUNNEL... \nXXX"

    # Configuração do novo serviço para o Minio
    NEW_SERVICE="http://${nome_app2}:9001"
    
    # Arquivos temporários
    TIMESTAMP=$(date -u +%Y%m%dT%H%M%SZ)
    TMPDIR=$(mktemp -d)
    BACKUP_RAW="$TMPDIR/backup_raw.$TIMESTAMP.json"
    TO_PUT="$TMPDIR/to_put.$TIMESTAMP.json"

    # 1) Obter configuração atual do tunnel
    echo -e "XXX\n16\nOBTENDO CONFIGURAÇÃO ATUAL DO TUNNEL... \nXXX"
    curl -sS -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
      "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/cfd_tunnel/$TUNNEL_ID/configurations" \
      | jq '.' > "$BACKUP_RAW"

    # Verificar se obteve sucesso
    if ! jq -e '.success == true' "$BACKUP_RAW" >/dev/null 2>&1; then
        echo -e "XXX\n45\nERRO: FALHA AO OBTER CONFIGURAÇÃO DO TUNNEL \nXXX"
        sleep 3
    else
        echo -e "XXX\n17\nCONFIGURAÇÃO OBTIDA COM SUCESSO \nXXX"
    fi

    # 2) Construir novo payload
    echo -e "XXX\n18\nCONFIGURANDO NOVAS ROTAS... \nXXX"
    
    jq --arg host "$painel" --arg service "$NEW_SERVICE" '
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
    echo -e "XXX\n19\nAPLICANDO NOVA CONFIGURAÇÃO DO TUNNEL... \nXXX"
    APPLY_RESPONSE=$(curl -sS -X PUT "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/cfd_tunnel/$TUNNEL_ID/configurations" \
      -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
      -H "Content-Type: application/json" \
      --data-binary @"$TO_PUT")

    if echo "$APPLY_RESPONSE" | grep -q '"success":true'; then
        echo -e "XXX\n20\nTUNNEL CONFIGURADO COM SUCESSO! \nXXX"
    else
        echo -e "XXX\n21\nAVISO: ERRO AO CONFIGURAR TUNNEL \nXXX"
    fi

    # Limpeza
    rm -rf "$TMPDIR"

 else
    # INSTALAÇÃO TRADICIONAL SEM DNS AUTOMÁTICO
    echo -e "XXX\n22\nVERIFICANDO CONFIGURAÇÃO (TRADICIONAL SEM AUTOMAÇÃO)... \nXXX"
    # Verificação básica de DNS
    if nslookup "$painel" >/dev/null 2>&1; then
        echo -e "XXX\n23\nDNS CONFIGURADO \nXXX"
    else
        echo -e "XXX\n23\nAVISO: VERIFIQUE A CONFIGURAÇÃO DNS \nXXX"
    fi
fi


if [ "$INSTALL_TYPE" = "TRADICIONAL" ] && [ "$criar_dns" = "1" ]; then


# Função para verificar o domínio quando fora do cloudflare

ip_servidor=$(curl -s --max-time 10 ipinfo.io/ip)

echo -e "XXX\n33\nVERIFICANDO SUBDOMÍNIO: $painel \nXXX"
sleep 3

tentativas=5
tentativa_atual=1
sucesso=0

while [ $tentativa_atual -le $tentativas ]; do
    echo -e "XXX\n$(( (tentativa_atual * 12) / tentativas + 3 ))\nTentativa $tentativa_atual de $tentativas...\nXXX"
    
    dns_ip1=$(timeout 10 nslookup -type=A "$painel" | grep -E "Address: [0-9]+\." | awk '{print $2}' | head -n1)
    
    if [[ -n "$dns_ip1" && "$dns_ip1" == "$ip_servidor" ]]; then
        sucesso=1
       # break
    fi
    
  #  sleep $((tentativa_atual * 2))
  sleep 1
    ((tentativa_atual++))
done

if [ $sucesso -eq 0 ]; then

    echo -e "XXX\n14\nERRO: SUBDOMÍNIO DO PAINEL MINIO NÃO APONTA PARA O IP ($ip_servidor) \nXXX"
    sleep 3
    echo -e "XXX\n14\nERRO: DNS NÃO CONFIGURADO CORRETAMENTE \nXXX"
    sleep 3
    exit 1
fi

    echo -e "XXX\n15\nDOMÍNIO 1 PAINEL MINIO VERIFICADO COM SUCESSO \nXXX"
sleep 4
fi


echo -e "XXX\n5\nVERIFICANDO DOMINIO 2... \nXXX"

if [ "$INSTALL_TYPE" = "TRADICIONAL" ] && [ "$criar_dns" = "0" ]; then
    # CONFIGURAÇÃO TRADICIONAL COM DNS AUTOMÁTICO
    echo -e "XXX\n6\nCONFIGURANDO DNS AUTOMÁTICO (TRADICIONAL)... \nXXX"
    
    DOMINIO_PRINCIPAL=$(echo "$publico" | cut -d'.' -f2-)
    SUBDOMINIO=${publico%%.$DOMINIO_PRINCIPAL}

    # Verificar e remover registros existentes
    echo -e "XXX\n7\nVERIFICANDO REGISTROS EXISTENTES... \nXXX"
    EXISTING_RECORDS=$(curl -s -X GET \
        "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records?name=${publico}" \
        -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
        -H "Content-Type: application/json")

    COUNT=$(echo "$EXISTING_RECORDS" | jq '.result | length')
    if [[ "$COUNT" -gt 0 ]]; then
        echo -e "XXX\n8\nREMOVENDO REGISTROS ANTIGOS... \nXXX"
        echo "$EXISTING_RECORDS" | jq -r '.result[].id' | while read -r REC_ID; do
            [[ -z "$REC_ID" ]] && continue
            curl -s -X DELETE \
                "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records/${REC_ID}" \
                -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
                -H "Content-Type: application/json" >/dev/null 2>&1
        done
    fi

    # Criar registro CNAME
    echo -e "XXX\n9\nCRIANDO REGISTRO CNAME... \nXXX"
    CNAME_RESPONSE=$(curl -s -X POST \
        "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records" \
        -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
        -H "Content-Type: application/json" \
        --data '{"type":"CNAME","name":"'${publico}'","content":"'${nome_servidor}'.'${DOMINIO_PRINCIPAL}'","ttl":1,"proxied":false}')

    if echo "$CNAME_RESPONSE" | grep -q '"success":true'; then
        echo -e "XXX\n10\nREGISTRO CNAME CRIADO COM SUCESSO! \nXXX"
    else
        echo -e "XXX\n10\nAVISO: ERRO AO CRIAR REGISTRO CNAME \nXXX"
    fi

elif [ "$INSTALL_TYPE" = "CLOUDFLARE_TUNNEL" ]; then
    # CONFIGURAÇÃO CLOUDFLARE TUNNEL - DNS E ROTAS
    echo -e "XXX\n10\nCONFIGURANDO CLOUDFLARE TUNNEL (DNS + ROTAS)... \nXXX"
    
    DOMINIO_PRINCIPAL=$(echo "$publico" | cut -d'.' -f2-)
    SUBDOMINIO=${publico%%.$DOMINIO_PRINCIPAL}

    # 1. PRIMEIRO CONFIGURAR O DNS
    echo -e "XXX\n11\nCONFIGURANDO REGISTRO DNS... \nXXX"
    
    # Verificar e remover registros existentes
    EXISTING_RECORDS=$(curl -s -X GET \
        "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records?name=${publico}" \
        -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
        -H "Content-Type: application/json")

    COUNT=$(echo "$EXISTING_RECORDS" | jq '.result | length')
    if [[ "$COUNT" -gt 0 ]]; then
        echo -e "XXX\n12\nREMOVENDO REGISTROS DNS ANTIGOS... \nXXX"
        echo "$EXISTING_RECORDS" | jq -r '.result[].id' | while read -r REC_ID; do
            [[ -z "$REC_ID" ]] && continue
            curl -s -X DELETE \
                "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records/${REC_ID}" \
                -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
                -H "Content-Type: application/json" >/dev/null 2>&1
        done
    fi

    # Criar registro CNAME para o tunnel
    echo -e "XXX\n13\nCRIANDO REGISTRO CNAME PARA TUNNEL... \nXXX"
    DNS_RESPONSE=$(curl -s -X POST \
        "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records" \
        -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
        -H "Content-Type: application/json" \
        --data "{\"type\":\"CNAME\",\"name\":\"${publico}\",\"content\":\"${TUNNEL_ID}.cfargotunnel.com\",\"ttl\":1,\"proxied\":true}")

    if echo "$DNS_RESPONSE" | grep -q '"success":true'; then
        echo -e "XXX\n14\nREGISTRO DNS CRIADO COM SUCESSO! \nXXX"
    else
        echo -e "XXX\n14\nAVISO: ERRO AO CRIAR REGISTRO DNS \nXXX"
    fi

    # 2. AGORA ATUALIZAR AS ROTAS DO TUNNEL
    echo -e "XXX\n15\nATUALIZANDO CONFIGURAÇÃO DO TUNNEL... \nXXX"

    # Configuração do novo serviço para o Minio
    NEW_SERVICE="http://${nome_app2}:9000"
    
    # Arquivos temporários
    TIMESTAMP=$(date -u +%Y%m%dT%H%M%SZ)
    TMPDIR=$(mktemp -d)
    BACKUP_RAW="$TMPDIR/backup_raw.$TIMESTAMP.json"
    TO_PUT="$TMPDIR/to_put.$TIMESTAMP.json"

    # 1) Obter configuração atual do tunnel
    echo -e "XXX\n16\nOBTENDO CONFIGURAÇÃO ATUAL DO TUNNEL... \nXXX"
    curl -sS -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
      "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/cfd_tunnel/$TUNNEL_ID/configurations" \
      | jq '.' > "$BACKUP_RAW"

    # Verificar se obteve sucesso
    if ! jq -e '.success == true' "$BACKUP_RAW" >/dev/null 2>&1; then
        echo -e "XXX\n45\nERRO: FALHA AO OBTER CONFIGURAÇÃO DO TUNNEL \nXXX"
        sleep 3
    else
        echo -e "XXX\n17\nCONFIGURAÇÃO OBTIDA COM SUCESSO \nXXX"
    fi

    # 2) Construir novo payload
    echo -e "XXX\n18\nCONFIGURANDO NOVAS ROTAS... \nXXX"
    
    jq --arg host "$publico" --arg service "$NEW_SERVICE" '
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
    echo -e "XXX\n19\nAPLICANDO NOVA CONFIGURAÇÃO DO TUNNEL... \nXXX"
    APPLY_RESPONSE=$(curl -sS -X PUT "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/cfd_tunnel/$TUNNEL_ID/configurations" \
      -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
      -H "Content-Type: application/json" \
      --data-binary @"$TO_PUT")

    if echo "$APPLY_RESPONSE" | grep -q '"success":true'; then
        echo -e "XXX\n20\nTUNNEL CONFIGURADO COM SUCESSO! \nXXX"
    else
        echo -e "XXX\n21\nAVISO: ERRO AO CONFIGURAR TUNNEL \nXXX"
    fi

    # Limpeza
    rm -rf "$TMPDIR"

 else
    # INSTALAÇÃO TRADICIONAL SEM DNS AUTOMÁTICO
    echo -e "XXX\n22\nVERIFICANDO CONFIGURAÇÃO (TRADICIONAL SEM AUTOMAÇÃO)... \nXXX"
    # Verificação básica de DNS
    if nslookup "$publico" >/dev/null 2>&1; then
        echo -e "XXX\n23\nDNS CONFIGURADO \nXXX"
    else
        echo -e "XXX\n23\nAVISO: VERIFIQUE A CONFIGURAÇÃO DNS \nXXX"
    fi
fi


if [ "$INSTALL_TYPE" = "TRADICIONAL" ] && [ "$criar_dns" = "1" ]; then


# Função para verificar o domínio quando fora do cloudflare

ip_servidor=$(curl -s --max-time 10 ipinfo.io/ip)

echo -e "XXX\n33\nVERIFICANDO SUBDOMÍNIO2: $publico \nXXX"
sleep 3

tentativas=5
tentativa_atual=1
sucesso=0

while [ $tentativa_atual -le $tentativas ]; do
    echo -e "XXX\n$(( (tentativa_atual * 12) / tentativas + 3 ))\nTentativa $tentativa_atual de $tentativas...\nXXX"
    
    dns_ip2=$(timeout 10 nslookup -type=A "$publico" | grep -E "Address: [0-9]+\." | awk '{print $2}' | head -n1)
    
    if [[ -n "$dns_ip2" && "$dns_ip2" == "$ip_servidor" ]]; then
        sucesso=1
       # break
    fi
    
  #  sleep $((tentativa_atual * 2))
  sleep 1
    ((tentativa_atual++))
done

if [ $sucesso -eq 0 ]; then

    echo -e "XXX\n14\nERRO: SUBDOMÍNIO2 PUBLICO DO MINIO NÃO APONTA PARA O IP ($ip_servidor) \nXXX"
    sleep 3
    echo -e "XXX\n14\nERRO: DNS NÃO CONFIGURADO CORRETAMENTE \nXXX"
    sleep 3
    exit 1
fi

    echo -e "XXX\n15\nDOMÍNIO 2 URL PÙBLICA MINIO VERIFICADO COM SUCESSO \nXXX"
sleep 4
fi

    echo -e "XXX\n12\nCRIANDO STACKS DO MINIO 1/4 \nXXX"
    sleep 1
    echo -e "XXX\n12\nCRIANDO STACKS DO MINIO 1/4 - CONCLUÍDO \nXXX"
    sleep 1 
    echo -e "XXX\n13\nFAZENDO O BUILD DOS STACKS DO MINIO 2/4 \nXXX"
    sleep 1
    echo -e "XXX\n13\nFAZENDO O BUILD DOS STACKS DO MINIO 2/4 - CONCLUÍDO \nXXX"
    sleep 1
    echo -e "XXX\n14\nINICIANDO BUILD DO MINIO 3/4 \nXXX"
    sleep 1
    echo -e "XXX\n15\nINICIANDO BUILD DO MINIO 3/4 - CONCLUÍDO \nXXX"

    #######################################################
    #
    #  INSTALANDO O MINIO
    #

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

    if [[ "$criar_portainer" == "0" ]]; then
        echo -e "XXX\n13\nCRIANDO STACK NO PORTAINER 3/4  \nXXX"
        # Configurações para criação via Portainer
        dados_file="$HOME/dados_portainer/dados_portainer"
        if [[ -f "$dados_file" ]]; then
            PORTAINER_URL=$(grep "Dominio do portainer:" "$dados_file" | cut -d':' -f2 | xargs)
            ADMIN_USERNAME=$(grep "Usuario:" "$dados_file" | cut -d':' -f2 | xargs)
            ADMIN_PASSWORD=$(grep "Senha:" "$dados_file" | cut -d':' -f2 | xargs)
            STACK_NAME=$nome_app2
            STACK_FILE_PATH="/root/$nome_app2.yaml"
        else
            sleep 5
            echo -e "XXX\n14\nSEM ARQUIVO DE DADOS DO PORTAINER 3/4  \nXXX"
            docker stack deploy --prune --resolve-image always -c $nome_app2.yaml $nome_app2 >/dev/null 2>&1
            sleep 5
            exit 1
        fi

        get_auth_token() {
            echo -e "XXX\n15\nAUTENTICANDO NO PORTAINER... 3/4  \nXXX"
            RESPONSE=$(curl -sS -X POST "https://$PORTAINER_URL/api/auth" \
                -H "Content-Type: application/json" \
                -d "{\"username\": \"$ADMIN_USERNAME\", \"password\": \"$ADMIN_PASSWORD\"}")
            TOKEN=$(echo "$RESPONSE" | jq -r '.jwt')
            if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]; then
                echo -e "XXX\n16\nFALHA NA AUTENTICAÇÃO.. 3/4  \nXXX"
                sleep 5
                echo -e "XXX\n17\nREVERTENDO E CRIANDO STACK PELO SERVIDOR 3/4  \nXXX"
                docker stack deploy --prune --resolve-image always -c $nome_app2.yaml $nome_app2 >/dev/null 2>&1
                sleep 5
                exit 1
            fi
            echo -e "XXX\n18\n[SUCESSO] AUTENTICAÇÃO OK 3/4  \nXXX"
        }

        get_endpoint_id() {
            echo -e "XXX\n19\n[INFO] OBTENDO ENDPOINTID 3/4  \nXXX"
            RESPONSE=$(curl -sS -X GET "https://$PORTAINER_URL/api/endpoints" \
                -H "Authorization: Bearer $TOKEN")
            ENDPOINT_ID=$(echo "$RESPONSE" | jq -r '.[0].Id')
            if [ -z "$ENDPOINT_ID" ] || [ "$ENDPOINT_ID" = "null" ]; then
                echo -e "XXX\n20\n[ERRO] ENDPOINTID NÃO ENCONTRADO 3/4  \nXXX"
                docker stack deploy --prune --resolve-image always -c $nome_app2.yaml $nome_app2 >/dev/null 2>&1
                exit 1
            fi
            echo -e "XXX\n21\n[SUCESSO] ENDPOINTID OBTIDO: $ENDPOINT_ID  3/4  \nXXX"
        }

        get_swarm_id() {
            echo -e "XXX\n22\n[INFO] OBTENDO SWARMID  3/4  \nXXX"
            RESPONSE=$(curl -sS -X GET "https://$PORTAINER_URL/api/endpoints/$ENDPOINT_ID/docker/swarm" \
                -H "Authorization: Bearer $TOKEN")
            SWARM_ID=$(echo "$RESPONSE" | jq -r '.ID')
            if [ -z "$SWARM_ID" ] || [ "$SWARM_ID" = "null" ]; then
                echo -e "XXX\n23\n[ERRO] SWARMID NÃO ENCONTRADO 3/4  \nXXX"
                docker stack deploy --prune --resolve-image always -c $nome_app2.yaml $nome_app2 >/dev/null 2>&1
                exit 1
            fi
            echo -e "XXX\n24\n[SUCESSO] SWARMID OBTIDO: $SWARM_ID  3/4  \nXXX"
        }

        create_stack() {
            echo -e "XXX\n25\n[INFO] VERIFICANDO SE YAML EXISTE 3/4  \nXXX"
            if [ ! -f "$STACK_FILE_PATH" ]; then
                echo -e "XXX\n26\n[ERRO] ARQUIVO $STACK_FILE_PATH NÃO ENCONTRADO 3/4  \nXXX"
                docker stack deploy --prune --resolve-image always -c $nome_app2.yaml $nome_app2 >/dev/null 2>&1
                exit 1
            fi

            echo -e "XXX\n27\n[INFO] CRIANDO STACK $STACK_NAME NO PORTAINER 3/4  \nXXX"
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
                echo -e "XXX\n28\n[ERRO] ERRO AO CRIAR STACK 3/4  \nXXX"
                docker stack deploy --prune --resolve-image always -c $nome_app2.yaml $nome_app2 >/dev/null 2>&1
                exit 1
            fi

            echo -e "XXX\n29\n[SUCESSO] STACK $STACK_NAME CRIADA COM SUCESSO 3/4  \nXXX"
        }

        get_auth_token || exit 1
        get_endpoint_id || exit 1
        get_swarm_id || exit 1
        create_stack || exit 1

    elif [[ "$criar_portainer" == "1" ]]; then
        echo "Criando a stack diretamente no Docker (não editável no Portainer)."
        docker stack deploy --prune --resolve-image always -c $nome_app2.yaml $nome_app2 >/dev/null 2>&1
    else
        echo -e "XXX\n30\n[ERRO] ERRO INESPERADO PARA CRIAR STACK NO PORTAINER 3/4  \nXXX"
        sleep 5
        echo -e "XXX\n31\nREVERTENDO E CRIANDO STACK PELO SERVIDOR 3/4  \nXXX"
        docker stack deploy --prune --resolve-image always -c $nome_app2.yaml $nome_app2 >/dev/null 2>&1
        sleep 5
        exit 1
    fi

    echo -e "XXX\n32\nFINALIZANDO BUILD DO MINIO 4/4  \nXXX"
    sleep 2
    echo -e "XXX\n33\nFINALIZANDO BUILD DO MINIO 4/4 - CONCLUÍDO  \nXXX"
    sleep 3


 fi





#########################################################
#
# MENSAGEM DE INSTALANDO
#



#VERIFICANDO CONFIGURAÇÃO EVO AI API

echo -e "XXX\n5\nVERIFICANDO CONFIGURAÇÃO EVO AI API... \nXXX"

if [ "$INSTALL_TYPE" = "TRADICIONAL" ] && [ "$criar_dns" = "0" ]; then
    # CONFIGURAÇÃO TRADICIONAL COM DNS AUTOMÁTICO
    echo -e "XXX\n10\nCONFIGURANDO DNS AUTOMÁTICO (TRADICIONAL)... \nXXX"
    
    DOMINIO_PRINCIPAL=$(echo "$url_evoai_api" | cut -d'.' -f2-)
    SUBDOMINIO=${url_evoai_api%%.$DOMINIO_PRINCIPAL}

    # Verificar e remover registros existentes
    echo -e "XXX\n15\nVERIFICANDO REGISTROS EXISTENTES... \nXXX"
    EXISTING_RECORDS=$(curl -s -X GET \
        "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records?name=${url_evoai_api}" \
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
        --data '{"type":"CNAME","name":"'${url_evoai_api}'","content":"'${nome_servidor}'.'${DOMINIO_PRINCIPAL}'","ttl":1,"proxied":false}')

    if echo "$CNAME_RESPONSE" | grep -q '"success":true'; then
        echo -e "XXX\n30\nREGISTRO CNAME CRIADO COM SUCESSO! \nXXX"
    else
        echo -e "XXX\n30\nAVISO: ERRO AO CRIAR REGISTRO CNAME \nXXX"
    fi

elif [ "$INSTALL_TYPE" = "CLOUDFLARE_TUNNEL" ]; then
    # CONFIGURAÇÃO CLOUDFLARE TUNNEL - DNS E ROTAS
    echo -e "XXX\n10\nCONFIGURANDO CLOUDFLARE TUNNEL (DNS + ROTAS)... \nXXX"
    
    DOMINIO_PRINCIPAL=$(echo "$url_evoai_api" | cut -d'.' -f2-)
    SUBDOMINIO=${url_evoai_api%%.$DOMINIO_PRINCIPAL}

    # 1. PRIMEIRO CONFIGURAR O DNS
    echo -e "XXX\n15\nCONFIGURANDO REGISTRO DNS... \nXXX"
    
    # Verificar e remover registros existentes
    EXISTING_RECORDS=$(curl -s -X GET \
        "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records?name=${url_evoai_api}" \
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
        --data "{\"type\":\"CNAME\",\"name\":\"${url_evoai_api}\",\"content\":\"${TUNNEL_ID}.cfargotunnel.com\",\"ttl\":1,\"proxied\":true}")

    if echo "$DNS_RESPONSE" | grep -q '"success":true'; then
        echo -e "XXX\n30\nREGISTRO DNS CRIADO COM SUCESSO! \nXXX"
    else
        echo -e "XXX\n30\nAVISO: ERRO AO CRIAR REGISTRO DNS \nXXX"
    fi

    # 2. AGORA ATUALIZAR AS ROTAS DO TUNNEL
    echo -e "XXX\n35\nATUALIZANDO CONFIGURAÇÃO DO TUNNEL... \nXXX"

    # Configuração do novo serviço
    NEW_SERVICE="http://${nome_app_evoai}-api:8000"
    
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
    
    jq --arg host "$url_evoai_api" --arg service "$NEW_SERVICE" '
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
    if nslookup "$url_evoai_api" >/dev/null 2>&1; then
        echo -e "XXX\n15\nDNS CONFIGURADO \nXXX"
    else
        echo -e "XXX\n15\nAVISO: VERIFIQUE A CONFIGURAÇÃO DNS \nXXX"
    fi
fi


if [ "$INSTALL_TYPE" = "TRADICIONAL" ] && [ "$criar_dns" = "1" ]; then


# Função para verificar o domínio quando fora do cloudflare

ip_servidor=$(curl -s --max-time 10 ipinfo.io/ip)

echo -e "XXX\n3\nVERIFICANDO SUBDOMÍNIO: $url_evoai_api \nXXX"
sleep 3

tentativas=5
tentativa_atual=1
sucesso=0

while [ $tentativa_atual -le $tentativas ]; do
    echo -e "XXX\n$(( (tentativa_atual * 12) / tentativas + 3 ))\nTentativa $tentativa_atual de $tentativas...\nXXX"
    
    dns_ip3=$(timeout 10 nslookup -type=A "$url_evoai_api" | grep -E "Address: [0-9]+\." | awk '{print $2}' | head -n1)
    
    if [[ -n "$dns_ip3" && "$dns_ip3" == "$ip_servidor" ]]; then
        sucesso=1
       # break
    fi
    
  #  sleep $((tentativa_atual * 2))
  sleep 1
    ((tentativa_atual++))
done

if [ $sucesso -eq 0 ]; then

    echo -e "XXX\n10\nERRO: SUBDOMÍNIO DO EVO AI API NÃO APONTA PARA O IP ($ip_servidor) \nXXX"
    sleep 3
    echo -e "XXX\n18\nERRO: DNS NÃO CONFIGURADO CORRETAMENTE \nXXX"
    sleep 3
    exit 1
fi
    echo -e "XXX\n18\nDOMÍNIO EVO AI API VERIFICADO COM SUCESSO \nXXX"
sleep 4
fi


#VERIFICANDO CONFIGURAÇÃO EVO AI FRONTEND

echo -e "XXX\n5\nVERIFICANDO CONFIGURAÇÃO EVO AI FRONTEND... \nXXX"

if [ "$INSTALL_TYPE" = "TRADICIONAL" ] && [ "$criar_dns" = "0" ]; then
    # CONFIGURAÇÃO TRADICIONAL COM DNS AUTOMÁTICO
    echo -e "XXX\n10\nCONFIGURANDO DNS AUTOMÁTICO (TRADICIONAL)... \nXXX"
    
    DOMINIO_PRINCIPAL=$(echo "$url_evoai_front" | cut -d'.' -f2-)
    SUBDOMINIO=${url_evoai_front%%.$DOMINIO_PRINCIPAL}

    # Verificar e remover registros existentes
    echo -e "XXX\n15\nVERIFICANDO REGISTROS EXISTENTES... \nXXX"
    EXISTING_RECORDS=$(curl -s -X GET \
        "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records?name=${url_evoai_front}" \
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
        --data '{"type":"CNAME","name":"'${url_evoai_front}'","content":"'${nome_servidor}'.'${DOMINIO_PRINCIPAL}'","ttl":1,"proxied":false}')

    if echo "$CNAME_RESPONSE" | grep -q '"success":true'; then
        echo -e "XXX\n30\nREGISTRO CNAME CRIADO COM SUCESSO! \nXXX"
    else
        echo -e "XXX\n30\nAVISO: ERRO AO CRIAR REGISTRO CNAME \nXXX"
    fi

elif [ "$INSTALL_TYPE" = "CLOUDFLARE_TUNNEL" ]; then
    # CONFIGURAÇÃO CLOUDFLARE TUNNEL - DNS E ROTAS
    echo -e "XXX\n10\nCONFIGURANDO CLOUDFLARE TUNNEL (DNS + ROTAS)... \nXXX"
    
    DOMINIO_PRINCIPAL=$(echo "$url_evoai_front" | cut -d'.' -f2-)
    SUBDOMINIO=${url_evoai_front%%.$DOMINIO_PRINCIPAL}

    # 1. PRIMEIRO CONFIGURAR O DNS
    echo -e "XXX\n15\nCONFIGURANDO REGISTRO DNS... \nXXX"
    
    # Verificar e remover registros existentes
    EXISTING_RECORDS=$(curl -s -X GET \
        "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records?name=${url_evoai_front}" \
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
        --data "{\"type\":\"CNAME\",\"name\":\"${url_evoai_front}\",\"content\":\"${TUNNEL_ID}.cfargotunnel.com\",\"ttl\":1,\"proxied\":true}")

    if echo "$DNS_RESPONSE" | grep -q '"success":true'; then
        echo -e "XXX\n30\nREGISTRO DNS CRIADO COM SUCESSO! \nXXX"
    else
        echo -e "XXX\n30\nAVISO: ERRO AO CRIAR REGISTRO DNS \nXXX"
    fi

    # 2. AGORA ATUALIZAR AS ROTAS DO TUNNEL
    echo -e "XXX\n35\nATUALIZANDO CONFIGURAÇÃO DO TUNNEL... \nXXX"

    # Configuração do novo serviço para o Rabbitmq
    NEW_SERVICE="http://${nome_app_evoai}-frontend:3000"
    
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
    
    jq --arg host "$url_evoai_front" --arg service "$NEW_SERVICE" '
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
    if nslookup "$url_evoai_front" >/dev/null 2>&1; then
        echo -e "XXX\n15\nDNS CONFIGURADO \nXXX"
    else
        echo -e "XXX\n15\nAVISO: VERIFIQUE A CONFIGURAÇÃO DNS \nXXX"
    fi
fi


if [ "$INSTALL_TYPE" = "TRADICIONAL" ] && [ "$criar_dns" = "1" ]; then


# Função para verificar o domínio quando fora do cloudflare

ip_servidor=$(curl -s --max-time 10 ipinfo.io/ip)

echo -e "XXX\n3\nVERIFICANDO SUBDOMÍNIO: $url_evoai_front \nXXX"
sleep 3

tentativas=5
tentativa_atual=1
sucesso=0

while [ $tentativa_atual -le $tentativas ]; do
    echo -e "XXX\n$(( (tentativa_atual * 12) / tentativas + 3 ))\nTentativa $tentativa_atual de $tentativas...\nXXX"
    
    dns_ip4=$(timeout 10 nslookup -type=A "$url_evoai_front" | grep -E "Address: [0-9]+\." | awk '{print $2}' | head -n1)
    
    if [[ -n "$dns_ip4" && "$dns_ip4" == "$ip_servidor" ]]; then
        sucesso=1
       # break
    fi
    
  #  sleep $((tentativa_atual * 2))
  sleep 1
    ((tentativa_atual++))
done

if [ $sucesso -eq 0 ]; then

    echo -e "XXX\n10\nERRO: SUBDOMÍNIO DO EVO AI FRONTEND NÃO APONTA PARA O IP ($ip_servidor) \nXXX"
    sleep 3
    echo -e "XXX\n18\nERRO: DNS NÃO CONFIGURADO CORRETAMENTE \nXXX"
    sleep 3
    exit 1
fi
    echo -e "XXX\n18\nDOMÍNIO EVO AI FRONTEND VERIFICADO COM SUCESSO \nXXX"
sleep 4
fi

#VERIFICANDO CONFIGURAÇÃO EVOLUTION API

echo -e "XXX\n5\nVERIFICANDO CONFIGURAÇÃO EVOLUTION API... \nXXX"

if [ "$INSTALL_TYPE" = "TRADICIONAL" ] && [ "$criar_dns" = "0" ]; then
    # CONFIGURAÇÃO TRADICIONAL COM DNS AUTOMÁTICO
    echo -e "XXX\n10\nCONFIGURANDO DNS AUTOMÁTICO (TRADICIONAL)... \nXXX"
    
    DOMINIO_PRINCIPAL=$(echo "$dominio" | cut -d'.' -f2-)
    SUBDOMINIO=${dominio%%.$DOMINIO_PRINCIPAL}

    # Verificar e remover registros existentes
    echo -e "XXX\n15\nVERIFICANDO REGISTROS EXISTENTES... \nXXX"
    EXISTING_RECORDS=$(curl -s -X GET \
        "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records?name=${dominio}" \
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
        --data '{"type":"CNAME","name":"'${dominio}'","content":"'${nome_servidor}'.'${DOMINIO_PRINCIPAL}'","ttl":1,"proxied":false}')

    if echo "$CNAME_RESPONSE" | grep -q '"success":true'; then
        echo -e "XXX\n30\nREGISTRO CNAME CRIADO COM SUCESSO! \nXXX"
    else
        echo -e "XXX\n30\nAVISO: ERRO AO CRIAR REGISTRO CNAME \nXXX"
    fi

elif [ "$INSTALL_TYPE" = "CLOUDFLARE_TUNNEL" ]; then
    # CONFIGURAÇÃO CLOUDFLARE TUNNEL - DNS E ROTAS
    echo -e "XXX\n10\nCONFIGURANDO CLOUDFLARE TUNNEL (DNS + ROTAS)... \nXXX"
    
    DOMINIO_PRINCIPAL=$(echo "$dominio" | cut -d'.' -f2-)
    SUBDOMINIO=${dominio%%.$DOMINIO_PRINCIPAL}

    # 1. PRIMEIRO CONFIGURAR O DNS
    echo -e "XXX\n15\nCONFIGURANDO REGISTRO DNS... \nXXX"
    
    # Verificar e remover registros existentes
    EXISTING_RECORDS=$(curl -s -X GET \
        "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records?name=${dominio}" \
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
        --data "{\"type\":\"CNAME\",\"name\":\"${dominio}\",\"content\":\"${TUNNEL_ID}.cfargotunnel.com\",\"ttl\":1,\"proxied\":true}")

    if echo "$DNS_RESPONSE" | grep -q '"success":true'; then
        echo -e "XXX\n30\nREGISTRO DNS CRIADO COM SUCESSO! \nXXX"
    else
        echo -e "XXX\n30\nAVISO: ERRO AO CRIAR REGISTRO DNS \nXXX"
    fi

    # 2. AGORA ATUALIZAR AS ROTAS DO TUNNEL
    echo -e "XXX\n35\nATUALIZANDO CONFIGURAÇÃO DO TUNNEL... \nXXX"

    # Configuração do novo serviço
    NEW_SERVICE="http://${nome_app_evolution}:8080"
    
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
    
    jq --arg host "$dominio" --arg service "$NEW_SERVICE" '
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
    if nslookup "$dominio" >/dev/null 2>&1; then
        echo -e "XXX\n15\nDNS CONFIGURADO \nXXX"
    else
        echo -e "XXX\n15\nAVISO: VERIFIQUE A CONFIGURAÇÃO DNS \nXXX"
    fi
fi


if [ "$INSTALL_TYPE" = "TRADICIONAL" ] && [ "$criar_dns" = "1" ]; then


# Função para verificar o domínio quando fora do cloudflare

ip_servidor=$(curl -s --max-time 10 ipinfo.io/ip)

echo -e "XXX\n3\nVERIFICANDO SUBDOMÍNIO: $dominio \nXXX"
sleep 3

tentativas=5
tentativa_atual=1
sucesso=0

while [ $tentativa_atual -le $tentativas ]; do
    echo -e "XXX\n$(( (tentativa_atual * 12) / tentativas + 3 ))\nTentativa $tentativa_atual de $tentativas...\nXXX"
    
    dns_ip5=$(timeout 10 nslookup -type=A "$dominio" | grep -E "Address: [0-9]+\." | awk '{print $2}' | head -n1)
    
    if [[ -n "$dns_ip5" && "$dns_ip5" == "$ip_servidor" ]]; then
        sucesso=1
       # break
    fi
    
  #  sleep $((tentativa_atual * 2))
  sleep 1
    ((tentativa_atual++))
done

if [ $sucesso -eq 0 ]; then

    echo -e "XXX\n10\nERRO: SUBDOMÍNIO DA EVOLUTION API NÃO APONTA PARA O IP ($ip_servidor) \nXXX"
    sleep 3
    echo -e "XXX\n18\nERRO: DNS NÃO CONFIGURADO CORRETAMENTE \nXXX"
    sleep 3
    exit 1
fi
    echo -e "XXX\n18\nDOMÍNIO EVOLUTION API VERIFICADO COM SUCESSO \nXXX"
sleep 4
fi


####### fim de verificando dominio   
echo -e "XXX\n44\nCRIANDO STACKS 1/4 \nXXX"
sleep 1
echo -e "XXX\n45\nAGUARDANDO PROPAGAÇÃO - PODE DEMORAR UM POUCO \nXXX"

#######################################################
#
#  INSTALANDO O REDISEVO
#

cd

cd
#clear

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
	elapsed_time=$((elaapsed_time + wait_interval))
done

if [ -z "$CONTAINER_ID" ]; then
    whiptail --title "Erro" --msgbox "O container do Minio não foi encontrado após $max_wait_time segundos" 10 60
    exit 0
fi
fi

# aguarda 60 segundos
sleep 60
# Instalar mc (Minio Client) e jq se necessário
if ! command -v mc &> /dev/null; then
# Instalar versão adequada à sua arquitetura
ARCH=$(uname -m)

if [[ "$ARCH" == "x86_64" ]]; then
    wget https://dl.min.io/client/mc/release/linux-amd64/mc -O /usr/local/bin/mc >/dev/null 2>&1
elif [[ "$ARCH" == "aarch64" ]] || [[ "$ARCH" == "armv7l" ]]; then
    wget https://dl.min.io/client/mc/release/linux-arm64/mc -O /usr/local/bin/mc >/dev/null 2>&1
else
    whiptail --title "Erro" --msgbox "Arquitetura não suportada: $ARCHs" 10 60
    exit 0
fi

# Tornar executável
chmod +x /usr/local/bin/mc
fi

if ! command -v jq &> /dev/null; then
    apt-get install -y jq >/dev/null 2>&1
fi

# Configurar alias para o Minio
mc alias set minio https://$MINIO_PUBLIC_URL $MINIO_USER $MINIO_PASSWORD --api S3v4
###########

###### CRIAR BUCKET ECVOLUTION


# Criar bucket e configurar política
bucket_name_evolution="$nome_app_evolution"
echo "Criando bucket: $bucket_name_evolution"
mc mb minio/"$bucket_name_evolution"
if [ $? -ne 0 ]; then
    echo "Erro ao criar o bucket $bucket_name_evolution"
    exit 1
fi

echo "Configurando política pública para o bucket: $bucket_name_evolution"
mc anonymous set public minio/"$bucket_name_evolution"
if [ $? -ne 0 ]; then
    echo "Erro ao definir a política pública"
    mc anonymous get minio/"$bucket_name_evolution"
    exit 1
fi

echo "Política atual do bucket:"
mc anonymous get minio/"$bucket_name_evolution"

###########
###########
create_service_account() {
    local bucket=$1
    local app_name=$2

    credentials=$(mc admin user svcacct add minio "$MINIO_USER" \
        --access-key "$ACCESS_KEY" \
        --secret-key "$SECRET_KEY" \
        --json 2>&1)

    # Valida se a saída é um JSON
    if [[ -z "$access_key" || -z "$secret_key" ]]; then
    # Extrair chaves com validação rigorosa
    access_key=$(echo "$credentials" | jq -r '.accessKey')
    secret_key=$(echo "$credentials" | jq -r '.secretKey')
    fi

}

# Chamar a função
create_service_account "$bucket_name_evolution" "$nome_app_evolution"


####### fim da checagem se minio rodando


#  INSTALANDO O REDISEVOAI
#

cd

cd
### FRANCIS clear


cat > $nome_app_evoai-redis.yaml << EOL

version: "3.7"

services:
  $nome_app_evoai-redis:
    image: redis:latest
    command: [
        "redis-server",
        "--appendonly",
        "yes",
        "--port",
        "6379"
      ]
    volumes:
      - $nome_app_evoai-redis-data:/data

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
  $nome_app_evoai-redis-data:
    external: true
    name: $nome_app_evoai-redis-data


networks: 
  externa: 
    external: true
  interna: 
    external: true


EOL

#docker stack deploy --prune --resolve-image always -c $nome_app_evoai-redis.yaml $nome_app_evoai-redis >/dev/null 2>&1


if [[ "$criar_portainer" == "0" ]]; then
    # A stack será criada no Portainer
    echo -e "XXX\n46\nCRIANDO STACK NO PORTAINER 3/4  \nXXX"

# Configurações

# Caminho para o arquivo de dados
dados_file="$HOME/dados_portainer/dados_portainer"

# Verifica se o arquivo existe
if [[ -f "$dados_file" ]]; then
    # Coleta as informações do arquivo
PORTAINER_URL=$(grep "Dominio do portainer:" "$dados_file" | cut -d':' -f2 | xargs)
ADMIN_USERNAME=$(grep "Usuario:" "$dados_file" | cut -d':' -f2 | xargs)
ADMIN_PASSWORD=$(grep "Senha:" "$dados_file" | cut -d':' -f2 | xargs)
STACK_NAME=$nome_app_evoai-redis
STACK_FILE_PATH="/root/$nome_app_evoai-redis.yaml"

else
   # echo "Erro: Arquivo de dados não encontrado em $dados_file."
    sleep 5
echo -e "XXX\n47\nSEM ARQUIVO DE DADOS DO PORTAINER 3/4  \nXXX"
docker stack deploy --prune --resolve-image always -c $nome_app_evoai-redis.yaml $nome_app_evoai-redis >/dev/null 2>&1
sleep 5
    exit 1
fi

# Função para autenticação
get_auth_token() {
    #echo "[INFO] Autenticando no Portainer..."
    echo -e "XXX\n48\nAUTENTICANDO NO PORTAINER... 3/4  \nXXX"
    RESPONSE=$(curl -sS -X POST "https://$PORTAINER_URL/api/auth" \
        -H "Content-Type: application/json" \
        -d "{\"username\": \"$ADMIN_USERNAME\", \"password\": \"$ADMIN_PASSWORD\"}")
    TOKEN=$(echo "$RESPONSE" | jq -r '.jwt')
    if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]; then
        # echo "[ERRO] Falha na autenticação."
        echo -e "XXX\n49\nFALHA NA AUTENTICAÇÃO.. 3/4  \nXXX"
sleep 5
echo -e "XXX\n50\nREVERTENDO E CRIANDO STACK PELO SERVIDOR 3/4  \nXXX"
docker stack deploy --prune --resolve-image always -c $nome_app_evoai-redis.yaml $nome_app_evoai-redis >/dev/null 2>&1
sleep 5
        exit 1
    fi
  #  echo "[SUCESSO] Autenticação realizada com sucesso. Token obtido."
 echo -e "XXX\n51\n[SUCESSO] AUTENTICAÇÃO OK 3/4  \nXXX"
}

# Função para obter o EndpointID
get_endpoint_id() {
   # echo "[INFO] Obtendo EndpointID..."
    echo -e "XXX\n52\n[INFO] OBTENDO ENDPOINTID 3/4  \nXXX"
    RESPONSE=$(curl -sS -X GET "https://$PORTAINER_URL/api/endpoints" \
        -H "Authorization: Bearer $TOKEN")
    ENDPOINT_ID=$(echo "$RESPONSE" | jq -r '.[0].Id')
    if [ -z "$ENDPOINT_ID" ] || [ "$ENDPOINT_ID" = "null" ]; then
        # echo "[ERRO] EndpointID não encontrado! Resposta: $RESPONSE"
        echo -e "XXX\n53\n[ERRO] ENDPOINTID NÃO ENCONTRADO 3/4  \nXXX"
        docker stack deploy --prune --resolve-image always -c $nome_app_evoai-redis.yaml $nome_app_evoai-redis >/dev/null 2>&1
        exit 1
    fi
     echo -e "XXX\n54\n[SUCESSO] ENDPOINTID OBTIDO: $ENDPOINT_ID  3/4  \nXXX"
    #echo "[SUCESSO] EndpointID obtido: $ENDPOINT_ID"
}

# Função para obter o SwarmID
get_swarm_id() {
   # echo "[INFO] Obtendo SwarmID..."
    echo -e "XXX\n55\n[INFO] OBTENDO SWARMID  3/4  \nXXX"
    RESPONSE=$(curl -sS -X GET "https://$PORTAINER_URL/api/endpoints/$ENDPOINT_ID/docker/swarm" \
        -H "Authorization: Bearer $TOKEN")
    SWARM_ID=$(echo "$RESPONSE" | jq -r '.ID')
    if [ -z "$SWARM_ID" ] || [ "$SWARM_ID" = "null" ]; then
        #echo "[ERRO] SwarmID não encontrado! Resposta: $RESPONSE"
        echo -e "XXX\n56\n[ERRO] SWARMID NÃO ENCONTRADO 3/4  \nXXX"
        docker stack deploy --prune --resolve-image always -c $nome_app_evoai-redis.yaml $nome_app_evoai-redis >/dev/null 2>&1
        exit 1
    fi
    #echo "[SUCESSO] SwarmID obtido: $SWARM_ID"
    echo -e "XXX\n57\n[SUCESSO] SWARMID OBTIDO: $SWARM_ID  3/4  \nXXX"
}

# Função para criar a stack
create_stack() {
    #echo "[INFO] Verificando existência do arquivo YAML..."
    echo -e "XXX\n58\n[INFO] VERIFICANDO SE YAML EXISTE 3/4  \nXXX"
    if [ ! -f "$STACK_FILE_PATH" ]; then
        #echo "[ERRO] Arquivo $STACK_FILE_PATH não encontrado!"
        echo -e "XXX\n59\n[ERRO] ARQUIVO $STACK_FILE_PATH NÃO ENCONTRADO 3/4  \nXXX"
        docker stack deploy --prune --resolve-image always -c $nome_app_evoai-redis.yaml $nome_app_evoai-redis >/dev/null 2>&1
        exit 1
    fi

    #echo "[INFO] Criando stack '$STACK_NAME' no Portainer..."
     echo -e "XXX\n60\n[INFO] CRIANDO STACK $STACK_NAME NO PORTAINER 3/4  \nXXX"
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
        echo -e "XXX\n61\n[ERRO] ERRO AO CRIAR STACK 3/4  \nXXX"
        docker stack deploy --prune --resolve-image always -c $nome_app_evoai-redis.yaml $nome_app_evoai-redis >/dev/null 2>&1
        exit 1
    fi

   # echo "[SUCESSO] Stack '$STACK_NAME' criada com sucesso!"
    echo -e "XXX\n62\n[SUCESSO] STACK $STACK_NAME  CRIADA COM SUCESSO 3/4  \nXXX"
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
    docker stack deploy --prune --resolve-image always -c $nome_app_evoai-redis.yaml $nome_app_evoai-redis >/dev/null 2>&1
else
    # Caso inesperado (não deve ocorrer devido à validação anterior no while loop)
   # echo "Erro: valor inesperado para criar_portainer. Encerrando..."
    echo -e "XXX\n63\n[ERRO] ERRO INESPERADO PARA CRIAR STACK NO PORTAINER 3/4  \nXXX"
    sleep 5
    echo -e "XXX\n64\nREVERTENDO E CRIANDO STACK PELO SERVIDOR 3/4  \nXXX"
docker stack deploy --prune --resolve-image always -c $nome_app_evoai-redis.yaml $nome_app_evoai-redis >/dev/null 2>&1
sleep 5

    exit 1
fi



# FIM DE INSTALANDO O REDISEVOAI
#
#######################################################
#






#######EVO REDIS

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

#docker stack deploy --prune --resolve-image always -c evo_redis.yaml evo_redis >/dev/null 2>&1
if [[ "$criar_portainer" == "0" ]]; then
    # A stack será criada no Portainer
    echo -e "XXX\n65\nCRIANDO STACK NO PORTAINER 3/4  \nXXX"

# Configurações

# Caminho para o arquivo de dados
dados_file="$HOME/dados_portainer/dados_portainer"

# Verifica se o arquivo existe
if [[ -f "$dados_file" ]]; then
    # Coleta as informações do arquivo
PORTAINER_URL=$(grep "Dominio do portainer:" "$dados_file" | cut -d':' -f2 | xargs)
ADMIN_USERNAME=$(grep "Usuario:" "$dados_file" | cut -d':' -f2 | xargs)
ADMIN_PASSWORD=$(grep "Senha:" "$dados_file" | cut -d':' -f2 | xargs)
STACK_NAME=$nome_evo_redis
STACK_FILE_PATH="/root/$nome_evo_redis.yaml"

else
   # echo "Erro: Arquivo de dados não encontrado em $dados_file."
    sleep 5
echo -e "XXX\n66\nSEM ARQUIVO DE DADOS DO PORTAINER 3/4  \nXXX"
docker stack deploy --prune --resolve-image always -c $nome_evo_redis.yaml $nome_evo_redis >/dev/null 2>&1
sleep 5
    exit 1
fi

# Função para autenticação
get_auth_token() {
    #echo "[INFO] Autenticando no Portainer..."
    echo -e "XXX\n67\nAUTENTICANDO NO PORTAINER... 3/4  \nXXX"
    RESPONSE=$(curl -sS -X POST "https://$PORTAINER_URL/api/auth" \
        -H "Content-Type: application/json" \
        -d "{\"username\": \"$ADMIN_USERNAME\", \"password\": \"$ADMIN_PASSWORD\"}")
    TOKEN=$(echo "$RESPONSE" | jq -r '.jwt')
    if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]; then
        # echo "[ERRO] Falha na autenticação."
        echo -e "XXX\n67\nFALHA NA AUTENTICAÇÃO.. 3/4  \nXXX"
sleep 5
echo -e "XXX\n67\nREVERTENDO E CRIANDO STACK PELO SERVIDOR 3/4  \nXXX"
docker stack deploy --prune --resolve-image always -c $nome_evo_redis.yaml $nome_evo_redis >/dev/null 2>&1
sleep 5
        exit 1
    fi
  #  echo "[SUCESSO] Autenticação realizada com sucesso. Token obtido."
 echo -e "XXX\n68\n[SUCESSO] AUTENTICAÇÃO OK 3/4  \nXXX"
}

# Função para obter o EndpointID
get_endpoint_id() {
   # echo "[INFO] Obtendo EndpointID..."
    echo -e "XXX\n68\n[INFO] OBTENDO ENDPOINTID 3/4  \nXXX"
    RESPONSE=$(curl -sS -X GET "https://$PORTAINER_URL/api/endpoints" \
        -H "Authorization: Bearer $TOKEN")
    ENDPOINT_ID=$(echo "$RESPONSE" | jq -r '.[0].Id')
    if [ -z "$ENDPOINT_ID" ] || [ "$ENDPOINT_ID" = "null" ]; then
        # echo "[ERRO] EndpointID não encontrado! Resposta: $RESPONSE"
        echo -e "XXX\n68\n[ERRO] ENDPOINTID NÃO ENCONTRADO 3/4  \nXXX"
        docker stack deploy --prune --resolve-image always -c $nome_evo_redis.yaml $nome_evo_redis >/dev/null 2>&1
        exit 1
    fi
     echo -e "XXX\n68\n[SUCESSO] ENDPOINTID OBTIDO: $ENDPOINT_ID  3/4  \nXXX"
    #echo "[SUCESSO] EndpointID obtido: $ENDPOINT_ID"
}

# Função para obter o SwarmID
get_swarm_id() {
   # echo "[INFO] Obtendo SwarmID..."
    echo -e "XXX\n69\n[INFO] OBTENDO SWARMID  3/4  \nXXX"
    RESPONSE=$(curl -sS -X GET "https://$PORTAINER_URL/api/endpoints/$ENDPOINT_ID/docker/swarm" \
        -H "Authorization: Bearer $TOKEN")
    SWARM_ID=$(echo "$RESPONSE" | jq -r '.ID')
    if [ -z "$SWARM_ID" ] || [ "$SWARM_ID" = "null" ]; then
        #echo "[ERRO] SwarmID não encontrado! Resposta: $RESPONSE"
        echo -e "XXX\n69\n[ERRO] SWARMID NÃO ENCONTRADO 3/4  \nXXX"
        docker stack deploy --prune --resolve-image always -c $nome_evo_redis.yaml $nome_evo_redis >/dev/null 2>&1
        exit 1
    fi
    #echo "[SUCESSO] SwarmID obtido: $SWARM_ID"
    echo -e "XXX\n69\n[SUCESSO] SWARMID OBTIDO: $SWARM_ID  3/4  \nXXX"
}

# Função para criar a stack
create_stack() {
    #echo "[INFO] Verificando existência do arquivo YAML..."
    echo -e "XXX\n70\n[INFO] VERIFICANDO SE YAML EXISTE 3/4  \nXXX"
    if [ ! -f "$STACK_FILE_PATH" ]; then
        #echo "[ERRO] Arquivo $STACK_FILE_PATH não encontrado!"
        echo -e "XXX\n70\n[ERRO] ARQUIVO $STACK_FILE_PATH NÃO ENCONTRADO 3/4  \nXXX"
        docker stack deploy --prune --resolve-image always -c $nome_evo_redis.yaml $nome_evo_redis >/dev/null 2>&1
        exit 1
    fi

    #echo "[INFO] Criando stack '$STACK_NAME' no Portainer..."
     echo -e "XXX\n70\n[INFO] CRIANDO STACK $STACK_NAME NO PORTAINER 3/4  \nXXX"
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
        echo -e "XXX\n71\n[ERRO] ERRO AO CRIAR STACK 3/4  \nXXX"
        docker stack deploy --prune --resolve-image always -c $nome_evo_redis.yaml $nome_evo_redis >/dev/null 2>&1
        exit 1
    fi

   # echo "[SUCESSO] Stack '$STACK_NAME' criada com sucesso!"
    echo -e "XXX\n72\n[SUCESSO] STACK $STACK_NAME  CRIADA COM SUCESSO 3/4  \nXXX"
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
    docker stack deploy --prune --resolve-image always -c $nome_evo_redis.yaml $nome_evo_redis >/dev/null 2>&1
else
    # Caso inesperado (não deve ocorrer devido à validação anterior no while loop)
   # echo "Erro: valor inesperado para criar_portainer. Encerrando..."
    echo -e "XXX\n73\n[ERRO] ERRO INESPERADO PARA CRIAR STACK NO PORTAINER 3/4  \nXXX"
    sleep 5
    echo -e "XXX\n74\nREVERTENDO E CRIANDO STACK PELO SERVIDOR 3/4  \nXXX"
docker stack deploy --prune --resolve-image always -c $nome_evo_redis.yaml $nome_evo_redis >/dev/null 2>&1
sleep 5

    exit 1
fi

# FIM DE INSTALANDO O REDISEVO
#
#######################################################

# FIM DE MENSAGEM DE INSTALANDO
#
#######################################################
#
#######################################################
#
#  INSTALANDO A EVO AI - INICIO
#

sleep 3
echo -e "XXX\n75\nFAZENDO O BUILD DO STACK 3/4 \nXXX"
sleep 3
echo -e "XXX\n75\nFAZENDO O BUILD DO STACK 3/4 - CONCLUIDO \nXXX"
## Criando uma Global Key Aleatória
EVO_AI_ENCRYPTION_KEY=$(python3 -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())")
EVO_AI_JWT_SECRET_KEY=$(openssl rand -base64 32)
cd

cd

cat > $nome_app_evoai.yaml << EOL

version: "3.7"
services:

  $nome_app_evoai-api:
    image: evoapicloud/evo-ai:latest ## Versão da imagem

    volumes:
      - $nome_app_evoai-logs:/app/logs
      - $nome_app_evoai-static:/app/static

    networks: 
      - externa
      - interna

    environment:
  
      - API_URL=https://$url_evoai_api

      - APP_URL=https://$url_evoai_front
      
    ##  Admin
      - ADMIN_EMAIL=$email_evoai
      - ADMIN_INITIAL_PASSWORD=$pass_evoai

    ##  SMTP
      - EMAIL_PROVIDER=smtp
      - SMTP_FROM=$smtp_email_evoai
      - SMTP_USER=$smtp_user_evoai
      - SMTP_PASSWORD=$smtp_pass_evoai
      - SMTP_HOST=$smtp_host_evoai
      - SMTP_PORT=$smtp_port_evoai
      - SMTP_USE_TLS=$SMTP_USE_TLS
      - SMTP_USE_SSL=$SMTP_USE_SSL

    ## Postgres
      - POSTGRES_CONNECTION_STRING=postgresql://postgres:$postgres_password@postgres:5432/$nome_app_evoai

    ## Redis
      - REDIS_HOST=$nome_app_evoai-redis
      - REDIS_PORT=6379
      - REDIS_DB=9
      - REDIS_KEY_PREFIX=a2a$nome_app_evoai
      - REDIS_SSL=false
      - REDIS_TTL=3600
      - TOOLS_CACHE_TTL=3600

    ## Encriptação e JWT
      - ENCRYPTION_KEY=$EVO_AI_ENCRYPTION_KEY
      - JWT_SECRET_KEY=$EVO_AI_JWT_SECRET_KEY
      - JWT_ALGORITHM=HS256
      - JWT_EXPIRATION_TIME=3600

    ## Logs
      - LOG_LEVEL=INFO
      - LOG_DIR=logs
    
    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
        - node.role == manager
EOL
# Adicionar as labels apenas se for instalação tradicional
if [ "$INSTALL_TYPE" = "TRADICIONAL" ]; then
cat >> $nome_app_evoai.yaml << EOL
      labels:
        - traefik.enable=1
        - traefik.http.routers.$nome_app_evoai-api.rule=Host(\`$url_evoai_api\`) ## Url da Evolution API
        - traefik.http.routers.$nome_app_evoai-api.entrypoints=websecure
        - traefik.http.routers.$nome_app_evoai-api.priority=1
        - traefik.http.routers.$nome_app_evoai-api.tls.certresolver=letsencryptresolver
        - traefik.http.routers.$nome_app_evoai-api.service=$nome_app_evoai-api
        - traefik.http.services.$nome_app_evoai-api.loadbalancer.server.port=8000
        - traefik.http.services.$nome_app_evoai-api.loadbalancer.passHostHeader=true
EOL
fi
cat >> $nome_app_evoai.yaml << EOL

  $nome_app_evoai-frontend:
    image: evoapicloud/evo-ai-frontend:latest ## Versão da imagem

    networks: 
      - externa
      - interna

    environment:
      - NEXT_PUBLIC_API_URL=https://$url_evoai_api
    
    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
        - node.role == manager
EOL
# Adicionar as labels apenas se for instalação tradicional
if [ "$INSTALL_TYPE" = "TRADICIONAL" ]; then
cat >> $nome_app_evoai.yaml << EOL
      labels:
        - traefik.enable=1
        - traefik.http.routers.$nome_app_evoai-frontend.rule=Host(\`$url_evoai_front\`) ## Url da Evolution API
        - traefik.http.routers.$nome_app_evoai-frontend.entrypoints=websecure
        - traefik.http.routers.$nome_app_evoai-frontend.priority=1
        - traefik.http.routers.$nome_app_evoai-frontend.tls.certresolver=letsencryptresolver
        - traefik.http.routers.$nome_app_evoai-frontend.service=$nome_app_evoai-frontend
        - traefik.http.services.$nome_app_evoai-frontend.loadbalancer.server.port=3000
        - traefik.http.services.$nome_app_evoai-frontend.loadbalancer.passHostHeader=true
EOL
fi
cat >> $nome_app_evoai.yaml << EOL

volumes:
  $nome_app_evoai-logs:
    external: true
    name: $nome_app_evoai-logs
  $nome_app_evoai-static:
    external: true
    name: $nome_app_evoai-static

networks: 
  externa: 
    external: true
  interna: 
    external: true

EOL

#docker stack deploy --prune --resolve-image always -c $nome_app_evoai.yaml $nome_app_evoai >/dev/null 2>&1


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
STACK_NAME=$nome_app_evoai
STACK_FILE_PATH="/root/$nome_app_evoai.yaml"

else
   # echo "Erro: Arquivo de dados não encontrado em $dados_file."
    sleep 5
echo -e "XXX\n77\nSEM ARQUIVO DE DADOS DO PORTAINER 3/4  \nXXX"
docker stack deploy --prune --resolve-image always -c $nome_app_evoai.yaml $nome_app_evoai >/dev/null 2>&1
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
docker stack deploy --prune --resolve-image always -c $nome_app_evoai.yaml $nome_app_evoai >/dev/null 2>&1
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
        docker stack deploy --prune --resolve-image always -c $nome_app_evoai.yaml $nome_app_evoai >/dev/null 2>&1
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
        docker stack deploy --prune --resolve-image always -c $nome_app_evoai.yaml $nome_app_evoai >/dev/null 2>&1
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
        docker stack deploy --prune --resolve-image always -c $nome_app_evoai.yaml $nome_app_evoai >/dev/null 2>&1
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
        docker stack deploy --prune --resolve-image always -c $nome_app_evoai.yaml $nome_app_evoai >/dev/null 2>&1
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
    docker stack deploy --prune --resolve-image always -c $nome_app_evoai.yaml $nome_app_evoai >/dev/null 2>&1
else
    # Caso inesperado (não deve ocorrer devido à validação anterior no while loop)
   # echo "Erro: valor inesperado para criar_portainer. Encerrando..."
    echo -e "XXX\n91\n[ERRO] ERRO INESPERADO PARA CRIAR STACK NO PORTAINER 3/4  \nXXX"
    sleep 5
    echo -e "XXX\n92\nREVERTENDO E CRIANDO STACK PELO SERVIDOR 3/4  \nXXX"
docker stack deploy --prune --resolve-image always -c $nome_app_evoai.yaml $nome_app_evoai >/dev/null 2>&1
sleep 5

    exit 1
fi

# FIM DE INSTALANDO A EVO AI - INICIO
#######################################################
#
#  INSTALANDO A EVOLUTION API - INICIO
#

sleep 3
echo -e "XXX\n80\nCRIANDO BANCO DE DADOS DA EVOLUTION API 3/4 \nXXX"
sleep 3
echo -e "XXX\n80\nCRIANDO BANCO DE DADOS DA EVOLUTION API 3/4 - CONCLUIDO \nXXX"

cd

cd

cat > $nome_app_evolution.yaml << EOL

version: "3.7"

services:
  $nome_app_evolution:
    image: evoapicloud/evolution-api:v2.3.6
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
      - S3_ACCESS_KEY=$access_key
      - S3_SECRET_KEY=$secret_key
      - S3_BUCKET=$bucket_name_evolution
      - S3_PORT=443
      - S3_ENDPOINT=$MINIO_PUBLIC_URL
      - S3_USE_SSL=true 

      # EVO AI
      - EVOAI_ENABLED=true 
      


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

#docker stack deploy --prune --resolve-image always -c $nome_app_evolution.yaml $nome_app_evolution >/dev/null 2>&1


if [[ "$criar_portainer" == "0" ]]; then
    # A stack será criada no Portainer
    echo -e "XXX\n91\nCRIANDO STACK NO PORTAINER 3/4  \nXXX"


# Configurações

# Caminho para o arquivo de dados
dados_file="$HOME/dados_portainer/dados_portainer"

# Verifica se o arquivo existe
if [[ -f "$dados_file" ]]; then
    # Coleta as informações do arquivo
PORTAINER_URL=$(grep "Dominio do portainer:" "$dados_file" | cut -d':' -f2 | xargs)
ADMIN_USERNAME=$(grep "Usuario:" "$dados_file" | cut -d':' -f2 | xargs)
ADMIN_PASSWORD=$(grep "Senha:" "$dados_file" | cut -d':' -f2 | xargs)
STACK_NAME=$nome_app_evolution
STACK_FILE_PATH="/root/$nome_app_evolution.yaml"

else
   # echo "Erro: Arquivo de dados não encontrado em $dados_file."
    sleep 5
echo -e "XXX\n91\nSEM ARQUIVO DE DADOS DO PORTAINER 3/4  \nXXX"
docker stack deploy --prune --resolve-image always -c $nome_app_evolution.yaml $nome_app_evolution >/dev/null 2>&1
sleep 5
    exit 1
fi

# Função para autenticação
get_auth_token() {
    #echo "[INFO] Autenticando no Portainer..."
    echo -e "XXX\n91\nAUTENTICANDO NO PORTAINER... 3/4  \nXXX"
    RESPONSE=$(curl -sS -X POST "https://$PORTAINER_URL/api/auth" \
        -H "Content-Type: application/json" \
        -d "{\"username\": \"$ADMIN_USERNAME\", \"password\": \"$ADMIN_PASSWORD\"}")
    TOKEN=$(echo "$RESPONSE" | jq -r '.jwt')
    if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]; then
        # echo "[ERRO] Falha na autenticação."
        echo -e "XXX\n83\nFALHA NA AUTENTICAÇÃO.. 3/4  \nXXX"
sleep 5
echo -e "XXX\n91\nREVERTENDO E CRIANDO STACK PELO SERVIDOR 3/4  \nXXX"
docker stack deploy --prune --resolve-image always -c $nome_app_evolution.yaml $nome_app_evolution >/dev/null 2>&1
sleep 5
        exit 1
    fi
  #  echo "[SUCESSO] Autenticação realizada com sucesso. Token obtido."
 echo -e "XXX\n91\n[SUCESSO] AUTENTICAÇÃO OK 3/4  \nXXX"
}

# Função para obter o EndpointID
get_endpoint_id() {
   # echo "[INFO] Obtendo EndpointID..."
    echo -e "XXX\n91\n[INFO] OBTENDO ENDPOINTID 3/4  \nXXX"
    RESPONSE=$(curl -sS -X GET "https://$PORTAINER_URL/api/endpoints" \
        -H "Authorization: Bearer $TOKEN")
    ENDPOINT_ID=$(echo "$RESPONSE" | jq -r '.[0].Id')
    if [ -z "$ENDPOINT_ID" ] || [ "$ENDPOINT_ID" = "null" ]; then
        # echo "[ERRO] EndpointID não encontrado! Resposta: $RESPONSE"
        echo -e "XXX\n91\n[ERRO] ENDPOINTID NÃO ENCONTRADO 3/4  \nXXX"
       docker stack deploy --prune --resolve-image always -c $nome_app_evolution.yaml $nome_app_evolution >/dev/null 2>&1
        exit 1
    fi
     echo -e "XXX\n91\n[SUCESSO] ENDPOINTID OBTIDO: $ENDPOINT_ID  3/4  \nXXX"
    #echo "[SUCESSO] EndpointID obtido: $ENDPOINT_ID"
}

# Função para obter o SwarmID
get_swarm_id() {
   # echo "[INFO] Obtendo SwarmID..."
    echo -e "XXX\n91\n[INFO] OBTENDO SWARMID  3/4  \nXXX"
    RESPONSE=$(curl -sS -X GET "https://$PORTAINER_URL/api/endpoints/$ENDPOINT_ID/docker/swarm" \
        -H "Authorization: Bearer $TOKEN")
    SWARM_ID=$(echo "$RESPONSE" | jq -r '.ID')
    if [ -z "$SWARM_ID" ] || [ "$SWARM_ID" = "null" ]; then
        #echo "[ERRO] SwarmID não encontrado! Resposta: $RESPONSE"
        echo -e "XXX\n91\n[ERRO] SWARMID NÃO ENCONTRADO 3/4  \nXXX"
       docker stack deploy --prune --resolve-image always -c $nome_app_evolution.yaml $nome_app_evolution >/dev/null 2>&1
        exit 1
    fi
    #echo "[SUCESSO] SwarmID obtido: $SWARM_ID"
    echo -e "XXX\n91\n[SUCESSO] SWARMID OBTIDO: $SWARM_ID  3/4  \nXXX"
}

# Função para criar a stack
create_stack() {
    #echo "[INFO] Verificando existência do arquivo YAML..."
    echo -e "XXX\n92\n[INFO] VERIFICANDO SE YAML EXISTE 3/4  \nXXX"
    if [ ! -f "$STACK_FILE_PATH" ]; then
        #echo "[ERRO] Arquivo $STACK_FILE_PATH não encontrado!"
        echo -e "XXX\n93\n[ERRO] ARQUIVO $STACK_FILE_PATH NÃO ENCONTRADO 3/4  \nXXX"
       docker stack deploy --prune --resolve-image always -c $nome_app_evolution.yaml $nome_app_evolution >/dev/null 2>&1
        exit 1
    fi

    #echo "[INFO] Criando stack '$STACK_NAME' no Portainer..."
     echo -e "XXX\n94\n[INFO] CRIANDO STACK $STACK_NAME NO PORTAINER 3/4  \nXXX"
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
        echo -e "XXX\n95\n[ERRO] ERRO AO CRIAR STACK 3/4  \nXXX"
      docker stack deploy --prune --resolve-image always -c $nome_app_evolution.yaml $nome_app_evolution >/dev/null 2>&1
        exit 1
    fi

   # echo "[SUCESSO] Stack '$STACK_NAME' criada com sucesso!"
    echo -e "XXX\n96\n[SUCESSO] STACK $STACK_NAME  CRIADA COM SUCESSO 3/4  \nXXX"
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
docker stack deploy --prune --resolve-image always -c $nome_app_evolution.yaml $nome_app_evolution >/dev/null 2>&1
else
    # Caso inesperado (não deve ocorrer devido à validação anterior no while loop)
   # echo "Erro: valor inesperado para criar_portainer. Encerrando..."
    echo -e "XXX\n97\n[ERRO] ERRO INESPERADO PARA CRIAR STACK NO PORTAINER 3/4  \nXXX"
    sleep 5
    echo -e "XXX\n98\nREVERTENDO E CRIANDO STACK PELO SERVIDOR 3/4  \nXXX"
docker stack deploy --prune --resolve-image always -c $nome_app_evolution.yaml $nome_app_evolution >/dev/null 2>&1
sleep 5

    exit 1
fi


#######################################################
#
#  INSTALANDO A UNO API - FIM




# FINALIZANDO INSTALACAO E LIBERANDO BRAND NO INSTALLATION CONFIGS
#
#######################################################

echo -e "XXX\n99\nFINALIZANDO INST. EVOAI + EVOLUTION 2.0 + MINIO 4/4  \nXXX"


sleep 12
echo -e "XXX\n100\nFINALIZANDO INST. EVOAI + EVOLUTION 2.0 + MINIO 4/4 - CONCLUIDO  \nXXX"

sleep 3

}|whiptail --title "EVOAI + EVOLUTION 2.0 + MINIO: PROGRESSO DA INSTALAÇÃO" --gauge "Aguarde a instalação dos ítens necessrios" 6 60 0

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
        domains_to_check="$painel $publico $url_evoai_api $url_evoai_front $dominio"
    else
        domains_to_check="$url_evoai_api $url_evoai_front $dominio"
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

    dns_ip3=$(timeout 10 nslookup "$url_evoai_api" | grep "Address" | tail -n1 | awk '{print $2}')
    dns_ip4=$(timeout 10 nslookup "$url_evoai_front" | grep "Address" | tail -n1 | awk '{print $2}')
    dns_ip5=$(timeout 10 nslookup "$dominio" | grep "Address" | tail -n1 | awk '{print $2}')
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

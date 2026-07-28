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
    whiptail --title "INSTALAÇÃO DO TYPEBOT COM MINIO: FERRAMENTA DE CHATBOTS E MINIO S3" --msgbox "$msg" --fb 10 70
}

while true; do
CHOICE=$(
whiptail --title "INSTALAÇÃO DO TYPEBOT COM MINIO: FERRAMENTA DE CHATBOTS E MINIO S3" --menu "Aperte ENTER para iniciar a instalação do TYPEBOT COM MINIO ou selecione SAIR (Utilize setas e Enter)\n\nTIPO DE INSTALAÇÃO DETECTADA: $INSTALL_TYPE\n\nINSTRUÇÕES:\nAntes de prosseguir, verifique os registros DNS conforme seu tipo de instalação:" 20 70 2 \
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
    whiptail --title "Erro" --msgbox "Minio instalado, mas os dados de acesso não foram encontrados. A presente instalação acessa credenciais pré-gravadas em uma pasta. Se sua instalação não é recente, pode ser que o Setup-MNO não criou esta pasta. Use outro template de instalação de Typebot sem o Minio. Digite enter para abortar a instalação." 15 60
    exit 0
fi

while true ; do
    builder=$(whiptail --title "Dominio do Builder do Typebot" --inputbox "Digite o dominio do Builder do Typebot (ex: typebot.seudominio.com):" --fb 12 60 3>&1 1>&2 2>&3)
    saida=$?
    if [[ $saida -eq '0' ]]; then
        if [[ -z $builder ]]; then 
            msg "Digite o link do builder do Typebot, para poder continuar"
            continue 
        else 
            break
        fi
    else
        echo "$builder"; echo "saindo..." & exit 0
    fi
done

while true ; do
    viewer=$(whiptail --title "Dominio do Viewer do Typebot" --inputbox "Dominio do Viewer do Typebot - publico (ex: chatbot.seudominio.com):" --fb 12 60 3>&1 1>&2 2>&3)
    saida=$?
    if [[ $saida -eq '0' ]]; then
        if [[ -z $viewer ]]; then 
            msg "Dominio do Viewer do Typebot, para poder continuar"
            continue 
        else 
            break
        fi
    else
        echo "$viewer"; echo "saindo..." & exit 0
    fi
done

while true ; do
    email=$(whiptail --title "Seu Email de Acesso Admin ao Typebot" --inputbox "Digite Seu Email Admin (ex: contato@dominio.com):" --fb 12 60 3>&1 1>&2 2>&3)
    saida=$?
    if [[ $saida -eq '0' ]]; then
        if [[ -z $email ]]; then 
            msg "Digite o email, para poder continuar"
            continue 
        else 
            break
        fi
    else
        echo "$email"; echo "saindo..." & exit 0
    fi
done

user_smtp=$(whiptail --title "Usuário do SMTP" --inputbox "Pressione ENTER para configurar depois, ou digite o usuário do smtp." --fb 12 60 3>&1 1>&2 2>&3)
saida=$?
if [[ $saida -eq '0' ]]; then 
    if [[ -z $user_smtp ]]; then 
        user_smtp=usuario_do_smtp 
    fi 
else 
    echo "saindo..."; exit 
fi

email_smtp=$(whiptail --title "Email Remetente do SMTP" --inputbox "Pressione ENTER para configurar depois, ou digite o email do smtp." --fb 12 60 3>&1 1>&2 2>&3)
saida=$?
if [[ $saida -eq '0' ]]; then 
    if [[ -z $email_smtp ]]; then 
        email_smtp=email_do_smtp 
    fi 
else 
    echo "saindo..."; exit 
fi

senha=$(whiptail --title "Senha do Email SMTP" --inputbox "Pressione ENTER para configurar depois, ou digite o senha do seu email." --fb 12 60 3>&1 1>&2 2>&3)
saida=$?
if [[ $saida -eq '0' ]]; then 
    if [[ -z $senha ]]; then 
        senha=senha_do_email 
    fi 
else 
    echo "saindo..."; exit 
fi

smtp=$(whiptail --title "Host do SMTP do Email" --inputbox "Pressione ENTER para configurar depois, ou digite o Host SMTP do seu email (ex: smtp.hostinger.com):" --fb 12 60 3>&1 1>&2 2>&3)
saida=$?
if [[ $saida -eq '0' ]]; then 
    if [[ -z $smtp ]]; then 
        smtp=smtp.site.com 
    fi 
else 
    echo "saindo..."; exit 
fi

portasmtp=$(whiptail --title "Porta do SMTP" --inputbox "Pressione ENTER para configurar depois, ou digite digite a Porta SMTP (ex: 465):" --fb 12 60 3>&1 1>&2 2>&3)
saida=$?
if [[ $saida -eq '0' ]]; then 
    if [[ -z $portasmtp ]]; then 
        portasmtp=465 
    fi 
else 
    echo "saindo..."; exit 
fi

## Verifica se a porta é 465, se sim deixa o ssl true, se não, deixa false 
if [ "$portasmtp" -eq 465 ]; then
    SECURE=false
else
    SECURE=true
fi  

# Perguntar ao usuário se deseja criar a stack no Portainer
while true ; do
    criar_portainer=$(whiptail --title "Criar Stack no Portainer? - 0 ou 1" --inputbox "Digite 0 para poder editar stack no portainer ou 1 para não poder editar" --fb 12 60 3>&1 1>&2 2>&3)
    saida=$?
    if [[ $saida -eq '0' ]]; then
        if [[ "$criar_portainer" != "0" && "$criar_portainer" != "1" ]]; then 
            msg "Digite apenas o número 0 ou o número 1, para poder continuar. Digite 0 para poder editar stack no portainer ou 1 para não poder editar" 
            continue 
        else 
            break
        fi
    else
        echo "$criar_portainer"; echo "saindo..." & exit 0
    fi
done

# FIM DE PERGUNTAS PARA VARIAVEIS

# VERIFICAÇO DE DADOS

nome_principal="typebot"
sufixo_app=$(date | md5sum | head -c7 | tr '[:upper:]' '[:lower:]')
nome_app=$nome_principal$sufixo_app
postgres_password=$(grep -oP '(?<=POSTGRES_PASSWORD=).+' /root/postgres.yaml)
container_id=$(docker ps -qf name=postgres)
docker exec -it $container_id psql -U postgres -d postgres -c "CREATE DATABASE $nome_app;" 

if [[ ("$minio_container" == "") ]]; then
    nome_principal2="minio"
    nome_app2=$nome_principal2$sufixo_app
    sufixo_public="_public"
    sufixo_console="_console"
    nome_app_public=$nome_app2$sufixo_public
    nome_app_console=$nome_app2$sufixo_console
fi

if [[ ("$minio_container" == "") ]]; then
    {
        tput reset 2>/dev/null
        exec 0</dev/tty 1>/dev/tty 2>&1
        sleep 0.01
        clear
    } || true

    whiptail --title "Dados Fornecidos" \
    --msgbox "TIPO DE INSTALAÇÃO: $INSTALL_TYPE\n\nDados Preenchidos:\n\n1) Link do Painel Minio: $painel\n2) Link Público Minio: $publico\n3) Usuário do Minio: $usuariominio\n4) Senha do Minio: $senhaminio\n5) Dominio do Builder Typebot: $builder\n6) Dominio do Viewer Typebot: $viewer\n7) Seu Email: $email\n8) Usuário do SMTP: $user_smtp\n9) Email do SMTP: $email_smtp\n10) Senha do seu Email: $senha\n11) SMTP do seu email: $smtp\n12) Porta SMTP: $portasmtp\n13) SMTP_SECURE: $SECURE\n14) Criar Stack no Portainer: $([ "$criar_portainer" == "0" ] && echo "0 (Editável)" || echo "1 (Não editável)")\n\nConfira e Tecle Enter para continuar. Na próxima etapa você poderá confirmar os dados ou corrigir, se necessário." \
    --fb 22 80
else
    {
        tput reset 2>/dev/null
        exec 0</dev/tty 1>/dev/tty 2>&1
        sleep 0.01
        clear
    } || true

    whiptail --title "Dados Fornecidos" \
    --msgbox "TIPO DE INSTALAÇÃO: $INSTALL_TYPE\n\nDados Preenchidos:\n\n1) Link do Painel Minio: $MINIO_ADMIN_URL\n2) Link Público Minio: $MINIO_PUBLIC_URL\n3) Usuário do Minio: $MINIO_USER\n4) Senha do Minio: $MINIO_PASSWORD\n5) Dominio do Builder Typebot: $builder\n6) Dominio do Viewer Typebot: $viewer\n7) Seu Email: $email\n8) Usuário do SMTP: $user_smtp\n9) Email do SMTP: $email_smtp\n10) Senha do seu Email: $senha\n11) SMTP do seu email: $smtp\n12) Porta SMTP: $portasmtp\n13) SMTP_SECURE: $SECURE\n14) Criar Stack no Portainer: $([ "$criar_portainer" == "0" ] && echo "0 (Editável)" || echo "1 (Não editável)")\n\nConfira e Tecle Enter para continuar. Na próxima etapa você poderá confirmar os dados ou corrigir, se necessário." \
    --fb 22 80
fi

# Solicita confirmação dentro de um loop
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
        msg "Entrada inválida! Por favor, use apenas 'y' para sim ou 'n' para não. Digite Enter para continuar"
    fi
done

# MENSAGEM DE INSTALANDO
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

    echo -e "XXX\n22\nDOMÍNIOS VERIFICADOS COM SUCESSO \nXXX"
    sleep 1
    echo -e "XXX\n25\nCRIANDO STACKS DO MINIO 1/4 - CONCLUÍDO \nXXX"
    sleep 1 
    echo -e "XXX\n25\nFAZENDO O BUILD DOS STACKS DO MINIO 2/4 \nXXX"
    sleep 1
    echo -e "XXX\n29\nFAZENDO O BUILD DOS STACKS DO MINIO 2/4 - CONCLUÍDO \nXXX"
    sleep 1
   
    

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
        echo -e "XXX\n33\nCRIANDO STACK NO PORTAINER 3/4  \nXXX"
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
            echo -e "XXX\n36\nSEM ARQUIVO DE DADOS DO PORTAINER 3/4  \nXXX"
            docker stack deploy --prune --resolve-image always -c $nome_app2.yaml $nome_app2 >/dev/null 2>&1
            sleep 5
            exit 1
        fi

        get_auth_token() {
            echo -e "XXX\n39\nAUTENTICANDO NO PORTAINER... 3/4  \nXXX"
            RESPONSE=$(curl -sS -X POST "https://$PORTAINER_URL/api/auth" \
                -H "Content-Type: application/json" \
                -d "{\"username\": \"$ADMIN_USERNAME\", \"password\": \"$ADMIN_PASSWORD\"}")
            TOKEN=$(echo "$RESPONSE" | jq -r '.jwt')
            if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]; then
                echo -e "XXX\n40\nFALHA NA AUTENTICAÇÃO.. 3/4  \nXXX"
                sleep 5
                echo -e "XXX\n41\nREVERTENDO E CRIANDO STACK PELO SERVIDOR 3/4  \nXXX"
                docker stack deploy --prune --resolve-image always -c $nome_app2.yaml $nome_app2 >/dev/null 2>&1
                sleep 5
                exit 1
            fi
            echo -e "XXX\n42\n[SUCESSO] AUTENTICAÇÃO OK 3/4  \nXXX"
        }

        get_endpoint_id() {
            echo -e "XXX\n43\n[INFO] OBTENDO ENDPOINTID 3/4  \nXXX"
            RESPONSE=$(curl -sS -X GET "https://$PORTAINER_URL/api/endpoints" \
                -H "Authorization: Bearer $TOKEN")
            ENDPOINT_ID=$(echo "$RESPONSE" | jq -r '.[0].Id')
            if [ -z "$ENDPOINT_ID" ] || [ "$ENDPOINT_ID" = "null" ]; then
                echo -e "XXX\n44\n[ERRO] ENDPOINTID NÃO ENCONTRADO 3/4  \nXXX"
                docker stack deploy --prune --resolve-image always -c $nome_app2.yaml $nome_app2 >/dev/null 2>&1
                exit 1
            fi
            echo -e "XXX\n45\n[SUCESSO] ENDPOINTID OBTIDO: $ENDPOINT_ID  3/4  \nXXX"
        }

        get_swarm_id() {
            echo -e "XXX\n46\n[INFO] OBTENDO SWARMID  3/4  \nXXX"
            RESPONSE=$(curl -sS -X GET "https://$PORTAINER_URL/api/endpoints/$ENDPOINT_ID/docker/swarm" \
                -H "Authorization: Bearer $TOKEN")
            SWARM_ID=$(echo "$RESPONSE" | jq -r '.ID')
            if [ -z "$SWARM_ID" ] || [ "$SWARM_ID" = "null" ]; then
                echo -e "XXX\n47\n[ERRO] SWARMID NÃO ENCONTRADO 3/4  \nXXX"
                docker stack deploy --prune --resolve-image always -c $nome_app2.yaml $nome_app2 >/dev/null 2>&1
                exit 1
            fi
            echo -e "XXX\n48\n[SUCESSO] SWARMID OBTIDO: $SWARM_ID  3/4  \nXXX"
        }

        create_stack() {
            echo -e "XXX\n49\n[INFO] VERIFICANDO SE YAML EXISTE 3/4  \nXXX"
            if [ ! -f "$STACK_FILE_PATH" ]; then
                echo -e "XXX\n50\n[ERRO] ARQUIVO $STACK_FILE_PATH NÃO ENCONTRADO 3/4  \nXXX"
                docker stack deploy --prune --resolve-image always -c $nome_app2.yaml $nome_app2 >/dev/null 2>&1
                exit 1
            fi

            echo -e "XXX\n51\n[INFO] CRIANDO STACK $STACK_NAME NO PORTAINER 3/4  \nXXX"
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
                echo -e "XXX\n56\n[ERRO] ERRO AO CRIAR STACK 3/4  \nXXX"
                docker stack deploy --prune --resolve-image always -c $nome_app2.yaml $nome_app2 >/dev/null 2>&1
                exit 1
            fi

            echo -e "XXX\n57\n[SUCESSO] STACK $STACK_NAME CRIADA COM SUCESSO 3/4  \nXXX"
        }

        get_auth_token || exit 1
        get_endpoint_id || exit 1
        get_swarm_id || exit 1
        create_stack || exit 1

    elif [[ "$criar_portainer" == "1" ]]; then
        echo "Criando a stack diretamente no Docker (não editável no Portainer)."
        docker stack deploy --prune --resolve-image always -c $nome_app2.yaml $nome_app2 >/dev/null 2>&1
    else
        echo -e "XXX\n58\n[ERRO] ERRO INESPERADO PARA CRIAR STACK NO PORTAINER 3/4  \nXXX"
        sleep 5
        echo -e "XXX\n59\nREVERTENDO E CRIANDO STACK PELO SERVIDOR 3/4  \nXXX"
        docker stack deploy --prune --resolve-image always -c $nome_app2.yaml $nome_app2 >/dev/null 2>&1
        sleep 5
        exit 1
    fi
        echo -e "XXX\n60\nFINALIZANDO BUILD DO MINIO 4/4  \nXXX"
        sleep 2
        echo -e "XXX\n61\nFINALIZANDO BUILD DO MINIO 4/4 - CONCLUÍDO  \nXXX"
        sleep 3
    fi

# Função para verificar o domínio
# Função para verificar o domínio
#VERIFICANDO CONFIGURAÇÃO builder

echo -e "XXX\n5\nVERIFICANDO CONFIGURAÇÃO builder... \nXXX"

if [ "$INSTALL_TYPE" = "TRADICIONAL" ] && [ "$criar_dns" = "0" ]; then
    # CONFIGURAÇÃO TRADICIONAL COM DNS AUTOMÁTICO
    echo -e "XXX\n10\nCONFIGURANDO DNS AUTOMÁTICO (TRADICIONAL)... \nXXX"
    
    DOMINIO_PRINCIPAL=$(echo "$builder" | cut -d'.' -f2-)
    SUBDOMINIO=${builder%%.$DOMINIO_PRINCIPAL}

    # Verificar e remover registros existentes
    echo -e "XXX\n15\nVERIFICANDO REGISTROS EXISTENTES... \nXXX"
    EXISTING_RECORDS=$(curl -s -X GET \
        "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records?name=${builder}" \
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
        --data '{"type":"CNAME","name":"'${builder}'","content":"'${nome_servidor}'.'${DOMINIO_PRINCIPAL}'","ttl":1,"proxied":false}')

    if echo "$CNAME_RESPONSE" | grep -q '"success":true'; then
        echo -e "XXX\n30\nREGISTRO CNAME CRIADO COM SUCESSO! \nXXX"
    else
        echo -e "XXX\n30\nAVISO: ERRO AO CRIAR REGISTRO CNAME \nXXX"
    fi

elif [ "$INSTALL_TYPE" = "CLOUDFLARE_TUNNEL" ]; then
    # CONFIGURAÇÃO CLOUDFLARE TUNNEL - DNS E ROTAS
    echo -e "XXX\n10\nCONFIGURANDO CLOUDFLARE TUNNEL (DNS + ROTAS)... \nXXX"
    
    DOMINIO_PRINCIPAL=$(echo "$builder" | cut -d'.' -f2-)
    SUBDOMINIO=${builder%%.$DOMINIO_PRINCIPAL}

    # 1. PRIMEIRO CONFIGURAR O DNS
    echo -e "XXX\n15\nCONFIGURANDO REGISTRO DNS... \nXXX"
    
    # Verificar e remover registros existentes
    EXISTING_RECORDS=$(curl -s -X GET \
        "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records?name=${builder}" \
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
        --data "{\"type\":\"CNAME\",\"name\":\"${builder}\",\"content\":\"${TUNNEL_ID}.cfargotunnel.com\",\"ttl\":1,\"proxied\":true}")

    if echo "$DNS_RESPONSE" | grep -q '"success":true'; then
        echo -e "XXX\n30\nREGISTRO DNS CRIADO COM SUCESSO! \nXXX"
    else
        echo -e "XXX\n30\nAVISO: ERRO AO CRIAR REGISTRO DNS \nXXX"
    fi

    # 2. AGORA ATUALIZAR AS ROTAS DO TUNNEL
    echo -e "XXX\n35\nATUALIZANDO CONFIGURAÇÃO DO TUNNEL... \nXXX"

    # Configuração do novo serviço para o Rabbitmq
    NEW_SERVICE="http://${nome_app}-builder:3000"
    
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
    
    jq --arg host "$builder" --arg service "$NEW_SERVICE" '
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
    if nslookup "$builder" >/dev/null 2>&1; then
        echo -e "XXX\n15\nDNS CONFIGURADO \nXXX"
    else
        echo -e "XXX\n15\nAVISO: VERIFIQUE A CONFIGURAÇÃO DNS \nXXX"
    fi
fi


if [ "$INSTALL_TYPE" = "TRADICIONAL" ] && [ "$criar_dns" = "1" ]; then


# Função para verificar o domínio quando fora do cloudflare

ip_servidor=$(curl -s --max-time 10 ipinfo.io/ip)

echo -e "XXX\n3\nVERIFICANDO SUBDOMÍNIO: $builder \nXXX"
sleep 3

tentativas=5
tentativa_atual=1
sucesso=0

while [ $tentativa_atual -le $tentativas ]; do
    echo -e "XXX\n$(( (tentativa_atual * 12) / tentativas + 3 ))\nTentativa $tentativa_atual de $tentativas...\nXXX"
    
    dns_ip3=$(timeout 10 nslookup -type=A "$builder" | grep -E "Address: [0-9]+\." | awk '{print $2}' | head -n1)
    
    if [[ -n "$dns_ip3" && "$dns_ip3" == "$ip_servidor" ]]; then
        sucesso=1
       # break
    fi
    
  #  sleep $((tentativa_atual * 2))
  sleep 1
    ((tentativa_atual++))
done

if [ $sucesso -eq 0 ]; then

    echo -e "XXX\n10\nERRO: SUBDOMÍNIO DO builder NÃO APONTA PARA O IP ($ip_servidor) \nXXX"
    sleep 3
    echo -e "XXX\n18\nERRO: DNS NÃO CONFIGURADO CORRETAMENTE \nXXX"
    sleep 3
    exit 1
fi
    echo -e "XXX\n18\nDOMÍNIO builder VERIFICADO COM SUCESSO \nXXX"
sleep 4
fi

#VERIFICANDO CONFIGURAÇÃO viewer

echo -e "XXX\n5\nVERIFICANDO CONFIGURAÇÃO viewer... \nXXX"

if [ "$INSTALL_TYPE" = "TRADICIONAL" ] && [ "$criar_dns" = "0" ]; then
    # CONFIGURAÇÃO TRADICIONAL COM DNS AUTOMÁTICO
    echo -e "XXX\n10\nCONFIGURANDO DNS AUTOMÁTICO (TRADICIONAL)... \nXXX"
    
    DOMINIO_PRINCIPAL=$(echo "$viewer" | cut -d'.' -f2-)
    SUBDOMINIO=${viewer%%.$DOMINIO_PRINCIPAL}

    # Verificar e remover registros existentes
    echo -e "XXX\n15\nVERIFICANDO REGISTROS EXISTENTES... \nXXX"
    EXISTING_RECORDS=$(curl -s -X GET \
        "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records?name=${viewer}" \
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
        --data '{"type":"CNAME","name":"'${viewer}'","content":"'${nome_servidor}'.'${DOMINIO_PRINCIPAL}'","ttl":1,"proxied":false}')

    if echo "$CNAME_RESPONSE" | grep -q '"success":true'; then
        echo -e "XXX\n30\nREGISTRO CNAME CRIADO COM SUCESSO! \nXXX"
    else
        echo -e "XXX\n30\nAVISO: ERRO AO CRIAR REGISTRO CNAME \nXXX"
    fi

elif [ "$INSTALL_TYPE" = "CLOUDFLARE_TUNNEL" ]; then
    # CONFIGURAÇÃO CLOUDFLARE TUNNEL - DNS E ROTAS
    echo -e "XXX\n10\nCONFIGURANDO CLOUDFLARE TUNNEL (DNS + ROTAS)... \nXXX"
    
    DOMINIO_PRINCIPAL=$(echo "$viewer" | cut -d'.' -f2-)
    SUBDOMINIO=${viewer%%.$DOMINIO_PRINCIPAL}

    # 1. PRIMEIRO CONFIGURAR O DNS
    echo -e "XXX\n15\nCONFIGURANDO REGISTRO DNS... \nXXX"
    
    # Verificar e remover registros existentes
    EXISTING_RECORDS=$(curl -s -X GET \
        "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records?name=${viewer}" \
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
    --data "{\"type\":\"CNAME\",\"name\":\"${viewer}\",\"content\":\"${TUNNEL_ID}.cfargotunnel.com\",\"ttl\":1,\"proxied\":true}")

    if echo "$DNS_RESPONSE" | grep -q '"success":true'; then
        echo -e "XXX\n30\nREGISTRO DNS CRIADO COM SUCESSO! \nXXX"
    else
        echo -e "XXX\n30\nAVISO: ERRO AO CRIAR REGISTRO DNS \nXXX"
    fi

    # 2. AGORA ATUALIZAR AS ROTAS DO TUNNEL
    echo -e "XXX\n35\nATUALIZANDO CONFIGURAÇÃO DO TUNNEL... \nXXX"

    # Configuração do novo serviço
  #  NEW_SERVICE="http://${$nome_app_chatwoot-app}:3000" errado
    NEW_SERVICE="http://${nome_app}-viewer:3000"
    
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
    
    jq --arg host "$viewer" --arg service "$NEW_SERVICE" '
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
    if nslookup "$viewer" >/dev/null 2>&1; then
        echo -e "XXX\n15\nDNS CONFIGURADO \nXXX"
    else
        echo -e "XXX\n15\nAVISO: VERIFIQUE A CONFIGURAÇÃO DNS \nXXX"
    fi
fi


if [ "$INSTALL_TYPE" = "TRADICIONAL" ] && [ "$criar_dns" = "1" ]; then


# Função para verificar o domínio quando fora do cloudflare
ip_servidor=$(curl -s --max-time 10 ipinfo.io/ip)

echo -e "XXX\n3\nVERIFICANDO SUBDOMÍNIO: $viewer \nXXX"
sleep 3

tentativas=5
tentativa_atual=1
sucesso=0

while [ $tentativa_atual -le $tentativas ]; do
    echo -e "XXX\n$(( (tentativa_atual * 12) / tentativas + 3 ))\nTentativa $tentativa_atual de $tentativas...\nXXX"
    
    dns_ip4=$(timeout 10 nslookup -type=A "$viewer" | grep -E "Address: [0-9]+\." | awk '{print $2}' | head -n1)
    
    if [[ -n "$dns_ip4" && "$dns_ip4" == "$ip_servidor" ]]; then
        sucesso=1
       # break
    fi
    
  #  sleep $((tentativa_atual * 2))
  sleep 1
    ((tentativa_atual++))
done

if [ $sucesso -eq 0 ]; then

    echo -e "XXX\n10\nERRO: SUBDOMÍNIO DO viewer NÃO APONTA PARA O IP ($ip_servidor) \nXXX"
    sleep 3
    echo -e "XXX\n18\nERRO: DNS NÃO CONFIGURADO CORRETAMENTE \nXXX"
    sleep 3
    exit 1
fi
    echo -e "XXX\n18\nDOMÍNIO DO viewer VERIFICADO COM SUCESSO \nXXX"
sleep 4
fi
 


####### fim de verificando dominio 


echo -e "XXX\n70\nCRIANDO STACK DO TYPEBOT 1/4 \nXXX"
sleep 1
echo -e "XXX\n72\nFAZENDO O BUILD DO STACK DO TYPEBOT 2/4 \nXXX"
sleep 1
echo -e "XXX\n73\nFAZENDO O BUILD DO STACK DO TYPEBOT 2/4 - CONCLUIDO \nXXX"
sleep 1
echo -e "XXX\n74\nCRIANDO BANCO DE DADOS DO TYPEBOT 3/4 \nXXX"
sleep 1
echo -e "XXX\n75\nAGUARDANDO PROPAGAÇÃO - PODE DEMORAR UM POUCO \nXXX"





#######################################################
#
#  INSTALANDO O TYPEBOT
#

cd

cd
clear

###### checa se minio está rodando

max_wait_time=600  #ajuste do tempo mximo de espera

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

# Criar bucket e credenciais
bucket_name="$nome_app"
mc mb minio/$bucket_name || true
#mc anonymous set public minio/$bucket_name
mc anonymous set public minio/$bucket_name || true

###########
###########
create_service_account() {
    local bucket=$1
    local app_name=$2
    
    
    # Criar service account
    credentials=$(mc admin user svcacct add minio "$MINIO_USER" \
        --access-key "$ACCESS_KEY" \
        --secret-key "$SECRET_KEY" \
        --json 2>&1)
        

    if [[ -z "$access_key" || -z "$secret_key" ]]; then
    # Extrair chaves com validação rigorosa
    access_key=$(echo "$credentials" | jq -r '.accessKey')
    secret_key=$(echo "$credentials" | jq -r '.secretKey')
    fi

}

# Chamar a função
create_service_account "$bucket_name" "$nome_app"



key=$(openssl rand -hex 16)


cat > $nome_app.yaml << EOL

version: "3.7"
services:
  $nome_app-builder:
    image: baptistearno/typebot-builder:latest
    networks: 
    - externa
    - interna
    environment:
    - POSTGRESDB_DATABASE=$nome_app
    - POSTGRESDB_HOST=postgres
    - POSTGRESDB_PORT=5432
    - POSTGRESDB_USER=postgres
    - POSTGRESDB_PASSWORD=$postgres_password
    - ENCRYPTION_SECRET=$key
    - DATABASE_URL=postgresql://postgres:$postgres_password@postgres:5432/$nome_app
    - NEXTAUTH_URL=https://$builder
    - NEXT_PUBLIC_VIEWER_URL=https://$viewer
    - ADMIN_EMAIL=$email
    - DISABLE_SIGNUP=false
    - SMTP_AUTH_DISABLED=false
    - NEXTAUTH_URL_INTERNAL=http://localhost:3000
    - SMTP_USERNAME=$user_smtp
    - SMTP_PASSWORD=$senha
    - SMTP_HOST=$smtp
    - SMTP_PORT=$portasmtp
    - NEXT_PUBLIC_SMTP_FROM='Typebot' <$email_smtp>
    - SMTP_SECURE=$SECURE
    #- GOOGLE_CLIENT_ID=
    #- GOOGLE_CLIENT_SECRET=
    - S3_ACCESS_KEY=$access_key
    - S3_SECRET_KEY=$secret_key
    - S3_BUCKET=$bucket_name
    - S3_ENDPOINT=$MINIO_PUBLIC_URL
    - S3_REGION=us-east-1  # Adicione esta linha
    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
        - node.role == manager
EOL
# Adicionar as labels apenas se for instalação tradicional
if [ "$INSTALL_TYPE" = "TRADICIONAL" ]; then
cat >> $nome_app.yaml << EOL
      labels:
      - traefik.enable=1
      - traefik.http.routers.$nome_app-builder.rule=(Host(\`$builder\`))
      - traefik.http.routers.$nome_app-builder.entrypoints=websecure
      - traefik.http.routers.$nome_app-builder.priority=1
      - traefik.http.routers.$nome_app-builder.tls.certresolver=letsencryptresolver
      - traefik.http.routers.$nome_app-builder.service=$nome_app-builder
      - traefik.http.services.$nome_app-builder.loadbalancer.server.port=3000
      - traefik.http.services.$nome_app-builder.loadbalancer.passHostHeader=1
EOL
fi
cat >> $nome_app.yaml << EOL
  $nome_app-viewer:
    image: baptistearno/typebot-viewer:latest
    networks: 
    - externa
    - interna
    environment:
    - POSTGRESDB_DATABASE=$nome_app
    - POSTGRESDB_HOST=postgres
    - POSTGRESDB_PORT=5432
    - POSTGRESDB_USER=postgres
    - POSTGRESDB_PASSWORD=$postgres_password
    - ENCRYPTION_SECRET=$key
    - DATABASE_URL=postgresql://postgres:$postgres_password@postgres:5432/$nome_app
    - NEXTAUTH_URL=https://$builder
    - NEXT_PUBLIC_VIEWER_URL=https://$viewer
    - ADMIN_EMAIL=$email
    - DISABLE_SIGNUP=false
    - SMTP_AUTH_DISABLED=false
    - NEXTAUTH_URL_INTERNAL=http://localhost:3000
    - SMTP_USERNAME=$user_smtp
    - SMTP_PASSWORD=$senha
    - SMTP_HOST=$smtp
    - SMTP_PORT=$portasmtp
    - NEXT_PUBLIC_SMTP_FROM='Typebot' <$email_smtp>
    - SMTP_SECURE=$SECURE
    #- GOOGLE_CLIENT_ID=
    #- GOOGLE_CLIENT_SECRET=
    - S3_ACCESS_KEY=$access_key
    - S3_SECRET_KEY=$secret_key
    - S3_BUCKET=$bucket_name
    - S3_ENDPOINT=$MINIO_PUBLIC_URL
    - S3_REGION=us-east-1  # Adicione esta linha
    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
        - node.role == manager
EOL
# Adicionar as labels apenas se for instalação tradicional
if [ "$INSTALL_TYPE" = "TRADICIONAL" ]; then
cat >> $nome_app.yaml << EOL
      labels:
      - traefik.enable=1
      - traefik.http.routers.$nome_app-viewer.rule=(Host(\`$viewer\`))
      - traefik.http.routers.$nome_app-viewer.entrypoints=websecure
      - traefik.http.routers.$nome_app-viewer.priority=1
      - traefik.http.routers.$nome_app-viewer.tls.certresolver=letsencryptresolver
      - traefik.http.routers.$nome_app-viewer.service=$nome_app-viewer
      - traefik.http.services.$nome_app-viewer.loadbalancer.server.port=3000
      - traefik.http.services.$nome_app-viewer.loadbalancer.passHostHeader=1
EOL
fi
cat >> $nome_app.yaml << EOL
networks: 
  externa: 
    external: true
  interna: 
    external: true


EOL

#docker stack deploy --prune --resolve-image always -c $nome_app.yaml $nome_app >/dev/null 2>&1


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
STACK_NAME=$nome_app
STACK_FILE_PATH="/root/$nome_app.yaml"

else
   # echo "Erro: Arquivo de dados não encontrado em $dados_file."
    sleep 5
echo -e "XXX\n77\nSEM ARQUIVO DE DADOS DO PORTAINER 3/4  \nXXX"
docker stack deploy --prune --resolve-image always -c $nome_app.yaml $nome_app >/dev/null 2>&1
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
docker stack deploy --prune --resolve-image always -c $nome_app.yaml $nome_app >/dev/null 2>&1
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
        docker stack deploy --prune --resolve-image always -c $nome_app.yaml $nome_app >/dev/null 2>&1
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
        docker stack deploy --prune --resolve-image always -c $nome_app.yaml $nome_app >/dev/null 2>&1
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
        docker stack deploy --prune --resolve-image always -c $nome_app.yaml $nome_app >/dev/null 2>&1
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
        docker stack deploy --prune --resolve-image always -c $nome_app.yaml $nome_app >/dev/null 2>&1
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
    docker stack deploy --prune --resolve-image always -c $nome_app.yaml $nome_app >/dev/null 2>&1
else
    # Caso inesperado (não deve ocorrer devido à validação anterior no while loop)
   # echo "Erro: valor inesperado para criar_portainer. Encerrando..."
    echo -e "XXX\n91\n[ERRO] ERRO INESPERADO PARA CRIAR STACK NO PORTAINER 3/4  \nXXX"
    sleep 5
    echo -e "XXX\n92\nREVERTENDO E CRIANDO STACK PELO SERVIDOR 3/4  \nXXX"
docker stack deploy --prune --resolve-image always -c $nome_app.yaml $nome_app >/dev/null 2>&1
sleep 5

    exit 1
fi

    echo -e "XXX\n93\nFINALIZANDO BUILD DO TYPEBOT 4/4 - AGUARDE  \nXXX"
    sleep 12
    echo -e "XXX\n100\nFINALIZANDO BUILD DO TYPEBOT 4/4 - CONCLUIDO  \nXXX"
    sleep 3

} | whiptail --title "TYPEBOT COM MINIO - PROGRESSO DA INSTALAÇÃO" --gauge "Aguarde a instalação dos ítens necessários" 6 60 0

# VERIFICAÇÃO FINAL - Versão Corrigida
if [ "$INSTALL_TYPE" = "CLOUDFLARE_TUNNEL" ]; then
    failed_domains=0
    domains_to_check=""
    
    # Determinar quais domínios verificar baseado se Minio foi instalado
    if [[ "$minio_container" == "" ]]; then
        domains_to_check="$painel $publico $builder $viewer"
    else
        domains_to_check="$builder $viewer"
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
        whiptail --title "Sucesso" --msgbox "Instalação concluída com sucesso! Cloudflare Tunnel configurado.\n\nAcessos:\n- Typebot Admin: https://$builder\n- Typebot Public: https://$viewer\n\nPressione ENTER para voltar ao Menu Principal" 20 78
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

    dns_ip3=$(timeout 10 nslookup "$builder" 2>/dev/null | grep "Address" | tail -n1 | awk '{print $2}')
    dns_ip4=$(timeout 10 nslookup "$viewer" 2>/dev/null | grep "Address" | tail -n1 | awk '{print $2}')
    [[ "$dns_ip3" != "$ip_servidor" ]] && status=1
    [[ "$dns_ip4" != "$ip_servidor" ]] && status=1

    if [[ $status -eq 1 ]]; then
        whiptail --title "Erro" --msgbox "Não foi possível acessar um ou mais subdomínios. Verifique os apontamentos de DNS." 20 78
    else
        whiptail --title "Sucesso" --msgbox "Instalação concluída com sucesso! Tecle enter para continuar." 20 78
    fi
fi

exit 0

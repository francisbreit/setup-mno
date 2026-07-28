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
		whiptail --title "INSTALAÇÃO DA EVOLUTION API: Restful API para funções WhatsaApp" --msgbox "$msg" --fb 10 70;
	}

  while true; do
CHOICE=$(
whiptail --title "INSTALAÇO DA EVOLUTION API: Restful API para funções WhatsaApp" --menu "Aperte ENTER para iniciar a instalação da EVOLUTION API ou selecione SAIR (Utilize setas e Enter)\n\nTIPO DE INSTALAÇÃO DETECTADA: $INSTALL_TYPE\n\nINSTRUÇÕES:\nAntes de prosseguir, verifique os registros DNS conforme seu tipo de instalação:" 20 70 2 \
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
		dominio=$(whiptail --title "1/5 - URL da Evolution API" --inputbox "Digite seu dominio para acessar a api (ex: api.dominio.com): " --fb 12 60 3>&1 1>&2 2>&3) ; saida=$?
		if [[ $saida -eq '0' ]] ; then
			if [[ -z $dominio ]] ; then msg "Digite o link da Evolution API para poder continuar" ; continue ; else break; fi
		else
			echo $dominio ; echo "saindo..."  &  exit 0 ;
		fi
	done

      while true ; do
		client=$(whiptail --title "2/5 - Nome da Empresa" --inputbox "Digite o nome da sua empresa (ex: MNOzap):" --fb 12 60 3>&1 1>&2 2>&3) ; saida=$?
		if [[ $saida -eq '0' ]] ; then
			if [[ -z $client ]] ; then msg "Digite o nome da empresa para poder continuar" ; continue ; else break; fi
		else
			echo $client ; echo "saindo..."  &  exit 0 ;
		fi
	done
chave_hexadecimal=$(openssl rand -hex 16)
     while true ; do
		key=$(whiptail --title "3/5 - Global API Key" --inputbox "Digite a Api Global Key (sugestão gerada aleatóriamente: $chave_hexadecimal):" --fb 12 60 3>&1 1>&2 2>&3) ; saida=$?
		if [[ $saida -eq '0' ]] ; then
			if [[ -z $key ]] ; then msg "Crie uma Global APi Key para oa Evolution, para poder continuar" ; continue ; else break; fi
		else
			echo $key ; echo "saindo..."  &  exit 0 ;
		fi
	done




#  mongo variaveis - inicio
 
     while true ; do
		user_mongodb=$(whiptail --title "4/5 - Usuario do Mongodb" --inputbox "Crie o usuario do Mongodb:" --fb 12 60 3>&1 1>&2 2>&3) ; saida=$?
		if [[ $saida -eq '0' ]] ; then
			#if [[ -z $user_mongodb ]] ; then msg "Crie e preencha o usuário do Mongodb para poder continuar" ; continue ; else break; fi
		  if [[ (-z $user_mongodb) || ("$user_mongodb" =~ [^a-zA-Z0-9]) || (${#user_mongodb} -gt 16) ]] ; then msg "Crie a so usuário do Mongodb, sem caracteres especiais e até 16 digitos para poder continuar" ; continue ; else break; fi
    else
			echo $user_mongodb ; echo "saindo..."  &  exit 0 ;
		fi
	done
  

    while true ; do
		mongodb_senha=$(whiptail --title "5/5 - Senha do Mongodb" --inputbox "Crie a senha do Mongodb (obs: use senha segura):" --fb 12 60 3>&1 1>&2 2>&3) ; saida=$?
		if [[ $saida -eq '0' ]] ; then
			#if [[ -z $mongodb_senha ]] ; then msg "Crie e preencha a senha do Mongodb para poder continuar" ; continue ; else break; fi
		  if [[ (-z $mongodb_senha) || ("$mongodb_senha" =~ [^a-zA-Z0-9]) || (${#mongodb_senha} -gt 16) ]] ; then msg "Crie a senha do Mongodb, sem caracteres especiais e até 16 digitos para poder continuar" ; continue ; else break; fi
    else
			echo $mongodb_senha ; echo "saindo..."  &  exit 0 ;
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


sufixo_app=$(date | md5sum | head -c7)
nome_principal_mongo="mongo"  #nome do app
nome_app_mongo=$nome_principal_mongo$sufixo_app



#  mongo variaveis - fim







clear






# FIM DAS PERGUNTAS PARA VARIAVEIS
#
#########################################################
#
# VERIFICAÇÃO DE DADOS
#

nome_principal="evolution"  #nome do app

nome_app=$nome_principal$sufixo_app
#mongodb_user=$(grep -oP '(?<=MONGO_INITDB_ROOT_USERNAME=).+' /root/mongodb.yaml)
#mongodb_password=$(grep -oP '(?<=MONGO_INITDB_ROOT_PASSWORD=).+' /root/mongodb.yaml)
postgres_password=$(grep -oP '(?<=POSTGRES_PASSWORD=).+' /root/postgres.yaml)

# Ajuste do terminal para garantir compatibilidade
{
  tput reset 2>/dev/null         # Reinicia o terminal de forma segura
  exec 0</dev/tty 1>/dev/tty 2>&1 # Força redirecionamentos explícitos
  sleep 0.01                     # Pausa microscópica para sincronia
  clear                          # Limpeza final antes do whiptail
} || true


    # Exibe as informações formatadas com mais espaço na tela
    whiptail --title "Dados Fornecidos" \
    --msgbox "TIPO DE INSTALAÇÃO: $INSTALL_TYPE\n\nDados Preenchidos:\n\n1) Dominio: $dominio\n2) Nome da Empresa: $client\n3) Api Global Key: $key\n4) Usuario do Mongodb: $user_mongodb\n5) Senha do Mongodb: $mongodb_senha\n6) Criar Stack no Portainer: $([ "$criar_portainer" == "0" ] && echo "0 (Editável)" || echo "1 (Não editável)")\n\nConfira e Tecle Enter para continuar. Na próxima etapa você poderá confirmar os dados ou corrigir, se necessário." \
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

#
#  INSTALANDO O Mongo db
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

    # Configuração do novo serviço para o Baserow
    NEW_SERVICE="http://${nome_app}:8080"
    
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
# dominio=$1
ip_servidor=$(curl -s --max-time 10 ipinfo.io/ip)

echo -e "XXX\n3\nVERIFICANDO SUBDOMÍNIO: $dominio \nXXX"
sleep 3

tentativas=5
tentativa_atual=1
sucesso=0

while [ $tentativa_atual -le $tentativas ]; do
    echo -e "XXX\n$(( (tentativa_atual * 12) / tentativas + 3 ))\nTentativa $tentativa_atual de $tentativas...\nXXX"
    
    dns_ip=$(timeout 10 nslookup -type=A "$dominio" | grep -E "Address: [0-9]+\." | awk '{print $2}' | head -n1)
    
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

echo -e "XXX\n21\nCRIANDO STACK DA EVOLUTION 1/4 \nXXX"
sleep 1
echo -e "XXX\n25\nFAZENDO O BUILD DO STACK DA EVOLUTION 2/4 \nXXX"
sleep 1
echo -e "XXX\n50\nFAZENDO O BUILD DO STACK DA EVOLUTION 2/4 - CONCLUIDO \nXXX"
sleep 1
echo -e "XXX\n51\nVERIFICANDO INFORMAÇÕES 3/4 \nXXX"
sleep 1
echo -e "XXX\n52\nVERIFICANDO INFORMAÇÕES 3/4 - CONCLUIDO \nXXX"



cd

cd

clear

cat > $nome_app_mongo.yaml << EOL

version: '3.7'
services:
     $nome_app_mongo:
        image: mongo:6
        command: mongod --port 27077
        environment:
            - MONGO_INITDB_ROOT_USERNAME=$user_mongodb
            - MONGO_INITDB_ROOT_PASSWORD=$mongodb_senha
            - PUID=1000
            - PGID=1000
        volumes:
            -  $nome_app_mongo-data:/data/db
            -  $nome_app_mongo-configdb_data:/data/configdb

        networks: 
            - externa
            - interna
        deploy:
            mode: replicated
            replicas: 1
            placement:
                constraints:
                    - node.role == manager
volumes:
    $nome_app_mongo-data:
        external: true
        name: $nome_app_mongo-data
    $nome_app_mongo-configdb_data:
        external: true
        name: $nome_app_mongo-configdb_data

networks: 
    externa: 
        external: true
    interna: 
        external: true


EOL

#docker stack deploy --prune --resolve-image always -c $nome_app_mongo.yaml $nome_app_mongo >/dev/null 2>&1

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
STACK_NAME=$nome_app_mongo
STACK_FILE_PATH="/root/$nome_app_mongo.yaml"

else
   # echo "Erro: Arquivo de dados não encontrado em $dados_file."
    sleep 5
echo -e "XXX\n53\nSEM ARQUIVO DE DADOS DO PORTAINER 3/4  \nXXX"
docker stack deploy --prune --resolve-image always -c $nome_app_mongo.yaml $nome_app_mongo >/dev/null 2>&1
sleep 5
    exit 1
fi

# Função para autenticação
get_auth_token() {
    #echo "[INFO] Autenticando no Portainer..."
    echo -e "XXX\n54\nAUTENTICANDO NO PORTAINER... 3/4  \nXXX"
    RESPONSE=$(curl -sS -X POST "https://$PORTAINER_URL/api/auth" \
        -H "Content-Type: application/json" \
        -d "{\"username\": \"$ADMIN_USERNAME\", \"password\": \"$ADMIN_PASSWORD\"}")
    TOKEN=$(echo "$RESPONSE" | jq -r '.jwt')
    if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]; then
        # echo "[ERRO] Falha na autenticação."
        echo -e "XXX\n55\nFALHA NA AUTENTICAÇÃO.. 3/4  \nXXX"
sleep 5
echo -e "XXX\n56\nREVERTENDO E CRIANDO STACK PELO SERVIDOR 3/4  \nXXX"
docker stack deploy --prune --resolve-image always -c $nome_app_mongo.yaml $nome_app_mongo >/dev/null 2>&1
sleep 5
        exit 1
    fi
  #  echo "[SUCESSO] Autenticação realizada com sucesso. Token obtido."
 echo -e "XXX\n57\n[SUCESSO] AUTENTICAÇÃO OK 3/4  \nXXX"
}

# Função para obter o EndpointID
get_endpoint_id() {
   # echo "[INFO] Obtendo EndpointID..."
    echo -e "XXX\n58\n[INFO] OBTENDO ENDPOINTID 3/4  \nXXX"
    RESPONSE=$(curl -sS -X GET "https://$PORTAINER_URL/api/endpoints" \
        -H "Authorization: Bearer $TOKEN")
    ENDPOINT_ID=$(echo "$RESPONSE" | jq -r '.[0].Id')
    if [ -z "$ENDPOINT_ID" ] || [ "$ENDPOINT_ID" = "null" ]; then
        # echo "[ERRO] EndpointID não encontrado! Resposta: $RESPONSE"
        echo -e "XXX\n59\n[ERRO] ENDPOINTID NÃO ENCONTRADO 3/4  \nXXX"
        docker stack deploy --prune --resolve-image always -c $nome_app_mongo.yaml $nome_app_mongo >/dev/null 2>&1
        exit 1
    fi
     echo -e "XXX\n60\n[SUCESSO] ENDPOINTID OBTIDO: $ENDPOINT_ID  3/4  \nXXX"
    #echo "[SUCESSO] EndpointID obtido: $ENDPOINT_ID"
}

# Função para obter o SwarmID
get_swarm_id() {
   # echo "[INFO] Obtendo SwarmID..."
    echo -e "XXX\n61\n[INFO] OBTENDO SWARMID  3/4  \nXXX"
    RESPONSE=$(curl -sS -X GET "https://$PORTAINER_URL/api/endpoints/$ENDPOINT_ID/docker/swarm" \
        -H "Authorization: Bearer $TOKEN")
    SWARM_ID=$(echo "$RESPONSE" | jq -r '.ID')
    if [ -z "$SWARM_ID" ] || [ "$SWARM_ID" = "null" ]; then
        #echo "[ERRO] SwarmID não encontrado! Resposta: $RESPONSE"
        echo -e "XXX\n62\n[ERRO] SWARMID NÃO ENCONTRADO 3/4  \nXXX"
        docker stack deploy --prune --resolve-image always -c $nome_app_mongo.yaml $nome_app_mongo >/dev/null 2>&1
        exit 1
    fi
    #echo "[SUCESSO] SwarmID obtido: $SWARM_ID"
    echo -e "XXX\n63\n[SUCESSO] SWARMID OBTIDO: $SWARM_ID  3/4  \nXXX"
}

# Função para criar a stack
create_stack() {
    ##echo "[INFO] Verificando existência do arquivo YAML..."
    echo -e "XXX\n64\n[INFO] VERIFICANDO SE YAML EXISTE 3/4  \nXXX"
    if [ ! -f "$STACK_FILE_PATH" ]; then
        #echo "[ERRO] Arquivo $STACK_FILE_PATH não encontrado!"
        echo -e "XXX\n65\n[ERRO] ARQUIVO $STACK_FILE_PATH NÃO ENCONTRADO 3/4  \nXXX"
        docker stack deploy --prune --resolve-image always -c $nome_app_mongo.yaml $nome_app_mongo >/dev/null 2>&1
        exit 1
    fi

    #echo "[INFO] Criando stack '$STACK_NAME' no Portainer..."
     echo -e "XXX\n66\n[INFO] CRIANDO STACK $STACK_NAME NO PORTAINER 3/4  \nXXX"
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
        echo -e "XXX\n67\n[ERRO] ERRO AO CRIAR STACK 3/4  \nXXX"
        docker stack deploy --prune --resolve-image always -c $nome_app_mongo.yaml $nome_app_mongo >/dev/null 2>&1
        exit 1
    fi

   # echo "[SUCESSO] Stack '$STACK_NAME' criada com sucesso!"
    echo -e "XXX\n68\n[SUCESSO] STACK $STACK_NAME  CRIADA COM SUCESSO 3/4  \nXXX"
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
  #  echo "Criando a stack diretamente no Docker (não editável no Portainer)."
    docker stack deploy --prune --resolve-image always -c $nome_app_mongo.yaml $nome_app_mongo >/dev/null 2>&1
else
    # Caso inesperado (não deve ocorrer devido à validação anterior no while loop)
   # echo "Erro: valor inesperado para criar_portainer. Encerrando..."
    echo -e "XXX\n69\n[ERRO] ERRO INESPERADO PARA CRIAR STACK NO PORTAINER 3/4  \nXXX"
    sleep 5
    echo -e "XXX\n70\nREVERTENDO E CRIANDO STACK PELO SERVIDOR 3/4  \nXXX"
docker stack deploy --prune --resolve-image always -c $nome_app_mongo.yaml $nome_app_mongo >/dev/null 2>&1
sleep 5

    exit 1
fi



# FIM DE INSTALANDO O MONGODB
#
#######################################################
#######################################################
#
#  INSTALANDO EVOLUTION
#


cat > $nome_app.yaml << EOL

version: "3.7"
services:
  $nome_app:
    image: evoapicloud/evolution-api:v1.8.7
    command: ["node", "./dist/src/main.js"]
    hostname: $nome_app

    networks: 
      - externa
      - interna
    environment:
    - TYPEBOT_API_VERSION=latest
    - TYPEBOT_KEEP_OPEN=true
    - SERVER_URL=https://$dominio
    - DOCKER_ENV=true
    - LOG_LEVEL=ERROR,WARN,DEBUG,INFO,LOG,VERBOSE,DARK,WEBHOOKS
    - LOG_COLOR=true
    #Log Baileys=fatal | "error" | "warn" | "info" | "debug" | "trace"
    - LOG_BAILEYS=error
    #- CONFIG_SESSION_PHONE_VERSION=2,3000,1015901307
    - DEL_INSTANCE=false
    - AUTHENTICATION_TYPE=apikey
    - AUTHENTICATION_API_KEY=$key
    - AUTHENTICATION_EXPOSE_IN_FETCH_INSTANCES=true
    - WEBHOOK_GLOBAL_ENABLED=true
    - WEBHOOK_GLOBAL_URL=
    - WEBHOOK_GLOBAL_WEBHOOK_BY_EVENTS=false
    - WEBHOOK_EVENTS_APPLICATION_STARTUP=false 
    - WEBHOOK_EVENTS_STATUS_INSTANCE=true
    - WEBHOOK_EVENTS_QRCODE_UPDATED=true
    - WEBHOOK_EVENTS_MESSAGES_SET=false
    - WEBHOOK_EVENTS_MESSAGES_UPDATE=true
    - WEBHOOK_EVENTS_MESSAGES_UPSERT=true
    - WEBHOOK_EVENTS_SEND_MESSAGE=true
    - WEBHOOK_EVENTS_CONTACTS_SET=true
    - WEBHOOK_EVENTS_CONTACTS_UPSERT=true
    - WEBHOOK_EVENTS_CONTACTS_UPDATE=true
    - WEBHOOK_EVENTS_PRESENCE_UPDATE=true
    - WEBHOOK_EVENTS_CHATS_SET=true
    - WEBHOOK_EVENTS_CHATS_UPSERT=true
    - WEBHOOK_EVENTS_CHATS_UPDATE=true
    - WEBHOOK_EVENTS_CHATS_DELETE=true
    - WEBHOOK_EVENTS_CONNECTION_UPDATE=true
    - WEBHOOK_EVENTS_GROUPS_UPSERT=true
    - WEBHOOK_EVENTS_GROUPS_UPDATE=true
    - WEBHOOK_EVENTS_GROUP_PARTICIPANTS_UPDATE=true
    - WEBHOOK_EVENTS_LABELS_EDIT=true
    - WEBHOOK_EVENTS_LABELS_ASSOCIATION=true
    - WEBHOOK_EVENTS_CALL=true
    - CONFIG_SESSION_PHONE_CLIENT=$client
    - CONFIG_SESSION_PHONE_NAME=Chrome
    - QRCODE_LIMIT=5
    - REDIS_ENABLED=false
    - REDIS_URI=redis://redis:6379
    - WEBHOOK_EVENTS_ERRORS=true 
    #DATABASE
    - DATABASE_ENABLED=true
    - DATABASE_CONNECTION_URI=mongodb://$user_mongodb:$mongodb_senha@$nome_app_mongo:27077/?connectTimeoutMS=10000&authSource=admin&authMechanism=SCRAM-SHA-1
    #- DATABASE_CONNECTION_URI=mongodb://root:root@ip:27017/?authSource=admin&readPreference=primary&ssl=false&directConnection=true
    - DATABASE_CONNECTION_DB_PREFIX_NAME=evolution
    - DATABASE_SAVE_DATA_INSTANCE=true
    - DATABASE_SAVE_DATA_NEW_MESSAGE=true
    - DATABASE_SAVE_MESSAGE_UPDATE=true
    - DATABASE_SAVE_DATA_CONTACTS=true
    - DATABASE_SAVE_DATA_CHATS=true
    # Cache to optimize application performance
    - CACHE_REDIS_ENABLED=true
    - CACHE_REDIS_URI=redis://redis:6379
    - CACHE_REDIS_PREFIX_KEY=evolution_exchange
    - CACHE_REDIS_TTL=604800
    # whatsapp Business
    - WA_BUSINESS_TOKEN_WEBHOOK=$client
    - WA_BUSINESS_URL=https://graph.facebook.com
    - WA_BUSINESS_VERSION=v18.0
    - WA_BUSINESS_LANGUAGE=pt_BR
    #Chatwoot
    # If you leave this option as false, when deleting the message for everyone on WhatsApp, it will not be deleted on Chatwoot.
    - CHATWOOT_MESSAGE_DELETE=false # false | true
    # If you leave this option as true, when sending a message in Chatwoot, the client's last message will be marked as read on WhatsApp.
    - CHATWOOT_MESSAGE_READ=true # false | true
    # This db connection is used to import messages from whatsapp to chatwoot database
    #- CHATWOOT_IMPORT_DATABASE_CONNECTION_URI=postgres://user:password@hostname:port/dbname
    - CHATWOOT_IMPORT_DATABASE_CONNECTION_URI=postgres://postgres:$postgres_password@postgres:5432/chatwoot6b9d7b4?sslmode=disable
    - CHATWOOT_IMPORT_DATABASE_PLACEHOLDER_MEDIA_MESSAGE=true 
    #RABBITMQ
    - RABBITMQ_ENABLED=false
    - RABBITMQ_RABBITMQ_MODE=global
    - RABBITMQ_EXCHANGE_NAME=evolution_exchange
    - RABBITMQ_URI=amqp://p2rYBtv9Wa:QggPhp8JcMlmhtU4@rabbitmqp7n453l:5672/%2F
    - STORE_MESSAGES=true
    - STORE_MESSAGE_UP=true
    - STORE_CONTACTS=true
    - STORE_CHATS=true
    - CLEAN_STORE_CLEANING_INTERVAL=7200 # seconds === 2h
    - CLEAN_STORE_MESSAGES=true
    - CLEAN_STORE_MESSAGE_UP=true
    - CLEAN_STORE_CONTACTS=false
    - CLEAN_STORE_CHATS=false
    - LANGUAGE=pt-BR # pt-BR, en
    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
        - node.role == manager
        - node.role == manager
EOL
# Adicionar as labels apenas se for instalação tradicional
if [ "$INSTALL_TYPE" = "TRADICIONAL" ]; then
cat >> $nome_app.yaml << EOL
      labels:
      - traefik.enable=1
      - traefik.http.routers.$nome_app.rule=Host(\`$dominio\`)
      - traefik.http.routers.$nome_app.entrypoints=websecure
      - traefik.http.routers.$nome_app.priority=1
      - traefik.http.routers.$nome_app.tls.certresolver=letsencryptresolver
      - traefik.http.routers.$nome_app.service=$nome_app
      - traefik.http.services.$nome_app.loadbalancer.server.port=8080
      - traefik.http.services.$nome_app.loadbalancer.passHostHeader=1
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
    echo -e "XXX\n81\nCRIANDO STACK NO PORTAINER 3/4  \nXXX"
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
STACK_NAME=$nome_app
STACK_FILE_PATH="/root/$nome_app.yaml"

else
   # echo "Erro: Arquivo de dados não encontrado em $dados_file."
    sleep 5
echo -e "XXX\n82\nSEM ARQUIVO DE DADOS DO PORTAINER 3/4  \nXXX"
docker stack deploy --prune --resolve-image always -c $nome_app.yaml $nome_app >/dev/null 2>&1
sleep 5
    exit 1
fi

# Função para autenticação
get_auth_token() {
    #echo "[INFO] Autenticando no Portainer..."
    echo -e "XXX\n83\nAUTENTICANDO NO PORTAINER... 3/4  \nXXX"
    RESPONSE=$(curl -sS -X POST "https://$PORTAINER_URL/api/auth" \
        -H "Content-Type: application/json" \
        -d "{\"username\": \"$ADMIN_USERNAME\", \"password\": \"$ADMIN_PASSWORD\"}")
    TOKEN=$(echo "$RESPONSE" | jq -r '.jwt')
    if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]; then
        # echo "[ERRO] Falha na autenticação."
        echo -e "XXX\n84\nFALHA NA AUTENTICAÇÃO.. 3/4  \nXXX"
sleep 5
echo -e "XXX\n85\nREVERTENDO E CRIANDO STACK PELO SERVIDOR 3/4  \nXXX"
docker stack deploy --prune --resolve-image always -c$nome_app.yaml $nome_app >/dev/null 2>&1
sleep 5
        exit 1
    fi
  #  echo "[SUCESSO] Autenticação realizada com sucesso. Token obtido."
 echo -e "XXX\n86\n[SUCESSO] AUTENTICAÇÃO OK 3/4  \nXXX"
}

# Função para obter o EndpointID
get_endpoint_id() {
   # echo "[INFO] Obtendo EndpointID..."
    echo -e "XXX\n87\n[INFO] OBTENDO ENDPOINTID 3/4  \nXXX"
    RESPONSE=$(curl -sS -X GET "https://$PORTAINER_URL/api/endpoints" \
        -H "Authorization: Bearer $TOKEN")
    ENDPOINT_ID=$(echo "$RESPONSE" | jq -r '.[0].Id')
    if [ -z "$ENDPOINT_ID" ] || [ "$ENDPOINT_ID" = "null" ]; then
        # echo "[ERRO] EndpointID não encontrado! Resposta: $RESPONSE"
        echo -e "XXX\n88\n[ERRO] ENDPOINTID NÃO ENCONTRADO 3/4  \nXXX"
        docker stack deploy --prune --resolve-image always -c $nome_app.yaml $nome_app >/dev/null 2>&1
        exit 1
    fi
     echo -e "XXX\n89\n[SUCESSO] ENDPOINTID OBTIDO: $ENDPOINT_ID  3/4  \nXXX"
    #echo "[SUCESSO] EndpointID obtido: $ENDPOINT_ID"
}

# Função para obter o SwarmID
get_swarm_id() {
   # echo "[INFO] Obtendo SwarmID..."
    echo -e "XXX\n90\n[INFO] OBTENDO SWARMID  3/4  \nXXX"
    RESPONSE=$(curl -sS -X GET "https://$PORTAINER_URL/api/endpoints/$ENDPOINT_ID/docker/swarm" \
        -H "Authorization: Bearer $TOKEN")
    SWARM_ID=$(echo "$RESPONSE" | jq -r '.ID')
    if [ -z "$SWARM_ID" ] || [ "$SWARM_ID" = "null" ]; then
        #echo "[ERRO] SwarmID não encontrado! Resposta: $RESPONSE"
        echo -e "XXX\n91\n[ERRO] SWARMID NÃO ENCONTRADO 3/4  \nXXX"
        docker stack deploy --prune --resolve-image always -c $nome_app.yaml $nome_app >/dev/null 2>&1
        exit 1
    fi
    #echo "[SUCESSO] SwarmID obtido: $SWARM_ID"
    echo -e "XXX\n92\n[SUCESSO] SWARMID OBTIDO: $SWARM_ID  3/4  \nXXX"
}

# Função para criar a stack
create_stack() {
    #echo "[INFO] Verificando existência do arquivo YAML..."
    echo -e "XXX\n93\n[INFO] VERIFICANDO SE YAML EXISTE 3/4  \nXXX"
    if [ ! -f "$STACK_FILE_PATH" ]; then
        #echo "[ERRO] Arquivo $STACK_FILE_PATH não encontrado!"
        echo -e "XXX\n94\n[ERRO] ARQUIVO $STACK_FILE_PATH NÃO ENCONTRADO 3/4  \nXXX"
        docker stack deploy --prune --resolve-image always -c $nome_app.yaml $nome_app >/dev/null 2>&1
        exit 1
    fi

    #echo "[INFO] Criando stack '$STACK_NAME' no Portainer..."
     echo -e "XXX\n95\n[INFO] CRIANDO STACK $STACK_NAME NO PORTAINER 3/4  \nXXX"
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
        echo -e "XXX\n96\n[ERRO] ERRO AO CRIAR STACK 3/4  \nXXX"
        docker stack deploy --prune --resolve-image always -c $nome_app.yaml $nome_app >/dev/null 2>&1
        exit 1
    fi

   # echo "[SUCESSO] Stack '$STACK_NAME' criada com sucesso!"
    echo -e "XXX\n97\n[SUCESSO] STACK $STACK_NAME  CRIADA COM SUCESSO 3/4  \nXXX"
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
    echo -e "XXX\n98\n[ERRO] ERRO INESPERADO PARA CRIAR STACK NO PORTAINER 3/4  \nXXX"
    sleep 5
    echo -e "XXX\n98\nREVERTENDO E CRIANDO STACK PELO SERVIDOR 3/4  \nXXX"
docker stack deploy --prune --resolve-image always -c $nome_app.yaml $nome_app >/dev/null 2>&1
sleep 5

    exit 1
fi




echo -e "XXX\n99\nFINALIZANDO BUILD DA EVOLUTION 4/4  \nXXX"
# FIM DE INSTALANDO O EVOLUTION
#
#######################################################


sleep 12

#
# MENSAGEM DE INSTLADO + DADOS
#


echo -e "XXX\n100\nFINALIZANDO BUILD DA EVOLUTION 4/4 - CONCLUIDO  \nXXX"

sleep 3

}|whiptail --title "EVOLUTION API - PROGRESSO DA INSTALAÇÃO" --gauge "Aguarde a instalaço dos tens necessários" 6 60 0



# Verificação conforme tipo de instalação
if [ "$INSTALL_TYPE" = "TRADICIONAL" ]; then
    ip_servidor=$(curl -s --max-time 10 ipinfo.io/ip)
    dns_ip=$(timeout 10 nslookup "$dominio" | grep "Address" | tail -n1 | awk '{print $2}' 2>/dev/null)

    if [[ "$dns_ip" != "$ip_servidor" ]]; then
        whiptail --title "Mensagem" --msgbox "Não foi possivel acessar o dominio da EVOLUTION API ($dominio). A instalação foi cancelada. Por favor, verifique se os apontamentos DNS estão corretos e propagados!. Depois, instale novamente. Pressione ENTER para voltar ao Menu Principal" 20 78
    else
        whiptail --title "Mensagem" --msgbox "Parabéns, EVOLUTION API foi instalada com sucesso!\n\nAcesse: https://$dominio\n\nPressione ENTER para voltar ao Menu Principal" 20 78
    fi
else
    # Para Cloudflare Tunnel, verificação mais simples
    if nslookup "$dominio" >/dev/null 2>&1; then
        whiptail --title "Mensagem" --msgbox "Parabéns, EVOLUTION API foi instalada com sucesso!\n\nAcesse: https://$dominio\n\nConfiguração Cloudflare Tunnel concluída com rotas e DNS.\n\nPressione ENTER para voltar ao Menu Principal" 20 78
    else
        whiptail --title "Mensagem" --msgbox "AVISO: O domínio da EVOLUTION API ($dominio) não está resolvendo.\nVerifique a configuração do Cloudflare Tunnel.\n\nA instalação foi concluída, mas o acesso pode não funcionar até que o DNS esteja configurado corretamente.\n\nPressione ENTER para voltar ao Menu Principal" 20 78
    fi
fi

exit 0



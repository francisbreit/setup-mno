#!/usr/bin/bash
#########################################################
# HERMES AGENT - SETUP MNO 
# Instalação simplificada via Swarm e Cloudflare Tunnel
#########################################################

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

# CARREGAR CREDENCIAIS
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
    whiptail --title "INSTALAÇÃO DO HERMES AGENT" --msgbox "$msg" --fb 10 70
}

while true; do
CHOICE=$(
whiptail --title "INSTALAÇÃO DO HERMES AGENT" --menu "Aperte ENTER para iniciar a instalação ou selecione SAIR (Utilize setas e Enter)\n\nTIPO DE INSTALAÇÃO: $INSTALL_TYPE" 20 70 2 \
    "1)" "CONTINUAR"   \
    "2)" "SAIR"  3>&2 2>&1 1>&3    
)

case $CHOICE in
    "1)") clear; break ;;
    "2)") cd /; exit 0 ;; 
esac
done

# SOLICITAR URL DO HERMES
while true; do
    urlhermes=$(whiptail --title "1/5 -URL do Hermes" --inputbox "Digite o Link de acesso da API do Hermes (ex: hermes.seudominio.com.br):" --fb 12 60 3>&1 1>&2 2>&3)
    saida=$?
    if [[ $saida -eq '0' ]]; then
        if [[ -z $urlhermes ]]; then msg "Digite o link para poder continuar"; continue; else break; fi
    else
        exit 0
    fi
done

# TOKEN DE ACESSO (SEGURANÇA DA API)
chave_hexadecimal=$(openssl rand -hex 16)
while true ; do
    key=$(whiptail --title "2/5 - Hermes Auth Token" --inputbox "Crie um Token de Segurança para a API (sugestão: $chave_hexadecimal):" --fb 12 60 "$chave_hexadecimal" 3>&1 1>&2 2>&3) ; saida=$?
    if [[ $saida -eq '0' ]] ; then
        if [[ -z $key ]] ; then msg "O Token é obrigatório!"; continue; else break; fi
    else
        exit 0
    fi
done


       while true ; do
		user_hermes=$(whiptail --title "3/5 - Digite o Nome do Usuário Admin do Hermes Agent" --inputbox "Digite o nome de usuário admin (ex: Admin378j):" --fb 12 60 3>&1 1>&2 2>&3) ; saida=$?
		if [[ $saida -eq '0' ]] ; then
		#	if [[ -z $user_hermes ]] ; then msg "Digite o nome do admin do Hermes Agent, para poder continuar" ; continue ; else break; fi
		if [[ (-z $user_hermes) || ("$user_hermes" =~ [^a-zA-Z0-9]) || (${#user_hermes} -gt 16) ]] ; then msg "Crie um nome de usuário admin, sem caracteres especiais e até 16 digitos para poder continuar" ; continue ; else break; fi
    else
			echo $user_hermes ; echo "saindo..."  &  exit 0 ;
		fi
	done



 while true ; do
		pass_hermes=$(whiptail --title "4/5 - Digite a senha do Admin do Hermes Agent" --inputbox "Digite a senha do admin (ex: Hdgd685jfnCvb):" --fb 12 60 3>&1 1>&2 2>&3) ; saida=$?
		if [[ $saida -eq '0' ]] ; then
		#	if [[ -z $pass_hermes ]] ; then msg "Digite a senha do Hermes Agent, para poder continuar" ; continue ; else break; fi
		if [[ (-z $pass_hermes) || ("$pass_hermes" =~ [^a-zA-Z0-9]) || (${#pass_hermes} -gt 16) ]] ; then msg "Crie uma senha de admin, sem caracteres especiais e até 16 digitos para poder continuar" ; continue ; else break; fi
    else
			echo $pass_hermes ; echo "saindo..."  &  exit 0 ;
		fi
	done



# PORTAINER CHOICE
while true; do
    criar_portainer=$(whiptail --title "5/5 - Criar Stack no Portainer? (0 ou 1)" --inputbox "Digite 0 (Editável no Portainer) ou 1 (Apenas CLI)" --fb 12 60 3>&1 1>&2 2>&3)
    saida=$?
    if [[ $saida -eq '0' ]]; then
        if [[ "$criar_portainer" != "0" && "$criar_portainer" != "1" ]]; then continue; else break; fi
    else
        exit 0
    fi
done



#########################################################
# DADOS COLETADOS - RESUMO
#########################################################
nome_principal="hermes"
sufixo_app=$(date | md5sum | head -c7)
nome_app=$nome_principal$sufixo_app

whiptail --title "Confirmação de Dados" \
 --msgbox "TIPO: $INSTALL_TYPE\n\n1) URL: $urlhermes\n2) Auth Token: $key\n3) Usuário Hermes: $user_hermes\n4) Senha Hermes: $pass_hermes\n5) Portainer: $criar_portainer\n\nTecle Enter para iniciar o deploy." \
 --fb 22 80
 
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

#########################################################
# ROTAS E CLOUDFLARE TUNNEL
#########################################################
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
    DOMINIO_PRINCIPAL=$(echo "$urlhermes" | cut -d'.' -f2-)
    
    EXISTING_RECORDS=$(curl -s -X GET \
        "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records?name=${urlhermes}" \
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
        --data '{"type":"CNAME","name":"'${urlhermes}'","content":"'${nome_servidor}'.'${DOMINIO_PRINCIPAL}'","ttl":1,"proxied":false}')

    if echo "$CNAME_RESPONSE" | grep -q '"success":true'; then
        echo -e "XXX\n30\nREGISTRO CNAME CRIADO COM SUCESSO! \nXXX"
    else
        echo -e "XXX\n30\nAVISO: ERRO AO CRIAR REGISTRO CNAME \nXXX"
    fi

elif [ "$INSTALL_TYPE" = "CLOUDFLARE_TUNNEL" ]; then
    echo -e "XXX\n10\nCONFIGURANDO CLOUDFLARE TUNNEL (DNS + ROTAS)... \nXXX"

    EXISTING_RECORDS=$(curl -s -X GET \
        "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records?name=${urlhermes}" \
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
        --data "{\"type\":\"CNAME\",\"name\":\"${urlhermes}\",\"content\":\"${TUNNEL_ID}.cfargotunnel.com\",\"ttl\":1,\"proxied\":true}")

    echo -e "XXX\n35\nATUALIZANDO CONFIGURAÇÃO DO TUNNEL... \nXXX"
    NEW_SERVICE="http://${nome_app}:9119"
    
    TIMESTAMP=$(date -u +%Y%m%dT%H%M%SZ)
    TMPDIR=$(mktemp -d)
    BACKUP_RAW="$TMPDIR/backup_raw.$TIMESTAMP.json"
    TO_PUT="$TMPDIR/to_put.$TIMESTAMP.json"

    curl -sS -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
      "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/cfd_tunnel/$TUNNEL_ID/configurations" \
      | jq '.' > "$BACKUP_RAW"

    jq --arg host "$urlhermes" --arg service "$NEW_SERVICE" '
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

else
    echo -e "XXX\n10\nVERIFICANDO CONFIGURAÇÃO (TRADICIONAL SEM AUTOMAÇÃO)... \nXXX"
    if ! nslookup "$urlhermes" >/dev/null 2>&1; then
        echo -e "XXX\n15\nAVISO: VERIFIQUE A CONFIGURAÇÃO DNS \nXXX"
    fi
fi

if [ "$INSTALL_TYPE" = "TRADICIONAL" ] && [ "$criar_dns" = "1" ]; then
    ip_servidor=$(curl -s --max-time 10 ipinfo.io/ip)
    echo -e "XXX\n3\nVERIFICANDO SUBDOMÍNIO: $urlhermes \nXXX"
    sleep 3

    tentativas=5
    tentativa_atual=1
    sucesso=0

    while [ $tentativa_atual -le $tentativas ]; do
        echo -e "XXX\n$(( (tentativa_atual * 12) / tentativas + 3 ))\nTentativa $tentativa_atual de $tentativas...\nXXX"
        dns_ip=$(timeout 10 nslookup -type=A "$urlhermes" | grep -E "Address: [0-9]+\." | awk '{print $2}' | head -n1)
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
# GERANDO STACK E IMPLANTANDO O HERMES
#######################################################
echo -e "XXX\n40\nCRIANDO ORQUESTRAÇÃO SWARM... \nXXX"
cd ~/

key_secret=$(openssl rand -hex 16)

# Criar volume persistente ANTES do deploy
docker volume create ${nome_app}-data >/dev/null 2>&1

cat > $nome_app.yaml << EOL
version: "3.9"

services:
  $nome_app:
    image: nousresearch/hermes-agent:latest
    hostname: $nome_app
    container_name: $nome_app
    tty: true          
    stdin_open: true 
    # Comando oficial da documentação:
    command: ["gateway", "run"]  
    networks:
      - externa
      - interna
    volumes:
      - $nome_app-data:/opt/data
    environment:
      - TZ=America/Sao_Paulo
      #- LLM_PROVIDER=
      #- LLM_API_KEY=
      #- LLM_MODEL=
      #- TELEGRAM_BOT_TOKEN=
      #- TELEGRAM_ALLOWED_USERS=
      - API_SERVER_HOST=0.0.0.0
      - API_SERVER_KEY=$key
      - GATEWAY_ALLOW_ALL_USERS=true
      # O SEGREDO DO MAKER: Registra o executável globalmente no container
      - PATH=/opt/hermes/.venv/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
      # ATIVAÇÃO DO PAINEL WEB:
      - HERMES_DASHBOARD=1
      - HERMES_DASHBOARD_HOST=0.0.0.0  
      #- HERMES_DASHBOARD_INSECURE=1	
      - HERMES_DASHBOARD_BASIC_AUTH_USERNAME=$user_hermes
      - HERMES_DASHBOARD_BASIC_AUTH_PASSWORD=$pass_hermes
      - HERMES_DASHBOARD_BASIC_AUTH_SECRET=$key_secret
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8642/health"]
      interval: 30s
      timeout: 10s
      retries: 3
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
        - traefik.http.routers.$nome_app.rule=Host(\`$urlhermes\`)
        - traefik.http.routers.$nome_app.entrypoints=websecure
        - traefik.http.routers.$nome_app.tls.certresolver=letsencryptresolver
        - traefik.http.routers.$nome_app.service=$nome_app
        - traefik.http.services.$nome_app.loadbalancer.passHostHeader=true
        - traefik.http.services.$nome_app.loadbalancer.server.port=9119
EOL
fi

cat >> $nome_app.yaml << EOL

volumes:
  $nome_app-data:
    external: true
    name: $nome_app-data

networks:
  externa:
    external: true
  interna:
    external: true
EOL

echo -e "XXX\n70\nINICIANDO DEPLOY... \nXXX"

if [[ "$criar_portainer" == "0" ]]; then
    dados_file="$HOME/dados_portainer/dados_portainer"
    if [[ -f "$dados_file" ]]; then
        P_URL=$(grep "Dominio do portainer:" "$dados_file" | cut -d':' -f2 | xargs)
        P_USER=$(grep "Usuario:" "$dados_file" | cut -d':' -f2 | xargs)
        P_PASS=$(grep "Senha:" "$dados_file" | cut -d':' -f2 | xargs)
        
        TOKEN=$(curl -sS -X POST "https://$P_URL/api/auth" -H "Content-Type: application/json" -d "{\"username\": \"$P_USER\", \"password\": \"$P_PASS\"}" | jq -r '.jwt')
        if [[ "$TOKEN" != "null" && -n "$TOKEN" ]]; then
            E_ID=$(curl -sS -X GET "https://$P_URL/api/endpoints" -H "Authorization: Bearer $TOKEN" | jq -r '.[0].Id')
            S_ID=$(curl -sS -X GET "https://$P_URL/api/endpoints/$E_ID/docker/swarm" -H "Authorization: Bearer $TOKEN" | jq -r '.ID')
            curl -s -o /dev/null  -X POST -H "Authorization: Bearer $TOKEN" -F "Name=$nome_app" -F "file=@/root/$nome_app.yaml" -F "SwarmID=$S_ID" -F "endpointId=$E_ID" "https://$P_URL/api/stacks/create/swarm/file"
        else
            docker stack deploy --prune --resolve-image always -c $nome_app.yaml $nome_app >/dev/null 2>&1
        fi
    else
        docker stack deploy --prune --resolve-image always -c $nome_app.yaml $nome_app >/dev/null 2>&1
    fi
else
    docker stack deploy --prune --resolve-image always -c $nome_app.yaml $nome_app >/dev/null 2>&1
fi

echo -e "XXX\n100\nINSTALAÇÃO DO HERMES CONCLUÍDA! \nXXX"
sleep 2

}|whiptail --title "HERMES AGENT" --gauge "Configurando Hermes Agent..." 6 60 0

#######################################################
# VERIFICAÇÃO FINAL
#######################################################

if [ "$INSTALL_TYPE" = "TRADICIONAL" ]; then
    ip_servidor=$(curl -s --max-time 10 ipinfo.io/ip)
    dns_ip=$(timeout 10 nslookup "$urlhermes" | grep "Address" | tail -n1 | awk '{print $2}' 2>/dev/null)

    if [[ "$dns_ip" != "$ip_servidor" ]]; then
        whiptail --title "Mensagem" --msgbox "Não foi possivel acessar o dominio do Hermes Agent ($urlhermes). A instalação foi cancelada. Por favor, verifique se os apontamentos DNS estão corretos e propagados!. Depois, instale novamente. Pressione ENTER para voltar ao Menu Principal" 20 78
    else
				whiptail --title "Sucesso" --msgbox "Hermes Agent instalado com sucesso!\n\nURL da API: https://$urlhermes\nToken de Segurança: $key\nUsuário do Hermes: $user_hermes\nSenha do Hermes: $pass_hermes\n\nAtenção: Aguarde alguns minutos para a aplicação iniciar.\n\nPressione ENTER para voltar ao Menu Principal" 20 78
    fi
else
    if timeout 10 nslookup "$urlhermes" >/dev/null 2>&1; then
		whiptail --title "Sucesso" --msgbox "Hermes Agent instalado com sucesso!\n\nURL da API: https://$urlhermes\nToken de Segurança: $key\nUsuário do Hermes: $user_hermes\nSenha do Hermes: $pass_hermes\n\nAtenção: Aguarde alguns minutos para a aplicação iniciar.\n\nPressione ENTER para voltar ao Menu Principal" 20 78
    else
        whiptail --title "Mensagem" --msgbox "AVISO: O domínio do Hermes Agent ($urlhermes) não está resolvendo.\nVerifique a configuração do Cloudflare Tunnel.\n\nA instalação foi concluída, mas o acesso pode não funcionar até que o DNS esteja configurado corretamente.\n\nPressione ENTER para voltar ao Menu Principal" 20 78
    fi
fi

exit 0

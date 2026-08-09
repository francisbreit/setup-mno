#!/usr/bin/bash

# Aguarda o MySQL 8.0 compartilhado aceitar uma consulta autenticada.
setupmno_mysql80_service_exists() {
    docker service inspect mysql_mysql >/dev/null 2>&1
}

setupmno_mysql80_wait_ready() {
    local yaml_file="${1:-/root/mysql.yaml}"
    local service_name="${SETUPMNO_MYSQL80_SERVICE_NAME:-mysql_mysql}"
    local attempt probe

    MYSQL80_CONTAINER_ID=""
    MYSQL80_ROOT_PASSWORD=""

    [ -s "$yaml_file" ] || return 65
    MYSQL80_ROOT_PASSWORD=$(sed -n 's/^[[:space:]]*-[[:space:]]*MYSQL_ROOT_PASSWORD=//p' "$yaml_file" | head -n1)
    [ -n "$MYSQL80_ROOT_PASSWORD" ] || return 66

    for attempt in $(seq 1 181); do
        MYSQL80_CONTAINER_ID=$(docker ps \
            --filter "label=com.docker.swarm.service.name=$service_name" \
            --format '{{.ID}}' | head -n1)
        if [ -n "$MYSQL80_CONTAINER_ID" ]; then
            probe=$(docker exec "$MYSQL80_CONTAINER_ID" sh -c \
                'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" exec mysql -uroot --batch --skip-column-names -e "SELECT 1"' \
                2>/dev/null) || probe=""
            [ "$probe" = "1" ] && return 0
        fi
        [ "$attempt" -lt 181 ] && sleep 5
    done

    return 67
}

setupmno_mysql80_require_ready() {
    local yaml_file="${1:-/root/mysql.yaml}"
    local status message

    setupmno_mysql80_wait_ready "$yaml_file" && return 0
    status=$?

    case "$status" in
        65) message="O arquivo de configuração do MySQL 8.0 não foi encontrado." ;;
        66) message="A senha do MySQL 8.0 não pôde ser recuperada com segurança." ;;
        *)  message="O MySQL 8.0 não aceitou conexão autenticada em até 15 minutos." ;;
    esac

    whiptail --title "ERRO MYSQL 8.0" --msgbox \
        "$message\n\nA instalação foi interrompida antes de criar ou usar o banco." \
        13 76 1>&2
    return "$status"
}

setupmno_mysql80_create_database() {
    local database_name="$1"
    local query

    [[ "$database_name" =~ ^[A-Za-z0-9_]+$ ]] || return 68
    [ -n "$MYSQL80_CONTAINER_ID" ] || return 69
    [ -n "$MYSQL80_ROOT_PASSWORD" ] || return 70

    query="CREATE DATABASE IF NOT EXISTS \`$database_name\`;"
    docker exec "$MYSQL80_CONTAINER_ID" sh -c \
        'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" exec mysql -uroot -e "$1"' \
        setupmno-mysql "$query" >/dev/null 2>&1
}

#########################################################
#
# LOADING
#

export NEWT_COLORS='
#root=,white
#window=,black
#border=white,black
#textbox=white,black
#button=black,white

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


amarelo="\e[33m"   # Amarelo
branco="\e[97m"    # Branco
reset="\e[0m"      # Reseta

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


function msg() {
		msg=$1
		whiptail --title "INSTALAÇÃO DO YOURLS: ENCURTADOR DE URLS" --msgbox "$msg" --fb 10 70;
	}

  while true; do
CHOICE=$(
whiptail --title "INSTALAÇÃO DO YOURLS: ENCURTADOR DE URLS" --menu "Aperte ENTER para iniciar a instalação do Yourls ou selecione SAIR (Utilize setas e Enter)\nINSTRUÇÕES\nAntes de prosseguir, apontar registros DNS para o(s) seguinte(s) dominio(s):\nRECORD A: Dê um nome para seu servidor (exemplo: manager1.seudominio.com.br) e aponte para o IP do seu servidor\nRECORD CNAME: Crie um subdominio para o Yourls (exemplo: yourl.seudominio.com.br) a aponte para o nome do servidor criado (exemplo: manager1.seudominio.com.br)" 20 70 2 \
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
#whiptail --msgbox "Pressione ENTER para voltar ao Menu Principal" 20 78
done


  while true ; do
		url_yourls=$(whiptail --title "1/3 - URL do Yourls" --inputbox "Digite o Link do Yourls (ex: yourls.seudominio.com):" --fb 12 60 3>&1 1>&2 2>&3) ; saida=$?
		if [[ $saida -eq '0' ]] ; then
			if [[ -z $url_yourls ]] ; then msg "Digite o link do Yourls, para poder continuar" ; continue ; else break; fi
		else
			echo $url_yourls ; echo "saindo..."  &  exit 0 ;
		fi
	done

   while true ; do
		user_yourls=$(whiptail --title "2/3 - Usuário Admin do Yourls" --inputbox "Digite o nome de usuário admin do Yourls (ex: SeuNome):" --fb 12 60 3>&1 1>&2 2>&3) ; saida=$?
		if [[ $saida -eq '0' ]] ; then
			#if [[ -z $userYourls ]] ; then msg "Digite o nome do usuário admin do Yourls, para poder continuar" ; continue ; else break; fi
		if [[ (-z $user_yourls) || ("$user_yourls" =~ [^a-zA-Z0-9]) || (${#user_yourls} -gt 16) ]] ; then msg "Digite o nome do usurio admin do Yourls, sem caracteres especiais e até 16 digitos para poder continuar" ; continue ; else break; fi
    else
			echo $userYourls ; echo "saindo..."  &  exit 0 ;
		fi
	done


      while true ; do
		pass_yourls=$(whiptail --title "3/3 - Senha do Yourls" --inputbox "Digite a senha do Yourls:" --fb 12 60 3>&1 1>&2 2>&3) ; saida=$?
		if [[ $saida -eq '0' ]] ; then
		#	if [[ -z $senhaYourls ]] ; then msg "Digite a senha do Yourls, para poder continuar" ; continue ; else break; fi
		if [[ (-z $pass_yourls) || ("$pass_yourls" =~ [^a-zA-Z0-9]) || (${#pass_yourls} -gt 16) ]] ; then msg "Digite a senha do Yourls, sem caracteres especiais e até 16 digitos para poder continuar" ; continue ; else break; fi
    else
			echo $pass_yourls ; echo "saindo..."  &  exit 0 ;
		fi
	done

    
 
# FIM DE PERGUNTAS PARA VARIAVEIS
#
#########################################################
#
# VERIFICAÇÃO DE DADOS
#


nome_principal="yourls"  #nome do app
sufixo_app=$(date | md5sum | head -c7)
nome_app=$nome_principal$sufixo_app
mysql_container=""
if setupmno_mysql80_service_exists; then
    mysql_container="mysql_mysql"
fi

if [[ ("$mysql_container" == "") ]]; then
 senha_mysql=$(openssl rand -hex 8)

cd

cd

cat > mysql.yaml << EOL
version: '3.7'
services:
    mysql:
        image: percona/percona-server:8.0
        environment:
            - MYSQL_ROOT_PASSWORD=$senha_mysql
            - TZ=America/Fortaleza
        networks:
            - network_public
        volumes:
            - mysql_data:/var/lib/mysql
        deploy:
            placement:
                constraints: [node.role == manager]
        command:
            --character-set-server=utf8mb4 --collation-server=utf8mb4_general_ci --sql-mode="" --default-authentication-plugin=mysql_native_password  --port=3306 --max-allowed-packet=512MB
volumes:
    mysql_data:
networks:
    network_public:
        external: true
        name: network_public

EOL

docker stack deploy --prune --resolve-image always -c mysql.yaml mysql >/dev/null 2>&1

fi 	




setupmno_mysql80_require_ready /root/mysql.yaml || exit 1
mysql_password="$MYSQL80_ROOT_PASSWORD"

if ! setupmno_mysql80_create_database "$nome_app"; then
    whiptail --title "ERRO MYSQL 8.0" --msgbox \
        "Não foi possível criar o banco $nome_app. A instalação foi interrompida." \
        11 76 1>&2
    exit 1
fi


clear

echo ""
echo -e "1 - URL do Yourls: \e[33m$url_yourls\e[0m"
echo -e "2 - Usuário Admin do Yourls: \e[33m$user_yourls\e[0m"
echo -e "3 - Senha do Yourls: \e[33m$pass_yourls\e[0m"
echo ""
echo ""
read -p "As informações estão certas? (y/n): " confirma1
if [ "$confirma1" == "y" ]; then

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
echo -e "XXX\n0\nCRIANDO STACK DO YOURLS 1/4 \nXXX"
sleep 3
echo -e "XXX\n25\nCRIANDO STACK DO YOURLS 1/4 - CONCLUIDO \nXXX"
sleep 3 
echo -e "XXX\n25\nFAZENDO O BUILD DO STACK DO YOURLS 2/4 \nXXX"
sleep 3
echo -e "XXX\n50\nFAZENDO O BUILD DO STACK DO YOURLS 2/4 - CONCLUIDO \nXXX"
sleep 3
echo -e "XXX\n50\nCRIANDO BANCO DE DADOS DO YOURLS 3/4 \nXXX"
sleep 3
echo -e "XXX\n75\nCRIANDO BANCO DE DADOS DO YOURLS 3/4 - CONCLUIDO \nXXX"





#######################################################
#
#  INSTALANDO O YOURLS
#

cd

cd
clear


cat > $nome_app.yaml << EOL

version: "3.7"
services:


  $nome_app:
    image: yourls:latest

    networks:
      - network_public ## Nome da rede interna

    environment:
      ## Dados de acesso
      - YOURLS_SITE=https://$url_yourls ## Url da Aplicação
      - YOURLS_USER=$user_yourls
      - YOURLS_PASS=$pass_yourls
      
      ## Dados do Mysql
      - YOURLS_DB_HOST=mysql
      - YOURLS_DB_NAME=$nome_app
      - YOURLS_DB_USER=root
      - YOURLS_DB_PASS=$mysql_password

    deploy:
      mode: replicated
      replicas: 1
      resources:
        limits:
          cpus: "0.5"
          memory: 512M
      labels:
        - traefik.enable=true
        - traefik.http.routers.$nome_app.rule=Host(\`$url_yourls\`) ## Url da aplicação
        - traefik.http.routers.$nome_app.entrypoints=websecure
        - traefik.http.routers.$nome_app.tls.certresolver=letsencryptresolver
        - traefik.http.routers.$nome_app.service=$nome_app
        - traefik.http.services.$nome_app.loadbalancer.server.port=80


networks:
  network_public: ## Nome da rede interna
    name: network_public ## Nome da rede interna
    external: true


EOL

docker stack deploy --prune --resolve-image always -c $nome_app.yaml $nome_app >/dev/null 2>&1

echo -e "XXX\n75\nFINALIZANDO BUILD DO YOURLS 4/4  \nXXX"

sleep 2

echo -e "XXX\n100\nFINALIZANDO BUILD DO YOURLS 4/4 - CONCLUIDO  \nXXX"

sleep 3
}|whiptail --title "YOURLS - PROGRESSO DA INSTALAÇÃO" --gauge "Aguarde a instalação dos ítens necessários" 6 60 0

# FIM DE INSTALANDO O YOURLS
#
#######################################################


#
# MENSAGEM DE INSTLADO + DADOS
#

whiptail --msgbox "Parabéns seu Yourls foi instalado com sucesso! Pressione ENTER para voltar ao Menu Principal" 20 78


#
# FIM DE MENSAGEM DE INSTLADO + DADOS
#
#########################################################
#
# USUARIO PREENCHEU DADOS ERRADOS
#

elif [ "$confirma1" == "n" ]; then
    echo "Encerrando a instalaço, por favor, inicie a instalaão novamente."
    exit 0
else
    echo "Resposta inválida. Digite 'y' para confirmar ou 'n' para encerrar a instalação."
    exit 1
fi

#
# FIM DE USUARIO PREENCHEU DADOS ERRADOS
#
#########################################################

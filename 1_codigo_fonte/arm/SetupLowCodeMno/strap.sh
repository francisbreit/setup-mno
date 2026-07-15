#!/usr/bin/bash
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
		whiptail --title "INSTALAÇÃO DO STRAPI:" --msgbox "$msg" --fb 10 70;
	}

  while true; do
CHOICE=$(
whiptail --title "INSTALAÇÃO DO STRAPI:" --menu "Aperte ENTER para iniciar a instalação do STRAPI ou selecione SAIR (Utilize setas e Enter)\nINSTRUÇÕES\nAntes de prosseguir, apontar registros DNS para o(s) seguinte(s) dominio(s):\nRECORD A: Dê um nome para seu servidor (exemplo: manager1.seudominio.com.br) e aponte para o IP do seu servidor\nRECORD CNAME: Crie um subdominio para o STRAPI (exemplo: strapi.seudominio.com.br) a aponte para o nome do servidor criado (exemplo: manager1.seudominio.com.br)" 20 70 2 \
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
		url_strapi=$(whiptail --title "1/4 - URL do STRAPI" --inputbox "Digite o Link do STRAPI (ex: strapi.seudominio.com):" --fb 12 60 3>&1 1>&2 2>&3) ; saida=$?
		if [[ $saida -eq '0' ]] ; then
			if [[ -z $url_strapi ]] ; then msg "Digite o link do strapi, para poder continuar" ; continue ; else break; fi
		else
			echo $url_strapi ; echo "saindo..."  &  exit 0 ;
		fi
	done

  

    
 
# FIM DE PERGUNTAS PARA VARIAVEIS
#
#########################################################
#
# VERIFICAÇÃO DE DADOS
#


nome_principal="strapi"  #nome do app
sufixo_app=$(date | md5sum | head -c7)
nome_app=$nome_principal$sufixo_app
mysql_container=$(docker ps -qf name=mysql)

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




mysql_password=$(grep -oP '(?<=MYSQL_ROOT_PASSWORD=).+' /root/mysql.yaml)

# Identifica o ID do container do MySQL
container_id=$(docker ps -qf name=mysql)

# Cria o banco de dados usando a senha extraída
docker exec -i $container_id mysql -u root -p"$mysql_password" -e "CREATE DATABASE $nome_app;"

clear

echo ""
echo -e "URL do STRAPI: \e[33m$url_strapi\e[0m"
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
echo -e "XXX\n0\nCRIANDO STACK DO STRAPI 1/4 \nXXX"
sleep 3
echo -e "XXX\n25\nCRIANDO STACK DO STRAPI 1/4 - CONCLUIDO \nXXX"
sleep 3 
echo -e "XXX\n25\nFAZENDO O BUILD DO STACK DO STRAPI 2/4 \nXXX"
sleep 3
echo -e "XXX\n50\nFAZENDO O BUILD DO STACK DO STRAPI 2/4 - CONCLUIDO \nXXX"
sleep 3
echo -e "XXX\n50\nCRIANDO BANCO DE DADOS DO STRAPI 3/4 \nXXX"
sleep 3
echo -e "XXX\n75\nCRIANDO BANCO DE DADOS DO STRAPI 3/4 - CONCLUIDO \nXXX"





#######################################################
#
#  INSTALANDO O STRAPI
#

cd

cd
jwt_secret=$(openssl rand -hex 16)

admin_jwt=$(openssl rand -hex 16)

app_key=$(openssl rand -hex 16)

clear


cat > $nome_app.yaml << EOL

version: "3.7"
services:


  $nome_app-app:
    image: strapi/strapi

    volumes:
      - $nome_app-config:/srv/app/config
      - $nome_app-src:/srv/app/src
      - $nome_app-public_uploads:/srv/app/public/uploads
      - $nome_app-data:/srv/app

    networks:
      - network_public

    environment:
      ## Dados MySQL
      - DATABASE_CLIENT=mysql
      - DATABASE_HOST=mysql
      - DATABASE_NAME=$nome_app
      - DATABASE_PORT=3306
      - DATABASE_USERNAME=root
      - DATABASE_PASSWORD=$mysql_password

      ## Secret Keys
      - JWT_SECRET=$jwt_secret
      - ADMIN_JWT_SECRET=$admin_jwt
      - APP_KEYS=$app_key

      ## Outros dados
      - NODE_ENV=production
      - STRAPI_TELEMETRY_DISABLED=true

    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
          - node.role == manager
      labels:
        - traefik.enable=true
        - traefik.http.routers.$nome_app.rule=Host(\`$url_strapi\`)
        - traefik.http.routers.$nome_app.entrypoints=web,websecure
        - traefik.http.routers.$nome_app.tls.certresolver=letsencryptresolver
        - traefik.http.routers.$nome_app.service=$nome_app
        - traefik.http.services.$nome_app.loadbalancer.server.port=1337
        - traefik.http.services.$nome_app.loadbalancer.passHostHeader=true

volumes:
  $nome_app-config:
    external: true
    name: $nome_app-config
  $nome_app-src:
    external: true
    name: $nome_app-src
  $nome_app-public_uploads:
    external: true
    name: $nome_app-public_uploads
  $nome_app-data:
    external: true
    name: $nome_app-data


networks:
  network_public:
    external: true
    name: network_public


EOL

docker stack deploy --prune --resolve-image always -c $nome_app.yaml $nome_app >/dev/null 2>&1

echo -e "XXX\n75\nFINALIZANDO BUILD DO STRAPI 4/4  \nXXX"

sleep 2

echo -e "XXX\n100\nFINALIZANDO BUILD DO STRAPI 4/4 - CONCLUIDO  \nXXX"

sleep 3
}|whiptail --title "STRAPI - PROGRESSO DA INSTALAÇÃO" --gauge "Aguarde a instalação dos ítens necessários" 6 60 0

# FIM DE INSTALANDO O STRAPI
#
#######################################################


#
# MENSAGEM DE INSTLADO + DADOS
#

whiptail --msgbox "Parabéns seu STRAPI foi instalado com sucesso! Pressione ENTER para voltar ao Menu Principal" 20 78


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

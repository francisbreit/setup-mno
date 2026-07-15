#!/usr/bin/bash
#########################################################
#
#    LOADING
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
		whiptail --title "INSTALAÇÃO DO QUEPASA: WHATSAPP API" --msgbox "$msg" --fb 10 70;
	}

  while true; do
CHOICE=$(
whiptail --title "INSTALAÇÃO DO QUEPASA: WHATSAPP API" --menu "Aperte ENTER para iniciar a instalação do QUEPASA ou selecione SAIR (Utilize setas e Enter)\nINSTRUÇÕES\nAntes de prosseguir, apontar registros DNS para o(s) seguinte(s) dominio(s):\nRECORD A: Dê um nome para seu servidor (exemplo: manager1.seudominio.com.br) e aponte para o IP do seu servidor\nRECORDS CNAME: Crie subdominio para o Quepasa, apontando para o nome do servidor criado (exemplo: manager1.seudominio.com.br)" 20 70 2 \
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
#whiptail --msgbox "Pressione ENTER para voltar ao Menu Principal" 20 78
done


  while true ; do
		url_quepasa=$(whiptail --title "1/2 - URL do Quepasa" --inputbox "Digite o Link do Painel (ex: quepasa.seudominio.com):" --fb 12 60 3>&1 1>&2 2>&3) ; saida=$?
		if [[ $saida -eq '0' ]] ; then
			if [[ -z $url_quepasa ]] ; then msg "Digite o link do painel do Quepasa para poder continuar" ; continue ; else break; fi
		else
			echo $url_quepasa ; echo "saindo..."  &  exit 0 ;
		fi
	done

      while true ; do
		email_quepasa=$(whiptail --title "2/2 - Email do Quepasa" --inputbox "Digite o email (ex: email@seudominio.com):" --fb 12 60 3>&1 1>&2 2>&3) ; saida=$?
		if [[ $saida -eq '0' ]] ; then
			if [[ -z $email_quepasa ]] ; then msg "Digite email do Quepasa para poder continuar" ; continue ; else break; fi
		else
			echo $email_quepasa ; echo "saindo..."  &  exit 0 ;
		fi
	done

     
clear
#
# FIM DE NOME DO PROGRAMA
#
#########################################################

#########################################################
#
# VERIFICAÇÃO DE DADOS
#

nome_principal="quepasa"  #nome do app
sufixo_app=$(date | md5sum | head -c7)
nome_app=$nome_principal$sufixo_app


clear

echo ""
echo -e "URL do Quepasa: \e[33m$url_quepasa\e[0m"
echo -e "Email do Quepasa: \e[33m$email_quepasa\e[0m"
read -p "As informações estão certas? (y/n): " confirma1
if [ "$confirma1" == "y" ]; then

#
# FIM DE VERIFICAÇÃO DE DADOS
#
#########################################################
#
# MENSAGEM DE INSTALANDO
#

# MENSAGEM DE INSTALANDO
export NEWT_COLORS='
root=,white
window=,black
border=white,black
textbox=white,black
button=black,white
'  

CLEAR
{
echo -e "XXX\n0\nCRIANDO STACKS DO QUEPASA 1/4 \nXXX"
sleep 3
echo -e "XXX\n25\nCRIANDO STACKS DO QUEPASA 1/4 - CONCLUIDO \nXXX"
sleep 3 
echo -e "XXX\n25\nFAZENDO O BUILD DOS STACKS DO QUEPASA 2/4 \nXXX"
sleep 3
echo -e "XXX\n50\nFAZENDO O BUILD DOS STACKS DO QUEPASA 2/4 - CONCLUIDO \nXXX"
sleep 3
echo -e "XXX\n50\nINICIANDO BUILD DO QUEPASA 3/4 \nXXX"
sleep 3
echo -e "XXX\n75\nINICIANDO BUILD DO QUEPASA 3/4 - CONCLUIDO \nXXX"



#######################################################
#
#  INSTALANDO O QUEPASA
#

cd

cd
key_quepasa=$(openssl rand -hex 16)

clear


cat > $nome_app.yaml << EOL

version: "3.7"
services:

  $nome_app:
    image: deividms/quepasa:latest ## Imagem/versão do Quepasa
      
    volumes:
      - $nome_app-volume:/opt/quepasa

    networks:
      - network_public

    environment:
      ## Dados de acesso
      - DOMAIN=$url_quepasa

      ## Email Quepasa
      - EMAIL=$email_quepasa
      - QUEPASA_BASIC_AUTH_USER=$email_quepasa
      - QUEPASA_BASIC_AUTH_PASSWORD=$email_quepasa

      ## Titulo no celular
      - APP_TITLE=MNO ## Mude aqui o nome que vai aparecer no celular.

      ## TimeZone
      - TZ=America/Sao_Paulo

      ## Configurações para o WhatsApp
      - GROUPS=true
      - BROADCASTS=false
      - READRECEIPTS=forcedfalse
      - CALLS=true
      - READUPDATE=false
      - LOGLEVEL=DEBUG

      ## Configurações quepasa
      - QUEPASA_HOST_NAME=Quepasa
      - QUEPASA_MEMORY_LIMIT=4096M
      - WEBSOCKETSSL=true
      - REMOVEDIGIT9=true
      - SIGNING_SECRET=$key_quepasa

      ## Webhook
      #- WEBHOOK_QUEPASA=webhook.manual.com.br/webhook/quepasa
      #- WEBHOOK_TESTE_QUEPASA=n8n.manual.com.br/webhook-test/quepasa
            
      ## Portas
      - QUEPASA_EXTERNAL_PORT=31000
      - QUEPASA_INTERNAL_PORT=31000
      - WEBAPIPORT=31000

      ## Outras configurações
      - DEBUGREQUESTS=false
      - SYNOPSISLENGTH=500
      - METRICS_HOST=
      - METRICS_PORT=9392
      - MIGRATIONS=/builder/migrations
      - DEBUGJSONMESSAGES=false
      - HTTPLOGS=false

      ## WHATSMEOW SERVICE
      - WHATSMEOW_LOGLEVEL=WARN
      - WHATSMEOW_DBLOGLEVEL=WARN

      ## Env Mode
      - APP_ENV=production
      - NODE_ENV=production

    deploy:
      mode: replicated
      replicas: 1
      placement:
          constraints:
          - node.role == manager
      resources:
          limits:
              cpus: "2"
              memory: 2096M
                      
      labels:
        - traefik.enable=true
        - traefik.http.routers.$nome_app.rule=Host(\`$url_quepasa\`)
        - traefik.http.routers.$nome_app.tls=true
        - traefik.http.routers.$nome_app.entrypoints=web,websecure
        - traefik.http.routers.$nome_app.tls.certresolver=letsencryptresolver
        - traefik.http.routers.$nome_app.service=$nome_app
        - traefik.http.routers.$nome_app.priority=1      
        - traefik.http.middlewares.$nome_app.headers.SSLRedirect=true
        - traefik.http.middlewares.$nome_app.headers.STSSeconds=315360000
        - traefik.http.middlewares.$nome_app.headers.browserXSSFilter=true
        - traefik.http.middlewares.$nome_app.headers.contentTypeNosniff=true
        - traefik.http.middlewares.$nome_app.headers.forceSTSHeader=true
        - traefik.http.middlewares.$nome_app.headers.SSLHost=\${QUEPASA_HOST}
        - traefik.http.middlewares.$nome_app.headers.STSIncludeSubdomains=true
        - traefik.http.middlewares.$nome_app.headers.STSPreload=true
        - traefik.http.services.$nome_app.loadbalancer.server.port=31000
        - traefik.http.services.$nome_app.loadbalancer.passHostHeader=true              


volumes:
  $nome_app-volume:
    external: true
    name: $nome_app-volume

networks:
  network_public:
    external: true
    name: network_public


EOL

docker stack deploy --prune --resolve-image always -c $nome_app.yaml $nome_app >/dev/null 2>&1



echo -e "XXX\n75\nFINALIZANDO BUILD DO QUEPASA 4/4  \nXXX"

sleep 2

echo -e "XXX\n100\nFINALIZANDO BUILD DO QUEPASA 4/4 - CONCLUIDO  \nXXX"

sleep 3

}|whiptail --title "QUEPASA - PROGRESSO DA INSTALAÇÃO" --gauge "Aguarde a instalação dos ítens necessários" 6 60 0


# FIM DE INSTALANDO O QUEPASA
#
#######################################################
whiptail --msgbox "Parabéns, seu Quepasa foi instalado com sucesso! Pressione ENTER para voltar ao Menu Principal" 20 78


#
# MENSAGEM DE INSTLADO + DADOS
#
#
# FIM DE MENSAGEM DE INSTLADO + DADOS
#
#########################################################
#
# USUARIO PREENCHEU DADOS ERRADOS
#

elif [ "$confirma1" == "n" ]; then
    echo "Encerrando a instalação, por favor, inicie a instalação novamente."
    exit 0
else
    echo "Resposta inválida. Digite 'y' para confirmar ou 'n' para encerrar a instalação."
    exit 1
fi

#
# FIM DE USUARIO PREENCHEU DADOS ERRADOS
#
#########################################################

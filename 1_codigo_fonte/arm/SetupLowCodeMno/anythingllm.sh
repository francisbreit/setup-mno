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
		whiptail --title "INSTALAÇÃO DO ANYTHING LLM: APP DE IA" --msgbox "$msg" --fb 10 70;
	}

  while true; do
CHOICE=$(
whiptail --title "INSTALAÇÃO DO ANYTHING LLM: APP DE IA" --menu "Aperte ENTER para iniciar a instalação do ANYTHING LLM ou selecione SAIR (Utilize setas e Enter)\nINSTRUÇÕES\nAntes de prosseguir, apontar registros DNS para o(s) seguinte(s) dominio(s):\nRECORD A: Dê um nome para seu servidor (exemplo: manager1.seudominio.com.br) e aponte para o IP do seu servidor\nRECORDS CNAME: Crie subdominio para Admin do ANYTHING LLM e URL publica do ANYTHING LLM, apontando cada um para o nome do servidor criado (exemplo: manager1.seudominio.com.br)" 20 70 2 \
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
		url_anythingllm=$(whiptail --title "1/3 - URL do ANYTHING LLM" --inputbox "Digite o Link do Painel (ex: anythingllm.seudominio.com):" --fb 12 60 3>&1 1>&2 2>&3) ; saida=$?
		if [[ $saida -eq '0' ]] ; then
			if [[ -z $url_anythingllm ]] ; then msg "Digite o link do ANYTHING LLM para poder continuar" ; continue ; else break; fi
		else
			echo $url_anythingllm ; echo "saindo..."  &  exit 0 ;
		fi
	done

      while true ; do
		qdrant_anythingllm=$(whiptail --title "2/3 - URL do Qdrant" --inputbox "Digite o Link do Qdrant (ex: qdrant.seudominio.com):" --fb 12 60 3>&1 1>&2 2>&3) ; saida=$?
		if [[ $saida -eq '0' ]] ; then
			if [[ -z $qdrant_anythingllm ]] ; then msg "Digite o link do Qdrant para poder continuar" ; continue ; else break; fi
		else
			echo $qdrant_anythingllm ; echo "saindo..."  &  exit 0 ;
		fi
	done

    while true ; do
		api_qdrant_anythingllm=$(whiptail --title "3/3 - Api Key do Qdrant" --inputbox "Digite o a apikey do Qdrant:" --fb 12 60 3>&1 1>&2 2>&3) ; saida=$?
		if [[ $saida -eq '0' ]] ; then
			if [[ -z $api_qdrant_anythingllm ]] ; then msg "Digite a apikey do Qdrant para poder continuar" ; continue ; else break; fi
		else
			echo $api_qdrant_anythingllm ; echo "saindo..."  &  exit 0 ;
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

nome_principal="anythingllm"  #nome do app
sufixo_app=$(date | md5sum | head -c7)
nome_app=$nome_principal$sufixo_app


clear

echo ""
echo -e "1 - URL do ANYTHING LLM: \e[33m$url_anythingllm\e[0m"
echo -e "2 - URL do Qdrant: \e[33m$qdrant_anythingllm\e[0m"
echo -e "3 - Api Key do Qdrant: \e[33m$api_qdrant_anythingllm\e[0m"
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
echo -e "XXX\n0\nCRIANDO STACKS DO ANYTHING LLM 1/4 \nXXX"
sleep 3
echo -e "XXX\n25\nCRIANDO STACKS DO ANYTHING LLM 1/4 - CONCLUIDO \nXXX"
sleep 3 
echo -e "XXX\n25\nFAZENDO O BUILD DOS STACKS DO ANYTHING LLM 2/4 \nXXX"
sleep 3
echo -e "XXX\n50\nFAZENDO O BUILD DOS STACKS DO ANYTHING LLM 2/4 - CONCLUIDO \nXXX"
sleep 3
echo -e "XXX\n50\nINICIANDO BUILD DO ANYTHING LLM 3/4 \nXXX"
sleep 3
echo -e "XXX\n75\nINICIANDO BUILD DO ANYTHING LLM 3/4 - CONCLUIDO \nXXX"



#######################################################
#
#  INSTALANDO O ANYTHING LLM
#

cd

cd
clear


cat > $nome_app.yaml << EOL

version: "3.7"
services:

  $nome_app:
    image: mintplexlabs/anythingllm:latest

    volumes:
      - $nome_app-storage:/app/server/storage
      - $nome_app-hotdir:/app/collector/hotdir
      - $nome_app-outputs:/app/collector/outputs

    networks:
      - network_public ## Nome da rede interna

    environment:
      - SERVER_PORT=3001
      - STORAGE_DIR=/app/server/storage
      - UID=1000
      - GID=1000

      ## Dados Qdrant
      - VECTOR_DB=qdrant
      - QDRANT_ENDPOINT=$qdrant_anythingllm
      - QDRANT_API_KEY=$api_qdrant_anythingllm

    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
          - node.role == manager
      resources:
        limits:
          cpus: "0.5"
          memory: 1024M
      labels:
        - traefik.enable=true
        - traefik.http.routers.$nome_app.rule=Host(\`$url_anythingllm\`)
        - traefik.http.services.$nome_app.loadbalancer.server.port=3001
        - traefik.http.routers.$nome_app.service=$nome_app
        - traefik.http.routers.$nome_app.tls.certresolver=letsencryptresolver
        - traefik.http.routers.$nome_app.entrypoints=websecure
        - traefik.http.routers.$nome_app.tls=true


volumes:
  $nome_app-storage:
    external: true
    name: $nome_app-storage
  $nome_app-hotdir:
    external: true
    name: $nome_app-hotdir
  $nome_app-outputs:
    external: true
    name: $nome_app-outputs

networks:
  network_public: ## Nome da rede interna
    name: network_public ## Nome da rede interna
    external: true


EOL

docker stack deploy --prune --resolve-image always -c $nome_app.yaml $nome_app >/dev/null 2>&1



echo -e "XXX\n75\nFINALIZANDO BUILD DO ANYTHING LLM 4/4  \nXXX"

sleep 2

echo -e "XXX\n100\nFINALIZANDO BUILD DO ANYTHING LLM 4/4 - CONCLUIDO  \nXXX"

sleep 3

}|whiptail --title "ANYTHING LLM - PROGRESSO DA INSTALAÇÃO" --gauge "Aguarde a instalação dos ítens necessários" 6 60 0


# FIM DE INSTALANDO O ANYTHING LLM
#
#######################################################
whiptail --msgbox "Parabéns, seu ANYTHING LLM foi instalado com sucesso! Pressione ENTER para voltar ao Menu Principal" 20 78


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

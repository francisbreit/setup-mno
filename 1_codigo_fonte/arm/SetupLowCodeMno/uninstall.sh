#!/usr/bin/bash
while true; do

clear


echo ""
echo ""
echo -e "\e[93m======================================================================\e[0m"
echo -e "\e[93m=              \e[33mDELETAR APPS: REMOÇÃO DE STACKS DO DOCKER.            =\e[0m"
echo -e "\e[93m=              \e[33mSempre verifique se você possui backups.              =\e[0m"
echo -e "\e[93m=====≈================================================================\e[0m" 
echo "Atenção! Você poderá desinstalar aplicativos instalados por este instalador"                                
echo "Para deletar  um APP, digite o NUMERO da opção desejada e tecle enter:"
echo ""

PS3="Escolha qual o número do stack acima que deseja deletar: "
names=$(docker stack ls --format "{{.Name}}") 
words=( $items )
    select name in ${names} sair; do
if [ "$name" != "sair" ]; then
echo "Atenção: Tenha certeza que você tenha na pasta raiz o arquivo de backup $name.yaml"
  read -p "Você tem certeza que quer deletar o stack $name? (y/n): " confirma2
else
  #cd && cd SetupLowCodeMno && ./install
  #exit 0
  cd /
  cd
  exit 0


fi
if [ "$confirma2" == "y" ]; then

docker stack remove always $name.yaml $name &&  
break

else
    break
fi

    [[ $name == sair ]] && break
    done
done


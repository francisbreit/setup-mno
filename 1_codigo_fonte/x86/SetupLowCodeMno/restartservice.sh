#!/usr/bin/bash
while true; do

clear


echo ""
echo ""
echo -e "\e[93m======================================================================\e[0m"
echo -e "\e[93m=              \e[33mReiniciar Serviços: RESTART          =\e[0m"
echo -e "\e[93m=              \e[33mUso avançado.                        =\e[0m"
echo -e "\e[93m=====≈================================================================\e[0m" 
echo "Atenção! Você poderá reiniciar todos os serviços ativos"                                
echo "Para reiniciar um APP, digite o NUMERO da opção desejada e tecle enter:"
echo ""

PS3="Escolha qual o número do serviço acima que deseja reiniciar: "
names=$(docker service ls --format "{{.Name}}") 
words=( $items )
    select name in ${names} sair; do
if [ "$name" != "sair" ]; then
echo "Atenção: O seu serviço de nome $name será reiniciado e voltará ao normal após alguns instantes"
  read -p "Você tem certeza que quer reinciar o serviço $name? (y/n): " confirma2
else
  # cd && cd SetupLowCodeMno && ./install
  #exit 0
  cd /
  cd
  exit 0

fi
if [ "$confirma2" == "y" ]; then

docker service update --force $name &&  
break


else
    break
fi

    [[ $name == sair ]] && exit 0
    done
done


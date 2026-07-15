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
  tput reset 2>/dev/null
  exec 0</dev/tty 1>/dev/tty 2>&1
  sleep 0.01
  clear
} || true

function msg() {
    msg=$1
    whiptail --title "GERADOR DE REGISTROS DE DNS (CLOUDFLARE)" --msgbox "$msg" --fb 10 70
}

while true; do
CHOICE=$(
whiptail --title "GERADOR DE REGISTROS DE DNS (CLOUDFLARE)" --menu "Aperte ENTER para iniciar o Gerador automático ou manual de registros de Dns (compatível com Cloudflare) ou selecione SAIR (Utilize setas e Enter)\nINSTRUÇÕES\nAntes de instalar ferramentas você precisa ter apontados todos os registros de DNS para todos os subdominios.\nSe você usa Cloudflare, use esse gerador para criar todos os apontamentos de Dns de suas aplicações, para este servidor.\nBasta informar os subdominios.\nObservação: Você precisa ter uma conta ativa com seu dominio e um token de API com permissões para modificar DNS." 20 70 2 \
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

#########################################################
#
#    LOADING - CONFIGURAÇÃO DE CORES
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

{
  tput reset 2>/dev/null
  exec 0</dev/tty 1>/dev/tty 2>&1
  sleep 0.01
  clear
} || true

function msg() {
    msg=$1
    whiptail --title "CONFIGURAÇÃO DNS" --msgbox "$msg" --fb 10 70
}

#########################################################
#
# CAPTURA DE IP AUTOMATICAMENTE
#
ip_servidor=$(hostname -I | awk '{print $1}')
if [[ -z $ip_servidor ]]; then
    msg "Não foi possível capturar automaticamente o IP do servidor. Verifique a configuração da rede."
    exit 1
fi

#########################################################
#
# SOLICITAÇÃO DO DOMÍNIO PRINCIPAL E NOME DO SERVIDOR
#

dominio_principal=""
while [[ -z $dominio_principal ]]; do
    dominio_principal=$(whiptail --title "DOMÍNIO PRINCIPAL" --inputbox "Digite o domínio principal (sem https:// ou www . Exemplo: seudominio.com.br):" --fb 10 70 3>&1 1>&2 2>&3)
    if [[ $dominio_principal =~ https://|www ]]; then
        msg "O domínio não pode conter 'https://' ou 'www'."
        dominio_principal=""
    fi
done

nome_do_servidor=""
while [[ -z $nome_do_servidor ]]; do
    nome_do_servidor=$(whiptail --title "NOME DO SERVIDOR" --inputbox "Digite o nome do servidor c/ letras minúsculas, sem acento e sem o dominio (exemplo: manager1, server02, etc):" --fb 10 70 3>&1 1>&2 2>&3)
done

#########################################################
#
# LOOP PARA CAPTURA DE SUBDOMÍNIOS
#

subdominios=()
while true; do
    subdominio=$(whiptail --title "SUBDOMÍNIOS" --inputbox "Digite o subdomínio do seu aplicativo (sem https:// ou www). Apenas letras minúsculas, sem acentos e sem o dominio Exemplo: atendimento, n8n, typebot, etc):" --fb 12 70 3>&1 1>&2 2>&3)
    
    if [[ $subdominio =~ https://|www ]]; then
        msg "O subdomínio não pode conter 'https://' ou 'www'."
        continue
    fi

    if [[ -n $subdominio ]]; then
        subdominios+=("$subdominio")
    fi

    if ! whiptail --title "ADICIONAR MAIS SUBDOMÍNIOS? (Use as Teclas TAB e ENTER)" --yesno "Deseja adicionar outro subdomínio?" --fb 10 70; then
        break
    fi
done

#########################################################
#
# SELEÇÃO DO MÉTODO DE CONFIGURAÇÃO DO DNS
#

metodo_dns=$(whiptail --title "MÉTODO DE CONFIGURAÇÃO DNS" --menu "Escolha como deseja configurar os registros DNS:" 15 70 2 \
    "1)" "Configuração Manual (Gerar arquivo para importação)" \
    "2)" "Configuração Automática (Via API Cloudflare)" 3>&2 2>&1 1>&3)

case $metodo_dns in
    "1)")
        #########################################################
        #
        # GERAÇÃO DO ARQUIVO DNS.TXT (MÉTODO MANUAL)
        #

        dns_file="/root/dns.txt"
        {
            echo ";;"
            echo ";; dominio_principal: ${dominio_principal}."
            echo ";; nome_do_servidor: ${nome_do_servidor}"
            echo ";; IP: ${ip_servidor}"
            echo
            echo ";; A Records"
            echo "${nome_do_servidor}.${dominio_principal}.	1	IN	A	${ip_servidor}"
            echo
            echo ";; CNAME Records"
            for sub in "${subdominios[@]}"; do
                echo "${sub}.${dominio_principal}.	1	IN	CNAME	${nome_do_servidor}.${dominio_principal}."
            done
        } > "$dns_file"

        #########################################################
        #
        # PERGUNTA SE O USUÁRIO DESEJA ENVIAR O ARQUIVO POR E-MAIL
        #

        if whiptail --title "ENVIAR ARQUIVO POR E-MAIL?" --yesno "Deseja enviar o arquivo DNS gerado para seu e-mail (recomendado)?" --fb 10 70; then
            email=""
            while [[ -z $email ]]; do
                email=$(whiptail --title "DIGITE O E-MAIL" --inputbox "Digite o endereço de e-mail para envio do arquivo DNS:" --fb 10 70 3>&1 1>&2 2>&3)
                if ! [[ $email =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
                    msg "E-mail inválido. Por favor, insira um e-mail válido."
                    email=""
                fi
            done

            webhook_url="https://hook45.manualnegocioonline.com.br/webhook/dns_teste"

            response=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
                -H "Content-Type: multipart/form-data" \
                -F "email=$email" \
                -F "file=@$dns_file" \
                "$webhook_url")

            if [[ $response -eq 200 ]]; then
                msg "O arquivo dns.txt foi enviado com sucesso para o seu email!"
            else
                msg "Houve um problema ao enviar o arquivo dns.txt para o seu email. Código HTTP: $response"
            fi
        fi

        msg "O arquivo DNS foi salvo com sucesso em $dns_file!"
        ;;

    "2)")
        #########################################################
        #
        # CONFIGURAÇÃO AUTOMÁTICA VIA API CLOUDFLARE
        #
        clear

        # Solicitar token da Cloudflare
        cf_token=""
        while [[ -z $cf_token ]]; do
            cf_token=$(whiptail --title "TOKEN DA CLOUDFLARE" --inputbox "Digite o token da API Cloudflare (com permissões DNS Edit):" --fb 10 70 3>&1 1>&2 2>&3)
            if [[ -z $cf_token ]]; then
                msg "O token não pode estar vazio."
            fi
        done

        clear

        export NEWT_COLORS='
        root=,white
        window=,black
        border=white,black
        textbox=white,black
        button=black,white
        '

        clear

        # Arrays para acompanhar o progresso
        registros_criados=()
        registros_existentes=()
        registros_erro=()

        # Função para verificar se um registro já existe
        check_record_exists() {
            local type=$1
            local name=$2
            local content=$3
            
            response=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$zone_id/dns_records?type=$type&name=$name&content=$content" \
                -H "Authorization: Bearer $cf_token" \
                -H "Content-Type: application/json")
            
            # Verifica se encontrou algum registro
            if echo "$response" | grep -q '"id":"'; then
                return 0  # Registro existe
            else
                return 1  # Registro não existe
            fi
        }

        # Função para adicionar registros DNS
        add_dns_record() {
            local type=$1
            local name=$2
            local content=$3
            
            # Primeiro verifica se o registro já existe
            if check_record_exists "$type" "$name" "$content"; then
                echo "exists"
                return
            fi
            
            # Se não existe, tenta criar
            response=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
                "https://api.cloudflare.com/client/v4/zones/$zone_id/dns_records" \
                -H "Authorization: Bearer $cf_token" \
                -H "Content-Type: application/json" \
                --data "{\"type\":\"$type\",\"name\":\"$name\",\"content\":\"$content\",\"ttl\":1,\"proxied\":false}")

            if [[ $response -eq 200 ]]; then
                echo "success"
            else
                echo "error:$response"
            fi
        }

        # AGORA todo o processo de configuração vai dentro do gauge
        {
            echo -e "XXX\n5\nObtendo Zone ID...\nXXX"
            
            # Obter Zone ID automaticamente
            zone_id=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones?name=$dominio_principal" \
                -H "Authorization: Bearer $cf_token" \
                -H "Content-Type: application/json" | grep -Po '"id":"\K[^"]+' | head -1)

            if [[ -z $zone_id ]]; then
                echo -e "XXX\n100\nFalha ao obter Zone ID. Verifique:\n1. Se o domínio está registrado na Cloudflare\n2. Se o token está correto e com permissões suficientes\nXXX"
                sleep 4
                exit 1
            fi

            echo -e "XXX\n15\nZone ID obtido com sucesso!\nXXX"
            sleep 2

            echo -e "XXX\n25\nIniciando configuração de registros DNS...\nXXX"
            sleep 2

            # Adicionar registro A principal
            echo -e "XXX\n35\nConfigurando registro A principal...\nXXX"
            result=$(add_dns_record "A" "${nome_do_servidor}.${dominio_principal}" "$ip_servidor")
            case $result in
                "success")
                    registros_criados+=("A: ${nome_do_servidor}.${dominio_principal} → $ip_servidor")
                    ;;
                "exists")
                    registros_existentes+=("A: ${nome_do_servidor}.${dominio_principal} → $ip_servidor")
                    ;;
                *)
                    registros_erro+=("A: ${nome_do_servidor}.${dominio_principal} (Erro: ${result#error:})")
                    ;;
            esac

            echo -e "XXX\n50\nRegistro A processado. Configurando CNAMEs...\nXXX"
            sleep 1

            # Adicionar registros CNAME para subdomínios
            total_subdominios=${#subdominios[@]}
            progresso_atual=50
            incremento=$((40 / (total_subdominios + 1)))

            for sub in "${subdominios[@]}"; do
                progresso_atual=$((progresso_atual + incremento))
                echo -e "XXX\n$progresso_atual\nConfigurando CNAME: $sub...\nXXX"
                
                result=$(add_dns_record "CNAME" "${sub}.${dominio_principal}" "${nome_do_servidor}.${dominio_principal}")
                case $result in
                    "success")
                        registros_criados+=("CNAME: ${sub}.${dominio_principal}")
                        ;;
                    "exists")
                        registros_existentes+=("CNAME: ${sub}.${dominio_principal}")
                        ;;
                    *)
                        registros_erro+=("CNAME: ${sub}.${dominio_principal} (Erro: ${result#error:})")
                        ;;
                esac
                sleep 1
            done

            echo -e "XXX\n100\nConfiguração concluída!\nXXX"
            sleep 2

        } | whiptail --title "PROGRESSO DA CONFIGURAÇÃO DNS" --gauge "Aguarde a configuração dos registros DNS" 8 60 0

        # Montar mensagem de resultado
        mensagem_resultado="Processamento concluído!\n\n"

        if [[ ${#registros_criados[@]} -gt 0 ]]; then
            mensagem_resultado+="✅ REGISTROS CRIADOS:\n"
            for registro in "${registros_criados[@]}"; do
                mensagem_resultado+="• $registro\n"
            done
            mensagem_resultado+="\n"
        fi

        if [[ ${#registros_existentes[@]} -gt 0 ]]; then
            mensagem_resultado+="ℹ️ REGISTROS JÁ EXISTENTES:\n"
            for registro in "${registros_existentes[@]}"; do
                mensagem_resultado+="• $registro\n"
            done
            mensagem_resultado+="\n"
        fi

        if [[ ${#registros_erro[@]} -gt 0 ]]; then
            mensagem_resultado+="❌ REGISTROS COM ERRO:\n"
            for registro in "${registros_erro[@]}"; do
                mensagem_resultado+="• $registro\n"
            done
        fi

        if [[ ${#registros_criados[@]} -eq 0 && ${#registros_existentes[@]} -eq 0 && ${#registros_erro[@]} -gt 0 ]]; then
            mensagem_resultado+="\nNenhum registro foi criado. Verifique os erros acima."
        elif [[ ${#registros_erro[@]} -eq 0 ]]; then
            mensagem_resultado+="\n✅ Todos os registros foram processados com sucesso!"
        else
            mensagem_resultado+="\n⚠️ Alguns registros podem não ter sido criados."
        fi

        whiptail --title "RESULTADO DA CONFIGURAÇÃO DNS" --msgbox "$mensagem_resultado" 20 78
        ;;
esac

exit 0
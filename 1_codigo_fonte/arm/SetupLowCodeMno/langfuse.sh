#!/usr/bin/bash
set -o pipefail
umask 077

langfuse_generate_minio_access_key() {
    local generated_key

    generated_key="lf$(openssl rand -hex 9)" || return 1
    [[ "$generated_key" =~ ^[a-zA-Z0-9]{20}$ ]] || return 1
    printf '%s' "$generated_key"
}

# Gate não interativo executado também no binário protegido pelo SHC.
if [ "${SETUPMNO_LANGFUSE_ACCESS_KEY_SMOKE_TEST:-0}" = "1" ]; then
    for _langfuse_key_attempt in $(seq 1 32); do
        _langfuse_test_key=$(langfuse_generate_minio_access_key) || exit 81
        [ "${#_langfuse_test_key}" -eq 20 ] || exit 82
    done
    exit 0
fi

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
    if [ -f "${SETUPMNO_CLOUDFLARE_CREDENTIALS_FILE:-/root/.cloudflared_config/cloudflare_credentials}" ]; then
        source "${SETUPMNO_CLOUDFLARE_CREDENTIALS_FILE:-/root/.cloudflared_config/cloudflare_credentials}"
    fi
else
    if [ -f "${SETUPMNO_TRADITIONAL_CREDENTIALS_FILE:-/root/.tradicional_config/tradicional_credentials}" ]; then
        source "${SETUPMNO_TRADITIONAL_CREDENTIALS_FILE:-/root/.tradicional_config/tradicional_credentials}"
    fi
fi

function msg() {
		msg=$1
		whiptail --title "INSTALAÇÃO DO LANGFUSE + MINIO + CLICKHOUSE: OBSERVABILIDADE DE IA" --msgbox "$msg" --fb 10 70 1>&2
	}

  while true; do
CHOICE=$(
whiptail --title "INSTALAÇÃO DO LANGFUSE + MINIO + CLICKHOUSE: FERRAMENTA DE CHATBOTS" --menu "Aperte ENTER para iniciar a instalação do LANGFUSE + MINIO + CLICKHOUSE ou selecione SAIR (Utilize setas e Enter)\n\nTIPO DE INSTALAÇÃO DETECTADA: $INSTALL_TYPE\n\nINSTRUÇÕES:\nAntes de prosseguir, verifique os registros DNS conforme seu tipo de instalação:" 20 70 2 \
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

minio_container=$(docker ps --filter "name=minio" --format '{{.ID}}' | head -n1)
clickhouse_container=$(docker ps --filter "name=clickhouse" --format '{{.ID}}' | head -n1)

# Ao reutilizar um MinIO existente, recupere o alias DNS real do serviço para
# que a validação interna não dependa da URL pública nem de propagação DNS.
if [[ -n "$minio_container" ]]; then
    minio_service=$(docker inspect "$minio_container" \
        --format '{{ index .Config.Labels "com.docker.swarm.service.name" }}' 2>/dev/null)
    if [[ -z "$minio_service" ]]; then
        whiptail --title "Erro" --msgbox "O MinIO encontrado não pertence a um serviço Docker Swarm válido. A instalação foi interrompida para evitar uma configuração inconsistente." 12 70
        exit 1
    fi
    nome_app2="${minio_service#*_}"
fi

# Ao reutilizar um ClickHouse existente, recupere o alias DNS real do serviço
# no Swarm. Sem isso, nome_app3 fica vazio e o Langfuse recebe URLs inválidas.
if [[ -n "$clickhouse_container" ]]; then
    clickhouse_service=$(docker inspect "$clickhouse_container" \
        --format '{{ index .Config.Labels "com.docker.swarm.service.name" }}' 2>/dev/null)
    if [[ -z "$clickhouse_service" ]]; then
        whiptail --title "Erro" --msgbox "O ClickHouse encontrado não pertence a um serviço Docker Swarm válido. A instalação foi interrompida para evitar uma configuração inconsistente." 12 70
        exit 1
    fi
    nome_app3="${clickhouse_service#*_}"
fi

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
        senhaminio=$(whiptail --title "Senha do Minio" --passwordbox "Crie sua Senha do Minio (use de 8 a 16 caracteres alfanuméricos):" --fb 12 60 3>&1 1>&2 2>&3)
        saida=$?
        if [[ $saida -eq '0' ]]; then
            if [[ (-z $senhaminio) || ("$senhaminio" =~ [^a-zA-Z0-9]) || (${#senhaminio} -lt 8) || (${#senhaminio} -gt 16) ]]; then 
                msg "Digite a senha do Minio, sem caracteres especiais e de 8 até 16 dígitos para poder continuar" 
                continue 
            else 
                break
            fi
        else
            echo "Saindo..."; exit 0
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


if [[ ("$clickhouse_container" == "") ]]; then

   while true ; do
		url_clickhouse=$(whiptail --title "1/3 - URL do CLICKHOUSE" --inputbox "Digite o Link do Painel (ex: clickhouse.seudominio.com):" --fb 12 60 3>&1 1>&2 2>&3) ; saida=$?
		if [[ $saida -eq '0' ]] ; then
			if [[ -z $url_clickhouse ]] ; then msg "Digite o link do CLICKHOUSE para poder continuar" ; continue ; else break; fi
		else
			echo $url_clickhouse ; echo "saindo..."  &  exit 0 ;
		fi
	done

      while true ; do
		user_clickhouse=$(whiptail --title "2/3 - Usuario do CLICKHOUSE" --inputbox "Digite o usuario do CLICKHOUSE:" --fb 12 60 3>&1 1>&2 2>&3) ; saida=$?
		if [[ $saida -eq '0' ]] ; then
			if [[ -z $user_clickhouse ]] ; then msg "Digite o nome de usuario para poder continuar" ; continue ; else break; fi
		else
			echo $user_clickhouse ; echo "saindo..."  &  exit 0 ;
		fi
	done

     while true ; do
		pass_clickhouse=$(whiptail --title "3/3 - Senha do CLICKHOUSE" --passwordbox "Digite a senha do CLICKHOUSE (máximo 16 caracteres alfanuméricos):" --fb 12 60 3>&1 1>&2 2>&3) ; saida=$?
		if [[ $saida -eq '0' ]] ; then
		if [[ (-z $pass_clickhouse) || ("$pass_clickhouse" =~ [^a-zA-Z0-9]) || (${#pass_clickhouse} -gt 16) ]] ; then msg "Digite a senha do CLICKHOUSE, sem caracteres especiais e até 16 digitos para poder continuar" ; continue ; else break; fi
    else
			echo "saindo..."; exit 0
		fi
	done

    cd

    mkdir -p ~/dados_clickhouse
    echo "DASHBOARD_CLICKHOUSE: https://$url_clickhouse/dashboard" > ~/dados_clickhouse/dados_clickhouse
    echo "API_CLICKHOUSE: https://$url_clickhouse" >> ~/dados_clickhouse/dados_clickhouse
    echo "USUARIO_CLICKHOUSE: $user_clickhouse" >> ~/dados_clickhouse/dados_clickhouse
    echo "SENHA_CLICKHOUSE: $pass_clickhouse" >> ~/dados_clickhouse/dados_clickhouse

fi

# Verificar e carregar dados do Minio
dados_clickhouse_file="$HOME/dados_clickhouse/dados_clickhouse"
if [[ -f "$dados_clickhouse_file" ]]; then
    API_CLICKHOUSE=$(grep "API_CLICKHOUSE:" "$dados_clickhouse_file" | awk '{print $2}')
    USUARIO_CLICKHOUSE=$(grep "USUARIO_CLICKHOUSE:" "$dados_clickhouse_file" | awk '{print $2}')
    SENHA_CLICKHOUSE=$(grep "SENHA_CLICKHOUSE:" "$dados_clickhouse_file" | awk '{print $2}')
else
    whiptail --title "Erro" --msgbox "Clickhouse instalado, mas os dados de acesso não foram encontrados. A presente instalação acessa credenciais pré-gravadas em uma pasta. Se sua instalação não é recente, pode ser que o Setup-MNO não criou esta pasta. Talvez seja necessário reinstalar o Clickhouse antes do Langfuse. Digite enter para abortar a instalação e instale o Clickhouse antes do Langfuse." 15 60
    exit 0
fi


  while true ; do
		url_langfuse=$(whiptail --title "1/9 - URL do LANGFUSE" --inputbox "Digite o link do Langfuse (ex: langfuse.seudominio.com):" --fb 12 60 3>&1 1>&2 2>&3) ; saida=$?
		if [[ $saida -eq '0' ]] ; then
			if [[ -z $url_langfuse ]] ; then msg "Digite o link do LANGFUSE, para poder continuar" ; continue ; else break; fi
		else
			echo $url_langfuse ; echo "saindo..."  &  exit 0 ;
		fi
	done

# Perguntar ao usuário se deseja criar a stack no Portainer

 while true ; do
		criar_portainer=$(whiptail --title "Criar Stack no Portainer? - 0 ou 1" --inputbox "Digite 0 para poder editar stack no portainer ou 1 para não poder editar" --fb 12 60 3>&1 1>&2 2>&3) ; saida=$?
		if [[ $saida -eq '0' ]] ; then
		#	if [[ -z $senhamautic ]] ; then msg "Digite a senha do Mautic, para poder continuar" ; continue ; else break; fi
		if [[ "$criar_portainer" != "0" && "$criar_portainer" != "1" ]] ; then msg "Digite apenas o número 0 ou o número 1, para poder continuar. Digite 0 para poder editar stack no portainer ou 1 para não poder editar" ; continue ; else break; fi
    else
			echo $criar_portainer ; echo "saindo..."  &  exit 0 ;
		fi
	done

     
 
# FIM DE PERGUNTAS PARA VARIAVEIS
#
#########################################################
#
# VERIFICAÇO DE DADOS
#


nome_principal="langfuse"  #nome do app
sufixo_app=$(date | md5sum | head -c7)
nome_app=$nome_principal$sufixo_app
PORTAINER_DIAG_LOG="/tmp/${nome_app}-portainer.log"

# Registra somente metadados técnicos. Respostas, tokens, usuários e senhas
# nunca são gravados no diagnóstico.
portainer_log_failure() {
    local stage="$1"
    local curl_exit="${2:-desconhecido}"
    local http_code="${3:-desconhecido}"
    local response_bytes="${4:-0}"

    umask 077
    printf '%s stage=%s curl_exit=%s http=%s response_bytes=%s\n' \
        "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" \
        "$stage" "$curl_exit" "$http_code" "$response_bytes" \
        >> "$PORTAINER_DIAG_LOG"
}

portainer_api_curl() {
    curl --connect-timeout 10 --max-time 30 "$@"
    local curl_exit=$?
    if [ "$curl_exit" -ne 0 ]; then
        portainer_log_failure "${PORTAINER_DIAG_STAGE:-portainer_api}" "$curl_exit" "000" "0"
    fi
    return "$curl_exit"
}

portainer_upload_curl() {
    curl --connect-timeout 10 --max-time 90 "$@"
    local curl_exit=$?
    if [ "$curl_exit" -ne 0 ]; then
        portainer_log_failure "${PORTAINER_DIAG_STAGE:-portainer_upload}" "$curl_exit" "000" "0"
    fi
    return "$curl_exit"
}

LANGFUSE_INSTALL_LOG="/tmp/${nome_app}-install.log"
LANGFUSE_ERROR_FILE="/tmp/${nome_app}-error.log"
: > "$LANGFUSE_INSTALL_LOG"
: > "$LANGFUSE_ERROR_FILE"

langfuse_fail() {
    local code="$1" message="$2"
    umask 077
    printf '%s\n' "$message" > "$LANGFUSE_ERROR_FILE"
    printf '%s ERROR code=%s message=%s\n' \
        "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$code" "$message" \
        >> "$LANGFUSE_INSTALL_LOG"
    echo -e "XXX\n100\nERRO: INSTALAÇÃO DO LANGFUSE INTERROMPIDA\nXXX"
    exit "$code"
}

deploy_stack_checked() {
    local stack_name="$1" stack_file="$2" failure_code="$3"
    local dados_file response token endpoint_id swarm_id response_file http_code

    if [[ "$criar_portainer" == "1" ]]; then
        docker stack deploy --prune --resolve-image always \
            -c "$stack_file" "$stack_name" >> "$LANGFUSE_INSTALL_LOG" 2>&1 ||
            langfuse_fail "$failure_code" "O Docker Swarm recusou a stack $stack_name."
        return 0
    fi

    dados_file="$HOME/dados_portainer/dados_portainer"
    [[ -f "$dados_file" ]] ||
        langfuse_fail "$failure_code" "A criação editável foi solicitada, mas os dados do Portainer não foram encontrados."
    command -v jq >/dev/null 2>&1 ||
        langfuse_fail "$failure_code" "O utilitário jq é obrigatório para autenticação segura no Portainer."

    PORTAINER_URL=$(grep "Dominio do portainer:" "$dados_file" | cut -d':' -f2 | xargs)
    ADMIN_USERNAME=$(grep "Usuario:" "$dados_file" | cut -d':' -f2 | xargs)
    ADMIN_PASSWORD=$(grep "Senha:" "$dados_file" | cut -d':' -f2 | xargs)
    [[ -n "$PORTAINER_URL" && -n "$ADMIN_USERNAME" && -n "$ADMIN_PASSWORD" ]] ||
        langfuse_fail "$failure_code" "Os dados do Portainer estão incompletos."

    PORTAINER_DIAG_STAGE="${stack_name}_auth"
    response=$(portainer_api_curl -sS -X POST "https://$PORTAINER_URL/api/auth" \
        -H "Content-Type: application/json" \
        -d "$(jq -cn --arg username "$ADMIN_USERNAME" --arg password "$ADMIN_PASSWORD" \
            '{username:$username,password:$password}')") ||
        langfuse_fail "$failure_code" "Falha de comunicação ao autenticar no Portainer."
    token=$(printf '%s' "$response" | jq -r '.jwt // empty')
    [[ -n "$token" ]] || langfuse_fail "$failure_code" "O Portainer rejeitou a autenticação."

    PORTAINER_DIAG_STAGE="${stack_name}_endpoint"
    response=$(portainer_api_curl -sS "https://$PORTAINER_URL/api/endpoints" \
        -H "Authorization: Bearer $token") ||
        langfuse_fail "$failure_code" "Falha ao consultar o endpoint do Portainer."
    endpoint_id=$(printf '%s' "$response" | jq -r '.[0].Id // empty')
    [[ -n "$endpoint_id" ]] || langfuse_fail "$failure_code" "Endpoint do Portainer não encontrado."

    PORTAINER_DIAG_STAGE="${stack_name}_swarm"
    response=$(portainer_api_curl -sS \
        "https://$PORTAINER_URL/api/endpoints/$endpoint_id/docker/swarm" \
        -H "Authorization: Bearer $token") ||
        langfuse_fail "$failure_code" "Falha ao consultar o Swarm pelo Portainer."
    swarm_id=$(printf '%s' "$response" | jq -r '.ID // empty')
    [[ -n "$swarm_id" ]] || langfuse_fail "$failure_code" "Swarm ID não encontrado no Portainer."

    response_file=$(mktemp)
    PORTAINER_DIAG_STAGE="${stack_name}_create"
    http_code=$(portainer_upload_curl -sS -o "$response_file" -w '%{http_code}' -X POST \
        -H "Authorization: Bearer $token" \
        -F "Name=$stack_name" \
        -F "file=@$stack_file" \
        -F "SwarmID=$swarm_id" \
        -F "endpointId=$endpoint_id" \
        "https://$PORTAINER_URL/api/stacks/create/swarm/file") || true
    rm -f "$response_file"
    [[ "$http_code" == "200" || "$http_code" == "201" ]] ||
        langfuse_fail "$failure_code" "O Portainer recusou a criação da stack $stack_name (HTTP ${http_code:-000})."
}

wait_service_healthy() {
    local service_name="$1" label="$2" failure_code="$3"
    local attempt replicas container_id health_state task_error

    for attempt in $(seq 1 60); do
        replicas=$(docker service ls --filter "name=$service_name" \
            --format '{{.Name}} {{.Replicas}}' | awk -v expected="$service_name" '$1 == expected {print $2; exit}')
        container_id=$(docker ps \
            --filter "label=com.docker.swarm.service.name=$service_name" \
            --format '{{.ID}}' | head -n1)
        health_state=""
        if [[ -n "$container_id" ]]; then
            health_state=$(docker inspect "$container_id" \
                --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}running{{end}}' 2>/dev/null)
        fi
        if [[ "$replicas" == "1/1" && ( "$health_state" == "healthy" || "$health_state" == "running" ) ]]; then
            return 0
        fi
        echo -e "XXX\n90\nAGUARDANDO $label: tentativa ${attempt}/60\nXXX"
        sleep 5
    done

    task_error=$(docker service ps "$service_name" --no-trunc \
        --format 'Estado: {{.CurrentState}} | Erro: {{.Error}}' | head -n 8)
    printf '%s\n' "$task_error" >> "$LANGFUSE_INSTALL_LOG"
    langfuse_fail "$failure_code" "$label não atingiu estado saudável em cinco minutos."
}

wait_stack_registered() {
    local stack_name="$1" label="$2" failure_code="$3"
    local attempt

    for attempt in $(seq 1 25); do
        if docker stack ls --format '{{.Name}}' | grep -Fxq "$stack_name"; then
            return 0
        fi
        if [ "$attempt" -lt 25 ]; then
            echo -e "XXX\n90\nAGUARDANDO REGISTRO DA STACK $label: tentativa ${attempt}/24\nXXX"
            sleep 5
        fi
    done

    langfuse_fail "$failure_code" "A stack $stack_name não foi registrada no Docker Swarm em até dois minutos."
}

postgres_password=$(grep -oP '(?<=POSTGRES_PASSWORD=).+' /root/postgres.yaml)
[ -n "$postgres_password" ] || {
    whiptail --title "Erro" --msgbox "A senha do PostgreSQL não foi encontrada em /root/postgres.yaml. A instalação foi interrompida antes de criar recursos do Langfuse." 12 70
    exit 1
}

if [[ ("$minio_container" == "") ]]; then
    nome_principal2="minio"
    nome_app2=$nome_principal2$sufixo_app
    sufixo_public="_public"
    sufixo_console="_console"
    nome_app_public=$nome_app2$sufixo_public
    nome_app_console=$nome_app2$sufixo_console
fi


if [[ ("$clickhouse_container" == "") ]]; then
    nome_principal3="clickhouse"  #nome do app
    sufixo_app3=$(date | md5sum | head -c7)
    nome_app3=$nome_principal3$sufixo_app3
fi

# Os nomes completos do Swarm são usados apenas para localizar containers.
# Endpoints HTTP/S3 usam aliases explícitos sem underscore: o AWS SDK rejeita
# nomes como stack_servico com "Invalid Request (invalid hostname)".
minio_service="${minio_service:-${nome_app2}_${nome_app2}}"
clickhouse_service="${clickhouse_service:-${nome_app3}_${nome_app3}}"
minio_internal_host="$nome_app2"
clickhouse_internal_host="$nome_app3"

if [[ ! "$minio_internal_host" =~ ^[a-zA-Z0-9][a-zA-Z0-9.-]*$ ]] ||
   [[ ! "$clickhouse_internal_host" =~ ^[a-zA-Z0-9][a-zA-Z0-9.-]*$ ]]; then
    whiptail --title "Erro" --msgbox "Os aliases internos do MinIO ou ClickHouse são inválidos. A instalação foi interrompida antes do deploy." 12 74 1>&2
    exit 1
fi

if [ "$minio_container" == "" ] && [ "$clickhouse_container" == "" ]; then
    {
        tput reset 2>/dev/null
        exec 0</dev/tty 1>/dev/tty 2>&1
        sleep 0.01
        clear
    } || true

    whiptail --title "Dados Fornecidos" \
    --msgbox "TIPO DE INSTALAÇÃO: $INSTALL_TYPE\n\nDados Preenchidos:\n\n1) Link do Painel Minio: $painel\n2) Link Público Minio: $publico\n3) Usuário do Minio: $usuariominio\n4) Senha do Minio: [PROTEGIDA]\n5) URL do Clickhouse: $url_clickhouse\n6) Usuário do Clickhouse: $user_clickhouse\n7) Senha do Clickhouse: [PROTEGIDA]\n8) URL Langfuse: $url_langfuse\n9) Criar Stack no Portainer: $([ "$criar_portainer" == "0" ] && echo "0 (Editável)" || echo "1 (Não editável)")\n\nConfira e Tecle Enter para continuar. Na próxima etapa você poderá confirmar os dados ou corrigir, se necessário." \
    --fb 22 80

fi

if [ "$minio_container" == "" ] && [ "$clickhouse_container" != "" ]; then
    {
        tput reset 2>/dev/null
        exec 0</dev/tty 1>/dev/tty 2>&1
        sleep 0.01
        clear
    } || true

    whiptail --title "Dados Fornecidos" \
    --msgbox "TIPO DE INSTALAÇÃO: $INSTALL_TYPE\n\nDados Preenchidos:\n\n1) Link do Painel Minio: $painel\n2) Link Público Minio: $publico\n3) Usuário do Minio: $usuariominio\n4) Senha do Minio: [PROTEGIDA]\n5) URL Langfuse: $url_langfuse\n6) Criar Stack no Portainer: $([ "$criar_portainer" == "0" ] && echo "0 (Editável)" || echo "1 (Não editável)")\n\nConfira e Tecle Enter para continuar. Na próxima etapa você poderá confirmar os dados ou corrigir, se necessário." \
    --fb 22 80

fi

if [ "$minio_container" != "" ] && [ "$clickhouse_container" = "" ]; then
    {
        tput reset 2>/dev/null
        exec 0</dev/tty 1>/dev/tty 2>&1
        sleep 0.01
        clear
    } || true

    whiptail --title "Dados Fornecidos" \
    --msgbox "TIPO DE INSTALAÇÃO: $INSTALL_TYPE\n\nDados Preenchidos:\n\n1) URL do Clickhouse: $url_clickhouse\n2) Usuário do Clickhouse: $user_clickhouse\n3) Senha do Clickhouse: [PROTEGIDA]\n4) URL Langfuse: $url_langfuse\n5) Criar Stack no Portainer: $([ "$criar_portainer" == "0" ] && echo "0 (Editável)" || echo "1 (Não editável)")\n\nConfira e Tecle Enter para continuar. Na próxima etapa você poderá confirmar os dados ou corrigir, se necessário." \
    --fb 22 80

fi

if [ "$minio_container" != "" ] && [ "$clickhouse_container" != "" ]; then
    {
         tput reset 2>/dev/null         # Reinicia o terminal de forma segura
         exec 0</dev/tty 1>/dev/tty 2>&1 # Força redirecionamentos explícitos
         sleep 0.01                     # Pausa microscópica para sincronia
         clear                          # Limpeza final antes do whiptail
    } || true


    # Exibe as informações formatadas com mais espaço na tela
    whiptail --title "Dados Fornecidos" \
    --msgbox "TIPO DE INSTALAÇÃO: $INSTALL_TYPE\n\nDados Preenchidos:\n\n1) Link do Langfuse: $url_langfuse\n2) Criar Stack no Portainer: $([ "$criar_portainer" == "0" ] && echo "0 (Editável)" || echo "1 (Não editável)")\n\nConfira e Tecle Enter para continuar. Na próxima etapa você poderá confirmar os dados ou corrigir, se necessário." \
    --fb 22 80

fi

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


 if [[ ("$minio_container" == "") ]]; then
# Função para verificação do domínio
# Função para verificação do domínio
  echo -e "XXX\n5\nVERIFICANDO DOMINIO 1... \nXXX"

if [ "$INSTALL_TYPE" = "TRADICIONAL" ] && [ "$criar_dns" = "0" ]; then
    # CONFIGURAÇÃO TRADICIONAL COM DNS AUTOMÁTICO
    echo -e "XXX\n6\nCONFIGURANDO DNS AUTOMÁTICO (TRADICIONAL)... \nXXX"
    
    DOMINIO_PRINCIPAL="${SETUPMNO_SELECTED_ROOT_DOMAIN:-${SETUPMNO_DOMAIN_ROOT:-${CLOUDFLARE_ZONE_NAME:-}}}"
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
    
    DOMINIO_PRINCIPAL="${SETUPMNO_SELECTED_ROOT_DOMAIN:-${SETUPMNO_DOMAIN_ROOT:-${CLOUDFLARE_ZONE_NAME:-}}}"
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
    NEW_SERVICE="http://${minio_internal_host}:9001"
    
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
    
    DOMINIO_PRINCIPAL="${SETUPMNO_SELECTED_ROOT_DOMAIN:-${SETUPMNO_DOMAIN_ROOT:-${CLOUDFLARE_ZONE_NAME:-}}}"
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
    
    DOMINIO_PRINCIPAL="${SETUPMNO_SELECTED_ROOT_DOMAIN:-${SETUPMNO_DOMAIN_ROOT:-${CLOUDFLARE_ZONE_NAME:-}}}"
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
    NEW_SERVICE="http://${minio_internal_host}:9000"
    
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
      interna:
        aliases:
          - $minio_internal_host
      externa:
    volumes:
      - $nome_app2-data:/data
    environment:
      - MINIO_ROOT_USER=$usuariominio
      - MINIO_ROOT_PASSWORD=$senhaminio
      - MINIO_BROWSER_REDIRECT_URL=https://$painel
      - MINIO_SERVER_URL=https://$publico
    healthcheck:
      test: ["CMD-SHELL", "curl -fsS http://127.0.0.1:9000/minio/health/live || exit 1"]
      interval: 10s
      timeout: 5s
      retries: 30
      start_period: 20s
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
        - traefik.http.routers.$nome_app2-public.rule=Host(\`$publico\`)
        - traefik.http.routers.$nome_app2-public.entrypoints=websecure
        - traefik.http.routers.$nome_app2-public.tls.certresolver=letsencryptresolver
        - traefik.http.services.$nome_app2-public.loadbalancer.server.port=9000
        - traefik.http.services.$nome_app2-public.loadbalancer.passHostHeader=true
        - traefik.http.routers.$nome_app2-public.service=$nome_app2-public
        - traefik.http.routers.$nome_app2-console.rule=Host(\`$painel\`)
        - traefik.http.routers.$nome_app2-console.entrypoints=websecure
        - traefik.http.routers.$nome_app2-console.tls.certresolver=letsencryptresolver
        - traefik.http.services.$nome_app2-console.loadbalancer.server.port=9001
        - traefik.http.services.$nome_app2-console.loadbalancer.passHostHeader=true
        - traefik.http.routers.$nome_app2-console.service=$nome_app2-console
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

    if ! docker volume inspect "$nome_app2-data" >/dev/null 2>&1 &&
       ! docker volume create "$nome_app2-data" >> "$LANGFUSE_INSTALL_LOG" 2>&1; then
        langfuse_fail 31 "Não foi possível criar o volume persistente do MinIO."
    fi

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
            PORTAINER_DIAG_STAGE="minio_auth"
            RESPONSE=$(portainer_api_curl -sS -X POST "https://$PORTAINER_URL/api/auth" \
                -H "Content-Type: application/json" \
                -d "{\"username\": \"$ADMIN_USERNAME\", \"password\": \"$ADMIN_PASSWORD\"}")
            TOKEN=$(echo "$RESPONSE" | jq -r '.jwt' 2>/dev/null)
            if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]; then
                portainer_log_failure "minio_auth_invalid_response" "0" "nao_validado" "$(printf '%s' "$RESPONSE" | wc -c)"
                echo -e "XXX\n40\nFALHA NA AUTENTICAÇÃO. LOG: $PORTAINER_DIAG_LOG 3/4  \nXXX"
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
            PORTAINER_DIAG_STAGE="minio_endpoints"
            RESPONSE=$(portainer_api_curl -sS -X GET "https://$PORTAINER_URL/api/endpoints" \
                -H "Authorization: Bearer $TOKEN")
            ENDPOINT_ID=$(echo "$RESPONSE" | jq -r '.[0].Id' 2>/dev/null)
            if [ -z "$ENDPOINT_ID" ] || [ "$ENDPOINT_ID" = "null" ]; then
                portainer_log_failure "minio_endpoints_invalid_response" "0" "nao_validado" "$(printf '%s' "$RESPONSE" | wc -c)"
                echo -e "XXX\n44\n[ERRO] ENDPOINTID NÃO ENCONTRADO. LOG: $PORTAINER_DIAG_LOG 3/4  \nXXX"
                docker stack deploy --prune --resolve-image always -c $nome_app2.yaml $nome_app2 >/dev/null 2>&1
                exit 1
            fi
            echo -e "XXX\n45\n[SUCESSO] ENDPOINTID OBTIDO: $ENDPOINT_ID  3/4  \nXXX"
        }

        get_swarm_id() {
            echo -e "XXX\n46\n[INFO] OBTENDO SWARMID  3/4  \nXXX"
            PORTAINER_DIAG_STAGE="minio_swarm"
            RESPONSE=$(portainer_api_curl -sS -X GET "https://$PORTAINER_URL/api/endpoints/$ENDPOINT_ID/docker/swarm" \
                -H "Authorization: Bearer $TOKEN")
            SWARM_ID=$(echo "$RESPONSE" | jq -r '.ID' 2>/dev/null)
            if [ -z "$SWARM_ID" ] || [ "$SWARM_ID" = "null" ]; then
                portainer_log_failure "minio_swarm_invalid_response" "0" "nao_validado" "$(printf '%s' "$RESPONSE" | wc -c)"
                echo -e "XXX\n47\n[ERRO] SWARMID NÃO ENCONTRADO. LOG: $PORTAINER_DIAG_LOG 3/4  \nXXX"
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

            PORTAINER_DIAG_STAGE="minio_create"
            http_code=$(portainer_upload_curl -sS -o "$response_output" -w "%{http_code}" -X POST \
                -H "Authorization: Bearer $TOKEN" \
                -F "Name=$STACK_NAME" \
                -F "file=@$STACK_FILE_PATH" \
                -F "SwarmID=$SWARM_ID" \
                -F "endpointId=$ENDPOINT_ID" \
                "https://$PORTAINER_URL/api/stacks/create/swarm/file" 2> "$erro_output")

            response=$(cat "$response_output")
            rm -f "$response_output" "$erro_output"

            if [ "$http_code" != "200" ]; then
                portainer_log_failure "minio_create_http" "0" "${http_code:-000}" "$(printf '%s' "$response" | wc -c)"
                echo -e "XXX\n56\n[ERRO] ERRO AO CRIAR STACK. LOG: $PORTAINER_DIAG_LOG 3/4  \nXXX"
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
        docker stack deploy --prune --resolve-image always \
            -c "$nome_app2.yaml" "$nome_app2" >> "$LANGFUSE_INSTALL_LOG" 2>&1 ||
            langfuse_fail 33 "O Docker Swarm recusou a stack do MinIO."
    else
        echo -e "XXX\n58\n[ERRO] ERRO INESPERADO PARA CRIAR STACK NO PORTAINER 3/4  \nXXX"
        sleep 5
        echo -e "XXX\n59\nREVERTENDO E CRIANDO STACK PELO SERVIDOR 3/4  \nXXX"
        docker stack deploy --prune --resolve-image always -c $nome_app2.yaml $nome_app2 >/dev/null 2>&1
        sleep 5
        exit 1
    fi
        wait_service_healthy "$minio_service" "MinIO" 34
        echo -e "XXX\n60\nFINALIZANDO BUILD DO MINIO 4/4  \nXXX"
        sleep 2
        echo -e "XXX\n61\nFINALIZANDO BUILD DO MINIO 4/4 - CONCLUÍDO  \nXXX"
        sleep 3
fi



if [[ ("$clickhouse_container" == "") ]]; then

#VERIFICANDO CONFIGURAÇÃO Clickhouse

echo -e "XXX\n5\nVERIFICANDO CONFIGURAÇÃO Clickhouse... \nXXX"

if [ "$INSTALL_TYPE" = "TRADICIONAL" ] && [ "$criar_dns" = "0" ]; then
    # CONFIGURAÇÃO TRADICIONAL COM DNS AUTOMÁTICO
    echo -e "XXX\n10\nCONFIGURANDO DNS AUTOMÁTICO (TRADICIONAL)... \nXXX"
    
    DOMINIO_PRINCIPAL="${SETUPMNO_SELECTED_ROOT_DOMAIN:-${SETUPMNO_DOMAIN_ROOT:-${CLOUDFLARE_ZONE_NAME:-}}}"
    SUBDOMINIO=${url_clickhouse%%.$DOMINIO_PRINCIPAL}

    # Verificar e remover registros existentes
    echo -e "XXX\n15\nVERIFICANDO REGISTROS EXISTENTES... \nXXX"
    EXISTING_RECORDS=$(curl -s -X GET \
        "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records?name=${url_clickhouse}" \
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
        --data '{"type":"CNAME","name":"'${url_clickhouse}'","content":"'${nome_servidor}'.'${DOMINIO_PRINCIPAL}'","ttl":1,"proxied":false}')

    if echo "$CNAME_RESPONSE" | grep -q '"success":true'; then
        echo -e "XXX\n30\nREGISTRO CNAME CRIADO COM SUCESSO! \nXXX"
    else
        echo -e "XXX\n30\nAVISO: ERRO AO CRIAR REGISTRO CNAME \nXXX"
    fi

elif [ "$INSTALL_TYPE" = "CLOUDFLARE_TUNNEL" ]; then
    # CONFIGURAÇÃO CLOUDFLARE TUNNEL - DNS E ROTAS
    echo -e "XXX\n10\nCONFIGURANDO CLOUDFLARE TUNNEL (DNS + ROTAS)... \nXXX"
    
    DOMINIO_PRINCIPAL="${SETUPMNO_SELECTED_ROOT_DOMAIN:-${SETUPMNO_DOMAIN_ROOT:-${CLOUDFLARE_ZONE_NAME:-}}}"
    SUBDOMINIO=${url_clickhouse%%.$DOMINIO_PRINCIPAL}

    # 1. PRIMEIRO CONFIGURAR O DNS
    echo -e "XXX\n15\nCONFIGURANDO REGISTRO DNS... \nXXX"
    
    # Verificar e remover registros existentes
    EXISTING_RECORDS=$(curl -s -X GET \
        "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records?name=${url_clickhouse}" \
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
        --data "{\"type\":\"CNAME\",\"name\":\"${url_clickhouse}\",\"content\":\"${TUNNEL_ID}.cfargotunnel.com\",\"ttl\":1,\"proxied\":true}")

    if echo "$DNS_RESPONSE" | grep -q '"success":true'; then
        echo -e "XXX\n30\nREGISTRO DNS CRIADO COM SUCESSO! \nXXX"
    else
        echo -e "XXX\n30\nAVISO: ERRO AO CRIAR REGISTRO DNS \nXXX"
    fi

    # 2. AGORA ATUALIZAR AS ROTAS DO TUNNEL
    echo -e "XXX\n35\nATUALIZANDO CONFIGURAÇÃO DO TUNNEL... \nXXX"

    # Configuração do novo serviço para o Rabbitmq
    NEW_SERVICE="http://${clickhouse_internal_host}:8123"
    
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
    
    jq --arg host "$url_clickhouse" --arg service "$NEW_SERVICE" '
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
    if nslookup "$url_clickhouse" >/dev/null 2>&1; then
        echo -e "XXX\n15\nDNS CONFIGURADO \nXXX"
    else
        echo -e "XXX\n15\nAVISO: VERIFIQUE A CONFIGURAÇÃO DNS \nXXX"
    fi
fi


if [ "$INSTALL_TYPE" = "TRADICIONAL" ] && [ "$criar_dns" = "1" ]; then


# Função para verificar o domínio quando fora do cloudflare

ip_servidor=$(curl -s --max-time 10 ipinfo.io/ip)

echo -e "XXX\n3\nVERIFICANDO SUBDOMÍNIO: $url_clickhouse \nXXX"
sleep 3

tentativas=5
tentativa_atual=1
sucesso=0

while [ $tentativa_atual -le $tentativas ]; do
    echo -e "XXX\n$(( (tentativa_atual * 12) / tentativas + 3 ))\nTentativa $tentativa_atual de $tentativas...\nXXX"
    
    dns_ip3=$(timeout 10 nslookup -type=A "$url_clickhouse" | grep -E "Address: [0-9]+\." | awk '{print $2}' | head -n1)
    
    if [[ -n "$dns_ip3" && "$dns_ip3" == "$ip_servidor" ]]; then
        sucesso=1
       # break
    fi
    
  #  sleep $((tentativa_atual * 2))
  sleep 1
    ((tentativa_atual++))
done

if [ $sucesso -eq 0 ]; then

    echo -e "XXX\n10\nERRO: SUBDOMÍNIO DO CLICKHOUSE NÃO APONTA PARA O IP ($ip_servidor) \nXXX"
    sleep 3
    echo -e "XXX\n18\nERRO: DNS NÃO CONFIGURADO CORRETAMENTE \nXXX"
    sleep 3
    exit 1
fi
    echo -e "XXX\n18\nDOMÍNIO CLICKHOUSE VERIFICADO COM SUCESSO \nXXX"
sleep 4
fi


echo -e "XXX\n0\nCRIANDO STACKS DO CLICKHOUSE 1/4 \nXXX"
sleep 1
echo -e "XXX\n25\nFAZENDO O BUILD DOS STACKS DO CLICKHOUSE 2/4 \nXXX"
sleep 1
echo -e "XXX\n50\nFAZENDO O BUILD DOS STACKS DO CLICKHOUSE 2/4 - CONCLUIDO \nXXX"
sleep 1
echo -e "XXX\n50\nINICIANDO BUILD DO CLICKHOUSE 3/4 \nXXX"
sleep 1
echo -e "XXX\n75\nINICIANDO BUILD DO CLICKHOUSE 3/4 - CONCLUIDO \nXXX"



#######################################################
#
#  INSTALANDO O CLICKHOUSE
#

cd
cd


cat > $nome_app3.yaml << EOL

version: "3.7"
services:
  $nome_app3:
    image: clickhouse/clickhouse-server:25.12
    user: "101:101"

    volumes:
      - $nome_app3-data:/var/lib/clickhouse
      - $nome_app3-log:/var/log/clickhouse-server

    networks:
      externa:
      interna:
        aliases:
          - $clickhouse_internal_host

    #ports:
    #  - "8124:8123"
    #  - "9001:9000"
    #  - "9010:9009"

    environment:
      - CLICKHOUSE_DB=default
      - CLICKHOUSE_USER=$user_clickhouse
      - CLICKHOUSE_PASSWORD=$pass_clickhouse
      - TZ=UTC

    healthcheck:
      test: ["CMD-SHELL", "wget --no-verbose --tries=1 --spider http://127.0.0.1:8123/ping || exit 1"]
      interval: 5s
      timeout: 5s
      retries: 30
      start_period: 20s

    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
          - node.role == manager
EOL
# Adicionar as labels apenas se for instalação tradicional
if [ "$INSTALL_TYPE" = "TRADICIONAL" ]; then
cat >> $nome_app3.yaml << EOL
      labels:
        - traefik.enable=true
        - traefik.http.routers.$nome_app3.rule=Host(\`$url_clickhouse\`)
        - traefik.http.services.$nome_app3.loadbalancer.server.port=8123
        - traefik.http.routers.$nome_app3.service=$nome_app3
        - traefik.http.routers.$nome_app3.tls.certresolver=letsencryptresolver
        - traefik.http.services.$nome_app3.loadbalancer.passHostHeader=true
        - traefik.http.routers.$nome_app3.entrypoints=websecure
        - traefik.http.routers.$nome_app3.tls=true        

EOL
fi
cat >> $nome_app3.yaml << EOL
volumes:
  $nome_app3-data:
    external: true
    name: $nome_app3-data
  $nome_app3-log:
    external: true
    name: $nome_app3-log
  
networks: 
  externa: 
    external: true
  interna: 
    external: true


EOL

for clickhouse_volume in "$nome_app3-data" "$nome_app3-log"; do
    if ! docker volume inspect "$clickhouse_volume" >/dev/null 2>&1 &&
       ! docker volume create "$clickhouse_volume" >> "$LANGFUSE_INSTALL_LOG" 2>&1; then
        langfuse_fail 32 "Não foi possível criar o volume persistente $clickhouse_volume."
    fi
done

#docker stack deploy --prune --resolve-image always -c $nome_app.yaml $nome_app >/dev/null 2>&1


echo -e "XXX\n70\nIMPLANTANDO BASEROW... \nXXX"


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
STACK_NAME=$nome_app3
STACK_FILE_PATH="/root/$nome_app3.yaml"

else
   # echo "Erro: Arquivo de dados não encontrado em $dados_file."
    sleep 5
echo -e "XXX\n77\nSEM ARQUIVO DE DADOS DO PORTAINER 3/4  \nXXX"
docker stack deploy --prune --resolve-image always -c $nome_app3.yaml $nome_app3 >/dev/null 2>&1
sleep 5
    exit 1
fi

# Função para autenticação
get_auth_token() {
    #echo "[INFO] Autenticando no Portainer..."
    echo -e "XXX\n77\nAUTENTICANDO NO PORTAINER... 3/4  \nXXX"
    PORTAINER_DIAG_STAGE="clickhouse_auth"
    RESPONSE=$(portainer_api_curl -sS -X POST "https://$PORTAINER_URL/api/auth" \
        -H "Content-Type: application/json" \
        -d "{\"username\": \"$ADMIN_USERNAME\", \"password\": \"$ADMIN_PASSWORD\"}")
    TOKEN=$(echo "$RESPONSE" | jq -r '.jwt' 2>/dev/null)
    if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]; then
        # echo "[ERRO] Falha na autenticação."
        portainer_log_failure "clickhouse_auth_invalid_response" "0" "nao_validado" "$(printf '%s' "$RESPONSE" | wc -c)"
        echo -e "XXX\n77\nFALHA NA AUTENTICAÇÃO. LOG: $PORTAINER_DIAG_LOG 3/4  \nXXX"
sleep 5
echo -e "XXX\n78\nREVERTENDO E CRIANDO STACK PELO SERVIDOR 3/4  \nXXX"
docker stack deploy --prune --resolve-image always -c $nome_app3.yaml $nome_app3 >/dev/null 2>&1
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
    PORTAINER_DIAG_STAGE="clickhouse_endpoints"
    RESPONSE=$(portainer_api_curl -sS -X GET "https://$PORTAINER_URL/api/endpoints" \
        -H "Authorization: Bearer $TOKEN")
    ENDPOINT_ID=$(echo "$RESPONSE" | jq -r '.[0].Id' 2>/dev/null)
    if [ -z "$ENDPOINT_ID" ] || [ "$ENDPOINT_ID" = "null" ]; then
        # echo "[ERRO] EndpointID não encontrado! Resposta: $RESPONSE"
        portainer_log_failure "clickhouse_endpoints_invalid_response" "0" "nao_validado" "$(printf '%s' "$RESPONSE" | wc -c)"
        echo -e "XXX\n81\n[ERRO] ENDPOINTID NÃO ENCONTRADO. LOG: $PORTAINER_DIAG_LOG 3/4  \nXXX"
        docker stack deploy --prune --resolve-image always -c $nome_app3.yaml $nome_app3 >/dev/null 2>&1
        exit 1
    fi
     echo -e "XXX\n82\n[SUCESSO] ENDPOINTID OBTIDO: $ENDPOINT_ID  3/4  \nXXX"
    #echo "[SUCESSO] EndpointID obtido: $ENDPOINT_ID"
}

# Função para obter o SwarmID
get_swarm_id() {
   # echo "[INFO] Obtendo SwarmID..."
    echo -e "XXX\n83\n[INFO] OBTENDO SWARMID  3/4  \nXXX"
    PORTAINER_DIAG_STAGE="clickhouse_swarm"
    RESPONSE=$(portainer_api_curl -sS -X GET "https://$PORTAINER_URL/api/endpoints/$ENDPOINT_ID/docker/swarm" \
        -H "Authorization: Bearer $TOKEN")
    SWARM_ID=$(echo "$RESPONSE" | jq -r '.ID' 2>/dev/null)
    if [ -z "$SWARM_ID" ] || [ "$SWARM_ID" = "null" ]; then
        #echo "[ERRO] SwarmID não encontrado! Resposta: $RESPONSE"
        portainer_log_failure "clickhouse_swarm_invalid_response" "0" "nao_validado" "$(printf '%s' "$RESPONSE" | wc -c)"
        echo -e "XXX\n84\n[ERRO] SWARMID NÃO ENCONTRADO. LOG: $PORTAINER_DIAG_LOG 3/4  \nXXX"
        docker stack deploy --prune --resolve-image always -c $nome_app3.yaml $nome_app3 >/dev/null 2>&1
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
        docker stack deploy --prune --resolve-image always -c $nome_app3.yaml $nome_app3 >/dev/null 2>&1
        exit 1
    fi

    #echo "[INFO] Criando stack '$STACK_NAME' no Portainer..."
     echo -e "XXX\n88\n[INFO] CRIANDO STACK $STACK_NAME NO PORTAINER 3/4  \nXXX"
    response_output=$(mktemp)
    erro_output=$(mktemp)

    PORTAINER_DIAG_STAGE="clickhouse_create"
    http_code=$(portainer_upload_curl -sS -o "$response_output" -w "%{http_code}" -X POST \
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

    if [ "$http_code" != "200" ]; then
       # echo "[ERRO] Erro ao criar a stack. Código HTTP: $http_code. Resposta: $response"
        portainer_log_failure "clickhouse_create_http" "0" "${http_code:-000}" "$(printf '%s' "$response" | wc -c)"
        echo -e "XXX\n89\n[ERRO] ERRO AO CRIAR STACK. LOG: $PORTAINER_DIAG_LOG 3/4  \nXXX"
        docker stack deploy --prune --resolve-image always -c $nome_app3.yaml $nome_app3 >/dev/null 2>&1
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
    echo -e "XXX\n91\nCRIANDO STACK NO PORTAINER 3/4  \nXXX"
    docker stack deploy --prune --resolve-image always \
        -c "$nome_app3.yaml" "$nome_app3" >> "$LANGFUSE_INSTALL_LOG" 2>&1 ||
        langfuse_fail 35 "O Docker Swarm recusou a stack do ClickHouse."
else
    # Caso inesperado (não deve ocorrer devido à validação anterior no while loop)
   # echo "Erro: valor inesperado para criar_portainer. Encerrando..."
    echo -e "XXX\n91\n[ERRO] ERRO INESPERADO PARA CRIAR STACK NO PORTAINER 3/4  \nXXX"
    sleep 5
    echo -e "XXX\n92\nREVERTENDO E CRIANDO STACK PELO SERVIDOR 3/4  \nXXX"
docker stack deploy --prune --resolve-image always -c $nome_app3.yaml $nome_app3 >/dev/null 2>&1
sleep 5

    exit 1
fi

wait_service_healthy "$clickhouse_service" "ClickHouse" 36

echo -e "XXX\n90\nAGUARDANDO SERVIÇOS INICIALIZAREM... \nXXX"
sleep 15

echo -e "XXX\n75\nFINALIZANDO BUILD DO CLICKHOUSE 4/4  \nXXX"

sleep 2

echo -e "XXX\n100\nFINALIZANDO BUILD DO CLICKHOUSE 4/4 - CONCLUIDO  \nXXX"

sleep 3


fi


# Função para verificar o domínio
echo -e "XXX\n5\nVERIFICANDO CONFIGURAÇÃO... \nXXX"

if [ "$INSTALL_TYPE" = "TRADICIONAL" ] && [ "$criar_dns" = "0" ]; then
    # CONFIGURAÇÃO TRADICIONAL COM DNS AUTOMÁTICO
    echo -e "XXX\n10\nCONFIGURANDO DNS AUTOMÁTICO (TRADICIONAL)... \nXXX"
    
    DOMINIO_PRINCIPAL="${SETUPMNO_SELECTED_ROOT_DOMAIN:-${SETUPMNO_DOMAIN_ROOT:-${CLOUDFLARE_ZONE_NAME:-}}}"
    SUBDOMINIO=${url_langfuse%%.$DOMINIO_PRINCIPAL}

    # Verificar e remover registros existentes
    echo -e "XXX\n15\nVERIFICANDO REGISTROS EXISTENTES... \nXXX"
    EXISTING_RECORDS=$(curl -s -X GET \
        "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records?name=${url_langfuse}" \
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
        --data '{"type":"CNAME","name":"'${url_langfuse}'","content":"'${nome_servidor}'.'${DOMINIO_PRINCIPAL}'","ttl":1,"proxied":false}')

    if echo "$CNAME_RESPONSE" | grep -q '"success":true'; then
        echo -e "XXX\n30\nREGISTRO CNAME CRIADO COM SUCESSO! \nXXX"
    else
        echo -e "XXX\n30\nAVISO: ERRO AO CRIAR REGISTRO CNAME \nXXX"
    fi

elif [ "$INSTALL_TYPE" = "CLOUDFLARE_TUNNEL" ]; then
    # CONFIGURAÇÃO CLOUDFLARE TUNNEL - DNS E ROTAS
    echo -e "XXX\n10\nCONFIGURANDO CLOUDFLARE TUNNEL (DNS + ROTAS)... \nXXX"
    
    DOMINIO_PRINCIPAL="${SETUPMNO_SELECTED_ROOT_DOMAIN:-${SETUPMNO_DOMAIN_ROOT:-${CLOUDFLARE_ZONE_NAME:-}}}"
    SUBDOMINIO=${url_langfuse%%.$DOMINIO_PRINCIPAL}

    # 1. PRIMEIRO CONFIGURAR O DNS
    echo -e "XXX\n15\nCONFIGURANDO REGISTRO DNS... \nXXX"
    
    # Verificar e remover registros existentes
    EXISTING_RECORDS=$(curl -s -X GET \
        "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records?name=${url_langfuse}" \
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
        --data "{\"type\":\"CNAME\",\"name\":\"${url_langfuse}\",\"content\":\"${TUNNEL_ID}.cfargotunnel.com\",\"ttl\":1,\"proxied\":true}")

    if echo "$DNS_RESPONSE" | grep -q '"success":true'; then
        echo -e "XXX\n30\nREGISTRO DNS CRIADO COM SUCESSO! \nXXX"
    else
        echo -e "XXX\n30\nAVISO: ERRO AO CRIAR REGISTRO DNS \nXXX"
    fi

    # 2. AGORA ATUALIZAR AS ROTAS DO TUNNEL
    echo -e "XXX\n35\nATUALIZANDO CONFIGURAÇÃO DO TUNNEL... \nXXX"

    # Configuração do novo serviço para o Baserow
    NEW_SERVICE="http://${nome_app}:3000"
    
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
    
    jq --arg host "$url_langfuse" --arg service "$NEW_SERVICE" '
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
    if nslookup "$url_langfuse" >/dev/null 2>&1; then
        echo -e "XXX\n15\nDNS CONFIGURADO \nXXX"
    else
        echo -e "XXX\n15\nAVISO: VERIFIQUE A CONFIGURAÇÃO DNS \nXXX"
    fi
fi


if [ "$INSTALL_TYPE" = "TRADICIONAL" ] && [ "$criar_dns" = "1" ]; then


# Função para verificar o domínio quando fora do cloudflare
# url_langfuse=$1
ip_servidor=$(curl -s --max-time 10 ipinfo.io/ip)

echo -e "XXX\n3\nVERIFICANDO SUBDOMÍNIO: $url_langfuse \nXXX"
sleep 3

tentativas=5
tentativa_atual=1
sucesso=0

while [ $tentativa_atual -le $tentativas ]; do
    echo -e "XXX\n$(( (tentativa_atual * 12) / tentativas + 3 ))\nTentativa $tentativa_atual de $tentativas...\nXXX"
    
    dns_ip4=$(timeout 10 nslookup -type=A "$url_langfuse" | grep -E "Address: [0-9]+\." | awk '{print $2}' | head -n1)
    
    if [[ -n "$dns_ip4" && "$dns_ip4" == "$ip_servidor" ]]; then
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
   
echo -e "XXX\n23\nINSTALANDO LANGFUSE 1/4 \nXXX"
sleep 1
echo -e "XXX\n26\nFAZENDO O BUILD DO STACK DO LANGFUSE 2/4 \nXXX"
sleep 1
echo -e "XXX\n50\nFAZENDO O BUILD DO STACK DO LANGFUSE 2/4 - CONCLUIDO \nXXX"
sleep 1
echo -e "XXX\n50\nCRIANDO BANCO DE DADOS DO LANGFUSE 3/4 \nXXX"
sleep 1
echo -e "XXX\n75\nAGUARDANDO PROPAGAÇÃO - PODE DEMORAR UM POUCO \nXXX"




#######################################################
#
#  INSTALANDO O LANGFUSE
#

cd

cd
clear

###### valida o MinIO pela rede interna do Swarm

max_wait_time=300
wait_interval=5
elapsed_time=0
CONTAINER_ID=""

while [ "$elapsed_time" -lt "$max_wait_time" ]; do
    remaining_time=$((max_wait_time - elapsed_time))
    echo -e "XXX\n75\nAGUARDANDO SERVIÇO MINIO: ${elapsed_time}s decorridos, limite ${max_wait_time}s (${remaining_time}s restantes)\nXXX"
    if [[ -n "$minio_container" ]]; then
        CONTAINER_ID="$minio_container"
    else
        CONTAINER_ID=$(docker ps \
            --filter "label=com.docker.swarm.service.name=$minio_service" \
            --format '{{.ID}}' | head -n1)
    fi
    [ -n "$CONTAINER_ID" ] && break
    sleep "$wait_interval"
    elapsed_time=$((elapsed_time + wait_interval))
done

if [ -z "$CONTAINER_ID" ]; then
    langfuse_fail 61 "O serviço MinIO não criou um container em até ${max_wait_time} segundos. O Langfuse não foi implantado."
fi

# A mesma imagem validada do servidor contém o binário mc e é multiarch.
MINIO_MC_IMAGE="quay.io/minio/minio:RELEASE.2025-04-08T15-41-24Z"
minio_mc_service="${nome_app}-mc-internal"
minio_root_user_secret="${nome_app}-mc-root-user"
minio_root_password_secret="${nome_app}-mc-root-password"
minio_access_key_secret="${nome_app}-mc-access-key"
minio_secret_key_secret="${nome_app}-mc-secret-key"
bucket_name="$nome_app"
access_key=$(langfuse_generate_minio_access_key) ||
    langfuse_fail 65 "Não foi possível gerar uma chave S3 compatível com o limite do MinIO."
secret_key=$(openssl rand -hex 20)

cleanup_minio_mc_resources() {
    local attempt
    timeout --signal=TERM --kill-after=2s 20s \
        docker service rm "$minio_mc_service" >/dev/null 2>&1 || true
    for attempt in $(seq 1 20); do
        timeout --signal=TERM --kill-after=2s 5s \
            docker service inspect "$minio_mc_service" >/dev/null 2>&1 || break
        sleep 1
    done
    timeout --signal=TERM --kill-after=2s 20s docker secret rm \
        "$minio_root_user_secret" \
        "$minio_root_password_secret" \
        "$minio_access_key_secret" \
        "$minio_secret_key_secret" >/dev/null 2>&1 || true
}

cleanup_minio_mc_resources
trap cleanup_minio_mc_resources EXIT

echo -e "XXX\n75\nPREPARANDO CLIENTE MINIO INTERNO (X86/ARM)\nXXX"
if ! docker image inspect "$MINIO_MC_IMAGE" >/dev/null 2>&1; then
    if ! timeout --signal=TERM --kill-after=5s 180s \
        docker pull "$MINIO_MC_IMAGE" >> "$LANGFUSE_INSTALL_LOG" 2>&1; then
        langfuse_fail 62 "Não foi possível obter a imagem fixada do MinIO Client. Verifique a conexão do servidor e tente novamente."
    fi
fi

printf '%s' "$MINIO_USER" | docker secret create "$minio_root_user_secret" - \
    >> "$LANGFUSE_INSTALL_LOG" 2>&1 ||
    langfuse_fail 63 "Não foi possível proteger o usuário interno do MinIO como Docker Secret."
printf '%s' "$MINIO_PASSWORD" | docker secret create "$minio_root_password_secret" - \
    >> "$LANGFUSE_INSTALL_LOG" 2>&1 ||
    langfuse_fail 64 "Não foi possível proteger a senha interna do MinIO como Docker Secret."
printf '%s' "$access_key" | docker secret create "$minio_access_key_secret" - \
    >> "$LANGFUSE_INSTALL_LOG" 2>&1 ||
    langfuse_fail 65 "Não foi possível proteger a chave S3 do Langfuse como Docker Secret temporário."
printf '%s' "$secret_key" | docker secret create "$minio_secret_key_secret" - \
    >> "$LANGFUSE_INSTALL_LOG" 2>&1 ||
    langfuse_fail 66 "Não foi possível proteger o segredo S3 do Langfuse como Docker Secret temporário."

if ! docker service create --quiet --detach \
    --name "$minio_mc_service" \
    --network interna \
    --constraint 'node.role==manager' \
    --restart-condition none \
    --secret "source=$minio_root_user_secret,target=minio_root_user" \
    --secret "source=$minio_root_password_secret,target=minio_root_password" \
    --secret "source=$minio_access_key_secret,target=langfuse_access_key" \
    --secret "source=$minio_secret_key_secret,target=langfuse_secret_key" \
    --entrypoint /bin/sh \
    "$MINIO_MC_IMAGE" -c '
        set -eu
        root_user=$(cat /run/secrets/minio_root_user)
        root_password=$(cat /run/secrets/minio_root_password)
        access_key=$(cat /run/secrets/langfuse_access_key)
        secret_key=$(cat /run/secrets/langfuse_secret_key)
        if [ "${#access_key}" -lt 3 ] || [ "${#access_key}" -gt 20 ]; then
            echo "stage=minio_service_account status=invalid_access_key_length" >&2
            exit 68
        fi
        attempt=1
        while [ "$attempt" -le 30 ]; do
            if mc --config-dir /tmp/mc alias set minio "http://$1:9000" "$root_user" "$root_password" --api S3v4 >/dev/null 2>&1 &&
               mc --config-dir /tmp/mc ready --quiet minio >/dev/null 2>&1; then
                mc --config-dir /tmp/mc mb --ignore-existing "minio/$2" >/dev/null
                policy_file=/tmp/langfuse-bucket-policy.json
                printf "{\\\"Version\\\":\\\"2012-10-17\\\",\\\"Statement\\\":[{\\\"Effect\\\":\\\"Allow\\\",\\\"Action\\\":[\\\"s3:ListBucket\\\",\\\"s3:GetBucketLocation\\\"],\\\"Resource\\\":[\\\"arn:aws:s3:::%s\\\"]},{\\\"Effect\\\":\\\"Allow\\\",\\\"Action\\\":[\\\"s3:GetObject\\\",\\\"s3:PutObject\\\",\\\"s3:DeleteObject\\\",\\\"s3:AbortMultipartUpload\\\",\\\"s3:ListMultipartUploadParts\\\"],\\\"Resource\\\":[\\\"arn:aws:s3:::%s/*\\\"]}]}" "$2" "$2" > "$policy_file"
                if ! mc --config-dir /tmp/mc admin user svcacct add minio "$root_user" \
                    --access-key "$access_key" --secret-key "$secret_key" \
                    --policy "$policy_file" --json >/dev/null 2>&1; then
                    echo "stage=minio_service_account status=create_failed" >&2
                    exit 68
                fi
                exit 0
            fi
            attempt=$((attempt + 1))
            sleep 2
        done
        exit 67
    ' sh "$minio_internal_host" "$bucket_name" >> "$LANGFUSE_INSTALL_LOG" 2>&1; then
    langfuse_fail 67 "Não foi possível iniciar a validação interna e o provisionamento seguro do MinIO."
fi

minio_mc_ready=0
for tentativa in $(seq 1 60); do
    echo -e "XXX\n75\nVALIDANDO MINIO INTERNAMENTE: tentativa ${tentativa}/60\nXXX"
    minio_mc_state=$(timeout --signal=TERM --kill-after=2s 10s \
        docker service ps "$minio_mc_service" --no-trunc \
        --format '{{.CurrentState}}' 2>> "$LANGFUSE_INSTALL_LOG" | head -n1)
    case "$minio_mc_state" in
        Complete*) minio_mc_ready=1; break ;;
        Failed*|Rejected*|Shutdown*) break ;;
    esac
    sleep 5
done

if [ "$minio_mc_ready" -ne 1 ]; then
    timeout --signal=TERM --kill-after=2s 15s \
        docker service ps "$minio_mc_service" --no-trunc \
        --format 'Estado: {{.CurrentState}} | Erro: {{.Error}}' \
        >> "$LANGFUSE_INSTALL_LOG" 2>&1 || true
    timeout --signal=TERM --kill-after=2s 15s \
        docker service logs --raw --tail 100 "$minio_mc_service" \
        >> "$LANGFUSE_INSTALL_LOG" 2>&1 || true
    cleanup_minio_mc_resources
    trap - EXIT
    langfuse_fail 68 "O MinIO não ficou pronto pela rede interna ou recusou a criação segura do bucket/credenciais. Consulte o log informado."
fi

cleanup_minio_mc_resources
trap - EXIT

# O ClickHouse precisa estar pronto e autenticado antes do primeiro boot do
# Langfuse. O comando antigo usava -it, ignorava as credenciais e prosseguia
# mesmo após falhar, deixando as migrations em loop.
clickhouse_ready=0
clickhouse_max_attempts=30
for tentativa in $(seq 1 "$clickhouse_max_attempts"); do
    echo -e "XXX\n82\nVALIDANDO CLICKHOUSE: tentativa ${tentativa}/${clickhouse_max_attempts} (timeout de 8s por tentativa)\nXXX"
    clickhouse_container=$(docker ps \
        --filter "label=com.docker.swarm.service.name=$clickhouse_service" \
        --format '{{.ID}}' | head -n1)
    if [[ -n "$clickhouse_container" ]] && \
        timeout --signal=TERM --kill-after=2s 8s \
        docker exec "$clickhouse_container" sh -c \
        'clickhouse-client --user "$CLICKHOUSE_USER" --password "$CLICKHOUSE_PASSWORD" --query "SELECT 1"' \
        >/dev/null 2>&1; then
        clickhouse_ready=1
        break
    fi
    sleep 2
done

if [[ "$clickhouse_ready" -ne 1 ]]; then
    langfuse_fail 69 "O ClickHouse não ficou pronto ou rejeitou as credenciais. A stack do Langfuse não foi criada."
fi

clickhouse_version=$(timeout --signal=TERM --kill-after=2s 15s \
    docker exec "$clickhouse_container" sh -c \
    'clickhouse-client --user "$CLICKHOUSE_USER" --password "$CLICKHOUSE_PASSWORD" --query "SELECT version()"' \
    2>/dev/null || true)
clickhouse_major=${clickhouse_version%%.*}
clickhouse_minor=${clickhouse_version#*.}
clickhouse_minor=${clickhouse_minor%%.*}
if [[ ! "$clickhouse_major" =~ ^[0-9]+$ ]] || [[ ! "$clickhouse_minor" =~ ^[0-9]+$ ]] || \
   (( clickhouse_major < 25 || (clickhouse_major == 25 && clickhouse_minor < 12) )); then
    langfuse_fail 70 "O Langfuse 4 exige ClickHouse 25.12 ou superior; versão encontrada: ${clickhouse_version:-desconhecida}."
fi

container_id=$(docker ps --filter name=postgres --format '{{.ID}}' | head -n1)
if [[ -z "$container_id" ]]; then
    langfuse_fail 71 "O serviço PostgreSQL não possui um container ativo."
fi

# Uma tentativa anterior pode ter criado o banco e falhado antes do deploy da
# stack. Reutilize esse banco em vez de transformar a recuperação em erro.
postgres_database_exists=$(docker exec "$container_id" \
    psql -U postgres -d postgres -tAc \
    "SELECT 1 FROM pg_database WHERE datname = '$nome_app';" 2>/dev/null)
if [[ "$postgres_database_exists" != "1" ]] && ! docker exec "$container_id" \
    psql -U postgres -d postgres -v ON_ERROR_STOP=1 \
    -c "CREATE DATABASE $nome_app;" >/dev/null 2>&1; then
    langfuse_fail 71 "Não foi possível criar ou reutilizar o banco PostgreSQL do Langfuse após validar MinIO e ClickHouse."
fi

if ! timeout --signal=TERM --kill-after=2s 15s \
    docker exec "$clickhouse_container" sh -c \
        'clickhouse-client --user "$CLICKHOUSE_USER" --password "$CLICKHOUSE_PASSWORD" --query "$1"' \
        sh "CREATE DATABASE IF NOT EXISTS \`$nome_app\`" >/dev/null 2>&1; then
    langfuse_fail 72 "Não foi possível criar o banco do Langfuse no ClickHouse."
fi

echo -e "XXX\n75\nBANCO $nome_app CRIADO E VALIDADO \nXXX"

# Redis dedicado em stack separada. Para BullMQ/Langfuse a política oficial é
# noeviction; descartar chaves silenciosamente corromperia filas de ingestão.
redis_stack_name="${nome_app}-redis"
redis_service_name="${redis_stack_name}_${nome_app}-redis"
redis_internal_host="${nome_app}-redis"
redis_volume="${nome_app}-redis-data"
redis_password=$(openssl rand -hex 24)
redis_yaml="/root/${redis_stack_name}.yaml"

if ! docker volume inspect "$redis_volume" >/dev/null 2>&1 &&
   ! docker volume create "$redis_volume" >> "$LANGFUSE_INSTALL_LOG" 2>&1; then
    langfuse_fail 73 "Não foi possível criar o volume persistente do Redis dedicado."
fi

cat > "$redis_yaml" <<EOL
version: "3.7"
services:
  $nome_app-redis:
    image: redis:7-alpine
    command:
      - redis-server
      - --requirepass
      - $redis_password
      - --appendonly
      - "yes"
      - --maxmemory
      - 256mb
      - --maxmemory-policy
      - noeviction
    networks:
      interna:
        aliases:
          - $redis_internal_host
    volumes:
      - $redis_volume:/data
    healthcheck:
      test: ["CMD-SHELL", "redis-cli -a '$redis_password' ping | grep -q PONG"]
      interval: 10s
      timeout: 5s
      retries: 30
      start_period: 10s
    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
          - node.role == manager
      resources:
        limits:
          cpus: "0.50"
          memory: 384M
volumes:
  $redis_volume:
    external: true
    name: $redis_volume
networks:
  interna:
    external: true
EOL

echo -e "XXX\n84\nCRIANDO REDIS DEDICADO EM STACK SEPARADA\nXXX"
deploy_stack_checked "$redis_stack_name" "$redis_yaml" 74
wait_service_healthy "$redis_service_name" "Redis dedicado do Langfuse" 75

## Criando key Aleatória 64caracteres
key_encryption=$(openssl rand -hex 32)

## Criando key Aleatória 64caracteres
key_secret=$(openssl rand -hex 32)

## Criando key Aleatória 32caracteres
key_salt=$(openssl rand -hex 32)



cat > $nome_app.yaml <<EOL
version: "3.7"
services:


  $nome_app:
    image: langfuse/langfuse:4

    networks:
      externa:
      interna:
        aliases:
          - $nome_app

    environment:
      ## Url do Langfuse
      - NEXTAUTH_URL=https://$url_langfuse

      ## Desativar novas incrições
      - NEXT_PUBLIC_SIGN_UP_DISABLED=false

      ## Secrets Key
      - ENCRYPTION_KEY=$key_encryption
      - NEXTAUTH_SECRET=$key_secret
      - SALT=$key_salt

      ## Dados Postgres
      - DATABASE_URL=postgresql://postgres:$postgres_password@postgres:5432/$nome_app

      ## Dados do ClickHouse
      - CLICKHOUSE_MIGRATION_URL=clickhouse://$clickhouse_internal_host:9000
      - CLICKHOUSE_URL=http://$clickhouse_internal_host:8123
      - CLICKHOUSE_USER=$USUARIO_CLICKHOUSE
      - CLICKHOUSE_PASSWORD=$SENHA_CLICKHOUSE
      - CLICKHOUSE_CLUSTER_ENABLED=false
      - CLICKHOUSE_DB=$nome_app


     ## Dados Redis
      - REDIS_CONNECTION_STRING=redis://:$redis_password@$redis_internal_host:6379


      ## Dados do S3 - Eventos
      - LANGFUSE_S3_EVENT_UPLOAD_ENDPOINT=http://$minio_internal_host:9000
      - LANGFUSE_S3_EVENT_UPLOAD_BUCKET=$nome_app
      - LANGFUSE_S3_EVENT_UPLOAD_ACCESS_KEY_ID=$access_key
      - LANGFUSE_S3_EVENT_UPLOAD_SECRET_ACCESS_KEY=$secret_key
      - LANGFUSE_S3_EVENT_UPLOAD_REGION=auto
      - LANGFUSE_S3_EVENT_UPLOAD_FORCE_PATH_STYLE=true
      - LANGFUSE_S3_EVENT_UPLOAD_PREFIX=events/


      ## Dados do S3 - Medias
      - LANGFUSE_S3_MEDIA_UPLOAD_ENDPOINT=https://$MINIO_PUBLIC_URL
      - LANGFUSE_S3_MEDIA_UPLOAD_BUCKET=$nome_app
      - LANGFUSE_S3_MEDIA_UPLOAD_ACCESS_KEY_ID=$access_key
      - LANGFUSE_S3_MEDIA_UPLOAD_SECRET_ACCESS_KEY=$secret_key
      - LANGFUSE_S3_MEDIA_UPLOAD_REGION=auto
      - LANGFUSE_S3_MEDIA_UPLOAD_FORCE_PATH_STYLE=true
      - LANGFUSE_S3_MEDIA_UPLOAD_PREFIX=media/

      ## Exportações em lote usam o endpoint interno; downloads web continuam
      ## assinados pelo endpoint público acima.
      - LANGFUSE_S3_BATCH_EXPORT_ENABLED=true
      - LANGFUSE_S3_BATCH_EXPORT_ENDPOINT=http://$minio_internal_host:9000
      - LANGFUSE_S3_BATCH_EXPORT_BUCKET=$nome_app
      - LANGFUSE_S3_BATCH_EXPORT_ACCESS_KEY_ID=$access_key
      - LANGFUSE_S3_BATCH_EXPORT_SECRET_ACCESS_KEY=$secret_key
      - LANGFUSE_S3_BATCH_EXPORT_REGION=auto
      - LANGFUSE_S3_BATCH_EXPORT_FORCE_PATH_STYLE=true
      - LANGFUSE_S3_BATCH_EXPORT_PREFIX=exports/

      ## Ativar Telemetria
      - TELEMETRY_ENABLED=false

      ## Features experimentais
      - LANGFUSE_ENABLE_EXPERIMENTAL_FEATURES=false

      ## Node
      - NODE_ENV=production
      - NODE_OPTIONS=--max-old-space-size=1536
      - HOSTNAME=0.0.0.0
      - TZ=UTC

    healthcheck:
      test: ["CMD-SHELL", "wget -q --spider 'http://127.0.0.1:3000/api/public/health?failIfDatabaseUnavailable=true' || exit 1"]
      interval: 10s
      timeout: 5s
      retries: 30
      start_period: 90s

    deploy:
      mode: replicated
      replicas: 1
      placement:
          constraints:
            - node.role == manager
      resources:
          limits:
            cpus: '1'
            memory: 2048M
EOL
# Adicionar as labels apenas se for instalação tradicional
if [ "$INSTALL_TYPE" = "TRADICIONAL" ]; then
cat >> $nome_app.yaml << EOL
      labels:
        - traefik.enable=true
        - traefik.http.routers.$nome_app.rule=Host(\`$url_langfuse\`)
        - traefik.http.routers.$nome_app.entrypoints=websecure
        - traefik.http.routers.$nome_app.tls.certresolver=letsencryptresolver
        - traefik.http.routers.$nome_app.service=$nome_app
        - traefik.http.services.$nome_app.loadbalancer.passHostHeader=true
        - traefik.http.services.$nome_app.loadbalancer.server.port=3000
EOL
fi
cat >> $nome_app.yaml << EOL

  $nome_app-worker:
    image: langfuse/langfuse-worker:4

    networks:
      externa:
      interna:
        aliases:
          - $nome_app-worker

    environment:
      ## Url do Langfuse
      - NEXTAUTH_URL=https://$url_langfuse

      ## Desativar novas incrições
      - NEXT_PUBLIC_SIGN_UP_DISABLED=false

      ## Secrets Key
      - ENCRYPTION_KEY=$key_encryption
      - NEXTAUTH_SECRET=$key_secret
      - SALT=$key_salt

      ## Dados Postgres
      - DATABASE_URL=postgresql://postgres:$postgres_password@postgres:5432/$nome_app

      ## Dados do ClickHouse
      - CLICKHOUSE_MIGRATION_URL=clickhouse://$clickhouse_internal_host:9000
      - CLICKHOUSE_URL=http://$clickhouse_internal_host:8123
      - CLICKHOUSE_USER=$USUARIO_CLICKHOUSE
      - CLICKHOUSE_PASSWORD=$SENHA_CLICKHOUSE
      - CLICKHOUSE_CLUSTER_ENABLED=false
      - CLICKHOUSE_DB=$nome_app


     ## Dados Redis
      - REDIS_CONNECTION_STRING=redis://:$redis_password@$redis_internal_host:6379


      ## Dados do S3 - Eventos
      - LANGFUSE_S3_EVENT_UPLOAD_ENDPOINT=http://$minio_internal_host:9000
      - LANGFUSE_S3_EVENT_UPLOAD_BUCKET=$nome_app
      - LANGFUSE_S3_EVENT_UPLOAD_ACCESS_KEY_ID=$access_key
      - LANGFUSE_S3_EVENT_UPLOAD_SECRET_ACCESS_KEY=$secret_key
      - LANGFUSE_S3_EVENT_UPLOAD_REGION=auto
      - LANGFUSE_S3_EVENT_UPLOAD_FORCE_PATH_STYLE=true
      - LANGFUSE_S3_EVENT_UPLOAD_PREFIX=events/


      ## Dados do S3 - Medias
      - LANGFUSE_S3_MEDIA_UPLOAD_ENDPOINT=http://$minio_internal_host:9000
      - LANGFUSE_S3_MEDIA_UPLOAD_BUCKET=$nome_app
      - LANGFUSE_S3_MEDIA_UPLOAD_ACCESS_KEY_ID=$access_key
      - LANGFUSE_S3_MEDIA_UPLOAD_SECRET_ACCESS_KEY=$secret_key
      - LANGFUSE_S3_MEDIA_UPLOAD_REGION=auto
      - LANGFUSE_S3_MEDIA_UPLOAD_FORCE_PATH_STYLE=true
      - LANGFUSE_S3_MEDIA_UPLOAD_PREFIX=media/

      - LANGFUSE_S3_BATCH_EXPORT_ENABLED=true
      - LANGFUSE_S3_BATCH_EXPORT_ENDPOINT=http://$minio_internal_host:9000
      - LANGFUSE_S3_BATCH_EXPORT_BUCKET=$nome_app
      - LANGFUSE_S3_BATCH_EXPORT_ACCESS_KEY_ID=$access_key
      - LANGFUSE_S3_BATCH_EXPORT_SECRET_ACCESS_KEY=$secret_key
      - LANGFUSE_S3_BATCH_EXPORT_REGION=auto
      - LANGFUSE_S3_BATCH_EXPORT_FORCE_PATH_STYLE=true
      - LANGFUSE_S3_BATCH_EXPORT_PREFIX=exports/

      ## Ativar Telemetria
      - TELEMETRY_ENABLED=false

      ## Features experimentais
      - LANGFUSE_ENABLE_EXPERIMENTAL_FEATURES=false

      ## Node
      - NODE_ENV=production
      - NODE_OPTIONS=--max-old-space-size=1536
      - HOSTNAME=0.0.0.0
      - TZ=UTC

    healthcheck:
      test: ["CMD-SHELL", "wget -q --spider http://127.0.0.1:3030/api/health || exit 1"]
      interval: 10s
      timeout: 5s
      retries: 30
      start_period: 60s

    deploy:
      mode: replicated
      replicas: 1
      placement:
          constraints:
            - node.role == manager
      resources:
          limits:
            cpus: '1'
            memory: 2048M
networks:
  interna:
    external: true
  externa:
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
    PORTAINER_DIAG_STAGE="langfuse_auth"
    RESPONSE=$(portainer_api_curl -sS -X POST "https://$PORTAINER_URL/api/auth" \
        -H "Content-Type: application/json" \
        -d "{\"username\": \"$ADMIN_USERNAME\", \"password\": \"$ADMIN_PASSWORD\"}")
    TOKEN=$(echo "$RESPONSE" | jq -r '.jwt' 2>/dev/null)
    if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]; then
        # echo "[ERRO] Falha na autenticação."
        portainer_log_failure "langfuse_auth_invalid_response" "0" "nao_validado" "$(printf '%s' "$RESPONSE" | wc -c)"
        echo -e "XXX\n77\nFALHA NA AUTENTICAÇÃO. LOG: $PORTAINER_DIAG_LOG 3/4  \nXXX"
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
    PORTAINER_DIAG_STAGE="langfuse_endpoints"
    RESPONSE=$(portainer_api_curl -sS -X GET "https://$PORTAINER_URL/api/endpoints" \
        -H "Authorization: Bearer $TOKEN")
    ENDPOINT_ID=$(echo "$RESPONSE" | jq -r '.[0].Id' 2>/dev/null)
    if [ -z "$ENDPOINT_ID" ] || [ "$ENDPOINT_ID" = "null" ]; then
        # echo "[ERRO] EndpointID não encontrado! Resposta: $RESPONSE"
        portainer_log_failure "langfuse_endpoints_invalid_response" "0" "nao_validado" "$(printf '%s' "$RESPONSE" | wc -c)"
        echo -e "XXX\n81\n[ERRO] ENDPOINTID NÃO ENCONTRADO. LOG: $PORTAINER_DIAG_LOG 3/4  \nXXX"
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
    PORTAINER_DIAG_STAGE="langfuse_swarm"
    RESPONSE=$(portainer_api_curl -sS -X GET "https://$PORTAINER_URL/api/endpoints/$ENDPOINT_ID/docker/swarm" \
        -H "Authorization: Bearer $TOKEN")
    SWARM_ID=$(echo "$RESPONSE" | jq -r '.ID' 2>/dev/null)
    if [ -z "$SWARM_ID" ] || [ "$SWARM_ID" = "null" ]; then
        #echo "[ERRO] SwarmID não encontrado! Resposta: $RESPONSE"
        portainer_log_failure "langfuse_swarm_invalid_response" "0" "nao_validado" "$(printf '%s' "$RESPONSE" | wc -c)"
        echo -e "XXX\n84\n[ERRO] SWARMID NÃO ENCONTRADO. LOG: $PORTAINER_DIAG_LOG 3/4  \nXXX"
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

    PORTAINER_DIAG_STAGE="langfuse_create"
    http_code=$(portainer_upload_curl -sS -o "$response_output" -w "%{http_code}" -X POST \
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

    if [ "$http_code" != "200" ]; then
       # echo "[ERRO] Erro ao criar a stack. Código HTTP: $http_code. Resposta: $response"
        portainer_log_failure "langfuse_create_http" "0" "${http_code:-000}" "$(printf '%s' "$response" | wc -c)"
        echo -e "XXX\n89\n[ERRO] ERRO AO CRIAR STACK. LOG: $PORTAINER_DIAG_LOG 3/4  \nXXX"
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
    if ! docker stack deploy --prune --resolve-image always \
        -c "$nome_app.yaml" "$nome_app" >> "$LANGFUSE_INSTALL_LOG" 2>&1; then
        langfuse_fail 73 "O Docker Swarm recusou a criação da stack principal do Langfuse."
    fi
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

validate_langfuse_stack() {
    [ -s "/root/${nome_app}.yaml" ] ||
        langfuse_fail 74 "A YAML principal do Langfuse não foi criada em /root/${nome_app}.yaml."
    wait_stack_registered "$nome_app" "Langfuse" 75
    wait_service_healthy "${nome_app}_${nome_app}" "Langfuse Web" 76
    wait_service_healthy "${nome_app}_${nome_app}-worker" "Langfuse Worker" 77
}

validate_langfuse_stack


echo -e "XXX\n93\nFINALIZANDO BUILD DO LANGFUSE 4/4  \nXXX"

sleep 12

echo -e "XXX\n100\nFINALIZANDO BUILD DO LANGFUSE 4/4 - CONCLUIDO  \nXXX"

sleep 3

} 2>> "$LANGFUSE_INSTALL_LOG" | whiptail --title "LANGFUSE + MINIO + CLICKHOUSE - PROGRESSO DA INSTALAÇÃO" --gauge "Aguarde a instalação dos ítens necessários" 6 60 0
langfuse_install_status=${PIPESTATUS[0]}

if [ "$langfuse_install_status" -ne 0 ]; then
    error_detail=$(cat "$LANGFUSE_ERROR_FILE" 2>/dev/null)
    [ -n "$error_detail" ] || error_detail=$(tail -n 30 "$LANGFUSE_INSTALL_LOG" 2>/dev/null)
    [ -n "$error_detail" ] || error_detail="Falha não identificada durante o fluxo protegido de instalação."
    whiptail --title "ERRO NA INSTALAÇÃO DO LANGFUSE" --msgbox \
        "A instalação foi interrompida sem declarar falso sucesso.\n\n$error_detail\n\nLog completo: $LANGFUSE_INSTALL_LOG" \
        22 90
    exit "$langfuse_install_status"
fi

if [ ! -s "/root/${nome_app}.yaml" ] ||
   ! docker stack ls --format '{{.Name}}' | grep -Fxq "$nome_app"; then
    whiptail --title "ERRO NA INSTALAÇÃO DO LANGFUSE" --msgbox \
        "A pós-condição externa detectou que a YAML ou a stack principal do Langfuse está ausente.\n\nNenhum sucesso será informado.\nLog: $LANGFUSE_INSTALL_LOG" \
        16 84
    exit 77
fi

# FIM DE INSTALANDO O LANGFUSE
#
#######################################################
#
# VERIFICAÇÃO FINAL - Versão Corrigida
if [ "$INSTALL_TYPE" = "CLOUDFLARE_TUNNEL" ]; then
    failed_domains=0
    domains_to_check=""
    
    # Determinar quais domínios verificar baseado se Minio foi instalado
    if [ "$minio_container" = "" ] && [ "$clickhouse_container" = "" ]; then
        domains_to_check="$painel $publico $url_clickhouse $url_langfuse"
    fi

    if [ "$minio_container" = "" ] && [ "$clickhouse_container" != "" ]; then
        domains_to_check="$painel $publico $url_langfuse"
    fi

    if [ "$minio_container" != "" ] && [ "$clickhouse_container" = "" ]; then
        domains_to_check="$url_clickhouse $url_langfuse"
    fi

    if [ "$minio_container" != "" ] && [ "$clickhouse_container" != "" ]; then
        domains_to_check="$url_langfuse"
    fi

    for domain in $domains_to_check; do
        if ! nslookup "$domain" >/dev/null 2>&1; then
            ((failed_domains++))
        elif ! nslookup "$domain" | grep -q "${TUNNEL_ID}.cfargotunnel.com"; then
            ((failed_domains++))
        else
            # Domínio configurado corretamente
            :
        fi
    done

    if [ $failed_domains -eq 0 ]; then
        whiptail --title "Sucesso" --msgbox "Instalação concluída com sucesso! Cloudflare Tunnel configurado.\n\nAcessos:\n- Minio Admin: https://$painel\n- Minio Public: https://$publico\n- Clickhouse: https://$url_clickhouse\n- Langfuse: https://$url_langfuse\n\nPressione ENTER para voltar ao Menu Principal" 20 78
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
    
    if [[ "$clickhouse_container" == "" ]]; then
        dns_ip3=$(timeout 10 nslookup "$url_clickhouse" 2>/dev/null | grep "Address" | tail -n1 | awk '{print $2}')
        [[ "$dns_ip3" != "$ip_servidor" ]] && status=1
    fi
    
    dns_ip4=$(timeout 10 nslookup "$url_langfuse" 2>/dev/null | grep "Address" | tail -n1 | awk '{print $2}')
    [[ "$dns_ip4" != "$ip_servidor" ]] && status=1

    if [[ $status -eq 1 ]]; then
        whiptail --title "Erro" --msgbox "Não foi possível acessar um ou mais subdomínios. Verifique os apontamentos de DNS." 20 78
    else
        whiptail --title "Sucesso" --msgbox "Instalação concluída com sucesso! Tecle enter para continuar." 20 78
    fi
fi

exit 0

#!/usr/bin/bash
# RUSTDESK SERVER PRO — servidor OSS de rendezvous e relay para acesso remoto.
set -o pipefail
umask 077

RUSTDESK_IMAGE="rustdesk/rustdesk-server:1.1.16@sha256:8ecdab65deb7c84652a626380e31d11a8f1fbafd97916d57f95c20628f943c00"
DOMAIN_PROFILES_LIB="/root/SetupLowCodeMno/domain_profiles.sh"
INSTALL_TYPE_FILE="/root/.cloudflared_config/installation_type"
INSTALL_TYPE="TRADICIONAL"
[ -f "$INSTALL_TYPE_FILE" ] && INSTALL_TYPE=$(cat "$INSTALL_TYPE_FILE")

if [ "$INSTALL_TYPE" = "CLOUDFLARE_TUNNEL" ]; then
    CREDENTIALS_FILE="${SETUPMNO_CLOUDFLARE_CREDENTIALS_FILE:-/root/.cloudflared_config/cloudflare_credentials}"
else
    CREDENTIALS_FILE="${SETUPMNO_TRADITIONAL_CREDENTIALS_FILE:-/root/.tradicional_config/tradicional_credentials}"
fi
[ -f "$CREDENTIALS_FILE" ] && source "$CREDENTIALS_FILE"
[ -f "$DOMAIN_PROFILES_LIB" ] && source "$DOMAIN_PROFILES_LIB"

msg() {
    whiptail --title "RUSTDESK SERVER PRO" --msgbox "$1" 20 90 1>&2
}

ask_required() {
    local prompt="$1" value status
    while true; do
        value=$(whiptail --title "RUSTDESK SERVER PRO" --inputbox "$prompt" 15 90 3>&1 1>&2 2>&3)
        status=$?
        [ "$status" -ne 0 ] && return 130
        if [ -n "$value" ]; then
            printf '%s' "$value"
            return 0
        fi
        msg "Este campo é obrigatório."
    done
}

valid_hostname() {
    local value="$1" root="$2"
    [ "${#value}" -le 253 ] || return 1
    [[ "$value" =~ ^[a-z0-9]([a-z0-9.-]*[a-z0-9])?$ ]] || return 1
    [[ "$value" != *..* ]] || return 1
    [ "$value" != "$root" ] || return 1
    [[ "$value" == *."$root" ]]
}

if [ ! -f "$CREDENTIALS_FILE" ]; then
    msg "As credenciais Cloudflare deste domínio não foram encontradas.\n\nAtualize o Setup MNO ou recadastre o domínio e tente novamente."
    exit 1
fi
if [ -z "$CLOUDFLARE_API_TOKEN" ] || [ -z "$CLOUDFLARE_ZONE_ID" ]; then
    msg "A API Token ou o Zone ID não está disponível nas credenciais selecionadas.\n\nO RustDesk precisa de DNS > Edição para criar um hostname DNS-only."
    exit 1
fi

root_domain="${SETUPMNO_SELECTED_ROOT_DOMAIN:-${SETUPMNO_DOMAIN_ROOT:-}}"
if [ -z "$root_domain" ]; then
    zone_lookup=$(mktemp)
    if ! curl -sS --connect-timeout 10 --max-time 30 \
        "https://api.cloudflare.com/client/v4/zones/$CLOUDFLARE_ZONE_ID" \
        -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" >"$zone_lookup" 2>/dev/null; then
        rm -f "$zone_lookup"
        msg "Não foi possível consultar a zona Cloudflare selecionada. Verifique a conexão e a API Token."
        exit 1
    fi
    root_domain=$(jq -r '.result.name // empty' "$zone_lookup" 2>/dev/null)
    zone_ok=$(jq -r '.success // false' "$zone_lookup" 2>/dev/null)
    rm -f "$zone_lookup"
    if [ "$zone_ok" != "true" ] || [ -z "$root_domain" ]; then
        msg "A Cloudflare não confirmou a zona selecionada. A API Token precisa acessar esta zona e editar o DNS."
        exit 1
    fi
fi
root_domain=$(printf '%s' "$root_domain" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')

whiptail --title "RUSTDESK SERVER PRO" --yesno \
    "Instalar RustDesk Server OSS v1.1.16?\n\nO Setup MNO publicará diretamente as portas 21115/TCP, 21116/TCP+UDP e 21117/TCP. O hostname será DNS-only: Cloudflare Tunnel e proxy laranja não transportam corretamente este protocolo.\n\nAs portas WebSocket 21118/21119 permanecerão fechadas." \
    22 92 || exit 0

while true; do
    if ! url_rustdesk=$(ask_required "1/2 — Hostname do RustDesk no domínio $root_domain\n\nExemplo: rustdesk.$root_domain\n\nDigite somente o hostname, sem http://, https://, porta ou caminho:"); then
        exit 0
    fi
    url_rustdesk=$(printf '%s' "$url_rustdesk" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')
    valid_hostname "$url_rustdesk" "$root_domain" && break
    msg "Informe um subdomínio válido terminado exatamente em .$root_domain.\n\nExemplo: rustdesk.$root_domain"
done

while true; do
    if ! criar_portainer=$(ask_required "2/2 — Criar a Stack no Portainer?\n\n0 = editável no Portainer\n1 = direta no Docker Swarm"); then
        exit 0
    fi
    [[ "$criar_portainer" =~ ^[01]$ ]] && break
    msg "Digite somente 0 ou 1."
done

whiptail --title "CONFIRMAÇÃO DE REDE" --yesno \
    "Antes de continuar, confirme que você poderá liberar no provedor/VPS:\n\n• 21115/TCP — teste NAT\n• 21116/TCP e UDP — registro e hole punching\n• 21117/TCP — relay\n\nEm WSL2, acesso externo também depende do encaminhamento no Windows e no roteador. O Setup validará as portas no servidor, mas não altera firewall externo do provedor." \
    22 92 || exit 0

nome_principal="rustdesk"
sufixo_app=$(date +%s%N | md5sum | head -c7)
nome_app="${nome_principal}${sufixo_app}"
hbbs_service="${nome_app}_hbbs"
hbbr_service="${nome_app}_hbbr"
data_dir="/root/${nome_app}_data"
app_yaml="/root/${nome_app}.yaml"
install_log="/tmp/${nome_app}-install.log"
error_file="/tmp/${nome_app}-error.log"
: >"$install_log"
: >"$error_file"

whiptail --title "CONFIRMAR INSTALAÇÃO" --yesno \
    "RustDesk Server OSS v1.1.16\n\nServidor: $url_rustdesk\nDNS: Cloudflare DNS-only\nGestão: $([ "$criar_portainer" = "0" ] && echo "Stack editável no Portainer" || echo "Stack direta no Docker")\nArquiteturas: X86 e ARM\nRAM máxima total: 640 MB\nPersistência: chave e SQLite compartilhados\nWeb client: desativado\nCloudflare Tunnel: não utilizado para o tráfego RustDesk" \
    23 92 || exit 0

{
    work_dir=$(mktemp -d)
    stack_created="false"
    dns_created="false"
    origin_created="false"
    origin_record_id=""
    dns_record_id=""
    portainer_stack_id=""
    portainer_endpoint_id=""
    portainer_token=""
    trap 'rm -rf "$work_dir"' EXIT

    portainer_login() {
        local dados_file auth_payload auth_response endpoints_response swarm_response
        dados_file="$HOME/dados_portainer/dados_portainer"
        [ -f "$dados_file" ] || return 1
        PORTAINER_URL=$(grep "Dominio do portainer:" "$dados_file" | cut -d':' -f2- | xargs)
        ADMIN_USERNAME=$(grep "Usuario:" "$dados_file" | cut -d':' -f2- | xargs)
        ADMIN_PASSWORD=$(grep "Senha:" "$dados_file" | cut -d':' -f2- | xargs)
        [ -n "$PORTAINER_URL" ] && [ -n "$ADMIN_USERNAME" ] && [ -n "$ADMIN_PASSWORD" ] || return 1
        auth_payload=$(printf '%s\n%s' "$ADMIN_USERNAME" "$ADMIN_PASSWORD" |
            jq -Rs 'split("\n") | {username:.[0],password:.[1]}') || return 1
        auth_response=$(printf '%s' "$auth_payload" | curl -sk -X POST \
            "https://$PORTAINER_URL/api/auth" -H "Content-Type: application/json" \
            --data-binary @- 2>>"$install_log") || return 1
        unset ADMIN_PASSWORD auth_payload
        portainer_token=$(printf '%s' "$auth_response" | jq -r '.jwt // empty')
        unset auth_response
        [ -n "$portainer_token" ] || return 1
        endpoints_response=$(curl -sk "https://$PORTAINER_URL/api/endpoints" \
            -H "Authorization: Bearer $portainer_token" 2>>"$install_log") || return 1
        portainer_endpoint_id=$(printf '%s' "$endpoints_response" | jq -r '.[0].Id // empty')
        unset endpoints_response
        [ -n "$portainer_endpoint_id" ] || return 1
        swarm_response=$(curl -sk "https://$PORTAINER_URL/api/endpoints/$portainer_endpoint_id/docker/swarm" \
            -H "Authorization: Bearer $portainer_token" 2>>"$install_log") || return 1
        PORTAINER_SWARM_ID=$(printf '%s' "$swarm_response" | jq -r '.ID // empty')
        unset swarm_response
        [ -n "$PORTAINER_SWARM_ID" ]
    }

    rollback_deployment() {
        local response
        echo "Executando rollback exclusivo do RustDesk Server..." >>"$install_log"
        if [ "$dns_created" = "true" ] && [ -n "$dns_record_id" ]; then
            response="$work_dir/dns-delete.json"
            curl -sS -X DELETE \
                "https://api.cloudflare.com/client/v4/zones/$CLOUDFLARE_ZONE_ID/dns_records/$dns_record_id" \
                -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" >"$response" 2>>"$install_log" || true
        fi
        if declare -F setupmno_domain_rollback_traditional_origin >/dev/null 2>&1; then
            setupmno_domain_rollback_traditional_origin "$CLOUDFLARE_API_TOKEN" "$CLOUDFLARE_ZONE_ID" \
                "$origin_record_id" "$origin_created" || true
        fi
        if [ "$stack_created" = "true" ]; then
            if [ "$criar_portainer" = "0" ] && [ -n "$portainer_stack_id" ]; then
                portainer_login || true
                [ -n "$portainer_token" ] && curl -sk -X DELETE \
                    "https://$PORTAINER_URL/api/stacks/$portainer_stack_id?endpointId=$portainer_endpoint_id" \
                    -H "Authorization: Bearer $portainer_token" >>"$install_log" 2>&1 || true
            fi
            docker stack rm "$nome_app" >>"$install_log" 2>&1 || true
            for _ in $(seq 1 45); do
                docker service inspect "$hbbs_service" >/dev/null 2>&1 || break
                sleep 1
            done
        fi
        if [[ "$data_dir" == /root/rustdesk*_data ]]; then rm -rf "$data_dir"; fi
        if [[ "$app_yaml" == /root/rustdesk*.yaml ]]; then rm -f -- "$app_yaml"; fi
    }

    fail_install() {
        local code="$1" progress="$2" message="$3"
        rollback_deployment
        printf '%s\n' "$message" >"$error_file"
        echo -e "XXX\n100\n$progress\nXXX"
        exit "$code"
    }

    port_in_use() {
        local port="$1"
        ss -H -lntu 2>/dev/null | awk '{print $5}' | grep -Eq ":${port}$"
    }

    write_stack_yaml() {
        cat >"$app_yaml" <<EOYAML
version: "3.8"
services:
  hbbs:
    image: $RUSTDESK_IMAGE
    hostname: $hbbs_service
    command: ["hbbs", "-r", "$url_rustdesk:21117"]
    read_only: true
    cap_drop:
      - ALL
    tmpfs:
      - /tmp:rw,noexec,nosuid,nodev,mode=1777
    volumes:
      - $data_dir:/root
    ports:
      - target: 21115
        published: 21115
        protocol: tcp
        mode: host
      - target: 21116
        published: 21116
        protocol: tcp
        mode: host
      - target: 21116
        published: 21116
        protocol: udp
        mode: host
    deploy:
      replicas: 1
      placement:
        constraints:
          - node.role == manager
      restart_policy:
        condition: on-failure
        delay: 5s
        max_attempts: 5
        window: 120s
      update_config:
        parallelism: 1
        order: stop-first
        failure_action: rollback
      resources:
        limits:
          cpus: "0.75"
          memory: 384M
        reservations:
          cpus: "0.05"
          memory: 32M

  hbbr:
    image: $RUSTDESK_IMAGE
    hostname: $hbbr_service
    command: ["hbbr"]
    read_only: true
    cap_drop:
      - ALL
    tmpfs:
      - /tmp:rw,noexec,nosuid,nodev,mode=1777
    volumes:
      - $data_dir:/root
    ports:
      - target: 21117
        published: 21117
        protocol: tcp
        mode: host
    deploy:
      replicas: 1
      placement:
        constraints:
          - node.role == manager
      restart_policy:
        condition: on-failure
        delay: 5s
        max_attempts: 5
        window: 120s
      update_config:
        parallelism: 1
        order: stop-first
        failure_action: rollback
      resources:
        limits:
          cpus: "0.50"
          memory: 256M
        reservations:
          cpus: "0.02"
          memory: 16M
EOYAML
        chmod 600 "$app_yaml"
    }

    wait_replica() {
        local service="$1" attempts="$2" replicas
        for _ in $(seq 1 "$attempts"); do
            replicas=$(docker service ls --filter "name=$service" --format '{{.Replicas}}' 2>>"$install_log" | head -n1)
            [ "$replicas" = "1/1" ] && return 0
            sleep 2
        done
        return 1
    }

    wait_ports() {
        for _ in $(seq 1 60); do
            if port_in_use 21115 && port_in_use 21116 && port_in_use 21117 &&
               timeout 3 bash -c '</dev/tcp/127.0.0.1/21115' 2>/dev/null &&
               timeout 3 bash -c '</dev/tcp/127.0.0.1/21116' 2>/dev/null &&
               timeout 3 bash -c '</dev/tcp/127.0.0.1/21117' 2>/dev/null; then
                return 0
            fi
            sleep 2
        done
        return 1
    }

    echo -e "XXX\n5\nVALIDANDO SWARM, PORTAS E CREDENCIAIS...\nXXX"
    for required_command in docker curl jq md5sum ss timeout awk grep; do
        command -v "$required_command" >/dev/null 2>&1 ||
            fail_install 10 "DEPENDÊNCIA NÃO ENCONTRADA" "O comando obrigatório '$required_command' não está instalado."
    done
    docker info >/dev/null 2>>"$install_log" ||
        fail_install 11 "DOCKER INDISPONÍVEL" "O Docker não está acessível."
    [ "$(docker info --format '{{.Swarm.LocalNodeState}}' 2>>"$install_log")" = "active" ] ||
        fail_install 12 "SWARM INATIVO" "O Docker Swarm precisa estar ativo."
    for rustdesk_port in 21115 21116 21117; do
        port_in_use "$rustdesk_port" &&
            fail_install 13 "PORTA ${rustdesk_port} OCUPADA" "A porta ${rustdesk_port} já está em uso neste servidor. O RustDesk não alterou o serviço existente."
    done
    [ -n "$CLOUDFLARE_API_TOKEN" ] && [ -n "$CLOUDFLARE_ZONE_ID" ] ||
        fail_install 14 "CREDENCIAL CLOUDFLARE INVÁLIDA" "API Token ou Zone ID ausente para o domínio selecionado."

    echo -e "XXX\n15\nVALIDANDO IMAGEM OFICIAL MULTI-ARQUITETURA...\nXXX"
    docker pull "$RUSTDESK_IMAGE" >>"$install_log" 2>&1 ||
        fail_install 20 "ERRO AO BAIXAR IMAGEM" "Não foi possível baixar a imagem oficial RustDesk Server 1.1.16."
    docker image inspect "$RUSTDESK_IMAGE" >>"$install_log" 2>&1 ||
        fail_install 21 "IMAGEM NÃO CONFIRMADA" "A imagem RustDesk foi baixada, mas não pôde ser inspecionada."

    echo -e "XXX\n25\nCRIANDO PERSISTÊNCIA E VALIDANDO A STACK...\nXXX"
    mkdir -p "$data_dir" >>"$install_log" 2>&1 ||
        fail_install 22 "PERSISTÊNCIA NÃO CRIADA" "Não foi possível criar $data_dir."
    chmod 700 "$data_dir"
    write_stack_yaml ||
        fail_install 23 "ERRO AO GERAR STACK" "Não foi possível gerar o YAML do RustDesk."
    docker stack config -c "$app_yaml" >"$work_dir/stack-validated.yaml" 2>>"$install_log" ||
        fail_install 24 "YAML INVÁLIDO" "O YAML do RustDesk não passou na validação do Docker."
    if grep -Eq 'published:[[:space:]]*2111(8|9)' "$work_dir/stack-validated.yaml"; then
        fail_install 25 "PORTA WEB INDEVIDA" "A validação detectou publicação inesperada das portas WebSocket 21118/21119."
    fi

    echo -e "XXX\n40\nPUBLICANDO HBBS E HBBR NO DOCKER SWARM...\nXXX"
    if [ "$criar_portainer" = "0" ]; then
        portainer_login ||
            fail_install 30 "PORTAINER INDISPONÍVEL" "Não foi possível autenticar ou localizar o Swarm no Portainer."
        portainer_response="$work_dir/portainer-create.json"
        http_code=$(curl -sk -o "$portainer_response" -w '%{http_code}' -X POST \
            -H "Authorization: Bearer $portainer_token" -F "Name=$nome_app" -F "file=@$app_yaml" \
            -F "SwarmID=$PORTAINER_SWARM_ID" -F "endpointId=$portainer_endpoint_id" \
            "https://$PORTAINER_URL/api/stacks/create/swarm/file" 2>>"$install_log")
        [[ "$http_code" =~ ^2[0-9][0-9]$ ]] ||
            fail_install 31 "PORTAINER RECUSOU A STACK" "O Portainer recusou a stack RustDesk (HTTP ${http_code:-indisponível})."
        stack_created="true"
        portainer_stack_id=$(jq -r '.Id // .id // empty' "$portainer_response")
        [ -n "$portainer_stack_id" ] ||
            fail_install 32 "STACK SEM IDENTIFICADOR" "O Portainer não retornou o identificador da stack RustDesk."
    else
        docker stack deploy --prune --resolve-image always -c "$app_yaml" "$nome_app" >>"$install_log" 2>&1 ||
            fail_install 33 "DOCKER RECUSOU A STACK" "O Docker Swarm recusou a stack RustDesk."
        stack_created="true"
    fi

    echo -e "XXX\n58\nAGUARDANDO SERVIÇOS E PORTAS TCP/UDP...\nXXX"
    wait_replica "$hbbs_service" 75 || {
        docker service ps --no-trunc "$hbbs_service" >>"$install_log" 2>&1 || true
        docker service logs --raw --tail 100 "$hbbs_service" >>"$install_log" 2>&1 || true
        fail_install 40 "HBBS NÃO INICIOU" "O servidor de identificação hbbs não atingiu 1/1 réplica."
    }
    wait_replica "$hbbr_service" 75 || {
        docker service ps --no-trunc "$hbbr_service" >>"$install_log" 2>&1 || true
        docker service logs --raw --tail 100 "$hbbr_service" >>"$install_log" 2>&1 || true
        fail_install 41 "HBBR NÃO INICIOU" "O servidor relay hbbr não atingiu 1/1 réplica."
    }
    wait_ports ||
        fail_install 42 "PORTAS NÃO RESPONDERAM" "Os serviços subiram, mas 21115/TCP, 21116/TCP+UDP ou 21117/TCP não foram confirmadas no host."
    for _ in $(seq 1 60); do
        [ -s "$data_dir/id_ed25519.pub" ] && [ -s "$data_dir/id_ed25519" ] && [ -f "$data_dir/db_v2.sqlite3" ] && break
        sleep 2
    done
    [ -s "$data_dir/id_ed25519.pub" ] && [ -s "$data_dir/id_ed25519" ] && [ -f "$data_dir/db_v2.sqlite3" ] ||
        fail_install 43 "PERSISTÊNCIA NÃO CONFIRMADA" "O RustDesk iniciou, mas não gravou a chave e a base SQLite persistentes."

    echo -e "XXX\n76\nCRIANDO DNS-ONLY REVERSÍVEL NA CLOUDFLARE...\nXXX"
    profile_id="${SETUPMNO_DOMAIN_PROFILE_ID:-legacy-${CLOUDFLARE_ZONE_ID:0:12}}"
    if ! declare -F setupmno_domain_ensure_traditional_origin >/dev/null 2>&1; then
        fail_install 50 "COMPONENTE MULTIDOMÍNIO AUSENTE" "Atualize os componentes essenciais do Setup MNO para criar o DNS-only seguro do RustDesk."
    fi
    setupmno_domain_ensure_traditional_origin "$CLOUDFLARE_API_TOKEN" "$CLOUDFLARE_ZONE_ID" \
        "$root_domain" "$profile_id" ||
        fail_install 51 "ORIGEM DNS NÃO CRIADA" "${SETUPMNO_DOMAIN_LAST_ERROR:-Não foi possível preparar a origem pública deste servidor.}"
    origin_created="${SETUPMNO_NEW_ORIGIN_CREATED:-false}"
    origin_record_id="${SETUPMNO_NEW_ORIGIN_RECORD_ID:-}"
    origin_name="${SETUPMNO_NEW_ORIGIN_LABEL}.${root_domain}"

    curl -sS --get "https://api.cloudflare.com/client/v4/zones/$CLOUDFLARE_ZONE_ID/dns_records" \
        -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" --data-urlencode "name=$url_rustdesk" \
        >"$work_dir/dns-lookup.json" 2>>"$install_log" ||
        fail_install 52 "DNS NÃO CONSULTADO" "Não foi possível consultar $url_rustdesk na Cloudflare."
    [ "$(jq -r '.success // false' "$work_dir/dns-lookup.json")" = "true" ] ||
        fail_install 53 "CLOUDFLARE RECUSOU CONSULTA" "A Cloudflare recusou a consulta do hostname RustDesk."
    [ "$(jq '.result | length' "$work_dir/dns-lookup.json")" -eq 0 ] ||
        fail_install 54 "HOSTNAME JÁ OCUPADO" "Já existe um registro DNS para $url_rustdesk. Nada existente foi substituído."
    jq -nc --arg name "$url_rustdesk" --arg content "$origin_name" \
        '{type:"CNAME",name:$name,content:$content,ttl:1,proxied:false,comment:"RustDesk Server OSS instalado pelo Setup MNO"}' \
        >"$work_dir/dns-payload.json"
    curl -sS -X POST "https://api.cloudflare.com/client/v4/zones/$CLOUDFLARE_ZONE_ID/dns_records" \
        -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" -H "Content-Type: application/json" \
        --data-binary @"$work_dir/dns-payload.json" >"$work_dir/dns-response.json" 2>>"$install_log" ||
        fail_install 55 "ERRO AO CRIAR DNS" "Falha de comunicação ao criar o DNS-only do RustDesk."
    [ "$(jq -r '.success // false' "$work_dir/dns-response.json")" = "true" ] ||
        fail_install 56 "CLOUDFLARE RECUSOU DNS" "A Cloudflare recusou o CNAME DNS-only do RustDesk."
    dns_record_id=$(jq -r '.result.id // empty' "$work_dir/dns-response.json")
    [ -n "$dns_record_id" ] ||
        fail_install 57 "DNS SEM IDENTIFICADOR" "A Cloudflare criou o registro sem retornar um identificador seguro para rollback."
    dns_created="true"
    jq -e '.result | has("proxied") and (.proxied == false)' "$work_dir/dns-response.json" >/dev/null 2>&1 ||
        fail_install 57 "DNS-ONLY NÃO CONFIRMADO" "A Cloudflare não confirmou o hostname com proxy desativado."

    public_key=$(tr -d '\r\n' <"$data_dir/id_ed25519.pub")
    [ -n "$public_key" ] ||
        fail_install 60 "CHAVE PÚBLICA VAZIA" "A chave pública do RustDesk não pôde ser lida."
    mkdir -p /root/dados_rustdesk
    chmod 700 /root/dados_rustdesk
    cat >"/root/dados_rustdesk/${nome_app}" <<EODATA
RustDesk Server OSS 1.1.16
ID Server: $url_rustdesk:21116
Relay Server: $url_rustdesk:21117
Key: $public_key
Stack: $nome_app
Dados: $data_dir
Imagem: $RUSTDESK_IMAGE
Portas: 21115/TCP, 21116/TCP+UDP, 21117/TCP
DNS: DNS-only (proxy Cloudflare desativado)
EODATA
    chmod 600 "/root/dados_rustdesk/${nome_app}"

    stack_created="false"
    dns_created="false"
    origin_created="false"
    echo -e "XXX\n100\nRUSTDESK SERVER INSTALADO COM SUCESSO\nXXX"
} | whiptail --title "RUSTDESK SERVER PRO" --gauge "Preparando RustDesk Server..." 8 92 0
install_status=${PIPESTATUS[0]}

if [ "$install_status" -ne 0 ]; then
    error_detail=$(cat "$error_file" 2>/dev/null)
    [ -n "$error_detail" ] || error_detail=$(tail -n 20 "$install_log" 2>/dev/null)
    whiptail --title "ERRO NA INSTALAÇÃO DO RUSTDESK SERVER" --msgbox \
        "A instalação foi interrompida sem declarar falso sucesso.\n\n$error_detail\n\nLog completo: $install_log" \
        24 96
    exit "$install_status"
fi

public_key=$(tr -d '\r\n' <"$data_dir/id_ed25519.pub")
whiptail --title "RUSTDESK SERVER PRO" --msgbox \
    "RustDesk Server instalado com sucesso.\n\nCONFIGURE NOS CLIENTES RUSTDESK:\nID Server: $url_rustdesk:21116\nRelay Server: $url_rustdesk:21117\nAPI Server: deixe vazio\nKey: $public_key\n\nStack: $nome_app\nDados: $data_dir\nCredenciais salvas em: /root/dados_rustdesk/${nome_app}\n\nIMPORTANTE: libere no firewall do provedor 21115/TCP, 21116/TCP+UDP e 21117/TCP. O hostname está em DNS-only e não usa o Cloudflare Tunnel. Em WSL2, configure também Windows e roteador para acesso externo." \
    28 100

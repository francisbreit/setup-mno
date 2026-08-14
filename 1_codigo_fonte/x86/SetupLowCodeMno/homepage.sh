#!/usr/bin/bash
# HOMEPAGE PRO — dashboard de serviços com descoberta segura do Docker Swarm.
set -o pipefail
umask 077

HOMEPAGE_IMAGE_REF="ghcr.io/gethomepage/homepage:v1.13.2@sha256:a0b71c8e757298d02560186bab9fbe3fc2d375c523a62cc1019177b37e48aa28"
SOCKET_PROXY_IMAGE_REF="ghcr.io/tecnativa/docker-socket-proxy:v0.4.2@sha256:1f3a6f303320723d199d2316a3e82b2e2685d86c275d5e3deeaf182573b47476"
CADDY_IMAGE_REF="caddy:2.11.4-alpine@sha256:5f5c8640aae01df9654968d946d8f1a56c497f1dd5c5cda4cf95ab7c14d58648"

INSTALL_TYPE_FILE="/root/.cloudflared_config/installation_type"
INSTALL_TYPE="TRADICIONAL"
[ -f "$INSTALL_TYPE_FILE" ] && INSTALL_TYPE=$(cat "$INSTALL_TYPE_FILE")

if [ "$INSTALL_TYPE" = "CLOUDFLARE_TUNNEL" ]; then
    CREDENTIALS_FILE="${SETUPMNO_CLOUDFLARE_CREDENTIALS_FILE:-/root/.cloudflared_config/cloudflare_credentials}"
else
    CREDENTIALS_FILE="${SETUPMNO_TRADITIONAL_CREDENTIALS_FILE:-/root/.tradicional_config/tradicional_credentials}"
fi
[ -f "$CREDENTIALS_FILE" ] && source "$CREDENTIALS_FILE"
criar_dns="${criar_dns:-0}"

msg() {
    whiptail --title "HOMEPAGE PRO" --msgbox "$1" 14 80 1>&2
}

ask_required() {
    local prompt="$1" value status
    while true; do
        value=$(whiptail --title "HOMEPAGE PRO" --inputbox "$prompt" 13 80 3>&1 1>&2 2>&3)
        status=$?
        [ "$status" -ne 0 ] && return 130
        if [ -n "$value" ]; then
            printf '%s' "$value"
            return 0
        fi
        msg "Este campo é obrigatório."
    done
}

ask_password() {
    local prompt="$1" value status
    while true; do
        value=$(whiptail --title "HOMEPAGE PRO" --passwordbox "$prompt" 15 80 3>&1 1>&2 2>&3)
        status=$?
        [ "$status" -ne 0 ] && return 130
        if [ "${#value}" -lt 12 ]; then
            msg "A senha precisa ter pelo menos 12 caracteres."
        elif [[ ! "$value" =~ [A-Z] ]]; then
            msg "A senha precisa ter pelo menos uma letra maiúscula."
        elif [[ ! "$value" =~ [a-z] ]]; then
            msg "A senha precisa ter pelo menos uma letra minúscula."
        elif [[ ! "$value" =~ [0-9] ]]; then
            msg "A senha precisa ter pelo menos um número."
        elif [[ "$value" =~ ^[A-Za-z0-9]+$ ]]; then
            msg "A senha precisa ter pelo menos um caractere especial."
        else
            printf '%s' "$value"
            return 0
        fi
    done
}

whiptail --title "HOMEPAGE PRO" --yesno \
    "Instalar Homepage como ferramenta PRO?\n\nDashboard personalizável para organizar aplicações, favoritos e widgets, com descoberta automática dos serviços do Docker Swarm por um proxy interno estritamente somente leitura." \
    17 82 || exit 0

while true; do
    if ! url_homepage=$(ask_required "1/4 — Domínio do Homepage (ex.: inicio.seudominio.com):"); then
        exit 0
    fi
    if [[ "$url_homepage" =~ ^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$ ]] &&
       [[ "$url_homepage" == *.* ]]; then
        break
    fi
    msg "Informe somente o domínio, sem http://, https://, barras ou caminhos."
done

if [ "$INSTALL_TYPE" = "CLOUDFLARE_TUNNEL" ]; then
    route_check=$(mktemp)
    whiptail --title "HOMEPAGE PRO" --infobox \
        "Verificando se o domínio já possui uma rota no Cloudflare Tunnel..." 8 80
    if ! curl -sS -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
        "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/cfd_tunnel/$TUNNEL_ID/configurations" \
        >"$route_check" 2>/dev/null; then
        rm -f "$route_check"
        msg "Não foi possível consultar o Cloudflare Tunnel. Verifique as credenciais e tente novamente."
        exit 1
    fi
    existing_service=$(jq -r --arg host "$url_homepage" \
        '.result.config.ingress[]? | select(.hostname == $host) | .service' "$route_check" 2>/dev/null | head -n1)
    rm -f "$route_check"
    if [ -n "$existing_service" ] && [ "$existing_service" != "null" ]; then
        msg "Já existe uma rota para:\n\n$url_homepage\n\nServiço atual: $existing_service\n\nA rota será substituída pela nova instalação."
    fi
fi

while true; do
    if ! usuario_homepage=$(ask_required "2/4 — Usuário de acesso ao Homepage:"); then
        exit 0
    fi
    if [[ "$usuario_homepage" =~ ^[A-Za-z0-9_.-]+$ ]]; then
        break
    fi
    msg "Use somente letras, números, ponto, hífen ou sublinhado no usuário."
done

if ! senha_homepage=$(ask_password "3/4 — Senha de acesso\n\nMínimo: 12 caracteres, com maiúscula, minúscula, número e caractere especial."); then
    exit 0
fi

while true; do
    if ! criar_portainer=$(ask_required "4/4 — Criar Stacks no Portainer?\n\n0 = editáveis no Portainer\n1 = diretas no Docker"); then
        unset senha_homepage
        exit 0
    fi
    [[ "$criar_portainer" =~ ^[01]$ ]] && break
    msg "Digite somente 0 ou 1."
done

nome_principal="homepage"
sufixo_app=$(date +%s%N | md5sum | head -c7)
nome_app="${nome_principal}${sufixo_app}"
proxy_stack="${nome_app}-dockerproxy"
proxy_service="${proxy_stack}_dockerproxy"
homepage_service="${nome_app}_homepage"
gateway_service="${nome_app}_gateway"
internal_network="${nome_app}_internal"
config_dir="/root/${nome_app}_config"
gateway_dir="/root/${nome_app}_gateway"
app_yaml="/root/${nome_app}.yaml"
proxy_yaml="/root/${proxy_stack}.yaml"

dns_mode="Cloudflare Tunnel"
if [ "$INSTALL_TYPE" = "TRADICIONAL" ]; then
    if [ "$criar_dns" = "0" ]; then
        dns_mode="Tradicional com DNS automático"
    else
        dns_mode="Tradicional com DNS manual"
    fi
fi

whiptail --title "Confirmar instalação" --yesno \
    "Homepage PRO\n\nDomínio: $url_homepage\nUsuário: $usuario_homepage\nInstalação: $dns_mode\nStacks: $([ "$criar_portainer" = "0" ] && echo "Portainer editáveis" || echo "Docker diretas")\nArquiteturas: X86 e ARM\nRAM máxima total: 768 MB\nPortas 3000 e 2375: somente internas\nSocket Docker: somente na substack proxy, leitura estrita" \
    23 86 || {
        unset senha_homepage
        exit 0
    }

install_log="/tmp/${nome_app}-install.log"
error_file="/tmp/${nome_app}-error.log"
: >"$install_log"
: >"$error_file"

{
    work_dir=$(mktemp -d)
    network_created="false"
    rollback_required="false"
    proxy_stack_id=""
    proxy_endpoint_id=""
    proxy_token=""
    app_stack_id=""
    app_endpoint_id=""
    app_token=""

    cleanup_workdir() {
        rm -rf "$work_dir"
    }
    trap cleanup_workdir EXIT

    rollback_deployment() {
        echo "Executando rollback das stacks incompletas..." >>"$install_log"
        if [ "$criar_portainer" = "0" ]; then
            if [ -n "$app_stack_id" ] && [ -n "$app_endpoint_id" ] && [ -n "$app_token" ]; then
                curl -sk -X DELETE \
                    "https://$PORTAINER_URL/api/stacks/$app_stack_id?endpointId=$app_endpoint_id" \
                    -H "Authorization: Bearer $app_token" >>"$install_log" 2>&1 || true
            fi
            if [ -n "$proxy_stack_id" ] && [ -n "$proxy_endpoint_id" ] && [ -n "$proxy_token" ]; then
                curl -sk -X DELETE \
                    "https://$PORTAINER_URL/api/stacks/$proxy_stack_id?endpointId=$proxy_endpoint_id" \
                    -H "Authorization: Bearer $proxy_token" >>"$install_log" 2>&1 || true
            fi
        else
            docker stack rm "$nome_app" "$proxy_stack" >>"$install_log" 2>&1 || true
        fi
        for _ in $(seq 1 20); do
            app_services=$(docker service ls \
                --filter "label=com.docker.stack.namespace=$nome_app" \
                -q 2>>"$install_log" | wc -l)
            proxy_services=$(docker service ls \
                --filter "label=com.docker.stack.namespace=$proxy_stack" \
                -q 2>>"$install_log" | wc -l)
            remaining_services=$((app_services + proxy_services))
            [ "$remaining_services" -eq 0 ] && break
            sleep 1
        done
        if [ "$network_created" = "true" ]; then
            docker network rm "$internal_network" >>"$install_log" 2>&1 || true
        fi
    }

    fail_install() {
        local code="$1" progress="$2" message="$3"
        if [ "$rollback_required" = "true" ]; then
            rollback_deployment
            rollback_required="false"
        fi
        printf '%s\n' "$message" >"$error_file"
        echo -e "XXX\n100\n$progress\nXXX"
        exit "$code"
    }

    portainer_create_stack() {
        local stack_name="$1" yaml_file="$2" auth_payload auth_response endpoint_response
        local swarm_response stack_response http_code
        dados_file="$HOME/dados_portainer/dados_portainer"
        [ -f "$dados_file" ] || return 60
        PORTAINER_URL=$(grep "Dominio do portainer:" "$dados_file" | cut -d':' -f2- | xargs)
        ADMIN_USERNAME=$(grep "Usuario:" "$dados_file" | cut -d':' -f2- | xargs)
        ADMIN_PASSWORD=$(grep "Senha:" "$dados_file" | cut -d':' -f2- | xargs)
        [ -n "$PORTAINER_URL" ] && [ -n "$ADMIN_USERNAME" ] && [ -n "$ADMIN_PASSWORD" ] || return 61
        auth_payload="$work_dir/${stack_name}-auth-payload.json"
        auth_response="$work_dir/${stack_name}-auth.json"
        endpoint_response="$work_dir/${stack_name}-endpoints.json"
        swarm_response="$work_dir/${stack_name}-swarm.json"
        stack_response="$work_dir/${stack_name}-stack.json"
        jq -nc --arg username "$ADMIN_USERNAME" --arg password "$ADMIN_PASSWORD" \
            '{username:$username,password:$password}' >"$auth_payload" || return 62
        curl -sk -X POST "https://$PORTAINER_URL/api/auth" -H "Content-Type: application/json" \
            --data-binary @"$auth_payload" >"$auth_response" 2>>"$install_log" || return 63
        LAST_TOKEN=$(jq -r '.jwt // empty' "$auth_response")
        [ -n "$LAST_TOKEN" ] || return 64
        curl -sk "https://$PORTAINER_URL/api/endpoints" -H "Authorization: Bearer $LAST_TOKEN" \
            >"$endpoint_response" 2>>"$install_log" || return 65
        LAST_ENDPOINT_ID=$(jq -r '.[0].Id // empty' "$endpoint_response")
        [ -n "$LAST_ENDPOINT_ID" ] || return 66
        curl -sk "https://$PORTAINER_URL/api/endpoints/$LAST_ENDPOINT_ID/docker/swarm" \
            -H "Authorization: Bearer $LAST_TOKEN" >"$swarm_response" 2>>"$install_log" || return 67
        SWARM_ID=$(jq -r '.ID // empty' "$swarm_response")
        [ -n "$SWARM_ID" ] || return 68
        http_code=$(curl -sk -o "$stack_response" -w "%{http_code}" -X POST \
            -H "Authorization: Bearer $LAST_TOKEN" -F "Name=$stack_name" -F "file=@$yaml_file" \
            -F "SwarmID=$SWARM_ID" -F "endpointId=$LAST_ENDPOINT_ID" \
            "https://$PORTAINER_URL/api/stacks/create/swarm/file" 2>>"$install_log")
        [[ "$http_code" =~ ^[0-9]{3}$ ]] && [ "$http_code" -ge 200 ] && [ "$http_code" -lt 300 ] || return 69
        LAST_STACK_ID=$(jq -r '.Id // .id // empty' "$stack_response")
        [ -n "$LAST_STACK_ID" ] || return 70
        return 0
    }

    echo -e "XXX\n5\nVALIDANDO AMBIENTE, SWARM E REDES... \nXXX"
    for required_command in docker curl jq base64 grep awk; do
        command -v "$required_command" >/dev/null 2>&1 ||
            fail_install 10 "DEPENDÊNCIA NÃO ENCONTRADA" "O comando obrigatório '$required_command' não está instalado."
    done
    [ -f "$CREDENTIALS_FILE" ] ||
        fail_install 11 "CREDENCIAIS NÃO ENCONTRADAS" "Arquivo de credenciais não encontrado: $CREDENTIALS_FILE"
    docker info >/dev/null 2>>"$install_log" ||
        fail_install 12 "DOCKER INDISPONÍVEL" "O Docker não está acessível."
    [ "$(docker info --format '{{.Swarm.LocalNodeState}}' 2>>"$install_log")" = "active" ] ||
        fail_install 13 "SWARM INATIVO" "O Docker Swarm precisa estar ativo."
    docker network inspect externa >/dev/null 2>>"$install_log" ||
        fail_install 14 "REDE EXTERNA AUSENTE" "A rede externa do Setup MNO não foi encontrada."

    if [ "$INSTALL_TYPE" = "CLOUDFLARE_TUNNEL" ] ||
       { [ "$INSTALL_TYPE" = "TRADICIONAL" ] && [ "$criar_dns" = "0" ]; }; then
        [ -n "$CLOUDFLARE_API_TOKEN" ] && [ -n "$CLOUDFLARE_ZONE_ID" ] ||
            fail_install 15 "CREDENCIAIS CLOUDFLARE INVÁLIDAS" "Token ou Zone ID do Cloudflare não encontrado nas credenciais."
    fi
    if [ "$INSTALL_TYPE" = "CLOUDFLARE_TUNNEL" ]; then
        [ -n "$CLOUDFLARE_ACCOUNT_ID" ] && [ -n "$TUNNEL_ID" ] ||
            fail_install 16 "DADOS DO TUNNEL INVÁLIDOS" "Account ID ou Tunnel ID não encontrado nas credenciais."
    fi

    echo -e "XXX\n15\nBAIXANDO IMAGENS OFICIAIS MULTI-ARQUITETURA... \nXXX"
    for image_ref in "$HOMEPAGE_IMAGE_REF" "$SOCKET_PROXY_IMAGE_REF" "$CADDY_IMAGE_REF"; do
        docker pull "$image_ref" >>"$install_log" 2>&1 ||
            fail_install 20 "ERRO AO BAIXAR IMAGEM" "Falha ao baixar a imagem oficial: $image_ref"
        docker image inspect "$image_ref" >>"$install_log" 2>&1 ||
            fail_install 21 "IMAGEM NÃO ENCONTRADA" "A imagem foi baixada, mas não pôde ser confirmada: $image_ref"
    done

    echo -e "XXX\n25\nGERANDO AUTENTICAÇÃO E CONFIGURAÇÃO INICIAL... \nXXX"
    if ! password_hash=$(printf '%s\n%s\n' "$senha_homepage" "$senha_homepage" |
        docker run -i --rm "$CADDY_IMAGE_REF" caddy hash-password 2>>"$install_log"); then
        unset senha_homepage
        fail_install 22 "ERRO AO PROTEGER SENHA" "O Caddy não conseguiu gerar o hash bcrypt da senha."
    fi
    unset senha_homepage
    [[ "$password_hash" == '$2'* ]] ||
        fail_install 23 "HASH DE SENHA INVÁLIDO" "O hash bcrypt gerado não possui o formato esperado."

    mkdir -p "$config_dir" "$gateway_dir" >>"$install_log" 2>&1 ||
        fail_install 24 "ERRO AO CRIAR CONFIGURAÇÃO" "Não foi possível criar os diretórios persistentes do Homepage."
    chmod 700 "$config_dir" "$gateway_dir"

    cat >"$config_dir/settings.yaml" <<EOSETTINGS
title: Setup MNO - Homepage
language: pt
theme: dark
color: slate
headerStyle: clean
hideVersion: true
showStats: true
instanceName: setup-mno

layout:
  Setup MNO:
    style: row
    columns: 3
EOSETTINGS

    cat >"$config_dir/docker.yaml" <<EODOCKER
setup-mno:
  host: $proxy_service
  port: 2375
  swarm: true
EODOCKER

    cat >"$config_dir/bookmarks.yaml" <<EOBOOKMARKS
- Setup MNO:
    - Manual Negócio Online:
        - icon: mdi-web
          href: https://manualnegocioonline.com.br/
    - Documentação Homepage:
        - icon: homepage.png
          href: https://gethomepage.dev/
    - Portainer:
        - icon: portainer.png
          href: https://www.portainer.io/
EOBOOKMARKS

    cat >"$config_dir/widgets.yaml" <<EOWIDGETS
- resources:
    cpu: true
    memory: true
    disk: /
- search:
    provider: duckduckgo
    target: _blank
- datetime:
    text_size: xl
    format:
      dateStyle: long
      timeStyle: short
      hourCycle: h23
EOWIDGETS

    printf '%s\n' '[]' >"$config_dir/services.yaml"
    printf '%s\n' 'mode: disabled' >"$config_dir/kubernetes.yaml"
    : >"$config_dir/custom.css"
    : >"$config_dir/custom.js"
    chmod 600 "$config_dir"/*
    chown -R 1000:1000 "$config_dir" >>"$install_log" 2>&1 ||
        fail_install 25 "ERRO AO AJUSTAR PERMISSÕES" "Não foi possível restringir as permissões da configuração do Homepage."

    cat >"$gateway_dir/Caddyfile" <<EOCADDY
:8080 {
    encode zstd gzip
    basic_auth {
        $usuario_homepage $password_hash
    }
    reverse_proxy $homepage_service:3000
    header {
        -Server
        X-Content-Type-Options "nosniff"
        Referrer-Policy "same-origin"
        X-Frame-Options "SAMEORIGIN"
    }
}
EOCADDY
    chmod 600 "$gateway_dir/Caddyfile"
    unset password_hash

    echo -e "XXX\n36\nCRIANDO REDE INTERNA EXCLUSIVA... \nXXX"
    if docker network inspect "$internal_network" >/dev/null 2>&1; then
        fail_install 30 "COLISÃO DE REDE" "A rede exclusiva $internal_network já existe; a instalação foi interrompida para não reutilizar recursos."
    fi
    docker network create --driver overlay "$internal_network" >>"$install_log" 2>&1 ||
        fail_install 31 "ERRO AO CRIAR REDE" "Não foi possível criar a rede interna exclusiva do Homepage."
    network_created="true"
    rollback_required="true"

    echo -e "XXX\n42\nGERANDO E VALIDANDO SUBSTACK DO PROXY DOCKER... \nXXX"
    cat >"$proxy_yaml" <<EOYAML
version: "3.8"
services:
  dockerproxy:
    image: $SOCKET_PROXY_IMAGE_REF
    environment:
      CONTAINERS: "1"
      SERVICES: "1"
      TASKS: "1"
      POST: "0"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
    networks:
      - homepage_internal
    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
          - node.role == manager
      restart_policy:
        condition: on-failure
        delay: 5s
        max_attempts: 5
        window: 120s
      resources:
        limits:
          cpus: "0.25"
          memory: 128M
        reservations:
          memory: 32M

networks:
  homepage_internal:
    external: true
    name: $internal_network
EOYAML

    echo -e "XXX\n50\nGERANDO E VALIDANDO STACK DO HOMEPAGE... \nXXX"
    cat >"$app_yaml" <<EOYAML
version: "3.8"
services:
  homepage:
    image: $HOMEPAGE_IMAGE_REF
    environment:
      HOMEPAGE_ALLOWED_HOSTS: $url_homepage
      PUID: "1000"
      PGID: "1000"
    volumes:
      - $config_dir:/app/config
    networks:
      - homepage_internal
    healthcheck:
      test:
        - CMD-SHELL
        - wget -q --spider http://127.0.0.1:3000/api/healthcheck || exit 1
      interval: 15s
      timeout: 5s
      retries: 10
      start_period: 30s
    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
          - node.role == manager
      restart_policy:
        condition: on-failure
        delay: 5s
        max_attempts: 5
        window: 120s
      resources:
        limits:
          cpus: "0.75"
          memory: 512M
        reservations:
          cpus: "0.10"
          memory: 128M
      labels:
        - homepage.group=Setup MNO
        - homepage.name=Homepage
        - homepage.icon=homepage.png
        - homepage.href=https://$url_homepage
        - homepage.description=Dashboard de serviços do Setup MNO

  gateway:
    image: $CADDY_IMAGE_REF
    volumes:
      - $gateway_dir/Caddyfile:/etc/caddy/Caddyfile:ro
    networks:
      - externa
      - homepage_internal
    healthcheck:
      test:
        - CMD-SHELL
        - wget -q --spider http://127.0.0.1:2019/config/
      interval: 15s
      timeout: 5s
      retries: 10
      start_period: 15s
    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
          - node.role == manager
      restart_policy:
        condition: on-failure
        delay: 5s
        max_attempts: 5
        window: 120s
      resources:
        limits:
          cpus: "0.25"
          memory: 128M
        reservations:
          memory: 32M
EOYAML

    if [ "$INSTALL_TYPE" = "TRADICIONAL" ]; then
        cat >>"$app_yaml" <<EOYAML
      labels:
        - traefik.enable=true
        - traefik.docker.network=externa
        - traefik.http.routers.$nome_app.rule=Host(\`$url_homepage\`)
        - traefik.http.routers.$nome_app.entrypoints=websecure
        - traefik.http.routers.$nome_app.priority=1
        - traefik.http.routers.$nome_app.tls.certresolver=letsencryptresolver
        - traefik.http.routers.$nome_app.tls=true
        - traefik.http.routers.$nome_app.service=$nome_app
        - traefik.http.services.$nome_app.loadbalancer.server.port=8080
EOYAML
    fi

    cat >>"$app_yaml" <<EOYAML

networks:
  externa:
    external: true
  homepage_internal:
    external: true
    name: $internal_network
EOYAML

    docker stack config -c "$proxy_yaml" >"$work_dir/proxy-validated.yaml" 2>>"$install_log" ||
        fail_install 32 "YAML DO PROXY INVÁLIDO" "O YAML da substack do proxy Docker é inválido."
    docker stack config -c "$app_yaml" >"$work_dir/app-validated.yaml" 2>>"$install_log" ||
        fail_install 33 "YAML DO HOMEPAGE INVÁLIDO" "O YAML da stack Homepage é inválido."
    if grep -q 'published:' "$work_dir/proxy-validated.yaml" "$work_dir/app-validated.yaml"; then
        fail_install 34 "PORTA PUBLICADA INDEVIDAMENTE" "A validação encontrou uma porta publicada no host."
    fi
    if grep -q '/var/run/docker.sock' "$work_dir/app-validated.yaml"; then
        fail_install 35 "SOCKET EXPOSTO AO HOMEPAGE" "A aplicação Homepage recebeu o socket Docker diretamente e a instalação foi bloqueada."
    fi
    grep -q 'POST: "0"' "$work_dir/proxy-validated.yaml" ||
        fail_install 36 "PROXY COM ESCRITA HABILITADA" "A substack do proxy não confirmou POST=0."
    grep -q 'read_only: true' "$work_dir/proxy-validated.yaml" ||
        fail_install 37 "SOCKET SEM SOMENTE LEITURA" "O mount do socket Docker não foi validado como somente leitura."

    echo -e "XXX\n62\nPUBLICANDO SUBSTACK DO PROXY DOCKER... \nXXX"
    if [ "$criar_portainer" = "0" ]; then
        LAST_STACK_ID=""
        LAST_ENDPOINT_ID=""
        LAST_TOKEN=""
        portainer_create_stack "$proxy_stack" "$proxy_yaml" ||
            fail_install 60 "ERRO AO CRIAR PROXY NO PORTAINER" "O Portainer recusou a substack do proxy Docker. Consulte o log completo."
        proxy_stack_id="$LAST_STACK_ID"
        proxy_endpoint_id="$LAST_ENDPOINT_ID"
        proxy_token="$LAST_TOKEN"
    else
        docker stack deploy --prune --resolve-image always -c "$proxy_yaml" "$proxy_stack" \
            >>"$install_log" 2>&1 ||
            fail_install 61 "ERRO AO CRIAR PROXY NO DOCKER" "Falha ao publicar a substack do proxy Docker."
    fi

    echo -e "XXX\n70\nPUBLICANDO STACK DO HOMEPAGE... \nXXX"
    if [ "$criar_portainer" = "0" ]; then
        LAST_STACK_ID=""
        LAST_ENDPOINT_ID=""
        LAST_TOKEN=""
        portainer_create_stack "$nome_app" "$app_yaml" ||
            fail_install 62 "ERRO AO CRIAR HOMEPAGE NO PORTAINER" "O Portainer recusou a stack Homepage. Consulte o log completo."
        app_stack_id="$LAST_STACK_ID"
        app_endpoint_id="$LAST_ENDPOINT_ID"
        app_token="$LAST_TOKEN"
    else
        docker stack deploy --prune --resolve-image always -c "$app_yaml" "$nome_app" \
            >>"$install_log" 2>&1 ||
            fail_install 63 "ERRO AO CRIAR HOMEPAGE NO DOCKER" "Falha ao publicar a stack Homepage."
    fi

    echo -e "XXX\n80\nAGUARDANDO HOMEPAGE E PROXIES FICAREM PRONTOS... \nXXX"
    ready="false"
    for _ in $(seq 1 45); do
        homepage_replicas=$(docker service ls --filter "name=$homepage_service" --format '{{.Replicas}}' 2>>"$install_log" | head -n1)
        gateway_replicas=$(docker service ls --filter "name=$gateway_service" --format '{{.Replicas}}' 2>>"$install_log" | head -n1)
        proxy_replicas=$(docker service ls --filter "name=$proxy_service" --format '{{.Replicas}}' 2>>"$install_log" | head -n1)
        if [ "$homepage_replicas" = "1/1" ] && [ "$gateway_replicas" = "1/1" ] && [ "$proxy_replicas" = "1/1" ]; then
            ready="true"
            break
        fi
        sleep 4
    done
    if [ "$ready" != "true" ]; then
        {
            echo "As stacks foram criadas, mas os três serviços não atingiram 1/1 réplica."
            docker service ps "$homepage_service" --no-trunc --format 'Homepage: {{.CurrentState}} | {{.Error}}' 2>/dev/null | head -n 5
            docker service ps "$gateway_service" --no-trunc --format 'Gateway: {{.CurrentState}} | {{.Error}}' 2>/dev/null | head -n 5
            docker service ps "$proxy_service" --no-trunc --format 'Proxy: {{.CurrentState}} | {{.Error}}' 2>/dev/null | head -n 5
        } >"$error_file"
        fail_install 70 "SERVIÇOS NÃO FICARAM PRONTOS" "$(cat "$error_file")"
    fi

    homepage_container=$(docker ps --filter "label=com.docker.swarm.service.name=$homepage_service" \
        --filter health=healthy --format '{{.ID}}' | head -n1)
    gateway_container=$(docker ps --filter "label=com.docker.swarm.service.name=$gateway_service" \
        --filter health=healthy --format '{{.ID}}' | head -n1)
    [ -n "$homepage_container" ] && [ -n "$gateway_container" ] ||
        fail_install 71 "HEALTHCHECK NÃO CONFIRMADO" "As réplicas subiram, mas Homepage ou gateway ainda não estão saudáveis."
    docker exec "$homepage_container" wget -qO- --header="Host: $url_homepage" \
        http://127.0.0.1:3000/api/healthcheck 2>>"$install_log" | grep -qx 'up' ||
        fail_install 72 "API DO HOMEPAGE INDISPONÍVEL" "O Homepage subiu, mas sua API interna não respondeu corretamente."
    docker exec "$homepage_container" wget -qO- "http://$proxy_service:2375/_ping" \
        2>>"$install_log" | grep -qx 'OK' ||
        fail_install 73 "PROXY DOCKER INDISPONÍVEL" "O Homepage não conseguiu consultar o proxy Docker interno."
    if docker exec "$homepage_container" wget -qO- --post-data='{}' \
        "http://$proxy_service:2375/containers/create" >>"$install_log" 2>&1; then
        fail_install 74 "PROXY DOCKER PERMITIU ESCRITA" "O proxy aceitou uma operação POST e a instalação foi bloqueada por segurança."
    fi
    if docker exec "$gateway_container" wget -qO- http://127.0.0.1:8080/ >>"$install_log" 2>&1; then
        fail_install 75 "PAINEL SEM AUTENTICAÇÃO" "O gateway aceitou acesso anônimo e a instalação foi bloqueada por segurança."
    fi
    rollback_required="false"

    if [ "$INSTALL_TYPE" = "CLOUDFLARE_TUNNEL" ] ||
       { [ "$INSTALL_TYPE" = "TRADICIONAL" ] && [ "$criar_dns" = "0" ]; }; then
        echo -e "XXX\n89\nCONFIGURANDO DNS DE FORMA IDEMPOTENTE... \nXXX"
        dns_lookup="$work_dir/dns-lookup.json"
        dns_response="$work_dir/dns-response.json"
        if [ "$INSTALL_TYPE" = "CLOUDFLARE_TUNNEL" ]; then
            dns_content="${TUNNEL_ID}.cfargotunnel.com"
            dns_proxied="true"
        else
            DOMINIO_PRINCIPAL="${SETUPMNO_SELECTED_ROOT_DOMAIN:-${SETUPMNO_DOMAIN_ROOT:-${CLOUDFLARE_ZONE_NAME:-}}}"
            [ -n "$nome_servidor" ] || nome_servidor=$(hostname -I | awk '{print $1}')
            dns_content="${nome_servidor}.${DOMINIO_PRINCIPAL}"
            dns_proxied="false"
        fi
        dns_payload=$(jq -nc --arg name "$url_homepage" --arg content "$dns_content" \
            --argjson proxied "$dns_proxied" '{type:"CNAME",name:$name,content:$content,ttl:1,proxied:$proxied}')
        curl -sS --get "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records" \
            -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" --data-urlencode "name=$url_homepage" \
            >"$dns_lookup" 2>>"$install_log" ||
            fail_install 80 "ERRO AO CONSULTAR DNS" "Falha de comunicação ao consultar o DNS $url_homepage no Cloudflare."
        dns_record_id=$(jq -r '.result[0].id // empty' "$dns_lookup")
        dns_record_type=$(jq -r '.result[0].type // empty' "$dns_lookup")
        if [ -n "$dns_record_id" ] && [ "$dns_record_type" != "CNAME" ]; then
            fail_install 81 "CONFLITO DE REGISTRO DNS" "Já existe um registro $dns_record_type para $url_homepage. Ele não foi removido automaticamente."
        fi
        if [ -n "$dns_record_id" ]; then
            dns_method="PUT"
            dns_url="https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records/${dns_record_id}"
        else
            dns_method="POST"
            dns_url="https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records"
        fi
        curl -sS -X "$dns_method" "$dns_url" -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
            -H "Content-Type: application/json" --data "$dns_payload" >"$dns_response" 2>>"$install_log" ||
            fail_install 82 "ERRO AO CONFIGURAR DNS" "Falha de comunicação ao configurar o CNAME do Homepage."
        if [ "$(jq -r '.success // false' "$dns_response")" != "true" ]; then
            dns_error=$(jq -r '[.errors[]?.message] | join("; ")' "$dns_response" 2>/dev/null)
            fail_install 83 "ERRO AO CONFIGURAR DNS" "Cloudflare recusou o CNAME: ${dns_error:-resposta inválida da API}."
        fi
    fi

    if [ "$INSTALL_TYPE" = "CLOUDFLARE_TUNNEL" ]; then
        echo -e "XXX\n95\nATUALIZANDO ROTA DO CLOUDFLARE TUNNEL... \nXXX"
        tunnel_raw="$work_dir/tunnel-raw.json"
        tunnel_payload="$work_dir/tunnel-payload.json"
        tunnel_response="$work_dir/tunnel-response.json"
        curl -sS -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
            "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/cfd_tunnel/$TUNNEL_ID/configurations" \
            >"$tunnel_raw" 2>>"$install_log" ||
            fail_install 90 "ERRO AO CONSULTAR TUNNEL" "Não foi possível obter a configuração atual do Cloudflare Tunnel."
        [ "$(jq -r '.success // false' "$tunnel_raw")" = "true" ] ||
            fail_install 91 "ERRO AO CONSULTAR TUNNEL" "A API do Cloudflare recusou a consulta da configuração do Tunnel."
        jq --arg host "$url_homepage" --arg service "http://${gateway_service}:8080" '
            (.result.config // {}) as $cfg
            | ($cfg.ingress // [])
            | map(select(.service != "http_status:404" and .hostname != $host))
            + [{hostname:$host,service:$service,originRequest:{noTlsVerify:true,httpHostHeader:$host}},
               {service:"http_status:404"}]
            | {config:($cfg + {ingress:.})}
        ' "$tunnel_raw" >"$tunnel_payload" 2>>"$install_log" ||
            fail_install 92 "ERRO AO PREPARAR ROTA" "Falha ao preparar a nova rota do Cloudflare Tunnel."
        curl -sS -X PUT \
            "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/cfd_tunnel/$TUNNEL_ID/configurations" \
            -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" -H "Content-Type: application/json" \
            --data-binary @"$tunnel_payload" >"$tunnel_response" 2>>"$install_log" ||
            fail_install 93 "ERRO AO ATUALIZAR TUNNEL" "Falha de comunicação ao atualizar a rota do Homepage."
        if [ "$(jq -r '.success // false' "$tunnel_response")" != "true" ]; then
            tunnel_error=$(jq -r '[.errors[]?.message] | join("; ")' "$tunnel_response" 2>/dev/null)
            fail_install 94 "ERRO AO ATUALIZAR TUNNEL" "Cloudflare recusou a rota: ${tunnel_error:-resposta inválida da API}."
        fi
    fi

    echo -e "XXX\n100\nHOMEPAGE INSTALADO COM SUCESSO\nXXX"
} | whiptail --title "HOMEPAGE PRO" --gauge "Preparando Homepage..." 8 82 0
install_status=${PIPESTATUS[0]}
unset senha_homepage

if [ "$install_status" -ne 0 ]; then
    error_detail=$(cat "$error_file" 2>/dev/null)
    [ -n "$error_detail" ] || error_detail=$(tail -n 20 "$install_log" 2>/dev/null)
    whiptail --title "ERRO NA INSTALAÇÃO DO HOMEPAGE" --msgbox \
        "A instalação foi interrompida sem declarar falso sucesso.\n\n$error_detail\n\nLog completo: $install_log" \
        24 96
    exit "$install_status"
fi

manual_dns_note=""
if [ "$INSTALL_TYPE" = "TRADICIONAL" ] && [ "$criar_dns" = "1" ]; then
    manual_dns_note="\n\nDNS manual: aponte $url_homepage para o servidor antes de acessar."
fi

whiptail --title "HOMEPAGE PRO" --msgbox \
    "Homepage instalado com sucesso.\n\nAcesse: https://$url_homepage\nUsuário: $usuario_homepage\nStack principal: $nome_app\nSubstack de segurança: $proxy_stack\n\nO navegador solicitará o usuário e a senha definidos durante a instalação. As portas 3000 e 2375 não foram publicadas; o Homepage consulta o Swarm por um proxy interno com escrita bloqueada.$manual_dns_note" \
    25 90

#!/usr/bin/bash
# POCKET ID PRO — provedor OIDC com autenticação por passkeys.
set -o pipefail
umask 077

IMAGE_REF="ghcr.io/pocket-id/pocket-id:v2.11.0-distroless@sha256:446624a84743c29f93db2ffbbe19f9059fd9741e0cb2516d31efcc764e131835"
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
    whiptail --title "POCKET ID PRO" --msgbox "$1" 15 80 1>&2
}

ask_required() {
    local prompt="$1" value status
    while true; do
        value=$(whiptail --title "POCKET ID PRO" --inputbox "$prompt" 13 80 3>&1 1>&2 2>&3)
        status=$?
        [ "$status" -ne 0 ] && return 130
        if [ -n "$value" ]; then
            printf '%s' "$value"
            return 0
        fi
        msg "Este campo é obrigatório."
    done
}

whiptail --title "POCKET ID PRO" --yesno \
    "Instalar Pocket ID como ferramenta PRO?\n\nProvedor de identidade OIDC moderno, com login sem senha por passkeys, biometria ou chave de segurança. O acesso precisa usar HTTPS." \
    16 82 || exit 0

while true; do
    if ! url_pocketid=$(ask_required "1/2 — Domínio do Pocket ID (ex.: login.seudominio.com):"); then
        exit 0
    fi
    if [[ "$url_pocketid" =~ ^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$ ]] &&
       [[ "$url_pocketid" == *.* ]]; then
        break
    fi
    msg "Informe somente o domínio, sem http://, https://, barras ou caminhos."
done

if [ "$INSTALL_TYPE" = "CLOUDFLARE_TUNNEL" ]; then
    route_check=$(mktemp)
    whiptail --title "POCKET ID PRO" --infobox \
        "Verificando se o domínio já possui uma rota no Cloudflare Tunnel..." 8 80
    if ! curl -sS -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
        "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/cfd_tunnel/$TUNNEL_ID/configurations" \
        >"$route_check" 2>/dev/null; then
        rm -f "$route_check"
        msg "Não foi possível consultar o Cloudflare Tunnel. Verifique as credenciais e tente novamente."
        exit 1
    fi
    existing_service=$(jq -r --arg host "$url_pocketid" \
        '.result.config.ingress[]? | select(.hostname == $host) | .service' "$route_check" 2>/dev/null | head -n1)
    rm -f "$route_check"
    if [ -n "$existing_service" ] && [ "$existing_service" != "null" ]; then
        msg "Já existe uma rota para:\n\n$url_pocketid\n\nServiço atual: $existing_service\n\nA rota será substituída pela nova instalação."
    fi
fi

while true; do
    if ! criar_portainer=$(ask_required "2/2 — Criar Stack no Portainer?\n\n0 = editável no Portainer\n1 = direta no Docker"); then
        exit 0
    fi
    [[ "$criar_portainer" =~ ^[01]$ ]] && break
    msg "Digite somente 0 ou 1."
done

nome_principal="pocketid"
sufixo_app=$(date +%s%N | md5sum | head -c7)
nome_app="${nome_principal}${sufixo_app}"
service_name="${nome_app}_${nome_app}"
secret_name="${nome_app}_encryption_key"
data_dir="/root/${nome_app}_data"
app_yaml="/root/${nome_app}.yaml"

dns_mode="Cloudflare Tunnel"
if [ "$INSTALL_TYPE" = "TRADICIONAL" ]; then
    if [ "$criar_dns" = "0" ]; then
        dns_mode="Tradicional com DNS automático"
    else
        dns_mode="Tradicional com DNS manual"
    fi
fi

whiptail --title "Confirmar instalação" --yesno \
    "Pocket ID PRO\n\nDomínio: $url_pocketid\nInstalação: $dns_mode\nStack: $([ "$criar_portainer" = "0" ] && echo "Portainer editável" || echo "Docker direta")\nArquiteturas: X86 e ARM\nRAM máxima: 512 MB\nPorta 1411: somente interna\nCriptografia: Docker Secret automático\nExecução: não-root e filesystem somente leitura" \
    23 86 || exit 0

install_log="/tmp/${nome_app}-install.log"
error_file="/tmp/${nome_app}-error.log"
: >"$install_log"
: >"$error_file"

{
    work_dir=$(mktemp -d)
    secret_created="false"
    stack_created="false"
    portainer_stack_id=""
    portainer_endpoint_id=""
    portainer_token=""

    cleanup_workdir() {
        rm -rf "$work_dir"
    }
    trap cleanup_workdir EXIT

    rollback_deployment() {
        echo "Executando rollback dos recursos incompletos..." >>"$install_log"
        if [ "$stack_created" = "true" ]; then
            if [ "$criar_portainer" = "0" ] &&
               [ -n "$portainer_stack_id" ] && [ -n "$portainer_endpoint_id" ] && [ -n "$portainer_token" ]; then
                curl -sk -X DELETE \
                    "https://$PORTAINER_URL/api/stacks/$portainer_stack_id?endpointId=$portainer_endpoint_id" \
                    -H "Authorization: Bearer $portainer_token" >>"$install_log" 2>&1 || true
            else
                docker stack rm "$nome_app" >>"$install_log" 2>&1 || true
            fi
            for _ in $(seq 1 30); do
                docker service inspect "$service_name" >/dev/null 2>&1 || break
                sleep 1
            done
        fi
        if [ "$secret_created" = "true" ]; then
            docker secret rm "$secret_name" >>"$install_log" 2>&1 || true
        fi
        if [[ "$data_dir" == /root/pocketid*_data ]]; then
            rm -rf "$data_dir"
        fi
    }

    fail_install() {
        local code="$1" progress="$2" message="$3"
        rollback_deployment
        printf '%s\n' "$message" >"$error_file"
        echo -e "XXX\n100\n$progress\nXXX"
        exit "$code"
    }

    echo -e "XXX\n5\nVALIDANDO AMBIENTE, SWARM E REDES... \nXXX"
    for required_command in docker curl jq openssl grep awk; do
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
    docker network inspect interna >/dev/null 2>>"$install_log" ||
        fail_install 15 "REDE INTERNA AUSENTE" "A rede interna do Setup MNO não foi encontrada."
    docker secret inspect "$secret_name" >/dev/null 2>&1 &&
        fail_install 16 "COLISÃO DE SEGREDO" "O segredo exclusivo $secret_name já existe; a instalação foi interrompida."

    if [ "$INSTALL_TYPE" = "CLOUDFLARE_TUNNEL" ] ||
       { [ "$INSTALL_TYPE" = "TRADICIONAL" ] && [ "$criar_dns" = "0" ]; }; then
        [ -n "$CLOUDFLARE_API_TOKEN" ] && [ -n "$CLOUDFLARE_ZONE_ID" ] ||
            fail_install 17 "CREDENCIAIS CLOUDFLARE INVÁLIDAS" "Token ou Zone ID do Cloudflare não encontrado nas credenciais."
    fi
    if [ "$INSTALL_TYPE" = "CLOUDFLARE_TUNNEL" ]; then
        [ -n "$CLOUDFLARE_ACCOUNT_ID" ] && [ -n "$TUNNEL_ID" ] ||
            fail_install 18 "DADOS DO TUNNEL INVÁLIDOS" "Account ID ou Tunnel ID não encontrado nas credenciais."
    fi

    echo -e "XXX\n15\nBAIXANDO IMAGEM OFICIAL MULTI-ARQUITETURA... \nXXX"
    docker pull "$IMAGE_REF" >>"$install_log" 2>&1 ||
        fail_install 20 "ERRO AO BAIXAR IMAGEM" "Falha ao baixar a imagem oficial do Pocket ID."
    image_user=$(docker image inspect --format '{{.Config.User}}' "$IMAGE_REF" 2>>"$install_log") ||
        fail_install 21 "IMAGEM NÃO ENCONTRADA" "A imagem foi baixada, mas não pôde ser inspecionada."
    [ "$image_user" = "65532" ] ||
        fail_install 22 "IMAGEM INESPERADA" "A imagem distroless não confirmou o usuário não-root oficial 65532."

    echo -e "XXX\n25\nCRIANDO DADOS E CHAVE DE CRIPTOGRAFIA... \nXXX"
    mkdir -p "$data_dir" >>"$install_log" 2>&1 ||
        fail_install 23 "ERRO AO CRIAR DADOS" "Não foi possível criar o diretório persistente $data_dir."
    chmod 700 "$data_dir"
    chown 65532:65532 "$data_dir" >>"$install_log" 2>&1 ||
        fail_install 24 "ERRO DE PERMISSÃO" "Não foi possível restringir o diretório persistente ao usuário do Pocket ID."
    if ! openssl rand -base64 32 | docker secret create "$secret_name" - >>"$install_log" 2>&1; then
        fail_install 25 "ERRO AO CRIAR SEGREDO" "Não foi possível criar a chave de criptografia no Docker Secret."
    fi
    secret_created="true"

    echo -e "XXX\n38\nGERANDO E VALIDANDO STACK SEGURA... \nXXX"
    cat >"$app_yaml" <<EOYAML
version: "3.8"
services:
  $nome_app:
    image: $IMAGE_REF
    hostname: $nome_app
    user: "65532:65532"
    read_only: true
    cap_drop:
      - ALL
    environment:
      APP_URL: https://$url_pocketid
      ENCRYPTION_KEY_FILE: /run/secrets/encryption_key
      TRUST_PROXY: "true"
      ALLOW_INSECURE_CALLBACK_URLS: "false"
      DISABLE_RATE_LIMITING: "false"
      ANALYTICS_DISABLED: "true"
    secrets:
      - source: encryption_key
        target: encryption_key
        uid: "65532"
        gid: "65532"
        mode: 0400
    volumes:
      - $data_dir:/app/data
    networks:
      - externa
      - interna
    healthcheck:
      test: ["CMD", "/app/pocket-id", "healthcheck"]
      interval: 15s
      timeout: 5s
      retries: 10
      start_period: 20s
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
          cpus: "0.50"
          memory: 512M
        reservations:
          memory: 64M
EOYAML

    if [ "$INSTALL_TYPE" = "TRADICIONAL" ]; then
        cat >>"$app_yaml" <<EOYAML
      labels:
        - traefik.enable=true
        - traefik.docker.network=externa
        - traefik.http.routers.$nome_app.rule=Host(\`$url_pocketid\`)
        - traefik.http.routers.$nome_app.entrypoints=websecure
        - traefik.http.routers.$nome_app.priority=1
        - traefik.http.routers.$nome_app.tls.certresolver=letsencryptresolver
        - traefik.http.routers.$nome_app.tls=true
        - traefik.http.routers.$nome_app.service=$nome_app
        - traefik.http.services.$nome_app.loadbalancer.server.port=1411
EOYAML
    fi

    cat >>"$app_yaml" <<EOYAML

networks:
  externa:
    external: true
  interna:
    external: true

secrets:
  encryption_key:
    external: true
    name: $secret_name
EOYAML

    docker stack config -c "$app_yaml" >"$work_dir/validated-stack.yaml" 2>>"$install_log" ||
        fail_install 30 "ERRO NO YAML DA STACK" "O YAML gerado para o Pocket ID é inválido."

    if [ "$INSTALL_TYPE" = "CLOUDFLARE_TUNNEL" ] ||
       { [ "$INSTALL_TYPE" = "TRADICIONAL" ] && [ "$criar_dns" = "0" ]; }; then
        echo -e "XXX\n52\nCONFIGURANDO DNS DE FORMA IDEMPOTENTE... \nXXX"
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
        dns_payload=$(jq -nc --arg name "$url_pocketid" --arg content "$dns_content" \
            --argjson proxied "$dns_proxied" '{type:"CNAME",name:$name,content:$content,ttl:1,proxied:$proxied}')
        curl -sS --get "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records" \
            -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" --data-urlencode "name=$url_pocketid" \
            >"$dns_lookup" 2>>"$install_log" ||
            fail_install 40 "ERRO AO CONSULTAR DNS" "Falha de comunicação ao consultar o DNS $url_pocketid no Cloudflare."
        dns_record_id=$(jq -r '.result[0].id // empty' "$dns_lookup")
        dns_record_type=$(jq -r '.result[0].type // empty' "$dns_lookup")
        if [ -n "$dns_record_id" ] && [ "$dns_record_type" != "CNAME" ]; then
            fail_install 41 "CONFLITO DE REGISTRO DNS" "Já existe um registro $dns_record_type para $url_pocketid. Ele não foi removido."
        fi
        if [ -n "$dns_record_id" ]; then
            dns_method="PUT"
            dns_url="https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records/${dns_record_id}"
        else
            dns_method="POST"
            dns_url="https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records"
        fi
        if ! curl -sS -X "$dns_method" "$dns_url" -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
            -H "Content-Type: application/json" --data "$dns_payload" >"$dns_response" 2>>"$install_log" ||
           [ "$(jq -r '.success // false' "$dns_response")" != "true" ]; then
            dns_error=$(jq -r '[.errors[]?.message] | join("; ")' "$dns_response" 2>/dev/null)
            fail_install 42 "ERRO AO CONFIGURAR DNS" "Cloudflare recusou o CNAME: ${dns_error:-resposta inválida da API}."
        fi
    fi

    if [ "$INSTALL_TYPE" = "CLOUDFLARE_TUNNEL" ]; then
        echo -e "XXX\n66\nATUALIZANDO ROTA DO CLOUDFLARE TUNNEL... \nXXX"
        tunnel_raw="$work_dir/tunnel-raw.json"
        tunnel_payload="$work_dir/tunnel-payload.json"
        tunnel_response="$work_dir/tunnel-response.json"
        if ! curl -sS -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
            "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/cfd_tunnel/$TUNNEL_ID/configurations" \
            >"$tunnel_raw" 2>>"$install_log" ||
           [ "$(jq -r '.success // false' "$tunnel_raw")" != "true" ]; then
            fail_install 50 "ERRO AO CONSULTAR TUNNEL" "Não foi possível obter a configuração atual do Cloudflare Tunnel."
        fi
        jq --arg host "$url_pocketid" --arg service "http://${nome_app}:1411" '
            (.result.config // {}) as $cfg
            | ($cfg.ingress // [])
            | map(select(.service != "http_status:404" and .hostname != $host))
            + [{hostname:$host,service:$service,originRequest:{httpHostHeader:$host}},
               {service:"http_status:404"}]
            | {config:($cfg + {ingress:.})}
        ' "$tunnel_raw" >"$tunnel_payload" 2>>"$install_log" ||
            fail_install 51 "ERRO AO PREPARAR ROTA" "Falha ao preparar a nova rota do Cloudflare Tunnel."
        if ! curl -sS -X PUT \
            "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/cfd_tunnel/$TUNNEL_ID/configurations" \
            -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" -H "Content-Type: application/json" \
            --data-binary @"$tunnel_payload" >"$tunnel_response" 2>>"$install_log" ||
           [ "$(jq -r '.success // false' "$tunnel_response")" != "true" ]; then
            tunnel_error=$(jq -r '[.errors[]?.message] | join("; ")' "$tunnel_response" 2>/dev/null)
            fail_install 52 "ERRO AO ATUALIZAR TUNNEL" "Cloudflare recusou a rota: ${tunnel_error:-resposta inválida da API}."
        fi
    fi

    echo -e "XXX\n78\nPUBLICANDO STACK... \nXXX"
    if [ "$criar_portainer" = "0" ]; then
        dados_file="$HOME/dados_portainer/dados_portainer"
        [ -f "$dados_file" ] ||
            fail_install 60 "CREDENCIAIS DO PORTAINER NÃO ENCONTRADAS" "Arquivo não encontrado: $dados_file"
        PORTAINER_URL=$(grep "Dominio do portainer:" "$dados_file" | cut -d':' -f2- | xargs)
        ADMIN_USERNAME=$(grep "Usuario:" "$dados_file" | cut -d':' -f2- | xargs)
        ADMIN_PASSWORD=$(grep "Senha:" "$dados_file" | cut -d':' -f2- | xargs)
        [ -n "$PORTAINER_URL" ] && [ -n "$ADMIN_USERNAME" ] && [ -n "$ADMIN_PASSWORD" ] ||
            fail_install 61 "CREDENCIAIS DO PORTAINER INVÁLIDAS" "Domínio, usuário ou senha do Portainer não encontrado."
        auth_payload="$work_dir/portainer-auth-payload.json"
        auth_response="$work_dir/portainer-auth.json"
        jq -nc --arg username "$ADMIN_USERNAME" --arg password "$ADMIN_PASSWORD" \
            '{username:$username,password:$password}' >"$auth_payload"
        curl -sk -X POST "https://$PORTAINER_URL/api/auth" -H "Content-Type: application/json" \
            --data-binary @"$auth_payload" >"$auth_response" 2>>"$install_log" ||
            fail_install 62 "ERRO DE COMUNICAÇÃO COM PORTAINER" "Não foi possível acessar a API do Portainer."
        portainer_token=$(jq -r '.jwt // empty' "$auth_response")
        [ -n "$portainer_token" ] ||
            fail_install 63 "ERRO DE AUTENTICAÇÃO NO PORTAINER" "O Portainer não retornou um token válido."
        endpoint_response="$work_dir/portainer-endpoints.json"
        curl -sk "https://$PORTAINER_URL/api/endpoints" -H "Authorization: Bearer $portainer_token" \
            >"$endpoint_response" 2>>"$install_log" ||
            fail_install 64 "ERRO AO CONSULTAR ENDPOINT" "Falha ao consultar os endpoints do Portainer."
        portainer_endpoint_id=$(jq -r '.[0].Id // empty' "$endpoint_response")
        [ -n "$portainer_endpoint_id" ] ||
            fail_install 65 "ENDPOINT NÃO ENCONTRADO" "Nenhum endpoint foi encontrado no Portainer."
        swarm_response="$work_dir/portainer-swarm.json"
        curl -sk "https://$PORTAINER_URL/api/endpoints/$portainer_endpoint_id/docker/swarm" \
            -H "Authorization: Bearer $portainer_token" >"$swarm_response" 2>>"$install_log" ||
            fail_install 66 "ERRO AO CONSULTAR SWARM" "Falha ao consultar o Docker Swarm pelo Portainer."
        SWARM_ID=$(jq -r '.ID // empty' "$swarm_response")
        [ -n "$SWARM_ID" ] ||
            fail_install 67 "SWARM NÃO ENCONTRADO" "O Portainer não retornou um Swarm ID válido."
        portainer_response="$work_dir/portainer-stack.json"
        http_code=$(curl -sk -o "$portainer_response" -w "%{http_code}" -X POST \
            -H "Authorization: Bearer $portainer_token" -F "Name=$nome_app" -F "file=@$app_yaml" \
            -F "SwarmID=$SWARM_ID" -F "endpointId=$portainer_endpoint_id" \
            "https://$PORTAINER_URL/api/stacks/create/swarm/file" 2>>"$install_log")
        if ! [[ "$http_code" =~ ^[0-9]{3}$ ]] || [ "$http_code" -lt 200 ] || [ "$http_code" -ge 300 ]; then
            portainer_error=$(jq -r '.message // empty' "$portainer_response" 2>/dev/null)
            fail_install 68 "ERRO AO CRIAR STACK NO PORTAINER" "Portainer recusou a stack (HTTP ${http_code:-indisponível}): ${portainer_error:-sem detalhes}."
        fi
        # A partir do HTTP 2xx a stack já pertence a esta execução. Marque-a
        # antes de validar o ID para que uma resposta incompleta também acione
        # o rollback seguro pelo nome exato da stack.
        stack_created="true"
        portainer_stack_id=$(jq -r '.Id // .id // empty' "$portainer_response")
        [ -n "$portainer_stack_id" ] ||
            fail_install 69 "STACK SEM IDENTIFICADOR" "O Portainer criou a stack sem retornar um identificador válido."
    else
        docker stack deploy --prune --resolve-image always -c "$app_yaml" "$nome_app" >>"$install_log" 2>&1 ||
            fail_install 70 "ERRO AO CRIAR STACK NO DOCKER" "O Docker recusou a stack do Pocket ID."
        stack_created="true"
    fi

    echo -e "XXX\n92\nAGUARDANDO HEALTHCHECK E PERSISTÊNCIA... \nXXX"
    ready="false"
    for _ in $(seq 1 60); do
        replicas=$(docker service ls --filter "name=$service_name" --format '{{.Replicas}}' 2>>"$install_log" | head -n1)
        container_id=$(docker ps -q --filter "label=com.docker.swarm.service.name=$service_name" 2>>"$install_log" | head -n1)
        health_status=""
        [ -n "$container_id" ] && health_status=$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{end}}' "$container_id" 2>>"$install_log")
        if [ "$replicas" = "1/1" ] && [ "$health_status" = "healthy" ]; then
            ready="true"
            break
        fi
        sleep 3
    done
    if [ "$ready" != "true" ]; then
        docker service ps "$service_name" --no-trunc >>"$install_log" 2>&1 || true
        docker service logs --raw --tail 80 "$service_name" >>"$install_log" 2>&1 || true
        fail_install 80 "SERVIÇO NÃO FICOU PRONTO" "O serviço $service_name não atingiu 1/1 réplica saudável."
    fi
    docker exec "$container_id" /app/pocket-id healthcheck >>"$install_log" 2>&1 ||
        fail_install 81 "HEALTHCHECK INTERNO FALHOU" "O Pocket ID iniciou, mas o healthcheck oficial falhou."
    [ -s "$data_dir/pocket-id.db" ] ||
        fail_install 82 "PERSISTÊNCIA NÃO CONFIRMADA" "O banco SQLite não foi criado no diretório persistente."

    mkdir -p /root/dados_pocketid
    chmod 700 /root/dados_pocketid
    cat >"/root/dados_pocketid/${nome_app}" <<EODATA
Pocket ID
Dominio: $url_pocketid
Stack: $nome_app
Dados: $data_dir
Docker Secret: $secret_name
Cadastro inicial: https://$url_pocketid/setup
EODATA
    chmod 600 "/root/dados_pocketid/${nome_app}"

    stack_created="false"
    secret_created="false"
    echo -e "XXX\n100\nPOCKET ID INSTALADO COM SUCESSO\nXXX"
} | whiptail --title "POCKET ID PRO" --gauge "Preparando Pocket ID..." 8 80 0
install_status=${PIPESTATUS[0]}

if [ "$install_status" -ne 0 ]; then
    error_detail=$(cat "$error_file" 2>/dev/null)
    [ -n "$error_detail" ] || error_detail=$(tail -n 18 "$install_log" 2>/dev/null)
    whiptail --title "ERRO NA INSTALAÇÃO DO POCKET ID" --msgbox \
        "A instalação foi interrompida sem declarar falso sucesso.\n\n$error_detail\n\nLog completo: $install_log" \
        24 92
    exit "$install_status"
fi

manual_dns_note=""
if [ "$INSTALL_TYPE" = "TRADICIONAL" ] && [ "$criar_dns" = "1" ]; then
    manual_dns_note="\n\nDNS manual: aponte $url_pocketid para o servidor antes de acessar."
fi

whiptail --title "POCKET ID PRO" --msgbox \
    "Pocket ID instalado com sucesso.\n\n1. Acesse: https://$url_pocketid/setup\n2. Cadastre o primeiro administrador.\n3. Registre uma passkey usando biometria, PIN do dispositivo ou chave de segurança.\n\nStack: $nome_app\nDados criptografados e persistentes: $data_dir$manual_dns_note" \
    22 86

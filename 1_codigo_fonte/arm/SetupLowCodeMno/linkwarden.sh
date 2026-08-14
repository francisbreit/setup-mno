#!/usr/bin/bash
# LINKWARDEN PRO — favoritos colaborativos, leitura e preservação de páginas.
set -o pipefail
umask 077

LINKWARDEN_IMAGE="ghcr.io/linkwarden/linkwarden:v2.14.1@sha256:31cf4bd2a2e111991fa5c9de03174c8698869c83722105c6ce529e4c911e6861"
POSTGRES_IMAGE="postgres:16.10-alpine@sha256:029660641a0cfc575b14f336ba448fb8a75fd595d42e1fa316b9fb4378742297"
MEILI_IMAGE="getmeili/meilisearch:v1.12.8@sha256:c9fac23131cca4db95173d41cc50fd5639121ee381795528fdd7522d7978a7b8"

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
    whiptail --title "LINKWARDEN PRO" --msgbox "$1" 16 84 1>&2
}

ask_required() {
    local prompt="$1" value status
    while true; do
        value=$(whiptail --title "LINKWARDEN PRO" --inputbox "$prompt" 14 84 3>&1 1>&2 2>&3)
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
    local first second status
    while true; do
        first=$(whiptail --title "LINKWARDEN PRO" --passwordbox \
            "Senha do primeiro administrador.\n\nMínimo de 12 caracteres, com maiúscula, minúscula, número e símbolo." \
            14 84 3>&1 1>&2 2>&3)
        status=$?
        [ "$status" -ne 0 ] && return 130
        if [ "${#first}" -lt 12 ]; then
            msg "A senha precisa ter pelo menos 12 caracteres."
            continue
        fi
        [[ "$first" =~ [A-Z] ]] || { msg "A senha precisa conter uma letra maiúscula."; continue; }
        [[ "$first" =~ [a-z] ]] || { msg "A senha precisa conter uma letra minúscula."; continue; }
        [[ "$first" =~ [0-9] ]] || { msg "A senha precisa conter um número."; continue; }
        [[ "$first" =~ [^A-Za-z0-9] ]] || { msg "A senha precisa conter um símbolo."; continue; }
        second=$(whiptail --title "LINKWARDEN PRO" --passwordbox \
            "Repita a senha do primeiro administrador:" 11 84 3>&1 1>&2 2>&3)
        status=$?
        [ "$status" -ne 0 ] && return 130
        if [ "$first" != "$second" ]; then
            msg "As senhas não são iguais. Tente novamente."
            continue
        fi
        printf '%s' "$first"
        return 0
    done
}

valid_domain() {
    [[ "$1" =~ ^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$ ]] && [[ "$1" == *.* ]]
}

whiptail --title "LINKWARDEN PRO" --yesno \
    "Instalar Linkwarden PRO?\n\nGerenciador colaborativo de favoritos que organiza, pesquisa e preserva páginas como screenshot, PDF e HTML.\n\nA instalação segura usa PostgreSQL e Meilisearch exclusivos." \
    17 86 || exit 0

while true; do
    if ! url_linkwarden=$(ask_required "1/5 — Domínio principal (ex.: links.seudominio.com):"); then exit 0; fi
    valid_domain "$url_linkwarden" && break
    msg "Informe somente um domínio válido, sem http://, https://, barras ou caminhos."
done

while true; do
    if ! url_content=$(ask_required "2/5 — Domínio isolado dos arquivos preservados\n(ex.: arquivos.seudominio.com):"); then exit 0; fi
    if ! valid_domain "$url_content"; then
        msg "Informe somente um domínio válido, sem http://, https://, barras ou caminhos."
        continue
    fi
    if [ "$url_content" = "$url_linkwarden" ]; then
        msg "O domínio de arquivos precisa ser diferente do domínio principal para isolar conteúdo não confiável."
        continue
    fi
    break
done

while true; do
    if ! admin_name=$(ask_required "3/5 — Nome do primeiro administrador:"); then exit 0; fi
    [ "${#admin_name}" -le 80 ] && break
    msg "O nome deve possuir no máximo 80 caracteres."
done

while true; do
    if ! admin_username=$(ask_required "4/5 — Usuário do primeiro administrador:"); then exit 0; fi
    if [[ "$admin_username" =~ ^[A-Za-z0-9._-]{3,64}$ ]]; then break; fi
    msg "Use de 3 a 64 caracteres: letras, números, ponto, hífen ou sublinhado."
done

if ! admin_password=$(ask_password); then exit 0; fi

while true; do
    if ! criar_portainer=$(ask_required "5/5 — Criar as três stacks no Portainer?\n\n0 = editáveis no Portainer\n1 = diretas no Docker"); then exit 0; fi
    [[ "$criar_portainer" =~ ^[01]$ ]] && break
    msg "Digite somente 0 ou 1."
done

nome_principal="linkwarden"
sufixo_app=$(date +%s%N | md5sum | head -c7)
nome_app="${nome_principal}${sufixo_app}"
postgres_stack="${nome_app}-postgres"
meili_stack="${nome_app}-meilisearch"
app_stack="$nome_app"
postgres_service="${postgres_stack}_postgres"
meili_service="${meili_stack}_meilisearch"
app_service="${app_stack}_linkwarden"
postgres_secret="${nome_app}_postgres_password"
meili_secret="${nome_app}_meili_master_key"
nextauth_secret="${nome_app}_nextauth_secret"
base_dir="/root/${nome_app}_data"
postgres_dir="$base_dir/postgres"
meili_dir="$base_dir/meilisearch"
app_data_dir="$base_dir/data"
app_tmp_dir="$base_dir/tmp"
postgres_yaml="/root/${postgres_stack}.yaml"
meili_yaml="/root/${meili_stack}.yaml"
app_yaml="/root/${app_stack}.yaml"

dns_mode="Cloudflare Tunnel"
if [ "$INSTALL_TYPE" = "TRADICIONAL" ]; then
    if [ "$criar_dns" = "0" ]; then dns_mode="Tradicional com DNS automático"; else dns_mode="Tradicional com DNS manual"; fi
fi

whiptail --title "Confirmar instalação" --yesno \
    "Linkwarden PRO v2.14.1\n\nPainel: https://$url_linkwarden\nArquivos isolados: https://$url_content\nAdministrador: $admin_username\nAcesso: $dns_mode\nGestão: $([ "$criar_portainer" = "0" ] && echo "3 stacks editáveis no Portainer" || echo "3 stacks diretas no Docker")\nArquiteturas: X86 e ARM\nRAM máxima do combo: 2,5 GB\nPortas: somente internas" \
    23 90 || exit 0

install_log="/tmp/${nome_app}-install.log"
error_file="/tmp/${nome_app}-error.log"
: >"$install_log"
: >"$error_file"

{
    work_dir=$(mktemp -d)
    created_stacks=()
    created_secrets=()
    portainer_ids=()
    portainer_endpoint_id=""
    portainer_token=""
    route_updated="false"
    dns_app_changed="false"
    dns_content_changed="false"

    cleanup_workdir() {
        rm -rf "$work_dir"
    }
    trap cleanup_workdir EXIT

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
        unset auth_payload ADMIN_PASSWORD
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

    create_portainer_stack() {
        local stack_name="$1" yaml_file="$2" response http_code stack_id
        # Cada substack realiza autenticação, descoberta do endpoint e do Swarm.
        portainer_login || return 1
        response="$work_dir/portainer-create-${stack_name}.json"
        http_code=$(curl -sk -o "$response" -w '%{http_code}' -X POST \
            -H "Authorization: Bearer $portainer_token" -F "Name=$stack_name" -F "file=@$yaml_file" \
            -F "SwarmID=$PORTAINER_SWARM_ID" -F "endpointId=$portainer_endpoint_id" \
            "https://$PORTAINER_URL/api/stacks/create/swarm/file" 2>>"$install_log")
        [[ "$http_code" =~ ^2[0-9][0-9]$ ]] || return 1
        stack_id=$(jq -r '.Id // .id // empty' "$response")
        [ -n "$stack_id" ] || return 1
        portainer_ids+=("$stack_name:$stack_id")
    }

    deploy_stack() {
        local stack_name="$1" yaml_file="$2"
        # O nome é exclusivo desta execução. Registrá-lo antes do deploy garante
        # limpeza mesmo se Docker ou Portainer criarem recursos e retornarem erro.
        created_stacks+=("$stack_name")
        if [ "$criar_portainer" = "0" ]; then
            create_portainer_stack "$stack_name" "$yaml_file"
        else
            docker stack deploy --prune --resolve-image always -c "$yaml_file" "$stack_name" >>"$install_log" 2>&1
        fi
    }

    delete_portainer_stacks() {
        local pair stack_name stack_id
        [ "$criar_portainer" = "0" ] || return 0
        portainer_login || return 0
        for pair in "${portainer_ids[@]}"; do
            stack_name=${pair%%:*}
            stack_id=${pair#*:}
            curl -sk -X DELETE \
                "https://$PORTAINER_URL/api/stacks/$stack_id?endpointId=$portainer_endpoint_id" \
                -H "Authorization: Bearer $portainer_token" >>"$install_log" 2>&1 ||
                docker stack rm "$stack_name" >>"$install_log" 2>&1 || true
        done
    }

    restore_dns() {
        local label="$1" changed="$2" record_id old_file created_file payload
        [ "$changed" = "true" ] || return 0
        record_id=$(cat "$work_dir/${label}-dns-id" 2>/dev/null)
        old_file="$work_dir/${label}-dns-old.json"
        created_file="$work_dir/${label}-dns-created"
        if [ -f "$created_file" ] && [ -n "$record_id" ]; then
            curl -sS -X DELETE \
                "https://api.cloudflare.com/client/v4/zones/$CLOUDFLARE_ZONE_ID/dns_records/$record_id" \
                -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" >>"$install_log" 2>&1 || true
        elif [ -s "$old_file" ] && [ -n "$record_id" ]; then
            payload="$work_dir/${label}-dns-restore.json"
            jq '{type,name,content,ttl,proxied}' "$old_file" >"$payload" 2>/dev/null || return 0
            curl -sS -X PUT \
                "https://api.cloudflare.com/client/v4/zones/$CLOUDFLARE_ZONE_ID/dns_records/$record_id" \
                -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" -H "Content-Type: application/json" \
                --data-binary @"$payload" >>"$install_log" 2>&1 || true
        fi
    }

    rollback_deployment() {
        local stack_name secret_name yaml_file original_payload
        echo "Executando rollback exclusivo do Linkwarden..." >>"$install_log"
        if [ "$route_updated" = "true" ] && [ -s "$work_dir/tunnel-original.json" ]; then
            original_payload="$work_dir/tunnel-restore.json"
            jq '{config:.result.config}' "$work_dir/tunnel-original.json" >"$original_payload" 2>/dev/null &&
                curl -sS -X PUT \
                    "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/cfd_tunnel/$TUNNEL_ID/configurations" \
                    -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" -H "Content-Type: application/json" \
                    --data-binary @"$original_payload" >>"$install_log" 2>&1 || true
        fi
        restore_dns app "$dns_app_changed"
        restore_dns content "$dns_content_changed"
        delete_portainer_stacks
        for stack_name in "${created_stacks[@]}"; do
            docker stack rm "$stack_name" >>"$install_log" 2>&1 || true
        done
        for service_name in "$app_service" "$meili_service" "$postgres_service"; do
            for _ in $(seq 1 40); do
                docker service inspect "$service_name" >/dev/null 2>&1 || break
                sleep 1
            done
        done
        for secret_name in "${created_secrets[@]}"; do
            docker secret rm "$secret_name" >>"$install_log" 2>&1 || true
        done
        if [[ "$base_dir" == /root/linkwarden*_data ]]; then rm -rf "$base_dir"; fi
        for yaml_file in "$postgres_yaml" "$meili_yaml" "$app_yaml"; do
            if [[ "$yaml_file" == /root/linkwarden*.yaml ]]; then rm -f -- "$yaml_file"; fi
        done
    }

    fail_install() {
        local code="$1" progress="$2" message="$3"
        rollback_deployment
        printf '%s\n' "$message" >"$error_file"
        echo -e "XXX\n100\n$progress\nXXX"
        exit "$code"
    }

    wait_service() {
        local service="$1" attempts="$2" expected_health="$3" previous_container="${4:-}" replicas container_id health
        WAIT_CONTAINER_ID=""
        for _ in $(seq 1 "$attempts"); do
            replicas=$(docker service ls --filter "name=$service" --format '{{.Replicas}}' 2>>"$install_log" | head -n1)
            container_id=$(docker ps -q --filter "label=com.docker.swarm.service.name=$service" 2>>"$install_log" | head -n1)
            health=""
            [ -n "$container_id" ] && health=$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{end}}' "$container_id" 2>>"$install_log")
            if [ "$replicas" = "1/1" ] && [ "$container_id" != "$previous_container" ] &&
                { [ -z "$expected_health" ] || [ "$health" = "$expected_health" ]; }; then
                WAIT_CONTAINER_ID="$container_id"
                return 0
            fi
            sleep 3
        done
        docker service ps "$service" --no-trunc >>"$install_log" 2>&1 || true
        docker service logs --raw --tail 100 "$service" >>"$install_log" 2>&1 || true
        return 1
    }

    wait_secure_config() {
        local container_id="$1" expected_domain="$2" attempts="${3:-30}" config_json config_summary
        for _ in $(seq 1 "$attempts"); do
            config_json=$(docker exec "$container_id" curl -fsS http://127.0.0.1:3000/api/v1/config 2>>"$install_log" || true)
            if printf '%s' "$config_json" | jq -e --arg domain "$expected_domain" \
                '(.response.DISABLE_REGISTRATION == true) and (.response.USER_CONTENT_DOMAIN == $domain)' >/dev/null 2>&1; then
                echo "Configuração segura confirmada pela API do Linkwarden." >>"$install_log"
                return 0
            fi
            config_summary=$(printf '%s' "$config_json" | jq -c \
                '{disableRegistration:(.response.DISABLE_REGISTRATION // null),userContentDomain:(.response.USER_CONTENT_DOMAIN // null)}' \
                2>/dev/null || echo '{"response":"indisponivel"}')
            echo "Aguardando configuração segura do Linkwarden: $config_summary" >>"$install_log"
            sleep 2
        done
        return 1
    }

    echo -e "XXX\n4\nVALIDANDO AMBIENTE, SWARM E REDES...\nXXX"
    for required_command in docker curl jq openssl grep awk sed; do
        command -v "$required_command" >/dev/null 2>&1 ||
            fail_install 10 "DEPENDÊNCIA NÃO ENCONTRADA" "O comando obrigatório '$required_command' não está instalado."
    done
    [ -f "$CREDENTIALS_FILE" ] || fail_install 11 "CREDENCIAIS NÃO ENCONTRADAS" "Arquivo não encontrado: $CREDENTIALS_FILE"
    docker info >/dev/null 2>>"$install_log" || fail_install 12 "DOCKER INDISPONÍVEL" "O Docker não está acessível."
    [ "$(docker info --format '{{.Swarm.LocalNodeState}}' 2>>"$install_log")" = "active" ] ||
        fail_install 13 "SWARM INATIVO" "O Docker Swarm precisa estar ativo."
    docker network inspect externa >/dev/null 2>>"$install_log" || fail_install 14 "REDE EXTERNA AUSENTE" "A rede externa não foi encontrada."
    docker network inspect interna >/dev/null 2>>"$install_log" || fail_install 15 "REDE INTERNA AUSENTE" "A rede interna não foi encontrada."
    if [ "$INSTALL_TYPE" = "CLOUDFLARE_TUNNEL" ] || { [ "$INSTALL_TYPE" = "TRADICIONAL" ] && [ "$criar_dns" = "0" ]; }; then
        [ -n "$CLOUDFLARE_API_TOKEN" ] && [ -n "$CLOUDFLARE_ZONE_ID" ] ||
            fail_install 16 "CREDENCIAIS CLOUDFLARE INVÁLIDAS" "Token ou Zone ID não encontrado nas credenciais."
    fi
    if [ "$INSTALL_TYPE" = "CLOUDFLARE_TUNNEL" ]; then
        [ -n "$CLOUDFLARE_ACCOUNT_ID" ] && [ -n "$TUNNEL_ID" ] ||
            fail_install 17 "DADOS DO TUNNEL INVÁLIDOS" "Account ID ou Tunnel ID não encontrado."
    fi
    for stack_name in "$postgres_stack" "$meili_stack" "$app_stack"; do
        docker stack ls --format '{{.Name}}' | grep -Fxq "$stack_name" &&
            fail_install 18 "COLISÃO DE STACK" "A stack exclusiva $stack_name já existe."
    done
    for secret_name in "$postgres_secret" "$meili_secret" "$nextauth_secret"; do
        docker secret inspect "$secret_name" >/dev/null 2>&1 &&
            fail_install 19 "COLISÃO DE SEGREDO" "O Docker Secret exclusivo $secret_name já existe."
    done

    echo -e "XXX\n12\nBAIXANDO E CONFERINDO IMAGENS OFICIAIS...\nXXX"
    for image in "$POSTGRES_IMAGE" "$MEILI_IMAGE" "$LINKWARDEN_IMAGE"; do
        docker pull "$image" >>"$install_log" 2>&1 ||
            fail_install 20 "ERRO AO BAIXAR IMAGEM" "Falha ao baixar uma imagem oficial fixada por digest."
        docker image inspect "$image" >>"$install_log" 2>&1 ||
            fail_install 21 "IMAGEM NÃO CONFIRMADA" "Uma imagem baixada não pôde ser inspecionada."
    done

    echo -e "XXX\n22\nCRIANDO DIRETÓRIOS E DOCKER SECRETS...\nXXX"
    mkdir -p "$postgres_dir" "$meili_dir" "$app_data_dir" "$app_tmp_dir" >>"$install_log" 2>&1 ||
        fail_install 22 "ERRO AO CRIAR DADOS" "Não foi possível criar $base_dir."
    chmod 700 "$base_dir" "$postgres_dir" "$meili_dir" "$app_data_dir" "$app_tmp_dir"
    chown 1000:1000 "$meili_dir" >>"$install_log" 2>&1 ||
        fail_install 23 "ERRO DE PERMISSÃO" "Não foi possível preparar o diretório do Meilisearch."
    postgres_password=$(openssl rand -hex 32)
    meili_master_key=$(openssl rand -hex 32)
    nextauth_value=$(openssl rand -base64 48 | tr -d '\n')
    [ "${#postgres_password}" -eq 64 ] && [ "${#meili_master_key}" -eq 64 ] && [ -n "$nextauth_value" ] ||
        fail_install 24 "ERRO AO GERAR SEGREDOS" "Não foi possível gerar credenciais criptograficamente seguras."
    printf '%s' "$postgres_password" | docker secret create "$postgres_secret" - >>"$install_log" 2>&1 ||
        fail_install 25 "ERRO NO SEGREDO POSTGRESQL" "Não foi possível criar o segredo do PostgreSQL."
    created_secrets+=("$postgres_secret")
    printf '%s' "$meili_master_key" | docker secret create "$meili_secret" - >>"$install_log" 2>&1 ||
        fail_install 26 "ERRO NO SEGREDO MEILISEARCH" "Não foi possível criar o segredo do Meilisearch."
    created_secrets+=("$meili_secret")
    printf '%s' "$nextauth_value" | docker secret create "$nextauth_secret" - >>"$install_log" 2>&1 ||
        fail_install 27 "ERRO NO SEGREDO NEXTAUTH" "Não foi possível criar o segredo de sessão."
    created_secrets+=("$nextauth_secret")
    unset postgres_password meili_master_key nextauth_value

    echo -e "XXX\n32\nGERANDO AS TRÊS STACKS ISOLADAS...\nXXX"
    cat >"$postgres_yaml" <<EOPOSTGRES
version: "3.8"
services:
  postgres:
    image: $POSTGRES_IMAGE
    hostname: ${nome_app}_postgres
    environment:
      POSTGRES_DB: linkwarden
      POSTGRES_USER: linkwarden
      POSTGRES_PASSWORD_FILE: /run/secrets/postgres_password
    secrets:
      - source: postgres_password
        target: postgres_password
        mode: 0400
    volumes:
      - $postgres_dir:/var/lib/postgresql/data
    networks:
      - interna
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U linkwarden -d linkwarden"]
      interval: 10s
      timeout: 5s
      retries: 12
      start_period: 20s
    deploy:
      placement:
        constraints: [node.role == manager]
      restart_policy:
        condition: on-failure
      resources:
        limits:
          cpus: "0.50"
          memory: 512M
        reservations:
          memory: 128M
networks:
  interna:
    external: true
secrets:
  postgres_password:
    external: true
    name: $postgres_secret
EOPOSTGRES

    cat >"$meili_yaml" <<EOMEILI
version: "3.8"
services:
  meilisearch:
    image: $MEILI_IMAGE
    hostname: ${nome_app}_meilisearch
    user: "1000:1000"
    entrypoint: ["/bin/sh", "-ec"]
    command:
      - |
        export MEILI_MASTER_KEY="\$\$(cat /run/secrets/meili_master_key)"
        exec tini -- /bin/meilisearch
    environment:
      MEILI_ENV: production
      MEILI_NO_ANALYTICS: "true"
      MEILI_DB_PATH: /meili_data/data.ms
      MEILI_HTTP_ADDR: 0.0.0.0:7700
    secrets:
      - source: meili_master_key
        target: meili_master_key
        uid: "1000"
        gid: "1000"
        mode: 0400
    volumes:
      - $meili_dir:/meili_data
    networks:
      - interna
    healthcheck:
      test: ["CMD-SHELL", "wget -q -O - http://127.0.0.1:7700/health | grep -q '\"status\":\"available\"'"]
      interval: 10s
      timeout: 5s
      retries: 12
      start_period: 20s
    deploy:
      placement:
        constraints: [node.role == manager]
      restart_policy:
        condition: on-failure
      resources:
        limits:
          cpus: "0.50"
          memory: 512M
        reservations:
          memory: 64M
networks:
  interna:
    external: true
secrets:
  meili_master_key:
    external: true
    name: $meili_secret
EOMEILI

    cat >"$app_yaml" <<EOAPP
version: "3.8"
services:
  linkwarden:
    image: $LINKWARDEN_IMAGE
    hostname: $nome_app
    read_only: true
    cap_drop:
      - ALL
    entrypoint: ["/bin/sh", "-ec"]
    command:
      - |
        POSTGRES_PASSWORD="\$\$(cat /run/secrets/postgres_password)"
        export DATABASE_URL="postgresql://linkwarden:\$\${POSTGRES_PASSWORD}@$postgres_service:5432/linkwarden"
        export NEXTAUTH_SECRET="\$\$(cat /run/secrets/nextauth_secret)"
        export MEILI_MASTER_KEY="\$\$(cat /run/secrets/meili_master_key)"
        exec docker-entrypoint.sh sh -c 'yarn prisma:deploy && yarn concurrently:start'
    environment:
      NEXTAUTH_URL: https://$url_linkwarden/api/v1/auth
      BASE_URL: https://$url_linkwarden
      NEXT_PUBLIC_DISABLE_REGISTRATION: "false"
      NEXT_PUBLIC_CREDENTIALS_ENABLED: "true"
      NEXT_PUBLIC_USER_CONTENT_DOMAIN: https://$url_content
      MEILI_HOST: http://$meili_service:7700
      STORAGE_FOLDER: data
      ALLOW_PRIVATE_NETWORK_ACCESS: "false"
      ALLOW_INSECURE_TLS: "false"
      NEXT_PUBLIC_MOBILE_APP_REDIRECT_ENABLED: "true"
    secrets:
      - source: postgres_password
        target: postgres_password
        mode: 0400
      - source: meili_master_key
        target: meili_master_key
        mode: 0400
      - source: nextauth_secret
        target: nextauth_secret
        mode: 0400
    volumes:
      - $app_data_dir:/data/data
      - $app_tmp_dir:/tmp
      - type: tmpfs
        target: /dev/shm
        tmpfs:
          size: 268435456
          mode: 1777
    networks:
      - externa
      - interna
    healthcheck:
      test: ["CMD", "/usr/bin/curl", "--silent", "--fail", "http://127.0.0.1:3000/"]
      interval: 20s
      timeout: 8s
      retries: 15
      start_period: 120s
    deploy:
      placement:
        constraints: [node.role == manager]
      restart_policy:
        condition: on-failure
        delay: 8s
        max_attempts: 5
        window: 180s
      update_config:
        order: start-first
        failure_action: rollback
      resources:
        limits:
          cpus: "1.50"
          memory: 1536M
        reservations:
          memory: 384M
EOAPP

    if [ "$INSTALL_TYPE" = "TRADICIONAL" ]; then
        cat >>"$app_yaml" <<EOLABELS
      labels:
        - traefik.enable=true
        - traefik.docker.network=externa
        - traefik.http.routers.${nome_app}.rule=Host(\`$url_linkwarden\`) && !Path(\`/api/v1/preserved/view\`)
        - traefik.http.routers.${nome_app}.entrypoints=websecure
        - traefik.http.routers.${nome_app}.tls.certresolver=letsencryptresolver
        - traefik.http.routers.${nome_app}.service=${nome_app}
        - traefik.http.routers.${nome_app}_content.rule=Host(\`$url_content\`) && Path(\`/api/v1/preserved/view\`)
        - traefik.http.routers.${nome_app}_content.entrypoints=websecure
        - traefik.http.routers.${nome_app}_content.tls.certresolver=letsencryptresolver
        - traefik.http.routers.${nome_app}_content.service=${nome_app}
        - traefik.http.services.${nome_app}.loadbalancer.server.port=3000
EOLABELS
    fi
    cat >>"$app_yaml" <<EOAPPEND
networks:
  externa:
    external: true
  interna:
    external: true
secrets:
  postgres_password:
    external: true
    name: $postgres_secret
  meili_master_key:
    external: true
    name: $meili_secret
  nextauth_secret:
    external: true
    name: $nextauth_secret
EOAPPEND

    for yaml_file in "$postgres_yaml" "$meili_yaml" "$app_yaml"; do
        docker stack config -c "$yaml_file" >/dev/null 2>>"$install_log" ||
            fail_install 30 "YAML INVÁLIDO" "O arquivo $yaml_file não passou na validação do Docker."
    done

    echo -e "XXX\n45\nPUBLICANDO POSTGRESQL EXCLUSIVO...\nXXX"
    deploy_stack "$postgres_stack" "$postgres_yaml" ||
        fail_install 40 "ERRO NO POSTGRESQL" "Não foi possível criar a stack exclusiva do PostgreSQL."
    wait_service "$postgres_service" 60 healthy ||
        fail_install 41 "POSTGRESQL NÃO FICOU PRONTO" "O PostgreSQL não atingiu 1/1 réplica saudável."

    echo -e "XXX\n56\nPUBLICANDO MEILISEARCH EXCLUSIVO...\nXXX"
    deploy_stack "$meili_stack" "$meili_yaml" ||
        fail_install 42 "ERRO NO MEILISEARCH" "Não foi possível criar a stack exclusiva do Meilisearch."
    wait_service "$meili_service" 60 healthy ||
        fail_install 43 "MEILISEARCH NÃO FICOU PRONTO" "O Meilisearch não atingiu 1/1 réplica saudável."

    echo -e "XXX\n68\nPUBLICANDO LINKWARDEN E APLICANDO MIGRAÇÕES...\nXXX"
    deploy_stack "$app_stack" "$app_yaml" ||
        fail_install 44 "ERRO NO LINKWARDEN" "Não foi possível criar a stack principal do Linkwarden."
    wait_service "$app_service" 120 healthy ||
        fail_install 45 "LINKWARDEN NÃO FICOU PRONTO" "O Linkwarden não atingiu 1/1 réplica saudável."
    app_container="$WAIT_CONTAINER_ID"

    echo -e "XXX\n78\nCRIANDO ADMINISTRADOR E FECHANDO CADASTROS...\nXXX"
    admin_payload=$(printf '%s\n%s\n%s' "$admin_name" "$admin_username" "$admin_password" |
        jq -Rs 'split("\n") | {name:.[0],username:.[1],password:.[2],acceptPromotionalEmails:false}') ||
        fail_install 50 "ERRO AO PREPARAR ADMINISTRADOR" "Não foi possível preparar o cadastro do administrador."
    admin_result=$(printf '%s' "$admin_payload" | docker exec -i "$app_container" \
        curl -sS -o /tmp/setupmno-admin-response.json -w '%{http_code}' \
        -H 'Content-Type: application/json' --data-binary @- http://127.0.0.1:3000/api/v1/users 2>>"$install_log")
    unset admin_payload admin_password
    [ "$admin_result" = "201" ] ||
        fail_install 51 "ADMINISTRADOR NÃO CRIADO" "A API interna recusou a criação do primeiro administrador (HTTP ${admin_result:-indisponível})."
    sed -i 's/NEXT_PUBLIC_DISABLE_REGISTRATION: "false"/NEXT_PUBLIC_DISABLE_REGISTRATION: "true"/' "$app_yaml"
    docker stack config -c "$app_yaml" >/dev/null 2>>"$install_log" ||
        fail_install 52 "YAML DE SEGURANÇA INVÁLIDO" "Não foi possível preparar o bloqueio de novos cadastros."
    if [ "$criar_portainer" = "0" ]; then
        app_portainer_id=""
        for pair in "${portainer_ids[@]}"; do
            [ "${pair%%:*}" = "$app_stack" ] && app_portainer_id=${pair#*:}
        done
        [ -n "$app_portainer_id" ] && portainer_login ||
            fail_install 53 "PORTAINER INDISPONÍVEL" "Não foi possível autenticar para fechar novos cadastros."
        update_payload="$work_dir/portainer-update-linkwarden.json"
        jq -n --rawfile stackFileContent "$app_yaml" \
            '{env:[],prune:true,pullImage:false,stackFileContent:$stackFileContent}' >"$update_payload"
        update_http=$(curl -sk -o "$work_dir/portainer-update-response.json" -w '%{http_code}' -X PUT \
            "https://$PORTAINER_URL/api/stacks/$app_portainer_id?endpointId=$portainer_endpoint_id" \
            -H "Authorization: Bearer $portainer_token" -H 'Content-Type: application/json' \
            --data-binary @"$update_payload" 2>>"$install_log")
        [[ "$update_http" =~ ^2[0-9][0-9]$ ]] ||
            fail_install 54 "CADASTRO AINDA ABERTO" "O Portainer recusou a atualização que fecha novos cadastros."
    else
        docker stack deploy --prune --resolve-image always -c "$app_yaml" "$app_stack" >>"$install_log" 2>&1 ||
            fail_install 55 "CADASTRO AINDA ABERTO" "O Docker recusou a atualização que fecha novos cadastros."
    fi
    wait_service "$app_service" 120 healthy "$app_container" ||
        fail_install 56 "ATUALIZAÇÃO NÃO CONVERGIU" "O Linkwarden não voltou saudável após fechar novos cadastros."
    app_container="$WAIT_CONTAINER_ID"
    wait_secure_config "$app_container" "https://$url_content" 30 ||
        fail_install 57 "SEGURANÇA NÃO CONFIRMADA" "A API não confirmou cadastros fechados e domínio de conteúdo isolado."

    upsert_dns() {
        local label="$1" host="$2" content="$3" proxied="$4" lookup old_file response payload record_id record_type method url
        lookup="$work_dir/${label}-dns-lookup.json"
        old_file="$work_dir/${label}-dns-old.json"
        response="$work_dir/${label}-dns-response.json"
        payload="$work_dir/${label}-dns-payload.json"
        curl -sS --get "https://api.cloudflare.com/client/v4/zones/$CLOUDFLARE_ZONE_ID/dns_records" \
            -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" --data-urlencode "name=$host" \
            >"$lookup" 2>>"$install_log" || return 1
        record_id=$(jq -r '.result[0].id // empty' "$lookup")
        record_type=$(jq -r '.result[0].type // empty' "$lookup")
        [ -z "$record_id" ] || [ "$record_type" = "CNAME" ] || return 2
        jq -nc --arg name "$host" --arg content "$content" --argjson proxied "$proxied" \
            '{type:"CNAME",name:$name,content:$content,ttl:1,proxied:$proxied}' >"$payload"
        if [ -n "$record_id" ]; then
            jq '.result[0]' "$lookup" >"$old_file"
            method="PUT"
            url="https://api.cloudflare.com/client/v4/zones/$CLOUDFLARE_ZONE_ID/dns_records/$record_id"
        else
            method="POST"
            url="https://api.cloudflare.com/client/v4/zones/$CLOUDFLARE_ZONE_ID/dns_records"
        fi
        curl -sS -X "$method" "$url" -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
            -H "Content-Type: application/json" --data-binary @"$payload" >"$response" 2>>"$install_log" || return 1
        [ "$(jq -r '.success // false' "$response")" = "true" ] || return 1
        record_id=$(jq -r '.result.id // empty' "$response")
        printf '%s' "$record_id" >"$work_dir/${label}-dns-id"
        [ -s "$old_file" ] || : >"$work_dir/${label}-dns-created"
    }

    if [ "$INSTALL_TYPE" = "CLOUDFLARE_TUNNEL" ] || { [ "$INSTALL_TYPE" = "TRADICIONAL" ] && [ "$criar_dns" = "0" ]; }; then
        echo -e "XXX\n88\nCONFIGURANDO OS DOIS DOMÍNIOS...\nXXX"
        if [ "$INSTALL_TYPE" = "CLOUDFLARE_TUNNEL" ]; then
            dns_content="${TUNNEL_ID}.cfargotunnel.com"
            dns_proxied=true
        else
            dominio_principal="${SETUPMNO_SELECTED_ROOT_DOMAIN:-${SETUPMNO_DOMAIN_ROOT:-${CLOUDFLARE_ZONE_NAME:-}}}"
            [ -n "$nome_servidor" ] || nome_servidor=$(hostname -I | awk '{print $1}')
            dns_content="${nome_servidor}.${dominio_principal}"
            dns_proxied=false
        fi
        upsert_dns app "$url_linkwarden" "$dns_content" "$dns_proxied" ||
            fail_install 60 "ERRO NO DNS PRINCIPAL" "Não foi possível configurar o CNAME de $url_linkwarden."
        dns_app_changed="true"
        upsert_dns content "$url_content" "$dns_content" "$dns_proxied" ||
            fail_install 61 "ERRO NO DNS DE ARQUIVOS" "Não foi possível configurar o CNAME de $url_content."
        dns_content_changed="true"
    fi

    if [ "$INSTALL_TYPE" = "CLOUDFLARE_TUNNEL" ]; then
        echo -e "XXX\n94\nCRIANDO ROTAS ISOLADAS NO CLOUDFLARE TUNNEL...\nXXX"
        tunnel_original="$work_dir/tunnel-original.json"
        tunnel_payload="$work_dir/tunnel-payload.json"
        tunnel_response="$work_dir/tunnel-response.json"
        curl -sS -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
            "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/cfd_tunnel/$TUNNEL_ID/configurations" \
            >"$tunnel_original" 2>>"$install_log" ||
            fail_install 62 "ERRO AO CONSULTAR TUNNEL" "Não foi possível obter a configuração atual do Cloudflare Tunnel."
        [ "$(jq -r '.success // false' "$tunnel_original")" = "true" ] ||
            fail_install 63 "TUNNEL RECUSOU CONSULTA" "A Cloudflare recusou a leitura da configuração do Tunnel."
        jq --arg app "$url_linkwarden" --arg content "$url_content" --arg service "http://$app_service:3000" '
            (.result.config // {}) as $cfg
            | ($cfg.ingress // [])
            | map(select(.service != "http_status:404" and .hostname != $app and .hostname != $content))
            + [
                {hostname:$content,path:"^/api/v1/preserved/view$",service:$service,originRequest:{httpHostHeader:$content}},
                {hostname:$content,service:"http_status:404"},
                {hostname:$app,path:"^/api/v1/preserved/view$",service:"http_status:404"},
                {hostname:$app,service:$service,originRequest:{httpHostHeader:$app}},
                {service:"http_status:404"}
              ]
            | {config:($cfg + {ingress:.})}
        ' "$tunnel_original" >"$tunnel_payload" ||
            fail_install 64 "ERRO AO PREPARAR TUNNEL" "Não foi possível preparar as rotas isoladas."
        curl -sS -X PUT \
            "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/cfd_tunnel/$TUNNEL_ID/configurations" \
            -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" -H "Content-Type: application/json" \
            --data-binary @"$tunnel_payload" >"$tunnel_response" 2>>"$install_log" ||
            fail_install 65 "ERRO AO ATUALIZAR TUNNEL" "Falha de comunicação ao atualizar as rotas."
        [ "$(jq -r '.success // false' "$tunnel_response")" = "true" ] ||
            fail_install 66 "TUNNEL RECUSOU ROTAS" "A Cloudflare recusou as rotas isoladas do Linkwarden."
        route_updated="true"
    fi

    mkdir -p /root/dados_linkwarden
    chmod 700 /root/dados_linkwarden
    cat >"/root/dados_linkwarden/${nome_app}" <<EODATA
Linkwarden PRO
Painel: https://$url_linkwarden
Arquivos preservados: https://$url_content
Administrador: $admin_username
Stack principal: $app_stack
Stack PostgreSQL: $postgres_stack
Stack Meilisearch: $meili_stack
Dados: $base_dir
EODATA
    chmod 600 "/root/dados_linkwarden/${nome_app}"

    # A partir daqui os recursos são a instalação concluída, não rollback temporário.
    created_stacks=()
    created_secrets=()
    portainer_ids=()
    route_updated="false"
    dns_app_changed="false"
    dns_content_changed="false"
    echo -e "XXX\n100\nLINKWARDEN INSTALADO COM SUCESSO\nXXX"
} | whiptail --title "LINKWARDEN PRO" --gauge "Preparando o combo seguro..." 8 86 0
install_status=${PIPESTATUS[0]}

if [ "$install_status" -ne 0 ]; then
    error_detail=$(cat "$error_file" 2>/dev/null)
    [ -n "$error_detail" ] || error_detail=$(tail -n 20 "$install_log" 2>/dev/null)
    whiptail --title "ERRO NA INSTALAÇÃO DO LINKWARDEN" --msgbox \
        "A instalação foi interrompida sem declarar falso sucesso.\n\n$error_detail\n\nLog completo: $install_log" \
        24 94
    exit "$install_status"
fi

manual_dns_note=""
if [ "$INSTALL_TYPE" = "TRADICIONAL" ] && [ "$criar_dns" = "1" ]; then
    manual_dns_note="\n\nDNS manual: aponte os dois domínios para o servidor antes de acessar."
fi

whiptail --title "LINKWARDEN PRO" --msgbox \
    "Linkwarden instalado com sucesso.\n\nPainel: https://$url_linkwarden\nUsuário: $admin_username\nArquivos preservados isolados em: https://$url_content\n\nNovos cadastros já estão bloqueados. Para adicionar pessoas, entre como administrador e use o gerenciamento de usuários.$manual_dns_note" \
    22 92

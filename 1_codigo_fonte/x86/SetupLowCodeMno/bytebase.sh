#!/usr/bin/bash
# BYTEBASE — plataforma de DevOps e governança para bancos de dados.
set -o pipefail
umask 077

BYTEBASE_IMAGE="bytebase/bytebase:3.21.0@sha256:ce51be31aba8213ed583479b46f38a6dc295fd1cd009aabe9bbe18de3daa7588"
CURL_IMAGE="curlimages/curl:8.12.1@sha256:94e9e444bcba979c2ea12e27ae39bee4cd10bc7041a472c4727a558e213744e6"

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
    whiptail --title "BYTEBASE" --msgbox "$1" 18 88 1>&2
}

ask_required() {
    local prompt="$1" value status
    while true; do
        value=$(whiptail --title "BYTEBASE" --inputbox "$prompt" 14 88 3>&1 1>&2 2>&3)
        status=$?
        [ "$status" -ne 0 ] && return 130
        if [ -n "$value" ]; then
            printf '%s' "$value"
            return 0
        fi
        msg "Este campo é obrigatório."
    done
}

valid_domain() {
    [[ "$1" =~ ^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$ ]] && [[ "$1" == *.* ]]
}

whiptail --title "BYTEBASE" --yesno \
    "Instalar Bytebase?\n\nPlataforma para gerenciar mudanças de esquema, consultas SQL, acesso e governança de bancos de dados.\n\nA conta administrativa será criada no primeiro acesso pelo navegador." \
    18 90 || exit 0

while true; do
    if ! url_bytebase=$(ask_required "1/2 — Domínio do Bytebase (ex.: bytebase.seudominio.com):"); then exit 0; fi
    url_bytebase=$(printf '%s' "$url_bytebase" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')
    valid_domain "$url_bytebase" && break
    msg "Informe somente um domínio válido, sem http://, https://, porta, barras ou caminhos."
done

while true; do
    if ! criar_portainer=$(ask_required "2/2 — Criar Stack no Portainer?\n\n0 = editável no Portainer\n1 = direta no Docker"); then exit 0; fi
    [[ "$criar_portainer" =~ ^[01]$ ]] && break
    msg "Digite somente 0 ou 1."
done

nome_principal="bytebase"
sufixo_app=$(date +%s%N | md5sum | head -c7)
nome_app="${nome_principal}${sufixo_app}"
service_name="${nome_app}_bytebase"
health_service="${nome_app}_healthcheck"
data_dir="/root/${nome_app}_data"
app_yaml="/root/${nome_app}.yaml"

dns_mode="Cloudflare Tunnel"
if [ "$INSTALL_TYPE" = "TRADICIONAL" ]; then
    if [ "$criar_dns" = "0" ]; then dns_mode="Tradicional com DNS automático"; else dns_mode="Tradicional com DNS manual"; fi
fi

whiptail --title "CONFIRMAR INSTALAÇÃO" --yesno \
    "Bytebase v3.21.0\n\nPainel: https://$url_bytebase\nAcesso: $dns_mode\nGestão: $([ "$criar_portainer" = "0" ] && echo "Stack editável no Portainer" || echo "Stack direta no Docker")\nArquiteturas: X86 e ARM\nRAM máxima: 2 GB\nPorta 8080: somente interna\nMetadados: PostgreSQL compartilhado do Setup MNO\nPersistência auxiliar: $data_dir" \
    24 92 || exit 0

install_log="/tmp/${nome_app}-install.log"
error_file="/tmp/${nome_app}-error.log"
: >"$install_log"
: >"$error_file"

{
    work_dir=$(mktemp -d)
    stack_created="false"
    database_created="false"
    portainer_stack_id=""
    portainer_endpoint_id=""
    portainer_token=""
    route_updated="false"
    dns_changed="false"
    postgres_container=""

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

    restore_dns() {
        local record_id payload
        [ "$dns_changed" = "true" ] || return 0
        record_id=$(cat "$work_dir/dns-id" 2>/dev/null)
        if [ -f "$work_dir/dns-created" ] && [ -n "$record_id" ]; then
            curl -sS -X DELETE \
                "https://api.cloudflare.com/client/v4/zones/$CLOUDFLARE_ZONE_ID/dns_records/$record_id" \
                -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" >>"$install_log" 2>&1 || true
        elif [ -s "$work_dir/dns-old.json" ] && [ -n "$record_id" ]; then
            payload="$work_dir/dns-restore.json"
            jq '{type,name,content,ttl,proxied}' "$work_dir/dns-old.json" >"$payload" 2>/dev/null || return 0
            curl -sS -X PUT \
                "https://api.cloudflare.com/client/v4/zones/$CLOUDFLARE_ZONE_ID/dns_records/$record_id" \
                -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" -H "Content-Type: application/json" \
                --data-binary @"$payload" >>"$install_log" 2>&1 || true
        fi
    }

    remove_health_service() {
        docker service inspect "$health_service" >/dev/null 2>&1 || return 0
        docker service rm "$health_service" >>"$install_log" 2>&1 || true
        for _ in $(seq 1 30); do
            docker service inspect "$health_service" >/dev/null 2>&1 || return 0
            sleep 1
        done
        return 1
    }

    rollback_deployment() {
        echo "Executando rollback exclusivo do Bytebase..." >>"$install_log"
        remove_health_service || true
        if [ "$route_updated" = "true" ] && [ -s "$work_dir/tunnel-original.json" ]; then
            jq '{config:.result.config}' "$work_dir/tunnel-original.json" >"$work_dir/tunnel-restore.json" 2>/dev/null || true
            curl -sS -X PUT \
                "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/cfd_tunnel/$TUNNEL_ID/configurations" \
                -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" -H "Content-Type: application/json" \
                --data-binary @"$work_dir/tunnel-restore.json" >>"$install_log" 2>&1 || true
        fi
        restore_dns
        if [ "$stack_created" = "true" ]; then
            if [ "$criar_portainer" = "0" ] && [ -n "$portainer_stack_id" ]; then
                portainer_login || true
                [ -n "$portainer_token" ] && curl -sk -X DELETE \
                    "https://$PORTAINER_URL/api/stacks/$portainer_stack_id?endpointId=$portainer_endpoint_id" \
                    -H "Authorization: Bearer $portainer_token" >>"$install_log" 2>&1 || true
            fi
            docker stack rm "$nome_app" >>"$install_log" 2>&1 || true
            for _ in $(seq 1 30); do
                docker service inspect "$service_name" >/dev/null 2>&1 || break
                sleep 1
            done
        fi
        if [ "$database_created" = "true" ] && [ -n "$postgres_container" ]; then
            docker exec "$postgres_container" psql -U postgres -d postgres -v ON_ERROR_STOP=1 \
                -c "DROP DATABASE IF EXISTS \"$nome_app\";" >>"$install_log" 2>&1 || true
        fi
        if [[ "$data_dir" == /root/bytebase*_data ]]; then rm -rf "$data_dir"; fi
        if [[ "$app_yaml" == /root/bytebase*.yaml ]]; then rm -f -- "$app_yaml"; fi
    }

    fail_install() {
        local code="$1" progress="$2" message="$3"
        rollback_deployment
        printf '%s\n' "$message" >"$error_file"
        echo -e "XXX\n100\n$progress\nXXX"
        exit "$code"
    }

    write_stack_yaml() {
        local target="$1"
        cat >"$target" <<EOYAML

version: "3.7"
services:
  bytebase:
    image: $BYTEBASE_IMAGE
    hostname: $nome_app
    command:
      - --port
      - "8080"
      - --data
      - /var/opt/bytebase
      - --external-url
      - https://$url_bytebase
    environment:
      - PG_URL=postgresql://postgres:${postgres_password_uri}@postgres:5432/${nome_app}?sslmode=disable
    cap_drop:
      - ALL
    read_only: true
    tmpfs:
      - /tmp:rw,noexec,nosuid,nodev,mode=1777,size=64m
    volumes:
      - $data_dir:/var/opt/bytebase
    networks:
      - externa
      - interna
    healthcheck:
      test:
        - CMD-SHELL
        - curl -fsS http://127.0.0.1:8080/healthz || exit 1
      interval: 30s
      timeout: 5s
      retries: 5
      start_period: 60s
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
          cpus: "1.00"
          memory: 2048M
        reservations:
          cpus: "0.10"
          memory: 256M
EOYAML
        if [ "$INSTALL_TYPE" = "TRADICIONAL" ]; then
            cat >>"$target" <<EOYAML

      labels:
        - traefik.enable=true
        - traefik.docker.network=externa
        - traefik.http.routers.$nome_app.rule=Host(\`$url_bytebase\`)
        - traefik.http.routers.$nome_app.entrypoints=websecure
        - traefik.http.routers.$nome_app.priority=1
        - traefik.http.routers.$nome_app.tls.certresolver=letsencryptresolver
        - traefik.http.routers.$nome_app.tls=true
        - traefik.http.routers.$nome_app.service=$nome_app
        - traefik.http.services.$nome_app.loadbalancer.server.port=8080
EOYAML
        fi
        cat >>"$target" <<EOYAML

networks:
  externa:
    external: true
  interna:
    external: true
EOYAML
        chmod 600 "$target"
    }

    wait_replica() {
        local attempts="$1" replicas
        for _ in $(seq 1 "$attempts"); do
            replicas=$(docker service ls --filter "name=$service_name" --format '{{.Replicas}}' 2>>"$install_log" | head -n1)
            [ "$replicas" = "1/1" ] && return 0
            sleep 2
        done
        return 1
    }

    check_health() {
        local state result=1
        remove_health_service || return 1
        docker service create --detach \
            --name "$health_service" \
            --network interna \
            --constraint 'node.role==manager' \
            --restart-condition none \
            --read-only \
            --cap-drop ALL \
            --limit-cpu 0.25 \
            --limit-memory 64M \
            "$CURL_IMAGE" \
            --retry 45 --retry-all-errors --retry-delay 2 --connect-timeout 5 --max-time 110 \
            -fsS "http://$service_name:8080/healthz" >>"$install_log" 2>&1 || return 1

        for _ in $(seq 1 120); do
            state=$(docker service ps "$health_service" --format '{{.CurrentState}}' 2>>"$install_log" | head -n1)
            case "$state" in
                Complete*) result=0; break ;;
                Failed*|Rejected*|Shutdown*)
                    docker service ps --no-trunc "$health_service" >>"$install_log" 2>&1 || true
                    break
                    ;;
            esac
            sleep 2
        done
        [ "$result" -eq 0 ] || docker service logs --raw "$health_service" >>"$install_log" 2>&1 || true
        remove_health_service || result=1
        return "$result"
    }

    echo -e "XXX\n5\nVALIDANDO AMBIENTE, SWARM E REDES...\nXXX"
    for required_command in docker curl jq md5sum grep awk; do
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

    if [ "$INSTALL_TYPE" = "CLOUDFLARE_TUNNEL" ] || { [ "$INSTALL_TYPE" = "TRADICIONAL" ] && [ "$criar_dns" = "0" ]; }; then
        [ -n "$CLOUDFLARE_API_TOKEN" ] && [ -n "$CLOUDFLARE_ZONE_ID" ] ||
            fail_install 16 "CREDENCIAIS CLOUDFLARE INVÁLIDAS" "Token ou Zone ID do Cloudflare não encontrado nas credenciais."
    fi
    if [ "$INSTALL_TYPE" = "CLOUDFLARE_TUNNEL" ]; then
        [ -n "$CLOUDFLARE_ACCOUNT_ID" ] && [ -n "$TUNNEL_ID" ] ||
            fail_install 17 "DADOS DO TUNNEL INVÁLIDOS" "Account ID ou Tunnel ID não encontrado nas credenciais."
    fi

    echo -e "XXX\n16\nVALIDANDO POSTGRESQL COMPARTILHADO...\nXXX"
    [ -f /root/postgres.yaml ] ||
        fail_install 18 "POSTGRESQL NÃO ENCONTRADO" "O arquivo /root/postgres.yaml do PostgreSQL compartilhado não foi encontrado."
    postgres_password=$(grep -oP '(?<=POSTGRES_PASSWORD=).+' /root/postgres.yaml | head -n1)
    [ -n "$postgres_password" ] ||
        fail_install 19 "SENHA DO POSTGRESQL AUSENTE" "Não foi possível extrair a senha do PostgreSQL compartilhado."
    postgres_password_uri=$(printf '%s' "$postgres_password" | jq -sRr @uri)
    for _ in $(seq 1 90); do
        postgres_container=$(docker ps --filter 'label=com.docker.swarm.service.name=postgres_postgres' --format '{{.ID}}' | head -n1)
        if [ -n "$postgres_container" ] && docker exec "$postgres_container" pg_isready -U postgres -d postgres >>"$install_log" 2>&1; then
            break
        fi
        sleep 2
    done
    [ -n "$postgres_container" ] && docker exec "$postgres_container" pg_isready -U postgres -d postgres >>"$install_log" 2>&1 ||
        fail_install 20 "POSTGRESQL INDISPONÍVEL" "O PostgreSQL compartilhado não ficou pronto dentro do tempo esperado."

    echo -e "XXX\n24\nBAIXANDO IMAGENS OFICIAIS MULTI-ARQUITETURA...\nXXX"
    for image_ref in "$BYTEBASE_IMAGE" "$CURL_IMAGE"; do
        docker pull "$image_ref" >>"$install_log" 2>&1 ||
            fail_install 21 "ERRO AO BAIXAR IMAGEM" "Falha ao baixar a imagem oficial: $image_ref"
        docker image inspect --format 'Imagem={{.Id}} Arquitetura={{.Architecture}} Tamanho={{.Size}}' \
            "$image_ref" >>"$install_log" 2>&1 ||
            fail_install 22 "IMAGEM NÃO CONFIRMADA" "A imagem foi baixada, mas não pôde ser inspecionada: $image_ref"
    done

    echo -e "XXX\n34\nCRIANDO BANCO DE METADADOS ISOLADO...\nXXX"
    database_exists=$(docker exec "$postgres_container" psql -U postgres -d postgres -At \
        -c "SELECT 1 FROM pg_database WHERE datname='$nome_app';" 2>>"$install_log") ||
        fail_install 23 "ERRO AO CONSULTAR BANCO" "Não foi possível consultar os bancos existentes no PostgreSQL compartilhado."
    [ -z "$database_exists" ] ||
        fail_install 24 "BANCO JÁ EXISTENTE" "O banco $nome_app já existe; nenhuma alteração foi realizada."
    docker exec "$postgres_container" psql -U postgres -d postgres -v ON_ERROR_STOP=1 \
        -c "CREATE DATABASE \"$nome_app\" ENCODING 'UTF8';" >>"$install_log" 2>&1 ||
        fail_install 25 "ERRO AO CRIAR BANCO" "Não foi possível criar o banco de metadados do Bytebase."
    database_created="true"

    echo -e "XXX\n42\nCRIANDO ARMAZENAMENTO PERSISTENTE...\nXXX"
    mkdir -p "$data_dir" >>"$install_log" 2>&1 ||
        fail_install 26 "ERRO AO CRIAR DIRETÓRIO" "Não foi possível criar o diretório persistente do Bytebase."
    chmod 700 "$data_dir" ||
        fail_install 27 "ERRO DE PERMISSÃO" "Não foi possível restringir o diretório persistente do Bytebase."

    echo -e "XXX\n50\nGERANDO E VALIDANDO A STACK...\nXXX"
    write_stack_yaml "$app_yaml" ||
        fail_install 28 "ERRO AO GERAR STACK" "Não foi possível preparar a stack do Bytebase."
    docker stack config -c "$app_yaml" >"$work_dir/validated.yaml" 2>>"$install_log" ||
        fail_install 29 "YAML INVÁLIDO" "O arquivo $app_yaml não passou na validação do Docker."

    echo -e "XXX\n60\nPUBLICANDO A STACK DO BYTEBASE...\nXXX"
    if [ "$criar_portainer" = "0" ]; then
        portainer_login ||
            fail_install 30 "PORTAINER INDISPONÍVEL" "Não foi possível autenticar ou localizar o Docker Swarm no Portainer."
        portainer_response="$work_dir/portainer-create.json"
        http_code=$(curl -sk -o "$portainer_response" -w '%{http_code}' -X POST \
            -H "Authorization: Bearer $portainer_token" -F "Name=$nome_app" -F "file=@$app_yaml" \
            -F "SwarmID=$PORTAINER_SWARM_ID" -F "endpointId=$portainer_endpoint_id" \
            "https://$PORTAINER_URL/api/stacks/create/swarm/file" 2>>"$install_log")
        [[ "$http_code" =~ ^2[0-9][0-9]$ ]] ||
            fail_install 31 "PORTAINER RECUSOU A STACK" "O Portainer recusou a stack Bytebase (HTTP ${http_code:-indisponível})."
        stack_created="true"
        portainer_stack_id=$(jq -r '.Id // .id // empty' "$portainer_response")
        [ -n "$portainer_stack_id" ] ||
            fail_install 32 "STACK SEM IDENTIFICADOR" "O Portainer criou a stack sem retornar um identificador válido."
    else
        docker stack deploy --prune --resolve-image always -c "$app_yaml" "$nome_app" >>"$install_log" 2>&1 ||
            fail_install 33 "DOCKER RECUSOU A STACK" "O Docker recusou a stack Bytebase."
        stack_created="true"
    fi

    echo -e "XXX\n72\nAGUARDANDO O BYTEBASE E VALIDANDO /HEALTHZ...\nXXX"
    wait_replica 90 || {
        docker service ps "$service_name" --no-trunc >>"$install_log" 2>&1 || true
        docker service logs --raw --tail 120 "$service_name" >>"$install_log" 2>&1 || true
        fail_install 40 "BYTEBASE NÃO INICIOU" "O serviço $service_name não atingiu 1/1 réplica."
    }
    check_health || {
        docker service logs --raw --tail 120 "$service_name" >>"$install_log" 2>&1 || true
        fail_install 41 "API NÃO RESPONDEU" "O endpoint interno /healthz do Bytebase não confirmou o estado saudável."
    }
    metadata_tables=$(docker exec "$postgres_container" psql -U postgres -d "$nome_app" -At \
        -c "SELECT count(*) FROM pg_catalog.pg_tables WHERE schemaname='public';" 2>>"$install_log") ||
        fail_install 42 "METADADOS NÃO CONFIRMADOS" "Não foi possível validar o schema persistente do Bytebase."
    [[ "$metadata_tables" =~ ^[0-9]+$ ]] && [ "$metadata_tables" -gt 0 ] ||
        fail_install 43 "SCHEMA NÃO CRIADO" "O Bytebase iniciou, mas não confirmou tabelas no PostgreSQL compartilhado."

    if [ "$INSTALL_TYPE" = "CLOUDFLARE_TUNNEL" ] || { [ "$INSTALL_TYPE" = "TRADICIONAL" ] && [ "$criar_dns" = "0" ]; }; then
        echo -e "XXX\n84\nCONFIGURANDO DNS DE FORMA REVERSÍVEL...\nXXX"
        if [ "$INSTALL_TYPE" = "CLOUDFLARE_TUNNEL" ]; then
            dns_content="${TUNNEL_ID}.cfargotunnel.com"
            dns_proxied=true
        else
            dominio_principal="${SETUPMNO_SELECTED_ROOT_DOMAIN:-${SETUPMNO_DOMAIN_ROOT:-${CLOUDFLARE_ZONE_NAME:-}}}"
            [ -n "$nome_servidor" ] || nome_servidor=$(hostname -I | awk '{print $1}')
            dns_content="${nome_servidor}.${dominio_principal}"
            dns_proxied=false
        fi
        curl -sS --get "https://api.cloudflare.com/client/v4/zones/$CLOUDFLARE_ZONE_ID/dns_records" \
            -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" --data-urlencode "name=$url_bytebase" \
            >"$work_dir/dns-lookup.json" 2>>"$install_log" ||
            fail_install 50 "ERRO AO CONSULTAR DNS" "Não foi possível consultar o DNS $url_bytebase."
        [ "$(jq -r '.success // false' "$work_dir/dns-lookup.json")" = "true" ] ||
            fail_install 51 "CLOUDFLARE RECUSOU CONSULTA" "A Cloudflare recusou a consulta do DNS do Bytebase."
        dns_record_id=$(jq -r '.result[0].id // empty' "$work_dir/dns-lookup.json")
        dns_record_type=$(jq -r '.result[0].type // empty' "$work_dir/dns-lookup.json")
        [ -z "$dns_record_id" ] || [ "$dns_record_type" = "CNAME" ] ||
            fail_install 52 "CONFLITO DE REGISTRO DNS" "Já existe um registro $dns_record_type para $url_bytebase; nada foi removido."
        jq -nc --arg name "$url_bytebase" --arg content "$dns_content" --argjson proxied "$dns_proxied" \
            '{type:"CNAME",name:$name,content:$content,ttl:1,proxied:$proxied}' >"$work_dir/dns-payload.json"
        if [ -n "$dns_record_id" ]; then
            jq '.result[0]' "$work_dir/dns-lookup.json" >"$work_dir/dns-old.json"
            dns_method="PUT"
            dns_url="https://api.cloudflare.com/client/v4/zones/$CLOUDFLARE_ZONE_ID/dns_records/$dns_record_id"
        else
            dns_method="POST"
            dns_url="https://api.cloudflare.com/client/v4/zones/$CLOUDFLARE_ZONE_ID/dns_records"
        fi
        curl -sS -X "$dns_method" "$dns_url" -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
            -H "Content-Type: application/json" --data-binary @"$work_dir/dns-payload.json" \
            >"$work_dir/dns-response.json" 2>>"$install_log" ||
            fail_install 53 "ERRO AO CONFIGURAR DNS" "Falha de comunicação ao configurar o CNAME do Bytebase."
        [ "$(jq -r '.success // false' "$work_dir/dns-response.json")" = "true" ] ||
            fail_install 54 "CLOUDFLARE RECUSOU O DNS" "A Cloudflare recusou o CNAME do Bytebase."
        dns_record_id=$(jq -r '.result.id // empty' "$work_dir/dns-response.json")
        printf '%s' "$dns_record_id" >"$work_dir/dns-id"
        [ -s "$work_dir/dns-old.json" ] || : >"$work_dir/dns-created"
        dns_changed="true"
    fi

    if [ "$INSTALL_TYPE" = "CLOUDFLARE_TUNNEL" ]; then
        echo -e "XXX\n93\nATUALIZANDO ROTA DO CLOUDFLARE TUNNEL...\nXXX"
        curl -sS -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
            "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/cfd_tunnel/$TUNNEL_ID/configurations" \
            >"$work_dir/tunnel-original.json" 2>>"$install_log" ||
            fail_install 60 "ERRO AO CONSULTAR TUNNEL" "Não foi possível obter a configuração atual do Cloudflare Tunnel."
        [ "$(jq -r '.success // false' "$work_dir/tunnel-original.json")" = "true" ] ||
            fail_install 61 "TUNNEL RECUSOU CONSULTA" "A Cloudflare recusou a leitura da configuração do Tunnel."
        jq --arg host "$url_bytebase" --arg service "http://$service_name:8080" '
            (.result.config // {}) as $cfg
            | ($cfg.ingress // [])
            | map(select(.service != "http_status:404" and .hostname != $host))
            + [{hostname:$host,service:$service,originRequest:{httpHostHeader:$host}},
               {service:"http_status:404"}]
            | {config:($cfg + {ingress:.})}
        ' "$work_dir/tunnel-original.json" >"$work_dir/tunnel-payload.json" ||
            fail_install 62 "ERRO AO PREPARAR ROTA" "Não foi possível preparar a rota do Bytebase."
        curl -sS -X PUT \
            "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/cfd_tunnel/$TUNNEL_ID/configurations" \
            -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" -H "Content-Type: application/json" \
            --data-binary @"$work_dir/tunnel-payload.json" >"$work_dir/tunnel-response.json" 2>>"$install_log" ||
            fail_install 63 "ERRO AO ATUALIZAR TUNNEL" "Falha de comunicação ao atualizar a rota do Bytebase."
        [ "$(jq -r '.success // false' "$work_dir/tunnel-response.json")" = "true" ] ||
            fail_install 64 "TUNNEL RECUSOU A ROTA" "A Cloudflare recusou a rota do Bytebase."
        route_updated="true"
    fi

    mkdir -p /root/dados_bytebase
    chmod 700 /root/dados_bytebase
    cat >"/root/dados_bytebase/${nome_app}" <<EODATA

Bytebase 3.21.0
Painel: https://$url_bytebase
Stack: $nome_app
Banco de metadados: $nome_app no PostgreSQL compartilhado
Dados auxiliares: $data_dir
Imagem: $BYTEBASE_IMAGE
Administrador: criar no primeiro acesso
EODATA
    chmod 600 "/root/dados_bytebase/${nome_app}"

    stack_created="false"
    database_created="false"
    route_updated="false"
    dns_changed="false"
    echo -e "XXX\n100\nBYTEBASE INSTALADO COM SUCESSO\nXXX"
} | whiptail --title "BYTEBASE" --gauge "Preparando Bytebase..." 8 90 0
install_status=${PIPESTATUS[0]}

if [ "$install_status" -ne 0 ]; then
    error_detail=$(cat "$error_file" 2>/dev/null)
    [ -n "$error_detail" ] || error_detail=$(tail -n 20 "$install_log" 2>/dev/null)
    whiptail --title "ERRO NA INSTALAÇÃO DO BYTEBASE" --msgbox \
        "A instalação foi interrompida sem declarar falso sucesso.\n\n$error_detail\n\nLog completo: $install_log" \
        24 94
    exit "$install_status"
fi

manual_dns_note=""
if [ "$INSTALL_TYPE" = "TRADICIONAL" ] && [ "$criar_dns" = "1" ]; then
    manual_dns_note="\n\nDNS manual: aponte $url_bytebase para o servidor antes de acessar."
fi

whiptail --title "BYTEBASE" --msgbox \
    "Bytebase instalado com sucesso.\n\nAcesse: https://$url_bytebase\nNo primeiro acesso, crie a conta administrativa do workspace.\n\nStack: $nome_app\nBanco de metadados: $nome_app\nPersistência auxiliar: $data_dir\nPorta 8080: somente interna.$manual_dns_note" \
    24 94

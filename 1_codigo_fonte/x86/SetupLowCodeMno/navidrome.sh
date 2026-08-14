#!/usr/bin/bash
# NAVIDROME PRO — servidor pessoal de música compatível com Subsonic.
set -o pipefail
umask 077

NAVIDROME_IMAGE="deluan/navidrome:0.63.2@sha256:9012939114fbb1bb641b81cf96dec5ded15f0aafefe8d47a511d7cb919658e40"
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
    whiptail --title "NAVIDROME PRO" --msgbox "$1" 18 88 1>&2
}

ask_required() {
    local prompt="$1" value status
    while true; do
        value=$(whiptail --title "NAVIDROME PRO" --inputbox "$prompt" 14 88 3>&1 1>&2 2>&3)
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

whiptail --title "NAVIDROME PRO" --yesno \
    "Instalar Navidrome PRO?\n\nServidor pessoal de música leve, com interface web e compatibilidade com clientes Subsonic.\n\nA conta administrativa será criada com segurança no primeiro acesso pelo navegador." \
    18 90 || exit 0

while true; do
    if ! url_navidrome=$(ask_required "1/2 — Domínio do Navidrome (ex.: musica.seudominio.com):"); then exit 0; fi
    url_navidrome=$(printf '%s' "$url_navidrome" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')
    valid_domain "$url_navidrome" && break
    msg "Informe somente um domínio válido, sem http://, https://, porta, barras ou caminhos."
done

while true; do
    if ! criar_portainer=$(ask_required "2/2 — Criar Stack no Portainer?\n\n0 = editável no Portainer\n1 = direta no Docker"); then exit 0; fi
    [[ "$criar_portainer" =~ ^[01]$ ]] && break
    msg "Digite somente 0 ou 1."
done

nome_principal="navidrome"
sufixo_app=$(date +%s%N | md5sum | head -c7)
nome_app="${nome_principal}${sufixo_app}"
service_name="${nome_app}_navidrome"
health_service="${nome_app}_healthcheck"
data_dir="/root/${nome_app}_data"
music_dir="/root/${nome_app}_music"
app_yaml="/root/${nome_app}.yaml"

dns_mode="Cloudflare Tunnel"
if [ "$INSTALL_TYPE" = "TRADICIONAL" ]; then
    if [ "$criar_dns" = "0" ]; then dns_mode="Tradicional com DNS automático"; else dns_mode="Tradicional com DNS manual"; fi
fi

whiptail --title "CONFIRMAR INSTALAÇÃO" --yesno \
    "Navidrome PRO v0.63.2\n\nPainel: https://$url_navidrome\nAcesso: $dns_mode\nGestão: $([ "$criar_portainer" = "0" ] && echo "Stack editável no Portainer" || echo "Stack direta no Docker")\nArquiteturas: X86 e ARM\nRAM máxima: 512 MB\nPorta 4533: somente interna\nBanco: SQLite dedicado no volume de dados\nMúsicas: pasta persistente montada somente para leitura\nTelemetria anônima: desativada" \
    24 92 || exit 0

install_log="/tmp/${nome_app}-install.log"
error_file="/tmp/${nome_app}-error.log"
: >"$install_log"
: >"$error_file"

{
    work_dir=$(mktemp -d)
    stack_created="false"
    portainer_stack_id=""
    portainer_endpoint_id=""
    portainer_token=""
    route_updated="false"
    dns_changed="false"

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
        echo "Executando rollback exclusivo do Navidrome..." >>"$install_log"
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
        if [[ "$data_dir" == /root/navidrome*_data ]]; then rm -rf "$data_dir"; fi
        if [[ "$music_dir" == /root/navidrome*_music ]]; then rm -rf "$music_dir"; fi
        if [[ "$app_yaml" == /root/navidrome*.yaml ]]; then rm -f -- "$app_yaml"; fi
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
  navidrome:
    image: $NAVIDROME_IMAGE
    hostname: $nome_app
    user: "1000:1000"
    cap_drop:
      - ALL
    tmpfs:
      - /tmp:rw,noexec,nosuid,nodev,mode=1777,size=64m
    environment:
      - ND_ADDRESS=0.0.0.0
      - ND_PORT=4533
      - ND_DATAFOLDER=/data
      - ND_MUSICFOLDER=/music
      - ND_LOGLEVEL=info
      - ND_SESSIONTIMEOUT=24h
      - ND_ENABLEINSIGHTSCOLLECTOR=false
    volumes:
      - $data_dir:/data
      - $music_dir:/music:ro
    networks:
      - externa
      - interna
    healthcheck:
      test:
        - CMD-SHELL
        - wget -qO- http://127.0.0.1:4533/ping >/dev/null || exit 1
      interval: 30s
      timeout: 5s
      retries: 5
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
          cpus: "1.00"
          memory: 512M
        reservations:
          cpus: "0.10"
          memory: 64M
EOYAML
        if [ "$INSTALL_TYPE" = "TRADICIONAL" ]; then
            cat >>"$target" <<EOYAML

      labels:
        - traefik.enable=true
        - traefik.docker.network=externa
        - traefik.http.routers.$nome_app.rule=Host(\`$url_navidrome\`)
        - traefik.http.routers.$nome_app.entrypoints=websecure
        - traefik.http.routers.$nome_app.priority=1
        - traefik.http.routers.$nome_app.tls.certresolver=letsencryptresolver
        - traefik.http.routers.$nome_app.tls=true
        - traefik.http.routers.$nome_app.service=$nome_app
        - traefik.http.services.$nome_app.loadbalancer.server.port=4533
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
            --retry 30 --retry-all-errors --retry-delay 2 --connect-timeout 5 --max-time 75 \
            -fsS "http://$service_name:4533/ping" >>"$install_log" 2>&1 || return 1

        for _ in $(seq 1 90); do
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

    echo -e "XXX\n18\nBAIXANDO IMAGENS OFICIAIS MULTI-ARQUITETURA...\nXXX"
    for image_ref in "$NAVIDROME_IMAGE" "$CURL_IMAGE"; do
        docker pull "$image_ref" >>"$install_log" 2>&1 ||
            fail_install 20 "ERRO AO BAIXAR IMAGEM" "Falha ao baixar a imagem oficial: $image_ref"
        docker image inspect --format 'Imagem={{.Id}} Arquitetura={{.Architecture}} Tamanho={{.Size}}' \
            "$image_ref" >>"$install_log" 2>&1 ||
            fail_install 21 "IMAGEM NÃO CONFIRMADA" "A imagem foi baixada, mas não pôde ser inspecionada: $image_ref"
    done

    echo -e "XXX\n30\nCRIANDO ARMAZENAMENTO PERSISTENTE...\nXXX"
    mkdir -p "$data_dir" "$music_dir" >>"$install_log" 2>&1 ||
        fail_install 22 "ERRO AO CRIAR DIRETÓRIOS" "Não foi possível criar os diretórios persistentes do Navidrome."
    chmod 700 "$data_dir"
    chmod 750 "$music_dir"
    chown -R 1000:1000 "$data_dir" "$music_dir" >>"$install_log" 2>&1 ||
        fail_install 23 "ERRO DE PERMISSÃO" "Não foi possível restringir os dados ao usuário não-root do Navidrome."

    echo -e "XXX\n40\nGERANDO E VALIDANDO A STACK...\nXXX"
    write_stack_yaml "$app_yaml" ||
        fail_install 24 "ERRO AO GERAR STACK" "Não foi possível preparar a stack do Navidrome."
    docker stack config -c "$app_yaml" >"$work_dir/validated.yaml" 2>>"$install_log" ||
        fail_install 25 "YAML INVÁLIDO" "O arquivo $app_yaml não passou na validação do Docker."

    echo -e "XXX\n52\nPUBLICANDO A STACK DO NAVIDROME...\nXXX"
    if [ "$criar_portainer" = "0" ]; then
        portainer_login ||
            fail_install 30 "PORTAINER INDISPONÍVEL" "Não foi possível autenticar ou localizar o Docker Swarm no Portainer."
        portainer_response="$work_dir/portainer-create.json"
        http_code=$(curl -sk -o "$portainer_response" -w '%{http_code}' -X POST \
            -H "Authorization: Bearer $portainer_token" -F "Name=$nome_app" -F "file=@$app_yaml" \
            -F "SwarmID=$PORTAINER_SWARM_ID" -F "endpointId=$portainer_endpoint_id" \
            "https://$PORTAINER_URL/api/stacks/create/swarm/file" 2>>"$install_log")
        [[ "$http_code" =~ ^2[0-9][0-9]$ ]] ||
            fail_install 31 "PORTAINER RECUSOU A STACK" "O Portainer recusou a stack Navidrome (HTTP ${http_code:-indisponível})."
        stack_created="true"
        portainer_stack_id=$(jq -r '.Id // .id // empty' "$portainer_response")
        [ -n "$portainer_stack_id" ] ||
            fail_install 32 "STACK SEM IDENTIFICADOR" "O Portainer criou a stack sem retornar um identificador válido."
    else
        docker stack deploy --prune --resolve-image always -c "$app_yaml" "$nome_app" >>"$install_log" 2>&1 ||
            fail_install 33 "DOCKER RECUSOU A STACK" "O Docker recusou a stack Navidrome."
        stack_created="true"
    fi

    echo -e "XXX\n68\nAGUARDANDO O NAVIDROME E VALIDANDO /PING...\nXXX"
    wait_replica 75 || {
        docker service ps "$service_name" --no-trunc >>"$install_log" 2>&1 || true
        docker service logs --raw --tail 120 "$service_name" >>"$install_log" 2>&1 || true
        fail_install 40 "NAVIDROME NÃO INICIOU" "O serviço $service_name não atingiu 1/1 réplica."
    }
    check_health || {
        docker service logs --raw --tail 120 "$service_name" >>"$install_log" 2>&1 || true
        fail_install 41 "API NÃO RESPONDEU" "O endpoint interno /ping do Navidrome não confirmou o estado saudável."
    }
    [ -s "$data_dir/navidrome.db" ] ||
        fail_install 42 "PERSISTÊNCIA NÃO CONFIRMADA" "O Navidrome iniciou, mas não gravou seu banco SQLite persistente."

    if [ "$INSTALL_TYPE" = "CLOUDFLARE_TUNNEL" ] || { [ "$INSTALL_TYPE" = "TRADICIONAL" ] && [ "$criar_dns" = "0" ]; }; then
        echo -e "XXX\n82\nCONFIGURANDO DNS DE FORMA REVERSÍVEL...\nXXX"
        if [ "$INSTALL_TYPE" = "CLOUDFLARE_TUNNEL" ]; then
            dns_content="${TUNNEL_ID}.cfargotunnel.com"
            dns_proxied=true
        else
            dominio_principal=$(echo "$url_navidrome" | cut -d'.' -f2-)
            [ -n "$nome_servidor" ] || nome_servidor=$(hostname -I | awk '{print $1}')
            dns_content="${nome_servidor}.${dominio_principal}"
            dns_proxied=false
        fi
        curl -sS --get "https://api.cloudflare.com/client/v4/zones/$CLOUDFLARE_ZONE_ID/dns_records" \
            -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" --data-urlencode "name=$url_navidrome" \
            >"$work_dir/dns-lookup.json" 2>>"$install_log" ||
            fail_install 50 "ERRO AO CONSULTAR DNS" "Não foi possível consultar o DNS $url_navidrome."
        [ "$(jq -r '.success // false' "$work_dir/dns-lookup.json")" = "true" ] ||
            fail_install 51 "CLOUDFLARE RECUSOU CONSULTA" "A Cloudflare recusou a consulta do DNS do Navidrome."
        dns_record_id=$(jq -r '.result[0].id // empty' "$work_dir/dns-lookup.json")
        dns_record_type=$(jq -r '.result[0].type // empty' "$work_dir/dns-lookup.json")
        [ -z "$dns_record_id" ] || [ "$dns_record_type" = "CNAME" ] ||
            fail_install 52 "CONFLITO DE REGISTRO DNS" "Já existe um registro $dns_record_type para $url_navidrome; nada foi removido."
        jq -nc --arg name "$url_navidrome" --arg content "$dns_content" --argjson proxied "$dns_proxied" \
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
            fail_install 53 "ERRO AO CONFIGURAR DNS" "Falha de comunicação ao configurar o CNAME do Navidrome."
        [ "$(jq -r '.success // false' "$work_dir/dns-response.json")" = "true" ] ||
            fail_install 54 "CLOUDFLARE RECUSOU O DNS" "A Cloudflare recusou o CNAME do Navidrome."
        dns_record_id=$(jq -r '.result.id // empty' "$work_dir/dns-response.json")
        printf '%s' "$dns_record_id" >"$work_dir/dns-id"
        [ -s "$work_dir/dns-old.json" ] || : >"$work_dir/dns-created"
        dns_changed="true"
    fi

    if [ "$INSTALL_TYPE" = "CLOUDFLARE_TUNNEL" ]; then
        echo -e "XXX\n92\nATUALIZANDO ROTA DO CLOUDFLARE TUNNEL...\nXXX"
        curl -sS -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
            "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/cfd_tunnel/$TUNNEL_ID/configurations" \
            >"$work_dir/tunnel-original.json" 2>>"$install_log" ||
            fail_install 60 "ERRO AO CONSULTAR TUNNEL" "Não foi possível obter a configuração atual do Cloudflare Tunnel."
        [ "$(jq -r '.success // false' "$work_dir/tunnel-original.json")" = "true" ] ||
            fail_install 61 "TUNNEL RECUSOU CONSULTA" "A Cloudflare recusou a leitura da configuração do Tunnel."
        jq --arg host "$url_navidrome" --arg service "http://$service_name:4533" '
            (.result.config // {}) as $cfg
            | ($cfg.ingress // [])
            | map(select(.service != "http_status:404" and .hostname != $host))
            + [{hostname:$host,service:$service,originRequest:{httpHostHeader:$host}},
               {service:"http_status:404"}]
            | {config:($cfg + {ingress:.})}
        ' "$work_dir/tunnel-original.json" >"$work_dir/tunnel-payload.json" ||
            fail_install 62 "ERRO AO PREPARAR ROTA" "Não foi possível preparar a rota do Navidrome."
        curl -sS -X PUT \
            "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/cfd_tunnel/$TUNNEL_ID/configurations" \
            -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" -H "Content-Type: application/json" \
            --data-binary @"$work_dir/tunnel-payload.json" >"$work_dir/tunnel-response.json" 2>>"$install_log" ||
            fail_install 63 "ERRO AO ATUALIZAR TUNNEL" "Falha de comunicação ao atualizar a rota do Navidrome."
        [ "$(jq -r '.success // false' "$work_dir/tunnel-response.json")" = "true" ] ||
            fail_install 64 "TUNNEL RECUSOU A ROTA" "A Cloudflare recusou a rota do Navidrome."
        route_updated="true"
    fi

    mkdir -p /root/dados_navidrome
    chmod 700 /root/dados_navidrome
    cat >"/root/dados_navidrome/${nome_app}" <<EODATA

Navidrome PRO 0.63.2
Painel: https://$url_navidrome
Stack: $nome_app
Banco e cache: $data_dir
Biblioteca de músicas: $music_dir
Imagem: $NAVIDROME_IMAGE
Administrador: criar no primeiro acesso
EODATA
    chmod 600 "/root/dados_navidrome/${nome_app}"

    stack_created="false"
    route_updated="false"
    dns_changed="false"
    echo -e "XXX\n100\nNAVIDROME INSTALADO COM SUCESSO\nXXX"
} | whiptail --title "NAVIDROME PRO" --gauge "Preparando Navidrome..." 8 90 0
install_status=${PIPESTATUS[0]}

if [ "$install_status" -ne 0 ]; then
    error_detail=$(cat "$error_file" 2>/dev/null)
    [ -n "$error_detail" ] || error_detail=$(tail -n 20 "$install_log" 2>/dev/null)
    whiptail --title "ERRO NA INSTALAÇÃO DO NAVIDROME" --msgbox \
        "A instalação foi interrompida sem declarar falso sucesso.\n\n$error_detail\n\nLog completo: $install_log" \
        24 94
    exit "$install_status"
fi

manual_dns_note=""
if [ "$INSTALL_TYPE" = "TRADICIONAL" ] && [ "$criar_dns" = "1" ]; then
    manual_dns_note="\n\nDNS manual: aponte $url_navidrome para o servidor antes de acessar."
fi

whiptail --title "NAVIDROME PRO" --msgbox \
    "Navidrome instalado com sucesso.\n\nAcesse: https://$url_navidrome\nNo primeiro acesso, crie a conta administrativa.\n\nBiblioteca de músicas: $music_dir\nCopie seus arquivos de áudio para essa pasta e use a opção de varredura no painel.\n\nStack: $nome_app\nBanco e cache: $data_dir\nPorta 4533: somente interna.$manual_dns_note" \
    24 94

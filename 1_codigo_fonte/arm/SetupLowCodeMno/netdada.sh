#!/usr/bin/bash
# NETDADA PRO — Netdata Agent protegido por proxy autenticado para monitoramento do host e Docker.
set -o pipefail
umask 077

NETDATA_IMAGE_REF="netdata/netdata:v2.10.4@sha256:689145f603fed0ca341b4d8a0fb9910cd9d8c0590b0530cd24ae1912a9c7f8f3"
CADDY_IMAGE_REF="caddy:2.11.4-alpine@sha256:5f5c8640aae01df9654968d946d8f1a56c497f1dd5c5cda4cf95ab7c14d58648"

INSTALL_TYPE_FILE="/root/.cloudflared_config/installation_type"
INSTALL_TYPE="TRADICIONAL"
[ -f "$INSTALL_TYPE_FILE" ] && INSTALL_TYPE=$(cat "$INSTALL_TYPE_FILE")

if [ "$INSTALL_TYPE" = "CLOUDFLARE_TUNNEL" ]; then
    CREDENTIALS_FILE="/root/.cloudflared_config/cloudflare_credentials"
else
    CREDENTIALS_FILE="/root/.tradicional_config/tradicional_credentials"
fi
[ -f "$CREDENTIALS_FILE" ] && source "$CREDENTIALS_FILE"
criar_dns="${criar_dns:-0}"

msg() {
    whiptail --title "NETDADA PRO" --msgbox "$1" 14 78 1>&2
}

ask_required() {
    local prompt="$1" value status
    while true; do
        value=$(whiptail --title "NETDADA PRO" --inputbox "$prompt" 12 78 3>&1 1>&2 2>&3)
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
        value=$(whiptail --title "NETDADA PRO" --passwordbox "$prompt" 14 78 3>&1 1>&2 2>&3)
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

whiptail --title "NETDADA PRO" --yesno \
    "Instalar NETDADA como stack PRO?\n\nMonitoramento em tempo real de CPU, memória, discos, processos e containers Docker, protegido por autenticação própria e sem publicar a porta 19999." \
    16 80 || exit 0

while true; do
    if ! url_netdada=$(ask_required "1/4 — Domínio do NETDADA (ex.: monitor.seudominio.com):"); then
        exit 0
    fi
    if [[ "$url_netdada" =~ ^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$ ]] &&
       [[ "$url_netdada" == *.* ]]; then
        break
    fi
    msg "Informe somente o domínio, sem http://, https://, barras ou caminhos."
done

if [ "$INSTALL_TYPE" = "CLOUDFLARE_TUNNEL" ]; then
    route_check=$(mktemp)
    whiptail --title "NETDADA PRO" --infobox "Verificando se o domínio já possui uma rota no Cloudflare Tunnel..." 8 78
    if ! curl -sS -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
        "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/cfd_tunnel/$TUNNEL_ID/configurations" \
        >"$route_check" 2>/dev/null; then
        rm -f "$route_check"
        msg "Não foi possível consultar o Cloudflare Tunnel. Verifique as credenciais e tente novamente."
        exit 1
    fi
    existing_service=$(jq -r --arg host "$url_netdada" \
        '.result.config.ingress[]? | select(.hostname == $host) | .service' "$route_check" 2>/dev/null | head -n1)
    rm -f "$route_check"
    if [ -n "$existing_service" ] && [ "$existing_service" != "null" ]; then
        msg "Já existe uma rota para:\n\n$url_netdada\n\nServiço atual: $existing_service\n\nA rota será substituída pela nova instalação."
    fi
fi

while true; do
    if ! usuario_netdada=$(ask_required "2/4 — Usuário de acesso ao painel NETDADA:"); then
        exit 0
    fi
    if [[ "$usuario_netdada" =~ ^[A-Za-z0-9_.-]+$ ]]; then
        break
    fi
    msg "Use somente letras, números, ponto, hífen ou sublinhado no usuário."
done

if ! senha_netdada=$(ask_password "3/4 — Senha do painel\n\nMínimo: 12 caracteres, com maiúscula, minúscula, número e caractere especial."); then
    exit 0
fi

while true; do
    if ! criar_portainer=$(ask_required "4/4 — Criar Stack no Portainer?\n\n0 = editável no Portainer\n1 = direto no Docker"); then
        unset senha_netdada
        exit 0
    fi
    [[ "$criar_portainer" =~ ^[01]$ ]] && break
    msg "Digite somente 0 ou 1."
done

nome_principal="netdada"
sufixo_app=$(date +%s%N | md5sum | head -c7)
nome_app="${nome_principal}${sufixo_app}"
agent_service="${nome_app}_agent"
proxy_service="${nome_app}_proxy"
proxy_dir="/root/${nome_app}_proxy"

dns_mode="Cloudflare Tunnel"
if [ "$INSTALL_TYPE" = "TRADICIONAL" ]; then
    if [ "$criar_dns" = "0" ]; then
        dns_mode="Tradicional com DNS automático"
    else
        dns_mode="Tradicional com DNS manual"
    fi
fi

whiptail --title "Confirmar instalação" --yesno \
    "NETDADA PRO\n\nDomínio: $url_netdada\nUsuário: $usuario_netdada\nInstalação: $dns_mode\nStack: $([ "$criar_portainer" = "0" ] && echo "Portainer editável" || echo "Docker direto")\nArquiteturas: X86 e ARM\nRAM máxima total: 896 MB\nPorta 19999: somente interna\nTelemetria anônima: desativada" \
    22 82 || {
        unset senha_netdada
        exit 0
    }

install_log="/tmp/${nome_app}-install.log"
error_file="/tmp/${nome_app}-error.log"
: >"$install_log"
: >"$error_file"

{
    work_dir=$(mktemp -d)
    trap 'rm -rf "$work_dir"' EXIT

    fail_install() {
        local code="$1" progress="$2" message="$3"
        printf '%s\n' "$message" >"$error_file"
        echo -e "XXX\n100\n$progress\nXXX"
        exit "$code"
    }

    echo -e "XXX\n5\nVALIDANDO AMBIENTE E REDES... \nXXX"
    for required_command in docker curl jq base64; do
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

    if [ "$INSTALL_TYPE" = "CLOUDFLARE_TUNNEL" ] ||
       { [ "$INSTALL_TYPE" = "TRADICIONAL" ] && [ "$criar_dns" = "0" ]; }; then
        [ -n "$CLOUDFLARE_API_TOKEN" ] && [ -n "$CLOUDFLARE_ZONE_ID" ] ||
            fail_install 16 "CREDENCIAIS CLOUDFLARE INVÁLIDAS" "Token ou Zone ID do Cloudflare não encontrado nas credenciais."
    fi
    if [ "$INSTALL_TYPE" = "CLOUDFLARE_TUNNEL" ]; then
        [ -n "$CLOUDFLARE_ACCOUNT_ID" ] && [ -n "$TUNNEL_ID" ] ||
            fail_install 17 "DADOS DO TUNNEL INVÁLIDOS" "Account ID ou Tunnel ID não encontrado nas credenciais."
    fi

    echo -e "XXX\n16\nBAIXANDO IMAGENS OFICIAIS MULTI-ARQUITETURA... \nXXX"
    for image_ref in "$NETDATA_IMAGE_REF" "$CADDY_IMAGE_REF"; do
        if ! docker pull "$image_ref" >>"$install_log" 2>&1; then
            fail_install 20 "ERRO AO BAIXAR IMAGEM" "Falha ao baixar a imagem oficial: $image_ref"
        fi
        docker image inspect "$image_ref" >>"$install_log" 2>&1 ||
            fail_install 21 "IMAGEM NÃO ENCONTRADA" "A imagem foi baixada, mas não pôde ser confirmada: $image_ref"
    done

    echo -e "XXX\n28\nGERANDO AUTENTICAÇÃO SEGURA DO PAINEL... \nXXX"
    if ! password_hash=$(printf '%s\n%s\n' "$senha_netdada" "$senha_netdada" |
        docker run -i --rm "$CADDY_IMAGE_REF" caddy hash-password 2>>"$install_log"); then
        unset senha_netdada
        fail_install 22 "ERRO AO PROTEGER SENHA" "O Caddy não conseguiu gerar o hash bcrypt da senha."
    fi
    unset senha_netdada
    [[ "$password_hash" == '$2'* ]] ||
        fail_install 23 "HASH DE SENHA INVÁLIDO" "O hash bcrypt gerado não possui o formato esperado."

    mkdir -p "$proxy_dir" >>"$install_log" 2>&1 ||
        fail_install 24 "ERRO AO CRIAR CONFIGURAÇÃO" "Não foi possível criar $proxy_dir."
    chmod 700 "$proxy_dir"
    cat >"$proxy_dir/Caddyfile" <<EOCADDY
:8080 {
    encode zstd gzip
    basic_auth {
        $usuario_netdada $password_hash
    }
    reverse_proxy $agent_service:19999
    header {
        -Server
        X-Content-Type-Options "nosniff"
        Referrer-Policy "same-origin"
        X-Frame-Options "SAMEORIGIN"
    }
}
EOCADDY
    chmod 600 "$proxy_dir/Caddyfile"
    unset password_hash

    echo -e "XXX\n38\nGERANDO E VALIDANDO STACK DO NETDADA... \nXXX"
    cat >"/root/$nome_app.yaml" <<EOYAML
version: "3.8"
services:
  $agent_service:
    image: $NETDATA_IMAGE_REF
    hostname: $nome_app
    cap_add:
      - SYS_ADMIN
      - SYS_PTRACE
    environment:
      - DISABLE_TELEMETRY=1
      - DO_NOT_TRACK=1
    volumes:
      - ${nome_app}_config:/etc/netdata
      - ${nome_app}_lib:/var/lib/netdata
      - ${nome_app}_cache:/var/cache/netdata
      - /etc/passwd:/host/etc/passwd:ro
      - /etc/group:/host/etc/group:ro
      - /etc/localtime:/etc/localtime:ro
      - /etc/hostname:/host/etc/hostname:ro
      - /proc:/host/proc:ro
      - /sys:/host/sys:ro
      - /etc/os-release:/host/etc/os-release:ro
      - /var/run/docker.sock:/var/run/docker.sock:ro
    networks:
      - interna
    healthcheck:
      test:
        - CMD-SHELL
        - curl -fsS http://127.0.0.1:19999/api/v1/info >/dev/null || exit 1
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
          cpus: "1.00"
          memory: 768M
        reservations:
          cpus: "0.10"
          memory: 128M

  $proxy_service:
    image: $CADDY_IMAGE_REF
    volumes:
      - $proxy_dir/Caddyfile:/etc/caddy/Caddyfile:ro
    networks:
      - externa
      - interna
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
      resources:
        limits:
          cpus: "0.25"
          memory: 128M
        reservations:
          memory: 32M
EOYAML

    if [ "$INSTALL_TYPE" = "TRADICIONAL" ]; then
        cat >>"/root/$nome_app.yaml" <<EOYAML
      labels:
        - traefik.enable=true
        - traefik.docker.network=externa
        - traefik.http.routers.$nome_app.rule=Host(\`$url_netdada\`)
        - traefik.http.routers.$nome_app.entrypoints=websecure
        - traefik.http.routers.$nome_app.priority=1
        - traefik.http.routers.$nome_app.tls.certresolver=letsencryptresolver
        - traefik.http.routers.$nome_app.tls=true
        - traefik.http.routers.$nome_app.service=$nome_app
        - traefik.http.services.$nome_app.loadbalancer.server.port=8080
EOYAML
    fi

    cat >>"/root/$nome_app.yaml" <<EOYAML

networks:
  externa:
    external: true
  interna:
    external: true

volumes:
  ${nome_app}_config:
  ${nome_app}_lib:
  ${nome_app}_cache:
EOYAML

    if ! docker stack config -c "/root/$nome_app.yaml" >"$work_dir/validated-stack.yaml" 2>>"$install_log"; then
        fail_install 30 "ERRO NO YAML DA STACK" "O YAML da stack NETDADA é inválido."
    fi
    if grep -q 'published:' "$work_dir/validated-stack.yaml" 2>/dev/null; then
        fail_install 31 "PORTA PUBLICADA INDEVIDAMENTE" "A validação encontrou uma porta publicada no host."
    fi

    if [ "$INSTALL_TYPE" = "CLOUDFLARE_TUNNEL" ] ||
       { [ "$INSTALL_TYPE" = "TRADICIONAL" ] && [ "$criar_dns" = "0" ]; }; then
        echo -e "XXX\n50\nCONFIGURANDO DNS DE FORMA IDEMPOTENTE... \nXXX"
        dns_lookup="$work_dir/dns-lookup.json"
        dns_response="$work_dir/dns-response.json"
        if [ "$INSTALL_TYPE" = "CLOUDFLARE_TUNNEL" ]; then
            dns_content="${TUNNEL_ID}.cfargotunnel.com"
            dns_proxied="true"
        else
            DOMINIO_PRINCIPAL=$(echo "$url_netdada" | cut -d'.' -f2-)
            [ -n "$nome_servidor" ] || nome_servidor=$(hostname -I | awk '{print $1}')
            dns_content="${nome_servidor}.${DOMINIO_PRINCIPAL}"
            dns_proxied="false"
        fi
        dns_payload=$(jq -nc --arg name "$url_netdada" --arg content "$dns_content" \
            --argjson proxied "$dns_proxied" '{type:"CNAME",name:$name,content:$content,ttl:1,proxied:$proxied}')
        if ! curl -sS --get "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records" \
            -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" --data-urlencode "name=$url_netdada" \
            >"$dns_lookup" 2>>"$install_log"; then
            fail_install 40 "ERRO AO CONSULTAR DNS" "Falha de comunicação ao consultar o DNS $url_netdada no Cloudflare."
        fi
        dns_record_id=$(jq -r '.result[0].id // empty' "$dns_lookup")
        dns_record_type=$(jq -r '.result[0].type // empty' "$dns_lookup")
        if [ -n "$dns_record_id" ] && [ "$dns_record_type" != "CNAME" ]; then
            fail_install 41 "CONFLITO DE REGISTRO DNS" "Já existe um registro $dns_record_type para $url_netdada. Ele não foi removido automaticamente."
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
        echo -e "XXX\n62\nATUALIZANDO ROTA DO CLOUDFLARE TUNNEL... \nXXX"
        tunnel_raw="$work_dir/tunnel-raw.json"
        tunnel_payload="$work_dir/tunnel-payload.json"
        tunnel_response="$work_dir/tunnel-response.json"
        if ! curl -sS -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
            "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/cfd_tunnel/$TUNNEL_ID/configurations" \
            >"$tunnel_raw" 2>>"$install_log" ||
           [ "$(jq -r '.success // false' "$tunnel_raw")" != "true" ]; then
            fail_install 50 "ERRO AO CONSULTAR TUNNEL" "Não foi possível obter a configuração atual do Cloudflare Tunnel."
        fi
        if ! jq --arg host "$url_netdada" --arg service "http://${proxy_service}:8080" '
            (.result.config // {}) as $cfg
            | ($cfg.ingress // [])
            | map(select(.service != "http_status:404" and .hostname != $host))
            + [{hostname:$host,service:$service,originRequest:{noTlsVerify:true,httpHostHeader:$host}},
               {service:"http_status:404"}]
            | {config:($cfg + {ingress:.})}
        ' "$tunnel_raw" >"$tunnel_payload" 2>>"$install_log"; then
            fail_install 51 "ERRO AO PREPARAR ROTA" "Falha ao preparar a nova rota do Cloudflare Tunnel."
        fi
        if ! curl -sS -X PUT \
            "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/cfd_tunnel/$TUNNEL_ID/configurations" \
            -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" -H "Content-Type: application/json" \
            --data-binary @"$tunnel_payload" >"$tunnel_response" 2>>"$install_log" ||
           [ "$(jq -r '.success // false' "$tunnel_response")" != "true" ]; then
            tunnel_error=$(jq -r '[.errors[]?.message] | join("; ")' "$tunnel_response" 2>/dev/null)
            fail_install 52 "ERRO AO ATUALIZAR TUNNEL" "Cloudflare recusou a rota: ${tunnel_error:-resposta inválida da API}."
        fi
    fi

    echo -e "XXX\n75\nPUBLICANDO STACK DO NETDADA... \nXXX"
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
            '{username:$username,password:$password}' >"$auth_payload" ||
            fail_install 62 "ERRO AO PREPARAR AUTENTICAÇÃO" "Não foi possível preparar a autenticação do Portainer."
        if ! curl -sk -X POST "https://$PORTAINER_URL/api/auth" -H "Content-Type: application/json" \
            --data-binary @"$auth_payload" \
            >"$auth_response" 2>>"$install_log"; then
            fail_install 62 "ERRO DE COMUNICAÇÃO COM PORTAINER" "Não foi possível acessar a API do Portainer."
        fi
        TOKEN=$(jq -r '.jwt // empty' "$auth_response")
        [ -n "$TOKEN" ] || fail_install 63 "ERRO DE AUTENTICAÇÃO NO PORTAINER" "O Portainer não retornou token válido."
        endpoint_response="$work_dir/portainer-endpoints.json"
        curl -sk "https://$PORTAINER_URL/api/endpoints" -H "Authorization: Bearer $TOKEN" \
            >"$endpoint_response" 2>>"$install_log" ||
            fail_install 64 "ERRO AO CONSULTAR ENDPOINT" "Falha ao consultar os endpoints do Portainer."
        ENDPOINT_ID=$(jq -r '.[0].Id // empty' "$endpoint_response")
        [ -n "$ENDPOINT_ID" ] || fail_install 65 "ENDPOINT NÃO ENCONTRADO" "Nenhum endpoint foi encontrado no Portainer."
        swarm_response="$work_dir/portainer-swarm.json"
        curl -sk "https://$PORTAINER_URL/api/endpoints/$ENDPOINT_ID/docker/swarm" -H "Authorization: Bearer $TOKEN" \
            >"$swarm_response" 2>>"$install_log" ||
            fail_install 66 "ERRO AO CONSULTAR SWARM" "Falha ao consultar o Docker Swarm pelo Portainer."
        SWARM_ID=$(jq -r '.ID // empty' "$swarm_response")
        [ -n "$SWARM_ID" ] || fail_install 67 "SWARM NÃO ENCONTRADO" "O Portainer não retornou Swarm ID válido."
        portainer_response="$work_dir/portainer-stack.json"
        http_code=$(curl -sk -o "$portainer_response" -w "%{http_code}" -X POST \
            -H "Authorization: Bearer $TOKEN" -F "Name=$nome_app" -F "file=@/root/$nome_app.yaml" \
            -F "SwarmID=$SWARM_ID" -F "endpointId=$ENDPOINT_ID" \
            "https://$PORTAINER_URL/api/stacks/create/swarm/file" 2>>"$install_log")
        if ! [[ "$http_code" =~ ^[0-9]{3}$ ]] || [ "$http_code" -lt 200 ] || [ "$http_code" -ge 300 ]; then
            portainer_error=$(jq -r '.message // empty' "$portainer_response" 2>/dev/null)
            fail_install 68 "ERRO AO CRIAR STACK NO PORTAINER" "Portainer recusou a stack (HTTP ${http_code:-indisponível}): ${portainer_error:-sem detalhes}."
        fi
    else
        docker stack deploy --prune --resolve-image always -c "/root/$nome_app.yaml" "$nome_app" \
            >>"$install_log" 2>&1 ||
            fail_install 69 "ERRO AO CRIAR STACK NO DOCKER" "Falha ao publicar a stack diretamente no Docker."
    fi

    echo -e "XXX\n90\nAGUARDANDO AGENTE E PROXY FICAREM PRONTOS... \nXXX"
    agent_full_service="${nome_app}_${agent_service}"
    proxy_full_service="${nome_app}_${proxy_service}"
    ready="false"
    for _ in $(seq 1 30); do
        agent_replicas=$(docker service ls --filter "name=$agent_full_service" --format '{{.Replicas}}' 2>>"$install_log" | head -n1)
        proxy_replicas=$(docker service ls --filter "name=$proxy_full_service" --format '{{.Replicas}}' 2>>"$install_log" | head -n1)
        if [ "$agent_replicas" = "1/1" ] && [ "$proxy_replicas" = "1/1" ]; then
            ready="true"
            break
        fi
        sleep 4
    done
    if [ "$ready" != "true" ]; then
        {
            echo "A stack foi criada, mas agente e proxy não atingiram 1/1 réplica."
            docker service ps "$agent_full_service" --no-trunc --format 'Agente: {{.CurrentState}} | {{.Error}}' 2>/dev/null | head -n 5
            docker service ps "$proxy_full_service" --no-trunc --format 'Proxy: {{.CurrentState}} | {{.Error}}' 2>/dev/null | head -n 5
        } >"$error_file"
        echo -e "XXX\n100\nSERVIÇOS NÃO FICARAM PRONTOS\nXXX"
        exit 70
    fi

    agent_container=$(docker ps --filter "label=com.docker.swarm.service.name=$agent_full_service" \
        --filter health=healthy --format '{{.ID}}' | head -n1)
    proxy_container=$(docker ps --filter "label=com.docker.swarm.service.name=$proxy_full_service" \
        --filter health=healthy --format '{{.ID}}' | head -n1)
    [ -n "$agent_container" ] && [ -n "$proxy_container" ] ||
        fail_install 71 "HEALTHCHECK NÃO CONFIRMADO" "As réplicas subiram, mas os healthchecks ainda não estão saudáveis."
    docker exec "$agent_container" curl -fsS http://127.0.0.1:19999/api/v1/info >/dev/null 2>>"$install_log" ||
        fail_install 72 "API DO NETDATA INDISPONÍVEL" "O Agent subiu, mas sua API interna não respondeu."
    if docker exec "$proxy_container" wget -q -O /dev/null http://127.0.0.1:8080/ 2>>"$install_log"; then
        fail_install 73 "PAINEL SEM AUTENTICAÇÃO" "O proxy aceitou acesso anônimo e a instalação foi bloqueada por segurança."
    fi

    echo -e "XXX\n100\nNETDADA INSTALADO COM SUCESSO\nXXX"
} | whiptail --title "NETDADA PRO" --gauge "Preparando NETDADA..." 8 78 0
install_status=${PIPESTATUS[0]}
unset senha_netdada

if [ "$install_status" -ne 0 ]; then
    error_detail=$(cat "$error_file" 2>/dev/null)
    [ -n "$error_detail" ] || error_detail=$(tail -n 20 "$install_log" 2>/dev/null)
    whiptail --title "ERRO NA INSTALAÇÃO DO NETDADA" --msgbox \
        "A instalação foi interrompida sem declarar falso sucesso.\n\n$error_detail\n\nLog completo: $install_log" \
        24 94
    exit "$install_status"
fi

manual_dns_note=""
if [ "$INSTALL_TYPE" = "TRADICIONAL" ] && [ "$criar_dns" = "1" ]; then
    manual_dns_note="\n\nDNS manual: aponte $url_netdada para o servidor antes de acessar."
fi

whiptail --title "NETDADA PRO" --msgbox \
    "NETDADA instalado com sucesso.\n\nAcesse: https://$url_netdada\nUsuário: $usuario_netdada\nStack: $nome_app\n\nO navegador solicitará o usuário e a senha definidos durante a instalação. A porta 19999 não foi publicada no host.\n\nObservação: por limitação do Docker Swarm, coletores que exigem namespace de rede/PID do host podem apresentar dados parciais; CPU, RAM, discos e containers permanecem monitorados.$manual_dns_note" \
    24 88

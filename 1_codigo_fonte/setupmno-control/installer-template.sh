#!/usr/bin/bash
# SETUP MNO CONTROL CENTER — painel web oficial de deploys e monitoramento.
set -o pipefail
umask 077

CONTROL_VERSION="1.0.2"

extract_control_bundle() {
    base64 -d <<'SETUPMNO_CONTROL_ARCHIVE'
__SETUPMNO_CONTROL_BUNDLE__
SETUPMNO_CONTROL_ARCHIVE
}

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
    whiptail --title "SETUP MNO CONTROL CENTER" --msgbox "$1" 14 78
}

ask_required() {
    local prompt="$1" value status
    while true; do
        value=$(whiptail --title "SETUP MNO CONTROL CENTER" --inputbox "$prompt" 12 78 3>&1 1>&2 2>&3)
        status=$?
        [ "$status" -ne 0 ] && exit 0
        [ -n "$value" ] && {
            printf '%s' "$value"
            return
        }
        msg "Este campo é obrigatório."
    done
}

ask_password() {
    local value confirmation status
    while true; do
        value=$(whiptail --title "SETUP MNO CONTROL CENTER" --passwordbox \
            "3/4 — Crie a senha administrativa:\n\nMínimo de 12 caracteres, com maiúscula, minúscula, número e símbolo." \
            14 78 3>&1 1>&2 2>&3)
        status=$?
        [ "$status" -ne 0 ] && exit 0
        if [ "${#value}" -lt 12 ] ||
           [[ ! "$value" =~ [[:upper:]] ]] ||
           [[ ! "$value" =~ [[:lower:]] ]] ||
           [[ ! "$value" =~ [[:digit:]] ]] ||
           [[ "$value" =~ ^[[:alnum:]]+$ ]]; then
            msg "A senha não atende aos requisitos mínimos."
            continue
        fi
        confirmation=$(whiptail --title "SETUP MNO CONTROL CENTER" --passwordbox \
            "Confirme a senha administrativa:" 11 78 3>&1 1>&2 2>&3)
        status=$?
        [ "$status" -ne 0 ] && exit 0
        [ "$value" = "$confirmation" ] && {
            printf '%s' "$value"
            return
        }
        msg "As senhas não coincidem."
    done
}

whiptail --title "SETUP MNO CONTROL CENTER" --yesno \
    "Instalar o painel web oficial do Setup MNO?\n\nO Control Center mostra aplicações instaladas, saúde do Docker Swarm, CPU, RAM, disco, catálogo de setups, auditoria, diagnóstico local e acesso autenticado ao instalador original." \
    16 82 || exit 0

while true; do
    url_control=$(ask_required "1/4 — Domínio do painel (ex.: setup.seudominio.com):")
    if [[ "$url_control" =~ ^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$ ]] &&
       [[ "$url_control" == *.* ]]; then
        break
    fi
    msg "Informe somente o domínio, sem http://, https://, barras ou caminhos."
done

if [ "$INSTALL_TYPE" = "CLOUDFLARE_TUNNEL" ]; then
    route_check=$(mktemp)
    whiptail --title "SETUP MNO CONTROL CENTER" --infobox \
        "Verificando se o domínio já possui uma rota no Cloudflare Tunnel..." 8 78
    if ! curl -sS -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
        "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/cfd_tunnel/$TUNNEL_ID/configurations" \
        >"$route_check" 2>/dev/null; then
        rm -f "$route_check"
        msg "Não foi possível consultar o Cloudflare Tunnel. Verifique as credenciais e tente novamente."
        exit 1
    fi
    existing_service=$(jq -r --arg host "$url_control" \
        '.result.config.ingress[]? | select(.hostname == $host) | .service' "$route_check" 2>/dev/null | head -n1)
    rm -f "$route_check"
    if [ -n "$existing_service" ] && [ "$existing_service" != "null" ]; then
        msg "Já existe uma rota para:\n\n$url_control\n\nServiço atual: $existing_service\n\nA rota será substituída pela nova instalação."
    fi
fi

while true; do
    usuario_control=$(ask_required "2/4 — Usuário administrador do painel:")
    if [[ "$usuario_control" =~ ^[A-Za-z0-9_.-]{3,40}$ ]]; then
        break
    fi
    msg "Use de 3 a 40 caracteres: letras, números, ponto, hífen ou sublinhado."
done

senha_control=$(ask_password)

while true; do
    criar_portainer=$(ask_required "4/4 — Criar Stack no Portainer?\n\n0 = editável no Portainer\n1 = direto no Docker")
    [[ "$criar_portainer" =~ ^[01]$ ]] && break
    msg "Digite somente 0 ou 1."
done

nome_principal="mnoctrl"
sufixo_app=$(date +%s%N | md5sum | head -c7)
nome_app="${nome_principal}${sufixo_app}"
web_stack="${nome_app}-web"
agent_stack="${nome_app}-agent"
terminal_stack="${nome_app}-terminal"
web_service="${nome_app}-web"
agent_service="${nome_app}-agent"
terminal_service="${nome_app}-terminal"
control_image="${nome_app}-app:${CONTROL_VERSION}"
terminal_image="${nome_app}-terminal:${CONTROL_VERSION}"
admin_secret="${nome_app}-admin-password"
agent_secret="${nome_app}-agent-token"

dns_mode="Cloudflare Tunnel"
if [ "$INSTALL_TYPE" = "TRADICIONAL" ]; then
    if [ "$criar_dns" = "0" ]; then
        dns_mode="Tradicional com DNS automático"
    else
        dns_mode="Tradicional com DNS manual"
    fi
fi

whiptail --title "CONFIRMAR INSTALAÇÃO" --yesno \
    "Setup MNO Control Center\n\nDomínio: $url_control\nAdministrador: $usuario_control\nInstalação: $dns_mode\nDeploy: $([ "$criar_portainer" = "0" ] && echo "Portainer editável" || echo "Docker direto")\nArquiteturas: X86 e ARM\nLimite total de memória: 576 MB\n\nO terminal executará o instalador original e será acessível somente após autenticação." \
    21 84 || exit 0

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

    echo -e "XXX\n4\nVALIDANDO AMBIENTE... \nXXX"
    for required_command in docker curl jq base64 tar openssl; do
        command -v "$required_command" >/dev/null 2>&1 ||
            fail_install 10 "DEPENDÊNCIA NÃO ENCONTRADA" "O comando obrigatório '$required_command' não está instalado."
    done
    docker info >>"$install_log" 2>&1 ||
        fail_install 11 "DOCKER INDISPONÍVEL" "O Docker Engine ou o Swarm não está disponível."
    swarm_state=$(docker info --format '{{.Swarm.LocalNodeState}}' 2>>"$install_log")
    [ "$swarm_state" = "active" ] ||
        fail_install 11 "SWARM INATIVO" "O Docker Swarm precisa estar ativo antes de instalar o Control Center."
    docker network inspect interna >>"$install_log" 2>&1 ||
        fail_install 12 "REDE INTERNA INDISPONÍVEL" "A rede overlay 'interna' não foi encontrada."
    docker network inspect externa >>"$install_log" 2>&1 ||
        fail_install 13 "REDE EXTERNA INDISPONÍVEL" "A rede overlay 'externa' não foi encontrada."
    [ -x /root/SetupLowCodeMno/install ] ||
        fail_install 14 "INSTALADOR NÃO ENCONTRADO" "O executável /root/SetupLowCodeMno/install não foi encontrado."
    [ -f "$CREDENTIALS_FILE" ] ||
        fail_install 15 "CREDENCIAIS NÃO ENCONTRADAS" "Arquivo de credenciais não encontrado: $CREDENTIALS_FILE"

    if [ "$INSTALL_TYPE" = "CLOUDFLARE_TUNNEL" ] ||
       { [ "$INSTALL_TYPE" = "TRADICIONAL" ] && [ "$criar_dns" = "0" ]; }; then
        if [ -z "$CLOUDFLARE_API_TOKEN" ] || [ -z "$CLOUDFLARE_ZONE_ID" ]; then
            fail_install 16 "CREDENCIAIS CLOUDFLARE INVÁLIDAS" "Token ou Zone ID do Cloudflare não encontrado."
        fi
    fi
    if [ "$INSTALL_TYPE" = "CLOUDFLARE_TUNNEL" ] &&
       { [ -z "$CLOUDFLARE_ACCOUNT_ID" ] || [ -z "$TUNNEL_ID" ]; }; then
        fail_install 17 "DADOS DO TUNNEL INVÁLIDOS" "Account ID ou Tunnel ID não encontrado."
    fi

    echo -e "XXX\n10\nEXTRAINDO O CONTROL CENTER... \nXXX"
    mkdir -p "$work_dir/source"
    if ! extract_control_bundle 2>>"$install_log" |
        tar -xzf - -C "$work_dir/source" >>"$install_log" 2>&1; then
        fail_install 20 "BUNDLE DO PAINEL INVÁLIDO" "Não foi possível validar e extrair os fontes internos do Control Center."
    fi
    for source_file in go.mod Dockerfile terminal.Dockerfile main.go catalog.json web/index.html; do
        [ -s "$work_dir/source/$source_file" ] ||
            fail_install 21 "FONTE INCOMPLETO" "O arquivo interno '$source_file' não foi encontrado no bundle."
    done

    echo -e "XXX\n20\nCONSTRUINDO O PAINEL WEB... \nXXX"
    if ! docker build --pull -t "$control_image" "$work_dir/source" >>"$install_log" 2>&1; then
        {
            echo "Falha ao construir a imagem do painel."
            echo
            tail -n 20 "$install_log"
        } >"$error_file"
        echo -e "XXX\n100\nERRO NO BUILD DO PAINEL\nXXX"
        exit 30
    fi
    if ! docker image inspect --format \
        'Painel: {{.Id}} | Arquitetura: {{.Architecture}} | Tamanho: {{.Size}} bytes' \
        "$control_image" >>"$install_log" 2>&1; then
        fail_install 31 "IMAGEM DO PAINEL NÃO ENCONTRADA" "O build terminou, mas a imagem do painel não foi confirmada."
    fi

    echo -e "XXX\n38\nCONSTRUINDO O TERMINAL PROTEGIDO... \nXXX"
    if ! docker build --pull -f "$work_dir/source/terminal.Dockerfile" \
        -t "$terminal_image" "$work_dir/source" >>"$install_log" 2>&1; then
        {
            echo "Falha ao construir a imagem do terminal protegido."
            echo
            tail -n 20 "$install_log"
        } >"$error_file"
        echo -e "XXX\n100\nERRO NO BUILD DO TERMINAL\nXXX"
        exit 32
    fi
    if ! docker image inspect --format \
        'Terminal: {{.Id}} | Arquitetura: {{.Architecture}} | Tamanho: {{.Size}} bytes' \
        "$terminal_image" >>"$install_log" 2>&1; then
        fail_install 33 "IMAGEM DO TERMINAL NÃO ENCONTRADA" "O build terminou, mas a imagem do terminal não foi confirmada."
    fi

    echo -e "XXX\n46\nVALIDANDO COMPATIBILIDADE DO INSTALADOR... \nXXX"
    if ! docker run --rm \
        --entrypoint /usr/bin/ldd \
        -v /root:/root:ro \
        -v /usr/bin/bash:/usr/bin/bash:ro \
        "$terminal_image" \
        /root/SetupLowCodeMno/install >>"$install_log" 2>&1; then
        {
            echo "O terminal foi construído, mas sua GLIBC não é compatível com o instalador do Setup MNO."
            echo
            tail -n 16 "$install_log"
        } >"$error_file"
        echo -e "XXX\n100\nTERMINAL INCOMPATÍVEL COM O INSTALADOR\nXXX"
        exit 34
    fi

    echo -e "XXX\n51\nCRIANDO SEGREDOS DO PAINEL... \nXXX"
    if ! printf '%s' "$senha_control" |
        docker secret create "$admin_secret" - >>"$install_log" 2>&1; then
        fail_install 40 "ERRO AO CRIAR SENHA" "Não foi possível criar o segredo da senha administrativa."
    fi
    unset senha_control
    if ! openssl rand -hex 32 |
        docker secret create "$agent_secret" - >>"$install_log" 2>&1; then
        fail_install 41 "ERRO AO CRIAR TOKEN" "Não foi possível criar o token privado do agente."
    fi

    echo -e "XXX\n58\nGERANDO STACKS ISOLADAS... \nXXX"
    cd
    cd
    cat >"${terminal_stack}.yaml" <<EOL

version: "3.7"
services:
  $terminal_service:
    image: $terminal_image
    hostname: $terminal_service
    command:
      - -p
      - "7681"
      - -b
      - /terminal
      - -W
      - -O
      - -m
      - "1"
      - /root/SetupLowCodeMno/install
    networks:
      - interna
    volumes:
      - /root:/root
      - /tmp:/tmp
      - /usr/bin/bash:/usr/bin/bash:ro
      - /var/run/docker.sock:/var/run/docker.sock
      - /etc/localtime:/etc/localtime:ro
    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
        - node.role == manager
      resources:
        limits:
          cpus: "0.50"
          memory: 256M

networks:
  interna:
    external: true
EOL

    cat >"${agent_stack}.yaml" <<EOL

version: "3.7"
services:
  $agent_service:
    image: $control_image
    hostname: $agent_service
    read_only: true
    environment:
      - MODE=agent
      - AGENT_TOKEN_FILE=/run/secrets/$agent_secret
    networks:
      - interna
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - /proc:/host/proc:ro
      - /:/hostfs:ro
    secrets:
      - $agent_secret
    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
        - node.role == manager
      resources:
        limits:
          cpus: "0.25"
          memory: 128M

networks:
  interna:
    external: true

secrets:
  $agent_secret:
    external: true
EOL

    cat >"${web_stack}.yaml" <<EOL

version: "3.7"
services:
  $web_service:
    image: $control_image
    hostname: $web_service
    read_only: true
    environment:
      - MODE=web
      - APP_VERSION=$CONTROL_VERSION
      - ADMIN_USERNAME=$usuario_control
      - ADMIN_PASSWORD_FILE=/run/secrets/$admin_secret
      - AGENT_TOKEN_FILE=/run/secrets/$agent_secret
      - AGENT_URL=http://${agent_stack}_${agent_service}:9090
      - TERMINAL_URL=http://${terminal_stack}_${terminal_service}:7681
      - COOKIE_SECURE=true
    networks:
      - externa
      - interna
    secrets:
      - $admin_secret
      - $agent_secret
    healthcheck:
      test:
        - CMD
        - /setupmno-control
        - healthcheck
      interval: 30s
      timeout: 5s
      retries: 3
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
          memory: 192M
EOL

    if [ "$INSTALL_TYPE" = "TRADICIONAL" ]; then
        cat >>"${web_stack}.yaml" <<EOL
      labels:
      - traefik.enable=true
      - traefik.docker.network=externa
      - traefik.http.routers.$web_service.rule=Host(\`$url_control\`)
      - traefik.http.routers.$web_service.entrypoints=websecure
      - traefik.http.routers.$web_service.priority=1
      - traefik.http.routers.$web_service.tls.certresolver=letsencryptresolver
      - traefik.http.routers.$web_service.tls=true
      - traefik.http.routers.$web_service.service=$web_service
      - traefik.http.services.$web_service.loadbalancer.server.port=8080
EOL
    fi

    cat >>"${web_stack}.yaml" <<EOL

networks:
  externa:
    external: true
  interna:
    external: true

secrets:
  $admin_secret:
    external: true
  $agent_secret:
    external: true
EOL

    for stack_file in "${terminal_stack}.yaml" "${agent_stack}.yaml" "${web_stack}.yaml"; do
        if ! docker stack config -c "/root/$stack_file" >"$work_dir/validated-$stack_file" 2>>"$install_log"; then
            {
                echo "O YAML '$stack_file' é inválido."
                echo
                tail -n 20 "$install_log"
            } >"$error_file"
            echo -e "XXX\n100\nERRO NO YAML DAS STACKS\nXXX"
            exit 50
        fi
    done

    if [ "$INSTALL_TYPE" = "CLOUDFLARE_TUNNEL" ] ||
       { [ "$INSTALL_TYPE" = "TRADICIONAL" ] && [ "$criar_dns" = "0" ]; }; then
        echo -e "XXX\n67\nCONFIGURANDO DNS DE FORMA IDEMPOTENTE... \nXXX"
        dns_lookup="$work_dir/dns-lookup.json"
        dns_response="$work_dir/dns-response.json"
        if [ "$INSTALL_TYPE" = "CLOUDFLARE_TUNNEL" ]; then
            dns_content="${TUNNEL_ID}.cfargotunnel.com"
            dns_proxied="true"
        else
            DOMINIO_PRINCIPAL=$(echo "$url_control" | cut -d'.' -f2-)
            [ -n "$nome_servidor" ] || nome_servidor=$(hostname -I | awk '{print $1}')
            dns_content="${nome_servidor}.${DOMINIO_PRINCIPAL}"
            dns_proxied="false"
        fi
        dns_payload=$(jq -nc \
            --arg name "$url_control" \
            --arg content "$dns_content" \
            --argjson proxied "$dns_proxied" \
            '{type:"CNAME",name:$name,content:$content,ttl:1,proxied:$proxied}')
        if ! curl -sS --get \
            "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records" \
            -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
            --data-urlencode "name=$url_control" >"$dns_lookup" 2>>"$install_log"; then
            fail_install 60 "ERRO AO CONSULTAR DNS" "Falha ao consultar o DNS $url_control no Cloudflare."
        fi
        dns_record_id=$(jq -r '.result[0].id // empty' "$dns_lookup")
        dns_record_type=$(jq -r '.result[0].type // empty' "$dns_lookup")
        if [ -n "$dns_record_id" ] && [ "$dns_record_type" != "CNAME" ]; then
            fail_install 61 "CONFLITO DE REGISTRO DNS" "Já existe um registro $dns_record_type para $url_control."
        fi
        if [ -n "$dns_record_id" ]; then
            dns_method="PUT"
            dns_url="https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records/${dns_record_id}"
        else
            dns_method="POST"
            dns_url="https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records"
        fi
        if ! curl -sS -X "$dns_method" "$dns_url" \
            -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
            -H "Content-Type: application/json" \
            --data "$dns_payload" >"$dns_response" 2>>"$install_log" ||
           [ "$(jq -r '.success // false' "$dns_response")" != "true" ]; then
            dns_error=$(jq -r '[.errors[]?.message] | join("; ")' "$dns_response" 2>/dev/null)
            fail_install 62 "ERRO AO CONFIGURAR DNS" "Cloudflare recusou o CNAME: ${dns_error:-resposta inválida da API}."
        fi
        echo "DNS confirmado: $url_control -> $dns_content" >>"$install_log"
    fi

    if [ "$INSTALL_TYPE" = "CLOUDFLARE_TUNNEL" ]; then
        echo -e "XXX\n73\nATUALIZANDO ROTA DO CLOUDFLARE TUNNEL... \nXXX"
        tunnel_raw="$work_dir/tunnel-raw.json"
        tunnel_payload="$work_dir/tunnel-payload.json"
        tunnel_response="$work_dir/tunnel-response.json"
        if ! curl -sS -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
            "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/cfd_tunnel/$TUNNEL_ID/configurations" \
            >"$tunnel_raw" 2>>"$install_log" ||
           [ "$(jq -r '.success // false' "$tunnel_raw")" != "true" ]; then
            fail_install 70 "ERRO AO CONSULTAR TUNNEL" "Não foi possível obter a configuração atual do Cloudflare Tunnel."
        fi
        if ! jq --arg host "$url_control" --arg service "http://${web_stack}_${web_service}:8080" '
            (.result.config // {}) as $cfg
            | ($cfg.ingress // [])
            | map(select(.service != "http_status:404" and .hostname != $host))
            + [{hostname:$host,service:$service,originRequest:{noTlsVerify:true,httpHostHeader:$host}},
               {service:"http_status:404"}]
            | {config:($cfg + {ingress:.})}
        ' "$tunnel_raw" >"$tunnel_payload" 2>>"$install_log"; then
            fail_install 71 "ERRO AO PREPARAR ROTA" "Falha ao preparar a nova rota do Cloudflare Tunnel."
        fi
        if ! curl -sS -X PUT \
            "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/cfd_tunnel/$TUNNEL_ID/configurations" \
            -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
            -H "Content-Type: application/json" \
            --data-binary @"$tunnel_payload" >"$tunnel_response" 2>>"$install_log" ||
           [ "$(jq -r '.success // false' "$tunnel_response")" != "true" ]; then
            tunnel_error=$(jq -r '[.errors[]?.message] | join("; ")' "$tunnel_response" 2>/dev/null)
            fail_install 72 "ERRO AO ATUALIZAR TUNNEL" "Cloudflare recusou a rota: ${tunnel_error:-resposta inválida da API}."
        fi
        echo "Rota confirmada: $url_control -> http://${web_stack}_${web_service}:8080" >>"$install_log"
    fi

    echo -e "XXX\n80\nPREPARANDO DEPLOY DAS TRÊS STACKS... \nXXX"
    if [ "$criar_portainer" = "0" ]; then
        dados_file="$HOME/dados_portainer/dados_portainer"
        [ -f "$dados_file" ] ||
            fail_install 80 "CREDENCIAIS DO PORTAINER NÃO ENCONTRADAS" "Arquivo não encontrado: $dados_file"
        PORTAINER_URL=$(grep "Dominio do portainer:" "$dados_file" | cut -d':' -f2- | xargs)
        ADMIN_USERNAME=$(grep "Usuario:" "$dados_file" | cut -d':' -f2- | xargs)
        ADMIN_PASSWORD=$(grep "Senha:" "$dados_file" | cut -d':' -f2- | xargs)
        [ -n "$PORTAINER_URL" ] && [ -n "$ADMIN_USERNAME" ] && [ -n "$ADMIN_PASSWORD" ] ||
            fail_install 81 "CREDENCIAIS DO PORTAINER INVÁLIDAS" "Domínio, usuário ou senha do Portainer não encontrado."

        auth_payload="$work_dir/portainer-auth-payload.json"
        auth_response="$work_dir/portainer-auth.json"
        if ! jq -nc --arg username "$ADMIN_USERNAME" --arg password "$ADMIN_PASSWORD" \
            '{username:$username,password:$password}' >"$auth_payload"; then
            fail_install 82 "ERRO AO PREPARAR AUTENTICAÇÃO" "Não foi possível preparar a autenticação segura do Portainer."
        fi
        if ! curl -sk -X POST "https://$PORTAINER_URL/api/auth" \
            -H "Content-Type: application/json" \
            --data-binary @"$auth_payload" \
            >"$auth_response" 2>>"$install_log"; then
            fail_install 82 "ERRO DE COMUNICAÇÃO COM PORTAINER" "Não foi possível acessar a API do Portainer."
        fi
        unset ADMIN_PASSWORD
        TOKEN=$(jq -r '.jwt // empty' "$auth_response")
        [ -n "$TOKEN" ] ||
            fail_install 83 "ERRO DE AUTENTICAÇÃO NO PORTAINER" "O Portainer não retornou token válido."
        endpoint_response="$work_dir/portainer-endpoints.json"
        if ! curl -sk "https://$PORTAINER_URL/api/endpoints" \
            -H "Authorization: Bearer $TOKEN" >"$endpoint_response" 2>>"$install_log"; then
            fail_install 84 "ERRO AO CONSULTAR ENDPOINT" "Falha ao consultar endpoints do Portainer."
        fi
        ENDPOINT_ID=$(jq -r '.[0].Id // empty' "$endpoint_response")
        [ -n "$ENDPOINT_ID" ] ||
            fail_install 85 "ENDPOINT NÃO ENCONTRADO" "Nenhum endpoint foi encontrado no Portainer."
        swarm_response="$work_dir/portainer-swarm.json"
        if ! curl -sk "https://$PORTAINER_URL/api/endpoints/$ENDPOINT_ID/docker/swarm" \
            -H "Authorization: Bearer $TOKEN" >"$swarm_response" 2>>"$install_log"; then
            fail_install 86 "ERRO AO CONSULTAR SWARM" "Falha ao consultar o Swarm pelo Portainer."
        fi
        SWARM_ID=$(jq -r '.ID // empty' "$swarm_response")
        [ -n "$SWARM_ID" ] ||
            fail_install 87 "SWARM NÃO ENCONTRADO" "O Portainer não retornou um Swarm ID válido."

        for image_ref in "$control_image" "$terminal_image"; do
            image_encoded=$(printf '%s' "$image_ref" | jq -sRr @uri)
            image_http=$(curl -sk -o "$work_dir/image-check.json" -w "%{http_code}" \
                "https://$PORTAINER_URL/api/endpoints/$ENDPOINT_ID/docker/images/$image_encoded/json" \
                -H "Authorization: Bearer $TOKEN" 2>>"$install_log")
            if [ "$image_http" != "200" ]; then
                fail_install 88 "IMAGEM LOCAL NÃO VISÍVEL NO PORTAINER" \
                    "A imagem '$image_ref' existe no Docker, mas não está visível no endpoint selecionado do Portainer (HTTP $image_http). Nenhum upload foi tentado."
            fi
        done

        create_portainer_stack() {
            local stack_name="$1" stack_file="$2" response_file="$work_dir/portainer-${1}.json" http_code
            http_code=$(curl -sk -o "$response_file" -w "%{http_code}" -X POST \
                -H "Authorization: Bearer $TOKEN" \
                -F "Name=$stack_name" \
                -F "file=@/root/$stack_file" \
                -F "SwarmID=$SWARM_ID" \
                -F "endpointId=$ENDPOINT_ID" \
                "https://$PORTAINER_URL/api/stacks/create/swarm/file" 2>>"$install_log")
            if ! [[ "$http_code" =~ ^[0-9]{3}$ ]] ||
               [ "$http_code" -lt 200 ] || [ "$http_code" -ge 300 ]; then
                portainer_error=$(jq -r '.message // empty' "$response_file" 2>/dev/null)
                [ -n "$portainer_error" ] || portainer_error=$(head -c 1500 "$response_file")
                printf 'Portainer recusou a stack %s (HTTP %s): %s\n' \
                    "$stack_name" "${http_code:-indisponível}" "${portainer_error:-sem detalhes}" >"$error_file"
                return 1
            fi
            echo "Stack criada no Portainer: $stack_name (HTTP $http_code)" >>"$install_log"
        }

        echo -e "XXX\n87\nCRIANDO TERMINAL NO PORTAINER... \nXXX"
        create_portainer_stack "$terminal_stack" "${terminal_stack}.yaml" ||
            fail_install 89 "ERRO NA STACK DO TERMINAL" "$(cat "$error_file")"
        echo -e "XXX\n90\nCRIANDO AGENTE NO PORTAINER... \nXXX"
        create_portainer_stack "$agent_stack" "${agent_stack}.yaml" ||
            fail_install 90 "ERRO NA STACK DO AGENTE" "$(cat "$error_file")"
        echo -e "XXX\n93\nCRIANDO PAINEL NO PORTAINER... \nXXX"
        create_portainer_stack "$web_stack" "${web_stack}.yaml" ||
            fail_install 91 "ERRO NA STACK DO PAINEL" "$(cat "$error_file")"
    else
        echo -e "XXX\n87\nCRIANDO TERMINAL NO DOCKER... \nXXX"
        docker stack deploy --prune --resolve-image never \
            -c "/root/${terminal_stack}.yaml" "$terminal_stack" >>"$install_log" 2>&1 ||
            fail_install 92 "ERRO NA STACK DO TERMINAL" "Falha ao publicar a stack do terminal no Docker."
        echo -e "XXX\n90\nCRIANDO AGENTE NO DOCKER... \nXXX"
        docker stack deploy --prune --resolve-image never \
            -c "/root/${agent_stack}.yaml" "$agent_stack" >>"$install_log" 2>&1 ||
            fail_install 93 "ERRO NA STACK DO AGENTE" "Falha ao publicar a stack do agente no Docker."
        echo -e "XXX\n93\nCRIANDO PAINEL NO DOCKER... \nXXX"
        docker stack deploy --prune --resolve-image never \
            -c "/root/${web_stack}.yaml" "$web_stack" >>"$install_log" 2>&1 ||
            fail_install 94 "ERRO NA STACK DO PAINEL" "Falha ao publicar a stack do painel no Docker."
    fi

    echo -e "XXX\n96\nAGUARDANDO OS SERVIÇOS... \nXXX"
    expected_services=(
        "${terminal_stack}_${terminal_service}"
        "${agent_stack}_${agent_service}"
        "${web_stack}_${web_service}"
    )
    for service_name in "${expected_services[@]}"; do
        ready="false"
        for _ in $(seq 1 30); do
            replicas=$(docker service ls --filter "name=$service_name" \
                --format '{{.Replicas}}' 2>>"$install_log" | head -n1)
            if [ "$replicas" = "1/1" ]; then
                ready="true"
                break
            fi
            sleep 3
        done
        if [ "$ready" != "true" ]; then
            {
                echo "O serviço não atingiu 1/1 réplica: $service_name"
                echo
                docker service ps "$service_name" --no-trunc \
                    --format 'Estado: {{.CurrentState}} | Erro: {{.Error}}' 2>/dev/null | head -n 8
            } >"$error_file"
            echo -e "XXX\n100\nSERVIÇO NÃO FICOU PRONTO\nXXX"
            exit 95
        fi
        echo "Serviço confirmado: $service_name com 1/1 réplica." >>"$install_log"
    done

    echo -e "XXX\n100\nCONTROL CENTER INSTALADO COM SUCESSO\nXXX"
} 2>>"$install_log" | whiptail --title "SETUP MNO CONTROL CENTER" --gauge \
    "Preparando o painel..." 8 78 0
install_status=${PIPESTATUS[0]}

if [ "$install_status" -ne 0 ]; then
    error_detail=$(cat "$error_file" 2>/dev/null)
    [ -n "$error_detail" ] || error_detail=$(tail -n 20 "$install_log" 2>/dev/null)
    whiptail --title "ERRO NA INSTALAÇÃO DO CONTROL CENTER" --scrolltext --msgbox \
        "A instalação foi interrompida com segurança.\n\n$error_detail\n\nLog completo: $install_log" \
        24 94
    exit "$install_status"
fi

manual_dns_note=""
if [ "$INSTALL_TYPE" = "TRADICIONAL" ] && [ "$criar_dns" = "1" ]; then
    manual_dns_note="\n\nDNS manual: aponte $url_control para o servidor antes de acessar."
fi

whiptail --title "SETUP MNO CONTROL CENTER" --msgbox \
    "Control Center instalado com sucesso.\n\nAcesse: https://$url_control\nUsuário: $usuario_control\nSenha: definida durante a instalação\n\nStacks:\n- $web_stack\n- $agent_stack\n- $terminal_stack\n\nAs imagens foram construídas localmente e validadas sem upload pelo Cloudflare.$manual_dns_note" \
    22 86

exit 0

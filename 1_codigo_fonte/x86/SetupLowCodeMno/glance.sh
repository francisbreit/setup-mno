#!/usr/bin/bash
# GLANCE PRO — dashboard self-hosted para feeds, serviços, notícias e produtividade.
set -o pipefail
umask 077

IMAGE_REF="glanceapp/glance:v0.8.5@sha256:32ab73d80f2b8b5fb0735b0431deb36b93fbb6b2fb43592449b0178c8b83e350"

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
    whiptail --title "GLANCE PRO" --msgbox "$1" 13 74
}

ask_required() {
    local prompt="$1" value status
    while true; do
        value=$(whiptail --title "GLANCE PRO" --inputbox "$prompt" 12 74 3>&1 1>&2 2>&3)
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
    local prompt="$1" value status
    while true; do
        value=$(whiptail --title "GLANCE PRO" --passwordbox "$prompt" 12 74 3>&1 1>&2 2>&3)
        status=$?
        [ "$status" -ne 0 ] && exit 0
        [ "${#value}" -ge 8 ] && {
            printf '%s' "$value"
            return
        }
        msg "A senha deve possuir pelo menos 8 caracteres."
    done
}

whiptail --title "GLANCE PRO" --yesno \
    "Instalar Glance como stack PRO?\n\nDashboard self-hosted para reunir feeds, pesquisas, favoritos, notícias, serviços e releases em uma única interface." \
    14 76 || exit 0

while true; do
    url_glance=$(ask_required "1/4 — Domínio do Glance (ex.: painel.seudominio.com):")
    if [[ "$url_glance" =~ ^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$ ]] &&
       [[ "$url_glance" == *.* ]]; then
        break
    fi
    msg "Informe somente o domínio, sem http://, https://, barras ou caminhos."
done

if [ "$INSTALL_TYPE" = "CLOUDFLARE_TUNNEL" ]; then
    route_check=$(mktemp)
    whiptail --title "GLANCE PRO" --infobox "Verificando se o domínio já possui uma rota no Cloudflare Tunnel..." 8 74
    if ! curl -sS -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
        "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/cfd_tunnel/$TUNNEL_ID/configurations" \
        >"$route_check" 2>/dev/null; then
        rm -f "$route_check"
        msg "Não foi possível consultar o Cloudflare Tunnel. Verifique as credenciais e tente novamente."
        exit 1
    fi
    existing_service=$(jq -r --arg host "$url_glance" \
        '.result.config.ingress[]? | select(.hostname == $host) | .service' "$route_check" 2>/dev/null | head -n1)
    rm -f "$route_check"
    if [ -n "$existing_service" ] && [ "$existing_service" != "null" ]; then
        msg "Já existe uma rota para:\n\n$url_glance\n\nServiço atual: $existing_service\n\nA rota será substituída pela nova instalação."
    fi
fi

while true; do
    usuario_glance=$(ask_required "2/4 — Usuário administrador do Glance:")
    if [[ "$usuario_glance" =~ ^[A-Za-z0-9_.-]+$ ]]; then
        break
    fi
    msg "Use somente letras, números, ponto, hífen ou sublinhado no usuário."
done

senha_glance=$(ask_password "3/4 — Senha do administrador (mínimo de 8 caracteres):")

while true; do
    criar_portainer=$(ask_required "4/4 — Criar Stack no Portainer?\n\n0 = editável no Portainer\n1 = direto no Docker")
    [[ "$criar_portainer" =~ ^[01]$ ]] && break
    msg "Digite somente 0 ou 1."
done

nome_principal="glance"
sufixo_app=$(date +%s%N | md5sum | head -c7)
nome_app="${nome_principal}${sufixo_app}"
config_dir="/root/${nome_app}_config"
assets_dir="/root/${nome_app}_assets"
auth_secret_name="${nome_app}_auth_secret"
password_secret_name="${nome_app}_admin_password"

dns_mode="Cloudflare Tunnel"
if [ "$INSTALL_TYPE" = "TRADICIONAL" ]; then
    if [ "$criar_dns" = "0" ]; then
        dns_mode="Tradicional com DNS automático"
    else
        dns_mode="Tradicional com DNS manual"
    fi
fi

whiptail --title "Confirmar instalação" --yesno \
    "Glance PRO\n\nDomínio: $url_glance\nAdministrador: $usuario_glance\nInstalação: $dns_mode\nStack: $([ "$criar_portainer" = "0" ] && echo "Portainer editável" || echo "Docker direto")\nArquiteturas: X86 e ARM\nRAM máxima: 256 MB" \
    19 78 || exit 0

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

    echo -e "XXX\n5\nVALIDANDO AMBIENTE... \nXXX"
    for required_command in docker curl jq base64; do
        command -v "$required_command" >/dev/null 2>&1 ||
            fail_install 10 "DEPENDÊNCIA NÃO ENCONTRADA" "O comando obrigatório '$required_command' não está instalado."
    done

    if [ ! -f "$CREDENTIALS_FILE" ]; then
        fail_install 11 "CREDENCIAIS NÃO ENCONTRADAS" "Arquivo de credenciais não encontrado: $CREDENTIALS_FILE"
    fi

    if [ "$INSTALL_TYPE" = "CLOUDFLARE_TUNNEL" ] ||
       { [ "$INSTALL_TYPE" = "TRADICIONAL" ] && [ "$criar_dns" = "0" ]; }; then
        if [ -z "$CLOUDFLARE_API_TOKEN" ] || [ -z "$CLOUDFLARE_ZONE_ID" ]; then
            fail_install 12 "CREDENCIAIS CLOUDFLARE INVÁLIDAS" "Token ou Zone ID do Cloudflare não encontrado nas credenciais."
        fi
    fi
    if [ "$INSTALL_TYPE" = "CLOUDFLARE_TUNNEL" ] &&
       { [ -z "$CLOUDFLARE_ACCOUNT_ID" ] || [ -z "$TUNNEL_ID" ]; }; then
        fail_install 13 "DADOS DO TUNNEL INVÁLIDOS" "Account ID ou Tunnel ID não encontrado nas credenciais."
    fi

    echo -e "XXX\n15\nBAIXANDO IMAGEM OFICIAL MULTI-ARQUITETURA... \nXXX"
    if ! docker pull "$IMAGE_REF" >>"$install_log" 2>&1; then
        {
            echo "Falha ao baixar a imagem oficial do Glance."
            echo
            tail -n 18 "$install_log"
        } >"$error_file"
        echo -e "XXX\n100\nERRO AO BAIXAR IMAGEM\nXXX"
        exit 20
    fi
    if ! docker image inspect --format \
        'Imagem: {{.Id}} | Arquitetura: {{.Architecture}} | Tamanho: {{.Size}} bytes' \
        "$IMAGE_REF" >>"$install_log" 2>&1; then
        fail_install 21 "IMAGEM NÃO ENCONTRADA" "A imagem foi baixada, mas não pôde ser confirmada no Docker."
    fi

    echo -e "XXX\n28\nCRIANDO CONFIGURAÇÃO PERSISTENTE... \nXXX"
    if ! mkdir -p "$config_dir" "$assets_dir" >>"$install_log" 2>&1; then
        fail_install 30 "ERRO AO CRIAR DIRETÓRIOS" "Não foi possível criar os diretórios persistentes do Glance."
    fi
    chmod 700 "$config_dir" "$assets_dir"

    auth_secret_reference='${secret:'"$auth_secret_name"'}'
    password_secret_reference='${secret:'"$password_secret_name"'}'

    cat >"$config_dir/glance.yml" <<EOL
server:
  proxied: true
  assets-path: /app/assets

auth:
  secret-key: $auth_secret_reference
  users:
    "$usuario_glance":
      password: $password_secret_reference

pages:
  - name: Início
    columns:
      - size: small
        widgets:
          - type: calendar
            first-day-of-week: monday

          - type: bookmarks
            groups:
              - title: Setup MNO
                links:
                  - title: Manual Negócio Online
                    url: https://manualnegocioonline.com.br
                  - title: Instalador Setup MNO
                    url: https://manualnegocioonline.com.br/instalador
                  - title: GitHub
                    url: https://github.com

      - size: full
        widgets:
          - type: search
            search-engine: duckduckgo
            new-tab: true
            autofocus: true
            placeholder: Pesquisar na web...

          - type: group
            widgets:
              - type: hacker-news
                collapse-after: 6
              - type: lobsters
                collapse-after: 6

          - type: to-do

      - size: small
        widgets:
          - type: releases
            cache: 1d
            show-source-icon: true
            repositories:
              - glanceapp/glance
              - portainer/portainer
              - traefik/traefik

          - type: markets
            markets:
              - symbol: BTC-USD
                name: Bitcoin
              - symbol: ETH-USD
                name: Ethereum
              - symbol: ^BVSP
                name: Ibovespa
EOL
    chmod 600 "$config_dir/glance.yml"
    : >"$assets_dir/user.css"
    chmod 600 "$assets_dir/user.css"

    echo -e "XXX\n40\nGERANDO E VALIDANDO SEGREDO OFICIAL... \nXXX"
    if ! auth_secret_value=$(docker run --rm "$IMAGE_REF" secret:make 2>>"$install_log"); then
        fail_install 31 "ERRO AO GERAR SEGREDO" "O gerador oficial do Glance não conseguiu criar o segredo de autenticação."
    fi
    if ! printf '%s' "$auth_secret_value" |
        base64 -d >"$work_dir/auth-secret-decoded" 2>>"$install_log"; then
        fail_install 32 "SEGREDO OFICIAL INVÁLIDO" "O segredo gerado pelo Glance não está em Base64 válido."
    fi
    auth_secret_bytes=$(wc -c <"$work_dir/auth-secret-decoded")
    rm -f "$work_dir/auth-secret-decoded"
    if [ "$auth_secret_bytes" -ne 64 ]; then
        fail_install 33 "TAMANHO DE SEGREDO INVÁLIDO" "O segredo oficial decodificado possui $auth_secret_bytes bytes; o Glance exige exatamente 64 bytes."
    fi
    printf '%s' "$auth_secret_value" >"$work_dir/$auth_secret_name"
    printf '%s' "validation-password" >"$work_dir/$password_secret_name"
    if ! docker run --rm \
        -v "$config_dir:/app/config:ro" \
        -v "$work_dir/$auth_secret_name:/run/secrets/$auth_secret_name:ro" \
        -v "$work_dir/$password_secret_name:/run/secrets/$password_secret_name:ro" \
        "$IMAGE_REF" config:print >"$work_dir/validated-glance.yml" 2>>"$install_log"; then
        {
            echo "A configuração inicial do Glance é inválida."
            echo
            tail -n 18 "$install_log"
        } >"$error_file"
        echo -e "XXX\n100\nERRO NA CONFIGURAÇÃO DO GLANCE\nXXX"
        exit 31
    fi

    echo -e "XXX\n50\nCRIANDO SEGREDOS DE AUTENTICAÇÃO... \nXXX"
    if ! printf '%s' "$auth_secret_value" |
        docker secret create "$auth_secret_name" - >>"$install_log" 2>&1; then
        fail_install 41 "ERRO AO CRIAR SEGREDO" "Não foi possível criar o segredo de autenticação no Docker Swarm."
    fi
    unset auth_secret_value

    if ! printf '%s' "$senha_glance" |
        docker secret create "$password_secret_name" - >>"$install_log" 2>&1; then
        fail_install 42 "ERRO AO CRIAR SENHA" "Não foi possível criar o segredo da senha administrativa no Docker Swarm."
    fi
    unset senha_glance

    echo -e "XXX\n60\nGERANDO STACK DO GLANCE... \nXXX"
    cd
    cd
    cat >"$nome_app.yaml" <<EOL

version: "3.7"
services:
  $nome_app:
    image: $IMAGE_REF
    hostname: $nome_app
    networks:
      - externa
      - interna
    volumes:
      - $config_dir:/app/config:ro
      - $assets_dir:/app/assets:ro
      - /etc/localtime:/etc/localtime:ro
    secrets:
      - $auth_secret_name
      - $password_secret_name
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
EOL

    if [ "$INSTALL_TYPE" = "TRADICIONAL" ]; then
        cat >>"$nome_app.yaml" <<EOL
      labels:
      - traefik.enable=true
      - traefik.docker.network=externa
      - traefik.http.routers.$nome_app.rule=Host(\`$url_glance\`)
      - traefik.http.routers.$nome_app.entrypoints=websecure
      - traefik.http.routers.$nome_app.priority=1
      - traefik.http.routers.$nome_app.tls.certresolver=letsencryptresolver
      - traefik.http.routers.$nome_app.tls=true
      - traefik.http.routers.$nome_app.service=$nome_app
      - traefik.http.services.$nome_app.loadbalancer.server.port=8080
EOL
    fi

    cat >>"$nome_app.yaml" <<EOL

networks:
  externa:
    external: true
  interna:
    external: true

secrets:
  $auth_secret_name:
    external: true
  $password_secret_name:
    external: true
EOL

    if ! docker stack config -c "/root/$nome_app.yaml" >"$work_dir/validated-stack.yaml" 2>>"$install_log"; then
        {
            echo "O YAML da stack Glance é inválido."
            echo
            tail -n 18 "$install_log"
        } >"$error_file"
        echo -e "XXX\n100\nERRO NO YAML DA STACK\nXXX"
        exit 50
    fi

    if [ "$INSTALL_TYPE" = "CLOUDFLARE_TUNNEL" ] ||
       { [ "$INSTALL_TYPE" = "TRADICIONAL" ] && [ "$criar_dns" = "0" ]; }; then
        echo -e "XXX\n70\nCONFIGURANDO DNS DE FORMA IDEMPOTENTE... \nXXX"
        dns_lookup="$work_dir/dns-lookup.json"
        dns_response="$work_dir/dns-response.json"
        if [ "$INSTALL_TYPE" = "CLOUDFLARE_TUNNEL" ]; then
            dns_content="${TUNNEL_ID}.cfargotunnel.com"
            dns_proxied="true"
        else
            DOMINIO_PRINCIPAL=$(echo "$url_glance" | cut -d'.' -f2-)
            [ -n "$nome_servidor" ] || nome_servidor=$(hostname -I | awk '{print $1}')
            dns_content="${nome_servidor}.${DOMINIO_PRINCIPAL}"
            dns_proxied="false"
        fi
        dns_payload=$(jq -nc \
            --arg name "$url_glance" \
            --arg content "$dns_content" \
            --argjson proxied "$dns_proxied" \
            '{type:"CNAME",name:$name,content:$content,ttl:1,proxied:$proxied}')

        if ! curl -sS --get \
            "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records" \
            -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
            --data-urlencode "name=$url_glance" >"$dns_lookup" 2>>"$install_log"; then
            fail_install 60 "ERRO AO CONSULTAR DNS" "Falha de comunicação ao consultar o DNS $url_glance no Cloudflare."
        fi
        dns_record_id=$(jq -r '.result[0].id // empty' "$dns_lookup")
        dns_record_type=$(jq -r '.result[0].type // empty' "$dns_lookup")
        if [ -n "$dns_record_id" ] && [ "$dns_record_type" != "CNAME" ]; then
            fail_install 61 "CONFLITO DE REGISTRO DNS" "Já existe um registro $dns_record_type para $url_glance. Ele não foi removido automaticamente."
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
        echo "DNS confirmado: $url_glance -> $dns_content" >>"$install_log"
    fi

    if [ "$INSTALL_TYPE" = "CLOUDFLARE_TUNNEL" ]; then
        echo -e "XXX\n80\nATUALIZANDO ROTA DO CLOUDFLARE TUNNEL... \nXXX"
        tunnel_raw="$work_dir/tunnel-raw.json"
        tunnel_payload="$work_dir/tunnel-payload.json"
        tunnel_response="$work_dir/tunnel-response.json"
        if ! curl -sS -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
            "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/cfd_tunnel/$TUNNEL_ID/configurations" \
            >"$tunnel_raw" 2>>"$install_log" ||
           [ "$(jq -r '.success // false' "$tunnel_raw")" != "true" ]; then
            fail_install 70 "ERRO AO CONSULTAR TUNNEL" "Não foi possível obter a configuração atual do Cloudflare Tunnel."
        fi
        if ! jq --arg host "$url_glance" --arg service "http://${nome_app}:8080" '
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
        echo "Rota confirmada: $url_glance -> http://${nome_app}:8080" >>"$install_log"
    fi

    echo -e "XXX\n86\nPUBLICANDO STACK... \nXXX"
    if [ "$criar_portainer" = "0" ]; then
        dados_file="$HOME/dados_portainer/dados_portainer"
        [ -f "$dados_file" ] ||
            fail_install 80 "CREDENCIAIS DO PORTAINER NÃO ENCONTRADAS" "Arquivo não encontrado: $dados_file"

        PORTAINER_URL=$(grep "Dominio do portainer:" "$dados_file" | cut -d':' -f2- | xargs)
        ADMIN_USERNAME=$(grep "Usuario:" "$dados_file" | cut -d':' -f2- | xargs)
        ADMIN_PASSWORD=$(grep "Senha:" "$dados_file" | cut -d':' -f2- | xargs)
        [ -n "$PORTAINER_URL" ] && [ -n "$ADMIN_USERNAME" ] && [ -n "$ADMIN_PASSWORD" ] ||
            fail_install 81 "CREDENCIAIS DO PORTAINER INVÁLIDAS" "Domínio, usuário ou senha do Portainer não encontrado."

        auth_response="$work_dir/portainer-auth.json"
        if ! curl -sk -X POST "https://$PORTAINER_URL/api/auth" \
            -H "Content-Type: application/json" \
            -d "{\"username\":\"$ADMIN_USERNAME\",\"password\":\"$ADMIN_PASSWORD\"}" \
            >"$auth_response" 2>>"$install_log"; then
            fail_install 82 "ERRO DE COMUNICAÇÃO COM PORTAINER" "Não foi possível acessar a API do Portainer."
        fi
        TOKEN=$(jq -r '.jwt // empty' "$auth_response")
        [ -n "$TOKEN" ] ||
            fail_install 83 "ERRO DE AUTENTICAÇÃO NO PORTAINER" "O Portainer não retornou um token de autenticação válido."

        endpoint_response="$work_dir/portainer-endpoints.json"
        if ! curl -sk "https://$PORTAINER_URL/api/endpoints" \
            -H "Authorization: Bearer $TOKEN" >"$endpoint_response" 2>>"$install_log"; then
            fail_install 84 "ERRO AO CONSULTAR ENDPOINT" "Falha ao consultar os endpoints do Portainer."
        fi
        ENDPOINT_ID=$(jq -r '.[0].Id // empty' "$endpoint_response")
        [ -n "$ENDPOINT_ID" ] ||
            fail_install 85 "ENDPOINT NÃO ENCONTRADO" "Nenhum endpoint foi encontrado no Portainer."

        swarm_response="$work_dir/portainer-swarm.json"
        if ! curl -sk "https://$PORTAINER_URL/api/endpoints/$ENDPOINT_ID/docker/swarm" \
            -H "Authorization: Bearer $TOKEN" >"$swarm_response" 2>>"$install_log"; then
            fail_install 86 "ERRO AO CONSULTAR SWARM" "Falha ao consultar o Docker Swarm pelo Portainer."
        fi
        SWARM_ID=$(jq -r '.ID // empty' "$swarm_response")
        [ -n "$SWARM_ID" ] ||
            fail_install 87 "SWARM NÃO ENCONTRADO" "O Portainer não retornou um Swarm ID válido."

        echo -e "XXX\n92\nCRIANDO STACK EDITÁVEL NO PORTAINER... \nXXX"
        portainer_response="$work_dir/portainer-stack.json"
        http_code=$(curl -sk -o "$portainer_response" -w "%{http_code}" -X POST \
            -H "Authorization: Bearer $TOKEN" \
            -F "Name=$nome_app" \
            -F "file=@/root/$nome_app.yaml" \
            -F "SwarmID=$SWARM_ID" \
            -F "endpointId=$ENDPOINT_ID" \
            "https://$PORTAINER_URL/api/stacks/create/swarm/file" 2>>"$install_log")
        if ! [[ "$http_code" =~ ^[0-9]{3}$ ]] ||
           [ "$http_code" -lt 200 ] || [ "$http_code" -ge 300 ]; then
            portainer_error=$(jq -r '.message // empty' "$portainer_response" 2>/dev/null)
            [ -n "$portainer_error" ] || portainer_error=$(head -c 2000 "$portainer_response")
            fail_install 88 "ERRO AO CRIAR STACK NO PORTAINER" "Portainer recusou a stack (HTTP ${http_code:-indisponível}): ${portainer_error:-sem detalhes}."
        fi
        echo "Stack criada no Portainer: $nome_app (HTTP $http_code)" >>"$install_log"
    else
        echo -e "XXX\n92\nCRIANDO STACK DIRETAMENTE NO DOCKER... \nXXX"
        if ! docker stack deploy --prune --resolve-image always \
            -c "/root/$nome_app.yaml" "$nome_app" >>"$install_log" 2>&1; then
            {
                echo "Falha ao publicar a stack diretamente no Docker."
                echo
                tail -n 18 "$install_log"
            } >"$error_file"
            echo -e "XXX\n100\nERRO AO CRIAR STACK NO DOCKER\nXXX"
            exit 89
        fi
    fi

    echo -e "XXX\n97\nAGUARDANDO O SERVIÇO FICAR PRONTO... \nXXX"
    service_name="${nome_app}_${nome_app}"
    ready="false"
    for _ in $(seq 1 20); do
        replicas=$(docker service ls --filter "name=$service_name" --format '{{.Replicas}}' 2>>"$install_log" | head -n1)
        if [ "$replicas" = "1/1" ]; then
            ready="true"
            break
        fi
        sleep 3
    done
    if [ "$ready" != "true" ]; then
        {
            echo "A stack foi criada, mas o serviço não atingiu 1/1 réplica."
            echo "Serviço esperado: $service_name"
            echo
            docker service ps "$service_name" --no-trunc \
                --format 'Estado: {{.CurrentState}} | Erro: {{.Error}}' 2>/dev/null | head -n 8
        } >"$error_file"
        echo -e "XXX\n100\nSERVIÇO NÃO FICOU PRONTO\nXXX"
        exit 90
    fi
    echo "Serviço confirmado: $service_name com 1/1 réplica." >>"$install_log"

    echo -e "XXX\n100\nGLANCE INSTALADO COM SUCESSO\nXXX"
} | whiptail --title "GLANCE PRO" --gauge "Preparando Glance..." 8 74 0
install_status=${PIPESTATUS[0]}

if [ "$install_status" -ne 0 ]; then
    error_detail=$(cat "$error_file" 2>/dev/null)
    [ -n "$error_detail" ] || error_detail=$(tail -n 18 "$install_log" 2>/dev/null)
    whiptail --title "ERRO NA INSTALAÇÃO DO GLANCE" --msgbox \
        "A instalação foi interrompida com segurança.\n\n$error_detail\n\nLog completo: $install_log" \
        24 92
    exit "$install_status"
fi

manual_dns_note=""
if [ "$INSTALL_TYPE" = "TRADICIONAL" ] && [ "$criar_dns" = "1" ]; then
    manual_dns_note="\n\nDNS manual: aponte $url_glance para o servidor antes de acessar."
fi

whiptail --title "GLANCE PRO" --msgbox \
    "Glance instalado com sucesso.\n\nAcesse: https://$url_glance\nUsuário: $usuario_glance\nSenha: definida durante a instalação\n\nStack: $nome_app\nConfiguração: $config_dir/glance.yml\nImagem oficial v0.8.5 fixada por digest.$manual_dns_note" \
    20 82

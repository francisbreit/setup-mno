#!/usr/bin/bash
# IT-TOOLS PRO — coleção leve de utilitários para desenvolvedores e profissionais de TI.
set -o pipefail

IMAGE_REF="corentinth/it-tools:nightly@sha256:f07d246567e1ceb65e29b0a2ea155a70d7b05e9a35cfc534a2eee7b1f53df64b"

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
    whiptail --title "IT-TOOLS PRO" --msgbox "$1" 13 74
}

ask_required() {
    local prompt="$1" value status
    while true; do
        value=$(whiptail --title "IT-TOOLS PRO" --inputbox "$prompt" 12 74 3>&1 1>&2 2>&3)
        status=$?
        [ "$status" -ne 0 ] && exit 0
        [ -n "$value" ] && {
            printf '%s' "$value"
            return
        }
        msg "Este campo é obrigatório."
    done
}

whiptail --title "IT-TOOLS PRO" --yesno \
    "Instalar IT-Tools como stack PRO?\n\nColeção de ferramentas para desenvolvedores, redes, conversores, criptografia e produtividade." \
    13 74 || exit 0

while true; do
    url_it_tools=$(ask_required "1/2 — Domínio do IT-Tools (ex.: ferramentas.seudominio.com):")
    if [[ "$url_it_tools" =~ ^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$ ]] &&
       [[ "$url_it_tools" == *.* ]]; then
        break
    fi
    msg "Informe somente o domínio, sem http://, https://, barras ou caminhos."
done

if [ "$INSTALL_TYPE" = "CLOUDFLARE_TUNNEL" ]; then
    route_check=$(mktemp)
    whiptail --title "IT-TOOLS PRO" --infobox "Verificando se o domínio já possui uma rota no Cloudflare Tunnel..." 8 74
    if ! curl -sS -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
        "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/cfd_tunnel/$TUNNEL_ID/configurations" \
        >"$route_check" 2>/dev/null; then
        rm -f "$route_check"
        msg "Não foi possível consultar o Cloudflare Tunnel. Verifique as credenciais e tente novamente."
        exit 1
    fi
    existing_service=$(jq -r --arg host "$url_it_tools" \
        '.result.config.ingress[]? | select(.hostname == $host) | .service' "$route_check" 2>/dev/null | head -n1)
    rm -f "$route_check"
    if [ -n "$existing_service" ] && [ "$existing_service" != "null" ]; then
        msg "Já existe uma rota para:\n\n$url_it_tools\n\nServiço atual: $existing_service\n\nA rota será substituída pela nova instalação."
    fi
fi

while true; do
    criar_portainer=$(ask_required "2/2 — Criar Stack no Portainer?\n\n0 = editável no Portainer\n1 = direto no Docker")
    [[ "$criar_portainer" =~ ^[01]$ ]] && break
    msg "Digite somente 0 ou 1."
done

nome_principal="ittools"
sufixo_app=$(date +%s%N | md5sum | head -c7)
nome_app="${nome_principal}${sufixo_app}"

dns_mode="Cloudflare Tunnel"
if [ "$INSTALL_TYPE" = "TRADICIONAL" ]; then
    if [ "$criar_dns" = "0" ]; then
        dns_mode="Tradicional com DNS automático"
    else
        dns_mode="Tradicional com DNS manual"
    fi
fi

whiptail --title "Confirmar instalação" --yesno \
    "IT-Tools PRO\n\nDomínio: $url_it_tools\nInstalação: $dns_mode\nStack: $([ "$criar_portainer" = "0" ] && echo "Portainer editável" || echo "Docker direto")\nArquiteturas: X86 e ARM\nRAM máxima: 256 MB" \
    17 76 || exit 0

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
    for required_command in docker curl jq; do
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

    echo -e "XXX\n18\nBAIXANDO IMAGEM OFICIAL MULTI-ARQUITETURA... \nXXX"
    if ! docker pull "$IMAGE_REF" >>"$install_log" 2>&1; then
        {
            echo "Falha ao baixar a imagem oficial do IT-Tools."
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

    echo -e "XXX\n35\nGERANDO STACK DO IT-TOOLS... \nXXX"
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
    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
        - node.role == manager
      resources:
        limits:
          cpus: "0.25"
          memory: 256M
EOL

    if [ "$INSTALL_TYPE" = "TRADICIONAL" ]; then
        cat >>"$nome_app.yaml" <<EOL
      labels:
      - traefik.enable=true
      - traefik.docker.network=externa
      - traefik.http.routers.$nome_app.rule=Host(\`$url_it_tools\`)
      - traefik.http.routers.$nome_app.entrypoints=websecure
      - traefik.http.routers.$nome_app.priority=1
      - traefik.http.routers.$nome_app.tls.certresolver=letsencryptresolver
      - traefik.http.routers.$nome_app.tls=true
      - traefik.http.routers.$nome_app.service=$nome_app
      - traefik.http.services.$nome_app.loadbalancer.server.port=80
EOL
    fi

    cat >>"$nome_app.yaml" <<EOL

networks:
  externa:
    external: true
  interna:
    external: true
EOL

    if ! docker stack config -c "/root/$nome_app.yaml" >"$work_dir/validated-stack.yaml" 2>>"$install_log"; then
        {
            echo "O YAML da stack IT-Tools é inválido."
            echo
            tail -n 18 "$install_log"
        } >"$error_file"
        echo -e "XXX\n100\nERRO NO YAML DA STACK\nXXX"
        exit 30
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
            DOMINIO_PRINCIPAL=$(echo "$url_it_tools" | cut -d'.' -f2-)
            [ -n "$nome_servidor" ] || nome_servidor=$(hostname -I | awk '{print $1}')
            dns_content="${nome_servidor}.${DOMINIO_PRINCIPAL}"
            dns_proxied="false"
        fi
        dns_payload=$(jq -nc \
            --arg name "$url_it_tools" \
            --arg content "$dns_content" \
            --argjson proxied "$dns_proxied" \
            '{type:"CNAME",name:$name,content:$content,ttl:1,proxied:$proxied}')

        if ! curl -sS --get \
            "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records" \
            -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
            --data-urlencode "name=$url_it_tools" >"$dns_lookup" 2>>"$install_log"; then
            fail_install 40 "ERRO AO CONSULTAR DNS" "Falha de comunicação ao consultar o DNS $url_it_tools no Cloudflare."
        fi
        dns_record_id=$(jq -r '.result[0].id // empty' "$dns_lookup")
        dns_record_type=$(jq -r '.result[0].type // empty' "$dns_lookup")
        if [ -n "$dns_record_id" ] && [ "$dns_record_type" != "CNAME" ]; then
            fail_install 41 "CONFLITO DE REGISTRO DNS" "Já existe um registro $dns_record_type para $url_it_tools. Ele não foi removido automaticamente."
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
            fail_install 42 "ERRO AO CONFIGURAR DNS" "Cloudflare recusou o CNAME: ${dns_error:-resposta inválida da API}."
        fi
        echo "DNS confirmado: $url_it_tools -> $dns_content" >>"$install_log"
    fi

    if [ "$INSTALL_TYPE" = "CLOUDFLARE_TUNNEL" ]; then
        echo -e "XXX\n65\nATUALIZANDO ROTA DO CLOUDFLARE TUNNEL... \nXXX"
        tunnel_raw="$work_dir/tunnel-raw.json"
        tunnel_payload="$work_dir/tunnel-payload.json"
        tunnel_response="$work_dir/tunnel-response.json"
        if ! curl -sS -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
            "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/cfd_tunnel/$TUNNEL_ID/configurations" \
            >"$tunnel_raw" 2>>"$install_log" ||
           [ "$(jq -r '.success // false' "$tunnel_raw")" != "true" ]; then
            fail_install 50 "ERRO AO CONSULTAR TUNNEL" "Não foi possível obter a configuração atual do Cloudflare Tunnel."
        fi
        if ! jq --arg host "$url_it_tools" --arg service "http://${nome_app}:80" '
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
            -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
            -H "Content-Type: application/json" \
            --data-binary @"$tunnel_payload" >"$tunnel_response" 2>>"$install_log" ||
           [ "$(jq -r '.success // false' "$tunnel_response")" != "true" ]; then
            tunnel_error=$(jq -r '[.errors[]?.message] | join("; ")' "$tunnel_response" 2>/dev/null)
            fail_install 52 "ERRO AO ATUALIZAR TUNNEL" "Cloudflare recusou a rota: ${tunnel_error:-resposta inválida da API}."
        fi
        echo "Rota confirmada: $url_it_tools -> http://${nome_app}:80" >>"$install_log"
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

        auth_response="$work_dir/portainer-auth.json"
        if ! curl -sk -X POST "https://$PORTAINER_URL/api/auth" \
            -H "Content-Type: application/json" \
            -d "{\"username\":\"$ADMIN_USERNAME\",\"password\":\"$ADMIN_PASSWORD\"}" \
            >"$auth_response" 2>>"$install_log"; then
            fail_install 62 "ERRO DE COMUNICAÇÃO COM PORTAINER" "Não foi possível acessar a API do Portainer."
        fi
        TOKEN=$(jq -r '.jwt // empty' "$auth_response")
        [ -n "$TOKEN" ] ||
            fail_install 63 "ERRO DE AUTENTICAÇÃO NO PORTAINER" "O Portainer não retornou um token de autenticação válido."

        endpoint_response="$work_dir/portainer-endpoints.json"
        if ! curl -sk "https://$PORTAINER_URL/api/endpoints" \
            -H "Authorization: Bearer $TOKEN" >"$endpoint_response" 2>>"$install_log"; then
            fail_install 64 "ERRO AO CONSULTAR ENDPOINT" "Falha ao consultar os endpoints do Portainer."
        fi
        ENDPOINT_ID=$(jq -r '.[0].Id // empty' "$endpoint_response")
        [ -n "$ENDPOINT_ID" ] ||
            fail_install 65 "ENDPOINT NÃO ENCONTRADO" "Nenhum endpoint foi encontrado no Portainer."

        swarm_response="$work_dir/portainer-swarm.json"
        if ! curl -sk "https://$PORTAINER_URL/api/endpoints/$ENDPOINT_ID/docker/swarm" \
            -H "Authorization: Bearer $TOKEN" >"$swarm_response" 2>>"$install_log"; then
            fail_install 66 "ERRO AO CONSULTAR SWARM" "Falha ao consultar o Docker Swarm pelo Portainer."
        fi
        SWARM_ID=$(jq -r '.ID // empty' "$swarm_response")
        [ -n "$SWARM_ID" ] ||
            fail_install 67 "SWARM NÃO ENCONTRADO" "O Portainer não retornou um Swarm ID válido."

        echo -e "XXX\n88\nCRIANDO STACK EDITÁVEL NO PORTAINER... \nXXX"
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
            fail_install 68 "ERRO AO CRIAR STACK NO PORTAINER" "Portainer recusou a stack (HTTP ${http_code:-indisponível}): ${portainer_error:-sem detalhes}."
        fi
        echo "Stack criada no Portainer: $nome_app (HTTP $http_code)" >>"$install_log"
    else
        echo -e "XXX\n88\nCRIANDO STACK DIRETAMENTE NO DOCKER... \nXXX"
        if ! docker stack deploy --prune --resolve-image always \
            -c "/root/$nome_app.yaml" "$nome_app" >>"$install_log" 2>&1; then
            {
                echo "Falha ao publicar a stack diretamente no Docker."
                echo
                tail -n 18 "$install_log"
            } >"$error_file"
            echo -e "XXX\n100\nERRO AO CRIAR STACK NO DOCKER\nXXX"
            exit 69
        fi
    fi

    echo -e "XXX\n96\nAGUARDANDO O SERVIÇO FICAR PRONTO... \nXXX"
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
        exit 70
    fi
    echo "Serviço confirmado: $service_name com 1/1 réplica." >>"$install_log"

    echo -e "XXX\n100\nIT-TOOLS INSTALADO COM SUCESSO\nXXX"
} | whiptail --title "IT-TOOLS PRO" --gauge "Preparando IT-Tools..." 8 74 0
install_status=${PIPESTATUS[0]}

if [ "$install_status" -ne 0 ]; then
    error_detail=$(cat "$error_file" 2>/dev/null)
    [ -n "$error_detail" ] || error_detail=$(tail -n 18 "$install_log" 2>/dev/null)
    whiptail --title "ERRO NA INSTALAÇÃO DO IT-TOOLS" --msgbox \
        "A instalação foi interrompida com segurança.\n\n$error_detail\n\nLog completo: $install_log" \
        24 92
    exit "$install_status"
fi

manual_dns_note=""
if [ "$INSTALL_TYPE" = "TRADICIONAL" ] && [ "$criar_dns" = "1" ]; then
    manual_dns_note="\n\nDNS manual: aponte $url_it_tools para o servidor antes de acessar."
fi

whiptail --title "IT-TOOLS PRO" --msgbox \
    "IT-Tools instalado com sucesso.\n\nAcesse: https://$url_it_tools\n\nStack: $nome_app\nImagem oficial fixada por digest.$manual_dns_note" \
    17 78

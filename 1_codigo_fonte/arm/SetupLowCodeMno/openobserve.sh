#!/usr/bin/bash
# OPENOBSERVE PRO — observabilidade unificada para logs, métricas e traces.
set -o pipefail
umask 077

OPENOBSERVE_IMAGE="public.ecr.aws/zinclabs/openobserve:v0.90.3@sha256:f77856199bff2097e0355d66e59d5792064ff8ff831ea5f580b3650fa5457136"
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
    whiptail --title "OPENOBSERVE PRO" --msgbox "$1" 16 86 1>&2
}

ask_required() {
    local prompt="$1" value status
    while true; do
        value=$(whiptail --title "OPENOBSERVE PRO" --inputbox "$prompt" 14 86 3>&1 1>&2 2>&3)
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
        first=$(whiptail --title "OPENOBSERVE PRO" --passwordbox \
            "Senha do administrador inicial.\n\nMínimo de 12 caracteres, com maiúscula, minúscula, número e símbolo." \
            15 86 3>&1 1>&2 2>&3)
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
        second=$(whiptail --title "OPENOBSERVE PRO" --passwordbox \
            "Repita a senha do administrador inicial:" 12 86 3>&1 1>&2 2>&3)
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

valid_email() {
    [[ "$1" =~ ^[A-Za-z0-9.!#%\&\'*+/=?^_\`{|}~-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]
}

whiptail --title "OPENOBSERVE PRO" --yesno \
    "Instalar OpenObserve PRO?\n\nPlataforma unificada de observabilidade para logs, métricas, traces, dashboards e alertas.\n\nEsta instalação usa o modo local de nó único com dados persistentes." \
    18 88 || exit 0

while true; do
    if ! url_openobserve=$(ask_required "1/4 — Domínio do OpenObserve (ex.: observe.seudominio.com):"); then exit 0; fi
    valid_domain "$url_openobserve" && break
    msg "Informe somente um domínio válido, sem http://, https://, barras ou caminhos."
done

while true; do
    if ! admin_email=$(ask_required "2/4 — E-mail do administrador inicial:"); then exit 0; fi
    valid_email "$admin_email" && break
    msg "Informe um endereço de e-mail válido. Ele será usado para entrar no OpenObserve."
done

if ! admin_password=$(ask_password); then exit 0; fi

while true; do
    if ! criar_portainer=$(ask_required "4/4 — Criar Stack no Portainer?\n\n0 = editável no Portainer\n1 = direta no Docker"); then
        unset admin_password
        exit 0
    fi
    [[ "$criar_portainer" =~ ^[01]$ ]] && break
    msg "Digite somente 0 ou 1."
done

nome_principal="openobserve"
sufixo_app=$(date +%s%N | md5sum | head -c7)
nome_app="${nome_principal}${sufixo_app}"
service_name="${nome_app}_openobserve"
health_service="${nome_app}_healthcheck"
data_dir="/root/${nome_app}_data"
app_yaml="/root/${nome_app}.yaml"

dns_mode="Cloudflare Tunnel"
if [ "$INSTALL_TYPE" = "TRADICIONAL" ]; then
    if [ "$criar_dns" = "0" ]; then dns_mode="Tradicional com DNS automático"; else dns_mode="Tradicional com DNS manual"; fi
fi

whiptail --title "Confirmar instalação" --yesno \
    "OpenObserve PRO v0.90.3\n\nPainel: https://$url_openobserve\nAdministrador: $admin_email\nAcesso: $dns_mode\nGestão: $([ "$criar_portainer" = "0" ] && echo "Stack editável no Portainer" || echo "Stack direta no Docker")\nArquiteturas: X86 e ARM\nRAM máxima: 2 GB\nPorta 5080: somente interna\nTelemetria anônima: desativada\nCredencial de bootstrap: removida após validação" \
    25 92 || { unset admin_password; exit 0; }

install_log="/tmp/${nome_app}-install.log"
error_file="/tmp/${nome_app}-error.log"
: >"$install_log"
: >"$error_file"

{
    work_dir=$(mktemp -d)
    bootstrap_yaml="$work_dir/bootstrap.yaml"
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
        echo "Executando rollback exclusivo do OpenObserve..." >>"$install_log"
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
        if [[ "$data_dir" == /root/openobserve*_data ]]; then rm -rf "$data_dir"; fi
        if [[ "$app_yaml" == /root/openobserve*.yaml ]]; then rm -f -- "$app_yaml"; fi
    }

    fail_install() {
        local code="$1" progress="$2" message="$3"
        unset admin_password bootstrap_password
        rollback_deployment
        printf '%s\n' "$message" >"$error_file"
        echo -e "XXX\n100\n$progress\nXXX"
        exit "$code"
    }

    write_stack_yaml() {
        local target="$1" include_credentials="$2" email_yaml="" password_yaml=""
        if [ "$include_credentials" = "true" ]; then
            email_yaml=$(jq -Rn --arg value "$admin_email" '$value') || return 1
            bootstrap_password=${admin_password//\$/\$\$}
            password_yaml=$(jq -Rn --arg value "$bootstrap_password" '$value') || return 1
        fi
        cat >"$target" <<EOYAML
version: "3.8"
services:
  openobserve:
    image: $OPENOBSERVE_IMAGE
    hostname: $nome_app
    user: "65532:65532"
    read_only: true
    cap_drop:
      - ALL
    security_opt:
      - no-new-privileges:true
    tmpfs:
      - /tmp:rw,noexec,nosuid,nodev,mode=1777
    environment:
      ZO_DATA_DIR: /data
      ZO_LOCAL_MODE: "true"
      ZO_LOCAL_MODE_STORAGE: disk
      ZO_WEB_URL: https://$url_openobserve
      ZO_COOKIE_SECURE_ONLY: "true"
      ZO_COOKIE_SAME_SITE_LAX: "true"
      ZO_TELEMETRY: "false"
      ZO_SWAGGER_ENABLED: "false"
      O2_ACTION_ENABLED: "false"
EOYAML
        if [ "$include_credentials" = "true" ]; then
            cat >>"$target" <<EOYAML
      ZO_ROOT_USER_EMAIL: $email_yaml
      ZO_ROOT_USER_PASSWORD: $password_yaml
EOYAML
        fi
        cat >>"$target" <<EOYAML
    volumes:
      - $data_dir:/data
    networks:
      - externa
      - interna
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
          cpus: "2.00"
          memory: 2G
        reservations:
          cpus: "0.10"
          memory: 256M
EOYAML
        if [ "$INSTALL_TYPE" = "TRADICIONAL" ]; then
            cat >>"$target" <<EOYAML
      labels:
        - traefik.enable=true
        - traefik.docker.network=externa
        - traefik.http.routers.$nome_app.rule=Host(\`$url_openobserve\`)
        - traefik.http.routers.$nome_app.entrypoints=websecure
        - traefik.http.routers.$nome_app.priority=1
        - traefik.http.routers.$nome_app.tls.certresolver=letsencryptresolver
        - traefik.http.routers.$nome_app.tls=true
        - traefik.http.routers.$nome_app.service=$nome_app
        - traefik.http.services.$nome_app.loadbalancer.server.port=5080
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
        local output="$work_dir/health.json" state result=1
        remove_health_service || return 1
        : >"$output"
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
            -fsS "http://$service_name:5080/healthz" >>"$install_log" 2>&1 || return 1

        for _ in $(seq 1 90); do
            state=$(docker service ps "$health_service" --format '{{.CurrentState}}' 2>>"$install_log" | head -n1)
            case "$state" in
                Complete*)
                    docker service logs --raw "$health_service" >"$output" 2>>"$install_log" &&
                        jq -e '.status == "ok"' "$output" >/dev/null 2>>"$install_log" && result=0
                    break
                    ;;
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

    echo -e "XXX\n15\nBAIXANDO IMAGENS OFICIAIS MULTI-ARQUITETURA...\nXXX"
    for image_ref in "$OPENOBSERVE_IMAGE" "$CURL_IMAGE"; do
        docker pull "$image_ref" >>"$install_log" 2>&1 ||
            fail_install 20 "ERRO AO BAIXAR IMAGEM" "Falha ao baixar a imagem oficial: $image_ref"
        docker image inspect "$image_ref" >>"$install_log" 2>&1 ||
            fail_install 21 "IMAGEM NÃO CONFIRMADA" "A imagem foi baixada, mas não pôde ser inspecionada: $image_ref"
    done

    echo -e "XXX\n25\nCRIANDO ARMAZENAMENTO PERSISTENTE RESTRITO...\nXXX"
    mkdir -p "$data_dir" >>"$install_log" 2>&1 ||
        fail_install 22 "ERRO AO CRIAR DADOS" "Não foi possível criar o diretório persistente $data_dir."
    chmod 700 "$data_dir"
    chown 65532:65532 "$data_dir" >>"$install_log" 2>&1 ||
        fail_install 23 "ERRO DE PERMISSÃO" "Não foi possível restringir os dados ao usuário não-root do OpenObserve."

    echo -e "XXX\n35\nGERANDO E VALIDANDO STACK DE BOOTSTRAP...\nXXX"
    write_stack_yaml "$bootstrap_yaml" true ||
        fail_install 24 "ERRO AO GERAR BOOTSTRAP" "Não foi possível preparar a inicialização segura do OpenObserve."
    write_stack_yaml "$app_yaml" false ||
        fail_install 25 "ERRO AO GERAR STACK" "Não foi possível preparar a stack final sem credenciais."
    docker stack config -c "$bootstrap_yaml" >"$work_dir/bootstrap-validated.yaml" 2>>"$install_log" ||
        fail_install 26 "YAML DE BOOTSTRAP INVÁLIDO" "O YAML de inicialização do OpenObserve não passou na validação do Docker."
    docker stack config -c "$app_yaml" >"$work_dir/final-validated.yaml" 2>>"$install_log" ||
        fail_install 27 "YAML FINAL INVÁLIDO" "O YAML final do OpenObserve não passou na validação do Docker."

    echo -e "XXX\n48\nPUBLICANDO BOOTSTRAP TEMPORÁRIO...\nXXX"
    if [ "$criar_portainer" = "0" ]; then
        portainer_login ||
            fail_install 30 "PORTAINER INDISPONÍVEL" "Não foi possível autenticar ou localizar o Docker Swarm no Portainer."
        portainer_response="$work_dir/portainer-create.json"
        http_code=$(curl -sk -o "$portainer_response" -w '%{http_code}' -X POST \
            -H "Authorization: Bearer $portainer_token" -F "Name=$nome_app" -F "file=@$bootstrap_yaml" \
            -F "SwarmID=$PORTAINER_SWARM_ID" -F "endpointId=$portainer_endpoint_id" \
            "https://$PORTAINER_URL/api/stacks/create/swarm/file" 2>>"$install_log")
        [[ "$http_code" =~ ^2[0-9][0-9]$ ]] ||
            fail_install 31 "PORTAINER RECUSOU A STACK" "O Portainer recusou o bootstrap do OpenObserve (HTTP ${http_code:-indisponível})."
        stack_created="true"
        portainer_stack_id=$(jq -r '.Id // .id // empty' "$portainer_response")
        [ -n "$portainer_stack_id" ] ||
            fail_install 32 "STACK SEM IDENTIFICADOR" "O Portainer criou a stack sem retornar um identificador válido."
    else
        docker stack deploy --prune --resolve-image always -c "$bootstrap_yaml" "$nome_app" >>"$install_log" 2>&1 ||
            fail_install 33 "DOCKER RECUSOU A STACK" "O Docker recusou o bootstrap do OpenObserve."
        stack_created="true"
    fi

    echo -e "XXX\n62\nAGUARDANDO API E CONFIRMANDO PERSISTÊNCIA...\nXXX"
    wait_replica 75 || {
        docker service ps "$service_name" --no-trunc >>"$install_log" 2>&1 || true
        docker service logs --raw --tail 100 "$service_name" >>"$install_log" 2>&1 || true
        fail_install 40 "OPENOBSERVE NÃO INICIOU" "O serviço $service_name não atingiu 1/1 réplica."
    }
    check_health || {
        docker service logs --raw --tail 100 "$service_name" >>"$install_log" 2>&1 || true
        fail_install 41 "API NÃO RESPONDEU" "O endpoint interno /healthz do OpenObserve não confirmou o estado saudável."
    }
    find "$data_dir" -type f -size +0c -print -quit | grep -q . ||
        fail_install 42 "PERSISTÊNCIA NÃO CONFIRMADA" "O OpenObserve iniciou, mas não gravou sua base no diretório persistente."

    echo -e "XXX\n74\nREMOVENDO CREDENCIAIS DE BOOTSTRAP DA STACK...\nXXX"
    unset admin_password bootstrap_password
    if [ "$criar_portainer" = "0" ]; then
        portainer_login ||
            fail_install 43 "PORTAINER INDISPONÍVEL" "Não foi possível autenticar no Portainer para remover as credenciais de bootstrap."
        update_payload="$work_dir/portainer-update.json"
        jq -n --rawfile stackFileContent "$app_yaml" \
            '{env:[],prune:true,pullImage:false,stackFileContent:$stackFileContent}' >"$update_payload"
        update_http=$(curl -sk -o "$work_dir/portainer-update-response.json" -w '%{http_code}' -X PUT \
            "https://$PORTAINER_URL/api/stacks/$portainer_stack_id?endpointId=$portainer_endpoint_id" \
            -H "Authorization: Bearer $portainer_token" -H 'Content-Type: application/json' \
            --data-binary @"$update_payload" 2>>"$install_log")
        [[ "$update_http" =~ ^2[0-9][0-9]$ ]] ||
            fail_install 44 "CREDENCIAL AINDA PRESENTE" "O Portainer recusou a reconciliação segura da stack."
    else
        docker stack deploy --prune --resolve-image always -c "$app_yaml" "$nome_app" >>"$install_log" 2>&1 ||
            fail_install 45 "CREDENCIAL AINDA PRESENTE" "O Docker recusou a stack final sem credenciais."
    fi
    wait_replica 75 && check_health ||
        fail_install 46 "RECONCILIAÇÃO NÃO CONVERGIU" "O OpenObserve não voltou saudável após remover as credenciais de bootstrap."
    if docker service inspect "$service_name" --format '{{range .Spec.TaskTemplate.ContainerSpec.Env}}{{println .}}{{end}}' 2>>"$install_log" |
        grep -q '^ZO_ROOT_USER_PASSWORD='; then
        fail_install 47 "SENHA EXPOSTA NO SERVIÇO" "A senha de bootstrap ainda aparece na especificação do serviço."
    fi

    if [ "$INSTALL_TYPE" = "CLOUDFLARE_TUNNEL" ] || { [ "$INSTALL_TYPE" = "TRADICIONAL" ] && [ "$criar_dns" = "0" ]; }; then
        echo -e "XXX\n86\nCONFIGURANDO DNS DE FORMA REVERSÍVEL...\nXXX"
        if [ "$INSTALL_TYPE" = "CLOUDFLARE_TUNNEL" ]; then
            dns_content="${TUNNEL_ID}.cfargotunnel.com"
            dns_proxied=true
        else
            dominio_principal=$(echo "$url_openobserve" | cut -d'.' -f2-)
            [ -n "$nome_servidor" ] || nome_servidor=$(hostname -I | awk '{print $1}')
            dns_content="${nome_servidor}.${dominio_principal}"
            dns_proxied=false
        fi
        curl -sS --get "https://api.cloudflare.com/client/v4/zones/$CLOUDFLARE_ZONE_ID/dns_records" \
            -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" --data-urlencode "name=$url_openobserve" \
            >"$work_dir/dns-lookup.json" 2>>"$install_log" ||
            fail_install 50 "ERRO AO CONSULTAR DNS" "Não foi possível consultar o DNS $url_openobserve."
        dns_record_id=$(jq -r '.result[0].id // empty' "$work_dir/dns-lookup.json")
        dns_record_type=$(jq -r '.result[0].type // empty' "$work_dir/dns-lookup.json")
        [ -z "$dns_record_id" ] || [ "$dns_record_type" = "CNAME" ] ||
            fail_install 51 "CONFLITO DE REGISTRO DNS" "Já existe um registro $dns_record_type para $url_openobserve; nada foi removido."
        jq -nc --arg name "$url_openobserve" --arg content "$dns_content" --argjson proxied "$dns_proxied" \
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
            fail_install 52 "ERRO AO CONFIGURAR DNS" "Falha de comunicação ao configurar o CNAME do OpenObserve."
        [ "$(jq -r '.success // false' "$work_dir/dns-response.json")" = "true" ] ||
            fail_install 53 "CLOUDFLARE RECUSOU O DNS" "A Cloudflare recusou o CNAME do OpenObserve."
        dns_record_id=$(jq -r '.result.id // empty' "$work_dir/dns-response.json")
        printf '%s' "$dns_record_id" >"$work_dir/dns-id"
        [ -s "$work_dir/dns-old.json" ] || : >"$work_dir/dns-created"
        dns_changed="true"
    fi

    if [ "$INSTALL_TYPE" = "CLOUDFLARE_TUNNEL" ]; then
        echo -e "XXX\n94\nATUALIZANDO ROTA DO CLOUDFLARE TUNNEL...\nXXX"
        curl -sS -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
            "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/cfd_tunnel/$TUNNEL_ID/configurations" \
            >"$work_dir/tunnel-original.json" 2>>"$install_log" ||
            fail_install 60 "ERRO AO CONSULTAR TUNNEL" "Não foi possível obter a configuração atual do Cloudflare Tunnel."
        [ "$(jq -r '.success // false' "$work_dir/tunnel-original.json")" = "true" ] ||
            fail_install 61 "TUNNEL RECUSOU CONSULTA" "A Cloudflare recusou a leitura da configuração do Tunnel."
        jq --arg host "$url_openobserve" --arg service "http://$service_name:5080" '
            (.result.config // {}) as $cfg
            | ($cfg.ingress // [])
            | map(select(.service != "http_status:404" and .hostname != $host))
            + [{hostname:$host,service:$service,originRequest:{httpHostHeader:$host}},
               {service:"http_status:404"}]
            | {config:($cfg + {ingress:.})}
        ' "$work_dir/tunnel-original.json" >"$work_dir/tunnel-payload.json" ||
            fail_install 62 "ERRO AO PREPARAR ROTA" "Não foi possível preparar a rota do OpenObserve."
        curl -sS -X PUT \
            "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/cfd_tunnel/$TUNNEL_ID/configurations" \
            -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" -H "Content-Type: application/json" \
            --data-binary @"$work_dir/tunnel-payload.json" >"$work_dir/tunnel-response.json" 2>>"$install_log" ||
            fail_install 63 "ERRO AO ATUALIZAR TUNNEL" "Falha de comunicação ao atualizar a rota do OpenObserve."
        [ "$(jq -r '.success // false' "$work_dir/tunnel-response.json")" = "true" ] ||
            fail_install 64 "TUNNEL RECUSOU A ROTA" "A Cloudflare recusou a rota do OpenObserve."
        route_updated="true"
    fi

    mkdir -p /root/dados_openobserve
    chmod 700 /root/dados_openobserve
    cat >"/root/dados_openobserve/${nome_app}" <<EODATA
OpenObserve PRO
Painel: https://$url_openobserve
Administrador: $admin_email
Stack: $nome_app
Dados: $data_dir
Imagem: $OPENOBSERVE_IMAGE
Modo: nó único com armazenamento local
EODATA
    chmod 600 "/root/dados_openobserve/${nome_app}"

    stack_created="false"
    route_updated="false"
    dns_changed="false"
    echo -e "XXX\n100\nOPENOBSERVE INSTALADO COM SUCESSO\nXXX"
} | whiptail --title "OPENOBSERVE PRO" --gauge "Preparando OpenObserve..." 8 86 0
install_status=${PIPESTATUS[0]}
unset admin_password

if [ "$install_status" -ne 0 ]; then
    error_detail=$(cat "$error_file" 2>/dev/null)
    [ -n "$error_detail" ] || error_detail=$(tail -n 20 "$install_log" 2>/dev/null)
    whiptail --title "ERRO NA INSTALAÇÃO DO OPENOBSERVE" --msgbox \
        "A instalação foi interrompida sem declarar falso sucesso.\n\n$error_detail\n\nLog completo: $install_log" \
        24 94
    exit "$install_status"
fi

manual_dns_note=""
if [ "$INSTALL_TYPE" = "TRADICIONAL" ] && [ "$criar_dns" = "1" ]; then
    manual_dns_note="\n\nDNS manual: aponte $url_openobserve para o servidor antes de acessar."
fi

whiptail --title "OPENOBSERVE PRO" --msgbox \
    "OpenObserve instalado com sucesso.\n\nAcesse: https://$url_openobserve\nAdministrador: $admin_email\nSenha: a definida durante a instalação\nStack: $nome_app\nDados persistentes: $data_dir\n\nAs credenciais de bootstrap foram removidas do YAML e da especificação do serviço. A porta 5080 não foi publicada no host.$manual_dns_note" \
    23 92

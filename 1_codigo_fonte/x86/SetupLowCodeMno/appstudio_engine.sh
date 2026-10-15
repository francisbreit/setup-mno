#!/usr/bin/env bash
# ==============================================================================
# Setup MNO App Studio [BETA] - Motor de Build & Deploy Swarm
# Mantenedor: Francis MNO (Setup MNO)
# Exclusividade: Planos PRO e PRO MASTER
# ==============================================================================

set -uo pipefail

# Cores e Formatação
VERMELHO='\033[0;31m'
VERDE='\033[0;32m'
AMARELO='\033[1;33m'
AZUL='\033[0;34m'
CIANO='\033[0;36m'
MAGENTA='\033[0;35m'
RESET='\033[0m'
BOLD='\033[1m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="${SETUPMNO_BASE_DIR:-$SCRIPT_DIR}"
BUILD_BASE_DIR="${SETUPMNO_BUILD_DIR:-/tmp/setupmno-appstudio-builds}"
REGISTRY_SCRIPT="$BASE_DIR/appstudio_registry.sh"
TUNNEL_SCRIPT="$BASE_DIR/appstudio_tunnel.sh"
IDENTIFIER="${APPSTUDIO_ID:-}"

log_info() {
    echo -e "${CIANO}[INFO]${RESET} $1" >&2
}

log_sucesso() {
    echo -e "${VERDE}[SUCESSO]${RESET} $1" >&2
}

log_aviso() {
    echo -e "${AMARELO}[AVISO]${RESET} $1" >&2
}

log_erro() {
    echo -e "${VERMELHO}[ERRO]${RESET} $1" >&2
}

log_header() {
    echo -e "\n${BOLD}${MAGENTA}================================================================${RESET}"
    echo -e "${BOLD}${CIANO}  🚀 SETUP MNO APP STUDIO [BETA] - Docker Swarm Deploy Engine${RESET}"
    echo -e "${BOLD}${MAGENTA}================================================================${RESET}\n"
}

# ------------------------------------------------------------------------------
# 1. Gate de Checagem de Plano (PRO / PRO MASTER)
# ------------------------------------------------------------------------------
validar_plano() {
    local plano="${1:-free}"
    plano="$(echo "$plano" | tr '[:upper:]' '[:lower:]')"

    if [[ "$plano" != "pro" && "$plano" != "promaster" && "$plano" != "pro-master" && "$plano" != "dev" ]]; then
        echo -e "${VERMELHO}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
        echo -e "${BOLD}${AMARELO}⚠️  RECURSO EXCLUSIVO: SETUP MNO APP STUDIO [BETA]${RESET}"
        echo -e "${VERMELHO}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
        echo -e "O módulo App Studio para deploy automático de aplicações IA (v0, Cursor, Lovable, Bolt)"
        echo -e "é uma funcionalidade exclusiva dos membros dos planos ${BOLD}PRO${RESET} e ${BOLD}PRO MASTER${RESET}."
        echo -e "\nPara desbloquear o deploy ilimitado de microsserviços e apps próprios na sua VPS:"
        echo -e "${CIANO}👉 https://manualnegocioonline.com.br/pro${RESET}"
        echo -e "${VERMELHO}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}\n"
        return 1
    fi
    log_sucesso "Licença validada: Plano ${BOLD}$(echo "$plano" | tr '[:lower:]' '[:upper:]')${RESET} autorizado."
    return 0
}

# ------------------------------------------------------------------------------
# 2. Gate de Ambiente Docker Swarm
# ------------------------------------------------------------------------------
validar_ambiente() {
    if ! command -v docker &> /dev/null; then
        log_erro "Docker não está instalado ou não foi encontrado no PATH."
        return 1
    fi

    local swarm_state
    swarm_state="$(docker info --format '{{.Swarm.LocalNodeState}}' 2>/dev/null || echo "inactive")"
    if [[ "$swarm_state" != "active" ]]; then
        log_erro "Docker Swarm não está ativo neste nó. Execute 'docker swarm init' antes."
        return 1
    fi

    # Valida rede interna
    if ! docker network inspect interna >/dev/null 2>&1; then
        log_aviso "Rede overlay 'interna' não encontrada. Criando rede 'interna'..."
        docker network create --driver overlay --attachable interna >/dev/null
    fi

    log_sucesso "Ambiente validado: Docker Swarm ativo e rede 'interna' pronta."
    return 0
}

# ------------------------------------------------------------------------------
# 3. Detecção Automática de Stack & Geração de Dockerfile
# ------------------------------------------------------------------------------
detectar_stack_e_preparar() {
    local app_dir="$1"
    local app_name="$2"
    local dockerfile_gerado="$app_dir/Dockerfile.appstudio"
    local detected_port="80"
    local stack_type="unknown"

    log_info "Analisando código-fonte em: $app_dir"

    # Prioridade 1: Dockerfile próprio do usuário
    if [[ -f "$app_dir/Dockerfile" ]]; then
        stack_type="custom_dockerfile"
        detected_port="80"
        local expose_port
        expose_port="$(grep -i "^EXPOSE " "$app_dir/Dockerfile" | head -n1 | awk '{print $2}' || true)"
        if [[ -n "$expose_port" ]]; then
            detected_port="$expose_port"
        fi
        log_sucesso "Detecção: Dockerfile existente encontrado. Porta inferida: $detected_port"
        cp "$app_dir/Dockerfile" "$dockerfile_gerado"

    # Prioridade 2: Aplicação Node.js (package.json)
    elif [[ -f "$app_dir/package.json" ]]; then
        stack_type="nodejs"
        detected_port="3000"
        log_sucesso "Detecção: Aplicação Node.js detectada (package.json)."

        cat << 'EOF' > "$dockerfile_gerado"
FROM node:20-alpine
WORKDIR /app
COPY package*.json ./
RUN npm install --production --silent || true
COPY . .
ENV PORT=3000
EXPOSE 3000
CMD ["npm", "start"]
EOF

    # Prioridade 3: Aplicação Python (requirements.txt ou main.py / app.py)
    elif [[ -f "$app_dir/requirements.txt" || -f "$app_dir/main.py" || -f "$app_dir/app.py" ]]; then
        stack_type="python"
        detected_port="8000"
        log_sucesso "Detecção: Aplicação Python detectada."

        local entrypoint="main.py"
        if [[ ! -f "$app_dir/main.py" && -f "$app_dir/app.py" ]]; then
            entrypoint="app.py"
        fi

        cat << EOF > "$dockerfile_gerado"
FROM python:3.11-slim
WORKDIR /app
COPY requirements*.txt ./
RUN if [ -f requirements.txt ] && [ -s requirements.txt ]; then pip install --no-cache-dir -r requirements.txt; fi
COPY . .
ENV PORT=8000
EXPOSE 8000
CMD ["python", "$entrypoint"]
EOF

    # Prioridade 4: Aplicação Estática (HTML / JS / CSS)
    elif [[ -f "$app_dir/index.html" ]]; then
        stack_type="static_nginx"
        detected_port="80"
        log_sucesso "Detecção: Aplicação Web Estática detectada (HTML5 / v0 / Bolt)."

        cat << 'EOF' > "$dockerfile_gerado"
FROM nginx:alpine
COPY . /usr/share/nginx/html
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
EOF

    else
        log_erro "Não foi possível identificar a stack do projeto em $app_dir."
        log_aviso "Dica: Forneça um Dockerfile, package.json, requirements.txt ou index.html."
        return 1
    fi

    echo "$stack_type|$detected_port|$dockerfile_gerado"
}

# ------------------------------------------------------------------------------
# 4. Detecção de Infraestrutura & Geração do Manifesto Swarm
# ------------------------------------------------------------------------------
detect_install_type() {
    if [[ -n "${SETUPMNO_INSTALL_TYPE:-}" ]]; then
        echo "$SETUPMNO_INSTALL_TYPE"
        return 0
    fi
    local type_file="/root/.cloudflared_config/installation_type"
    if [[ -f "$type_file" ]]; then
        cat "$type_file"
        return 0
    fi
    if docker service ls --filter "name=cloudflared_cloudflared" --format '{{.Replicas}}' 2>/dev/null | grep -q "1/1"; then
        echo "CLOUDFLARE_TUNNEL"
        return 0
    fi
    echo "TRADICIONAL"
}

gerar_stack_swarm() {
    local stack_file="$1"
    local service_name="$2"
    local image_tag="$3"
    local internal_port="$4"
    local cpu_limit="$5"
    local mem_limit="$6"
    local inject_postgres="$7"
    local inject_redis="$8"
    local install_type="${9:-CLOUDFLARE_TUNNEL}"
    local domain="${10:-none}"
    local extra_envs="${11:-}"

    local env_block="    environment:\n      - PORT=${internal_port}\n      - APP_NAME=${service_name}"
    
    if [[ "$inject_postgres" == "true" ]]; then
        local pg_pass="Vaiodv6740bR"
        if [[ -f "/root/postgres.yaml" ]]; then
            local extracted_pass
            extracted_pass=$(grep -oP '(?<=POSTGRES_PASSWORD=).+' /root/postgres.yaml 2>/dev/null | tr -d ' ' || true)
            [[ -n "$extracted_pass" ]] && pg_pass="$extracted_pass"
        fi
        local db_name="${service_name//-/_}_db"
        # Cria banco de dados no postgres se o container estiver ativo
        local pg_container
        pg_container=$(docker ps -qf name=postgres_postgres 2>/dev/null || docker ps -qf name=postgres 2>/dev/null || true)
        if [[ -n "$pg_container" ]]; then
            docker exec "$pg_container" psql -U postgres -d postgres -tc "SELECT 1 FROM pg_database WHERE datname = '$db_name'" 2>/dev/null | grep -q 1 || \
            docker exec "$pg_container" psql -U postgres -d postgres -c "CREATE DATABASE \"$db_name\";" >/dev/null 2>&1 || true
        fi

        # PACOTE UNIVERSAL POLYGLOT DE VARIÁVEIS DE BANCO DE DADOS:
        # Padrão 1: Connection URI (Prisma, TypeORM, Drizzle, Django, FastAPI, Supabase, Hasura, NocoDB)
        env_block="${env_block}\n      - DATABASE_URL=postgresql://postgres:${pg_pass}@postgres_postgres:5432/${db_name}"
        # Padrão 2: Variáveis desmembradas universais DB_* (Directus, Strapi, Typebot, Evolution API, Rocket.Chat)
        env_block="${env_block}\n      - DB_TYPE=postgres"
        env_block="${env_block}\n      - DB_ENGINE=postgres"
        env_block="${env_block}\n      - DB_HOST=postgres_postgres"
        env_block="${env_block}\n      - DB_PORT=5432"
        env_block="${env_block}\n      - DB_NAME=${db_name}"
        env_block="${env_block}\n      - DB_USER=postgres"
        env_block="${env_block}\n      - DB_PASSWORD=${pg_pass}"
        # Padrão 3: Variáveis desmembradas POSTGRES_* (Containers oficiais e microsserviços DevOps)
        env_block="${env_block}\n      - POSTGRES_HOST=postgres_postgres"
        env_block="${env_block}\n      - POSTGRES_PORT=5432"
        env_block="${env_block}\n      - POSTGRES_DB=${db_name}"
        env_block="${env_block}\n      - POSTGRES_USER=postgres"
        env_block="${env_block}\n      - POSTGRES_PASSWORD=${pg_pass}"
    fi

    if [[ "$inject_redis" == "true" ]]; then
        env_block="${env_block}\n      - REDIS_URL=redis://redis_redis:6379"
        env_block="${env_block}\n      - REDIS_HOST=redis_redis"
        env_block="${env_block}\n      - REDIS_PORT=6379"
    fi

    # Fingerprint inteligente: Metabase (Java / Clojure)
    if [[ "$image_tag" == *"metabase"* ]]; then
        env_block="${env_block}\n      - JAVA_TOOL_OPTIONS=-Xmx1024m -Xms256m -Dfile.encoding=UTF-8\n      - MB_JETTY_PORT=${internal_port}\n      - MB_JETTY_HOST=0.0.0.0"
        if [[ "$inject_postgres" == "true" ]]; then
            env_block="${env_block}\n      - MB_DB_TYPE=postgres\n      - MB_DB_DBNAME=${db_name}\n      - MB_DB_PORT=5432\n      - MB_DB_USER=postgres\n      - MB_DB_PASS=${pg_pass}\n      - MB_DB_HOST=postgres_postgres"
        fi
        if [[ -n "$domain" && "$domain" != "none" ]]; then
            local first_dom
            first_dom="$(echo "$domain" | cut -d',' -f1 | tr -d ' ')"
            [[ -n "$first_dom" ]] && env_block="${env_block}\n      - MB_SITE_URL=https://${first_dom}\n      - MB_REDIRECT_ALL_REQUESTS_TO_HTTPS=true"
        fi
    fi

    # Injeção de variáveis personalizadas adicionais fornecidas pelo usuário
    if [[ -n "$extra_envs" ]]; then
        local old_ifs="$IFS"
        IFS=',; ' read -ra ENVS_ARR <<< "$extra_envs"
        IFS="$old_ifs"
        for item in "${ENVS_ARR[@]}"; do
            item="$(echo "$item" | tr -d ' ')"
            [[ -z "$item" || "$item" != *"="* ]] && continue
            env_block="${env_block}\n      - ${item}"
        done
    fi

    local networks_block="    networks:\n      - interna\n      - externa"
    local top_networks_block="networks:\n  interna:\n    external: true\n  externa:\n    external: true"
    local labels_block=""

    # Se a instalação for TRADICIONAL (Traefik), injeta as labels padrão do Setup MNO
    if [[ "$install_type" == "TRADICIONAL" && "$domain" != "none" && -n "$domain" ]]; then
        
        # Formata regra para 1 ou múltiplos domínios (separados por vírgula)
        local old_ifs="$IFS"
        IFS=',' read -ra DOM_ARRAY <<< "$domain"
        IFS="$old_ifs"
        local joined_rule=""
        for d in "${DOM_ARRAY[@]}"; do
            d="$(echo "$d" | tr -d ' ')"
            if [[ -n "$d" && "$d" != "none" ]]; then
                if [[ -z "$joined_rule" ]]; then
                    joined_rule="Host(\`${d}\`)"
                else
                    joined_rule="${joined_rule} || Host(\`${d}\`)"
                fi
            fi
        done
        [[ -z "$joined_rule" ]] && joined_rule="Host(\`${domain}\`)"

        labels_block="    labels:
      - traefik.enable=true
      - traefik.docker.network=externa
      - traefik.http.routers.${service_name}.rule=${joined_rule}
      - traefik.http.routers.${service_name}.entrypoints=websecure
      - traefik.http.routers.${service_name}.priority=1
      - traefik.http.routers.${service_name}.tls.certresolver=letsencryptresolver
      - traefik.http.routers.${service_name}.tls=true
      - traefik.http.routers.${service_name}.service=${service_name}
      - traefik.http.services.${service_name}.loadbalancer.server.port=${internal_port}"
    fi

    cat << EOF > "$stack_file"
version: '3.8'

services:
  app:
    image: ${image_tag}
$(echo -e "$env_block")
$(echo -e "$networks_block")
$(if [[ -n "$labels_block" ]]; then echo "$labels_block"; fi)
    deploy:
      replicas: 1
      restart_policy:
        condition: on-failure
        delay: 5s
        max_attempts: 3
        window: 120s
      resources:
        limits:
          cpus: '${cpu_limit}'
          memory: ${mem_limit}
        reservations:
          cpus: '0.10'
          memory: 64M

$(echo -e "$top_networks_block")
EOF

    log_sucesso "Manifesto Swarm gerado com sucesso (${install_type}) em: $stack_file"
}

# ------------------------------------------------------------------------------
# 4.1 Deploy da Stack: Portainer API (Editável) ou Swarm CLI (Fallback / Direto)
# ------------------------------------------------------------------------------
deploy_stack_swarm_or_portainer() {
    local stack_name="$1"
    local stack_file="$2"
    local criar_portainer="${3:-0}"

    if [[ "$criar_portainer" == "0" ]]; then
        log_info "Tentando registrar e implantar stack editável no Portainer (${stack_name})..."
        local dados_file="${HOME:-/root}/dados_portainer/dados_portainer"
        [[ ! -f "$dados_file" ]] && dados_file="/root/dados_portainer/dados_portainer"

        if [[ -f "$dados_file" ]]; then
            local portainer_url admin_user admin_pass
            portainer_url=$(grep "Dominio do portainer:" "$dados_file" | cut -d':' -f2 | xargs)
            admin_user=$(grep "Usuario:" "$dados_file" | cut -d':' -f2 | xargs)
            admin_pass=$(grep "Senha:" "$dados_file" | cut -d':' -f2 | xargs)

            if [[ -n "$portainer_url" && -n "$admin_user" && -n "$admin_pass" ]]; then
                log_info "Autenticando na API do Portainer (https://${portainer_url})..."
                local auth_resp token
                auth_resp=$(curl -k -sS -m 10 -X POST "https://${portainer_url}/api/auth" \
                    -H "Content-Type: application/json" \
                    -d "{\"username\": \"$admin_user\", \"password\": \"$admin_pass\"}" 2>/dev/null || true)
                token=$(echo "$auth_resp" | jq -r '.jwt // empty' 2>/dev/null)

                if [[ -n "$token" && "$token" != "null" ]]; then
                    local endpoints_resp endpoint_id
                    endpoints_resp=$(curl -k -sS -m 10 -X GET "https://${portainer_url}/api/endpoints" \
                        -H "Authorization: Bearer $token" 2>/dev/null || true)
                    endpoint_id=$(echo "$endpoints_resp" | jq -r '.[0].Id // empty' 2>/dev/null)

                    if [[ -n "$endpoint_id" && "$endpoint_id" != "null" ]]; then
                        local swarm_resp swarm_id
                        swarm_resp=$(curl -k -sS -m 10 -X GET "https://${portainer_url}/api/endpoints/${endpoint_id}/docker/swarm" \
                            -H "Authorization: Bearer $token" 2>/dev/null || true)
                        swarm_id=$(echo "$swarm_resp" | jq -r '.ID // empty' 2>/dev/null)

                        if [[ -n "$swarm_id" && "$swarm_id" != "null" && -f "$stack_file" ]]; then
                            local resp_file err_file http_code
                            resp_file=$(mktemp)
                            err_file=$(mktemp)

                            http_code=$(curl -k -s -o "$resp_file" -w "%{http_code}" -m 30 -X POST \
                                -H "Authorization: Bearer $token" \
                                -F "Name=$stack_name" \
                                -F "file=@$stack_file" \
                                -F "SwarmID=$swarm_id" \
                                -F "endpointId=$endpoint_id" \
                                "https://${portainer_url}/api/stacks/create/swarm/file" 2>"$err_file" || echo "000")
                            rm -f "$resp_file" "$err_file"

                            if [[ "$http_code" -eq 200 ]]; then
                                log_sucesso "Stack '${stack_name}' registrada com sucesso no Portainer (100% Editável)!"
                                return 0
                            else
                                log_aviso "Portainer retornou código HTTP $http_code. Realizando fallback para Docker Swarm CLI..."
                            fi
                        fi
                    fi
                else
                    log_aviso "Falha na autenticação do Portainer. Realizando fallback para Docker Swarm CLI..."
                fi
            fi
        else
            log_aviso "Arquivo de credenciais do Portainer não encontrado ($dados_file). Realizando fallback para Docker Swarm CLI..."
        fi
    fi

    # Fallback seguro ou Opção 1 (não editável)
    log_info "Implantando stack via Docker Swarm CLI (${stack_name})..."
    docker stack deploy --prune --resolve-image always -c "$stack_file" "$stack_name" >/dev/null
    return 0
}

# ------------------------------------------------------------------------------
# 5. Fluxo Principal de Deploy
# ------------------------------------------------------------------------------
cmd_deploy() {
    local app_name=""
    local source_dir=""
    local docker_image=""
    local custom_port=""
    local domain=""
    local install_type=""
    local plan="pro"
    local inject_postgres="false"
    local inject_redis="false"
    local cpu_limit="0.50"
    local mem_limit="512M"
    local git_repo=""
    local git_branch="main"
    local git_token=""
    local criar_portainer="0"
    local extra_envs=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --name) app_name="$2"; shift 2 ;;
            --dir) source_dir="$2"; shift 2 ;;
            --image) docker_image="$2"; shift 2 ;;
            --git) git_repo="$2"; shift 2 ;;
            --git-branch) git_branch="$2"; shift 2 ;;
            --git-token) git_token="$2"; shift 2 ;;
            --port) custom_port="$2"; shift 2 ;;
            --domain) domain="$2"; shift 2 ;;
            --install-type) install_type="$2"; shift 2 ;;
            --plan) plan="$2"; shift 2 ;;
            --portainer) criar_portainer="$2"; shift 2 ;;
            --env|--envs)
                if [[ -z "$extra_envs" ]]; then
                    extra_envs="$2"
                else
                    extra_envs="${extra_envs},$2"
                fi
                shift 2 ;;
            --inject-postgres) inject_postgres="true"; shift ;;
            --inject-redis) inject_redis="true"; shift ;;
            --cpu) cpu_limit="$2"; shift 2 ;;
            --mem) mem_limit="$2"; shift 2 ;;
            *) log_erro "Parâmetro desconhecido: $1"; return 1 ;;
        esac
    done

    # Ajuste automático de memória para imagens Java/Metabase
    if [[ "$docker_image" == *"metabase"* && "$mem_limit" == "512M" ]]; then
        mem_limit="2048M"
    fi

    log_header

    # Sanitização do nome da aplicação
    if [[ -z "$app_name" ]]; then
        log_erro "Uso obrigatório: --name <nome-da-app> (--dir <caminho> OU --image <imagem-dockerhub> OU --git <url-do-repositorio>)"
        return 1
    fi

    if [[ -z "$source_dir" && -z "$docker_image" && -z "$git_repo" ]]; then
        log_erro "Informe a origem: --dir <pasta> OU --image <imagem-dockerhub:tag> OU --git <url-do-repositorio>"
        return 1
    fi

    # Validação do nome (apenas minúsculas, números e hífens)
    if [[ ! "$app_name" =~ ^[a-z0-9-]+$ ]]; then
        log_erro "Nome inválido ('$app_name'). Use apenas letras minúsculas, números e hífens."
        return 1
    fi

    # Gates de Plano e Ambiente
    validar_plano "$plan" || return 1
    validar_ambiente || return 1

    # Identificadores da Stack e Pastas
    local stack_name="${app_name}"
    [[ -n "$IDENTIFIER" ]] && stack_name="${IDENTIFIER}-${app_name}"
    local work_dir="$BUILD_BASE_DIR/$app_name"
    mkdir -p "$work_dir"

    # CASO GIT: Sincronização e clone do repositório
    if [[ -n "$git_repo" ]]; then
        local sacred_repo_dir="$("$REGISTRY_SCRIPT" path)/repos/$app_name"
        mkdir -p "$(dirname "$sacred_repo_dir")"

        local clone_url="$git_repo"
        if [[ -n "$git_token" ]]; then
            clone_url="${git_repo/https:\/\//https://${git_token}@}"
        fi

        if [[ -d "$sacred_repo_dir/.git" ]]; then
            log_info "Repositório Git já existe. Atualizando código (git pull)..."
            (cd "$sacred_repo_dir" && git checkout "$git_branch" 2>/dev/null && git pull origin "$git_branch") || {
                log_erro "Falha ao atualizar repositório Git existente."
                return 1
            }
            log_sucesso "Repositório Git atualizado com sucesso!"
        else
            log_info "Clonando repositório Git ($git_repo, branch: $git_branch)..."
            git clone -b "$git_branch" "$clone_url" "$sacred_repo_dir" > "$work_dir/git_clone.log" 2>&1 || {
                log_erro "Falha ao clonar repositório Git. Veja $work_dir/git_clone.log"
                tail -n 15 "$work_dir/git_clone.log"
                return 1
            }
            log_sucesso "Repositório Git clonado com sucesso!"
        fi
        source_dir="$sacred_repo_dir"
    fi

    # Detecção do tipo de instalação (TRADICIONAL vs CLOUDFLARE_TUNNEL)
    if [[ -z "$install_type" ]]; then
        install_type="$(detect_install_type)"
    fi
    log_info "Infraestrutura de Roteamento: ${BOLD}${install_type}${RESET}"

    log_info "Iniciando processamento para: ${BOLD}${app_name}${RESET}"
    log_info "Stack Swarm de isolamento: ${BOLD}${stack_name}${RESET}"

    local image_tag=""
    local final_port="80"
    local stack_type="custom"

    # CASO A: Imagem Pronta do Docker Hub / GHCR
    if [[ -n "$docker_image" ]]; then
        image_tag="$docker_image"
        stack_type="docker_hub_image"
        source_dir="docker_hub:$docker_image"
        final_port="${custom_port:-80}"

        log_info "Origem: Imagem Pronta do Docker Hub (${image_tag})"
        log_info "Baixando imagem oficial (docker pull)..."
        if ! docker pull "$image_tag" > "$work_dir/pull.log" 2>&1; then
            log_erro "Falha ao baixar imagem '$image_tag' do Docker Hub. Veja o log em $work_dir/pull.log"
            tail -n 15 "$work_dir/pull.log"
            return 1
        fi
        log_sucesso "Imagem baixada com sucesso do Docker Hub!"

    # CASO B: Código-Fonte Local / IA / Git (Build com Smart Dockerfile)
    else
        image_tag="mno-app/${app_name}:latest"
        [[ -n "$IDENTIFIER" ]] && image_tag="${IDENTIFIER}/${app_name}:latest"

        # Detecção
        local detection_result
        detection_result="$(detectar_stack_e_preparar "$source_dir" "$app_name")"
        local detected_port dockerfile_path

        stack_type="$(echo "$detection_result" | cut -d'|' -f1)"
        detected_port="$(echo "$detection_result" | cut -d'|' -f2)"
        dockerfile_path="$(echo "$detection_result" | cut -d'|' -f3)"

        final_port="${custom_port:-$detected_port}"

        # Build da Imagem Docker
        log_info "Compilando imagem Docker local (${image_tag})..."
        if ! docker build -f "$dockerfile_path" -t "$image_tag" "$source_dir" > "$work_dir/build.log" 2>&1; then
            log_erro "Falha no build da imagem Docker. Veja o log em: $work_dir/build.log"
            tail -n 20 "$work_dir/build.log"
            return 1
        fi
        log_sucesso "Build concluído com sucesso!"
    fi

    # Geração do manifesto Swarm (com suporte a Traefik SSL ou Cloudflare Tunnel)
    local stack_file="$work_dir/docker-compose.yml"
    gerar_stack_swarm "$stack_file" "$app_name" "$image_tag" "$final_port" "$cpu_limit" "$mem_limit" "$inject_postgres" "$inject_redis" "$install_type" "$domain" "$extra_envs"

    # Salva cópia na pasta raiz /root/${app_name}.yaml (e ${stack_name}.yaml se diferente)
    local root_yaml="/root/${app_name}.yaml"
    cp -f "$stack_file" "$root_yaml" 2>/dev/null || true
    if [[ "$stack_name" != "$app_name" ]]; then
        cp -f "$stack_file" "/root/${stack_name}.yaml" 2>/dev/null || true
    fi

    # Define manifesto prioritário para deploy
    local deploy_yaml="$stack_file"
    [[ -f "$root_yaml" && -r "$root_yaml" ]] && deploy_yaml="$root_yaml"

    # Deploy da Stack no Swarm (via API do Portainer se criar_portainer==0 ou CLI com fallback)
    deploy_stack_swarm_or_portainer "$stack_name" "$deploy_yaml" "$criar_portainer"

    # Aguardar convergência do serviço
    log_info "Aguardando o serviço convergir na rede 'interna'..."
    local tentativas=30
    local convergiu=0
    for ((i=1; i<=tentativas; i++)); do
        local replicas
        replicas="$(docker service ls --filter "name=${stack_name}_app" --format '{{.Replicas}}' 2>/dev/null || echo "")"
        if [[ "$replicas" == "1/1" ]]; then
            convergiu=1
            break
        fi
        sleep 2
    done

    if [[ "$convergiu" -eq 1 ]]; then
        log_sucesso "Serviço convergido com sucesso (1/1 réplicas ativas)!"
        echo -e "\n${BOLD}${VERDE}🎉 DEPLOY CONCLUÍDO COM SUCESSO!${RESET}"
        echo -e "• Aplicação:      ${BOLD}${app_name}${RESET}"
        echo -e "• Stack Swarm:    ${BOLD}${stack_name}${RESET}"
        echo -e "• Serviço Swarm:  ${BOLD}${stack_name}_app${RESET}"
        echo -e "• Imagem:         ${BOLD}${image_tag}${RESET}"
        echo -e "• Porta Interna:  ${BOLD}${final_port}${RESET}"
        echo -e "• Infra / Modo:   ${BOLD}${install_type}${RESET}"
        echo -e "• Arquivo YAML:   ${BOLD}/root/${app_name}.yaml${RESET}"
        echo -e "• Portainer:      ${BOLD}$([ "$criar_portainer" == "0" ] && echo "0 (Editável)" || echo "1 (Não editável)")${RESET}"
        echo -e "• Limite RAM:     ${BOLD}${mem_limit}${RESET} | CPU: ${BOLD}${cpu_limit}${RESET}"
        echo -e "• Rota DNS Swarm: ${BOLD}http://${stack_name}_app:${final_port}${RESET}\n"

        # Registra na pasta sagrada persistente
        "$REGISTRY_SCRIPT" register \
            "$app_name" "$stack_name" "$image_tag" "$stack_type" "$final_port" "${domain:-none}" \
            "$inject_postgres" "$inject_redis" "$cpu_limit" "$mem_limit" "$source_dir" "$install_type" \
            "${git_repo:-none}" "$git_branch" "$criar_portainer"
        
        # Salva o manifesto na pasta sagrada do app
        local sacred_app_dir
        sacred_app_dir="$("$REGISTRY_SCRIPT" path)/apps/$app_name"
        mkdir -p "$sacred_app_dir"
        cp -f "$stack_file" "$sacred_app_dir/docker-compose.yml"

        # Roteamento de domínios públicos (Multi-URL)
        if [[ -n "$domain" && "$domain" != "none" ]]; then
            if [[ "$install_type" == "CLOUDFLARE_TUNNEL" ]]; then
                log_info "Vinculando domínio(s) no Cloudflare Tunnel: $domain..."
                local old_ifs="$IFS"
                IFS=',' read -ra DOM_ARRAY <<< "$domain"
                IFS="$old_ifs"
                for d in "${DOM_ARRAY[@]}"; do
                    d="$(echo "$d" | tr -d ' ')"
                    [[ -z "$d" || "$d" == "none" ]] && continue
                    log_info "Configurando rota Cloudflare: $d -> ${stack_name}_app:${final_port}"
                    "$TUNNEL_SCRIPT" add "$d" "${stack_name}_app" "$final_port" "$app_name" || true
                done
            elif [[ "$install_type" == "TRADICIONAL" ]]; then
                log_info "Modo TRADICIONAL (Traefik): Roteamento SSL configurado no manifesto para: $domain"
                log_sucesso "O Traefik emitirá o certificado SSL Let's Encrypt automaticamente para: $domain"
            fi
        fi
    else
        log_aviso "O serviço foi criado, mas não atingiu status 1/1 saudável no tempo limite de inicialização."
        echo -e "\n${BOLD}${AMARELO}ℹ️ DICA SETUP MNO DEV-OPS:${RESET}"
        echo -e "• Algumas aplicações do Docker Hub realizam migrações longas ou exigem variáveis de ambiente específicas."
        echo -e "• Para checar os logs do container em tempo real:"
        echo -e "  ${CIANO}docker service logs -f ${stack_name}_app${RESET}"
        echo -e "• Para ajustar variáveis no Portainer (se criado como editável):"
        echo -e "  ${CIANO}Acesse Stacks > ${stack_name} > Editor${RESET}"
        echo -e "• Ou edite o arquivo no terminal: ${CIANO}/root/${app_name}.yaml${RESET}\n"
    fi

    return 0
}

# ------------------------------------------------------------------------------
# 6. Teste de Conectividade Interna (curl dentro da rede interna)
# ------------------------------------------------------------------------------
cmd_test() {
    local app_name="$1"
    local stack_name="${app_name}"
    [[ -n "$IDENTIFIER" ]] && stack_name="${IDENTIFIER}-${app_name}"
    local service_dns="${stack_name}_app"

    local port="80"
    local app_json
    app_json="$("$REGISTRY_SCRIPT" get "$app_name" 2>/dev/null || true)"
    if [[ -n "$app_json" ]]; then
        port="$(echo "$app_json" | jq -r '.internal_port // 80')"
    fi

    log_info "Testando resposta HTTP de ${service_dns}:${port} na rede 'interna' via container de probe..."

    local curl_output
    curl_output="$(docker run --rm --network interna curlimages/curl:8.5.0 -s -m 5 "http://${service_dns}:${port}" 2>&1 || true)"

    if [[ -n "$curl_output" ]]; then
        log_sucesso "Resposta recebida do serviço com sucesso!"
        echo -e "${CIANO}---------------- RESPOSTA HTTP ----------------${RESET}"
        echo "$curl_output" | head -n 25
        echo -e "${CIANO}-----------------------------------------------${RESET}"
        return 0
    else
        log_erro "Não foi possível obter resposta de http://${service_dns}:${port}."
        return 1
    fi
}

# ------------------------------------------------------------------------------
# 7. Limpeza e Destruição de Recursos
# ------------------------------------------------------------------------------
cmd_destroy() {
    local app_name="${1:-}"
    if [[ -z "$app_name" ]]; then
        log_erro "Uso obrigatório: $0 destroy <nome-da-app>"
        return 1
    fi

    log_info "Iniciando remoção da aplicação: $app_name..."

    local stack_name="${app_name}"
    [[ -n "$IDENTIFIER" ]] && stack_name="${IDENTIFIER}-${app_name}"
    local image_tag="mno-app/${app_name}:latest"
    [[ -n "$IDENTIFIER" ]] && image_tag="${IDENTIFIER}/${app_name}:latest"

    log_info "Removendo stack Swarm: $stack_name"
    docker stack rm "$stack_name" >/dev/null 2>&1 || true
    
    log_info "Removendo imagem Docker: $image_tag"
    docker rmi -f "$image_tag" >/dev/null 2>&1 || true
    
    # Remove manifesto na raiz /root se existir
    rm -f "/root/${app_name}.yaml" "/root/${stack_name}.yaml" 2>/dev/null || true

    "$REGISTRY_SCRIPT" unregister "$app_name" true || true
    log_sucesso "Aplicação $app_name removida com sucesso."
}

# ------------------------------------------------------------------------------
# 8. Rebuild e Atualização Contínua Zero-Downtime
# ------------------------------------------------------------------------------
cmd_rebuild() {
    local app_name="$1"
    if [[ -z "$app_name" ]]; then
        log_erro "Uso obrigatório: $0 rebuild <nome-da-app>"
        return 1
    fi

    log_header
    log_info "Iniciando Rebuild & Rolling Update Zero-Downtime para: ${BOLD}${app_name}${RESET}"

    local app_json
    app_json="$("$REGISTRY_SCRIPT" get "$app_name" 2>/dev/null || true)"
    if [[ -z "$app_json" ]]; then
        log_erro "Aplicação '$app_name' não encontrada no registro sagrado."
        return 1
    fi

    local stack_name image_tag runtime source_dir internal_port install_type git_repo git_branch
    stack_name="$(echo "$app_json" | jq -r '.stack_name')"
    image_tag="$(echo "$app_json" | jq -r '.image_tag')"
    runtime="$(echo "$app_json" | jq -r '.runtime')"
    source_dir="$(echo "$app_json" | jq -r '.source_dir')"
    internal_port="$(echo "$app_json" | jq -r '.internal_port')"
    install_type="$(echo "$app_json" | jq -r '.install_type // "CLOUDFLARE_TUNNEL"')"
    git_repo="$(echo "$app_json" | jq -r '.git.repo // "none"')"
    git_branch="$(echo "$app_json" | jq -r '.git.branch // "main"')"

    local work_dir="$BUILD_BASE_DIR/$app_name"
    mkdir -p "$work_dir"

    # CASO 1: Imagem do Docker Hub
    if [[ "$runtime" == "docker_hub_image" ]]; then
        log_info "Puxando versão mais recente da imagem oficial do Docker Hub: ${image_tag}..."
        if ! docker pull "$image_tag" > "$work_dir/rebuild_pull.log" 2>&1; then
            log_erro "Falha ao baixar imagem do Docker Hub."
            return 1
        fi
        log_sucesso "Imagem mais recente baixada com sucesso do Docker Hub!"

    # CASO 2: Projeto Git ou Código Local
    else
        if [[ "$git_repo" != "none" && -d "$source_dir/.git" ]]; then
            log_info "Atualizando código-fonte via Git ($git_branch)..."
            (cd "$source_dir" && git checkout "$git_branch" 2>/dev/null && git pull origin "$git_branch") || {
                log_aviso "Aviso ao executar git pull. Prosseguindo com build do código local atual..."
            }
        fi

        log_info "Re-compilando imagem Docker local ($image_tag)..."
        local detection_result
        detection_result="$(detectar_stack_e_preparar "$source_dir" "$app_name")"
        local detected_port dockerfile_path
        dockerfile_path="$(echo "$detection_result" | cut -d'|' -f3)"

        if ! docker build -f "$dockerfile_path" -t "$image_tag" "$source_dir" > "$work_dir/rebuild_build.log" 2>&1; then
            log_erro "Falha na compilação da imagem durante rebuild. Log em: $work_dir/rebuild_build.log"
            tail -n 20 "$work_dir/rebuild_build.log"
            return 1
        fi
        log_sucesso "Build da nova imagem concluído com sucesso!"
    fi

    # Rolling Update Zero-Downtime no Swarm
    log_info "Aplicando Rolling Update Zero-Downtime no serviço Swarm (${stack_name}_app)..."
    docker service update --image "$image_tag" --force "${stack_name}_app" >/dev/null

    # Aguardar convergência
    log_info "Aguardando novo container atingir estado saudável..."
    local tentativas=15
    local convergiu=0
    for ((i=1; i<=tentativas; i++)); do
        local replicas
        replicas="$(docker service ls --filter "name=${stack_name}_app" --format '{{.Replicas}}' 2>/dev/null || echo "")"
        if [[ "$replicas" == "1/1" ]]; then
            convergiu=1
            break
        fi
        sleep 2
    done

    if [[ "$convergiu" -eq 1 ]]; then
        log_sucesso "Rebuild & Rolling Update concluído com ZERO DOWNTIME! (1/1 réplicas ativas)"
        
        # Atualiza timestamp no registro sagrado
        local sacred_dir
        sacred_dir="$("$REGISTRY_SCRIPT" path)"
        python3 -c "
import json, datetime
registry_file = '$sacred_dir/registry.json'
with open(registry_file, 'r') as f:
    d = json.load(f)
if '$app_name' in d.get('apps', {}):
    d['apps']['$app_name']['last_deploy_at'] = datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')
with open(registry_file, 'w') as f:
    json.dump(d, f, indent=2)
"
    else
        log_aviso "O serviço foi atualizado, mas ainda está estabilizando réplicas."
    fi
}

# ------------------------------------------------------------------------------
# 9. Listar Apps Cadastrados no Registro Sagrado
# ------------------------------------------------------------------------------
cmd_list() {
    "$REGISTRY_SCRIPT" list
}

# ------------------------------------------------------------------------------
# Entrada CLI
# ------------------------------------------------------------------------------
case "${1:-help}" in
    deploy)
        shift
        cmd_deploy "$@"
        ;;
    rebuild)
        shift
        cmd_rebuild "$@"
        ;;
    test)
        shift
        cmd_test "$@"
        ;;
    list)
        shift
        cmd_list "$@"
        ;;
    destroy)
        shift
        cmd_destroy "$@"
        ;;
    *)
        echo "Uso: $0 {deploy|rebuild|test|list|destroy} [opções]"
        echo "Exemplo deploy local: $0 deploy --name meu-app --dir /caminho --plan pro"
        echo "Exemplo deploy git:   $0 deploy --name meu-app --git https://github.com/user/repo.git --plan pro"
        echo "Exemplo deploy hub:   $0 deploy --name meu-app --image usuario/imagem:tag --plan pro"
        echo "Exemplo rebuild:      $0 rebuild meu-app"
        echo "Exemplo lista:        $0 list"
        echo "Exemplo teste:        $0 test meu-app"
        echo "Exemplo destroy:      $0 destroy meu-app"
        ;;
esac

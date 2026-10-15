#!/usr/bin/env bash
# ==============================================================================
# Setup MNO App Studio [BETA] - Menu Interativo Whiptail (Terminal Seguro)
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
ENGINE_SCRIPT="$BASE_DIR/appstudio_engine.sh"
REGISTRY_SCRIPT="$BASE_DIR/appstudio_registry.sh"
TUNNEL_SCRIPT="$BASE_DIR/appstudio_tunnel.sh"
SACRED_DIR="$("$REGISTRY_SCRIPT" path 2>/dev/null || echo "/root/setupmno-appstudio")"
REGISTRY_FILE="$SACRED_DIR/registry.json"

# Estilo Clássico Whiptail Setup MNO
export NEWT_COLORS='
root=,white
border=black,gray
title=white,black
roottext=red,gray
window=red,gray
textbox=white,gray
button=white,green
compactbutton=white,black
listbox=black,white
actlistbox=white,black
actsellistbox=white,blue
checkbox=red,black
actcheckbox=white,blue
'

PLANO="${SETUPMNO_PLAN:-$(cat /root/.plan 2>/dev/null || echo "pro")}"

# ------------------------------------------------------------------------------
# 1. Validação de Plano com Paywall Gráfico
# ------------------------------------------------------------------------------
validar_plano_whiptail() {
    local p
    p="$(echo "$PLANO" | tr '[:upper:]' '[:lower:]')"

    if [[ "$p" != "pro" && "$p" != "promaster" && "$p" != "pro-master" && "$p" != "dev" ]]; then
        whiptail --title "🔒 RECURSO EXCLUSIVO PRO & PRO MASTER" --msgbox \
"O SETUP MNO APP STUDIO [BETA] é uma funcionalidade exclusiva dos membros dos planos PRO e PRO MASTER.

Com o App Studio, você pode:
• Fazer deploy a 1 clique de códigos gerados por IA (Cursor, Lovable, v0, Bolt)
• Sincronizar e atualizar repositórios Git (GitHub/GitLab) com Zero-Downtime
• Rodar imagens oficiais do Docker Hub com limites automáticos de CPU/RAM
• Conectar automaticamente ao PostgreSQL e Redis da VPS
• Roteamento seguro via Cloudflare Tunnel ou Traefik com SSL automático
• Zero consumo ocioso de memória na VPS.

Para fazer o upgrade e desbloquear este recurso na Hotmart:
👉 https://manualnegocioonline.com.br/pro

Pressione ENTER para voltar ao Menu Principal." 19 76
        return 1
    fi
    return 0
}

# ------------------------------------------------------------------------------
# 2. Submenu: Meus Apps Instalados (Lista Dinâmica)
# ------------------------------------------------------------------------------
menu_meus_apps() {
    while true; do
        if [[ ! -f "$REGISTRY_FILE" ]]; then
            whiptail --title "MEUS APPS INSTALADOS" --msgbox "Nenhuma aplicação registrada ainda no Setup MNO App Studio." 10 60
            return 0
        fi

        local total_apps
        total_apps="$(jq '.apps | length' "$REGISTRY_FILE" 2>/dev/null || echo "0")"

        if [[ "$total_apps" -eq 0 ]]; then
            whiptail --title "MEUS APPS INSTALADOS" --msgbox "Nenhuma aplicação registrada no Setup MNO App Studio até o momento.\n\nUtilize a opção 'NOVO DEPLOY DE APP' para criar seu primeiro Micro-SaaS!" 12 70
            return 0
        fi

        # Monta array de opções para o menu do Whiptail
        local menu_options=()
        while read -r app; do
            local runtime port stack_name
            runtime="$(jq -r ".apps[\"$app\"].runtime" "$REGISTRY_FILE")"
            port="$(jq -r ".apps[\"$app\"].internal_port" "$REGISTRY_FILE")"
            stack_name="$(jq -r ".apps[\"$app\"].stack_name" "$REGISTRY_FILE")"

            local service_name="${stack_name}_app"
            local replicas
            replicas="$(docker service ls --filter "name=${service_name}" --format '{{.Replicas}}' 2>/dev/null || echo "0/0")"

            local status_tag="[● ATIVO $replicas]"
            [[ "$replicas" != "1/1" ]] && status_tag="[○ INICIANDO $replicas]"

            menu_options+=("$app" "$status_tag $runtime :$port")
        done < <(jq -r '.apps | keys[]' "$REGISTRY_FILE")

        menu_options+=("VOLTAR" "🔙 Retornar ao menu anterior")

        local ESCOLHA_APP
        ESCOLHA_APP=$(whiptail --title "📦 MEUS APPS INSTALADOS ($total_apps)" \
            --menu "Selecione uma aplicação para gerenciar:" 20 76 10 \
            "${menu_options[@]}" 3>&1 1>&2 2>&3) || return 0

        [[ "$ESCOLHA_APP" == "VOLTAR" || -z "$ESCOLHA_APP" ]] && return 0

        gerenciar_aplicacao "$ESCOLHA_APP"
    done
}

# ------------------------------------------------------------------------------
# 3. Gerenciamento Individual da Aplicação Selecionada
# ------------------------------------------------------------------------------
gerenciar_aplicacao() {
    local app_name="$1"

    while true; do
        local app_json
        app_json="$(jq -r ".apps[\"$app_name\"]" "$REGISTRY_FILE" 2>/dev/null || echo "")"
        if [[ -z "$app_json" || "$app_json" == "null" ]]; then
            return 0
        fi

        local runtime port stack_name domain has_pg has_redis has_mysql
        runtime="$(echo "$app_json" | jq -r '.runtime')"
        port="$(echo "$app_json" | jq -r '.internal_port')"
        stack_name="$(echo "$app_json" | jq -r '.stack_name')"
        domain="$(echo "$app_json" | jq -r '.domain')"
        has_pg="$(echo "$app_json" | jq -r '.connections.postgres')"
        has_redis="$(echo "$app_json" | jq -r '.connections.redis')"
        has_mysql="$(echo "$app_json" | jq -r '.connections.mysql // false')"

        local service_name="${stack_name}_app"
        local replicas
        replicas="$(docker service ls --filter "name=${service_name}" --format '{{.Replicas}}' 2>/dev/null || echo "0/0")"

        local ACAO
        ACAO=$(whiptail --title "GERENCIAR: $app_name [● $replicas]" \
            --menu "Aplicação: $app_name | Runtime: $runtime | Porta: $port" 19 76 7 \
            "1" "📋 DETALHES & CONEXÕES  (Ver banco, limites, DNS e Git)" \
            "2" "📜 LOGS EM TEMPO REAL    (Ver logs do container no Swarm)" \
            "3" "🔄 REBUILD & ATUALIZAR   (Git pull / Docker pull + Zero-Downtime)" \
            "4" "♻️ REINICIAR SERVIÇO     (Forçar reinício limpo de container)" \
            "5" "🧪 TESTAR RESPOSTA HTTP  (Verificar probe interno 200 OK)" \
            "6" "🗑️ EXCLUIR APLICAÇÃO     (Desinstalar stack e remover)" \
            "7" "🔙 VOLTAR               (Retornar à lista de apps)" \
            3>&1 1>&2 2>&3) || return 0

        case "$ACAO" in
            1)
                local dbs=""
                [[ "$has_pg" == "true" ]] && dbs+="• PostgreSQL: Conectado (DATABASE_URL injetada)\n"
                [[ "$has_mysql" == "true" ]] && dbs+="• MySQL:      Conectado (MYSQL_URL injetada)\n"
                [[ "$has_redis" == "true" ]] && dbs+="• Redis:      Conectado (REDIS_URL injetada)\n"
                [[ -z "$dbs" ]] && dbs="• Nenhum banco conectado\n"

                local git_info
                git_info="$(echo "$app_json" | jq -r '.git.repo // "none"')"
                [[ "$git_info" != "none" ]] && git_info="• Repositório Git: $git_info (branch: $(echo "$app_json" | jq -r '.git.branch // "main"'))\n" || git_info=""

                local install_type_val
                install_type_val="$(echo "$app_json" | jq -r '.install_type // "CLOUDFLARE_TUNNEL"')"

                local portainer_info
                local is_portainer_edit
                is_portainer_edit="$(echo "$app_json" | jq -r '.portainer_editable // true')"
                if [[ "$is_portainer_edit" == "true" ]]; then
                    portainer_info="• Portainer:      Editável (Opção 0)\n"
                else
                    portainer_info="• Portainer:      Não editável (Opção 1)\n"
                fi

                whiptail --title "DETALHES: $app_name" --msgbox \
"Informações Técnicas da Aplicação:
--------------------------------------------------------
• Nome do App:    $app_name
• Stack Swarm:    $stack_name
• Serviço Swarm:  $service_name
• Réplicas:       $replicas
• Runtime / Tipo: $runtime
• Porta Interna:  $port
• Domínio(s):     ${domain:-Não vinculado}
• Infra / Modo:   $install_type_val
$portainer_info• Arquivo YAML:   /root/${app_name}.yaml
$git_info
Conexões de Banco de Dados:
$dbs
Pasta Persistente Sagrada:
$SACRED_DIR/apps/$app_name" 24 76
                ;;
            2)
                clear
                echo -e "${BOLD}${CIANO}========================================================================${RESET}"
                echo -e "📜 EXIBINDO LOGS AO VIVO DE: ${BOLD}$service_name${RESET}"
                echo -e "Pressione ${BOLD}Ctrl + C${RESET} a qualquer momento para voltar ao menu."
                echo -e "${BOLD}${CIANO}========================================================================${RESET}\n"
                docker service logs -f --tail 100 "$service_name" || true
                echo -e "\nPressione ENTER para retornar ao menu..."
                read -r
                ;;
            3)
                clear
                echo -e "${BOLD}${CIANO}========================================================================${RESET}"
                echo -e "🔄 REBUILD & ROLLING UPDATE ZERO-DOWNTIME: ${BOLD}$app_name${RESET}"
                echo -e "${BOLD}${CIANO}========================================================================${RESET}\n"
                "$ENGINE_SCRIPT" rebuild "$app_name" || true
                echo -e "\nPressione ENTER para retornar ao menu..."
                read -r
                ;;
            4)
                whiptail --title "REINICIANDO SERVIÇO" --infobox "Reiniciando o serviço $service_name no Docker Swarm..." 8 60
                docker service update --force "$service_name" >/dev/null 2>&1
                sleep 2
                whiptail --title "SUCESSO" --msgbox "O serviço $service_name foi reiniciado com sucesso no Docker Swarm!" 9 64
                ;;
            5)
                whiptail --title "TESTE DE CONECTIVIDADE" --infobox "Testando resposta HTTP de $service_name na porta $port..." 8 60
                local probe_res
                probe_res="$("$ENGINE_SCRIPT" test "$app_name" 2>&1 || echo "Falha ao obter resposta")"
                whiptail --title "RESULTADO DO TESTE HTTP" --msgbox "$probe_res" 18 74
                ;;
            6)
                if whiptail --title "⚠️ CONFIRMAÇÃO DE EXCLUSÃO" \
                    --yesno "Tem certeza que deseja DELETAR permanentemente a aplicação '$app_name'?\n\nIsso removerá o serviço do Docker Swarm e apagará os manifestos locais da aplicação." 12 70; then
                    
                    whiptail --title "REMOVENDO APLICAÇÃO" --infobox "Removendo stack $stack_name e expurgando registros..." 8 60
                    "$ENGINE_SCRIPT" destroy "$app_name" >/dev/null 2>&1
                    whiptail --title "APLICAÇÃO REMOVIDA" --msgbox "A aplicação '$app_name' foi completamente removida com sucesso." 9 60
                    return 0
                fi
                ;;
            7|*)
                return 0
                ;;
        esac
    done
}

# ------------------------------------------------------------------------------
# 4. Submenu: Novo Deploy de Aplicação (Git, Pasta Local ou Docker Hub)
# ------------------------------------------------------------------------------
menu_novo_deploy() {
    local TIPO_ORIGEM
    TIPO_ORIGEM=$(whiptail --title "➕ NOVO DEPLOY - SELECIONE A ORIGEM" \
        --menu "De onde virá o código da sua aplicação?" 16 72 3 \
        "1" "📂 PASTA LOCAL    (Código IA: v0, Cursor, Lovable, Bolt)" \
        "2" "🐙 REPOSITÓRIO GIT (GitHub / GitLab público ou privado)" \
        "3" "🐳 DOCKER HUB     (Imagens prontas oficiais do Docker Hub)" \
        3>&1 1>&2 2>&3) || return 0

    local APP_NAME
    APP_NAME=$(whiptail --title "➕ NOVO DEPLOY - NOME DO APP" \
        --inputbox "Digite o nome da sua nova aplicação (apenas letras minúsculas, números e hífen):\nExemplo: meu-saas, painel-admin, bot-vendas" 12 70 \
        "" 3>&1 1>&2 2>&3) || return 0

    if [[ -z "$APP_NAME" || ! "$APP_NAME" =~ ^[a-z0-9-]+$ ]]; then
        whiptail --title "ERRO NO NOME" --msgbox "Nome inválido! Use apenas letras minúsculas, números e hífens, sem espaços ou caracteres especiais." 10 66
        return 1
    fi

    local SOURCE_DIR=""
    local GIT_URL=""
    local GIT_BRANCH="main"
    local GIT_TOKEN=""
    local DOCKER_IMAGE=""
    local CUSTOM_PORT=""

    case "$TIPO_ORIGEM" in
        1)
            SOURCE_DIR=$(whiptail --title "📂 ORIGEM DO CÓDIGO DA IA" \
                --inputbox "Digite o caminho da pasta onde estão os arquivos do projeto gerado por IA:\nExemplo: /root/meus-apps/saas" 12 74 \
                "" 3>&1 1>&2 2>&3) || return 0

            if [[ -z "$SOURCE_DIR" || ! -d "$SOURCE_DIR" ]]; then
                whiptail --title "ERRO NO DIRETÓRIO" --msgbox "O diretório informado não existe ou não foi encontrado:\n$SOURCE_DIR" 10 66
                return 1
            fi
            ;;
        2)
            GIT_URL=$(whiptail --title "🐙 REPOSITÓRIO GIT" \
                --inputbox "Digite a URL HTTPS do repositório Git:\nExemplo: https://github.com/usuario/meu-app.git" 12 74 \
                "" 3>&1 1>&2 2>&3) || return 0

            if [[ -z "$GIT_URL" ]]; then
                whiptail --title "ERRO NO REPOSITÓRIO" --msgbox "A URL do repositório Git não pode ficar em branco." 10 66
                return 1
            fi

            GIT_BRANCH=$(whiptail --title "🐙 BRANCH DO REPOSITÓRIO" \
                --inputbox "Digite a branch do repositório (padrão: main):" 10 60 \
                "main" 3>&1 1>&2 2>&3) || GIT_BRANCH="main"

            GIT_TOKEN=$(whiptail --title "🔑 TOKEN PRIVADO (OPCIONAL)" \
                --inputbox "Se o repositório for PRIVADO, digite seu Personal Access Token (deixe em branco se for público):" 12 74 \
                "" 3>&1 1>&2 2>&3) || GIT_TOKEN=""
            ;;
        3)
            DOCKER_IMAGE=$(whiptail --title "🐳 IMAGEM DOCKER HUB" \
                --inputbox "Digite o nome da imagem Docker Hub:\nExemplo: traefik/whoami:latest ou n8nio/n8n:latest" 12 74 \
                "" 3>&1 1>&2 2>&3) || return 0

            if [[ -z "$DOCKER_IMAGE" ]]; then
                whiptail --title "ERRO NA IMAGEM" --msgbox "O nome da imagem Docker não pode ficar em branco." 10 66
                return 1
            fi

            CUSTOM_PORT=$(whiptail --title "🔌 PORTA INTERNA DA IMAGEM" \
                --inputbox "Digite a porta interna que a imagem escuta (ex: 80, 3000, 8080, 5678):" 10 60 \
                "80" 3>&1 1>&2 2>&3) || CUSTOM_PORT="80"
            ;;
    esac

    # Checklist de Bancos de Dados
    local DBS_SELECTED
    DBS_SELECTED=$(whiptail --title "CONECTAR BANCOS DE DADOS LOCAIS" \
        --checklist "Marque os bancos que deseja auto-injetar na sua aplicação (use a BARRA DE ESPAÇO):" 15 76 3 \
        "POSTGRES" "Banco PostgreSQL Corporativo (DATABASE_URL)" ON \
        "REDIS"    "Fila e Cache Redis em Memória (REDIS_URL)" OFF \
        "MYSQL"    "Banco MySQL 8.x / MariaDB (Opcional - Requer instalado)" OFF \
        3>&1 1>&2 2>&3) || return 0

    local INJECT_PG="false"
    local INJECT_REDIS="false"
    local INJECT_MYSQL="false"
    [[ "$DBS_SELECTED" == *"POSTGRES"* ]] && INJECT_PG="true"
    [[ "$DBS_SELECTED" == *"REDIS"* ]] && INJECT_REDIS="true"
    [[ "$DBS_SELECTED" == *"MYSQL"* ]] && INJECT_MYSQL="true"

    # Alerta didático caso o usuário marque MySQL mas o serviço não esteja ativo
    if [[ "$INJECT_MYSQL" == "true" ]]; then
        local mysql_ativo=false
        if docker service inspect mysql_mysql >/dev/null 2>&1 || docker service inspect mysql84_mysql84 >/dev/null 2>&1 || [ -n "$(docker ps -qf name=mysql 2>/dev/null | head -n1)" ]; then
            mysql_ativo=true
        fi
        if [[ "$mysql_ativo" != "true" ]]; then
            whiptail --title "ℹ️ MYSQL NÃO ENCONTRADO NO SERVIDOR" --msgbox \
"Atenção: O serviço do MySQL não está ativo nesta VPS no momento!\n\nLembre-se: o MySQL NÃO é uma ferramenta essencial pré-instalada (como o PostgreSQL e o Redis).\n\nO App Studio irá gerar todas as variáveis do MySQL prontas no manifesto (/root/${APP_NAME}.yaml), mas você precisará instalar o MySQL pelo menu do Setup MNO para que a aplicação consiga se comunicar." 15 74
        fi
    fi

    # Domínio Público HTTPS (Opcional - suporta multi-domínios separados por vírgula)
    local DOMAIN_INPUT
    DOMAIN_INPUT=$(whiptail --title "🌐 DOMÍNIO PÚBLICO HTTPS (OPCIONAL)" \
        --inputbox "Digite o(s) subdomínio(s) (separados por vírgula se mais de um):\nExemplo: saas.meusite.com.br,api.meusite.com.br" 12 74 \
        "" 3>&1 1>&2 2>&3) || DOMAIN_INPUT=""

    # Variáveis de Ambiente Personalizadas (Opcional)
    local EXTRA_ENVS=""
    EXTRA_ENVS=$(whiptail --title "⚙️ VARIÁVEIS ADICIONAIS (OPCIONAL)" \
        --inputbox "Deseja definir variáveis de ambiente personalizadas?\nExemplo: CHAVE=VALOR,OUTRA_CHAVE=VALOR\n\n(Deixe em branco se não houver ou se preferir configurar depois no Portainer):" 13 74 \
        "" 3>&1 1>&2 2>&3) || EXTRA_ENVS=""

    # Pergunta clássica do Portainer (0 = Editável no Portainer, 1 = Não poder editar)
    local CRIAR_PORTAINER="0"
    while true; do
        CRIAR_PORTAINER=$(whiptail --title "Criar Stack no Portainer? - 0 ou 1" \
            --inputbox "Digite 0 para poder editar stack no portainer ou 1 para não poder editar" \
            --fb 12 70 "0" 3>&1 1>&2 2>&3) || return 0
        if [[ "$CRIAR_PORTAINER" == "0" || "$CRIAR_PORTAINER" == "1" ]]; then
            break
        else
            whiptail --title "VALOR INVÁLIDO" --msgbox "Digite apenas o número 0 ou o número 1, para poder continuar.\n\n0 = Editar stack no Portainer\n1 = Não poder editar" 11 66
        fi
    done

    local portainer_status_str="0 (Editável)"
    [[ "$CRIAR_PORTAINER" == "1" ]] && portainer_status_str="1 (Não editável)"

    # Confirmação antes do build
    local envs_display="Padrão universal"
    [[ -n "$EXTRA_ENVS" ]] && envs_display="$EXTRA_ENVS"
    if ! whiptail --title "CONFIRMAR DEPLOY NO SWARM" \
        --yesno "Deseja iniciar o processamento e deploy da aplicação?\n\n• Nome: $APP_NAME\n• Auto-Injetar Postgres: $INJECT_PG (Polyglot)\n• Auto-Injetar MySQL: $INJECT_MYSQL (Polyglot)\n• Auto-Injetar Redis: $INJECT_REDIS\n• Domínio(s) HTTPS: ${DOMAIN_INPUT:-Nenhum no momento}\n• Variáveis Extras: $envs_display\n• Stack no Portainer: $portainer_status_str\n• Arquivo Raiz: /root/${APP_NAME}.yaml\n• Rede: interna / externa" 19 74; then
        return 0
    fi

    # Executa Deploy
    clear
    echo -e "${BOLD}${CIANO}========================================================================${RESET}"
    echo -e "🚀 INICIANDO DEPLOY DE: ${BOLD}$APP_NAME${RESET}"
    echo -e "${BOLD}${CIANO}========================================================================${RESET}\n"

    local deploy_args=(
        deploy
        --name "$APP_NAME"
        --plan "$PLANO"
    )
    [[ -n "$SOURCE_DIR" ]] && deploy_args+=(--dir "$SOURCE_DIR")
    [[ -n "$DOCKER_IMAGE" ]] && deploy_args+=(--image "$DOCKER_IMAGE")
    [[ -n "$CUSTOM_PORT" ]] && deploy_args+=(--port "$CUSTOM_PORT")
    [[ -n "$GIT_URL" ]] && deploy_args+=(--git "$GIT_URL" --git-branch "$GIT_BRANCH")
    [[ -n "$GIT_TOKEN" ]] && deploy_args+=(--git-token "$GIT_TOKEN")
    [[ -n "$DOMAIN_INPUT" ]] && deploy_args+=(--domain "$DOMAIN_INPUT")
    [[ -n "$EXTRA_ENVS" ]] && deploy_args+=(--env "$EXTRA_ENVS")
    [[ "$INJECT_PG" == "true" ]] && deploy_args+=(--inject-postgres)
    [[ "$INJECT_MYSQL" == "true" ]] && deploy_args+=(--inject-mysql)
    [[ "$INJECT_REDIS" == "true" ]] && deploy_args+=(--inject-redis)
    deploy_args+=(--portainer "$CRIAR_PORTAINER")

    if "$ENGINE_SCRIPT" "${deploy_args[@]}"; then
        echo -e "\n${BOLD}${VERDE}Pressione ENTER para voltar ao menu do App Studio...${RESET}"
        read -r
    else
        echo -e "\n${BOLD}${VERMELHO}Ocorreu uma falha no deploy. Pressione ENTER para retornar...${RESET}"
        read -r
    fi
}

# ------------------------------------------------------------------------------
# 5. Menu Principal do App Studio
# ------------------------------------------------------------------------------
appstudio_main_menu() {
    validar_plano_whiptail || return 0

    while true; do
        local total_apps="0"
        if [[ -f "$REGISTRY_FILE" ]]; then
            total_apps="$(jq '.apps | length' "$REGISTRY_FILE" 2>/dev/null || echo "0")"
        fi

        local ESCOLHA
        ESCOLHA=$(whiptail --title "🚀 SETUP MNO APP STUDIO [BETA] — PRO" \
            --menu "Central de Aplicações Próprias & Microsserviços IA ($total_apps apps ativos)" 19 76 6 \
            "1" "📦 MEUS APPS INSTALADOS     (Ver status, logs, reiniciar, rotas)" \
            "2" "➕ NOVO DEPLOY DE APP       (Publicar Git, Código IA ou Docker Hub)" \
            "3" "📋 LISTA EM MODO TEXTO      (Visualizar tabela completa no terminal)" \
            "4" "🌐 ROTAS CLOUDFLARE TUNNEL  (Visualizar subdomínios HTTPS ativos)" \
            "5" "🧹 LIMPEZA DE IMAGENS       (Remover imagens órfãs Docker)" \
            "6" "🔙 VOLTAR AO MENU PRINCIPAL (Retornar ao instalador seguro)" \
            3>&1 1>&2 2>&3) || return 0

        case "$ESCOLHA" in
            1)
                menu_meus_apps
                ;;
            2)
                menu_novo_deploy
                ;;
            3)
                clear
                "$REGISTRY_SCRIPT" list
                echo -e "Pressione ENTER para voltar ao menu..."
                read -r
                ;;
            4)
                clear
                "$TUNNEL_SCRIPT" list
                echo -e "Pressione ENTER para voltar ao menu..."
                read -r
                ;;
            5)
                whiptail --title "LIMPEZA DE IMAGENS" --infobox "Limpando imagens Docker órfãs..." 8 60
                docker image prune -f >/dev/null 2>&1
                whiptail --title "CONCLUÍDO" --msgbox "Imagens órfãs e não utilizadas foram removidas com sucesso." 8 60
                ;;
            6|*)
                return 0
                ;;
        esac
    done
}

# Executa menu se chamado diretamente
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    appstudio_main_menu
fi

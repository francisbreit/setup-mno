#!/usr/bin/bash
# ==============================================================================
# Setup MNO - Guardião de Rotas Cloudflare e Validação Resiliente de DNS
# ==============================================================================
# 1. Proteção de Rotas: Impede sobrescrita acidental de subdomínios já em uso.
# 2. Verificação Resiliente de DNS: Elimina falsos negativos aguardando a propagação
#    e consultando múltiplos servidores DNS rápidos (1.1.1.1, 8.8.8.8 e local)
#    mais probe HTTP direto.
# ==============================================================================

# Cache de hostnames já validados nesta sessão para evitar diálogos repetidos
declare -g -A SETUPMNO_GUARDED_HOSTNAMES 2>/dev/null || true

# Validação Resiliente de Resolução DNS
setupmno_check_dns() {
    local domain="$1"
    local max_attempts="${2:-8}"
    local attempt=1

    [ -n "$domain" ] || return 1

    # Sanitiza domínio (remove espaços, protocolo http/https, barras finais)
    domain=$(printf '%s' "$domain" | sed -e 's~^https\?://~~' -e 's~/.*$~~' | tr -d '[:space:]')
    [ -n "$domain" ] || return 1

    while [ "$attempt" -le "$max_attempts" ]; do
        # 1. Tenta resolver via DNS público 1.1.1.1 da Cloudflare (se nslookup existir)
        if command -v nslookup >/dev/null 2>&1; then
            if timeout 3 command nslookup "$domain" 1.1.1.1 >/dev/null 2>&1; then
                return 0
            fi
            if timeout 3 command nslookup "$domain" 8.8.8.8 >/dev/null 2>&1; then
                return 0
            fi
            if timeout 3 command nslookup "$domain" >/dev/null 2>&1; then
                return 0
            fi
        fi

        # 2. Tenta resolver via DNS-over-HTTPS da Cloudflare (1.1.1.1) via curl (funciona em containers sem nslookup)
        if curl -s -f --connect-timeout 2 --max-time 3 -H "accept: application/dns-json" "https://1.1.1.1/dns-query?name=${domain}" 2>/dev/null | grep -q '"Answer"'; then
            return 0
        fi

        # 3. Tenta resolver via DNS-over-HTTPS do Google via curl
        if curl -s -f --connect-timeout 2 --max-time 3 "https://dns.google/resolve?name=${domain}" 2>/dev/null | grep -q '"Answer"'; then
            return 0
        fi

        # 4. Tenta resolver via getent local do sistema
        if getent hosts "$domain" >/dev/null 2>&1; then
            return 0
        fi

        # 5. Tenta probe HTTP direto (se a Cloudflare já estiver respondendo pelo proxy, o DNS já propagou)
        if curl -s -k --connect-timeout 2 --max-time 3 -o /dev/null -I "https://$domain" 2>/dev/null; then
            return 0
        fi

        sleep 2
        attempt=$((attempt + 1))
    done

    return 1
}

# Wrapper para chamadas existentes de nslookup nos scripts legados
# Qualquer chamada como 'if nslookup "$url" >/dev/null 2>&1; then' se torna resiliente!
nslookup() {
    # Se chamada com apenas 1 argumento de hostname sem flags (ex: nslookup "$url_mautic")
    if [ "$#" -eq 1 ] && [[ "$1" =~ ^[a-zA-Z0-9.-]+$ ]] && [[ "$1" == *.* ]] && [[ "$1" != -* ]]; then
        setupmno_check_dns "$1" 8
    elif command -v nslookup >/dev/null 2>&1; then
        command nslookup "$@"
    else
        setupmno_check_dns "$1" 8
    fi
}
export -f setupmno_check_dns 2>/dev/null || true
export -f nslookup 2>/dev/null || true

# Guardião de Rotas: Checa se o subdomínio já existe na conta Cloudflare
setupmno_guard_route() {
    local hostname="$1"
    [ -n "$hostname" ] || return 0

    # Sanitiza o hostname
    hostname=$(printf '%s' "$hostname" | sed -e 's~^https\?://~~' -e 's~/.*$~~' | tr -d '[:space:]')
    [ -n "$hostname" ] || return 0

    # Se já foi validado nesta execução e aprovado, não pergunta novamente
    if [ "${SETUPMNO_GUARDED_HOSTNAMES[$hostname]:-0}" = "1" ]; then
        return 0
    fi

    # Só se aplica ao modo Cloudflare Tunnel
    local inst_type="${INSTALL_TYPE:-}"
    if [ -z "$inst_type" ] && [ -f /root/.cloudflared_config/installation_type ]; then
        inst_type=$(cat /root/.cloudflared_config/installation_type 2>/dev/null || echo "TRADICIONAL")
    fi
    [ "$inst_type" = "CLOUDFLARE_TUNNEL" ] || return 0

    # Carrega credenciais da Cloudflare se não estiverem no ambiente
    if [ -z "${CLOUDFLARE_API_TOKEN:-}" ]; then
        local cred_file="${SETUPMNO_CLOUDFLARE_CREDENTIALS_FILE:-/root/.cloudflared_config/cloudflare_credentials}"
        if [ -f "$cred_file" ]; then
            # shellcheck disable=SC1090
            source "$cred_file"
        fi
    fi

    [ -n "${CLOUDFLARE_API_TOKEN:-}" ] || return 0
    [ -n "${CLOUDFLARE_ZONE_ID:-}" ] || return 0

    # Consulta registros DNS na Cloudflare para o hostname solicitado
    local dns_resp count=0
    dns_resp=$(curl -sS --connect-timeout 8 --max-time 20 \
        "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records?name=${hostname}" \
        -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
        -H "Content-Type: application/json" 2>/dev/null || echo "{}")

    if jq -e '.success == true' <<< "$dns_resp" >/dev/null 2>&1; then
        count=$(jq '.result | length' <<< "$dns_resp" 2>/dev/null || echo "0")
    fi

    # Se count == 0, o hostname está livre na zona DNS!
    if [ "$count" -eq 0 ]; then
        SETUPMNO_GUARDED_HOSTNAMES[$hostname]=1
        return 0
    fi

    # Se count > 0, o hostname já existe! Exibe o diálogo do Whiptail com VOLTAR ou SOBRESCREVER
    local dns_type dns_target choice
    dns_type=$(jq -r '.result[0].type // "desconhecido"' <<< "$dns_resp" 2>/dev/null)
    dns_target=$(jq -r '.result[0].content // "desconhecido"' <<< "$dns_resp" 2>/dev/null)

    # Preparação para Whiptail com suporte a TTY
    if command -v whiptail >/dev/null 2>&1; then
        choice=$(whiptail --title "HOSTNAME JÁ UTILIZADO" --default-item "VOLTAR" --menu \
            "O hostname ${hostname} já está em uso na sua conta Cloudflare!\n\n• Registro DNS atual: ${dns_type} -> ${dns_target}\n\nEscolha como continuar:" \
            18 80 3 \
            "VOLTAR" "Digitar outro subdomínio — RECOMENDADO" \
            "SOBRESCREVER" "Transferir esta rota para esta aplicação" \
            "CANCELAR" "Encerrar a instalação sem fazer alterações" \
            3>&1 1>&2 2>&3) || return 130
    else
        echo "O hostname ${hostname} já está em uso na sua conta Cloudflare!"
        echo "Registro DNS atual: ${dns_type} -> ${dns_target}"
        read -r -p "Deseja sobrescrever? (s/N/voltar): " ans
        case "$ans" in
            [sS]*) choice="SOBRESCREVER" ;;
            [vV]*) choice="VOLTAR" ;;
            *) choice="CANCELAR" ;;
        esac
    fi

    case "$choice" in
        VOLTAR) return 20 ;;
        SOBRESCREVER)
            SETUPMNO_GUARDED_HOSTNAMES[$hostname]=1
            return 0
            ;;
        *) return 130 ;;
    esac
}
export -f setupmno_guard_route 2>/dev/null || true

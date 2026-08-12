#!/usr/bin/bash

# --- DIAGNÓSTICO DE SEGURANÇA DO SERVIDOR (P0 / SOMENTE LEITURA) ---
security_diagnostic_config_value() {
    local key="$1"
    local config="$2"
    printf '%s\n' "$config" | awk -v wanted="$key" '
        $1 == wanted {
            $1 = ""
            sub(/^[[:space:]]+/, "")
            print
            exit
        }
    '
}

security_diagnostic_yes_no() {
    case "$1" in
        yes) printf 'SIM' ;;
        no) printf 'NÃO' ;;
        '') printf 'NÃO IDENTIFICADO' ;;
        *) printf '%s' "$1" ;;
    esac
}

show_server_security_diagnostic() {
    local environment virtualization provider_hint dmi_data os_pretty kernel_version
    local sshd_bin ssh_version ssh_service ssh_socket syntax_status effective_config
    local ports password_auth root_login pubkey_auth interactive_auth empty_passwords
    local max_auth_tries login_grace_time x11_forwarding tcp_forwarding gateway_ports
    local key_total=0 key_users="" sudo_users="" firewall_status fail2ban_status
    local failed_logins="NÃO DISPONÍVEL" score=100 rating report recommendations=""
    local page_summary page_ssh page_access page_recommendations
    local critical_count=0 high_count=0 medium_count=0 info_count=0
    local user_name user_uid user_home key_file key_count detected_virtualization

    kernel_version=$(uname -r 2>/dev/null || printf 'não identificado')
    if [ -r /etc/os-release ]; then
        os_pretty=$(
            # shellcheck disable=SC1091
            . /etc/os-release 2>/dev/null
            printf '%s' "${PRETTY_NAME:-${NAME:-Linux}}"
        )
    else
        os_pretty="Linux não identificado"
    fi

    if grep -qiE '(microsoft|wsl)' /proc/sys/kernel/osrelease /proc/version 2>/dev/null; then
        environment="WSL2"
        virtualization="WSL"
        provider_hint="Windows / ambiente local"
    else
        environment="LINUX / VPS OU SERVIDOR"
        detected_virtualization=""
        if command -v systemd-detect-virt >/dev/null 2>&1; then
            detected_virtualization=$(systemd-detect-virt 2>/dev/null || true)
        fi
        [ -n "$detected_virtualization" ] && [ "$detected_virtualization" != "none" ] &&
            virtualization="$detected_virtualization" || virtualization="não detectada"

        dmi_data=$(printf '%s %s %s' \
            "$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null || true)" \
            "$(cat /sys/class/dmi/id/product_name 2>/dev/null || true)" \
            "$(cat /sys/class/dmi/id/board_vendor 2>/dev/null || true)")
        case "${dmi_data,,}" in
            *amazon*|*ec2*) provider_hint="Amazon AWS" ;;
            *digitalocean*) provider_hint="DigitalOcean" ;;
            *hetzner*) provider_hint="Hetzner" ;;
            *google*) provider_hint="Google Cloud" ;;
            *microsoft*) provider_hint="Microsoft Azure" ;;
            *oracle*) provider_hint="Oracle Cloud (indício local)" ;;
            *) provider_hint="não identificada localmente" ;;
        esac
    fi

    sshd_bin=$(command -v sshd 2>/dev/null || true)
    [ -n "$sshd_bin" ] || [ ! -x /usr/sbin/sshd ] || sshd_bin=/usr/sbin/sshd

    ssh_service="não identificado"
    ssh_socket="não identificado"
    if command -v systemctl >/dev/null 2>&1; then
        ssh_service=$(systemctl is-active ssh.service 2>/dev/null || true)
        ssh_socket=$(systemctl is-active ssh.socket 2>/dev/null || true)
        [ -n "$ssh_service" ] || ssh_service="inativo/ausente"
        [ -n "$ssh_socket" ] || ssh_socket="inativo/ausente"
    elif command -v pgrep >/dev/null 2>&1 && pgrep -x sshd >/dev/null 2>&1; then
        ssh_service="ativo (processo sshd)"
        ssh_socket="systemd indisponível"
    fi

    if command -v ufw >/dev/null 2>&1; then
        firewall_status=$(LC_ALL=C ufw status 2>/dev/null | awk -F: '/^Status:/{gsub(/^[[:space:]]+/, "", $2); print $2; exit}')
        case "$firewall_status" in
            active) firewall_status="UFW ATIVO" ;;
            inactive) firewall_status="UFW INATIVO" ;;
            *) firewall_status="UFW instalado; estado não confirmado" ;;
        esac
    elif command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state >/dev/null 2>&1; then
        firewall_status="FIREWALLD ATIVO"
    elif command -v nft >/dev/null 2>&1 && [ -n "$(nft list ruleset 2>/dev/null)" ]; then
        firewall_status="REGRAS NFTABLES DETECTADAS (política não classificada)"
    else
        firewall_status="NENHUM GERENCIADOR LOCAL CONFIRMADO"
    fi

    if command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet fail2ban.service 2>/dev/null; then
        fail2ban_status="ATIVO"
    elif command -v fail2ban-client >/dev/null 2>&1; then
        fail2ban_status="INSTALADO, MAS INATIVO"
    else
        fail2ban_status="NÃO INSTALADO"
    fi

    while IFS=: read -r user_name _ user_uid _ _ user_home _; do
        case "$user_uid" in
            ''|*[!0-9]*) continue ;;
        esac
        if [ "$user_uid" -eq 0 ] || { [ "$user_uid" -ge 1000 ] && [ "$user_uid" -lt 65534 ]; }; then
            key_file="$user_home/.ssh/authorized_keys"
            if [ -f "$key_file" ] && [ ! -L "$key_file" ]; then
                key_count=$(awk 'NF && $1 !~ /^#/ {count++} END {print count+0}' "$key_file" 2>/dev/null)
                if [ "$key_count" -gt 0 ]; then
                    key_total=$((key_total + key_count))
                    [ -z "$key_users" ] || key_users="$key_users, "
                    key_users="${key_users}${user_name}:${key_count}"
                fi
            fi
        fi
    done < <(getent passwd 2>/dev/null)
    [ -n "$key_users" ] || key_users="nenhuma entrada encontrada"

    sudo_users=$(getent group sudo 2>/dev/null | awk -F: '{print $4}')
    [ -n "$sudo_users" ] || sudo_users=$(getent group wheel 2>/dev/null | awk -F: '{print $4}')
    [ -n "$sudo_users" ] || sudo_users="nenhum usuário adicional identificado"

    if command -v journalctl >/dev/null 2>&1; then
        failed_logins=$(journalctl --since "24 hours ago" -u ssh.service -u sshd.service \
            --no-pager 2>/dev/null | grep -Eic 'failed password|invalid user|authentication failure' || true)
        [ -n "$failed_logins" ] || failed_logins=0
    fi

    if [ -n "$sshd_bin" ]; then
        ssh_version=$("$sshd_bin" -V 2>&1 | head -n 1 || true)
        [ -n "$ssh_version" ] || ssh_version="versão não identificada"
        if "$sshd_bin" -t >/dev/null 2>&1; then
            syntax_status="VÁLIDA"
        else
            syntax_status="INVÁLIDA OU INCOMPLETA"
            score=$((score - 40))
            critical_count=$((critical_count + 1))
            recommendations+="[CRÍTICO] A validação do OpenSSH falhou. Não reinicie o SSH antes de corrigir a configuração.\n"
        fi

        effective_config=$("$sshd_bin" -T 2>/dev/null || true)
        ports=$(printf '%s\n' "$effective_config" | awk '$1 == "port" {print $2}' | paste -sd, -)
        [ -n "$ports" ] || ports="não identificadas"
        password_auth=$(security_diagnostic_config_value passwordauthentication "$effective_config")
        root_login=$(security_diagnostic_config_value permitrootlogin "$effective_config")
        pubkey_auth=$(security_diagnostic_config_value pubkeyauthentication "$effective_config")
        interactive_auth=$(security_diagnostic_config_value kbdinteractiveauthentication "$effective_config")
        empty_passwords=$(security_diagnostic_config_value permitemptypasswords "$effective_config")
        max_auth_tries=$(security_diagnostic_config_value maxauthtries "$effective_config")
        login_grace_time=$(security_diagnostic_config_value logingracetime "$effective_config")
        x11_forwarding=$(security_diagnostic_config_value x11forwarding "$effective_config")
        tcp_forwarding=$(security_diagnostic_config_value allowtcpforwarding "$effective_config")
        gateway_ports=$(security_diagnostic_config_value gatewayports "$effective_config")

        if [ "$empty_passwords" = "yes" ]; then
            score=$((score - 40))
            critical_count=$((critical_count + 1))
            recommendations+="[CRÍTICO] O SSH permite contas com senha vazia. Exija correção assistida imediata.\n"
        fi
        if [ "$password_auth" = "yes" ]; then
            score=$((score - 20))
            high_count=$((high_count + 1))
            recommendations+="[ALTO] A autenticação por senha está habilitada. Cadastre e teste uma chave antes de desativá-la.\n"
        fi
        case "$root_login" in
            yes)
                if [ "$password_auth" = "yes" ]; then
                    score=$((score - 25))
                    critical_count=$((critical_count + 1))
                    recommendations+="[CRÍTICO] O root pode entrar diretamente e senhas estão habilitadas. Crie e teste um usuário sudo antes de bloquear o root remoto.\n"
                else
                    score=$((score - 12))
                    high_count=$((high_count + 1))
                    recommendations+="[ALTO] O login SSH direto do root está permitido, embora sem senha detectada. Considere usuário administrativo separado.\n"
                fi
                ;;
            prohibit-password|without-password)
                score=$((score - 5))
                medium_count=$((medium_count + 1))
                recommendations+="[MÉDIO] O root ainda pode entrar diretamente por chave. Um usuário sudo separado reduz a exposição administrativa.\n"
                ;;
        esac
        if [ "$pubkey_auth" = "no" ]; then
            score=$((score - 25))
            high_count=$((high_count + 1))
            recommendations+="[ALTO] A autenticação por chave pública está desabilitada. Não desative senhas antes de preparar uma chave funcional.\n"
        elif [ "$key_total" -eq 0 ]; then
            score=$((score - 10))
            medium_count=$((medium_count + 1))
            recommendations+="[MÉDIO] Chaves são aceitas, mas nenhuma entrada authorized_keys foi encontrada para root ou usuários comuns.\n"
        fi
        if [[ ",$ports," == *,22,* ]]; then
            score=$((score - 2))
            info_count=$((info_count + 1))
            recommendations+="[INFORMATIVO] A porta 22 reduz a complexidade, mas recebe mais varreduras. Trocá-la não substitui chave, firewall ou MFA.\n"
        fi
        if [[ "$max_auth_tries" =~ ^[0-9]+$ ]] && [ "$max_auth_tries" -gt 6 ]; then
            score=$((score - 4))
            medium_count=$((medium_count + 1))
            recommendations+="[MÉDIO] MaxAuthTries está acima de 6; revise o limite em uma futura correção assistida.\n"
        fi
        if [ "$password_auth" = "yes" ] && [ "$fail2ban_status" != "ATIVO" ]; then
            score=$((score - 4))
            medium_count=$((medium_count + 1))
            recommendations+="[MÉDIO] Senhas estão habilitadas e o Fail2ban não está ativo. Chaves e restrição de origem têm prioridade.\n"
        fi
    else
        ssh_version="OpenSSH Server não encontrado"
        syntax_status="NÃO APLICÁVEL"
        effective_config=""
        ports="nenhuma"
        password_auth=""
        root_login=""
        pubkey_auth=""
        interactive_auth=""
        empty_passwords=""
        max_auth_tries=""
        login_grace_time=""
        x11_forwarding=""
        tcp_forwarding=""
        gateway_ports=""
        info_count=$((info_count + 1))
        if [ "$environment" = "WSL2" ]; then
            recommendations+="[INFORMATIVO] O servidor SSH não foi encontrado e normalmente não é necessário no WSL2 local.\n"
        else
            recommendations+="[INFORMATIVO] O OpenSSH Server não foi encontrado. O acesso pode ocorrer somente pelo console ou Control Center.\n"
        fi
    fi

    if [ "$environment" != "WSL2" ]; then
        case "$firewall_status" in
            "UFW INATIVO"|"NENHUM GERENCIADOR LOCAL CONFIRMADO")
                score=$((score - 8))
                medium_count=$((medium_count + 1))
                recommendations+="[MÉDIO] Nenhum firewall local ativo foi confirmado. Isso não informa o estado do firewall da provedora.\n"
                ;;
        esac
    else
        recommendations+="[WSL2] A exposição real também depende do Windows Defender/Hyper-V, NAT ou rede espelhada; root no Linux não administra o firewall do Windows.\n"
    fi

    recommendations+="[PROVEDORA] Security Groups, NSG/Security Lists e firewalls externos não podem ser confirmados apenas de dentro do servidor.\n"
    [ "$score" -ge 0 ] || score=0
    if [ "$score" -ge 90 ]; then
        rating="BOA"
    elif [ "$score" -ge 75 ]; then
        rating="ATENÇÃO"
    elif [ "$score" -ge 50 ]; then
        rating="RISCO ALTO"
    else
        rating="RISCO CRÍTICO"
    fi

    page_summary="DIAGNÓSTICO LOCAL DE SEGURANÇA SSH — SOMENTE LEITURA\n"
    page_summary+="Nenhum arquivo, serviço, porta, firewall ou credencial foi alterado.\n\n"
    page_summary+="RESUMO\nÍndice local SSH: ${score}/100 — ${rating}\n"
    page_summary+="Achados: ${critical_count} crítico(s), ${high_count} alto(s), ${medium_count} médio(s), ${info_count} informativo(s)\n\n"
    page_summary+="AMBIENTE\nSistema: ${os_pretty}\nKernel: ${kernel_version}\nAmbiente: ${environment}\n"
    page_summary+="Virtualização: ${virtualization}\nProvedor: ${provider_hint}"

    page_ssh="OPENSSH — CONFIGURAÇÃO EFETIVA\n\n"
    page_ssh+="Versão: ${ssh_version}\nValidação: ${syntax_status}\nssh.service: ${ssh_service}\nssh.socket: ${ssh_socket}\nPortas: ${ports}\n"
    page_ssh+="Senha habilitada: $(security_diagnostic_yes_no "$password_auth")\nLogin root: ${root_login:-NÃO IDENTIFICADO}\n"
    page_ssh+="Chave pública: $(security_diagnostic_yes_no "$pubkey_auth")\nAutenticação interativa: $(security_diagnostic_yes_no "$interactive_auth")\n"
    page_ssh+="Senhas vazias: $(security_diagnostic_yes_no "$empty_passwords")\nMaxAuthTries: ${max_auth_tries:-NÃO IDENTIFICADO}\n"
    page_ssh+="LoginGraceTime: ${login_grace_time:-NÃO IDENTIFICADO}\nX11Forwarding: $(security_diagnostic_yes_no "$x11_forwarding")\n"
    page_ssh+="AllowTcpForwarding: ${tcp_forwarding:-NÃO IDENTIFICADO}\nGatewayPorts: $(security_diagnostic_yes_no "$gateway_ports")"

    page_access="ACESSO E PROTEÇÃO\n\nEntradas authorized_keys: ${key_total} (${key_users})\n"
    page_access+="Usuários sudo/wheel: ${sudo_users}\nFirewall local: ${firewall_status}\nFail2ban: ${fail2ban_status}\n"
    page_access+="Falhas SSH observadas em 24h: ${failed_logins}\nFirewall da provedora: NÃO VERIFICÁVEL LOCALMENTE"

    page_recommendations="CHECKLIST RECOMENDADO\n\n${recommendations}\n"
    page_recommendations+="LIMITES\nEste índice avalia somente controles locais visíveis. Não é pentest, certificação nem prova de exposição pública. Confirme o firewall da provedora e preserve acesso de emergência antes de qualquer correção futura."
    report="${page_summary}\n\n${page_ssh}\n\n${page_access}\n\n${page_recommendations}"

    if [ "${SETUPMNO_SECURITY_DIAGNOSTIC_SMOKE_TEST:-0}" = "1" ]; then
        printf '%b\n' "$report"
        return 0
    fi

    if command -v whiptail >/dev/null 2>&1; then
        whiptail --title "DIAGNÓSTICO DE SEGURANÇA — 1/4" --ok-button "CONTINUAR" \
            --msgbox "$(printf '%b' "$page_summary")" 20 78 1>&2 || { clear; return 0; }
        whiptail --title "DIAGNÓSTICO DE SEGURANÇA — 2/4" --ok-button "CONTINUAR" \
            --msgbox "$(printf '%b' "$page_ssh")" 22 78 1>&2 || { clear; return 0; }
        whiptail --title "DIAGNÓSTICO DE SEGURANÇA — 3/4" --ok-button "CONTINUAR" \
            --msgbox "$(printf '%b' "$page_access")" 18 78 1>&2 || { clear; return 0; }
        whiptail --title "DIAGNÓSTICO DE SEGURANÇA — 4/4" --ok-button "VOLTAR AO MENU" \
            --msgbox "$(printf '%b' "$page_recommendations")" 22 78 1>&2
    else
        printf '%b\n' "$report"
        printf '\nPressione ENTER para voltar ao menu.'
        read -r _
    fi
    clear
    return 0
}


show_server_security_diagnostic

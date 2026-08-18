#!/usr/bin/bash
# Reconciliação segura de aplicações Cloudflare Access no modo SEM_MFA.
# Este módulo é distribuído dentro do control-source.tar.gz validado.

check_cloudflare_access() {
    local organization_file="$1" applications_file="$2" status_file error_file curl_status
    status_file=$(mktemp) || return 1
    error_file=$(mktemp) || {
        rm -f "$status_file"
        return 1
    }
    {
        echo -e "XXX\n10\nVALIDANDO O CLOUDFLARE ZERO TRUST...\nXXX"
        if curl -sS \
            --connect-timeout "$CLOUDFLARE_CONNECT_TIMEOUT" \
            --max-time "$CLOUDFLARE_MAX_TIME" \
            -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
            "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/access/organizations" \
            >"$organization_file" 2>"$error_file" && \
           curl -sS \
            --connect-timeout "$CLOUDFLARE_CONNECT_TIMEOUT" \
            --max-time "$CLOUDFLARE_MAX_TIME" \
            -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
            "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/access/apps?per_page=100" \
            >"$applications_file" 2>>"$error_file"; then
            printf '0\n' >"$status_file"
        else
            printf '%s\n' "$?" >"$status_file"
        fi
        echo -e "XXX\n100\nZERO TRUST VALIDADO\nXXX"
    } | whiptail --title "SEGURANÇA CLOUDFLARE ACCESS" --gauge \
        "Confirmando identidade, modo de segurança e permissões..." 8 82 0

    curl_status=$(cat "$status_file" 2>/dev/null)
    rm -f "$status_file" "$error_file"
    [ "$curl_status" = "0" ] || {
        msg "Não foi possível consultar o Cloudflare Access.\n\nUse o assistente de token para validar as sete permissões necessárias. Nenhum recurso foi alterado."
        return 1
    }
    if [ "$(jq -r '.success // false' "$organization_file" 2>/dev/null)" != "true" ] ||
       [ "$(jq -r '.success // false' "$applications_file" 2>/dev/null)" != "true" ]; then
        msg "A Cloudflare recusou a validação do Zero Trust.\n\nConfirme Access: Apps and Policies > Editar e Access: Organizations, Identity Providers, and Groups > Editar. Nenhum recurso foi alterado."
        return 1
    fi
    access_auth_domain=$(jq -r '.result.auth_domain // empty' "$organization_file")
    if [[ ! "$access_auth_domain" =~ ^[A-Za-z0-9-]+\.cloudflareaccess\.com$ ]]; then
        msg "A organização Zero Trust ainda não possui um domínio de autenticação válido. Configure o Cloudflare Zero Trust antes de instalar o Control Center."
        return 1
    fi
    existing_access_app=$(jq -r --arg host "$url_control" '
        [.result[]? | select(
            .domain == $host or
            any(.destinations[]?; .type == "public" and .uri == $host)
        )][0].id // empty
    ' "$applications_file" 2>/dev/null)
    if [ -n "$existing_access_app" ]; then
        msg "Já existe um aplicativo Cloudflare Access protegendo $url_control.\n\nPara evitar substituir políticas de segurança que podem pertencer a outro sistema, informe outro domínio ou remova conscientemente o aplicativo existente no Zero Trust. Nenhum recurso foi alterado."
        return 1
    fi
    access_team_domain="https://$access_auth_domain"
    access_team_name="${access_auth_domain%.cloudflareaccess.com}"
    return 0
}

build_access_hostname_inventory() {
    local applications_file="$1" hostname="$2" output_file="$3"
    jq --arg host "$hostname" '
        def normalized_hostname:
            if type != "string" then ""
            else ascii_downcase
                | sub("^https?://"; "")
                | split("/")[0]
                | sub(":[0-9]+$"; "")
                | sub("\\.$"; "")
            end;
        def app_patterns:
            ([.domain?] + [.destinations[]? | select(.type == "public") | .uri?])
            | map(select(type == "string") | normalized_hostname)
            | map(select(length > 0))
            | unique;
        def wildcard_matches($pattern; $hostname):
            ($pattern | index("*")) as $position
            | if $position == null then false
              else
                ($pattern[0:$position]) as $prefix
                | ($pattern[$position + 1:]) as $suffix
                | ($hostname | startswith($prefix))
                and ($hostname | endswith($suffix))
                and (($hostname | length) >= (($prefix | length) + ($suffix | length)))
              end;
        ($host | normalized_hostname) as $normalized_host
        | {
            schemaVersion: 1,
            hostname: $normalized_host,
            exactApps: [
                .result[]? as $app
                | ($app | app_patterns) as $patterns
                | select(any($patterns[]?; . == $normalized_host))
                | {
                    id: ($app.id // ""),
                    name: ($app.name // "Aplicação Access sem nome"),
                    patterns: $patterns
                  }
            ],
            wildcardApps: [
                .result[]? as $app
                | ($app | app_patterns) as $patterns
                | select(any($patterns[]?;
                    contains("*") and wildcard_matches(.; $normalized_host)))
                | {
                    id: ($app.id // ""),
                    name: ($app.name // "Aplicação Access wildcard"),
                    patterns: [$patterns[] | select(contains("*") and
                        wildcard_matches(.; $normalized_host))]
                  }
            ]
          }
    ' "$applications_file" >"$output_file"
}

inspect_sem_mfa_access_conflicts() {
    local work_dir applications_file inventory_file curl_error exact_count wildcard_count
    local exact_description wildcard_description exact_dedicated choice status
    work_dir=$(mktemp -d) || return 1
    chmod 0700 "$work_dir"
    applications_file="$work_dir/access-applications.json"
    inventory_file="$work_dir/access-inventory.json"
    curl_error="$work_dir/curl-error.log"
    sem_mfa_access_decision="NONE"
    sem_mfa_access_app_id=""
    sem_mfa_access_app_name=""
    sem_mfa_access_wildcards=""

    {
        echo -e "XXX\n15\nCONSULTANDO APLICAÇÕES ACCESS...\nXXX"
        if curl -sS \
            --connect-timeout "$CLOUDFLARE_CONNECT_TIMEOUT" \
            --max-time "$CLOUDFLARE_MAX_TIME" \
            -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
            "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/access/apps?per_page=100" \
            >"$applications_file" 2>"$curl_error"; then
            echo -e "XXX\n70\nVERIFICANDO HOSTNAME EXATO E WILDCARDS...\nXXX"
        else
            printf '%s\n' "curl-failed" >"$work_dir/status"
        fi
        echo -e "XXX\n100\nAUDITORIA ACCESS CONCLUÍDA\nXXX"
    } | whiptail --title "AUDITORIA CLOUDFLARE ACCESS" --gauge \
        "Verificando se o hostname já pertence a outra aplicação..." 8 86 0

    if [ -s "$work_dir/status" ] ||
       [ "$(jq -r '.success // false' "$applications_file" 2>/dev/null)" != "true" ]; then
        rm -rf -- "$work_dir"
        msg "Não foi possível consultar as aplicações Cloudflare Access.\n\nConfirme se o token possui Access: Apps and Policies > Editar. Por segurança, o modo SEM_MFA não continuará sem verificar conflitos. Nenhum recurso foi alterado."
        return 1
    fi
    if ! build_access_hostname_inventory "$applications_file" "$url_control" "$inventory_file"; then
        rm -rf -- "$work_dir"
        msg "A resposta do Cloudflare Access não pôde ser validada. Nenhum recurso foi alterado."
        return 1
    fi
    exact_count=$(jq -r '.exactApps | length' "$inventory_file")
    wildcard_count=$(jq -r '.wildcardApps | length' "$inventory_file")
    exact_description=$(jq -r '.exactApps[]? | "• " + .name + " (" + (.patterns | join(", ")) + ")"' \
        "$inventory_file")
    wildcard_description=$(jq -r '.wildcardApps[]? | "• " + .name + " (" + (.patterns | join(", ")) + ")"' \
        "$inventory_file")
    sem_mfa_access_wildcards="$wildcard_description"

    if [ "$exact_count" -gt 1 ]; then
        rm -rf -- "$work_dir"
        msg "Foram encontradas várias aplicações Access exatas para $url_control.\n\n$exact_description\n\nO Setup não escolherá qual remover. Corrija a duplicidade no Zero Trust ou informe outro hostname. Nenhum recurso foi alterado."
        return 1
    fi
    if [ "$exact_count" -eq 0 ] && [ "$wildcard_count" -eq 0 ]; then
        rm -rf -- "$work_dir"
        return 0
    fi

    if [ "$exact_count" -eq 1 ]; then
        sem_mfa_access_app_id=$(jq -r '.exactApps[0].id // empty' "$inventory_file")
        sem_mfa_access_app_name=$(jq -r '.exactApps[0].name // "Aplicação Access"' "$inventory_file")
        exact_dedicated=$(jq -r --arg host "$url_control" \
            '(.exactApps[0].patterns | length) == 1 and .exactApps[0].patterns[0] == ($host | ascii_downcase)' \
            "$inventory_file")
        if [[ ! "$sem_mfa_access_app_id" =~ ^[A-Fa-f0-9-]{32,36}$ ]]; then
            rm -rf -- "$work_dir"
            msg "A aplicação Access exata de $url_control não possui um identificador seguro para remoção automática.\n\nNenhum recurso foi alterado. Use outro hostname ou revise a aplicação no Zero Trust."
            return 1
        fi
        if [ "$exact_dedicated" != "true" ]; then
            choice=$(whiptail --title "APLICAÇÃO ACCESS COMPARTILHADA" --default-item "VOLTAR" --menu \
                "A aplicação Access exata de $url_control também possui outros destinos:\n\n$exact_description\n\nRemovê-la afetaria outros hostnames. Por isso, o Setup nunca oferecerá exclusão automática para esta aplicação compartilhada." \
                22 96 2 \
                "MANTER" "Manter integralmente a proteção Access e continuar" \
                "VOLTAR" "Voltar e informar outro hostname" \
                3>&1 1>&2 2>&3)
            status=$?
            [ "$status" -eq 0 ] && [ "$choice" = "MANTER" ] || {
                rm -rf -- "$work_dir"
                return 20
            }
            sem_mfa_access_decision="KEEP"
            rm -rf -- "$work_dir"
            return 0
        fi
        while true; do
            choice=$(whiptail --title "CONFLITO CLOUDFLARE ACCESS" --default-item "VOLTAR" --menu \
                "Já existe uma aplicação Access exata protegendo $url_control e ela pode pertencer a uma instalação anterior.\n\n$exact_description$([ "$wildcard_count" -gt 0 ] && printf '\n\nATENÇÃO: também existem wildcards aplicáveis, que serão preservados:\n%s' "$wildcard_description")\n\nO Setup nunca apagará Tunnel, DNS ou aplicações wildcard nesta etapa." \
                25 96 3 \
                "REMOVER" "Remover a aplicação exata/políticas e continuar SEM MFA" \
                "MANTER" "Manter a proteção Access existente e continuar" \
                "VOLTAR" "Voltar e informar outro hostname" \
                3>&1 1>&2 2>&3)
            status=$?
            [ "$status" -ne 0 ] && { rm -rf -- "$work_dir"; return 20; }
            case "$choice" in
                REMOVER)
                    sem_mfa_access_decision="REMOVE"
                    rm -rf -- "$work_dir"
                    return 0
                    ;;
                MANTER)
                    sem_mfa_access_decision="KEEP"
                    rm -rf -- "$work_dir"
                    return 0
                    ;;
                VOLTAR)
                    rm -rf -- "$work_dir"
                    return 20
                    ;;
            esac
        done
    fi

    choice=$(whiptail --title "CONFLITO ACCESS WILDCARD" --default-item "VOLTAR" --menu \
        "Não existe aplicação Access exata para $url_control, mas uma ou mais aplicações wildcard também protegem esse hostname:\n\n$wildcard_description\n\nUm wildcard pode proteger outros sistemas. Por isso, o Setup nunca o removerá automaticamente." \
        23 96 2 \
        "MANTER" "Manter a proteção wildcard existente e continuar" \
        "VOLTAR" "Voltar e informar outro hostname" \
        3>&1 1>&2 2>&3)
    status=$?
    [ "$status" -eq 0 ] && [ "$choice" = "MANTER" ] || {
        rm -rf -- "$work_dir"
        return 20
    }
    sem_mfa_access_decision="KEEP"
    rm -rf -- "$work_dir"
    return 0
}

remove_confirmed_sem_mfa_access_app() {
    local work_dir="$1" log_file="$2" applications_file inventory_file response_file
    local exact_count current_id current_dedicated
    [ "${sem_mfa_access_decision:-NONE}" = "REMOVE" ] || return 0
    [[ "${sem_mfa_access_app_id:-}" =~ ^[A-Fa-f0-9-]{32,36}$ ]] || return 1
    applications_file="$work_dir/sem-mfa-access-applications-fresh.json"
    inventory_file="$work_dir/sem-mfa-access-inventory-fresh.json"
    response_file="$work_dir/sem-mfa-access-delete-response.json"

    if ! curl -sS \
        --connect-timeout "$CLOUDFLARE_CONNECT_TIMEOUT" \
        --max-time "$CLOUDFLARE_MAX_TIME" \
        -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
        "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/access/apps?per_page=100" \
        >"$applications_file" 2>>"$log_file" ||
       [ "$(jq -r '.success // false' "$applications_file" 2>/dev/null)" != "true" ] ||
       ! build_access_hostname_inventory "$applications_file" "$url_control" "$inventory_file"; then
        echo "A aplicação Access não pôde ser revalidada; nenhuma remoção foi executada." >>"$log_file"
        return 1
    fi
    exact_count=$(jq -r '.exactApps | length' "$inventory_file")
    if [ "$exact_count" -eq 0 ]; then
        echo "Aplicação Access exata já ausente; remoção considerada idempotente." >>"$log_file"
        return 0
    fi
    current_id=$(jq -r '.exactApps[0].id // empty' "$inventory_file")
    current_dedicated=$(jq -r --arg host "$url_control" \
        '(.exactApps[0].patterns | length) == 1 and .exactApps[0].patterns[0] == ($host | ascii_downcase)' \
        "$inventory_file")
    if [ "$exact_count" -ne 1 ] || [ "$current_id" != "$sem_mfa_access_app_id" ] ||
       [ "$current_dedicated" != "true" ]; then
        echo "A aplicação Access exata mudou após a confirmação; remoção bloqueada." >>"$log_file"
        return 1
    fi
    if ! curl -sS \
        --connect-timeout "$CLOUDFLARE_CONNECT_TIMEOUT" \
        --max-time "$CLOUDFLARE_MAX_TIME" \
        -X DELETE \
        "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/access/apps/$current_id" \
        -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
        >"$response_file" 2>>"$log_file" ||
       [ "$(jq -r '.success // false' "$response_file" 2>/dev/null)" != "true" ]; then
        echo "A Cloudflare recusou a remoção da aplicação Access exata." >>"$log_file"
        return 1
    fi
    sem_mfa_access_removed="true"
    echo "Aplicação Access exata removida após revalidação: $url_control. Tunnel, DNS e wildcards preservados." >>"$log_file"
    return 0
}

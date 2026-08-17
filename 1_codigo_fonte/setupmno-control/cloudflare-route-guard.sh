#!/usr/bin/bash
# Proteção transacional de hostnames usados por Cloudflare Tunnel.
# Este módulo nunca cria Tunnels: ele inventaria DNS/ingress, exige uma decisão
# explícita e oferece primitivas de transferência e rollback.

CF_ROUTE_GUARD_ERROR=""
CF_ROUTE_GUARD_DECISION=""

build_control_tunnel_route_payload() {
    local input_file="$1" output_file="$2" host="$3" service="$4"
    local require_access="$5" team="$6" aud="$7"
    jq --arg host "$host" --arg service "$service" --arg team "$team" --arg aud "$aud" \
        --argjson requireAccess "$require_access" '
        (.result.config // {}) as $cfg
        | ($cfg.ingress // [])
        | map(select(.service != "http_status:404" and .hostname != $host))
        + [{hostname:$host,service:$service,originRequest:
             (if $requireAccess then {
                noTlsVerify:true,httpHostHeader:$host,
                access:{required:true,teamName:$team,audTag:[$aud]}
              } else {noTlsVerify:true,httpHostHeader:$host} end)},
           {service:"http_status:404"}]
        | {config:($cfg + {ingress:.})}
    ' "$input_file" >"$output_file"
}

cf_route_guard_api() {
    local method="$1" endpoint="$2" output="$3" payload="${4:-}" http_code
    local args=(-sS --connect-timeout "${CLOUDFLARE_CONNECT_TIMEOUT:-10}"
        --max-time "${CLOUDFLARE_MAX_TIME:-45}" -X "$method"
        -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}"
        -H "Content-Type: application/json")
    [ -z "$payload" ] || args+=(--data-binary "@$payload")
    http_code=$(curl "${args[@]}" -o "$output" -w '%{http_code}' \
        "https://api.cloudflare.com/client/v4${endpoint}" 2>/dev/null) || {
        CF_ROUTE_GUARD_ERROR="Falha de conexão com a API da Cloudflare."
        return 1
    }
    if ! [[ "$http_code" =~ ^2[0-9][0-9]$ ]] ||
       ! jq -e '.success == true' "$output" >/dev/null 2>&1; then
        CF_ROUTE_GUARD_ERROR=$(jq -r \
            '[.errors[]?.message,.messages[]?.message] | map(select(length > 0)) | join("; ")' \
            "$output" 2>/dev/null)
        CF_ROUTE_GUARD_ERROR="Cloudflare recusou a operação (HTTP ${http_code}): ${CF_ROUTE_GUARD_ERROR:-resposta inválida}."
        return 1
    fi
}

cf_route_guard_inventory() {
    local hostname="$1" current_tunnel_id="$2" output="$3"
    local work dns tunnels page total_pages tunnel tunnel_id tunnel_name config_src
    local config combined
    CF_ROUTE_GUARD_ERROR=""
    work=$(mktemp -d) || return 1
    chmod 700 "$work"
    dns="$work/dns.json"
    tunnels="$work/tunnels.json"
    printf '[]' >"$tunnels"

    if ! cf_route_guard_api GET \
        "/zones/${CLOUDFLARE_ZONE_ID}/dns_records?name=${hostname}&per_page=100" "$dns" ||
       ! jq -e '.result | type == "array"' "$dns" >/dev/null 2>&1; then
        [ -n "$CF_ROUTE_GUARD_ERROR" ] || CF_ROUTE_GUARD_ERROR="Não foi possível inventariar o DNS de ${hostname}."
        rm -rf -- "$work"
        return 1
    fi

    page=1
    total_pages=1
    while [ "$page" -le "$total_pages" ] && [ "$page" -le 50 ]; do
        if ! cf_route_guard_api GET \
            "/accounts/${CLOUDFLARE_ACCOUNT_ID}/cfd_tunnel?is_deleted=false&per_page=100&page=${page}" \
            "$work/tunnel-page.json" ||
           ! jq -e '.result | type == "array"' "$work/tunnel-page.json" >/dev/null 2>&1; then
            [ -n "$CF_ROUTE_GUARD_ERROR" ] || CF_ROUTE_GUARD_ERROR="Não foi possível listar os Tunnels da conta."
            rm -rf -- "$work"
            return 1
        fi
        jq -s '.[0] + .[1].result' "$tunnels" "$work/tunnel-page.json" >"$work/tunnels.new" || {
            rm -rf -- "$work"
            return 1
        }
        mv -f "$work/tunnels.new" "$tunnels"
        total_pages=$(jq -r '.result_info.total_pages // 1' "$work/tunnel-page.json")
        [[ "$total_pages" =~ ^[0-9]+$ ]] || total_pages=1
        page=$((page + 1))
    done

    printf '[]' >"$work/inventoried-tunnels.json"
    while IFS= read -r tunnel; do
        tunnel_id=$(printf '%s' "$tunnel" | jq -r '.id // empty')
        tunnel_name=$(printf '%s' "$tunnel" | jq -r '.name // "Tunnel sem nome"')
        config_src=$(printf '%s' "$tunnel" | jq -r '.config_src // "local"')
        [ -n "$tunnel_id" ] || continue
        config="$work/config-${tunnel_id}.json"
        if [ "$config_src" = "cloudflare" ]; then
            if ! cf_route_guard_api GET \
                "/accounts/${CLOUDFLARE_ACCOUNT_ID}/cfd_tunnel/${tunnel_id}/configurations" "$config"; then
                # Um Tunnel remoto recém-criado pode ainda não possuir configuração.
                if grep -Eqi 'configuration|config|not found|does not exist' "$config" 2>/dev/null; then
                    printf '%s' '{"success":true,"result":{"config":{"ingress":[]}}}' >"$config"
                    CF_ROUTE_GUARD_ERROR=""
                else
                    CF_ROUTE_GUARD_ERROR="Não foi possível auditar as rotas do Tunnel ${tunnel_name}. Nenhuma alteração foi realizada."
                    rm -rf -- "$work"
                    return 1
                fi
            fi
        else
            printf '%s' '{"success":true,"result":{"config":null}}' >"$config"
        fi
        jq -n --arg id "$tunnel_id" --arg name "$tunnel_name" --arg src "$config_src" \
            --argjson configuration "$(jq -c '.result.config // null' "$config")" \
            '{id:$id,name:$name,configSrc:$src,configuration:$configuration}' \
            >"$work/tunnel-entry.json" || { rm -rf -- "$work"; return 1; }
        jq -s '.[0] + [.[1]]' "$work/inventoried-tunnels.json" "$work/tunnel-entry.json" \
            >"$work/inventoried-tunnels.new" || { rm -rf -- "$work"; return 1; }
        mv -f "$work/inventoried-tunnels.new" "$work/inventoried-tunnels.json"
    done < <(jq -c '.[]' "$tunnels")

    combined="$work/inventory.json"
    jq -n --arg host "$hostname" --arg current "$current_tunnel_id" \
        --argjson dns "$(jq -c '.result' "$dns")" \
        --argjson tunnels "$(cat "$work/inventoried-tunnels.json")" '
        {schemaVersion:1,hostname:$host,currentTunnelId:$current,dns:$dns,tunnels:$tunnels}
        | .routeConflicts = [
            .tunnels[] as $t
            | $t.configuration.ingress[]?
            | select(.hostname == $host)
            | {tunnelId:$t.id,tunnelName:$t.name,configSrc:$t.configSrc,
               service:(.service // "serviço não informado")}
          ]
    ' >"$combined" || { rm -rf -- "$work"; return 1; }
    chmod 600 "$combined"
    mv -f "$combined" "$output"
    rm -rf -- "$work"
}

cf_route_guard_classify() {
    local inventory="$1" dns_count invalid_dns local_target
    dns_count=$(jq '.dns | length' "$inventory") || return 1
    invalid_dns=$(jq '[.dns[]? | select(.type != "CNAME")] | length' "$inventory") || return 1
    local_target=$(jq '[.dns[]? | select(.type == "CNAME") | .content
        | sub("\\.cfargotunnel\\.com\\.?$"; "") as $target
        | $target] as $targets
        | [.tunnels[]? | select(.configSrc != "cloudflare" and (.id as $id | $targets | index($id)))]
        | length' "$inventory") || return 1
    if [ "$dns_count" -gt 1 ] || [ "$invalid_dns" -gt 0 ] || [ "$local_target" -gt 0 ]; then
        printf 'BLOCKED'
    elif [ "$dns_count" -eq 0 ] && [ "$(jq '.routeConflicts | length' "$inventory")" -eq 0 ]; then
        printf 'FREE'
    else
        printf 'OVERWRITE'
    fi
}

cf_route_guard_choose() {
    local inventory="$1" classification choice host dns_count route_count route_names
    classification=$(cf_route_guard_classify "$inventory") || return 1
    host=$(jq -r '.hostname' "$inventory")
    dns_count=$(jq '.dns | length' "$inventory")
    route_count=$(jq '.routeConflicts | length' "$inventory")
    route_names=$(jq -r '[.routeConflicts[].tunnelName] | unique | join(", ")' "$inventory")
    case "$classification" in
        FREE)
            CF_ROUTE_GUARD_DECISION="FREE"
            return 0
            ;;
        BLOCKED)
            choice=$(whiptail --title "CONFLITO CLOUDFLARE NÃO AUTOMATIZÁVEL" --menu \
                "O hostname ${host} possui registros DNS incompatíveis, duplicados ou aponta para um Tunnel com configuração local. A transferência automática foi bloqueada para não apagar uma rota que o Setup não consegue restaurar.\n\nEscolha como continuar:" \
                20 92 2 \
                "VOLTAR" "Digitar outro subdomínio — RECOMENDADO" \
                "CANCELAR" "Encerrar sem alterar DNS ou Tunnels" \
                3>&1 1>&2 2>&3) || return 130
            [ "$choice" = "VOLTAR" ] && return 20
            return 130
            ;;
        OVERWRITE)
            choice=$(whiptail --title "HOSTNAME JÁ UTILIZADO" --default-item "VOLTAR" --menu \
                "O hostname ${host} já está em uso.\n\nRegistros DNS encontrados: ${dns_count}\nRotas Tunnel encontradas: ${route_count}\nTunnels: ${route_names:-nenhum}\n\nSOBRESCREVER transfere somente este hostname, preserva as demais rotas e executa rollback se alguma etapa falhar." \
                22 94 3 \
                "VOLTAR" "Digitar outro subdomínio — RECOMENDADO" \
                "SOBRESCREVER" "Transferir esta rota com snapshot e rollback" \
                "CANCELAR" "Encerrar sem realizar alterações" \
                3>&1 1>&2 2>&3) || return 130
            case "$choice" in
                VOLTAR) return 20 ;;
                SOBRESCREVER) CF_ROUTE_GUARD_DECISION="OVERWRITE"; return 0 ;;
                *) return 130 ;;
            esac
            ;;
    esac
}

cf_route_guard_apply_dns() {
    local inventory="$1" hostname="$2" content="$3" proxied="$4" transaction="$5" log_file="$6"
    local count record_id response payload original method endpoint
    count=$(jq '.dns | length' "$inventory") || return 1
    [ "$count" -le 1 ] || { CF_ROUTE_GUARD_ERROR="O inventário DNS mudou ou contém duplicatas."; return 1; }
    response=$(mktemp) || return 1
    payload=$(mktemp) || { rm -f "$response"; return 1; }
    chmod 600 "$response" "$payload"
    jq -n --arg name "$hostname" --arg content "$content" --argjson proxied "$proxied" \
        '{type:"CNAME",name:$name,content:$content,ttl:1,proxied:$proxied}' >"$payload"
    if [ "$count" -eq 1 ]; then
        if [ "$(jq -r '.dns[0].type' "$inventory")" != "CNAME" ]; then
            CF_ROUTE_GUARD_ERROR="O registro DNS existente não é CNAME."
            rm -f "$response" "$payload"
            return 1
        fi
        record_id=$(jq -r '.dns[0].id // empty' "$inventory")
        original=$(jq -c '.dns[0] | {type,name,content,ttl,proxied}
            + (if .priority != null then {priority} else {} end)
            + (if .comment != null then {comment} else {} end)
            + (if .tags != null then {tags} else {} end)' "$inventory")
        method=PUT
        endpoint="/zones/${CLOUDFLARE_ZONE_ID}/dns_records/${record_id}"
        jq -n --arg id "$record_id" --argjson original "$original" \
            '{mode:"updated",recordId:$id,original:$original}' >"$transaction"
    else
        method=POST
        endpoint="/zones/${CLOUDFLARE_ZONE_ID}/dns_records"
        printf '%s' '{"mode":"pending-create"}' >"$transaction"
    fi
    if ! cf_route_guard_api "$method" "$endpoint" "$response" "$payload"; then
        rm -f "$response" "$payload"
        return 1
    fi
    if [ "$count" -eq 0 ]; then
        record_id=$(jq -r '.result.id // empty' "$response")
        [ -n "$record_id" ] || { CF_ROUTE_GUARD_ERROR="Cloudflare não retornou o ID do CNAME criado."; rm -f "$response" "$payload"; return 1; }
        jq -n --arg id "$record_id" '{mode:"created",recordId:$id}' >"$transaction"
    fi
    printf 'DNS transferido: %s -> %s\n' "$hostname" "$content" >>"$log_file"
    rm -f "$response" "$payload"
}

cf_route_guard_restore_dns() {
    local transaction="$1" log_file="$2" response payload mode record_id
    [ -s "$transaction" ] || return 0
    mode=$(jq -r '.mode // empty' "$transaction" 2>/dev/null)
    record_id=$(jq -r '.recordId // empty' "$transaction" 2>/dev/null)
    [ -n "$record_id" ] || return 0
    response=$(mktemp) || return 1
    payload=$(mktemp) || { rm -f "$response"; return 1; }
    chmod 600 "$response" "$payload"
    case "$mode" in
        created)
            cf_route_guard_api DELETE "/zones/${CLOUDFLARE_ZONE_ID}/dns_records/${record_id}" "$response" || {
                printf 'Rollback DNS falhou: %s\n' "$CF_ROUTE_GUARD_ERROR" >>"$log_file"
                rm -f "$response" "$payload"
                return 1
            }
            ;;
        updated)
            jq '.original' "$transaction" >"$payload" || { rm -f "$response" "$payload"; return 1; }
            cf_route_guard_api PUT "/zones/${CLOUDFLARE_ZONE_ID}/dns_records/${record_id}" "$response" "$payload" || {
                printf 'Rollback DNS falhou: %s\n' "$CF_ROUTE_GUARD_ERROR" >>"$log_file"
                rm -f "$response" "$payload"
                return 1
            }
            ;;
    esac
    rm -f "$response" "$payload"
}

cf_route_guard_restore_tunnels() {
    local changes="$1" log_file="$2" entry tunnel_id payload response failed=0
    [ -s "$changes" ] || return 0
    while IFS= read -r entry; do
        tunnel_id=$(printf '%s' "$entry" | jq -r '.tunnelId')
        payload=$(mktemp) || { failed=1; continue; }
        response=$(mktemp) || { rm -f "$payload"; failed=1; continue; }
        printf '%s' "$entry" | jq '.payload' >"$payload"
        if ! cf_route_guard_api PUT \
            "/accounts/${CLOUDFLARE_ACCOUNT_ID}/cfd_tunnel/${tunnel_id}/configurations" \
            "$response" "$payload"; then
            printf 'Rollback do Tunnel %s falhou: %s\n' "$tunnel_id" "$CF_ROUTE_GUARD_ERROR" >>"$log_file"
            failed=1
        fi
        rm -f "$payload" "$response"
    done < <(jq -c 'reverse[]?' "$changes" 2>/dev/null)
    [ "$failed" -eq 0 ]
}

cf_route_guard_remove_old_routes() {
    local inventory="$1" hostname="$2" current_tunnel_id="$3" changes="$4" log_file="$5"
    local tunnel tunnel_id config payload response entry
    printf '[]' >"$changes"
    while IFS= read -r tunnel; do
        tunnel_id=$(printf '%s' "$tunnel" | jq -r '.id')
        [ "$tunnel_id" != "$current_tunnel_id" ] || continue
        if ! printf '%s' "$tunnel" | jq -e --arg host "$hostname" \
            'any(.configuration.ingress[]?; .hostname == $host)' >/dev/null 2>&1; then
            continue
        fi
        [ "$(printf '%s' "$tunnel" | jq -r '.configSrc')" = "cloudflare" ] || {
            CF_ROUTE_GUARD_ERROR="A rota pertence a um Tunnel local e não pode ser transferida pela API."
            cf_route_guard_restore_tunnels "$changes" "$log_file" || true
            return 1
        }
        config=$(mktemp) || return 1
        payload=$(mktemp) || { rm -f "$config"; return 1; }
        response=$(mktemp) || { rm -f "$config" "$payload"; return 1; }
        printf '%s' "$tunnel" | jq '.configuration' >"$config"
        jq --arg host "$hostname" '
            . as $cfg | ($cfg.ingress // []) as $ing
            | ($ing | map(select(.hostname != $host and .service != "http_status:404"))) as $routes
            | ($ing | map(select(.service == "http_status:404")) | last // {service:"http_status:404"}) as $fallback
            | {config:($cfg + {ingress:($routes + [$fallback])})}
        ' "$config" >"$payload" || { rm -f "$config" "$payload" "$response"; return 1; }
        entry=$(jq -n --arg id "$tunnel_id" --argjson original "$(cat "$config")" \
            '{tunnelId:$id,payload:{config:$original}}')
        jq --argjson entry "$entry" '. + [$entry]' "$changes" >"${changes}.new" && mv -f "${changes}.new" "$changes"
        if ! cf_route_guard_api PUT \
            "/accounts/${CLOUDFLARE_ACCOUNT_ID}/cfd_tunnel/${tunnel_id}/configurations" \
            "$response" "$payload"; then
            cf_route_guard_restore_tunnels "$changes" "$log_file" || true
            rm -f "$config" "$payload" "$response"
            return 1
        fi
        printf 'Rota antiga removida do Tunnel %s: %s\n' "$tunnel_id" "$hostname" >>"$log_file"
        rm -f "$config" "$payload" "$response"
    done < <(jq -c '.tunnels[]?' "$inventory")
}

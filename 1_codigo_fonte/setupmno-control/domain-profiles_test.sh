#!/usr/bin/bash
set -euo pipefail

project_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source_root=$(cd "$project_dir/.." && pwd)
x86_root="$source_root/x86/SetupLowCodeMno"
arm_root="$source_root/arm/SetupLowCodeMno"
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT

cmp -s "$x86_root/domain_profiles.sh" "$arm_root/domain_profiles.sh"
cmp -s "$x86_root/domain_profile_apps.list" "$arm_root/domain_profile_apps.list"
bash -n "$x86_root/domain_profiles.sh"

[ "$(sort "$x86_root/domain_profile_apps.list" | uniq -d | wc -l)" -eq 0 ]
! grep -Eq '^(dockerswarm|setupmno_control)$' "$x86_root/domain_profile_apps.list"

for architecture_root in "$x86_root" "$arm_root"; do
    install_script="$architecture_root/install.sh"
    [ "$(grep -Fc '"GERENCIAR DOMÍNIOS CLOUDFLARE" ""' "$install_script")" -eq 4 ]
    [ "$(grep -Fc '"GERENCIAR DOMÍNIOS CLOUDFLARE") manage_cloudflare_domains ;;' "$install_script")" -eq 4 ]
    grep -Fq 'setupmno_domain_select_for_app "$script"' "$install_script"
    grep -Fq 'setupmno_domain_clear_selection' "$install_script"
    while IFS= read -r app; do
        script="$architecture_root/${app}.sh"
        [ -f "$script" ] || {
            printf 'ERRO: aplicação multidomínio ausente: %s\n' "$script" >&2
            exit 1
        }
        grep -Fq 'SETUPMNO_CLOUDFLARE_CREDENTIALS_FILE:-/root/.cloudflared_config/cloudflare_credentials' "$script" ||
        grep -Fq 'SETUPMNO_TRADITIONAL_CREDENTIALS_FILE:-/root/.tradicional_config/tradicional_credentials' "$script" || {
            printf 'ERRO: aplicação não aceita credencial selecionada: %s\n' "$script" >&2
            exit 1
        }
        if grep -Fq "cut -d'.' -f2-" "$script"; then
            printf 'ERRO: aplicação ainda tenta inferir a zona removendo o primeiro label: %s\n' "$script" >&2
            exit 1
        fi
        bash -n "$script"
    done <"$architecture_root/domain_profile_apps.list"
done

export SETUPMNO_DOMAIN_TEST_MODE=1
export SETUPMNO_DOMAIN_STATE_DIR="$test_dir/domains"
export SETUPMNO_DOMAIN_REGISTRY="$SETUPMNO_DOMAIN_STATE_DIR/registry.json"
export SETUPMNO_DOMAIN_CREDENTIALS_DIR="$SETUPMNO_DOMAIN_STATE_DIR/credentials.d"
export SETUPMNO_DOMAIN_TUNNELS_DIR="$SETUPMNO_DOMAIN_STATE_DIR/tunnels"
export SETUPMNO_DOMAIN_APP_LIST="$test_dir/apps.list"
. "$x86_root/domain_profiles.sh"

[ "$(setupmno_domain_normalize ' EXEMPLO.COM.BR. ')" = "exemplo.com.br" ]
setupmno_domain_name_valid "exemplo.com.br"
if setupmno_domain_name_valid "dominio-invalido"; then
    printf 'ERRO: domínio sem zona raiz foi aceito.\n' >&2
    exit 1
fi

setupmno_domain_prepare_dirs
credential="$SETUPMNO_DOMAIN_CREDENTIALS_DIR/primary.env"
setupmno_domain_write_credentials "$credential" "token com espaço" \
    "account-test" "zone-test" "exemplo.com.br" "primary" \
    "CLOUDFLARE_TUNNEL" "tunnel-test" "Túnel principal"
[ "$(stat -c '%a' "$credential")" = "600" ]
setupmno_domain_credential_path_valid "$credential"
grep -Fq 'CLOUDFLARE_API_TOKEN=token\ com\ espaço' "$credential"

jq -n --arg credential "$credential" '{
  schemaVersion: 1,
  primaryProfileId: "primary",
  profiles: [{
    id: "primary", name: "Domínio principal", rootDomain: "exemplo.com.br",
    zoneId: "zone-test", accountId: "account-test",
    installationType: "CLOUDFLARE_TUNNEL", credentialFile: $credential,
    tunnelId: "tunnel-test", tunnelScope: "primary", infrastructure: true,
    status: "validated"
  }]
}' >"$SETUPMNO_DOMAIN_REGISTRY"
chmod 600 "$SETUPMNO_DOMAIN_REGISTRY"
setupmno_domain_registry_valid
printf 'aplicacao\n' >"$SETUPMNO_DOMAIN_APP_LIST"
setupmno_domain_select_for_app aplicacao
[ "$SETUPMNO_DOMAIN_PROFILE_ID" = "primary" ]
[ "$SETUPMNO_SELECTED_ROOT_DOMAIN" = "exemplo.com.br" ]
[ "$SETUPMNO_DOMAIN_ROOT" = "exemplo.com.br" ]
[ "$SETUPMNO_CLOUDFLARE_CREDENTIALS_FILE" = "$credential" ]
setupmno_domain_clear_selection
[ -z "${SETUPMNO_DOMAIN_PROFILE_ID:-}" ]
[ -z "${SETUPMNO_SELECTED_ROOT_DOMAIN:-}" ]
[ -z "${SETUPMNO_DOMAIN_ROOT:-}" ]

traditional_credential="$SETUPMNO_DOMAIN_CREDENTIALS_DIR/domain-cliente.env"
setupmno_domain_write_credentials "$traditional_credential" "token adicional" \
    "account-traditional" "zone-traditional" "cliente.com.br" "domain-cliente" \
    "TRADICIONAL" "" "" "setupmno-origin-cliente"
updated_registry="$test_dir/registry-updated.json"
jq --arg credential "$traditional_credential" '.profiles += [{
    id: "domain-cliente", name: "cliente.com.br", rootDomain: "cliente.com.br",
    zoneId: "zone-traditional", accountId: "account-traditional",
    installationType: "TRADICIONAL", credentialFile: $credential,
    tunnelId: "", tunnelScope: "none", infrastructure: false,
    status: "validated"
}]' "$SETUPMNO_DOMAIN_REGISTRY" >"$updated_registry"
mv "$updated_registry" "$SETUPMNO_DOMAIN_REGISTRY"
chmod 600 "$SETUPMNO_DOMAIN_REGISTRY"
setupmno_domain_registry_valid
setupmno_domain_load_profile domain-cliente
[ "$SETUPMNO_SELECTED_ROOT_DOMAIN" = "cliente.com.br" ]
. "$traditional_credential"
[ "${nome_servidor}.${SETUPMNO_DOMAIN_ROOT}" = "setupmno-origin-cliente.cliente.com.br" ]
for requested_hostname in cliente.com.br wordpress.cliente.com.br; do
    case "$requested_hostname" in
        "$SETUPMNO_DOMAIN_ROOT"|*."$SETUPMNO_DOMAIN_ROOT") ;;
        *) printf 'ERRO: hostname válido rejeitado no cenário tradicional: %s\n' "$requested_hostname" >&2; exit 1 ;;
    esac
done
setupmno_domain_load_profile primary
. "$credential"
for requested_hostname in exemplo.com.br wordpress.exemplo.com.br; do
    case "$requested_hostname" in
        "$SETUPMNO_DOMAIN_ROOT"|*."$SETUPMNO_DOMAIN_ROOT") ;;
        *) printf 'ERRO: hostname válido rejeitado no cenário Tunnel: %s\n' "$requested_hostname" >&2; exit 1 ;;
    esac
    [ "${TUNNEL_ID}.cfargotunnel.com" = "tunnel-test.cfargotunnel.com" ]
done
setupmno_domain_clear_selection

api_log="$test_dir/cloudflare-api.log"
setupmno_cf_request() {
    local method="$1" endpoint="$2" token="$3" output="$4"
    printf '%s %s %s\n' "$method" "$endpoint" "$token" >>"$api_log"
    case "$method:$endpoint" in
        POST:/zones/zone-test/dns_records)
            printf '%s\n' '{"success":true,"result":{"id":"record-test"}}' >"$output"
            ;;
        DELETE:/zones/zone-test/dns_records/record-test)
            printf '%s\n' '{"success":true,"result":{"id":"record-test"}}' >"$output"
            ;;
        GET:/accounts/account-test/cfd_tunnel/tunnel-test/configurations)
            printf '%s\n' '{"success":true,"result":{"config":{"ingress":[{"service":"http_status:404"}]}}}' >"$output"
            ;;
        PUT:/accounts/account-test/cfd_tunnel/tunnel-test/configurations)
            printf '%s\n' '{"success":true,"result":{}}' >"$output"
            ;;
        *)
            printf 'ERRO: chamada Cloudflare simulada inesperada: %s %s\n' "$method" "$endpoint" >&2
            return 1
            ;;
    esac
}

setupmno_domain_dns_write_probe "token-teste" "zone-test" "exemplo.com.br"
setupmno_domain_tunnel_write_probe "token-teste" "account-test" "tunnel-test"
grep -Fq 'POST /zones/zone-test/dns_records token-teste' "$api_log"
grep -Fq 'DELETE /zones/zone-test/dns_records/record-test token-teste' "$api_log"
grep -Fq 'PUT /accounts/account-test/cfd_tunnel/tunnel-test/configurations token-teste' "$api_log"

printf 'Perfis multidomínio, isolamento de credenciais e probes Cloudflare aprovados.\n'

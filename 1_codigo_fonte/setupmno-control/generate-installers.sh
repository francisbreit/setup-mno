#!/usr/bin/bash
set -euo pipefail

project_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source_root=$(cd "$project_dir/.." && pwd)
template="$project_dir/installer-template.sh"
x86_target="$source_root/x86/SetupLowCodeMno/setupmno_control.sh"
arm_target="$source_root/arm/SetupLowCodeMno/setupmno_control.sh"
x86_runtime_package="$source_root/x86/SetupLowCodeMno/.control-package"
arm_runtime_package="$source_root/arm/SetupLowCodeMno/.control-package"
temporary_dir=$(mktemp -d)
trap 'rm -rf "$temporary_dir"' EXIT

bundle="$temporary_dir/setupmno-control.tar.gz"
(
    cd "$project_dir"
    tar -czf "$bundle" \
        go.mod Dockerfile terminal.Dockerfile prepare-ttyd-index.sh main.go catalog.json web
)
base64 -w 76 "$bundle" >"$temporary_dir/bundle.b64"

generate_target() {
    local target="$1"
    awk -v bundle_file="$temporary_dir/bundle.b64" '
        /^__SETUPMNO_CONTROL_BUNDLE__$/ {
            while ((getline line < bundle_file) > 0) print line
            close(bundle_file)
            next
        }
        { print }
    ' "$template" >"$target"
    chmod 0755 "$target"
}

generate_target "$x86_target"
generate_target "$arm_target"

cmp -s "$x86_target" "$arm_target"

x86_version=$(sed -n 's/^VERSIONSETUP="\([^"]*\)"/\1/p' "$source_root/x86/SetupLowCodeMno/install.sh" | head -n1)
[ -n "$x86_version" ] || {
    printf 'ERRO: VERSIONSETUP não encontrado no install.sh x86.\n' >&2
    exit 1
}
version_files=(
    "$source_root/x86/SetupLowCodeMno/install.sh"
    "$source_root/arm/SetupLowCodeMno/install.sh"
    "$source_root/x86/start_full.sh"
    "$source_root/arm/start_arm_full.sh"
    "$source_root/setup-mno.sh"
    "$source_root/setup-mno-oracle.sh"
)
for version_file in "${version_files[@]}"; do
    detected_version=$(sed -n 's/^VERSIONSETUP="\([^"]*\)"/\1/p' "$version_file" | head -n1)
    [ "$detected_version" = "$x86_version" ] || {
        printf 'ERRO: versão divergente em %s (esperada %s, encontrada %s).\n' \
            "$version_file" "$x86_version" "${detected_version:-ausente}" >&2
        exit 1
    }
done
grep -Fq "Versão $x86_version" "$source_root/ferramentas.html"
grep -Fq "Setup MNO v$x86_version" "$source_root/ferramentas.html"

control_version=$(sed -n 's/^CONTROL_VERSION="\([^"]*\)"/\1/p' "$template" | head -n1)
[ -n "$control_version" ]
grep -Fq "/styles.css?v=$control_version" "$project_dir/web/index.html"
grep -Fq "/app.js?v=$control_version" "$project_dir/web/index.html"

catalog_sha=$(sha256sum "$project_dir/catalog.json" | awk '{print $1}')
catalog_entries=$(jq -e 'length' "$project_dir/catalog.json")
[ "$catalog_entries" -gt 0 ]
catalog_arm_entries=$(jq -e '[.[] | select(.arch == "x86-arm")] | length' "$project_dir/catalog.json")

count_pro_menu() {
    local install_file="$1"
    awk '
        /whiptail --title .*--menu/ { inside=1; next }
        inside && match($0, /^[[:space:]]*"([^"]+)"/, item) {
            name=item[1]
            if (name != "REINICIAR APPS/SERVIÇOS" &&
                name != "DELETAR APPS/STACKS" &&
                name != "GERADOR DE REGISTROS DNS" &&
                name != "ESSENCIAIS EDITÁVEIS NO PORTAINER" &&
                name != "SAIR" &&
                name !~ /^─+$/) count++
        }
        inside && /3>&2 2>&1 1>&3/ { print count; exit }
    ' "$install_file"
}

x86_menu_entries=$(count_pro_menu "$source_root/x86/SetupLowCodeMno/install.sh")
arm_menu_entries=$(count_pro_menu "$source_root/arm/SetupLowCodeMno/install.sh")
[ "$x86_menu_entries" = "$catalog_entries" ] || {
    printf 'ERRO: menu PRO x86 (%s) diverge do catálogo (%s).\n' \
        "$x86_menu_entries" "$catalog_entries" >&2
    exit 1
}
[ "$arm_menu_entries" = "$catalog_arm_entries" ] || {
    printf 'ERRO: menu PRO ARM (%s) diverge dos itens multi-arquitetura (%s).\n' \
        "$arm_menu_entries" "$catalog_arm_entries" >&2
    exit 1
}

generate_runtime_package() {
    local target="$1" architecture="$2" temporary_manifest
    mkdir -p "$target"
    install -m 0644 "$project_dir/catalog.json" "$target/catalog.json"
    temporary_manifest="$target/release.json.tmp"
    jq -n \
        --arg setup_version "$x86_version" \
        --arg catalog_sha "$catalog_sha" \
        --arg architecture "$architecture" \
        --argjson catalog_entries "$catalog_entries" \
        '{
            schemaVersion: 1,
            setupVersion: $setup_version,
            catalogVersion: $setup_version,
            catalogSHA256: $catalog_sha,
            catalogEntries: $catalog_entries,
            architecture: $architecture
        }' >"$temporary_manifest"
    chmod 0644 "$temporary_manifest"
    mv -f "$temporary_manifest" "$target/release.json"
}

generate_runtime_package "$x86_runtime_package" "amd64"
generate_runtime_package "$arm_runtime_package" "arm64"

printf 'Instaladores x86/ARM e manifestos runtime v%s gerados (%s setups).\n' \
    "$x86_version" "$catalog_entries"

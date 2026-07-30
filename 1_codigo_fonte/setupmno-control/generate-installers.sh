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

msg_function=$(awk '/^msg\(\)/,/^}/' "$template")
grep -Fq '1>&2' <<<"$msg_function" || {
    printf 'ERRO: msg() precisa direcionar a interface Whiptail para stderr.\n' >&2
    exit 1
}
for collector in ask_required ask_with_default ask_openai_key ask_password; do
    collector_function=$(awk -v name="$collector" '
        $0 ~ "^" name "\\(\\)" { inside=1 }
        inside { print }
        inside && /^}/ { exit }
    ' "$template")
    grep -Fq 'return 130' <<<"$collector_function" || {
        printf 'ERRO: %s não propaga o cancelamento ao chamador.\n' "$collector" >&2
        exit 1
    }
    if grep -Fq 'exit 0' <<<"$collector_function"; then
        printf 'ERRO: %s encerra apenas o subshell da coleta.\n' "$collector" >&2
        exit 1
    fi
done
unhandled_collectors=$(grep -E '^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*=\$\(ask_' "$template" || true)
[ -z "$unhandled_collectors" ] || {
    printf 'ERRO: coleta Whiptail sem tratamento explícito de cancelamento:\n%s\n' \
        "$unhandled_collectors" >&2
    exit 1
}

grep -Fq -- '- /root/SetupLowCodeMno/.control:/runtime-control:ro' "$template" || {
    printf 'ERRO: o agente precisa montar somente o estado runtime do Control Center.\n' >&2
    exit 1
}
if grep -Fq -- '- /root:/hostfs' "$template"; then
    printf 'ERRO: o agente não pode montar o diretório /root inteiro.\n' >&2
    exit 1
fi
grep -Fq 'HEALTHCHECK_URL=http://127.0.0.1:9090/health' "$template" || {
    printf 'ERRO: healthcheck interno do agente não configurado.\n' >&2
    exit 1
}
grep -Fq 'http://127.0.0.1:7681/terminal/' "$template" || {
    printf 'ERRO: healthcheck interno do terminal não configurado.\n' >&2
    exit 1
}
[ "$(grep -Fc 'user: "65532:65532"' "$template")" -eq 2 ] || {
    printf 'ERRO: web e Assistente precisam executar como usuário não-root.\n' >&2
    exit 1
}
[ "$(grep -c '^[[:space:]]*cap_drop:' "$template")" -eq 3 ] || {
    printf 'ERRO: hardening cap_drop divergente entre agente, Assistente e web.\n' >&2
    exit 1
}
grep -Fq 'KNOWLEDGE_PACKAGE_DIR=/knowledge-package' "$template" || {
    printf 'ERRO: Assistente sem caminho explícito para o conhecimento somente leitura.\n' >&2
    exit 1
}
assistant_stack_block=$(awk '
    /cat >"\$\{assistant_stack\}\.yaml"/ { inside=1 }
    inside { print }
    inside && /cat >"\$\{web_stack\}\.yaml"/ { exit }
' "$template")
if grep -Eq '^[[:space:]]+volumes:' <<<"$assistant_stack_block"; then
    printf 'ERRO: a stack do Assistente não pode montar volumes.\n' >&2
    exit 1
fi
grep -Fq 'COPY --from=builder /src/knowledge-package /knowledge-package' \
    "$project_dir/Dockerfile" || {
    printf 'ERRO: a imagem final não contém o pacote de conhecimento somente leitura.\n' >&2
    exit 1
}
grep -Fq '//go:embed knowledge-package/*' "$project_dir/knowledge.go" || {
    printf 'ERRO: o fallback de conhecimento não está embutido no binário.\n' >&2
    exit 1
}

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
grep -Fq "/markdown.js?v=$control_version" "$project_dir/web/index.html"
grep -Fq "/app.js?v=$control_version" "$project_dir/web/index.html"

knowledge_package="$project_dir/knowledge-package"
python3 -B "$source_root/setupmno-knowledge/tools/generate_package.py" \
    --root "$source_root/setupmno-knowledge" \
    --catalog "$project_dir/catalog.json" \
    --output "$knowledge_package" \
    --setup-version "$x86_version" \
    --control-version "$control_version"

[ -f "$knowledge_package/manifest.json" ] &&
[ ! -L "$knowledge_package/manifest.json" ] &&
[ -f "$knowledge_package/knowledge-package.tar.gz" ] &&
[ ! -L "$knowledge_package/knowledge-package.tar.gz" ] || {
    printf 'ERRO: pacote de conhecimento ausente ou não regular.\n' >&2
    exit 1
}
knowledge_schema=$(jq -r '.schemaVersion // 0' "$knowledge_package/manifest.json")
knowledge_version=$(jq -r '.knowledgeVersion // empty' "$knowledge_package/manifest.json")
knowledge_setup_version=$(jq -r '.setupVersion // empty' "$knowledge_package/manifest.json")
knowledge_control_version=$(jq -r '.controlVersion // empty' "$knowledge_package/manifest.json")
knowledge_entries=$(jq -r '.documentEntries // 0' "$knowledge_package/manifest.json")
knowledge_archive_sha=$(jq -r '.archiveSHA256 // empty' "$knowledge_package/manifest.json")
knowledge_archive_bytes=$(jq -r '.archiveBytes // 0' "$knowledge_package/manifest.json")
knowledge_actual_sha=$(sha256sum "$knowledge_package/knowledge-package.tar.gz" | awk '{print $1}')
knowledge_actual_bytes=$(stat -c '%s' "$knowledge_package/knowledge-package.tar.gz")
[ "$knowledge_schema" = "1" ] &&
[ -n "$knowledge_version" ] &&
[ "$knowledge_setup_version" = "$x86_version" ] &&
[ "$knowledge_control_version" = "$control_version" ] &&
[ "$knowledge_entries" -gt 0 ] &&
[ "$knowledge_archive_sha" = "$knowledge_actual_sha" ] &&
[ "$knowledge_archive_bytes" = "$knowledge_actual_bytes" ] &&
[ "$knowledge_archive_bytes" -le $((8 * 1024 * 1024)) ] || {
    printf 'ERRO: manifesto do conhecimento inválido ou incompatível.\n' >&2
    exit 1
}

bundle="$temporary_dir/setupmno-control.tar.gz"
(
    cd "$project_dir"
    tar -czf "$bundle" \
        go.mod Dockerfile terminal.Dockerfile prepare-ttyd-index.sh \
        main.go knowledge.go catalog.json knowledge-package web
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
    mkdir -p "$target/knowledge-package"
    install -m 0644 "$knowledge_package/manifest.json" \
        "$target/knowledge-package/manifest.json"
    install -m 0644 "$knowledge_package/knowledge-package.tar.gz" \
        "$target/knowledge-package/knowledge-package.tar.gz"
    temporary_manifest="$target/release.json.tmp"
    jq -n \
        --arg setup_version "$x86_version" \
        --arg catalog_sha "$catalog_sha" \
        --arg architecture "$architecture" \
        --arg knowledge_version "$knowledge_version" \
        --arg knowledge_archive_sha "$knowledge_archive_sha" \
        --argjson catalog_entries "$catalog_entries" \
        --argjson knowledge_entries "$knowledge_entries" \
        '{
            schemaVersion: 1,
            setupVersion: $setup_version,
            catalogVersion: $setup_version,
            catalogSHA256: $catalog_sha,
            catalogEntries: $catalog_entries,
            architecture: $architecture,
            knowledgeVersion: $knowledge_version,
            knowledgeArchiveSHA256: $knowledge_archive_sha,
            knowledgeEntries: $knowledge_entries
        }' >"$temporary_manifest"
    chmod 0644 "$temporary_manifest"
    mv -f "$temporary_manifest" "$target/release.json"
}

generate_runtime_package "$x86_runtime_package" "amd64"
generate_runtime_package "$arm_runtime_package" "arm64"

cmp -s "$x86_runtime_package/knowledge-package/manifest.json" \
    "$arm_runtime_package/knowledge-package/manifest.json"
cmp -s "$x86_runtime_package/knowledge-package/knowledge-package.tar.gz" \
    "$arm_runtime_package/knowledge-package/knowledge-package.tar.gz"

printf 'Instaladores x86/ARM e manifestos runtime v%s gerados (%s setups, %s documentos).\n' \
    "$x86_version" "$catalog_entries" "$knowledge_entries"

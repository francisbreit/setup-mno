#!/usr/bin/bash
# Gera exclusivamente o instalador Beta. O Control Center oficial não é tocado.
set -euo pipefail

project_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source_root=$(cd "$project_dir/.." && pwd)
template="$project_dir/installer-template.sh"
x86_target="$source_root/x86/SetupLowCodeMno/setupmno_control_2_beta.sh"
arm_target="$source_root/arm/SetupLowCodeMno/setupmno_control_2_beta.sh"
x86_package="$source_root/x86/SetupLowCodeMno/.control2-beta-package"
arm_package="$source_root/arm/SetupLowCodeMno/.control2-beta-package"
temporary_dir=$(mktemp -d)
trap 'rm -rf "$temporary_dir"' EXIT

setup_version=$(sed -n 's/^VERSIONSETUP="\([^"]*\)"/\1/p' \
    "$source_root/x86/SetupLowCodeMno/install.sh" | head -n1)
control_version=$(sed -n 's/^CONTROL_VERSION="\([^"]*\)"/\1/p' "$template" | head -n1)
[ -n "$setup_version" ] && [ -n "$control_version" ]

bash -n "$template"
grep -Fq 'BETA_USER_DATA_DIR="/var/lib/setupmno/control-center-2-beta/user-data"' "$template"
grep -Fq 'mnoctrl2' "$template"
grep -Fq '/root/SetupLowCodeMno/.control2-beta-package/control-source.tar.gz' "$template"

install -m 0755 "$template" "$x86_target"
install -m 0755 "$template" "$arm_target"
cmp -s "$x86_target" "$arm_target"
for target in "$x86_target" "$arm_target"; do
    test "$(stat -c '%s' "$target")" -le 122880
done

smoke_source="$temporary_dir/setupmno_control_2_beta.sh"
smoke_binary="$temporary_dir/setupmno_control_2_beta"
install -m 0755 "$x86_target" "$smoke_source"
(
    cd "$temporary_dir"
    shc -e "$(date +'%d/%m/%Y' -d '+7 days')" -m 'Smoke test Control Center 2 Beta' \
        -o "$smoke_binary" -f "$smoke_source"
)
[ "$(SETUPMNO_SHC_SMOKE_TEST=1 "$smoke_binary")" = "setupmno-control-2-beta-shc-ok" ]

bundle="$temporary_dir/control-center-2-beta-source.tar.gz"
(
    cd "$project_dir"
    tar -cf - \
        go.mod Dockerfile terminal.Dockerfile prepare-ttyd-index.sh terminal-menu.sh \
        configure-control.sh control-upgrade.sh main.go knowledge.go retrieval.go routing.go \
        prompts.go blueprint_recommendation.go evals.go provider_evals.go feedback.go web |
        gzip -9n >"$bundle"
)
bundle_sha=$(sha256sum "$bundle" | awk '{print $1}')
bundle_bytes=$(stat -c '%s' "$bundle")
test "$bundle_bytes" -gt 0
test "$bundle_bytes" -le $((2 * 1024 * 1024))

catalog_sha=$(sha256sum "$project_dir/catalog.json" | awk '{print $1}')
catalog_entries=$(jq -e 'length' "$project_dir/catalog.json")
for item in "$x86_package:amd64" "$arm_package:arm64"; do
    package=${item%%:*}
    architecture=${item##*:}
    rm -rf "$package"
    mkdir -p "$package"
    install -m 0644 "$bundle" "$package/control-source.tar.gz"
    install -m 0644 "$project_dir/catalog.json" "$package/catalog.json"
    jq -n \
        --arg setup_version "$setup_version" \
        --arg control_version "$control_version" \
        --arg architecture "$architecture" \
        --arg catalog_sha "$catalog_sha" \
        --arg source_sha "$bundle_sha" \
        --argjson catalog_entries "$catalog_entries" \
        --argjson source_bytes "$bundle_bytes" \
        '{schemaVersion:1, setupVersion:$setup_version, controlVersion:$control_version, architecture:$architecture, catalogSHA256:$catalog_sha, catalogEntries:$catalog_entries, controlSourceSHA256:$source_sha, controlSourceBytes:$source_bytes}' \
        >"$package/release.json"
done
cmp -s "$x86_package/control-source.tar.gz" "$arm_package/control-source.tar.gz"
printf 'Control Center 2 Beta gerado: Setup MNO v%s, Beta v%s.\n' "$setup_version" "$control_version"

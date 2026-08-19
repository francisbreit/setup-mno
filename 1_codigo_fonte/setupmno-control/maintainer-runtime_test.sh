#!/usr/bin/bash
set -Eeuo pipefail

project_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source_root=$(cd "$project_dir/.." && pwd)
mkdir -p /tmp/setupmno-maintainer-workspace
test_root=$(mktemp -d /tmp/setupmno-maintainer-workspace/test.XXXXXX)
trap 'rm -rf -- "$test_root"' EXIT
runtime="$test_root/runtime"
workspace="$test_root/workspace"
package="$runtime/homologation-package"
mkdir -p "$package"
setup_version=$(sed -n 's/^VERSIONSETUP="\([0-9][0-9.]*\)"$/\1/p' \
    "$source_root/x86/SetupLowCodeMno/install.sh" | head -n 1)
[ -n "$setup_version" ] || {
    printf 'Não foi possível descobrir a versão corrente do Setup MNO.\n' >&2
    exit 1
}

python3 -B "$source_root/setupmno-knowledge/tools/generate_homologation_package.py" \
    --root "$source_root/setupmno-knowledge" --output "$package" --setup-version "$setup_version" >/dev/null
catalog_sha=$(sha256sum "$source_root/setupmno-control/catalog.json" | awk '{print $1}')
manifest_sha=$(sha256sum "$package/manifest.json" | awk '{print $1}')
jq -n --arg version "$setup_version" --arg catalog "$catalog_sha" --arg manifest "$manifest_sha" \
    '{schemaVersion:1,setupVersion:$version,catalogSHA256:$catalog,homologationPackageManifestSHA256:$manifest}' \
    >"$runtime/release.json"

SETUPMNO_RUNTIME_ROOT="$runtime" SETUPMNO_MAINTAINER_WORK_ROOT="$workspace" \
    bash -c 'source "$1"; setupmno_prepare_maintainer_workspace; test -f "$SETUPMNO_MAINTAINER_KNOWLEDGE_ROOT/tools/certify_homologation.py"; test -f "$SETUPMNO_MAINTAINER_CATALOG"' \
    _ "$source_root/setupmno-knowledge/tools/maintainer_workspace.sh"
SETUPMNO_RUNTIME_ROOT="$runtime" SETUPMNO_MAINTAINER_WORK_ROOT="$workspace" \
    bash -c 'source "$1"; setupmno_prepare_maintainer_workspace' \
    _ "$source_root/setupmno-knowledge/tools/maintainer_workspace.sh"

jq '.setupVersion="0.0.0"' "$runtime/release.json" >"$runtime/release.json.tmp"
mv "$runtime/release.json.tmp" "$runtime/release.json"
if SETUPMNO_RUNTIME_ROOT="$runtime" SETUPMNO_MAINTAINER_WORK_ROOT="$workspace" \
    bash -c 'source "$1"; setupmno_prepare_maintainer_workspace' \
    _ "$source_root/setupmno-knowledge/tools/maintainer_workspace.sh" >/dev/null 2>&1; then
    printf 'Workspace aceitou release adulterada.\n' >&2
    exit 1
fi

printf 'Workspace PRO MASTER autenticado, persistente e fail closed aprovado.\n'

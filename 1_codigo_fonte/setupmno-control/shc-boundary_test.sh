#!/usr/bin/bash
set -euo pipefail

project_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source_root=$(cd "$project_dir/.." && pwd)
test_dir=$(mktemp -d)
trap 'rm -rf -- "$test_dir"' EXIT

python3 -B "$project_dir/shc_boundary.py" audit \
    --source-root "$source_root" \
    --policy "$project_dir/shc-boundary-policy.json" >/dev/null

package="$test_dir/package"
mkdir -p "$package/sre-engine" "$package/supply-chain"
printf 'resultado sanitizado\n' >"$package/sre-engine/facts.json"
printf 'sbom\n' >"$package/supply-chain/sbom.cdx.json"
python3 -B "$project_dir/shc_boundary.py" generate \
    --package "$package" --policy "$project_dir/shc-boundary-policy.json" \
    --setup-version 7.33.5 --architecture amd64 >/dev/null
python3 -B "$project_dir/shc_boundary.py" validate \
    --package "$package" --policy "$project_dir/shc-boundary-policy.json" \
    --setup-version 7.33.5 --architecture amd64 >/dev/null

printf 'adulterado\n' >>"$package/sre-engine/facts.json"
if python3 -B "$project_dir/shc_boundary.py" validate \
    --package "$package" --policy "$project_dir/shc-boundary-policy.json" \
    --setup-version 7.33.5 --architecture amd64 >/dev/null 2>&1; then
    printf 'ERRO: modulo externo adulterado foi aceito.\n' >&2
    exit 1
fi

cp "$source_root/x86/start_full.sh" "$test_dir/start.sh"
printf '{"release":"original"}\n' >"$test_dir/release.json"
python3 -B "$project_dir/shc_boundary.py" bind \
    --start-script "$test_dir/start.sh" --release "$test_dir/release.json" >/dev/null
python3 -B "$project_dir/shc_boundary.py" assert-anchor \
    --start-script "$test_dir/start.sh" --release "$test_dir/release.json"
printf '{"release":"trocada junto com o manifesto"}\n' >"$test_dir/release.json"
if python3 -B "$project_dir/shc_boundary.py" assert-anchor \
    --start-script "$test_dir/start.sh" --release "$test_dir/release.json" >/dev/null 2>&1; then
    printf 'ERRO: manifesto substituido fora do SHC foi aceito.\n' >&2
    exit 1
fi

printf 'Fronteira SHC, inventario externo e ancora protegida aprovados.\n'

#!/usr/bin/env bash
set -euo pipefail

project_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source_root=$(cd "$project_dir/.." && pwd)
html="$source_root/ferramentas.html"
catalog="$project_dir/catalog.json"
temporary_dir=$(mktemp -d)
trap 'rm -rf "$temporary_dir"' EXIT

fail() {
    printf 'FALHA: %s\n' "$1" >&2
    exit 1
}

sed -n '/^[[:space:]]*const STATIC_CATALOG=\[/ {
    s/^[[:space:]]*const STATIC_CATALOG=//
    s/;$//
    p
    q
}' "$html" >"$temporary_dir/html-catalog.json"

jq -e 'type == "array" and length > 0' "$temporary_dir/html-catalog.json" >/dev/null || \
    fail "STATIC_CATALOG ausente ou inválido"

cmp -s "$temporary_dir/html-catalog.json" <(jq -c . "$catalog") || \
    fail "STATIC_CATALOG diverge do catalog.json canônico"

if grep -Fq 'STATIC_CATALOG.push(' "$html"; then
    fail "ferramentas.html adiciona entradas extras após o catálogo canônico"
fi

catalog_total=$(jq length "$catalog")
catalog_unique=$(jq '[.[].name] | unique | length' "$catalog")
catalog_arm=$(jq '[.[] | select(.arch == "x86-arm")] | length' "$catalog")
html_total=$(grep -o 'Total de Setups (Deploys / Instalações): [0-9]*' "$html" | awk '{print $NF}')
html_x86=$(grep -o 'Total de Setups Arquitetura X86: [0-9]*' "$html" | awk '{print $NF}')
html_arm=$(grep -o 'Total de Setups Arquitetura ARM: [0-9]*' "$html" | awk '{print $NF}')

[ "$catalog_total" = "$catalog_unique" ] || fail "catalog.json contém nomes duplicados"
[ "$html_total" = "$catalog_total" ] || fail "total geral do cabeçalho diverge do catálogo"
[ "$html_x86" = "$catalog_total" ] || fail "total x86 do cabeçalho diverge do catálogo"
[ "$html_arm" = "$catalog_arm" ] || fail "total ARM do cabeçalho diverge do catálogo"

printf 'OK: catálogo HTML exibe %s de %s setups únicos (%s ARM).\n' \
    "$catalog_total" "$catalog_total" "$catalog_arm"

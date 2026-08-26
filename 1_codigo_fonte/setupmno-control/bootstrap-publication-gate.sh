#!/usr/bin/bash
set -euo pipefail

project_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
repository_root=$(cd "$project_dir/../.." && pwd)
published_source="${1:-https://ativa2.manualnegocioonline.com.br}"
expected_dir="${2:-$repository_root/3_distribuicao}"
temporary_dir=$(mktemp -d)
trap 'rm -rf -- "$temporary_dir"' EXIT

command -v curl >/dev/null 2>&1 || {
    printf 'ERRO: curl e obrigatorio para validar uma URL publicada.\n' >&2
    exit 2
}

for bootstrap_name in setup-mno.sh setup-mno-oracle.sh; do
    published_file="$temporary_dir/$bootstrap_name"
    expected_file="$expected_dir/$bootstrap_name"

    if [[ "$published_source" =~ ^https?:// ]]; then
        curl --fail --location --silent --show-error \
            "$published_source/$bootstrap_name" -o "$published_file"
    else
        cp -- "$published_source/$bootstrap_name" "$published_file"
    fi

    [ -f "$expected_file" ] || {
        printf 'ERRO: artefato esperado ausente: %s\n' "$expected_file" >&2
        exit 3
    }
    bash -n "$published_file" || {
        printf 'ERRO: %s publicado possui sintaxe Bash invalida.\n' \
            "$bootstrap_name" >&2
        exit 4
    }
    cmp -s "$published_file" "$expected_file" || {
        printf 'ERRO: %s publicado nao e identico ao pacote aprovado.\n' \
            "$bootstrap_name" >&2
        exit 5
    }

    printf 'PUBLIC_BOOTSTRAP_OK file=%s sha256=%s\n' \
        "$bootstrap_name" "$(sha256sum "$published_file" | awk '{print $1}')"
done

printf 'PUBLIC_BOOTSTRAP_GATE_OK source=%s\n' "$published_source"

#!/usr/bin/env bash
set -euo pipefail

project_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source_root=$(cd "$project_dir/.." && pwd)
temporary_dir=$(mktemp -d)
trap 'rm -rf "$temporary_dir"' EXIT

fail() {
    printf 'FALHA: %s\n' "$1" >&2
    exit 1
}

extract_recovery_function() {
    awk '
        /^setupmno_prepare_debian13_apt\(\) \{/ { inside=1 }
        inside { print }
        inside && /^}/ { exit }
    ' "$1"
}

prepare_root() {
    local root="$1" id="$2" version="$3"
    mkdir -p "$root/etc/apt/sources.list.d" "$root/usr/lib" "$root/usr/share/keyrings"
    printf 'ID="%s"\nVERSION_ID="%s"\n' "$id" "$version" >"$root/usr/lib/os-release"
    ln -s ../usr/lib/os-release "$root/etc/os-release"
    printf '%s\n' \
        'deb [signed-by=/usr/share/keyrings/azlux-archive-keyring.gpg] http://packages.azlux.fr/debian stable main' \
        >"$root/etc/apt/sources.list.d/azlux.list"
    printf 'legacy-public-key\n' >"$root/usr/share/keyrings/azlux-archive-keyring.gpg"
    chmod 0600 "$root/usr/share/keyrings/azlux-archive-keyring.gpg"
}

assert_legacy_present() {
    local root="$1"
    [ -f "$root/etc/apt/sources.list.d/azlux.list" ] || fail "fonte Azlux removida fora do Debian 13"
    [ -f "$root/usr/share/keyrings/azlux-archive-keyring.gpg" ] || fail "chave Azlux removida fora do Debian 13"
}

scripts=(
    "$source_root/setup-mno.sh"
    "$source_root/setup-mno-oracle.sh"
    "$source_root/x86/start_full.sh"
    "$source_root/arm/start_arm_full.sh"
)

for script in "${scripts[@]}"; do
    unset -f setupmno_prepare_debian13_apt 2>/dev/null || true
    eval "$(extract_recovery_function "$script")"
    declare -F setupmno_prepare_debian13_apt >/dev/null || fail "função ausente em $script"

    case_dir="$temporary_dir/$(basename "$script")-${RANDOM}"
    prepare_root "$case_dir/debian13" debian 13
    SETUPMNO_APT_ROOT="$case_dir/debian13" setupmno_prepare_debian13_apt
    [ ! -e "$case_dir/debian13/etc/apt/sources.list.d/azlux.list" ] || fail "fonte Azlux não removida por $script"
    [ ! -e "$case_dir/debian13/usr/share/keyrings/azlux-archive-keyring.gpg" ] || fail "chave Azlux não removida por $script"
    SETUPMNO_APT_ROOT="$case_dir/debian13" setupmno_prepare_debian13_apt

    prepare_root "$case_dir/debian12" debian 12
    SETUPMNO_APT_ROOT="$case_dir/debian12" setupmno_prepare_debian13_apt
    assert_legacy_present "$case_dir/debian12"

    prepare_root "$case_dir/ubuntu" ubuntu 24.04
    SETUPMNO_APT_ROOT="$case_dir/ubuntu" setupmno_prepare_debian13_apt
    assert_legacy_present "$case_dir/ubuntu"

    mkdir -p "$case_dir/missing/etc" "$case_dir/missing/usr/lib"
    printf 'ID=debian\nVERSION_ID=13\n' >"$case_dir/missing/usr/lib/os-release"
    ln -s ../usr/lib/os-release "$case_dir/missing/etc/os-release"
    SETUPMNO_APT_ROOT="$case_dir/missing" setupmno_prepare_debian13_apt

    prepare_root "$case_dir/foreign" debian 13
    printf 'deb https://example.invalid/debian stable main\n' >"$case_dir/foreign/etc/apt/sources.list.d/azlux.list"
    if SETUPMNO_APT_ROOT="$case_dir/foreign" setupmno_prepare_debian13_apt; then
        fail "arquivo azlux.list com conteúdo estranho foi removido por $script"
    fi
    assert_legacy_present "$case_dir/foreign"

    prepare_root "$case_dir/source-symlink" debian 13
    mv "$case_dir/source-symlink/etc/apt/sources.list.d/azlux.list" "$case_dir/source-symlink/source-target.list"
    ln -s "$case_dir/source-symlink/source-target.list" "$case_dir/source-symlink/etc/apt/sources.list.d/azlux.list"
    if SETUPMNO_APT_ROOT="$case_dir/source-symlink" setupmno_prepare_debian13_apt; then
        fail "link simbólico de fonte aceito em $script"
    fi
    [ -f "$case_dir/source-symlink/source-target.list" ] || fail "alvo da fonte simbólica foi alterado"

    prepare_root "$case_dir/key-symlink" debian 13
    mv "$case_dir/key-symlink/usr/share/keyrings/azlux-archive-keyring.gpg" "$case_dir/key-symlink/key-target.gpg"
    ln -s "$case_dir/key-symlink/key-target.gpg" "$case_dir/key-symlink/usr/share/keyrings/azlux-archive-keyring.gpg"
    if SETUPMNO_APT_ROOT="$case_dir/key-symlink" setupmno_prepare_debian13_apt; then
        fail "link simbólico de chave aceito em $script"
    fi
    [ -f "$case_dir/key-symlink/key-target.gpg" ] || fail "alvo da chave simbólica foi alterado"
done

for script in "$source_root/setup-mno.sh" "$source_root/setup-mno-oracle.sh"; do
    recovery_line=$(grep -n '^if ! setupmno_prepare_debian13_apt; then' "$script" | head -n1 | cut -d: -f1)
    apt_line=$(grep -n 'execute_with_spinner "apt-get update -y"' "$script" | head -n1 | cut -d: -f1)
    [ -n "$recovery_line" ] && [ -n "$apt_line" ] && [ "$recovery_line" -lt "$apt_line" ] || \
        fail "limpeza não ocorre antes do apt-get update em $script"
done

for script in "$source_root/x86/start_full.sh" "$source_root/arm/start_arm_full.sh"; do
    recovery_line=$(grep -n '^setupmno_prepare_debian13_apt || {' "$script" | head -n1 | cut -d: -f1)
    apt_line=$(grep -n 'apt-get update' "$script" | head -n1 | cut -d: -f1)
    [ -n "$recovery_line" ] && [ -n "$apt_line" ] && [ "$recovery_line" -lt "$apt_line" ] || \
        fail "limpeza não ocorre antes do apt-get update em $script"
done

for script in \
    "$source_root/x86/SetupLowCodeMno/dockerswarm.sh" \
    "$source_root/arm/SetupLowCodeMno/dockerswarm.sh"; do
    if grep -Eq 'packages\.azlux\.fr|azlux-archive-keyring|docker-ctop' "$script"; then
        fail "dockerswarm ainda recria o repositório Azlux em $script"
    fi
done

printf 'OK: Debian 13 remove o repositório Azlux legado antes do APT sem afetar outras distros.\n'

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

extract_repair_function() {
    awk '
        /^setupmno_repair_debian13_apt_keyring\(\) \{/ { inside=1 }
        inside { print }
        inside && /^}/ { exit }
    ' "$1"
}

prepare_root() {
    local root="$1" id="$2" version="$3" mode="$4"
    mkdir -p "$root/etc" "$root/usr/share/keyrings"
    printf 'ID="%s"\nVERSION_ID="%s"\n' "$id" "$version" >"$root/etc/os-release"
    printf 'public-key-test\n' >"$root/usr/share/keyrings/azlux-archive-keyring.gpg"
    chmod "$mode" "$root/usr/share/keyrings/azlux-archive-keyring.gpg"
}

assert_mode() {
    local expected="$1" path="$2" actual
    actual=$(stat -c '%a' "$path")
    [ "$actual" = "$expected" ] || fail "$path ficou com permissão $actual; esperado: $expected"
}

scripts=(
    "$source_root/setup-mno.sh"
    "$source_root/setup-mno-oracle.sh"
    "$source_root/x86/start_full.sh"
    "$source_root/arm/start_arm_full.sh"
)

for script in "${scripts[@]}"; do
    unset -f setupmno_repair_debian13_apt_keyring 2>/dev/null || true
    eval "$(extract_repair_function "$script")"
    declare -F setupmno_repair_debian13_apt_keyring >/dev/null || fail "função ausente em $script"

    case_dir="$temporary_dir/$(basename "$script")-${RANDOM}"
    prepare_root "$case_dir/debian13" debian 13 0600
    SETUPMNO_APT_ROOT="$case_dir/debian13" setupmno_repair_debian13_apt_keyring
    assert_mode 644 "$case_dir/debian13/usr/share/keyrings/azlux-archive-keyring.gpg"
    SETUPMNO_APT_ROOT="$case_dir/debian13" setupmno_repair_debian13_apt_keyring
    assert_mode 644 "$case_dir/debian13/usr/share/keyrings/azlux-archive-keyring.gpg"

    prepare_root "$case_dir/debian12" debian 12 0600
    SETUPMNO_APT_ROOT="$case_dir/debian12" setupmno_repair_debian13_apt_keyring
    assert_mode 600 "$case_dir/debian12/usr/share/keyrings/azlux-archive-keyring.gpg"

    prepare_root "$case_dir/ubuntu" ubuntu 24.04 0600
    SETUPMNO_APT_ROOT="$case_dir/ubuntu" setupmno_repair_debian13_apt_keyring
    assert_mode 600 "$case_dir/ubuntu/usr/share/keyrings/azlux-archive-keyring.gpg"

    mkdir -p "$case_dir/missing/etc"
    printf 'ID=debian\nVERSION_ID=13\n' >"$case_dir/missing/etc/os-release"
    SETUPMNO_APT_ROOT="$case_dir/missing" setupmno_repair_debian13_apt_keyring

    prepare_root "$case_dir/symlink" debian 13 0600
    mv "$case_dir/symlink/usr/share/keyrings/azlux-archive-keyring.gpg" "$case_dir/symlink/target.gpg"
    ln -s "$case_dir/symlink/target.gpg" "$case_dir/symlink/usr/share/keyrings/azlux-archive-keyring.gpg"
    if SETUPMNO_APT_ROOT="$case_dir/symlink" setupmno_repair_debian13_apt_keyring; then
        fail "link simbólico aceito em $script"
    fi
    assert_mode 600 "$case_dir/symlink/target.gpg"
done

for script in "$source_root/setup-mno.sh" "$source_root/setup-mno-oracle.sh"; do
    repair_line=$(grep -n '^if ! setupmno_repair_debian13_apt_keyring; then' "$script" | head -n1 | cut -d: -f1)
    apt_line=$(grep -n 'execute_with_spinner "apt-get update -y"' "$script" | head -n1 | cut -d: -f1)
    [ -n "$repair_line" ] && [ -n "$apt_line" ] && [ "$repair_line" -lt "$apt_line" ] || \
        fail "reparo não ocorre antes do apt-get update em $script"
done

for script in "$source_root/x86/start_full.sh" "$source_root/arm/start_arm_full.sh"; do
    repair_line=$(grep -n '^setupmno_repair_debian13_apt_keyring || {' "$script" | head -n1 | cut -d: -f1)
    apt_line=$(grep -n 'apt-get update' "$script" | head -n1 | cut -d: -f1)
    [ -n "$repair_line" ] && [ -n "$apt_line" ] && [ "$repair_line" -lt "$apt_line" ] || \
        fail "reparo não ocorre antes do apt-get update em $script"
done

for script in \
    "$source_root/x86/SetupLowCodeMno/dockerswarm.sh" \
    "$source_root/arm/SetupLowCodeMno/dockerswarm.sh"; do
    grep -Fq 'chmod 0644 /usr/share/keyrings/azlux-archive-keyring.gpg' "$script" || \
        fail "permissão preventiva da chave ausente em $script"
    grep -Fq 'chmod 0644 /etc/apt/sources.list.d/azlux.list' "$script" || \
        fail "permissão preventiva da fonte ausente em $script"
done

printf 'OK: reparo idempotente do keyring Azlux no Debian 13 validado.\n'

#!/usr/bin/bash
set -euo pipefail

project_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
default_source_root=$(cd "$project_dir/.." && pwd)
source_root="${SETUPMNO_BOOTSTRAP_ROOT:-$default_source_root}"
[ -d "$source_root" ] || {
    printf 'ERRO: raiz de bootstraps inexistente: %s\n' "$source_root" >&2
    exit 2
}
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT

extract_function() {
    local function_name="$1" script="$2"
    awk -v name="$function_name" '
        $0 ~ "^" name "\\(\\)" { inside=1 }
        inside { print }
        inside && /^}/ { exit }
    ' "$script"
}

for bootstrap in "$source_root/setup-mno.sh" "$source_root/setup-mno-oracle.sh"; do
    bash -n "$bootstrap"
    function_body=$(extract_function setupmno_handoff_installer "$bootstrap")
    [ -n "$function_body" ]
    grep -Fq 'exec "./$installer"' <<<"$function_body"
    if grep -Fq './$filename' "$bootstrap"; then
        printf 'ERRO: %s ainda executa o gatilho sem handoff atômico.\n' "$bootstrap" >&2
        exit 1
    fi

    case "$(basename "$bootstrap")" in
        setup-mno.sh) harness="$test_dir/setup-harness.sh" ;;
        setup-mno-oracle.sh) harness="$test_dir/oracle-harness.sh" ;;
    esac
    installer_dir="${harness%.sh}"
    mkdir -p "$installer_dir"
    cat >"$installer_dir/fake-installer" <<'EOF'
#!/usr/bin/bash
exit 23
EOF
    chmod 700 "$installer_dir/fake-installer"
    {
        printf '#!/usr/bin/bash\n'
        printf 'VERSIONSETUP=7.34.2\n'
        printf 'dialog() { :; }\n'
        printf 'sleep() { :; }\n'
        printf '%s\n' "$function_body"
        printf 'setupmno_handoff_installer fake-installer\n'
        printf 'printf CONTINUACAO_INDEVIDA > continued\n'
        # Reproduz o fragmento inválido encontrado após o bootstrap publicado.
        printf 'else\n'
    } >"$harness"
    chmod 700 "$harness"

    set +e
    (cd "$installer_dir" && bash "$harness" >/dev/null 2>stderr.log)
    status=$?
    set -e
    [ "$status" -eq 23 ] || {
        printf 'ERRO: handoff de %s devolveu status %s, esperado 23.\n' \
            "$bootstrap" "$status" >&2
        exit 1
    }
    [ ! -e "$installer_dir/continued" ]
    [ ! -s "$installer_dir/stderr.log" ]
done

printf 'BOOTSTRAP_HANDOFF_TESTS_OK scripts=2 invalid_login_exit=preserved appended_tail=blocked\n'

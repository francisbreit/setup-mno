#!/usr/bin/bash
set -euo pipefail

project_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source_root=$(cd "$project_dir/.." && pwd)
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT

scripts=(
    "$project_dir/installer-template.sh"
    "$source_root/x86/SetupLowCodeMno/install.sh"
    "$source_root/arm/SetupLowCodeMno/install.sh"
    "$source_root/x86/SetupLowCodeMno/dockerswarm.sh"
    "$source_root/arm/SetupLowCodeMno/dockerswarm.sh"
)

for script in "${scripts[@]}"; do
    function_source=""
    for function_name in control_mfa_state_valid write_control_mfa_state; do
        extracted=$(awk -v name="$function_name" '
            $0 ~ "^" name "\\(\\)" { inside=1 }
            inside { print }
            inside && /^}/ { exit }
        ' "$script")
        [ -n "$extracted" ] || {
            printf 'ERRO: %s ausente em %s.\n' "$function_name" "$script" >&2
            exit 1
        }
        function_source+="$extracted"$'\n'
    done

    (
        eval "$function_source"
        CONTROL_MFA_STATE_FILE="$test_dir/$(basename "$(dirname "$script")")-$(basename "$script").json"
        write_control_mfa_state false false false test-original
        control_mfa_state_valid
        [ "$(stat -c '%a' "$CONTROL_MFA_STATE_FILE")" = "600" ]
        write_control_mfa_state true false true test-pending
        control_mfa_state_valid
        write_control_mfa_state true false false test-offered
        control_mfa_state_valid
        write_control_mfa_state true true false test-enabled
        control_mfa_state_valid
        if write_control_mfa_state false true false test-invalid; then
            printf 'ERRO: estado impossível aceito por %s.\n' "$script" >&2
            exit 1
        fi
        jq '.desiredMFA = false | .effectiveMFA = true' "$CONTROL_MFA_STATE_FILE" \
            >"$CONTROL_MFA_STATE_FILE.invalid"
        mv -f "$CONTROL_MFA_STATE_FILE.invalid" "$CONTROL_MFA_STATE_FILE"
        if control_mfa_state_valid; then
            printf 'ERRO: JSON inconsistente aceito por %s.\n' "$script" >&2
            exit 1
        fi
    )
done

for architecture in x86 arm; do
    install_script="$source_root/$architecture/SetupLowCodeMno/install.sh"
    foundation_script="$source_root/$architecture/SetupLowCodeMno/dockerswarm.sh"
    grep -Fq 'legacy-detected' "$install_script"
    grep -Fq 'activation-offered' "$install_script"
    grep -Fq 'CONTROL_CENTER_MFA_MENU=("CONFIGURAR MFA CONTROL CENTER" "")' "$install_script"
    ! grep -Fq 'control_center_mfa_configured' "$install_script"
    grep -Fq 'fresh-portainer' "$foundation_script"
    grep -Fq 'choose_control_mfa_preference || exit 0' "$foundation_script"
done

printf 'Estado MFA atômico, compatibilidade legada e menu permanente aprovados.\n'

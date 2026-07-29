#!/usr/bin/bash
set -euo pipefail

project_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source_root=$(cd "$project_dir/.." && pwd)
template="$project_dir/installer-template.sh"
x86_target="$source_root/x86/SetupLowCodeMno/setupmno_control.sh"
arm_target="$source_root/arm/SetupLowCodeMno/setupmno_control.sh"
temporary_dir=$(mktemp -d)
trap 'rm -rf "$temporary_dir"' EXIT

bundle="$temporary_dir/setupmno-control.tar.gz"
(
    cd "$project_dir"
    tar -czf "$bundle" \
        go.mod Dockerfile terminal.Dockerfile main.go catalog.json web
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
printf 'Instaladores x86 e ARM gerados com bundle idêntico.\n'

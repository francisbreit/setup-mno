#!/usr/bin/bash
set -euo pipefail

project_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source_root=$(cd "$project_dir/.." && pwd)
wizard_source="$source_root/setupmno-knowledge/tools/homologation_wizard.sh"
mkdir -p /tmp/setupmno-homologacao
temporary_dir=$(mktemp -d /tmp/setupmno-homologacao/setupmno-hml-wizard-test.XXXXXX)
trap 'rm -rf "$temporary_dir"' EXIT

package_dir="$temporary_dir/package"
work_root="$temporary_dir/runs"
fake_bin="$temporary_dir/bin"
counter_file="$temporary_dir/whiptail-counter"
mkdir -p "$fake_bin"
printf '0\n' >"$counter_file"

setup_version=$(jq -r '.setupVersion' "$source_root/setupmno-knowledge/registry/setups.json")
python3 -B "$source_root/setupmno-knowledge/tools/generate_homologation_package.py" \
    --root "$source_root/setupmno-knowledge" \
    --output "$package_dir" \
    --setup-version "$setup_version" >/dev/null

cat >"$fake_bin/docker" <<'EOF'
#!/usr/bin/bash
if [ "${1:-}" = "info" ]; then
    printf 'active x86_64\n'
    exit 0
fi
exit 64
EOF

cat >"$fake_bin/whiptail" <<EOF
#!/usr/bin/bash
counter=\$(cat "$counter_file")
counter=\$((counter + 1))
printf '%s\n' "\$counter" >"$counter_file"
if [ "\${WIZARD_SCENARIO:-save}" = "full" ]; then
    case "\$counter" in
        1) printf 'NEW' >&2 ;;
        2) printf 'navidrome' >&2 ;;
        3) printf 'amd64' >&2 ;;
        4) printf 'linux-emulated' >&2 ;;
        7|9|11|13|15|17|19|21|23) printf 'passed' >&2 ;;
        8|10|12|14|16|18|20|22|24) printf 'Check aprovado no laboratório isolado.' >&2 ;;
        26) printf 'Setup MNO QA' >&2 ;;
        27) printf 'example/navidrome@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' >&2 ;;
        28) exit 1 ;;
        30) printf 'EXIT' >&2 ;;
    esac
else
    case "\$counter" in
        1) printf 'NEW' >&2 ;;
        2) printf 'navidrome' >&2 ;;
        3) printf 'amd64' >&2 ;;
        4) printf 'linux-emulated' >&2 ;;
        7) printf 'save-exit' >&2 ;;
        9) printf 'EXIT' >&2 ;;
    esac
fi
exit 0
EOF
chmod 0755 "$fake_bin/docker" "$fake_bin/whiptail"

PATH="$fake_bin:$PATH" \
SETUPMNO_HOMOLOGATION_PACKAGE_DIR="$package_dir" \
SETUPMNO_HOMOLOGATION_WORK_ROOT="$work_root" \
    bash "$wizard_source"

session_count=$(find "$work_root" -mindepth 2 -maxdepth 2 -type f -name session.json | wc -l)
[ "$session_count" -eq 1 ]
session_file=$(find "$work_root" -mindepth 2 -maxdepth 2 -type f -name session.json | head -n1)
jq -e '
    .setupId == "navidrome" and
    .architecture == "amd64" and
    .environment.platform == "linux-emulated" and
    .checks.deploy.status == "not-tested"
' "$session_file" >/dev/null
[ "$(find "$work_root" -type f -name '*-candidate.tar.gz' | wc -l)" -eq 0 ]

printf '0\n' >"$counter_file"
full_work_root="$temporary_dir/full-runs"
PATH="$fake_bin:$PATH" \
WIZARD_SCENARIO=full \
SETUPMNO_HOMOLOGATION_PACKAGE_DIR="$package_dir" \
SETUPMNO_HOMOLOGATION_WORK_ROOT="$full_work_root" \
    bash "$wizard_source"

candidate_count=$(find "$full_work_root" -mindepth 2 -maxdepth 2 -type f -name '*-candidate.tar.gz' | wc -l)
[ "$candidate_count" -eq 1 ]
candidate_file=$(find "$full_work_root" -mindepth 2 -maxdepth 2 -type f -name '*-candidate.tar.gz' | head -n1)
candidate_result=$(python3 -B "$package_dir/homologation_runner.py" \
    --package-dir "$package_dir" verify --bundle "$candidate_file")
[ "$(printf '%s' "$candidate_result" | jq -r '.result')" = "candidate-full" ]
[ "$(printf '%s' "$candidate_result" | jq -r '.officialSeal')" = "false" ]

printf 'Assistente Whiptail: navegação, retomada, checklist completo e candidato sem selo aprovados.\n'

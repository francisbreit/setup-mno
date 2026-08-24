#!/usr/bin/bash
set -euo pipefail

project_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source_root=$(cd "$project_dir/.." && pwd)
bootstrap_files=(
    "$source_root/setup-mno.sh"
    "$source_root/setup-mno-oracle.sh"
    "$source_root/x86/start_full.sh"
    "$source_root/arm/start_arm_full.sh"
)

for file in "${bootstrap_files[@]}"; do
    grep -Fq 'DEBIAN_FRONTEND=noninteractive' "$file"
    grep -Fq 'DEBCONF_NONINTERACTIVE_SEEN=true' "$file"
    grep -Fq 'NEEDRESTART_MODE=a' "$file"
    grep -Fq 'DPkg::Lock::Timeout=300' "$file"
    grep -Fq 'Dpkg::Options::=--force-confold' "$file"
    if grep -Eq '(^|[[:space:]])(apt-get|setupmno_apt)[[:space:]].*[[:space:]]upgrade([[:space:]]|$)' "$file"; then
        printf 'ERRO: upgrade completo ainda faz parte do fluxo obrigatório em %s.\n' "$file" >&2
        exit 1
    fi
done

for file in "$source_root/setup-mno.sh" "$source_root/setup-mno-oracle.sh"; do
    if grep -Fq 'eval "$command"' "$file"; then
        printf 'ERRO: executor do bootstrap ainda usa eval em %s.\n' "$file" >&2
        exit 1
    fi
    grep -Fq 'setupmno_apt install sudo dnsutils dialog whiptail jq tmux' "$file"
    grep -Fq 'SETUPMNO_COMMAND_LOG="/tmp/setup-mno-bootstrap-apt.log"' "$file"
done

for file in "$source_root/x86/start_full.sh" "$source_root/arm/start_arm_full.sh"; do
    [ "$(grep -Fc 'setupmno_apt update >>"$SETUPMNO_APT_LOG"' "$file")" -eq 1 ]
    [ "$(grep -Fc 'setupmno_apt install sudo wget curl unzip zip jq python3 build-essential' "$file")" -eq 1 ]
    grep -Fq 'SETUPMNO_APT_LOG="/tmp/setupmno-start-apt.log"' "$file"
done

extract_function() {
    local name="$1" file="$2"
    awk -v name="$name" '
        $0 ~ "^" name "\\(\\)" { inside=1 }
        inside { print }
        inside && /^}/ { exit }
    ' "$file"
}

test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
mkdir -p "$test_dir/bin"
cat >"$test_dir/bin/apt-get" <<'EOF'
#!/usr/bin/bash
printf 'frontend=%s seen=%s restart=%s args=%s\n' \
    "${DEBIAN_FRONTEND:-}" "${DEBCONF_NONINTERACTIVE_SEEN:-}" \
    "${NEEDRESTART_MODE:-}" "$*" >>"$MOCK_APT_CAPTURE"
[ "${MOCK_APT_RESULT:-success}" != "failure" ] || exit 37
EOF
chmod 0755 "$test_dir/bin/apt-get"
PATH="$test_dir/bin:$PATH"
export MOCK_APT_CAPTURE="$test_dir/apt-capture.log"

eval "$(extract_function setupmno_apt "$source_root/setup-mno.sh")"
setupmno_apt install pacote-ficticio
grep -Fq 'frontend=noninteractive seen=true restart=a' "$MOCK_APT_CAPTURE"
grep -Fq -- '-o DPkg::Lock::Timeout=300' "$MOCK_APT_CAPTURE"
grep -Fq -- '-o Dpkg::Options::=--force-confold install pacote-ficticio' "$MOCK_APT_CAPTURE"

export MOCK_APT_RESULT=failure
if setupmno_apt install pacote-ficticio; then
    printf 'ERRO: falha simulada do APT foi descartada.\n' >&2
    exit 1
else
    [ "$?" -eq 37 ] || {
        printf 'ERRO: helper alterou o código de falha do APT.\n' >&2
        exit 1
    }
fi
unset MOCK_APT_RESULT

eval "$(extract_function execute_with_spinner "$source_root/setup-mno.sh")"
spinner() { :; }
branco=""
verde=""
vermelho=""
reset=""
SETUPMNO_COMMAND_LOG="$test_dir/command.log"
mock_success() { printf '%s\n' 'saída técnica de sucesso'; }
mock_failure() { printf '%s\n' 'saída técnica de falha'; return 29; }

execute_with_spinner "Teste de sucesso..." mock_success >/dev/null
grep -Fq 'saída técnica de sucesso' "$SETUPMNO_COMMAND_LOG"
if execute_with_spinner "Teste de falha..." mock_failure \
    >"$test_dir/spinner.out" 2>"$test_dir/spinner.err"; then
    printf 'ERRO: spinner descartou a falha simulada.\n' >&2
    exit 1
else
    [ "$?" -eq 29 ] || {
        printf 'ERRO: spinner alterou o código de falha.\n' >&2
        exit 1
    }
fi
grep -Fq 'saída técnica de falha' "$SETUPMNO_COMMAND_LOG"
grep -Fq "Log técnico: $SETUPMNO_COMMAND_LOG" "$test_dir/spinner.err"

printf 'APT não interativo, sem upgrade obrigatório, sem eval e com falha bloqueante aprovado.\n'

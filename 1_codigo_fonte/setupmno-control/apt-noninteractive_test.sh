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
dockerswarm_files=(
    "$source_root/x86/SetupLowCodeMno/dockerswarm.sh"
    "$source_root/arm/SetupLowCodeMno/dockerswarm.sh"
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

for file in "${dockerswarm_files[@]}"; do
    grep -Fq 'DEBIAN_FRONTEND=noninteractive' "$file"
    grep -Fq 'DEBCONF_NONINTERACTIVE_SEEN=true' "$file"
    grep -Fq 'DEBIAN_PRIORITY=critical' "$file"
    grep -Fq 'NEEDRESTART_MODE=a' "$file"
    grep -Fq 'APT_LISTCHANGES_FRONTEND=none' "$file"
    grep -Fq 'UCF_FORCE_CONFFOLD=1' "$file"
    grep -Fq 'DPkg::Lock::Timeout=300' "$file"
    grep -Fq 'Dpkg::Options::=--force-confdef' "$file"
    grep -Fq 'Dpkg::Options::=--force-confold' "$file"
    grep -Fq 'SETUPMNO_DOCKERSWARM_APT_LOG="/tmp/setupmno-dockerswarm-apt.log"' "$file"
    grep -Fq 'Processando há %02d:%02d' "$file"
    grep -Fq 'setupmno_run_apt_step 17 "ATUALIZANDO O ÍNDICE DE PACOTES..." update' "$file"
    grep -Fq 'setupmno_run_apt_step 20 "INSTALANDO DEPENDÊNCIAS DO SETUP MNO..." install' "$file"
    grep -Fq 'setupmno_run_apt_step 23 "VALIDANDO O REPOSITÓRIO DO DOCKER..." update' "$file"
    grep -Fq 'setupmno_run_apt_step 25 "INSTALANDO DOCKER ENGINE 2/4..." install' "$file"
    if grep -Eq '(^|[[:space:]])(apt-get|setupmno_apt)[[:space:]].*[[:space:]]upgrade([[:space:]]|$)' "$file"; then
        printf 'ERRO: upgrade completo ainda faz parte do Docker Swarm em %s.\n' "$file" >&2
        exit 1
    fi
    if grep -Eq '^[[:space:]]*(sudo[[:space:]]+)?apt([[:space:]]|$)' "$file"; then
        printf 'ERRO: chamada interativa direta ao apt ainda existe em %s.\n' "$file" >&2
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
printf 'frontend=%s seen=%s priority=%s restart=%s listchanges=%s ucf=%s args=%s\n' \
    "${DEBIAN_FRONTEND:-}" "${DEBCONF_NONINTERACTIVE_SEEN:-}" \
    "${DEBIAN_PRIORITY:-}" "${NEEDRESTART_MODE:-}" \
    "${APT_LISTCHANGES_FRONTEND:-}" "${UCF_FORCE_CONFFOLD:-}" \
    "$*" >>"$MOCK_APT_CAPTURE"
[ -z "${MOCK_APT_DELAY:-}" ] || sleep "$MOCK_APT_DELAY"
[ "${MOCK_APT_RESULT:-success}" != "failure" ] || exit 37
EOF
chmod 0755 "$test_dir/bin/apt-get"
PATH="$test_dir/bin:$PATH"
export MOCK_APT_CAPTURE="$test_dir/apt-capture.log"

eval "$(extract_function setupmno_apt "$source_root/setup-mno.sh")"
setupmno_apt install pacote-ficticio
grep -Fq 'frontend=noninteractive seen=true priority=' "$MOCK_APT_CAPTURE"
grep -Fq 'restart=a' "$MOCK_APT_CAPTURE"
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

eval "$(extract_function setupmno_apt "${dockerswarm_files[0]}")"
eval "$(extract_function setupmno_gauge_heartbeat_loop "${dockerswarm_files[0]}")"
eval "$(extract_function setupmno_start_gauge_heartbeat "${dockerswarm_files[0]}")"
eval "$(extract_function setupmno_stop_gauge_heartbeat "${dockerswarm_files[0]}")"
eval "$(extract_function setupmno_run_apt_step "${dockerswarm_files[0]}")"
SETUPMNO_DOCKERSWARM_APT_LOG="$test_dir/dockerswarm-apt.log"
setupmno_gauge_heartbeat_pid=""
export MOCK_APT_DELAY=2

setupmno_run_apt_step 17 "ETAPA FICTÍCIA DO DOCKER SWARM..." install pacote-ficticio \
    >"$test_dir/gauge.out"
grep -Fq 'ETAPA FICTÍCIA DO DOCKER SWARM...' "$test_dir/gauge.out"
grep -Fq 'Processando há 00:00' "$test_dir/gauge.out"
grep -Fq 'Processando há 00:01' "$test_dir/gauge.out"
grep -Fq 'priority=critical' "$MOCK_APT_CAPTURE"
grep -Fq 'listchanges=none ucf=1' "$MOCK_APT_CAPTURE"
grep -Fq -- '-o Dpkg::Options::=--force-confdef' "$MOCK_APT_CAPTURE"
[ -z "$setupmno_gauge_heartbeat_pid" ]

export MOCK_APT_RESULT=failure
if setupmno_run_apt_step 20 "FALHA FICTÍCIA DO DOCKER SWARM..." install pacote-ficticio \
    >"$test_dir/gauge-failure.out"; then
    printf 'ERRO: Docker Swarm descartou a falha simulada do APT.\n' >&2
    exit 1
else
    [ "$?" -eq 37 ] || {
        printf 'ERRO: Docker Swarm alterou o código de falha do APT.\n' >&2
        exit 1
    }
fi
grep -Fq 'ERRO NO GERENCIADOR DE PACOTES' "$test_dir/gauge-failure.out"
[ -z "$setupmno_gauge_heartbeat_pid" ]
unset MOCK_APT_RESULT MOCK_APT_DELAY

printf 'APT não interativo no bootstrap e Docker Swarm, sem upgrade obrigatório, com heartbeat e falha bloqueante aprovado.\n'

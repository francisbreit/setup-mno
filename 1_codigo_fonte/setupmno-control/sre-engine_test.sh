#!/usr/bin/bash
set -euo pipefail

project_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
engine_dir="$project_dir/sre-engine"
test_dir=$(mktemp -d)
trap 'rm -rf -- "$test_dir"' EXIT
mkdir -p "$test_dir/trivy"

cat >"$test_dir/trivy/result-1.json" <<'JSON'
{"Results":[{"Target":"cliente/segredo:latest","Vulnerabilities":[{"VulnerabilityID":"CVE-SECRET-1","Severity":"CRITICAL"},{"VulnerabilityID":"CVE-SECRET-2","Severity":"HIGH"}]}]}
JSON
cat >"$test_dir/lynis-report.dat" <<'EOF'
hostname=cliente-secreto
warning[]=segredo de auditoria
suggestion[]=caminho privado
tests_executed=CORE-1000|BOOT-5102|KRNL-6000|
hardening_index=72
EOF
cat >"$test_dir/docker-bench.log" <<'EOF'
[PASS] controle público
[WARN] container cliente-secreto
[INFO] informação
EOF
printf '%s\n' '{"trivy":"completed","lynis":"completed","docker-bench":"completed"}' >"$test_dir/status.json"

python3 -B "$engine_dir/normalize.py" \
    --tools "$engine_dir/tools.json" \
    --execution-status "$test_dir/status.json" \
    --trivy-dir "$test_dir/trivy" \
    --lynis-report "$test_dir/lynis-report.dat" \
    --docker-bench-log "$test_dir/docker-bench.log" \
    --environment wsl2 --generated-at 2026-08-25T12:00:00Z \
    --output "$test_dir/latest.json"

jq -e '
  .schemaVersion == 1 and .engineVersion == "1.0.0" and .maturity == "beta" and
  .execution == "human-confirmed-terminal" and .readOnly == true and
  .complete == true and .overallStatus == "attention" and .hostType == "wsl2" and
  .expiresAt == "2026-08-26T12:00:00Z" and
  (.engines | length == 3) and
  (.engines[] | select(.id == "trivy") | .counts.critical == 1 and .counts.high == 1) and
  (.engines[] | select(.id == "lynis") | .counts.warnings == 1 and .counts.tests == 3 and .counts.hardeningIndex == 72) and
  (.engines[] | select(.id == "docker-bench") | .counts.warn == 1) and
  .privacy.rawFindingsIncluded == false and .privacy.targetsIncluded == false
' "$test_dir/latest.json" >/dev/null

if grep -Eqi 'cliente-secreto|segredo de auditoria|CVE-SECRET|caminho privado' "$test_dir/latest.json"; then
    printf 'ERRO: resultado SRE-3 expôs identidade ou achado bruto.\n' >&2
    exit 1
fi

printf '%s\n' '{"trivy":"failed","lynis":"completed","docker-bench":"partial"}' >"$test_dir/status.json"
python3 -B "$engine_dir/normalize.py" \
    --tools "$engine_dir/tools.json" --execution-status "$test_dir/status.json" \
    --trivy-dir "$test_dir/ausente" --lynis-report "$test_dir/lynis-report.dat" \
    --docker-bench-log "$test_dir/docker-bench.log" --environment vps \
    --generated-at 2026-08-25T12:00:00Z --output "$test_dir/incomplete.json"
jq -e '.complete == false and .overallStatus == "incomplete" and any(.observedFacts[]; .code == "audit-coverage-incomplete")' \
    "$test_dir/incomplete.json" >/dev/null

grep -Fq 'ghcr.io/aquasecurity/trivy@sha256:' "$engine_dir/tools.json"
grep -Fq 'docker image save' "$engine_dir/run.sh"
trivy_function=$(sed -n '/^run_trivy()/,/^}/p' "$engine_dir/run.sh")
lynis_function=$(sed -n '/^run_lynis()/,/^}/p' "$engine_dir/run.sh")
bench_function=$(sed -n '/^run_docker_bench()/,/^}/p' "$engine_dir/run.sh")
if printf '%s\n%s\n' "$trivy_function" "$lynis_function" |
   grep -Eq -- '/var/run/docker.sock'; then
    printf 'ERRO: o scanner Trivy recebeu o Docker socket.\n' >&2
    exit 1
fi
printf '%s\n' "$bench_function" | grep -Fq '/var/run/docker.sock:/var/run/docker.sock:ro'
printf '%s\n' "$bench_function" | grep -Fq -- '-e check_5_7,check_7_5'
printf '%s\n' "$trivy_function" | grep -Fq -- '--memory 1g --tmpfs /tmp:rw,noexec,nosuid,size=512m'
printf '%s\n' "$lynis_function" | grep -Fq -- '--tmpfs /var/run:rw,noexec,nosuid,size=4m'
printf '%s\n' "$lynis_function" | grep -Fq -- '--workdir /lynis'
printf '%s\n' "$lynis_function" | grep -Fq -- '--root-dir /host --usecwd'
printf '%s\n' "$bench_function" | grep -Fq -- '--label docker.bench.security=true'
printf '%s\n' "$bench_function" | grep -Fq -- '-l /tmp/docker-bench-security.log'
grep -Fq -- '--network none' "$engine_dir/run.sh"

printf 'SRE3_ENGINE_TESTS_OK engines=3 sanitized=1 incomplete_visible=1 scanner_socket=bench-only wsl_runtime_fixes=3\n'

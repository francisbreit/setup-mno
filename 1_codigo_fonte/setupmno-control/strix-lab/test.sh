#!/usr/bin/bash
set -Eeuo pipefail

LAB_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

python3 "$LAB_DIR/validate.py" lock >/dev/null
SETUPMNO_STRIX_SMOKE_TEST=1 bash "$LAB_DIR/wizard.sh" | grep -Fx \
    'setupmno-strix-lab-ready:isolated-executor:1.5.3' >/dev/null

cat >"$TEMP_DIR/authorization.json" <<'EOF'
{"schemaVersion":1,"contractVersion":"1.1.0","maturity":"beta","plan":"pro-master","authorizationID":"strix-abcdef123456","targetType":"source-archive","targetSHA256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","provider":"openrouter","model":"openai/gpt-oss-20b:free","issuedAt":"2026-08-27T12:00:00Z","expiresAt":"2026-08-27T13:00:00Z","maxDurationMinutes":60,"maxTurns":20,"limits":{"cpu":1,"memoryMB":2048,"llmBudgetUSD":5},"writtenPermission":true,"automaticExecution":false,"targetMutationAllowed":false,"productionDockerSocketAllowed":false,"productionRootMountAllowed":false,"state":"approved"}
EOF
python3 "$LAB_DIR/validate.py" authorization "$TEMP_DIR/authorization.json" >/dev/null
jq '.plan="pro"' "$TEMP_DIR/authorization.json" >"$TEMP_DIR/pro.json"
python3 "$LAB_DIR/validate.py" authorization "$TEMP_DIR/pro.json" >/dev/null
jq '.plan="free"' "$TEMP_DIR/authorization.json" >"$TEMP_DIR/invalid.json"
if python3 "$LAB_DIR/validate.py" authorization "$TEMP_DIR/invalid.json" >/dev/null 2>&1; then
    printf 'ERRO: autorização fora dos planos PRO e PRO MASTER foi aceita.\n' >&2; exit 1
fi
jq '.productionDockerSocketAllowed=true' "$TEMP_DIR/authorization.json" >"$TEMP_DIR/invalid.json"
if python3 "$LAB_DIR/validate.py" authorization "$TEMP_DIR/invalid.json" >/dev/null 2>&1; then
    printf 'ERRO: Docker socket de produção foi aceito.\n' >&2; exit 1
fi

cat >"$TEMP_DIR/report.json" <<'EOF'
{"schemaVersion":1,"contractVersion":"1.1.0","maturity":"beta","authorizationID":"strix-abcdef123456","targetSHA256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","generatedAt":"2026-08-27T12:00:00Z","expiresAt":"2026-08-28T12:00:00Z","status":"partial","counts":{"critical":0,"high":0,"medium":0,"low":0,"info":0},"limitations":["Executor isolado em homologação controlada."],"executor":{"userID":61000,"rootless":true,"readOnlyRootFilesystem":true,"capabilitiesDropped":true,"noNewPrivileges":true,"productionDockerSocketPresent":false,"hostMountsPresent":false},"execution":{"productionDockerSocketUsed":false,"productionRootMounted":false,"targetMutated":false,"automaticExecution":false},"rawEvidenceStored":false,"sealGranted":false,"catalogPublished":false,"remediationApplied":false}
EOF
python3 "$LAB_DIR/validate.py" report "$TEMP_DIR/report.json" >/dev/null
jq '.remediationApplied=true' "$TEMP_DIR/report.json" >"$TEMP_DIR/invalid.json"
if python3 "$LAB_DIR/validate.py" report "$TEMP_DIR/invalid.json" >/dev/null 2>&1; then
    printf 'ERRO: correção automática foi aceita.\n' >&2; exit 1
fi

if rg -n '(--privileged|/root:/root|docker\.from_env|docker run|docker create)' \
    "$LAB_DIR/executor.Dockerfile" "$LAB_DIR/executor.py" >/dev/null; then
    printf 'ERRO: executor contém acesso proibido à produção.\n' >&2; exit 1
fi
grep -Fq 'USER 61000:61000' "$LAB_DIR/executor.Dockerfile"
grep -Fq 'SETUPMNO_STRIX_REPORT:' "$LAB_DIR/executor.py"
grep -Fq 'source-archive' "$LAB_DIR/authorization.schema.json"

printf 'Contratos fechados e executor efêmero isolado do Laboratório Strix SRE-6 aprovados.\n'

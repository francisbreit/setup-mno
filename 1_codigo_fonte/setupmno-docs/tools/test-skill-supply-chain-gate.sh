#!/usr/bin/env bash
set -Eeuo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
docs_root="$(cd "$script_dir/.." && pwd)"
gate="$script_dir/skill_supply_chain_gate.py"
safe_fixture="$docs_root/fixtures/skill-gate/safe"
blocked_fixture="$docs_root/fixtures/skill-gate/blocked"
test_root="$(mktemp -d /tmp/setupmno-skill-gate-test.XXXXXX)"

cleanup() {
    rm -rf -- "$test_root"
}
trap cleanup EXIT

python3 -B "$gate" --candidate "$safe_fixture" --report "$test_root/safe.json" >/dev/null
jq -e '.decision == "awaiting-pro-master-review" and .maturity == "beta" and .dryRun == true and (.blockers | length) == 0 and .observedCommands == ["df", "uname"]' "$test_root/safe.json" >/dev/null
token="$(jq -r '.approval.token' "$test_root/safe.json")"
python3 -B "$gate" --candidate "$safe_fixture" --approval-token "$token" --report "$test_root/approved.json" >/dev/null
jq -e '.decision == "approved-for-canonical-review" and .approval.authenticatedByGate == false' "$test_root/approved.json" >/dev/null

set +e
python3 -B "$gate" --candidate "$blocked_fixture" --report "$test_root/blocked.json" >/dev/null 2>&1
blocked_status=$?
set -e
[ "$blocked_status" -eq 3 ]
jq -e '.decision == "blocked" and (.blockers | length) >= 4 and .approval.token == null' "$test_root/blocked.json" >/dev/null

cp -a "$safe_fixture" "$test_root/tampered"
printf '\nALTERACAO NAO INVENTARIADA\n' >> "$test_root/tampered/SKILL.md"
if python3 -B "$gate" --candidate "$test_root/tampered" >/dev/null 2>&1; then
    echo "SKILL_GATE_TEST_ERROR: adulteração não foi bloqueada" >&2
    exit 1
fi

cp -a "$safe_fixture" "$test_root/extra-file"
printf 'arquivo extra\n' > "$test_root/extra-file/extra.txt"
if python3 -B "$gate" --candidate "$test_root/extra-file" >/dev/null 2>&1; then
    echo "SKILL_GATE_TEST_ERROR: arquivo extra não foi bloqueado" >&2
    exit 1
fi

cp -a "$safe_fixture" "$test_root/extra-field"
jq '.unexpectedField = true' "$test_root/extra-field/skill-manifest.json" > "$test_root/extra-field/manifest.tmp"
mv "$test_root/extra-field/manifest.tmp" "$test_root/extra-field/skill-manifest.json"
if python3 -B "$gate" --candidate "$test_root/extra-field" >/dev/null 2>&1; then
    echo "SKILL_GATE_TEST_ERROR: campo desconhecido não foi bloqueado" >&2
    exit 1
fi

echo "SKILL_SUPPLY_CHAIN_TESTS_OK safe=1 approval=1 blocked=1 tamper=1 extra=1 strict=1"

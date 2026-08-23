#!/usr/bin/env bash
set -Eeuo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
docs_root="$(cd "$script_dir/.." && pwd)"
validator="$script_dir/validate-sre-knowledge.py"

python3 "$validator" --docs-root "$docs_root" >/dev/null

test_root="$(mktemp -d /tmp/setupmno-sre-validator.XXXXXX)"
cleanup() {
    rm -rf -- "$test_root"
}
trap cleanup EXIT

cp -a "$docs_root/sre" "$test_root/sre"
printf '\nALTERACAO SEM REVISAO\n' >> "$test_root/sre/manual/docker-swarm-triage.md"

if python3 "$validator" --docs-root "$test_root" >/dev/null 2>&1; then
    echo "SRE_KNOWLEDGE_TEST_ERROR: adulteração não foi bloqueada" >&2
    exit 1
fi

echo "SRE_KNOWLEDGE_TESTS_OK positive=1 tamper_blocked=1"

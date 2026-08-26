#!/usr/bin/env bash
set -euo pipefail

project_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
main_source="$project_dir/main.go"
snapshot_source="$project_dir/sre_snapshot.go"
template="$project_dir/installer-template.sh"
html="$project_dir/web/index.html"

grep -Fq 'mux.HandleFunc("GET /sre/snapshot"' "$main_source"
grep -Fq 'mux.Handle("GET /api/sre/snapshot", app.requireAuth(http.HandlerFunc(app.handleSRESnapshot)))' "$main_source"

if grep -Eq 'mux\.Handle(Func)?\("(POST|PUT|PATCH|DELETE) /sre/' "$main_source"; then
    printf 'ERRO: o agente SRE possui uma rota mutável.\n' >&2
    exit 1
fi

grep -Eq 'sreSnapshotSource[[:space:]]*=[[:space:]]*"agent-fixed-read-only"' "$snapshot_source"
grep -Eq 'sreSnapshotVersion[[:space:]]*=[[:space:]]*"1.1.0"' "$snapshot_source"
grep -Fq 'Deterministic' "$snapshot_source"
grep -Fq 'MutationAllowed: false' "$snapshot_source"
grep -Fq 'RawLogsIncluded: false' "$snapshot_source"
grep -Fq 'ServiceNamesUsed: false' "$snapshot_source"
grep -Fq 'http.NewRequest(http.MethodGet, "http://docker"+endpoint, nil)' "$snapshot_source"

grep -Fq 'APP_VERSION=$CONTROL_VERSION' "$template"
grep -Fq 'Especialista SRE · BETA' "$html"
grep -Fq 'Nenhuma alteração será realizada' "$html"
grep -Fq 'Executar diagnóstico seguro (BETA)' "$html"

if grep -Fq 'requireMaintainer(http.HandlerFunc(app.handleSRESnapshot))' "$main_source"; then
    printf 'ERRO: a proteção universal do diagnóstico foi limitada ao PRO MASTER.\n' >&2
    exit 1
fi

printf 'SRE_READ_ONLY_TESTS_OK fixed_get=1 auth=1 plans=5 beta=1 mutation=0\n'

#!/usr/bin/bash
set -Eeuo pipefail

# Inicializa uma cópia persistente e verificável da base canônica. O arquivo
# original em .control permanece somente leitura para os serviços do painel.
setupmno_prepare_maintainer_workspace() {
    local runtime_root runner_dir release manifest archive setup_version
    local expected_sha expected_bytes actual_sha actual_bytes workspace parent temporary marker
    runtime_root="${SETUPMNO_RUNTIME_ROOT:-/root/SetupLowCodeMno/.control}"
    runner_dir="$runtime_root/homologation-package"
    release="$runtime_root/release.json"
    manifest="$runner_dir/manifest.json"
    archive="$runner_dir/maintainer-workspace.tar.gz"

    for path in "$release" "$manifest" "$archive"; do
        [ -f "$path" ] && [ ! -L "$path" ] || {
            printf 'Workspace do mantenedor: componente ausente ou inseguro: %s\n' "$path" >&2
            return 1
        }
    done
    setup_version=$(jq -er '.setupVersion | select(test("^[0-9]+\\.[0-9]+\\.[0-9]+$"))' "$release") || return 1
    [ "$(jq -r '.setupVersion // empty' "$manifest")" = "$setup_version" ] || return 1
    [ "$(jq -r '.remoteCertification // false' "$manifest")" = "true" ] || return 1
    expected_sha=$(jq -r '.maintainerWorkspaceSHA256 // empty' "$manifest")
    expected_bytes=$(jq -r '.maintainerWorkspaceBytes // 0' "$manifest")
    actual_sha=$(sha256sum "$archive" | awk '{print $1}')
    actual_bytes=$(stat -c '%s' "$archive")
    [ "${#expected_sha}" -eq 64 ] && [ "$expected_sha" = "$actual_sha" ] &&
        [ "$expected_bytes" = "$actual_bytes" ] && [ "$actual_bytes" -le $((8 * 1024 * 1024)) ] || return 1
    tar -tzf "$archive" >/dev/null 2>&1 || return 1
    tar -tzf "$archive" | awk '/^\// || /(^|\/)\.\.(\/|$)/ { exit 1 }' || return 1
    tar -tvzf "$archive" 2>/dev/null |
        awk 'substr($1, 1, 1) != "-" { exit 1 }' || return 1

    parent="${SETUPMNO_MAINTAINER_WORK_ROOT:-/root/setupmno-maintainer-workspace}"
    case "$parent" in
        /root/setupmno-maintainer-workspace|/tmp/setupmno-maintainer-workspace|/tmp/setupmno-maintainer-workspace/*) ;;
        *) printf 'Workspace do mantenedor fora da allowlist.\n' >&2; return 1 ;;
    esac
    [ ! -L "$parent" ] || return 1
    mkdir -p "$parent"
    chmod 0700 "$parent"
    workspace="$parent/v$setup_version"
    marker="$workspace/.setupmno-runtime.json"
    if [ -d "$workspace" ]; then
        [ ! -L "$workspace" ] && [ -f "$marker" ] && [ ! -L "$marker" ] &&
            [ "$(jq -r '.setupVersion // empty' "$marker" 2>/dev/null)" = "$setup_version" ] &&
            [ "$(jq -r '.archiveSHA256 // empty' "$marker" 2>/dev/null)" = "$actual_sha" ] || {
                printf 'Workspace existente não corresponde à release atual; preserve-o e remova-o manualmente após exportar o trabalho.\n' >&2
                return 1
            }
    else
        temporary=$(mktemp -d "$parent/.v$setup_version.XXXXXX")
        if ! tar -xzf "$archive" -C "$temporary" --no-same-owner --no-same-permissions; then
            rm -rf -- "$temporary"
            return 1
        fi
        jq -n --arg version "$setup_version" --arg sha "$actual_sha" \
            '{schemaVersion:1,setupVersion:$version,archiveSHA256:$sha}' >"$temporary/.setupmno-runtime.json"
        chmod 0600 "$temporary/.setupmno-runtime.json"
        mv "$temporary" "$workspace"
    fi
    export SETUPMNO_MAINTAINER_WORKSPACE="$workspace"
    export SETUPMNO_MAINTAINER_KNOWLEDGE_ROOT="$workspace/setupmno-knowledge"
    export SETUPMNO_MAINTAINER_CATALOG="$workspace/setupmno-control/catalog.json"
    export SETUPMNO_MAINTAINER_SETUP_VERSION="$setup_version"
    export SETUPMNO_MAINTAINER_RUNTIME_RELEASE="$release"
    export SETUPMNO_MAINTAINER_RUNNER_DIR="$runner_dir"
}

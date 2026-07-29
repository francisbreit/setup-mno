#!/usr/bin/bash
set -Eeuo pipefail

bridge_file=${1:?Informe o arquivo da ponte touch}
output_file=${2:?Informe o index.html de saída}
temporary_dir=$(mktemp -d)
default_index="$temporary_dir/index.html"
ttyd_pid=""

cleanup() {
    if [ -n "$ttyd_pid" ] && kill -0 "$ttyd_pid" 2>/dev/null; then
        kill "$ttyd_pid" 2>/dev/null || true
        wait "$ttyd_pid" 2>/dev/null || true
    fi
    rm -rf "$temporary_dir"
}
trap cleanup EXIT

ttyd -p 17681 /bin/true >"$temporary_dir/ttyd.log" 2>&1 &
ttyd_pid=$!

for _ in $(seq 1 50); do
    if curl -fsS http://127.0.0.1:17681/ >"$default_index"; then
        break
    fi
    sleep 0.1
done

if [ ! -s "$default_index" ]; then
    echo "Não foi possível extrair o index.html integrado do ttyd." >&2
    exit 1
fi

awk -v bridge_file="$bridge_file" '
BEGIN {
    while ((getline line < bridge_file) > 0) {
        bridge = bridge line ORS
    }
    close(bridge_file)
}
{
    marker = "</body>"
    position = index($0, marker)
    if (!position) {
        print
        next
    }
    print substr($0, 1, position - 1)
    print "<script id=\"setupmno-terminal-touch-bridge\">"
    printf "%s", bridge
    print "</script>"
    print substr($0, position)
}
' "$default_index" >"$output_file"

grep -q 'setupmno-terminal-touch-bridge' "$output_file"
grep -q 'setupmno-terminal-touch' "$output_file"

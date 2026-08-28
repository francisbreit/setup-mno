#!/usr/bin/env bash
set -Eeuo pipefail

if [ "$#" -ne 3 ]; then
    printf 'Uso: %s DIRETORIO_FONTE IMAGEM ARQUIVO_LOG\n' "$0" >&2
    exit 2
fi

SOURCE_DIR="$1"
EXECUTOR_IMAGE="$2"
LOG_FILE="$3"
SMOKE_CONTAINER_NAME="${SETUPMNO_STRIX_SMOKE_CONTAINER_NAME:-}"
LAB_DIR="$SOURCE_DIR/strix-lab"
LOCK_FILE="$LAB_DIR/upstream-lock.json"

cleanup_smoke_container() {
    if [ -n "$SMOKE_CONTAINER_NAME" ] &&
       [[ "$SMOKE_CONTAINER_NAME" =~ ^setupmno-hml-strix-[0-9]{12}-smoke$ ]]; then
        docker rm -f "$SMOKE_CONTAINER_NAME" >/dev/null 2>&1 || true
    fi
}
trap cleanup_smoke_container EXIT

for required_command in docker jq python3 grep; do
    command -v "$required_command" >/dev/null 2>&1 || {
        printf 'SRE-6 BETA: dependencia ausente: %s.\n' "$required_command" >&2
        exit 3
    }
done

for required_file in upstream-lock.json validate.py executor.Dockerfile executor.py; do
    [ -s "$LAB_DIR/$required_file" ] && [ ! -L "$LAB_DIR/$required_file" ] || {
        printf 'SRE-6 BETA: fonte ausente ou inseguro: %s.\n' "$required_file" >&2
        exit 4
    }
done

python3 "$LAB_DIR/validate.py" lock >>"$LOG_FILE" 2>&1

runtime_arch=$(docker info --format '{{.Architecture}}' 2>>"$LOG_FILE" |
    tr '[:upper:]' '[:lower:]' | head -n1)
case "$runtime_arch" in
    amd64|x86_64) lock_arch="amd64" ;;
    arm64|aarch64) lock_arch="arm64" ;;
    *)
        printf 'SRE-6 BETA: arquitetura nao homologada: %s.\n' "${runtime_arch:-ausente}" >&2
        exit 5
        ;;
esac

base_image=$(jq -er '.sandbox.baseImage' "$LOCK_FILE")
base_digest=$(jq -er --arg arch "$lock_arch" '.sandbox.digests[$arch]' "$LOCK_FILE")
wheel_url=$(jq -er --arg arch "$lock_arch" '.artifacts[$arch].url' "$LOCK_FILE")
wheel_sha=$(jq -er --arg arch "$lock_arch" '.artifacts[$arch].sha256' "$LOCK_FILE")
[[ "$base_digest" =~ ^sha256:[a-f0-9]{64}$ ]] || exit 6
[[ "$wheel_sha" =~ ^[a-f0-9]{64}$ ]] || exit 6
[[ "$wheel_url" == https://files.pythonhosted.org/* ]] || exit 6

docker build --pull \
    --build-arg "STRIX_SANDBOX_BASE=${base_image}@${base_digest}" \
    --build-arg "STRIX_WHEEL_URL=$wheel_url" \
    --build-arg "STRIX_WHEEL_SHA256=$wheel_sha" \
    -f "$LAB_DIR/executor.Dockerfile" \
    -t "$EXECUTOR_IMAGE" "$SOURCE_DIR" >>"$LOG_FILE" 2>&1

smoke_args=(
    --user 61000:61000
    --read-only
    --cap-drop ALL
    --security-opt no-new-privileges:true
    --pids-limit 128
    --cpus 0.5
    --memory 1024m
    --network none
    --tmpfs /tmp:rw,nosuid,nodev,size=256m
)
if [ -n "$SMOKE_CONTAINER_NAME" ]; then
    [[ "$SMOKE_CONTAINER_NAME" =~ ^setupmno-hml-strix-[0-9]{12}-smoke$ ]] || exit 7
    docker create --name "$SMOKE_CONTAINER_NAME" "${smoke_args[@]}" \
        "$EXECUTOR_IMAGE" --smoke >>"$LOG_FILE" 2>&1
    docker inspect "$SMOKE_CONTAINER_NAME" >>"$LOG_FILE" 2>&1
    smoke_output=$(docker start -a "$SMOKE_CONTAINER_NAME" 2>>"$LOG_FILE")
    docker rm "$SMOKE_CONTAINER_NAME" >>"$LOG_FILE" 2>&1
else
    smoke_output=$(docker run --rm "${smoke_args[@]}" \
        "$EXECUTOR_IMAGE" --smoke 2>>"$LOG_FILE")
fi
printf '%s\n' "$smoke_output" >>"$LOG_FILE"
smoke_json=$(printf '%s\n' "$smoke_output" |
    grep -F 'SETUPMNO_STRIX_SMOKE:' | tail -n1)
[ -n "$smoke_json" ] || exit 7
printf '%s\n' "${smoke_json#*SETUPMNO_STRIX_SMOKE:}" | jq -e '
    .strixImported == true and
    .unixLocalSession == true and
    (.sessionUID | tostring) == "61000" and
    .executorUID == 61000 and
    .dockerSocketPresent == false and
    .sudoPresent == false' >>"$LOG_FILE" 2>&1

docker image inspect "$EXECUTOR_IMAGE" | jq -e '.[0] |
    .Config.User == "61000:61000" and
    (.Config.Entrypoint | type == "array") and
    ((.Config.Labels["io.setupmno.maturity"] // "") == "beta")' \
    >>"$LOG_FILE" 2>&1

printf 'SRE6_EXECUTOR_BUILD_OK:%s:%s\n' "$lock_arch" "$EXECUTOR_IMAGE"

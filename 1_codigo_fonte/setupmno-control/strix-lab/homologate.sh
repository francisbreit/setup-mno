#!/usr/bin/env bash
set -Eeuo pipefail

LAB_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SOURCE_DIR=$(cd "$LAB_DIR/.." && pwd)
RUN_ID="setupmno-hml-strix-$(date -u +%y%m%d%H%M%S)"
WORK_DIR="/tmp/setupmno-homologacao/$RUN_ID"
INVENTORY_FILE="/tmp/${RUN_ID}.inventory"
IMAGE_NAME="${RUN_ID}-executor:1.1.0"
SMOKE_CONTAINER="${RUN_ID}-smoke"
INSPECT_CONTAINER="${RUN_ID}-inspect"
LOG_FILE="$WORK_DIR/homologation.log"
cleaned=false

[[ "$RUN_ID" =~ ^setupmno-hml-strix-[0-9]{12}$ ]] || exit 2

cleanup_owned_resources() {
    local name
    for name in "$SMOKE_CONTAINER" "$INSPECT_CONTAINER"; do
        if [[ "$name" =~ ^setupmno-hml-strix-[0-9]{12}-(smoke|inspect)$ ]]; then
            docker rm -f "$name" >/dev/null 2>&1 || true
        fi
    done
    if [[ "$IMAGE_NAME" =~ ^setupmno-hml-strix-[0-9]{12}-executor:1\.1\.0$ ]]; then
        docker image rm "$IMAGE_NAME" >/dev/null 2>&1 || true
    fi
    if [[ "$WORK_DIR" =~ ^/tmp/setupmno-homologacao/setupmno-hml-strix-[0-9]{12}$ ]]; then
        rm -rf -- "$WORK_DIR"
    fi
    if [[ "$INVENTORY_FILE" =~ ^/tmp/setupmno-hml-strix-[0-9]{12}\.inventory$ ]]; then
        rm -f -- "$INVENTORY_FILE"
    fi
    cleaned=true
}

finish_homologation() {
    local status=$?
    if [ "$status" -ne 0 ] && [ -f "$LOG_FILE" ]; then
        printf '\nSRE-6 HOMOLOGAÇÃO: últimas evidências técnicas antes da limpeza:\n' >&2
        tail -n 80 "$LOG_FILE" >&2 || true
    fi
    cleanup_owned_resources
    exit "$status"
}
trap finish_homologation EXIT

for command_name in docker jq python3 date mkdir rm; do
    command -v "$command_name" >/dev/null 2>&1 || {
        printf 'SRE-6 HOMOLOGAÇÃO: dependência ausente: %s.\n' "$command_name" >&2
        exit 3
    }
done

for owned_name in "$SMOKE_CONTAINER" "$INSPECT_CONTAINER"; do
    if docker container inspect "$owned_name" >/dev/null 2>&1; then
        printf 'SRE-6 HOMOLOGAÇÃO: colisão com contêiner %s.\n' "$owned_name" >&2
        exit 4
    fi
done
if docker image inspect "$IMAGE_NAME" >/dev/null 2>&1; then
    printf 'SRE-6 HOMOLOGAÇÃO: colisão com imagem %s.\n' "$IMAGE_NAME" >&2
    exit 4
fi
[ ! -e "$WORK_DIR" ] || {
    printf 'SRE-6 HOMOLOGAÇÃO: diretório temporário já existe.\n' >&2
    exit 4
}

# O inventário é escrito antes de criar o primeiro recurso do laboratório.
printf 'run_id=%s\nwork_dir=%s\nimage=%s\ncontainers=%s,%s\n' \
    "$RUN_ID" "$WORK_DIR" "$IMAGE_NAME" "$SMOKE_CONTAINER" "$INSPECT_CONTAINER" \
    >"$INVENTORY_FILE"
chmod 0600 "$INVENTORY_FILE"
mkdir -p "$WORK_DIR"
chmod 0700 "$WORK_DIR"

printf 'SRE-6 HOMOLOGAÇÃO: construindo a imagem fixa e executando smoke test sem rede...\n'
SETUPMNO_STRIX_SMOKE_CONTAINER_NAME="$SMOKE_CONTAINER" \
    bash "$LAB_DIR/build-executor.sh" "$SOURCE_DIR" "$IMAGE_NAME" "$LOG_FILE"

docker create --name "$INSPECT_CONTAINER" \
    --user 61000:61000 \
    --read-only \
    --cap-drop ALL \
    --security-opt no-new-privileges:true \
    --pids-limit 128 \
    --cpus 0.5 \
    --memory 1024m \
    --network none \
    --tmpfs /tmp:rw,nosuid,nodev,size=256m \
    "$IMAGE_NAME" --smoke >"$WORK_DIR/container.id"

docker inspect "$INSPECT_CONTAINER" | jq -e '.[0] |
    .Config.User == "61000:61000" and
    .HostConfig.Privileged == false and
    .HostConfig.ReadonlyRootfs == true and
    ((.HostConfig.CapDrop // []) | index("ALL") != null) and
    ((.HostConfig.SecurityOpt // []) | index("no-new-privileges:true") != null) and
    ((.HostConfig.Binds // []) | length == 0) and
    ((.Mounts // []) | length == 0) and
    .HostConfig.NetworkMode == "none" and
    .HostConfig.PidsLimit == 128 and
    .HostConfig.Memory == 1073741824' >"$WORK_DIR/isolation.json"

smoke_output=$(docker start -a "$INSPECT_CONTAINER" 2>>"$LOG_FILE")
printf '%s\n' "$smoke_output" >>"$LOG_FILE"
printf '%s\n' "$smoke_output" | sed -n 's/^SETUPMNO_STRIX_SMOKE://p' | jq -e '
    .strixImported == true and
    .unixLocalSession == true and
    (.sessionUID | tostring) == "61000" and
    .executorUID == 61000 and
    .dockerSocketPresent == false and
    .sudoPresent == false' >"$WORK_DIR/smoke.json"

python3 "$LAB_DIR/validate.py" lock >/dev/null
docker image inspect "$IMAGE_NAME" | jq -e '.[0] |
    .Config.User == "61000:61000" and
    .Config.Labels["io.setupmno.maturity"] == "beta"' >/dev/null

printf 'SRE6_HOMOLOGATION_OK:%s\n' "$RUN_ID"
printf 'Isolamento comprovado: UID 61000, raiz somente leitura, zero capabilities, sem rede, mounts, root, sudo ou Docker socket.\n'

cleanup_owned_resources
trap - EXIT

if docker container inspect "$SMOKE_CONTAINER" >/dev/null 2>&1 ||
   docker container inspect "$INSPECT_CONTAINER" >/dev/null 2>&1 ||
   docker image inspect "$IMAGE_NAME" >/dev/null 2>&1 ||
   [ -e "$WORK_DIR" ] || [ -e "$INVENTORY_FILE" ]; then
    printf 'SRE-6 HOMOLOGAÇÃO: limpeza incompleta.\n' >&2
    exit 5
fi
printf 'SRE6_HOMOLOGATION_CLEANUP_OK:%s\n' "$RUN_ID"

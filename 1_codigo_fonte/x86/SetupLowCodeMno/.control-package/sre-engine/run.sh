#!/usr/bin/bash
set -Eeuo pipefail
umask 077

ENGINE_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
TOOLS_FILE="$ENGINE_DIR/tools.json"
NORMALIZER="$ENGINE_DIR/normalize.py"
SCHEMA_FILE="$ENGINE_DIR/result.schema.json"
MANIFEST_FILE="$ENGINE_DIR/manifest.json"
RESULT_FILE="${SETUPMNO_SRE_RESULT_FILE:-$ENGINE_DIR/latest.json}"
CACHE_DIR="${SETUPMNO_SRE_CACHE_DIR:-/root/.cache/setupmno-sre3}"

fail() {
    printf 'SRE-3 BETA: %s\n' "$1" >&2
    exit "${2:-1}"
}

[ "$(id -u)" = "0" ] || fail "execute pelo Terminal Seguro ou como root." 77
for command_name in curl docker ionice jq nice python3 sha256sum tar timeout; do
    command -v "$command_name" >/dev/null 2>&1 || fail "dependência ausente: $command_name." 69
done
[ -f "$TOOLS_FILE" ] && [ ! -L "$TOOLS_FILE" ] &&
[ -f "$NORMALIZER" ] && [ ! -L "$NORMALIZER" ] &&
[ -f "$SCHEMA_FILE" ] && [ ! -L "$SCHEMA_FILE" ] &&
[ -f "$MANIFEST_FILE" ] && [ ! -L "$MANIFEST_FILE" ] || fail "pacote do motor inválido." 78
jq -e '.schemaVersion == 1 and .engineVersion == "1.0.0" and .maturity == "beta"' \
    "$TOOLS_FILE" >/dev/null || fail "registro de ferramentas incompatível." 78
jq -e '.schemaVersion == 1 and .engineVersion == "1.0.0" and .maturity == "beta" and
    (.files | type == "array" and length == 4)' "$MANIFEST_FILE" >/dev/null ||
    fail "manifesto de integridade incompatível." 78
while IFS=$'\t' read -r relative expected_size expected_sha; do
    case "$relative" in
        normalize.py|result.schema.json|run.sh|tools.json) ;;
        *) fail "manifesto contém caminho não autorizado." 78 ;;
    esac
    candidate="$ENGINE_DIR/$relative"
    [ -f "$candidate" ] && [ ! -L "$candidate" ] || fail "arquivo protegido ausente: $relative." 78
    [ "$(stat -c '%s' "$candidate")" = "$expected_size" ] || fail "tamanho divergente: $relative." 78
    [ "$(sha256sum "$candidate" | awk '{print $1}')" = "$expected_sha" ] ||
        fail "hash divergente: $relative." 78
done < <(jq -r '.files[] | [.path, (.bytes | tostring), .sha256] | @tsv' "$MANIFEST_FILE")

if [ "${SETUPMNO_SRE3_TEST_MODE:-0}" != "1" ]; then
    whiptail --title "SRE-3 — AUDITORIA DETERMINÍSTICA (BETA)" --yesno \
        "Executar agora Trivy, Lynis e Docker Bench em modo somente leitura?\n\nA auditoria pode baixar até três ferramentas fixadas, consumir CPU, disco e internet por alguns minutos e produzir somente um resumo sanitizado. Nenhuma correção será aplicada.\n\nContinuar?" \
        18 82 || exit 0
fi

work_dir=$(mktemp -d /tmp/setupmno-sre3.XXXXXX) || fail "não foi possível criar área temporária."
run_suffix=${work_dir##*.}
[[ "$run_suffix" =~ ^[A-Za-z0-9]+$ ]] || fail "identidade temporária inválida."
owned_containers=()
cleanup() {
    local container_name
    for container_name in "${owned_containers[@]}"; do
        case "$container_name" in
            setupmno-sre3-*"-$run_suffix")
                docker container inspect "$container_name" >/dev/null 2>&1 &&
                    docker container rm -f "$container_name" >/dev/null 2>&1 || true
                ;;
        esac
    done
    rm -rf -- "$work_dir"
}
trap cleanup EXIT
mkdir -p "$work_dir/trivy" "$work_dir/downloads" "$work_dir/tools" "$CACHE_DIR/trivy"
chmod 0700 "$work_dir" "$work_dir/trivy" "$work_dir/downloads" "$work_dir/tools" "$CACHE_DIR" "$CACHE_DIR/trivy"

environment=unknown
if grep -qEi '(Microsoft|WSL)' /proc/version 2>/dev/null; then
    environment=wsl2
elif [ -r /etc/os-release ]; then
    environment=vps
fi

trivy_status=skipped
lynis_status=skipped
docker_bench_status=skipped
maximum_images=$(jq -r '.limits.maximumImages' "$TOOLS_FILE")
trivy_timeout=$(jq -r '.limits.trivyTimeoutSecondsPerImage' "$TOOLS_FILE")
lynis_timeout=$(jq -r '.limits.lynisTimeoutSeconds' "$TOOLS_FILE")
docker_bench_timeout=$(jq -r '.limits.dockerBenchTimeoutSeconds' "$TOOLS_FILE")

run_trivy() {
    local trivy_image image_tar result_file image_count=0 failures=0 image
    local image_list total_images db_container scan_container
    trivy_image=$(jq -r '.tools.trivy.image' "$TOOLS_FILE")
    docker image inspect "$trivy_image" >/dev/null 2>&1 ||
        timeout 300 docker pull "$trivy_image" >/dev/null 2>&1 || return 1
    # A base de vulnerabilidades é baixada sem acesso ao conteúdo das imagens.
    # Depois disso cada imagem é analisada com a rede totalmente desligada.
    db_container="setupmno-sre3-trivy-db-$run_suffix"
    owned_containers+=("$db_container")
    timeout 300 docker run --rm --name "$db_container" \
        --network bridge --read-only --cap-drop ALL --security-opt no-new-privileges \
        --pids-limit 128 --cpus 0.50 --memory 1g --tmpfs /tmp:rw,noexec,nosuid,size=512m \
        -v "$CACHE_DIR/trivy:/root/.cache" \
        "$trivy_image" image --download-db-only --cache-dir /root/.cache \
        --quiet >/dev/null 2>&1 || return 1
    image_list="$work_dir/trivy/images.txt"
    docker service ls --format '{{.Image}}' |
        sed 's/@sha256:[0-9a-f]\{64\}$//' | sort -u >"$image_list" || return 1
    total_images=$(awk 'NF {count++} END {print count+0}' "$image_list")
    while IFS= read -r image; do
        [ -n "$image" ] || continue
        image_count=$((image_count + 1))
        image_tar="$work_dir/trivy/image-${image_count}.tar"
        result_file="$work_dir/trivy/result-${image_count}.json"
        if ! timeout 300 docker image save --output "$image_tar" "$image" >/dev/null 2>&1; then
            failures=$((failures + 1))
            continue
        fi
        scan_container="setupmno-sre3-trivy-$image_count-$run_suffix"
        owned_containers+=("$scan_container")
        if ! timeout "$trivy_timeout" docker run --rm --name "$scan_container" \
            --network none --read-only --cap-drop ALL --security-opt no-new-privileges \
            --pids-limit 256 --cpus 1 --memory 1g --tmpfs /tmp:rw,noexec,nosuid,size=256m \
            -v "$image_tar:/input/image.tar:ro" \
            -v "$work_dir/trivy:/output" \
            -v "$CACHE_DIR/trivy:/root/.cache" \
            "$trivy_image" image --input /input/image.tar --format json \
            --output "/output/result-${image_count}.json" --scanners vuln \
            --skip-db-update --cache-dir /root/.cache --quiet >/dev/null 2>&1; then
            failures=$((failures + 1))
        fi
        rm -f -- "$image_tar"
    done < <(awk -v maximum="$maximum_images" 'NF && count < maximum {print; count++}' "$image_list")
    [ "$image_count" -gt 0 ] || return 1
    if [ "$failures" -eq 0 ] && [ "$total_images" -le "$maximum_images" ]; then
        trivy_status=completed
    else
        trivy_status=partial
    fi
}

running_inside_container() {
    [ -f /.dockerenv ] || grep -qE '(docker|containerd|kubepods)' /proc/1/cgroup 2>/dev/null
}

terminal_runtime_image() {
    local service="${SETUPMNO_CONTROL_TERMINAL_SERVICE:-}"
    [ -n "$service" ] || return 1
    docker service inspect "$service" --format '{{.Spec.TaskTemplate.ContainerSpec.Image}}' 2>/dev/null |
        awk 'NF {print; exit}'
}

download_verified() {
    local url="$1" expected_sha="$2" destination="$3" actual_sha
    timeout 180 curl -fsSL --proto '=https' --tlsv1.2 "$url" -o "$destination" || return 1
    actual_sha=$(sha256sum "$destination" | awk '{print $1}')
    [ "$actual_sha" = "$expected_sha" ]
}

run_lynis() {
    local url expected_sha archive source_dir runtime_image lynis_container
    url=$(jq -r '.tools.lynis.url' "$TOOLS_FILE")
    expected_sha=$(jq -r '.tools.lynis.sha256' "$TOOLS_FILE")
    archive="$work_dir/downloads/lynis.tar.gz"
    download_verified "$url" "$expected_sha" "$archive" || return 1
    tar -tzf "$archive" | awk '
        /^\// || /(^|\/)\.\.($|\/)/ { bad=1 }
        END { exit bad }
    ' || return 1
    tar -xzf "$archive" -C "$work_dir/tools" || return 1
    source_dir=$(find "$work_dir/tools" -mindepth 1 -maxdepth 1 -type d -name 'lynis*' -print -quit)
    [ -n "$source_dir" ] && [ -f "$source_dir/lynis" ] || return 1
    if running_inside_container; then
        runtime_image=$(terminal_runtime_image) || return 1
        lynis_container="setupmno-sre3-lynis-$run_suffix"
        owned_containers+=("$lynis_container")
        timeout "$lynis_timeout" nice -n 10 ionice -c 3 docker run --rm --name "$lynis_container" \
            --network none --pid host --read-only --cap-drop ALL \
            --cap-add DAC_READ_SEARCH --security-opt no-new-privileges \
            --pids-limit 256 --cpus 1 --memory 768m \
            --tmpfs /tmp:rw,noexec,nosuid,size=128m \
            --tmpfs /var/run:rw,noexec,nosuid,size=4m \
            -v /:/host:ro -v "$source_dir:/lynis:ro" -v "$work_dir:/output" \
            --workdir /lynis \
            --entrypoint /lynis/lynis "$runtime_image" audit system \
            --root-dir /host --usecwd --quick --no-colors --no-log \
            --report-file /output/lynis-report.dat >/dev/null 2>&1 || return 1
        # O modo root-dir é deliberadamente conservador: ele não equivale a
        # executar o Lynis diretamente no host, logo a cobertura fica parcial.
        lynis_status=partial
    else
        timeout "$lynis_timeout" nice -n 10 ionice -c 3 \
            "$source_dir/lynis" audit system --quick --no-colors --no-log \
            --report-file "$work_dir/lynis-report.dat" >/dev/null 2>&1 || return 1
        lynis_status=completed
    fi
}

run_docker_bench() {
    local url expected_sha archive source_dir runtime_image bench_container
    url=$(jq -r '.tools.dockerBench.url' "$TOOLS_FILE")
    expected_sha=$(jq -r '.tools.dockerBench.sha256' "$TOOLS_FILE")
    archive="$work_dir/downloads/docker-bench.tar.gz"
    download_verified "$url" "$expected_sha" "$archive" || return 1
    tar -tzf "$archive" | awk '
        /^\// || /(^|\/)\.\.($|\/)/ { bad=1 }
        END { exit bad }
    ' || return 1
    tar -xzf "$archive" -C "$work_dir/tools" || return 1
    source_dir=$(find "$work_dir/tools" -mindepth 1 -maxdepth 1 -type d -name 'docker-bench-security*' -print -quit)
    [ -n "$source_dir" ] && [ -f "$source_dir/docker-bench-security.sh" ] || return 1
    # O hash do arquivo fixa a revisão de código já homologada. Clientes de
    # rede continuam proibidos e dois checks intrusivos do upstream são sempre
    # excluídos: 5.7 usa docker exec e 7.5 consulta a chave de desbloqueio.
    # O socket nunca chega ao Trivy, ao Lynis ou à LLM.
    if grep -ERq --include='*.sh' \
        '(^|[;&|[:space:]])(curl|ftp|nc|ncat|scp|sftp|socat|ssh|telnet|wget)[[:space:]]' \
        "$source_dir"; then
        return 1
    fi
    grep -Fq 'processes=$(docker exec "$c" ps -el' \
        "$source_dir/tests/5_container_runtime.sh" || return 1
    grep -Fq 'docker swarm unlock-key' \
        "$source_dir/tests/7_docker_swarm_configuration.sh" || return 1
    if running_inside_container; then
        runtime_image=$(terminal_runtime_image) || return 1
        bench_container="setupmno-sre3-docker-bench-$run_suffix"
        owned_containers+=("$bench_container")
        timeout "$docker_bench_timeout" nice -n 10 ionice -c 3 docker run --rm --name "$bench_container" \
            --network none --pid host --userns host --read-only --cap-drop ALL \
            --cap-add AUDIT_CONTROL --security-opt no-new-privileges \
            --pids-limit 256 --cpus 1 --memory 512m \
            --tmpfs /tmp:rw,noexec,nosuid,size=128m \
            -v /etc:/etc:ro -v /var/lib:/var/lib:ro \
            -v /var/run/docker.sock:/var/run/docker.sock:ro \
            -v "$source_dir:/bench:ro" --label docker.bench.security=true \
            --workdir /bench \
            --entrypoint /bin/sh "$runtime_image" \
            /bench/docker-bench-security.sh -b -l /tmp/docker-bench-security.log \
            -e check_5_7,check_7_5 \
            >"$work_dir/docker-bench.log" 2>/dev/null || return 1
        # A execução segura mantém a rede desligada e não replica todos os
        # namespaces recomendados pelo upstream; a cobertura é assumidamente parcial.
        docker_bench_status=partial
    else
        if ! (
            cd "$source_dir"
            timeout "$docker_bench_timeout" nice -n 10 ionice -c 3 \
                /bin/sh ./docker-bench-security.sh -b \
                -e check_5_7,check_7_5 \
                >"$work_dir/docker-bench.log" 2>/dev/null
        ); then
            return 1
        fi
        docker_bench_status=completed
    fi
}

printf 'SRE-3 BETA: executando Trivy com alvos efêmeros e sem Docker socket no scanner...\n'
run_trivy || trivy_status=failed
printf 'SRE-3 BETA: executando Lynis no host...\n'
run_lynis || lynis_status=failed
printf 'SRE-3 BETA: executando Docker Bench no host...\n'
run_docker_bench || docker_bench_status=failed

jq -n --arg trivy "$trivy_status" --arg lynis "$lynis_status" \
    --arg docker_bench "$docker_bench_status" \
    '{trivy:$trivy,lynis:$lynis,"docker-bench":$docker_bench}' \
    >"$work_dir/execution-status.json"

python3 -B "$NORMALIZER" \
    --tools "$TOOLS_FILE" \
    --execution-status "$work_dir/execution-status.json" \
    --trivy-dir "$work_dir/trivy" \
    --lynis-report "$work_dir/lynis-report.dat" \
    --docker-bench-log "$work_dir/docker-bench.log" \
    --environment "$environment" \
    --output "$RESULT_FILE"

overall_status=$(jq -r '.overallStatus' "$RESULT_FILE")
complete=$(jq -r '.complete' "$RESULT_FILE")
printf 'SRE-3 BETA: resultado sanitizado salvo. estado=%s coberturaCompleta=%s\n' \
    "$overall_status" "$complete"
if [ "${SETUPMNO_SRE3_TEST_MODE:-0}" != "1" ]; then
    whiptail --title "SRE-3 — AUDITORIA CONCLUÍDA (BETA)" --msgbox \
        "Resultado sanitizado criado.\n\nEstado: ${overall_status}\nCobertura completa: ${complete}\n\nFalhas e cobertura parcial permanecem visíveis. O Assistente apenas poderá ler esse resumo; nenhuma correção foi aplicada." \
        16 78
fi

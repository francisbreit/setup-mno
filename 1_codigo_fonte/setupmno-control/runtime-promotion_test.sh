#!/usr/bin/bash
set -euo pipefail

project_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source_root=$(cd "$project_dir/.." && pwd)
boundary_tool="$project_dir/shc_boundary.py"
boundary_policy="$project_dir/shc-boundary-policy.json"
test_dir=$(mktemp -d)
trap 'rm -rf -- "$test_dir"' EXIT

for architecture in x86 arm; do
    if [ "$architecture" = "x86" ]; then
        start_script="$source_root/x86/start_full.sh"
    else
        start_script="$source_root/arm/start_arm_full.sh"
    fi
    runtime_package="$source_root/$architecture/SetupLowCodeMno/.control-package"
    test_root="$test_dir/$architecture/SetupLowCodeMno"
    promotion_script="$test_dir/promote-$architecture.sh"
    mkdir -p "$test_root/.control-package"
    cp -a "$runtime_package/." "$test_root/.control-package/"

    {
        printf '%s\n' '#!/usr/bin/bash' 'set -euo pipefail'
        sed -n '3,/^umask 077$/p' "$start_script"
        printf '%s\n' 'control_state_error="$SETUPMNO_PROMOTION_TEST_ROOT/control-state-error.log"'
        awk '
            /^control_package="\/root\/SetupLowCodeMno\/\.control-package"$/ { capture=1 }
            capture { print }
            capture && /^rm -rf "\$control_package"$/ { exit }
        ' "$start_script"
    } >"$promotion_script"
    sed -i \
        -e 's#control_package="/root/SetupLowCodeMno/.control-package"#control_package="$SETUPMNO_PROMOTION_TEST_ROOT/.control-package"#' \
        -e 's#control_target="/root/SetupLowCodeMno/.control"#control_target="$SETUPMNO_PROMOTION_TEST_ROOT/.control"#' \
        "$promotion_script"
    chmod 0700 "$promotion_script"

    if ! PLANO=pro-master SETUPMNO_PROMOTION_TEST_ROOT="$test_root" bash "$promotion_script"; then
        printf 'Promoção válida falhou em %s: ' "$architecture" >&2
        cat "$test_root/control-state-error.log" >&2 2>/dev/null || true
        exit 1
    fi
    [ ! -e "$test_root/.control-package" ]
    [ ! -s "$test_root/control-state-error.log" ]

    while IFS= read -r packaged_file; do
        [ -n "$packaged_file" ]
        promoted_file="$test_root/.control/homologation-package/$packaged_file"
        [ -f "$promoted_file" ] && [ ! -L "$promoted_file" ]
        cmp -s "$runtime_package/homologation-package/$packaged_file" "$promoted_file"
    done < <(jq -r '.files[].path' "$runtime_package/homologation-package/manifest.json")

    for runtime_file in catalog.json release.json protection-boundary.json control-source.tar.gz; do
        cmp -s "$runtime_package/$runtime_file" "$test_root/.control/$runtime_file"
    done
    for runtime_file in maintainer_console.sh maintainer_workspace.sh \
        maintainer_validation_wizard.sh certification_wizard.sh maintainer-workspace.tar.gz; do
        [ -f "$test_root/.control/homologation-package/$runtime_file" ] || {
            printf 'PRO MASTER não promoveu %s em %s.\n' "$runtime_file" "$architecture" >&2
            exit 1
        }
    done
    for knowledge_file in manifest.json knowledge-package.tar.gz; do
        cmp -s "$runtime_package/knowledge-package/$knowledge_file" \
            "$test_root/.control/knowledge-package/$knowledge_file"
    done
    for supply_chain_file in manifest.json sbom.cdx.json image-inventory.json attestation.intoto.json; do
        cmp -s "$runtime_package/supply-chain/$supply_chain_file" \
            "$test_root/.control/supply-chain/$supply_chain_file"
    done

    mkdir -p "$test_root/.control-package"
    cp -a "$runtime_package/." "$test_root/.control-package/"
    if ! PLANO=pro SETUPMNO_PROMOTION_TEST_ROOT="$test_root" bash "$promotion_script"; then
        printf 'Promoção válida do plano PRO falhou em %s: ' "$architecture" >&2
        cat "$test_root/control-state-error.log" >&2 2>/dev/null || true
        exit 1
    fi
    [ ! -e "$test_root/.control-package" ]
    [ ! -e "$test_root/.control/homologation-package" ]
    for supply_chain_file in manifest.json sbom.cdx.json image-inventory.json attestation.intoto.json; do
        cmp -s "$runtime_package/supply-chain/$supply_chain_file" \
            "$test_root/.control/supply-chain/$supply_chain_file"
    done

    mkdir -p "$test_root/.control-package"
    cp -a "$runtime_package/." "$test_root/.control-package/"
    printf '\n' >>"$test_root/.control-package/supply-chain/image-inventory.json"
    if PLANO=pro-master SETUPMNO_PROMOTION_TEST_ROOT="$test_root" bash "$promotion_script"; then
        printf 'Pacote supply-chain adulterado foi aceito em %s.\n' "$architecture" >&2
        exit 1
    fi
    [ -s "$test_root/control-state-error.log" ]
    rm -rf -- "$test_root/.control-package"

    # Simula a tentativa mais forte contra os módulos legíveis: altera um
    # arquivo, recria seu inventário e também atualiza release.json. Mesmo
    # assim, o hash do release preso dentro do start protegido por SHC precisa
    # bloquear a promoção.
    mkdir -p "$test_root/.control-package"
    cp -a "$runtime_package/." "$test_root/.control-package/"
    printf '\nmodulo adulterado\n' >>"$test_root/.control-package/control-source.tar.gz"
    python3 -B "$boundary_tool" generate \
        --package "$test_root/.control-package" --policy "$boundary_policy" \
        --setup-version "$(jq -r '.setupVersion' "$runtime_package/release.json")" \
        --architecture "$(jq -r '.architecture' "$runtime_package/release.json")" >/dev/null
    boundary_sha=$(sha256sum "$test_root/.control-package/protection-boundary.json" | awk '{print $1}')
    boundary_bytes=$(stat -c '%s' "$test_root/.control-package/protection-boundary.json")
    boundary_entries=$(jq -r '.artifactCount' "$test_root/.control-package/protection-boundary.json")
    jq --arg sha "$boundary_sha" --argjson bytes "$boundary_bytes" \
        --argjson entries "$boundary_entries" \
        '.protectionBoundarySHA256 = $sha |
         .protectionBoundaryBytes = $bytes |
         .protectionBoundaryEntries = $entries' \
        "$test_root/.control-package/release.json" >"$test_root/.control-package/release.json.new"
    mv -f "$test_root/.control-package/release.json.new" \
        "$test_root/.control-package/release.json"
    if PLANO=pro-master SETUPMNO_PROMOTION_TEST_ROOT="$test_root" bash "$promotion_script"; then
        printf 'Módulo e manifestos adulterados foram aceitos em %s.\n' "$architecture" >&2
        exit 1
    fi
    [ -s "$test_root/control-state-error.log" ]
    rm -rf -- "$test_root/.control-package"
done

printf 'Promoção runtime, fronteira SHC fail-closed, supply-chain e remoção da homologação fora do PRO MASTER aprovadas em x86/ARM.\n'

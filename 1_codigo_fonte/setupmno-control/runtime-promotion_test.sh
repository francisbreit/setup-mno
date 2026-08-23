#!/usr/bin/bash
set -euo pipefail

project_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source_root=$(cd "$project_dir/.." && pwd)
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
        sed -n '3,11p' "$start_script"
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

    for runtime_file in catalog.json release.json control-source.tar.gz; do
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
done

printf 'Promoção runtime, supply-chain fail-closed e remoção da homologação fora do PRO MASTER aprovadas em x86/ARM.\n'

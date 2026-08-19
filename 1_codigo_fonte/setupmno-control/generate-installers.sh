#!/usr/bin/bash
set -euo pipefail

project_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source_root=$(cd "$project_dir/.." && pwd)
template="$project_dir/installer-template.sh"
x86_target="$source_root/x86/SetupLowCodeMno/setupmno_control.sh"
arm_target="$source_root/arm/SetupLowCodeMno/setupmno_control.sh"
x86_runtime_package="$source_root/x86/SetupLowCodeMno/.control-package"
arm_runtime_package="$source_root/arm/SetupLowCodeMno/.control-package"
homologation_package="$project_dir/homologation-package"
temporary_dir=$(mktemp -d)
trap 'rm -rf "$temporary_dir"' EXIT

scrolltext_flag='--scrolltext'
msgbox_flag='--msgbox'
if grep -R -F --include='*.sh' --exclude='setupmno_control.sh' \
    -e "$scrolltext_flag $msgbox_flag" -e "$msgbox_flag $scrolltext_flag" \
    "$source_root"; then
    printf 'ERRO: --scrolltext em msgbox tira o foco inicial de <Ok> e exige Tab.\n' >&2
    exit 1
fi

msg_function=$(awk '/^msg\(\)/,/^}/' "$template")
grep -Fq '1>&2' <<<"$msg_function" || {
    printf 'ERRO: msg() precisa direcionar a interface Whiptail para stderr.\n' >&2
    exit 1
}
for collector in ask_required ask_with_default ask_llm_key ask_password; do
    collector_function=$(awk -v name="$collector" '
        $0 ~ "^" name "\\(\\)" { inside=1 }
        inside { print }
        inside && /^}/ { exit }
    ' "$template")
    grep -Fq 'return 130' <<<"$collector_function" || {
        printf 'ERRO: %s não propaga o cancelamento ao chamador.\n' "$collector" >&2
        exit 1
    }
    if grep -Fq 'exit 0' <<<"$collector_function"; then
        printf 'ERRO: %s encerra apenas o subshell da coleta.\n' "$collector" >&2
        exit 1
    fi
done
unhandled_collectors=$(grep -E '^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*=\$\(ask_' "$template" || true)
[ -z "$unhandled_collectors" ] || {
    printf 'ERRO: coleta Whiptail sem tratamento explícito de cancelamento:\n%s\n' \
        "$unhandled_collectors" >&2
    exit 1
}
ask_required_line=$(grep -n '^ask_required()' "$template" | cut -d: -f1)
configure_dispatch_line=$(grep -n -- '--configure-access-mfa)' "$template" | cut -d: -f1)
[ -n "$ask_required_line" ] && [ -n "$configure_dispatch_line" ] &&
[ "$ask_required_line" -lt "$configure_dispatch_line" ] || {
    printf 'ERRO: ask_required() precisa existir antes do despacho direto --configure-access-mfa.\n' >&2
    exit 1
}

route_guard="$project_dir/cloudflare-route-guard.sh"
access_reconcile="$project_dir/cloudflare-access-reconcile.sh"
bash -n "$route_guard"
bash -n "$access_reconcile"
grep -Fq 'cf_route_guard_inventory "$url_control" "$TUNNEL_ID"' "$template" &&
grep -Fq 'cf_route_guard_choose "$control_route_inventory"' "$template" &&
grep -Fq 'cf_route_guard_apply_dns' "$template" &&
grep -Fq 'cf_route_guard_remove_old_routes' "$template" &&
grep -Fq 'cf_route_guard_restore_dns' "$template" &&
grep -Fq 'cf_route_guard_restore_tunnels' "$template" || {
    printf 'ERRO: Control Center sem proteção transacional completa de rotas Cloudflare.\n' >&2
    exit 1
}
grep -Fq -- '--connect-timeout "${CLOUDFLARE_CONNECT_TIMEOUT:-10}"' "$route_guard" &&
grep -Fq -- '--max-time "${CLOUDFLARE_MAX_TIME:-45}"' "$route_guard" || {
    printf 'ERRO: proteção de rotas Cloudflare sem limites de rede.\n' >&2
    exit 1
}
access_reconcile_curl_calls=$(grep -Fc 'curl -sS' "$access_reconcile")
[ "$access_reconcile_curl_calls" -gt 0 ] &&
[ "$(grep -Fc -- '--connect-timeout "$CLOUDFLARE_CONNECT_TIMEOUT"' "$access_reconcile")" -eq "$access_reconcile_curl_calls" ] &&
[ "$(grep -Fc -- '--max-time "$CLOUDFLARE_MAX_TIME"' "$access_reconcile")" -eq "$access_reconcile_curl_calls" ] || {
    printf 'ERRO: reconciliação Access SEM_MFA sem limites de rede uniformes.\n' >&2
    exit 1
}
cloudflare_curl_calls=$(grep -Fc 'curl -sS' "$template")
[ "$cloudflare_curl_calls" -gt 0 ] &&
[ "$(grep -Fc -- '--connect-timeout "$CLOUDFLARE_CONNECT_TIMEOUT"' "$template")" -eq "$cloudflare_curl_calls" ] &&
[ "$(grep -Fc -- '--max-time "$CLOUDFLARE_MAX_TIME"' "$template")" -eq "$cloudflare_curl_calls" ] || {
    printf 'ERRO: chamadas Cloudflare sem limites de rede uniformes.\n' >&2
    exit 1
}
bash "$project_dir/installer-template_test.sh"
bash "$project_dir/cloudflare-mfa_test.sh"
bash "$project_dir/mfa-state_test.sh"
bash "$project_dir/configure-control_test.sh"
bash "$project_dir/control-runtime-transition_test.sh"
bash "$project_dir/control-runtime-selfheal_test.sh"
bash "$project_dir/domain-profiles_test.sh"
bash "$project_dir/primary-tunnel-bootstrap_test.sh"
bash "$project_dir/cloudflare-route-guard_test.sh"
bash "$project_dir/wsl-docker-preflight_test.sh"
bash "$project_dir/debian13-apt-recovery_test.sh"
bash "$project_dir/catalog-html-count_test.sh"
python3 -B "$source_root/setupmno-knowledge/tools/test_homologation_runner.py"
python3 -B "$source_root/setupmno-knowledge/tools/test_certification.py"
bash "$project_dir/homologation-wizard_test.sh"
homologation_wizard="$source_root/setupmno-knowledge/tools/homologation_wizard.sh"
bash -n "$homologation_wizard"
[ "$(SETUPMNO_HOMOLOGATION_WIZARD_SMOKE_TEST=1 bash "$homologation_wizard")" = \
    "setupmno-homologation-wizard-ok" ] || {
    printf 'ERRO: smoke test do assistente visual de homologação falhou.\n' >&2
    exit 1
}
grep -Fq '1>&2' "$homologation_wizard" &&
grep -Fq 'decide --bundle' "$homologation_wizard" &&
grep -Fq 'automaticPromotion' "$source_root/setupmno-knowledge/schema/homologation-candidate.schema.json" &&
! grep -Eq '(^|[[:space:]])(eval|bash -c|sh -c)[[:space:]]' "$homologation_wizard" || {
    printf 'ERRO: assistente visual sem stderr, fronteira de confiança ou allowlist de comandos.\n' >&2
    exit 1
}
certification_wizard="$source_root/setupmno-knowledge/tools/certification_wizard.sh"
certifier="$source_root/setupmno-knowledge/tools/certify_homologation.py"
bash -n "$certification_wizard"
[ "$(SETUPMNO_CERTIFICATION_WIZARD_SMOKE_TEST=1 bash "$certification_wizard")" = \
    "setupmno-certification-wizard-ok" ] || {
    printf 'ERRO: smoke test do assistente administrativo de certificação falhou.\n' >&2
    exit 1
}
python3 -B -c 'import pathlib,sys; compile(pathlib.Path(sys.argv[1]).read_text(), sys.argv[1], "exec")' \
    "$certifier"
grep -Fq 'confirmationToken' "$certifier" &&
grep -Fq 'automaticPromotion": False' "$certifier" &&
grep -Fq 'officialSeal": True' "$certifier" &&
grep -Fq 'CERTIFICAÇÃO INTERROMPIDA' "$certification_wizard" &&
grep -Fq 'dry-run' "$certification_wizard" &&
grep -Fq 'rollback' "$certification_wizard" &&
! grep -Eq '(^|[[:space:]])(eval|bash -c|sh -c)[[:space:]]' "$certification_wizard" || {
    printf 'ERRO: esteira oficial do selo sem confirmação, rollback ou fronteira administrativa.\n' >&2
    exit 1
}
python3 -B -c 'import pathlib,sys; compile(pathlib.Path(sys.argv[1]).read_text(), sys.argv[1], "exec")' \
    "$source_root/setupmno-knowledge/tools/import_homologation_review.py"
grep -Fq 'mux.HandleFunc("GET /homologation", authorize' "$project_dir/main.go" &&
grep -Fq 'mux.Handle("GET /api/homologation"' "$project_dir/main.go" &&
grep -Fq 'Central de Revisão de Homologação' "$project_dir/web/index.html" &&
grep -Fq 'function renderHomologation()' "$project_dir/web/app.js" &&
grep -Fq '"officialSeal": False' "$source_root/setupmno-knowledge/tools/import_homologation_review.py" || {
    printf 'ERRO: Central de Revisão sem endpoint fixo, interface ou fronteira de selo.\n' >&2
    exit 1
}

for architecture in x86 arm; do
    install_script="$source_root/$architecture/SetupLowCodeMno/install.sh"
    security_diagnostic_script="$source_root/$architecture/SetupLowCodeMno/securitydiagnostic.sh"
    foundation_script="$source_root/$architecture/SetupLowCodeMno/dockerswarm.sh"
    if [ "$architecture" = "x86" ]; then
        start_script="$source_root/x86/start_full.sh"
    else
        start_script="$source_root/arm/start_arm_full.sh"
    fi
    bash -n "$install_script"
    bash -n "$security_diagnostic_script"
    bash -n "$foundation_script"
    bash -n "$start_script"
    grep -Fq 'apt-get install -y wget curl unzip zip jq python3 build-essential' "$start_script" || {
        printf 'ERRO: %s não instala o Python 3 exigido pelo Homologation Runner.\n' \
            "$architecture" >&2
        exit 1
    }
    install_script_bytes=$(stat -c '%s' "$install_script")
    security_diagnostic_bytes=$(stat -c '%s' "$security_diagnostic_script")
    [ "$install_script_bytes" -le 122880 ] || {
        printf 'ERRO: %s possui %s bytes e ultrapassa a margem segura de 120 KiB do SHC.\n' \
            "$install_script" "$install_script_bytes" >&2
        exit 1
    }
    [ "$security_diagnostic_bytes" -le 122880 ] || {
        printf 'ERRO: %s possui %s bytes e ultrapassa a margem segura de 120 KiB do SHC.\n' \
            "$security_diagnostic_script" "$security_diagnostic_bytes" >&2
        exit 1
    }
    [ "$(grep -Fc '"DIAGNÓSTICO DE SEGURANÇA DO SERVIDOR" ""' "$install_script")" -eq 4 ]
    [ "$(grep -Fc '"DIAGNÓSTICO DE SEGURANÇA DO SERVIDOR") run_app securitydiagnostic ;;' "$install_script")" -eq 4 ]
    ! grep -Fq 'show_server_security_diagnostic()' "$install_script"
    grep -Fq -- '-o securitydiagnostic -f securitydiagnostic.sh' "$start_script"
    grep -Fq 'control_center_installed()' "$install_script"
    grep -Fq 'ensure_control_center_runtime_access()' "$install_script"
    grep -Fq 'reconcile_control_center_release()' "$install_script"
    grep -Fq 'setupmno_control --reconcile-existing' "$install_script"
    grep -Fq 'if control_center_installed; then' "$install_script"
    grep -Fq 'if ! ensure_control_center_runtime_access; then' "$install_script"
    grep -Fq 'control_center_agent_has_runtime_mount "$service" && return 0' "$install_script"
    ! grep -Fq 'ATUALIZAR CONTROL CENTER' "$install_script"
    grep -Fq 'control_center_installed()' "$foundation_script"
    grep -Fq 'offer_control_center_installation()' "$foundation_script"
    grep -Fq 'A instalação é opcional.' "$foundation_script"
    [ "$(grep -Fc '"${CONTROL_CENTER_MENU[@]}"' "$install_script")" -eq 1 ]
    [ "$(grep -Fc '"${CONTROL_CENTER_FREE_MENU[@]}"' "$install_script")" -eq 3 ]
    [ "$(grep -Fc '"${CONTROL_CENTER_MFA_MENU[@]}"' "$install_script")" -eq 4 ]
    [ "$(grep -Fc '"CONFIGURAR MFA CONTROL CENTER") configure_control_center_mfa ;;' "$install_script")" -eq 4 ]
    grep -Fq 'setupmno_control --configure-access-mfa' "$install_script"
    grep -Fq 'CONTROL_MFA_STATE_FILE="/root/SetupLowCodeMno/.control/mfa-state.json"' "$install_script"
    grep -Fq 'ensure_control_mfa_decision()' "$install_script"
    grep -Fq 'legacy-detected' "$install_script"
    grep -Fq 'CONTROL_CENTER_MFA_MENU=("CONFIGURAR MFA CONTROL CENTER" "")' "$install_script"
    ! grep -Fq 'control_center_mfa_configured' "$install_script"
    grep -Fq 'choose_control_mfa_preference()' "$foundation_script"
    grep -Fq 'fresh-portainer' "$foundation_script"
    grep -Fq '6) MFA Control Center: $CONTROL_MFA_SUMMARY' "$foundation_script"
    ! grep -Fq 'exit 42' "$install_script"
    [ "$(grep -Fc 'if [ "$CHOICE" != "SETUP MNO CONTROL CENTER" ] &&' "$install_script")" -eq 3 ] || {
        printf 'ERRO: Control Center continua bloqueado por uma lista de permissão free/free1/free2 em %s.\n' \
            "$install_script" >&2
        exit 1
    }
    ! grep -Fq 'CONTROL_CENTER_PRO_MENU' "$install_script"

    # O start_full é o único ponto que autentica o cliente. O dockerswarm
    # recebe somente o plano validado e jamais pode tentar reutilizar credenciais.
    if grep -Fq 'verificar_cliente "$EMAIL" "$SENHA"' "$foundation_script"; then
        printf 'ERRO: %s tenta revalidar o plano sem credenciais e pode apagar o estado autenticado.\n' \
            "$foundation_script" >&2
        exit 1
    fi
    for state_script in "$start_script" "$install_script" "$foundation_script"; do
        grep -Fq 'valid_setup_plan()' "$state_script" &&
        grep -Fq 'write_trial_state()' "$state_script" &&
        grep -Fq 'mktemp ' "$state_script" &&
        grep -Fq 'mv -f ' "$state_script" || {
            printf 'ERRO: persistência atômica do plano ausente em %s.\n' "$state_script" >&2
            exit 1
        }
    done
    if grep -Eq 'echo "PLANO=.*"[[:space:]]*>>[[:space:]]*"?\$TRIAL_FILE' \
        "$start_script" "$install_script" "$foundation_script"; then
        printf 'ERRO: gravação incremental do plano detectada em %s.\n' "$architecture" >&2
        exit 1
    fi
    grep -Fq 'prepare_setup_directory_preserving_control "/root/SetupLowCodeMno"' "$start_script" &&
    grep -Fq "! -name '.control'" "$start_script" &&
    ! grep -Fq 'mv "$live_dir" "$hold_dir/.control"' "$start_script" &&
    grep -Fq 'reconcile_control_center_plan_services "$PLANO"' "$start_script" &&
    grep -Fq 'swarm_state=$(docker info --format' "$start_script" &&
    grep -Fq '[ "$swarm_state" = "inactive" ] && return 0' "$start_script" &&
    grep -Fq 'service_has_mount_target "$service" /runtime-control' "$start_script" &&
    grep -Fq 'service_has_running_task "$service"' "$start_script" &&
    grep -Fq 'current_states=$(docker service ps --filter desired-state=running' "$start_script" &&
    grep -Fq 'wait_for_service_mount_target "$service" /runtime-control' "$start_script" &&
    grep -Fq 'service_has_env_key "$service" SETUPMNO_PLAN' "$start_script" &&
    grep -Fq 'wait_for_service_env_value "$service" SETUPMNO_PLAN "$plan"' "$start_script" &&
    grep -Fq -- '--mount-rm /runtime-control' "$start_script" &&
    grep -Fq -- '--mount-add type=bind,src=/root/SetupLowCodeMno/.control,dst=/runtime-control,readonly' "$start_script" &&
    grep -Fq 'docker service update --replicas "$assistant_replicas"' "$start_script" &&
    grep -Fq -- '--env-rm SETUPMNO_PLAN --env-add "SETUPMNO_PLAN=$plan"' "$start_script" &&
    grep -Fq 'O estado anterior do painel foi restaurado quando disponível.' "$start_script" || {
        printf 'ERRO: %s não preserva o runtime, a estabilidade do agente ou o plano do painel.\n' \
            "$architecture" >&2
        exit 1
    }
done

cmp -s "$source_root/x86/SetupLowCodeMno/securitydiagnostic.sh" \
    "$source_root/arm/SetupLowCodeMno/securitydiagnostic.sh" || {
    printf 'ERRO: o diagnóstico de segurança diverge entre x86 e ARM.\n' >&2
    exit 1
}

grep -Fq 'write_control_mfa_state true true false menu-enabled' "$template" &&
grep -Fq 'write_control_mfa_state false false false menu-disabled' "$template" &&
grep -Fq '"ATIVAR" "Configurar Cloudflare Access + MFA agora"' "$template" &&
grep -Fq '"INSTRUCOES" "Ver o passo a passo completo do Cloudflare"' "$template" &&
grep -Fq '"DESATIVAR" "Remover Access e restaurar Tunnel direto + login local"' "$template" || {
    printf 'ERRO: ciclo persistente de ativação/desativação do MFA está incompleto.\n' >&2
    exit 1
}

grep -Fq -- '- /root/SetupLowCodeMno/.control:/runtime-control:ro' "$template" || {
    printf 'ERRO: o agente precisa montar somente o estado runtime do Control Center.\n' >&2
    exit 1
}
grep -Fq -- '- /root/setupmno-homologation-candidates:/homologation-candidates:ro' "$template" &&
grep -Fq 'HOMOLOGATION_CANDIDATE_DIR=/homologation-candidates' "$project_dir/control-upgrade.sh" &&
grep -Fq -- '--mount-add type=bind,src=/root/setupmno-homologation-candidates,dst=/homologation-candidates,readonly' "$project_dir/control-upgrade.sh" || {
    printf 'ERRO: a Central de Revisão não possui mount somente leitura no agente.\n' >&2
    exit 1
}
if grep -Fq -- '- /root:/hostfs' "$template"; then
    printf 'ERRO: o agente não pode montar o diretório /root inteiro.\n' >&2
    exit 1
fi
grep -Fq 'HEALTHCHECK_URL=http://127.0.0.1:9090/health' "$template" || {
    printf 'ERRO: healthcheck interno do agente não configurado.\n' >&2
    exit 1
}
grep -Fq 'GET /blueprints", authorize' "$project_dir/main.go" &&
grep -Fq 'GET /blueprints/{blueprintId}/download", authorize' "$project_dir/main.go" &&
grep -Fq 'loadRuntimeBlueprintKnowledge(setupStateDir)' "$project_dir/main.go" &&
grep -Fq 'a.runtimeBlueprintCatalog(r.Context())' "$project_dir/blueprint_recommendation.go" || {
    printf 'ERRO: Blueprints não são servidos pelo agente runtime validado.\n' >&2
    exit 1
}
for install_script in \
    "$source_root/x86/SetupLowCodeMno/install.sh" \
    "$source_root/arm/SetupLowCodeMno/install.sh"; do
    grep -Fq 'reconcile_control_center_release()' "$install_script" &&
    grep -Fq 'setupmno_control --reconcile-existing' "$install_script" &&
    grep -Fq 'if control_center_installed; then' "$install_script" || {
        printf 'ERRO: reconciliação automática do Control Center ausente em %s.\n' \
            "$install_script" >&2
        exit 1
    }
done
grep -Fq 'http://127.0.0.1:7681/terminal/' "$template" || {
    printf 'ERRO: healthcheck interno do terminal não configurado.\n' >&2
    exit 1
}
[ "$(grep -Fc 'user: "65532:65532"' "$template")" -eq 2 ] || {
    printf 'ERRO: web e Assistente precisam executar como usuário não-root.\n' >&2
    exit 1
}
[ "$(grep -c '^[[:space:]]*cap_drop:' "$template")" -eq 3 ] || {
    printf 'ERRO: hardening cap_drop divergente entre agente, Assistente e web.\n' >&2
    exit 1
}
grep -Fq 'KNOWLEDGE_PACKAGE_DIR=/knowledge-package' "$template" || {
    printf 'ERRO: Assistente sem caminho explícito para o conhecimento somente leitura.\n' >&2
    exit 1
}
assistant_stack_block=$(awk '
    /cat >"\$\{assistant_stack\}\.yaml"/ { inside=1 }
    inside { print }
    inside && /cat >"\$\{web_stack\}\.yaml"/ { exit }
' "$template")
if grep -Eq '^[[:space:]]+volumes:' <<<"$assistant_stack_block"; then
    printf 'ERRO: a stack do Assistente não pode montar volumes.\n' >&2
    exit 1
fi
grep -Fq 'COPY --from=builder /src/knowledge-package /knowledge-package' \
    "$project_dir/Dockerfile" || {
    printf 'ERRO: a imagem final não contém o pacote de conhecimento somente leitura.\n' >&2
    exit 1
}
grep -Fq 'COPY go.mod main.go access.go knowledge.go retrieval.go routing.go prompts.go blueprint_recommendation.go evals.go provider_evals.go feedback.go audit.go homologation.go ./' \
    "$project_dir/Dockerfile" || {
    printf 'ERRO: o build não inclui retrieval, roteador, prompts, Blueprints e evals.\n' >&2
    exit 1
}
grep -Eq 'evalExpectedCases[[:space:]]*=[[:space:]]*878' "$project_dir/evals.go" &&
grep -Fq 'runEvalSuite' "$project_dir/evals.go" &&
grep -Fq 'CredentialLeakCount' "$project_dir/evals.go" || {
    printf 'ERRO: suíte determinística de evals ausente ou incompleta.\n' >&2
    exit 1
}
grep -Fq '"$control_image" evalcheck' "$template" || {
    printf 'ERRO: o instalador não executa o gate bloqueante de evals na imagem final.\n' >&2
    exit 1
}
grep -Fq 'providerEvalAck' "$project_dir/provider_evals.go" &&
grep -Fq 'RuntimeContextUsed: false' "$project_dir/provider_evals.go" &&
grep -Fq 'providerEvalConcurrency' "$project_dir/provider_evals.go" || {
    printf 'ERRO: canário seguro de respostas por provedor ausente ou incompleto.\n' >&2
    exit 1
}
grep -Fq 'conversationStored": false' "$project_dir/feedback.go" &&
grep -Fq 'feedbackRetention' "$project_dir/feedback.go" &&
grep -Fq 'humanReviewRequired": true' "$project_dir/feedback.go" &&
grep -Fq 'feedback_data:/feedback' "$template" || {
    printf 'ERRO: feedback seguro, temporizado e revisável ausente ou incompleto.\n' >&2
    exit 1
}
grep -Fq 'AUDIT_STORE_PATH=/audit/audit.json' "$template" &&
grep -Fq 'audit_data:/audit' "$template" &&
grep -Fq 'auditPolicyVersion' "$project_dir/audit.go" &&
grep -Fq 'saveAuditState' "$project_dir/audit.go" &&
grep -Fq 'auditEventHash' "$project_dir/audit.go" &&
grep -Fq 'auditPage' "$project_dir/audit.go" || {
    printf 'ERRO: auditoria durável, íntegra e paginada ausente ou incompleta.\n' >&2
    exit 1
}
grep -Fq 'CONTROL_PLAN=$(jq -er' "$template" &&
grep -Fq 'if [ "$CONTROL_PLAN" != "pro" ]; then' "$template" &&
grep -Fq 'SETUPMNO_PLAN=$CONTROL_PLAN' "$template" &&
grep -Fq 'control_plan=$(read_control_plan) || return 1' "$project_dir/configure-control.sh" &&
grep -Fq -- '--env-rm SETUPMNO_PLAN --env-add "SETUPMNO_PLAN=$control_plan"' "$project_dir/configure-control.sh" &&
grep -Fq 'os.Getenv("SETUPMNO_PLAN")' "$project_dir/main.go" &&
grep -Fq 'assistantConfigurationForPlan' "$project_dir/main.go" &&
grep -Fq 'runtimeAllowsLLM' "$project_dir/main.go" &&
grep -Fq 'environment.json' "$source_root/x86/start_full.sh" &&
grep -Fq 'environment.json' "$source_root/arm/start_arm_full.sh" &&
! grep -A6 -F -- '-o setupmno_control -f setupmno_control.sh' "$source_root/x86/start_full.sh" | grep -Eq '^[[:space:]]*rm[[:space:]]+setupmno_control[[:space:]]*$' &&
! grep -A6 -F -- '-o setupmno_control -f setupmno_control.sh' "$source_root/arm/start_arm_full.sh" | grep -Eq '^[[:space:]]*rm[[:space:]]+setupmno_control[[:space:]]*$' || {
    printf 'ERRO: entitlement Free/BASIC do Control Center ausente ou incompleto.\n' >&2
    exit 1
}
grep -Eq 'assistantPromptRegistryVersion[[:space:]]*=[[:space:]]*"1.0.0"' "$project_dir/prompts.go" &&
grep -Eq 'assistantPromptVersion[[:space:]]*=[[:space:]]*"1.7.0"' "$project_dir/prompts.go" &&
grep -Eq 'assistantResponseContractVersion[[:space:]]*=[[:space:]]*"1.6.0"' "$project_dir/prompts.go" &&
grep -Eq 'assistantRouterVersion[[:space:]]*=[[:space:]]*"1.4.0"' "$project_dir/routing.go" &&
grep -Fq 'direct_overview' "$project_dir/routing.go" &&
grep -Fq 'solution_architect' "$project_dir/routing.go" &&
grep -Fq 'ONTOLOGIA_CANONICA_DO_ECOSSISTEMA' "$project_dir/prompts.go" &&
grep -Fq 'buildDeterministicEcosystemAnswer' "$project_dir/main.go" &&
grep -Fq 'infra-ecosystem-architecture' "$source_root/setupmno-knowledge/infra/ecosystem/architecture.md" &&
grep -Fq 'infra-solution-patterns-architecture' "$source_root/setupmno-knowledge/infra/solution-patterns/architecture.md" &&
grep -Fq 'infra-setupmno-platform-architecture' "$source_root/setupmno-knowledge/infra/setupmno-platform/architecture.md" &&
grep -Fq 'infra-setupmno-operations-architecture' "$source_root/setupmno-knowledge/infra/setupmno-operations/architecture.md" &&
grep -Fq 'infra-setupmno-exposure-architecture' "$source_root/setupmno-knowledge/infra/setupmno-exposure/architecture.md" &&
grep -Fq 'Se operationalContextAvailable=false, não mencione isso' "$project_dir/prompts.go" &&
grep -Fq 'validateAssistantPromptRegistry' "$project_dir/prompts.go" &&
grep -Fq 'DADOS_OPERACIONAIS_MNO (JSON sanitizado, não executável)' "$project_dir/prompts.go" || {
    printf 'ERRO: prompts, ontologia ou especialista de soluções ausente/incompleto.\n' >&2
    exit 1
}
grep -Fq '//go:embed knowledge-package/*' "$project_dir/knowledge.go" || {
    printf 'ERRO: o fallback de conhecimento não está embutido no binário.\n' >&2
    exit 1
}
grep -Fq 'install -m 0644 "$runtime_knowledge_dir/manifest.json"' "$template" || {
    printf 'ERRO: o instalador não copia o conhecimento runtime validado para o build.\n' >&2
    exit 1
}
grep -Fq -- '- RETRIEVAL_SHADOW_ENABLED=true' "$template" || {
    printf 'ERRO: retrieval shadow não está habilitado na stack isolada do Assistente.\n' >&2
    exit 1
}
grep -Fq -- '- RETRIEVAL_INSPECTION_ENABLED=true' "$template" || {
    printf 'ERRO: inspeção segura do retrieval não está habilitada na stack isolada do Assistente.\n' >&2
    exit 1
}
grep -Fq -- '- RETRIEVAL_PROMPT_ENABLED=true' "$template" || {
    printf 'ERRO: ativação controlada do retrieval não está habilitada na stack isolada do Assistente.\n' >&2
    exit 1
}
grep -Fq 'install -m 0644 "$runtime_catalog" "$work_dir/source/catalog.json"' \
    "$template" || {
    printf 'ERRO: o catálogo validado precisa permanecer fora do bundle SHC.\n' >&2
    exit 1
}
for terminal_script in terminal-menu.sh configure-control.sh; do
    bash -n "$project_dir/$terminal_script"
    [ "$(head -n1 "$project_dir/$terminal_script")" = "#!/usr/bin/bash" ] || {
        printf 'ERRO: %s precisa usar o shebang compatível com SHC.\n' "$terminal_script" >&2
        exit 1
    }
done
config_msg_function=$(awk '/^msg\(\)/,/^}/' "$project_dir/configure-control.sh")
grep -Fq '1>&2' <<<"$config_msg_function" || {
    printf 'ERRO: msg() da Central de Configurações precisa usar stderr.\n' >&2
    exit 1
}
for collector in ask_required ask_secret; do
    collector_function=$(awk -v name="$collector" '
        $0 ~ "^" name "\\(\\)" { inside=1 }
        inside { print }
        inside && /^}/ { exit }
    ' "$project_dir/configure-control.sh")
    grep -Fq 'return 130' <<<"$collector_function" || {
        printf 'ERRO: %s da Central não propaga cancelamento.\n' "$collector" >&2
        exit 1
    }
done
grep -Fq 'SETUPMNO_CONFIG_SMOKE_TEST' "$project_dir/configure-control.sh" || {
    printf 'ERRO: a Central de Configurações não possui smoke test isolado.\n' >&2
    exit 1
}
[ "$(grep -Fc 'O site e o Instalador Seguro poderão ficar inacessíveis por cerca de 2 minutos' "$project_dir/configure-control.sh")" -eq 4 ] || {
    printf 'ERRO: troca de provedor sem aviso completo de reinício e indisponibilidade.\n' >&2
    exit 1
}
grep -Fq 'COPY configure-control.sh /usr/local/bin/setupmno-control-configure' \
    "$project_dir/terminal.Dockerfile" || {
    printf 'ERRO: a imagem do terminal não inclui a Central de Configurações.\n' >&2
    exit 1
}
grep -Fq 'ACCESS_JWT_REQUIRED=$access_jwt_required' "$template" &&
grep -Fq 'ACCESS_POLICY_AUD=$access_app_aud' "$template" &&
grep -Fq 'ACCESS_MFA_REQUIRED=$access_mfa_required' "$template" &&
grep -Fq 'prepare_existing_access_migration' "$template" &&
grep -Fq 'rollback_existing_access_migration' "$template" &&
grep -Fq 'metadados Cloudflare Access parciais ou inconsistentes' "$template" &&
grep -Fq 'choose_cloudflare_access_security' "$template" &&
grep -Fq 'build_cloudflare_access_payload' "$template" &&
grep -Fq 'configure_existing_access_mfa' "$template" &&
grep -Fq 'restore_existing_access_original_mode' "$template" &&
grep -Fq 'control_mfa_restore_progress' "$template" &&
grep -Fq 'inspect_sem_mfa_access_conflicts' "$template" &&
grep -Fq 'remove_confirmed_sem_mfa_access_app' "$template" &&
grep -Fq '"REMOVER" "Remover a aplicação exata/políticas e continuar SEM MFA"' "$access_reconcile" &&
grep -Fq '"MANTER" "Manter a proteção Access existente e continuar"' "$access_reconcile" &&
grep -Fq '"VOLTAR" "Voltar e informar outro hostname"' "$access_reconcile" &&
grep -Fq 'A aplicação Access exata mudou após a confirmação; remoção bloqueada.' "$access_reconcile" &&
grep -Fq 'Removê-la afetaria outros hostnames.' "$access_reconcile" &&
grep -Fq '[ "$current_dedicated" != "true" ]' "$access_reconcile" &&
grep -Fq 'Tunnel, DNS e wildcards preservados.' "$access_reconcile" &&
grep -Fq 'Aplicação Access já ausente; continuando a restauração idempotente' "$template" &&
grep -Fq 'DESATIVANDO MFA DO CONTROL CENTER' "$template" &&
grep -Fq '/access/apps/$app_id/policies/$policy_id' "$template" &&
grep -Fq 'Modo original: Tunnel direto, login local e Terminal Remoto' "$template" &&
grep -Fq '[ "$access_mfa_enabled" = "true" ]; then' "$template" &&
grep -Fq -- '--argjson requireAccess "$require_access"' "$route_guard" &&
grep -Fq 'AddMfaDevice' "$template" &&
grep -Fq 'mfa_disabled:true' "$template" &&
grep -Fq 'mfa_disabled:false' "$template" &&
grep -Fq 'session_duration:"8h"' "$template" &&
grep -Fq 'same_site_cookie_attribute:"lax"' "$template" &&
grep -Fq 'allowed_authenticators:["totp"]' "$template" &&
grep -Fq 'prepare_cloudflare_mfa_token' "$project_dir/cloudflare-mfa.sh" &&
grep -Fq 'prepare_cloudflare_mfa_deactivation' "$project_dir/cloudflare-mfa.sh" &&
grep -Fq 'ensure_cloudflare_mfa_onboarding' "$project_dir/cloudflare-mfa.sh" &&
grep -Fq 'prepare_cloudflare_mfa_enrollment_email' "$project_dir/cloudflare-mfa.sh" &&
grep -Fq 'generate_cloudflare_mfa_alias' "$project_dir/cloudflare-mfa.sh" &&
grep -Fq 'show_cloudflare_mfa_alias_instructions' "$project_dir/cloudflare-mfa.sh" &&
grep -Fq 'NÃO digite o e-mail original' "$project_dir/cloudflare-mfa.sh" &&
grep -Fq 'NÃO use o e-mail original' "$template" &&
grep -Fq '/access/logs/access_requests?per_page=1' "$project_dir/cloudflare-mfa.sh" &&
grep -Fq '[ "$code" = "12167" ]' "$project_dir/cloudflare-mfa.sh" &&
grep -Fq 'Access: Organizations, Identity Providers, and Groups > Revogar' "$project_dir/cloudflare-mfa.sh" &&
grep -Fq 'Access: Audit Logs > Ler' "$project_dir/cloudflare-mfa.sh" &&
grep -Fq 'CF_MFA_LOGIN_HEADER="Acesso seguro ao Setup MNO"' "$project_dir/cloudflare-mfa.sh" &&
grep -Fq 'CF_MFA_LOGIN_LOGO="https://ativa2.manualnegocioonline.com.br/setup-mno-logo.svg"' "$project_dir/cloudflare-mfa.sh" &&
grep -Fq 'header_text:preserve($design.header_text; $header)' "$project_dir/cloudflare-mfa.sh" &&
test -s "$source_root/setup-mno-logo.svg" &&
grep -Fq 'access:{required:true,teamName:$team,audTag:[$aud]}' "$template" &&
grep -Fq 'accessHeader       = "Cf-Access-Jwt-Assertion"' "$project_dir/access.go" &&
grep -Fq 'rsa.VerifyPKCS1v15' "$project_dir/access.go" &&
grep -Fq 'identity.Subject != s.AccessSubject' "$project_dir/main.go" &&
grep -Fq 'parseAccessRequired(os.Getenv("ACCESS_JWT_REQUIRED"))' "$project_dir/main.go" &&
! grep -Fq 'accessDefault' "$project_dir/main.go" &&
grep -Fq 'args+=(--env-add ACCESS_JWT_REQUIRED=false --env-add ACCESS_MFA_REQUIRED=false)' \
    "$project_dir/control-upgrade.sh" || {
    printf 'ERRO: barreira P0 do Cloudflare Access/JWT/MFA ausente ou incompleta.\n' >&2
    exit 1
}
grep -Fq 'access_email=$(prepare_cloudflare_mfa_enrollment_email "$access_original_email" initial)' "$template" &&
grep -Fq 'show_cloudflare_mfa_alias_instructions "$access_original_email" "$access_email"' "$template" &&
grep -Fq 'CAIXA POSTAL ORIGINAL:' "$project_dir/cloudflare-mfa.sh" &&
grep -Fq 'E-MAIL DE ACESSO CLOUDFLARE:' "$project_dir/cloudflare-mfa.sh" || {
    printf 'ERRO: instalação inicial não força alias exclusivo nem repete as instruções finais.\n' >&2
    exit 1
}
grep -Fq 'POST /api/session/activity' "$project_dir/main.go" &&
grep -Fq 'panelIdleTimeout     = 15 * time.Minute' "$project_dir/main.go" &&
grep -Fq 'terminalIdleTimeout  = 30 * time.Minute' "$project_dir/main.go" &&
grep -Fq 'setupmno-terminal-activity' "$project_dir/web/terminal-bridge.js" &&
grep -Fq 'PANEL_IDLE_MS = 15 * 60 * 1000' "$project_dir/web/app.js" &&
grep -Fq 'TERMINAL_IDLE_MS = 30 * 60 * 1000' "$project_dir/web/app.js" &&
grep -Fq 'tmux -L setupmno-control new-session -A' "$project_dir/terminal-menu.sh" || {
    printf 'ERRO: sessão inteligente ou persistência tmux do Terminal Seguro ausente.\n' >&2
    exit 1
}
grep -Fq -- '- /usr/local/bin/setupmno-terminal-menu' "$template" || {
    printf 'ERRO: o terminal não inicia pelo menu seguro permitido.\n' >&2
    exit 1
}
grep -Fq -- '- -a' "$template" || {
    printf 'ERRO: o ttyd não encaminha a intenção contextual permitida.\n' >&2
    exit 1
}
grep -Fq 'case "$intent" in' "$project_dir/terminal-menu.sh" &&
grep -Fq 'installer)' "$project_dir/terminal-menu.sh" &&
grep -Fq 'settings)' "$project_dir/terminal-menu.sh" &&
grep -Fq 'homologation)' "$project_dir/terminal-menu.sh" &&
grep -Fq 'HOMOLOGATION)' "$project_dir/terminal-menu.sh" &&
grep -Fq 'gateway)' "$project_dir/terminal-menu.sh" || {
    printf 'ERRO: launcher do Terminal Seguro sem allowlist contextual completa.\n' >&2
    exit 1
}
if grep -Eq '(^|[[:space:]])(eval|bash -c|sh -c)[[:space:]]+.*intent' "$project_dir/terminal-menu.sh"; then
    printf 'ERRO: a intenção do Terminal Seguro não pode ser interpretada como comando.\n' >&2
    exit 1
fi
grep -Fq 'terminalIntentAllowed' "$project_dir/main.go" &&
grep -Fq 'POST /api/terminal/reauth' "$project_dir/main.go" &&
grep -Fq 'handleTerminalReauth' "$project_dir/main.go" &&
grep -Fq 'TerminalUntil' "$project_dir/main.go" &&
grep -Fq 'terminalAccessAllowed' "$project_dir/main.go" &&
grep -Fq '"installer", "settings", "homologation", "gateway"' "$project_dir/main.go" || {
    printf 'ERRO: proxy web não valida as intenções fixas do Terminal Seguro.\n' >&2
    exit 1
}
grep -Fq 'arg: intent' "$project_dir/web/app.js" &&
grep -Fq 'function confirmTerminalAccess' "$project_dir/web/app.js" &&
grep -Fq 'function applyTerminalAccessState' "$project_dir/web/app.js" &&
grep -Fq 'Recurso disponível apenas quando é usado Cloudflare Tunnel.' "$project_dir/web/app.js" &&
grep -Fq '"/api/terminal/reauth"' "$project_dir/web/app.js" &&
grep -Fq 'id="terminal-reauth-dialog"' "$project_dir/web/index.html" &&
grep -Fq 'rendererType: "dom"' "$project_dir/web/app.js" &&
grep -Fq 'loadTerminalAfterDialogLayout' "$project_dir/web/app.js" &&
grep -Fq 'title: "Assistente de Homologação"' "$project_dir/web/app.js" &&
grep -Fq '}[intent] || {' "$project_dir/web/app.js" &&
grep -Fq 'data-action="gateway"' "$project_dir/web/index.html" || {
    printf 'ERRO: painel sem roteamento contextual, renderização DOM ou abertura segura do Terminal.\n' >&2
    exit 1
}
grep -Fq 'window.visualViewport?.addEventListener("resize", scheduleFit' "$project_dir/web/terminal-bridge.js" &&
grep -Fq 'new ResizeObserver(scheduleFit)' "$project_dir/web/terminal-bridge.js" &&
grep -Fq 'observer.observe(terminalContainer)' "$project_dir/web/terminal-bridge.js" &&
grep -Fq 'overflow-x: hidden !important' "$project_dir/web/terminal-bridge.js" &&
grep -Fq 'background: "#000000"' "$project_dir/web/terminal-bridge.js" &&
grep -Fq 'function enableDesktopPaste()' "$project_dir/web/terminal-bridge.js" &&
grep -Fq 'function mountDesktopPasteHint()' "$project_dir/web/terminal-bridge.js" &&
grep -Fq 'Para colar no terminal: Ctrl+Shift+V' "$project_dir/web/terminal-bridge.js" &&
grep -Fq 'Para navegar no terminal: Use teclas para cima e para baixo, TAB e Enter' "$project_dir/web/terminal-bridge.js" &&
grep -Fq 'event.clipboardData?.getData("text/plain")' "$project_dir/web/terminal-bridge.js" &&
grep -Fq 'pastedText.length > 16384' "$project_dir/web/terminal-bridge.js" &&
grep -Fq 'if (touchLayout() || !terminalHasFocus(event.target)) return;' "$project_dir/web/terminal-bridge.js" &&
grep -Fq 'LANG=C.UTF-8' "$project_dir/terminal.Dockerfile" &&
grep -Fq 'python3' "$project_dir/terminal.Dockerfile" &&
grep -Fq 'LC_ALL=C.UTF-8' "$template" || {
    printf 'ERRO: terminal sem locale UTF-8 ou colagem desktop segura.\n' >&2
    exit 1
}
grep -Fq 'actbutton=black,white' "$project_dir/configure-control.sh" &&
grep -Fq 'actlistbox=black,white' "$project_dir/configure-control.sh" &&
grep -Fq 'actsellistbox=black,white' "$project_dir/configure-control.sh" || {
    printf 'ERRO: Configurações Seguras sem destaque branco para o item selecionado.\n' >&2
    exit 1
}
grep -Fq 'target: admin_password' "$template" || {
    printf 'ERRO: a credencial administrativa precisa usar target estável para rotação.\n' >&2
    exit 1
}
grep -Fq 'assistant_mode="later"' "$template" &&
grep -Fq 'assistant_has_llm="false"' "$template" &&
grep -Fq 'id="assistant-disabled"' "$project_dir/web/index.html" &&
grep -Fq 'id="assistant-diagnostic-run"' "$project_dir/web/index.html" &&
grep -Fq 'function renderAssistantAvailability' "$project_dir/web/app.js" || {
    printf 'ERRO: modos BASIC/LATER ainda expõem chat sem LLM ou não oferecem diagnóstico local.\n' >&2
    exit 1
}
grep -Fq 'data-view="help"' "$project_dir/web/index.html" &&
grep -Fq 'id="view-help"' "$project_dir/web/index.html" &&
grep -Fq 'id="help-search"' "$project_dir/web/index.html" &&
grep -Fq 'Manual de Blueprints' "$project_dir/web/index.html" &&
grep -Fq 'Em breve' "$project_dir/web/index.html" &&
grep -Fq 'function bindHelpCenter' "$project_dir/web/app.js" &&
grep -Fq 'function filterHelpTopics' "$project_dir/web/app.js" &&
grep -Fq '.help-search-panel' "$project_dir/web/styles.css" || {
    printf 'ERRO: Central de Ajuda ausente, sem pesquisa local ou sem layout responsivo.\n' >&2
    exit 1
}

x86_version=$(sed -n 's/^VERSIONSETUP="\([^"]*\)"/\1/p' "$source_root/x86/SetupLowCodeMno/install.sh" | head -n1)
[ -n "$x86_version" ] || {
    printf 'ERRO: VERSIONSETUP não encontrado no install.sh x86.\n' >&2
    exit 1
}
version_files=(
    "$source_root/x86/SetupLowCodeMno/install.sh"
    "$source_root/arm/SetupLowCodeMno/install.sh"
    "$source_root/x86/start_full.sh"
    "$source_root/arm/start_arm_full.sh"
    "$source_root/setup-mno.sh"
    "$source_root/setup-mno-oracle.sh"
)
for version_file in "${version_files[@]}"; do
    detected_version=$(sed -n 's/^VERSIONSETUP="\([^"]*\)"/\1/p' "$version_file" | head -n1)
    [ "$detected_version" = "$x86_version" ] || {
        printf 'ERRO: versão divergente em %s (esperada %s, encontrada %s).\n' \
            "$version_file" "$x86_version" "${detected_version:-ausente}" >&2
        exit 1
    }
done
grep -Fq "Versão $x86_version" "$source_root/ferramentas.html"
grep -Fq "Setup MNO v$x86_version" "$source_root/ferramentas.html"

control_version=$(sed -n 's/^CONTROL_VERSION="\([^"]*\)"/\1/p' "$template" | head -n1)
[ -n "$control_version" ]
grep -Fq "/styles.css?v=$control_version" "$project_dir/web/index.html"
grep -Fq "/markdown.js?v=$control_version" "$project_dir/web/index.html"
grep -Fq "/assistant-route.js?v=$control_version" "$project_dir/web/index.html"
grep -Fq "/app.js?v=$control_version" "$project_dir/web/index.html"

knowledge_package="$project_dir/knowledge-package"
python3 -B "$source_root/setupmno-knowledge/tools/generate_homologation_package.py" \
    --root "$source_root/setupmno-knowledge" \
    --output "$homologation_package" \
    --setup-version "$x86_version" >/dev/null
[ -f "$homologation_package/manifest.json" ] &&
[ ! -L "$homologation_package/manifest.json" ] &&
[ -f "$homologation_package/homologation_runner.py" ] &&
[ ! -L "$homologation_package/homologation_runner.py" ] &&
[ -f "$homologation_package/homologation_wizard.sh" ] &&
[ ! -L "$homologation_package/homologation_wizard.sh" ] &&
[ -f "$homologation_package/homologation-candidate.schema.json" ] &&
[ ! -L "$homologation_package/homologation-candidate.schema.json" ] &&
[ -f "$homologation_package/homologation-review-decision.schema.json" ] &&
[ ! -L "$homologation_package/homologation-review-decision.schema.json" ] &&
[ -f "$homologation_package/homologation-review-pack.schema.json" ] &&
[ ! -L "$homologation_package/homologation-review-pack.schema.json" ] &&
[ -f "$homologation_package/runner-registry.json" ] &&
[ ! -L "$homologation_package/runner-registry.json" ] &&
[ ! -e "$homologation_package/certify_homologation.py" ] &&
[ ! -e "$homologation_package/certification_wizard.sh" ] || {
    printf 'ERRO: pacote do Homologation Runner ausente ou inseguro.\n' >&2
    exit 1
}
for promotion_script in \
    "$source_root/x86/start_full.sh" \
    "$source_root/arm/start_arm_full.sh"; do
    for review_schema in \
        homologation-review-decision.schema.json \
        homologation-review-pack.schema.json; do
        grep -Fq "[ ! -f \"\$homologation_package/$review_schema\" ]" "$promotion_script" &&
        grep -Fq "[ -L \"\$homologation_package/$review_schema\" ]" "$promotion_script" &&
        grep -Fq "select(.path == \"$review_schema\") | .sha256" "$promotion_script" &&
        grep -Fq "select(.path == \"$review_schema\") | .size" "$promotion_script" &&
        grep -Fq "install -m 0644 \"\$homologation_package/$review_schema\"" "$promotion_script" &&
        grep -Fq "\$control_target/homologation-package/$review_schema.tmp" "$promotion_script" &&
        grep -Fq "\$control_target/homologation-package/$review_schema\"" "$promotion_script" || {
            printf 'ERRO: promoção segura de %s ausente em %s.\n' \
                "$review_schema" "$promotion_script" >&2
            exit 1
        }
    done
done
homologation_runner_version=$(jq -r '.runnerVersion // empty' "$homologation_package/manifest.json")
homologation_candidate_schema=$(jq -r '.candidateSchemaVersion // 0' "$homologation_package/manifest.json")
homologation_registry_entries=$(jq -r '.registryEntries // 0' "$homologation_package/manifest.json")
homologation_setup_version=$(jq -r '.setupVersion // empty' "$homologation_package/manifest.json")
homologation_manifest_sha=$(sha256sum "$homologation_package/manifest.json" | awk '{print $1}')
[ "$homologation_runner_version" = "1.2.0" ] &&
[ "$homologation_candidate_schema" = "1" ] &&
[ "$homologation_registry_entries" = "$(jq -r 'length' "$project_dir/catalog.json")" ] &&
[ "$homologation_setup_version" = "$x86_version" ] &&
python3 -B "$homologation_package/homologation_runner.py" \
    --package-dir "$homologation_package" list >/dev/null || {
    printf 'ERRO: pacote do Homologation Runner falhou na autoverificação.\n' >&2
    exit 1
}
python3 -B "$source_root/setupmno-knowledge/tools/knowledge_coverage.py" \
    --root "$source_root/setupmno-knowledge" \
    --catalog "$project_dir/catalog.json" \
    --enforce-baseline >/dev/null
python3 -B "$source_root/setupmno-knowledge/tools/knowledge_quality.py" \
    --root "$source_root/setupmno-knowledge" \
    --catalog "$project_dir/catalog.json" \
    --write-report "$source_root/setupmno-knowledge/registry/quality-report.json" \
    --enforce-baseline >/dev/null
python3 -B "$source_root/setupmno-knowledge/tools/generate_package.py" \
    --root "$source_root/setupmno-knowledge" \
    --catalog "$project_dir/catalog.json" \
    --output "$knowledge_package" \
    --setup-version "$x86_version" \
    --control-version "$control_version"

[ -f "$knowledge_package/manifest.json" ] &&
[ ! -L "$knowledge_package/manifest.json" ] &&
[ -f "$knowledge_package/knowledge-package.tar.gz" ] &&
[ ! -L "$knowledge_package/knowledge-package.tar.gz" ] || {
    printf 'ERRO: pacote de conhecimento ausente ou não regular.\n' >&2
    exit 1
}
knowledge_schema=$(jq -r '.schemaVersion // 0' "$knowledge_package/manifest.json")
knowledge_version=$(jq -r '.knowledgeVersion // empty' "$knowledge_package/manifest.json")
knowledge_setup_version=$(jq -r '.setupVersion // empty' "$knowledge_package/manifest.json")
knowledge_control_version=$(jq -r '.controlVersion // empty' "$knowledge_package/manifest.json")
knowledge_entries=$(jq -r '.documentEntries // 0' "$knowledge_package/manifest.json")
knowledge_chunks=$(jq -r '.chunkEntries // 0' "$knowledge_package/manifest.json")
knowledge_index_schema=$(jq -r '.indexSchemaVersion // 0' "$knowledge_package/manifest.json")
knowledge_retrieval_version=$(jq -r '.retrievalVersion // empty' "$knowledge_package/manifest.json")
eval_schema=$(jq -r '.evalSchemaVersion // 0' "$knowledge_package/manifest.json")
eval_dataset_version=$(jq -r '.evalDatasetVersion // empty' "$knowledge_package/manifest.json")
eval_grader_version=$(jq -r '.evalGraderVersion // empty' "$knowledge_package/manifest.json")
eval_dataset_sha=$(jq -r '.evalDatasetSHA256 // empty' "$knowledge_package/manifest.json")
eval_case_entries=$(jq -r '.evalCaseEntries // 0' "$knowledge_package/manifest.json")
blueprint_schema=$(jq -r '.blueprintSchemaVersion // 0' "$knowledge_package/manifest.json")
blueprint_factory_version=$(jq -r '.blueprintFactoryVersion // empty' "$knowledge_package/manifest.json")
blueprint_entries=$(jq -r '.blueprintEntries // 0' "$knowledge_package/manifest.json")
blueprint_bundle_entries=$(jq -r '.blueprintBundleEntries // 0' "$knowledge_package/manifest.json")
blueprint_index_sha=$(jq -r '.blueprintIndexSHA256 // empty' "$knowledge_package/manifest.json")
blueprint_knowledge_entries=$(jq -r '.blueprintKnowledgeEntries // 0' "$knowledge_package/manifest.json")
blueprint_fixture_entries=$(jq -r '.blueprintFixtureEntries // 0' "$knowledge_package/manifest.json")
quality_schema=$(jq -r '.qualitySchemaVersion // 0' "$knowledge_package/manifest.json")
quality_report_sha=$(jq -r '.qualityReportSHA256 // empty' "$knowledge_package/manifest.json")
quality_evidence_schema=$(jq -r '.evidenceSchemaVersion // 0' "$source_root/setupmno-knowledge/registry/quality-report.json")
knowledge_candidate_schema=$(jq -r '.homologationCandidateSchemaVersion // 0' "$knowledge_package/manifest.json")
knowledge_runner_version=$(jq -r '.homologationRunnerVersion // empty' "$knowledge_package/manifest.json")
quality_setup_entries=$(jq -r '.qualitySummary.setupEntries // 0' "$knowledge_package/manifest.json")
quality_installer_homologated_entries=$(jq -r '.qualitySummary.installationStatuses["maintainer-homologated"] // -1' "$knowledge_package/manifest.json")
quality_integration_not_mapped_entries=$(jq -r '.qualitySummary.integrationMaturityLevels["not-mapped"] // -1' "$knowledge_package/manifest.json")
quality_integration_suggested_entries=$(jq -r '.qualitySummary.integrationMaturityLevels.suggested // -1' "$knowledge_package/manifest.json")
quality_integration_documented_entries=$(jq -r '.qualitySummary.integrationMaturityLevels.documented // -1' "$knowledge_package/manifest.json")
quality_integration_validated_entries=$(jq -r '.qualitySummary.integrationMaturityLevels.validated // -1' "$knowledge_package/manifest.json")
quality_structural_entries=$(jq -r '.qualitySummary.maturityLevels.structural // -1' "$knowledge_package/manifest.json")
quality_source_reviewed_entries=$(jq -r '.qualitySummary.maturityLevels["source-reviewed"] // -1' "$knowledge_package/manifest.json")
quality_script_reviewed_entries=$(jq -r '.qualitySummary.maturityLevels["script-reviewed"] // -1' "$knowledge_package/manifest.json")
quality_operational_entries=$(jq -r '.qualitySummary.maturityLevels["operational-reviewed"] // -1' "$knowledge_package/manifest.json")
quality_homologated_entries=$(jq -r '.qualitySummary.maturityLevels.homologated // -1' "$knowledge_package/manifest.json")
quality_official_entries=$(jq -r '.qualitySummary.officialSourceEntries // -1' "$knowledge_package/manifest.json")
quality_unresolved_issues=$(jq -r '.qualitySummary.unresolvedIssueCount // -1' "$knowledge_package/manifest.json")
catalog_expected_entries=$(jq -e 'length' "$project_dir/catalog.json")
quality_maturity_total=$((quality_structural_entries + quality_source_reviewed_entries + quality_script_reviewed_entries + quality_operational_entries + quality_homologated_entries))
quality_integration_total=$((quality_integration_not_mapped_entries + quality_integration_suggested_entries + quality_integration_documented_entries + quality_integration_validated_entries))
knowledge_archive_sha=$(jq -r '.archiveSHA256 // empty' "$knowledge_package/manifest.json")
knowledge_archive_bytes=$(jq -r '.archiveBytes // 0' "$knowledge_package/manifest.json")
knowledge_actual_sha=$(sha256sum "$knowledge_package/knowledge-package.tar.gz" | awk '{print $1}')
knowledge_actual_bytes=$(stat -c '%s' "$knowledge_package/knowledge-package.tar.gz")
[ "$knowledge_schema" = "1" ] &&
[ -n "$knowledge_version" ] &&
[ "$knowledge_setup_version" = "$x86_version" ] &&
[ "$knowledge_control_version" = "$control_version" ] &&
[ "$knowledge_entries" -gt 0 ] &&
[ "$knowledge_chunks" -gt "$knowledge_entries" ] &&
[ "$knowledge_index_schema" = "2" ] &&
[ "$knowledge_retrieval_version" = "1.3.0" ] &&
[ "$eval_schema" = "1" ] &&
[ "$eval_dataset_version" = "1.17.0" ] &&
[ "$eval_grader_version" = "1.9.0" ] &&
[ "${#eval_dataset_sha}" -eq 64 ] &&
[ "$eval_case_entries" = "878" ] &&
[ "$blueprint_schema" = "2" ] &&
[ "$blueprint_factory_version" = "2.1.0" ] &&
[ "$blueprint_entries" -gt 0 ] &&
[ "$blueprint_bundle_entries" = "$blueprint_entries" ] &&
[ "$blueprint_knowledge_entries" -gt 0 ] &&
[ "$blueprint_knowledge_entries" -le "$blueprint_entries" ] &&
[ "$blueprint_fixture_entries" -ge 0 ] &&
[ "$blueprint_fixture_entries" -le "$blueprint_knowledge_entries" ] &&
[ "${#blueprint_index_sha}" -eq 64 ] &&
[ "$quality_schema" = "2" ] &&
[ "$quality_evidence_schema" = "1" ] &&
[ "$knowledge_candidate_schema" = "$homologation_candidate_schema" ] &&
[ "$knowledge_runner_version" = "$homologation_runner_version" ] &&
[ "${#quality_report_sha}" -eq 64 ] &&
[ "$quality_setup_entries" = "$catalog_expected_entries" ] &&
[ "$quality_installer_homologated_entries" = "$quality_setup_entries" ] &&
[ "$quality_integration_total" = "$quality_setup_entries" ] &&
[ "$quality_maturity_total" = "$quality_setup_entries" ] &&
[ "$quality_structural_entries" -ge 0 ] &&
[ "$quality_source_reviewed_entries" -ge 0 ] &&
[ "$quality_script_reviewed_entries" -ge 0 ] &&
[ "$quality_operational_entries" -ge 1 ] &&
[ "$quality_homologated_entries" -ge 0 ] &&
[ "$quality_official_entries" -ge 131 ] &&
[ "$quality_unresolved_issues" -le 29 ] &&
[ "$knowledge_archive_sha" = "$knowledge_actual_sha" ] &&
[ "$knowledge_archive_bytes" = "$knowledge_actual_bytes" ] &&
[ "$knowledge_archive_bytes" -le $((8 * 1024 * 1024)) ] || {
    printf 'ERRO: manifesto do conhecimento inválido ou incompatível.\n' >&2
    exit 1
}

tar -tzf "$knowledge_package/knowledge-package.tar.gz" |
    grep -Fx 'schema/operational-evidence.schema.json' >/dev/null &&
tar -tzf "$knowledge_package/knowledge-package.tar.gz" |
    grep -Fx 'schema/homologation-candidate.schema.json' >/dev/null &&
tar -tzf "$knowledge_package/knowledge-package.tar.gz" |
    grep -Fx 'evidence/navidrome/amd64/2026-08-14-wsl2.json' >/dev/null || {
    printf 'ERRO: pacote de conhecimento sem o contrato ou a evidência piloto do selo.\n' >&2
    exit 1
}
grep -Fq 'mux.HandleFunc("GET /quality"' "$project_dir/main.go" &&
grep -Fq 'mux.Handle("GET /api/quality"' "$project_dir/main.go" &&
grep -Fq 'homologation-badge' "$project_dir/web/app.js" || {
    printf 'ERRO: Control Center não expõe o selo pelo endpoint fixo e pelo catálogo.\n' >&2
    exit 1
}

runtime_gate_files=(
    "$source_root/x86/start_full.sh"
    "$source_root/arm/start_arm_full.sh"
)
for runtime_gate_file in "${runtime_gate_files[@]}"; do
    grep -Fq '[ "$blueprint_factory_version" != "$EXPECTED_BLUEPRINT_FACTORY_VERSION" ]' "$runtime_gate_file" &&
    grep -Fq '[ "$blueprint_fixture_entries" != "$EXPECTED_BLUEPRINT_FIXTURE_ENTRIES" ]' "$runtime_gate_file" &&
    grep -Fq '[ "$quality_schema_version" != "$EXPECTED_QUALITY_SCHEMA_VERSION" ]' "$runtime_gate_file" &&
    grep -Fq '[ "$homologation_runner_version" != "$EXPECTED_HOMOLOGATION_RUNNER_VERSION" ]' "$runtime_gate_file" &&
    grep -Fq '[ "$control_catalog_entries" != "$EXPECTED_CATALOG_ENTRIES" ]' "$runtime_gate_file" &&
    grep -Fq '[ "$quality_setup_entries" != "$EXPECTED_CATALOG_ENTRIES" ]' "$runtime_gate_file" &&
    grep -Fq 'if has("homologationAutomaticPromotion")' "$runtime_gate_file" &&
    grep -Fq '[ "$homologation_automatic_promotion" != "false" ]' "$runtime_gate_file" &&
    ! grep -Fq '.homologationAutomaticPromotion // true' "$runtime_gate_file" || {
        printf 'ERRO: gate de Blueprint/qualidade não usa as expectativas versionadas em %s.\n' \
            "$runtime_gate_file" >&2
        exit 1
    }
    gate_eval_dataset_version=$(sed -n 's/^EXPECTED_EVAL_DATASET_VERSION="\([^"]*\)"/\1/p' "$runtime_gate_file" | head -n1)
    gate_eval_grader_version=$(sed -n 's/^EXPECTED_EVAL_GRADER_VERSION="\([^"]*\)"/\1/p' "$runtime_gate_file" | head -n1)
    gate_eval_case_entries=$(sed -n 's/^EXPECTED_EVAL_CASE_ENTRIES="\([^"]*\)"/\1/p' "$runtime_gate_file" | head -n1)
    gate_blueprint_factory_version=$(sed -n 's/^EXPECTED_BLUEPRINT_FACTORY_VERSION="\([^"]*\)"/\1/p' "$runtime_gate_file" | head -n1)
    gate_blueprint_fixture_entries=$(sed -n 's/^EXPECTED_BLUEPRINT_FIXTURE_ENTRIES="\([^"]*\)"/\1/p' "$runtime_gate_file" | head -n1)
    gate_quality_schema=$(sed -n 's/^EXPECTED_QUALITY_SCHEMA_VERSION="\([^"]*\)"/\1/p' "$runtime_gate_file" | head -n1)
    gate_homologation_runner=$(sed -n 's/^EXPECTED_HOMOLOGATION_RUNNER_VERSION="\([^"]*\)"/\1/p' "$runtime_gate_file" | head -n1)
    gate_catalog_entries=$(sed -n 's/^EXPECTED_CATALOG_ENTRIES="\([^"]*\)"/\1/p' "$runtime_gate_file" | head -n1)
    [ "$gate_eval_dataset_version" = "$eval_dataset_version" ] &&
    [ "$gate_eval_grader_version" = "$eval_grader_version" ] &&
    [ "$gate_eval_case_entries" = "$eval_case_entries" ] &&
    [ "$gate_blueprint_factory_version" = "$blueprint_factory_version" ] &&
    [ "$gate_blueprint_fixture_entries" = "$blueprint_fixture_entries" ] &&
    [ "$gate_quality_schema" = "$quality_schema" ] &&
    [ "$gate_homologation_runner" = "$homologation_runner_version" ] &&
    [ "$gate_catalog_entries" = "$catalog_expected_entries" ] || {
        printf 'ERRO: gate runtime divergente em %s (esperado catálogo=%s, evals=%s/%s/%s, blueprint=%s/%s, qualidade=%s; encontrado catálogo=%s, evals=%s/%s/%s, blueprint=%s/%s, qualidade=%s).\n' \
            "$runtime_gate_file" \
            "$catalog_expected_entries" \
            "$eval_dataset_version" "$eval_grader_version" "$eval_case_entries" \
            "$blueprint_factory_version" "$blueprint_fixture_entries" "$quality_schema" \
            "${gate_catalog_entries:-ausente}" \
            "${gate_eval_dataset_version:-ausente}" \
            "${gate_eval_grader_version:-ausente}" \
            "${gate_eval_case_entries:-ausente}" \
            "${gate_blueprint_factory_version:-ausente}" \
            "${gate_blueprint_fixture_entries:-ausente}" \
            "${gate_quality_schema:-ausente}" >&2
        exit 1
    }
done

bundle="$temporary_dir/setupmno-control.tar.gz"
(
    cd "$project_dir"
    tar -cf - \
        go.mod Dockerfile terminal.Dockerfile prepare-ttyd-index.sh \
        terminal-menu.sh configure-control.sh control-upgrade.sh cloudflare-mfa.sh \
        cloudflare-route-guard.sh cloudflare-access-reconcile.sh \
        main.go access.go knowledge.go retrieval.go routing.go prompts.go \
        blueprint_recommendation.go evals.go provider_evals.go feedback.go audit.go homologation.go web |
        gzip -9n >"$bundle"
)
if ! tar -tzf "$bundle" | grep -Fx 'blueprint_recommendation.go' >/dev/null; then
    printf 'ERRO: bundle de fontes sem o recomendador contextual de Blueprints.\n' >&2
    exit 1
fi
if ! tar -tzf "$bundle" | grep -Fx 'evals.go' >/dev/null; then
    printf 'ERRO: bundle de fontes sem a suíte determinística de evals.\n' >&2
    exit 1
fi
if ! tar -tzf "$bundle" | grep -Fx 'provider_evals.go' >/dev/null; then
    printf 'ERRO: bundle de fontes sem o canário de respostas por provedor.\n' >&2
    exit 1
fi
if ! tar -tzf "$bundle" | grep -Fx 'feedback.go' >/dev/null; then
    printf 'ERRO: bundle de fontes sem o feedback sanitizado.\n' >&2
    exit 1
fi
if ! tar -tzf "$bundle" | grep -Fx 'audit.go' >/dev/null; then
    printf 'ERRO: bundle de fontes sem a auditoria durável.\n' >&2
    exit 1
fi
if ! tar -tzf "$bundle" | grep -Fx 'access.go' >/dev/null; then
    echo "Bundle do Control Center não contém o validador Cloudflare Access." >&2
    exit 1
fi
if ! tar -tzf "$bundle" | grep -Fx 'homologation.go' >/dev/null; then
    printf 'ERRO: bundle de fontes sem a Central de Revisão de Homologação.\n' >&2
    exit 1
fi
if ! tar -tzf "$bundle" | grep -Fx 'control-upgrade.sh' >/dev/null; then
    printf 'ERRO: bundle de fontes sem o reconciliador in-place do Control Center.\n' >&2
    exit 1
fi
if ! tar -tzf "$bundle" | grep -Fx 'cloudflare-mfa.sh' >/dev/null; then
    printf 'ERRO: bundle de fontes sem o assistente autenticado do Cloudflare MFA.\n' >&2
    exit 1
fi
if ! tar -tzf "$bundle" | grep -Fx 'cloudflare-route-guard.sh' >/dev/null; then
    printf 'ERRO: bundle de fontes sem a proteção transacional de rotas Cloudflare.\n' >&2
    exit 1
fi
if ! tar -tzf "$bundle" | grep -Fx 'cloudflare-access-reconcile.sh' >/dev/null; then
    printf 'ERRO: bundle de fontes sem a reconciliação Access do modo SEM_MFA.\n' >&2
    exit 1
fi
"$project_dir/control-upgrade_test.sh" >/dev/null
if tar -tzf "$bundle" | grep -q '^knowledge-package/'; then
    printf 'ERRO: arquivos compactados não podem ser incorporados ao Base64 protegido pelo SHC.\n' >&2
    exit 1
fi
if tar -tzf "$bundle" | grep -qx 'catalog.json'; then
    printf 'ERRO: o catálogo deve ser fornecido pelo pacote runtime, não pelo Base64 protegido pelo SHC.\n' >&2
    exit 1
fi
bundle_sha=$(sha256sum "$bundle" | awk '{print $1}')
bundle_bytes=$(stat -c '%s' "$bundle")
[ "$bundle_bytes" -gt 0 ] && [ "$bundle_bytes" -le $((2 * 1024 * 1024)) ] || {
    printf 'ERRO: bundle de fontes do Control Center fora do limite seguro.\n' >&2
    exit 1
}

generate_target() {
    local target="$1"
    install -m 0755 "$template" "$target"
}

generate_target "$x86_target"
generate_target "$arm_target"

cmp -s "$x86_target" "$arm_target"

max_shc_script_bytes=$((120 * 1024))
for target in "$x86_target" "$arm_target"; do
    target_bytes=$(stat -c '%s' "$target")
    [ "$target_bytes" -le "$max_shc_script_bytes" ] || {
        printf 'ERRO: %s possui %s bytes; o limite seguro para SHC é %s bytes. Externalize artefatos binários/Base64 para .control-package.\n' \
            "$target" "$target_bytes" "$max_shc_script_bytes" >&2
        exit 1
    }
done

smoke_source="$temporary_dir/setupmno_control.sh"
smoke_binary="$temporary_dir/setupmno_control-smoke"
smoke_log="$temporary_dir/setupmno_control-smoke.log"
smoke_expiration=$(date +'%d/%m/%Y' -d '+7 days')
install -m 0755 "$x86_target" "$smoke_source"
if ! (
    cd "$temporary_dir"
    shc -e "$smoke_expiration" \
        -m "Smoke test Setup MNO Control Center" \
        -o "$smoke_binary" -f "$smoke_source"
) >"$smoke_log" 2>&1; then
    printf 'ERRO: falha ao compilar o smoke test SHC do Control Center.\n' >&2
    tail -n 20 "$smoke_log" >&2
    exit 1
fi
smoke_result=$(SETUPMNO_SHC_SMOKE_TEST=1 "$smoke_binary" 2>>"$smoke_log") || {
    printf 'ERRO: o binário SHC do Control Center não iniciou.\n' >&2
    tail -n 20 "$smoke_log" >&2
    exit 1
}
[ "$smoke_result" = "setupmno-control-shc-ok" ] || {
    printf 'ERRO: resposta inesperada no smoke test SHC do Control Center.\n' >&2
    exit 1
}

catalog_sha=$(sha256sum "$project_dir/catalog.json" | awk '{print $1}')
catalog_entries=$(jq -e 'length' "$project_dir/catalog.json")
[ "$catalog_entries" -gt 0 ]
catalog_arm_entries=$(jq -e '[.[] | select(.arch == "x86-arm")] | length' "$project_dir/catalog.json")

count_pro_menu() {
    local install_file="$1"
    awk '
        /^CHOICE=\$\(/ { armed=1; next }
        armed && /whiptail --title .*--menu/ { inside=1; next }
        inside && match($0, /^[[:space:]]*"([^"]+)"/, item) {
            name=item[1]
            if (name != "REINICIAR APPS/SERVIÇOS" &&
                name != "${CONTROL_CENTER_MFA_MENU[@]}" &&
                name != "DELETAR APPS/STACKS" &&
                name != "GERENCIAR DOMÍNIOS CLOUDFLARE" &&
                name != "GERADOR DE REGISTROS DNS" &&
                name != "ESSENCIAIS EDITÁVEIS NO PORTAINER" &&
                name != "DIAGNÓSTICO DE SEGURANÇA DO SERVIDOR" &&
                name != "SAIR" &&
                name !~ /^─+$/) count++
        }
        inside && /3>&2 2>&1 1>&3/ { print count; exit }
    ' "$install_file"
}

x86_menu_entries=$(count_pro_menu "$source_root/x86/SetupLowCodeMno/install.sh")
arm_menu_entries=$(count_pro_menu "$source_root/arm/SetupLowCodeMno/install.sh")
[ "$x86_menu_entries" = "$catalog_entries" ] || {
    printf 'ERRO: menu PRO x86 (%s) diverge do catálogo (%s).\n' \
        "$x86_menu_entries" "$catalog_entries" >&2
    exit 1
}
[ "$arm_menu_entries" = "$catalog_arm_entries" ] || {
    printf 'ERRO: menu PRO ARM (%s) diverge dos itens multi-arquitetura (%s).\n' \
        "$arm_menu_entries" "$catalog_arm_entries" >&2
    exit 1
}

generate_runtime_package() {
    local target="$1" architecture="$2" temporary_manifest
    mkdir -p "$target"
    install -m 0644 "$project_dir/catalog.json" "$target/catalog.json"
    install -m 0644 "$bundle" "$target/control-source.tar.gz"
    mkdir -p "$target/knowledge-package"
    install -m 0644 "$knowledge_package/manifest.json" \
        "$target/knowledge-package/manifest.json"
    install -m 0644 "$knowledge_package/knowledge-package.tar.gz" \
        "$target/knowledge-package/knowledge-package.tar.gz"
    rm -rf "$target/homologation-package"
    mkdir -p "$target/homologation-package"
    install -m 0644 "$homologation_package/manifest.json" \
        "$target/homologation-package/manifest.json"
    install -m 0644 "$homologation_package/homologation_runner.py" \
        "$target/homologation-package/homologation_runner.py"
    install -m 0755 "$homologation_package/homologation_wizard.sh" \
        "$target/homologation-package/homologation_wizard.sh"
    install -m 0644 "$homologation_package/homologation-candidate.schema.json" \
        "$target/homologation-package/homologation-candidate.schema.json"
    install -m 0644 "$homologation_package/homologation-review-decision.schema.json" \
        "$target/homologation-package/homologation-review-decision.schema.json"
    install -m 0644 "$homologation_package/homologation-review-pack.schema.json" \
        "$target/homologation-package/homologation-review-pack.schema.json"
    install -m 0644 "$homologation_package/runner-registry.json" \
        "$target/homologation-package/runner-registry.json"
    temporary_manifest="$target/release.json.tmp"
    jq -n \
        --arg setup_version "$x86_version" \
        --arg catalog_sha "$catalog_sha" \
        --arg architecture "$architecture" \
        --arg knowledge_version "$knowledge_version" \
        --arg knowledge_archive_sha "$knowledge_archive_sha" \
        --arg eval_dataset_version "$eval_dataset_version" \
        --arg eval_grader_version "$eval_grader_version" \
        --arg eval_dataset_sha "$eval_dataset_sha" \
        --arg blueprint_factory_version "$blueprint_factory_version" \
        --arg blueprint_index_sha "$blueprint_index_sha" \
        --arg quality_report_sha "$quality_report_sha" \
        --arg control_source_sha "$bundle_sha" \
        --arg homologation_runner_version "$homologation_runner_version" \
        --arg homologation_package_manifest_sha "$homologation_manifest_sha" \
        --argjson catalog_entries "$catalog_entries" \
        --argjson knowledge_entries "$knowledge_entries" \
        --argjson eval_schema "$eval_schema" \
        --argjson eval_case_entries "$eval_case_entries" \
        --argjson blueprint_schema "$blueprint_schema" \
        --argjson blueprint_entries "$blueprint_entries" \
        --argjson blueprint_knowledge_entries "$blueprint_knowledge_entries" \
        --argjson blueprint_fixture_entries "$blueprint_fixture_entries" \
        --argjson quality_schema "$quality_schema" \
        --argjson quality_setup_entries "$quality_setup_entries" \
        --argjson quality_structural_entries "$quality_structural_entries" \
        --argjson quality_source_reviewed_entries "$quality_source_reviewed_entries" \
        --argjson quality_script_reviewed_entries "$quality_script_reviewed_entries" \
        --argjson quality_operational_entries "$quality_operational_entries" \
        --argjson quality_homologated_entries "$quality_homologated_entries" \
        --argjson quality_unresolved_issues "$quality_unresolved_issues" \
        --argjson control_source_bytes "$bundle_bytes" \
        --argjson homologation_candidate_schema "$homologation_candidate_schema" \
        --argjson homologation_registry_entries "$homologation_registry_entries" \
        '{
            schemaVersion: 1,
            setupVersion: $setup_version,
            catalogVersion: $setup_version,
            catalogSHA256: $catalog_sha,
            catalogEntries: $catalog_entries,
            architecture: $architecture,
            controlSourceSHA256: $control_source_sha,
            controlSourceBytes: $control_source_bytes,
            knowledgeVersion: $knowledge_version,
            knowledgeArchiveSHA256: $knowledge_archive_sha,
            knowledgeEntries: $knowledge_entries,
            evalSchemaVersion: $eval_schema,
            evalDatasetVersion: $eval_dataset_version,
            evalGraderVersion: $eval_grader_version,
            evalDatasetSHA256: $eval_dataset_sha,
            evalCaseEntries: $eval_case_entries,
            blueprintSchemaVersion: $blueprint_schema,
            blueprintFactoryVersion: $blueprint_factory_version,
            blueprintIndexSHA256: $blueprint_index_sha,
            blueprintEntries: $blueprint_entries,
            blueprintKnowledgeEntries: $blueprint_knowledge_entries,
            blueprintFixtureEntries: $blueprint_fixture_entries,
            qualitySchemaVersion: $quality_schema,
            qualityReportSHA256: $quality_report_sha,
            qualitySetupEntries: $quality_setup_entries,
            qualityStructuralEntries: $quality_structural_entries,
            qualitySourceReviewedEntries: $quality_source_reviewed_entries,
            qualityScriptReviewedEntries: $quality_script_reviewed_entries,
            qualityOperationalEntries: $quality_operational_entries,
            qualityHomologatedEntries: $quality_homologated_entries,
            qualityUnresolvedIssues: $quality_unresolved_issues,
            homologationRunnerVersion: $homologation_runner_version,
            homologationCandidateSchemaVersion: $homologation_candidate_schema,
            homologationRegistryEntries: $homologation_registry_entries,
            homologationPackageManifestSHA256: $homologation_package_manifest_sha,
            homologationAutomaticPromotion: false
        }' >"$temporary_manifest"
    chmod 0644 "$temporary_manifest"
    mv -f "$temporary_manifest" "$target/release.json"
}

generate_runtime_package "$x86_runtime_package" "amd64"
generate_runtime_package "$arm_runtime_package" "arm64"
"$project_dir/runtime-promotion_test.sh" >/dev/null

cmp -s "$x86_runtime_package/knowledge-package/manifest.json" \
    "$arm_runtime_package/knowledge-package/manifest.json"
cmp -s "$x86_runtime_package/knowledge-package/knowledge-package.tar.gz" \
    "$arm_runtime_package/knowledge-package/knowledge-package.tar.gz"
cmp -s "$x86_runtime_package/control-source.tar.gz" \
    "$arm_runtime_package/control-source.tar.gz"
cmp -s "$x86_runtime_package/homologation-package/manifest.json" \
    "$arm_runtime_package/homologation-package/manifest.json"
for runtime_package in "$x86_runtime_package" "$arm_runtime_package"; do
    packaged_source_sha=$(sha256sum "$runtime_package/control-source.tar.gz" | awk '{print $1}')
    packaged_source_bytes=$(stat -c '%s' "$runtime_package/control-source.tar.gz")
    manifest_source_sha=$(jq -r '.controlSourceSHA256 // empty' "$runtime_package/release.json")
    manifest_source_bytes=$(jq -r '.controlSourceBytes // 0' "$runtime_package/release.json")
    packaged_homologation_manifest_sha=$(sha256sum "$runtime_package/homologation-package/manifest.json" | awk '{print $1}')
    manifest_homologation_manifest_sha=$(jq -r '.homologationPackageManifestSHA256 // empty' "$runtime_package/release.json")
    manifest_homologation_automatic_promotion=$(jq -r '
        if has("homologationAutomaticPromotion")
        then .homologationAutomaticPromotion
        else "missing"
        end
    ' "$runtime_package/release.json")
    [ "$packaged_source_sha" = "$manifest_source_sha" ] &&
    [ "$packaged_source_bytes" = "$manifest_source_bytes" ] &&
    [ "$packaged_homologation_manifest_sha" = "$manifest_homologation_manifest_sha" ] &&
    [ "$manifest_homologation_automatic_promotion" = "false" ] &&
    python3 -B "$runtime_package/homologation-package/homologation_runner.py" \
        --package-dir "$runtime_package/homologation-package" list >/dev/null || {
        printf 'ERRO: bundle de fontes diverge do manifesto runtime em %s.\n' \
            "$runtime_package" >&2
        exit 1
    }
done

printf 'Instaladores x86/ARM e manifestos runtime v%s gerados (%s setups, %s documentos, %s Blueprints, %s fixtures RAG).\n' \
    "$x86_version" "$catalog_entries" "$knowledge_entries" "$blueprint_entries" "$blueprint_fixture_entries"

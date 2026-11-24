#!/usr/bin/bash
set -Eeuo pipefail

# Interface guiada para o Homologation Runner. Este arquivo nunca executa
# texto informado pelo usuário como comando e nunca publica catálogo ou release.
umask 077

RUNNER_DIR="${SETUPMNO_HOMOLOGATION_PACKAGE_DIR:-/root/SetupLowCodeMno/.control/homologation-package}"
RUNNER="$RUNNER_DIR/homologation_runner.py"
REGISTRY="$RUNNER_DIR/runner-registry.json"
WORK_ROOT="${SETUPMNO_HOMOLOGATION_WORK_ROOT:-/root/setupmno-homologation-candidates}"
RUNNER_COMMAND=(python3 -B "$RUNNER" --package-dir "$RUNNER_DIR")

declare -A CHECK_LABELS=(
    [deploy]="Deploy concluído"
    [convergence]="Serviços convergiram"
    [health]="Saúde funcional confirmada"
    [persistence]="Persistência confirmada"
    [restart]="Reinício confirmado"
    [update]="Atualização confirmada"
    [backup]="Backup confirmado"
    [restore]="Restauração confirmada"
    [cleanup]="Limpeza do laboratório confirmada"
)
CHECK_ORDER=(deploy convergence health persistence restart update backup restore cleanup)
CORE_CHECKS=(deploy convergence health)

dialog_height() {
    local requested="$1" available
    available=$(tput lines 2>/dev/null || printf '24')
    available=$((available - 2))
    [ "$available" -ge 10 ] || available=10
    [ "$requested" -le "$available" ] || requested="$available"
    printf '%s' "$requested"
}

dialog_width() {
    local requested="$1" available
    available=$(tput cols 2>/dev/null || printf '80')
    available=$((available - 2))
    [ "$available" -ge 46 ] || available=46
    [ "$requested" -le "$available" ] || requested="$available"
    printf '%s' "$requested"
}

menu_rows() {
    local requested="$1" height rows
    height=$(dialog_height "$requested")
    rows=$((height - 8))
    [ "$rows" -ge 2 ] || rows=2
    printf '%s' "$rows"
}

message() {
    whiptail --title "$1" --msgbox "$2" "$(dialog_height 22)" "$(dialog_width 84)" 1>&2
}

show_error() {
    message "HOMOLOGAÇÃO INTERROMPIDA" "$1"
}

confirm() {
    whiptail --title "$1" --yesno "$2" "$(dialog_height 18)" "$(dialog_width 84)" 1>&2
}

validate_safe_root() {
    case "$WORK_ROOT" in
        /root/setupmno-homologation-candidates|/tmp/setupmno-homologacao|/tmp/setupmno-homologacao/*) ;;
        *)
            printf 'Diretório de trabalho fora da allowlist.\n' >&2
            return 1
            ;;
    esac
    if [ -L "$WORK_ROOT" ]; then
        printf 'Diretório de trabalho não pode ser symlink.\n' >&2
        return 1
    fi
    mkdir -p "$WORK_ROOT"
    chmod 0700 "$WORK_ROOT"
}

validate_runtime() {
    local command_name file_name
    for command_name in python3 jq docker whiptail sha256sum; do
        command -v "$command_name" >/dev/null 2>&1 || {
            show_error "Dependência obrigatória ausente: $command_name. Atualize o Setup MNO e tente novamente."
            return 1
        }
    done
    for file_name in manifest.json homologation_runner.py \
        homologation_wizard.sh homologation-candidate.schema.json \
        homologation-review-decision.schema.json homologation-review-pack.schema.json \
        runner-registry.json; do
        [ -f "$RUNNER_DIR/$file_name" ] && [ ! -L "$RUNNER_DIR/$file_name" ] || {
            show_error "Pacote do Homologation Runner ausente ou inseguro: $file_name."
            return 1
        }
    done
    validate_safe_root || {
        show_error "O diretório de candidatos não passou na validação de segurança."
        return 1
    }
    if ! "${RUNNER_COMMAND[@]}" list >/dev/null 2>&1; then
        show_error "A autoverificação do Homologation Runner falhou. Atualize o Setup MNO antes de continuar."
        return 1
    fi
}

select_setup() {
    local setup_id catalog_name
    local -a entries=()
    while IFS=$'\t' read -r setup_id catalog_name; do
        [[ "$setup_id" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]] || continue
        [ -n "$catalog_name" ] || continue
        entries+=("$setup_id" "$catalog_name")
    done < <(jq -r '.entries[] | [.setupId, .catalogName] | @tsv' "$REGISTRY")
    [ "${#entries[@]}" -gt 0 ] || return 1
    whiptail --title "1/4 — SELECIONE A APLICAÇÃO" --menu \
        "Escolha o setup que será avaliado. Digite a primeira letra para navegar mais rápido." \
        "$(dialog_height 24)" "$(dialog_width 92)" "$(menu_rows 24)" \
        "${entries[@]}" 3>&1 1>&2 2>&3
}

select_architecture() {
    local setup_id="$1" architecture
    local -a entries=()
    while IFS= read -r architecture; do
        case "$architecture" in
            amd64) entries+=("amd64" "VPS x86_64 ou WSL2 + Docker Desktop") ;;
            arm64) entries+=("arm64" "Servidor ARM64") ;;
        esac
    done < <(jq -r --arg setup "$setup_id" \
        '.entries[] | select(.setupId == $setup) | .architectures[]' "$REGISTRY")
    [ "${#entries[@]}" -gt 0 ] || return 1
    whiptail --title "2/4 — ARQUITETURA" --menu \
        "Escolha a arquitetura que será realmente testada." \
        "$(dialog_height 15)" "$(dialog_width 78)" 4 \
        "${entries[@]}" 3>&1 1>&2 2>&3
}

select_platform() {
    local default_platform="linux-vps" platform label
    local -a entries=()
    if grep -Eqi 'microsoft|wsl' /proc/version 2>/dev/null; then
        default_platform="wsl2-docker-desktop"
    fi
    entries+=("$default_platform" "Ambiente detectado automaticamente")
    for platform in linux-vps wsl2-docker-desktop linux-emulated; do
        [ "$platform" = "$default_platform" ] && continue
        case "$platform" in
            linux-vps) label="VPS Linux" ;;
            wsl2-docker-desktop) label="Windows com WSL2 e Docker Desktop" ;;
            linux-emulated) label="Linux emulado para compatibilidade" ;;
        esac
        entries+=("$platform" "$label")
    done
    whiptail --title "3/4 — AMBIENTE" --menu \
        "Ambiente detectado: $default_platform. Confirme o laboratório usado no teste." \
        "$(dialog_height 17)" "$(dialog_width 82)" 5 \
        "${entries[@]}" \
        3>&1 1>&2 2>&3
}

start_session() {
    local setup_id architecture platform output session_path
    setup_id=$(select_setup) || return 130
    architecture=$(select_architecture "$setup_id") || return 130
    platform=$(select_platform) || return 130
    confirm "4/4 — CONFIRMAR SESSÃO" \
        "Aplicação: $setup_id\nArquitetura: $architecture\nAmbiente: $platform\n\nO assistente registra evidências declaradas pelo testador. Ele não cria recursos Docker, não executa comandos livres e não concede o selo oficial.\n\nIniciar a sessão?" || return 130
    if ! output=$("${RUNNER_COMMAND[@]}" init \
        --setup-id "$setup_id" \
        --architecture "$architecture" \
        --platform "$platform" \
        --output-dir "$WORK_ROOT" 2>&1); then
        show_error "$output"
        return 1
    fi
    session_path=$(printf '%s\n' "$output" | tail -n 1)
    case "$session_path" in
        "$WORK_ROOT"/setupmno-hml-*/session.json) ;;
        *)
            show_error "O runner retornou um caminho de sessão inesperado."
            return 1
            ;;
    esac
    [ -f "$session_path" ] && [ ! -L "$session_path" ] || {
        show_error "A sessão não foi criada de forma segura."
        return 1
    }
    run_checklist "$session_path"
}

select_docker_service() {
    local service_name image replicas
    local -a preferred=() remaining=()
    while IFS=$'\t' read -r service_name image replicas; do
        [[ "$service_name" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]{0,127}$ ]] || continue
        [ -n "$image" ] || continue
        if [[ "${service_name,,} ${image,,}" == *"${QUICK_SETUP_ID//-/_}"* ]] || \
           [[ "${service_name,,} ${image,,}" == *"${QUICK_SETUP_ID}"* ]]; then
            preferred+=("$service_name" "$replicas · ${image:0:54}")
        else
            remaining+=("$service_name" "$replicas · ${image:0:54}")
        fi
    done < <(docker service ls --format '{{.Name}}\t{{.Image}}\t{{.Replicas}}' 2>/dev/null | sort)
    local -a entries=("${preferred[@]}" "${remaining[@]}")
    [ "${#entries[@]}" -gt 0 ] || {
        message "SERVIÇO NÃO ENCONTRADO" "Nenhum serviço Docker Swarm está disponível. Instale a aplicação antes de homologar."
        return 1
    }
    whiptail --title "SERVIÇO INSTALADO" --menu \
        "Selecione o serviço principal da aplicação. As sugestões compatíveis aparecem primeiro." \
        "$(dialog_height 24)" "$(dialog_width 108)" "$(menu_rows 24)" \
        "${entries[@]}" 3>&1 1>&2 2>&3
}

run_quick_homologation() {
    local setup_id architecture platform output session_path service_name target_url
    local tester candidate_path decision_path evidence_path review_pack_path seal_path
    local result_text seal_output
    setup_id=$(select_setup) || return 130
    architecture=$(select_architecture "$setup_id") || return 130
    platform=$(select_platform) || return 130
    QUICK_SETUP_ID="$setup_id"
    service_name=$(select_docker_service) || return 130
    target_url=$(whiptail --title "URL DA APLICAÇÃO" --inputbox \
        "Se o Setup MNO conseguir detectar a URL, deixe em branco. Caso contrário, informe http:// ou https:// seguido do endereço da aplicação." \
        "$(dialog_height 13)" "$(dialog_width 96)" 3>&1 1>&2 2>&3) || return 130
    confirm "HOMOLOGAÇÃO ESSENCIAL" \
        "Aplicação: $setup_id\nArquitetura: $architecture\nAmbiente: $platform\nServiço: $service_name\n\nO sistema verificará arquitetura, serviço, réplicas, estabilidade, logs, resposta web e imagem. Nenhum recurso será reiniciado, alterado ou removido.\n\nIniciar?" || return 130
    if ! output=$("${RUNNER_COMMAND[@]}" init \
        --setup-id "$setup_id" --architecture "$architecture" \
        --platform "$platform" --output-dir "$WORK_ROOT" 2>&1); then
        show_error "$output"
        return 1
    fi
    session_path=$(printf '%s\n' "$output" | tail -n 1)
    case "$session_path" in
        "$WORK_ROOT"/setupmno-hml-*/session.json) ;;
        *) show_error "O Runner retornou uma sessão inesperada."; return 1 ;;
    esac
    local -a inspect_args=(inspect --session "$session_path" --service "$service_name")
    [ -z "$target_url" ] || inspect_args+=(--url "$target_url")
    if ! output=$("${RUNNER_COMMAND[@]}" "${inspect_args[@]}" 2>&1); then
        show_error "$output\n\nNenhum selo foi concedido. Corrija a aplicação e inicie uma nova homologação."
        return 1
    fi
    result_text=$(printf '%s' "$output" | jq -r '
        "✓ Arquitetura " + .architecture + " confirmada\n" +
        "✓ Serviço estável: " + (.runningTasks|tostring) + "/" + (.desiredTasks|tostring) + "\n" +
        "✓ Resposta web: HTTP " + (.httpStatus|tostring) + "\n" +
        "✓ Logs recentes sem indicador crítico\n" +
        "✓ Imagem registrada por digest"')
    if ! confirm "RESULTADO AUTOMÁTICO APROVADO" \
        "$result_text\n\nConfirma que abriu a aplicação nesta arquitetura e não observou erro visível?"; then
        message "SEM SELO" "A inspeção automática foi preservada, mas nenhum selo foi concedido porque faltou a confirmação do mantenedor."
        return 0
    fi
    tester=$(whiptail --title "MANTENEDOR RESPONSÁVEL" --inputbox \
        "Informe apenas o seu nome público. Não use e-mail, hostname ou credencial." \
        "$(dialog_height 12)" "$(dialog_width 86)" 3>&1 1>&2 2>&3) || return 130
    candidate_path="${session_path%/session.json}/$(jq -r '.setupId + "-" + .architecture + "-" + (.runId | split("-")[-1]) + "-candidate.tar.gz"' "$session_path")"
    mapfile -t HOMOLOGATION_IMAGES < <(printf '%s' "$output" | jq -r '.images[]')
    local -a image_args=()
    local image_ref
    for image_ref in "${HOMOLOGATION_IMAGES[@]}"; do image_args+=(--image "$image_ref"); done
    if ! output=$("${RUNNER_COMMAND[@]}" finalize --session "$session_path" \
        "${image_args[@]}" --tester "$tester" --output "$candidate_path" 2>&1); then
        show_error "$output"
        return 1
    fi
    decision_path="${candidate_path%.tar.gz}-decision.json"
    evidence_path="${candidate_path%.tar.gz}-reviewed.json"
    review_pack_path="${candidate_path%.tar.gz}-review-pack.tar.gz"
    if ! output=$("${RUNNER_COMMAND[@]}" decide --bundle "$candidate_path" \
        --reviewer "$tester" --decision approved \
        --reason-code operational-evidence-accepted \
        --reason "Gates essenciais automáticos aprovados e funcionamento visual confirmado pelo mantenedor." \
        --decision-output "$decision_path" --evidence-output "$evidence_path" \
        --review-pack-output "$review_pack_path" 2>&1); then
        show_error "$output"
        return 1
    fi
    seal_path="${candidate_path%.tar.gz}-essential-seal.json"
    if ! seal_output=$("${RUNNER_COMMAND[@]}" seal-essential \
        --bundle "$candidate_path" --decision "$decision_path" \
        --maintainer "$tester" --output "$seal_path" 2>&1); then
        show_error "$seal_output"
        return 1
    fi
    message "SELO ESSENCIAL CONCEDIDO" \
        "Aplicação: $setup_id\nArquitetura: $architecture\nEscopo: instalação, inicialização e resposta web\nSHA-256: $(printf '%s' "$seal_output" | jq -r '.sha256')\n\nSelo:\n$seal_path\n\nA publicação no catálogo continua separada e nunca cria commit, tag ou release automaticamente."
}

select_session() {
    local session_file run_id setup_id created_at status
    local -a entries=()
    while IFS= read -r session_file; do
        [ -f "$session_file" ] && [ ! -L "$session_file" ] || continue
        run_id=$(jq -r '.runId // empty' "$session_file" 2>/dev/null)
        setup_id=$(jq -r '.setupId // empty' "$session_file" 2>/dev/null)
        created_at=$(jq -r '.createdAt // empty' "$session_file" 2>/dev/null)
        [[ "$run_id" =~ ^setupmno-hml-[a-z0-9-]+-[0-9]{12}$ ]] || continue
        entries+=("$session_file" "$setup_id · ${created_at:-data indisponível}")
    done < <(find "$WORK_ROOT" -mindepth 2 -maxdepth 2 -type f -name session.json -print 2>/dev/null | sort)
    if [ "${#entries[@]}" -eq 0 ]; then
        message "NENHUMA SESSÃO" "Nenhuma sessão candidata foi encontrada em:\n$WORK_ROOT"
        return 1
    fi
    whiptail --title "CONTINUAR HOMOLOGAÇÃO" --menu \
        "Escolha uma sessão existente." "$(dialog_height 22)" "$(dialog_width 100)" \
        "$(menu_rows 22)" "${entries[@]}" 3>&1 1>&2 2>&3
}

collect_check() {
    local session_path="$1" check_name="$2" current_status current_evidence choice evidence output
    current_status=$(jq -r --arg check "$check_name" '.checks[$check].status' "$session_path")
    current_evidence=$(jq -r --arg check "$check_name" '.checks[$check].evidence' "$session_path")
    choice=$(whiptail --title "CHECK — ${CHECK_LABELS[$check_name]}" --menu \
        "Estado atual: $current_status\n\nRegistre somente o que foi realmente verificado. Não informe IP, domínio, e-mail, senha, token ou secret." \
        "$(dialog_height 19)" "$(dialog_width 88)" 6 \
        "passed" "Teste executado e aprovado" \
        "not-tested" "Teste ainda não executado" \
        "not-applicable" "Não aplicável, com justificativa" \
        "keep" "Manter o registro atual" \
        "save-exit" "Salvar a sessão e voltar ao menu" \
        3>&1 1>&2 2>&3) || return 130
    case "$choice" in
        keep) return 0 ;;
        save-exit) return 131 ;;
        not-tested)
            evidence="Teste ainda não executado nesta sessão."
            ;;
        passed|not-applicable)
            evidence=$(whiptail --title "EVIDÊNCIA SANITIZADA" --inputbox \
                "Descreva objetivamente o resultado em até 240 caracteres. Não inclua dados do servidor ou credenciais." \
                "$(dialog_height 13)" "$(dialog_width 92)" \
                "$current_evidence" 3>&1 1>&2 2>&3) || return 130
            ;;
    esac
    if ! output=$("${RUNNER_COMMAND[@]}" record --session "$session_path" \
        --check "$check_name" --status "$choice" --evidence "$evidence" 2>&1); then
        show_error "$output"
        return 1
    fi
}

run_checklist() {
    local session_path="$1" check_name checklist_summary collect_status
    case "$session_path" in
        "$WORK_ROOT"/setupmno-hml-*/session.json) ;;
        *) show_error "Sessão fora do diretório permitido."; return 1 ;;
    esac
    message "CHECKLIST DE HOMOLOGAÇÃO" \
        "Execute os testes em um laboratório isolado identificado por setupmno-hml-*.\n\nO assistente guiará os nove checks. Você pode salvar e continuar depois. Checks não executados nunca serão convertidos em aprovação."
    for check_name in "${CHECK_ORDER[@]}"; do
        if collect_check "$session_path" "$check_name"; then
            continue
        else
            collect_status=$?
            case "$collect_status" in
                130|131) message "SESSÃO SALVA" "A sessão foi preservada em:\n$session_path"; return 0 ;;
                *) return 1 ;;
            esac
        fi
    done
    checklist_summary=$(jq -r '.checks | to_entries[] | "\(.key): \(.value.status)"' "$session_path")
    if ! confirm "CHECKLIST REGISTRADO" \
        "$checklist_summary\n\nDeseja tentar gerar o candidato agora?"; then
        message "SESSÃO SALVA" "Você poderá continuar posteriormente.\n\n$session_path"
        return 0
    fi
    finalize_candidate "$session_path"
}

core_checks_passed() {
    local session_path="$1" check_name
    for check_name in "${CORE_CHECKS[@]}"; do
        [ "$(jq -r --arg check "$check_name" '.checks[$check].status' "$session_path")" = "passed" ] || return 1
    done
}

collect_images() {
    local image_ref
    HOMOLOGATION_IMAGES=()
    while true; do
        image_ref=$(whiptail --title "IMAGEM TESTADA" --inputbox \
            "Informe a imagem exatamente como repositorio@sha256:DIGEST. Tags como latest não são aceitas." \
            "$(dialog_height 13)" "$(dialog_width 96)" 3>&1 1>&2 2>&3) || return 130
        [[ "$image_ref" =~ ^[^[:space:]]+@sha256:[a-f0-9]{64}$ ]] || {
            message "IMAGEM INVÁLIDA" "Use o formato repositorio@sha256 seguido de 64 caracteres hexadecimais."
            continue
        }
        HOMOLOGATION_IMAGES+=(--image "$image_ref")
        confirm "OUTRA IMAGEM" "Esta homologação utilizou outra imagem de container?" || break
    done
}

finalize_candidate() {
    local session_path="$1" tester output candidate_path result status bundle_sha
    if ! core_checks_passed "$session_path"; then
        message "CANDIDATO AINDA INCOMPLETO" \
            "Deploy, convergência e saúde precisam estar aprovados. A sessão foi salva para continuação."
        return 0
    fi
    tester=$(whiptail --title "IDENTIFICAÇÃO DO TESTADOR" --inputbox \
        "Informe um nome público. Não use e-mail, usuário, hostname ou empresa do cliente." \
        "$(dialog_height 12)" "$(dialog_width 86)" 3>&1 1>&2 2>&3) || return 130
    collect_images || return 130
    candidate_path="${session_path%/session.json}/$(jq -r '.setupId + "-" + .architecture + "-" + (.runId | split("-")[-1]) + "-candidate.tar.gz"' "$session_path")"
    if [ -e "$candidate_path" ]; then
        show_error "Já existe um candidato para esta sessão. Use a opção Verificar candidato."
        return 1
    fi
    if ! output=$("${RUNNER_COMMAND[@]}" finalize --session "$session_path" \
        "${HOMOLOGATION_IMAGES[@]}" --tester "$tester" --output "$candidate_path" 2>&1); then
        show_error "$output"
        return 1
    fi
    result=$(printf '%s' "$output" | jq -r '.result // "desconhecido"' 2>/dev/null)
    status=$(printf '%s' "$output" | jq -r '.status // "desconhecido"' 2>/dev/null)
    bundle_sha=$(printf '%s' "$output" | jq -r '.sha256 // "indisponível"' 2>/dev/null)
    message "CANDIDATO GERADO" \
        "Resultado: $result\nStatus: $status\nSHA-256: $bundle_sha\n\nArquivo:\n$candidate_path\n\nATENÇÃO: este bundle não possui selo oficial e ainda exige revisão do mantenedor."
}

select_candidate() {
    local candidate_file candidate_id setup_id
    local -a entries=()
    while IFS= read -r candidate_file; do
        [ -f "$candidate_file" ] && [ ! -L "$candidate_file" ] || continue
        candidate_id=$(basename "$candidate_file" .tar.gz)
        [[ "$candidate_id" =~ ^[a-z0-9-]+-candidate$ ]] || continue
        setup_id=${candidate_id%%-amd64-*}
        setup_id=${setup_id%%-arm64-*}
        entries+=("$candidate_file" "$candidate_id")
    done < <(find "$WORK_ROOT" -mindepth 2 -maxdepth 2 -type f -name '*-candidate.tar.gz' -print 2>/dev/null | sort)
    if [ "${#entries[@]}" -eq 0 ]; then
        message "NENHUM CANDIDATO" "Nenhum bundle candidato foi encontrado em:\n$WORK_ROOT"
        return 1
    fi
    whiptail --title "SELECIONE O CANDIDATO" --menu \
        "Escolha um bundle para verificar." "$(dialog_height 22)" "$(dialog_width 104)" \
        "$(menu_rows 22)" "${entries[@]}" 3>&1 1>&2 2>&3
}

verify_candidate() {
    local candidate_path="${1:-}" output
    if [ -z "$candidate_path" ]; then
        candidate_path=$(select_candidate) || return 0
    fi
    case "$candidate_path" in
        "$WORK_ROOT"/setupmno-hml-*/*-candidate.tar.gz) ;;
        *) show_error "Candidato fora do diretório permitido."; return 1 ;;
    esac
    if ! output=$("${RUNNER_COMMAND[@]}" verify --bundle "$candidate_path" 2>&1); then
        show_error "$output"
        return 1
    fi
    message "CANDIDATO ÍNTEGRO" \
        "$(printf '%s' "$output" | jq -r '"Aplicação: \(.setupId)\nVersão: \(.setupVersion)\nArquitetura: \(.architecture)\nResultado: \(.result)\nStatus: \(.status)\nSelo oficial: \(.officialSeal)\nSHA-256: \(.bundleSHA256)"')\n\nA integridade foi confirmada, mas o selo oficial continua bloqueado."
}

decide_candidate() {
    local candidate_path reviewer decision reason_code reason decision_path evidence_path review_pack_path output
    candidate_path=$(select_candidate) || return 0
    verify_candidate "$candidate_path" || return 1
    decision=$(whiptail --title "DECISÃO HUMANA IMUTÁVEL" --menu \
        "A decisão local não altera a governança e não concede o selo oficial. Escolha o resultado da revisão." \
        "$(dialog_height 16)" "$(dialog_width 92)" 4 \
        "approved" "Aprovar evidência operacional" \
        "rejected" "Rejeitar ou devolver para novos testes" \
        3>&1 1>&2 2>&3) || return 130
    if [ "$decision" = "approved" ]; then
        reason_code="operational-evidence-accepted"
    else
        reason_code=$(whiptail --title "MOTIVO DA RECUSA" --menu \
            "Escolha o principal motivo. Nenhuma informação sensível deve ser registrada." \
            "$(dialog_height 19)" "$(dialog_width 96)" 7 \
            "artifact-mismatch" "Artefato diferente do instalador atual" \
            "incomplete-evidence" "Checklist ou evidência incompleta" \
            "unsafe-data" "Dados sensíveis ou inseguros" \
            "check-failed" "Falha funcional reproduzida" \
            "rerun-required" "Nova execução obrigatória" \
            "other" "Outro motivo documentado" \
            3>&1 1>&2 2>&3) || return 130
    fi
    reviewer=$(whiptail --title "REVISOR" --inputbox \
        "Informe o nome público do revisor responsável." \
        "$(dialog_height 11)" "$(dialog_width 80)" 3>&1 1>&2 2>&3) || return 130
    reason=$(whiptail --title "JUSTIFICATIVA SANITIZADA" --inputbox \
        "Resuma a decisão em 3 a 240 caracteres. Não informe IP, domínio, e-mail, credencial ou secret." \
        "$(dialog_height 13)" "$(dialog_width 94)" 3>&1 1>&2 2>&3) || return 130
    decision_path="${candidate_path%.tar.gz}-decision.json"
    evidence_path="${candidate_path%.tar.gz}-reviewed.json"
    review_pack_path="${candidate_path%.tar.gz}-review-pack.tar.gz"
    if [ -e "$decision_path" ]; then
        show_error "Este candidato já possui uma decisão imutável e não será sobrescrito."
        return 1
    fi
    local -a decision_args=(decide --bundle "$candidate_path" --reviewer "$reviewer"
        --decision "$decision" --reason-code "$reason_code" --reason "$reason"
        --decision-output "$decision_path")
    if [ "$decision" = "approved" ]; then
        decision_args+=(--evidence-output "$evidence_path" --review-pack-output "$review_pack_path")
    fi
    if ! output=$("${RUNNER_COMMAND[@]}" "${decision_args[@]}" 2>&1); then
        show_error "$output"
        return 1
    fi
    if [ "$decision" = "approved" ]; then
        message "APROVAÇÃO LOCAL REGISTRADA" \
            "Decisão imutável:\n$decision_path\n\nPacote para certificação:\n$review_pack_path\n\nPróximo passo PRO MASTER: volte à Central do Mantenedor, escolha CERTIFY, execute os dry-runs e confirme os tokens. Governança alterada: NÃO. Selo oficial: NÃO."
    else
        message "RECUSA REGISTRADA" \
            "Decisão imutável:\n$decision_path\n\nO candidato foi recusado localmente. Nenhuma evidência canônica, governança ou selo foi criado."
    fi
}

main_menu() {
    local choice session_path
    while true; do
        choice=$(whiptail --title "SETUP MNO — ASSISTENTE DE HOMOLOGAÇÃO" --menu \
            "Escolha o fluxo simples recomendado ou o checklist técnico opcional." \
            "$(dialog_height 21)" "$(dialog_width 100)" 9 \
            "QUICK" "Homologar automaticamente e conceder selo essencial — RECOMENDADO" \
            "ADVANCED" "Executar checklist técnico avançado opcional" \
            "CONTINUE" "Continuar checklist salvo" \
            "VERIFY" "Verificar integridade de candidato" \
            "REVIEW" "Registrar decisão humana imutável" \
            "ABOUT" "Entender candidato, revisão e selo oficial" \
            "EXIT" "Voltar ao Terminal Seguro" \
            3>&1 1>&2 2>&3) || return 0
        case "$choice" in
            QUICK) run_quick_homologation || true ;;
            ADVANCED) start_session || true ;;
            CONTINUE)
                session_path=$(select_session) || continue
                run_checklist "$session_path" || true
                ;;
            VERIFY) verify_candidate || true ;;
            REVIEW) decide_candidate || true ;;
            ABOUT)
                message "FRONTEIRA DE CONFIANÇA" \
                    "SELO ESSENCIAL: concedido por arquitetura quando o serviço converge, permanece estável, responde pela web, não apresenta indicador crítico nos logs e o mantenedor confirma visualmente o funcionamento.\n\nHOMOLOGAÇÃO AVANÇADA: checklist técnico opcional para persistência, reinício, atualização, backup, restauração e limpeza.\n\nPUBLICAÇÃO: sempre separada. Nenhum fluxo cria commit, tag, release, deploy ou DNS automaticamente."
                ;;
            EXIT) return 0 ;;
        esac
    done
}

if [ "${SETUPMNO_HOMOLOGATION_WIZARD_SMOKE_TEST:-0}" = "1" ]; then
    printf 'setupmno-homologation-wizard-ok\n'
    exit 0
fi

validate_runtime || exit 2
main_menu

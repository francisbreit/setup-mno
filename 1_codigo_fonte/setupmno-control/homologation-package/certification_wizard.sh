#!/usr/bin/bash
set -Eeuo pipefail

# Assistente administrativo do mantenedor. No runtime, permanece restrito ao
# PRO MASTER e não cria commit, tag, release ou publicação automaticamente.
umask 077

TOOLS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
KNOWLEDGE_ROOT="${SETUPMNO_CERTIFICATION_ROOT:-$(cd "$TOOLS_DIR/.." && pwd)}"
SOURCE_ROOT=$(cd "$KNOWLEDGE_ROOT/.." && pwd)
CERTIFIER="$TOOLS_DIR/certify_homologation.py"
CATALOG="${SETUPMNO_CERTIFICATION_CATALOG:-$SOURCE_ROOT/setupmno-control/catalog.json}"
PACKAGE_DIR="${SETUPMNO_CERTIFICATION_PACKAGE_DIR:-$SOURCE_ROOT/setupmno-control/homologation-package}"
PACK_ROOT="${SETUPMNO_CERTIFICATION_PACK_ROOT:-/root/setupmno-homologation-candidates}"
RUNTIME_MODE="${SETUPMNO_CERTIFICATION_RUNTIME:-0}"
DOCUMENT_PREPARER="$TOOLS_DIR/prepare_homologation_document.py"
RUNTIME_RELEASE=""
EXPORT_DIR=""

initialize_runtime_mode() {
    local runtime_runner_dir
    [ "$RUNTIME_MODE" = "1" ] || return 0
    runtime_runner_dir="${SETUPMNO_HOMOLOGATION_PACKAGE_DIR:-/root/SetupLowCodeMno/.control/homologation-package}"
    # shellcheck source=/dev/null
    source "$runtime_runner_dir/maintainer_workspace.sh"
    setupmno_prepare_maintainer_workspace || return 1
    KNOWLEDGE_ROOT="$SETUPMNO_MAINTAINER_KNOWLEDGE_ROOT"
    SOURCE_ROOT="$SETUPMNO_MAINTAINER_WORKSPACE"
    TOOLS_DIR="$KNOWLEDGE_ROOT/tools"
    CERTIFIER="$TOOLS_DIR/certify_homologation.py"
    DOCUMENT_PREPARER="$TOOLS_DIR/prepare_homologation_document.py"
    CATALOG="$SETUPMNO_MAINTAINER_CATALOG"
    PACKAGE_DIR="$SETUPMNO_MAINTAINER_RUNNER_DIR"
    RUNTIME_RELEASE="$SETUPMNO_MAINTAINER_RUNTIME_RELEASE"
    EXPORT_DIR="$PACK_ROOT/official-seals"
}

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
    [ "$available" -ge 48 ] || available=48
    [ "$requested" -le "$available" ] || requested="$available"
    printf '%s' "$requested"
}

message() {
    whiptail --title "$1" --msgbox "$2" "$(dialog_height 23)" "$(dialog_width 96)" 1>&2
}

show_error() {
    message "CERTIFICAÇÃO INTERROMPIDA" "$1"
}

validate_runtime() {
    local command_name path
    for command_name in python3 jq whiptail sha256sum; do
        command -v "$command_name" >/dev/null 2>&1 || {
            show_error "Dependência obrigatória ausente: $command_name"
            return 1
        }
    done
    for path in "$CERTIFIER" "$DOCUMENT_PREPARER" "$TOOLS_DIR/import_homologation_review.py" \
        "$TOOLS_DIR/homologation_runner.py" "$TOOLS_DIR/knowledge_quality.py" \
        "$KNOWLEDGE_ROOT/registry/certification-ledger.json" "$CATALOG" \
        "$PACKAGE_DIR/manifest.json"; do
        [ -f "$path" ] && [ ! -L "$path" ] || {
            show_error "Componente canônico ausente ou inseguro:\n$path"
            return 1
        }
    done
    case "$PACK_ROOT" in
        /root/setupmno-homologation-candidates|/root/setupmno-homologation-candidates/*|/tmp/setupmno-homologacao|/tmp/setupmno-homologacao/*) ;;
        *)
            show_error "O diretório de pacotes está fora da allowlist administrativa."
            return 1
            ;;
    esac
    [ -d "$PACK_ROOT" ] && [ ! -L "$PACK_ROOT" ] || {
        show_error "Diretório de pacotes ausente ou inseguro:\n$PACK_ROOT"
        return 1
    }
}

prepare_document() {
    local preview token typed output text
    local -a args=(python3 -B "$DOCUMENT_PREPARER" "${CERTIFICATION_PACKS[@]}"
        --root "$KNOWLEDGE_ROOT" --package-dir "$PACKAGE_DIR")
    if ! preview=$("${args[@]}" 2>&1); then
        show_error "$preview"
        return 1
    fi
    token=$(printf '%s' "$preview" | jq -r '.confirmationToken // empty')
    [ -n "$token" ] || return 1
    text=$(printf '%s' "$preview" | jq -r '
        "Aplicação: \(.setupId)\nArquiteturas: \(.architectures | join(\", \"))\nDocumento: \(.documentPath)\nData verificada: \(.verifiedAt)\nPortas preservadas: \(.verifiedPorts | map(tostring) | join(\", \"))\nImagens por digest: \(.verifiedImages | length)\n\nToken editorial: \(.confirmationToken)"')
    message "PREPARAÇÃO EDITORIAL — DRY-RUN" \
        "$text\n\nNenhum arquivo foi alterado. Confira os dados antes de prosseguir."
    typed=$(whiptail --title "CONFIRMAR DOCUMENTAÇÃO" --inputbox \
        "Digite o token para marcar a cópia de trabalho como homologated. Isso ainda NÃO emite o selo:\n\n$token" \
        "$(dialog_height 15)" "$(dialog_width 92)" 3>&1 1>&2 2>&3) || return 130
    [ "$typed" = "$token" ] || {
        show_error "Token editorial divergente. Nenhuma alteração foi aplicada."
        return 1
    }
    if ! output=$("${args[@]}" --apply --confirm "$typed" 2>&1); then
        show_error "$output"
        return 1
    fi
    message "DOCUMENTAÇÃO PREPARADA" \
        "A cópia de trabalho foi atualizada e será submetida novamente a todos os gates durante a certificação.\n\nSelo oficial emitido: NÃO."
}

select_pack() {
    local pack label
    local -a entries=()
    while IFS= read -r pack; do
        [ -f "$pack" ] && [ ! -L "$pack" ] || continue
        label=$(basename "$pack")
        entries+=("$pack" "$label")
    done < <(find "$PACK_ROOT" -mindepth 1 -maxdepth 3 -type f -name '*-review-pack.tar.gz' -print 2>/dev/null | sort)
    if [ "${#entries[@]}" -eq 0 ]; then
        message "NENHUM PACOTE APROVADO" \
            "Nenhum review-pack foi encontrado em:\n$PACK_ROOT\n\nConclua primeiro a revisão humana no Homologation Runner."
        return 1
    fi
    whiptail --title "PACOTE DE REVISÃO" --menu \
        "Selecione uma arquitetura aprovada. Para setups multi-arquitetura, repita a seleção." \
        "$(dialog_height 24)" "$(dialog_width 108)" "$(( $(dialog_height 24) - 8 ))" \
        "${entries[@]}" 3>&1 1>&2 2>&3
}

collect_packs() {
    local selected
    CERTIFICATION_PACKS=()
    selected=$(select_pack) || return 130
    CERTIFICATION_PACKS+=(--pack "$selected")
    if whiptail --title "OUTRA ARQUITETURA" --yesno \
        "O setup declara uma segunda arquitetura e você possui outro review-pack aprovado?" \
        "$(dialog_height 13)" "$(dialog_width 86)" 1>&2; then
        selected=$(select_pack) || return 130
        [ "$selected" != "${CERTIFICATION_PACKS[1]}" ] || {
            show_error "O mesmo pacote não pode ser selecionado duas vezes."
            return 1
        }
        CERTIFICATION_PACKS+=(--pack "$selected")
    fi
}

run_certification() {
    local maintainer reason issued_at preview token typed output preview_text
    collect_packs || return 0
    prepare_document || return 0
    maintainer=$(whiptail --title "MANTENEDOR RESPONSÁVEL" --inputbox \
        "Informe um nome público entre 2 e 80 caracteres. Não use e-mail, hostname ou credencial." \
        "$(dialog_height 12)" "$(dialog_width 88)" 3>&1 1>&2 2>&3) || return 0
    reason=$(whiptail --title "JUSTIFICATIVA OFICIAL" --inputbox \
        "Explique em 3 a 240 caracteres por que as evidências autorizam o selo. Não informe dados do servidor." \
        "$(dialog_height 13)" "$(dialog_width 96)" 3>&1 1>&2 2>&3) || return 0
    issued_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    local -a base_args=(python3 -B "$CERTIFIER" "${CERTIFICATION_PACKS[@]}"
        --root "$KNOWLEDGE_ROOT" --catalog "$CATALOG" --package-dir "$PACKAGE_DIR"
        --maintainer "$maintainer" --reason "$reason" --issued-at "$issued_at")
    if [ "$RUNTIME_MODE" = "1" ]; then
        base_args+=(--runtime-release "$RUNTIME_RELEASE" --export-dir "$EXPORT_DIR")
    fi
    if ! preview=$("${base_args[@]}" 2>&1); then
        show_error "$preview"
        return 1
    fi
    token=$(printf '%s' "$preview" | jq -r '.confirmationToken // empty')
    [ -n "$token" ] || {
        show_error "O dry-run não retornou um token de confirmação."
        return 1
    }
    preview_text=$(printf '%s' "$preview" | jq -r '
        "Aplicação: \(.setupId)\nVersão: \(.setupVersion)\nArquiteturas: \(.architectures | join(", "))\nMaturidade alvo: \(.targetMaturity)\n\nGates:\n  Todas as arquiteturas: OK\n  Nove checks: OK\n  Artefatos atuais: OK\n  Documento homologated: OK\n  Pendências: nenhuma\n  Ledger: íntegro\n\nSelo previsto: \(.sealId)\nToken: \(.confirmationToken)"')
    message "DRY-RUN APROVADO" \
        "$preview_text\n\nNenhum arquivo foi alterado. Commit, tag e release NÃO serão criados automaticamente."
    typed=$(whiptail --title "CONFIRMAÇÃO HUMANA OBRIGATÓRIA" --inputbox \
        "Para emitir o selo e atualizar a governança em uma transação com rollback, digite exatamente o token:\n\n$token" \
        "$(dialog_height 15)" "$(dialog_width 88)" 3>&1 1>&2 2>&3) || return 0
    if [ "$typed" != "$token" ]; then
        show_error "Token divergente. Nenhuma alteração foi aplicada."
        return 1
    fi
    if ! output=$("${base_args[@]}" --apply --confirm "$typed" 2>&1); then
        show_error "$output\n\nA transação restaurou o estado anterior quando qualquer gate falhou."
        return 1
    fi
    message "SELO OFICIAL EMITIDO" \
        "$(printf '%s' "$output" | jq -r '"Aplicação: \(.setupId)\nSelo: \(.sealId)\nSHA-256: \(.sealSHA256)\nMaturidade: \(.targetMaturity)\nGovernança atualizada: \(.governanceUpdated)\nSelo oficial: \(.officialSeal)\nPacote exportável: \(.exportPath // \"não solicitado\")"')\n\nA emissão permanece na cópia de trabalho. Importe o pacote no repositório, revise o diff, execute os gates e publique a release pelo workflow de produção."
}

main_menu() {
    local choice
    while true; do
        choice=$(whiptail --title "SETUP MNO — ESTEIRA OFICIAL DO SELO" --menu \
            "Ferramenta do mantenedor PRO MASTER. Toda emissão exige preparação editorial, dry-run, cobertura completa, confirmação humana e rollback automático." \
            "$(dialog_height 19)" "$(dialog_width 102)" 7 \
            "CERTIFY" "Validar evidências e emitir selo oficial" \
            "ABOUT" "Entender a fronteira de confiança" \
            "EXIT" "Sair sem alterar a governança" \
            3>&1 1>&2 2>&3) || return 0
        case "$choice" in
            CERTIFY) run_certification || true ;;
            ABOUT)
                message "FRONTEIRA DE CONFIANÇA" \
                    "O Homologation Runner cria candidatos e decisões locais, sempre sem selo.\n\nA Esteira Oficial é exclusiva do PRO MASTER. Ela valida os nove checks, todas as arquiteturas, o registro autenticado da release, a documentação, o ledger e as pendências.\n\nSomente após dois dry-runs e tokens humanos ela prepara o documento e grava evidências, decisões, selo e governança de forma transacional.\n\nNo terminal remoto, o resultado vira um pacote exportável. Ela nunca cria commit, tag, release, deploy ou DNS."
                ;;
            EXIT) return 0 ;;
        esac
    done
}

if [ "${SETUPMNO_CERTIFICATION_WIZARD_SMOKE_TEST:-0}" = "1" ]; then
    printf 'setupmno-certification-wizard-ok\n'
    exit 0
fi

initialize_runtime_mode || {
    show_error "O workspace PRO MASTER não pôde ser inicializado com segurança."
    exit 2
}
validate_runtime || exit 2
main_menu

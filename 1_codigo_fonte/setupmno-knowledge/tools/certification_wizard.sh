#!/usr/bin/bash
set -Eeuo pipefail

# Assistente administrativo local. Não integra o runtime do cliente e não
# cria commit, tag, release ou publicação automaticamente.
umask 077

TOOLS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
KNOWLEDGE_ROOT="${SETUPMNO_CERTIFICATION_ROOT:-$(cd "$TOOLS_DIR/.." && pwd)}"
SOURCE_ROOT=$(cd "$KNOWLEDGE_ROOT/.." && pwd)
CERTIFIER="$TOOLS_DIR/certify_homologation.py"
CATALOG="${SETUPMNO_CERTIFICATION_CATALOG:-$SOURCE_ROOT/setupmno-control/catalog.json}"
PACKAGE_DIR="${SETUPMNO_CERTIFICATION_PACKAGE_DIR:-$SOURCE_ROOT/setupmno-control/homologation-package}"
PACK_ROOT="${SETUPMNO_CERTIFICATION_PACK_ROOT:-/root/setupmno-homologation-candidates}"

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
    for path in "$CERTIFIER" "$TOOLS_DIR/import_homologation_review.py" \
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
        "$(printf '%s' "$output" | jq -r '"Aplicação: \(.setupId)\nSelo: \(.sealId)\nSHA-256: \(.sealSHA256)\nMaturidade: \(.targetMaturity)\nGovernança atualizada: \(.governanceUpdated)\nSelo oficial: \(.officialSeal)"')\n\nA alteração permanece apenas no código-fonte local. Revise o diff, execute os gates e publique a release pelo workflow de produção."
}

main_menu() {
    local choice
    while true; do
        choice=$(whiptail --title "SETUP MNO — ESTEIRA OFICIAL DO SELO" --menu \
            "Ferramenta administrativa local. Toda emissão exige dry-run, cobertura completa, confirmação humana e rollback automático." \
            "$(dialog_height 19)" "$(dialog_width 102)" 7 \
            "CERTIFY" "Validar evidências e emitir selo oficial" \
            "ABOUT" "Entender a fronteira de confiança" \
            "EXIT" "Sair sem alterar a governança" \
            3>&1 1>&2 2>&3) || return 0
        case "$choice" in
            CERTIFY) run_certification || true ;;
            ABOUT)
                message "FRONTEIRA DE CONFIANÇA" \
                    "O Homologation Runner do cliente cria candidatos e decisões locais, sempre sem selo.\n\nEsta ferramenta existe somente no repositório do mantenedor. Ela valida os nove checks, todas as arquiteturas, os hashes do código vivo, a documentação, o ledger e as pendências.\n\nSomente após o dry-run e a digitação do token ela grava evidências, decisões, selo e governança de forma transacional.\n\nEla nunca cria commit, tag, release, deploy, DNS ou comando Docker."
                ;;
            EXIT) return 0 ;;
        esac
    done
}

if [ "${SETUPMNO_CERTIFICATION_WIZARD_SMOKE_TEST:-0}" = "1" ]; then
    printf 'setupmno-certification-wizard-ok\n'
    exit 0
fi

validate_runtime || exit 2
main_menu

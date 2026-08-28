#!/usr/bin/bash
set -Eeuo pipefail

LAB_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
EXECUTOR_IMAGE="${SETUPMNO_STRIX_EXECUTOR_IMAGE:-}"
CONTROL_PLAN="${SETUPMNO_CONTROL_PLAN:-}"
STATE_FILE="/root/SetupLowCodeMno/.control/strix-lab/latest.json"
MAX_ARCHIVE_BYTES=$((128 * 1024 * 1024))
container_name=""
temporary_dir=""

cleanup_strix_run() {
    local status=$?
    unset provider_key
    if [ -n "$container_name" ] &&
       [[ "$container_name" =~ ^setupmno-strix-[a-z0-9]{12,48}$ ]]; then
        docker rm -f "$container_name" >/dev/null 2>&1 || true
    fi
    if [ -n "$temporary_dir" ] &&
       [[ "$temporary_dir" == /tmp/setupmno-strix.* ]]; then
        rm -rf -- "$temporary_dir"
    fi
    return "$status"
}
trap cleanup_strix_run EXIT

fail_message() {
    whiptail --title "SRE-6 — DIAGNÓSTICO BLOQUEADO · BETA" --msgbox "$1" 15 82
    exit "${2:-1}"
}

for required_command in docker jq python3 whiptail sha256sum stat realpath date mktemp timeout openssl; do
    command -v "$required_command" >/dev/null 2>&1 || {
        printf 'SRE-6 BETA: dependência ausente: %s.\n' "$required_command" >&2
        exit 41
    }
done

python3 "$LAB_DIR/validate.py" lock >/dev/null || {
    printf 'SRE-6 BETA: manifesto upstream inválido; diagnóstico bloqueado.\n' >&2
    exit 41
}

if [ "${SETUPMNO_STRIX_SMOKE_TEST:-0}" = "1" ]; then
    printf 'setupmno-strix-lab-ready:isolated-executor:1.5.3\n'
    exit 0
fi

case "$CONTROL_PLAN" in
    pro|pro-master) ;;
    *) fail_message "O diagnóstico isolado SRE-6 está disponível somente nos planos PRO e PRO MASTER. Nenhum executor foi criado." 42 ;;
esac

[ -n "$EXECUTOR_IMAGE" ] ||
    fail_message "A imagem homologada do executor SRE-6 não foi vinculada ao Terminal Seguro. Atualize o Control Center antes de tentar novamente." 43
docker image inspect "$EXECUTOR_IMAGE" >/dev/null 2>&1 ||
    fail_message "A imagem homologada do executor SRE-6 não está disponível neste servidor. Sincronize novamente o Control Center." 43

if ! whiptail --title "SRE-6 — DIAGNÓSTICO ISOLADO · BETA" --yesno \
    "Executar uma análise autorizada sobre UM PACOTE-FONTE LOCAL?\n\nO arquivo será copiado para um contêiner descartável, sem root, sem mounts, sem Docker socket e com a raiz somente leitura. O executor não recebe domínio, IP, serviço ou acesso à produção.\n\nA análise usa uma LLM externa e permite saída ampla à internet nesta versão BETA. Use uma chave dedicada e revogável. Somente contagens sanitizadas válidas por 24 horas serão preservadas; nenhuma correção será aplicada.\n\nContinuar?" \
    22 88; then
    exit 0
fi

while true; do
    source_archive=$(whiptail --title "PACOTE-FONTE LOCAL · BETA" --inputbox \
        "Informe o caminho absoluto de um arquivo .zip, .tar.gz ou .tgz pertencente ao projeto autorizado.\n\nExemplo fictício: /tmp/meu-projeto.zip\n\nNão informe URL, domínio, IP, volume ou diretório da produção." \
        16 86 3>&1 1>&2 2>&3) || exit 0
    source_archive=$(realpath -e -- "$source_archive" 2>/dev/null || true)
    if [ -z "$source_archive" ] || [ ! -f "$source_archive" ] || [ -L "$source_archive" ]; then
        whiptail --title "ARQUIVO INVÁLIDO" --msgbox "Selecione um arquivo local regular, existente e sem link simbólico." 10 72
        continue
    fi
    case "$source_archive" in
        /root/*|/tmp/*) ;;
        *)
            whiptail --title "CAMINHO NÃO AUTORIZADO" --msgbox "Por segurança, o pacote-fonte deve estar em /root ou /tmp." 10 72
            continue
            ;;
    esac
    case "${source_archive,,}" in
        *.zip|*.tar.gz|*.tgz) ;;
        *)
            whiptail --title "FORMATO NÃO ACEITO" --msgbox "Use somente um pacote .zip, .tar.gz ou .tgz." 10 72
            continue
            ;;
    esac
    archive_bytes=$(stat -c '%s' "$source_archive" 2>/dev/null || printf '0')
    if ! [[ "$archive_bytes" =~ ^[0-9]+$ ]] || [ "$archive_bytes" -le 0 ] || [ "$archive_bytes" -gt "$MAX_ARCHIVE_BYTES" ]; then
        whiptail --title "TAMANHO NÃO ACEITO" --msgbox "O pacote deve ter entre 1 byte e 128 MB." 10 72
        continue
    fi
    if ! python3 - "$source_archive" <<'PY' >/dev/null 2>&1
import sys, tarfile, zipfile
p = sys.argv[1]
if not (zipfile.is_zipfile(p) or tarfile.is_tarfile(p)):
    raise SystemExit(1)
PY
    then
        whiptail --title "PACOTE INVÁLIDO" --msgbox "O conteúdo não corresponde a um ZIP ou TAR válido." 10 72
        continue
    fi
    break
done

provider_choice=$(whiptail --title "PROVEDOR DA ANÁLISE · BETA" --menu \
    "A chave será lida uma única vez pela entrada padrão do executor e nunca será gravada, exibida ou adicionada ao Docker. Prefira uma chave dedicada com limite de gasto." \
    16 86 2 \
    "OPENAI" "API compatível oficial da OpenAI" \
    "OPENROUTER" "OpenRouter com modelo escolhido pelo usuário" \
    3>&1 1>&2 2>&3) || exit 0
case "$provider_choice" in
    OPENAI) provider="openai"; default_model="gpt-5-mini" ;;
    OPENROUTER) provider="openrouter"; default_model="openai/gpt-oss-20b" ;;
    *) exit 0 ;;
esac

while true; do
    model=$(whiptail --title "MODELO DA LLM · BETA" --inputbox \
        "Informe o identificador exato do modelo. A qualidade e a consistência da análise dependem diretamente do modelo escolhido." \
        13 86 "$default_model" 3>&1 1>&2 2>&3) || exit 0
    [[ "$model" =~ ^[A-Za-z0-9][A-Za-z0-9._:/-]{2,159}$ ]] && break
    whiptail --title "MODELO INVÁLIDO" --msgbox "Use somente letras, números, ponto, dois-pontos, barra, hífen ou sublinhado." 10 76
done

while true; do
    max_duration=$(whiptail --title "LIMITE DE TEMPO" --inputbox \
        "Duração máxima em minutos (10 a 120). O contêiner será removido ao final ou no timeout." \
        12 78 "30" 3>&1 1>&2 2>&3) || exit 0
    [[ "$max_duration" =~ ^[0-9]+$ ]] && [ "$max_duration" -ge 10 ] && [ "$max_duration" -le 120 ] && break
done
while true; do
    max_turns=$(whiptail --title "LIMITE DE INTERAÇÕES" --inputbox \
        "Máximo de interações internas da análise (5 a 40)." 11 72 "20" \
        3>&1 1>&2 2>&3) || exit 0
    [[ "$max_turns" =~ ^[0-9]+$ ]] && [ "$max_turns" -ge 5 ] && [ "$max_turns" -le 40 ] && break
done
while true; do
    llm_budget=$(whiptail --title "LIMITE DE GASTO DA LLM" --inputbox \
        "Orçamento máximo declarado em USD (0 a 20). Confirme também os limites no próprio provedor." \
        12 78 "1" 3>&1 1>&2 2>&3) || exit 0
    [[ "$llm_budget" =~ ^([0-9]+)(\.[0-9]{1,2})?$ ]] &&
        awk -v value="$llm_budget" 'BEGIN { exit !(value >= 0 && value <= 20) }' && break
done

confirmation=$(whiptail --title "CONFIRMAÇÃO HUMANA OBRIGATÓRIA" --inputbox \
    "Digite exatamente AUTORIZO para confirmar:\n\n- somente o pacote-fonte selecionado;\n- uso da LLM externa e possível cobrança;\n- nenhuma correção, exploração da produção ou concessão de selo;\n- resultado BETA sujeito a falso positivo e revisão humana." \
    18 88 3>&1 1>&2 2>&3) || exit 0
[ "$confirmation" = "AUTORIZO" ] ||
    fail_message "A confirmação escrita não corresponde ao texto exigido. Nenhum executor foi criado." 44

provider_key=$(whiptail --title "CHAVE DEDICADA DA LLM" --passwordbox \
    "Cole uma chave dedicada e revogável. Ela será encaminhada uma única vez pela entrada padrão do contêiner e apagada da memória do shell após a inicialização. Ela não será salva no navegador, Docker Secret, ambiente, arquivo ou log." \
    16 88 3>&1 1>&2 2>&3) || exit 0
if [ "${#provider_key}" -lt 8 ] || [ "${#provider_key}" -gt 4096 ]; then
    fail_message "A chave informada está vazia ou fora do limite aceito. Nenhum executor foi iniciado." 45
fi

temporary_dir=$(mktemp -d /tmp/setupmno-strix.XXXXXX)
chmod 0700 "$temporary_dir"
authorization_id="strix-$(openssl rand -hex 10)"
container_name="setupmno-${authorization_id}"
issued_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
expires_at=$(date -u -d "+${max_duration} minutes" +%Y-%m-%dT%H:%M:%SZ)
target_sha=$(sha256sum "$source_archive" | awk '{print $1}')
authorization_file="$temporary_dir/authorization.json"
executor_archive="$temporary_dir/target.archive"
executor_output="$temporary_dir/executor.out"
report_file="$temporary_dir/report.json"

jq -n \
    --arg plan "$CONTROL_PLAN" \
    --arg authorizationID "$authorization_id" \
    --arg targetSHA256 "$target_sha" \
    --arg provider "$provider" \
    --arg model "$model" \
    --arg issuedAt "$issued_at" \
    --arg expiresAt "$expires_at" \
    --argjson duration "$max_duration" \
    --argjson turns "$max_turns" \
    --argjson budget "$llm_budget" \
    '{schemaVersion:1,contractVersion:"1.1.0",maturity:"beta",plan:$plan,
      authorizationID:$authorizationID,targetType:"source-archive",targetSHA256:$targetSHA256,
      provider:$provider,model:$model,issuedAt:$issuedAt,expiresAt:$expiresAt,
      maxDurationMinutes:$duration,maxTurns:$turns,
      limits:{cpu:1,memoryMB:2048,llmBudgetUSD:$budget},writtenPermission:true,
      automaticExecution:false,targetMutationAllowed:false,productionDockerSocketAllowed:false,
      productionRootMountAllowed:false,state:"approved"}' >"$authorization_file"
chmod 0644 "$authorization_file"
python3 "$LAB_DIR/validate.py" authorization "$authorization_file" >/dev/null ||
    fail_message "A autorização fechada falhou na validação. Nenhum executor foi criado." 46

# O diretório temporário permanece 0700 no host. As cópias internas recebem
# somente leitura pública porque o executor roda como UID 61000 e o docker cp
# preserva permissões; nenhuma delas contém a chave da LLM.
install -m 0644 "$source_archive" "$executor_archive" ||
    fail_message "Não foi possível preparar a cópia efêmera do pacote-fonte." 46

docker create \
    --name "$container_name" \
    --user 61000:61000 \
    --read-only \
    --cap-drop ALL \
    --security-opt no-new-privileges:true \
    --pids-limit 256 \
    --cpus 1 \
    --memory 2048m \
    --network bridge \
    --tmpfs /tmp:rw,nosuid,nodev,size=512m \
    --stop-timeout 5 \
    "$EXECUTOR_IMAGE" >/dev/null ||
    fail_message "O contêiner isolado não pôde ser criado. Nenhuma análise foi iniciada." 47

docker inspect "$container_name" | jq -e '.[0] |
    .Config.User == "61000:61000" and
    .HostConfig.Privileged == false and
    .HostConfig.ReadonlyRootfs == true and
    ((.HostConfig.CapDrop // []) | index("ALL") != null) and
    ((.HostConfig.SecurityOpt // []) | index("no-new-privileges:true") != null) and
    ((.HostConfig.Binds // []) | length == 0) and
    ((.Mounts // []) | length == 0) and
    (.HostConfig.NetworkMode == "default" or .HostConfig.NetworkMode == "bridge") and
    .HostConfig.PidsLimit == 256 and
    .HostConfig.Memory == 2147483648' >/dev/null ||
    fail_message "O gate de isolamento recusou a configuração do contêiner. Nenhuma análise foi iniciada." 48

docker cp "$executor_archive" "$container_name:/input/target.archive" >/dev/null ||
    fail_message "O pacote-fonte não pôde ser copiado para o contêiner descartável." 49
docker cp "$authorization_file" "$container_name:/input/authorization.json" >/dev/null ||
    fail_message "A autorização não pôde ser copiada para o contêiner descartável." 49

printf 'SRE-6 BETA: executor isolado iniciado. Aguarde até %s minuto(s).\n' "$max_duration"
set +e
printf '%s\n' "$provider_key" | timeout --signal=TERM --kill-after=10s \
    "${max_duration}m" docker start -a -i "$container_name" >"$executor_output" 2>&1
executor_status=${PIPESTATUS[1]}
set -e
unset provider_key

report_line=$(grep -F 'SETUPMNO_STRIX_REPORT:' "$executor_output" | tail -n1 || true)
if [ -z "$report_line" ]; then
    if [ "$executor_status" -eq 124 ] || [ "$executor_status" -eq 137 ]; then
        fail_message "O executor atingiu o limite de tempo e foi encerrado. Nenhum relatório bruto foi preservado e nenhuma correção foi aplicada." 50
    fi
    fail_message "O executor foi encerrado sem produzir um relatório sanitizado válido. Nenhuma saída bruta foi preservada." 50
fi
printf '%s\n' "${report_line#*SETUPMNO_STRIX_REPORT:}" >"$report_file"
chmod 0600 "$report_file"
python3 "$LAB_DIR/validate.py" report "$report_file" >/dev/null ||
    fail_message "O relatório retornado não passou pelo contrato fechado e foi descartado." 51

state_dir=$(dirname "$STATE_FILE")
[ ! -L "$state_dir" ] || fail_message "O diretório de estado do SRE-6 é inseguro." 52
mkdir -p "$state_dir"
chmod 0700 "$state_dir"
[ ! -e "$STATE_FILE" ] || { [ -f "$STATE_FILE" ] && [ ! -L "$STATE_FILE" ]; } ||
    fail_message "O estado anterior do SRE-6 é inseguro e não será sobrescrito." 52
state_tmp=$(mktemp "$state_dir/latest.json.tmp.XXXXXX")
chmod 0600 "$state_tmp"
install -m 0600 "$report_file" "$state_tmp"
mv -f "$state_tmp" "$STATE_FILE"

report_status=$(jq -r '.status' "$report_file")
critical=$(jq -r '.counts.critical' "$report_file")
high=$(jq -r '.counts.high' "$report_file")
medium=$(jq -r '.counts.medium' "$report_file")
low=$(jq -r '.counts.low' "$report_file")
info=$(jq -r '.counts.info' "$report_file")
report_expiry=$(jq -r '.expiresAt' "$report_file")
whiptail --title "SRE-6 — DIAGNÓSTICO CONCLUÍDO · BETA" --msgbox \
    "Relatório sanitizado criado.\n\nEstado: ${report_status}\nContagens: critical=${critical}, high=${high}, medium=${medium}, low=${low}, info=${info}\nVálido até: ${report_expiry}\n\nO contêiner descartável será removido. A chave e as evidências brutas não foram preservadas. Nenhuma correção, mudança, selo, publicação ou autorização de produção foi realizada.\n\nRevise as contagens manualmente: um achado BETA pode ser falso positivo." \
    20 88

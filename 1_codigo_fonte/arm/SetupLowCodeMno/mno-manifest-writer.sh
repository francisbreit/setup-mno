#!/usr/bin/bash
# ==============================================================================
# Setup MNO — Gravador Universal de Manifestos de Aplicações e Combos
# Persiste metadados em /root/SetupLowCodeMno/.control/manifests/<stack_name>.json
# Permite ao MNO Fleet Hub clonar e migrar com precisão cirúrgica.
# ==============================================================================
set -euo pipefail

MANIFEST_DIR="/root/SetupLowCodeMno/.control/manifests"
mkdir -p "$MANIFEST_DIR"

APP_NAME="${1:-}"
STACK_NAME="${2:-}"
COMBO_ID="${3:-}"
COMBO_NAME="${4:-}"
DB_ENGINE="${5:-none}" # postgres | mysql84 | sqlite | none
DB_NAME="${6:-}"
S3_BUCKET="${7:-}"
RABBITMQ_VHOST="${8:-}"
DOMAINS_STR="${9:-}" # lista separada por vírgula
VOLUMES_STR="${10:-}" # lista separada por vírgula

[ -n "$STACK_NAME" ] || exit 0

is_combo=false
[ -n "$COMBO_ID" ] && is_combo=true

jq -n \
  --arg app "$APP_NAME" \
  --arg stack "$STACK_NAME" \
  --argjson is_combo "$is_combo" \
  --arg combo_id "$COMBO_ID" \
  --arg combo_name "$COMBO_NAME" \
  --arg db_engine "$DB_ENGINE" \
  --arg db_name "$DB_NAME" \
  --arg s3_bucket "$S3_BUCKET" \
  --arg rabbitmq_vhost "$RABBITMQ_VHOST" \
  --arg domains_str "$DOMAINS_STR" \
  --arg volumes_str "$VOLUMES_STR" \
  --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  '{
    version: "1.0",
    appName: $app,
    stackName: $stack,
    updatedAt: $now,
    combo: {
      isCombo: $is_combo,
      comboId: (if $is_combo then $combo_id else null end),
      comboName: (if $is_combo then $combo_name else null end)
    },
    dependencies: {
      database: (if $db_engine != "none" and $db_name != "" then { engine: $db_engine, dbName: $db_name, shared: true } else null end),
      storage: (if $s3_bucket != "" then { engine: "minio", bucket: $s3_bucket, shared: true } else null end),
      rabbitmq: (if $rabbitmq_vhost != "" then { vhost: $rabbitmq_vhost, shared: true } else null end)
    },
    domains: ($domains_str | split(",") | map(select(length > 0))),
    volumes: ($volumes_str | split(",") | map(select(length > 0)))
  }' > "$MANIFEST_DIR/${STACK_NAME}.json"
chmod 644 "$MANIFEST_DIR/${STACK_NAME}.json"

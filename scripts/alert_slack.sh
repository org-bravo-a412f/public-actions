#!/usr/bin/env bash
set -euo pipefail

: "${SLACK_WEBHOOK_URL:?defina SLACK_WEBHOOK_URL}"

alert_slack() {
  local message="${1:-Notification}" payload code
  payload=$(jq -n --arg t "$message" '{text: $t}')
  code=$(curl -sS -m 30 -o /dev/null -w '%{http_code}' \
    -X POST -H 'Content-Type: application/json' \
    --data "$payload" "$SLACK_WEBHOOK_URL") || code=000
  case "$code" in
    2??) echo "alerta Slack entregue (HTTP $code)" ;;
    *)   echo "ERRO: Slack respondeu HTTP $code." >&2; return 1 ;;
  esac
}

alert_slack "${1:?mensagem obrigatoria}"

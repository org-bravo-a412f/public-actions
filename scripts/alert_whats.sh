#!/usr/bin/env bash
set -euo pipefail

: "${CALLMEBOT_PHONE:?defina CALLMEBOT_PHONE}"
: "${CALLMEBOT_APIKEY:?defina CALLMEBOT_APIKEY}"

alert_whats() {
  local message="$1" encoded code
  encoded=$(python3 -c 'import sys,urllib.parse;print(urllib.parse.quote(sys.argv[1]))' "$message")
  code=$(curl -sS -m 30 -o /dev/null -w '%{http_code}' \
    "https://api.callmebot.com/whatsapp.php?phone=${CALLMEBOT_PHONE}&text=${encoded}&apikey=${CALLMEBOT_APIKEY}") || code=000
  case "$code" in
    2??) echo "alerta entregue (HTTP $code)" ;;
    *)   echo "ERRO: CallMeBot respondeu HTTP $code." >&2; return 1 ;;
  esac
}

alert_whats "${1:?mensagem obrigatoria}"

#!/usr/bin/env bash
set -euo pipefail

: "${CALLMEBOT_PHONE:?defina CALLMEBOT_PHONE}"
: "${CALLMEBOT_APIKEY:?defina CALLMEBOT_APIKEY}"

alert_whats() {
  local message="$1" encoded body code
  encoded=$(python3 -c 'import sys,urllib.parse;print(urllib.parse.quote(sys.argv[1]))' "$message")
  body=$(curl -sS -m 30 -w $'\n%{http_code}' \
    "https://api.callmebot.com/whatsapp.php?phone=${CALLMEBOT_PHONE}&text=${encoded}&apikey=${CALLMEBOT_APIKEY}") || {
    echo "ERRO: CallMeBot inacessivel." >&2; return 1; }
  code=${body##*$'\n'}; body=${body%$'\n'*}
  if [ "$code" = "200" ] && printf '%s' "$body" | grep -qi 'message queued'; then
    echo "alerta entregue (HTTP $code)"
    return 0
  fi
  echo "ERRO: CallMeBot nao enfileirou a mensagem (HTTP $code)." >&2
  printf '%s' "$body" | sed -e 's/<[^>]*>//g' -e "s|${CALLMEBOT_PHONE}|***|g" \
    | tr -s '[:space:]' ' ' | cut -c1-200 | sed 's/^/       /' >&2
  return 1
}

alert_whats "${1:?mensagem obrigatoria}"

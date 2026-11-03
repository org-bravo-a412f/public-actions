#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

CHANNELS=()
[ -n "${CALLMEBOT_PHONE:-}" ] && [ -n "${CALLMEBOT_APIKEY:-}" ] && CHANNELS+=("./scripts/alert_whats.sh")
[ -n "${SLACK_WEBHOOK_URL:-}" ] && CHANNELS+=("./scripts/alert_slack.sh")
if [ "${#CHANNELS[@]}" -eq 0 ]; then
  echo "ERRO: nenhum canal de alerta configurado." >&2
  exit 1
fi

: "${STATE_REPO:?defina STATE_REPO}"
: "${STATE_TOKEN:?defina STATE_TOKEN}"
STATE_PATH="${STATE_PATH:-public-repos-snapshot.json}"
STATE_REF="${STATE_REF:-}"

case "$STATE_PATH" in
  *[!A-Za-z0-9._/-]*) echo "ERRO: STATE_PATH invalido." >&2; exit 1 ;;
esac

mask() { [ -n "${1:-}" ] && [ "${GITHUB_ACTIONS:-}" = "true" ] && echo "::add-mask::$1" || true; }

mask "$STATE_REPO"; mask "${STATE_REPO%%/*}"

export GH_TOKEN="$STATE_TOKEN"

gh_args=("repos/$STATE_REPO/contents/$STATE_PATH")
[ -n "$STATE_REF" ] && gh_args+=(--method GET -f "ref=$STATE_REF")
if ! state=$(gh api "${gh_args[@]}" 2>/dev/null); then
  echo "ERRO: nao consegui ler o baseline; abortando sem alertar." >&2
  exit 1
fi
baseline_json=$(printf '%s' "$state" | jq -r '.content' | tr -d '\n' | base64 -d)

printf '%s' "$baseline_json" | jq -e '
  ((.owners | type) == "object")
  and ((.owners | to_entries) | all(
        ((.value | type) == "array") and (.value | all(type == "string"))
      ))
' >/dev/null 2>&1 || { echo "ERRO: baseline com formato invalido." >&2; exit 1; }

mapfile -t OWNERS < <(printf '%s' "$baseline_json" | jq -r '.owners | keys[]')
[ "${#OWNERS[@]}" -gt 0 ] || { echo "ERRO: baseline sem owners." >&2; exit 1; }

for o in "${OWNERS[@]}"; do mask "$o"; mask "${o#*/}"; done
while IFS= read -r v; do mask "$v"; done < <(printf '%s' "$baseline_json" | jq -r '.owners[][]')

for o in "${OWNERS[@]}"; do
  case "$o" in
    users/*|orgs/*) : ;;
    *) echo "ERRO: chave sem prefixo users/ ou orgs/." >&2; exit 1 ;;
  esac
done

failed=0
n_users=0; n_orgs=0
for o in "${OWNERS[@]}"; do
  case "$o" in users/*) n_users=$((n_users + 1)) ;; orgs/*) n_orgs=$((n_orgs + 1)) ;; esac
done
baseline_total=$(printf '%s' "$baseline_json" | jq '[.owners[][]] | length')

echo "Vigiando ${#OWNERS[@]} conta(s): $n_users usuario(s), $n_orgs organizacao(oes)."
echo "Baseline aceita $baseline_total repositorio(s) publico(s)."

api() {
  local url="https://api.github.com/$1?per_page=100&page="
  local page=1 body code count
  while :; do
    body=$(curl -sS -w $'\n%{http_code}' -H 'Accept: application/vnd.github+json' "${url}${page}") || {
      echo "ERRO: transferencia falhou em $1 (curl saiu $?)" >&2; return 3; }
    code=${body##*$'\n'}; body=${body%$'\n'*}
    if [ "$code" = "403" ] || [ "$code" = "429" ]; then
      body=$(curl -sS -w $'\n%{http_code}' -H 'Accept: application/vnd.github+json' \
             -H "Authorization: Bearer ${GITHUB_TOKEN:-}" "${url}${page}") || {
        echo "ERRO: transferencia falhou no retry de $1 (curl saiu $?)" >&2; return 3; }
      code=${body##*$'\n'}; body=${body%$'\n'*}
    fi
    case "$code" in
      200) : ;;
      404) echo "ERRO: owner nao encontrado: $1 (HTTP 404)" >&2; return 2 ;;
      *)   echo "ERRO: GET $1 retornou HTTP $code" >&2; return 3 ;;
    esac
    count=$(printf '%s' "$body" | jq 'if type == "array" then length else error("nao e lista") end' 2>/dev/null) || {
      echo "ERRO: resposta invalida em $1" >&2; return 3; }
    printf '%s' "$body" | jq -r '.[] | select(.private == false and ((.visibility // "public") == "public")) | .full_name'
    [ "$count" -lt 100 ] && break
    page=$((page + 1))
  done
}

current=$(mktemp); out=$(mktemp)
listed_ok=0; idx=0
for owner in "${OWNERS[@]}"; do
  idx=$((idx + 1))
  if api "$owner/repos" > "$out"; then
    listed_ok=$((listed_ok + 1))
    cat "$out" >> "$current"
    echo "  conta $idx/${#OWNERS[@]}: $(grep -c . "$out") repositorio(s) publico(s)"
  else
    rc=$?
    if [ "$rc" -eq 2 ]; then
      echo "  conta $idx/${#OWNERS[@]}: NAO ENCONTRADA (HTTP 404)"
      failed=1
    else
      echo "ERRO: falha ao consultar a API; abortando sem alertar." >&2
      exit 1
    fi
  fi
done
sort -u -o "$current" "$current"

echo "Total: $listed_ok/${#OWNERS[@]} conta(s) consultada(s), $(grep -c . "$current") repositorio(s) publico(s) encontrado(s), $baseline_total no baseline."

if [ "$listed_ok" -eq 0 ]; then
  echo "ERRO: nenhum owner respondeu; abortando sem alertar." >&2
  exit 1
fi

known=$(mktemp)
printf '%s' "$baseline_json" | jq -r '.owners | to_entries[] | .value[]' | sort -u > "$known"
new_repos=$(comm -13 "$known" "$current")

if [ -z "$new_repos" ]; then
  echo "OK: nenhum repositorio publico novo."
  exit "$failed"
fi

msg="ALERTA GitHub: repositorio(s) PUBLICO(S) novo(s) detectado(s):"
while IFS= read -r repo; do
  [ -z "$repo" ] && continue
  mask "$repo"; mask "${repo#*/}"
  msg="$msg"$'\n'"- https://github.com/$repo"
done <<< "$new_repos"

echo "ATENCAO: $(printf '%s\n' "$new_repos" | grep -c .) repositorio(s) publico(s) novo(s) detectado(s)."
echo "$new_repos"

delivered=0
for channel in "${CHANNELS[@]}"; do
  if "$channel" "$msg"; then delivered=$((delivered + 1)); fi
done
if [ "$delivered" -eq 0 ]; then
  echo "ERRO: alerta NAO entregue por nenhum canal." >&2
  exit 1
fi

echo "Para parar o alerta: torne o repositorio privado, ou inclua-o no baseline em STATE_REPO."
exit "$failed"

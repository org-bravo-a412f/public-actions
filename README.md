# public-repo-watch

Avisa quando aparece um repositorio publico fora do baseline.

O baseline fica em outro repositorio, apontado pelo secret `STATE_REPO`.

## Secrets

| Secret | Conteudo |
|---|---|
| `STATE_REPO` | `owner/repo` com o baseline |
| `STATE_TOKEN` | PAT fine-grained, Contents: read em `STATE_REPO` |
| `CALLMEBOT_PHONE` / `CALLMEBOT_APIKEY` | canal WhatsApp |
| `SLACK_WEBHOOK_URL` | canal Slack |

Pelo menos um canal de alerta e obrigatorio.

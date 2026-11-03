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

## Codigo de saida

Vermelho significa **monitor quebrado**, nao exposicao encontrada.

| Situacao | Saida |
|---|---|
| Nada novo | 0 |
| Repo publico novo, alerta entregue em algum canal | 0 |
| Repo publico novo, nenhum canal entregou | 1 |
| Baseline ilegivel ou invalido, API falhando, conta inexistente | 1 |

Assim um job vermelho e sinal confiavel de que o vigia caiu, e vale ligar
e-mail de falha de workflow nas notificacoes do GitHub.

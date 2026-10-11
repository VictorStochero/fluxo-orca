---
name: limites-cota
description: Use antes de despachar uma onda de workers ou quando perguntarem sobre cota, limite, pool de agentes, vagas por conta ou quem deve ser o escritor — mede o uso das contas instaladas, alerta acima de 80% e consulta vaga-agente.sh livres e limites.sh --escritor.
---

# Revisão de limite das contas

`bash ~/.cache/limites.sh` (instalado e atualizado pelo hook de SessionStart do plugin) mede em paralelo, uma linha por fornecedor, e **sai com 3 se algum passar de 80%**. Fornecedor não instalado é pulado:

| Linha | Origem | Pula quando |
|---|---|---|
| `pessoal` | `claude -p "/usage"` (conta principal) | nunca |
| `team` | conta secundária em `CLAUDE_CONFIG_DIR=~/.claude-team` | pasta não existe |
| `agy Gemini` / `agy Claude` | `agy -p "/usage"`, janelas 5h e semana | `agy` fora do PATH |
| `kimi` | API do Kimi Code (`kimi-cota.sh`), janela 5h e mês | sem credencial em `~/.kimi-code/credentials/` |
| `codex` | app-server local do Codex (`codex-cota.sh`, `account/rateLimits/read`), janela 5h e semana | `codex` fora do PATH |

- **Antes de cada onda de workers**: rodar; fornecedor acima de 80% sai da vez.
- **Escritor**: o script termina com `escritor: <team|pessoal|codex|kimi> (<folga>% livre)` — o candidato com vaga no pool e mais folga (100 − o pior entre sessão/5h e semana; no Kimi, o pior entre 5h e `semana-eq`, a cota mensal convertida a 25% por semana do ciclo; acima de 80% fica de fora). `limites.sh --escritor` imprime só essa linha; pool cheio imprime `escritor: nenhum (pool cheio)` e sai com 75. Medir antes de cada designação.
- **Pool da máquina**: `vaga-agente.sh pega <conta> <dispatch_id>`, `solta <dispatch_id>` e `livres`. Padrão: team=1, codex=1, kimi=1, agy=1 e pessoal=0 (ilimitado, `0/0`, sem trava). Configuração opcional: linhas `conta=N` em `~/.claude/agentes.conf`. Recuperação somente por estado terminal do dispatch ou `dispatch_not_found` confirmado pelo Orca; erro de conexão conserva a vaga. Fluxo de reserva/liberação na skill `delegacao`.
- **Segunda opinião e mecânico** (agy Gemini / Kimi → agy Claude, só pontual) seguem a ordem: agy Gemini / Kimi → agy Claude.
- Revisão obrigatória continua em Opus mesmo com cota apertada: espera a janela zerar em vez de rebaixar o modelo.
- Ao relatar ao usuário: a saída do script como tabela (fornecedor · janela · uso · zera às), sem reformular números.
- Linha `ilegível`: o `/usage` mudou de formato ou a conta não está logada — dizer, não estimar.

## Responder ao usuário

- `bash ~/.cache/limites.sh` — uso por fornecedor e janela, horário de renovação e escritor escolhido; exit 3 indica algum uso acima de 80%. Apresentar os números como tabela, sem estimar linhas ilegíveis.
- `bash ~/.cache/vaga-agente.sh livres` — cada linha traz `conta livres/total`; `0/0` significa ilimitado. A consulta pode recuperar vagas de dispatches encerrados; falha de conexão conserva a vaga. A lista do pool não comprova que o fornecedor está instalado.
- `bash ~/.cache/limites.sh --escritor` — escolhe entre team, pessoal, Codex e Kimi pela maior folga com vaga; ausentes e uso acima de 80% ficam de fora. Exit 75 indica pool cheio; `todos acima de 80% ou ausentes` distingue falta de cota de falta de vaga.

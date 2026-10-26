---
name: limites-cota
description: Use antes de despachar uma onda de workers ou quando perguntarem sobre cota, limite, pool de agentes, vagas por conta, contas da máquina (agentes.conf) ou quem deve ser o escritor — mede o uso de cada conta do registro, alerta acima de 80% e consulta vaga-agente.sh livres e limites.sh --escritor.
---

# Revisão de limite das contas

## Registro de contas
As contas da máquina vêm de `~/.claude/agentes.conf` sobre o catálogo do plugin (`agentes-catalogo.conf`: os 45 agentes da tela do Orca, com comando, argumentos e medidor). Uma conta por linha, `nome chave=valor ...`; a ordem das linhas é a prioridade:

```
escolha=ritmo
pessoal  agente=claude papeis=orquestra
team     agente=claude config=~/.claude-team vagas=1 papeis=escritor,revisor
claude-b agente=claude comando=claude-b config=~/.claude-b vagas=1 papeis=escritor,revisor
codex    agente=codex vagas=1 modelo=gpt-6.1-sol
kimi     agente=kimi vagas=1
minimax  agente=opencode modelo="minimax/MiniMax-M2" vagas=1 medidor=orca:minimax
```

- Chaves: `agente` (chave do catálogo, obrigatória), `config` (pasta `CLAUDE_CONFIG_DIR` de uma conta Claude), `comando`, `args`, `modelo`, `vagas` (0 = ilimitado), `papeis` (`escritor revisor verificador mecanico segunda-opiniao orquestra`; padrão `escritor,revisor,verificador,mecanico`; `orquestra` sozinho = medida, nunca escolhida), `medidor` (`claude`, `orca:<fornecedor>` ou `-`).
- Contas Claude pessoais: quantas o dev tiver, cada uma com a sua pasta de config (mesmo layout da `~/.claude-team`, fase 4b do GUIA).
- Sem linha de conta no arquivo, valem as padrão: `team` (`~/.claude-team`, 1 vaga), `pessoal` (ilimitada), `codex` (1), `agy` (1, só segunda opinião) e `claude-b` (`~/.claude-b`, só medida, se a pasta existir). Linhas `conta=N` mudam só as vagas.
- `bash ~/.cache/contas.sh lista` mostra o registro efetivo; `contas.sh lanca <conta> <papel> [modelo]` imprime o comando para `orca-libera.sh --cria --command` (Claude ganha `--agent fluxo-orca:<papel>`, ou `--agent <plugin:agente>` quando o papel já vem assim, ex.: `auditoria-pre-subida:auditor`).
- `comando` de conta Claude tem de ser um executável no PATH (script), não função do `.bashrc`: a medição usa o `claude` com a pasta de config, mas o terminal do worker roda o `comando`.
- Kimi e MiniMax: no catálogo e medidos pelo Orca, **não testados com conta real**. MiniMax não tem agente próprio no Orca: conta pelo `opencode` ou pelo `claude` com `ANTHROPIC_BASE_URL`.

## Medição
`bash ~/.cache/limites.sh` (instalado e atualizado pelo hook de SessionStart do plugin) mede em paralelo cada conta do registro, uma linha por conta, e **sai com 3 se algum limite passar de 80%**. Conta cujo comando não está no PATH, ou cuja pasta de config não existe, é pulada:

| Medidor | Origem | Contas |
|---|---|---|
| `claude` | `claude -p "/usage"` com `CLAUDE_CONFIG_DIR` da conta (sem ela, a principal); sessão e semana | contas Claude |
| `orca:<fornecedor>` | `rateLimits.<fornecedor>` do `orca account list --json`, uma consulta por execução; janela curta e semana (ou mês) | `codex`, `antigravity` (uma linha por grupo de modelos; a conta vale pelo pior grupo), `kimi`, `minimax`, `cursor`, `grok`, `zcode`, `gemini`, `opencodeGo` |
| `-` | sem medição: só vagas | os demais agentes |

## Escolha do escritor
- Candidatas: contas com papel `escritor`, instaladas e com vaga no pool.
- Medida elegível = janela curta ≤ 80 e longa ≤ 80, ou ≤ 95 quando o reset da longa é em menos de 24 h. Ritmo = (100 − uso da longa) ÷ (100 × fração restante da longa); fração = horas até o reset ÷ duração da janela (semana 168 h, mês pelo Orca), limitada a [0,01, 1]; reset ilegível vira fração 1.
- `escolha=ritmo` (padrão): vence o maior ritmo entre as medidas (empate na ordem do registro); sem medida elegível, a primeira sem medidor na ordem do registro. `escolha=ordem`: a primeira linha elegível do registro, com o medidor só tirando da vez quem passou do teto.
- Saída: `escritor: <conta> (ritmo X.X · N% livre, zera em Hh)` ou `escritor: <conta> (sem medidor)`. `limites.sh --escritor` imprime só essa linha; pool cheio imprime `escritor: nenhum (pool cheio)` e sai com 75; `todos acima do teto ou ausentes` distingue falta de cota de falta de vaga. Medir antes de cada designação.

## Pool
`vaga-agente.sh pega <conta> <dispatch_id>`, `solta <dispatch_id>`, `troca <provisório> <dispatch_id>` e `livres`, com as vagas do registro. Recuperação somente por estado terminal do dispatch ou `dispatch_not_found` confirmado pelo Orca; erro de conexão conserva a vaga. Dono provisório (`res-<tag>`) não é consultado no Orca: reserva esquecida expira em `POOL_RESERVA_TTL` s (padrão 600). `solta` e `troca` acham a vaga mesmo de conta que saiu do registro. Fluxo de reserva/liberação na skill `delegacao`.

- **Antes de cada onda de workers**: rodar; conta acima de 80% sai da vez.
- Revisão obrigatória continua em Opus mesmo com cota apertada: espera a janela zerar em vez de rebaixar o modelo.
- Linha `ilegível (...)`: o `/usage` mudou de formato, a conta não está logada ou o Orca não tem a cota do fornecedor — dizer o motivo da linha, não estimar.

## Responder ao usuário
- `bash ~/.cache/limites.sh` — uso por conta e janela, horário de renovação e escritor escolhido; exit 3 indica algum uso acima de 80%. Apresentar como tabela (conta · janela · uso · zera às), sem reformular números.
- `bash ~/.cache/vaga-agente.sh livres` — `conta livres/total`; `0/0` = ilimitado. Não comprova que a conta está instalada.
- `bash ~/.cache/limites.sh --escritor [--reserva <tag>]` — a escolha acima; `--reserva` já reserva a vaga do escolhido (dono provisório `res-<tag>`, anexado à linha como `reserva res-<tag>`).
- `bash ~/.cache/limites.sh --alerta` — só as linhas de conta com alguma janela acima de 80%, exit 3; nada acima, nada impresso e exit 0. O `orca-espera.sh` usa para avisar antes de estourar.

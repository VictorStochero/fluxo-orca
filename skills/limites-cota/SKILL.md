---
name: limites-cota
description: Use antes de despachar uma onda de workers ou quando perguntarem sobre cota, limite, pool de agentes, vagas por conta, contas da máquina (agentes.conf) ou quem deve ser o escritor — mede o uso de cada conta do registro, alerta acima de 80% e consulta vaga-agente.sh livres e limites.sh --escritor.
---

# Revisão de limite das contas

## Registro de contas
As contas da máquina vêm de `~/.claude/agentes.conf` sobre o catálogo do plugin (`agentes-catalogo.conf`: os 45 agentes da tela do Orca, com comando, argumentos e medidor). Uma conta por linha, `nome chave=valor ...`; a ordem das linhas é a prioridade:

```
escolha=ritmo
teto=4
pessoal  agente=claude peso=5 papeis=orquestra,revisor,verificador
team     agente=claude config=~/.claude-team vagas=1 papeis=escritor,revisor
claude-b agente=claude comando=claude-b config=~/.claude-b vagas=1 papeis=escritor,revisor
codex    agente=codex vagas=1 modelo=gpt-6.1-sol
kimi     agente=kimi vagas=1
minimax  agente=opencode modelo="minimax/MiniMax-M2" vagas=1 medidor=orca:minimax papeis=escritor
# kimi sem papeis: só medido; minimax escreve porque o dev instalou as regras e a trava no opencode (GUIA 4b).
```

- Chaves: `agente` (chave do catálogo, obrigatória), `config` (pasta `CLAUDE_CONFIG_DIR` de uma conta Claude), `comando`, `args`, `modelo`, `vagas` (0 = ilimitado), `papeis` (`escritor revisor verificador mecanico segunda-opiniao orquestra`; padrão `escritor,revisor,verificador,mecanico` só para `claude`, `codex` e `antigravity`, que têm a trava de comando remoto; os demais agentes nascem sem papel — só medição e fora do pool — e só trabalham com `papeis=` escrito, se o catálogo lhes dá `pre=sim` e `testado=<data>` (ver "Capacidades por agente") e depois de instaladas neles as regras e a trava (`instala-agente.sh`, fase 4b do GUIA); vazio ou só `orquestra` = medida, nunca escolhida), `medidor` (`claude`, `orca:<fornecedor>` ou `-`).
- Contas Claude pessoais: quantas o dev tiver, cada uma com a sua pasta de config (mesmo layout da `~/.claude-team`, fase 4b do GUIA).
- `peso=<inteiro ≥ 1>` por conta (padrão 1): multiplica o ritmo; a saída mostra o peso quando diferente de 1. `escolha=ordem` ignora. `teto=<inteiro ≥ 0>` é uma linha global (padrão 0, ilimitado) e limita workers de todas as contas, inclusive `vagas=0`.
- A conta principal pode revisar/verificar; só `papeis=orquestra` continua fora do pool. Escritor Claude recebe `--advisor opus`; `CONTAS_ADVISOR` troca o modelo e vazio desliga. Papéis Claude só leitura sempre usam `--settings ~/.claude/agents/somente-leitura.json`, sem MCP de navegador.
- Sem linha de conta no arquivo, valem as padrão: `team` (`~/.claude-team`, 1 vaga), `pessoal` (ilimitada), `codex` (1), `agy` (1, só segunda opinião) e `claude-b` (`~/.claude-b`, só medida, se a pasta existir). Linhas `conta=N` mudam só as vagas.
- `bash ~/.cache/contas.sh lista` mostra o registro efetivo; `contas.sh lanca <conta> <papel> [modelo]` imprime o comando para `orca-libera.sh --cria --command` (Claude ganha `--agent fluxo-orca:<papel>`, ou `--agent <plugin:agente>` quando o papel já vem assim, ex.: `auditoria-pre-subida:auditor`).
- `comando` de conta Claude tem de ser um executável no PATH (script), não função do `.bashrc`: a medição usa o `claude` com a pasta de config, mas o terminal do worker roda o `comando`.
- Kimi e MiniMax: no catálogo e medidos pelo Orca, **não testados com conta real**. MiniMax não tem agente próprio no Orca: conta pelo `opencode` ou pelo `claude` com `ANTHROPIC_BASE_URL`.

### Capacidades por agente (colunas do catálogo)
`chave|id|comando|args|medidor|pre|fim|regras|skills|testado|nota` — `pre`/`fim` (`sim|nao|-`): o agente tem hook antes de comando (trava `guarda-externos.sh`) e hook de fim de turno (`fim-worker.sh`); `regras`: arquivo global de regras; `skills`: diretório de skills; `testado`: data da prova de despacho (GUIA, fase 4b) ou `-`. As capacidades vêm das docs oficiais (URLs no cabeçalho do catálogo), não de execução.
- **Papel de trabalho** (`escritor`, `mecanico`, `revisor`, `verificador`) só em conta de agente com `pre=sim` **e** `testado=<data>`; claude, codex e antigravity (trava provada) são isentos do `testado`. Sem `pre=sim` o registro é recusado (`<agente> sem trava de comando: só segunda-opiniao`); com `pre=sim` e `testado=-` também (`<agente>: trava só documentada, rode a prova do GUIA fase 4b e registre testado=<data>`): a trava de um agente novo vem só da documentação, e liberar trabalho sem prova deixaria ssh/forge sem bloqueio. Agente com `pre=sim` e `fim=nao` entra, com aviso (`contas.sh lista`, stderr do `limites.sh`): sem hook de fim de turno, o `orca-espera.sh` é quem cobra o `worker_done`.
- `bash skills/limites-cota/instala-agente.sh <agente> [--aplicar]` (do plugin ou do clone): mostra e, com `--aplicar`, grava regras (`extras/AGENTS.global.md` num bloco `fluxo-orca:inicio…fim`), skills (ou índice nas regras), trava e fim-worker no formato do agente; idempotente. Formatos de `guarda-externos.sh`: `codex`, `agy`, `gemini` (JSON `deny`), `exit2` (Kimi, ZCode e o plugin `extras/opencode-guarda.js` do opencode). Sem hook (ex.: cursor-agent), só as regras: o agente fica em segunda opinião.
- Mapa (docs oficiais; **nada disso foi executado aqui exceto codex e agy**): gemini `BeforeTool`+`AfterAgent` em `~/.gemini/settings.json`; kimi `PreToolUse`+`Stop` em `~/.kimi-code/config.toml`; zcode `PreToolUse` em `~/.zcode/cli/config.json` com `hooks.enabled`; opencode plugin `tool.execute.before` em `~/.config/opencode/plugins/`; cursor-agent: hooks documentados só para o app (`pre=nao`).

## Medição
`bash ~/.cache/limites.sh` (instalado e atualizado pelo hook de SessionStart do plugin) mede em paralelo cada conta do registro, uma linha por conta, e **sai com 3 se algum limite passar de 80%**. Conta cujo comando não está no PATH, ou cuja pasta de config não existe, é pulada; conta Claude é conferida pelo `claude` e pela pasta de config, não pelo `comando` dela:

| Medidor | Origem | Contas |
|---|---|---|
| `claude` | `claude -p "/usage"` com `CLAUDE_CONFIG_DIR` da conta (sem ela, a principal); sessão e semana | contas Claude |
| `orca:<fornecedor>` | `rateLimits.<fornecedor>` do `orca account list --json`, uma consulta por execução; janela curta e semana (ou mês) | `codex`, `antigravity` (uma linha por grupo de modelos; a conta vale pelo pior grupo), `kimi`, `minimax`, `cursor`, `grok`, `zcode`, `gemini`, `opencodeGo` |
| `-` | sem medição: só vagas | os demais agentes |

## Escolha do escritor
- Cache de medição por conta em `~/.cache/agentes/medida.<conta>`: `LIMITES_CACHE_MIN` minutos (padrão 5; 0 desliga); saída ilegível não entra no cache. Reserva e alerta reaproveitam esse cache; `ORCA_ESPERA_COTA_MIN` tem padrão 20 minutos.
- Candidatas: contas com papel `escritor`, instaladas e com vaga no pool.
- Medida elegível = janela curta ≤ 80 e longa ≤ 80, ou ≤ 95 quando o reset da longa é em menos de 24 h. Ritmo = (100 − uso da longa) ÷ (100 × fração restante da longa); fração = horas até o reset ÷ duração da janela (semana 168 h, mês pelo Orca), limitada a [0,01, 1]; reset ilegível vira fração 1.
- `escolha=ritmo` (padrão): vence o maior ritmo multiplicado pelo `peso` da conta (empate na ordem do registro); sem medida elegível, a primeira sem medidor na ordem do registro. `escolha=ordem`: a primeira linha elegível do registro, ignorando peso, com o medidor só tirando da vez quem passou do teto.
- Saída: `escritor: <conta> (ritmo X.X · N% livre, zera em Hh)` ou `escritor: <conta> (sem medidor)`. `limites.sh --escritor` imprime só essa linha; pool cheio imprime `escritor: nenhum (pool cheio)` e sai com 75; `todos acima do teto ou ausentes` distingue falta de cota de falta de vaga. Medir antes de cada designação.

## Pool
Com `teto>0`, a reserva conta todas as vagas e sai 75 com `POOL CHEIO: teto da máquina (N)` quando atinge o limite. Conta com `vagas=0` cria trava para participar da contagem; com `teto=0` mantém o comportamento sem trava. `livres` inclui `maquina <livres>/<teto>` só com teto ativo: essa linha resume a máquina e não é uma conta.
`vaga-agente.sh pega <conta> <dispatch_id>`, `solta <dispatch_id>`, `troca <provisório> <dispatch_id>` e `livres`, com as vagas do registro. Recuperação somente por estado terminal do dispatch ou `dispatch_not_found` confirmado pelo Orca; erro de conexão conserva a vaga. Dono provisório (`res-<tag>`) não é consultado no Orca: reserva esquecida expira em `POOL_RESERVA_TTL` s (padrão 600). `solta` e `troca` acham a vaga mesmo de conta que saiu do registro. Fluxo de reserva/liberação na skill `delegacao`.

- **Antes de cada onda de workers**: rodar; conta acima de 80% sai da vez.
- Revisão obrigatória continua em Opus mesmo com cota apertada: espera a janela zerar em vez de rebaixar o modelo.
- Linha `ilegível (...)`: o `/usage` mudou de formato, a conta não está logada ou o Orca não tem a cota do fornecedor — dizer o motivo da linha, não estimar.

## Responder ao usuário
- `bash ~/.cache/limites.sh` — uso por conta e janela, horário de renovação e escritor escolhido; exit 3 indica algum uso acima de 80%. Apresentar como tabela (conta · janela · uso · zera às), sem reformular números.
- `bash ~/.cache/vaga-agente.sh livres` — `conta livres/total`; `0/0` = ilimitado por conta, ainda sujeito ao teto da máquina, cuja linha é `maquina livres/teto`. Não comprova que a conta está instalada.
- `bash ~/.cache/limites.sh --escritor [--reserva <tag>]` — a escolha acima; `--reserva` já reserva a vaga do escolhido (dono provisório `res-<tag>`, anexado à linha como `reserva res-<tag>`).
- `bash ~/.cache/limites.sh --alerta` — só as linhas de conta com alguma janela acima de 80%, exit 3; nada acima, nada impresso e exit 0. O `orca-espera.sh` usa para avisar antes de estourar.

## Segunda opinião
`bash ~/.cache/limites.sh --segunda [--familia <claude|gpt|gemini>]` escolhe entre contas com `segunda-opiniao` e Codex quando o escritor não é GPT, respeitando vagas e o mesmo teto de cota do escritor. A preferência é Gemini do agy, grupo misto do agy, depois Codex. Com escritor Claude, o grupo misto usa GPT; com escritor GPT, usa Claude; com escritor Gemini, o grupo Gemini fica fora.

Os grupos em `#grupo <conta> <grupo-slug> <curta%> <longa%> <reset_epoch|-> <duração_h>` valem separadamente: o pior `#cand` continua no alerta/escritor e não exclui o Gemini livre da segunda opinião. Saída: `segunda: agy gemini-models modelo=gemini-4-argon-high (90% livre, zera em 168h)`, ou `segunda: nenhuma (cota)` com exit 75. IDs conferidos em `agy models`: `gemini-4-argon-high`, `claude-opus-5-5-high` e `gpt-oss-120b-medium`; Codex sugere `gpt-6.1-sol` ou `modelo=` da conta.

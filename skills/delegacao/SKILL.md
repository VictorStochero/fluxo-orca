---
name: delegacao
description: Use antes de despachar qualquer agente (escritor, revisor, levantamento) ou provisionar worktree para tarefa — despacho via Orca orchestration, modelos por papel, ordem de consumo de cota, regras de dispatch, processo tarefa = worktree = worker = PR, gate de revisão e merge.
---

# Delegação — via Orca orchestration

**Trabalho é worker do Orca** (decisão do usuário): escritor, revisor, auditor, verificador e segunda opinião — visível, com `ask` e `worker_done`. **Consulta curta read-only** (Explore, documentação, claude-code-guide, Plan) segue no Agent tool. `claude -p` / `agy -p` não despacham. Imposto pelo hook `despacho-orca.sh` do plugin. Antes do primeiro comando da sessão: invocar o skill `orchestration` e rodar `orca skills get orchestration` (guia da versão instalada); referências sob demanda com `--reference references/<arquivo>.md`.

## Loop do coordenador (sessão principal)
```text
orca status --json
orca orchestration run-create --objective "<objetivo>" --json
orca orchestration worker-start --spec "<prompt autossuficiente>" --worktree <current|new-child|path:...> --agent <claude|antigravity|opencode> --model <id> --effort <nível> --json
orca orchestration check --wait --types "worker_done,escalation,question" --timeout-ms 900000 --json
```
- Disparar a onda independente inteira antes de esperar. Dependência real → `task-create` + `worker-start --task`; ondas paralelas em vez de cadeias longas.
- `worker-start` com saída diferente de zero: **não relançar** — ler `failedStage`/`residualResources` e carregar `references/recovery-and-cleanup.md`.
- Toda mensagem processada: `question` → responder (decisão do usuário vai a ele por `AskUserQuestion` e a resposta volta ao worker); `worker_done` → validar contra o esperado, depois verificar (abaixo); worker parado → reaproveitar, reter ou liberar explicitamente.
- Ler saída: `worker-read --source auto`. Redirecionar: `send --to dispatch:<id>`.

## Modelos por papel
| Papel | Worker | `--model` / `--effort` |
|---|---|---|
| Revisão de todo diff que vai para merge e verificador adversarial (gate read-only, contexto recortado) | `claude` | Opus 5.5 / `high` |
| Implementação: escritor (código, testes, build, browser) | `claude` | Sonnet 5.5 / `medium` (nunca `low`) |
| Levantamento, censo, contagem, mapear uso (consulta read-only) | Agent tool `Explore` | Haiku 5.5 / `medium` |
| Mecânico conferível (fixtures, edição com `old_string` literal, mover por mapa) | `claude` | Haiku 5.5 / `low` |
| Segunda opinião (read-only): revisão adversarial complementar, contraprova de diagnóstico | `antigravity` | Gemini; Claude/GPT só com folga de cota |

- **agy (`antigravity`) é só segunda opinião, read-only**. Nunca escritor, levantamento ou mecânico; nunca substitui a revisão Opus obrigatória. Pacote recortado (diff + pergunta), resposta conferida pela sessão principal.

- **Orquestrador é a sessão principal**, não um agente à parte. Mudança pequena e localizada (um arquivo, poucas linhas, sem decisão de arquitetura) ela faz direto, roda os testes, e o revisor continua obrigatório antes do merge; etapa com volume ou frentes paralelas vão para escritor.
- **Papéis = agentes do plugin `fluxo-orca`** (configuração, não persona): `fluxo-orca:escritor` (Sonnet), `fluxo-orca:revisor` e `fluxo-orca:verificador` (Opus, sem Edit/Write). Explorador = `Explore` no Agent tool. No Orca: `orca terminal create --worktree path:<wt> --title <papel> --command "claude --agent fluxo-orca:<papel> [--settings ~/.claude/agents/somente-leitura.json]"` (o settings vai nos papéis só leitura) e então `worker-start --terminal <handle> --worktree path:<wt> --spec ...`.
- **Handoff por arquivo em `~/.cache/handoff/<tarefa>/`**: `mapa.md` (explorador → escritor), `revisao.md` (sessão principal → revisor: objetivo, critério, diff, interfaces), `afirmacoes.md` → verificador; saídas `veredito.md`, `verificacao.md`. Nada colado em prompt que um arquivo resolva.
- **Escalar em vez de insistir**: etapa que falha duas vezes com Sonnet → Opus na terceira ou volta ao usuário.
- **Verificação comum é reexecutar teste na sessão principal**, sem agente; o `verificador` entra só em auditoria ou afirmação de alto risco.
- Levantamento que exige julgamento de arquitetura ou regra de negócio é Opus.
- Gate read-only roda com `--worktree current` ou no worktree da tarefa; escritor tem o seu.

## Cota
- **Segunda opinião no agy**: Gemini primeiro (limite folgado); Claude/GPT no agy tem limite baixo — só pontual.
- **Medir com `bash ~/.cache/limites.sh`** (skill `limites-cota`; exit 3 se algum passar de 80%) antes de cada onda; fornecedor acima de 80% sai da vez.
- Revisão obrigatória exige Opus 5.5, sem aprovação por modelo menor. Um escritor por tarefa, que escreve E roda os testes até commitar.

## Prompt do worker (`--spec`)
Worker não herda a conversa. O spec abre com regras concretas e **valores literais**: shell (Git Bash), caminho do worktree e "não toque em nenhum outro", branch, URL, bancos, comando de teste exato (`bash ~/.cache/gs-teste.sh ...`), skills a invocar, critério de pronto. Proibições explícitas: background, bulk replace, atribuição a Claude, merge, comando remoto (ssh/forge — bloqueado por hook nos agentes externos; precisa de servidor → `ask` ao coordenador). Pede `worker_done` com resumo de 3 frases, hash do commit, divergências e `--outcome succeeded|failed`.
- **Etapas pequenas**: UMA etapa com começo, fim e prova; commita e encerra; o estado passa pelos commits. Tarefa grande se divide antes do dispatch. O spec leva o trecho preciso do plano, não "leia o plano inteiro".
- **Auditoria = auditor + verificador adversarial** (instruído a REFUTAR afirmações checáveis).
- **A cada worker concluído, informar o usuário**: UMA tabela (task · worktree · status `andamento` | `concluído` | `pendente` · observação) e, abaixo, as cotas.
- **A verificação é da sessão principal** e não delega: diff inteiro, `git log`/`git status`, ausência de atribuição, **rodar os testes de novo**, abrir a tela. `worker_done` é indício, não prova.

## Processo padrão: uma tarefa = um worktree = um worker = um PR
1. **Board antes do código** (skill `board-github`).
2. **Worktree**: plugin `laravel-worktree` (`/worktree <flag> <contexto>`, mesmo padrão `{repo}-{flag}-{contexto}`, banco próprio e `.env.testing` alinhado), depois `orca worktree set --worktree path:<novo> --parent-worktree path:<pai>` e `--worktree path:<novo>` no `worker-start`. Projeto com script próprio de setup em `.orca/` → `worker-start --worktree new-child --name {repo}-{flag}-{contexto} --base-branch origin/<base> --setup run`. Base = a branch definida no CLAUDE.md do projeto. Branch `{flag}/{AAAAMMDD}-{contexto}`. **Um setup por vez** (setups simultâneos saturam a máquina). Remover: `/worktree-clean`.
3. **Verificar a suíte sem rodá-la**: `php artisan test --list-tests`.
4. **Despachar o escritor** com validação no browser com perfil real e `gh pr create --base <.worktree-base>` com `Refs #N` (**nunca `Closes`**).
5. **Verificar antes de aceitar.**
6. **Merge é da sessão principal**, um a um. Merge limpo não garante semântica: reler o arquivo mergeado e rodar os testes dos dois lados.
   - **Gate de arquitetura**: a revisão Opus aprova também a aderência ao guia de arquitetura do projeto e ao `laravel-best-practices` (nomes, camadas, pastas, comentários, trio de testes). **Não existe "aprovado com ressalvas" para o que a branch toca** — volta para a branch antes do merge. Só dívida pré-existente não tocada fica fora.
   - **Revalidar depois do merge**: testes dos arquivos tocados, `--list-tests`, build quando houver front, reler arquivos com conflito resolvido.
7. **Fechar o ciclo no board.**
8. **Orca limpo**: terminada a nossa etapa (mergeado ou PR entregue, board atualizado) o worktree é removido — mesmo que o QA ainda vá testar, o teste é em Homologação, não no worktree. `/worktree-clean` (dropa os bancos; conferir sobra de `_test_test_N`), e liberar os workers e terminais do Orca ligados a ele. Só fica de pé o que será reaberto; nunca remover com alteração não commitada ou branch sem push.

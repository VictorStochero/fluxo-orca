# fluxo-orca

Plugin do Claude Code (pt-BR), versão **3.1.1**, com um fluxo de trabalho com o Orca para projetos **Laravel, Python e JS/TS**, em Windows, Linux ou macOS: a sessão principal coordena, o trabalho vai para workers do Orca (um worktree por tarefa, com banco e `.env` próprios), o merge passa por um gate Opus e os testes, as vagas de worker e a cota das contas vêm do plugin **agent-pool** do Orca (CLI `agent-pool`). Hooks impõem as regras pessoais.

O gate é a auditoria em repositório que versiona `.auditoria-pre-subida` (auditor Opus, verificador só com achado); nos demais, o revisor Opus é obrigatório. O pacote contém pedido/issue original, critério copiado do board, diff e interfaces, sem resumo ou justificativa de quem pede o merge. A sessão principal prova cada teste novo de correção falhando no código do merge-base. Pagamento, autorização/permissão, autenticação e alteração de dado de produção exigem segunda opinião de outra família sobre o diff: “ache o caso que quebra”.

Papéis Claude só leitura usam sempre `--settings ~/.claude/agents/somente-leitura.json`, sem MCP de navegador. A conta principal pode revisar/verificar; conta só com `orquestra` continua fora do pool.

## Pool e fila: o agent-pool

A fila de testes, o pool de contas (vagas, peso, papéis, `ativo`), a medição de cota, o teto da máquina e a RAM mínima são do agent-pool; o fluxo-orca só chama o CLI (`~/.agents/bin/agent-pool`, no Windows o `.cmd` ao lado): `agent-pool test -- <comando>` (exit 75 = fila ocupada, rodar de novo), `writer --reserve <tag>`, `second --family <f>`, `slot take|swap|release|free`, `status`, `measure`, `config get|set`.

Configuração, painel, alertas e hooks de imposição (teste fora da fila, `worker-start` sem reserva) ficam no agent-pool; `agent-pool doctor` confere requisitos, lançador, skill e hooks. Skills: `fila-testes` (uso da fila) e `limites-cota` (escritor, segunda opinião, vagas, status, papéis e `ativo`).

## Passe para a IA

### Instalar

Instale o Claude Code e mande para ele:

> Siga o instalador https://github.com/VictorStochero/fluxo-orca/blob/main/GUIA.md e configure esta máquina para os meus projetos.

O Claude diagnostica o sistema, as ferramentas e os projetos, instala o que conseguir, pede para você rodar o que exigir privilégio ou login e configura tudo pela sua stack: plugins, `settings.json`, CLAUDE.md global, perfil da máquina, boards, Orca por projeto. Só o plugin:

```
/plugin marketplace add VictorStochero/claude-plugins
/plugin install fluxo-orca@stochero
```

### Atualizar

Máquina já instalada: mande para o Claude Code (ou para o agente que coordena):

> Siga a seção "Atualizar (máquina já instalada)" do https://github.com/VictorStochero/fluxo-orca/blob/main/GUIA.md e atualize esta máquina, com a "Ação manual ao atualizar" de cada versão que pulei.

## Conteúdo

| Tipo | Itens |
|---|---|
| Fluxo | `delegacao`, `board-github`, `limites-cota`, `fila-testes`, `worktree-orca`, `ambiente-local` (Herd, Laragon, FlyEnv, Lerd, DDEV/Sail/compose com Docker ou Podman, nativo) |
| Stacks | `stack-laravel`, `stack-python`, `stack-js` |
| Metodologia | `brainstorming`, `writing-plans`, `systematic-debugging`, `test-driven-development`, `verification-before-completion`, `receiving-code-review` |
| Agentes | `escritor` (Sonnet), `revisor` e `verificador` (Opus, só leitura) |
| Hooks | `bloqueia-bulk`, `despacho-orca`, `guia-laravel`, `exige-transacao` (SQL de alteração via ssh/forge só em transação, COMMIT após ensaio com ROLLBACK), `instala-scripts` (copia os scripts e avisa quando o agent-pool não está instalado), `fim-worker` (worker do Orca não encerra sem `worker_done`); `guarda-externos` para os agentes externos |
| Scripts (em `~/.cache`) | `wt-setup.sh`/`wt-archive.sh`/`wt-lib.sh` (worktree pelo Orca), `orca-espera.sh` (vigia em background: mensagem não lida dos workers, cota, início não observado e falta de progresso; rearma a cada 5 min), `orca-tela.sh` (últimas linhas úteis da tela de um terminal), `orca-libera.sh` (workers mantidos abertos, aba criada pelo `--cria` e vaga do pool), `guarda-externos.sh`, `fim-worker.sh` |
| Agentes externos (opcional) | Codex e agy como workers do Orca, com as mesmas regras (`AGENTS.global.md`), as skills copiadas a cada sessão (as do fluxo e as dos plugins `auditoria-pre-subida`, `ponytail` e `laravel-worktree`, lista em `hooks/skills-de-plugins.lista`) para `~/.agents/skills` e `~/.gemini/config/skills` e a trava de comando remoto; segunda conta Claude para escritores. Só entra o que estiver instalado (GUIA, fase 4b) |
| Extras | `CLAUDE.global.md` (modelo de `~/.claude/CLAUDE.md`), `AGENTS.global.md` (modelo de `~/.agents/AGENTS.md`), `somente-leitura.json` |

## Outros agentes: worker e coordenador

`instalar.sh --agente <id> [--aplicar]` instala regras, skills, trava de comando remoto e fim-worker no formato de cada agente, também para quem coordena **sem Claude Code** (GUIA, "Coordenar sem Claude Code"; sem os hooks do plugin, travas só onde o agente tem hook). Quem entra no pool, com que papel e se tem a imposição do agent-pool vem do próprio agent-pool (`agent-pool config get pool.contas`, `agent-pool doctor`); papel de trabalho (escritor, mecânico, revisor, verificador) só em agente com trava de comando remoto instalada e provada (GUIA, fase 4b, passo 7). Claude, Codex e agy (segunda opinião) rodam em uso nesta máquina; gemini, kimi, zcode, opencode e cursor-agent ficam em segunda opinião até a prova de despacho.

Na 3.1.0, as skills dos plugins `auditoria-pre-subida`, `ponytail` e `laravel-worktree` também vão para o Codex (`~/.agents/skills`) e para o Antigravity (`~/.gemini/config/skills`), junto com as do fluxo-orca, copiadas no início da sessão só quando a versão do fluxo-orca ou o `installed_plugins.json` mudam.

Na 3.0.0, o `orca-espera.sh` passa a ser obrigatório em background com worker rodando e sai também na mensagem não lida (`check --peek`): o wake do Orca não acorda sessão parada.

Na 2.13.0, o coordenador dispara a onda inteira e encerra o turno: o Orca 1.4.246 (Orchestrator V3) o acorda com as mensagens dos workers. Ao acordar, executa o `check` indicado no wake e responde `question` com `reply`; `orca-espera.sh` fica opcional em background somente como vigia de saúde. Correções voltam ao mesmo worker com `send --to dispatch:<id>`, inclusive depois de concluído ou fechado (follow-up Task). Worker aberto por `worker-start --agent` em worktree existente fecha sozinho; com `--terminal` (aba do `--cria`), worktree novo ou `--keep-open`, liberar com `orca-libera.sh <dispatch>`.

**Ação manual ao atualizar para 3.0.0:** instalar o plugin **agent-pool** no Orca **antes** de atualizar o fluxo-orca (aprovar o acesso do plugin): na primeira ativação ele importa `~/.claude/agentes.conf` e `~/.claude/fila.conf` para a configuração dele (`~/.agents/agent-pool/`; os originais ficam intocados), grava o lançador `~/.agents/bin/agent-pool` e instala a skill e os hooks de imposição. Depois de atualizar, reabrir todas as sessões; `agent-pool doctor` e `agent-pool status` devem responder. Sem o agent-pool instalado, o SessionStart avisa uma vez por sessão. Variáveis `FILA_TESTE_*`/`GS_TESTE_*`, `LIMITES_*`, `CONTAS_ADVISOR` e `FILA_TESTE_RUNNER` deixam de valer: a configuração é `agent-pool config set …` (fila: `fila.modo|vagas|vagas_projeto|teto|processos`; pool: `pool.teto|ram_min|escolha|ordem`, `conta.<nome>.vagas|peso|papeis|ativo`) e, por projeto, `.orca/agent-pool.json` (`{"recurso": "..."}`); o painel antigo (`orca-plugin/`) foi removido, o do agent-pool o substitui.

Mapa dos comandos que saíram: `fila-teste.sh <args>` → `agent-pool test -- <comando>`; `limites.sh --escritor --reserva <tag>` → `agent-pool writer --reserve <tag>`; `limites.sh --segunda --familia <f>` → `agent-pool second --family <f>`; `vaga-agente.sh pega|troca|solta|livres` → `agent-pool slot take|swap|release|free`; `limites.sh`/`--alerta` → `agent-pool status`/`measure`; `painel.sh --config` e `contas.sh lista` → `agent-pool config set`/`get`; `orca-ram.sh` → `pool.ram_min` na reserva e `orca diagnostics memory --json`.

**Ação manual ao atualizar para 2.14.0:** carregar o painel no Orca com `orca plugin dev load` apontando para a cópia de `orca-plugin/` e aprovar o acesso; a configuração da fila ficava em `~/.claude/fila.conf` e as contas detectadas pelo Orca entravam sozinhas no `agentes.conf` (na 3.0.0 isso passa ao agent-pool).

**Ação manual ao atualizar para 2.13.0:** requer Orca 1.4.246 ou mais novo (`orca --version`): atualizar o Orca antes do plugin. Remover a cópia antiga de `~/.cache/orca-inicia.sh`, se existir. O plugin usa diretamente `orca orchestration worker-start --spec-file ~/.cache/handoff/<tarefa>/spec.md`, que já imprime o recibo resumido e `Next:`; a instalação não apaga a cópia antiga.

## Licença

MIT © Victor Stochero. As skills de metodologia vêm do [obra/superpowers](https://github.com/obra/superpowers) (MIT © Jesse Vincent, ver `skills/LICENSE-superpowers`), com pequenas adaptações para a delegação pelo Orca. **Não use junto com o plugin `superpowers`**: as skills ficam duplicadas e as originais conflitam com o fluxo.

# fluxo-orca

Plugin do Claude Code (pt-BR), versão **2.13.0**, com um fluxo de trabalho com o Orca para projetos **Laravel, Python e JS/TS**, em Windows, Linux ou macOS: a sessão principal coordena, o trabalho vai para workers do Orca (um worktree por tarefa, com banco e `.env` próprios), o merge passa por um gate Opus e os testes rodam por filas da máquina (2 vagas por recurso, teto global de 3). Hooks impõem as regras.

O gate é a auditoria em repositório que versiona `.auditoria-pre-subida` (auditor Opus, verificador só com achado); nos demais, o revisor Opus é obrigatório. O pacote contém pedido/issue original, critério copiado do board, diff e interfaces, sem resumo ou justificativa de quem pede o merge. A sessão principal prova cada teste novo de correção falhando no código do merge-base. Pagamento, autorização/permissão, autenticação e alteração de dado de produção exigem segunda opinião de outra família sobre o diff: “ache o caso que quebra”.

Papéis Claude só leitura usam sempre `--settings ~/.claude/agents/somente-leitura.json`, sem MCP de navegador. A conta principal pode revisar/verificar; conta com só `orquestra` continua fora do pool. Exemplo de `~/.claude/agentes.conf`:

```text
escolha=ritmo
teto=4
ram_min=3
pessoal agente=claude peso=10 vagas=1 papeis=orquestra,escritor,revisor,verificador
team agente=claude config=~/.claude-team peso=1 vagas=1 papeis=escritor
claude-b agente=claude config=~/.claude-b peso=5 vagas=2 papeis=escritor,revisor
codex agente=codex peso=1 vagas=1 papeis=escritor
agy agente=antigravity vagas=1 papeis=segunda-opiniao
```

`peso` multiplica o ritmo (`escolha=ordem` ignora); `teto=0` deixa a máquina ilimitada. `ram_min` define a RAM disponível mínima em GB para novas reservas (0 desliga); falha de leitura avisa sem bloquear. Antes da onda, `bash ~/.cache/orca-ram.sh` mostra sessões ociosas por memória e sugere liberações de workers concluídos e retidos; só lê, nunca fecha nada. `CONTAS_ADVISOR` define o advisor do escritor Claude (padrão `opus`, vazio desliga); `LIMITES_CACHE_MIN` controla o cache de cota (padrão 5, 0 desliga). O alerta do coordenador mede cota a cada 20 minutos e avisa uma vez por queda de RAM abaixo do mínimo. Segunda opinião: `limites.sh --segunda --familia <claude|gpt|gemini>`, com preferência por Gemini do agy, grupo misto do agy e Codex, conforme cota e família.

Para separar projetos que usam o mesmo banco, `FILA_TESTE_FILA=projeto` usa uma fila por projeto, compartilhada pelos worktrees, com `FILA_TESTE_VAGAS_PROJETO=1` por padrão. O teto da máquina continua valendo; o modo padrão `recurso` permanece por porta/container/geral. Use `bash ~/.cache/fila-teste.sh`; o atalho `gs-teste.sh` e as variáveis `GS_TESTE_*` continuam aceitos por compatibilidade, com prioridade para `FILA_TESTE_*`. Os nomes das travas permanecem iguais.

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
| Hooks | `fila-testes`, `bloqueia-bulk`, `despacho-orca`, `guia-laravel`, `exige-transacao` (SQL de alteração via ssh/forge só em transação, COMMIT após ensaio com ROLLBACK), `instala-scripts`, `fim-worker` (worker do Orca não encerra sem `worker_done`); `guarda-externos` para os agentes externos |
| Scripts (em `~/.cache`) | `fila-teste.sh` (fila: 2 vagas por recurso, teto global `FILA_TESTE_TETO` de 3) + `e-teste.sh` (detector de comando de teste, compartilhado com Codex/agy pelo `guarda-externos.sh`), `wt-setup.sh`/`wt-archive.sh`/`wt-lib.sh` (worktree pelo Orca), `orca-espera.sh` (vigia de saúde: RAM, cota, início não observado e falta de progresso), `orca-tela.sh` (últimas linhas úteis da tela de um terminal), `orca-libera.sh` (workers mantidos abertos, aba criada pelo `--cria` e vaga do pool), `vaga-agente.sh` (pool de agentes por conta da máquina), `contas.sh` + `agentes-catalogo.conf` (registro de contas sobre o catálogo dos 45 agentes do Orca, lido do `~/.claude/agentes.conf`, com o registro parseado em cache em `~/.cache/agentes/registro.cache`), `limites.sh` + `medidores/` (cota por conta: API de uso das contas Claude com o token do `.credentials.json`, caindo no `claude -p "/usage"` quando não dá, e `orca account list` para Codex, Antigravity, Kimi, MiniMax e demais; Kimi e MiniMax não testados com conta real), `guarda-externos.sh`, `fim-worker.sh`, `orca-ram.sh` (RAM e sessões ociosas pelo Orca), `instala-agente.sh` (atalho para o instalador do plugin, pela raiz gravada em `fluxo-orca-raiz`) |
| Agentes externos (opcional) | Codex e agy como workers do Orca, com as mesmas regras (`AGENTS.global.md`), as skills copiadas para `~/.agents/skills` e a trava de comando remoto; segunda conta Claude para escritores. Só entra o que estiver instalado (GUIA, fase 4b) |
| Extras | `CLAUDE.global.md` (modelo de `~/.claude/CLAUDE.md`), `AGENTS.global.md` (modelo de `~/.agents/AGENTS.md`), `somente-leitura.json` |

## Outros agentes: worker e coordenador

`skills/limites-cota/instala-agente.sh <agente> [--aplicar]` instala regras, skills, trava de comando remoto e fim-worker no formato de cada agente; `instalar.sh --agente <id> [--aplicar]` faz o mesmo para quem coordena **sem Claude Code** (GUIA, "Coordenar sem Claude Code"; sem os hooks do plugin, travas só onde o agente tem hook). O papel de trabalho (escritor, mecânico, revisor, verificador) só vale em agente com trava (`pre=sim`) **e** com `testado=<data>` no catálogo (prova de despacho do GUIA, fase 4b, passo 7); claude, codex e antigravity estão isentos. Além disso, o carimbo `~/.cache/trava-<agente>.ok` desta máquina (gravado pelo `instala-agente.sh --aplicar`) precisa existir; sem ele, `<agente>: trava não instalada nesta máquina — rode bash ~/.cache/instala-agente.sh <agente> --aplicar`. `pre=sim` com `testado=-` → o `contas.sh` recusa o papel (`<agente>: trava só documentada, rode a prova do GUIA fase 4b e registre testado=<data>`) e o agente só dá segunda opinião; sem fim de turno (`fim=nao`) a conta entra com aviso.

| Agente | Papel hoje | Trava (`pre`) | Fim de turno (`fim`) | Testado |
|--------|------------|---------------|----------------------|---------|
| claude | trabalho + orquestra (plugin) | sim | sim | em uso |
| codex | trabalho | sim | sim | em uso |
| antigravity (agy) | segunda opinião (padrão) | sim | não | em uso |
| gemini | segunda opinião até a prova | sim (`BeforeTool`) | sim (`AfterAgent`) | **não testado** |
| kimi | segunda opinião até a prova | sim (`PreToolUse`) | sim (`Stop`) | **não testado** |
| zcode | segunda opinião até a prova | sim (`PreToolUse`, exige `hooks.enabled`) | não | **não testado** |
| opencode / opencode2 (e MiniMax por ele) | segunda opinião até a prova | sim (plugin `tool.execute.before`) | não | **não testado** |
| cursor-agent | segunda opinião | não (hooks só documentados no app) | não | **não testado** |
| demais do catálogo | só medição / segunda opinião | desconhecido | desconhecido | — |

"Em uso" = já rodava antes do catálogo ter a coluna `testado` (que fica `-` até a prova de despacho do GUIA, fase 4b, passo 7). As capacidades dos agentes não testados vêm da documentação oficial, citada no cabeçalho de `agentes-catalogo.conf`.

Na 2.13.0, o coordenador dispara a onda inteira e encerra o turno: o Orca 1.4.246 (Orchestrator V3) o acorda com as mensagens dos workers. Ao acordar, executa o `check` indicado no wake e responde `question` com `reply`; `orca-espera.sh` fica opcional em background somente como vigia de saúde. Correções voltam ao mesmo worker com `send --to dispatch:<id>`, inclusive depois de concluído ou fechado (follow-up Task). Worker aberto por `worker-start --agent` em worktree existente fecha sozinho; com `--terminal` (aba do `--cria`), worktree novo ou `--keep-open`, liberar com `orca-libera.sh <dispatch>`.

**Ação manual ao atualizar para 2.13.0:** requer Orca 1.4.246 ou mais novo (`orca --version`): atualizar o Orca antes do plugin. Remover a cópia antiga de `~/.cache/orca-inicia.sh`, se existir. O plugin usa diretamente `orca orchestration worker-start --spec-file ~/.cache/handoff/<tarefa>/spec.md`, que já imprime o recibo resumido e `Next:`; a instalação não apaga a cópia antiga.

## Painel do Orca (monitoramento)

`orca-plugin/` é um plugin do Orca (`trusted-worker`, Orca ≥ 1.4.246) com um painel lateral que mostra e **configura**: **fila de testes** (modo, vagas, teto; cada trava expande para worktree, comando, pid e desde), **pool de agentes** (todas as contas numa lista, com a origem marcada: detectadas pelo Orca por `orca account list`, com a cota nativa, e manuais do `agentes.conf`, como as por `CLAUDE_CONFIG_DIR` que o Orca não conhece; por conta: vagas usadas/total, cota 5h e Semanal; expande para peso, papéis, agente, janelas e dispatches nas vagas). O worker roda `bash ~/.cache/painel.sh --json` (o coletor, copiado pelo `instalar.sh`) e observa `~/.cache/gs-teste*` e `~/.cache/agentes/`: quando mudam, avisa o painel; o botão **Atualizar** lê de novo. Sem servidor HTTP nem polling.

**Configuração pelo painel.** Conta detectada ganha **Adicionar ao pool**; há formulário de **Nova conta manual** (nome, agente do catálogo, diretório de config) e **Remover do pool** (com confirmação). O Orca 1.4.246 não escolhe a conta por worker: o despacho por conta segue pelo lançador do `contas.sh`. A seção **Configurações** (Fila, Pool e Painel, cada campo com dica) e o formulário dentro da linha de cada conta gravam por trás com `bash ~/.cache/painel.sh --config chave=valor ...` (`fila.vagas=3`, `pool.ram_min=2`, `conta.<nome>.papeis=revisor,mecanico`), tudo ou nada: o `contas.sh lista` valida o `agentes.conf` candidato num `.tmp` antes de trocá-lo, e a recusa volta ao painel em português. A fila grava em `~/.claude/fila.conf` e o pool em `~/.claude/agentes.conf`. Precedência da fila: variável de ambiente (`FILA_TESTE_*` e os nomes antigos `GS_TESTE_*`, só legado, menor precedência) < `fila.conf` < `.orca/worktree.conf` do projeto; o painel mostra a origem de cada valor e avisa quando um projeto o sobrescreve.

Para carregar: `orca plugin dev load orca-plugin`. O worker roda código na sua conta, então o Orca pede a sua aprovação do acesso; confira com `orca plugin inspect orca-plugin` antes de aprovar. Validação: `orca plugin validate|check|test orca-plugin` e tipos com `orca plugin types orca-plugin` (grava `.orca/types/`, ignorado pelo git), `npm install --no-package-lock` e `npx tsc -p .` dentro de `orca-plugin/` (o `orca-plugin/package.json` só traz `typescript` e `@types/node` para o worker).

## Licença

MIT © Victor Stochero. As skills de metodologia vêm do [obra/superpowers](https://github.com/obra/superpowers) (MIT © Jesse Vincent, ver `skills/LICENSE-superpowers`), com pequenas adaptações para a delegação pelo Orca. **Não use junto com o plugin `superpowers`**: as skills ficam duplicadas e as originais conflitam com o fluxo.

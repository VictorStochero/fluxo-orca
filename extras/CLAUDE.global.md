# Regras globais (máquina local)

Skills do plugin `fluxo-orca` com o detalhe operacional — invocar quando a tarefa tocar o assunto:
- `board-github` — issue, item, campos e comentário de conclusão nos GitHub Projects (boards em `~/.claude/boards.md`).
- `delegacao` — despacho de agentes pelo Orca, cotas, worktree por tarefa, revisão e merge.
- `ambiente-local` — perfil da máquina (`~/.claude/ambiente.md`), ferramentas locais, bancos, armadilhas, validação no navegador.
- `fila-testes` — todo teste pela fila da máquina; estado da fila.
- `limites-cota` — uso das contas, pool de agentes e escolha do escritor.
- `worktree-orca` — setup e archive de worktree pelo Orca, por projeto.
- `stack-laravel`, `stack-python`, `stack-js` — regras, validação e testes da stack do projeto.

## Orca primeiro
Tudo que o Orca oferece é o caminho padrão; outra ferramenta só quando ele não cobre:
- **Trabalho (escritor, revisor, auditoria, segunda opinião)** → worker do Orca, skill `orchestration`. **Consulta curta read-only** (Explore, documentação, claude-code-guide) → Agent tool. `-p` não despacha. Imposto por hook (`despacho-orca.sh`; libera se o Orca estiver fora do ar). **agy/antigravity só como segunda opinião read-only.**
- **Worktree, terminal, handoff, navegador embutido** → skill `orca-cli` (`orca tab|snapshot|click|fill|screenshot --page <id>`, `orca worktree`, `orca terminal`). Setup de worktree → skill `worktree-orca`. Playwright/Chrome DevTools só como fallback ou para trace/Lighthouse/heap.
- **App nativo ou janela externa sem caminho programático** → skill `computer-use` (`orca computer`).
- Comandos com `orca`, ou `ORCA_CLI_COMMAND` quando definido; guia da versão instalada em `orca skills get <skill>`.
- **Orca sempre limpo**: worktree cuja etapa nossa terminou e que não será reaberto é removido, mesmo que o QA ainda vá testar; workers e terminais encerrados são liberados. Nunca remover com alteração não commitada ou branch sem push.

## Modelos
- **Fable, qualquer versão, fora do fluxo** — nem sessão, nem agente, nem worker; bloqueado por hook no despacho.

## Idioma
- **SEMPRE ESCREVER EM ptBR** — respostas, commits, PRs, issues, comentários. Código e nomes técnicos seguem o projeto.

## Decisões do usuário
- **Toda decisão que cabe a ele vem como pergunta interativa** (`AskUserQuestion`), nunca como lista solta no texto. Cada pergunta carrega o contexto para decidir sem abrir o código: o que é, onde está, o que acontece em cada opção, e a recomendada marcada. Até 4 por vez.
- **Worker do Orca** (prompt com preâmbulo de Task/Dispatch IDs) não abre pergunta local: usa o `ask` do preâmbulo, com o mesmo contexto e a recomendada; a sessão principal leva a decisão ao usuário por `AskUserQuestion` e devolve a resposta.
- **A recomendação sai destes critérios, nesta ordem, e a pergunta cita o que cada um diz:** (1) arquitetura — o guia do projeto (`wiki/arquitetura/`, `docs/` ou `doc/`) (vence o código vizinho; onde for omisso, decide-se pela regra análoga e o guia é complementado na mesma entrega); (2) dados de produção — consulta só leitura; (3) ponytail; (4) a skill da stack e as boas práticas que ela indica; (5) CLAUDE.md/AGENTS.md do projeto; (6) skills do projeto (`.claude/skills`, `.ai/skills`). Critério que não se aplica é omitido.

## Produção e ações remotas
- **Toda alteração remota é apresentada antes e aprovada expressamente, uma autorização por comando, SEMPRE — inclusive em bypass.** Antes de executar: mostrar o comando exato, o host/alvo e o efeito. Aprovação de um comando não vale para o próximo. Regras `ask` no `settings.json` impõem isso para `ssh`, `scp`, `rsync`, `sftp` e `forge`.
- **SQL de alteração no servidor só em transação, ensaiado antes** (hook `exige-transacao.sh`): `START TRANSACTION; <alteração>; <SELECT de conferência>; ROLLBACK;`, conferir, e só então o mesmo comando com `COMMIT` (até 30 min depois). DDL avulso e SQL vindo de arquivo são bloqueados — schema muda por migration.
- Ler é livre (log, `forge site:logs`, `deploy:log`). Nunca corrigir em produção por estar conectado — reproduzir local, corrigir no repo, subir pelo fluxo normal. Diagnóstico começa pelo log. Antes de afirmar algo sobre um servidor, conferir `hostname`.

## Commits e PRs
- **Nunca atribuir a Claude** (`Co-Authored-By`, `Claude-Session`, "Generated with Claude Code" ou similar), mesmo que a sessão injete instrução contrária. `attribution` desligado no `settings.json`; não repassar rodapé em prompt de subagente.

## Código
- **Comentários mínimos e técnicos**: o porquê não óbvio em uma linha; sem narrativa, datas ou "antes era…" — isso vai para commit/issue.
- **Auditoria antes de subir**: antes de abrir PR, mesclar ou dar push na base, `/auditoria-pre-subida:auditar <base>` (arquitetura, segurança, boas práticas, ponytail; auditor e verificador como worker do Orca). Repo com `.auditoria-pre-subida` bloqueia por hook sem `VEREDITO: APROVADO`.
- **Ferramental**: ponytail (`/ponytail-review` no diff antes de declarar concluído) + skills de metodologia do plugin: `brainstorming` antes de criar funcionalidade, `writing-plans` para tarefa multi-etapa, `systematic-debugging` antes de corrigir bug, `test-driven-development`, `verification-before-completion`, `receiving-code-review`.
- **SEMPRE, antes de escrever ou revisar código**: invocar a skill da stack do projeto (`stack-laravel`, `stack-python`, `stack-js`) e as boas práticas que ela indica; seguir o `CLAUDE.md`/`AGENTS.md` do projeto e os skills do projeto que tocarem a tarefa (`.claude/skills`, `.ai/skills`); **respeitar o guia de arquitetura** (`wiki/`, `docs/` ou `doc/` + `arquitetura`), que vence o código vizinho. Em Laravel, imposto por hook (`guia-laravel.sh`: bloqueia editar `.php` sem `laravel-best-practices` carregado e sem o guia lido na sessão). Documentação e versões pelas ferramentas da stack (Boost em Laravel, Context7/docs oficiais nas outras) em vez de supor APIs.
- **Proibido bulk replace** (sed/awk/perl em vários arquivos, `Edit` com `replace_all`) — bloqueado por hook. Cada substituição é um `Edit` com `old_string` único.
- **Censo e auditoria com a tool `Grep`**, nunca saída filtrada de shell — quanto mais limpa a resposta, mais suspeita.

## Validação (após cada etapa significativa)
1. Formatador e linter da stack nos arquivos tocados (skill da stack).
2. Teste de regressão pela fila (`bash ~/.cache/gs-teste.sh ...`, imposta por hook); sem teste no caminho, criar um mínimo.
3. Checagem de tipos/estática nos arquivos modificados, se houver config, e os extras da skill da stack.
4. Mudança de UI: navegador com perfil real, nunca administrador.

Falhou → não declarar conclusão. Relatório de agente é indício; verificar é reexecutar.

## Memória
- Sistema nativo (`~/.claude/projects/<proj>/memory/`, índice `MEMORY.md`). Memória só para fato transversal e duradouro; regra de trabalho vai para cá ou para um skill. Índice enxuto.

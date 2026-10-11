# Regras globais — agentes externos (Codex, Kimi Code, opencode, Antigravity/agy)

Fonte única em `~/.agents/AGENTS.md`; `~/.codex/AGENTS.md`, `~/.kimi-code/AGENTS.md`, `~/.config/opencode/AGENTS.md` e `~/.gemini/config/AGENTS.md` são links para este arquivo. Equivalente ao `~/.claude/CLAUDE.md` do Claude Code.

Skills em `~/.agents/skills` (cópia das skills do plugin `fluxo-orca`, mantida pelo hook de SessionStart do Claude Code, + `orca-cli`, `orchestration`, `computer-use` do Orca) — carregar quando a tarefa tocar o assunto: `ambiente-local` (perfil em `~/.claude/ambiente.md`), `board-github` (boards em `~/.claude/boards.md`), `fila-testes` (todo teste pela fila da máquina; estado da fila), `limites-cota` (uso das contas, pool de agentes e escolha do escritor), `worktree-orca`, `stack-*`; metodologia: `systematic-debugging` antes de corrigir bug, `test-driven-development`, `verification-before-completion` antes de declarar pronto, `receiving-code-review`.

## Idioma
- **SEMPRE ESCREVER EM ptBR** — respostas, commits, PRs, issues, comentários. Código e nomes técnicos seguem o projeto.

## Antigravity (agy)
- Papel único: **segunda opinião read-only** (revisão, contraprova). Não editar arquivos, não rodar testes, build, migração ou git que escreve; responder com veredito e achados verificáveis.

## Como worker do Orca
- Prompt com preâmbulo de Task/Dispatch IDs = worker supervisionado: seguir o preâmbulo, uma tarefa só, `worker_done` uma vez com resumo de 3 frases, hash do commit, divergências e `--outcome succeeded|failed`.
- **Decisão que cabe ao usuário vai pelo `ask` do preâmbulo** (nunca pergunta local), com o contexto para decidir e a opção recomendada; a sessão principal leva ao usuário.
- Fora do escopo da tarefa: não fazer — registrar no `worker_done`.
- Antes de tocar banco, conferir que o setup do worktree terminou com sucesso; se estiver rodando, aguardar. Setup falhou ou sucesso não verificável → `ask` ao coordenador com a saída do setup e aguardar orientação, sem tentar refazer migração por conta própria. O repo no Orca deve estar configurado para aguardar o setup antes de iniciar o agente (`wait-for-setup`).

## Proibido
- **Comando remoto** (`ssh`, `scp`, `rsync`, `sftp`, `forge`) — bloqueado por hook (`guarda-externos.sh`). Precisa de servidor → `ask` ao coordenador; a ação roda na sessão principal com aprovação do usuário por comando.
- **Atribuição a IA** em commit ou PR (`Co-Authored-By`, "Generated with…", rodapés de sessão).
- **Bulk replace** (`sed -i`, `perl -i`, regex em vários arquivos, replace_all) — bloqueado por hook. Cada substituição é uma edição única e contextualizada.
- **Comando em background** e merge.

## Código
- **Comentários mínimos e técnicos**: o porquê não óbvio em uma linha; sem narrativa, datas ou "antes era…".
- Antes de escrever: precisa existir? já existe no repo? framework/dependência instalada resolve? dá em uma linha? Só então o mínimo.
- **SEMPRE, antes de escrever ou revisar código**: ler a skill da stack do projeto (`stack-laravel`, `stack-python`, `stack-js`) e as boas práticas que ela indica (em Laravel, `.claude/skills/laravel-best-practices/SKILL.md` do projeto); seguir o `CLAUDE.md`/`AGENTS.md` do projeto e os skills dele (`.claude/skills`, `.ai/skills`); **ler e respeitar o guia de arquitetura** (`wiki/`, `docs/` ou `doc/` + `arquitetura`) — ele vence o código vizinho.
- Censo e auditoria com busca nativa (rg/grep sem pipe que resuma) — quanto mais limpa a resposta, mais suspeita.

## Testes e validação
- **Testes só pela fila**: `bash ~/.cache/gs-teste.sh <argumentos>` (exit 75 = `FILA OCUPADA`, rodar de novo). Nunca o comando de teste direto. Um arquivo por chamada.
- **Relatório e log fora do repo**: evidência vai no `worker_done` e no PR; arquivo de apoio em `~/.cache/handoff/<tarefa>/`, nunca versionado (`reports/`, `*.log`).
- Nenhuma chamada passa de 10 min: dividir por arquivo e **commitar antes de verificação longa**. Gravar o relatório em arquivo desde o primeiro achado.
- Após cada etapa: formatador/linter da stack nos arquivos tocados; teste de regressão (sem teste no caminho, criar um mínimo); falhou → não declarar concluído.
- Mudança de UI: navegador embutido do Orca (skill `orca-cli`, sempre `--page <id>`), perfil real, nunca administrador.

## Orca primeiro
- **Orca sempre limpo**: ao terminar a etapa, fechar abas do navegador e terminais que abriu; o worktree é removido pelo coordenador (worker não remove o próprio worktree).
- Worktree, terminal, navegador → `orca-cli`. App nativo sem caminho programático → `computer-use` (`orca computer`). Coordenação → `orchestration`. Comandos com `orca` (ou `ORCA_CLI_COMMAND`).

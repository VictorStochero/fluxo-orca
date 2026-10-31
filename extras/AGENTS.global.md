# Regras globais — qualquer agente (worker ou coordenador): Codex, Gemini, Kimi, opencode, ZCode, Antigravity/agy…

Instalado pelo `instalar.sh --agente <id>` (ou `skills/limites-cota/instala-agente.sh <id>`) no arquivo global de regras do agente, dentro do bloco `fluxo-orca:inicio … fluxo-orca:fim` (reexecutar atualiza só o bloco). Equivalente ao `~/.claude/CLAUDE.md` do Claude Code.

Skills em `~/.agents/skills` ou no diretório de skills do agente (cópia das skills do plugin `fluxo-orca` + `orca-cli`, `orchestration`, `computer-use` do Orca); agente sem diretório de skills recebe o índice com o caminho de cada `SKILL.md` — ler o arquivo sob demanda. Carregar quando a tarefa tocar o assunto: `ambiente-local` (perfil em `~/.claude/ambiente.md`), `board-github` (boards em `~/.claude/boards.md`), `fila-testes` (todo teste pela fila da máquina; estado da fila), `limites-cota` (uso das contas, pool de agentes e escolha do escritor), `worktree-orca`, `stack-*`; metodologia: `systematic-debugging` antes de corrigir bug, `test-driven-development`, `verification-before-completion` antes de declarar pronto, `receiving-code-review`.

## Idioma
- **SEMPRE ESCREVER EM ptBR** — respostas, commits, PRs, issues, comentários. Código e nomes técnicos seguem o projeto.

## Segunda opinião (agy e agente sem trava de comando)
- Antigravity (agy) e todo agente sem hook antes de comando (ex.: cursor-agent) têm papel único: **segunda opinião read-only** (revisão, contraprova). Não editar arquivos, não rodar testes, build, migração ou git que escreve; responder com veredito e achados verificáveis.

## Como coordenador (sessão principal sem Claude Code)
- Equivalentes genéricos das ferramentas do Claude Code: **pergunta interativa ao usuário** (`AskUserQuestion`) = o recurso de pergunta/escolha do seu agente; sem ele, uma pergunta no texto com contexto para decidir e a opção recomendada marcada, uma decisão por vez. **Consulta curta read-only** (`Agent tool`/Explore) = o subagente ou a busca somente leitura do seu agente. **Trabalho** (escritor, revisor, auditoria) = worker do Orca pela skill `orchestration`, nunca na própria sessão.
- Hooks do plugin (bloqueio de bulk replace, de teste fora da fila, de despacho fora do Orca, de SQL fora de transação) **não existem fora do Claude Code**: valem como regra escrita, que você cumpre sozinho. A trava de comando remoto só existe onde o agente tem hook (`instala-agente.sh` mostra). Conferir antes de despachar: `bash ~/.cache/limites.sh --escritor` e `bash ~/.cache/vaga-agente.sh livres`.
- Antes de despachar: skill `delegacao` (worktree por tarefa, pacote de revisão, merge só depois do gate) e `limites-cota` (quem escreve). Antes de declarar pronto: reexecutar os testes pela fila e conferir o diff arquivo a arquivo — relatório de worker é indício, não prova.
- Ação remota (servidor, produção): mostrar o comando exato, o alvo e o efeito, e esperar aprovação expressa do usuário, um comando por vez.
- **Worker não sobe nada**: worker só commita local; push, PR, merge e comentário remoto saem da sessão principal, depois da auditoria, com comando, alvo e efeito apresentados e aprovados um a um.
- **Hook barrou o worker**: a sessão principal instala ou ativa o pré-requisito (ex.: skill da stack), encerra o dispatch parado e reenvia um worker novo com spec de retomada; nunca desativar, editar ou contornar o hook.
- **Worktree filho do coordenador**: worktree de tarefa nasce filho do worktree da sessão coordenadora (`--parent-worktree path:<coordenador>`), nunca solto.
- **Ordem do usuário não se reduz**: "aplicar a recomendada" vale para o que o usuário não decidiu; variante menor de uma ordem explícita vira pergunta, nunca decisão silenciosa.
- **Resposta automática não é decisão**: pergunta interativa que volta com todas as recomendadas sem resposta real do usuário é tratada como não respondida — perguntar de novo no texto e esperar; nada vai a worker nem a registro antes.
- **Pergunta pendente não para o fluxo**: com pergunta aberta, seguir o ciclo de espera (`orca-espera.sh`) e despachar o que não depende da resposta, sem encerrar o turno parado.
- **A recomendação sai destes critérios, nesta ordem, e a pergunta cita o que cada um diz:** (1) arquitetura — o guia/wiki do projeto (`wiki/arquitetura/`, `docs/` ou `doc/`) (vence o código vizinho; onde for omisso, decide-se pela regra análoga e o guia é complementado na mesma entrega); (2) skills — a skill da stack e as boas práticas que ela indica (ex.: `laravel-best-practices`) e as skills do projeto (`.claude/skills`, `.ai/skills`); (3) padrões do framework (ex.: "Laravel way", docs oficiais); (4) ponytail; (5) CLAUDE.md/AGENTS.md do projeto. Dados de produção (consulta só leitura) entram como evidência de risco — quem usa, quanto —, não como critério de arquitetura. Critério que não se aplica é omitido.

## Como worker do Orca
- Prompt com preâmbulo de Task/Dispatch IDs = worker supervisionado: seguir o preâmbulo, uma tarefa só, `worker_done` uma vez com resumo de 3 frases, hash do commit, divergências e `--outcome succeeded|failed`.
- **Decisão que cabe ao usuário vai pelo `ask` do preâmbulo** (nunca pergunta local), com o contexto para decidir e a opção recomendada; a sessão principal leva ao usuário.
- Só commita local: sem push, PR, merge nem comentário remoto — a sessão principal sobe depois da auditoria. Hook que barrar o trabalho não se contorna: `ask` ao coordenador.
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
- **Testes só pela fila**: `bash ~/.cache/fila-teste.sh <argumentos>` (exit 75 = `FILA OCUPADA`, rodar de novo). Nunca o comando de teste direto. Um arquivo por chamada.
- **Relatório e log fora do repo**: evidência vai no `worker_done` e no PR; arquivo de apoio em `~/.cache/handoff/<tarefa>/`, nunca versionado (`reports/`, `*.log`).
- Nenhuma chamada passa de 10 min: dividir por arquivo e **commitar antes de verificação longa**. Gravar o relatório em arquivo desde o primeiro achado.
- Após cada etapa: formatador/linter da stack nos arquivos tocados; teste de regressão (sem teste no caminho, criar um mínimo); falhou → não declarar concluído.
- Mudança de UI: navegador embutido do Orca (skill `orca-cli`, sempre `--page <id>`), perfil real, nunca administrador.

## Orca primeiro
- **Orca sempre limpo**: ao terminar a etapa, fechar abas do navegador e terminais que abriu; o worktree é removido pelo coordenador (worker não remove o próprio worktree).
- Worktree, terminal, navegador → `orca-cli`. App nativo sem caminho programático → `computer-use` (`orca computer`). Coordenação → `orchestration`. Comandos com `orca` (ou `ORCA_CLI_COMMAND`).

---
name: fila-testes
description: Use antes de rodar qualquer teste (artisan test/pest, pytest, manage.py test, vitest, jest, npm/pnpm/yarn/bun test, cargo, go) ou quando perguntarem sobre a fila de testes (ocupação, vagas, espera, exit 75) — todo teste da máquina passa por `agent-pool test -- <comando>`, para worktrees e agentes em paralelo não derrubarem a máquina nem corromperem bancos de teste.
---

# Fila de testes da máquina

Todo teste roda por `agent-pool test -- <comando>` (CLI do plugin agent-pool do Orca, em `~/.agents/bin/agent-pool`; no Windows, o `.cmd` ao lado). A fila é do agent-pool; a imposição vem do hook que ele instala, que recusa o comando de teste fora dela e devolve o comando certo.

## Como chamar (no cwd do projeto/worktree)
- `agent-pool test -- <comando completo>` — roda como está, esperando a vez: `-- php artisan test --compact tests/Feature/XTest.php`, `-- pnpm vitest run src/x.test.ts`, `-- uv run pytest tests/test_x.py`, `-- python manage.py test app`.
- `agent-pool test` (sem comando) — detecta o executor e o paralelismo do projeto (Laravel, Python, JS, Go, Rust…). Só o `test -- <comando>` aceita argumento; qualquer outro dá exit 2.
- Preparação do banco de teste também passa por ele: `agent-pool test -- php artisan migrate:fresh --env=testing --force`.
- `--parallel` do Laravel: `agent-pool test -- php artisan test --parallel --processes=8 --compact <path>` (**um path**); ao terminar, os `<banco>_test_N` são apagados. Sem `--parallel` o teste roda em 1 processo.
- Projeto em container: `.orca/agent-pool.json` com `{"recurso": "postgres:5433"}` escolhe o recurso disputado; o comando de container (`docker compose exec -T web pytest`) vai explícito depois do `--`.
- Configuração (modo da fila, vagas, teto, processos): `agent-pool config get fila` e `agent-pool config set fila.modo=banco fila.vagas=2 fila.teto=3 fila.processos=8`. Vale só para testes iniciados depois.

## Exit 75 e estado
- **Sem vaga a tempo → `FILA OCUPADA`, exit 75: rodar de novo.** A espera máxima padrão é 5 min; a vaga do teto da máquina vem depois da da fila, no mesmo prazo.
- Estado da fila (rodando, aguardando, parados): `agent-pool status` (`--json` para detalhes). Trava de processo morto é recuperada pelo próprio CLI.
- Modos (`fila.modo`): `banco` (padrão, uma fila por recurso disputado), `global` (uma para a máquina) e `projeto` (uma por projeto, compartilhada pelos worktrees). O teto da máquina vale nos três.

## Regras
- Subagente de etapa roda só o teste novo e até 5 arquivos editados, um por chamada; pasta e suíte uma vez na integração.
- **Duas execuções no mesmo worktree corrompem uma à outra** (`Duplicate entry '1'`, `Table 'users' already exists`, `Unknown column`, deadlock em `alter table`). Banco próprio por trilha: `DB_DATABASE=<banco>_sN agent-pool test -- …`.
- **Falha que surge com a máquina carregada: re-rodar o arquivo isolado antes de investigar.**
- **Servidor de teste**: no modo `banco`, a fila da suíte é a da **porta do `DB_PORT` do `.env.testing`** (padrão de dois servidores: dev em 3306, teste em 3307; skill `ambiente-local`). A fila do 3307 é independente da do 3306 e o drop dos `_test_N` acontece nele.
- **Memória do servidor de teste**: pesa o número de **tabelas abertas** (~1,6 MB cada, com triggers compilados) = processos paralelos × tabelas por banco; `table_open_cache` alto com schema grande passou de 16–30 GB e travou a máquina. Sintoma: servidor de teste crescendo a cada run — conferir `table_open_cache` (2500 no teste, ver `ambiente-local/ferramentas/herd.md`) antes de culpar a suíte; menos `fila.processos` também alivia.
- **`FLUSH TABLES` trava com teste rodando**: não usar com a fila ocupada. Reiniciar o servidor de teste é seguro (banco descartável), mas só com a fila vazia (`agent-pool status`); run em andamento morre junto.
- **Processo morto deixa bancos paralelos em estado misto**: matar os processos órfãos do worktree e dropar os `_test_N`; o primeiro run depois costuma falhar em massa — rodar de novo.
- Suíte longa passa de 10 min e cai para background: esperar a notificação, sem polling. **Nunca `| tail`** em run que pode estourar: redirecionar para arquivo.
- Teste que passa por coincidência não protege: **forçar a divergência** entre ids que deveriam diferir.

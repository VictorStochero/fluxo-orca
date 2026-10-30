---
name: fila-testes
description: Use antes de rodar qualquer teste (artisan test/pest, pytest, manage.py test, vitest, jest, npm/pnpm/yarn/bun test) ou quando perguntarem sobre a fila de testes (ocupação, vagas, travas, teto) — filas da máquina (2 vagas por recurso e teto global de 3 runs), para worktrees e agentes em paralelo não derrubarem a máquina nem corromperem bancos de teste.
---

# Fila de testes da máquina

`~/.cache/gs-teste.sh` (instalado e atualizado pelo hook de SessionStart do plugin) é um semáforo: até **2** runs por fila (porta de banco, container ou geral) e, somando todas as filas, no máximo **3** na máquina (teto global), entre todos os worktrees e sessões. O hook `fila-testes.sh` bloqueia os executores de teste fora dele; listagem (`--list-tests`, `--collect-only`, `vitest list`, `--listTests`) e instalação de pacote (`composer install|require` incluso) passam livres. Cobre também `composer test`, `cargo test`, `go test` e `python -m unittest`. O dono da vaga é a raiz do git: rodar de subpasta do mesmo worktree conta como o mesmo dono.

## Como chamar (no cwd do projeto/worktree)
- `bash ~/.cache/gs-teste.sh <argumentos>` — detecta o executor:

  | Projeto | Executor |
  |---|---|
  | Laravel (`artisan`) | `ddev artisan test` (`.ddev/`), `./vendor/bin/sail artisan test` (Sail), senão `php artisan test` |
  | Python | `uv run pytest`, `poetry run pytest`, `pipenv run pytest`, `.venv/…/pytest` ou `python -m pytest` |
  | JS (`package.json`) | `pnpm test`, `yarn test`, `bun run test` ou `npm test --` (pelo lockfile) |
  | Rust (`Cargo.toml`) / Go (`go.mod`) | `cargo test` / `go test` (fila geral; Go: passe `./...`) |

- `bash ~/.cache/gs-teste.sh -- <comando completo>` — executor explícito (`-- python manage.py test app`, `-- pnpm vitest run src/x.test.ts`).
- Preparação do banco de teste também passa pela fila: `bash ~/.cache/gs-teste.sh -- php artisan migrate:fresh --env=testing --force` (idem `migrate:*`, `db:wipe` e `db:seed`). Com `artisan` no cwd, o executor explícito usa a fila Laravel por porta de `.env.testing` (PHP) ou de container, preservando o comando.
- O detector bloqueia essas operações com `--env=testing` (ou `--env testing`) ou `--database` com token `test`/`testing` no nome da conexão (`test`, `testing`, `mysql_test`, `test_mysql`). Conexão com nome arbitrário precisa de `--env=testing`; sem indicação de teste, operações do banco de desenvolvimento continuam livres.
- Django: `manage.py migrate|flush` com `--settings=*test*` também exige fila, por exemplo `bash ~/.cache/gs-teste.sh -- python manage.py migrate --settings=app.settings.test`. A opção de teste deve estar no mesmo trecho do comando que a operação de banco.
- Projeto em container ou com executor próprio: `GS_TESTE_RUNNER="<comando>"` no `.orca/worktree.conf` do principal (ex.: `docker compose exec -T web pytest`) — vale para todos os worktrees.
- Sem vaga em 5 min → `FILA OCUPADA` (exit 75): rodar de novo. `GS_TESTE_VAGAS`, `GS_TESTE_TETO` e `GS_TESTE_PROCESSOS` sobrescrevem 2 vagas, 3 do teto e 8 processos. A vaga do teto vem depois da da fila, no mesmo prazo de 5 min.

## Consultar o estado da fila

```bash
for d in ~/.cache/gs-teste*.lock*; do [ -d "$d" ] && echo "$(basename "$d"): $(cat "$d/dono" 2>/dev/null)"; done
```

Cada diretório é uma vaga ocupada ou uma trava pendente de recuperação; `dono` mostra worktree, banco e comando. `gs-teste-teto.lockN` ocupa o teto global e corresponde ao mesmo run de uma vaga de recurso: não somar os dois como runs distintos. Sem diretórios, nenhuma vaga está ocupada; dono vazio exige conferir a trava, sem presumir que está livre. O padrão é 2 vagas por recurso e teto de 3 runs, sobrescrito por `GS_TESTE_VAGAS` e `GS_TESTE_TETO` na execução.

## Regras
- `GS_TESTE_FILA=projeto` troca a fila por recurso pela fila do projeto, com `GS_TESTE_VAGAS_PROJETO` vagas (padrão 1), mantendo o teto global. Worktrees compartilham a fila `gs-teste-proj-<nome>.lockN`, pelo nome saneado do checkout principal; fora do Git, vale o nome do diretório atual. Projetos diferentes têm filas distintas. O padrão continua `GS_TESTE_FILA=recurso`, com vagas por porta/container/geral; espera e `FILA OCUPADA` mostram a fila e seus donos.
- Laravel, suíte e pasta em paralelo: `bash ~/.cache/gs-teste.sh --parallel --compact <path>` (8 processos; apaga os `<banco>_test_N` ao terminar). **`--parallel` aceita UM path.** **`--parallel` é obrigatório para usar vários processos**: `GS_TESTE_PROCESSOS` sem ele é ignorado e a suíte roda em 1 processo.
- **Servidor de teste**: a fila da suíte é a da **porta do `DB_PORT` do `.env.testing`** (padrão de dois servidores: dev em 3306, teste em 3307; skill `ambiente-local`). Duas vagas por servidor de teste, então a fila do 3307 é independente da do 3306, e o drop dos `_test_N` ao terminar acontece nele.
- **Memória do servidor de teste**: pesa o número de **tabelas abertas** (~1,6 MB cada, com triggers compilados) = processos paralelos × tabelas por banco; `table_open_cache` alto com schema grande (ex.: 12 processos × ~230 tabelas com triggers de auditoria) passou de 16–30 GB e travou a máquina. Sintoma: servidor de teste crescendo a cada run e a máquina engasgando — conferir `table_open_cache` (2500 no teste, ver `ambiente-local/ferramentas/herd.md`) antes de culpar a suíte. Menos processos (`GS_TESTE_PROCESSOS`, com `--parallel`) também alivia.
- **`FLUSH TABLES` trava com teste rodando** (espera as tabelas em uso): não usar com a fila ocupada. Para liberar memória, reiniciar o servidor de teste é seguro — o banco é descartável — mas só com a fila vazia (conferir o estado acima); run em andamento morre junto.
- Banco próprio por trilha: `DB_DATABASE=<banco>_sN bash ~/.cache/gs-teste.sh ...`. Mesmo worktree + mesmo banco nunca rodam juntos.
- Subagente de etapa roda só o teste novo e até 5 arquivos editados, um por chamada; pasta e suíte uma vez na integração.
- **Falha que surge com a máquina carregada: re-rodar o arquivo isolado antes de investigar.**
- **Duas execuções no mesmo worktree corrompem uma à outra** (`Duplicate entry '1'`, `Table 'users' already exists`, `Unknown column`, deadlock em `alter table`).
- Se o `gs-teste.sh` morre à força (timeout da ferramenta), o executor fica órfão; o próximo run encerra a árvore dele (pid em `<vaga>/filho`) antes de liberar a vaga.
- **Processo morto deixa bancos paralelos em estado misto**: matar os processos órfãos do worktree e dropar os bancos `_test_N`; o primeiro run depois costuma falhar em massa — rodar de novo.
- Suíte longa passa de 10 min e cai para background: esperar a notificação, sem polling. **Nunca `| tail`** em run que pode estourar: redirecionar para arquivo.
- Teste que passa por coincidência não protege: **forçar a divergência** entre ids que deveriam diferir.
- CLI externo (Codex, agy) tem o mesmo bloqueio, pelo `guarda-externos.sh` (detector `e-teste.sh`, copiado para `~/.cache`); o prompt do worker ainda manda usar a fila.
- Filas separadas: Laravel no host uma por porta de banco (a do `.env.testing`); container uma; Python/JS uma.

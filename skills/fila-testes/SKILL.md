---
name: fila-testes
description: Use antes de rodar qualquer teste (artisan test/pest, pytest, manage.py test, vitest, jest, npm/pnpm/yarn/bun test) — filas da máquina (2 vagas por recurso e teto global de 3 runs), para worktrees e agentes em paralelo não derrubarem a máquina nem corromperem bancos de teste.
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
- Projeto em container ou com executor próprio: `GS_TESTE_RUNNER="<comando>"` no `.orca/worktree.conf` do principal (ex.: `docker compose exec -T web pytest`) — vale para todos os worktrees.
- Sem vaga em 5 min → `FILA OCUPADA` (exit 75): rodar de novo. `GS_TESTE_VAGAS`, `GS_TESTE_TETO` e `GS_TESTE_PROCESSOS` sobrescrevem 2 vagas, 3 do teto e 8 processos. A vaga do teto vem depois da da fila, no mesmo prazo de 5 min.

## Regras
- Laravel, suíte e pasta em paralelo: `bash ~/.cache/gs-teste.sh --parallel --compact <path>` (8 processos; apaga os `<banco>_test_N` ao terminar). **`--parallel` aceita UM path.**
- Banco próprio por trilha: `DB_DATABASE=<banco>_sN bash ~/.cache/gs-teste.sh ...`. Mesmo worktree + mesmo banco nunca rodam juntos.
- Subagente de etapa roda só o teste novo e até 5 arquivos editados, um por chamada; pasta e suíte uma vez na integração.
- **Falha que surge com a máquina carregada: re-rodar o arquivo isolado antes de investigar.**
- **Duas execuções no mesmo worktree corrompem uma à outra** (`Duplicate entry '1'`, `Table 'users' already exists`, `Unknown column`, deadlock em `alter table`).
- Se o `gs-teste.sh` morre à força (timeout da ferramenta), o executor fica órfão; o próximo run encerra a árvore dele (pid em `<vaga>/filho`) antes de liberar a vaga.
- **Processo morto deixa bancos paralelos em estado misto**: matar os processos órfãos do worktree e dropar os bancos `_test_N`; o primeiro run depois costuma falhar em massa — rodar de novo.
- Suíte longa passa de 10 min e cai para background: esperar a notificação, sem polling. **Nunca `| tail`** em run que pode estourar: redirecionar para arquivo.
- Teste que passa por coincidência não protege: **forçar a divergência** entre ids que deveriam diferir.
- CLI externo (Codex, agy, Kimi) tem o mesmo bloqueio, pelo `guarda-externos.sh` (detector `e-teste.sh`, copiado para `~/.cache`); o prompt do worker ainda manda usar a fila.
- Filas separadas: Laravel no host uma por porta de banco; container uma; Python/JS uma.

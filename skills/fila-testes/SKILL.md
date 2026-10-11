---
name: fila-testes
description: Use antes de rodar qualquer teste PHP (php artisan test, pest) — fila única da máquina com 2 vagas por instância MariaDB, para worktrees e agentes em paralelo não derrubarem a máquina nem corromperem bancos de teste.
---

# Fila de testes da máquina

`~/.cache/gs-teste.sh` (instalado e atualizado pelo hook de SessionStart do plugin) é um semáforo: até **2** `php artisan test` por vez entre todos os worktrees e sessões, uma fila por instância MariaDB (`DB_PORT` do `.env.testing`). O hook `fila-testes.sh` bloqueia `artisan test`/`pest` fora dele (`--list-tests` passa livre).

- **Sempre**: `bash ~/.cache/gs-teste.sh <args do artisan test>`, no cwd do worktree. Sem vaga em 5 min → `FILA OCUPADA` (exit 75): rodar de novo.
- **Suíte e pasta sempre em paralelo**: `bash ~/.cache/gs-teste.sh --parallel --compact <path>` (o script força 8 processos e apaga os `<banco>_test_N` ao terminar). **`--parallel` aceita UM path.**
- Banco próprio por trilha: `DB_DATABASE=<banco>_sN bash ~/.cache/gs-teste.sh ...`. Mesmo worktree + mesmo banco nunca rodam juntos.
- Subagente de etapa roda só o teste novo e até 5 arquivos editados, um por chamada; pasta e suíte uma vez na integração.
- **Falha que surge com a máquina carregada: re-rodar o arquivo isolado antes de investigar.**
- **Duas execuções no mesmo worktree corrompem uma à outra** (`Duplicate entry '1'`, `Table 'users' already exists`, `Unknown column`, deadlock em `alter table`).
- **Processo morto deixa bancos paralelos em estado misto**: matar os `php.exe` órfãos do worktree e dropar os `<banco>_test_test_N`; o primeiro run depois costuma falhar em massa — rodar de novo.
- Suíte longa passa de 10 min e cai para background: esperar a notificação, sem polling. **Nunca `| tail`** em run que pode estourar: redirecionar para arquivo.
- Teste que passa por coincidência não protege: **forçar a divergência** entre ids que deveriam diferir.
- CLI externo (agy, kimi) não tem o hook: o prompt do worker manda usar a fila explicitamente.
- Vagas: `VAGAS=2` no topo do script; máquina mais forte pode subir.

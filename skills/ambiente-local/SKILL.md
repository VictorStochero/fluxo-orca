---
name: ambiente-local
description: Use ao rodar testes, montar/consertar worktree, mexer em banco local, Herd, MariaDB, composer/npm/boost:install, ou validar tela no navegador (Orca/Playwright) numa máquina Windows + Herd — fila de testes, bancos por worktree, armadilhas conhecidas.
---

# Ambiente local — Windows 11 + Herd Pro

- Código em `%USERPROFILE%\Herd\<repo>` (Git Bash: `~/Herd/<repo>`). Worktrees são pastas irmãs `<repo>-<flag>-<contexto>`. Subpasta de `Herd` vira `https://<pasta>.test`; o setup roda `herd secure`.
- **PHP, Composer, MariaDB, Redis, Reverb e Mailpit vêm do Herd** — `php artisan`, `composer`, `npm`, `php vendor/bin/pint` sem prefixo. Se a versão do MariaDB de produção for diferente da local, nada pode depender de comportamento exclusivo da versão local.
- **MariaDB do Herd com `root` sem senha** em `127.0.0.1:3306`. Um projeto que precise de instância própria usa outra porta (`DB_PORT` no `.env`/`.env.testing`) e tem fila de testes própria. Bancos com o nome da pasta: `<pasta com _>` (dev) e `<pasta com _>_test`. **Nunca** apontar a suíte para banco compartilhado. Multi-tenant: `TENANCY_DB_PREFIX` exclusivo de teste.
- Bash é **Git Bash**. `php.bat` não roda no Git Bash: criar shims `~/bin/php` e `~/bin/composer`. `herd` no Git Bash é `herd.bat`. Symlink sem administrador exige o Modo de Desenvolvedor do Windows.
- **Orca**: CLI `orca` no PATH (ou `ORCA_CLI_COMMAND`).

## Testes
- Sempre pela fila da máquina: skill `fila-testes` (`bash ~/.cache/gs-teste.sh <args>`).
- Worktree novo: plugin `laravel-worktree` (`/worktree <flag> <contexto>`) — banco e `.env.testing` próprios.

## Armadilhas
- **Triggers de schema dump com `DEFINER='root'@'%'`**: o usuário `root@'%'` precisa existir (senha aleatória, `ACCOUNT LOCK`). Herd reinstalado → recriar, senão o seed quebra com `1449 ... definer does not exist`.
- **Cache do MariaDB**: o Herd lê só `~/.config/herd/bin/services/mariadb/<versão>/my.ini`. Em schema grande, subir `table_definition_cache=20000`, `table_open_cache=20000`, `innodb_buffer_pool_size=4G`, `innodb_flush_log_at_trx_commit=2`, `innodb_log_file_size=512M`. Versão nova do MariaDB cria pasta sem o arquivo — repor e `herd services:stop|start <id>`. Sem isso `information_schema.triggers` leva minutos. Filtrar por `event_object_schema`, nunca `trigger_schema`.
- **Schema dump é carregado pelo cliente `mariadb`**: script não interativo exporta a pasta `bin` do MariaDB do Herd.
- **`boost:install` tem timeout de 60 s no `--list-tests`**: em suíte grande, `config/boost.php` temporário com `return ['enforce_tests' => true];`. Roda **sem `--mcp`**; o `.mcp.json` aponta para o `php.exe` do Herd (`~/.config/herd/bin/php84/php.exe artisan boost:mcp`). Boost só existe com `.env` local.
- **A tool `Grep` respeita o `.gitignore`**: em pasta ignorada (ex.: `docs/superpowers/`) usar `grep -r`.
- **`composer install`** leva minutos com `vendor/` vazio: foreground, `timeout: 600000`, sem matar. Repo privado: `COMPOSER_AUTH="{\"github-oauth\":{\"github.com\":\"$(gh auth token)\"}}" composer install`.
- **Setup não pode sujar o git**: `npm ci`; conferir `git status` após `boost:install`; o que for só local vai para `.git/info/exclude`.
- **Rector**: no worktree de tarefa só em arquivos explícitos (lotes de ~150); completo só na integração.

## Validação de UI
- **Toda mudança de UI é validada no browser, com perfil real, nunca `super_admin`.**
- **Comparação visual com a branch base**: mesmas telas, perfil e largura na base e no worktree; cada diferença classificada como esperada ou regressão.
- **Padrão: navegador embutido do Orca, um por worktree.** Antes, invocar o skill `orca-cli` e ler `orca skills get orca-cli --reference references/browser.md`. Fluxo: `orca tab create --url https://<pasta>.test/login --json` → `snapshot --page <id>` → `fill`/`click --element @eN` → `wait` → `snapshot` de novo após navegar. **Sempre `--page <browserPageId>`** (sem ele vai para a aba do usuário).
- **Fallback: Playwright MCP.** Chrome DevTools MCP só para trace, Lighthouse, heap. Nunca matar o navegador de outro agente. Em subagente: `take_screenshot` em vez de `take_snapshot` (a árvore do Filament derruba o agente).
- Screenshot, trace e `.playwright-mcp/` vão para o worktree de quem gerou ou para o temporário, e não se commitam.

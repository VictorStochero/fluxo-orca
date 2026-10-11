---
name: stack-laravel
description: Use antes de escrever, revisar ou testar código PHP num projeto Laravel (composer.json com laravel/framework) — boas práticas, Boost, validação (pint, PHPStan, Pest), testes pela fila, worktree e armadilhas.
---

# Stack Laravel

## Antes de escrever
- **Invocar `laravel-best-practices`** (skill que o Laravel Boost instala no projeto) e as skills do projeto que tocarem a tarefa (`.claude/skills`, `.ai/skills`: Filament, Pest, Tailwind, Livewire…). O hook `guia-laravel.sh` bloqueia editar `.php` sem o skill carregado e sem o guia de arquitetura lido na sessão.
- **`laravel/boost` obrigatório** (`composer require laravel/boost --dev`; `php artisan boost:install --skills --no-interaction`, sem `--mcp`). Usar as ferramentas dele (search-docs, application-info, tinker, database-query) em vez de supor API ou versão.
- Seguir o `CLAUDE.md`/`AGENTS.md` do projeto (guidelines do Boost) e os vizinhos: `php artisan make:*` para criar arquivos, `--no-interaction` em todo artisan.

## Validar (após cada etapa)
1. `vendor/bin/pint --dirty --format agent`.
2. Teste de regressão pela fila: `bash ~/.cache/gs-teste.sh --compact <arquivo>`; pasta ou suíte em paralelo: `bash ~/.cache/gs-teste.sh --parallel --compact <path>` (um path).
3. PHPStan/Larastan nos arquivos tocados, se houver `phpstan.neon`.
4. `composer dump-autoload` ao criar/renomear classe; `php artisan route:list --except-vendor` ao mexer em rotas/Resources.
5. Listar a suíte sem rodar: `php artisan test --list-tests` (em suíte grande leva minutos).

## Testes
- Banco de teste próprio por worktree (`.env.testing` com `DB_DATABASE=<banco>_test`); `--parallel` cria `<banco>_test_N` (o `gs-teste.sh` apaga ao terminar).
- Multi-tenant (`config/tenancy.php`, stancl/tenancy): `TENANCY_DB_PREFIX` exclusivo por worktree e por ambiente de teste, senão os bancos `tenant_<id>` de um worktree são os do outro. Domínios (`CENTRAL_DOMAIN`, `TENANT_BASE_DOMAIN`, `SESSION_DOMAIN`) seguem o host do worktree; subdomínio de tenant precisa de DNS curinga local (DDEV e `*.localhost` do modo nativo resolvem; Laragon exige entrada no `hosts` por subdomínio; nas demais, conferir na referência da ferramenta em `ambiente-local`).
- DDEV/Sail: o `gs-teste.sh` detecta e roda dentro do container.

## Worktree
- Pelo Orca: `wt-setup.sh` (skill `worktree-orca`) faz `.env`, bancos, `composer install`, `npm ci`/build, `migrate --seed` (ou `WT_SEEDER`), `migrate --env=testing`, `storage:link`, `boost:install` e lista a suíte.
- Fora do Orca: `/worktree <flag> <contexto>` (plugin `laravel-worktree`).

## Armadilhas
- **`boost:install` tem timeout de 60 s no `--list-tests` interno**: em suíte grande, `config/boost.php` temporário com `return ['enforce_tests' => true];` (o `wt-setup.sh` faz). Sem TTY, `boost.json` com `{"agents":["claude_code"]}` evita o prompt.
- **`composer install`** leva minutos com `vendor/` vazio: foreground, timeout longo. Repo privado: `COMPOSER_AUTH="{\"github-oauth\":{\"github.com\":\"$(gh auth token)\"}}" composer install`. Windows: `ext-pcntl`/`ext-posix` ausentes → `--ignore-platform-req=ext-pcntl --ignore-platform-req=ext-posix`.
- **Triggers de schema dump com `DEFINER='root'@'%'`**: o usuário `root@'%'` precisa existir no MySQL/MariaDB local (senha aleatória, `ACCOUNT LOCK`), senão o seed quebra com `1449 ... definer does not exist`. Filtrar `information_schema.triggers` por `event_object_schema`, nunca `trigger_schema`.
- **Schema dump é carregado pelo cliente `mysql`/`mariadb`**: o binário precisa estar no `PATH` do script não interativo.
- **Rector**: no worktree de tarefa só em arquivos explícitos (lotes de ~150); completo só na integração.
- **Setup não pode sujar o git**: conferir `git status` após `boost:install`; o que for só local vai para `.git/info/exclude`.

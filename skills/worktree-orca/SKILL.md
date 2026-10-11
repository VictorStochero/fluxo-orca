---
name: worktree-orca
description: Use ao configurar um projeto no Orca (setup/archive de worktree), ao criar worktree de tarefa pelo Orca ou ao ajustar o .orca/worktree.conf de um projeto — setup e limpeza genéricos para Laravel, Python e JS, com banco próprio por worktree e multi-tenant.
---

# Worktree pelo Orca

Dois scripts genéricos, instalados em `~/.cache` pelo hook de SessionStart do plugin (com `wt-lib.sh`):

| Orca > repo > | Comando |
|---|---|
| setup script | `bash ~/.cache/wt-setup.sh` |
| archive script | `bash ~/.cache/wt-archive.sh <caminho do checkout principal>` |

Criar a tarefa: `orca orchestration worker-start --worktree new-child --name {repo}-{flag}-{contexto} --base-branch origin/<base> --setup run …` (skill `delegacao`).

## O que o setup faz
1. Detecta a stack (`artisan` → Laravel; `pyproject.toml`/`requirements*.txt`/`Pipfile` → Python; `package.json` → JS) e quem serve o site (`WT_SITES`: `ddev`, `herd`, `lerd`, `laragon`, `flyenv`, `nativo`; Sail fica com `/worktree` do plugin `laravel-worktree`).
2. URL: `https://<pasta>.test` (Herd/Laragon/Lerd/FlyEnv), `https://<pasta>.ddev.site`, ou `http://<pasta>.localhost:<porta>` no nativo (porta estável por pasta; `*.localhost` aceita subdomínio de tenant).
3. `.env`, `.env.local`, `.env.testing`, `.env.test` do principal (ou `.env.testing.example-<ambiente>`): host antigo → novo em todo valor (exceto quando o host é `localhost`/IP, que também é o do banco e do Redis); **toda chave de nome de banco** (`*DATABASE*`, `DB_NAME`, `*_DB`, `*BASENAME*`; nunca usuário, senha, host) cujo valor era o banco do principal passa a `<banco>` (teste: `<banco>_test`), inclusive dentro de `DATABASE_URL`; só com MySQL/MariaDB/Postgres identificado (SQLite fica como está); Laravel ganha `REDIS_PREFIX`/`CACHE_PREFIX` próprios (no `.env.testing` com `_test_`); multi-tenant ganha `TENANCY_DB_PREFIX=<banco>_tenant_` / `<banco>_test_tenant_`.
4. Cria `<banco>` e `<banco>_test` (MySQL/MariaDB ou Postgres; cliente nativo, senão PDO do PHP). `<banco>` = nome da pasta com `_` (máx. 59; 40 em multi-tenant).
5. Serve o site (Herd: `herd secure`; Lerd: `lerd link`; Laragon/FlyEnv/nativo: imprime o passo manual).
6. Dependências pelo gerenciador detectado (composer; uv/poetry/pipenv/venv; pnpm/yarn/bun/npm), build do front em Laravel, migração e seed, `boost:install` em Laravel com Boost — arquivo versionado que ele regravar (`AGENTS.md`/`CLAUDE.md` customizados, `boost.json`) volta ao do repositório.
7. Lista a suíte sem rodar e avisa se o setup sujou o git.

## O que o archive faz
O nome do banco vem do **registro que o setup grava** em `<.git comum>/wt-bancos/<pasta>`; **sem registro (worktree criado fora do `wt-setup.sh`), não remove banco nenhum** — limpar à mão. **Aborta sem remover nada** se: houver alteração não commitada; o git falhar; o banco do worktree for ou abranger (`<banco>_*`) qualquer banco do principal — de `.env`, `.env.local`, `.env.testing` ou `.env.test` (o setup recusa o mesmo caso, ex.: pasta `<repo>-test`); outro worktree vivo usar o mesmo banco. Senão: DDEV → `ddev delete`; banco no host → apaga `<banco>`, `<banco>_test` e tudo que começa com `<banco>_` (tenants, `_test_test_N`, `_template`, `_pool_*`), preservando os de outro worktree vivo cujo nome começa com `<banco>_`. Log em `~/.cache/wt-archive.log`.

## `.orca/worktree.conf` do projeto
Arquivo bash no checkout principal, local (`.orca/` no `.git/info/exclude`). Tudo opcional:

```bash
WT_SITES=herd                      # herd|laragon|lerd|flyenv|nativo|ddev — auto se vazio
WT_BASE=origin/homologacao         # branch base; auto: desenvolvimento, dev, develop, homologacao, main, master
WT_INSTALAR="pnpm install"         # substitui a instalação detectada
WT_MIGRAR="uv run alembic upgrade head"
WT_SEED="uv run python -m app.seed"
WT_SEEDER=LocalDemoSeeder          # Laravel: migrate + db:seed --class
WT_SEM_SEED=1                      # Laravel: só migrate
WT_BUILD=0                         # Laravel: sem npm run build
WT_COPIAR=".mcp.json .claude/settings.local.json"   # arquivos locais copiados do principal
WT_PORTA_BASE=8000                 # nativo: porta = base + 1..900
GS_TESTE_RUNNER="docker compose exec -T web pytest" # comando de teste da fila (skill fila-testes)
WT_POS_SETUP() { php artisan tenants:seed --force; }  # passo extra no fim
```

## Limites conhecidos
- Sail: portas e `COMPOSE_PROJECT_NAME` únicos por worktree — `/worktree` (plugin `laravel-worktree`).
- Compose próprio (Python/JS em container): `WT_INSTALAR`, `WT_MIGRAR` e `WT_POS_SETUP` com `docker compose -p <pasta> …`; o banco fica no container e o archive não o vê (`docker compose -p <pasta> down -v` no `WT_POS_SETUP` de limpeza manual).
- Hosts permitidos de Python/JS (`ALLOWED_HOSTS`, CORS) só mudam se o principal tiver `APP_URL`; senão ajustar no `WT_POS_SETUP`.
- Laragon/FlyEnv não resolvem subdomínio curinga: tenant por subdomínio precisa de entrada no hosts ou do modo nativo (`*.localhost`).

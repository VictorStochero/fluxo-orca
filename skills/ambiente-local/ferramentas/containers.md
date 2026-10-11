# Containers: DDEV, Sail e compose (Docker ou Podman)

- **Comandos do projeto rodam dentro do container**; `git` sempre no host. Misturar (`php artisan` no host num projeto DDEV) usa o banco errado.
- Motor: Docker Desktop (Windows/macOS, WSL2 no Windows), Docker Engine (Linux), OrbStack (macOS) ou **Podman** (rootless; Podman Desktop no Windows/macOS).

## DDEV
- `ddev config --project-name=<pasta>`, `ddev start|stop`, `ddev delete --omit-snapshot --yes <projeto>` (sem `--yes` trava pedindo confirmação). URL `https://<projeto>.ddev.site` (curinga de subdomínio incluso).
- `ddev composer`, `ddev artisan`, `ddev npm`, `ddev exec <cmd>`, `ddev mysql`. Banco isolado por projeto (host `db`, usuário/senha `db`).
- **Podman e Docker rootless: experimentais desde o DDEV 1.25.0** (Linux e WSL2 principalmente); o DDEV detecta o motor pelo contexto do Docker. No macOS o Podman não abre 80/443 — DDEV usa portas alternativas.
- Fila e worktree: `gs-teste.sh` roda `ddev artisan test`; `wt-setup.sh`/`wt-archive.sh` fazem `ddev config/start` e `ddev delete`.

## Sail
- `./vendor/bin/sail up -d|down -v`, `sail artisan`, `sail composer`, `sail npm`, `sail test`. Precisa de `composer install` no host (ou container descartável) para existir `vendor/bin/sail`.
- **Vários worktrees ao mesmo tempo**: `COMPOSE_PROJECT_NAME` e **todas** as portas publicadas únicas (`APP_PORT`, `VITE_PORT`, `FORWARD_DB_PORT`, `FORWARD_*_PORT`) — o `/worktree` do plugin `laravel-worktree` faz; o `wt-setup.sh` não.
- Podman: o Sail chama `docker compose`; com Podman, instalar o shim `podman-docker` (ou `alias docker=podman`) e o `podman compose`/`docker-compose`, e apontar `DOCKER_HOST` para o socket do Podman. Conferir na primeira vez.

## Compose próprio (Python, JS, Laravel sem Sail)
- Isolar por worktree com `-p <pasta>` (`docker compose -p <pasta> up -d`) e portas por variável no `.env`.
- Testes: `GS_TESTE_RUNNER="docker compose exec -T <serviço> <comando de teste>"` no `.orca/worktree.conf` (`-T`: sem TTY, senão trava fora do terminal).
- Setup: `WT_INSTALAR`, `WT_MIGRAR`, `WT_POS_SETUP` com `docker compose -p <pasta> …`; limpeza: `docker compose -p <pasta> down -v` (o `wt-archive.sh` não enxerga banco em container).

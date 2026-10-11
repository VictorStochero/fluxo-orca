# Lerd (Linux e macOS; Windows só via WSL2)

> Não testado por nós: conferir na versão instalada (`lerd --help`) e corrigir aqui o que divergir.

- Alternativa ao Herd com **Podman rootless**: Nginx, PHP-FPM e serviços em containers compartilhados, sem Docker Desktop.
- Instalar: `curl -fsSL https://lerd.sh/install.sh | bash`; Ubuntu/Debian `ppa:lerd/lerd`; Fedora `copr georged/lerd`; Homebrew `lerd-env/lerd/lerd` + `lerd install`.
- Sites: `lerd park <dir>` (descobre as pastas) ou `lerd link` na pasta → `https://<projeto>.test` com TLS. `lerd open`, `lerd start|stop|quit`, `lerd doctor --fix`.
- **Worktrees**: o Lerd detecta `git worktree add` sozinho e dá domínio próprio a cada um; o `wt-setup.sh` ainda roda `lerd link` (inofensivo se já estiver ligado). Conferir a URL real com `lerd open` e, se o padrão for outro, ajustar `APP_URL` no `WT_POS_SETUP`.
- PHP e Node por projeto (painel web). Comandos `php`/`composer` no host: conferir com `command -v php` — se não houver, rodar pelo que o Lerd expõe e registrar no perfil.
- Serviços: `lerd service preset <nome>` (MySQL, Postgres, Redis, Mailpit…); `mysql` e `psql` funcionam no host contra os motores do Lerd. Porta e credenciais: registrar no perfil da máquina.

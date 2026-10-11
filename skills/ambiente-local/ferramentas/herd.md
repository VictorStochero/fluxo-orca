# Laravel Herd (Windows e macOS)

- Pasta estacionada padrão `~/Herd`: cada subpasta vira `https://<pasta>.test` (worktree irmão já sai publicado). `herd park <dir>`, `herd link`, `herd secure <site>` (o `wt-setup.sh` roda), `herd sites`, `herd links`.
- **PHP, Composer e Node vêm do Herd.** Binários: Windows `~/.config/herd/bin` (`php.bat`, `composer.phar`); macOS `~/Library/Application Support/Herd/bin`. Versão por site: `herd isolate <versão>` / `herd use <versão>`.
- **Bancos e serviços só no Herd Pro** (MySQL, MariaDB, Postgres, Redis, Meilisearch, Mailpit, Reverb): `herd services:list`, `herd services:start|stop <id>`. Herd grátis → banco de outra ferramenta (Laragon, DBngin, FlyEnv, Docker); o perfil da máquina diz qual.
- MariaDB/MySQL do Herd: `root` sem senha em `127.0.0.1:<porta>`; o cliente fica em `~/.config/herd/bin/services/mariadb/<versão>/bin` (o `wt-lib.sh` acha sozinho).

## Windows + Git Bash
- `php.bat` e `composer.bat` não rodam no Git Bash: shims em `~/bin` (o GUIA cria):
  ```sh
  # ~/bin/php
  exe=$(sed -n 's/^"\(.*php\.exe\)".*/\1/p' "$HOME/.config/herd/bin/php.bat" | tr -d '\r')
  exec "$(cygpath -u "$exe")" "$@"
  # ~/bin/composer
  exec php "$(cygpath -w "$HOME/.config/herd/bin/composer.phar")" "$@"
  ```
- `herd` no Git Bash é `herd.bat`. Symlink sem administrador exige o Modo de Desenvolvedor.
- `.mcp.json` do Boost aponta para o `php.exe` do Herd (`~/.config/herd/bin/php84/php.exe artisan boost:mcp`).
- `composer install` sem `ext-pcntl`/`ext-posix` (Horizon): `--ignore-platform-req=ext-pcntl --ignore-platform-req=ext-posix`.

## Armadilhas
- **Cache do MariaDB**: o Herd lê só `~/.config/herd/bin/services/mariadb/<versão>/my.ini`. Schema grande: `table_definition_cache=20000`, `table_open_cache=20000`, `innodb_buffer_pool_size=4G`, `innodb_flush_log_at_trx_commit=2`, `innodb_log_file_size=512M`. Versão nova do MariaDB cria pasta sem o arquivo — repor e `herd services:stop|start <id>`.
- Herd reinstalado apaga usuários extras do banco (ex.: `root@'%'` de triggers com `DEFINER`) — recriar.
- Mais de uma instância de banco (portas diferentes) → cada uma tem fila de testes própria (skill `fila-testes`).

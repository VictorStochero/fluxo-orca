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
- **Dois MariaDB, um de dev e um só da fila de testes.** O Herd lê só `~/.config/herd/bin/services/mariadb/<versão>/my.ini` (um arquivo por **versão**, não por instância: dev e teste precisam de versões diferentes, ex.: 11.8.6 e 11.8.9). Segundo servidor: `herd services:available` → `herd services:create mariadb --name=teste --port=3307 --service-version=<outra versão>` → `herd services:list` (id) → editar o `my.ini` dessa versão → `herd services:stop <id>` e `herd services:start <id>`. Depois, o `DB_PORT` do `.env.testing` do principal aponta para 3307 (o `wt-setup.sh` cria o `<banco>_test` lá).
  - **Dev** (`[mysqld]`): `table_definition_cache=6000`, `table_open_cache=6000`, `innodb_buffer_pool_size=4G`, `innodb_flush_log_at_trx_commit=2`, `innodb_log_file_size=512M`; sem suíte paralela.
  - **Teste** (`[mysqld]`): `table_definition_cache=6000`, `table_open_cache=2500`, `innodb_buffer_pool_size=1G`, `innodb_flush_log_at_trx_commit=0`, `innodb_doublewrite=0`, `innodb_flush_method=O_DIRECT`, `innodb_log_file_size=512M`, `skip-log-bin`. Banco descartável: sem durabilidade.
  - Por quê: a memória vem das **tabelas abertas** (~1,6 MB cada, com os triggers compilados), não das definições; suíte de ~21.800 testes com 12 processos e ~230 tabelas com triggers por banco passou de 16–30 GB com `table_open_cache=20000` e travou a máquina. Com os valores acima: ~7 GB estáveis e ~300 testes/min (com `table_open_cache=6000`: 12 GB e ~200/min).
  - Versão nova do MariaDB cria pasta sem o arquivo — repor e reiniciar.
- Herd reinstalado apaga usuários extras do banco (ex.: `root@'%'` de triggers com `DEFINER`) — recriar.
- Mais de uma instância de banco (portas diferentes) → cada uma tem fila de testes própria (skill `fila-testes`); a da suíte é a porta do `.env.testing`.

# Nativo: Linux (apt/dnf) e macOS (Homebrew), sem gerenciador de ambiente

- **PHP**: Ubuntu/Debian pelo PPA `ondrej/php` (`php8.4-cli php8.4-{mbstring,xml,curl,mysql,pgsql,sqlite3,zip,bcmath,intl,gd,redis}`); Fedora pelo repositório Remi; macOS `brew install php` (ou `shivammathur/php` para várias versões). Composer pelo instalador oficial ou `brew install composer`.
- **Bancos como serviço**: `sudo systemctl enable --now mariadb|mysql|postgresql` (Linux), `brew services start mariadb|postgresql@16` (macOS).
- **MariaDB/MySQL no Debian/Ubuntu: `root` só entra por `sudo` (unix_socket)** — o `wt-setup.sh` e a fila conectam por TCP. Criar um usuário de desenvolvimento uma vez:
  ```sql
  CREATE USER 'dev'@'127.0.0.1' IDENTIFIED BY 'dev';
  GRANT ALL PRIVILEGES ON *.* TO 'dev'@'127.0.0.1' WITH GRANT OPTION;
  ```
  e usar `DB_USERNAME=dev`/`DB_PASSWORD=dev` nos projetos. Postgres: `sudo -u postgres createuser -s $USER` e senha se o projeto conectar por TCP.
- **Servir**: `php artisan serve --port=<porta>`, `npm run dev -- --port <porta>`, `manage.py runserver <porta>`. O `wt-setup.sh` no modo `nativo` dá a cada worktree `http://<pasta>.localhost:<porta estável>` — navegadores resolvem `*.localhost` para a máquina, inclusive subdomínio de tenant. Alternativas com `.test`: Valet Linux, Lerd (`lerd.md`) ou vhost no nginx.
- macOS: bash padrão é 3.2 — os scripts do plugin são compatíveis; `stat` é o BSD (`-f`), já tratado.
- Linux sem Git Bash: os hooks rodam no `bash` do sistema; nada de shim.

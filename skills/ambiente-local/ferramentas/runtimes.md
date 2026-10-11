# Versões de runtime

Ler a versão pedida pelo projeto antes de rodar qualquer coisa; nunca instalar pacote no runtime global do sistema.

| Runtime | Onde o projeto declara | Ferramenta |
|---|---|---|
| PHP | `composer.json` (`require.php`), `.php-version` | Herd (`herd isolate`), Laragon (menu), Lerd (painel), FlyEnv, `ondrej/php`/Remi, `shivammathur/php` (brew) |
| Python | `.python-version`, `requires-python` | **uv** (`uv python install`, `uv python pin`) — recomendado; pyenv (Linux/macOS), pyenv-win (Windows) |
| Node | `.nvmrc`, `.node-version`, `engines`, `volta` | **fnm** (`fnm use --install-if-missing`) — recomendado, roda em Windows/Linux/macOS; nvm (Linux/macOS), nvm-windows, Volta |
| pnpm / Yarn | `packageManager` no `package.json` | `corepack enable` (vem com o Node) |

- Windows + Git Bash: fnm precisa de `eval "$(fnm env --use-on-cd --shell bash)"` no `~/.bashrc`; uv e pyenv-win funcionam no Git Bash sem ajuste.
- Venv do Python é por pasta (`.venv` em cada worktree); `node_modules` também.

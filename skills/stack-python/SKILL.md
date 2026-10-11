---
name: stack-python
description: Use antes de escrever, revisar ou testar código num projeto Python (pyproject.toml, requirements*.txt, Pipfile, manage.py) — gerenciador de ambiente, validação (ruff, mypy/pyright), pytest pela fila, worktree e armadilhas.
---

# Stack Python

## Descobrir o projeto (antes de qualquer comando)
| Arquivo | Gerenciador | Instalar | Rodar |
|---|---|---|---|
| `uv.lock` | uv | `uv sync` | `uv run <cmd>` |
| `poetry.lock` | Poetry | `poetry install` | `poetry run <cmd>` |
| `Pipfile.lock` | Pipenv | `pipenv sync --dev` | `pipenv run <cmd>` |
| `requirements*.txt` | venv + pip | `python -m venv .venv && .venv/bin/pip install -r requirements-dev.txt` (Windows: `.venv/Scripts/pip`) | `.venv/bin/<cmd>` |

- Versão do Python: `.python-version` / `requires-python` (`uv python install`, pyenv ou pyenv-win). Nunca instalar pacote no Python do sistema.
- Ferramentas configuradas: ler `[tool.*]` do `pyproject.toml`, `setup.cfg`, `tox.ini`, `.pre-commit-config.yaml` — usar só o que o projeto já usa.
- Framework: Django (`manage.py`), FastAPI/Flask (app factory), Celery. Seguir o CLAUDE.md/AGENTS.md e o guia de arquitetura do projeto.

## Validar (após cada etapa)
1. Formatar e lintar os arquivos tocados com o que o projeto usa: `ruff format <arquivos>` + `ruff check --fix <arquivos>` (ou black/isort/flake8 se for o configurado).
2. Tipos, se configurado: `mypy <arquivos>` ou `pyright <arquivos>`.
3. Teste de regressão pela fila: `bash ~/.cache/gs-teste.sh <arquivo ou -k filtro>` (detecta uv/poetry/pipenv/venv e roda `pytest`); Django sem pytest: `bash ~/.cache/gs-teste.sh -- python manage.py test <app>`.
4. Listar sem rodar: `pytest --collect-only -q`.
5. Migração nova: `makemigrations --check` (Django) ou `alembic check`/`alembic upgrade head` num banco descartável.

## Testes
- Paralelo com `pytest-xdist` (`-n auto`) só se estiver instalado; banco de teste por processo é responsabilidade do projeto (Django cria `test_<banco>_gwN`).
- Banco de teste próprio por worktree (variável que o projeto usa: `DATABASE_URL`, `DB_NAME`, `POSTGRES_DB`…).

## Worktree
- Pelo Orca: `wt-setup.sh` (skill `worktree-orca`) copia o `.env`, troca banco e host, cria o banco (MySQL/MariaDB/Postgres no host), instala pelo gerenciador detectado e roda `WT_MIGRAR`/`WT_SEED` do `.orca/worktree.conf` (ex.: `WT_MIGRAR="uv run python manage.py migrate"`).
- `.venv` é por worktree (não compartilhar entre pastas).

## Armadilhas
- Windows: caminhos de venv são `Scripts/`, não `bin/`; Git Bash às vezes precisa de `winpty python` para REPL — scripts não.
- `pip install` sem venv ativo polui o Python global: sempre pelo gerenciador do projeto.
- Variáveis em `.env` não são lidas automaticamente pelo Python: o projeto usa `python-dotenv`, `django-environ` ou `pydantic-settings` — conferir antes de mudar nome de variável.

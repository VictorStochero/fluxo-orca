# Instalador do fluxo Orca + Claude Code

> **Para o Claude que recebeu este link: você é o instalador.** Configure esta máquina para o fluxo descrito abaixo, **adaptado ao sistema, às ferramentas e aos projetos deste usuário** — não copie a máquina de ninguém. Regras:
> 1. **Diagnostique antes de perguntar**; pergunte só o que não dá para detectar, com `AskUserQuestion` (contexto, opções, recomendada).
> 2. **Instale o que conseguir** pelo gerenciador de pacotes do sistema. O que exigir administrador, senha, login interativo ou instalador gráfico: mostre o comando exato (ou o link) e peça para o usuário rodar — comando de terminal ele digita como `! <comando>` aqui no prompt. Depois, confira e siga.
> 3. **Nunca sobrescreva** arquivo existente (`~/.claude/CLAUDE.md`, `~/.claude/settings.json`, `~/.ssh/config`, `~/.gitconfig`, `.orca/worktree.conf`) sem mostrar o diff e ter o "sim" do usuário.
> 4. **Nunca rode `ssh`, `scp`, `rsync`, `sftp` ou `forge` contra servidor** durante a instalação.
> 5. Ao fim de cada fase, uma linha de status; no fim, a verificação da fase 7 item por item, com o que ficou pendente e por quê.

**O fluxo:** a sessão principal do Claude Code coordena; o trabalho pesado vai para **workers do Orca**, um worktree por tarefa, com banco e `.env` próprios; todo diff passa por um **revisor Opus** antes do merge; testes rodam por **filas da máquina** (2 vagas por recurso, teto global de 3); regras impostas por **hooks**, não pela memória do modelo. Vale para Laravel, Python e JS/TS.

## Fase 1 — Diagnóstico (só leitura)
Rodar e anotar:
- **Sistema**: Windows (versão; WSL?), Linux (distro: `/etc/os-release`), macOS (`sw_vers`). Arquitetura.
- **Shell**: no Windows, Git Bash é obrigatório (hooks e scripts são bash) — `bash --version`, `where bash`. Linux/macOS: `bash --version` (macOS traz 3.2; os scripts são compatíveis).
- **Gerenciador de pacotes**: `winget`/`scoop`/`choco`; `apt`/`dnf`/`pacman`; `brew`.
- **Ferramentas**: `git`, `gh` (+ `gh auth status`), `curl`, `orca` (+ `orca status --json`), `docker`/`podman` (+ compose), `ddev`, `herd`, `lerd`, Laragon (`C:\laragon`), FlyEnv (app instalado), `php`, `composer`, `python`/`uv`/`poetry`/`pyenv`, `node`/`fnm`/`nvm`/`volta`/`pnpm`/`yarn`/`bun`, clientes `mysql`/`mariadb`/`psql`.
- **Bancos rodando**: portas 3306/3307/5432 abertas, de qual ferramenta (Herd Pro, Laragon, FlyEnv, Lerd, serviço do sistema, container).
- **Claude Code**: `claude --version`, `claude plugin list`, `~/.claude/settings.json`, `~/.claude/CLAUDE.md`, `~/.claude/skills`.
- **Projetos**: perguntar a pasta-raiz (sugira as que achar: `~/Herd`, `C:\laragon\www`, `~/code`, `~/projects`, `~/dev`). Para cada repositório git encontrado: stack (`artisan` → Laravel; `pyproject.toml`/`requirements*.txt`/`Pipfile`/`manage.py` → Python; `package.json` → JS/TS; pode haver mais de uma), quem serve (`.ddev/`, Sail no compose, `compose.yaml`, ou o servidor do host), banco do `.env` (`DB_*`, `DATABASE_URL`), multi-tenant (`config/tenancy.php`), `.env.testing`/`.env.test`, guia de arquitetura (`wiki/`, `docs/`, `doc/`), CLAUDE.md/AGENTS.md, branch base (`develop`, `dev`, `homologacao`, `main`).

Mostrar o resumo ao usuário e perguntar: quais projetos entram no fluxo; quem serve os sites quando houver mais de uma opção (ex.: Herd + Laragon); se algum é multi-tenant por subdomínio.

## Fase 2 — Pré-requisitos
Instalar o que faltar (o usuário roda o que exigir privilégio):

| Item | Windows | Linux | macOS |
|---|---|---|---|
| Git (+ Git Bash) | `winget install Git.Git` | `apt/dnf install git` | `xcode-select --install` ou `brew install git` |
| GitHub CLI | `winget install GitHub.cli` | repositório oficial do `gh` | `brew install gh` |
| Orca | instalador do site oficial (gráfico) | idem | idem |
| Modo de Desenvolvedor (symlink sem admin) | Configurações > Sistema > Para desenvolvedores | — | — |

E, por stack dos projetos escolhidos (só o que faltar; respeitar o que o usuário já usa):
- **Laravel**: PHP + Composer pela ferramenta do usuário (Herd, Laragon, FlyEnv, Lerd, DDEV/Sail, ou nativo: `ondrej/php`/Remi/`brew install php`); banco (MySQL/MariaDB/Postgres) idem.
- **Python**: **uv** recomendado (`winget install astral-sh.uv`, `curl -LsSf https://astral.sh/uv/install.sh | sh`, `brew install uv`), ou o que o projeto já usa (Poetry, Pipenv, pyenv).
- **JS/TS**: **fnm** recomendado (`winget install Schniz.fnm`, `curl -fsSL https://fnm.vercel.app/install | bash`, `brew install fnm`) + `corepack enable`; ou nvm/volta se já existir.
- **Containers**: Docker Desktop / Docker Engine / OrbStack, ou Podman (+ Podman Desktop); DDEV se os projetos usarem.
- **Opcional** (configuração na fase 4b): Codex CLI (escritor em paralelo ao Sonnet; `npm i -g @openai/codex`, login pelo usuário com `! codex login`); agy (Antigravity CLI) para segunda opinião; Kimi Code; segunda conta Claude (ex.: Team) para escritores.

Detalhes e armadilhas de cada ferramenta: `skills/ambiente-local/ferramentas/*.md` deste repositório.

## Fase 3 — git, gh e SSH
1. **git** (perguntar nome e e-mail se `git config --global user.email` estiver vazio):
   ```bash
   git config --global user.name "<Nome>"; git config --global user.email "<email>"
   git config --global init.defaultBranch main; git config --global push.autoSetupRemote true
   ```
   Windows, além disso: `core.autocrlf false`, `core.filemode false`, `core.longpaths true`.
2. **gh** — o usuário roda: `! gh auth login --git-protocol https --web` e `! gh auth refresh -s project,read:org` (o escopo `project` é do board). Depois `gh auth setup-git` e conferir `gh auth status`.
3. **SSH** — chave da máquina, sem sobrescrever existente:
   ```bash
   [ -f ~/.ssh/id_ed25519 ] || ssh-keygen -t ed25519 -C "<email>" -f ~/.ssh/id_ed25519 -N ""
   gh ssh-key add ~/.ssh/id_ed25519.pub --title "$(hostname)"
   ```
   Servidores: perguntar se o usuário acessa algum. Host, usuário e alias vêm dele (nada disso é publicado); um bloco por servidor em `~/.ssh/config` (`Host`, `HostName`, `User`, `IdentityFile ~/.ssh/id_ed25519`, `IdentitiesOnly yes`, `ServerAliveInterval 30`). Quem administra o servidor cadastra a chave pública lá.
4. **Windows + PHP do Herd**: shims `~/bin/php` e `~/bin/composer` (conteúdo em `ferramentas/herd.md`). Laragon/FlyEnv: pôr os binários no PATH do Git Bash. fnm no Git Bash: `eval "$(fnm env --use-on-cd --shell bash)"` no `~/.bashrc`.

## Fase 4 — Claude Code: plugins, skills e settings
```bash
orca skills install                     # orca-cli, orchestration, computer-use

claude plugin marketplace add VictorStochero/claude-plugins
claude plugin install fluxo-orca@stochero
claude plugin install laravel-worktree@stochero          # só se houver projeto Laravel

claude plugin marketplace add DietrichGebert/ponytail
claude plugin install ponytail@ponytail

claude plugin install code-review@anthropic-plugin-directory
claude plugin install code-simplifier@anthropic-plugin-directory
claude plugin install playwright@anthropic-plugin-directory
claude plugin install claude-md-management@anthropic-plugin-directory
claude plugin marketplace add anthropics/claude-plugins-official
claude plugin install chrome-devtools-mcp@claude-plugins-official
```
> ⚠️ **Não instalar o plugin `superpowers`** (de nenhum marketplace). O `fluxo-orca` já traz as 6 skills dele que o fluxo usa, adaptadas à delegação pelo Orca; as originais duplicam as skills e mandam executar plano/criar worktree por caminhos que conflitam com o fluxo. Se estiver instalado: `claude plugin disable superpowers@<marketplace>`.

Se as skills do Orca não aparecerem em `/skills`, ligar `~/.agents/skills/<skill>` em `~/.claude/skills/<skill>` (symlink).

**`~/.claude/settings.json`** — mesclar, sem apagar os hooks e a status line que o Orca gravou:
```json
{
  "permissions": {
    "defaultMode": "bypassPermissions",
    "ask": [
      "Bash(ssh *)", "PowerShell(ssh *)", "Bash(scp *)", "PowerShell(scp *)",
      "Bash(rsync *)", "PowerShell(rsync *)", "Bash(sftp *)", "PowerShell(sftp *)",
      "Bash(forge *)", "PowerShell(forge *)"
    ]
  },
  "skipDangerousModePermissionPrompt": true,
  "env": { "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "0" },
  "model": "opus",
  "attribution": { "commit": "", "pr": "", "sessionUrl": false }
}
```
Perguntar sobre `bypassPermissions`: com ele, o Claude roda sem pedir permissão a cada comando e as travas ficam com os hooks do plugin e a lista `ask` (que **continua pedindo** para todo comando remoto). Sem ele, omitir `defaultMode` e `skipDangerousModePermissionPrompt`.

Opcionais (perguntar): `"remoteControlAtStartup": true` e `"agentPushNotifEnabled": true` para acompanhar sessões e workers pelo celular; no Warp, `claude plugin marketplace add warpdotdev/claude-code-warp` e `claude plugin install warp@claude-code-warp`.

**`~/.claude/CLAUDE.md`** — baixar o modelo e **mesclar** com o existente, mostrando o diff:
```bash
gh api repos/VictorStochero/fluxo-orca/contents/extras/CLAUDE.global.md --jq .content | base64 -d
```
Se o usuário escreve em outro idioma que não pt-BR, ajustar a seção "Idioma".

## Fase 4b — Agentes externos e segunda conta Claude (opcional)
Só para o que o usuário instalou na fase 2. Os workers do Orca rodam esses CLIs sem humano (o Orca abre o Codex com `--dangerously-bypass-approvals-and-sandbox`), então as regras e a trava de comando remoto têm de estar neles também.

1. **Regras**: baixar `extras/AGENTS.global.md` para `~/.agents/AGENTS.md` (mesclar se existir, mostrando o diff) e ligar em cada CLI instalado — `~/.codex/AGENTS.md`, `~/.gemini/config/AGENTS.md` (agy), `~/.kimi-code/AGENTS.md`, `~/.config/opencode/AGENTS.md`:
   ```bash
   gh api repos/VictorStochero/fluxo-orca/contents/extras/AGENTS.global.md --jq .content | base64 -d > /tmp/AGENTS.global.md
   ln -s ~/.agents/AGENTS.md ~/.codex/AGENTS.md          # Windows (PowerShell): New-Item -ItemType SymbolicLink -Path "$HOME\.codex\AGENTS.md" -Target "$HOME\.agents\AGENTS.md"
   ```
2. **Skills**: o hook de SessionStart do plugin copia as skills para `~/.agents/skills` (reabrir o Claude Code uma vez depois de instalar o CLI). O Codex lê essa pasta sozinho; no agy, ligar cada uma em `~/.gemini/config/skills/<skill>`.
3. **Trava** (`~/.cache/guarda-externos.sh`, instalado pelo mesmo hook; no Windows também `guarda-externos-codex.cmd` e `guarda-externos-agy.cmd`): bloqueia `ssh`/`scp`/`rsync`/`sftp`/`forge` e bulk replace. Comando do hook: Windows → o `.cmd` com o caminho absoluto (`C:/Users/<u>/.cache/guarda-externos-codex.cmd`); Linux/macOS → `bash ~/.cache/guarda-externos.sh <formato>`.
   - **Codex** — em `~/.codex/hooks.json`, um grupo novo em `PreToolUse` (sem `matcher`), depois dos que o Orca gravou: `{"hooks":[{"type":"command","command":"<comando> codex","timeout":10}]}` (no Windows o `.cmd` já leva o formato). Exit 2 o Codex trata como falha e deixa passar; por isso o formato `codex` responde em JSON. **Hook novo só roda se estiver confiável**: abrir `codex` e aprovar em `/hooks`, ou gravar a confiança no `~/.codex/config.toml` (no Windows, nas duas grafias do caminho, `C:\...` e `C:/...`; `<n>` = posição do grupo em `PreToolUse`, começando em 0):
     ```bash
     # <evento>: pre_tool_use ou stop; <timeout>: o do hooks.json
     python -c "import hashlib,json,sys;print('sha256:'+hashlib.sha256(json.dumps({'event_name':sys.argv[2],'hooks':[{'async':False,'command':sys.argv[1],'timeout':int(sys.argv[3]),'type':'command'}]},separators=(',',':'),sort_keys=True).encode()).hexdigest())" "<comando exato do hooks.json>" <evento> <timeout>
     ```
     ```toml
     [hooks.state.'<caminho do hooks.json>:<evento>:<n>:0']
     enabled = true
     trusted_hash = "sha256:..."
     ```
   - **agy** — em `~/.gemini/config/hooks.json`, entrada `"guarda-externos": {"PreToolUse": [{"matcher": "*", "hooks": [{"type": "command", "command": "<comando> agy", "timeout": 10}]}]}` (formato `agy`).
   - **Kimi** — no `~/.kimi-code/config.toml`: `[[hooks]]` com `event = "PreToolUse"`, `command = "bash ~/.cache/guarda-externos.sh exit2"`, `timeout = 10`.
   - **Codex, fim do worker** — em `~/.codex/hooks.json`, um grupo novo em `Stop` (depois do que o Orca gravou): `{"hooks":[{"type":"command","command":"<fim-worker>","timeout":15}]}`, com `<fim-worker>` = `C:/Users/<u>/.cache/fim-worker-codex.cmd` no Windows ou `bash ~/.cache/fim-worker.sh` no Linux/macOS; confiança com `<evento>` = `stop`. Worker de Orca que encerra o turno sem `worker_done` recebe o comando de volta e continua (o Claude ganha o mesmo hook pelo plugin).
   - Conferir: `codex exec --dangerously-bypass-approvals-and-sandbox --skip-git-repo-check "Rode exatamente: ssh -V"` tem de responder que o hook bloqueou (equivalente no agy e no Kimi).
4. **Segunda conta Claude** (ex.: Team) para escritores: pasta `~/.claude-team` com links para `CLAUDE.md`, `settings.json`, `plugins`, `skills`, `agents` e `projects` de `~/.claude`; login pelo usuário com `! CLAUDE_CONFIG_DIR=~/.claude-team claude` e `/login`. Atalho no `~/.bashrc` (o `--settings` garante o mesmo settings mesmo se o link quebrar): `claude-team() { CLAUDE_CONFIG_DIR="$HOME/.claude-team" claude --settings "$HOME/.claude/settings.json" "$@"; }`. O `limites.sh` passa a medir a linha `team`, e a skill `delegacao` diz como abrir worker nessa conta.

## Fase 5 — Perfil da máquina e boards
1. **`~/.claude/ambiente.md`** — perfil com o que a fase 1 achou, no formato da skill `ambiente-local` (sistema, shell, quem serve os sites, bancos com porta e origem, contêiner, runtimes, raiz dos projetos e a tabela de projetos com stack, serviço, banco, multi-tenant, board e base). As skills leem este arquivo; mantê-lo verdadeiro.
2. **`~/.claude/boards.md`** — perguntar quais projetos têm GitHub Project. Para cada um: `gh project list --owner <org>` e `gh project field-list <nº> --owner <org> --format json`; gravar a tabela e os ids de campos/opções no formato da skill `board-github`. Sem board: arquivo com a tabela vazia.

**Migrando de outra máquina** (perguntar na fase 1): o que é pessoal não está no plugin nem no git — pedir ao usuário para trazer e restaurar antes desta fase, mostrando o diff com o que a detecção achou:
- `~/.claude/ambiente.md` e `~/.claude/boards.md` (armadilhas e regras de board não se detectam de novo); corrigir caminhos, portas e versões que mudaram.
- Por projeto, fora do git: `.env`/`.env.testing` e `.orca/worktree.conf` (vêm junto se a pasta for copiada; se o projeto for clonado de novo, trazer à parte).
- Opcional: memórias do Claude por projeto (`~/.claude/projects/*/memory`; o nome da pasta muda se o caminho do projeto mudar).
- Logins não migram: Claude (e a segunda conta), `gh`, Codex/agy/Kimi e as chaves SSH são refeitos nas fases 3 e 4b.

## Fase 6 — Por projeto
Para cada projeto escolhido:
1. **Orca**: `orca repo add --path <caminho>` e `orca repo set-base-ref --repo path:<caminho> --ref origin/<base>`. O usuário configura na tela do repo no Orca (sem CLI para isso), com o **mesmo texto em todos os repos** — passar os dois prontos para colar: Windows → setup `"%ProgramFiles%\Git\bin\bash.exe" "%USERPROFILE%\.cache\wt-setup.sh"` e archive `"%ProgramFiles%\Git\bin\bash.exe" "%USERPROFILE%\.cache\wt-archive.sh"`; Linux/macOS → `bash ~/.cache/wt-setup.sh` e `bash ~/.cache/wt-archive.sh`. Não usar `orca.yaml` fora do git para isso (skill `worktree-orca`).
2. **`.orca/worktree.conf`** (no projeto; `.orca/` no `.git/info/exclude`) só com o que a detecção não acerta — opções na skill `worktree-orca`. Exemplos: `WT_SITES=herd` em Herd + Laragon; `WT_SEEDER=DemoSeeder`; `WT_MIGRAR="uv run alembic upgrade head"`; `GS_TESTE_RUNNER="docker compose exec -T web pytest"` para projeto em container.
3. **Stack**:
   - Laravel: `laravel/boost` (`composer require laravel/boost --dev` se faltar — **perguntar**, muda dependência do projeto) e `php artisan boost:install --skills --no-interaction` (sem `--mcp`).
   - Python/JS: conferir que o gerenciador do lockfile e a versão do runtime pedida estão instalados (skills `stack-python`, `stack-js`).
4. **Teste rápido**: `bash ~/.cache/gs-teste.sh` com um arquivo de teste pequeno do projeto (ou a listagem: `--list-tests`, `pytest --collect-only -q`, `vitest list`).

## Fase 7 — Verificação
Reabrir o Claude Code e conferir, relatando cada item (ok / pendente + motivo):
1. `claude plugin list`: `fluxo-orca`, `ponytail`, `code-review`, `code-simplifier`, `playwright`, `claude-md-management`, `chrome-devtools-mcp` (+ `laravel-worktree` se houver Laravel) habilitados, **nenhum `superpowers`**; `/skills` mostra `delegacao`, `fila-testes`, `worktree-orca`, `stack-*`, `orca-cli`, `orchestration`.
2. `~/.cache/gs-teste.sh`, `~/.cache/e-teste.sh`, `~/.cache/wt-setup.sh`, `~/.cache/wt-archive.sh`, `~/.cache/wt-lib.sh`, `~/.cache/limites.sh`, `~/.cache/orca-espera.sh`, `~/.cache/fim-worker.sh` e `~/.claude/agents/somente-leitura.json` existem (hook de SessionStart).
3. Num projeto, o comando de teste direto (`php artisan test`, `pytest`, `pnpm test`…) é **bloqueado** pelo hook com a mensagem da fila; `bash ~/.cache/gs-teste.sh <listagem>` passa.
4. Um `sed -i` qualquer é bloqueado pelo hook `bloqueia-bulk`.
5. `bash ~/.cache/limites.sh` imprime ao menos a linha `pessoal`.
6. `orca status --json` responde; cada projeto aparece em `orca repo list`.
7. `git config --global user.email` preenchido; `gh auth status` com `project`; `ssh -T git@github.com` autentica (é o GitHub, não servidor; passa pela aprovação do `ask`).
8. Runtimes da stack de cada projeto respondem no shell dos hooks (`php -v`/`composer -V`, `uv --version`/`python --version`, `node -v` + gerenciador).
9. `~/.claude/ambiente.md` e `~/.claude/boards.md` existem e batem com o que foi configurado.
10. Agentes externos instalados (fase 4b): cada um responde em pt-BR (regras carregadas), lista as skills de `~/.agents/skills` e tem o `ssh -V` bloqueado pelo hook; `limites.sh` mostra a linha `codex` e/ou `team` quando existirem.
11. (Opcional, com o "sim" do usuário) criar um worktree de teste pelo Orca num projeto, conferir URL/banco/`.env` e arquivá-lo.

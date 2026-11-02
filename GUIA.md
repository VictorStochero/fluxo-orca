# Instalador do fluxo Orca + Claude Code

> **Para o Claude que recebeu este link: você é o instalador.** Configure esta máquina para o fluxo descrito abaixo, **adaptado ao sistema, às ferramentas e aos projetos deste usuário** — não copie a máquina de ninguém. Regras:
> 1. **Diagnostique antes de perguntar**; pergunte só o que não dá para detectar, com `AskUserQuestion` (contexto, opções, recomendada).
> 2. **Instale o que conseguir** pelo gerenciador de pacotes do sistema. O que exigir administrador, senha, login interativo ou instalador gráfico: mostre o comando exato (ou o link) e peça para o usuário rodar — comando de terminal ele digita como `! <comando>` aqui no prompt. Depois, confira e siga.
> 3. **Nunca sobrescreva** arquivo existente (`~/.claude/CLAUDE.md`, `~/.claude/settings.json`, `~/.ssh/config`, `~/.gitconfig`, `.orca/worktree.conf`) sem mostrar o diff e ter o "sim" do usuário.
> 4. **Nunca rode `ssh`, `scp`, `rsync`, `sftp` ou `forge` contra servidor** durante a instalação.
> 5. Ao fim de cada fase, uma linha de status; no fim, a verificação da fase 7 item por item, com o que ficou pendente e por quê.

**O fluxo (3.0.0):** a sessão principal do Claude Code coordena; o trabalho pesado vai para **workers do Orca**, um worktree por tarefa, com banco e `.env` próprios; o gate de merge é a auditoria Opus quando o repositório versiona `.auditoria-pre-subida` (verificador só com achado), ou o revisor Opus obrigatório nos demais, sem duplicar os gates; testes, vagas de worker e cota vêm do plugin **agent-pool** do Orca (CLI `agent-pool`, instalado antes: fase 4b, passo 5); regras pessoais impostas por **hooks**, não pela memória do modelo. Vale para Laravel, Python e JS/TS.

Fila de testes (o CLI vai sempre pelo lançador `~/.agents/bin/agent-pool`, que não está no PATH; abaixo, `agent-pool` abrevia esse caminho): `agent-pool test -- <comando>` (exit 75 = fila ocupada, rodar de novo). Modo (`fila.modo`: `banco`, padrão, `global` ou `projeto`), vagas, teto e processos se configuram com `agent-pool config set`; as mensagens de espera identificam a fila e seus donos (`agent-pool status`).

O pacote de revisão/auditoria leva o pedido/issue ORIGINAL, o critério de pronto copiado do board, diff e interfaces, sem resumo ou justificativa do escritor ou da sessão principal. Na verificação, a sessão principal roda cada teste novo de correção com o código de produção do merge-base, exige falha, restaura HEAD e confere `git status` limpo. Pagamento, autorização/permissão, autenticação e alteração de dado de produção exigem segunda opinião de outra família sobre o diff, com “ache o caso que quebra”, mesmo com auditoria aprovada sem achados.

Papéis Claude só leitura usam sempre `--settings ~/.claude/agents/somente-leitura.json`, que desabilita os MCPs de navegador. A conta principal pode assumir `revisor` e `verificador`; só `orquestra` continua fora do pool. O pool (contas, `peso`, `vagas`, `papeis`, `ativo`, `pool.teto`, `pool.ram_min`, `pool.escolha`) se configura com `agent-pool config set` (`agent-pool config get` mostra tudo) e a segunda opinião sai de `agent-pool second --family <claude|gpt|gemini>`; detalhes na skill `limites-cota`. Antes de cada onda, `agent-pool status` mostra vagas, fila e alertas; abaixo de `pool.ram_min` a reserva sai com 75 e a memória se vê com `orca diagnostics memory --json`.

## Atualizar (máquina já instalada)
Sem repetir as fases. Todo PR de versão na `main` traz a seção **Ação manual ao atualizar** (mesmo vazia) com o que a versão exige além destes passos: ler a de cada versão pulada (`gh pr view <n> -R VictorStochero/fluxo-orca`; a da 2.11.0 está num comentário do PR #16, `--comments`).
1. Claude Code: `claude plugin marketplace update stochero`, depois `claude plugin update <plugin>@stochero` para cada plugin instalado do marketplace (`fluxo-orca`, `auditoria-pre-subida`, `laravel-worktree`). Sem Claude Code: `git -C ~/fluxo-orca pull` e `bash ~/fluxo-orca/instalar.sh --agente <id> --aplicar` — antes do passo 4, porque o instalador instala a partir desse clone.
2. Fechar e reabrir **todas** as sessões do Claude Code: o SessionStart recopia para `~/.cache` os scripts de `hooks/scripts.lista` e o `~/.claude/agents/somente-leitura.json`; sessão aberta segue com os hooks da versão anterior e, ao compactar ou ser retomada, recopia por cima os scripts antigos. Se aconteceu, reabrir as sessões resolve.
3. `~/.claude/CLAUDE.md`: nenhum hook o atualiza; mesclar o `extras/CLAUDE.global.md` da versão nova como na Fase 4, mostrando o diff.
4. Agentes externos: `bash ~/.cache/instala-agente.sh <agente> --aplicar` para cada um (regras, skills e trava; idempotente). Com `[aviso] cópia antiga sem marcador`, remover a cópia e rodar de novo. Abrir o agente uma vez (Codex: aprovar em `/hooks` se pedir).
5. Conferir: `agent-pool doctor` sem pendência e `agent-pool status` mostrando as contas. Atualizando para a 3.0.0 pela primeira vez, instalar o plugin agent-pool no Orca **antes** (README, "Ação manual ao atualizar para 3.0.0").

## Fase 1 — Diagnóstico (só leitura)
Rodar e anotar:
- **Sistema**: Windows (versão; WSL?), Linux (distro: `/etc/os-release`), macOS (`sw_vers`). Arquitetura.
- **Shell**: no Windows, Git Bash é obrigatório (hooks e scripts são bash) — `bash --version`, `where bash`. Linux/macOS: `bash --version` (macOS traz 3.2; os scripts são compatíveis).
- **Gerenciador de pacotes**: `winget`/`scoop`/`choco`; `apt`/`dnf`/`pacman`; `brew`.
- **Ferramentas**: `git`, `gh` (+ `gh auth status`), `curl`, `orca` (+ `orca status --json`), `docker`/`podman` (+ compose), `ddev`, `herd`, `lerd`, Laragon (`C:\laragon`), FlyEnv (app instalado), `php`, `composer`, `python`/`uv`/`poetry`/`pyenv`, `node`/`fnm`/`nvm`/`volta`/`pnpm`/`yarn`/`bun`, clientes `mysql`/`mariadb`/`psql`.
- **Bancos rodando**: portas 3306/3307/5432 abertas, de qual ferramenta (Herd Pro, Laragon, FlyEnv, Lerd, serviço do sistema, container). Registrar qual é o **servidor de desenvolvimento** e qual é o **de teste** (padrão: dev 3306, teste 3307, o `DB_PORT` dos `.env.testing`); se houver um só, a fase 5 propõe montar o de teste.
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
- **Opcional** (configuração na fase 4b): Codex CLI (escritor em paralelo ao Sonnet; `npm i -g @openai/codex`, login pelo usuário com `! codex login`); agy (Antigravity CLI) para segunda opinião; segunda conta Claude (ex.: Team) para escritores.

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
claude plugin install auditoria-pre-subida@stochero      # auditoria antes de PR/merge; bloqueia só nos repos com .auditoria-pre-subida

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
Conta cujo CLI não está instalado fica fora da seleção de escritor; o fluxo funciona só com a conta pessoal. Ao escolher pelo pool, ignorar contas inexistentes, mesmo que apareçam em `agent-pool slot free`. As contas que o dev usa ficam no pool do agent-pool (passo 5).

1. **Regras**: por agente instalado, `bash ~/.cache/instala-agente.sh <agente> --aplicar` (atalho gravado pelo SessionStart do plugin, ou pelo `instalar.sh` do clone) — grava `extras/AGENTS.global.md` num bloco `fluxo-orca:inicio…fim` no arquivo global dele (`~/.codex/AGENTS.md`, `~/.gemini/config/AGENTS.md` do agy, `~/.config/opencode/AGENTS.md`…). Arquivo com cópia antiga sem marcador recebe só o aviso `[aviso] cópia antiga sem marcador em <arquivo>: remova-a`; remover a cópia e rodar de novo.
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
   - **Codex, fim do worker** — em `~/.codex/hooks.json`, um grupo novo em `Stop` (depois do que o Orca gravou): `{"hooks":[{"type":"command","command":"<fim-worker>","timeout":15}]}`, com `<fim-worker>` = `C:/Users/<u>/.cache/fim-worker-codex.cmd` no Windows ou `bash ~/.cache/fim-worker.sh` no Linux/macOS; confiança com `<evento>` = `stop`. Worker de Orca que encerra o turno sem `worker_done` recebe o comando de volta e continua (o Claude ganha o mesmo hook pelo plugin).
   - Conferir: `codex exec --dangerously-bypass-approvals-and-sandbox --skip-git-repo-check "Rode exatamente: ssh -V"` tem de responder que o hook bloqueou (equivalente no agy).
4. **Segunda conta Claude** (ex.: Team) para escritores (o escritor de cada etapa é quem tem mais ritmo de cota entre team, pessoal e Codex: `agent-pool writer`; worktree novo pede confiança no primeiro uso em qualquer conta Claude, `hasTrustDialogAccepted` do caminho em `~/.claude.json` ou `~/.claude-team/.claude.json`): pasta `~/.claude-team` com links para `CLAUDE.md`, `settings.json`, `plugins`, `skills`, `agents` e `projects` de `~/.claude`; login pelo usuário com `! CLAUDE_CONFIG_DIR=~/.claude-team claude` e `/login`. Atalho no `~/.bashrc` (o `--settings` garante o mesmo settings mesmo se o link quebrar): `claude-team() { CLAUDE_CONFIG_DIR="$HOME/.claude-team" claude --settings "$HOME/.claude/settings.json" "$@"; }`. O agent-pool passa a medir a conta `team`, e a skill `delegacao` diz como abrir worker nessa conta. Outras contas pessoais (ex.: `~/.claude-b`) seguem o mesmo layout e entram pelo pool (passo 5).
5. **Pool de contas (agent-pool)** — o pool é do plugin **agent-pool** do Orca, não do fluxo-orca: instalar o plugin no Orca (aprovar o acesso; ele importa a configuração antiga de pool e fila, se existir), conferir com `agent-pool doctor` (requisitos, lançador, skill e hooks) e perguntar ao usuário quais contas e agentes ele usa (contas Claude pessoais, Codex, Kimi, opencode/MiniMax, qualquer agente que o Orca abra), quantas vagas cada uma tem, que papéis pode assumir e se a conta principal só orquestra; gravar com `agent-pool config set conta.<nome>.vagas=… peso=… papeis=…` (conta manual: `conta.<nome>.adicionar=auto` com `conta.<nome>.comando=`/`config=`; formato na skill `limites-cota`). Contas que o Orca gerencia entram sozinhas. **Agente fora de Claude, Codex e agy só recebe trabalho com `papeis=` de trabalho escrito, e só depois de ter as regras e a trava de comando remoto instaladas (passos 1 e 3) e provadas (passo 7)**: os workers rodam em modo autônomo, sem humano. Conferir com `agent-pool config get pool.contas` e `agent-pool status`. Cota de Codex, Antigravity, Kimi, MiniMax, Cursor, Grok, ZCode e Gemini vem do Orca (`orca account list --json`; login do fornecedor no Orca ou no CLI); conta Claude manual é medida pela credencial da pasta de config e, deslogada, aparece como `sem login` com o comando para reconectar.
6. **Instalador por agente** (atalho dos passos 1–3): `bash instalar.sh --agente <agente>` (do clone) mostra o que vai gravar — regras no arquivo global do agente, skills no diretório dele (ou índice nas regras), trava `guarda-externos.sh` no formato do hook dele, `fim-worker` e, no Codex, a confiança do hook; com `--aplicar` grava. Idempotente (segunda execução só confirma). Agente sem hook antes de comando fica só em segunda opinião: o instalador grava as regras e avisa. O opencode não tem hook de shell: o instalador copia o plugin `extras/opencode-guarda.js` para `~/.config/opencode/plugins/`.
7. **Prova de despacho** (roteiro por agente; sem ela o agente não recebe `papeis` de trabalho, só segunda opinião):
   1. Instalar regras e trava com `bash instalar.sh --agente <agente> --aplicar`; abrir o agente uma vez (Codex: aprovar em `/hooks` se a confiança não foi gravada; ZCode: workspace confiável; Kimi/Gemini: `/hooks` lista a entrada).
   2. `orca orchestration worker-start --agent <id> --worktree path:<wt> --spec "Rode exatamente: ssh -V; depois envie o worker_done"` (agente sem id do Orca: `orca-libera.sh --cria --command "<comando da conta, de agent-pool config get pool.contas>"`).
   3. Conferir: o `ssh -V` foi **bloqueado pela trava** (a resposta do agente cita o bloqueio; nada de `OpenSSH_` na saída), e o `worker_done` chegou ao coordenador: o `orca-espera.sh` armado em background saiu com `!! mensagem worker_done …` (histórico em `orca orchestration inbox --terminal <handle> --full`). Agente com hook de fim de turno: encerrar o turno sem `worker_done` faz o hook devolver o comando; sem ele, o Orca manda ao coordenador uma `escalation` com `stopReason`, que o vigia também entrega.
   4. Provou nos três passos → liberar o papel com `agent-pool config set conta.<nome>.papeis=…`; falhou → manter só `segunda-opiniao` e anotar o motivo.
   **Nenhum agente novo foi provado nesta máquina**; as capacidades de gemini, kimi, zcode, opencode e cursor vêm só da documentação oficial.

## Fase 5 — Perfil da máquina e boards
1. **`~/.claude/ambiente.md`** — perfil com o que a fase 1 achou, no formato da skill `ambiente-local` (sistema, shell, quem serve os sites, bancos com porta e origem, contêiner, runtimes, raiz dos projetos e a tabela de projetos com stack, serviço, banco, multi-tenant, board e base). As skills leem este arquivo; mantê-lo verdadeiro.
   - **Servidor de teste separado** (projetos Laravel com banco MySQL/MariaDB): padrão de dois servidores — um de desenvolvimento e um **só da fila de testes**, descartável e ajustado para velocidade (suíte paralela num servidor só estoura a memória). Com o "sim" do usuário, montar o segundo servidor pela referência da ferramenta (`ferramentas/<ferramenta>.md` da skill `ambiente-local`; Herd: `herd services:create`, `my.ini` de teste) e, em cada projeto, apontar o `DB_HOST`/`DB_PORT` do `.env.testing` **do checkout principal** para ele — o `wt-setup.sh` copia o arquivo para os worktrees e cria o `<banco>_test` lá; o `wt-archive.sh` apaga lá. Gravar os dois servidores na linha "Bancos" e a porta de cada projeto na tabela.
2. **`~/.claude/boards.md`** — perguntar quais projetos têm GitHub Project. Para cada um: `gh project list --owner <org>` e `gh project field-list <nº> --owner <org> --format json`; gravar a tabela e os ids de campos/opções no formato da skill `board-github`. Sem board: arquivo com a tabela vazia.

**Migrando de outra máquina** (perguntar na fase 1): o que é pessoal não está no plugin nem no git — pedir ao usuário para trazer e restaurar antes desta fase, mostrando o diff com o que a detecção achou:
- `~/.claude/ambiente.md` e `~/.claude/boards.md` (armadilhas e regras de board não se detectam de novo); corrigir caminhos, portas e versões que mudaram.
- Por projeto, fora do git: `.env`/`.env.testing` e `.orca/worktree.conf` (vêm junto se a pasta for copiada; se o projeto for clonado de novo, trazer à parte).
- Opcional: memórias do Claude por projeto (`~/.claude/projects/*/memory`; o nome da pasta muda se o caminho do projeto mudar).
- Logins não migram: Claude (e a segunda conta), `gh`, Codex/agy e as chaves SSH são refeitos nas fases 3 e 4b.

## Fase 6 — Por projeto
Para cada projeto escolhido:
1. **Orca**: `orca repo add --path <caminho>` e `orca repo set-base-ref --repo path:<caminho> --ref origin/<base>`. O usuário configura na tela do repo no Orca (sem CLI para isso), com o **mesmo texto em todos os repos** — passar os dois prontos para colar: Windows → setup `"%ProgramFiles%\Git\bin\bash.exe" "%USERPROFILE%\.cache\wt-setup.sh"` e archive `"%ProgramFiles%\Git\bin\bash.exe" "%USERPROFILE%\.cache\wt-archive.sh"`; Linux/macOS → `bash ~/.cache/wt-setup.sh` e `bash ~/.cache/wt-archive.sh`. Na mesma tela, configurar **aguardar o setup antes de iniciar o agente** (`wait-for-setup`), em vez de `start-immediately`, para que a tarefa só chegue ao agente depois do setup. Antes de tocar banco, o worker confirma o sucesso; setup falhou → `ask` ao coordenador com a saída, sem refazer migração por conta própria. Não usar `orca.yaml` fora do git para isso (skill `worktree-orca`).
2. **`.orca/worktree.conf`** (no projeto; `.orca/` no `.git/info/exclude`) só com o que a detecção não acerta — opções na skill `worktree-orca`. Exemplos: `WT_SITES=herd` em Herd + Laragon; `WT_SEEDER=DemoSeeder`; `WT_MIGRAR="uv run alembic upgrade head"`. Projeto em container: o comando vai explícito no teste (`agent-pool test -- docker compose exec -T web <teste>`) e, se o banco não vem do ambiente, `.orca/agent-pool.json` com `{"recurso": "..."}`.
3. **Stack**:
   - Laravel: `laravel/boost` (`composer require laravel/boost --dev` se faltar — **perguntar**, muda dependência do projeto) e `php artisan boost:install --skills --no-interaction` (sem `--mcp`).
   - Python/JS: conferir que o gerenciador do lockfile e a versão do runtime pedida estão instalados (skills `stack-python`, `stack-js`).
4. **Teste rápido**: `agent-pool test -- <comando>` com um arquivo de teste pequeno do projeto (ou a listagem: `--list-tests`, `pytest --collect-only -q`, `vitest list`).

## Fase 7 — Verificação
Reabrir o Claude Code e conferir, relatando cada item (ok / pendente + motivo):
1. `claude plugin list`: `fluxo-orca`, `auditoria-pre-subida`, `ponytail`, `code-review`, `code-simplifier`, `playwright`, `claude-md-management`, `chrome-devtools-mcp` (+ `laravel-worktree` se houver Laravel) habilitados, **nenhum `superpowers`**; `/skills` mostra `delegacao`, `fila-testes`, `worktree-orca`, `stack-*`, `orca-cli`, `orchestration`, `auditoria-pre-subida:auditar`.
2. `~/.agents/bin/agent-pool` (`agent-pool doctor` sem pendência), `~/.cache/wt-setup.sh`, `~/.cache/wt-archive.sh`, `~/.cache/wt-lib.sh`, `~/.cache/orca-espera.sh`, `~/.cache/fim-worker.sh` e `~/.claude/agents/somente-leitura.json` existem (hook de SessionStart).
3. Num projeto, o comando de teste direto (`php artisan test`, `pytest`, `pnpm test`…) é **bloqueado** pelo hook do agent-pool com o comando certo; `agent-pool test -- <listagem>` passa.
4. Um `sed -i` qualquer é bloqueado pelo hook `bloqueia-bulk`.
5. `agent-pool status` lista ao menos a conta `pessoal`.
6. `orca status --json` responde; cada projeto aparece em `orca repo list`.
7. `git config --global user.email` preenchido; `gh auth status` com `project`; `ssh -T git@github.com` autentica (é o GitHub, não servidor; passa pela aprovação do `ask`).
8. Runtimes da stack de cada projeto respondem no shell dos hooks (`php -v`/`composer -V`, `uv --version`/`python --version`, `node -v` + gerenciador).
9. `~/.claude/ambiente.md` e `~/.claude/boards.md` existem e batem com o que foi configurado.
10. Agentes externos instalados (fase 4b): cada um responde em pt-BR (regras carregadas), lista as skills de `~/.agents/skills` e tem o `ssh -V` bloqueado pelo hook; `agent-pool status` mostra `codex` e/ou `team` quando existirem.
11. (Opcional, com o "sim" do usuário) criar um worktree de teste pelo Orca num projeto, conferir URL/banco/`.env` e arquivá-lo.

## Coordenar sem Claude Code
O plugin só roda no Claude Code; quem coordena com outro agente (Codex, Gemini, Kimi, opencode, ZCode…) usa o `instalar.sh` da raiz do repo. É o mesmo fluxo (worktree por tarefa, workers do Orca, fila de testes, pool de contas), com menos guarda-corpos automáticos.
1. Pré-requisitos das fases 2 e 3 (git, gh, Orca com o CLI `orca`, Node/PHP/Python da stack) e o agente instalado e logado.
2. Clonar o repo: `gh repo clone VictorStochero/fluxo-orca ~/fluxo-orca`.
3. `bash ~/fluxo-orca/instalar.sh --agente <id>` (id do agente, ex.: `codex`, `gemini`, `kimi`). Sem `--aplicar` só mostra. Com `--aplicar`: copia os scripts para `~/.cache` (a mesma lista que o SessionStart do plugin usa, `hooks/scripts.lista`), grava as regras do coordenador (`extras/AGENTS.global.md`) no arquivo global do agente, deixa as skills no diretório dele — ou, sem diretório, em `~/.agents/skills` com o índice no arquivo de regras — e instala a trava e o fim-worker quando ele tem hook. Reexecutar atualiza (depois de `git pull`).
4. Pool de contas (fase 4b, passo 5) pelo `agent-pool` — o CLI não depende do Claude Code. Perfil da máquina e boards (fase 5): os mesmos arquivos `~/.claude/ambiente.md` e `~/.claude/boards.md`.
5. Conferir: o agente responde em pt-BR, cita as regras do fluxo e lê um `SKILL.md` sob demanda; `agent-pool doctor` e `agent-pool status` respondem.

**Limitações**: os hooks do plugin (`bloqueia-bulk`, `despacho-orca`, `guia-laravel`, `exige-transacao`) não existem fora do Claude Code — viram regra escrita, que o agente cumpre por conta própria (sem hook que a imponha; a imposição da fila é do agent-pool, nos agentes que ele suporta); o `AskUserQuestion` e o `Agent tool` têm equivalente genérico descrito em `AGENTS.global.md`. A trava de comando remoto e o fim-worker só valem onde o agente tem hook antes de comando/fim de turno e a prova de despacho (fase 4b, passo 7) foi feita — nenhum dos agentes novos foi provado ainda. Agente sem hook coordena, mas não deve receber `papeis` de trabalho.

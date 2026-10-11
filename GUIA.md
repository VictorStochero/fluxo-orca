# Guia de instalação — fluxo Claude Code + Orca + Laravel

> **Para o Claude que recebeu este link**: siga as etapas em ordem nesta máquina. Antes de sobrescrever qualquer arquivo existente (`~/.claude/CLAUDE.md`, `~/.claude/settings.json`, `~/.ssh/config`, `~/.gitconfig`), mostre o que muda e peça confirmação ao usuário. Pergunte ao usuário o que só ele sabe (nome e e-mail do git, boards, servidores, conta secundária) com `AskUserQuestion`. Comando interativo (`gh auth login`) é o usuário quem roda, digitando `! <comando>` no prompt. **Nunca rode `ssh`, `scp`, `rsync`, `sftp` ou `forge` contra servidor** durante a instalação. No fim, rode a verificação da etapa 11 e relate o resultado de cada item.

O fluxo: a sessão principal do Claude Code coordena, o trabalho pesado vai para **workers do Orca** (um worktree por tarefa), cada diff passa por um **revisor Opus** antes do merge, e os testes PHP rodam por uma **fila única da máquina**. Hooks impõem as regras, então não dependem de o modelo lembrar delas.

## 0. Pré-requisitos (Windows 11)
- **Laravel Herd Pro** (PHP 8.4, Composer, MariaDB, Redis, Mailpit), com os projetos em `%USERPROFILE%\Herd\<repo>`.
- **Git for Windows** (Git Bash): os hooks rodam em `bash`. **Modo de Desenvolvedor** do Windows ligado (symlink sem administrador).
- **GitHub CLI** (`winget install GitHub.cli`).
- **Node/npm** (vem do Herd ou instalado à parte).
- **Orca** instalado e aberto, com a integração do Claude Code ligada nas configurações dele (o Orca grava os próprios hooks em `~/.orca/agent-hooks`, no `settings.json` e a status line).
- Opcional: **agy** (Antigravity CLI) para segunda opinião e **Kimi Code**. Sem eles, a revisão de cota só pula as linhas desses fornecedores.

## 1. git
Perguntar nome e e-mail ao usuário e gravar:
```bash
git config --global user.name "<Nome Sobrenome>"
git config --global user.email "<email>"
git config --global core.autocrlf false     # não converte fim de linha: diff limpo entre Windows e servidor
git config --global core.filemode false     # Windows não guarda bit de execução
git config --global core.longpaths true     # vendor/ e node_modules/ passam de 260 caracteres
git config --global init.defaultBranch main
git config --global push.autoSetupRemote true
```
Convenções (vêm do CLAUDE.md global e da skill `delegacao`): branch `{flag}/{AAAAMMDD}-{contexto}` (`feature|fix|hotfix|chore|docs|test|refactor`), PR com `Refs #N` (nunca `Closes`), **sem atribuição a Claude** em commit ou PR.

## 2. gh
O usuário roda (interativo — HTTPS, login pelo navegador):
```
! gh auth login --git-protocol https --web
! gh auth refresh -s project,read:org
```
O escopo `project` é o que a skill `board-github` usa para mexer nos GitHub Projects. Conferir:
```bash
gh auth status        # "Token scopes" precisa ter repo, project, read:org
gh auth setup-git     # git usa o token do gh no HTTPS
```

## 3. SSH
Chave da máquina (sem sobrescrever uma existente):
```bash
[ -f ~/.ssh/id_ed25519 ] || ssh-keygen -t ed25519 -C "<email>" -f ~/.ssh/id_ed25519 -N ""
gh ssh-key add ~/.ssh/id_ed25519.pub --title "$(hostname)"
```
**Servidores**: hosts, usuários e aliases não estão neste repositório (ele é público) — o usuário pede ao responsável pela infraestrutura, que também cadastra a chave pública nos servidores (Forge ou `authorized_keys`). Com os dados em mãos, um bloco por servidor em `~/.ssh/config`:
```
Host <alias>
    HostName <ip-ou-dominio>
    User <usuario>
    IdentityFile ~/.ssh/id_ed25519
    IdentitiesOnly yes
    ServerAliveInterval 30
```
Regras (impostas pelo CLAUDE.md global e pelas regras `ask` da etapa 6): ler log é livre; **toda alteração remota é mostrada antes (comando, host, efeito) e aprovada pelo usuário, uma por comando**; nunca corrigir em produção — reproduzir local, corrigir no repo, subir pelo fluxo normal; antes de afirmar algo sobre um servidor, conferir `hostname`.

## 4. Shims do Git Bash
`php.bat` e `composer.bat` do Herd não rodam no Git Bash. Criar `~/bin/php` e `~/bin/composer` (e garantir `~/bin` no `PATH` do Git Bash, normalmente já está):
```bash
mkdir -p ~/bin
cat > ~/bin/php <<'EOF'
#!/bin/sh
# Segue a versão ativa do Herd: o php.bat é regravado quando a versão muda.
exe=$(sed -n 's/^"\(.*php\.exe\)".*/\1/p' "$HOME/.config/herd/bin/php.bat" | tr -d '\r')
exec "$(cygpath -u "$exe")" "$@"
EOF
cat > ~/bin/composer <<'EOF'
#!/bin/sh
exec php "$(cygpath -w "$HOME/.config/herd/bin/composer.phar")" "$@"
EOF
chmod +x ~/bin/php ~/bin/composer
php -v && composer -V
```

## 5. Plugins e skills
Rodar no terminal (o próprio Claude pode rodar):
```bash
orca skills install                                   # orca-cli, orchestration, computer-use
orca skills installed

claude plugin marketplace add VictorStochero/claude-plugins
claude plugin install fluxo-orca@stochero
claude plugin install laravel-worktree@stochero

claude plugin marketplace add DietrichGebert/ponytail
claude plugin install ponytail@ponytail

claude plugin install code-review-anthropics@anthropic-plugin-directory
claude plugin install code-simplifier@anthropic-plugin-directory
claude plugin install playwright@anthropic-plugin-directory
claude plugin install claude-md-management@anthropic-plugin-directory

claude plugin marketplace add anthropics/claude-plugins-official
claude plugin install chrome-devtools-mcp@claude-plugins-official
```
> ⚠️ **Não instalar o plugin `superpowers`** (nem `superpowers@superpowers-dev`, nem `superpowers@anthropic-plugin-directory`). O `fluxo-orca` já traz as 6 skills dele que o fluxo usa, adaptadas: as originais mandam executar plano por `subagent-driven-development` e criar worktree por `using-git-worktrees`, o que conflita com a delegação pelo Orca (o hook `despacho-orca` bloqueia esse caminho) e duplica as skills. Se já estiver instalado: `claude plugin disable superpowers@<marketplace>` (ver o nome em `claude plugin list`).

Se as skills do Orca não aparecerem em `/skills`, ligar `~/.agents/skills/<skill>` em `~/.claude/skills/<skill>` (symlink).

O `fluxo-orca` traz:

| Tipo | Itens |
|---|---|
| Skills | `delegacao`, `ambiente-local`, `board-github`, `fila-testes`, `limites-cota`, `brainstorming`, `writing-plans`, `systematic-debugging`, `test-driven-development`, `verification-before-completion`, `receiving-code-review` |
| Agentes | `fluxo-orca:escritor` (Sonnet), `fluxo-orca:revisor` e `fluxo-orca:verificador` (Opus, só leitura) |
| Hooks | `fila-testes` (teste só pela fila), `bloqueia-bulk` (sem `sed -i`/`replace_all`), `despacho-orca` (trabalho vai como worker do Orca; libera se o Orca estiver fechado; bloqueia modelo Fable), `guia-laravel` (editar `.php` exige `laravel-best-practices` e o guia de arquitetura lidos), `instala-scripts` (SessionStart) |

Os hooks entram ativos com o plugin — nada a configurar no `settings.json`. O `instala-scripts` copia e mantém atualizados, a cada sessão, `~/.cache/gs-teste.sh` (fila de testes), `~/.cache/limites.sh` e `~/.cache/kimi-cota.sh` (cota), e `~/.claude/agents/somente-leitura.json` (settings dos papéis só leitura).

## 6. `~/.claude/settings.json`
Mesclar no que já existe, **sem apagar** os hooks e a status line que o Orca gravou nem os `enabledPlugins` da etapa 5:
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
  "attribution": false
}
```
- `bypassPermissions`: o Claude roda sem pedir permissão a cada comando — as travas ficam a cargo dos hooks do plugin e da lista `ask`, que **continua pedindo aprovação mesmo em bypass** para todo comando remoto. Se o usuário preferir aprovar tudo, omitir `defaultMode` e `skipDangerousModePermissionPrompt` (perguntar).
- `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=0`: coordenação é pelo Orca, não pelos times nativos.
- `attribution: false`: sem rodapé do Claude em commits e PRs.

## 7. `~/.claude/CLAUDE.md`
Baixar o modelo e **mesclar** com o CLAUDE.md global existente (se houver), mostrando o diff ao usuário:
```bash
gh api repos/VictorStochero/fluxo-orca/contents/extras/CLAUDE.global.md --jq .content | base64 -d
```

## 8. Boards do GitHub (`~/.claude/boards.md`)
A skill `board-github` lê os boards desse arquivo, que fica fora do plugin porque tem ids internos. Perguntar ao usuário quais repositórios têm board e montar, para cada um:
```bash
gh project list --owner <org>
gh project field-list <nº> --owner <org> --format json
```
Formato: a tabela `Repositório | Board | nº | Owner | Project id` e, abaixo, os ids dos campos e das opções (Status, Setor/Área, Prioridade, Data, Fonte, Tema…) e o vocabulário de status do board.

## 9. Conta secundária (opcional)
Se o usuário tiver uma segunda conta Claude (ex.: Team), ela vive em `~/.claude-team` (`CLAUDE_CONFIG_DIR`). O `limites.sh` só mede essa linha se a pasta existir.

## 10. Por projeto Laravel
```bash
composer require laravel/boost --dev                   # se o projeto ainda não tiver
php artisan boost:install --skills --no-interaction    # sem --mcp
```
Worktree novo: `/worktree <flag> <contexto>` (plugin `laravel-worktree`). Ajustes do MariaDB do Herd para schema grande e outras armadilhas: skill `ambiente-local`.

## 11. Verificação
Reabrir o Claude Code e conferir, relatando cada item:
1. `claude plugin list` mostra `fluxo-orca`, `laravel-worktree`, `ponytail`, `code-review-anthropics`, `code-simplifier`, `playwright`, `claude-md-management`, `chrome-devtools-mcp`, e **nenhum `superpowers` habilitado**; `/skills` mostra `delegacao`, `fila-testes`, `limites-cota`, `orca-cli`, `orchestration`.
2. `ls ~/.cache/gs-teste.sh ~/.cache/limites.sh ~/.claude/agents/somente-leitura.json` existe (criados pelo hook de SessionStart).
3. Num projeto Laravel, `php artisan test` é **bloqueado** pelo hook com a mensagem da fila; `bash ~/.cache/gs-teste.sh --list-tests` passa.
4. Um `sed -i` qualquer é bloqueado pelo hook `bloqueia-bulk`.
5. `bash ~/.cache/limites.sh` imprime ao menos a linha `pessoal`.
6. `orca status --json` responde.
7. `git config --global user.email` preenchido; `gh auth status` com `project` nos escopos; `ssh -T git@github.com` responde "successfully authenticated" (é GitHub, não servidor — permitido; ainda assim passa pela aprovação do `ask`).
8. `php -v` e `composer -V` funcionam no Git Bash.

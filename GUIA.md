# Guia de instalação — fluxo Claude Code + Orca + Laravel

> **Para o Claude que recebeu este link**: siga as etapas em ordem nesta máquina. Antes de sobrescrever qualquer arquivo existente (`~/.claude/CLAUDE.md`, `~/.claude/settings.json`), mostre o que muda e peça confirmação ao usuário. Pergunte ao usuário o que só ele sabe (boards, conta secundária) com `AskUserQuestion`. No fim, rode a verificação da etapa 8 e relate o resultado de cada item.

O fluxo: a sessão principal do Claude Code coordena, o trabalho pesado vai para **workers do Orca** (um worktree por tarefa), cada diff passa por um **revisor Opus** antes do merge, e os testes PHP rodam por uma **fila única da máquina**. Hooks impõem as regras, então não dependem de o modelo lembrar delas.

## 0. Pré-requisitos (Windows 11)
- **Laravel Herd Pro** (PHP 8.4, Composer, MariaDB, Redis, Mailpit), com os projetos em `%USERPROFILE%\Herd\<repo>`.
- **Git for Windows** (Git Bash): os hooks rodam em `bash`. Modo de Desenvolvedor do Windows ligado (symlink sem administrador).
- **GitHub CLI** logado: `gh auth status` (escopos `repo`, `project`).
- **Node/npm** (vem do Herd ou instalado à parte).
- **Orca** instalado e aberto, com a integração do Claude Code ligada nas configurações dele (o Orca grava os próprios hooks em `~/.orca/agent-hooks` e no `settings.json`).
- Opcional: **agy** (Antigravity CLI) para segunda opinião e **Kimi Code**. Sem eles, a revisão de cota só pula as linhas desses fornecedores.

## 1. Skills do Orca
```bash
orca skills install          # orca-cli, orchestration, computer-use
orca skills installed        # conferir
```
Se não aparecerem em `/skills` no Claude Code, ligar `~/.agents/skills/<skill>` em `~/.claude/skills/<skill>` (symlink).

## 2. Plugins
No Claude Code:
```
/plugin marketplace add VictorStochero/claude-plugins
/plugin install fluxo-orca@stochero
/plugin install laravel-worktree@stochero

/plugin marketplace add DietrichGebert/ponytail
/plugin install ponytail@ponytail
```
E, do diretório oficial (`/plugin` → Discover): `code-review`, `code-simplifier`, `playwright`, `claude-md-management`, `chrome-devtools-mcp`.

O `fluxo-orca` traz:

| Tipo | Itens |
|---|---|
| Skills | `delegacao`, `ambiente-local`, `board-github`, `fila-testes`, `limites-cota`, `brainstorming`, `writing-plans`, `systematic-debugging`, `test-driven-development`, `verification-before-completion`, `receiving-code-review` |
| Agentes | `fluxo-orca:escritor` (Sonnet), `fluxo-orca:revisor` e `fluxo-orca:verificador` (Opus, só leitura) |
| Hooks | `fila-testes` (teste só pela fila), `bloqueia-bulk` (sem `sed -i`/`replace_all`), `despacho-orca` (trabalho vai como worker do Orca; libera se o Orca estiver fechado), `guia-laravel` (editar `.php` exige `laravel-best-practices` e o guia de arquitetura lidos), `instala-scripts` (SessionStart) |

O `instala-scripts` copia e mantém atualizados, a cada sessão, `~/.cache/gs-teste.sh` (fila de testes), `~/.cache/limites.sh` e `~/.cache/kimi-cota.sh` (cota), e `~/.claude/agents/somente-leitura.json` (settings dos papéis só leitura). Não há o que copiar à mão.

## 3. `~/.claude/settings.json`
Mesclar no que já existe, sem apagar os hooks que o Orca gravou:
```json
{
  "permissions": {
    "ask": [
      "Bash(ssh *)", "PowerShell(ssh *)", "Bash(scp *)", "PowerShell(scp *)",
      "Bash(rsync *)", "PowerShell(rsync *)", "Bash(sftp *)", "PowerShell(sftp *)",
      "Bash(forge *)", "PowerShell(forge *)"
    ]
  },
  "model": "opus",
  "attribution": false
}
```
Os `ask` garantem que comando remoto nunca rode sem aprovação, mesmo em bypass. `attribution: false` tira o rodapé do Claude de commits e PRs.

## 4. `~/.claude/CLAUDE.md`
Baixar o modelo e **mesclar** com o CLAUDE.md global existente (se houver), mostrando o diff ao usuário:
```bash
gh api repos/VictorStochero/fluxo-orca/contents/extras/CLAUDE.global.md --jq .content | base64 -d
```

## 5. Boards do GitHub (`~/.claude/boards.md`)
A skill `board-github` lê os boards desse arquivo, que fica fora do plugin porque tem ids internos. Perguntar ao usuário quais repositórios têm board e montar, para cada um:
```bash
gh project list --owner <org>
gh project field-list <nº> --owner <org> --format json
```
Formato: a tabela `Repositório | Board | nº | Owner | Project id` e, abaixo, os ids dos campos e das opções (Status, Setor/Área, Prioridade, Data, Fonte, Tema…) e o vocabulário de status do board.

## 6. Conta secundária (opcional)
Se o usuário tiver uma segunda conta Claude (ex.: Team), ela vive em `~/.claude-team` (`CLAUDE_CONFIG_DIR`). O `limites.sh` só mede essa linha se a pasta existir.

## 7. Por projeto Laravel
```bash
composer require laravel/boost --dev          # se o projeto ainda não tiver
php artisan boost:install --skills --no-interaction   # sem --mcp
```
Worktree novo: `/worktree <flag> <contexto>` (plugin `laravel-worktree`). Ajustes do MariaDB do Herd para schema grande e outras armadilhas: skill `ambiente-local`.

## 8. Verificação
Reabrir o Claude Code e conferir, relatando cada item:
1. `/plugin` lista `fluxo-orca`, `laravel-worktree` e `ponytail` habilitados; `/skills` mostra `delegacao`, `fila-testes`, `limites-cota`, `orca-cli`, `orchestration`.
2. `ls ~/.cache/gs-teste.sh ~/.cache/limites.sh ~/.claude/agents/somente-leitura.json` existe (criados pelo hook de SessionStart).
3. Num projeto Laravel, `php artisan test` é **bloqueado** pelo hook com a mensagem da fila; `bash ~/.cache/gs-teste.sh --list-tests` passa.
4. `bash ~/.cache/limites.sh` imprime ao menos a linha `pessoal`.
5. `orca status --json` responde.
6. Um `sed -i` qualquer é bloqueado pelo hook `bloqueia-bulk`.

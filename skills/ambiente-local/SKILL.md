---
name: ambiente-local
description: Use ao rodar comandos de projeto, montar/consertar worktree, mexer em banco local, servir site, instalar runtime ou validar tela no navegador — lê o perfil da máquina em ~/.claude/ambiente.md e a referência da ferramenta local (Herd, Laragon, FlyEnv, Lerd, DDEV/Sail/compose com Docker ou Podman, Linux nativo, macOS).
---

# Ambiente local

**Primeiro: ler `~/.claude/ambiente.md`** (perfil da máquina, escrito na instalação pelo GUIA do plugin). Ele diz o sistema, o shell, quem serve os sites, onde está cada banco, os runtimes e os projetos com a stack de cada um. Sem o arquivo: montar pelo formato abaixo, perguntando ao usuário o que não der para detectar, e gravar.

Depois, a referência da ferramenta em uso (nesta pasta):

| Ferramenta | Arquivo |
|---|---|
| Laravel Herd (Windows/macOS) | `ferramentas/herd.md` |
| Laragon (Windows) | `ferramentas/laragon.md` |
| FlyEnv (Windows/macOS/Linux) | `ferramentas/flyenv.md` |
| Lerd (Linux/macOS, Podman) | `ferramentas/lerd.md` |
| DDEV, Sail, docker/podman compose | `ferramentas/containers.md` |
| Linux (apt/dnf) ou macOS (brew) sem gerenciador | `ferramentas/nativo.md` |
| Versões de PHP, Python e Node (pyenv, uv, nvm, fnm, volta) | `ferramentas/runtimes.md` |

Combinações são comuns (ex.: Herd serve o PHP e Laragon o MySQL): o perfil separa **quem serve o site** de **onde está o banco**.

## Regras de qualquer ambiente
- **Worktrees** são pastas irmãs `<repo>-<flag>-<contexto>`, criadas pelo Orca com `wt-setup.sh` (skill `worktree-orca`); banco próprio por worktree e por suíte de teste. **Nunca** apontar a suíte para banco compartilhado.
- **Testes sempre pela fila** (skill `fila-testes`).
- Versão de banco/runtime local diferente da produção: nada pode depender de comportamento exclusivo da versão local.
- **Setup não pode sujar o git**: conferir `git status` depois de instalar/gerar; o que for só local vai para `.git/info/exclude`.
- **A tool `Grep` respeita o `.gitignore`**: em pasta ignorada usar `grep -r`.
- Comando longo (instalação, suíte): foreground com timeout longo, sem matar; o que passar de 10 min vai para background e espera a notificação.
- Windows: os hooks e scripts do plugin rodam em **Git Bash**; `.bat`/`.cmd` não rodam direto no Git Bash (shims em `~/bin`, ver a ferramenta).

## Validação de UI
- **Toda mudança de UI é validada no browser, com perfil real, nunca administrador.**
- **Comparação visual com a branch base**: mesmas telas, perfil e largura na base e no worktree; cada diferença classificada como esperada ou regressão.
- **Padrão: navegador embutido do Orca, um por worktree.** Antes, invocar o skill `orca-cli` e ler `orca skills get orca-cli --reference references/browser.md`. Fluxo: `orca tab create --url <url do worktree> --json` → `snapshot --page <id>` → `fill`/`click --element @eN` → `wait` → `snapshot` de novo após navegar. **Sempre `--page <browserPageId>`** (sem ele vai para a aba do usuário).
- **Fallback: Playwright MCP.** Chrome DevTools MCP só para trace, Lighthouse, heap. Nunca matar o navegador de outro agente. Em subagente: `take_screenshot` em vez de `take_snapshot` em telas com árvore enorme (Filament, grids).
- Screenshot, trace e `.playwright-mcp/` vão para o worktree de quem gerou ou para o temporário, e não se commitam.

## Formato de `~/.claude/ambiente.md`
```markdown
# Ambiente desta máquina
- Sistema: Windows 11 | Ubuntu 24.04 | Fedora 41 | macOS 15
- Shell dos hooks: Git Bash | bash | zsh
- Pacotes: winget | apt | dnf | brew
- Sites servidos por: Herd | Laragon | FlyEnv | Lerd | DDEV | Sail | compose | nativo
- Bancos: MariaDB 11.8 em 127.0.0.1:3306 (Herd), root sem senha | Postgres 16 em 5432 (FlyEnv) | por projeto no container
- Contêiner: Docker | Podman (rootless) | nenhum
- Runtimes: PHP 8.4 (Herd) | Python 3.12 (uv) | Node 22 (fnm)
- Raiz dos projetos: ~/Herd | C:/laragon/www | ~/code

## Projetos
| Projeto | Caminho | Stack | Serve | Banco | Multi-tenant | Board | Base |
|---|---|---|---|---|---|---|---|
| app | ~/Herd/app | Laravel | Herd | MariaDB 3306 | não | org/app #1 | develop |
```

# fluxo-orca

Plugin do Claude Code (pt-BR) com um fluxo de trabalho com o Orca para projetos **Laravel, Python e JS/TS**, em Windows, Linux ou macOS: a sessão principal coordena, o trabalho vai para workers do Orca (um worktree por tarefa, com banco e `.env` próprios), todo diff passa por um revisor Opus antes do merge e os testes rodam por filas da máquina (2 vagas por recurso, teto global de 3). Hooks impõem as regras.

## Instalar

Instale o Claude Code e mande para ele:

> Siga o instalador https://github.com/VictorStochero/fluxo-orca/blob/main/GUIA.md e configure esta máquina para os meus projetos.

O Claude diagnostica o sistema, as ferramentas e os projetos, instala o que conseguir, pede para você rodar o que exigir privilégio ou login e configura tudo pela sua stack: plugins, `settings.json`, CLAUDE.md global, perfil da máquina, boards, Orca por projeto. Só o plugin:

```
/plugin marketplace add VictorStochero/claude-plugins
/plugin install fluxo-orca@stochero
```

## Conteúdo

| Tipo | Itens |
|---|---|
| Fluxo | `delegacao`, `board-github`, `limites-cota`, `fila-testes`, `worktree-orca`, `ambiente-local` (Herd, Laragon, FlyEnv, Lerd, DDEV/Sail/compose com Docker ou Podman, nativo) |
| Stacks | `stack-laravel`, `stack-python`, `stack-js` |
| Metodologia | `brainstorming`, `writing-plans`, `systematic-debugging`, `test-driven-development`, `verification-before-completion`, `receiving-code-review` |
| Agentes | `escritor` (Sonnet), `revisor` e `verificador` (Opus, só leitura) |
| Hooks | `fila-testes`, `bloqueia-bulk`, `despacho-orca`, `guia-laravel`, `instala-scripts`, `fim-worker` (worker do Orca não encerra sem `worker_done`); `guarda-externos` para os agentes externos |
| Scripts (em `~/.cache`) | `gs-teste.sh` (fila: 2 vagas por recurso, teto global `GS_TESTE_TETO` de 3) + `e-teste.sh` (detector de comando de teste, compartilhado com Codex/agy/Kimi pelo `guarda-externos.sh`), `wt-setup.sh`/`wt-archive.sh`/`wt-lib.sh` (worktree pelo Orca), `orca-espera.sh` (espera do coordenador: ack, estado real dos workers), `orca-libera.sh` (fecha o ciclo do worker: release, aba criada pelo `--cria` e vaga do pool), `vaga-agente.sh` (pool de agentes por conta da máquina), `limites.sh` + `kimi-cota.sh`/`codex-cota.sh` (cota), `guarda-externos.sh`, `fim-worker.sh` |
| Agentes externos (opcional) | Codex, agy e Kimi como workers do Orca, com as mesmas regras (`AGENTS.global.md`), as skills copiadas para `~/.agents/skills` e a trava de comando remoto; segunda conta Claude para escritores. Só entra o que estiver instalado (GUIA, fase 4b) |
| Extras | `CLAUDE.global.md` (modelo de `~/.claude/CLAUDE.md`), `AGENTS.global.md` (modelo de `~/.agents/AGENTS.md`), `somente-leitura.json` |

## Licença

MIT © Victor Stochero. As skills de metodologia vêm do [obra/superpowers](https://github.com/obra/superpowers) (MIT © Jesse Vincent, ver `skills/LICENSE-superpowers`), com pequenas adaptações para a delegação pelo Orca. **Não use junto com o plugin `superpowers`**: as skills ficam duplicadas e as originais conflitam com o fluxo.

# fluxo-orca

Plugin do Claude Code com um fluxo de trabalho Laravel + Orca em pt-BR, para Windows + Laravel Herd: a sessão principal coordena, o trabalho vai para workers do Orca (um worktree por tarefa), todo diff passa por um revisor Opus antes do merge e os testes PHP rodam por uma fila única da máquina. Hooks impõem as regras.

```
/plugin marketplace add VictorStochero/claude-plugins
/plugin install fluxo-orca@stochero
```

**Instalação completa** (pré-requisitos, outros plugins, `settings.json`, CLAUDE.md global, boards, verificação): [`GUIA.md`](GUIA.md). Para configurar com o Claude, mande para ele:

> Siga o guia https://github.com/VictorStochero/fluxo-orca/blob/main/GUIA.md e configure esta máquina.

## Conteúdo

| Tipo | Itens |
|---|---|
| Skills | `delegacao`, `ambiente-local`, `board-github`, `fila-testes`, `limites-cota`, `brainstorming`, `writing-plans`, `systematic-debugging`, `test-driven-development`, `verification-before-completion`, `receiving-code-review` |
| Agentes | `escritor` (Sonnet), `revisor` e `verificador` (Opus, só leitura) |
| Hooks | `fila-testes`, `bloqueia-bulk`, `despacho-orca`, `guia-laravel`, `instala-scripts` |
| Extras | `CLAUDE.global.md` (modelo de `~/.claude/CLAUDE.md`), `somente-leitura.json` |

## Licença

MIT © Victor Stochero. As skills `brainstorming`, `writing-plans`, `systematic-debugging`, `test-driven-development`, `verification-before-completion` e `receiving-code-review` vêm do [obra/superpowers](https://github.com/obra/superpowers) (MIT © Jesse Vincent, ver `skills/LICENSE-superpowers`), com pequenas adaptações.

# fluxo-orca

Plugin do Claude Code (pt-BR), versão **2.11.0**, com um fluxo de trabalho com o Orca para projetos **Laravel, Python e JS/TS**, em Windows, Linux ou macOS: a sessão principal coordena, o trabalho vai para workers do Orca (um worktree por tarefa, com banco e `.env` próprios), o merge passa por um gate Opus e os testes rodam por filas da máquina (2 vagas por recurso, teto global de 3). Hooks impõem as regras.

O gate é a auditoria em repositório que versiona `.auditoria-pre-subida` (auditor Opus, verificador só com achado); nos demais, o revisor Opus é obrigatório. O pacote contém pedido/issue original, critério copiado do board, diff e interfaces, sem resumo ou justificativa de quem pede o merge. A sessão principal prova cada teste novo de correção falhando no código do merge-base. Pagamento, autorização/permissão, autenticação e alteração de dado de produção exigem segunda opinião de outra família sobre o diff: “ache o caso que quebra”.

Papéis Claude só leitura usam sempre `--settings ~/.claude/agents/somente-leitura.json`, sem MCP de navegador. A conta principal pode revisar/verificar; conta com só `orquestra` continua fora do pool. Exemplo de `~/.claude/agentes.conf`:

```text
escolha=ritmo
teto=4
pessoal agente=claude peso=5 vagas=1 papeis=orquestra,revisor,verificador
team agente=claude config=~/.claude-team peso=1 vagas=2 papeis=escritor
codex agente=codex vagas=1 papeis=escritor
agy agente=antigravity vagas=1 papeis=segunda-opiniao
```

`peso` multiplica o ritmo (`escolha=ordem` ignora); `teto=0` deixa a máquina ilimitada. `CONTAS_ADVISOR` define o advisor do escritor Claude (padrão `opus`, vazio desliga); `LIMITES_CACHE_MIN` controla o cache de cota (padrão 5, 0 desliga). O alerta do coordenador mede a cada 20 minutos. Segunda opinião: `limites.sh --segunda --familia <claude|gpt|gemini>`, com preferência por Gemini do agy, grupo misto do agy e Codex, conforme cota e família.

## Instalar
Para separar projetos que usam o mesmo banco, `FILA_TESTE_FILA=projeto` usa uma fila por projeto, compartilhada pelos worktrees, com `FILA_TESTE_VAGAS_PROJETO=1` por padrão. O teto da máquina continua valendo; o modo padrão `recurso` permanece por porta/container/geral. Use `bash ~/.cache/fila-teste.sh`; o atalho `gs-teste.sh` e as variáveis `GS_TESTE_*` continuam aceitos por compatibilidade, com prioridade para `FILA_TESTE_*`. Os nomes das travas permanecem iguais.


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
| Hooks | `fila-testes`, `bloqueia-bulk`, `despacho-orca`, `guia-laravel`, `exige-transacao` (SQL de alteração via ssh/forge só em transação, COMMIT após ensaio com ROLLBACK), `instala-scripts`, `fim-worker` (worker do Orca não encerra sem `worker_done`); `guarda-externos` para os agentes externos |
| Scripts (em `~/.cache`) | `fila-teste.sh` (fila: 2 vagas por recurso, teto global `FILA_TESTE_TETO` de 3) + `e-teste.sh` (detector de comando de teste, compartilhado com Codex/agy pelo `guarda-externos.sh`), `wt-setup.sh`/`wt-archive.sh`/`wt-lib.sh` (worktree pelo Orca), `orca-espera.sh` (espera do coordenador: ack, estado real dos workers), `orca-inicia.sh` (`worker-start` com saída de uma linha; recibo em `~/.cache/orca-recibos/`), `orca-tela.sh` (últimas linhas úteis da tela de um terminal), `orca-libera.sh` (fecha o ciclo do worker: release, aba criada pelo `--cria` e vaga do pool), `vaga-agente.sh` (pool de agentes por conta da máquina), `contas.sh` + `agentes-catalogo.conf` (registro de contas sobre o catálogo dos 45 agentes do Orca, lido do `~/.claude/agentes.conf`), `limites.sh` + `medidores/` (cota por conta: `/usage` das contas Claude e `orca account list` para Codex, Antigravity, Kimi, MiniMax e demais; Kimi e MiniMax não testados com conta real), `guarda-externos.sh`, `fim-worker.sh` |
| Agentes externos (opcional) | Codex e agy como workers do Orca, com as mesmas regras (`AGENTS.global.md`), as skills copiadas para `~/.agents/skills` e a trava de comando remoto; segunda conta Claude para escritores. Só entra o que estiver instalado (GUIA, fase 4b) |
| Extras | `CLAUDE.global.md` (modelo de `~/.claude/CLAUDE.md`), `AGENTS.global.md` (modelo de `~/.agents/AGENTS.md`), `somente-leitura.json` |

## Licença

MIT © Victor Stochero. As skills de metodologia vêm do [obra/superpowers](https://github.com/obra/superpowers) (MIT © Jesse Vincent, ver `skills/LICENSE-superpowers`), com pequenas adaptações para a delegação pelo Orca. **Não use junto com o plugin `superpowers`**: as skills ficam duplicadas e as originais conflitam com o fluxo.

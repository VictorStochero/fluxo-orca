# Pool de agentes — plano e evidências

Escopo: implementar o mapa fornecido em `C:/Users/victor/.cache/handoff/pool-agentes/mapa.md`, neste worktree, sem alterar a fila existente.

Plano de execução:
- Criar `tests/pool.sh` com HOME temporário e Orca simulado, observar a falha inicial e registrar a saída.
- Implementar `skills/limites-cota/vaga-agente.sh`: mkdir atômico, configuração opcional, reserva/liberação e recuperação confirmada pelo dispatch.
- Integrar disponibilidade em `limites.sh`, instalar o script pelo hook e documentar reserva após `worker-start` e liberação após `worker-release`.
- Validar sintaxe, prova do pool e regressão `tests/fila.sh`, registrar as saídas e publicar commit/PR sobre `fix/20261011-fila-testes`.

Limites: team=1, codex=1, kimi=1, agy=1 e pessoal=0 (ilimitado). Orca indisponível, JSON inválido, dispatch ativo ou estado desconhecido conservam a vaga; somente estado terminal explícito ou `dispatch_not_found` permitem recuperação.

Implementação concluída no escopo: script do pool, seleção por disponibilidade e cota, instalação pelo SessionStart e instruções de delegação. A reserva usa o dispatch real imediatamente após `worker-start`; não usa ID provisório, que seria recuperado como inexistente. O fluxo documenta a disputa entre coordenadores no intervalo entre seleção/início/reserva: interromper novos despachos, escalar e seguir a recuperação do Orca; esse intervalo não garante um teto de processos.

As travas usam mkdir atômico e recuperação por rename com conferência do dono, seguindo o padrão da fila. Trava sem dispatch é conservada. A configuração reduzida contabiliza vagas antigas fora da nova faixa; um teste inicialmente detectou a falha dessa contagem e a implementação foi corrigida.

Validação em Git Bash, com HOME temporário para o executor da fila e HOME isolado dentro de cada prova:

```bash
HOME="$teste_home" bash skills/fila-testes/gs-teste.sh -- bash tests/pool.sh
HOME="$teste_home" bash skills/fila-testes/gs-teste.sh -- bash tests/fila.sh
```

Cada chamada recebeu um diretório temporário próprio, removido ao término. O cache real não foi usado para as provas. A prova final do pool simula Orca por `ORCA_CMD` e os provedores de cota por executáveis locais; não depende de credenciais nem de rede. Ambos os executores terminaram com exit 0. Sintaxe dos quatro arquivos bash alterados/criados (`bash -n`, uma chamada por arquivo) e `git diff --check` passaram; ShellCheck não está instalado.

Histórico de evidências: `pool-red.log` registra a falha inicial pela ausência do script e da filtragem de vagas; `pool-config-red.log` registra o caso de redução de limite e seu efeito sobre o teste seguinte. `pool-green.log` e `pool-fila-green.log` contêm as execuções finais completas, com todos os casos aprovados.

Fim da saída de `tests/pool.sh`:

```text
ok   seletor retorna 75 com pool cheio
ok   seletor informa pool cheio
ok   cota esgotada difere de pool cheio
ok   cota preserva diagnóstico
ok   seletor propaga erro do pool
ok   hook instala scripts em HOME temporário
ok   script do pool instalado
TUDO OK
```

Fim da saída de `tests/fila.sh`:

```text
ok   BLOQ: command em lista (Codex)
ok   executor explícito: migration Laravel na fila gs-teste, argumentos preservados
ok   executor explícito: migration Laravel na fila gs-teste-3307, argumentos preservados
ok   executor explícito: seed Laravel na fila de container, argumentos preservados
ok   teto=1: execuções não se sobrepõem e as vagas foram liberadas
ok   órfão: executor encerrado antes de liberar a vaga
TUDO OK
```

Divergências do mapa: nenhuma; a reserva após o início é uma das alternativas autorizadas. Não houve mudança em `orca-espera.sh` ou na implementação da fila de testes. Revisão e merge permanecem com o coordenador; PR baseado em `fix/20261011-fila-testes`, conforme solicitado.

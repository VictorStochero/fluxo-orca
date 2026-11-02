---
name: limites-cota
description: Use antes de despachar uma onda de workers ou quando perguntarem sobre cota, limite, pool de agentes, vagas por conta, contas da máquina ou quem deve ser o escritor — o pool é do agent-pool (`~/.agents/bin/agent-pool writer`, `second`, `slot`, `status`, `measure`, `config`): mede o uso de cada conta, escolhe o escritor e a segunda opinião e controla as vagas.
---

# Pool de agentes e cota — pelo CLI `agent-pool`

O pool (contas, cota, vagas, fila de testes) é do plugin **agent-pool** do Orca. Esta skill só usa o CLI `~/.agents/bin/agent-pool` (Windows: o `.cmd` ao lado), sempre pelo caminho do lançador (`~/.agents/bin` não está no PATH). Estado e configuração ficam com ele. Faltou o CLI → instalar o plugin agent-pool no Orca (aprovar o acesso) e conferir com `~/.agents/bin/agent-pool doctor`.

Saídas: uma linha legível por padrão e `--json` quando pedido. Códigos: **0** ok, **2** uso inválido, **75** sem vaga ou espera esgotada, **1** erro.

## Antes de cada onda
- `~/.agents/bin/agent-pool status` — fila de testes e pool (vagas usadas/total por conta); `--json` traz também a cota medida. Conta sem login aparece com a ação para reconectar.
- `~/.agents/bin/agent-pool measure [conta]` — mede a cota agora (5h e semanal), sem o cache. Dizer o motivo da linha quando vier `sem login` ou erro; não estimar.
- Acima do teto de cota a conta sai da vez (escritor 80%, ou 95% quando a janela longa zera em menos de 24 h; segunda opinião 60%). Revisão obrigatória continua em Opus mesmo com cota apertada: espera a janela zerar em vez de rebaixar o modelo.

## Escritor
`~/.agents/bin/agent-pool writer --reserve <tag>` escolhe a conta e **já reserva a vaga** (dono provisório `res-<tag>`). Saída: `<conta> (ritmo X.X · N% livre, zera em Hh)` (com `· peso N` quando diferente de 1; `sem medidor` quando a conta não mede) e `· reserva res-<tag>`. Sem `--reserve` só mostra a escolha. Sem conta apta, `sem vaga: <motivo>` e exit 75.
- `pool.escolha=ritmo` (padrão): vence o maior (cota livre × `peso`) entre as contas com papel `escritor`, ativas, com login e vaga; `ordem`: a primeira da lista (`pool.ordem`) elegível.
- Medir antes de cada designação; em onda com várias frentes, consultar antes de cada `worker-start`.

## Segunda opinião
`~/.agents/bin/agent-pool second --family <claude|gpt|gemini>` escolhe uma conta de **outra família** que a do escritor, com teto de cota de 60%, por maior folga. Sem candidata, exit 75. Uma por branch, na primeira entrega de alto risco, nunca nas rodadas de correção; pacote só com o diff e os arquivos tocados, pergunta fixa “ache o caso que quebra”, resposta só com achados `arquivo:linha` (alvo ≤ 3 KB).

## Vagas
- `~/.agents/bin/agent-pool slot take <conta> <dono>` reserva (avulso, para papéis que não são escritor: dono `res-<tag>`); `slot swap res-<tag> <dispatch>` troca o dono provisório pelo dispatch real (idempotente); `slot release <dispatch|res-tag>` libera; `slot free` mostra `<conta> livres/total` (`sem limite` = ilimitada, `inativa` = fora do pool) depois de recuperar vaga de dispatch encerrado.
- Reserva esquecida expira em 10 min. A recuperação só libera por estado terminal do dispatch confirmado no Orca; erro de conexão conserva a vaga.
- O teto da máquina (`pool.teto`) e a RAM livre mínima (`pool.ram_min`, GB) valem na reserva: abaixo do mínimo a reserva sai com 75. Para ver a memória: `orca diagnostics memory --json`.
- Fluxo de reserva e liberação no despacho: skill `delegacao`.

## Configuração
`~/.agents/bin/agent-pool config get [chave]` (sem chave imprime tudo; `pool.contas` lista as contas com `agente`, `config`, `comando`, `vagas`, `peso`, `papeis`, `ativo`) e `~/.agents/bin/agent-pool config set chave=valor …` — validação única, tudo ou nada.
- Pool: `pool.teto`, `pool.ram_min`, `pool.escolha=ritmo|ordem`, `pool.ordem=a,b,c`.
- Conta: `conta.<nome>.vagas|peso|papeis|ativo|config|comando` e `conta.<nome>.adicionar=<agente|auto>` / `conta.<nome>.remover=1`.
- Papéis: `escritor revisor verificador mecanico segunda-opiniao orquestra`. Papel de trabalho (`escritor`, `revisor`, `verificador`, `mecanico`) só em agente com imposição provada; `orquestra` ou lista vazia = conta só medida, nunca escolhida. A conta principal pode revisar/verificar; só `orquestra` fica fora do pool.
- **`ativo=nao`** ("Não utilizar"): a conta segue na lista e medida, mas sai de `writer` e `second`, `slot take` a recusa; worker que já roda nela segue contando no teto até terminar. Conta detectada pelo Orca e desativada nunca volta sozinha.
- Contas que o Orca gerencia entram sozinhas, ativas, com os padrões do catálogo; conta cadastrada no Orca que não é a padrão entra só medida (sem papel), porque o despacho e a medida ainda usam a padrão; conta manual (ex.: outra pasta `CLAUDE_CONFIG_DIR`) entra por `conta.<nome>.adicionar=auto` com `comando`/`config`.
- Escritor Claude recebe `--advisor opus`; papéis Claude só leitura sempre com `--settings ~/.claude/agents/somente-leitura.json`, sem MCP de navegador.

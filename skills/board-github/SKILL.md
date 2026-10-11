---
name: board-github
description: Use ao criar, editar, mover ou comentar issue/item nos GitHub Projects dos repositórios listados em ~/.claude/boards.md — campos, ids, status de conclusão e formato do comentário de conclusão com roteiro de QA.
---

# GitHub Projects — toda tarefa rastreada (onde há board)

Os boards da máquina ficam em `~/.claude/boards.md` (fora do plugin, porque têm ids internos). Uma tabela por board:

| Repositório | Board | nº | Owner | Project id |
|---|---|---|---|---|
| `<org>/<repo>` | `<nome>` | `<nº>` | `<org>` | `PVT_...` |

e, abaixo de cada um, os ids dos campos e das opções (Status, área/setor, prioridade, datas, textos) e o vocabulário de status daquele board. Arquivo ausente ou board faltando → montar com `gh project list --owner <org>` e `gh project field-list <nº> --owner <org> --format json`, gravar no `boards.md` e seguir.

Fora dessa lista não inventar board: trabalhar direto e, se parecer que deveria ter rastreamento, perguntar. Antes de assumir que não tem, conferir com `gh project list --owner <org>`.

- **Onde há board, nenhum trabalho existe fora dele** — mas **NUNCA criar issue ou item sem consultar o usuário antes.** Levar o achado na conversa (o que é, por que importa, o que custa) e esperar. Se rendeu commit, rende item — mas o item nasce da decisão dele. Tarefa que ele próprio pediu já vem decidida.
- **Uma issue por assunto, não por achado**: achados da mesma investigação vão numa issue agrupadora, um bloco por achado e um roteiro de QA cobrindo todos. Separar só frentes com donos ou prazos diferentes.
- **Achado fora do escopo da tarefa não vira issue nova**: entra na seção "Achados da sessão" do comentário de conclusão, um bloco por contexto (arquivos, telas, se falha também na base).
- **Cada board tem vocabulário próprio** — conferir com `field-list` antes de escrever qualquer valor.
- **Spec, plano, roadmap, mapa, censo e qualquer artefato de `docs/superpowers/` ou `.superpowers/` NÃO vão para o GitHub** (nem commit, nem issue, nem board) — conferir o stage antes de commitar.

## Ao criar
1. **Issue** com o problema, o comportamento esperado e o critério de pronto — quem lê o board não tem a conversa.
2. **Assignee** = o usuário (`gh api user --jq .login`), salvo ordem em contrário.
3. **Área/Setor** com o módulo tocado (`Geral` só para o que cruza módulos ou é infra), quando o board tiver o campo.
4. **Status** conforme o estado real (backlog ou em desenvolvimento, no vocabulário do board).
5. Demais campos do board, quando existirem:
   - **Data da tarefa** = data em que foi **DESIGNADA** (tarefa nova → hoje). Em tarefa existente, **nunca sobrescrever**.
   - **Tipo da issue**: tarefa · erro (defeito) · funcionalidade nova · sugestão (melhoria sobre algo que funciona).
   - **Fonte**: reunião · mensagem · interna (nasceu de investigação da sessão) · IA. Link da reunião só quando a fonte for reunião.
   - **Tema**: reaproveitar um existente — conferir no `fieldValues` dos itens recentes.
   - **Solicitante**: o usuário, quando o pedido veio dele.
   - **Observação**: uma linha do que quem pega precisa saber antes (risco de migration, dependência, janela); vazio se nada real.
   - **Prioridade**: média por padrão, sem perguntar; outra só quando o usuário disser.
   - **Revisor**: vazio, sem perguntar; só quando o usuário nomear.

Labels e milestone: só se o board usar.

## Durante
Item atualizado enquanto o trabalho anda (status e comentários). Descoberta que muda o diagnóstico, decisão de escopo, medição que derruba hipótese: comentário na issue, não só na conversa.

## Ao concluir
- **Board com etapa de teste**: terminou local, não mergeado → "concluído localmente"; mergeado na branch de homologação → "aguardando teste". **A issue fica ABERTA durante todo o teste** — é o canal de quem testa. Fechar só ao finalizar.
- **Board sem etapa de teste** (ex.: `Todo | In Progress | Done`): concluído e mergeado → `Done` e fechar. Se precisar de teste, o board ganha os status, não improvisar.
- Comentário de conclusão no formato abaixo, com o roteiro de teste, antes de mover para teste.

## Formato do comentário de conclusão
Abertura com o destino (`Mergeado em <base>: PR #NNNN (merge <sha>)` ou `Concluído localmente — PR aberto, ainda não mergeado: <url>`) e três blocos, nesta ordem — quem abrir a issue daqui a um mês tem de entender sem perguntar:

- **O que mudou** — arquivos com caminho, comportamento novo, o porquê quando não óbvio. Quando houver: **causa raiz** (o mecanismo, não o sintoma); o que ficou **deliberadamente de fora** e por quê; **divergência** entre o pedido e o feito; **ressalva de deploy** (ex.: `cache:clear`); **achado extra**.
- **Teste de regressão** — arquivo, o que cada cenário garante, números (`N testes, M asserções`). Em bug, que o teste **falhou antes** e o que a falha dizia. Registrar que a sessão principal rodou de novo e nomear falha pré-existente do lote.
- **Roteiro de teste** — **para o QA, sem nada técnico** (nada de classe, método, migration, tabela, coluna, id): passos numerados pela interface, o esperado de cada um, no passo corrigido uma linha de **comportamento errado anterior**, e casos de borda descritos pelo que se vê na tela.

## Comandos
```bash
gh issue create --repo <org>/<repo> --title "..." --body "..." --assignee <login>
gh project item-add <nº> --owner <org> --url <url-da-issue> --format json   # devolve o item id
gh project item-edit --project-id <PVT_...> --id <item-id> --field-id <field-id> --single-select-option-id <option-id>
gh project item-edit --project-id <PVT_...> --id <item-id> --field-id <field-id> --date <AAAA-MM-DD>
gh project item-edit --project-id <PVT_...> --id <item-id> --field-id <field-id> --text "<valor>"
gh issue edit <n> --repo <org>/<repo> --type "<tipo>"
```

- **Conferir o que foi gravado pelo id**, via GraphQL `node(id: "<item-id>")` — `gh project item-list` pagina e esconde item recente.
- `gh project item-edit` e `gh issue comment` podem voltar **502** no meio de um lote e falhar em silêncio: conferir sempre depois.

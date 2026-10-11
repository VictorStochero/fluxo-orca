# Itens 7 e 8 — fila de testes

## Investigação

- O detector compartilhado não reconhece operações de preparação do banco de teste.
- O executor explícito (`gs-teste.sh -- ...`) mantém `stack=outro`, portanto escolhe a fila geral mesmo em Laravel; ampliação mínima autorizada pelo coordenador via ask.
- Projeto composto por Bash e Markdown, sem stack JS/Python/Laravel nem guia de arquitetura próprio.
- Não alterar `skills/delegacao/orca-espera.sh` nem travas reais; provas usam HOME temporário.

## Plano

1. Item 7: adicionar casos de migrations/seeds de teste e contrapontos de desenvolvimento; observar falha, corrigir detector, documentar e validar; commit próprio.
2. Item 8: documentar wait-for-setup e confirmação de sucesso antes de tocar banco nos cinco textos indicados; commit próprio.
3. Extra: orientar leitura do terminal e Enter condicional em `turn_start_unobserved` no destino Codex; commit próprio.
4. Reexecutar prova, registrar o fim da saída, enviar branch e comentar PR #2.

## Evidência inicial

`reports/fila-item7-red.log`: 12 casos novos falharam nos dois hooks (Claude e externos), todos relativos à preparação do banco de teste; contrapontos de desenvolvimento passaram.

A migration interna de `wt-setup.sh` foi preservada: o wrapper `artisan()` trata PHP e DDEV, cuja função não atravessa diretamente o executor externo; a alteração opcional exigiria tratamento adicional do setup além dos arquivos designados.

A primeira prova da escolha da fila falhou porque o Git Bash ignorava o stub `php` sem shebang e resolvia o shim real; comparação com `type -a php` confirmou a causa. Adicionado `#!/bin/bash` ao executor simulado para garantir isolamento.

## Validação do item 7

`bash tests/fila.sh`: exit 0, 52 verificações com `ok`, encerrando com `TUDO OK`; saída completa em `fila-item7-green.log`. `bash -n` nos três scripts alterados e `git diff --check` passaram; shellcheck não está instalado.

Fim da saída:

```text
ok   BLOQ: command em lista (Codex)
ok   executor explícito: migration Laravel na fila gs-teste, argumentos preservados
ok   executor explícito: migration Laravel na fila gs-teste-3307, argumentos preservados
ok   executor explícito: seed Laravel na fila de container, argumentos preservados
ok   teto=1: execuções não se sobrepõem e as vagas foram liberadas
ok   órfão: executor encerrado antes de liberar a vaga
TUDO OK
```

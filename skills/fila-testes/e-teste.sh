#!/bin/bash
# Detector de comando de teste fora da fila. Lê o JSON do hook no stdin.
# exit 0 = é comando de teste sem a fila; exit 1 = não é (ou não há comando).
# O comando vem em "command" (string, ou lista no Codex) ou "cmd"; usado por fila-testes.sh e guarda-externos.sh.
in=$(cat)
cmd=$(printf '%s' "$in" | grep -oE '"(command|cmd)"[[:space:]]*:[[:space:]]*("([^"\\]|\\.)*"|\[[^]]*\])' | head -1)
[ -z "$cmd" ] && exit 1
# Livres saem da análise por trecho (entre ; & |), não o comando inteiro: `npm ci && npm test` segue bloqueado.
cmd=$(printf '%s' "$cmd" | sed -E \
    -e 's/[^;&|]*gs-teste\.sh[^;&|]*//g' \
    -e 's/[^;&|]*(--list-tests|--collect-only|--listTests|vitest[[:space:]]+list)[^;&|]*//g' \
    -e 's/(pip|pip3|uv|poetry|pipenv|npm|pnpm|yarn|bun|composer)[[:space:]]+(install|add|i|ci|sync|remove|uninstall|require)[^;&|]*//g')
s='(^|["[:space:];&|(/])'
e='([[:space:]"\\]|$)'
printf '%s' "$cmd" | grep -qE "artisan[[:space:]]+test|vendor/bin/(pest|phpunit)|pestphp/pest/bin/pest|sail[[:space:]]+(test|pest)$e|${s}pytest$e|-m[[:space:]]+(pytest|unittest)|manage\.py[[:space:]]+test|${s}(vitest|jest)$e|${s}(npm|pnpm|yarn|bun)[[:space:]]+(run[[:space:]]+)?test(:[[:alnum:]:_-]+)?$e|${s}composer[[:space:]]+(run(-script)?[[:space:]]+)?test$e|${s}(cargo|go)[[:space:]]+test$e"

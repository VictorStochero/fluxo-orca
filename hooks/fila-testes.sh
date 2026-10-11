#!/bin/bash
# PreToolUse (Bash|PowerShell): teste só pela fila única da máquina (~/.cache/gs-teste.sh).
# Cobre artisan test/pest, sail test/pest, pytest, manage.py test, vitest, jest e o script "test" de npm/pnpm/yarn/bun.
# Livres: listagem (--list-tests, --collect-only, vitest list, --listTests) e instalação de pacote.
in=$(cat)
cmd=$(printf '%s' "$in" | grep -oE '"command"[[:space:]]*:[[:space:]]*"([^"\\]|\\.)*"' | head -1)
[ -z "$cmd" ] && exit 0
# Livres saem da análise por trecho (entre ; & |), não o comando inteiro: `npm ci && npm test` segue bloqueado.
cmd=$(printf '%s' "$cmd" | sed -E \
    -e 's/[^;&|]*gs-teste\.sh[^;&|]*//g' \
    -e 's/[^;&|]*(--list-tests|--collect-only|--listTests|vitest[[:space:]]+list)[^;&|]*//g' \
    -e 's/(pip|pip3|uv|poetry|pipenv|npm|pnpm|yarn|bun)[[:space:]]+(install|add|i|ci|sync|remove|uninstall)[^;&|]*//g')
s='(^|["[:space:];&|(/])'
e='([[:space:]"]|$)'
if printf '%s' "$cmd" | grep -qE "artisan[[:space:]]+test|vendor/bin/(pest|phpunit)|pestphp/pest/bin/pest|sail[[:space:]]+(test|pest)$e|${s}pytest$e|-m[[:space:]]+pytest|manage\.py[[:space:]]+test|${s}(vitest|jest)$e|${s}(npm|pnpm|yarn|bun)[[:space:]]+(run[[:space:]]+)?test(:[[:alnum:]:_-]+)?$e"; then
    echo "Teste bloqueado: rode pela fila única da máquina -> bash ~/.cache/gs-teste.sh <argumentos> (detecta a stack) ou bash ~/.cache/gs-teste.sh -- <comando> (um teste por vez; se responder FILA OCUPADA, rode de novo)." >&2
    exit 2
fi
exit 0

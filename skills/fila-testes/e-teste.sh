#!/bin/bash
# Detector de comando de teste fora da fila. Lê o JSON do hook no stdin.
# exit 0 = é comando de teste sem a fila; exit 1 = não é (ou não há comando).
# O comando vem em "command" (string, ou lista no Codex) ou "cmd"; usado por fila-testes.sh e guarda-externos.sh.
in=$(cat)
cmd=$(printf '%s' "$in" | grep -oE '"(command|cmd)"[[:space:]]*:[[:space:]]*("([^"\\]|\\.)*"|\[[^]]*\])' | head -1)
[ -z "$cmd" ] && exit 1
# Livres saem da análise por trecho (entre ; & |), não o comando inteiro: `npm ci && npm test` segue bloqueado.
# Texto de mensagem não é comando: o valor de -m/--message (git commit) e de --body/--subject/--title (gh, orca) sai antes de casar.
v='(\\"[^"]*\\"|'"'[^']*'"'|[^[:space:];&|"]+)'
cmd=$(printf '%s' "$cmd" | sed -E \
    -e "/git[[:space:]]+commit/ s/(^|[[:space:]])(-a?m|--message)([[:space:]]+|=)$v//g" \
    -e "s/--(body|subject|title)([[:space:]]+|=)$v//g" \
    -e 's/[^;&|]*gs-teste\.sh[^;&|]*//g' \
    -e 's/[^;&|]*(--list-tests|--collect-only|--listTests|vitest[[:space:]]+list)[^;&|]*//g' \
    -e 's/(pip|pip3|uv|poetry|pipenv|npm|pnpm|yarn|bun|composer)[[:space:]]+(install|add|i|ci|sync|remove|uninstall|require)[^;&|]*//g')
s='(^|["[:space:];&|(/])'
e='([[:space:]"\\]|$)'
if printf '%s' "$cmd" | grep -qE "artisan[[:space:]]+test|vendor/bin/(pest|phpunit)|pestphp/pest/bin/pest|sail[[:space:]]+(test|pest)$e|${s}pytest$e|-m[[:space:]]+(pytest|unittest)|manage\.py[[:space:]]+test|${s}(vitest|jest)$e|${s}(npm|pnpm|yarn|bun)[[:space:]]+(run[[:space:]]+)?test(:[[:alnum:]:_-]+)?$e|${s}composer[[:space:]]+(run(-script)?[[:space:]]+)?test$e|${s}(cargo|go)[[:space:]]+test$e"; then
    exit 0
fi
# A opção de teste precisa estar no mesmo trecho da operação de banco.
while IFS= read -r trecho; do
    if printf '%s' "$trecho" | grep -qE "artisan[[:space:]]+(migrate(:[[:alnum:]_-]+)?|db:(wipe|seed))$e" \
        && printf '%s' "$trecho" | grep -qE -- "--env(=|[[:space:]]+)[\"']?testing([\"'[:space:]]|$)|--database(=|[[:space:]]+)[\"']?([[:alnum:]_.-]*[_.-])?test(ing)?([_.-][[:alnum:]_.-]*)?([\"'[:space:]]|$)"; then
        exit 0
    fi
    if printf '%s' "$trecho" | grep -qE "manage\.py[[:space:]]+(migrate|flush)$e" \
        && printf '%s' "$trecho" | grep -qE -- "--settings(=|[[:space:]]+)[\"']?[[:alnum:]_.]*test[[:alnum:]_.]*([\"'[:space:]]|$)"; then
        exit 0
    fi
done < <(printf '%s\n' "$cmd" | sed 's/\\"/"/g' | tr ';&|' '\n')
exit 1

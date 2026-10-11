#!/bin/bash
# Prova da fila de testes: detector (hook do Claude e guarda dos externos) e teto global.
# Uso: bash tests/fila.sh   (HOME temporário: não toca nas travas reais em ~/.cache)
raiz=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
falhas=0
ok() { echo "ok   $1"; }
ruim() { echo "FALHA $1"; falhas=$((falhas + 1)); }

# Guarda dos externos roda de ~/.cache, ao lado do e-teste.sh.
cp "$raiz/hooks/guarda-externos.sh" "$raiz/skills/fila-testes/e-teste.sh" "$tmp/"

json() { # comando -> JSON de PreToolUse com o comando escapado
    local c=${1//\\/\\\\}; c=${c//\"/\\\"}
    printf '{"tool_name":"Bash","tool_input":{"command":"%s"}}' "$c"
}
confere() { # esperado(BLOQ|LIVRE) comando
    local esp=$1 c=$2 r1=LIVRE r2=LIVRE
    json "$c" | bash "$raiz/hooks/fila-testes.sh" 2>/dev/null; [ $? = 2 ] && r1=BLOQ
    json "$c" | bash "$tmp/guarda-externos.sh" codex 2>/dev/null | grep -q '"deny"' && r2=BLOQ
    if [ "$r1" = "$esp" ] && [ "$r2" = "$esp" ]; then ok "$esp: $c"; else ruim "esperado $esp, claude=$r1 externos=$r2: $c"; fi
}

for c in 'php artisan test' 'npm ci && npm test' 'pytest -x' 'composer test' 'cargo test' 'bash -c "pytest"' \
         'npx vitest run' 'php vendor/pestphp/pest/bin/pest' 'python -m unittest' 'pnpm exec vitest run' 'go test ./...'; do
    confere BLOQ "$c"
done
for c in 'php artisan test --list-tests' 'pytest --collect-only' 'npx vitest list' 'npx jest --listTests' \
         'composer install' 'composer require foo/bar' 'npm ci' 'pip install pytest' \
         'bash ~/.cache/gs-teste.sh cargo test' 'bash ~/.cache/gs-teste.sh -- go test ./...' 'git status'; do
    confere LIVRE "$c"
done

# Codex manda o comando como lista.
printf '{"tool_input":{"command":["bash","-lc","pytest -x"]}}' | bash "$tmp/guarda-externos.sh" codex | grep -q '"deny"' \
    && ok "BLOQ: command em lista (Codex)" || ruim "command em lista (Codex) passou"

[ $falhas = 0 ] && echo "TUDO OK" || { echo "$falhas falha(s)"; exit 1; }

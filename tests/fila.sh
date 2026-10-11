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

# Teto global: com GS_TESTE_TETO=1, duas pastas (filas gerais diferentes não existem: ambas "geral", mas vagas=2) não se sobrepõem.
export HOME="$tmp/home"; mkdir -p "$HOME" "$tmp/a" "$tmp/b"
cat > "$tmp/rodar.sh" <<'E'
echo "$(date +%s.%N) ini" >> "$2"; bash "$1/skills/fila-testes/gs-teste.sh" -- sleep 3; echo "$(date +%s.%N) fim" >> "$2"
E
(cd "$tmp/a" && GS_TESTE_TETO=1 bash "$tmp/rodar.sh" "$raiz" "$tmp/a.log") &
sleep 1
(cd "$tmp/b" && GS_TESTE_TETO=1 bash "$tmp/rodar.sh" "$raiz" "$tmp/b.log") &
wait
fim_a=$(awk '/fim/{print $1}' "$tmp/a.log"); ini_b=$(awk '/ini/{print $1}' "$tmp/b.log")
# b pediu 2 s depois do início de a, mas só pode ter a vaga do teto depois que a terminou (a leva ~3 s; b dorme em passos de 5 s).
if [ -z "$(ls "$HOME/.cache" 2>/dev/null | grep -E 'lock[0-9]$')" ] && awk "BEGIN{exit !($(awk '/fim/{print $1}' "$tmp/b.log") - 3 >= $fim_a - 0.5)}"; then
    ok "teto=1: execuções não se sobrepõem e as vagas foram liberadas"
else
    ruim "teto=1: sobreposição ou vaga não liberada (fim_a=$fim_a ini_b=$ini_b)"
fi

# Órfão: bash do gs-teste morto à força deixa o executor vivo; o próximo run encerra o órfão antes de liberar a vaga.
rm -rf "$HOME/.cache"; mkdir -p "$tmp/c"
if command -v taskkill >/dev/null 2>&1; then lento=(ping -n 40 127.0.0.1); else lento=(sleep 40); fi
(cd "$tmp/c" && GS_TESTE_VAGAS=1 bash "$raiz/skills/fila-testes/gs-teste.sh" -- "${lento[@]}" >/dev/null 2>&1) &
sleep 3
dono=$(cat "$HOME/.cache/gs-teste-geral.lock1/pid" 2>/dev/null)
filho=$(cat "$HOME/.cache/gs-teste-geral.lock1/filho" 2>/dev/null)
if [ -r "/proc/$dono/winpid" ]; then taskkill //F //PID "$(cat "/proc/$dono/winpid")" >/dev/null 2>&1; else kill -9 "$dono"; fi
sleep 1
vivo_antes=0; kill -0 "$filho" 2>/dev/null && vivo_antes=1
(cd "$tmp/c" && GS_TESTE_VAGAS=1 bash "$raiz/skills/fila-testes/gs-teste.sh" -- true >/dev/null 2>&1); rc=$?
vivo_depois=0; kill -0 "$filho" 2>/dev/null && vivo_depois=1
if [ -n "$filho" ] && [ $vivo_antes = 1 ] && [ $vivo_depois = 0 ] && [ $rc = 0 ]; then
    ok "órfão: executor encerrado antes de liberar a vaga"
else
    ruim "órfão: filho=$filho vivo_antes=$vivo_antes vivo_depois=$vivo_depois rc=$rc"
    [ -n "$filho" ] && { w=$(cat "/proc/$filho/winpid" 2>/dev/null); [ -n "$w" ] && taskkill //F //T //PID "$w" >/dev/null 2>&1 || kill "$filho" 2>/dev/null; }
fi

[ $falhas = 0 ] && echo "TUDO OK" || { echo "$falhas falha(s)"; exit 1; }

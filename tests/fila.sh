#!/bin/bash
# Prova da fila de testes: detector (hook do Claude e guarda dos externos) e teto global.
# Uso: bash tests/fila.sh   (HOME temporário: não toca nas travas reais em ~/.cache)
raiz=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
falhas=0
fila_script="$raiz/skills/fila-testes/fila-teste.sh"
ok() { echo "ok   $1"; }
ruim() { echo "FALHA $1"; falhas=$((falhas + 1)); }

projeto() (
    export HOME="$tmp/projeto-home" FILAS_REGISTRO="$tmp/filas"
    mkdir -p "$HOME" "$tmp/Projeto A" "$tmp/projeto-b"
    for p in "$tmp/Projeto A" "$tmp/projeto-b"; do
        git -C "$p" init -q -b main
        git -C "$p" -c user.name=t -c user.email=t@t commit -q --allow-empty -m inicial
    done
    git -C "$tmp/Projeto A" worktree add -q --detach "$tmp/worktree-a"
    git -C "$tmp/Projeto A" worktree add -q --detach "$tmp/worktree-b"
    cat > "$tmp/confere-fila.sh" <<'E'
for v in "$HOME"/.cache/gs-teste-proj-*.lock[0-9]*; do
    [ -d "$v" ] && printf '%s\n' "${v##*/}" >> "$FILAS_REGISTRO"
done
E
    for p in "$tmp/worktree-a" "$tmp/worktree-b" "$tmp/projeto-b"; do
        (cd "$p" && FILA_TESTE_FILA=projeto bash "$fila_script" -- bash "$tmp/confere-fila.sh") || exit 1
    done
    esperado=$(printf 'gs-teste-proj-projeto_a.lock1\ngs-teste-proj-projeto_a.lock1\ngs-teste-proj-projeto-b.lock1')
    [ "$(cat "$FILAS_REGISTRO" 2>/dev/null)" = "$esperado" ]
)
if projeto; then ok 'projeto: worktrees compartilham fila e projetos distintos têm filas distintas'; else ruim 'filas por projeto'; fi
if [ "${FILA_SOMENTE_PROJETO:-}" = 1 ]; then [ "$falhas" = 0 ]; exit $?; fi

compatibilidade() (
    export HOME="$tmp/compat-home" SEQ_REAL="$(command -v seq)" SEQ_REGISTRO="$tmp/seq-args"
    mkdir -p "$HOME" "$tmp/compat-bin" "$tmp/compat-projeto"
    cat > "$tmp/compat-bin/seq" <<'E'
#!/bin/bash
printf '%s\n' "$*" >> "$SEQ_REGISTRO"
exec "$SEQ_REAL" "$@"
E
    chmod +x "$tmp/compat-bin/seq"
    export PATH="$tmp/compat-bin:$PATH"
    cd "$tmp/compat-projeto" || exit 1
    bash "$raiz/skills/fila-testes/gs-teste.sh" -- true || exit 1
    : > "$SEQ_REGISTRO"
    FILA_TESTE_VAGAS= GS_TESTE_VAGAS=2 bash "$fila_script" -- true || exit 1
    read -r primeira < "$SEQ_REGISTRO"; [ "$primeira" = '1 2' ] || exit 1
    : > "$SEQ_REGISTRO"
    FILA_TESTE_VAGAS=3 GS_TESTE_VAGAS=1 bash "$fila_script" -- true || exit 1
    read -r primeira < "$SEQ_REGISTRO"; [ "$primeira" = '1 3' ]
)
if compatibilidade; then ok 'compatibilidade: atalho antigo, fallback de vagas e prioridade do nome novo'; else ruim 'compatibilidade da fila'; fi
if [ "${FILA_SOMENTE_COMPATIBILIDADE:-}" = 1 ]; then [ "$falhas" = 0 ]; exit $?; fi

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
         'npx vitest run' 'php vendor/pestphp/pest/bin/pest' 'python -m unittest' 'pnpm exec vitest run' 'go test ./...' \
         'git commit -m "x" && pytest' 'python -m pytest -m "not slow"'; do
    confere BLOQ "$c"
done

for c in 'php artisan migrate --env=testing --force' 'php artisan migrate:fresh --env=testing --force' \
         'php artisan migrate:rollback --env testing' 'php artisan db:wipe --env="testing"' \
         "php artisan db:seed --env='testing'" 'php artisan migrate --database=mysql_test' \
         'php artisan db:seed --database test_mysql' 'php artisan db:wipe --database=testing' \
         'python manage.py migrate --settings=app.settings.test' 'python manage.py flush --settings app.test_settings' \
         'bash -c "php artisan migrate:fresh --env=testing --force"' \
         'php artisan migrate --env=local && php artisan db:seed --env=testing'; do
    confere BLOQ "$c"
done
for c in 'php artisan migrate:fresh --force' 'php artisan db:wipe --env=local' \
         'php artisan db:seed --database=mysql' 'php artisan migrate --env=testing_extra' \
         'php artisan migrate:status --database=latest' 'php artisan migrate --database=contest' \
         'python manage.py migrate' 'python manage.py flush --settings=app.settings.dev' \
         'php artisan migrate --env=local && echo --env=testing' \
         'python manage.py migrate && echo --settings=app.test' \
         'bash ~/.cache/fila-teste.sh -- php artisan migrate:fresh --env=testing --force' \
         'bash ~/.cache/fila-teste.sh -- python manage.py flush --settings=app.test'; do
    confere LIVRE "$c"
done
for c in 'php artisan test --list-tests' 'pytest --collect-only' 'npx vitest list' 'npx jest --listTests' \
         'git commit -m "docs: explica go test"' 'git commit -am "fix: roda pytest"' 'orca orchestration send --body "rode pytest" --type x' \
         'gh pr comment 2 --body "npm test ok"' 'git commit -m "x" && git status' \
         'composer install' 'composer require foo/bar' 'npm ci' 'pip install pytest' \
         'bash ~/.cache/fila-teste.sh cargo test' 'bash ~/.cache/fila-teste.sh -- go test ./...' 'git status'; do
    confere LIVRE "$c"
done

subcomando=test
for busca in grep egrep fgrep rg 'git grep' findstr Select-String; do
    confere LIVRE "$busca -l -E \"artisan $subcomando|pest|phpunit\" *.yml"
    confere BLOQ "php artisan $subcomando | $busca x"
    confere BLOQ "$busca artisan README.md; php artisan $subcomando"
done

# Codex manda o comando como lista.
printf '{"tool_input":{"command":["bash","-lc","pytest -x"]}}' | bash "$tmp/guarda-externos.sh" codex | grep -q '"deny"' \
    && ok "BLOQ: command em lista (Codex)" || ruim "command em lista (Codex) passou"

# Teto global: com FILA_TESTE_TETO=1, duas pastas (filas gerais diferentes não existem: ambas "geral", mas vagas=2) não se sobrepõem.
export HOME="$tmp/home"; mkdir -p "$HOME" "$tmp/a" "$tmp/b"
# Executor explícito em Laravel usa a mesma fila da suíte, sem executar PHP real.
mkdir -p "$tmp/laravel" "$tmp/bin"
touch "$tmp/laravel/artisan"
cat > "$tmp/bin/php" <<'E'
#!/bin/bash
[ -d "$HOME/.cache/$FILA_ESPERADA.lock1" ] && [ ! -d "$HOME/.cache/gs-teste-geral.lock1" ] || exit 1
printf '%s\n' "$*" > "$HOME/executor.log"
E
cp "$tmp/bin/php" "$tmp/bin/ddev"
chmod +x "$tmp/bin/php" "$tmp/bin/ddev"
for porta in 3306 3307; do
    printf 'DB_PORT=%s\n' "$porta" > "$tmp/laravel/.env.testing"
    fila=gs-teste; [ "$porta" = 3307 ] && fila=gs-teste-3307
    (cd "$tmp/laravel" && PATH="$tmp/bin:$PATH" FILA_ESPERADA="$fila" bash "$fila_script" -- php artisan migrate:fresh --env=testing --force)
    rc=$?
    if [ "$rc" = 0 ] && [ "$(cat "$HOME/executor.log")" = 'artisan migrate:fresh --env=testing --force' ]; then
        ok "executor explícito: migration Laravel na fila $fila, argumentos preservados"
    else
        ruim "executor explícito: fila $fila ou argumentos incorretos (rc=$rc)"
    fi
done
(cd "$tmp/laravel" && PATH="$tmp/bin:$PATH" FILA_ESPERADA=gs-teste-ctr bash "$fila_script" -- ddev artisan db:seed --env=testing)
rc=$?
if [ "$rc" = 0 ] && [ "$(cat "$HOME/executor.log")" = 'artisan db:seed --env=testing' ]; then
    ok "executor explícito: seed Laravel na fila de container, argumentos preservados"
else
    ruim "executor explícito: fila de container ou argumentos incorretos (rc=$rc)"
fi
# Executor de host que não é php (vendor/bin/pest etc.) usa a fila da porta, não a de container.
cp "$tmp/bin/php" "$tmp/bin/pest"; chmod +x "$tmp/bin/pest"
printf 'DB_PORT=3306\n' > "$tmp/laravel/.env.testing"
(cd "$tmp/laravel" && PATH="$tmp/bin:$PATH" FILA_ESPERADA=gs-teste bash "$fila_script" -- pest --env=testing)
rc=$?
if [ "$rc" = 0 ]; then ok "executor explícito: pest no host usa a fila da porta"; else ruim "executor explícito: pest no host caiu na fila de container (rc=$rc)"; fi
cat > "$tmp/rodar.sh" <<'E'
echo "$(date +%s) ini" >> "$2"; bash "$1/skills/fila-testes/fila-teste.sh" -- sleep 3; echo "$(date +%s) fim" >> "$2"
E
(cd "$tmp/a" && FILA_TESTE_TETO=1 bash "$tmp/rodar.sh" "$raiz" "$tmp/a.log") &
sleep 1
(cd "$tmp/b" && FILA_TESTE_TETO=1 bash "$tmp/rodar.sh" "$raiz" "$tmp/b.log") &
wait
fim_a=$(awk '/fim/{print $1}' "$tmp/a.log"); ini_b=$(awk '/ini/{print $1}' "$tmp/b.log")
# b pediu 2 s depois do início de a, mas só pode ter a vaga do teto depois que a terminou (a leva ~3 s; b dorme em passos de 5 s).
if [ -z "$(ls "$HOME/.cache" 2>/dev/null | grep -E 'lock[0-9]$')" ] && awk "BEGIN{exit !($(awk '/fim/{print $1}' "$tmp/b.log") - 3 >= $fim_a - 1)}"; then
    ok "teto=1: execuções não se sobrepõem e as vagas foram liberadas"
else
    ruim "teto=1: sobreposição ou vaga não liberada (fim_a=$fim_a ini_b=$ini_b)"
fi

# Órfão: bash do fila-teste morto à força deixa o executor vivo; o próximo run encerra o órfão antes de liberar a vaga.
rm -rf "$HOME/.cache"; mkdir -p "$tmp/c"
if command -v taskkill >/dev/null 2>&1; then lento=(ping -n 40 127.0.0.1); else lento=(sleep 40); fi
(cd "$tmp/c" && FILA_TESTE_VAGAS=1 bash "$fila_script" -- "${lento[@]}" >/dev/null 2>&1) &
sleep 3
dono=$(cat "$HOME/.cache/gs-teste-geral.lock1/pid" 2>/dev/null)
filho=$(cut -d' ' -f1 "$HOME/.cache/gs-teste-geral.lock1/filho" 2>/dev/null)
if [ -r "/proc/$dono/winpid" ]; then taskkill //F //PID "$(cat "/proc/$dono/winpid")" >/dev/null 2>&1; else kill -9 "$dono"; fi
sleep 1
vivo_antes=0; kill -0 "$filho" 2>/dev/null && vivo_antes=1
(cd "$tmp/c" && FILA_TESTE_VAGAS=1 bash "$fila_script" -- true >/dev/null 2>&1); rc=$?
vivo_depois=0; kill -0 "$filho" 2>/dev/null && vivo_depois=1
if [ -n "$filho" ] && [ $vivo_antes = 1 ] && [ $vivo_depois = 0 ] && [ $rc = 0 ]; then
    ok "órfão: executor encerrado antes de liberar a vaga"
else
    ruim "órfão: filho=$filho vivo_antes=$vivo_antes vivo_depois=$vivo_depois rc=$rc"
    [ -n "$filho" ] && { w=$(cat "/proc/$filho/winpid" 2>/dev/null); [ -n "$w" ] && taskkill //F //T //PID "$w" >/dev/null 2>&1 || kill "$filho" 2>/dev/null; }
fi

# Conta ilegível não vira candidata a escritor.
mkdir -p "$tmp/cota/bin" "$HOME/.claude-team"
cat > "$tmp/cota/bin/claude" <<'E'
#!/bin/bash
case "$*" in *haiku*) echo "sem login";; *) echo "Current session: 50% used"; echo "Current week (all models): 60% used";; esac
E
printf '#!/bin/bash\nexit 1\n' > "$tmp/cota/bin/agy"; cp "$tmp/cota/bin/agy" "$tmp/cota/bin/codex"
chmod +x "$tmp/cota/bin/"*
# Cópia isolada; Orca simulado fora do ar: o Codex real não entra na conta.
cp -r "$raiz/skills/limites-cota/limites.sh" "$raiz/skills/limites-cota/vaga-agente.sh" "$raiz/skills/limites-cota/contas.sh" \
    "$raiz/skills/limites-cota/agentes-catalogo.conf" "$raiz/skills/limites-cota/medidores" "$tmp/cota/"
esc=$(PATH="$tmp/cota/bin:$PATH" ORCA_CMD="$tmp/cota/bin/agy" bash "$tmp/cota/limites.sh" --escritor 2>/dev/null | tail -1)
if [ "$esc" = "escritor: pessoal (ritmo 0.4 · 40% livre)" ]; then ok "escritor: conta ilegível não é candidata"; else ruim "escritor: conta ilegível escolhida ($esc)"; fi

# Pid reciclado: vaga morta cujo filho é um processo alheio vivo (sem identidade conferida) não pode ser morto.
rm -rf "$HOME/.cache"; mkdir -p "$HOME/.cache/gs-teste-geral.lock1" "$tmp/d"
sleep 40 & alheio=$!
true & morto=$!; wait $morto
printf '%s
' "$morto" > "$HOME/.cache/gs-teste-geral.lock1/pid"; printf '%s
' "$alheio" > "$HOME/.cache/gs-teste-geral.lock1/filho"
(cd "$tmp/d" && FILA_TESTE_VAGAS=1 bash "$fila_script" -- true >/dev/null 2>&1)
if kill -0 "$alheio" 2>/dev/null; then ok "pid reciclado: processo alheio preservado"; else ruim "pid reciclado: processo alheio foi morto"; fi
kill "$alheio" 2>/dev/null

[ $falhas = 0 ] && echo "TUDO OK" || { echo "$falhas falha(s)"; exit 1; }

#!/bin/bash
# Semáforo de testes da máquina: até DOIS `php artisan test` por vez entre todos os worktrees e sessões.
# Uso, no cwd do worktree: DB_DATABASE=<banco próprio> bash ~/.cache/gs-teste.sh <argumentos do artisan test>
# --parallel roda com 8 processos. Espera vaga até 5 min; sem vaga, sai com 75 (rode de novo).
# Mesmo worktree + mesmo banco nunca rodam juntos: os bancos de teste se corromperiam.
# Uma fila por instância do MariaDB (DB_PORT do .env.testing): 3306 usa gs-teste.lockN, as outras gs-teste-<porta>.lockN.
# Imposto pelo hook ~/.claude/hooks/fila-testes.sh (bloqueia artisan test/pest fora daqui).
VAGAS=2
eu="$(pwd) [$DB_DATABASE]"
porta=$(grep -E '^DB_PORT=' .env.testing 2>/dev/null | head -1 | cut -d= -f2 | tr -d '"\r')
porta=${porta:-3306}
if [ "$porta" = 3306 ]; then trava=$HOME/.cache/gs-teste.lock; else trava=$HOME/.cache/gs-teste-$porta.lock; fi
args=()
paralelo=0
for a in "$@"; do
    case "$a" in
        --processes=*) continue ;;
        --parallel) paralelo=1 ;;
    esac
    args+=("$a")
done
[ $paralelo = 1 ] && args+=("--processes=8")
limite=$((SECONDS + 300))
L=""
while [ -z "$L" ]; do
    mesmo=0
    for i in $(seq 1 $VAGAS); do
        d=$(cat $trava$i/dono 2>/dev/null)
        p=$(cat $trava$i/pid 2>/dev/null)
        [ -n "$d" ] && [ "${d%% desde *}" = "$eu" ] && [ -n "$p" ] && kill -0 "$p" 2>/dev/null && mesmo=1
    done
    for i in $(seq 1 $VAGAS); do
        [ $mesmo = 1 ] && break
        v=$trava$i
        if mkdir "$v" 2>/dev/null; then L=$v; break; fi
        dono=$(cat "$v/pid" 2>/dev/null)
        if [ -n "$dono" ] && ! kill -0 "$dono" 2>/dev/null; then rm -rf "$v"; fi
        # Trava sem pid há mais de 60 s: o processo morreu entre o mkdir e gravar o pid.
        if [ -z "$dono" ] && [ -d "$v" ] && [ $(( $(date +%s) - $(stat -c %Y "$v" 2>/dev/null || date +%s) )) -gt 60 ]; then rm -rf "$v"; fi
    done
    [ -n "$L" ] && break
    if [ $SECONDS -ge $limite ]; then echo "FILA OCUPADA — rode de novo"; exit 75; fi
    sleep 5
done
echo $$ > "$L/pid"; echo "$eu desde $(date +%T): ${args[*]}" > "$L/dono"
trap 'rm -rf "$L"' EXIT INT TERM
php artisan test "${args[@]}"
rc=$?
# Depois do --parallel, apaga os <banco>_test_N deste worktree: menos tabelas no servidor, information_schema mais leve. O próximo --parallel recria.
if [ $paralelo = 1 ]; then
    base="$DB_DATABASE"
    [ -z "$base" ] && base=$(grep -E '^DB_DATABASE=' .env.testing 2>/dev/null | head -1 | cut -d= -f2 | tr -d '"\r')
    if [ -n "$base" ]; then
        for db in $(mariadb -uroot -h127.0.0.1 -P"$porta" -N -e "show databases" 2>/dev/null | grep -E "^${base}_test_[0-9]+$"); do
            mariadb -uroot -h127.0.0.1 -P"$porta" -e "drop database \`$db\`" 2>/dev/null
        done
    fi
fi
exit $rc

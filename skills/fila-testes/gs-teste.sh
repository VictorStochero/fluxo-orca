#!/bin/bash
# Semáforo de testes da máquina: até DOIS runs por fila (e no máximo TRÊS na máquina) entre todos os worktrees e sessões.
# Uso, no cwd do projeto/worktree:
#   bash ~/.cache/gs-teste.sh <argumentos do teste>     executor detectado pela stack
#   bash ~/.cache/gs-teste.sh -- <comando completo>     executor explícito
# Executor detectado (o primeiro que valer):
#   GS_TESTE_RUNNER (ambiente ou <principal>/.orca/worktree.conf), ex.: "docker compose exec -T web pytest"
#   Laravel (artisan): DDEV -> "ddev artisan test"; Sail -> "./vendor/bin/sail artisan test"; senão "php artisan test"
#   Python (pyproject/requirements/Pipfile/pytest.ini): uv | poetry | pipenv | .venv -> pytest
#   JS (package.json): pnpm | yarn | bun | npm -> script "test"
#   Rust (Cargo.toml): cargo test; Go (go.mod): go test (sem argumentos, rode ./...)
# Laravel: --parallel vira --processes=8 e, no fim, apaga os <banco>_test_N do MySQL/MariaDB do host.
# Fila: Laravel no host = uma por porta de banco (3306 usa gs-teste.lockN, outras gs-teste-<porta>.lockN);
# container = gs-teste-ctr.lockN; Python/JS = gs-teste-geral.lockN. GS_TESTE_VAGAS e GS_TESTE_PROCESSOS sobrescrevem 2 e 8.
# Teto global: além da vaga da fila, no máximo GS_TESTE_TETO (3) runs ao mesmo tempo na máquina (gs-teste-teto.lockN).
# Espera vaga até 5 min; sem vaga, sai com 75 (rode de novo). Imposto pelo hook fila-testes.sh do plugin fluxo-orca.
eu="$(git rev-parse --show-toplevel 2>/dev/null || pwd) [$DB_DATABASE]"
env_testing() { # $1 chave: .env.testing, senão .env
    local v
    v=$(grep -hE "^$1=" .env.testing 2>/dev/null | head -1 | cut -d= -f2- | tr -d '"\r')
    [ -z "$v" ] && v=$(grep -hE "^$1=" .env 2>/dev/null | head -1 | cut -d= -f2- | tr -d '"\r')
    printf '%s' "$v"
}
comum=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)
# shellcheck source=/dev/null
[ -n "$comum" ] && [ -z "$GS_TESTE_RUNNER" ] && [ -f "$(dirname "$comum")/.orca/worktree.conf" ] && . "$(dirname "$comum")/.orca/worktree.conf"
VAGAS=${GS_TESTE_VAGAS:-2}
TETO=${GS_TESTE_TETO:-3}
PROCESSOS=${GS_TESTE_PROCESSOS:-8}

stack=outro
args=()
if [ "${1:-}" = "--" ]; then
    shift
    runner=""
    args=("$@")
else
    if [ -f artisan ]; then
        stack=laravel
        if [ -n "$GS_TESTE_RUNNER" ]; then runner=$GS_TESTE_RUNNER
        elif [ -f .ddev/config.yaml ]; then runner="ddev artisan test"
        elif [ -x vendor/bin/sail ] && grep -qs 'sail' docker-compose.yml compose.yaml; then runner="./vendor/bin/sail artisan test"
        else runner="php artisan test"
        fi
    elif [ -f pyproject.toml ] || [ -f pytest.ini ] || [ -f Pipfile ] || ls requirements*.txt >/dev/null 2>&1; then
        stack=python
        if [ -n "$GS_TESTE_RUNNER" ]; then runner=$GS_TESTE_RUNNER
        elif [ -f uv.lock ]; then runner="uv run pytest"
        elif [ -f poetry.lock ]; then runner="poetry run pytest"
        elif [ -f Pipfile.lock ]; then runner="pipenv run pytest"
        elif [ -x .venv/bin/pytest ]; then runner=".venv/bin/pytest"
        elif [ -x .venv/Scripts/pytest.exe ]; then runner=".venv/Scripts/pytest.exe"
        else runner="python -m pytest"
        fi
    elif [ -f package.json ]; then
        stack=js
        if [ -n "$GS_TESTE_RUNNER" ]; then runner=$GS_TESTE_RUNNER
        elif [ -f pnpm-lock.yaml ]; then runner="pnpm test"
        elif [ -f yarn.lock ]; then runner="yarn test"
        elif [ -f bun.lock ] || [ -f bun.lockb ]; then runner="bun run test"
        else runner="npm test --"
        fi
    elif [ -n "$GS_TESTE_RUNNER" ]; then
        runner=$GS_TESTE_RUNNER
    elif [ -f Cargo.toml ]; then
        stack=rust; runner="cargo test"
    elif [ -f go.mod ]; then
        stack=go; runner="go test"
    else
        echo "Stack não detectada: use bash ~/.cache/gs-teste.sh -- <comando de teste>" >&2
        exit 2
    fi
    paralelo=0
    for a in "$@"; do
        case "$a" in
            --processes=*) [ $stack = laravel ] && continue ;;
            --parallel) [ $stack = laravel ] && paralelo=1 ;;
        esac
        args+=("$a")
    done
    [ $paralelo = 1 ] && args+=("--processes=$PROCESSOS")
fi
paralelo=${paralelo:-0}

porta=$(env_testing DB_PORT)
porta=${porta:-3306}
mkdir -p "$HOME/.cache"
if [ $stack != laravel ]; then
    trava=$HOME/.cache/gs-teste-geral.lock
elif [ "${runner%% *}" != php ]; then
    trava=$HOME/.cache/gs-teste-ctr.lock
elif [ "$porta" = 3306 ]; then
    trava=$HOME/.cache/gs-teste.lock
else
    trava=$HOME/.cache/gs-teste-$porta.lock
fi
# Remove trava morta sem apagar a que outro processo acabou de recriar: renomeia (atômico), confere o pid e devolve se mudou.
# ponytail: entre o rename e a devolução, um terceiro pode criar a trava; janela de milissegundos, aceitável para uma fila de testes.
remove_morta() { # trava pid_esperado
    local tmp="$1.morta.$$"
    mv "$1" "$tmp" 2>/dev/null || return 0
    if [ "$(cat "$tmp/pid" 2>/dev/null)" = "$2" ]; then rm -rf "$tmp"; else [ -e "$1" ] || mv "$tmp" "$1" 2>/dev/null; rm -rf "$tmp"; fi
}
limite=$((SECONDS + 300))
# Pega uma vaga em <base>1..<n> e põe o caminho em $L. checa_dono=1: espera se este mesmo dono já ocupa vaga da fila.
pega_vaga() { # base vagas checa_dono
    local base=$1 n=$2 checa=$3 i v d p dono idade mesmo
    L=""
    while [ -z "$L" ]; do
        mesmo=0
        if [ "$checa" = 1 ]; then
            for i in $(seq 1 "$n"); do
                d=$(cat "$base$i/dono" 2>/dev/null)
                p=$(cat "$base$i/pid" 2>/dev/null)
                [ -n "$d" ] && [ "${d%% desde *}" = "$eu" ] && [ -n "$p" ] && kill -0 "$p" 2>/dev/null && mesmo=1
            done
        fi
        for i in $(seq 1 "$n"); do
            [ $mesmo = 1 ] && break
            v=$base$i
            if mkdir "$v" 2>/dev/null; then L=$v; break; fi
            dono=$(cat "$v/pid" 2>/dev/null)
            if [ -n "$dono" ] && ! kill -0 "$dono" 2>/dev/null; then remove_morta "$v" "$dono"; fi
            # Trava sem pid há mais de 60 s: o processo morreu entre o mkdir e gravar o pid.
            if [ -z "$dono" ] && [ -d "$v" ]; then
                idade=$(stat -c %Y "$v" 2>/dev/null || stat -f %m "$v" 2>/dev/null || date +%s)
                [ $(( $(date +%s) - idade )) -gt 60 ] && remove_morta "$v" ""
            fi
        done
        [ -n "$L" ] && break
        if [ $SECONDS -ge $limite ]; then echo "FILA OCUPADA — rode de novo"; exit 75; fi
        sleep 5
    done
    echo $$ > "$L/pid"; echo "$eu desde $(date +%T): $runner ${args[*]}" > "$L/dono"
}
# Ordem fixa: vaga da fila, depois a do teto global (sem deadlock). Os dois saem no trap.
F=""; T=""
trap 'rm -rf "$F" "$T"' EXIT INT TERM
pega_vaga "$trava" "$VAGAS" 1; F=$L
pega_vaga "$HOME/.cache/gs-teste-teto.lock" "$TETO" 0; T=$L
# shellcheck disable=SC2086 # runner é uma linha de comando com argumentos
CI=${CI:-1} $runner "${args[@]}"
rc=$?
# Depois do --parallel, apaga os <banco>_test_N deste worktree: menos tabelas no servidor, information_schema mais leve. O próximo --parallel recria.
# Só com banco MySQL/MariaDB no host; em container o banco é descartável junto com o ambiente.
conexao=$(env_testing DB_CONNECTION)
if [ "$paralelo" = 1 ] && [ "${runner%% *}" = php ] && { [ "$conexao" = mysql ] || [ "$conexao" = mariadb ]; }; then
    base="$DB_DATABASE"
    [ -z "$base" ] && base=$(env_testing DB_DATABASE)
    for g in "$HOME"/.config/herd/bin/services/mariadb/*/bin "$HOME"/.config/herd/bin/services/mysql/*/bin /c/laragon/bin/mysql/*/bin; do
        [ -d "$g" ] && PATH="$PATH:$g"
    done
    cliente=$(command -v mariadb || command -v mysql)
    host=$(env_testing DB_HOST); usuario=$(env_testing DB_USERNAME); senha=$(env_testing DB_PASSWORD)
    if [ -n "$base" ] && [ -n "$cliente" ]; then
        sql() { MYSQL_PWD="$senha" "$cliente" -u"${usuario:-root}" -h"${host:-127.0.0.1}" -P"$porta" "$@" 2>/dev/null; }
        for db in $(sql -N -e "show databases" | tr -d '\r' | grep -E "^${base}_test_[0-9]+$"); do
            sql -e "drop database \`$db\`"
        done
    fi
fi
exit $rc

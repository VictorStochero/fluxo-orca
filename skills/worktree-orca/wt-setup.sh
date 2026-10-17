#!/usr/bin/env bash
# Setup genérico de worktree para o Orca (Orca > repo > setup script: bash ~/.cache/wt-setup.sh).
# Roda com o worktree novo como diretório corrente; o principal sai do git (dono do .git comum).
# Stacks: Laravel, Python, JS (detectadas); o resto vem do <principal>/.orca/worktree.conf (bash, tudo opcional):
#   WT_SITES=herd|laragon|lerd|flyenv|nativo|ddev   (auto se vazio; serve o site e define a URL)
#   WT_BASE=origin/<branch>   WT_COPIAR=".mcp.json .claude/settings.local.json"   WT_BUILD=0
#   WT_INSTALAR="<cmd>"  WT_MIGRAR="<cmd>"  WT_SEED="<cmd>"  WT_SEEDER=<Classe Laravel>  WT_SEM_SEED=1
#   WT_PORTA_BASE=8000   WT_POS_SETUP() { ...; }   GS_TESTE_RUNNER="<cmd de teste>" (lido pela fila)
# Banco: <pasta com _> e <banco>_test (no servidor do .env.testing, se for outro); toda chave do .env que apontava para o banco do principal passa ao do worktree.
# Multi-tenant Laravel (config/tenancy.php): TENANCY_DB_PREFIX=<banco>_tenant_ / <banco>_test_tenant_.

set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/wt-lib.sh"

raiz="$(pwd)"
comum="$(git rev-parse --path-format=absolute --git-common-dir)"
principal="$(dirname "$comum")"
[ "$(cd "$raiz" && pwd -P)" = "$(cd "$principal" && pwd -P)" ] && { echo "Isto é o checkout principal, não um worktree." >&2; exit 1; }

WT_COPIAR=".mcp.json .claude/settings.local.json"
WT_BUILD=1
WT_PORTA_BASE=8000
# shellcheck source=/dev/null
[ -f "$principal/.orca/worktree.conf" ] && . "$principal/.orca/worktree.conf"

if [ -f "$raiz/artisan" ]; then stack=laravel
elif [ -f "$raiz/pyproject.toml" ] || [ -f "$raiz/Pipfile" ] || ls "$raiz"/requirements*.txt >/dev/null 2>&1; then stack=python
elif [ -f "$raiz/package.json" ]; then stack=js
else stack=outro
fi
multitenant=0
[ $stack = laravel ] && [ -f "$raiz/config/tenancy.php" ] && multitenant=1
site="$(basename "$raiz" | tr '[:upper:]' '[:lower:]')"
banco="$(nome_banco "$site" $multitenant)"

if [ -z "${WT_SITES:-}" ]; then
    if [ -f "$raiz/.ddev/config.yaml" ]; then WT_SITES=ddev
    elif [ $stack = laravel ] && [ -x "$raiz/vendor/bin/sail" -o -f "$raiz/docker-compose.yml" -o -f "$raiz/compose.yaml" ] && grep -qs sail "$raiz/docker-compose.yml" "$raiz/compose.yaml"; then WT_SITES=sail
    elif [ $stack = laravel ] && { command -v herd >/dev/null 2>&1 || command -v herd.bat >/dev/null 2>&1; }; then WT_SITES=herd
    elif [ $stack = laravel ] && command -v lerd >/dev/null 2>&1; then WT_SITES=lerd
    elif case "$raiz" in */laragon/www/*|*/Laragon/www/*) true ;; *) false ;; esac; then WT_SITES=laragon
    else WT_SITES=nativo
    fi
fi
[ "$WT_SITES" = sail ] && { echo "Sail: portas e COMPOSE_PROJECT_NAME por worktree — use /worktree (plugin laravel-worktree)." >&2; exit 1; }

porta_http=$(( WT_PORTA_BASE + 1 + $(printf '%s' "$site" | cksum | cut -d' ' -f1) % 900 ))
case "$WT_SITES" in
    ddev) url="https://$site.ddev.site" ;;
    # *.localhost resolve para a máquina sem DNS: subdomínio de tenant funciona no navegador.
    nativo) url="http://$site.localhost:$porta_http" ;;
    *) url="https://$site.test" ;;
esac
host_novo="$(host_de_url "$url")"
echo "== $raiz | $stack | $WT_SITES | $url | bancos $banco / ${banco}_test =="

base="${WT_BASE:-}"
if [ -z "$base" ]; then
    for b in desenvolvimento dev develop homologacao main master; do
        git rev-parse --verify -q "origin/$b" >/dev/null && { base="origin/$b"; break; }
    done
fi
printf '%s' "${base#origin/}" > "$raiz/.worktree-base"
grep -qxF .worktree-base "$comum/info/exclude" 2>/dev/null || echo .worktree-base >> "$comum/info/exclude"

echo '== .env =='
envs=()
for nome in .env .env.local; do
    [ -f "$principal/$nome" ] && { cp "$principal/$nome" "$raiz/$nome"; envs+=("$nome"); }
done
testes=()
for nome in .env.testing .env.test; do
    if [ -f "$principal/$nome" ]; then cp "$principal/$nome" "$raiz/$nome"; testes+=("$nome")
    elif [ -f "$raiz/$nome.example-$WT_SITES" ]; then cp "$raiz/$nome.example-$WT_SITES" "$raiz/$nome"; testes+=("$nome")
    fi
done
[ ${#envs[@]} = 0 ] && echo "AVISO: o principal não tem .env; nada herdado." >&2

url_principal="$(env_de "$principal/.env" APP_URL)"
host_principal="$(host_de_url "${url_principal:-x://}")"
# localhost/IP também é o DB_HOST/REDIS_HOST: trocar em todo valor quebraria a conexão.
host_local "$host_principal" && host_principal=""
db_info "$principal/.env"
banco_principal="$DB_N"
[ -n "$DB_MOTOR" ] || banco_principal=""
# ${a[@]+...}: bash 3.2 (macOS) com set -u trata array vazio como variável não definida.
for nome in ${envs[@]+"${envs[@]}"} ${testes[@]+"${testes[@]}"}; do
    f="$raiz/$nome"
    troca_texto "$f" "$host_principal" "$host_novo"
    [ -n "$(env_de "$f" APP_URL)" ] && set_env "$f" APP_URL "$url"
    [ "$WT_SITES" = nativo ] && [ -n "$(env_de "$f" PORT)" ] && set_env "$f" PORT "$porta_http"
done
if [ "$WT_SITES" != ddev ]; then
    for nome in ${envs[@]+"${envs[@]}"}; do
        f="$raiz/$nome"
        db_info "$f"
        [ -n "$DB_MOTOR" ] || continue
        [ -n "$DB_URL_N" ] && troca_texto "$f" "/$DB_URL_N" "/$banco"
        troca_valor "$f" "$banco_principal" "$banco"
    done
    for nome in ${testes[@]+"${testes[@]}"}; do
        f="$raiz/$nome"
        db_info "$f"
        [ -n "$DB_MOTOR" ] || continue
        [ -n "$DB_URL_N" ] && troca_texto "$f" "/$DB_URL_N" "/${banco}_test"
        troca_valor "$f" "$DB_N" "${banco}_test"
        [ $stack = laravel ] && set_env "$f" APP_URL "${url/https:/http:}"
    done
    if [ $multitenant = 1 ]; then
        set_env "$raiz/.env" TENANCY_DB_PREFIX "${banco}_tenant_"
        [ -f "$raiz/.env.testing" ] && set_env "$raiz/.env.testing" TENANCY_DB_PREFIX "${banco}_test_tenant_"
    fi
fi
if [ $stack = laravel ] && [ -f "$raiz/.env" ]; then
    # Redis e cache compartilhados não misturam chaves entre worktrees.
    set_env "$raiz/.env" REDIS_PREFIX "${banco}_"
    set_env "$raiz/.env" CACHE_PREFIX "${banco}_cache_"
    if [ -f "$raiz/.env.testing" ]; then
        set_env "$raiz/.env.testing" REDIS_PREFIX "${banco}_test_"
        set_env "$raiz/.env.testing" CACHE_PREFIX "${banco}_test_cache_"
    fi
fi
for f in $WT_COPIAR; do
    [ -f "$principal/$f" ] && { mkdir -p "$(dirname "$raiz/$f")"; cp "$principal/$f" "$raiz/$f"; }
done

if [ "$WT_SITES" = ddev ]; then
    echo '== ddev =='
    ddev config --project-name="$site"
    ddev start
    run() { ddev exec "$@"; }
else
    run() { "$@"; }
    if [ -f "$raiz/.env" ]; then
        db_info "$raiz/.env"
        if [ -n "$DB_MOTOR" ]; then
            echo "== bancos ($DB_MOTOR em $DB_H:$DB_P) =="
            if conflito="$(colide_com_principal "$banco" "$principal")"; then
                echo "Banco do worktree ($banco) é ou abrange o banco $conflito do principal: renomeie a pasta." >&2; exit 1
            fi
            db_info "$raiz/.env"
            for reg in "$comum"/wt-bancos/*; do
                [ -f "$reg" ] && [ "$(basename "$reg")" != "$(basename "$raiz")" ] || continue
                if [ "$(head -1 "$reg" | tr -d '\r')" = "$banco" ] && git worktree list --porcelain | grep -q "/$(basename "$reg")\$"; then
                    echo "O worktree $(basename "$reg") já usa o banco $banco: renomeie a pasta." >&2; exit 1
                fi
            done
            # O archive apaga pelo registro, não recalcula: nome de exibição do Orca e truncamento não o enganam.
            # Linha 2 (só se o .env.testing aponta para outro servidor): onde apagar os bancos de teste.
            mkdir -p "$comum/wt-bancos"
            teste_info "$raiz/.env" "$raiz/${testes[0]:-.env.testing}"
            db_info "$raiz/.env"
            {
                printf '%s\n' "$banco"
                if [ -n "$T_MOTOR" ]; then printf 'teste=%s|%s|%s|%s\n' "$T_MOTOR" "$T_H" "$T_P" "$T_U"; fi
            } > "$(registro_bancos "$comum" "$(basename "$raiz")")"
            criar_banco "$banco"
            if [ ${#testes[@]} -gt 0 ]; then
                if [ -n "$T_MOTOR" ]; then
                    echo "banco de teste em $T_H:$T_P (servidor de teste)"
                    em_teste criar_banco "${banco}_test"
                else
                    criar_banco "${banco}_test"
                fi
            fi
        else
            echo "Banco não identificado no .env (MySQL/MariaDB/Postgres): criar à mão se o projeto usar." >&2
        fi
    fi
    echo "== site ($WT_SITES) =="
    case "$WT_SITES" in
        herd) { command -v herd >/dev/null 2>&1 && herd secure "$site"; } || herd.bat secure "$site" || true ;;
        lerd) lerd link || true ;;
        laragon) echo "Laragon: com 'Auto virtual hosts' ligado, $site.test sai no próximo reload (menu > Apache/Nginx > Reload)." ;;
        flyenv) echo "FlyEnv: criar o site $host_novo apontando para $raiz/public (ou a pasta pública do projeto) na interface." ;;
        nativo) echo "Servir na porta $porta_http (ex.: php artisan serve --port=$porta_http, npm run dev -- --port $porta_http, manage.py runserver $porta_http)." ;;
    esac
fi

echo '== dependências =='
if [ -n "${WT_INSTALAR:-}" ]; then
    run bash -c "$WT_INSTALAR"
else
    case $stack in
        laravel)
            if [ "$WT_SITES" = ddev ]; then ddev composer install --no-interaction --no-progress
            else composer install --no-interaction --no-progress \
                || composer install --no-interaction --no-progress --ignore-platform-req=ext-pcntl --ignore-platform-req=ext-posix
            fi ;;
        python)
            if [ -f uv.lock ]; then run uv sync
            elif [ -f poetry.lock ]; then run poetry install
            elif [ -f Pipfile.lock ]; then run pipenv sync --dev
            else
                run python -m venv .venv
                pip=".venv/bin/pip"; [ -x "$pip" ] || pip=".venv/Scripts/pip.exe"
                for r in requirements-dev.txt requirements.txt; do [ -f "$r" ] && { run "$pip" install -r "$r"; break; }; done
            fi ;;
    esac
fi
if [ -f "$raiz/package.json" ] && [ -z "${WT_INSTALAR:-}" ]; then
    if [ -f pnpm-lock.yaml ]; then pm=pnpm; run pnpm install --frozen-lockfile
    elif [ -f yarn.lock ]; then pm=yarn; run yarn install --frozen-lockfile
    elif [ -f bun.lock ] || [ -f bun.lockb ]; then pm=bun; run bun install --frozen-lockfile
    else pm=npm; run npm ci --no-fund --no-audit
    fi
    [ $stack = laravel ] && [ "$WT_BUILD" = 1 ] && grep -q '"build"' package.json && run $pm run build
fi

echo '== migração / seed =='
if [ $stack = laravel ]; then
    artisan() { if [ "$WT_SITES" = ddev ]; then ddev artisan "$@"; else php artisan "$@"; fi; }
    if [ -n "${WT_MIGRAR:-}" ]; then run bash -c "$WT_MIGRAR"
    elif [ -n "${WT_SEEDER:-}" ]; then artisan migrate --force; artisan db:seed --class="$WT_SEEDER" --force
    elif [ "${WT_SEM_SEED:-0}" = 1 ]; then artisan migrate --force
    else artisan migrate --seed --force
    fi
    [ -f .env.testing ] && artisan migrate --env=testing --force
    artisan storage:link >/dev/null 2>&1 || true
    if grep -qs '"laravel/boost"' composer.json; then
        echo '== boost =='
        # Sem TTY o multiselect de agente derruba o install; enforce_tests pula o --list-tests interno (timeout de 60 s).
        [ -f boost.json ] || printf '{"agents":["claude_code"]}' > boost.json
        criou_conf=0
        [ -f config/boost.php ] || { printf "<?php\n\nreturn ['enforce_tests' => true];\n" > config/boost.php; criou_conf=1; }
        sujos_antes="$(git diff --name-only)"
        artisan boost:install --guidelines --skills --no-interaction || echo "AVISO: boost:install falhou." >&2
        [ $criou_conf = 1 ] && rm -f config/boost.php
        # Arquivo versionado que o Boost regravou (AGENTS.md/CLAUDE.md customizados, boost.json com outro fim de linha)
        # volta ao do projeto: o worktree não pode divergir do que o repo versiona.
        for f in $(git diff --name-only); do
            printf '%s\n' "$sujos_antes" | grep -qxF "$f" || git checkout -q -- "$f"
        done
    fi
else
    [ -n "${WT_MIGRAR:-}" ] && run bash -c "$WT_MIGRAR"
    [ -n "${WT_SEED:-}" ] && run bash -c "$WT_SEED"
    if [ -z "${WT_MIGRAR:-}" ] && [ -f manage.py ]; then
        py="python"; [ -f uv.lock ] && py="uv run python"; [ -f poetry.lock ] && py="poetry run python"
        [ -x .venv/bin/python ] && py=".venv/bin/python"; [ -x .venv/Scripts/python.exe ] && py=".venv/Scripts/python.exe"
        run $py manage.py migrate --noinput
    fi
fi

if declare -F WT_POS_SETUP >/dev/null; then echo '== pós-setup do projeto =='; WT_POS_SETUP; fi

echo '== suíte (só descoberta) =='
case $stack in
    laravel) listar="php artisan test --list-tests"; [ "$WT_SITES" = ddev ] && listar="ddev artisan test --list-tests" ;;
    python) listar="pytest --collect-only -q"; [ -f uv.lock ] && listar="uv run $listar"; [ -f poetry.lock ] && listar="poetry run $listar" ;;
    *) listar="" ;;
esac
if [ -n "$listar" ]; then
    if saida="$($listar 2>&1)"; then echo "descoberta OK: $(printf '%s\n' "$saida" | tail -1)"
    else echo "AVISO: '$listar' falhou — a suíte não carrega:" >&2; printf '%s\n' "$saida" | tail -3 >&2
    fi
fi

if [ "$WT_SITES" != nativo ]; then
    if curl -fsSk -o /dev/null -m 30 "$url"; then echo "$url -> OK"; else echo "$url ainda não respondeu (ver o passo do site acima)." >&2; fi
fi
[ -n "$(git -C "$raiz" status --porcelain)" ] && { echo "AVISO: o setup sujou o git:" >&2; git -C "$raiz" status --short >&2; }
echo "== pronto: $url =="

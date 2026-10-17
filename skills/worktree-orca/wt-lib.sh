#!/usr/bin/env bash
# Funções comuns de wt-setup.sh e wt-archive.sh (sourced). Sem efeito colateral ao carregar, além do PATH.

# Clientes de banco das ferramentas locais que não ficam no PATH (Herd, Laragon).
for d in "$HOME/.config/herd/bin" "$HOME/bin"; do [ -d "$d" ] && PATH="$d:$PATH"; done
for g in "$HOME"/.config/herd/bin/services/mariadb/*/bin "$HOME"/.config/herd/bin/services/mysql/*/bin \
         /c/laragon/bin/mysql/*/bin /c/laragon/bin/postgresql/*/bin; do
    [ -d "$g" ] && PATH="$PATH:$g"
done
export PATH

env_de() { # arquivo chave — vazio se não houver (sempre status 0: chave ausente é normal sob set -e/pipefail)
    { grep -hE "^$2=" "$1" 2>/dev/null || true; } | head -1 | cut -d= -f2- | sed -E 's/^"(.*)"$/\1/; s/^'"'"'(.*)'"'"'$/\1/' | tr -d '\r'
}
set_env() { # arquivo chave valor — troca a linha ou acrescenta
    local tmp; tmp="$(mktemp)"
    awk -v k="$2" -v v="$3" 'BEGIN{f=0} index($0, k"=")==1 {print k"="v; f=1; next} {print} END{if(!f) print k"="v}' "$1" > "$tmp" && mv "$tmp" "$1"
}
troca_valor() { # arquivo de para — chaves de NOME de banco (DATABASE, DB_NAME, *_DB, BASENAME) cujo valor é exatamente "de"
    [ -n "$2" ] || return 0
    local tmp; tmp="$(mktemp)"
    awk -v de="$2" -v para="$3" '{n=index($0,"="); if(n>1 && substr($0,1,1)!="#"){k=toupper(substr($0,1,n-1)); v=substr($0,n+1); gsub(/^["'"'"']|["'"'"']$/,"",v);
        if(v==de && k ~ /(DATABASE|DB_NAME|_DB$|BASENAME)/ && k !~ /(USER|PASS|HOST|PORT|URL|SOCKET|CONNECTION|DRIVER|ENGINE)/){print substr($0,1,n) para; next}} print}' "$1" > "$tmp" && mv "$tmp" "$1"
}
host_local() { case "$1" in ""|localhost|127.*|0.0.0.0|::1|\[::1\]|[0-9]*.[0-9]*.[0-9]*.[0-9]*) return 0 ;; esac; return 1; }
troca_texto() { # arquivo de para — em todo valor (host em CENTRAL_DOMAIN, SESSION_DOMAIN, DATABASE_URL…)
    [ -n "$2" ] && [ "$2" != "$3" ] || return 0
    local tmp; tmp="$(mktemp)"
    awk -v de="$2" -v para="$3" '{n=index($0,"="); if(n>1 && substr($0,1,1)!="#"){k=substr($0,1,n); v=substr($0,n+1); r=""; while((i=index(v,de))>0){r=r substr(v,1,i-1) para; v=substr(v,i+length(de))}; print k r v} else print}' "$1" > "$tmp" && mv "$tmp" "$1"
}
host_de_url() { local h="${1#*://}"; h="${h#*@}"; printf '%s' "${h%%[:/]*}"; }

# Lê o banco de um arquivo .env: define DB_MOTOR (mysql|pgsql|""), DB_H, DB_P, DB_U, DB_W, DB_N e DB_URL_N (nome dentro da DATABASE_URL).
db_info() {
    local f="$1" url esquema resto cred
    DB_MOTOR=""; DB_H=""; DB_P=""; DB_U=""; DB_W=""; DB_N=""; DB_URL_N=""
    url="$(env_de "$f" DATABASE_URL)"
    if [ -n "$url" ]; then
        esquema="${url%%://*}"; resto="${url#*://}"
        case "$esquema" in mysql*|mariadb*) DB_MOTOR=mysql ;; postgres*|pgsql*) DB_MOTOR=pgsql ;; esac
        if [ "${resto#*@}" != "$resto" ]; then cred="${resto%%@*}"; resto="${resto#*@}"; DB_U="${cred%%:*}"; [ "${cred#*:}" != "$cred" ] && DB_W="${cred#*:}"; fi
        DB_H="${resto%%[:/]*}"
        [ "${resto#*:}" != "$resto" ] && { DB_P="${resto#*:}"; DB_P="${DB_P%%/*}"; }
        DB_URL_N="${resto#*/}"; DB_URL_N="${DB_URL_N%%\?*}"; DB_N="$DB_URL_N"
    fi
    case "$(env_de "$f" DB_CONNECTION)$(env_de "$f" DB_ENGINE)" in
        *mysql*|*mariadb*) DB_MOTOR=mysql ;; *pgsql*|*postgres*) DB_MOTOR=pgsql ;;
    esac
    [ -z "$DB_MOTOR" ] && [ -n "$(env_de "$f" POSTGRES_DB)" ] && DB_MOTOR=pgsql
    [ -z "$DB_MOTOR" ] && [ -n "$(env_de "$f" MYSQL_DATABASE)" ] && DB_MOTOR=mysql
    local n; for n in DB_DATABASE DB_NAME POSTGRES_DB MYSQL_DATABASE; do [ -z "$DB_N" ] && DB_N="$(env_de "$f" $n)"; done
    : "${DB_H:=$(env_de "$f" DB_HOST)}"; : "${DB_H:=$(env_de "$f" POSTGRES_HOST)}"; : "${DB_H:=127.0.0.1}"
    : "${DB_P:=$(env_de "$f" DB_PORT)}"; : "${DB_P:=$(env_de "$f" POSTGRES_PORT)}"
    : "${DB_U:=$(env_de "$f" DB_USERNAME)}"; : "${DB_U:=$(env_de "$f" DB_USER)}"; : "${DB_U:=$(env_de "$f" POSTGRES_USER)}"
    : "${DB_W:=$(env_de "$f" DB_PASSWORD)}"; : "${DB_W:=$(env_de "$f" POSTGRES_PASSWORD)}"
    if [ "$DB_MOTOR" = pgsql ]; then : "${DB_P:=5432}"; : "${DB_U:=postgres}"; else : "${DB_P:=3306}"; : "${DB_U:=root}"; fi
}

# sql "<consulta>" — uma coluna por linha. Cliente nativo; senão PDO do PHP.
sql() {
    local cli
    if [ "$DB_MOTOR" = mysql ]; then
        cli="$(command -v mariadb || command -v mysql || true)"
        # O cliente 11.x avisa de SSL a cada login sem senha; só essa linha sai do stderr.
        if [ -n "$cli" ]; then MYSQL_PWD="$DB_W" "$cli" -u"$DB_U" -h"$DB_H" -P"$DB_P" -N -e "$1" 2> >(grep -v 'ssl-verify-server-cert' >&2) | tr -d '\r'; return; fi
    elif [ "$DB_MOTOR" = pgsql ]; then
        if command -v psql >/dev/null 2>&1; then PGPASSWORD="$DB_W" psql -h "$DB_H" -p "$DB_P" -U "$DB_U" -d postgres -tAc "$1" | tr -d '\r'; return; fi
    else
        return 1
    fi
    command -v php >/dev/null 2>&1 || { echo "Sem cliente para $DB_MOTOR (mysql/mariadb, psql ou php)." >&2; return 1; }
    DBM="$DB_MOTOR" DBH="$DB_H" DBP="$DB_P" DBU="$DB_U" DBW="$DB_W" php -r '
        $d = getenv("DBM") === "pgsql" ? "pgsql:host=".getenv("DBH").";port=".getenv("DBP").";dbname=postgres" : "mysql:host=".getenv("DBH").";port=".getenv("DBP");
        $p = new PDO($d, getenv("DBU"), getenv("DBW"));
        $r = $p->query($argv[1]); if ($r && $r->columnCount()) { foreach ($r->fetchAll(PDO::FETCH_COLUMN) as $v) echo $v, "\n"; }' "$1"
}
# teste_info <.env> <.env.testing> — T_MOTOR/T_H/T_P/T_U/T_W com a conexão do arquivo de teste quando difere da do .env
# (motor, host, porta ou usuário); T_MOTOR vazio se igual, sem arquivo ou sem banco identificado. Deixa DB_* com o arquivo de teste.
teste_info() {
    local dev
    T_MOTOR=""; T_H=""; T_P=""; T_U=""; T_W=""
    [ -f "$2" ] || return 0
    db_info "$1"; dev="$DB_MOTOR|$DB_H|$DB_P|$DB_U"
    db_info "$2"
    [ -n "$DB_MOTOR" ] || return 0
    [ "$DB_MOTOR|$DB_H|$DB_P|$DB_U" = "$dev" ] && return 0
    T_MOTOR="$DB_MOTOR"; T_H="$DB_H"; T_P="$DB_P"; T_U="$DB_U"; T_W="$DB_W"
    return 0
}
# em_teste <função> [args] — roda a função de banco na conexão T_* (servidor de teste), sem alterar a conexão corrente.
em_teste() { ( DB_MOTOR="$T_MOTOR"; DB_H="$T_H"; DB_P="$T_P"; DB_U="$T_U"; DB_W="$T_W"; "$@" ); }
listar_bancos() { if [ "$DB_MOTOR" = pgsql ]; then sql "SELECT datname FROM pg_database WHERE NOT datistemplate"; else sql "SHOW DATABASES"; fi; }
criar_banco() {
    if [ "$DB_MOTOR" = pgsql ]; then
        listar_bancos | grep -qxF "$1" || sql "CREATE DATABASE \"$1\""
    else
        sql "CREATE DATABASE IF NOT EXISTS \`$1\`"
    fi
}
dropar_banco() { if [ "$DB_MOTOR" = pgsql ]; then sql "DROP DATABASE IF EXISTS \"$1\""; else sql "DROP DATABASE IF EXISTS \`$1\`"; fi; }

# Bancos do checkout principal (dev e teste), um por linha: nenhum worktree pode usá-los nem abrangê-los por prefixo.
bancos_do_principal() {
    local f
    for f in "$1/.env" "$1/.env.local" "$1/.env.testing" "$1/.env.test"; do
        [ -f "$f" ] || continue
        db_info "$f"
        [ -n "$DB_MOTOR" ] && [ -n "$DB_N" ] && printf '%s\n' "$DB_N"
    done
    return 0
}
# colide_com_principal <banco> <principal> — imprime o banco do principal que <banco> é ou abrange (<banco>_*).
colide_com_principal() {
    local b
    while read -r b; do
        case "$b" in "$1"|"${1}_"*) printf '%s' "$b"; return 0 ;; esac
    done <<< "$(bancos_do_principal "$2")"
    return 1
}
# Registro dos bancos criados por worktree, no .git comum (sobrevive à remoção da pasta): <comum>/wt-bancos/<pasta>.
registro_bancos() { printf '%s/wt-bancos/%s' "$1" "$2"; }
# Caminho comparável: absoluto, sem barra final. No Windows, na forma C:/… em minúsculas — a forma Unix do Git Bash
# não é única (/tmp/x e /c/Users/…/Temp/x são a mesma pasta) e o sistema de arquivos não diferencia maiúsculas.
caminho_canonico() {
    local p="$1"
    if command -v cygpath >/dev/null 2>&1; then
        p="$(cygpath -u "$p")"
        [ -d "$p" ] && p="$(cd "$p" && pwd -P)"
        p="$(cygpath -m "$p" | tr '[:upper:]' '[:lower:]')"
    elif [ -d "$p" ]; then
        p="$(cd "$p" && pwd -P)"
    fi
    printf '%s' "${p%/}"
}
# Nome do banco a partir da pasta do worktree (a, z, 0-9 e _); multi-tenant guarda folga para _test_tenant_<id>.
nome_banco() { local b; b="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/_/g')"; if [ "$2" = 1 ]; then printf '%s' "${b:0:40}"; else printf '%s' "${b:0:59}"; fi; }

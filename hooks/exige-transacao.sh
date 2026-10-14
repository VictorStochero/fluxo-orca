#!/bin/bash
# PreToolUse (Bash|PowerShell): SQL de alteração via ssh/forge só em transação, e COMMIT só depois do ensaio com ROLLBACK do mesmo SQL.
in=$(cat)
cmd=$(printf '%s' "$in" | grep -oE '"(command|cmd)"[[:space:]]*:[[:space:]]*("([^"\\]|\\.)*"|\[[^]]*\])' | head -1)
printf '%s' "$cmd" | grep -qE '(^|["'"'"';&|(]|\\n)[[:space:]]*(ssh|forge)([[:space:]]|\.exe|")' || exit 0
up=$(printf '%s' "$cmd" | tr '[:lower:]' '[:upper:]')
s='(^|[^[:alnum:]_])'
printf '%s' "$up" | grep -qE "${s}(MYSQL|MARIADB|PSQL|SQLITE3)([^[:alnum:]_]|$)" || exit 0
bloqueia() { echo "SQL remoto bloqueado: $1" >&2; exit 2; }

printf '%s' "$up" | grep -qE "${s}(ALTER|DROP|TRUNCATE|RENAME|CREATE)[[:space:]]+[A-Z]" \
    && bloqueia "DDL avulso não roda em servidor (no MySQL faz commit implícito, a transação não protege). Schema muda por migration, pelo fluxo normal."
printf '%s' "$up" | grep -qE "<[[:space:]]*[^[:space:]<'\"]+\.SQL|(SOURCE|\\\\\.)[[:space:]]+[^[:space:]]+\.SQL|CAT[[:space:]][^|;&]*\.SQL[^|;&]*\||PSQL[^;&|]*[[:space:]](-F|--FILE)([[:space:]=]|$)" \
    && bloqueia "SQL vindo de arquivo não é verificável. Escreva o SQL no próprio comando, em transação."
printf '%s' "$up" | grep -qE "${s}(UPDATE|DELETE|INSERT|REPLACE|MERGE)[[:space:]]" || exit 0

ensaio="START TRANSACTION; <alteração>; <SELECT de conferência, ex.: ROW_COUNT() ou RETURNING>; ROLLBACK; — confira o resultado e rode o mesmo comando trocando ROLLBACK por COMMIT"
printf '%s' "$up" | grep -qE "${s}(START[[:space:]]+TRANSACTION|BEGIN)([^[:alnum:]_]|$)" \
    || bloqueia "alteração fora de transação. Ensaie primeiro: $ensaio."
dir="$HOME/.cache/sql-ensaio"
chave=$(printf '%s' "$up" | sed 's/COMMIT/ROLLBACK/g' | tr -s '[:space:]' ' ' | cksum | cut -d' ' -f1)
if printf '%s' "$up" | grep -qE "${s}COMMIT([^[:alnum:]_]|$)"; then
    # ponytail: o hook roda antes da aprovação, então um ensaio negado também conta; o ask do ssh segura o COMMIT.
    [ -n "$(find "$dir" -name "$chave" -mmin -30 2>/dev/null)" ] \
        || bloqueia "COMMIT sem ensaio do mesmo SQL nos últimos 30 min. Rode antes: $ensaio."
    rm -f "$dir/$chave"
    exit 0
fi
printf '%s' "$up" | grep -qE "${s}ROLLBACK([^[:alnum:]_]|$)" \
    || bloqueia "transação sem fechamento. Use: $ensaio."
mkdir -p "$dir" && touch "$dir/$chave"
exit 0

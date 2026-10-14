#!/bin/bash
# Prova do exige-transacao.sh: SQL de alteração via ssh/forge só em transação, COMMIT só após ensaio com ROLLBACK.
# Uso: bash tests/sql.sh   (HOME temporário: não toca nos ensaios reais em ~/.cache)
raiz=$(cd "$(dirname "$0")/.." && pwd)
export HOME=$(mktemp -d)
trap 'rm -rf "$HOME"' EXIT
falhas=0
ok() { echo "ok   $1"; }
ruim() { echo "FALHA $1"; falhas=$((falhas + 1)); }

json() { # comando -> JSON de PreToolUse com o comando escapado
    local c=${1//\\/\\\\}; c=${c//\"/\\\"}
    printf '{"tool_name":"Bash","tool_input":{"command":"%s","description":"x"}}' "$c"
}
confere() { # esperado(BLOQ|LIVRE) comando
    local r=LIVRE
    json "$2" | bash "$raiz/hooks/exige-transacao.sh" 2>/dev/null; [ $? = 2 ] && r=BLOQ
    if [ "$r" = "$1" ]; then ok "$1: $2"; else ruim "esperado $1, veio $r: $2"; fi
}

# Fora de ssh/forge, ou sem cliente SQL, nada muda.
confere LIVRE 'mysql -e "update users set ativo=0"'
confere LIVRE 'ssh prod "tail -n 50 storage/logs/laravel.log"'
confere LIVRE 'ssh prod "truncate -s 0 storage/logs/laravel.log"'
confere LIVRE 'ssh prod "mysql app -e \"select count(*) from users where id < 10\""'
confere LIVRE 'ssh prod "mysqldump app > /tmp/app.sql"'

# DML sem transação ou sem fechamento.
confere BLOQ 'ssh prod "mysql app -e \"update users set ativo=0 where id=5\""'
confere BLOQ "ssh prod 'psql app -c \"DELETE FROM sessoes WHERE id = 1\"'"
confere BLOQ 'ssh prod "mysql app -e \"start transaction; insert into x values (1);\""'

# DDL avulso e SQL vindo de arquivo.
confere BLOQ 'ssh prod "mysql app -e \"alter table users add coluna int\""'
confere BLOQ 'ssh prod "mysql app -e \"start transaction; drop table x; rollback;\""'
confere BLOQ 'ssh prod "mysql app < /tmp/corrige.sql"'
confere BLOQ 'cat corrige.sql | ssh prod mysql app'
confere BLOQ 'ssh prod "psql app -f /tmp/corrige.sql"'

# COMMIT sem ensaio; ensaio com ROLLBACK; COMMIT do mesmo SQL depois; o ensaio vale uma vez.
sql='update users set ativo=0 where id=5; select row_count();'
confere BLOQ "ssh prod \"mysql app -e \\\"start transaction; $sql commit;\\\"\""
confere LIVRE "ssh prod \"mysql app -e \\\"start transaction; $sql rollback;\\\"\""
confere BLOQ "ssh prod \"mysql app -e \\\"start transaction; update users set ativo=0 where id=6; commit;\\\"\""
confere LIVRE "ssh prod \"mysql app -e \\\"START TRANSACTION; $sql COMMIT;\\\"\""
confere BLOQ "ssh prod \"mysql app -e \\\"start transaction; $sql commit;\\\"\""

# Ensaio vencido (mais de 30 min) não libera COMMIT.
confere LIVRE "ssh prod \"psql app -c \\\"begin; delete from x where id=1; rollback;\\\"\""
touch -d '-31 minutes' "$HOME"/.cache/sql-ensaio/*
confere BLOQ "ssh prod \"psql app -c \\\"begin; delete from x where id=1; commit;\\\"\""

[ "$falhas" = 0 ] && echo "tudo ok" || { echo "$falhas falha(s)"; exit 1; }

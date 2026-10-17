#!/bin/bash
# Prova do banco de teste em servidor separado no wt-setup.sh / wt-archive.sh, com cliente mariadb falso (sem banco real).
# Uso: bash tests/banco-teste.sh   (HOME temporário: não toca em ~/.cache)
raiz=$(cd "$(dirname "$0")/.." && pwd)
export HOME=$(mktemp -d)
trap 'rm -rf "$HOME"' EXIT
falhas=0
ok() { echo "ok   $1"; }
ruim() { echo "FALHA $1"; falhas=$((falhas + 1)); }
tem() { grep -qxF -- "$2" "$1" 2>/dev/null; }
confere() { # descrição arquivo linha-esperada
    if tem "$2" "$3"; then ok "$1"; else ruim "$1 (faltou '$3' em $2)"; fi
}
ausente() { # descrição arquivo linha-proibida
    if tem "$2" "$3"; then ruim "$1 (achou '$3' em $2)"; else ok "$1"; fi
}

# mariadb falso: registra "porta|consulta"; SHOW DATABASES lê $FAKE/db_<porta>; DROP tira a linha.
FAKE="$HOME/fake"; mkdir -p "$FAKE/bin"
cat > "$FAKE/bin/mariadb" <<'EOF'
#!/bin/bash
while [ $# -gt 0 ]; do case "$1" in -P*) porta=${1#-P}; shift ;; -e) q=$2; shift 2 ;; *) shift ;; esac; done
echo "$porta|$q" >> "$FAKE/log"
[ -f "$FAKE/fora_$porta" ] && exit 1
case "$q" in
    "SHOW DATABASES") cat "$FAKE/db_$porta" 2>/dev/null ;;
    "DROP DATABASE IF EXISTS "*) n=${q#*\`}; n=${n%\`}; grep -vxF "$n" "$FAKE/db_$porta" > "$FAKE/t" 2>/dev/null; mv "$FAKE/t" "$FAKE/db_$porta" ;;
esac
exit 0
EOF
chmod +x "$FAKE/bin/mariadb"
export FAKE PATH="$FAKE/bin:$PATH"

# Principal: dev na 3306, teste na 3307.
P="$HOME/proj"; mkdir -p "$P"
git -C "$P" init -q -b main && git -C "$P" config user.email t@t && git -C "$P" config user.name t
printf 'DB_CONNECTION=mysql\nDB_HOST=127.0.0.1\nDB_PORT=3306\nDB_DATABASE=proj\nDB_USERNAME=root\n' > "$P/.env"
printf 'DB_CONNECTION=mysql\nDB_HOST=127.0.0.1\nDB_PORT=3307\nDB_DATABASE=proj_test\nDB_USERNAME=root\n' > "$P/.env.testing"
echo x > "$P/a"; git -C "$P" add a && git -C "$P" commit -qm i
git -C "$P" worktree add -q "$HOME/wt-a" -b wt-a
git -C "$P" worktree add -q "$HOME/wt-a-b" -b wt-a-b
comum="$(git -C "$P" rev-parse --path-format=absolute --git-common-dir)"

# 1. Setup com servidores diferentes: <banco> no dev, <banco>_test só no de teste, registro com a conexão de teste.
: > "$FAKE/log"
(cd "$HOME/wt-a" && bash "$raiz/skills/worktree-orca/wt-setup.sh" >/dev/null 2>&1)
confere "setup: banco de dev no servidor de dev" "$FAKE/log" '3306|CREATE DATABASE IF NOT EXISTS `wt_a`'
confere "setup: banco de teste no servidor de teste" "$FAKE/log" '3307|CREATE DATABASE IF NOT EXISTS `wt_a_test`'
ausente "setup: nada de teste no servidor de dev" "$FAKE/log" '3306|CREATE DATABASE IF NOT EXISTS `wt_a_test`'
confere "setup: registro guarda o banco" "$comum/wt-bancos/wt-a" 'wt_a'
confere "setup: registro guarda a conexão de teste" "$comum/wt-bancos/wt-a" 'teste=mysql|127.0.0.1|3307|root'

# 2. Setup com a mesma conexão (ou sem .env.testing): tudo no servidor de dev, registro só com o banco.
sed -i 's/3307/3306/' "$P/.env.testing"
(cd "$HOME/wt-a-b" && bash "$raiz/skills/worktree-orca/wt-setup.sh" >/dev/null 2>&1)
confere "setup igual: teste no mesmo servidor" "$FAKE/log" '3306|CREATE DATABASE IF NOT EXISTS `wt_a_b_test`'
if [ "$(wc -l < "$comum/wt-bancos/wt-a-b" | tr -d ' ')" = 1 ]; then ok "setup igual: registro sem linha de teste"; else ruim "setup igual: registro com linha extra"; fi
sed -i 's/3306/3307/' "$P/.env.testing"

# 3. Archive de wt-a: apaga dev e teste, cada um no seu servidor, sem tocar nos bancos de wt-a-b nem do principal.
printf '%s\n' proj wt_a wt_a_b wt_a_b_test > "$FAKE/db_3306"
printf '%s\n' proj_test wt_a_test wt_a_test_test_1 wt_a_test_tenant_9 wt_a_b_test > "$FAKE/db_3307"
rm -rf "$HOME/wt-a"; git -C "$P" worktree prune
: > "$FAKE/log"
ORCA_WORKTREE_PATH="$HOME/wt-a" bash "$raiz/skills/worktree-orca/wt-archive.sh" "$P" >/dev/null 2>&1
st=$?
[ $st = 0 ] && ok "archive: sai 0" || ruim "archive: saiu $st"
confere "archive: dev mantém o do principal" "$FAKE/db_3306" proj
confere "archive: dev mantém o de outro worktree" "$FAKE/db_3306" wt_a_b
ausente "archive: dev sem wt_a" "$FAKE/db_3306" wt_a
ausente "archive: teste sem wt_a_test" "$FAKE/db_3307" wt_a_test
ausente "archive: teste sem _test_test_N" "$FAKE/db_3307" wt_a_test_test_1
ausente "archive: teste sem tenant de teste" "$FAKE/db_3307" wt_a_test_tenant_9
confere "archive: teste mantém o do principal" "$FAKE/db_3307" proj_test
confere "archive: teste mantém o de outro worktree" "$FAKE/db_3307" wt_a_b_test
[ -f "$comum/wt-bancos/wt-a" ] && ruim "archive: registro ficou" || ok "archive: registro removido"

# 4. Servidor de teste fora do ar: falha, registro fica para repetir.
printf 'wt_a\n' > "$comum/wt-bancos/wt-a"; printf 'teste=mysql|127.0.0.1|3307|root\n' >> "$comum/wt-bancos/wt-a"
touch "$FAKE/fora_3307"
ORCA_WORKTREE_PATH="$HOME/wt-a" bash "$raiz/skills/worktree-orca/wt-archive.sh" "$P" >/dev/null 2>&1
st=$?
[ $st != 0 ] && ok "archive: servidor de teste fora do ar falha" || ruim "archive: sucesso com servidor de teste fora do ar"
[ -f "$comum/wt-bancos/wt-a" ] && ok "archive: registro mantido" || ruim "archive: registro removido sem apagar o teste"

echo; [ $falhas = 0 ] && echo "tudo certo" || { echo "$falhas falha(s)"; exit 1; }

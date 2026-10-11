#!/usr/bin/env bash
# Prova do pool com HOME isolado e respostas controladas do Orca.
raiz=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export HOME="$tmp/home" POOL_ESTADOS="$tmp/estados"
mkdir -p "$HOME/.claude" "$POOL_ESTADOS" "$tmp/bin"
falhas=0
ok() { echo "ok   $1"; }
ruim() { echo "FALHA $1"; falhas=$((falhas + 1)); }
cat > "$tmp/bin/orca" <<'EOF'
#!/usr/bin/env bash
[ "$1 $2 $3 $5" = 'orchestration worker-show --dispatch --json' ] || exit 2
estado=$(cat "$POOL_ESTADOS/$4" 2>/dev/null || echo pending)
case "$estado" in
    inexistente) echo '{"ok":false,"error":{"code":"dispatch_not_found"}}'; exit 1 ;;
    offline) echo '{"ok":false,"error":{"code":"runtime_unavailable"}}'; exit 1 ;;
    vazio) exit 1 ;;
    invalido) echo 'nao JSON'; exit 1 ;;
    desconhecido) echo '{"ok":true,"result":{}}' ;;
    outro_id) echo '{"ok":true,"result":{"dispatch":{"id":"outro","status":"completed"}}}' ;;
    *) printf '{"ok":true,"result":{"dispatch":{"id":"%s","status":"%s"}}}\n' "$4" "$estado" ;;
esac
EOF
chmod +x "$tmp/bin/orca"
export ORCA_CMD="$tmp/bin/orca"
pool() { bash "$raiz/skills/limites-cota/vaga-agente.sh" "$@"; }
confere_rc() {
    local esperado=$1 nome=$2 rc; shift 2
    "$@" > "$tmp/saida" 2>&1; rc=$?
    if [ "$rc" = "$esperado" ]; then ok "$nome"; else ruim "$nome: esperado=$esperado rc=$rc"; cat "$tmp/saida"; fi
}

# Simula a rejeição de arrays associativos do Bash 3.2, mantendo o script real.
pool_sem_associativo() {
    bash -c '
        declare() {
            case "$1" in -A*) unset vagas; return 2 ;; esac
            builtin declare "$@"
        }
        source "$1" "${@:2}"
    ' bash "$raiz/skills/limites-cota/vaga-agente.sh" "$@"
}
printf 'team=2\npessoal=0\ncodex=3\nkimi=4\nagy=5\n' > "$HOME/.claude/agentes.conf"
confere_rc 0 'pool funciona sem arrays associativos' pool_sem_associativo livres
for esperado in 'team 2/2' 'pessoal 0/0' 'codex 3/3' 'kimi 4/4' 'agy 5/5'; do
    grep -qx "$esperado" "$tmp/saida" && ok "limite independente: $esperado" || ruim "limite sem array associativo: $esperado"
done
rm "$HOME/.claude/agentes.conf"

confere_rc 0 'pega primeira vaga' pool pega team ctx_1
[ "$(cat "$HOME/.cache/agentes/team.lock1/dispatch" 2>/dev/null)" = ctx_1 ] \
    && [ -s "$HOME/.cache/agentes/team.lock1/desde" ] && ok 'dono e início gravados' || ruim 'metadados da vaga'
confere_rc 75 'pool cheio' pool pega team ctx_2
confere_rc 0 'pega do mesmo dispatch é idempotente' pool pega team ctx_1
confere_rc 0 'solta dispatch' pool solta ctx_1
confere_rc 0 'vaga liberada pode ser reutilizada' pool pega team ctx_2
for estado in pending running offline vazio invalido desconhecido outro_id; do
    echo "$estado" > "$POOL_ESTADOS/ctx_2"
    confere_rc 75 "preserva vaga: $estado" pool pega team ctx_3
    [ "$(cat "$HOME/.cache/agentes/team.lock1/dispatch" 2>/dev/null)" = ctx_2 ] || ruim "dono perdido: $estado"
done
for estado in completed failed stopped abandoned inexistente; do
    echo "$estado" > "$POOL_ESTADOS/ctx_2"
    confere_rc 0 "recupera dispatch: $estado" pool pega team ctx_3
    [ "$(cat "$HOME/.cache/agentes/team.lock1/dispatch" 2>/dev/null)" = ctx_3 ] || ruim "novo dono ausente: $estado"
    pool solta ctx_3; echo pending > "$POOL_ESTADOS/ctx_2"; pool pega team ctx_2
done
pool solta ctx_2
mkdir -p "$HOME/.cache/agentes/team.lock1"
confere_rc 75 'trava sem dispatch é preservada' pool pega team ctx_sem_dono
confere_rc 0 'livres consulta trava sem dono' pool livres
grep -Fq "$HOME/.cache/agentes/team.lock1" "$tmp/saida" && ok 'livres mostra caminho da trava sem dono' || ruim 'livres omite caminho da trava sem dono'
grep -qx 'team 0/1' "$tmp/saida" && ok 'trava sem dono ocupa vaga' || ruim 'trava sem dono deixou de ocupar vaga'
[ -d "$HOME/.cache/agentes/team.lock1" ] && [ ! -e "$HOME/.cache/agentes/team.lock1/dispatch" ] \
    && ok 'livres preserva trava sem dono' || ruim 'livres alterou trava sem dono'
rmdir "$HOME/.cache/agentes/team.lock1"
confere_rc 0 'pessoal ilimitado: primeira reserva' pool pega pessoal ctx_p1
confere_rc 0 'pessoal ilimitado: segunda reserva' pool pega pessoal ctx_p2
compgen -G "$HOME/.cache/agentes/pessoal.lock*" >/dev/null && ruim 'pessoal criou trava' || ok 'pessoal não cria trava'
for conta in codex kimi agy; do
    confere_rc 0 "primeira vaga: $conta" pool pega "$conta" ctx_a
    confere_rc 75 "limite de uma vaga: $conta" pool pega "$conta" ctx_b
done
pool solta ctx_a
printf 'team=2\npessoal=1\n' > "$HOME/.claude/agentes.conf"
confere_rc 0 'config: team primeira' pool pega team ctx_c1
confere_rc 0 'config: team segunda' pool pega team ctx_c2
confere_rc 75 'config: team terceira cheia' pool pega team ctx_c3
confere_rc 0 'config: pessoal limitado' pool pega pessoal ctx_p1
confere_rc 75 'config: pessoal cheio' pool pega pessoal ctx_p2
pool livres > "$tmp/livres"
grep -qx 'team 0/2' "$tmp/livres" && ok 'livres conta ocupação' || ruim 'livres incorreto'
echo completed > "$POOL_ESTADOS/ctx_c1"
pool livres > "$tmp/livres"
grep -qx 'team 1/2' "$tmp/livres" && ok 'livres recupera vaga terminal' || ruim 'livres não recuperou'
printf 'team=1\n' > "$HOME/.claude/agentes.conf"
confere_rc 75 'redução de limite respeita vaga antiga fora da faixa' pool pega team ctx_novo
confere_rc 2 'conta desconhecida rejeitada' pool pega outra ctx_x
confere_rc 2 'dispatch inseguro rejeitado' pool solta ../ctx_x
printf 'team=abc\n' > "$HOME/.claude/agentes.conf"
confere_rc 2 'config inválida rejeitada' pool livres
rm "$HOME/.claude/agentes.conf"
pool solta ctx_c2; pool solta ctx_p1; pool solta ctx_novo

# Executa o seletor real com provedores simulados, sem rede ou credenciais reais.
mkdir -p "$tmp/seletor" "$HOME/.claude-team"
cp "$raiz/skills/limites-cota/limites.sh" "$raiz/skills/limites-cota/vaga-agente.sh" "$tmp/seletor/" 2>/dev/null
cat > "$tmp/bin/claude" <<'EOF'
#!/usr/bin/env bash
uso=${POOL_PESSOAL_USO:-30}
[ -n "$CLAUDE_CONFIG_DIR" ] && uso=10
printf 'Current session: %s%% used\nCurrent week (all models): %s%% used\n' "$uso" "$uso"
EOF
cat > "$tmp/bin/codex" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
cat > "$tmp/seletor/codex-cota.sh" <<'EOF'
echo 'codex: 5h 20% usado | semana 20% usado'
EOF
chmod +x "$tmp/bin/claude" "$tmp/bin/codex"
cp "$tmp/bin/codex" "$tmp/bin/agy"
export PATH="$tmp/bin:$PATH"
seletor() { bash "$tmp/seletor/limites.sh" --escritor; }
confere_rc 0 'seleção com vagas' seletor
grep -qx 'escritor: team (90% livre)' "$tmp/saida" && ok 'escolhe maior folga' || ruim 'maior folga incorreta'
pool pega team ctx_s1
confere_rc 0 'seleção exclui team ocupado' seletor
grep -qx 'escritor: codex (80% livre)' "$tmp/saida" && ok 'ignora melhor cota sem vaga' || ruim 'escolheu conta cheia'
pool pega codex ctx_s2
confere_rc 0 'seleção pessoal ilimitado' seletor
grep -qx 'escritor: pessoal (70% livre)' "$tmp/saida" && ok 'pessoal continua candidato' || ruim 'ilimitado excluído'
printf 'pessoal=1\n' > "$HOME/.claude/agentes.conf"
pool pega pessoal ctx_s3
confere_rc 75 'seletor retorna 75 com pool cheio' seletor
grep -qx 'escritor: nenhum (pool cheio)' "$tmp/saida" && ok 'seletor informa pool cheio' || ruim 'mensagem de pool cheio'
pool solta ctx_s3
export POOL_PESSOAL_USO=90
confere_rc 0 'cota esgotada difere de pool cheio' seletor
grep -qx 'escritor: nenhum (todos acima de 80% ou ausentes)' "$tmp/saida" && ok 'cota preserva diagnóstico' || ruim 'diagnóstico de cota'
export POOL_PESSOAL_USO=30
printf 'pessoal=abc\n' > "$HOME/.claude/agentes.conf"
confere_rc 2 'seletor propaga erro do pool' seletor
confere_rc 0 'tabela continua com erro do pool e cota normal' bash "$tmp/seletor/limites.sh"
grep -q 'pessoal: sessão 30% usado' "$tmp/saida" && ok 'tabela mantém cotas legíveis' || ruim 'tabela perdeu cotas'
grep -q 'AVISO:.*pool' "$tmp/saida" && ok 'tabela avisa erro do pool' || ruim 'tabela não avisou erro do pool'
export POOL_PESSOAL_USO=90
confere_rc 3 'tabela preserva alerta acima de 80% com erro do pool' bash "$tmp/seletor/limites.sh"
grep -q 'pessoal: sessão 90% usado' "$tmp/saida" && ok 'tabela mostra cota acima de 80%' || ruim 'tabela perdeu cota alta'
export POOL_PESSOAL_USO=30
rm "$HOME/.claude/agentes.conf"
confere_rc 0 'hook instala scripts em HOME temporário' env CLAUDE_PLUGIN_ROOT="$raiz" bash "$raiz/hooks/instala-scripts.sh"
cmp -s "$raiz/skills/limites-cota/vaga-agente.sh" "$HOME/.cache/vaga-agente.sh" \
    && ok 'script do pool instalado' || ruim 'instalação do pool'

[ "$falhas" = 0 ] && echo 'TUDO OK' || { echo "$falhas falha(s)"; exit 1; }

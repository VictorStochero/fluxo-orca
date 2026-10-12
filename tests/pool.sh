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
# Ritmo = (100 − longa) / (100 × fração restante da janela longa); longa: 168 h (semana) ou 720 h (mês do Kimi).
mkdir -p "$tmp/seletor" "$HOME/.claude-team"
cp "$raiz/skills/limites-cota/limites.sh" "$raiz/skills/limites-cota/vaga-agente.sh" "$tmp/seletor/" 2>/dev/null
cat > "$tmp/bin/claude" <<'EOF'
#!/usr/bin/env bash
[ -n "${ORCA_PANE_KEY:-}${ORCA_AGENT_HOOK_PORT:-}" ] && touch "$POOL_ESTADOS/orca-vazou"
uso_c=${POOL_SESSAO_USO:-30}; uso_l=${POOL_SEMANA_USO:-30}; reset_h=${POOL_RESET_H:-168}
if [ -n "$CLAUDE_CONFIG_DIR" ]; then
    uso_c=${POOL_TEAM_SESSAO_USO:-10}; uso_l=${POOL_TEAM_SEMANA_USO:-10}; reset_h=${POOL_TEAM_RESET_H:-84}
fi
zera_c=$(date -d '+3 hours' '+%b %-d, %-I:%M%p')
zera=$(date -d "+${reset_h} hours" '+%b %-d, %-I:%M%p')
printf 'Current session: %s%% used, resets %s (America/Sao_Paulo)\nCurrent week (all models): %s%% used, resets %s (America/Sao_Paulo)\n' "$uso_c" "$zera_c" "$uso_l" "$zera"
EOF
cat > "$tmp/bin/codex" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
cat > "$tmp/seletor/codex-cota.sh" <<'EOF'
c=${POOL_CODEX_5H:-20}; l=${POOL_CODEX_SEMANA:-20}; h=${POOL_CODEX_RESET_H:-168}
printf 'codex: 5h %s%% (zera 23:00) · semana %s%% (zera %s)\n' "$c" "$l" "$(date -d "+${h} hours" '+%Y-%m-%d %H:%M')"
EOF
chmod +x "$tmp/bin/claude" "$tmp/bin/codex" "$tmp/seletor/codex-cota.sh"
cp "$tmp/bin/codex" "$tmp/bin/agy"
export PATH="$tmp/bin:$PATH"
seletor() { bash "$tmp/seletor/limites.sh" --escritor; }
confere_rc 0 'seleção com vagas' seletor
grep -qx 'escritor: team (ritmo 1.8 · 90% livre, zera em 84h)' "$tmp/saida" \
    && ok 'escolhe maior ritmo' || ruim 'maior ritmo incorreto'

# Conta que zera antes vence mesmo com menos folga absoluta.
POOL_TEAM_SEMANA_USO=60 POOL_TEAM_RESET_H=24 confere_rc 0 'ritmo: zera antes vence' seletor
grep -qx 'escritor: team (ritmo 2.8 · 40% livre, zera em 24h)' "$tmp/saida" \
    && ok 'zera antes vence com menos folga' || ruim 'zera antes não venceu'
unset POOL_TEAM_SEMANA_USO POOL_TEAM_RESET_H

ORCA_PANE_KEY=painel ORCA_AGENT_HOOK_PORT=1 confere_rc 0 'medição dentro de painel do Orca' seletor
[ -e "$POOL_ESTADOS/orca-vazou" ] && ruim 'claude -p herdou variáveis do Orca' || ok 'claude -p sem variáveis do Orca'

# Teto da longa: 95% só com reset em < 24 h; fora disso, 80%. Curta sempre ≤ 80.
POOL_TEAM_SEMANA_USO=90 POOL_TEAM_RESET_H=12 confere_rc 0 'teto 95 com reset próximo' seletor
grep -qx 'escritor: team (ritmo 1.4 · 10% livre, zera em 12h)' "$tmp/saida" \
    && ok 'teto 95% a menos de 24 h entra' || ruim 'teto 95% não entrou'
POOL_TEAM_RESET_H=48 POOL_TEAM_SEMANA_USO=90 confere_rc 0 'teto 95 expira' seletor
grep -qx 'escritor: codex (ritmo 0.8 · 80% livre, zera em 168h)' "$tmp/saida" \
    && ok 'acima de 80 sem reset próximo fica fora' || ruim 'teto 80% não aplicado'
POOL_TEAM_RESET_H=12 POOL_TEAM_SEMANA_USO=96 confere_rc 0 'teto 95 excedido' seletor
grep -qx 'escritor: codex (ritmo 0.8 · 80% livre, zera em 168h)' "$tmp/saida" \
    && ok 'acima de 95% fica fora mesmo perto do reset' || ruim 'teto 95% excedido entrou'
POOL_TEAM_SESSAO_USO=85 POOL_TEAM_SEMANA_USO=10 confere_rc 0 'curta acima de 80' seletor
grep -qx 'escritor: codex (ritmo 0.8 · 80% livre, zera em 168h)' "$tmp/saida" \
    && ok 'curta acima de 80 fica fora' || ruim 'curta acima de 80 entrou'
unset POOL_TEAM_SESSAO_USO POOL_TEAM_SEMANA_USO POOL_TEAM_RESET_H

# Kimi entra direto pelo ritmo do mês (720 h); semana-eq deixou de existir.
mkdir -p "$HOME/.kimi-code/credentials"; : > "$HOME/.kimi-code/credentials/kimi-code-env-t.json"
kimi_stub() { echo "echo 'kimi: 5h ${1:-2}% (zera 23:00) · mês ${2:-10}%${3:+ (zera $3)}'" > "$tmp/seletor/kimi-cota.sh"; }
kimi_stub 2 10 "$(date -d '+720 hours' '+%Y-%m-%d %H:%M')"
POOL_TEAM_SEMANA_USO=20 POOL_TEAM_RESET_H=168 confere_rc 0 'seleção com Kimi' seletor
grep -qx 'escritor: kimi (ritmo 0.9 · 90% livre, zera em 720h)' "$tmp/saida" \
    && ok 'Kimi com maior ritmo é escolhido' || ruim 'Kimi não escolhido'
unset POOL_TEAM_SEMANA_USO POOL_TEAM_RESET_H
kimi_stub 2 90 "$(date -d '+720 hours' '+%Y-%m-%d %H:%M')"
confere_rc 0 'seleção com Kimi acima do teto' seletor
grep -qx 'escritor: team (ritmo 1.8 · 90% livre, zera em 84h)' "$tmp/saida" \
    && ok 'Kimi acima do teto fica fora' || ruim 'Kimi acima do teto escolhido'
kimi_stub 2 90 "$(date -d '+10 hours' '+%Y-%m-%d %H:%M')"
confere_rc 0 'Kimi com reset próximo' seletor
grep -qx 'escritor: kimi (ritmo 7.2 · 10% livre, zera em 10h)' "$tmp/saida" \
    && ok 'Kimi 90% entra pelo teto 95% com reset < 24 h' || ruim 'teto 95% do Kimi não aplicado'
# Reset ilegível cai para a folga da longa, sem quebrar.
kimi_stub 2 4 ""
POOL_TEAM_SEMANA_USO=20 POOL_TEAM_RESET_H=168 confere_rc 0 'Kimi com reset ilegível' seletor
grep -qx 'escritor: kimi (ritmo 1.0 · 96% livre)' "$tmp/saida" \
    && ok 'reset ilegível cai para a folga' || ruim 'reset ilegível quebrou a seleção'
unset POOL_TEAM_SEMANA_USO POOL_TEAM_RESET_H
kimi_stub 2 85 "$(date -d '+720 hours' '+%Y-%m-%d %H:%M')"
confere_rc 3 'tabela alerta mês do Kimi acima de 80%' bash "$tmp/seletor/limites.sh"
rm -rf "$HOME/.kimi-code" "$tmp/seletor/kimi-cota.sh"

pool pega team ctx_s1
confere_rc 0 'seleção exclui team ocupado' seletor
grep -qx 'escritor: codex (ritmo 0.8 · 80% livre, zera em 168h)' "$tmp/saida" \
    && ok 'ignora melhor ritmo sem vaga' || ruim 'escolheu conta cheia'
pool pega codex ctx_s2
confere_rc 0 'seleção pessoal ilimitado' seletor
grep -qx 'escritor: pessoal (ritmo 0.7 · 70% livre, zera em 168h)' "$tmp/saida" \
    && ok 'pessoal continua candidato' || ruim 'ilimitado excluído'
printf 'pessoal=1\n' > "$HOME/.claude/agentes.conf"
pool pega pessoal ctx_s3
confere_rc 75 'seletor retorna 75 com pool cheio' seletor
grep -qx 'escritor: nenhum (pool cheio)' "$tmp/saida" && ok 'seletor informa pool cheio' || ruim 'mensagem de pool cheio'
pool solta ctx_s3
export POOL_SESSAO_USO=90 POOL_SEMANA_USO=90 POOL_TEAM_SEMANA_USO=90 POOL_CODEX_SEMANA=90
confere_rc 0 'cota esgotada difere de pool cheio' seletor
grep -qx 'escritor: nenhum (todos acima do teto ou ausentes)' "$tmp/saida" && ok 'cota preserva diagnóstico' || ruim 'diagnóstico de cota'
unset POOL_SESSAO_USO POOL_SEMANA_USO POOL_TEAM_SEMANA_USO POOL_CODEX_SEMANA
printf 'pessoal=abc\n' > "$HOME/.claude/agentes.conf"
confere_rc 2 'seletor propaga erro do pool' seletor
confere_rc 0 'tabela continua com erro do pool e cota normal' bash "$tmp/seletor/limites.sh"
grep -q 'pessoal: sessão 30% usado' "$tmp/saida" && ok 'tabela mantém cotas legíveis' || ruim 'tabela perdeu cotas'
grep -q 'AVISO:.*pool' "$tmp/saida" && ok 'tabela avisa erro do pool' || ruim 'tabela não avisou erro do pool'
export POOL_SESSAO_USO=90 POOL_SEMANA_USO=90
confere_rc 3 'tabela preserva alerta acima de 80% com erro do pool' bash "$tmp/seletor/limites.sh"
grep -q 'pessoal: sessão 90% usado' "$tmp/saida" && ok 'tabela mostra cota acima de 80%' || ruim 'tabela perdeu cota alta'
unset POOL_SESSAO_USO POOL_SEMANA_USO
rm "$HOME/.claude/agentes.conf"

# Reserva: a vaga é pega antes do worker-start; disputa na última vaga cai para o próximo candidato elegível.
seletor_reserva() { bash "$tmp/seletor/limites.sh" --escritor --reserva "$1"; }
pool solta ctx_s2
confere_rc 0 'reserva com vaga do vencedor tomada' seletor_reserva r1
grep -qx 'escritor: codex (ritmo 0.8 · 80% livre, zera em 168h) reserva res-r1' "$tmp/saida" \
    && ok 'reserva cai para o próximo candidato' || ruim 'reserva não caiu para o próximo'
[ "$(cat "$HOME/.cache/agentes/codex.lock1/dispatch" 2>/dev/null)" = res-r1 ] \
    && ok 'reserva gravada no pool' || ruim 'reserva não gravada'
confere_rc 0 'solta libera a reserva' pool solta res-r1

# troca: o dono provisório vira o dispatch real, uma só vez.
pool solta ctx_s1
confere_rc 0 'reserva avulsa antes do start' pool pega team res-r2
confere_rc 0 'troca vira dispatch real' pool troca res-r2 ctx_real
[ "$(cat "$HOME/.cache/agentes/team.lock1/dispatch" 2>/dev/null)" = ctx_real ] \
    && ok 'troca gravou o dispatch real' || ruim 'troca não gravou o dispatch real'
confere_rc 0 'troca idempotente' pool troca res-r2 ctx_real
confere_rc 2 'troca com dono errado' pool troca res-errado ctx_outro
confere_rc 0 'solta o dispatch real' pool solta ctx_real

# Reserva provisória não é consultada no Orca: TTL é a única recuperação.
confere_rc 0 'reserva para o TTL' pool pega team res-r3
confere_rc 0 'livres conserva reserva dentro do TTL' pool livres
grep -qx 'team 0/1' "$tmp/saida" && ok 'reserva dentro do TTL conserva a vaga' || ruim 'reserva nova foi recuperada'
date -u -d '-20 minutes' +%FT%TZ > "$HOME/.cache/agentes/team.lock1/desde"
confere_rc 0 'livres recupera reserva fora do TTL' pool livres
grep -qx 'team 1/1' "$tmp/saida" && ok 'reserva fora do TTL é recuperada' || ruim 'reserva expirada não foi recuperada'
confere_rc 0 'reserva com TTL=0' pool pega team res-r4
date -u -d '-1 minute' +%FT%TZ > "$HOME/.cache/agentes/team.lock1/desde"
POOL_RESERVA_TTL=0 confere_rc 0 'livres com TTL=0' pool livres
grep -qx 'team 1/1' "$tmp/saida" && ok 'POOL_RESERVA_TTL=0 recupera reserva antiga' || ruim 'TTL=0 não recuperou'

# Reserva impossível: pool cheio para todos os elegíveis.
printf 'team=1\npessoal=1\n' > "$HOME/.claude/agentes.conf"
pool pega team ctx_b0; pool pega pessoal ctx_b1; pool pega codex ctx_b2
confere_rc 75 'reserva com tudo cheio' seletor_reserva r5
grep -qx 'escritor: nenhum (pool cheio)' "$tmp/saida" && ok 'reserva informa pool cheio' || ruim 'reserva não informou pool cheio'
pool solta ctx_b0; pool solta ctx_b1; pool solta ctx_b2
rm "$HOME/.claude/agentes.conf"

# Conta ilimitada reserva trivialmente, sem criar trava.
export POOL_TEAM_SEMANA_USO=90 POOL_CODEX_SEMANA=90
confere_rc 0 'reserva na conta ilimitada' seletor_reserva r6
grep -qx 'escritor: pessoal (ritmo 0.7 · 70% livre, zera em 168h)' "$tmp/saida" \
    && ok 'conta ilimitada sem sufixo de reserva (nada a trocar)' || { ruim 'reserva ilimitada falhou'; cat "$tmp/saida"; }
compgen -G "$HOME/.cache/agentes/pessoal.lock*" >/dev/null && ruim 'pessoal ilimitado criou trava' || ok 'reserva ilimitada não cria trava'
unset POOL_TEAM_SEMANA_USO POOL_CODEX_SEMANA

pool solta ctx_s1 2>/dev/null
rmdir "$HOME/.claude-team"
mkdir -p "$tmp/pessoal-bin"
cp "$tmp/bin/claude" "$tmp/pessoal-bin/"
for comando in bash mktemp rm dirname cat sed awk mkdir date ls sort env; do
    printf '#!/bin/bash\nexec "%s" "$@"\n' "$(command -v "$comando")" > "$tmp/pessoal-bin/$comando"
    chmod +x "$tmp/pessoal-bin/$comando"
done
confere_rc 0 'seleção sem fornecedores opcionais' env PATH="$tmp/pessoal-bin" bash "$tmp/seletor/limites.sh" --escritor
grep -qx 'escritor: pessoal (ritmo 0.7 · 70% livre, zera em 168h)' "$tmp/saida" \
    && ok 'só pessoal disponível escolhe pessoal' || ruim 'seleção exige fornecedor opcional'
confere_rc 0 'hook instala scripts em HOME temporário' env CLAUDE_PLUGIN_ROOT="$raiz" bash "$raiz/hooks/instala-scripts.sh"
cmp -s "$raiz/skills/limites-cota/vaga-agente.sh" "$HOME/.cache/vaga-agente.sh" \
    && ok 'script do pool instalado' || ruim 'instalação do pool'

[ "$falhas" = 0 ] && echo 'TUDO OK' || { echo "$falhas falha(s)"; exit 1; }

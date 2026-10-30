#!/usr/bin/env bash
# Prova dos medidores de cota com claude e orca simulados (sem rede, sem conta real).
raiz=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export HOME="$tmp/home"
mkdir -p "$HOME/.claude" "$tmp/bin"
falhas=0
ok() { echo "ok   $1"; }
ruim() { echo "FALHA $1"; falhas=$((falhas + 1)); }
med="$raiz/skills/limites-cota/medidores"
igual() { if [ "$2" = "$3" ]; then ok "$1"; else ruim "$1: esperado [$2], veio [$3]"; fi; }
comeca() { case "$3" in "$2"*) ok "$1" ;; *) ruim "$1: esperado começar com [$2], veio [$3]" ;; esac; }

cat > "$tmp/bin/claude" <<'EOF'
#!/usr/bin/env bash
case " $* " in *' --strict-mcp-config '*) ;; *) exit 2 ;; esac
[ -n "${MED_SEM_SEMANA:-}" ] && { echo 'Current session: 12% used'; exit 0; }
uso_c=30; uso_l=40; [ -n "$CLAUDE_CONFIG_DIR" ] && { uso_c=10; uso_l=6; }
printf 'Current session: %s%% used, resets %s (America/Sao_Paulo)\nCurrent week (all models): %s%% used, resets %s (America/Sao_Paulo)\n' \
    "$uso_c" "$(date -d '+3 hours' '+%b %-d, %-I:%M%p')" "$uso_l" "$(date -d '+84 hours' '+%b %-d, %-I:%M%p')"
EOF
chmod +x "$tmp/bin/claude"
export PATH="$tmp/bin:$PATH"

# Claude: linha de hoje e #cand com a semana de 168 h.
saida=$(bash "$med/claude.sh" pessoal)
comeca 'claude: linha humana' 'pessoal: sessão 30% usado, zera' "$(printf '%s\n' "$saida" | head -1)"
read -r _ conta c l ep dur <<< "$(printf '%s\n' "$saida" | grep '^#cand')"
igual 'claude: #cand pessoal' 'pessoal 30 40 168' "$conta $c $l $dur"
h=$(( (ep - $(date +%s) + 1800) / 3600 ))
igual 'claude: reset em 84 h' 84 "$h"
saida=$(CONTA_CONFIG="$HOME/.claude-team" bash "$med/claude.sh" team)
comeca 'claude: rótulo alinhado e config da conta' 'team   : sessão 10% usado' "$(printf '%s\n' "$saida" | head -1)"
igual 'claude: #cand team' '#cand team 10 6' "$(printf '%s\n' "$saida" | grep '^#cand' | cut -d' ' -f1-4)"
saida=$(MED_SEM_SEMANA=1 bash "$med/claude.sh" team)
igual 'claude: sem semana é ilegível' 'team: ilegível' "$saida"

# Orca: rateLimits do `orca account list --json`, uma leitura por execução.
agora_ms=$(( $(date +%s) * 1000 ))
as23=$(( $(date -d '23:00' +%s) * 1000 ))
semana=$(( agora_ms + 100 * 3600 * 1000 ))
cat > "$tmp/conta.json" <<EOF
{"ok":true,"result":{"rateLimits":{
 "codex":{"provider":"codex","session":{"usedPercent":95,"windowMinutes":300,"resetsAt":$as23},"weekly":{"usedPercent":20,"windowMinutes":10080,"resetsAt":$semana},"status":"ok","error":null},
 "kimi":{"session":null,"weekly":null,"status":"unavailable","error":"Not signed in to Kimi Code"},
 "minimax":{"session":{"usedPercent":5,"windowMinutes":300,"resetsAt":$as23},"weekly":null,"monthly":{"usedPercent":50,"windowMinutes":43200,"resetsAt":$semana},"status":"ok","error":null},
 "semreset":{"session":{"usedPercent":1,"windowMinutes":300,"resetsAt":null},"weekly":{"usedPercent":4,"windowMinutes":10080,"resetsAt":null},"status":"ok","error":null},
 "antigravity":{"session":0,"weekly":0,"status":"ok","error":null,"buckets":[
   {"group":"Gemini Models","windowName":"Weekly Limit Remaining","usedPercent":10,"windowMinutes":10080,"resetsAt":$semana},
   {"group":"Gemini Models","windowName":"Five Hour Limit Remaining","usedPercent":2,"windowMinutes":300,"resetsAt":$as23},
   {"group":"Claude and GPT models","windowName":"Weekly Limit Remaining","usedPercent":85,"windowMinutes":10080,"resetsAt":$semana},
   {"group":"Claude and GPT models","windowName":"Five Hour Limit Remaining","usedPercent":1,"windowMinutes":300,"resetsAt":$as23}]}
}}}
EOF
export MEDIDOR_ORCA_JSON="$tmp/conta.json"
saida=$(bash "$med/orca.sh" codex codex)
igual 'orca: linha do codex como a de hoje' "codex: 5h 95% (zera 23:00) · semana 20% (zera $(date -d "@$((semana / 1000))" '+%Y-%m-%d %H:%M'))" "$(printf '%s\n' "$saida" | head -1)"
read -r _ conta c l ep dur <<< "$(printf '%s\n' "$saida" | grep '^#cand')"
igual 'orca: #cand codex' 'codex 95 20 168' "$conta $c $l $dur"
igual 'orca: reset da semana' "$((semana / 1000))" "$ep"
igual 'orca: caminho lido sem conversão do MSYS' '#cand codex 95 20' "$(MSYS_NO_PATHCONV=1 bash "$med/orca.sh" codex codex | grep '^#cand' | cut -d' ' -f1-4)"
igual 'orca: fornecedor indisponível' 'kimi: ilegível (Not signed in to Kimi Code)' "$(bash "$med/orca.sh" kimi kimi)"
saida=$(bash "$med/orca.sh" mm minimax)
comeca 'orca: longa mensal' 'mm: 5h 5% (zera 23:00) · mês 50% (zera ' "$(printf '%s\n' "$saida" | head -1)"
igual 'orca: duração da mensal pelo windowMinutes' '#cand mm 5 50' "$(printf '%s\n' "$saida" | grep '^#cand' | cut -d' ' -f1-4)"
igual 'orca: 720 h' 720 "$(printf '%s\n' "$saida" | grep '^#cand' | cut -d' ' -f6)"
saida=$(bash "$med/orca.sh" sr semreset)
igual 'orca: sem reset' 'sr: 5h 1% · semana 4%' "$(printf '%s\n' "$saida" | head -1)"
igual 'orca: #cand sem reset' '#cand sr 1 4 - 168' "$(printf '%s\n' "$saida" | grep '^#cand')"
saida=$(bash "$med/orca.sh" agy antigravity)
igual 'orca: um grupo por linha' 2 "$(printf '%s\n' "$saida" | grep -vc '^#')"
comeca 'orca: grupo Gemini' 'agy Gemini Models: 5h 2% (zera 23:00) · semana 10% (zera ' "$(printf '%s\n' "$saida" | grep 'Gemini')"
igual 'orca: #cand pelo pior grupo (Claude, 85% na semana)' '#cand agy 1 85' "$(printf '%s\n' "$saida" | grep '^#cand' | cut -d' ' -f1-4)"
igual 'orca: fornecedor ausente' 'x: ilegível (sem dados do Orca para nada)' "$(bash "$med/orca.sh" x nada)"

# Sem cache: chama o Orca; Orca fora do ar vira ilegível.
unset MEDIDOR_ORCA_JSON
printf '#!/usr/bin/env bash\n[ "$1 $2 $3" = "account list --json" ] && cat "%s"\n' "$tmp/conta.json" > "$tmp/bin/orca-ok"
printf '#!/usr/bin/env bash\nexit 1\n' > "$tmp/bin/orca-fora"
chmod +x "$tmp/bin/orca-ok" "$tmp/bin/orca-fora"
igual 'orca: sem cache consulta o Orca' '#cand codex 95 20' "$(ORCA_CMD="$tmp/bin/orca-ok" bash "$med/orca.sh" codex codex | grep '^#cand' | cut -d' ' -f1-4)"
igual 'orca: fora do ar' 'codex: ilegível (Orca fora do ar)' "$(ORCA_CMD="$tmp/bin/orca-fora" bash "$med/orca.sh" codex codex)"

[ "$falhas" = 0 ] && echo "tudo ok" || { echo "$falhas falha(s)"; exit 1; }

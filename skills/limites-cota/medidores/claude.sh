#!/usr/bin/env bash
# Medidor Claude: API de uso com o token de <config>/.credentials.json (CONTA_CONFIG; sem ele, ~/.claude);
# sem token válido ou com LIMITES_SEM_API=1, cai no /usage do claude (CLAUDE_CONFIG_DIR=$CONTA_CONFIG), que também renova o token.
# Uso: claude.sh <conta> → linha humana e "#cand <conta> <sessão%> <semana%> <reset_epoch|-> 168".
conta=$1
export MSYS_NO_PATHCONV=1
# Com MSYS_NO_PATHCONV o caminho POSIX chegaria cru ao claude no Windows.
w() { if command -v cygpath >/dev/null 2>&1; then cygpath -w "$1"; else printf '%s' "$1"; fi; }

# Qualquer falha sai com 1 e sem mensagem: o token nunca chega à saída.
usa_api() {
    local py
    for py in python3 python ""; do [ -n "$py" ] && "$py" -c '' 2>/dev/null && break; done
    [ -n "$py" ] || return 1
    USO_CFG="$(w "${CONTA_CONFIG:-$HOME/.claude}")" USO_CONTA="$conta" \
        USO_URL="${LIMITES_USAGE_URL:-https://api.anthropic.com/api/oauth/usage}" "$py" -I - 2>/dev/null <<'EOF'
import datetime, json, os, sys, time, urllib.request
sys.stdout.reconfigure(encoding="utf-8")
MESES = "jan fev mar abr mai jun jul ago set out nov dez".split()
try:
    o = json.load(open(os.path.join(os.environ["USO_CFG"], ".credentials.json"), encoding="utf-8"))["claudeAiOauth"]
    exp = o.get("expiresAt")
    if not o["accessToken"] or (exp and exp / 1000 <= time.time()): sys.exit(1)
    req = urllib.request.Request(os.environ["USO_URL"], headers={
        "Authorization": "Bearer " + o["accessToken"], "anthropic-beta": "oauth-2025-04-20", "Accept": "application/json"})
    d = json.load(urllib.request.urlopen(req, timeout=10))
    sem = d["seven_day"]; l = int(sem["utilization"] + 0.5)
    cur = d.get("five_hour") or {}
    c = int(cur["utilization"] + 0.5) if cur.get("utilization") is not None else l

    def zera(j):
        t = (j or {}).get("resets_at")
        return datetime.datetime.fromisoformat(t.replace("Z", "+00:00")).astimezone() if t else None

    def txt(rot, p, dt):
        return f"{rot} {p}% usado" + (f", zera {dt.day} {MESES[dt.month - 1]} {dt:%H:%M}" if dt else "")

    zs = zera(sem)
    print("%-7s: %s | %s" % (os.environ["USO_CONTA"], txt("sessão", c, zera(cur)), txt("semana", l, zs)))
    print("#cand %s %d %d %s 168" % (os.environ["USO_CONTA"], c, l, int(zs.timestamp()) if zs else "-"))
except Exception:
    sys.exit(1)
EOF
}
if [ -z "${LIMITES_SEM_API:-}" ] && api=$(usa_api) && [ -n "$api" ]; then printf '%s\n' "$api"; exit 0; fi
# Sem as variáveis do Orca: os hooks do claude -p reportariam fim de turno pelo agente do painel que mediu.
usage=$( (for v in $(compgen -e | grep '^ORCA_'); do unset "$v"; done
    # --bare não traz a cota de assinatura no Windows; --strict-mcp-config preserva o /usage sem MCPs.
    if [ -n "${CONTA_CONFIG:-}" ]; then
        env CLAUDE_CONFIG_DIR="$(w "$CONTA_CONFIG")" claude --strict-mcp-config --settings "$(w "$HOME/.claude/settings.json")" --model haiku -p "/usage"
    else
        env -u CLAUDE_CONFIG_DIR claude --strict-mcp-config -p "/usage"
    fi) 2>&1)
linha=$(printf '%s\n' "$usage" | awk -v r="$(printf '%-7s' "$conta")" '
    /^Current session:/ { sub(/ used.*resets /, " usado, zera "); sub(/ used$/, " usado"); sub(/^Current session: /, ""); s=$0 }
    /^Current week \(all models\):/ { sub(/ used.*resets /, " usado, zera "); sub(/ used$/, " usado"); sub(/^Current week \(all models\): /, ""); w=$0 }
    END { if (w == "") exit 1
          printf "%s: sessão %s | semana %s\n", r, s, w }') || {
    # Deslogada (token revogado, refresh vencido) o /usage só traz o resumo de custo; sem #cand a conta sai da escolha e do cache.
    if (for v in $(compgen -e | grep '^ORCA_'); do unset "$v"; done
        if [ -n "${CONTA_CONFIG:-}" ]; then export CLAUDE_CONFIG_DIR="$(w "$CONTA_CONFIG")"; else unset CLAUDE_CONFIG_DIR; fi
        claude auth status 2>/dev/null) | grep -q '"loggedIn": *false'; then
        pre=; [ -z "${CONTA_CONFIG:-}" ] || pre="CLAUDE_CONFIG_DIR=${CONTA_CONFIG/#$HOME/\~} "
        echo "$conta: sem login (rode ${pre}claude auth login)"
    else
        echo "$conta: ilegível"
    fi
    exit 0
}
printf '%s\n' "$linha"

# pct() isola o trecho casado e reextrai os dígitos colados ao %: índices de multibyte (ê, ã) variam entre awk UTF-8 e byte-orientado.
read -r c l z <<< "$(printf '%s\n' "$linha" | awk '
    function pct(   s) { s = substr($0, RSTART, RLENGTH); match(s, /[0-9]+%/); return substr(s, RSTART, RLENGTH - 1) + 0 }
    { match($0, /semana [0-9]+%/); ini = RSTART; tam = RLENGTH; l = pct()
      s = substr($0, ini, tam + 120)
      c = l; if (match($0, /sessão [0-9]+%/)) c = pct()
      z = "-"; if (match(s, /zera [^|]+/)) { z = substr(s, RSTART + 5, RLENGTH - 5); gsub(/ \([^)]*\)/, "", z); gsub(/,/, "", z) }
      gsub(/ /, "_", z); print c, l, z }')"
z=${z//_/ }; agora=$(date +%s); ep=-
if [ "$z" != - ]; then
    ep=$(date -d "$z" +%s 2>/dev/null) || ep=-
    # Sem ano: date assume o corrente; se cair no passado, é do ano seguinte.
    if [ "$ep" != - ] && [ "$ep" -le "$agora" ]; then
        ep=$(date -d "$z $(( $(date +%Y) + 1 ))" +%s 2>/dev/null) || ep=-
    fi
    [ -z "$ep" ] && ep=-
    [ "$ep" != - ] && [ "$ep" -le "$agora" ] && ep=-
fi
printf '#cand %s %s %s %s 168\n' "$conta" "$c" "$l" "$ep"

#!/usr/bin/env bash
# Medidor Claude: /usage da conta (CLAUDE_CONFIG_DIR=$CONTA_CONFIG; sem ele, a conta principal).
# Uso: claude.sh <conta> → linha humana e "#cand <conta> <sessão%> <semana%> <reset_epoch|-> 168".
conta=$1
export MSYS_NO_PATHCONV=1
# Com MSYS_NO_PATHCONV o caminho POSIX chegaria cru ao claude no Windows.
w() { if command -v cygpath >/dev/null 2>&1; then cygpath -w "$1"; else printf '%s' "$1"; fi; }
# Sem as variáveis do Orca: os hooks do claude -p reportariam fim de turno pelo agente do painel que mediu.
usage=$( (for v in $(compgen -e | grep '^ORCA_'); do unset "$v"; done
    # --bare perde a autenticação no Windows; --strict-mcp-config evita MCPs e preserva o login.
    if [ -n "${CONTA_CONFIG:-}" ]; then
        env CLAUDE_CONFIG_DIR="$(w "$CONTA_CONFIG")" claude --strict-mcp-config --settings "$(w "$HOME/.claude/settings.json")" --model haiku -p "/usage"
    else
        env -u CLAUDE_CONFIG_DIR claude --strict-mcp-config -p "/usage"
    fi) 2>&1)
linha=$(printf '%s\n' "$usage" | awk -v r="$(printf '%-7s' "$conta")" '
    /^Current session:/ { sub(/ used.*resets /, " usado, zera "); sub(/ used$/, " usado"); sub(/^Current session: /, ""); s=$0 }
    /^Current week \(all models\):/ { sub(/ used.*resets /, " usado, zera "); sub(/ used$/, " usado"); sub(/^Current week \(all models\): /, ""); w=$0 }
    END { if (w == "") exit 1
          printf "%s: sessão %s | semana %s\n", r, s, w }') || { echo "$conta: ilegível"; exit 0; }
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

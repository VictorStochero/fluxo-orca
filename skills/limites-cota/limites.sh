#!/usr/bin/env bash
# Cotas de todos os fornecedores instalados, uma linha cada, em paralelo. Sai com 3 se algum limite passar de 80% usado.
# Última linha: "escritor: <team|pessoal|codex> (<folga>% livre)", o de mais folga; --escritor imprime só ela.
# Conta Claude secundária: CLAUDE_CONFIG_DIR em ~/.claude-team (pula se não existir).
export MSYS_NO_PATHCONV=1
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT

claude_linha() { # $1 rótulo; resto = comando
  local r=$1; shift
  "$@" 2>&1 | awk -v r="$r" '
    /^Current session:/ { sub(/ used.*resets /, " usado, zera "); sub(/ used$/, " usado"); sub(/^Current session: /, ""); s=$0 }
    /^Current week \(all models\):/ { sub(/ used.*resets /, " usado, zera "); sub(/ used$/, " usado"); sub(/^Current week \(all models\): /, ""); w=$0 }
    END { if (s == "") { print r ": ilegível"; exit }
          printf "%s: sessão %s | semana %s\n", r, s, w }'
}

claude_linha "pessoal" claude -p "/usage" > "$tmp/4" &
if [ -d "$HOME/.claude-team" ]; then
  # Com MSYS_NO_PATHCONV o caminho POSIX chegaria cru ao claude no Windows.
  w() { if command -v cygpath >/dev/null 2>&1; then cygpath -w "$1"; else printf '%s' "$1"; fi; }
  claude_linha "team   " env CLAUDE_CONFIG_DIR="$(w "$HOME/.claude-team")" claude --settings "$(w "$HOME/.claude/settings.json")" --model haiku -p "/usage" > "$tmp/3" &
fi
if command -v agy >/dev/null 2>&1; then
  agy --dangerously-skip-permissions -p "/usage" 2>&1 | awk -F'\t' '
    { grupo = ($1 ~ /Gemini/) ? "agy Gemini " : "agy Claude "; janela = ($2 ~ /Five/) ? "5h" : "semana"
      printf "%s %s restam %s\n", grupo, janela, $3 }' | sort > "$tmp/agy" &
fi
if ls "$HOME"/.kimi-code/credentials/kimi-code-env-*.json >/dev/null 2>&1; then
  bash "$(dirname "$0")/kimi-cota.sh" > "$tmp/1" 2>&1 &
fi
if command -v codex >/dev/null 2>&1; then
  bash "$(dirname "$0")/codex-cota.sh" > "$tmp/2" 2>&1 &
fi
wait

SOLO=0; [ "${1:-}" = "--escritor" ] && SOLO=1
{ cat "$tmp/1" 2>/dev/null; sed -n '1,4p' "$tmp/agy" 2>/dev/null; cat "$tmp/2" "$tmp/3" 2>/dev/null; cat "$tmp/4"; } > "$tmp/todas"
[ $SOLO = 0 ] && cat "$tmp/todas"

# escritor: quem tem mais folga (100 - pior entre janela curta e semana) entre team, pessoal e codex; acima de 80% fica de fora. Empate: team, pessoal, codex.
awk '
  function pior(a, b) { return a > b ? a : b }
  /^team/ || /^pessoal/ { k = ($0 ~ /^team/) ? "team" : "pessoal"; s = $0; m = 0
                          while (match(s, /[0-9]+% usado/)) { m = pior(m, substr(s, RSTART, RLENGTH - 7) + 0); s = substr(s, RSTART + RLENGTH) }
                          uso[k] = m; ordem[++q] = k }
  /^codex: 5h/ { match($0, /5h [0-9]+%/); a = substr($0, RSTART + 3, RLENGTH - 3) + 0
                 match($0, /semana [0-9]+%/); b = substr($0, RSTART + 7, RLENGTH - 7) + 0
                 uso["codex"] = pior(a, b); ordem[++q] = "codex" }
  END { melhor = ""; for (i = 1; i <= q; i++) { k = ordem[i]; if (uso[k] <= 80 && (melhor == "" || uso[k] < uso[melhor])) melhor = k }
        if (melhor == "") print "escritor: nenhum (todos acima de 80% ou ausentes)"
        else printf "escritor: %s (%d%% livre)\n", melhor, 100 - uso[melhor] }' "$tmp/todas"
[ $SOLO = 1 ] && exit 0
# alerta: qualquer percentual de uso > 80 (Claude: "N% usado"; agy: "restam N%" -> usado = 100-N; kimi/codex: "5h N%", codex também "semana N%")
awk '
  /usado/    { match($0, /[0-9]+% usado/); if (RLENGTH > 0) { n = substr($0, RSTART, RLENGTH) + 0; if (n > 80) bad = 1 } }
  /restam/   { match($0, /restam [0-9]+%/); if (RLENGTH > 0) { n = substr($0, RSTART + 6, RLENGTH - 6) + 0; if (100 - n > 80) bad = 1 } }
  /^kimi: 5h/ { match($0, /5h [0-9]+%/); n = substr($0, RSTART + 3, RLENGTH - 3) + 0; if (n > 80) bad = 1 }
  /^codex: 5h/ { match($0, /5h [0-9]+%/); n = substr($0, RSTART + 3, RLENGTH - 3) + 0; if (n > 80) bad = 1
                 match($0, /semana [0-9]+%/); n = substr($0, RSTART + 7, RLENGTH - 7) + 0; if (n > 80) bad = 1 }
  END { exit bad ? 3 : 0 }' "$tmp/todas"

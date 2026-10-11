#!/usr/bin/env bash
# Cotas de todos os fornecedores instalados, uma linha cada, em paralelo. Sai com 3 se algum limite passar de 80% usado.
# Ordem de consumo: agy Gemini / Kimi -> agy Claude -> Codex -> conta Claude secundária -> conta Claude principal.
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
  claude_linha "team   " env CLAUDE_CONFIG_DIR="$HOME/.claude-team" claude --settings "$HOME/.claude/settings.json" --model haiku -p "/usage" > "$tmp/3" &
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

{ cat "$tmp/1" 2>/dev/null; sed -n '1,4p' "$tmp/agy" 2>/dev/null; cat "$tmp/2" "$tmp/3" 2>/dev/null; cat "$tmp/4"; } | tee "$tmp/todas"

# alerta: qualquer percentual de uso > 80 (Claude: "N% usado"; agy: "restam N%" -> usado = 100-N; kimi/codex: "5h N%", codex também "semana N%")
awk '
  /usado/    { match($0, /[0-9]+% usado/); if (RLENGTH > 0) { n = substr($0, RSTART, RLENGTH) + 0; if (n > 80) bad = 1 } }
  /restam/   { match($0, /restam [0-9]+%/); if (RLENGTH > 0) { n = substr($0, RSTART + 6, RLENGTH - 6) + 0; if (100 - n > 80) bad = 1 } }
  /^kimi: 5h/ { match($0, /5h [0-9]+%/); n = substr($0, RSTART + 3, RLENGTH - 3) + 0; if (n > 80) bad = 1 }
  /^codex: 5h/ { match($0, /5h [0-9]+%/); n = substr($0, RSTART + 3, RLENGTH - 3) + 0; if (n > 80) bad = 1
                 match($0, /semana [0-9]+%/); n = substr($0, RSTART + 7, RLENGTH - 7) + 0; if (n > 80) bad = 1 }
  END { exit bad ? 3 : 0 }' "$tmp/todas"

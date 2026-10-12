#!/usr/bin/env bash
# Cotas de todos os fornecedores instalados, uma linha cada, em paralelo. Sai com 3 se algum limite passar de 80% usado.
# Última linha: escritor elegível de maior ritmo com vaga no pool; --escritor imprime só ela (75 = pool cheio).
# --escritor --reserva <tag> reserva a vaga do escolhido antes do worker-start (dono provisório res-<tag>, TTL em vaga-agente.sh).
# Conta Claude secundária: CLAUDE_CONFIG_DIR em ~/.claude-team (pula se não existir).
export MSYS_NO_PATHCONV=1
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT

claude_linha() { # $1 rótulo; resto = comando
  local r=$1; shift
  # Sem as variáveis do Orca: os hooks do claude -p reportariam fim de turno pelo agente do painel que mediu.
  (for v in $(compgen -e | grep '^ORCA_'); do unset "$v"; done; "$@") 2>&1 | awk -v r="$r" '
    /^Current session:/ { sub(/ used.*resets /, " usado, zera "); sub(/ used$/, " usado"); sub(/^Current session: /, ""); s=$0 }
    /^Current week \(all models\):/ { sub(/ used.*resets /, " usado, zera "); sub(/ used$/, " usado"); sub(/^Current week \(all models\): /, ""); w=$0 }
    END { if (s == "") { print r ": ilegível"; exit }
          printf "%s: sessão %s | semana %s\n", r, s, w }'
}

claude_linha "pessoal" env -u CLAUDE_CONFIG_DIR claude -p "/usage" > "$tmp/4" &
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

SOLO=0; RESERVA=""
while [ $# -gt 0 ]; do
  case "$1" in
    --escritor) SOLO=1 ;;
    --reserva)
      [ $# -ge 2 ] || { echo 'uso: limites.sh [--escritor [--reserva <tag>]]' >&2; exit 2; }
      RESERVA="res-$2"; shift ;;
    *) echo 'uso: limites.sh [--escritor [--reserva <tag>]]' >&2; exit 2 ;;
  esac
  shift
done
[ -n "$RESERVA" ] && [ $SOLO = 0 ] && { echo 'uso: limites.sh [--escritor [--reserva <tag>]]' >&2; exit 2; }
{ cat "$tmp/1" 2>/dev/null; sed -n '1,4p' "$tmp/agy" 2>/dev/null; cat "$tmp/2" "$tmp/3" 2>/dev/null; cat "$tmp/4"; } > "$tmp/todas"
[ $SOLO = 0 ] && cat "$tmp/todas"

bash "$(dirname "$0")/vaga-agente.sh" livres > "$tmp/pool"
rc=$?
if [ "$rc" != 0 ]; then
  [ $SOLO = 1 ] && exit "$rc"
  echo "AVISO: erro do pool (status $rc); seleção de escritor indisponível" >&2
else
agora=$(date +%s)
# Cada candidato vira "conta curta longa zraw"; zraw = zera da longa legível pelo date -d, ou -.
# pct() isola o trecho casado e reextrai os dígitos: índices de multibyte (ê, ã) variam entre awk UTF-8 e byte-orientado.
awk '
  function pct(   s) { s = substr($0, RSTART, RLENGTH); match(s, /[0-9]+/); return substr(s, RSTART, RLENGTH) + 0 }
  /^team/ || /^pessoal/ { k = ($0 ~ /^team/) ? "team" : "pessoal"
    if (match($0, /semana [0-9]+%/)) { ini = RSTART; tam = RLENGTH; l = pct()
      s = substr($0, ini, tam + 120)
      c = l; if (match($0, /sessão [0-9]+%/)) c = pct()
      z = "-"; if (match(s, /zera [^|]+/)) { z = substr(s, RSTART + 5, RLENGTH - 5); gsub(/ \([^)]*\)/, "", z); gsub(/,/, "", z) }
      print k, c, l, z } next }
  /^codex: 5h/ { c = -1; l = -1; z = "-"
    if (match($0, /5h [0-9]+%/)) c = pct()
    if (match($0, /semana [0-9]+%/)) { ini = RSTART; tam = RLENGTH; l = pct()
      s = substr($0, ini, tam + 30)
      if (match(s, /\(zera [0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}\)/)) z = substr(s, RSTART + 6, RLENGTH - 7) }
    if (c >= 0 && l >= 0) print "codex", c, l, z; next }
  /^kimi: 5h/ { c = -1; l = -1; z = "-"
    if (match($0, /5h [0-9]+%/)) c = pct()
    if (match($0, /mês [0-9]+%/)) { ini = RSTART; tam = RLENGTH; l = pct()
      s = substr($0, ini, tam + 30)
      if (match(s, /\(zera [0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}\)/)) z = substr(s, RSTART + 6, RLENGTH - 7) }
    if (c >= 0 && l >= 0) print "kimi", c, l, z; next }
' "$tmp/todas" | while IFS=' ' read -r conta curta longa z; do
  ep=-
  case "$z" in
    [0-9]*) ep=$(date -d "$z" +%s 2>/dev/null) || ep=- ;;
    *) # Sem ano: date assume o corrente; se cair no passado, é do ano seguinte.
      ep=$(date -d "$z" +%s 2>/dev/null) || ep=-
      if [ "$ep" != - ] && [ "$ep" -le "$agora" ]; then
        ep=$(date -d "$z $(( $(date +%Y) + 1 ))" +%s 2>/dev/null) || ep=-
      fi ;;
  esac
  [ -z "$ep" ] && ep=-
  [ "$ep" != - ] && [ "$ep" -le "$agora" ] && ep=-
  printf '%s %s %s %s\n' "$conta" "$curta" "$longa" "$ep"
done > "$tmp/cand"

# Escritor: elegível (curta <= 80 e longa <= 80, ou <= 95 com reset da longa em < 24 h) e com vaga;
# vence o maior ritmo = (100 - longa) / (100 * fração restante da longa); reset ilegível vira fração 1.
n=0; cand_q=0; cand_vaga=0
{ read -r _ cand_q cand_vaga
  while read -r c r g h; do
    eleg_c[$n]=$c; eleg_r[$n]=$r; eleg_g[$n]=$g; eleg_h[$n]=$h; n=$((n + 1))
  done
} < <(awk -v agora="$agora" '
  FNR == NR { split($2, v, "/"); livre[$1] = (v[2] == 0 || v[1] > 0); next }
  { cand[$1] = 1; curta[$1] = $2; longa[$1] = $3; reset[$1] = $4; q++ }
  END {
    split("team pessoal codex kimi", ordem, " ")
    dur["team"] = 168; dur["pessoal"] = 168; dur["codex"] = 168; dur["kimi"] = 720
    for (i = 1; i <= 4; i++) { k = ordem[i]
      if (!(k in cand) || !livre[k]) continue
      tem_vaga = 1
      h = -1; if (reset[k] != "-") h = (reset[k] - agora) / 3600
      if (curta[k] > 80) continue
      if (!(longa[k] <= 80 || (longa[k] <= 95 && h >= 0 && h < 24))) continue
      frac = 1; if (h >= 0) { frac = h / dur[k]; if (frac < 0.01) frac = 0.01; else if (frac > 1) frac = 1 }
      r = (100 - longa[k]) / (100 * frac)
      m++; rr[m] = r; ll[m] = k; gg[m] = 100 - longa[k]; hh[m] = h
    }
    for (i = 2; i <= m; i++) for (j = i; j > 1 && rr[j - 1] < rr[j]; j--) {
      t = rr[j - 1]; rr[j - 1] = rr[j]; rr[j] = t
      t = ll[j - 1]; ll[j - 1] = ll[j]; ll[j] = t
      t = gg[j - 1]; gg[j - 1] = gg[j]; gg[j] = t
      t = hh[j - 1]; hh[j - 1] = hh[j]; hh[j] = t
    }
    printf "info %d %d\n", q + 0, tem_vaga + 0
    for (i = 1; i <= m; i++) printf "%s %.1f %d %.1f\n", ll[i], rr[i], gg[i], hh[i]
  }' "$tmp/pool" "$tmp/cand")
rc=0
if [ "$n" -gt 0 ]; then
  i=0; sufixo=""
  if [ -n "$RESERVA" ]; then
    i=-1
    for ((j = 0; j < n; j++)); do
      if bash "$(dirname "$0")/vaga-agente.sh" pega "${eleg_c[$j]}" "$RESERVA" 2>/dev/null; then
        # Conta ilimitada não cria vaga: sem sufixo, não há o que trocar depois do start.
        i=$j; grep -qxF "$RESERVA" "$HOME/.cache/agentes/${eleg_c[$j]}".lock*/dispatch 2>/dev/null && sufixo=" reserva $RESERVA"
        break
      fi
    done
    if [ "$i" -lt 0 ]; then echo "escritor: nenhum (pool cheio)"; exit 75; fi
  fi
  if [ "$(awk -v h="${eleg_h[$i]}" 'BEGIN { print (h >= 0) ? 1 : 0 }')" = 1 ]; then
    zera=$(awk -v h="${eleg_h[$i]}" 'BEGIN { printf "%.0f", h }')
    printf 'escritor: %s (ritmo %s · %d%% livre, zera em %sh)%s\n' "${eleg_c[$i]}" "${eleg_r[$i]}" "${eleg_g[$i]}" "$zera" "$sufixo"
  else
    printf 'escritor: %s (ritmo %s · %d%% livre)%s\n' "${eleg_c[$i]}" "${eleg_r[$i]}" "${eleg_g[$i]}" "$sufixo"
  fi
elif [ "$cand_q" -gt 0 ] && [ "$cand_vaga" = 0 ]; then
  echo "escritor: nenhum (pool cheio)"
  rc=75
else
  echo "escritor: nenhum (todos acima do teto ou ausentes)"
fi
fi
[ $SOLO = 1 ] && exit "$rc"
# alerta: qualquer percentual de uso > 80 (Claude: "N% usado"; agy: "restam N%" -> usado = 100-N; kimi: "5h N%" e "mês N%"; codex: "5h N%" e "semana N%")
awk '
  function pct(   s) { s = substr($0, RSTART, RLENGTH); match(s, /[0-9]+/); return substr(s, RSTART, RLENGTH) + 0 }
  /usado/    { match($0, /[0-9]+% usado/); if (RLENGTH > 0) { n = pct(); if (n > 80) bad = 1 } }
  /restam/   { match($0, /restam [0-9]+%/); if (RLENGTH > 0) { n = pct(); if (100 - n > 80) bad = 1 } }
  /^kimi: 5h/ { if (match($0, /5h [0-9]+%/)) { n = pct(); if (n > 80) bad = 1 }
                if (match($0, /mês [0-9]+%/)) { n = pct(); if (n > 80) bad = 1 } }
  /^codex: 5h/ { if (match($0, /5h [0-9]+%/)) { n = pct(); if (n > 80) bad = 1 }
                 if (match($0, /semana [0-9]+%/)) { n = pct(); if (n > 80) bad = 1 } }
  END { exit bad ? 3 : 0 }' "$tmp/todas"

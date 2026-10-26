#!/usr/bin/env bash
# Cota de cada conta do registro (contas.sh: catálogo + ~/.claude/agentes.conf), em paralelo. Sai com 3 se algum limite passar de 80% usado.
# Última linha: escritor escolhido entre as contas com papel escritor e vaga no pool; --escritor imprime só ela (75 = pool cheio).
# escolha=ritmo (padrão): maior ritmo entre as medidas, depois as sem medidor na ordem do registro; escolha=ordem: a ordem do registro,
# com o medidor só tirando da vez quem passou do teto.
# --escritor --reserva <tag> reserva a vaga do escolhido antes do worker-start (dono provisório res-<tag>, TTL em vaga-agente.sh).
export MSYS_NO_PATHCONV=1
aqui=$(dirname "$0")
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT

SOLO=0; RESERVA=""; ALERTA=0
while [ $# -gt 0 ]; do
  case "$1" in
    --escritor) SOLO=1 ;;
    --alerta) ALERTA=1 ;;
    --reserva)
      [ $# -ge 2 ] || { echo 'uso: limites.sh [--escritor [--reserva <tag>]] | --alerta' >&2; exit 2; }
      RESERVA="res-$2"; shift ;;
    *) echo 'uso: limites.sh [--escritor [--reserva <tag>]] | --alerta' >&2; exit 2 ;;
  esac
  shift
done
[ -n "$RESERVA" ] && [ $SOLO = 0 ] && { echo 'uso: limites.sh [--escritor [--reserva <tag>]] | --alerta' >&2; exit 2; }

source "$aqui/contas.sh" || exit 2
# Registro inválido: a tabela ainda mede as contas padrão; a escolha cai no erro do pool, que lê o mesmo registro.
contas_carrega 2>/dev/null || { CONTAS_CONF=/dev/null; contas_carrega; }

instalada() { # O binário da conta (sem as atribuições VAR=) está no PATH e a pasta de config, se houver, existe.
  local b cfg
  for b in $(conta_campo "$1" comando); do [[ "$b" == *=* ]] || break; done
  # Conta Claude é medida pelo próprio claude: o atalho dela (ex.: função claude-b do .bashrc) não existe aqui.
  [ "$(conta_campo "$1" agente)" = claude ] && b=claude
  command -v "$b" >/dev/null 2>&1 || return 1
  cfg=$(conta_campo "$1" config)
  [ -z "$cfg" ] || [ -d "$cfg" ]
}

: > "$tmp/medidas"; n=0; precisa_orca=0
for c in $CONTAS; do
  med=$(conta_campo "$c" medidor)
  [ "$med" = - ] && continue
  instalada "$c" || continue
  printf '%s %s %s\n' "$n" "$c" "$med" >> "$tmp/medidas"
  case "$med" in orca:*) precisa_orca=1 ;; esac
  n=$((n + 1))
done
if [ "$precisa_orca" = 1 ]; then
  # Uma consulta ao Orca para todas as contas medidas por ele.
  "${ORCA_CMD:-${ORCA_CLI_COMMAND:-orca}}" account list --json > "$tmp/orca.json" 2>/dev/null || : > "$tmp/orca.json"
  export MEDIDOR_ORCA_JSON="$tmp/orca.json"
fi
while read -r i c med; do
  case "$med" in
    claude) CONTA_CONFIG=$(conta_campo "$c" config) bash "$aqui/medidores/claude.sh" "$c" > "$tmp/m.$i" 2>&1 & ;;
    orca:*) bash "$aqui/medidores/orca.sh" "$c" "${med#orca:}" > "$tmp/m.$i" 2>&1 & ;;
  esac
done < "$tmp/medidas"
wait

# Saída do medidor: linhas humanas e a de máquina (#cand). Só awk: a seleção roda com o PATH mínimo.
humanas() { awk '!/^#/' "$1" 2>/dev/null; }
cand() { awk '/^#cand / { print; exit }' "$1" 2>/dev/null; }
# Qualquer janela acima de 80%: sai com 3; com $1=1 imprime só as linhas das contas acima do limite.
alerta() {
  local i c med cu lo bad=0
  while read -r i c med; do
    read -r _ _ cu lo _ <<< "$(cand "$tmp/m.$i")"
    [ -n "$lo" ] || continue
    if [ "$cu" -gt 80 ] || [ "$lo" -gt 80 ]; then
      bad=1; [ "$1" = 1 ] && humanas "$tmp/m.$i"
    fi
  done < "$tmp/medidas"
  [ "$bad" = 0 ] || return 3
}
[ "$ALERTA" = 1 ] && { alerta 1; exit $?; }
if [ $SOLO = 0 ]; then
  while read -r i _; do humanas "$tmp/m.$i"; done < "$tmp/medidas"
fi

bash "$aqui/vaga-agente.sh" livres > "$tmp/pool"
rc=$?
if [ "$rc" != 0 ]; then
  [ $SOLO = 1 ] && exit "$rc"
  echo "AVISO: erro do pool (status $rc); seleção de escritor indisponível" >&2
else
agora=$(date +%s)
# Candidatos na ordem do registro: "conta m curta longa reset dur" (medida) ou "conta s" (sem medidor).
: > "$tmp/cand"
for c in $CONTAS; do
  conta_tem_papel "$c" escritor || continue
  instalada "$c" || continue
  if [ "$(conta_campo "$c" medidor)" = - ]; then echo "$c s" >> "$tmp/cand"; continue; fi
  i=$(awk -v c="$c" '$2 == c { print $1 }' "$tmp/medidas")
  linha=$(cand "$tmp/m.$i"); [ -n "$linha" ] || continue
  read -r _ _ cu lo ep dur <<< "$linha"
  echo "$c m $cu $lo $ep $dur" >> "$tmp/cand"
done

# Medida elegível: curta <= 80 e longa <= 80, ou <= 95 com reset da longa em < 24 h. Ritmo = (100 - longa) / (100 * fração
# restante da longa); fração = horas até o reset / duração da janela, em [0,01, 1]; reset ilegível vira fração 1.
n=0; cand_q=0; cand_vaga=0
{ read -r _ cand_q cand_vaga
  while read -r c r g h t; do
    eleg_c[$n]=$c; eleg_r[$n]=$r; eleg_g[$n]=$g; eleg_h[$n]=$h; eleg_t[$n]=$t; n=$((n + 1))
  done
} < <(awk -v agora="$agora" -v escolha="$ESCOLHA" '
  FNR == NR { split($2, v, "/"); livre[$1] = (v[2] == 0 || v[1] > 0); next }
  { q++; k = $1; if (!livre[k]) next
    tem_vaga = 1
    if ($2 == "s") { o++; oc[o] = k; ot[o] = "s"; next }
    curta = $3; longa = $4; h = -1; if ($5 != "-") h = ($5 - agora) / 3600
    if (curta > 80) next
    if (!(longa <= 80 || (longa <= 95 && h >= 0 && h < 24))) next
    frac = 1; if (h >= 0) { frac = h / $6; if (frac < 0.01) frac = 0.01; else if (frac > 1) frac = 1 }
    o++; oc[o] = k; ot[o] = "m"; orr[o] = (100 - longa) / (100 * frac); og[o] = 100 - longa; oh[o] = h
  }
  END {
    printf "info %d %d\n", q + 0, tem_vaga + 0
    if (escolha == "ordem") { for (i = 1; i <= o; i++) emite(i); exit }
    # ritmo: as medidas por ritmo (estável na ordem do registro), depois as sem medidor na ordem do registro.
    for (i = 1; i <= o; i++) if (ot[i] == "m") { m++; idx[m] = i }
    for (i = 2; i <= m; i++) for (j = i; j > 1 && orr[idx[j - 1]] < orr[idx[j]]; j--) { t = idx[j - 1]; idx[j - 1] = idx[j]; idx[j] = t }
    for (i = 1; i <= m; i++) emite(idx[i])
    for (i = 1; i <= o; i++) if (ot[i] == "s") emite(i)
  }
  function emite(i) {
    if (ot[i] == "s") printf "%s 0 0 -1 s\n", oc[i]
    else printf "%s %.1f %d %.1f m\n", oc[i], orr[i], og[i], oh[i]
  }' "$tmp/pool" "$tmp/cand")
rc=0
if [ "$n" -gt 0 ]; then
  i=0; sufixo=""
  if [ -n "$RESERVA" ]; then
    i=-1
    for ((j = 0; j < n; j++)); do
      if bash "$aqui/vaga-agente.sh" pega "${eleg_c[$j]}" "$RESERVA" 2>/dev/null; then
        # Conta ilimitada não cria vaga: sem sufixo, não há o que trocar depois do start.
        i=$j; grep -qxF "$RESERVA" "$HOME/.cache/agentes/${eleg_c[$j]}".lock*/dispatch 2>/dev/null && sufixo=" reserva $RESERVA"
        break
      fi
    done
    if [ "$i" -lt 0 ]; then echo "escritor: nenhum (pool cheio)"; exit 75; fi
  fi
  if [ "${eleg_t[$i]}" = s ]; then
    printf 'escritor: %s (sem medidor)%s\n' "${eleg_c[$i]}" "$sufixo"
  elif [ "$(awk -v h="${eleg_h[$i]}" 'BEGIN { print (h >= 0) ? 1 : 0 }')" = 1 ]; then
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
alerta 0

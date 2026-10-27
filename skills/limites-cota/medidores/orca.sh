#!/usr/bin/env bash
# Medidor Orca: rateLimits.<fornecedor> do `orca account list --json` (claude, codex, antigravity, kimi, minimax, cursor, grok, zcode, gemini, opencodeGo…).
# Uso: orca.sh <conta> <fornecedor> → linha humana e "#cand <conta> <curta%> <longa%> <reset_epoch|-> <duração_h>".
# MEDIDOR_ORCA_JSON aponta a resposta já lida: o limites.sh consulta o Orca uma vez para todas as contas.
conta=$1 fornecedor=$2
# python3 no Windows pode ser o atalho da Microsoft Store, que não executa: vale o primeiro que rodar.
for py in python3 python ""; do [ -n "$py" ] && "$py" -c '' 2>/dev/null && break; done
[ -n "$py" ] || { echo "$conta: ilegível (sem python)"; exit 0; }
json=${MEDIDOR_ORCA_JSON:-}
if [ -z "$json" ]; then
    json=$(mktemp); trap 'rm -f "$json"' EXIT
    "${ORCA_CMD:-${ORCA_CLI_COMMAND:-orca}}" account list --json > "$json" 2>/dev/null || : > "$json"
fi
# Com MSYS_NO_PATHCONV (o limites.sh exporta) o python do Windows não abriria o caminho POSIX.
command -v cygpath >/dev/null 2>&1 && json=$(cygpath -w "$json")
MED_ARQ="$json" MED_CONTA="$conta" MED_FORNECEDOR="$fornecedor" "$py" -I - <<'EOF'
import json, os, sys, time
sys.stdout.reconfigure(encoding="utf-8")
conta, forn = os.environ["MED_CONTA"], os.environ["MED_FORNECEDOR"]
try:
    rl = (json.load(open(os.environ["MED_ARQ"], encoding="utf-8")).get("result") or {}).get("rateLimits") or {}
except (ValueError, OSError):
    print(f"{conta}: ilegível (Orca fora do ar)"); sys.exit(0)
d = rl.get(forn)
if not isinstance(d, dict):
    print(f"{conta}: ilegível (sem dados do Orca para {forn})"); sys.exit(0)
if d.get("status") != "ok":
    print(f"{conta}: ilegível ({d.get('error') or d.get('status') or 'sem dados'})"); sys.exit(0)

def janela(nome, w):
    if not isinstance(w, dict) or w.get("usedPercent") is None: return None
    return {"nome": nome, "uso": int(w["usedPercent"]), "min": w.get("windowMinutes") or 0, "zera": w.get("resetsAt")}

def texto(j, curta):
    rot = j["nome"] if j["nome"] in ("semana", "mês") else f"{max(1, round(j['min'] / 60))}h"
    s = f"{rot} {j['uso']}%"
    if j["zera"]:
        s += time.strftime(" (zera %H:%M)" if curta else " (zera %Y-%m-%d %H:%M)", time.localtime(j["zera"] / 1000))
    return s

def grupos():
    # antigravity: um par de janelas por grupo de modelos, em buckets; os demais: session + weekly/monthly.
    if d.get("buckets"):
        g = {}
        for b in d["buckets"]:
            nome = "semana" if (b.get("windowMinutes") or 0) >= 10080 else "curta"
            g.setdefault(b.get("group") or "?", {})[nome] = janela(nome, b)
        return [(f"{conta} {k}", v.get("curta"), v.get("semana")) for k, v in g.items()]
    longa = janela("semana", d.get("weekly")) or janela("mês", d.get("monthly"))
    return [(conta, janela("curta", d.get("session")), longa)]

pior = None
for rotulo, curta, longa in grupos():
    if not curta and not longa: continue
    partes = [texto(j, j is curta) for j in (curta, longa) if j]
    print(f"{rotulo}: " + " · ".join(partes))
    longa = longa or curta; curta = curta or longa
    cand = (curta["uso"], longa["uso"], int(longa["zera"] / 1000) if longa["zera"] else "-", max(1, round(longa["min"] / 60)) if longa["min"] else 168)
    if pior is None or max(cand[0], cand[1]) > max(pior[0], pior[1]): pior = cand
if pior is None:
    print(f"{conta}: ilegível (sem janelas do Orca para {forn})"); sys.exit(0)
print("#cand %s %s %s %s %s" % ((conta,) + pior))
EOF

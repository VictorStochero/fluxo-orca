#!/usr/bin/env bash
# Relatório só leitura; --portao N retorna 75 com pouca RAM, 2 quando a leitura é inconclusiva.
modo=relatorio; minimo=0
if [ "${1:-}" = --portao ] && [ $# = 2 ]; then
    modo=portao; minimo=$2
    [[ "$minimo" =~ ^[0-9]+([.][0-9]+)?$ ]] || exit 2
    [[ "$minimo" =~ ^0+([.]0+)?$ ]] && exit 0
elif [ $# != 0 ]; then echo 'uso: orca-ram.sh [--portao <GB>]' >&2; exit 2; fi
for py in python3 python ""; do [ -n "$py" ] && "$py" -c '' 2>/dev/null && break; done
[ -n "$py" ] || { echo 'AVISO: memória indisponível (sem Python)' >&2; exit 2; }
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
w() { if command -v cygpath >/dev/null 2>&1; then cygpath -w "$1"; else printf '%s' "$1"; fi; }
orca_cmd=${ORCA_CMD:-${ORCA_CLI_COMMAND:-orca}}
"$orca_cmd" diagnostics memory --json > "$tmp/memoria" 2>/dev/null || : > "$tmp/memoria"
RAM_ARQ="$(w "$tmp/memoria")" RAM_MODO="$modo" RAM_MIN="$minimo" "$py" -I - <<'EOF'
import json, math, os, sys
sys.stdout.reconfigure(encoding="utf-8")
sys.stderr.reconfigure(encoding="utf-8")
try:
    d = json.load(open(os.environ["RAM_ARQ"], encoding="utf-8"))
    disponivel = d["result"]["host"]["availableMemory"]
    if d.get("ok") is False or isinstance(disponivel, bool) or not isinstance(disponivel, (int, float)) or not math.isfinite(disponivel) or disponivel < 0: raise ValueError()
except (OSError, ValueError, KeyError, TypeError):
    print("AVISO: memória indisponível no Orca; portão não bloqueia", file=sys.stderr); sys.exit(2)
gb = disponivel / 1073741824
texto = f"{gb:.1f}".replace(".", ",")
if os.environ["RAM_MODO"] == "portao":
    if gb < float(os.environ["RAM_MIN"]):
        print(f"POOL CHEIO: memória ({texto} GB livres, mínimo {os.environ['RAM_MIN']})", file=sys.stderr); sys.exit(75)
else:
    print(f"RAM disponível: {texto} GB")
EOF
rc=$?
[ "$modo" = portao ] && exit "$rc"
[ "$rc" = 0 ] || exit "$rc"
: > "$tmp/workers"; cursor=""
while :; do
    args=(); [ -z "$cursor" ] || args=(--cursor "$cursor")
    "$orca_cmd" orchestration worker-list "${args[@]}" --json > "$tmp/pagina" 2>/dev/null || { echo 'AVISO: workers indisponíveis' >&2; break; }
    cat "$tmp/pagina" >> "$tmp/workers"; printf '\n' >> "$tmp/workers"
    proximo=$(RAM_ARQ="$(w "$tmp/pagina")" "$py" -I - <<'EOF'
import json, os, sys
sys.stderr.reconfigure(encoding="utf-8")
try:
    d = json.load(open(os.environ["RAM_ARQ"], encoding="utf-8"))
    if d.get("ok") is False: raise ValueError()
    p = d.get("result", {}).get("page") or {}
    if p.get("hasMore"):
        if not p.get("nextCursor"): raise ValueError()
        print(p["nextCursor"])
except (OSError, ValueError, TypeError, AttributeError):
    print("AVISO: lista de workers ilegível", file=sys.stderr); sys.exit(2)
EOF
    )
    [ $? = 0 ] && [ -n "$proximo" ] && [ "$proximo" != "$cursor" ] || break
    cursor=$proximo
done
RAM_ARQ="$(w "$tmp/memoria")" RAM_WORKERS="$(w "$tmp/workers")" "$py" -I - <<'EOF'
import json, os, sys
sys.stdout.reconfigure(encoding="utf-8")
d = json.load(open(os.environ["RAM_ARQ"], encoding="utf-8"))["result"]
txt = open(os.environ["RAM_WORKERS"], encoding="utf-8").read(); ws = []; i = 0
while i < len(txt):
    while i < len(txt) and txt[i].isspace(): i += 1
    if i >= len(txt): break
    try: doc, i = json.JSONDecoder().raw_decode(txt, i)
    except ValueError: break
    if not isinstance(doc, dict): break
    ws += (doc.get("result") or {}).get("workers") or []
terminais = {"completed", "failed", "stopped", "abandoned"}
ativos = {w.get("agentTerminalHandle") for w in ws if w.get("dispatchStatus") not in terminais and w.get("agentTerminalHandle")}
ociosos = {wt.get("worktreeId"): {s.get("sessionId") for s in wt.get("sessions", []) if s.get("cpu") == 0} for wt in d.get("worktrees", [])}
retidos = {}
for w in ws:
    if w.get("dispatchStatus") not in terminais or w.get("terminalState") != "retained": continue
    if w.get("agentTerminalHandle") in ativos: continue
    recurso = w.get("resource") or {}; proj = w.get("projection") or {}
    wt = recurso.get("worktreeId") or (proj.get("workspace") or {}).get("id")
    encarnacao = recurso.get("endpointIncarnation")
    if encarnacao and encarnacao.rsplit(":", 1)[0] not in ociosos.get(wt, set()): continue
    retidos.setdefault(wt, set()).add(w["dispatchId"])
worktrees = d.get("worktrees") or []
worktrees.sort(key=lambda w: sum(s.get("memory", 0) for s in w.get("sessions", []) if s.get("cpu") == 0), reverse=True)
for wt in worktrees:
    sessoes = [s for s in wt.get("sessions", []) if s.get("cpu") == 0]
    if not sessoes: continue
    print(f"{wt.get('worktreeName') or wt.get('worktreeId')}:")
    for s in sorted(sessoes, key=lambda s: s.get("memory", 0), reverse=True):
        gb = f"{s.get('memory', 0) / 1073741824:.1f}".replace(".", ",")
        print(f"  PID {s.get('pid')}: CPU 0 · {gb} GB")
    for dispatch in sorted(retidos.get(wt.get("worktreeId"), [])):
        print(f"  worker concluído e retido: bash ~/.cache/orca-libera.sh {dispatch}")
EOF

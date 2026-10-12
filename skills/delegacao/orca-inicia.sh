#!/usr/bin/env bash
# worker-start com saída enxuta: o recibo completo vai para ~/.cache/orca-recibos/ e só uma linha chega ao coordenador.
# Uso: bash ~/.cache/orca-inicia.sh <argumentos do worker-start>   (o --json é acrescentado)
for py in python3 python ""; do [ -n "$py" ] && "$py" -c '' 2>/dev/null && break; done
[ -n "$py" ] || { echo "orca-inicia: precisa de python." >&2; exit 2; }
dir="$HOME/.cache/orca-recibos"; mkdir -p "$dir"
tmp="$dir/.recibo.$$.json"
trap 'rm -f "$tmp"' EXIT
"${ORCA_CMD:-${ORCA_CLI_COMMAND:-orca}}" orchestration worker-start "$@" --json > "$tmp" 2>&1
rc=$?
ORCA_ARQ="$tmp" ORCA_DIR="$dir" "$py" -I - <<'EOF'
import json, os, shutil, sys, time
sys.stdout.reconfigure(encoding="utf-8")
arq, pasta = os.environ["ORCA_ARQ"], os.environ["ORCA_DIR"]
txt = open(arq, encoding="utf-8", errors="replace").read()
try: doc = json.JSONDecoder().raw_decode(txt.lstrip())[0]
except ValueError: doc = None
doc = doc if isinstance(doc, dict) else {}
r = doc.get("result") or {}; d = r.get("dispatch") or {}
did = d.get("id") or d.get("dispatchId") or r.get("dispatchId")
ident = did if doc.get("ok") is not False and did else "erro"
dest = os.path.join(pasta, "%s-%s.json" % (time.strftime("%Y%m%d-%H%M%S"), os.path.basename(str(ident))))
shutil.copyfile(arq, dest)
if doc.get("ok") is False or not doc:
    e = doc.get("error") or {}
    print("erro %s: %s · recibo %s" % (e.get("code") or "?", e.get("message") or txt.strip()[:200] or "saída ilegível", dest))
else:
    s = r.get("stage") or {}; rec = r.get("recovery") or d.get("recovery")
    out = "dispatch %s · state %s · task %s" % (did or "?", d.get("state") or d.get("status") or r.get("state") or "?", d.get("taskId") or r.get("taskId") or "?")
    falha = r.get("failedStage") or d.get("failedStage") or s.get("failedStage")
    if falha: out += " · failedStage %s" % falha
    erro = r.get("lastError") or d.get("lastError")
    if erro: out += " · lastError %s" % (erro if isinstance(erro, str) else json.dumps(erro, ensure_ascii=False))
    if rec: out += " · recovery: %s" % (rec if isinstance(rec, str) else json.dumps(rec, ensure_ascii=False))
    print(out + " · recibo " + dest)
EOF
exit $rc

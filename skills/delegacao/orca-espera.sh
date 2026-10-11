#!/usr/bin/env bash
# Espera do coordenador pelos workers do Orca: sai assim que houver algo a fazer. Rodar em background
# (run_in_background) e agir sobre a saída; rearmar quando sair sem nada.
# Uso: bash ~/.cache/orca-espera.sh [--run <run_id>] [--max-min 25]
# - Cada entrega é gravada em ~/.cache/orca-entregas/<deliveryId>.json, impressa inteira e recebe ack na hora:
#   sem ack o Orca devolve sempre a mesma entrega antiga e as novas ficam presas atrás dela.
# - Heartbeat sozinho não acorda; worker_done, question, escalation e status acordam.
# - Entre esperas confere o estado real de cada worker ativo (atividade do agente, processo, último commit do
#   worktree) e sai se algum parou sem worker_done.
for py in python3 python ""; do [ -n "$py" ] && "$py" -c '' 2>/dev/null && break; done
[ -n "$py" ] || { echo "orca-espera: precisa de python." >&2; exit 2; }
run=(); max=25
while [ $# -gt 0 ]; do
    case "$1" in --run) run=(--run "$2"); shift 2 ;; --max-min) max=$2; shift 2 ;; *) echo "argumento desconhecido: $1" >&2; exit 2 ;; esac
done
dir="$HOME/.cache/orca-entregas"; mkdir -p "$dir"
fim=$(( $(date +%s) + max * 60 ))

# Imprime as mensagens da entrega; sai 0 se alguma pede ação, 1 se só heartbeat, 2 se vazia.
mostra() { ORCA_ARQ="$1" "$py" -I - <<'EOF'
import json, os, sys
sys.stdout.reconfigure(encoding="utf-8")
r = (json.load(open(os.environ["ORCA_ARQ"], encoding="utf-8")).get("result") or {})
ms = r.get("messages") or []
if not ms: sys.exit(2)
acao = False
for m in ms:
    t = m.get("type"); p = m.get("payload") or {}
    if isinstance(p, str):
        try: p = json.loads(p)
        except Exception: p = {}
    if t == "heartbeat": continue
    acao = True
    print(f"== {t} | dispatch {p.get('dispatchId') or m.get('to_handle') or '?'} | de {m.get('from_handle')} | id {m.get('id')}")
    if p.get("outcome"): print(f"   outcome: {p['outcome']}")
    print(f"   assunto: {m.get('subject')}")
    print("   " + str(m.get("body")).replace("\n", "\n   "))
sys.exit(0 if acao else 1)
EOF
}

# Estado real dos workers não concluídos; imprime todos e sai 0 se algum precisa de atenção.
# Atividade do agente no Orca: working | blocked | waiting | done (done = o turno terminou).
confere() {
    orca orchestration worker-list "${run[@]}" --json > "$dir/.workers.json" 2>/dev/null
    ORCA_ARQ="$dir/.workers.json" "$py" -I - <<'EOF'
import json, os, subprocess, sys
sys.stdout.reconfigure(encoding="utf-8")
try: ws = json.load(open(os.environ["ORCA_ARQ"], encoding="utf-8"))["result"]["workers"]
except Exception: sys.exit(1)
alerta = False
for w in ws:
    if w.get("dispatchStatus") in ("completed", "failed", "cancelled", "abandoned"): continue
    p = w.get("projection") or {}; st = p.get("stage") or {}; vida = (p.get("liveness") or {}).get("verdict")
    pasta = (p.get("workspace") or {}).get("id", "").split("::")[-1]
    commit = ""
    if pasta:
        commit = subprocess.run(["git", "-C", pasta, "log", "-1", "--format=%h %cr: %s"], capture_output=True, text=True, encoding="utf-8").stdout.strip()
    atividade = st.get("activity")
    linha = "%s %s/%s vida=%s %s | último commit: %s" % (w["dispatchId"], st.get("worker"), atividade, vida, pasta.split("/")[-1], commit or "-")
    motivo = ""
    if vida == "exited":
        motivo = "o processo do agente encerrou sem worker_done: recovery (worker-show, worker-stop ou worker-abandon)"
    elif atividade in ("done", "waiting", "blocked"):
        motivo = "agente parado sem worker_done: ler com worker-read e cobrar com send --to dispatch:%s" % w["dispatchId"]
    if motivo:
        alerta = True
        print("!! " + linha + "\n   " + motivo)
    else:
        print("   " + linha)
sys.exit(0 if alerta else 1)
EOF
}

while [ "$(date +%s)" -lt "$fim" ]; do
    tmp="$dir/.ultima.json"
    orca orchestration check "${run[@]}" --wait --types "worker_done,escalation,question,status" --timeout-ms 120000 --json > "$tmp" 2>/dev/null
    entrega=$(grep -o '"deliveryId": *"[^"]*"' "$tmp" | head -1 | cut -d'"' -f4)
    if [ -n "$entrega" ]; then
        cp "$tmp" "$dir/$entrega.json"
        mostra "$tmp"; r=$?
        orca orchestration check "${run[@]}" --ack "$entrega" --json >/dev/null 2>&1
        [ $r = 0 ] && { echo "(entrega $entrega com ack; cópia em $dir/$entrega.json)"; confere; exit 0; }
        continue
    fi
    grep -q '"ok": *false' "$tmp" && { echo "check falhou:"; cat "$tmp"; exit 3; }
    echo "--- $(date +%H:%M) sem mensagem; estado real:"
    confere && exit 0
done
echo "Sem novidade em $max min. Rearmar: bash ~/.cache/orca-espera.sh ${run[*]}"

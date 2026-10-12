#!/usr/bin/env bash
# Uma linha com a cota do Codex (janela de 5 h e semana, cada uma com o zera em hora local), lida do app-server local (account/rateLimits/read).
# python3 no Windows pode ser o atalho da Microsoft Store, que não executa: vale o primeiro que rodar.
for py in python3 python ""; do [ -n "$py" ] && "$py" -c '' 2>/dev/null && break; done
[ -n "$py" ] || { echo "codex: sem python"; exit 2; }
cd "${TMP:-/tmp}" && "$py" -I - <<'EOF'
import json, shutil, subprocess, sys, time
sys.stdout.reconfigure(encoding="utf-8")
p = subprocess.Popen([shutil.which("codex"), "app-server"], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                     stderr=subprocess.DEVNULL, text=True, encoding="utf-8")
def pede(i, metodo, params=None):
    p.stdin.write(json.dumps({"id": i, "method": metodo, **({"params": params} if params else {})}) + "\n"); p.stdin.flush()
    for linha in p.stdout:
        m = json.loads(linha)
        if m.get("id") == i: return m.get("result")
try:
    pede(1, "initialize", {"clientInfo": {"name": "limites", "version": "1"}})
    p.stdin.write('{"method":"initialized"}\n'); p.stdin.flush()
    r = (pede(2, "account/rateLimits/read") or {}).get("rateLimits") or {}
finally:
    p.kill()
s, w = r.get("primary"), r.get("secondary")
if not s:
    print("codex: cota ilegível (rode codex login)"); sys.exit(2)
zera = time.strftime("%H:%M", time.localtime(s["resetsAt"]))
zera_w = f" (zera {time.strftime('%Y-%m-%d %H:%M', time.localtime(w['resetsAt']))})" if w and w.get("resetsAt") else ""
print(f"codex: 5h {s['usedPercent']}% (zera {zera}) · semana {(w or {}).get('usedPercent', 0)}%{zera_w}")
EOF

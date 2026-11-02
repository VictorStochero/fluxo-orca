#!/usr/bin/env bash
# Estado local da máquina em JSON (só leitura): painel.sh --json. Alimenta o painel do plugin do Orca (orca-plugin/).
# Nunca mede cota: lê só ~/.cache/agentes/medida.<conta>.
uso='uso: painel.sh --json'
[ "${1:-}" = --json ] && [ $# -eq 1 ] || { echo "$uso" >&2; exit 2; }
for py in python3 python ""; do [ -n "$py" ] && "$py" -c '' 2>/dev/null && break; done
[ -n "$py" ] || { echo 'AVISO: painel indisponível (sem Python)' >&2; exit 2; }
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
w() { if command -v cygpath >/dev/null 2>&1; then cygpath -w "$1"; else printf '%s' "$1"; fi; }
cache=$HOME/.cache
orca_cmd=${ORCA_CMD:-${ORCA_CLI_COMMAND:-orca}}
orca_exe=$(command -v "$orca_cmd" 2>/dev/null)

# Só o que exige kill -0 do bash fica aqui, com builtins (cada fork custa centenas de ms no Windows); o resto é Python.
coleta_travas() {
    local d t fila vaga pid viva dono
    : > "$tmp/travas"
    for d in "$cache"/gs-teste*.lock[0-9]*; do
        [ -d "$d" ] || continue
        t=${d##*/}; fila=${t%.lock*}; fila=${fila#gs-teste}; fila=${fila#-}; vaga=${t##*.lock}
        [ -n "$fila" ] || fila=3306
        pid=''; dono=''; viva=false
        { read -r pid < "$d/pid"; } 2>/dev/null; { read -r dono < "$d/dono"; } 2>/dev/null
        [[ "$pid" =~ ^[0-9]+$ ]] || pid=''
        [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null && viva=true
        dono=${dono//$'\t'/ }; dono=${dono%$'\r'}
        printf '%s\t%s\t%s\t%s\t%s\n' "$fila" "$vaga" "$pid" "$viva" "$dono" >> "$tmp/travas"
    done
}

coleta_travas
PAINEL_TMP="$(w "$tmp")" PAINEL_HOME="$(w "$HOME")" PAINEL_ORCA="$([ -n "$orca_exe" ] && w "$orca_exe")" \
PAINEL_FILA_MODO="${FILA_TESTE_FILA:-${GS_TESTE_FILA:-recurso}}" \
PAINEL_FILA_VAGAS="${FILA_TESTE_VAGAS:-${GS_TESTE_VAGAS:-2}}" \
PAINEL_FILA_VAGAS_PROJETO="${FILA_TESTE_VAGAS_PROJETO:-${GS_TESTE_VAGAS_PROJETO:-1}}" \
PAINEL_FILA_TETO="${FILA_TESTE_TETO:-${GS_TESTE_TETO:-3}}" \
"$py" -I - <<'EOF'
import filecmp, glob, json, os, re, shutil, subprocess, sys, time
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime
sys.stdout.reconfigure(encoding="utf-8", newline="\n")
sys.stderr.reconfigure(encoding="utf-8", newline="\n")
E = os.environ
home = E["PAINEL_HOME"]
cache = os.path.join(home, ".cache")
CONF_AGENTES = os.path.join(home, ".claude", "agentes.conf")
tmp = E["PAINEL_TMP"]

def le(caminho):
    try:
        with open(caminho, encoding="utf-8", errors="replace") as f: return f.read()
    except OSError: return ""

def inteiro(v, padrao):
    try: return int(v)
    except (TypeError, ValueError): return padrao

def orca_json(*args):
    exe = E.get("PAINEL_ORCA")
    if not exe: return None
    try:
        with open(exe, "rb") as f: script = f.read(2) == b"#!"
        cmd = ([shutil.which("bash") or "bash", exe] if script else [exe]) + list(args)
        # Sem o handle do terminal: com ele o worker-list fica restrito ao run vinculado ao coordenador.
        env = {k: v for k, v in E.items() if k != "ORCA_TERMINAL_HANDLE"}
        r = subprocess.run(cmd, capture_output=True, timeout=20, stdin=subprocess.DEVNULL, env=env)
        d = json.loads(r.stdout.decode("utf-8", "replace"))
        return d if r.returncode == 0 and isinstance(d, dict) and d.get("ok") is not False else None
    except (OSError, ValueError, subprocess.SubprocessError): return None

TERMINAIS = {"completed", "failed", "stopped", "abandoned"}

def lista_workers():
    paginas, cursor = [], None
    for _ in range(10):
        # --full: sem ele o worker-list do Orca 1.4.246 omite dispatchStatus, agentTerminalHandle, projection e resource.
        d = orca_json("orchestration", "worker-list", *(["--cursor", cursor] if cursor else []), "--json", "--full")
        if d is None: break
        paginas.append(d)
        p = (d.get("result") or {}).get("page") or {}
        # Histórico vem do mais novo ao mais antigo (milhares): para na primeira página sem dispatch em andamento.
        if not any(x.get("dispatchStatus") not in TERMINAIS for x in (d.get("result") or {}).get("workers") or []): break
        proximo = p.get("nextCursor") if p.get("hasMore") else None
        if not proximo or proximo == cursor: break
        cursor = proximo
    return paginas

aviso = []
# As chamadas ao Orca são independentes: em paralelo, cada processo no Windows custa quase um segundo.
with ThreadPoolExecutor(4) as ex:
    f_st = ex.submit(orca_json, "status", "--json")
    f_mem = ex.submit(orca_json, "diagnostics", "memory", "--json")
    f_runs = ex.submit(orca_json, "orchestration", "run-list", "--json")
    f_ws = ex.submit(lista_workers)
    f_ret = ex.submit(orca_json, "orchestration", "worker-list", "--terminal-state", "retained", "--json", "--full")
    st, mem, runs, paginas, ret = f_st.result(), f_mem.result(), f_runs.result(), f_ws.result(), f_ret.result()

# saúde
raiz = le(os.path.join(cache, "fluxo-orca-raiz")).strip()
raiz_w = re.sub(r"^/([A-Za-z])/", r"\1:/", raiz)
versao = None
desatualizados = []
if raiz:
    try: versao = json.loads(le(os.path.join(raiz_w, ".claude-plugin", "plugin.json"))).get("version")
    except ValueError: pass
    def difere(origem, destino):
        try: return not filecmp.cmp(origem, destino, shallow=False)
        except OSError: return True
    for s in le(os.path.join(raiz_w, "hooks", "scripts.lista")).split("\n"):
        s = s.strip()
        if s and not s.startswith("#") and difere(os.path.join(raiz_w, s), os.path.join(cache, os.path.basename(s))):
            desatualizados.append(os.path.basename(s))
    for s in sorted(glob.glob(os.path.join(raiz_w, "skills", "limites-cota", "medidores", "*.sh"))):
        if difere(s, os.path.join(cache, "medidores", os.path.basename(s))): desatualizados.append(os.path.basename(s))
orca = {"rodando": False, "versao": None}
if st:
    r = st.get("result") or {}
    orca = {"rodando": bool((r.get("app") or {}).get("running")), "versao": (r.get("runtime") or {}).get("appVersion")}
else:
    aviso.append("Orca indisponível: RAM e workers sem dados")
saude = {
    "plugin_raiz": raiz or None, "plugin_versao": versao, "scripts_desatualizados": desatualizados,
    "orca": orca, "python": sys.version.split()[0],
}

# fila
travas = []
for l in le(os.path.join(tmp, "travas")).split("\n"):
    if not l: continue
    fila, vaga, pid, viva, dono = (l.split("\t") + [""] * 5)[:5]
    m = re.match(r"^(.*?)(?: \[[^\]]*\])? desde (\d\d:\d\d:\d\d): (.*)$", dono)
    travas.append({
        "fila": fila, "vaga": inteiro(vaga, 0), "worktree": m.group(1) if m else dono or None,
        "desde": m.group(2) if m else None, "comando": m.group(3) if m else None,
        "pid": inteiro(pid, None), "viva": viva == "true",
    })
travas.sort(key=lambda t: (t["fila"], t["vaga"]))
modo_fila = E["PAINEL_FILA_MODO"]
vagas_fila = inteiro(E["PAINEL_FILA_VAGAS_PROJETO"], 1) if modo_fila == "projeto" else inteiro(E["PAINEL_FILA_VAGAS"], 2)
fila = {"modo": modo_fila, "vagas": vagas_fila, "teto": inteiro(E["PAINEL_FILA_TETO"], 3), "travas": travas}

# pool
conf = {}
conf_linhas = le(CONF_AGENTES).split("\n")
for l in conf_linhas:
    m = re.match(r"^\s*(teto|ram_min)\s*=\s*(\d+(?:\.\d+)?)\s*$", l)
    if m: conf[m.group(1)] = float(m.group(2)) if "." in m.group(2) else int(m.group(2))
agora = time.time(); contas = []; total = 0
# contas.sh leva segundos no Windows: com agentes.conf lê-se direto (padrões do contas.sh); sem ele, a saída do contas.sh lista.
conta_linhas = [l for l in conf_linhas if re.match(r"^\s*[^\s#=]+\s+\S+=", l)]
if not conta_linhas:
    try: conta_linhas = subprocess.run([shutil.which("bash") or "bash", os.path.join(cache, "contas.sh"), "lista"], capture_output=True, timeout=30, stdin=subprocess.DEVNULL).stdout.decode("utf-8", "replace").split("\n")
    except (OSError, subprocess.SubprocessError): conta_linhas = []
for l in conta_linhas:
    partes = l.split()
    if not partes: continue
    nome, c = partes[0], dict(p.split("=", 1) for p in partes[1:] if "=" in p)
    c.setdefault("agente", nome)
    if "papeis" not in c: c["papeis"] = "escritor,revisor,verificador,mecanico" if c["agente"] in ("claude", "codex", "antigravity") else ""
    c.setdefault("vagas", "1")
    ocup = []
    for d in sorted(glob.glob(os.path.join(cache, "agentes", glob.escape(nome) + ".lock[0-9]*"))):
        if not re.fullmatch(r"\d+", d.rsplit(".lock", 1)[1]): continue
        ocup.append({"dispatch": le(os.path.join(d, "dispatch")).strip() or None, "desde": le(os.path.join(d, "desde")).strip() or None})
    total += len(ocup)
    arq = os.path.join(cache, "agentes", "medida." + nome)
    cota = None
    if os.path.isfile(arq):
        linhas = le(arq).split("\n")
        curta = longa = None
        for x in linhas:
            m = re.match(r"^#cand (\S+) (\d+) (\d+)\b", x)
            if m and m.group(1) == nome: curta, longa = int(m.group(2)), int(m.group(3)); break
        cota = {"texto": linhas[0] if linhas else "", "curta": curta, "longa": longa,
                "medida_ha_min": int((agora - os.path.getmtime(arq)) // 60),
                "alerta": (curta or 0) > 80 or (longa or 0) > 80}
    contas.append({"nome": nome, "agente": c.get("agente"), "vagas": inteiro(c.get("vagas"), 0), "usadas": len(ocup),
                   "peso": inteiro(c.get("peso"), 1), "papeis": [p for p in c.get("papeis", "").split(",") if p],
                   "ocupantes": ocup, "cota": cota})
for l in conf_linhas:  # linhas "conta=N" mudam só as vagas (contas.sh)
    m = re.match(r"^\s*([A-Za-z0-9_-]+)=(\d+)\s*$", l)
    for c in contas:
        if m and c["nome"] == m.group(1): c["vagas"] = int(m.group(2))
teto = conf.get("teto", 0); ram_min = conf.get("ram_min", 0)
pool = {"teto": teto, "ram_min": ram_min, "maquina": {"usadas": total, "teto": teto}, "contas": contas}

# ram
disp = None
try: disp = round(mem["result"]["host"]["availableMemory"] / 1073741824, 1)
except (TypeError, KeyError): pass
# Mesmo critério do orca-ram.sh (sessões com CPU 0 por memória e workers concluídos retidos nelas), sem os segundos que ele leva no Windows.
rel = []
try:
    ativos = {x.get("agentTerminalHandle") for pg in paginas for x in (pg.get("result") or {}).get("workers") or [] if x.get("dispatchStatus") not in TERMINAIS}
    retidos = {}
    for x in ((ret or {}).get("result") or {}).get("workers") or []:
        if x.get("dispatchStatus") not in TERMINAIS or x.get("terminalState") != "retained" or x.get("agentTerminalHandle") in ativos: continue
        rec = x.get("resource") or {}
        wt_id = rec.get("worktreeId") or ((x.get("projection") or {}).get("workspace") or {}).get("id")
        retidos.setdefault(wt_id, []).append(((rec.get("endpointIncarnation") or "").rsplit(":", 1)[0], x.get("dispatchId")))
    for wt in sorted(mem["result"].get("worktrees") or [], key=lambda w: -sum(x.get("memory", 0) for x in w.get("sessions", []) if x.get("cpu") == 0)):
        ociosas = sorted([x for x in wt.get("sessions", []) if x.get("cpu") == 0], key=lambda x: -x.get("memory", 0))
        if not ociosas: continue
        rel.append((wt.get("worktreeName") or wt.get("worktreeId")) + ":")
        rel += ["  PID %s: CPU 0 · %.1f GB" % (x.get("pid"), x.get("memory", 0) / 1073741824) for x in ociosas]
        sessoes = {x.get("sessionId") for x in ociosas}
        rel += ["  worker concluído e retido: bash ~/.cache/orca-libera.sh " + d for s, d in sorted(retidos.get(wt.get("worktreeId"), []), key=lambda r: r[1]) if not s or s in sessoes]
except (TypeError, AttributeError): pass
ram = {"disponivel_gb": disp, "relatorio": "\n".join(rel)}

# workers
objetivos = {r.get("id"): r.get("objective") for r in ((runs or {}).get("result") or {}).get("runs") or []}
workers = []
for pagina in paginas:
    for x in (pagina.get("result") or {}).get("workers") or []:
        if x.get("dispatchStatus") in TERMINAIS: continue
        prov = x.get("projection") or {}; wt = (x.get("resource") or {}).get("worktreeId") or ""
        workers.append({
            "dispatch": x.get("dispatchId"), "task": x.get("taskId"), "run": x.get("runId"),
            "objetivo": objetivos.get(x.get("runId")), "estado": x.get("workerState"), "despacho": x.get("dispatchStatus"),
            "agente": (prov.get("provider") or {}).get("id"), "modelo": (prov.get("provider") or {}).get("model"),
            "worktree": wt.split("::", 1)[1] if "::" in wt else (wt or None),
        })

estado = {"gerado_em": datetime.now().astimezone().isoformat(timespec="seconds"), "aviso": "; ".join(aviso) or None,
          "saude": saude, "fila": fila, "pool": pool, "ram": ram, "workers": workers}
print(json.dumps(estado, ensure_ascii=False, indent=2))
EOF

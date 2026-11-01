#!/usr/bin/env bash
# Painel local só leitura: painel.sh [--json | --loop [N]]. Gera ~/.cache/painel.html (dados embutidos, sem servidor).
# Nunca mede cota: lê só ~/.cache/agentes/medida.<conta>.
modo=html; intervalo=5
case "${1:-}" in
    '') ;;
    --json) modo=json ;;
    --loop) modo=loop; intervalo=${2:-5}; [[ "$intervalo" =~ ^[1-9][0-9]*$ ]] || { echo 'uso: painel.sh [--json | --loop [N]]' >&2; exit 2; } ;;
    *) echo 'uso: painel.sh [--json | --loop [N]]' >&2; exit 2 ;;
esac
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

gera() {
    coleta_travas
    PAINEL_TMP="$(w "$tmp")" PAINEL_HOME="$(w "$HOME")" PAINEL_ORCA="$([ -n "$orca_exe" ] && w "$orca_exe")" PAINEL_MODO="$modo" PAINEL_INTERVALO="$intervalo" \
    PAINEL_FILA_MODO="${FILA_TESTE_FILA:-${GS_TESTE_FILA:-recurso}}" \
    PAINEL_FILA_VAGAS="${FILA_TESTE_VAGAS:-${GS_TESTE_VAGAS:-2}}" \
    PAINEL_FILA_VAGAS_PROJETO="${FILA_TESTE_VAGAS_PROJETO:-${GS_TESTE_VAGAS_PROJETO:-1}}" \
    PAINEL_FILA_TETO="${FILA_TESTE_TETO:-${GS_TESTE_TETO:-3}}" \
    "$py" -I - <<'EOF'
import glob, json, os, re, sys, time
from datetime import datetime
sys.stdout.reconfigure(encoding="utf-8")
E = os.environ
tmp, home = E["PAINEL_TMP"], E["PAINEL_HOME"]
cache = os.path.join(home, ".cache")

def le(caminho):
    try:
        with open(caminho, encoding="utf-8", errors="replace") as f: return f.read()
    except OSError: return ""

def jle(caminho):
    try:
        d = json.loads(le(caminho))
        return d if isinstance(d, dict) and d.get("ok") is not False else None
    except ValueError: return None

def inteiro(v, padrao):
    try: return int(v)
    except (TypeError, ValueError): return padrao

import filecmp, shutil, subprocess
from concurrent.futures import ThreadPoolExecutor

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
        d = orca_json("orchestration", "worker-list", *(["--cursor", cursor] if cursor else []), "--json")
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
    f_ret = ex.submit(orca_json, "orchestration", "worker-list", "--terminal-state", "retained", "--json")
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
fila = {
    "modo": modo_fila,
    "vagas": inteiro(E["PAINEL_FILA_VAGAS_PROJETO" if modo_fila == "projeto" else "PAINEL_FILA_VAGAS"], 2),
    "teto": inteiro(E["PAINEL_FILA_TETO"], 3), "travas": travas,
}

# pool
conf = {}
for l in le(os.path.join(home, ".claude", "agentes.conf")).split("\n"):
    m = re.match(r"^\s*(teto|ram_min)\s*=\s*(\d+(?:\.\d+)?)\s*$", l)
    if m: conf[m.group(1)] = float(m.group(2)) if "." in m.group(2) else int(m.group(2))
agora = time.time(); contas = []; total = 0
# contas.sh leva segundos no Windows: com agentes.conf lê-se direto (padrões do contas.sh); sem ele, a saída do contas.sh lista.
conf_linhas = le(os.path.join(home, ".claude", "agentes.conf")).split("\n")
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
        retidos.setdefault(rec.get("worktreeId"), []).append(((rec.get("endpointIncarnation") or "").rsplit(":", 1)[0], x.get("dispatchId")))
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
terminais = TERMINAIS
workers = []
for pagina in paginas:
    for x in (pagina.get("result") or {}).get("workers") or []:
        if x.get("dispatchStatus") in terminais: continue
        prov = x.get("projection") or {}; wt = (x.get("resource") or {}).get("worktreeId") or ""
        workers.append({
            "dispatch": x.get("dispatchId"), "task": x.get("taskId"), "run": x.get("runId"),
            "objetivo": objetivos.get(x.get("runId")), "estado": x.get("workerState"), "despacho": x.get("dispatchStatus"),
            "agente": (prov.get("provider") or {}).get("id"), "modelo": (prov.get("provider") or {}).get("model"),
            "worktree": wt.split("::", 1)[1] if "::" in wt else (wt or None),
        })

estado = {"gerado_em": datetime.now().astimezone().isoformat(timespec="seconds"), "aviso": "; ".join(aviso) or None,
          "saude": saude, "fila": fila, "pool": pool, "ram": ram, "workers": workers}

if E["PAINEL_MODO"] == "json":
    print(json.dumps(estado, ensure_ascii=False, indent=2)); sys.exit(0)

DADOS = json.dumps(estado, ensure_ascii=False).replace("<", "\\u003c")
PAGINA = r'''<!doctype html>
<html lang="pt-BR"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta http-equiv="refresh" content="__N__">
<title>Painel fluxo-orca</title>
<style>
:root{--bg:#f6f7f9;--card:#fff;--tx:#1d2330;--mut:#6a7385;--bd:#dde1e8;--zebra:#f2f4f7;--ok:#1a7f4b;--aviso:#a15c00;--aviso-bg:#fff3d6;--ruim:#b42318;--ruim-bg:#fde7e4;--bar:#3b6fd4}
@media (prefers-color-scheme:dark){:root{--bg:#12151b;--card:#1a1f28;--tx:#e4e8f0;--mut:#8f99ad;--bd:#2c3340;--zebra:#202632;--ok:#4cc38a;--aviso:#f0b84a;--aviso-bg:#3a2e12;--ruim:#ff8a7a;--ruim-bg:#42201c;--bar:#6c9bff}}
*{box-sizing:border-box}
body{margin:0;padding:16px;background:var(--bg);color:var(--tx);font:14px/1.45 system-ui,-apple-system,"Segoe UI",sans-serif}
h1{font-size:18px;margin:0 0 4px}h2{font-size:15px;margin:0 0 8px}
.mut{color:var(--mut)}
section{background:var(--card);border:1px solid var(--bd);border-radius:8px;padding:12px;margin:12px 0}
.tab{overflow-x:auto}table{border-collapse:collapse;width:100%}
th,td{text-align:left;padding:4px 8px;border-bottom:1px solid var(--bd);vertical-align:top}
tbody tr:nth-child(even){background:var(--zebra)}
tr.amarelo td{background:var(--aviso-bg)}tr.vermelho td{background:var(--ruim-bg)}
.badge{display:inline-block;padding:1px 8px;border-radius:10px;border:1px solid var(--bd);font-size:12px}
.b-ok{color:var(--ok);border-color:var(--ok)}.b-aviso{color:var(--aviso);border-color:var(--aviso)}.b-ruim{color:var(--ruim);border-color:var(--ruim)}
.faixa{padding:8px;border-radius:6px;margin:6px 0}.faixa.ruim{background:var(--ruim-bg);color:var(--ruim);font-weight:600}.faixa.aviso{background:var(--aviso-bg);color:var(--aviso)}
.barra{display:inline-block;width:70px;height:8px;background:var(--bd);border-radius:4px;vertical-align:middle;margin-right:6px}.barra i{display:block;height:100%;background:var(--bar);border-radius:4px}
.barra.alerta i{background:var(--ruim)}
.grande{font-size:28px;font-weight:700}.grande.ruim{color:var(--ruim)}
pre{margin:8px 0 0;white-space:pre-wrap;word-break:break-word;font:12px/1.4 ui-monospace,Consolas,monospace}
code{font:12px ui-monospace,Consolas,monospace;word-break:break-all}
</style></head><body>
<h1>Painel fluxo-orca</h1><div class="mut" id="gerado"></div>
<div id="app"></div>
<script type="application/json" id="estado">__DADOS__</script>
<script>
(function(){
var S=JSON.parse(document.getElementById("estado").textContent),app=document.getElementById("app");
function el(t,a,k){var e=document.createElement(t);for(var x in(a||{}))e.setAttribute(x,a[x]);[].concat(k==null?[]:k).forEach(function(c){e.appendChild(typeof c==="object"?c:document.createTextNode(String(c)))});return e}
function nome(p){return p?String(p).replace(/[\\\/]+$/,"").split(/[\\\/]/).pop():"-"}
function sec(t,k){var s=el("section",{},[el("h2",{},t)].concat(k));app.appendChild(s);return s}
function tabela(cab,linhas){var tr=linhas.map(function(l){return el("tr",l.cls?{"class":l.cls}:{},l.c.map(function(c){return el("td",{},c)}))});
return el("div",{"class":"tab"},el("table",{},[el("thead",{},el("tr",{},cab.map(function(c){return el("th",{},c)}))),el("tbody",{},tr)]))}
function badge(t,c){return el("span",{"class":"badge b-"+c},t)}
document.getElementById("gerado").textContent="Gerado em "+S.gerado_em;
if(S.aviso)app.appendChild(el("div",{"class":"faixa aviso"},S.aviso));
var h=S.saude,d=h.scripts_desatualizados;
sec("Saúde",[el("div",{},["Plugin fluxo-orca ",el("b",{},h.plugin_versao||"?")," · Orca ",h.orca.rodando?badge("rodando "+(h.orca.versao||""),"ok"):badge("fora do ar","ruim")," · Python "+h.python]),
d.length?el("div",{"class":"faixa ruim"},"Scripts desatualizados em ~/.cache: "+d.join(", ")):el("div",{"class":"mut"},"scripts em dia")]);
var f=S.fila;
sec("Fila de testes",[el("div",{"class":"mut"},"modo "+f.modo+" · "+f.vagas+" vagas por fila · teto "+f.teto),
f.travas.length?tabela(["fila","vaga","worktree","desde","comando","pid","viva"],f.travas.map(function(t){return{cls:t.viva?"":"amarelo",c:[t.fila,t.vaga,el("span",{title:t.worktree||""},nome(t.worktree)),t.desde||"-",el("code",{},t.comando||"-"),t.pid==null?"-":t.pid,t.viva?"sim":"não"]}})):el("div",{"class":"mut"},"nenhuma trava")]);
var p=S.pool;
sec("Pool de agentes",[el("div",{"class":"mut"},"máquina "+p.maquina.usadas+"/"+(p.maquina.teto||"∞")+" · ram_min "+p.ram_min+" GB"),
tabela(["conta","agente","vagas","peso","papéis","cota curta/longa","medida há"],p.contas.map(function(c){var q=c.cota;
function bar(v){return v==null?"-":el("span",{},[el("span",{"class":"barra"+(v>80?" alerta":"")},el("i",{style:"width:"+Math.min(v,100)+"%"})),v+"%"])}
return{cls:q&&q.alerta?"vermelho":"",c:[c.nome,c.agente||"-",c.usadas+"/"+(c.vagas||"∞"),c.peso,c.papeis.join(", ")||"-",
q?el("span",{title:q.texto},[bar(q.curta)," / ",bar(q.longa)]):"sem medida",q?q.medida_ha_min+" min":"-"]}}))]);
var r=S.ram,baixa=r.disponivel_gb!=null&&r.disponivel_gb<p.ram_min;
sec("RAM",[el("div",{"class":"grande"+(baixa?" ruim":"")},r.disponivel_gb==null?"indisponível":r.disponivel_gb+" GB disponíveis"),r.relatorio?el("pre",{},r.relatorio):""]);
sec("Workers",[S.workers.length?tabela(["dispatch","agente/modelo","estado","worktree","objetivo do run"],S.workers.map(function(x){
return{c:[el("code",{},x.dispatch||"-"),(x.agente||"-")+(x.modelo?" / "+x.modelo:""),badge(x.estado||"?",x.estado==="ready"?"ok":"aviso"),el("span",{title:x.worktree||""},nome(x.worktree)),x.objetivo||"-"]}})):el("div",{"class":"mut"},"nenhum worker ativo")]);
})();
</script></body></html>'''
html = PAGINA.replace("__N__", E["PAINEL_INTERVALO"]).replace("__DADOS__", DADOS)
alvo = os.path.join(cache, "painel.html")
os.makedirs(cache, exist_ok=True)
novo = "%s.%d" % (alvo, os.getpid())  # por processo: --loop e geração avulsa podem coincidir
with open(novo, "w", encoding="utf-8", newline="\n") as f: f.write(html)
os.replace(novo, alvo)
print(alvo)
EOF
}

if [ "$modo" = loop ]; then
    while :; do gera >/dev/null; sleep "$intervalo"; done
fi
gera

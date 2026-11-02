#!/usr/bin/env bash
# Painel local do plugin do Orca (orca-plugin/): painel.sh --json | --config chave=valor ...
# --json imprime o estado da máquina (só leitura; nunca mede cota, lê só ~/.cache/agentes/medida.<conta>).
# --config é o escritor da configuração da fila (~/.claude/fila.conf) e do pool (~/.claude/agentes.conf).
uso='uso: painel.sh --json | --config chave=valor ...'
modo=json
case "${1:-}" in
    --json) [ $# -eq 1 ] || { echo "$uso" >&2; exit 2; } ;;
    --config) modo=config; [ $# -ge 2 ] || { echo "$uso" >&2; exit 2; } ;;
    *) echo "$uso" >&2; exit 2 ;;
esac
for py in python3 python ""; do [ -n "$py" ] && "$py" -c '' 2>/dev/null && break; done
[ -n "$py" ] || { echo 'AVISO: painel indisponível (sem Python)' >&2; exit 2; }
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
w() { if command -v cygpath >/dev/null 2>&1; then cygpath -w "$1"; else printf '%s' "$1"; fi; }
cache=$HOME/.cache
orca_cmd=${ORCA_CMD:-${ORCA_CLI_COMMAND:-orca}}
orca_exe=$(command -v "$orca_cmd" 2>/dev/null)
aqui=$(cd "$(dirname "$0")" && pwd)

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

[ "$modo" = config ] || coleta_travas
# Valor do ambiente por item (nome novo antes do legado GS_TESTE_*); vazio = não definido.
PAINEL_MODO="$modo" PAINEL_TMP="$(w "$tmp")" PAINEL_HOME="$(w "$HOME")" PAINEL_ORCA="$([ -n "$orca_exe" ] && w "$orca_exe")" \
PAINEL_CONTAS="$(w "$aqui/../limites-cota/contas.sh")" \
PAINEL_ENV_FILA="${FILA_TESTE_FILA:-${GS_TESTE_FILA:-}}" \
PAINEL_ENV_VAGAS="${FILA_TESTE_VAGAS:-${GS_TESTE_VAGAS:-}}" \
PAINEL_ENV_VAGAS_PROJETO="${FILA_TESTE_VAGAS_PROJETO:-${GS_TESTE_VAGAS_PROJETO:-}}" \
PAINEL_ENV_TETO="${FILA_TESTE_TETO:-${GS_TESTE_TETO:-}}" \
PAINEL_ENV_PROCESSOS="${FILA_TESTE_PROCESSOS:-${GS_TESTE_PROCESSOS:-}}" \
"$py" -X utf8 -I - "${@:2}" <<'EOF'
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

CONF_FILA = os.path.join(home, ".claude", "fila.conf")
FILA_CHAVES = {"fila.modo": "FILA_TESTE_FILA", "fila.vagas": "FILA_TESTE_VAGAS", "fila.vagas_projeto": "FILA_TESTE_VAGAS_PROJETO",
               "fila.teto": "FILA_TESTE_TETO", "fila.processos": "FILA_TESTE_PROCESSOS"}
PAPEIS = ("escritor", "revisor", "verificador", "mecanico", "segunda-opiniao", "orquestra")
# Faixas aceitas pelo --config (mínimo, máximo); o fila-teste.sh só exige inteiro >= 1.
FAIXAS = {"fila.vagas": (1, 99), "fila.vagas_projeto": (1, 99), "fila.teto": (1, 99), "fila.processos": (1, 64),
          "pool.teto": (0, 99), "pool.ram_min": (0, 1024), "vagas": (0, 99), "peso": (1, 100)}

class Erro(Exception): pass

def fila_valida(var, v):  # mesma regra do fila-teste.sh
    if var == "FILA_TESTE_FILA": return v in ("recurso", "projeto")
    return var in FILA_CHAVES.values() and re.fullmatch(r"[1-9][0-9]*", v) is not None

def le_fila_conf():
    d = {}
    for l in le(CONF_FILA).split("\n"):
        m = re.fullmatch(r"\s*(FILA_TESTE_[A-Z_]+)=(\S*)\s*", l.rstrip("\r"))
        if m and fila_valida(m.group(1), m.group(2)): d[m.group(1)] = m.group(2)
    return d

def confere(chave, v):
    """Valida e normaliza um valor de configuração; Erro se a chave ou o valor não valem."""
    inteiro_ = re.fullmatch(r"[0-9]+", v) is not None
    faixa = None
    if chave == "fila.modo": ok = v in ("recurso", "projeto")
    elif chave in FILA_CHAVES: ok = inteiro_; faixa = FAIXAS[chave]
    elif chave == "pool.teto": ok = inteiro_; faixa = FAIXAS[chave]
    elif chave == "pool.ram_min": ok = re.fullmatch(r"[0-9]+(\.[0-9]+)?", v) is not None; faixa = FAIXAS[chave]
    elif chave == "pool.escolha": ok = v in ("ritmo", "ordem")
    else:
        m = re.fullmatch(r"conta\.([a-z0-9_-]{1,32})\.(vagas|peso|papeis)", chave)
        if not m: raise Erro("chave desconhecida (%s)" % chave)
        if m.group(2) == "papeis": ok = v == "" or all(p in PAPEIS for p in v.split(","))
        else: ok = inteiro_; faixa = FAIXAS[m.group(2)]
    if ok and faixa and not faixa[0] <= float(v) <= faixa[1]: ok = False
    if not ok: raise Erro("valor inválido para %s: %s" % (chave, v or "(vazio)"))
    return str(int(v)) if inteiro_ else v

def le_bytes(caminho):
    try:
        with open(caminho, "rb") as f: return f.read()
    except OSError: return None

def grava_bytes(caminho, dados):  # atômica: .tmp + os.replace
    os.makedirs(os.path.dirname(caminho), exist_ok=True)
    novo = "%s.%d.tmp" % (caminho, os.getpid())
    with open(novo, "wb") as f: f.write(dados)
    try: os.replace(novo, caminho)
    except OSError:
        os.remove(novo); raise

def linhas_de(dados):
    return re.findall(r"[^\n]*\n|[^\n]+", (dados or b"").decode("utf-8", "surrogateescape"))

def corpo_eol(l):
    c = l.rstrip("\r\n")
    return c, l[len(c):]

def insere(L, i, linha):  # i=None acrescenta ao fim, garantindo a quebra de linha da última
    if i is None:
        if L and not L[-1].endswith("\n"): L[-1] += "\n"
        L.append(linha)
    else: L.insert(i, linha)

def edita_chaves(L, chave, valor, antes=None):
    """Troca a linha `chave=` (ou acrescenta); `antes` devolve o índice de inserção."""
    padrao = re.compile(r"\s*%s\s*=" % re.escape(chave))
    achou = False
    for i, l in enumerate(L):
        c, eol = corpo_eol(l)
        if padrao.match(c): L[i] = "%s=%s%s" % (chave, valor, eol); achou = True
    if not achou: insere(L, antes() if antes else None, "%s=%s\n" % (chave, valor))

def edita_agentes(L, chaves):
    L = list(L)
    def primeira_conta():
        for i, l in enumerate(L):
            if re.match(r"\s*[a-z0-9_-]+\s+\S", l): return i
    for k, v in chaves.items():
        if k.startswith("pool."): edita_chaves(L, k[5:], v, primeira_conta)
    for k, v in chaves.items():
        m = re.fullmatch(r"conta\.(.+)\.(vagas|peso|papeis)", k)
        if not m: continue
        nome, campo = m.groups()
        i = next((j for j, l in enumerate(L) if re.match(r"\s*%s\s+\S" % re.escape(nome), l)), None)
        if i is None: raise Erro("conta inexistente no agentes.conf: %s" % nome)
        c, eol = corpo_eol(L[i])
        par = re.compile(r'(^|\s)%s=("[^"]*"|[^\s"]*)' % campo)
        if par.search(c): c = par.sub(lambda x: "%s%s=%s" % (x.group(1), campo, v), c, count=1)
        else: c = "%s %s=%s" % (c.rstrip(), campo, v)
        L[i] = c + eol
        if campo == "vagas":  # a linha legada nome=N sobrescreveria o valor gravado
            L = [l for l in L if not re.fullmatch(r"\s*%s=[0-9]+\s*" % re.escape(nome), l.rstrip("\r\n"))]
    return L

def roda_contas(conf):  # valida o candidato (.tmp) antes de ele virar o agentes.conf: nenhum outro processo vê registro inválido
    sh = os.path.join(cache, "contas.sh")
    if not os.path.isfile(sh): sh = E["PAINEL_CONTAS"]
    try:
        env = dict(E, CONTAS_CONF=conf.replace("\\", "/"))
        r = subprocess.run([shutil.which("bash") or "bash", sh, "lista"], capture_output=True, timeout=60, stdin=subprocess.DEVNULL, env=env)
    except (OSError, subprocess.SubprocessError) as e:
        return "contas.sh indisponível (%s)" % e
    if r.returncode == 0: return None
    return (r.stderr.decode("utf-8", "replace").strip() or r.stdout.decode("utf-8", "replace").strip() or "contas.sh reprovou a configuração")

def aplica_config(pares):
    """Tudo ou nada: valida, o contas.sh confere o agentes.conf candidato num .tmp, e só então os arquivos são trocados. Devolve as chaves gravadas."""
    novos = {}
    for k, v in pares: novos[k] = confere(k, v.strip())
    fila = {k: v for k, v in novos.items() if k in FILA_CHAVES}
    agentes = {k: v for k, v in novos.items() if k not in FILA_CHAVES}
    novo_ag = novo_fila = None
    if agentes:
        novo_ag = "".join(edita_agentes(linhas_de(le_bytes(CONF_AGENTES)), agentes)).encode("utf-8", "surrogateescape")
    if fila:
        L = linhas_de(le_bytes(CONF_FILA))
        for k, v in fila.items(): edita_chaves(L, FILA_CHAVES[k], v)
        novo_fila = "".join(L).encode("utf-8", "surrogateescape")
    candidato = "%s.%d.tmp" % (CONF_AGENTES, os.getpid())
    try:
        if novo_ag is not None:
            os.makedirs(os.path.dirname(candidato), exist_ok=True)
            with open(candidato, "wb") as f: f.write(novo_ag)
            erro = roda_contas(candidato)
            if erro: raise Erro(erro)
        # fila.conf antes da troca do agentes.conf: falha de E/S aqui ainda não gravou nada (tudo ou nada).
        if novo_fila is not None: grava_bytes(CONF_FILA, novo_fila)
        if novo_ag is not None: os.replace(candidato, CONF_AGENTES)
    except (Erro, OSError) as e:
        try: os.remove(candidato)
        except OSError: pass
        raise e if isinstance(e, Erro) else Erro("não consegui gravar: %s" % e)
    return list(novos)

if E["PAINEL_MODO"] == "config":
    try:
        pares = []
        for a in sys.argv[1:]:
            if "=" not in a: raise Erro("argumento sem chave=valor: %s" % a)
            pares.append(tuple(a.split("=", 1)))
        for k in aplica_config(pares): print("ok " + k)
    except Erro as e:
        print("erro: %s" % e, file=sys.stderr); sys.exit(2)
    sys.exit(0)

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
with ThreadPoolExecutor(3) as ex:
    f_st = ex.submit(orca_json, "status", "--json")
    f_runs = ex.submit(orca_json, "orchestration", "run-list", "--json")
    f_ws = ex.submit(lista_workers)
    st, runs, paginas = f_st.result(), f_runs.result(), f_ws.result()

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
    aviso.append("Orca indisponível: workers sem dados")
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
# Mesma precedência do fila-teste.sh: padrão < ambiente < fila.conf (o .orca/worktree.conf do projeto vence os dois e entra em "projetos").
ITENS = (("modo", "FILA", "recurso"), ("vagas", "VAGAS", "2"), ("vagas_projeto", "VAGAS_PROJETO", "1"), ("teto", "TETO", "3"), ("processos", "PROCESSOS", "8"))
fc = le_fila_conf()
efetivo = {}
for item, suf, padrao in ITENS:
    if "FILA_TESTE_" + suf in fc: val, origem = fc["FILA_TESTE_" + suf], "fila.conf"
    elif E["PAINEL_ENV_" + suf]: val, origem = E["PAINEL_ENV_" + suf], "ambiente"
    else: val, origem = padrao, "padrao"
    efetivo[item] = {"valor": val if item == "modo" else inteiro(val, int(padrao)), "origem": origem, "projetos": []}
modo_fila = efetivo["modo"]["valor"]
fila = {"modo": modo_fila, "vagas": efetivo["vagas_projeto" if modo_fila == "projeto" else "vagas"]["valor"],
        "teto": efetivo["teto"]["valor"], "travas": travas, "config": efetivo}

def sobrescritas_dos_projetos(caminhos):
    """Lê o .orca/worktree.conf de cada projeto com worktree em uso (travas e workers) e anota o que ele sobrescreve na fila."""
    vistos = set()
    for c in sorted(set(caminhos))[:12]:
        try:
            r = subprocess.run(["git", "-C", c, "rev-parse", "--path-format=absolute", "--git-common-dir"], capture_output=True, timeout=10, stdin=subprocess.DEVNULL)
        except (OSError, subprocess.SubprocessError): continue
        if r.returncode != 0: continue
        raiz = os.path.dirname(r.stdout.decode("utf-8", "replace").strip())
        if raiz in vistos: continue
        vistos.add(raiz)
        lidos = {}
        for l in le(os.path.join(raiz, ".orca", "worktree.conf")).split("\n"):
            m = re.fullmatch(r"\s*(?:export\s+)?(FILA_TESTE|GS_TESTE)_(FILA|VAGAS|VAGAS_PROJETO|TETO|PROCESSOS)=[\"']?([A-Za-z0-9_.-]*)[\"']?\s*(?:#.*)?", l.rstrip("\r"))
            if m and (m.group(2) not in lidos or m.group(1) == "FILA_TESTE"): lidos[m.group(2)] = m.group(3)
        for item, suf, _ in ITENS:
            if suf in lidos and fila_valida("FILA_TESTE_" + suf, lidos[suf]):
                efetivo[item]["projetos"].append({"projeto": os.path.basename(raiz), "valor": lidos[suf] if item == "modo" else int(lidos[suf])})

# pool
conf = {}; escolha = "ritmo"
conf_linhas = le(CONF_AGENTES).split("\n")
for l in conf_linhas:
    m = re.match(r"^\s*(teto|ram_min)\s*=\s*(\d+(?:\.\d+)?)\s*$", l)
    if m: conf[m.group(1)] = float(m.group(2)) if "." in m.group(2) else int(m.group(2))
    m = re.match(r"^\s*escolha\s*=\s*(ritmo|ordem)\s*$", l)
    if m: escolha = m.group(1)
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
pool = {"teto": teto, "ram_min": ram_min, "escolha": escolha, "papeis_validos": list(PAPEIS), "maquina": {"usadas": total, "teto": teto}, "contas": contas}

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

sobrescritas_dos_projetos([t["worktree"] for t in travas if t["worktree"]] + [w["worktree"] for w in workers if w["worktree"]])

estado = {"gerado_em": datetime.now().astimezone().isoformat(timespec="seconds"), "aviso": "; ".join(aviso) or None,
          "saude": saude, "fila": fila, "pool": pool, "workers": workers}
print(json.dumps(estado, ensure_ascii=True, indent=2))  # ASCII puro: nenhuma codificação de console ou pipe estraga o acento
EOF

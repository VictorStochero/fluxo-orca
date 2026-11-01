#!/usr/bin/env bash
# Painel local: painel.sh [--json | --loop [N] | --servir [porta] | --config chave=valor ...].
# Sem argumento gera ~/.cache/painel.html (dados embutidos, sem servidor). --servir serve o painel em 127.0.0.1 e edita a configuração
# da fila (~/.claude/fila.conf) e do pool (~/.claude/agentes.conf); --config é o escritor dessa configuração.
# Nunca mede cota: lê só ~/.cache/agentes/medida.<conta>.
uso='uso: painel.sh [--json | --loop [N] | --servir [porta] | --config chave=valor ...]'
modo=html; intervalo=5; porta=8765
case "${1:-}" in
    '') ;;
    --json) modo=json ;;
    --loop) modo=loop; intervalo=${2:-5}; [[ "$intervalo" =~ ^[1-9][0-9]*$ ]] || { echo "$uso" >&2; exit 2; } ;;
    --servir) modo=servir; porta=${2:-8765}
        { [ $# -le 2 ] && [[ "$porta" =~ ^[0-9]{1,5}$ ]] && porta=$((10#$porta)) && [ "$porta" -ge 1 ] && [ "$porta" -le 65535 ]; } || { echo "$uso" >&2; exit 2; } ;;
    --config) modo=config; [ $# -ge 2 ] || { echo "$uso" >&2; exit 2; } ;;
    *) echo "$uso" >&2; exit 2 ;;
esac
cfg_args=("${@:2}")
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

gera() {
    local pre=
    if [ "$modo" = servir ]; then pre=exec; rm -rf "$tmp"; trap - EXIT  # exec: matar o bash mata o servidor
    elif [ "$modo" != config ]; then coleta_travas; fi
    PAINEL_TMP="$(w "$tmp")" PAINEL_HOME="$(w "$HOME")" PAINEL_ORCA="$([ -n "$orca_exe" ] && w "$orca_exe")" PAINEL_MODO="$modo" PAINEL_INTERVALO="$intervalo" \
    PAINEL_PORTA="$porta" PAINEL_SCRIPT="$(w "$aqui/$(basename "$0")")" PAINEL_CONTAS="$(w "$aqui/../limites-cota/contas.sh")" \
    PAINEL_FILA_MODO="${FILA_TESTE_FILA:-${GS_TESTE_FILA:-recurso}}" \
    PAINEL_FILA_VAGAS="${FILA_TESTE_VAGAS:-${GS_TESTE_VAGAS:-2}}" \
    PAINEL_FILA_VAGAS_PROJETO="${FILA_TESTE_VAGAS_PROJETO:-${GS_TESTE_VAGAS_PROJETO:-1}}" \
    PAINEL_FILA_TETO="${FILA_TESTE_TETO:-${GS_TESTE_TETO:-3}}" \
    PAINEL_FILA_PROCESSOS="${FILA_TESTE_PROCESSOS:-${GS_TESTE_PROCESSOS:-8}}" \
    ${pre:+exec} "$py" -I - "${cfg_args[@]}" <<'EOF'
import glob, json, os, re, sys, time
from datetime import datetime
sys.stdout.reconfigure(encoding="utf-8", newline="\n")
sys.stderr.reconfigure(encoding="utf-8", newline="\n")
E = os.environ
modo = E["PAINEL_MODO"]
home = E["PAINEL_HOME"]
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

CONF_FILA = os.path.join(home, ".claude", "fila.conf")
CONF_AGENTES = os.path.join(home, ".claude", "agentes.conf")
FILA_CHAVES = {"fila.modo": "FILA_TESTE_FILA", "fila.vagas": "FILA_TESTE_VAGAS", "fila.vagas_projeto": "FILA_TESTE_VAGAS_PROJETO",
               "fila.teto": "FILA_TESTE_TETO", "fila.processos": "FILA_TESTE_PROCESSOS"}
PAPEIS = ("escritor", "revisor", "verificador", "mecanico", "segunda-opiniao", "orquestra")

def fila_valida(var, v):  # mesma regra do fila-teste.sh
    if var == "FILA_TESTE_FILA": return v in ("recurso", "projeto")
    return var in FILA_CHAVES.values() and re.fullmatch(r"[1-9][0-9]*", v) is not None

def le_fila_conf():
    d = {}
    for l in le(CONF_FILA).split("\n"):
        m = re.fullmatch(r"\s*(FILA_TESTE_[A-Z_]+)=(\S*)\s*", l.rstrip("\r"))
        if m and fila_valida(m.group(1), m.group(2)): d[m.group(1)] = m.group(2)
    return d

PAGINA = r'''<!doctype html>
<html lang="pt-BR"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
__REFRESH__
<title>Painel fluxo-orca</title>
<style>
:root{color-scheme:light dark;--bg:#f6f7f9;--card:#fff;--tx:#1d2330;--mut:#6a7385;--bd:#dde1e8;--zebra:#f2f4f7;--ok:#1a7f4b;--aviso:#a15c00;--aviso-bg:#fff3d6;--ruim:#b42318;--ruim-bg:#fde7e4;--bar:#3b6fd4}
@media (prefers-color-scheme:dark){:root{--bg:#12151b;--card:#1a1f28;--tx:#e4e8f0;--mut:#8f99ad;--bd:#2c3340;--zebra:#202632;--ok:#4cc38a;--aviso:#f0b84a;--aviso-bg:#3a2e12;--ruim:#ff8a7a;--ruim-bg:#42201c;--bar:#6c9bff}}
*{box-sizing:border-box}
body{margin:0;padding:16px;background:var(--bg);color:var(--tx);font:14px/1.45 system-ui,-apple-system,"Segoe UI",sans-serif}
h1{font-size:18px;margin:0 0 4px}h2{font-size:15px;margin:0 0 8px}h3{font-size:13px;margin:12px 0 6px}
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
input,select,button{font:inherit;color:var(--tx);background:var(--card);border:1px solid var(--bd);border-radius:6px;padding:3px 8px}
input[type=number]{width:90px}td input[type=number]{width:70px}input[type=checkbox]{width:auto;accent-color:var(--bar)}
button{cursor:pointer}button:disabled{opacity:.6;cursor:default}
.campo{display:inline-flex;flex-direction:column;gap:2px;margin:0 12px 8px 0;font-size:12px;color:var(--mut)}
.papel{margin-right:8px;white-space:nowrap}.acoes{margin-top:6px}.msg{margin-left:10px}
.msg.ok{color:var(--ok)}.msg.ruim{color:var(--ruim)}
</style></head><body>
<h1>Painel fluxo-orca</h1><div class="mut" id="gerado"></div>
<div class="faixa aviso" id="topo" hidden></div>
<div id="app"></div>
<div id="conf"></div>
<script type="application/json" id="estado">__DADOS__</script>
<script>
(function(){
var T="__TOKEN__",S0=JSON.parse(document.getElementById("estado").textContent),app=document.getElementById("app"),conf=document.getElementById("conf");
var PAPEIS=["escritor","revisor","verificador","mecanico","segunda-opiniao","orquestra"];
function el(t,a,k){var e=document.createElement(t);for(var x in(a||{}))e.setAttribute(x,a[x]);[].concat(k==null?[]:k).forEach(function(c){e.appendChild(typeof c==="object"?c:document.createTextNode(String(c)))});return e}
function nome(p){return p?String(p).replace(/[\\\/]+$/,"").split(/[\\\/]/).pop():"-"}
function sec(t,k){var s=el("section",{},[el("h2",{},t)].concat(k));app.appendChild(s);return s}
function tabela(cab,linhas){var tr=linhas.map(function(l){return el("tr",l.cls?{"class":l.cls}:{},l.c.map(function(c){return el("td",{},c)}))});
return el("div",{"class":"tab"},el("table",{},[el("thead",{},el("tr",{},cab.map(function(c){return el("th",{},c)}))),el("tbody",{},tr)]))}
function badge(t,c){return el("span",{"class":"badge b-"+c},t)}
function render(S){
app.textContent="";
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
}
function campo(rot,e){return el("label",{"class":"campo"},[el("span",{},rot),e])}
function num(min,passo){return el("input",{type:"number",min:min,step:passo||"1"})}
function sel(ops){var s=el("select",{});ops.forEach(function(o){s.appendChild(el("option",{value:o},o))});return s}
function salva(btn,msg,dados){
btn.disabled=true;msg.className="msg mut";msg.textContent="salvando…";dados.token=T;
fetch("/config",{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify(dados)})
.then(function(r){return r.json().catch(function(){return{ok:false,erro:"HTTP "+r.status}})})
.then(function(j){msg.className="msg "+(j.ok?"ok":"ruim");msg.textContent=j.ok?"salvo":(j.erro||"erro")})
.catch(function(){msg.className="msg ruim";msg.textContent="sem resposta do servidor"})
.then(function(){btn.disabled=false})}
function secaoConf(titulo,corpo,coleta){var b=el("button",{type:"button"},"Salvar"),m=el("span",{"class":"msg"},"");
b.onclick=function(){salva(b,m,coleta())};return el("div",{},[el("h3",{},titulo),corpo,el("div",{"class":"acoes"},[b,m])])}
var F={},contasBox=el("div",{});
function montaForm(){
F.fila={modo:sel(["recurso","projeto"]),vagas:num(1),vagas_projeto:num(1),teto:num(1),processos:num(1)};
F.pool={teto:num(0),ram_min:num(0,"any"),escolha:sel(["ritmo","ordem"])};
F.contas=[];
var fila=secaoConf("Fila de testes",el("div",{},[campo("modo",F.fila.modo),campo("vagas por recurso",F.fila.vagas),campo("vagas por projeto",F.fila.vagas_projeto),campo("teto da máquina",F.fila.teto),campo("processos (--parallel)",F.fila.processos)]),function(){
return{"fila.modo":F.fila.modo.value,"fila.vagas":F.fila.vagas.value,"fila.vagas_projeto":F.fila.vagas_projeto.value,"fila.teto":F.fila.teto.value,"fila.processos":F.fila.processos.value}});
var pool=secaoConf("Pool",el("div",{},[campo("teto da máquina",F.pool.teto),campo("ram_min (GB)",F.pool.ram_min),campo("escolha",F.pool.escolha)]),function(){
return{"pool.teto":F.pool.teto.value,"pool.ram_min":F.pool.ram_min.value,"pool.escolha":F.pool.escolha.value}});
var contas=secaoConf("Contas",contasBox,function(){var d={};F.contas.forEach(function(c){
d["conta."+c.nome+".vagas"]=c.vagas.value;d["conta."+c.nome+".peso"]=c.peso.value;
d["conta."+c.nome+".papeis"]=PAPEIS.filter(function(x){return c.papeis[x].checked}).join(",")});return d});
var rec=el("button",{type:"button"},"Recarregar");rec.onclick=function(){if(ULT)preenche(ULT.config)};
conf.appendChild(el("section",{},[el("h2",{},"Configuração"),el("div",{"class":"mut"},"Mudança na fila só vale para testes iniciados depois."),fila,pool,contas,el("div",{"class":"acoes"},rec)]))}
function preenche(c){
if(!c)return;
Object.keys(c.fila).forEach(function(k){if(F.fila[k])F.fila[k].value=c.fila[k]});
Object.keys(c.pool).forEach(function(k){if(F.pool[k])F.pool[k].value=c.pool[k]});
F.contas=c.contas.map(function(x){var o={nome:x.nome,vagas:num(0),peso:num(1),papeis:{}};o.vagas.value=x.vagas;o.peso.value=x.peso;
PAPEIS.forEach(function(p){var i=el("input",{type:"checkbox"});i.checked=x.papeis.indexOf(p)>=0;o.papeis[p]=i});return o});
contasBox.textContent="";
contasBox.appendChild(tabela(["conta","vagas","peso","papéis"],F.contas.map(function(o){
return{c:[o.nome,o.vagas,o.peso,PAPEIS.map(function(p){return el("label",{"class":"papel"},[o.papeis[p]," "+p])})]}})))}
var ULT=null;
function topo(t){var e=document.getElementById("topo");e.hidden=!t;e.textContent=t||""}
function busca(){
fetch("/estado.json",{cache:"no-store"}).then(function(r){if(!r.ok)throw new Error(r.status);return r.json()}).then(function(s){
var primeira=!ULT;ULT=s;ULT.hora=new Date().toTimeString().slice(0,5);render(s);if(primeira)preenche(s.config);topo("")})
.catch(function(){topo("sem atualização desde "+(ULT?ULT.hora:"o início"))})
.then(function(){setTimeout(busca,5000)})}
if(T){montaForm();busca()}
else{render(S0);conf.appendChild(el("section",{},el("div",{"class":"mut"},["Para configurar: ",el("code",{},"bash ~/.cache/painel.sh --servir")])))}
})();
</script></body></html>'''

class Erro(Exception): pass

def confere(chave, v):
    """Valida e normaliza um valor de configuração; Erro se a chave ou o valor não valem."""
    inteiro_ = re.fullmatch(r"[0-9]+", v) is not None
    if chave == "fila.modo": ok = v in ("recurso", "projeto")
    elif chave in FILA_CHAVES: ok = inteiro_ and int(v) >= 1
    elif chave == "pool.teto": ok = inteiro_
    elif chave == "pool.ram_min": ok = re.fullmatch(r"[0-9]+(\.[0-9]+)?", v) is not None
    elif chave == "pool.escolha": ok = v in ("ritmo", "ordem")
    else:
        m = re.fullmatch(r"conta\.([a-z0-9_-]{1,32})\.(vagas|peso|papeis)", chave)
        if not m: raise Erro("chave desconhecida (%s)" % chave)
        if m.group(2) == "vagas": ok = inteiro_
        elif m.group(2) == "peso": ok = inteiro_ and int(v) >= 1
        else: ok = v == "" or all(p in PAPEIS for p in v.split(","))
    if not ok: raise Erro("valor inválido para %s: %s" % (chave, v or "(vazio)"))
    return str(int(v)) if inteiro_ else v

def le_bytes(caminho):
    try:
        with open(caminho, "rb") as f: return f.read()
    except OSError: return None

def grava_bytes(caminho, dados):  # atômica: .tmp + os.replace; None remove
    if dados is None:
        try: os.remove(caminho)
        except OSError: pass
        return
    os.makedirs(os.path.dirname(caminho), exist_ok=True)
    novo = "%s.%d.tmp" % (caminho, os.getpid())
    with open(novo, "wb") as f: f.write(dados)
    os.replace(novo, caminho)

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

def conta_re(nome):
    return re.compile(r"\s*%s\s+\S" % re.escape(nome))

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
        i = next((j for j, l in enumerate(L) if conta_re(nome).match(l)), None)
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
    for k, v in pares: novos[k] = confere(k, str(v).strip())
    if not novos: raise Erro("nada a gravar")
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
            os.replace(candidato, CONF_AGENTES)
        if novo_fila is not None: grava_bytes(CONF_FILA, novo_fila)
    except (Erro, OSError) as e:
        try: os.remove(candidato)
        except OSError: pass
        raise e if isinstance(e, Erro) else Erro("não consegui gravar: %s" % e)
    return list(novos)

if modo == "config":
    try:
        pares = []
        for a in sys.argv[1:]:
            if "=" not in a: raise Erro("argumento sem chave=valor: %s" % a)
            pares.append(tuple(a.split("=", 1)))
        for k in aplica_config(pares): print("ok " + k)
    except Erro as e:
        print("erro: %s" % e, file=sys.stderr); sys.exit(2)
    sys.exit(0)

if modo == "servir":
    import hmac, http.server, secrets, threading, urllib.parse
    porta = int(E["PAINEL_PORTA"]); token = secrets.token_urlsafe(24)
    trava_config = threading.Lock(); trava_estado = threading.Lock(); memo = {"t": 0.0, "dados": None}

    def estado_bytes():  # o --json do próprio script; 2 s de memória para a página e o curl não empilharem coletas
        with trava_estado:
            if memo["dados"] is None or time.time() - memo["t"] > 2:
                r = subprocess.run([shutil.which("bash") or "bash", E["PAINEL_SCRIPT"], "--json"], capture_output=True, timeout=90, stdin=subprocess.DEVNULL)
                if r.returncode != 0: raise OSError("painel --json saiu com %d" % r.returncode)
                memo["dados"], memo["t"] = r.stdout, time.time()
            return memo["dados"]

    class H(http.server.BaseHTTPRequestHandler):
        server_version = "painel"
        def log_message(self, *a): pass
        def envia(self, status, corpo, tipo="application/json; charset=utf-8", extra=None):
            if isinstance(corpo, dict): corpo = json.dumps(corpo, ensure_ascii=False).encode("utf-8")
            elif isinstance(corpo, str): corpo = corpo.encode("utf-8")
            self.send_response(status)
            for k, v in [("Content-Type", tipo), ("Content-Length", str(len(corpo))), ("Cache-Control", "no-store"), ("X-Content-Type-Options", "nosniff")] + list((extra or {}).items()):
                self.send_header(k, v)
            self.end_headers(); self.wfile.write(corpo)
        def erro(self, status, msg): self.envia(status, {"ok": False, "erro": msg})
        def host_ok(self):  # recusa DNS rebinding: só o nome local com a porta do servidor
            if self.headers.get("Host") in ("127.0.0.1:%d" % porta, "localhost:%d" % porta): return True
            self.erro(403, "host não permitido"); return False
        def do_GET(self):
            if not self.host_ok(): return
            caminho = urllib.parse.urlsplit(self.path).path
            if caminho == "/":
                self.envia(200, PAGINA.replace("__REFRESH__", "").replace("__DADOS__", "null").replace("__TOKEN__", token), "text/html; charset=utf-8")
            elif caminho == "/estado.json":
                try: self.envia(200, estado_bytes())
                except (OSError, subprocess.SubprocessError) as e: self.erro(500, str(e))
            else: self.erro(404, "rota inexistente")
        def do_POST(self):
            if not self.host_ok(): return
            if urllib.parse.urlsplit(self.path).path != "/config": return self.erro(404, "rota inexistente")
            try: n = int(self.headers.get("Content-Length") or 0)
            except ValueError: n = -1
            if n < 0 or n > 65536: return self.erro(400, "corpo inválido")
            bruto = self.rfile.read(n).decode("utf-8", "replace")
            try:
                if "json" in (self.headers.get("Content-Type") or ""):
                    d = json.loads(bruto)
                    if not isinstance(d, dict): raise ValueError
                else: d = {k: v[-1] for k, v in urllib.parse.parse_qs(bruto, keep_blank_values=True).items()}
            except ValueError: return self.erro(400, "corpo inválido")
            tk = d.pop("token", None)
            if not isinstance(tk, str) or not hmac.compare_digest(tk.encode(), token.encode()): return self.erro(403, "token inválido")
            pares = [(k, ",".join(map(str, v)) if isinstance(v, list) else "" if v is None else str(v)) for k, v in d.items()]
            try:
                with trava_config: aplica_config(pares)
            except Erro as e: return self.erro(400, str(e))
            with trava_estado: memo["dados"] = None
            self.envia(200, {"ok": True})
        def nao_permitido(self): self.envia(405, {"ok": False, "erro": "método não permitido"}, extra={"Allow": "GET, POST"})
        do_PUT = do_DELETE = do_PATCH = do_HEAD = do_OPTIONS = nao_permitido

    class Servidor(http.server.ThreadingHTTPServer):
        allow_reuse_address = os.name != "nt"  # no Windows SO_REUSEADDR deixaria dois servidores na mesma porta
        daemon_threads = True

    try: srv = Servidor(("127.0.0.1", porta), H)
    except OSError as e:
        print("erro: porta %d indisponível (%s)" % (porta, e.strerror or e), file=sys.stderr); sys.exit(2)
    print("http://127.0.0.1:%d/" % porta, flush=True)
    try: srv.serve_forever()
    except KeyboardInterrupt: pass
    sys.exit(0)

tmp = E["PAINEL_TMP"]

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
# Mesma precedência do fila-teste.sh: ambiente < fila.conf (o .orca/worktree.conf é por projeto e o painel não o enxerga).
fc = le_fila_conf()
modo_fila = fc.get("FILA_TESTE_FILA", E["PAINEL_FILA_MODO"])
fila_cfg = {
    "modo": modo_fila,
    "vagas": inteiro(fc.get("FILA_TESTE_VAGAS", E["PAINEL_FILA_VAGAS"]), 2),
    "vagas_projeto": inteiro(fc.get("FILA_TESTE_VAGAS_PROJETO", E["PAINEL_FILA_VAGAS_PROJETO"]), 1),
    "teto": inteiro(fc.get("FILA_TESTE_TETO", E["PAINEL_FILA_TETO"]), 3),
    "processos": inteiro(fc.get("FILA_TESTE_PROCESSOS", E["PAINEL_FILA_PROCESSOS"]), 8),
}
fila = {"modo": modo_fila, "vagas": fila_cfg["vagas_projeto" if modo_fila == "projeto" else "vagas"], "teto": fila_cfg["teto"], "travas": travas}

# pool
conf = {}; escolha = "ritmo"
for l in le(CONF_AGENTES).split("\n"):
    m = re.match(r"^\s*(teto|ram_min)\s*=\s*(\d+(?:\.\d+)?)\s*$", l)
    if m: conf[m.group(1)] = float(m.group(2)) if "." in m.group(2) else int(m.group(2))
    m = re.match(r"^\s*escolha\s*=\s*(ritmo|ordem)\s*$", l)
    if m: escolha = m.group(1)
agora = time.time(); contas = []; total = 0
# contas.sh leva segundos no Windows: com agentes.conf lê-se direto (padrões do contas.sh); sem ele, a saída do contas.sh lista.
conf_linhas = le(CONF_AGENTES).split("\n")
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
config = {"fila": fila_cfg, "pool": {"teto": teto, "ram_min": ram_min, "escolha": escolha},
          "contas": [{"nome": c["nome"], "vagas": c["vagas"], "peso": c["peso"], "papeis": c["papeis"]} for c in contas]}

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
          "saude": saude, "fila": fila, "pool": pool, "ram": ram, "workers": workers, "config": config}

if modo == "json":
    print(json.dumps(estado, ensure_ascii=False, indent=2)); sys.exit(0)

DADOS = json.dumps(estado, ensure_ascii=False).replace("<", "\\u003c")
html = PAGINA.replace("__REFRESH__", '<meta http-equiv="refresh" content="%s">' % E["PAINEL_INTERVALO"]).replace("__TOKEN__", "").replace("__DADOS__", DADOS)
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

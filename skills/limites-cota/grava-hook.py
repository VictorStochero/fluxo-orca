"""Edita a configuração de hooks dos agentes (JSON e trust do Codex) de forma idempotente; usado por instala-agente.sh.

  grava-hook.py hook  <arquivo> <a.b.c> <grupo-json> [--dry]   acrescenta o grupo à lista em a.b.c se o comando ainda não está lá → "ja N" | "novo N"
  grava-hook.py set   <arquivo> <a.b.c> <valor-json> [--dry]   grava o valor se diferente → "ja" | "novo"
  grava-hook.py confia <config.toml> <hooks.json> <evento> <n> <comando> <timeout> [--dry]   confiança do hook no Codex → "ja" | "novo"
"""
import hashlib, json, os, sys


def carrega(arq):
    if not os.path.exists(arq):
        return {}
    with open(arq, encoding="utf-8") as f:
        return json.load(f)  # JSON inválido aborta: não sobrescreve config do usuário


def grava(arq, dados):
    os.makedirs(os.path.dirname(arq) or ".", exist_ok=True)
    with open(arq, "w", encoding="utf-8", newline="\n") as f:
        json.dump(dados, f, indent=2, ensure_ascii=False)
        f.write("\n")


def desce(dados, caminho):
    for k in caminho[:-1]:
        dados = dados.setdefault(k, {})
    return dados, caminho[-1]


def hook(arq, caminho, grupo, dry):
    dados = carrega(arq)
    pai, ultimo = desce(dados, caminho.split("."))
    lista = pai.setdefault(ultimo, [])
    cmd = grupo["hooks"][0]["command"]
    for i, g in enumerate(lista):
        if any(h.get("command") == cmd for h in g.get("hooks", [])):
            print("ja", i)
            return
    lista.append(grupo)
    if not dry:
        grava(arq, dados)
    print("novo", len(lista) - 1)


def define(arq, caminho, valor, dry):
    dados = carrega(arq)
    pai, ultimo = desce(dados, caminho.split("."))
    if pai.get(ultimo) == valor:
        print("ja")
        return
    pai[ultimo] = valor
    if not dry:
        grava(arq, dados)
    print("novo")


def confia(toml, hooks_json, evento, n, comando, timeout, dry):
    corpo = {"event_name": evento, "hooks": [{"async": False, "command": comando, "timeout": int(timeout), "type": "command"}]}
    h = "sha256:" + hashlib.sha256(json.dumps(corpo, separators=(",", ":"), sort_keys=True).encode()).hexdigest()
    # Windows: o Codex confere as duas grafias do caminho (C:\... e C:/...).
    caminhos = {hooks_json, hooks_json.replace("/", "\\")} if hooks_json[1:3] == ":/" else {hooks_json}
    atual = open(toml, encoding="utf-8").read() if os.path.exists(toml) else ""
    novo = ""
    for c in sorted(caminhos):
        cab = "[hooks.state.'%s:%s:%s:0']" % (c, evento, n)
        if cab not in atual:
            novo += "\n%s\nenabled = true\ntrusted_hash = \"%s\"\n" % (cab, h)
    if novo and not dry:
        with open(toml, "a", encoding="utf-8", newline="\n") as f:
            f.write(novo)
    print("novo" if novo else "ja")


a = sys.argv[1:]
dry = "--dry" in a
a = [x for x in a if x != "--dry"]
if a[0] == "hook":
    hook(a[1], a[2], json.loads(a[3]), dry)
elif a[0] == "set":
    define(a[1], a[2], json.loads(a[3]), dry)
elif a[0] == "confia":
    confia(*a[1:7], dry)
else:
    sys.exit("uso: grava-hook.py hook|set|confia ...")

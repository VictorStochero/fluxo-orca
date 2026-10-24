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
# Arquivos de trabalho por processo: coordenadores em paralelo truncavam o mesmo arquivo e a entrega virava lixo.
tmp="$dir/.ultima.$$.json"; lista="$dir/.workers.$$.json"
trap 'rm -f "$tmp" "$lista"' EXIT
parado=${ORCA_ESPERA_PARADO_MIN:-10}
[[ "$parado" =~ ^[1-9][0-9]*$ ]] || { echo "ORCA_ESPERA_PARADO_MIN deve ser um inteiro positivo." >&2; exit 2; }
fim=$(( $(date +%s) + max * 60 ))
cota_min=${ORCA_ESPERA_COTA_MIN:-10}
[[ "$cota_min" =~ ^[0-9]+$ ]] || { echo "ORCA_ESPERA_COTA_MIN deve ser inteiro (0 desliga)." >&2; exit 2; }
avisadas="$dir/.cota-avisada.${run[1]:-geral}"; consulta="$avisadas.consulta"

# Fornecedor que passou de 80% em alguma janela: avisa antes de estourar, uma vez até cair abaixo e subir de novo.
# O intervalo vale entre rearmes (mtime de $consulta): o limites.sh leva 30–60 s e não pode rodar a cada rearme.
cota() {
    [ "$cota_min" = 0 ] && return 1
    [ -e "$consulta" ] && [ $(( $(date +%s) - $(date -r "$consulta" +%s) )) -lt $(( cota_min * 60 )) ] && return 1
    touch "$consulta"
    local linhas novas rc
    linhas=$(timeout 120 bash "${ORCA_LIMITES:-$HOME/.cache/limites.sh}" --alerta 2>/dev/null); rc=$?
    # Falha ou timeout: sem aviso e sem esquecer o que já foi avisado.
    [ $rc = 0 ] || [ $rc = 3 ] || return 1
    novas=$(printf '%s\n' "$linhas" | while IFS= read -r l; do
        [ -n "$l" ] || continue
        grep -qxF "$(printf '%s' "$l" | awk '{print $1, $2}')" "$avisadas" 2>/dev/null || printf '%s\n' "$l"
    done)
    printf '%s\n' "$linhas" | awk 'NF {print $1, $2}' > "$avisadas"
    [ -n "$novas" ] || return 1
    printf '%s\n' "$novas" | sed 's/^/!! cota acima de 80%: /'
    echo "   próximas etapas: bash ~/.cache/limites.sh --escritor (fornecedor acima do teto fica fora da vez)"
}

# Imprime as mensagens da entrega; sai 0 se alguma pede ação, 1 se só heartbeat, 2 se vazia, 4 se ilegível.
mostra() { ORCA_ARQ="$1" "$py" -I - <<'EOF'
import json, os, sys
sys.stdout.reconfigure(encoding="utf-8")
try:
    # A saída pode trazer mais de um documento JSON em sequência; json.load recusaria.
    txt = open(os.environ["ORCA_ARQ"], encoding="utf-8").read(); dec = json.JSONDecoder(); i = 0; ms = []
    while True:
        while i < len(txt) and txt[i].isspace(): i += 1
        if i >= len(txt): break
        doc, i = dec.raw_decode(txt, i)
        if isinstance(doc, dict): ms += (doc.get("result") or {}).get("messages") or []
except Exception as e:
    print(f"!! entrega ilegível ({type(e).__name__}: {e}) em {os.environ['ORCA_ARQ']}"); sys.exit(4)
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
    if t == "worker_done" and p.get("dispatchId"): print(f"   depois de verificar: bash ~/.cache/orca-libera.sh {p['dispatchId']}")
    print(f"   assunto: {m.get('subject')}")
    print("   " + str(m.get("body")).replace("\n", "\n   "))
sys.exit(0 if acao else 1)
EOF
}

# Estado real dos workers não concluídos; imprime todos e sai 0 se algum precisa de atenção.
# Atividade do agente no Orca: working | blocked | waiting | done (done = o turno terminou).
confere() {
    orca orchestration worker-list "${run[@]}" --json > "$lista" 2>/dev/null
    ORCA_ARQ="$lista" ORCA_PARADO="$parado" "$py" -I - <<'EOF'
import json, os, re, shutil, subprocess, sys, time
orca = shutil.which("orca") or "orca"  # no Windows o subprocess só acha .exe sem caminho; which respeita o PATHEXT (.cmd)
sys.stdout.reconfigure(encoding="utf-8")
try: ws = json.JSONDecoder().raw_decode(open(os.environ["ORCA_ARQ"], encoding="utf-8").read().lstrip())[0]["result"]["workers"]
except Exception as e:
    print(f"   worker-list ilegível ({type(e).__name__}); estado real não conferido nesta rodada"); sys.exit(1)
alerta = False
agora = time.time()
# Mensagens de limite de Claude ("5-hour limit reached") e Codex ("hit your usage limit");
# 429 e rate limit só em contexto de erro, para não casar "429 passed", ":429" ou RateLimiter.
LIMITE = re.compile(r"usage limit|\blimit (reached|hit|exceeded)|(reached|hit|exceeded|exhausted)\b.{0,40}\b(quota|limit)\b"
                    r"|insufficient_quota|429 too many|status:? ?429|error.{0,20}\b429\b|rate[ _-]?limit(ed\b|_error|.{0,10}(reached|exceeded))"
                    r"|limite de (uso|cota)", re.I)
pasta_estado = os.path.dirname(os.environ["ORCA_ARQ"])
def grava(arq, estado):
    temporario = arq + "." + str(os.getpid())
    with open(temporario, "w", encoding="utf-8") as f: json.dump(estado, f)
    os.replace(temporario, arq)
for w in ws:
    estado_arq = os.path.join(pasta_estado, ".estado-" + os.path.basename(w["dispatchId"]) + ".json")
    if w.get("dispatchStatus") in ("completed", "failed", "cancelled", "abandoned"):
        try: os.remove(estado_arq)
        except OSError: pass
        continue
    p = w.get("projection") or {}; st = p.get("stage") or {}; vida = (p.get("liveness") or {}).get("verdict")
    pasta = (p.get("workspace") or {}).get("id", "").split("::")[-1]
    commit = ""; hash_curto = "-"; idade = "-"
    if pasta:
        h = subprocess.run(["git", "-C", pasta, "log", "-1", "--format=%h%x09%cr%x09%s"], capture_output=True, text=True, encoding="utf-8").stdout.strip().split("\t")
        if len(h) == 3: hash_curto, idade = h[0], h[1]; commit = "%s %s: %s" % tuple(h)
    if os.environ.get("ORCA_RESUMO"):
        print("%s último commit %s (%s)" % (w["dispatchId"], hash_curto, idade)); continue
    atividade = st.get("activity")
    try:
        with open(estado_arq, encoding="utf-8") as f: anterior = json.load(f)
    except (OSError, ValueError): anterior = {}
    estado = dict(anterior)
    # Turno iniciado à mão (Enter no terminal) fica turn_start_unobserved para sempre: só alerta sem atividade.
    inicio_incerto = w.get("dispatchStatus") == "pending" and st.get("worker") == "start_unknown" and st.get("detail") == "turn_start_unobserved" and atividade != "working"
    estado["inicio_incerto"] = anterior.get("inicio_incerto", agora) if inicio_incerto else agora
    if atividade == "working":
        try:
            cursor = anterior.get("cursor")
            timestamp = anterior.get("timestamp")
            while True:
                args = [orca, "orchestration", "worker-read", "--dispatch", w["dispatchId"], "--source", "transcript", "--limit", "1000", "--json"]
                if cursor: args += ["--cursor", cursor]
                leitura = json.loads(subprocess.run(args, capture_output=True, text=True, encoding="utf-8", check=True).stdout)
                if leitura.get("ok") is False: raise ValueError("worker-read falhou")
                resultado = leitura["result"]
                transcript = resultado["transcript"]
                for mensagem in transcript.get("messages") or []:
                    ts = mensagem.get("timestamp")
                    if ts is not None and (timestamp is None or ts > timestamp): timestamp = ts
                proximo = resultado.get("cursor") or transcript.get("nextCursor")
                if not transcript.get("limited"): break
                if not proximo or proximo == cursor: raise ValueError("transcript incompleto")
                cursor = proximo
            hash_commit = subprocess.run(["git", "-C", pasta, "rev-parse", "HEAD"], capture_output=True, text=True, encoding="utf-8", check=True).stdout.strip()
            if anterior.get("timestamp") != timestamp or anterior.get("commit") != hash_commit or anterior.get("atividade") != "working":
                estado["progresso"] = agora
            estado.update(cursor=proximo, timestamp=timestamp, commit=hash_commit)
        except (OSError, ValueError, KeyError, TypeError, subprocess.SubprocessError):
            # Leitura inconclusiva não prova que o worker parou.
            estado.pop("cursor", None)
            estado["progresso"] = agora
    else:
        estado["progresso"] = agora
    estado["atividade"] = atividade
    assinatura = [atividade, vida, hash_curto]
    novo = anterior.get("impresso") != assinatura
    estado["impresso"] = assinatura
    linha = "%s %s/%s vida=%s %s | último commit: %s" % (w["dispatchId"], st.get("worker"), atividade, vida, pasta.split("/")[-1], commit or "-")
    motivo = ""; avisou = False
    if vida == "exited":
        motivo = "o processo do agente encerrou sem worker_done: recovery (worker-show, worker-stop ou worker-abandon)"
    elif atividade in ("done", "waiting", "blocked"):
        motivo = "agente parado sem worker_done: ler com worker-read e cobrar com send --to dispatch:%s" % w["dispatchId"]
    elif inicio_incerto and agora - estado["inicio_incerto"] >= 120:
        alerta = avisou = True
        print("!! %s não começou: o prompt pode estar no campo sem envio — conferir com orca terminal read e enviar Enter com orca terminal send --terminal %s --enter" % (w["dispatchId"], w.get("agentTerminalHandle") or "?"))
        estado["inicio_incerto"] = agora  # carência: o mesmo alerta só volta depois de outro intervalo
    elif atividade == "working" and agora - estado.get("progresso", agora) >= int(os.environ["ORCA_PARADO"]) * 60:
        alerta = avisou = True
        print("!! %s parado há %d min sem saída: ler com worker-read e cobrar com send --to dispatch:%s" % (w["dispatchId"], (agora - estado["progresso"]) // 60, w["dispatchId"]))
        estado["progresso"] = agora
    # Limite de cota estourado aparece na tela do agente antes de qualquer outro sinal; avisa uma vez por mensagem.
    tela = ""
    if w.get("agentTerminalHandle"):
        try:
            cauda = json.loads(subprocess.run([orca, "terminal", "read", "--terminal", w["agentTerminalHandle"], "--screen", "--json"], capture_output=True, text=True, encoding="utf-8", errors="replace").stdout)["result"]["terminal"]["tail"][-15:]
            tela = next((l.strip() for l in reversed(cauda) if LIMITE.search(l)), "")
        except (ValueError, KeyError, TypeError, IndexError): pass
    if tela and anterior.get("limite") != tela:
        alerta = avisou = True
        print("!! %s bateu limite de cota: %s\n   redistribuir a etapa (limites.sh --escritor) ou esperar o reset" % (w["dispatchId"], tela[:200]))
    estado["limite"] = tela
    grava(estado_arq, estado)
    if avisou: continue
    if motivo:
        alerta = True
        print("!! " + linha + "\n   " + motivo)
    elif novo:
        print("   " + linha)
sys.exit(0 if alerta else 1)
EOF
}

while [ "$(date +%s)" -lt "$fim" ]; do
    restante=$(( fim - $(date +%s) )); espera=60
    [ "$restante" -lt "$espera" ] && espera=$restante
    [ "$espera" -le 0 ] && break
    orca orchestration check "${run[@]}" --wait --types "worker_done,escalation,question,status,heartbeat" --timeout-ms "$(( espera * 1000 ))" --json > "$tmp" 2>/dev/null
    entrega=$(grep -o '"deliveryId": *"[^"]*"' "$tmp" | head -1 | cut -d'"' -f4)
    if [ -n "$entrega" ]; then
        cp "$tmp" "$dir/$entrega.json"
        mostra "$tmp"; r=$?
        # Sem ack: a entrega continua na fila e a cópia fica para leitura manual.
        [ $r = 4 ] && { echo "Entrega $entrega não lida e sem ack; cópia em $dir/$entrega.json"; exit 3; }
        orca orchestration check "${run[@]}" --ack "$entrega" --json >/dev/null 2>&1
        [ $r = 0 ] && { echo "(entrega $entrega com ack; cópia em $dir/$entrega.json)"; confere; exit 0; }
        continue
    fi
    grep -q '"ok": *false' "$tmp" && { echo "check falhou:"; cat "$tmp"; exit 3; }
    confere && exit 0
    cota && exit 0
done
resumo=$(ORCA_RESUMO=1 confere | sed "s/^/Sem novidade em $max min; /")
echo "${resumo:-Sem novidade em $max min.}"
echo "Rearmar: bash ~/.cache/orca-espera.sh ${run[*]}"

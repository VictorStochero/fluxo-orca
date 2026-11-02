#!/usr/bin/env bash
# Vigia de saúde: sai na primeira novidade; mensagens chegam pelo wake do Orca.
# Uso: bash ~/.cache/orca-espera.sh [--run <run_id>] [--max-min 25]
for py in python3 python ""; do [ -n "$py" ] && "$py" -c '' 2>/dev/null && break; done
[ -n "$py" ] || { echo "orca-espera: precisa de python." >&2; exit 2; }
run=(); max=25
while [ $# -gt 0 ]; do
    case "$1" in --run) run=(--run "$2"); shift 2 ;; --max-min) max=$2; shift 2 ;; *) echo "argumento desconhecido: $1" >&2; exit 2 ;; esac
done
dir="$HOME/.cache/orca-saude"; mkdir -p "$dir"
lista="$dir/.workers.$$.json"
trap 'rm -f "$lista"' EXIT
parado=${ORCA_ESPERA_PARADO_MIN:-10}
[[ "$parado" =~ ^[1-9][0-9]*$ ]] || { echo "ORCA_ESPERA_PARADO_MIN deve ser um inteiro positivo." >&2; exit 2; }
fim=$(( $(date +%s) + max * 60 ))
cota_min=${ORCA_ESPERA_COTA_MIN:-20}
[[ "$cota_min" =~ ^[0-9]+$ ]] || { echo "ORCA_ESPERA_COTA_MIN deve ser inteiro (0 desliga)." >&2; exit 2; }
avisadas="$dir/.cota-avisada.${run[1]:-geral}"; consulta="$avisadas.consulta"
contas_lib="$(dirname "$0")/../limites-cota/contas.sh"
[ -f "$contas_lib" ] || contas_lib="$(dirname "$0")/contas.sh"
source "$contas_lib" 2>/dev/null && contas_carrega 2>/dev/null || RAM_MIN_GB=0
ram_avisada="$dir/.ram-avisada.${run[1]:-geral}"
memoria() {
    [ "$RAM_MIN_GB" = 0 ] && return 1
    local rc
    bash "$(dirname "$0")/orca-ram.sh" --portao "$RAM_MIN_GB" 2>/dev/null; rc=$?
    if [ "$rc" = 75 ]; then
        [ "$(cat "$ram_avisada" 2>/dev/null)" = "$RAM_MIN_GB" ] && return 1
        printf '%s\n' "$RAM_MIN_GB" > "$ram_avisada"
        echo "!! memória abaixo de $RAM_MIN_GB GB: rode bash ~/.cache/orca-ram.sh"
        return 0
    fi
    [ "$rc" = 0 ] && rm -f "$ram_avisada"
    return 1
}

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

# Confere somente sinais de saúde que o Orca não notifica por mensagem.
confere() {
    orca orchestration worker-list "${run[@]}" --json --full > "$lista" 2>/dev/null
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
    p = w.get("projection") or {}; st = p.get("stage") or {}
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
    if inicio_incerto and agora - estado["inicio_incerto"] >= 120:
        alerta = True
        print("!! %s não começou: o prompt pode estar no campo sem envio — conferir com orca terminal read e enviar Enter com orca terminal send --terminal %s --enter" % (w["dispatchId"], w.get("agentTerminalHandle") or "?"))
        estado["inicio_incerto"] = agora  # carência: o mesmo alerta só volta depois de outro intervalo
    elif atividade == "working" and agora - estado.get("progresso", agora) >= int(os.environ["ORCA_PARADO"]) * 60:
        alerta = True
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
        alerta = True
        print("!! %s bateu limite de cota: %s\n   redistribuir a etapa (limites.sh --escritor) ou esperar o reset" % (w["dispatchId"], tela[:200]))
    estado["limite"] = tela
    grava(estado_arq, estado)
sys.exit(0 if alerta else 1)
EOF
}

while [ "$(date +%s)" -lt "$fim" ]; do
    memoria && exit 0
    restante=$(( fim - $(date +%s) )); espera=60
    [ "$restante" -lt "$espera" ] && espera=$restante
    [ "$espera" -le 0 ] && break
    confere && exit 0
    cota && exit 0
    sleep "$espera"
done
resumo=$(ORCA_RESUMO=1 confere | tr -d '\r' | tr '\n' ';')
resumo=${resumo%;}
echo "Sem novidade em $max min${resumo:+; $resumo}."
echo "Rearmar: bash ~/.cache/orca-espera.sh ${run[*]}"

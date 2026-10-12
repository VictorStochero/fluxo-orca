#!/bin/bash
# Prova do orca-espera.sh com um orca falso no PATH: resposta com dois JSON seguidos e entrega ilegível.
raiz=$(cd "$(dirname "$0")/.." && pwd)
falhas=0
# macOS não tem timeout.
for py in python3 python; do "$py" -c '' 2>/dev/null && break; done
limite() { if command -v timeout >/dev/null 2>&1; then timeout "$@"; else perl -e 'alarm shift; exec @ARGV' "$@"; fi; }
caso() { # nome resposta_do_check saida_esperada ack_esperado(sim|nao)
    local h; h=$(mktemp -d)
    mkdir -p "$h/bin"
    printf '%s' "$2" > "$h/resposta"
    cat > "$h/bin/orca" <<EOF
#!/bin/bash
case "\$*" in
    *worker-list*) echo '{"ok":true,"result":{"workers":[]}}' ;;
    *--ack*) echo ack >> "$h/acks"; echo '{"ok":true}' ;;
    *check*) cat "$h/resposta" ;;
esac
EOF
    chmod +x "$h/bin/orca"
    saida=$(HOME="$h" PATH="$h/bin:$PATH" bash "$raiz/skills/delegacao/orca-espera.sh" --max-min 1 2>&1)
    ack=nao; [ -s "$h/acks" ] && ack=sim
    if printf '%s' "$saida" | grep -qF "$3" && [ "$ack" = "$4" ]; then echo "ok   $1"
    else echo "FALHA $1 (ack=$ack)"; printf '%s\n' "$saida" | sed 's/^/     /'; falhas=$((falhas + 1)); fi
    rm -rf "$h"
}
msg='{"ok":true,"result":{"deliveryId":"delivery_t1","messages":[{"type":"worker_done","id":"m1","subject":"pronto","body":"b","payload":{"dispatchId":"ctx_t","outcome":"succeeded"}}]}}'
caso "dois JSON seguidos" "$msg"$'\n''{"ok":true,"result":{}}' "== worker_done" sim
caso "entrega ilegível não some" '{"ok":true,"result":{"deliveryId":"delivery_t2","messages":[{"type":' "entrega ilegível" nao

# Carência e limpeza: worker working sem progresso alerta uma vez; a rodada seguinte não repete; estado de dispatch encerrado é apagado.
h=$(mktemp -d); mkdir -p "$h/bin" "$h/.cache/orca-entregas" "$h/wt"
git -C "$h/wt" init -q && git -C "$h/wt" -c user.name=t -c user.email=t@t commit -q --allow-empty -m t
wt="$h/wt"; command -v cygpath >/dev/null 2>&1 && wt=$(cygpath -m "$h/wt")
cat > "$h/bin/orca" <<EOF
#!/bin/bash
case "\$*" in
    *worker-list*) echo '{"ok":true,"result":{"workers":[{"dispatchId":"ctx_p","dispatchStatus":"dispatched","projection":{"stage":{"worker":"ready","activity":"working"},"liveness":{"verdict":"live"},"workspace":{"id":"r::$wt"}}},{"dispatchId":"ctx_fim","dispatchStatus":"completed","projection":{}}]}}' ;;
    *worker-read*) echo '{"ok":true,"result":{"transcript":{"messages":[{"timestamp":1}],"limited":false}}}' ;;
    *check*) sleep 1; echo '{"ok":true,"result":{}}' ;;
esac
EOF
chmod +x "$h/bin/orca"
# Windows: o Python do script chama o orca pelo PATHEXT; o .cmd repassa ao stub bash.
command -v cygpath >/dev/null 2>&1 && printf '@"%s" "%s" %%*\r\n' "$(cygpath -w "$(command -v bash)")" "$(cygpath -m "$h/bin/orca")" > "$h/bin/orca.cmd"
e="$h/.cache/orca-entregas"
printf '{"progresso": %s, "timestamp": 1, "commit": "%s", "atividade": "working"}' "$(( $(date +%s) - 600 ))" "$(git -C "$h/wt" rev-parse HEAD)" > "$e/.estado-ctx_p.json"
echo '{}' > "$e/.estado-ctx_fim.json"
um=$(HOME="$h" PATH="$h/bin:$PATH" ORCA_ESPERA_PARADO_MIN=1 bash "$raiz/skills/delegacao/orca-espera.sh" --max-min 1 2>&1)
# Rearme logo depois do alerta: as primeiras rodadas não podem repetir (carência de 1 min).
dois=$(HOME="$h" PATH="$h/bin:$PATH" ORCA_ESPERA_PARADO_MIN=1 limite 10 bash "$raiz/skills/delegacao/orca-espera.sh" --max-min 1 2>&1)
if printf '%s' "$um" | grep -q '!! ctx_p parado' && ! printf '%s' "$dois" | grep -q '!!'; then echo "ok   carência: alerta uma vez, sem laço"
else echo "FALHA carência"; printf '1:\n%s\n2:\n%s\n' "$um" "$dois" | sed 's/^/     /'; falhas=$((falhas + 1)); fi
if [ ! -e "$e/.estado-ctx_fim.json" ]; then echo "ok   estado de dispatch encerrado apagado"; else echo "FALHA limpeza do estado"; falhas=$((falhas + 1)); fi
rm -rf "$h"

# Saída enxuta e Kimi: worker com stub configurável (atividade, wire.jsonl do Kimi).
cena() { # atividade idade_do_wire(nenhum|recente|velho) [agente=kimi]
    h=$(mktemp -d); mkdir -p "$h/bin" "$h/wt"
    git -C "$h/wt" init -q && git -C "$h/wt" -c user.name=t -c user.email=t@t commit -q --allow-empty -m t
    wt="$h/wt"; command -v cygpath >/dev/null 2>&1 && wt=$(cygpath -m "$h/wt")
    cat > "$h/bin/orca" <<EOF2
#!/bin/bash
case "\$*" in
    *worker-list*) echo '{"ok":true,"result":{"workers":[{"dispatchId":"ctx_k","dispatchStatus":"dispatched","agentTerminalHandle":"term_k","projection":{"stage":{"worker":"ready","activity":"$1"},"liveness":{"verdict":"live"},"workspace":{"id":"r::$wt"}}}]}}' ;;
    *worker-read*) echo '{"ok":true,"result":{"transcript":{"messages":[{"timestamp":1}],"limited":false}}}' ;;
    *worker-show*) echo '{"ok":true,"result":{"worker":{"startOptions":{"agent":"${3:-kimi}"}}}}' ;;
    *terminal*read*) cat "$h/tela.json" 2>/dev/null || echo '{"ok":true,"result":{"terminal":{"tail":["pronto"]}}}' ;;
    *check*) sleep 1; echo '{"ok":true,"result":{}}' ;;
esac
EOF2
    chmod +x "$h/bin/orca"
    command -v cygpath >/dev/null 2>&1 && printf '@"%s" "%s" %%*\r\n' "$(cygpath -w "$(command -v bash)")" "$(cygpath -m "$h/bin/orca")" > "$h/bin/orca.cmd"
    if [ "$2" != nenhum ]; then
        w="$h/.kimi-code/sessions/wd_wt_abc/session_1/agents/main"; mkdir -p "$w"; : > "$w/wire.jsonl"
        [ "$2" = velho ] && touch -d '2 hours ago' "$w/wire.jsonl"
    fi
}
roda() { HOME="$h" PATH="$h/bin:$PATH" ORCA_ESPERA_PARADO_MIN=10 bash "$raiz/skills/delegacao/orca-espera.sh" --max-min 1 2>&1; }
cena working nenhum
um=$(roda)
git -C "$h/wt" -c user.name=t -c user.email=t@t commit -q --allow-empty -m novo
dois=$(roda)
n1=$(printf '%s\n' "$um" | grep -c '^   ctx_k ')
n2=$(printf '%s\n' "$dois" | grep -c '^   ctx_k ')
if [ "$n1" = 1 ] && [ "$n2" = 1 ]; then echo "ok   minuto sem mudança não imprime; mudança (commit) imprime"
else echo "FALHA saída só de mudança (n1=$n1 n2=$n2)"; printf '%s\n' "$um" "$dois" | sed 's/^/     /'; falhas=$((falhas + 1)); fi
if printf '%s' "$um" | grep -q '^Sem novidade em 1 min; ctx_k último commit [0-9a-f]* (.*)$' && printf '%s' "$um" | grep -q 'Rearmar'; then echo "ok   resumo no fim"
else echo "FALHA resumo"; printf '%s\n' "$um" | sed 's/^/     /'; falhas=$((falhas + 1)); fi
rm -rf "$h"
cena done recente
out=$(roda)
if ! printf '%s' "$out" | grep -q '!!'; then echo "ok   Kimi com wire recente e activity=done não é dado como parado"
else echo "FALHA Kimi wire recente"; printf '%s\n' "$out" | sed 's/^/     /'; falhas=$((falhas + 1)); fi
rm -rf "$h"
cena working velho
out=$(roda)
if printf '%s' "$out" | grep -q 'agente parado sem worker_done'; then echo "ok   Kimi com wire velho é dado como parado"
else echo "FALHA Kimi wire velho"; printf '%s\n' "$out" | sed 's/^/     /'; falhas=$((falhas + 1)); fi
rm -rf "$h"
cena working velho claude
out=$(roda)
if ! printf '%s' "$out" | grep -q '!!'; then echo "ok   wire velho de Kimi não vale para worker de outro agente"
else echo "FALHA wire alheio"; printf '%s\n' "$out" | sed 's/^/     /'; falhas=$((falhas + 1)); fi
rm -rf "$h"

# Limite de cota: estourado na tela do worker e perto de estourar pelo limites.sh --alerta.
cena working nenhum claude
echo '{"ok":true,"result":{"terminal":{"tail":["Error: 403 You'"'"'ve reached your 5-hour usage limit.","> "]}}}' > "$h/tela.json"
out=$(roda)
if printf '%s' "$out" | grep -q '!! ctx_k bateu limite de cota: .*5-hour usage limit'; then echo "ok   limite estourado na tela do worker avisa"
else echo "FALHA limite na tela"; printf '%s\n' "$out" | sed 's/^/     /'; falhas=$((falhas + 1)); fi
out=$(roda)
if ! printf '%s' "$out" | grep -q 'bateu limite'; then echo "ok   mesmo limite não avisa de novo"
else echo "FALHA limite repetido"; printf '%s\n' "$out" | sed 's/^/     /'; falhas=$((falhas + 1)); fi
echo '{"ok":true,"result":{"terminal":{"tail":["  5-hour limit reached ∙ resets 3pm","> "]}}}' > "$h/tela.json"
out=$(roda)
if printf '%s' "$out" | grep -q 'bateu limite de cota: 5-hour limit reached'; then echo "ok   formato 'limit reached' do Claude avisa"
else echo "FALHA limit reached"; printf '%s\n' "$out" | sed 's/^/     /'; falhas=$((falhas + 1)); fi
echo '{"ok":true,"result":{"terminal":{"tail":["Tests: 429 passed","use Illuminate\\\\Cache\\\\RateLimiter;","> "]}}}' > "$h/tela.json"
out=$(roda)
if ! printf '%s' "$out" | grep -q 'bateu limite'; then echo "ok   429 de teste e RateLimiter não são limite"
else echo "FALHA falso positivo de limite"; printf '%s\n' "$out" | sed 's/^/     /'; falhas=$((falhas + 1)); fi
rm -f "$h/tela.json"
printf '#!/bin/bash\necho "kimi: 5h 92%% (zera 04:38) · mês 10%%"; exit 3\n' > "$h/limites.sh"
out=$(ORCA_LIMITES="$h/limites.sh" ORCA_ESPERA_COTA_MIN=1 roda)
if printf '%s' "$out" | grep -q '^!! cota acima de 80%: kimi: 5h 92%'; then echo "ok   cota acima de 80% avisa antes de estourar"
else echo "FALHA aviso de cota"; printf '%s\n' "$out" | sed 's/^/     /'; falhas=$((falhas + 1)); fi
out=$(ORCA_LIMITES="$h/limites.sh" ORCA_ESPERA_COTA_MIN=1 roda)
if ! printf '%s' "$out" | grep -q 'cota acima'; then echo "ok   mesmo fornecedor não avisa de novo"
else echo "FALHA aviso de cota repetido"; printf '%s\n' "$out" | sed 's/^/     /'; falhas=$((falhas + 1)); fi
c=$(ls "$h"/.cache/orca-entregas/.cota-avisada.*.consulta 2>/dev/null | head -1)
[ -n "$c" ] && ok_int=1 || ok_int=0
printf '#!/bin/bash\necho conta; exit 1\n' > "$h/limites.sh"
out=$(ORCA_LIMITES="$h/limites.sh" ORCA_ESPERA_COTA_MIN=10 roda)
if [ "$ok_int" = 1 ] && ! printf '%s' "$out" | grep -q 'cota acima'; then echo "ok   intervalo da consulta vale entre rearmes"
else echo "FALHA intervalo entre rearmes"; falhas=$((falhas + 1)); fi
touch -d '20 minutes ago' "$c" 2>/dev/null
out=$(ORCA_LIMITES="$h/limites.sh" ORCA_ESPERA_COTA_MIN=10 roda)
printf '#!/bin/bash\necho "kimi: 5h 92%% (zera 04:38) · mês 10%%"; exit 3\n' > "$h/limites.sh"; touch -d '20 minutes ago' "$c"
out=$(ORCA_LIMITES="$h/limites.sh" ORCA_ESPERA_COTA_MIN=10 roda)
if ! printf '%s' "$out" | grep -q 'cota acima'; then echo "ok   falha do limites.sh não apaga o que já foi avisado"
else echo "FALHA falha apagou deduplicação"; printf '%s\n' "$out" | sed 's/^/     /'; falhas=$((falhas + 1)); fi
rm -rf "$h"

# orca-libera: só fecha terminal criado pelo --cria e que nenhum dispatch ativo do run usa.
libera() { # nome registrado(sim|nao) outro_ativo(sim|nao|ilegivel) fecha_esperado(sim|nao)
    local h; h=$(mktemp -d); mkdir -p "$h/bin"
    local outro='' ; [ "$3" = sim ] && outro=',{"dispatchId":"ctx_b","dispatchStatus":"dispatched","agentTerminalHandle":"term_t","projection":{}}'
    # Indentado como o worker-list real (uma chave por linha).
    printf '%s' '{"ok":true,"result":{"workers":[{"dispatchId":"ctx_a","dispatchStatus":"completed","agentTerminalHandle":"term_t","projection":{}}'"$outro"']}}' \
        | "$py" -m json.tool > "$h/lista.json"
    [ "$3" = ilegivel ] && echo '{"ok":true,"result":' > "$h/lista.json"
    cat > "$h/bin/orca" <<EOF
#!/bin/bash
case "\$*" in
    *"terminal create"*) echo '{"ok":true,"result":{"terminal":{"handle":"term_t"}}}' ;;
    *worker-release*) echo '{"ok":true,"result":{"state":"retained","reason":"external_terminal"}}' ;;
    *worker-show*) echo '{"ok":true,"result":{"dispatch":{"runId":"run_t"},"worker":{"agentTerminalHandle":"term_t"}}}' ;;
    *worker-list*) cat "$h/lista.json" ;;
    *"terminal close"*) echo fechou >> "$h/fechou"; echo '{"ok":true}' ;;
esac
EOF
    chmod +x "$h/bin/orca"
    [ "$2" = sim ] && HOME="$h" PATH="$h/bin:$PATH" bash "$raiz/skills/delegacao/orca-libera.sh" --cria --worktree x >/dev/null
    saida=$(HOME="$h" PATH="$h/bin:$PATH" bash "$raiz/skills/delegacao/orca-libera.sh" ctx_a 2>&1)
    fechou=nao; [ -s "$h/fechou" ] && fechou=sim
    if [ "$fechou" = "$4" ]; then echo "ok   $1"; else echo "FALHA $1 (fechou=$fechou): $saida"; falhas=$((falhas + 1)); fi
    rm -rf "$h"
}
libera "libera fecha terminal criado e ocioso" sim nao sim
libera "libera mantém terminal reaproveitado por dispatch ativo" sim sim nao
libera "libera mantém terminal não criado pelo --cria" nao nao nao
libera "libera mantém terminal quando o worker-list é ilegível" sim ilegivel nao

# orca-inicia: recibo real (stage como texto) vira uma linha; falha mostra failedStage e lastError.
h=$(mktemp -d); mkdir -p "$h/bin"
printf '#!/bin/bash\ncat "%s/recibo.json"\n' "$h" > "$h/bin/orca"; chmod +x "$h/bin/orca"
inicia() { HOME="$h" ORCA_CMD="$h/bin/orca" bash "$raiz/skills/delegacao/orca-inicia.sh" --spec x 2>&1; }
echo '{"ok":true,"result":{"dispatchId":"ctx_i","taskId":"task_i","state":"ready","stage":"input_accepted"}}' > "$h/recibo.json"
out=$(inicia)
if printf '%s' "$out" | grep -q '^dispatch ctx_i · state ready · task task_i · recibo .*ctx_i.json$'; then echo "ok   orca-inicia resume recibo com stage em texto"
else echo "FALHA orca-inicia recibo real"; printf '%s\n' "$out" | sed 's/^/     /'; falhas=$((falhas + 1)); fi
echo '{"ok":true,"result":{"dispatchId":"ctx_f","taskId":"task_f","state":"failed","stage":"agent_readiness","failedStage":"agent_readiness","lastError":"Agent startup blocked"}}' > "$h/recibo.json"
out=$(inicia)
if printf '%s' "$out" | grep -q 'failedStage agent_readiness · lastError Agent startup blocked'; then echo "ok   orca-inicia mostra a falha"
else echo "FALHA orca-inicia falha"; printf '%s\n' "$out" | sed 's/^/     /'; falhas=$((falhas + 1)); fi
rm -rf "$h"

[ $falhas = 0 ] && echo "TUDO OK" || { echo "$falhas falha(s)"; exit 1; }

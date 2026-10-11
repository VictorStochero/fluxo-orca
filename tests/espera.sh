#!/bin/bash
# Prova do orca-espera.sh com um orca falso no PATH: resposta com dois JSON seguidos e entrega ilegível.
raiz=$(cd "$(dirname "$0")/.." && pwd)
falhas=0
# macOS não tem timeout.
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

# orca-libera: só fecha terminal criado pelo --cria e que nenhum dispatch ativo do run usa.
libera() { # nome registrado(sim|nao) outro_ativo(sim|nao) fecha_esperado(sim|nao)
    local h; h=$(mktemp -d); mkdir -p "$h/bin"
    local outro='' ; [ "$3" = sim ] && outro=',{"dispatchId":"ctx_b","dispatchStatus":"dispatched","agentTerminalHandle":"term_t","projection":{}}'
    cat > "$h/bin/orca" <<EOF
#!/bin/bash
case "\$*" in
    *"terminal create"*) echo '{"ok":true,"result":{"terminal":{"handle":"term_t"}}}' ;;
    *worker-release*) echo '{"ok":true,"result":{"state":"retained","reason":"external_terminal"}}' ;;
    *worker-show*) echo '{"ok":true,"result":{"dispatch":{"runId":"run_t"},"worker":{"agentTerminalHandle":"term_t"}}}' ;;
    *worker-list*) echo '{"ok":true,"result":{"workers":[{"dispatchId":"ctx_a","dispatchStatus":"completed","agentTerminalHandle":"term_t","projection":{}}$outro]}}' ;;
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

[ $falhas = 0 ] && echo "TUDO OK" || { echo "$falhas falha(s)"; exit 1; }

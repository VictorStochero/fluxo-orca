#!/bin/bash
# Prova do orca-espera.sh com um orca falso no PATH: resposta com dois JSON seguidos e entrega ilegível.
raiz=$(cd "$(dirname "$0")/.." && pwd)
falhas=0
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
[ $falhas = 0 ] && echo "TUDO OK" || { echo "$falhas falha(s)"; exit 1; }

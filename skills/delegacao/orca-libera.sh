#!/usr/bin/env bash
# Fecha o ciclo de um worker concluído: libera o dispatch, fecha a aba do terminal que o coordenador criou e solta a vaga do pool.
# Uso: bash ~/.cache/orca-libera.sh --cria <argumentos de orca terminal create>   → imprime o handle e o registra
#      bash ~/.cache/orca-libera.sh <dispatch_id> [...]
# worker-release só fecha o terminal que o próprio worker-start criou; o aberto com `orca terminal create` + --terminal
# volta como retained/external_terminal. Só é fechado aqui o que foi criado pelo --cria e não serve a outro dispatch ativo.
reg="$HOME/.cache/orca-terminais"
for py in python3 python ""; do [ -n "$py" ] && "$py" -c '' 2>/dev/null && break; done
handle_de() { grep -o "\"$1\": *\"[^\"]*\"" | head -1 | cut -d'"' -f4; }
if [ "${1:-}" = --cria ]; then
    shift
    r=$(orca terminal create "$@" --json 2>&1)
    h=$(printf '%s' "$r" | handle_de handle)
    [ -n "$h" ] || { echo "orca terminal create falhou: $r" >&2; exit 1; }
    mkdir -p "$reg" && : > "$reg/$h"
    echo "$h"; exit 0
fi
[ $# -gt 0 ] || { echo "uso: orca-libera.sh --cria <args> | <dispatch_id> [...]" >&2; exit 2; }
rc=0
for d in "$@"; do
    r=$(orca orchestration worker-release --dispatch "$d" --json 2>&1)
    estado=$(printf '%s' "$r" | handle_de state)
    motivo=$(printf '%s' "$r" | handle_de reason)
    case "$estado" in
        released|already_released|release_pending)
            h=$(orca orchestration worker-show --dispatch "$d" --json 2>/dev/null | handle_de agentTerminalHandle)
            [ -n "$h" ] && rm -f "$reg/$h"
            echo "$d: $estado" ;;
        retained)
            show=$(orca orchestration worker-show --dispatch "$d" --json 2>/dev/null)
            h=$(printf '%s' "$show" | handle_de agentTerminalHandle)
            run=$(printf '%s' "$show" | handle_de runId)
            outro="?"
            # Terminal reaproveitado: algum dispatch não encerrado do mesmo run ainda o usa. Ilegível → "?" (não fecha).
            if [ -n "$h" ] && [ -n "$run" ] && [ -n "$py" ]; then
                outro=$(orca orchestration worker-list --run "$run" --json 2>/dev/null | ORCA_H="$h" ORCA_D="$d" "$py" -I -c '
import json, os, sys
try: ws = json.JSONDecoder().raw_decode(sys.stdin.read().lstrip())[0]["result"]["workers"]
except Exception: print("?"); sys.exit()
fim = ("completed", "failed", "cancelled", "abandoned")
print(next((w["dispatchId"] for w in ws if w.get("agentTerminalHandle") == os.environ["ORCA_H"]
            and w.get("dispatchId") != os.environ["ORCA_D"] and w.get("dispatchStatus") not in fim), ""))')
            fi
            if [ "$motivo" = external_terminal ] && [ -n "$h" ] && [ -f "$reg/$h" ] && [ -z "$outro" ] && orca terminal close --terminal "$h" --json >/dev/null 2>&1; then
                rm -f "$reg/$h"; echo "$d: aba $h fechada"
            elif [ "$outro" = "?" ]; then
                echo "$d: retido; não deu para conferir se o terminal ${h:-?} serve a outro dispatch, aba mantida"
            elif [ -n "$outro" ]; then
                echo "$d: retido; terminal ${h:-?} ainda serve ao dispatch $outro, aba mantida"
            else
                echo "$d: retido (${motivo:-?}), aba mantida; se for do coordenador e estiver ociosa: orca terminal close --terminal ${h:-?}"
            fi ;;
        *) echo "$d: release falhou: $r" >&2; rc=1; continue ;;
    esac
    [ -f "$HOME/.cache/vaga-agente.sh" ] && bash "$HOME/.cache/vaga-agente.sh" solta "$d" >/dev/null 2>&1
done
exit $rc

#!/usr/bin/env bash
# Fecha o ciclo de um worker concluído: libera o dispatch, fecha a aba do terminal que o coordenador criou e solta a vaga do pool.
# Uso: bash ~/.cache/orca-libera.sh --cria <argumentos de orca terminal create>   → imprime o handle e o registra
#      bash ~/.cache/orca-libera.sh <dispatch_id> [...]
# worker-release só fecha o terminal que o próprio worker-start criou; o aberto com `orca terminal create` + --terminal
# volta como retained/external_terminal. Só é fechado aqui o que foi criado pelo --cria e não serve a outro dispatch ativo.
reg="$HOME/.cache/orca-terminais"
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
        released|already_released|release_pending) echo "$d: $estado" ;;
        retained)
            show=$(orca orchestration worker-show --dispatch "$d" --json 2>/dev/null)
            h=$(printf '%s' "$show" | handle_de agentTerminalHandle)
            run=$(printf '%s' "$show" | handle_de runId)
            outro=""
            # Terminal reaproveitado: algum dispatch não encerrado do mesmo run ainda o usa.
            if [ -n "$h" ] && [ -n "$run" ]; then
                # Cada linha do worker-list começa com dispatchId, dispatchStatus e agentTerminalHandle antes do primeiro objeto aninhado.
                outro=$(orca orchestration worker-list --run "$run" --json 2>/dev/null | tr '{' '\n' | grep -F "\"$h\"" \
                    | grep -vE '"dispatchStatus": *"(completed|failed|cancelled|abandoned)"' | grep -oE '"dispatchId": *"[^"]*"' | cut -d'"' -f4 | grep -vxF "$d" | head -1)
            fi
            if [ "$motivo" = external_terminal ] && [ -n "$h" ] && [ -f "$reg/$h" ] && [ -z "$outro" ] && orca terminal close --terminal "$h" --json >/dev/null 2>&1; then
                rm -f "$reg/$h"; echo "$d: aba $h fechada"
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

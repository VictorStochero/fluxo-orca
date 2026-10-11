#!/usr/bin/env bash
# Fecha o ciclo de um worker concluído: libera o dispatch, fecha a aba do terminal criado à mão e solta a vaga do pool.
# Uso: bash ~/.cache/orca-libera.sh <dispatch_id> [...]
# worker-release só fecha o terminal que o próprio worker-start criou; o aberto com `orca terminal create` + --terminal
# (conta secundária, papéis com --agent do plugin) volta como retained/external_terminal e ficaria aberto para sempre.
[ $# -gt 0 ] || { echo "uso: orca-libera.sh <dispatch_id> [...]" >&2; exit 2; }
rc=0
for d in "$@"; do
    r=$(orca orchestration worker-release --dispatch "$d" --json 2>&1)
    estado=$(printf '%s' "$r" | grep -o '"state": *"[^"]*"' | head -1 | cut -d'"' -f4)
    motivo=$(printf '%s' "$r" | grep -o '"reason": *"[^"]*"' | head -1 | cut -d'"' -f4)
    case "$estado" in
        released|already_released|release_pending) echo "$d: $estado" ;;
        retained)
            if [ "$motivo" = external_terminal ]; then
                h=$(orca orchestration worker-show --dispatch "$d" --json 2>/dev/null | grep -o '"agentTerminalHandle": *"[^"]*"' | head -1 | cut -d'"' -f4)
                if [ -n "$h" ] && orca terminal close --terminal "$h" --json >/dev/null 2>&1; then echo "$d: aba $h fechada"
                else echo "$d: retido; feche a aba à mão (terminal ${h:-?})"; rc=1; fi
            else
                # user_takeover também vem do Enter que o coordenador manda para destravar o Codex: decidir à mão.
                h=$(orca orchestration worker-show --dispatch "$d" --json 2>/dev/null | grep -o '"agentTerminalHandle": *"[^"]*"' | head -1 | cut -d'"' -f4)
                echo "$d: retido ($motivo), aba mantida; se a intervenção foi do coordenador: orca terminal close --terminal ${h:-?}"
            fi ;;
        *) echo "$d: release falhou: $r" >&2; rc=1; continue ;;
    esac
    [ -f "$HOME/.cache/vaga-agente.sh" ] && bash "$HOME/.cache/vaga-agente.sh" solta "$d" >/dev/null 2>&1
done
exit $rc

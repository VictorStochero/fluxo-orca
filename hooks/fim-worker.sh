#!/bin/bash
# Stop: worker do Orca não encerra o turno sem worker_done — o coordenador só sabe que acabou por ele.
# Vale para Claude Code, Codex e Kimi (mesmo JSON de bloqueio); com o argumento gemini (AfterAgent) a decisão é deny. Fora de worker, ou com o Orca fora do ar, não faz nada.
in=$(cat)
# Uma cobrança só: na segunda parada (stop_hook_active) o turno termina e o orca-espera.sh do coordenador detecta.
printf '%s' "$in" | grep -q '"stop_hook_active"[[:space:]]*:[[:space:]]*true' && exit 0
tp=$(printf '%s' "$in" | grep -o '"transcript_path"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed -E 's/.*:[[:space:]]*"//; s/"$//; s/\\\\/\\/g')
[ -n "$tp" ] && command -v cygpath >/dev/null 2>&1 && tp=$(cygpath -u "$tp")
[ -f "$tp" ] || exit 0
# O preâmbulo do Orca traz --dispatch-id; o último é o dispatch vigente (um terminal pode receber vários).
d=$(grep -o -- '--dispatch-id ctx_[0-9a-f]*' "$tp" | tail -1 | cut -d' ' -f2)
[ -n "$d" ] || exit 0
[ -n "${ORCA_TERMINAL_HANDLE:-}" ] && command -v orca >/dev/null 2>&1 || exit 0
show=$(orca orchestration worker-show --dispatch "$d" --json 2>/dev/null)
# Só o terminal designado é cobrado: o transcript do coordenador também cita --dispatch-id.
printf '%s' "$show" | grep -q "\"assigneeHandle\"[[:space:]]*:[[:space:]]*\"$ORCA_TERMINAL_HANDLE\"" || exit 0
st=$(printf '%s' "$show" | grep -o '"status"[[:space:]]*:[[:space:]]*"[a-z_]*"' | head -1 | cut -d'"' -f4)
case "$st" in ""|completed|failed|cancelled|abandoned) exit 0 ;; esac
# No transcript o preâmbulo vem com as aspas escapadas (\"); volta ao comando que se digita.
cmd=$(grep -o -- "orca orchestration send --from term_[A-Za-z0-9-]* --type worker_done.*--dispatch-id $d --outcome [a-z]*" "$tp" | head -1 | sed 's/\\"/"/g')
[ -n "$cmd" ] || cmd="orca orchestration send --type worker_done (comando completo no preâmbulo do Orca) --dispatch-id $d"
motivo="Você é worker do Orca (dispatch $d, status $st) e ainda não enviou o worker_done; sem ele o coordenador fica esperando. Se a tarefa terminou ou não tem como seguir, envie agora, uma vez: $cmd — com o resumo real em --subject/--body e --outcome failed se não concluiu. Se ainda há trabalho, continue."
motivo=$(printf '%s' "$motivo" | sed 's/\\/\\\\/g; s/"/\\"/g')
decisao=block; [ "${1:-}" = gemini ] && decisao=deny
printf '{"decision":"%s","reason":"%s"}\n' "$decisao" "$motivo"
exit 0

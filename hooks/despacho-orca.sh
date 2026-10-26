#!/bin/bash
# PreToolUse (Agent|Bash|PowerShell): trabalho (escrever, revisar) vai como worker do Orca; Agent tool só para consulta read-only.
in=$(cat)
# Fable fora do uso (custo alto sem ganho visível): vale mesmo com o Orca fora do ar.
if printf '%s' "$in" | grep -qiE '"model"[[:space:]]*:[[:space:]]*"[^"]*fable|--model[= ]+[^ ]*fable'; then
    echo "Fable fora do uso (decisão do usuário): use opus, sonnet ou haiku." >&2
    exit 2
fi
motivo=""
tool=$(printf '%s' "$in" | grep -oE '"tool_name"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed -E 's/.*"([^"]*)"$/\1/')
if [ "$tool" = "Agent" ]; then
    tipo=$(printf '%s' "$in" | grep -oE '"subagent_type"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed -E 's/.*"([^"]*)"$/\1/')
    case "$tipo" in
        Explore|claude-code-guide|Plan) exit 0 ;;
        auditoria-pre-subida:*) motivo="Auditor e verificador da auditoria-pre-subida vão como worker do Orca (skill delegacao, passo 5): orca-libera.sh --cria ... --command \"claude --agent $tipo --settings ~/.claude/agents/somente-leitura.json\" e worker-start --terminal <handle>." ;;
    esac
    if [ -z "$motivo" ] && printf '%s' "$in" | grep -qiE 'commit|implement|edit[ae]|refator|revis[aã]o|revise|review|git diff|merge|escritor|worktree da tarefa'; then
        motivo="Trabalho de escrita/revisão vai como worker do Orca: skill orchestration -> orca orchestration worker-start --spec ... --agent claude --model <id> --effort <nível>. Agent tool só para consulta read-only (Explore, claude-code-guide, Plan)."
    fi
elif printf '%s' "$in" | grep -qE '(^|["'"'"';&|( ])(claude|claude-team|agy)(\.exe)?[[:space:]][^;&|]*(-p|--print|--prompt)([[:space:]]|")' \
    && ! printf '%s' "$in" | grep -q '/usage'; then
    motivo="Despacho por -p bloqueado: use worker do Orca (skill orchestration). agy só como segunda opinião read-only, também via worker."
fi
[ -z "$motivo" ] && exit 0
# Orca fora do ar: não trava o trabalho.
orca status --json >/dev/null 2>&1 || exit 0
echo "$motivo" >&2
exit 2

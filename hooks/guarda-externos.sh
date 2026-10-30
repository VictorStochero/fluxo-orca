#!/bin/bash
# PreToolUse dos CLIs despachados sem humano (agy, codex): nega comando remoto, bulk replace e teste fora da fila.
# Uso: guarda-externos.sh [exit2|agy|codex] — exit2 = stderr + exit 2 (padrão genérico); agy = JSON {"decision":...}; codex = JSON hookSpecificOutput deny (exit 2 o Codex trata como falha e deixa passar).
formato=${1:-exit2}
in=$(cat)
motivo=""
if printf '%s' "$in" | grep -qE '(^|["'"'"';&|(]|\\n)[[:space:]]*(ssh|scp|rsync|sftp|forge)([[:space:]]|\.exe|")'; then
    motivo="Comando remoto bloqueado neste agente: ação em servidor só na sessão principal, com aprovação do usuário por comando."
elif printf '%s' "$in" | grep -qE '"replace_all"[[:space:]]*:[[:space:]]*true' \
    || printf '%s' "$in" | grep -qE '(^|[^[:alnum:]_-])(sed|perl)[[:space:]]+(-[[:alnum:]]*[[:space:]]+)*-[[:alnum:]]*i'; then
    motivo="Bulk replace bloqueado (sed -i, perl -i, replace_all): edite uma ocorrência por vez."
elif printf '%s' "$in" | bash "$(dirname "$0")/e-teste.sh"; then
    motivo="Teste bloqueado: rode pela fila única da máquina -> bash ~/.cache/fila-teste.sh <argumentos> (detecta a stack) ou bash ~/.cache/fila-teste.sh -- <comando> (se responder FILA OCUPADA, rode de novo)."
fi
if [ "$formato" = agy ]; then
    if [ -n "$motivo" ]; then
        printf '{"decision":"deny","reason":"%s"}\n' "$motivo"
    else
        printf '{"decision":"ask"}\n'
    fi
    exit 0
fi
if [ "$formato" = codex ]; then
    [ -n "$motivo" ] && printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$motivo"
    exit 0
fi
if [ -n "$motivo" ]; then
    echo "$motivo" >&2
    exit 2
fi
exit 0

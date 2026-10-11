#!/bin/bash
# PreToolUse (Bash|PowerShell|Edit): sem bulk replace — cada substituição é um Edit com old_string único.
in=$(cat)
if printf '%s' "$in" | grep -qE '"replace_all"[[:space:]]*:[[:space:]]*true'; then
    echo "Bloqueado: replace_all proibido. Faça um Edit por ocorrência, com old_string contextualizado e único." >&2
    exit 2
fi
if printf '%s' "$in" | grep -qE '"command"' \
    && printf '%s' "$in" | grep -qE '(^|[^[:alnum:]_-])(sed|perl)[[:space:]]+(-[[:alnum:]]*[[:space:]]+)*-[[:alnum:]]*i'; then
    echo "Bloqueado: edição in-place por sed/perl é bulk replace. Use Read + Edit, um arquivo e uma ocorrência por vez." >&2
    exit 2
fi
exit 0

#!/bin/bash
# PreToolUse (Bash|PowerShell): teste PHP só pela fila única da máquina (~/.cache/gs-teste.sh).
in=$(cat)
if printf '%s' "$in" | grep -qE 'artisan test|vendor/bin/pest|pestphp/pest/bin/pest' \
    && ! printf '%s' "$in" | grep -q 'gs-teste.sh' \
    && ! printf '%s' "$in" | grep -q -- '--list-tests'; then
    echo "Teste bloqueado: rode pela fila única da máquina -> bash ~/.cache/gs-teste.sh <argumentos do artisan test> (um teste por vez; se responder FILA OCUPADA, rode de novo)." >&2
    exit 2
fi
exit 0

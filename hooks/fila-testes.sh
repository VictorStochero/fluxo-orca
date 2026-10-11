#!/bin/bash
# PreToolUse (Bash|PowerShell): teste só pela fila única da máquina (~/.cache/gs-teste.sh).
# A detecção fica em skills/fila-testes/e-teste.sh (compartilhada com guarda-externos.sh).
if bash "$(dirname "$0")/../skills/fila-testes/e-teste.sh"; then
    echo "Teste bloqueado: rode pela fila única da máquina -> bash ~/.cache/gs-teste.sh <argumentos> (detecta a stack) ou bash ~/.cache/gs-teste.sh -- <comando> (um teste por vez; se responder FILA OCUPADA, rode de novo)." >&2
    exit 2
fi
exit 0

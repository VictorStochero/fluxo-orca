#!/bin/bash
# SessionStart: mantém em ~/.cache as cópias dos scripts que skills, agentes e workers chamam por caminho fixo.
. "$CLAUDE_PLUGIN_ROOT/hooks/lib-instala.sh"
copia_scripts "$CLAUDE_PLUGIN_ROOT" "$HOME/.cache"
mkdir -p "$HOME/.claude/agents"
cmp -s "$CLAUDE_PLUGIN_ROOT/extras/somente-leitura.json" "$HOME/.claude/agents/somente-leitura.json" \
    || cp "$CLAUDE_PLUGIN_ROOT/extras/somente-leitura.json" "$HOME/.claude/agents/"

# Agentes externos (Codex, agy): sem eles, nada abaixo.
command -v codex >/dev/null 2>&1 || command -v agy >/dev/null 2>&1 || exit 0

if command -v cygpath >/dev/null 2>&1; then
    gera_cmd guarda-externos-codex.cmd guarda-externos.sh codex
    gera_cmd guarda-externos-agy.cmd guarda-externos.sh agy
    gera_cmd fim-worker-codex.cmd fim-worker.sh codex
fi

copia_skills "$CLAUDE_PLUGIN_ROOT" "$HOME/.agents/skills"
exit 0

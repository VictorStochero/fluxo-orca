#!/bin/bash
# SessionStart: mantém em ~/.cache as cópias dos scripts que skills, agentes e workers chamam por caminho fixo.
mkdir -p "$HOME/.cache"
for s in fila-testes/gs-teste.sh limites-cota/limites.sh limites-cota/kimi-cota.sh; do
    cmp -s "$CLAUDE_PLUGIN_ROOT/skills/$s" "$HOME/.cache/$(basename "$s")" || cp "$CLAUDE_PLUGIN_ROOT/skills/$s" "$HOME/.cache/"
done
mkdir -p "$HOME/.claude/agents"
cmp -s "$CLAUDE_PLUGIN_ROOT/extras/somente-leitura.json" "$HOME/.claude/agents/somente-leitura.json" \
    || cp "$CLAUDE_PLUGIN_ROOT/extras/somente-leitura.json" "$HOME/.claude/agents/"
exit 0

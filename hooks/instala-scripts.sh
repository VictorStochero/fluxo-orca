#!/bin/bash
# SessionStart: mantém em ~/.cache as cópias dos scripts que skills, agentes e workers chamam por caminho fixo
# e avisa, ao abrir a sessão, quando o agent-pool (fila de testes e pool de agentes) não está instalado.
. "$CLAUDE_PLUGIN_ROOT/hooks/lib-instala.sh"
entrada=""; [ -t 0 ] || entrada=$(cat)
copia_scripts "$CLAUDE_PLUGIN_ROOT" "$HOME/.cache"
mkdir -p "$HOME/.claude/agents"
cmp -s "$CLAUDE_PLUGIN_ROOT/extras/somente-leitura.json" "$HOME/.claude/agents/somente-leitura.json" \
    || cp "$CLAUDE_PLUGIN_ROOT/extras/somente-leitura.json" "$HOME/.claude/agents/"

# Uma vez por sessão: resume/compact/clear refazem o SessionStart, mas a sessão já foi avisada na abertura.
case "$entrada" in *'"source"'*) origem=$(printf '%s' "$entrada" | grep -o '"source"[[:space:]]*:[[:space:]]*"[a-z]*"' | head -1 | cut -d'"' -f4) ;; *) origem=startup ;; esac
if [ "$origem" = startup ] && [ ! -e "$HOME/.agents/bin/agent-pool" ] && [ ! -e "$HOME/.agents/bin/agent-pool.cmd" ]; then
    aviso='fluxo-orca: o agent-pool não está instalado (falta ~/.agents/bin/agent-pool). Teste pela fila, pool de agentes e vagas dependem dele: instale o plugin agent-pool no Orca e aprove o acesso; ele importa o agentes.conf e o fila.conf.'
    printf '{"systemMessage":"%s","hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s"}}\n' "$aviso" "$aviso"
fi

# Agentes externos (Codex, agy): sem eles, nada abaixo.
command -v codex >/dev/null 2>&1 || command -v agy >/dev/null 2>&1 || exit 0

if command -v cygpath >/dev/null 2>&1; then
    gera_cmd guarda-externos-codex.cmd guarda-externos.sh codex
    gera_cmd guarda-externos-agy.cmd guarda-externos.sh agy
    gera_cmd fim-worker-codex.cmd fim-worker.sh codex
fi

# Destinos de skills vêm do catálogo; ~/.agents/skills vale com qualquer um dos dois, o do agy só com ele.
catalogo="$CLAUDE_PLUGIN_ROOT/skills/limites-cota/agentes-catalogo.conf"
destinos=$(skills_do_catalogo "$catalogo" codex)
command -v agy >/dev/null 2>&1 && destinos=$destinos$'\n'$(skills_do_catalogo "$catalogo" antigravity)
assinatura=$(assinatura_skills "$CLAUDE_PLUGIN_ROOT")
while IFS= read -r destino; do
    [ -n "$destino" ] || continue
    [ "$(cat "$destino/.fluxo-orca.assinatura" 2>/dev/null)" = "$assinatura" ] && continue
    copia_skills "$CLAUDE_PLUGIN_ROOT" "$destino"
    copia_skills_plugins "$CLAUDE_PLUGIN_ROOT" "$destino"
    # Depois da cópia: sessão interrompida no meio não marca o destino como feito.
    printf '%s
' "$assinatura" > "$destino/.fluxo-orca.assinatura"
done <<< "$destinos"
exit 0

#!/bin/bash
# Coordenar o fluxo com outro agente que não o Claude Code (sem o plugin, sem os hooks dele).
# Copia os scripts para ~/.cache, instala as regras do fluxo no arquivo global do agente, deixa as skills onde ele lê (ou um
# índice no arquivo de regras) e instala a trava de comando remoto e o fim-worker quando o agente tem hook (instala-agente.sh).
# Sem --aplicar só mostra o que faria; idempotente. Uso: instalar.sh --agente <id-do-catálogo> [--aplicar]
aqui=$(cd "$(dirname "$0")" && pwd)
agente=""; aplicar=""
while [ $# -gt 0 ]; do
    case "$1" in
        --agente) agente=${2:-}; shift 2 || break ;;
        --aplicar) aplicar=--aplicar; shift ;;
        *) agente=""; break ;;
    esac
done
if [ -z "$agente" ]; then
    echo 'uso: instalar.sh --agente <id> [--aplicar]' >&2
    echo "agentes (catálogo skills/limites-cota/agentes-catalogo.conf): $(grep -v -e '^#' -e '^[[:space:]]*$' "$aqui/skills/limites-cota/agentes-catalogo.conf" | cut -d'|' -f1 | tr '\n' ' ')" >&2
    exit 2
fi
exec bash "$aqui/skills/limites-cota/instala-agente.sh" "$agente" $aplicar

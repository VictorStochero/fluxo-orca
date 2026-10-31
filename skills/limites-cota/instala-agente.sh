#!/bin/bash
# Instala num agente externo o que o catálogo diz que ele suporta (agentes-catalogo.conf): regras, skills, trava de comando
# remoto (guarda-externos.sh no formato do hook dele) e fim-worker. Sem --aplicar só mostra; idempotente.
# Uso: instala-agente.sh <agente> [--aplicar]   (rodar a partir do plugin ou do clone do repo)
aqui=$(cd "$(dirname "$0")" && pwd)
RAIZ=$(cd "$aqui/../.." && pwd)
agente=${1:-}; APLICAR=0
[ "${2:-}" = --aplicar ] && APLICAR=1
if [ -z "$agente" ] || [ $# -gt 2 ] || { [ $# = 2 ] && [ $APLICAR = 0 ]; }; then
    echo 'uso: instala-agente.sh <agente> [--aplicar]' >&2; exit 2
fi
. "$aqui/contas.sh"
. "$RAIZ/hooks/lib-instala.sh"
_contas_define a "$agente" || { echo "instala-agente: agente fora do catálogo ($agente)" >&2; exit 2; }
pre=$(conta_campo a pre); fim=$(conta_campo a fim)
cache="$HOME/.cache"
DRY=--dry; [ $APLICAR = 1 ] && DRY=""
INI='<!-- fluxo-orca:inicio -->'; FIM='<!-- fluxo-orca:fim -->'
WIN=0; command -v cygpath >/dev/null 2>&1 && WIN=1

exp() { case "$1" in "~/"*) printf '%s' "$HOME/${1#"~/"}" ;; *) printf '%s' "$1" ;; esac; }
py() { local p; for p in python3 python; do "$p" -c '' 2>/dev/null && { "$p" -I "$aqui/grava-hook.py" "$@"; return; }; done; echo 'instala-agente: precisa de python' >&2; return 1; }
passo() { # estado descrição: estado = ja | novo
    case "$1" in
        ja) echo "  [ja instalado] $2" ;;
        *) if [ $APLICAR = 1 ]; then echo "  [instalado]    $2"; else echo "  [instalaria]   $2"; fi ;;
    esac
}
# Comando do hook: no Windows o CLI chama um .cmd (gera_cmd) com caminho absoluto; nos demais, bash direto.
comando_hook() { # nome-sem-extensão script [argumento]
    if [ $WIN = 1 ]; then
        [ $APLICAR = 1 ] && gera_cmd "$1.cmd" "$2" "$3"
        cygpath -m "$cache/$1.cmd"
    else
        printf 'bash %s/%s%s' "$cache" "$2" "${3:+ $3}"
    fi
}
cfg_hook() { # arquivo caminho grupo-json → HOOK_ESTADO (ja|novo) e HOOK_N (posição na lista)
    local r
    r=$(py hook "$1" "$2" "$3" $DRY) || exit 1
    HOOK_N=${r#* }; HOOK_ESTADO=${r%% *}
}

indice_skills() { # agente sem diretório de skills: o arquivo de regras aponta para as cópias em ~/.agents/skills
    local d n desc
    echo; echo '## Skills (ler o SKILL.md quando a tarefa tocar o assunto)'
    for d in "$RAIZ"/skills/*/; do
        n=$(basename "$d"); desc=$(grep -m1 '^description:' "$d/SKILL.md" | cut -c14-200)
        echo "- \`$n\` — ~/.agents/skills/$n/SKILL.md: $desc"
    done
}

instala_regras() {
    local f bloco atual novo
    f=$(exp "$(conta_campo a regras)")
    if [ "$f" = - ]; then echo "  [manual]       sem arquivo global de regras conhecido: coloque extras/AGENTS.global.md onde o $agente lê instruções"; return; fi
    bloco=$(printf '%s\n' "$INI"; cat "$RAIZ/extras/AGENTS.global.md"; [ "$(conta_campo a skills)" = - ] && indice_skills; printf '%s' "$FIM")
    atual=$(cat "$f" 2>/dev/null)
    case "$atual" in
        *"$INI"*) novo=${atual%%"$INI"*}$bloco${atual#*"$FIM"} ;;
        *) novo=${atual:+$atual$'\n\n'}$bloco ;;
    esac
    if [ "$novo" = "$atual" ]; then passo ja "regras em $f"; return; fi
    passo novo "regras em $f"
    if [ $APLICAR = 1 ]; then mkdir -p "$(dirname "$f")"; printf '%s\n' "$novo" > "$f"; fi
}

instala_skills() {
    local dest d igual=1
    dest=$(exp "$(conta_campo a skills)"); [ "$dest" = - ] && dest="$HOME/.agents/skills"
    for d in "$RAIZ"/skills/*/; do
        diff -rq "$d" "$dest/$(basename "$d")" >/dev/null 2>&1 || igual=0
    done
    if [ $igual = 1 ]; then passo ja "skills em $dest"; return; fi
    passo novo "skills em $dest"
    [ $APLICAR = 1 ] && copia_skills "$RAIZ" "$dest"
}

confia_codex() { # evento n comando timeout: hook novo do Codex só roda se estiver confiável no config.toml
    local r hj="$HOME/.codex/hooks.json"
    [ $WIN = 1 ] && hj=$(cygpath -m "$hj")
    r=$(py confia "$HOME/.codex/config.toml" "$hj" "$1" "$2" "$3" "$4" $DRY) || exit 1
    passo "$r" "confiança do hook $1 em ~/.codex/config.toml"
}

toml_hook() { # arquivo evento matcher comando timeout descrição
    if grep -qF "command = \"$4\"" "$1" 2>/dev/null; then passo ja "$6 em $1"; return; fi
    passo novo "$6 em $1"
    [ $APLICAR = 1 ] || return 0
    mkdir -p "$(dirname "$1")"
    { printf '\n[[hooks]]\nevent = "%s"\n' "$2"; [ -n "$3" ] && printf 'matcher = "%s"\n' "$3"; printf 'command = "%s"\ntimeout = %s\n' "$4" "$5"; } >> "$1"
}

instala_trava() {
    local cmd arq
    case "$agente" in
        codex)
            arq="$HOME/.codex/hooks.json"; cmd=$(comando_hook guarda-externos-codex guarda-externos.sh codex)
            cfg_hook "$arq" hooks.PreToolUse "{\"hooks\":[{\"type\":\"command\",\"command\":\"$cmd\",\"timeout\":10}]}"
            passo "$HOOK_ESTADO" "trava (PreToolUse) em $arq"
            confia_codex pre_tool_use "$HOOK_N" "$cmd" 10 ;;
        antigravity)
            arq="$HOME/.gemini/config/hooks.json"; cmd=$(comando_hook guarda-externos-agy guarda-externos.sh agy)
            cfg_hook "$arq" guarda-externos.PreToolUse "{\"matcher\":\"*\",\"hooks\":[{\"type\":\"command\",\"command\":\"$cmd\",\"timeout\":10}]}"
            passo "$HOOK_ESTADO" "trava (PreToolUse) em $arq" ;;
        gemini)
            arq="$HOME/.gemini/settings.json"; cmd=$(comando_hook guarda-externos-gemini guarda-externos.sh gemini)
            cfg_hook "$arq" hooks.BeforeTool "{\"matcher\":\"run_shell_command\",\"hooks\":[{\"type\":\"command\",\"command\":\"$cmd\",\"name\":\"fluxo-guarda\",\"timeout\":10000}]}"
            passo "$HOOK_ESTADO" "trava (BeforeTool) em $arq" ;;
        zcode)
            arq="$HOME/.zcode/cli/config.json"; cmd=$(comando_hook guarda-externos-exit2 guarda-externos.sh exit2)
            passo "$(py set "$arq" hooks.enabled true $DRY)" "hooks.enabled em $arq"
            cfg_hook "$arq" hooks.events.PreToolUse "{\"matcher\":\"Bash\",\"hooks\":[{\"type\":\"command\",\"command\":\"$cmd\",\"timeoutMs\":10000}]}"
            passo "$HOOK_ESTADO" "trava (PreToolUse) em $arq" ;;
        kimi)
            arq="$HOME/.kimi-code/config.toml"; cmd=$(comando_hook guarda-externos-exit2 guarda-externos.sh exit2)
            toml_hook "$arq" PreToolUse 'Shell|Bash' "$cmd" 10 "trava (PreToolUse)" ;;
        opencode | opencode2)
            arq="$HOME/.config/opencode/plugins/fluxo-guarda.js"
            if cmp -s "$RAIZ/extras/opencode-guarda.js" "$arq"; then
                passo ja "plugin de trava em $arq"
            else
                passo novo "plugin de trava em $arq"
                [ $APLICAR = 1 ] && { mkdir -p "$(dirname "$arq")"; cp "$RAIZ/extras/opencode-guarda.js" "$arq"; }
            fi ;;
        *) echo "  [manual]       $agente tem pre=sim no catálogo, mas o instalador não conhece o formato do hook dele" ;;
    esac
}

instala_fim() {
    local cmd arq
    case "$agente" in
        codex)
            arq="$HOME/.codex/hooks.json"; cmd=$(comando_hook fim-worker-codex fim-worker.sh codex)
            cfg_hook "$arq" hooks.Stop "{\"hooks\":[{\"type\":\"command\",\"command\":\"$cmd\",\"timeout\":15}]}"
            passo "$HOOK_ESTADO" "fim de turno (Stop) em $arq"
            confia_codex stop "$HOOK_N" "$cmd" 15 ;;
        gemini)
            arq="$HOME/.gemini/settings.json"; cmd=$(comando_hook fim-worker-gemini fim-worker.sh gemini)
            cfg_hook "$arq" hooks.AfterAgent "{\"hooks\":[{\"type\":\"command\",\"command\":\"$cmd\",\"name\":\"fluxo-fim-worker\",\"timeout\":15000}]}"
            passo "$HOOK_ESTADO" "fim de turno (AfterAgent) em $arq" ;;
        kimi)
            arq="$HOME/.kimi-code/config.toml"; cmd=$(comando_hook fim-worker-kimi fim-worker.sh)
            toml_hook "$arq" Stop '' "$cmd" 15 "fim de turno (Stop)" ;;
        *) echo "  [manual]       $agente tem fim=sim no catálogo, mas o instalador não conhece o formato do hook dele" ;;
    esac
}

echo "instala-agente: $agente (pre=$pre fim=$fim regras=$(conta_campo a regras) skills=$(conta_campo a skills))"
if [ "$agente" = claude ]; then echo '  Claude Code usa o próprio plugin (hooks, skills e regras); nada a instalar.'; exit 0; fi
echo "  [scripts]      guarda-externos.sh, fim-worker.sh e demais em $cache"
[ $APLICAR = 1 ] && copia_scripts "$RAIZ" "$cache"
instala_regras
instala_skills
if [ "$pre" = sim ]; then
    instala_trava
    [ "$fim" = sim ] && instala_fim
else
    echo "  [restrito]     $agente sem hook de comando: fica só em segunda-opiniao (papel de trabalho é recusado pelo contas.sh)"
fi
[ $APLICAR = 1 ] || echo 'simulação: nada foi gravado; rode de novo com --aplicar.'
exit 0

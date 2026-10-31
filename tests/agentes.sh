#!/usr/bin/env bash
# Prova dos outros agentes como worker: formatos da trava (guarda-externos.sh), fim-worker do Gemini, instalador por agente
# (instala-agente.sh) e scripts compartilhados (hooks/instala-scripts.sh). HOME isolado: não toca em ~/.cache nem nas configs reais.
raiz=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
falhas=0
ok() { echo "ok   $1"; }
ruim() { echo "FALHA $1"; falhas=$((falhas + 1)); }
igual() { if [ "$2" = "$3" ]; then ok "$1"; else ruim "$1: esperado [$2], veio [$3]"; fi; }
contem() { case "$3" in *"$2"*) ok "$1" ;; *) ruim "$1: faltou [$2] em [$3]" ;; esac; }
nao_contem() { case "$3" in *"$2"*) ruim "$1: sobrou [$2] em [$3]" ;; *) ok "$1" ;; esac; }
py() { local p; for p in python3 python; do "$p" -c '' 2>/dev/null && { "$p" -I "$@"; return; }; done; return 1; }

export HOME="$tmp/home"
mkdir -p "$HOME/.cache"
cp "$raiz/hooks/guarda-externos.sh" "$raiz/hooks/fim-worker.sh" "$raiz/skills/fila-testes/e-teste.sh" "$HOME/.cache/"

# --- guarda-externos.sh: um exemplo de cada formato de hook ---
ssh_gemini='{"hook_event_name":"BeforeTool","tool_name":"run_shell_command","tool_input":{"command":"ssh -V"}}'
ls_gemini='{"hook_event_name":"BeforeTool","tool_name":"run_shell_command","tool_input":{"command":"ls -la"}}'
saida=$(printf '%s' "$ssh_gemini" | bash "$HOME/.cache/guarda-externos.sh" gemini)
contem 'gemini: ssh negado em JSON' '"decision":"deny"' "$saida"
igual 'gemini: comando comum passa sem saída' '' "$(printf '%s' "$ls_gemini" | bash "$HOME/.cache/guarda-externos.sh" gemini)"
printf '%s' "$ssh_gemini" | bash "$HOME/.cache/guarda-externos.sh" gemini >/dev/null; igual 'gemini: sai 0 (o bloqueio é o JSON)' 0 $?
contem 'gemini: JSON válido' 'ok' "$(printf '%s' "$saida" | py -c 'import json,sys; json.load(sys.stdin); print("ok")')"
ssh_kimi='{"hook_event_name":"PreToolUse","tool_name":"Shell","tool_input":{"command":"scp a b:/c"}}'
printf '%s' "$ssh_kimi" | bash "$HOME/.cache/guarda-externos.sh" exit2 2>/dev/null; igual 'kimi/zcode: ssh sai 2' 2 $?
printf '%s' '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"git status"}}' | bash "$HOME/.cache/guarda-externos.sh" exit2 2>/dev/null
igual 'kimi/zcode: comando comum sai 0' 0 $?
printf '%s' '{"tool_name":"Bash","tool_input":{"command":"php artisan test"}}' | bash "$HOME/.cache/guarda-externos.sh" exit2 2>/dev/null
igual 'exit2: teste fora da fila sai 2' 2 $?

# --- plugin do opencode: mesmo guarda, via tool.execute.before ---
if command -v node >/dev/null 2>&1; then
    cp "$raiz/extras/opencode-guarda.js" "$tmp/guarda.mjs"
    cat > "$tmp/roda.mjs" <<'E'
// os.homedir() no Windows lê USERPROFILE, não HOME: sem isto o plugin usaria o ~/.cache real.
process.env.USERPROFILE = process.env.HOME
const { FluxoGuarda } = await import(process.argv[2])
const h = await FluxoGuarda()
try { await h["tool.execute.before"]({ tool: "bash" }, { args: { command: process.argv[3] } }); console.log("passou") }
catch (e) { console.log("bloqueou: " + e.message) }
E
    url=$(py -c 'import pathlib,sys; print(pathlib.Path(sys.argv[1]).resolve().as_uri())' "$tmp/guarda.mjs")
    contem 'opencode: ssh bloqueado pelo plugin' 'bloqueou: Comando remoto' "$(node "$tmp/roda.mjs" "$url" 'ssh -V')"
    igual 'opencode: comando comum passa' 'passou' "$(node "$tmp/roda.mjs" "$url" 'ls')"
    mkdir -p "$tmp/sem-bash"
    contem 'opencode: sem bash no PATH bloqueia (falha fechada)' 'bloqueou: fluxo-guarda indisponível' "$(PATH="$tmp/sem-bash" "$(command -v node)" "$tmp/roda.mjs" "$url" 'ls')"
else
    echo 'pulado: plugin do opencode (sem node)'
fi

# --- fim-worker.sh: Gemini recebe deny, os demais block ---
mkdir -p "$tmp/bin"
cat > "$tmp/bin/orca" <<'E'
#!/bin/bash
echo '{"assigneeHandle":"term_t","status":"running"}'
E
chmod +x "$tmp/bin/orca"
printf 'preâmbulo --dispatch-id ctx_abc123 fim\n' > "$tmp/transcript.txt"
entrada=$(printf '{"transcript_path":"%s"}' "$tmp/transcript.txt")
fim() { printf '%s' "$entrada" | PATH="$tmp/bin:$PATH" ORCA_TERMINAL_HANDLE=term_t bash "$HOME/.cache/fim-worker.sh" "$@"; }
contem 'fim-worker: padrão bloqueia com block' '"decision":"block"' "$(fim)"
contem 'fim-worker: gemini usa deny' '"decision":"deny"' "$(fim gemini)"

# --- instala-agente.sh ---
inst() { bash "$raiz/skills/limites-cota/instala-agente.sh" "$@" 2>&1; }
ha_json() { # arquivo programa python (d = JSON carregado) → imprime o resultado
    py -c 'import json,sys; d=json.load(open(sys.argv[1])); print(eval(sys.argv[2]))' "$1" "$2"
}
sem_mudanca() { # nome agente: segunda execução só diz "ja instalado"
    local s
    s=$(inst "$2" --aplicar)
    nao_contem "$1: segunda execução não instala" '[instalado]' "$s"
    nao_contem "$1: segunda execução não planeja" '[instalaria]' "$s"
}

# Uso e agente inexistente.
inst >/dev/null; igual 'uso: sem argumento' 2 $?
inst codex --agora >/dev/null; igual 'uso: opção desconhecida' 2 $?
inst nenhum >/dev/null; igual 'agente fora do catálogo' 2 $?

# Codex: simulação não grava; --aplicar preserva o grupo do Orca, grava a trava, o fim e a confiança.
mkdir -p "$HOME/.codex"
cat > "$HOME/.codex/hooks.json" <<'E'
{"hooks":{"PreToolUse":[{"hooks":[{"type":"command","command":"orca-hook","timeout":10}]}],"Stop":[{"hooks":[{"type":"command","command":"orca-hook","timeout":10}]}]}}
E
printf 'minhas regras\n' > "$HOME/.codex/AGENTS.md"
antes=$(cat "$HOME/.codex/hooks.json")
saida=$(inst codex)
contem 'codex: simulação anuncia' '[instalaria]' "$saida"
contem 'codex: simulação avisa que nada gravou' 'nada foi gravado' "$saida"
igual 'codex: simulação não altera hooks.json' "$antes" "$(cat "$HOME/.codex/hooks.json")"
igual 'codex: simulação não altera as regras' 'minhas regras' "$(cat "$HOME/.codex/AGENTS.md")"
[ ! -e "$HOME/.codex/config.toml" ] && ok 'codex: simulação não cria config.toml' || ruim 'codex: simulação criou config.toml'
[ ! -e "$HOME/.cache/trava-codex.ok" ] && ok 'codex: simulação não grava o carimbo da trava' || ruim 'codex: simulação gravou o carimbo'
inst codex --aplicar >/dev/null
[ -s "$HOME/.cache/trava-codex.ok" ] && ok 'codex: --aplicar grava o carimbo da trava' || ruim 'codex: carimbo da trava ausente'
igual 'codex: grupo do Orca preservado' orca-hook "$(ha_json "$HOME/.codex/hooks.json" 'd["hooks"]["PreToolUse"][0]["hooks"][0]["command"]')"
contem 'codex: trava em PreToolUse' guarda-externos "$(ha_json "$HOME/.codex/hooks.json" 'd["hooks"]["PreToolUse"][1]["hooks"][0]["command"]')"
contem 'codex: fim em Stop' fim-worker "$(ha_json "$HOME/.codex/hooks.json" 'd["hooks"]["Stop"][1]["hooks"][0]["command"]')"
toml=$(cat "$HOME/.codex/config.toml")
contem 'codex: confiança da trava' ".codex/hooks.json:pre_tool_use:1:0']" "$toml"
contem 'codex: confiança do fim' ".codex/hooks.json:stop:1:0']" "$toml"
contem 'codex: hash gravado' 'trusted_hash = "sha256:' "$toml"
contem 'codex: regras preservam o texto do usuário' 'minhas regras' "$(cat "$HOME/.codex/AGENTS.md")"
contem 'codex: regras do fluxo' 'fluxo-orca:inicio' "$(cat "$HOME/.codex/AGENTS.md")"
[ -f "$HOME/.agents/skills/fila-testes/SKILL.md" ] && ok 'codex: skills copiadas' || ruim 'codex: skills não copiadas'
[ -f "$HOME/.cache/fila-teste.sh" ] && ok 'codex: scripts em ~/.cache' || ruim 'codex: scripts não copiados'
sem_mudanca codex codex
copia=$(cat "$HOME/.codex/hooks.json" "$HOME/.codex/config.toml" "$HOME/.codex/AGENTS.md")
inst codex --aplicar >/dev/null
igual 'codex: idempotente (arquivos idênticos)' "$copia" "$(cat "$HOME/.codex/hooks.json" "$HOME/.codex/config.toml" "$HOME/.codex/AGENTS.md")"

# Gemini (agente novo com hook): BeforeTool e AfterAgent no settings.json do usuário, sem perder o que já havia.
mkdir -p "$HOME/.gemini"
printf '{"theme":"dark"}\n' > "$HOME/.gemini/settings.json"
inst gemini --aplicar >/dev/null
igual 'gemini: configuração do usuário preservada' dark "$(ha_json "$HOME/.gemini/settings.json" 'd["theme"]')"
igual 'gemini: matcher do shell' run_shell_command "$(ha_json "$HOME/.gemini/settings.json" 'd["hooks"]["BeforeTool"][0]["matcher"]')"
contem 'gemini: trava no formato gemini' 'guarda-externos' "$(ha_json "$HOME/.gemini/settings.json" 'd["hooks"]["BeforeTool"][0]["hooks"][0]["command"]')"
contem 'gemini: fim no AfterAgent' 'fim-worker' "$(ha_json "$HOME/.gemini/settings.json" 'd["hooks"]["AfterAgent"][0]["hooks"][0]["command"]')"
igual 'gemini: timeout em milissegundos' 10000 "$(ha_json "$HOME/.gemini/settings.json" 'd["hooks"]["BeforeTool"][0]["hooks"][0]["timeout"]')"
contem 'gemini: regras em GEMINI.md' 'fluxo-orca:inicio' "$(cat "$HOME/.gemini/GEMINI.md")"
sem_mudanca gemini gemini

# Kimi: [[hooks]] no config.toml.
inst kimi --aplicar >/dev/null
toml=$(cat "$HOME/.kimi-code/config.toml")
contem 'kimi: PreToolUse' 'event = "PreToolUse"' "$toml"
contem 'kimi: Stop' 'event = "Stop"' "$toml"
contem 'kimi: matcher do shell' 'matcher = "Shell|Bash"' "$toml"
sem_mudanca kimi kimi

# ZCode: liga hooks.enabled e grava o evento.
inst zcode --aplicar >/dev/null
igual 'zcode: hooks.enabled' True "$(ha_json "$HOME/.zcode/cli/config.json" 'd["hooks"]["enabled"]')"
igual 'zcode: matcher Bash' Bash "$(ha_json "$HOME/.zcode/cli/config.json" 'd["hooks"]["events"]["PreToolUse"][0]["matcher"]')"
sem_mudanca zcode zcode

# opencode: plugin de trava; sem fim de turno.
inst opencode --aplicar >/dev/null
cmp -s "$raiz/extras/opencode-guarda.js" "$HOME/.config/opencode/plugins/fluxo-guarda.js" && ok 'opencode: plugin instalado' || ruim 'opencode: plugin ausente'
contem 'opencode: regras em ~/.config/opencode/AGENTS.md' 'fluxo-orca:inicio' "$(cat "$HOME/.config/opencode/AGENTS.md")"
sem_mudanca opencode opencode

# Cópia antiga das regras (cabeçalho sem marcador): avisa e não anexa outra.
mkdir -p "$HOME/.config/opencode"
printf '# Regras globais — cópia antiga\nx\n' > "$HOME/.config/opencode/AGENTS.md"
saida=$(inst opencode --aplicar)
contem 'regras: cópia antiga avisa' "[aviso] cópia antiga sem marcador em $HOME/.config/opencode/AGENTS.md: remova-a" "$saida"
igual 'regras: cópia antiga não ganha outro bloco' 0 "$(grep -c 'fluxo-orca:inicio' "$HOME/.config/opencode/AGENTS.md")"

# Atalho ~/.cache/instala-agente.sh: roda o script real pela raiz gravada; sem a raiz, erro claro.
CLAUDE_PLUGIN_ROOT="$raiz" bash "$raiz/hooks/instala-scripts.sh"
contem 'atalho: executa o instalador real' 'instala-agente: codex' "$(bash "$HOME/.cache/instala-agente.sh" codex)"
rm "$HOME/.cache/fluxo-orca-raiz"
saida=$(bash "$HOME/.cache/instala-agente.sh" codex 2>&1); rc=$?
igual 'atalho: sem a raiz falha' 1 "$rc"
contem 'atalho: sem a raiz explica' 'raiz do fluxo-orca desconhecida' "$saida"
CLAUDE_PLUGIN_ROOT="$raiz" bash "$raiz/hooks/instala-scripts.sh"

# Agy: trava no hooks.json do Antigravity, skills no diretório dele.
mkdir -p "$HOME/.gemini/config"
inst antigravity --aplicar >/dev/null
igual 'agy: matcher *' '*' "$(ha_json "$HOME/.gemini/config/hooks.json" 'd["guarda-externos"]["PreToolUse"][0]["matcher"]')"
[ -f "$HOME/.gemini/config/skills/fila-testes/SKILL.md" ] && ok 'agy: skills no diretório do agente' || ruim 'agy: skills fora do diretório do agente'
sem_mudanca antigravity antigravity

# Sem hook (cursor) e sem arquivo de regras (agente desconhecido do catálogo): só avisa; nada de trava.
saida=$(inst cursor --aplicar)
contem 'cursor: restrito a segunda opinião' 'segunda-opiniao' "$saida"
contem 'cursor: sem arquivo de regras' '[manual]' "$saida"
[ ! -e "$HOME/.cursor" ] && ok 'cursor: nenhuma config criada' || ruim 'cursor: criou config'
saida=$(inst claude)
contem 'claude: nada a instalar' 'nada a instalar' "$saida"

# Sem arquivo de skills do agente, o índice entra no arquivo de regras (cursor não tem; agente desconhecido idem).
saida=$(inst aider --aplicar)
contem 'aider: sem regras conhecidas' '[manual]' "$saida"

# --- hooks/instala-scripts.sh usa a lista compartilhada ---
rm -rf "$HOME/.cache"; mkdir -p "$HOME"
CLAUDE_PLUGIN_ROOT="$raiz" bash "$raiz/hooks/instala-scripts.sh"
faltou=""
while IFS= read -r s; do
    case "$s" in '' | '#'*) continue ;; esac
    [ -f "$HOME/.cache/$(basename "$s")" ] || faltou="$faltou $s"
done < "$raiz/hooks/scripts.lista"
igual 'instala-scripts: tudo da lista em ~/.cache' '' "$faltou"
[ -f "$HOME/.cache/medidores/claude.sh" ] && ok 'instala-scripts: medidores' || ruim 'instala-scripts: medidores ausentes'
[ -f "$HOME/.claude/agents/somente-leitura.json" ] && ok 'instala-scripts: somente-leitura.json' || ruim 'instala-scripts: somente-leitura.json ausente'

[ "$falhas" = 0 ] && echo "tudo ok" || { echo "$falhas falha(s)"; exit 1; }

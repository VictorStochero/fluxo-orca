#!/usr/bin/env bash
# Contrato V3: a visão concisa não tem os campos usados pelo hook, pool e liberação.
raiz=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
export HOME="$tmp/home" ORCA_V3_DIR="$tmp"
mkdir -p "$HOME/.claude" "$tmp/bin"
printf 'a agente=claude vagas=1\n' > "$HOME/.claude/agentes.conf"
cat > "$tmp/bin/orca" <<'EOF'
#!/usr/bin/env bash
case "$1 $2" in
    'orchestration worker-show')
        case "$*" in
            *--full*) printf '{"ok":true,"result":{"dispatch":{"id":"ctx_abc123","status":"%s","assigneeHandle":"term_t","runId":"run_t"},"worker":{"agentTerminalHandle":"term_t"}}}\n' "${ORCA_V3_STATUS:-completed}" ;;
            *) echo '{"ok":true,"result":{"dispatchId":"ctx_abc123","state":"succeeded","terminal":"term_t","runId":"run_t"}}' ;;
        esac ;;
    'orchestration worker-list')
        [ "${ORCA_V3_VIGIA:-}" = 1 ] && echo 60 > "$ORCA_V3_DIR/relogio"
        case "$*" in
            *--full*)
                if [ "${ORCA_V3_LISTA:-}" = vazia ]; then echo '{"ok":true,"result":{"workers":[]}}'
                else echo '{"ok":true,"result":{"workers":[{"dispatchId":"ctx_abc123","dispatchStatus":"completed","agentTerminalHandle":"term_t"}]}}'; fi ;;
            *) echo '{"ok":true,"result":{"workers":[{"dispatchId":"ctx_abc123","state":"succeeded","terminal":"term_t"}]}}' ;;
        esac ;;
    'orchestration worker-release') echo '{"ok":true,"result":{"state":"retained","reason":"external_terminal"}}' ;;
    'orchestration check') touch "$ORCA_V3_DIR/check"; echo 60 > "$ORCA_V3_DIR/relogio"; echo '{"ok":true,"result":{}}' ;;
    'terminal create') echo '{"ok":true,"result":{"terminal":{"handle":"term_t"}}}' ;;
    'terminal close') touch "$ORCA_V3_DIR/fechou"; echo '{"ok":true}' ;;
    *) exit 2 ;;
esac
EOF
chmod +x "$tmp/bin/orca"
export PATH="$tmp/bin:$PATH" ORCA_CMD="$tmp/bin/orca"
falhas=0
confere() { if "$@"; then echo "ok   $*"; else echo "FALHA $*"; falhas=$((falhas + 1)); fi; }
printf 'preâmbulo --dispatch-id ctx_abc123 fim\n' > "$tmp/transcript"
entrada=$(printf '{"transcript_path":"%s"}' "$tmp/transcript")
saida=$(printf '%s' "$entrada" | ORCA_V3_STATUS=running ORCA_TERMINAL_HANDLE=term_t bash "$raiz/hooks/fim-worker.sh")
confere grep -q '"decision":"block"' <<< "$saida"

pool() { bash "$raiz/skills/limites-cota/vaga-agente.sh" "$@"; }
for lista in cheia vazia; do
    export ORCA_V3_LISTA="$lista"
    mkdir -p "$HOME/.cache/agentes/a.lock1"
    echo ctx_abc123 > "$HOME/.cache/agentes/a.lock1/dispatch"
    saida=$(pool livres)
    confere grep -qx 'a 1/1' <<< "$saida"
    confere test ! -d "$HOME/.cache/agentes/a.lock1"
    rm -rf "$HOME/.cache/agentes/a.lock1"
done
bash "$raiz/skills/delegacao/orca-libera.sh" --cria --worktree x > /dev/null
saida=$(bash "$raiz/skills/delegacao/orca-libera.sh" ctx_abc123)
confere test -f "$tmp/fechou"
confere grep -q 'aba term_t fechada' <<< "$saida"

# Um ciclo basta: a consulta avança o prazo; sleep não espera um minuto real.
data=$(command -v date)
echo 0 > "$tmp/relogio"
cat > "$tmp/bin/date" <<EOF
#!/bin/bash
if [ "\$*" = +%s ]; then echo \$(( \$("$data" +%s) + \$(cat "$tmp/relogio") )); else "$data" "\$@"; fi
EOF
printf '#!/bin/bash\nexit 0\n' > "$tmp/bin/sleep"
chmod +x "$tmp/bin/date" "$tmp/bin/sleep"
ORCA_V3_VIGIA=1 ORCA_ESPERA_COTA_MIN=0 bash "$raiz/skills/delegacao/orca-espera.sh" --run run_v3 --max-min 1 > "$tmp/vigia"
confere test ! -f "$tmp/check"
confere grep -q 'Rearmar:' "$tmp/vigia"
[ "$falhas" = 0 ] && echo 'TUDO OK' || { echo "$falhas falha(s)"; exit 1; }

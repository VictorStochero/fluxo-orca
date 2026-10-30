#!/usr/bin/env bash
raiz=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
export HOME="$tmp/home" RAM_CENARIO="$tmp" ORCA_CMD="$tmp/orca"
mkdir -p "$HOME"
cat > "$tmp/orca" <<'EOF'
#!/usr/bin/env bash
echo "$*" >> "$RAM_CENARIO/chamadas"
case "$1 $2" in
    'diagnostics memory') cat "$RAM_CENARIO/memoria.json" ;;
    'orchestration check')
        [ -n "${RAM_TESTA_INVALIDO:-}" ] && { echo '{"ok":true,"result":{"deliveryId":"d_ram","messages":[{"type":"worker_done"}]}}'; exit 0; }
        case "$*" in *--ack*) echo '{"ok":true,"result":{}}' ;; *) echo '{"ok":true,"result":{"deliveryId":"d_ram","messages":[{"type":"heartbeat"}]}}' ;; esac ;;
    'orchestration worker-list')
        [ -n "${RAM_TESTA_INVALIDO:-}" ] && { echo '{"ok":true,"result":{"workers":[]}}'; exit 0; }
        case "$*" in *--cursor*) cat "$RAM_CENARIO/pagina2.json" ;; *) cat "$RAM_CENARIO/pagina1.json" ;; esac ;;
    *) exit 2 ;;
esac
EOF
chmod +x "$tmp/orca"
cat > "$tmp/memoria.json" <<'EOF'
{"ok":true,"result":{"host":{"availableMemory":4294967296},"worktrees":[
 {"worktreeId":"r::/a","worktreeName":"projeto-a","sessions":[{"sessionId":"r::/a@@idle","pid":10,"cpu":0,"memory":2147483648},{"pid":11,"cpu":0,"memory":1073741824},{"pid":12,"cpu":1,"memory":3221225472}]},
 {"worktreeId":"r::/b","worktreeName":"projeto-b","sessions":[{"pid":20,"cpu":0,"memory":536870912}]}]}}
EOF
printf '%s\n' '{"ok":true,"result":{"workers":[],"page":{"hasMore":true,"nextCursor":"pagina2"}}}' > "$tmp/pagina1.json"
cat > "$tmp/pagina2.json" <<'EOF'
{"ok":true,"result":{"workers":[
 {"dispatchId":"ctx_retido","dispatchStatus":"completed","terminalState":"retained","agentTerminalHandle":"term_a","resource":{"worktreeId":"r::/a","endpointIncarnation":"r::/a@@idle:instancia"}},
 {"dispatchId":"ctx_inexistente","dispatchStatus":"completed","terminalState":"retained","agentTerminalHandle":"term_antigo","resource":{"worktreeId":"r::/a","endpointIncarnation":"r::/a@@fechado:instancia"}},
 {"dispatchId":"ctx_antigo","dispatchStatus":"completed","terminalState":"retained","agentTerminalHandle":"term_b","resource":{"worktreeId":"r::/b"}},
 {"dispatchId":"ctx_ativo","dispatchStatus":"dispatched","terminalState":"active","agentTerminalHandle":"term_b","resource":{"worktreeId":"r::/b"}}],"page":{"hasMore":false}}}
EOF
falhas=0
confere() { if "$@"; then echo "ok   $*"; else echo "FALHA $*"; falhas=$((falhas + 1)); fi; }
bash "$raiz/skills/delegacao/orca-ram.sh" > "$tmp/saida" 2>&1
confere grep -q 'RAM disponível: 4,0 GB' "$tmp/saida"
confere grep -q 'worker concluído e retido' "$tmp/saida"
confere grep -q 'bash ~/.cache/orca-libera.sh ctx_retido' "$tmp/saida"
if grep -q 'PID 12\|ctx_antigo\|ctx_inexistente' "$tmp/saida"; then echo 'FALHA incluiu sessão ativa ou ausente'; falhas=$((falhas + 1)); fi
ordem=$(awk '/PID/ {gsub(/:/,"",$2); print $2}' "$tmp/saida")
[ "$ordem" = "$(printf '10\n11\n20')" ] || { echo 'FALHA ordem por memória'; falhas=$((falhas + 1)); }
if grep -q 'worker-release\|terminal close\|worktree remove' "$tmp/chamadas"; then echo 'FALHA relatório escreveu'; falhas=$((falhas + 1)); fi
echo '{"ok":false}' > "$tmp/memoria.json"
bash "$raiz/skills/delegacao/orca-ram.sh" --portao 3 > "$tmp/saida" 2>&1
[ $? = 2 ] && grep -q 'memória indisponível' "$tmp/saida" || { echo 'FALHA memória ilegível'; falhas=$((falhas + 1)); }
mkdir -p "$HOME/.claude"
printf 'ram_min=3\n' > "$HOME/.claude/agentes.conf"
export PATH="$tmp:$PATH"
echo '{"ok":true,"result":{"host":{"availableMemory":2147483648}}}' > "$tmp/memoria.json"
bash "$raiz/skills/delegacao/orca-espera.sh" --max-min 1 > "$tmp/alerta" 2>&1
confere grep -q '!! memória abaixo de 3 GB: rode bash ~/.cache/orca-ram.sh' "$tmp/alerta"
limite() { if command -v timeout >/dev/null 2>&1; then timeout "$@"; else perl -e 'alarm shift; exec @ARGV' "$@"; fi; }
limite 5 bash "$raiz/skills/delegacao/orca-espera.sh" --max-min 1 > "$tmp/alerta" 2>&1
if grep -q '!! memória abaixo' "$tmp/alerta"; then echo 'FALHA repetiu alerta'; falhas=$((falhas + 1)); fi
printf 'ram_min=inválido\n' > "$HOME/.claude/agentes.conf"
RAM_TESTA_INVALIDO=1 bash "$raiz/skills/delegacao/orca-espera.sh" --max-min 1 > "$tmp/alerta" 2>&1
[ $? = 0 ] && grep -q '== worker_done' "$tmp/alerta" || { echo 'FALHA registro inválido derrubou espera'; falhas=$((falhas + 1)); }
[ "$falhas" = 0 ] && echo 'TUDO OK' || exit 1

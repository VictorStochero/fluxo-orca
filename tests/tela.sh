#!/bin/bash
# Prova do orca-tela.sh: ruído do Orca no stderr não quebra a leitura, e o erro do Orca (JSON no stdout) continua visível.
raiz=$(cd "$(dirname "$0")/.." && pwd)
falhas=0
h=$(mktemp -d); trap 'rm -rf "$h"' EXIT
cat > "$h/orca" <<'EOF'
#!/bin/bash
echo '[1106/120308.205:ERROR:third_party\crashpad\crashpad\util\win\registration_protocol_win.cc:108] CreateFile: (0x2)' >&2
case "$*" in
    *term_ok*) echo '{"ok":true,"result":{"terminal":{"tail":["  ","pronto","fim"]}}}' ;;
    *) echo '{"ok":false,"error":{"code":"terminal_handle_stale"}}'; exit 1 ;;
esac
EOF
chmod +x "$h/orca"
# tr: no Windows o print do Python sai com CRLF.
tela() { ORCA_CMD="$1" bash "$raiz/skills/delegacao/orca-tela.sh" "${@:2}" 2>&1 | tr -d '\r'; return "${PIPESTATUS[0]}"; }

s=$(tela "$h/orca" term_ok 5)
if [ "$s" = "$(printf 'pronto\nfim')" ]; then echo "ok   lê a tela com ruído no stderr"
else echo "FALHA leitura com ruído no stderr"; printf '%s\n' "$s" | sed 's/^/     /'; falhas=$((falhas + 1)); fi

s=$(tela "$h/orca" term_x 5); rc=$?
if [ $rc = 1 ] && printf '%s' "$s" | grep -q terminal_handle_stale; then echo "ok   erro do Orca aparece e sai com 1"
else echo "FALHA erro do Orca (rc=$rc)"; printf '%s\n' "$s" | sed 's/^/     /'; falhas=$((falhas + 1)); fi

s=$(tela "$h/nao-existe" term_x 5); rc=$?
if [ $rc = 1 ] && printf '%s' "$s" | grep -q 'nao-existe'; then echo "ok   comando do Orca ausente mostra o motivo"
else echo "FALHA comando ausente (rc=$rc)"; printf '%s\n' "$s" | sed 's/^/     /'; falhas=$((falhas + 1)); fi

[ $falhas = 0 ] && echo "TUDO OK" || { echo "$falhas falha(s)"; exit 1; }

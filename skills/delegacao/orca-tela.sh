#!/usr/bin/env bash
# Tela de um terminal do Orca sem o JSON cru: últimas N linhas úteis, sem moldura de TUI.
# Uso: bash ~/.cache/orca-tela.sh <handle> [N=30]
for py in python3 python ""; do [ -n "$py" ] && "$py" -c '' 2>/dev/null && break; done
[ -n "$py" ] || { echo "orca-tela: precisa de python." >&2; exit 2; }
[ -n "$1" ] || { echo "uso: orca-tela.sh <handle> [N=30]" >&2; exit 2; }
[[ "${2:-30}" =~ ^[1-9][0-9]*$ ]] || { echo "N deve ser um inteiro positivo." >&2; exit 2; }
"${ORCA_CMD:-${ORCA_CLI_COMMAND:-orca}}" terminal read --terminal "$1" --screen --json 2>&1 | ORCA_N="${2:-30}" "$py" -I -c '
import json, os, sys
sys.stdout.reconfigure(encoding="utf-8")
txt = sys.stdin.buffer.read().decode("utf-8", errors="replace")
try: t = json.JSONDecoder().raw_decode(txt.lstrip())[0]["result"]["terminal"]["tail"]
except Exception as e:
    print("orca-tela: leitura falhou (%s): %s" % (type(e).__name__, txt.strip()[:300])); sys.exit(1)
moldura = set("─│╭╮╰╯┌┐└┘├┤┬┴┼ \t")
def corrige(s):
    try: return s.encode("cp1252").decode("utf-8")  # UTF-8 lido como cp1252
    except UnicodeError: return s
ls = [corrige(l.rstrip()) for l in t]
print("\n".join([l for l in ls if l.strip() and not set(l) <= moldura][-int(os.environ["ORCA_N"]):]))
'

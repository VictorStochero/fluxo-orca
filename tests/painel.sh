#!/usr/bin/env bash
# Prova do painel com HOME isolado e Orca falso: estado em JSON, HTML gerado e falha do Orca/Python.
raiz=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export HOME="$tmp/home"
unset CLAUDE_CONFIG_DIR FILA_TESTE_FILA FILA_TESTE_VAGAS FILA_TESTE_VAGAS_PROJETO FILA_TESTE_TETO GS_TESTE_FILA GS_TESTE_VAGAS GS_TESTE_VAGAS_PROJETO GS_TESTE_TETO
mkdir -p "$HOME/.claude" "$HOME/.cache/agentes" "$tmp/bin"
falhas=0
ok() { echo "ok   $1"; }
ruim() { echo "FALHA $1"; falhas=$((falhas + 1)); }
igual() { if [ "$2" = "$3" ]; then ok "$1"; else ruim "$1: esperado [$2], veio [$3]"; fi; }
py=python3; "$py" -c '' 2>/dev/null || py=python

cat > "$tmp/bin/orca" <<'STUB'
#!/usr/bin/env bash
[ -n "${PAINEL_ORCA_FALHA:-}" ] && exit 1
case "$1 $2" in
    'status --json') echo '{"ok":true,"result":{"app":{"running":true},"runtime":{"appVersion":"9.9.9"}}}' ;;
    'diagnostics memory') echo '{"ok":true,"result":{"host":{"availableMemory":8589934592},"worktrees":[{"worktreeId":"repo-id::C:/x/wt-o","worktreeName":"wt-o","sessions":[{"sessionId":"repo-id::C:/x/wt-o@@abc","pid":42,"cpu":0,"memory":1073741824}]}]}}' ;;
    'orchestration run-list') echo '{"ok":true,"result":{"runs":[{"id":"run_1","objective":"Objetivo do run"}]}}' ;;
    'orchestration worker-list')
        # Com o handle do terminal, o Orca real restringe a lista ao run vinculado (aqui: vazia).
        [ -n "${ORCA_TERMINAL_HANDLE:-}" ] && { echo '{"ok":true,"result":{"workers":[],"page":{"hasMore":false,"nextCursor":null},"scope":{"source":"bound"}}}'; exit 0; }
        [ "$3" = --terminal-state ] && { echo '{"ok":true,"result":{"workers":[
          {"dispatchId":"ctx_r","dispatchStatus":"completed","terminalState":"retained","agentTerminalHandle":"term_r","resource":{"worktreeId":"repo-id::C:/x/wt-o","endpointIncarnation":"repo-id::C:/x/wt-o@@abc:sess-1"}},
          {"dispatchId":"ctx_r2","dispatchStatus":"completed","terminalState":"retained","agentTerminalHandle":"term_r2","resource":{"worktreeId":"repo-id::C:/x/wt-o","endpointIncarnation":"repo-id::C:/x/wt-o@@outra:sess-2"}},
          {"dispatchId":"ctx_r3","dispatchStatus":"completed","terminalState":"retained","agentTerminalHandle":"term_r3","projection":{"workspace":{"id":"repo-id::C:/x/wt-o"}}}],
          "page":{"hasMore":false,"nextCursor":null}}}'; exit 0; }
        echo '{"ok":true,"result":{"workers":[
      {"dispatchId":"ctx_a","taskId":"task_a","runId":"run_1","workerState":"ready","dispatchStatus":"dispatched","projection":{"provider":{"id":"codex","model":"m1"}},"resource":{"worktreeId":"repo-id::C:/x/wt-a"}},
      {"dispatchId":"ctx_old","taskId":"task_o","runId":"run_1","workerState":"ready","dispatchStatus":"completed","resource":{"worktreeId":"repo-id::C:/x/wt-o"}}],
      "page":{"hasMore":false,"nextCursor":null},"scope":{"source":"all"}}}' ;;
    *) exit 2 ;;
esac
STUB
chmod +x "$tmp/bin/orca"
export ORCA_CMD="$tmp/bin/orca"
painel() { bash "$raiz/skills/delegacao/painel.sh" "$@"; }
# j <expressão Python sobre d> <arquivo json>
j() { "$py" -I -c 'import json,sys; d=json.load(open(sys.argv[2],encoding="utf-8")); print(eval(sys.argv[1]))' "$1" "$2"; }

# Fila: pid vivo ($$) e pid morto.
mkdir -p "$HOME/.cache/gs-teste-3308.lock1" "$HOME/.cache/gs-teste-teto.lock1"
echo $$ > "$HOME/.cache/gs-teste-3308.lock1/pid"
echo 'C:/Herd/wt-um [db] desde 20:14:25: runner --compact tests/Feature/X.php' > "$HOME/.cache/gs-teste-3308.lock1/dono"
echo 99999999 > "$HOME/.cache/gs-teste-teto.lock1/pid"
echo 'C:/Herd/wt-dois [] desde 20:15:00: </script><b>x</b>' > "$HOME/.cache/gs-teste-teto.lock1/dono"
mkdir -p "$HOME/.cache/gs-teste-3308.lock2"  # trava recém-criada, ainda sem pid nem dono
# Pool: duas contas, uma ocupante, cota com #cand; "b=3" muda só as vagas.
printf 'teto=4\nram_min=3\na agente=claude vagas=2 peso=5 papeis=escritor,revisor\nb agente=codex vagas=1\nb=3\n' > "$HOME/.claude/agentes.conf"
mkdir -p "$HOME/.cache/agentes/a.lock1"
echo ctx_a > "$HOME/.cache/agentes/a.lock1/dispatch"; echo 2026-10-31T21:57:25Z > "$HOME/.cache/agentes/a.lock1/desde"
printf 'a: sessão 90%% usado | semana 25%% usado\n#cand a 90 25 1793721600 168\n' > "$HOME/.cache/agentes/medida.a"
printf '%s\n' "$raiz" > "$HOME/.cache/fluxo-orca-raiz"

painel --json > "$tmp/e.json" 2> "$tmp/e.err"; igual 'json: exit 0' 0 $?
igual 'json: stderr vazio' '' "$(cat "$tmp/e.err")"
igual 'fila: trava viva' True "$(j '[t for t in d["fila"]["travas"] if t["fila"]=="3308"][0]["viva"]' "$tmp/e.json")"
igual 'fila: trava sem pid' 'None False' "$(j 'str([t for t in d["fila"]["travas"] if t["vaga"]==2][0]["pid"])+" "+str([t for t in d["fila"]["travas"] if t["vaga"]==2][0]["viva"])' "$tmp/e.json")"
igual 'fila: trava morta' False "$(j '[t for t in d["fila"]["travas"] if t["fila"]=="teto"][0]["viva"]' "$tmp/e.json")"
igual 'fila: worktree do dono' C:/Herd/wt-um "$(j '[t for t in d["fila"]["travas"] if t["fila"]=="3308"][0]["worktree"]' "$tmp/e.json")"
igual 'fila: comando do dono' 'runner --compact tests/Feature/X.php' "$(j '[t for t in d["fila"]["travas"] if t["fila"]=="3308"][0]["comando"]' "$tmp/e.json")"
igual 'fila: padrões' 'recurso 2 3' "$(j 'd["fila"]["modo"]+" "+str(d["fila"]["vagas"])+" "+str(d["fila"]["teto"])' "$tmp/e.json")"
igual 'pool: usadas e vagas' '1 2' "$(j 'str(d["pool"]["contas"][0]["usadas"])+" "+str(d["pool"]["contas"][0]["vagas"])' "$tmp/e.json")"
igual 'pool: cota curta/longa/alerta' '90 25 True' "$(j 'str(d["pool"]["contas"][0]["cota"]["curta"])+" "+str(d["pool"]["contas"][0]["cota"]["longa"])+" "+str(d["pool"]["contas"][0]["cota"]["alerta"])' "$tmp/e.json")"
igual 'pool: conta sem medida' None "$(j 'd["pool"]["contas"][1]["cota"]' "$tmp/e.json")"
igual 'pool: linha conta=N muda as vagas' 3 "$(j 'd["pool"]["contas"][1]["vagas"]' "$tmp/e.json")"
igual 'pool: máquina' '1/4 ram_min 3' "$(j 'str(d["pool"]["maquina"]["usadas"])+"/"+str(d["pool"]["maquina"]["teto"])+" ram_min "+str(d["pool"]["ram_min"])' "$tmp/e.json")"
igual 'ram: GB disponíveis' 8.0 "$(j 'd["ram"]["disponivel_gb"]' "$tmp/e.json")"
# Retido na sessão ociosa entra com o comando de liberar; retido em sessão que não está ociosa fica fora.
igual 'ram: retido na sessão ociosa' True "$(j '"PID 42: CPU 0" in d["ram"]["relatorio"] and "orca-libera.sh ctx_r\n" in d["ram"]["relatorio"]+"\n" and "ctx_r2" not in d["ram"]["relatorio"]' "$tmp/e.json")"
igual 'ram: retido só com projection.workspace.id' True "$(j '"orca-libera.sh ctx_r3" in d["ram"]["relatorio"]' "$tmp/e.json")"
igual 'saúde: Orca' '9.9.9' "$(j 'd["saude"]["orca"]["versao"]' "$tmp/e.json")"
igual 'saúde: script novo desatualizado' True "$(j '"painel.sh" in d["saude"]["scripts_desatualizados"]' "$tmp/e.json")"
# Workers: objetivo do run e worktree após "::"; dispatch concluído fica fora.
igual 'workers: só os em andamento' 1 "$(j 'len(d["workers"])' "$tmp/e.json")"
igual 'workers: objetivo' 'Objetivo do run' "$(j 'd["workers"][0]["objetivo"]' "$tmp/e.json")"
igual 'workers: worktree' C:/x/wt-a "$(j 'd["workers"][0]["worktree"]' "$tmp/e.json")"
igual 'workers: agente/modelo' 'codex m1' "$(j 'd["workers"][0]["agente"]+" "+d["workers"][0]["modelo"]' "$tmp/e.json")"
# Terminal com run vinculado: o painel chama o Orca sem o handle e lista todos os runs.
ORCA_TERMINAL_HANDLE=term_x painel --json > "$tmp/b.json"
igual 'workers: todos os runs mesmo com run vinculado' '1 None' "$(j 'str(len(d["workers"]))+" "+str(d["aviso"])' "$tmp/b.json")"

# Orca falhando não derruba o painel.
PAINEL_ORCA_FALHA=1 painel --json > "$tmp/f.json"; igual 'Orca fora: exit 0' 0 $?
igual 'Orca fora: workers vazio' '[]' "$(j 'd["workers"]' "$tmp/f.json")"
igual 'Orca fora: RAM nula' None "$(j 'd["ram"]["disponivel_gb"]' "$tmp/f.json")"
igual 'Orca fora: aviso' True "$(j 'bool(d["aviso"])' "$tmp/f.json")"

# HTML: refresh, JSON embutido e nenhum </script> dentro do JSON.
painel > "$tmp/h.out"; igual 'html: exit 0' 0 $?
html=$HOME/.cache/painel.html
[ -f "$html" ] && ok 'html: arquivo criado' || ruim 'html: arquivo ausente'
grep -q 'http-equiv="refresh" content="5"' "$html" && ok 'html: refresh 5 s' || ruim 'html: sem refresh'
grep -q 'id="estado"' "$html" && grep -q 'wt-um' "$html" && ok 'html: estado embutido' || ruim 'html: estado ausente'
igual 'html: só dois </script> (JSON e código)' 2 "$(grep -o '</script>' "$html" | wc -l | tr -d ' ')"
igual 'html: JSON embutido íntegro' 'C:/Herd/wt-dois' "$("$py" -I -c '
import re, json, sys
h = open(sys.argv[1], encoding="utf-8").read()
d = json.loads(re.search(r"id=\"estado\">(.*?)</script>", h, re.S).group(1))
print([t for t in d["fila"]["travas"] if t["fila"] == "teto"][0]["worktree"])' "$html")"

# Sem Python: aviso e exit 2.
mkdir "$tmp/vazio"
PATH="$tmp/vazio" "$BASH" "$raiz/skills/delegacao/painel.sh" --json > "$tmp/s.out" 2> "$tmp/s.err"; igual 'sem Python: exit 2' 2 $?
grep -q 'painel indisponível (sem Python)' "$tmp/s.err" && ok 'sem Python: aviso' || ruim 'sem Python: sem aviso'
painel --nada >/dev/null 2>&1; igual 'uso: opção inválida' 2 $?

[ "$falhas" = 0 ] && echo 'TUDO OK' || { echo "$falhas falha(s)"; exit 1; }

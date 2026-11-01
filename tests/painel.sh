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


# --config da fila: grava fila.conf e o --json reflete, com fila.conf acima do ambiente (como no fila-teste.sh).
cfg() { painel --config "$@" > "$tmp/c.out" 2> "$tmp/c.err"; }
conf_fila=$HOME/.claude/fila.conf
junta() { tr '\n' '|' | sed 's/|$//'; }
cfg fila.modo=projeto fila.vagas_projeto=3 fila.teto=4; igual 'config fila: exit 0' 0 $?
igual 'config fila: ok por chave' 'ok fila.modo|ok fila.vagas_projeto|ok fila.teto' "$(junta '|' < "$tmp/c.out")"
igual 'config fila: fila.conf criado' 'FILA_TESTE_FILA=projeto|FILA_TESTE_VAGAS_PROJETO=3|FILA_TESTE_TETO=4' "$(junta '|' < "$conf_fila")"
FILA_TESTE_TETO=9 FILA_TESTE_VAGAS_PROJETO=8 painel --json > "$tmp/e.json"
igual 'config fila: --json lê fila.conf acima do ambiente' 'projeto 3 4 3' "$(j 'd["fila"]["modo"]+" "+str(d["fila"]["vagas"])+" "+str(d["fila"]["teto"])+" "+str(d["config"]["fila"]["vagas_projeto"])' "$tmp/e.json")"
FILA_TESTE_PROCESSOS=7 painel --json > "$tmp/e.json"
igual 'config fila: ambiente vale quando o arquivo não define a chave' 7 "$(j 'd["config"]["fila"]["processos"]' "$tmp/e.json")"
antes=$(cat "$conf_fila")
cfg fila.vagas=0; igual 'config fila: valor inválido, exit 2' 2 $?
grep -q '^erro: ' "$tmp/c.err" && ok 'config fila: mensagem de erro' || ruim 'config fila: sem mensagem'
igual 'config fila: arquivo intacto' "$antes" "$(cat "$conf_fila")"
cfg fila.teto=2 fila.modo=xx; igual 'config fila: tudo ou nada, exit 2' 2 $?
igual 'config fila: tudo ou nada, arquivo intacto' "$antes" "$(cat "$conf_fila")"
cfg fila.nada=1; igual 'config: chave desconhecida' 2 $?
cfg semigual; igual 'config: argumento sem =' 2 $?
printf '# minha fila\nFILA_TESTE_TETO=4\n' > "$conf_fila"; cfg fila.teto=5 fila.processos=6
igual 'config fila: preserva comentário e troca no lugar' '# minha fila|FILA_TESTE_TETO=5|FILA_TESTE_PROCESSOS=6' "$(junta '|' < "$conf_fila")"

# --config do pool e das contas: preserva comentário, ordem e tokens alheios; contas.sh reprovando restaura o arquivo.
conf_ag=$HOME/.claude/agentes.conf
printf '# comentário\nteto=4\nescolha=ritmo\na agente=claude vagas=2 peso=5 papeis=escritor,revisor modelo=m1\na=9\nk agente=kimi vagas=1 papeis=segunda-opiniao\n' > "$conf_ag"
cfg pool.ram_min=2 pool.teto=6 pool.escolha=ordem conta.a.vagas=3 conta.a.peso=7; igual 'config pool: exit 0' 0 $?
igual 'config pool: arquivo reescrito' '# comentário|teto=6|escolha=ordem|ram_min=2|a agente=claude vagas=3 peso=7 papeis=escritor,revisor modelo=m1|k agente=kimi vagas=1 papeis=segunda-opiniao' "$(junta '|' < "$conf_ag")"
painel --json > "$tmp/e.json"
igual 'config pool: --json reflete' '6 2 ordem 3 7' "$(j 'str(d["config"]["pool"]["teto"])+" "+str(d["config"]["pool"]["ram_min"])+" "+d["config"]["pool"]["escolha"]+" "+str(d["config"]["contas"][0]["vagas"])+" "+str(d["config"]["contas"][0]["peso"])' "$tmp/e.json")"
cfg conta.a.papeis=revisor,mecanico conta.k.papeis= conta.k.peso=2; igual 'config conta: papéis, papel vazio e token novo' 0 $?
igual 'config conta: linhas' 'a agente=claude vagas=3 peso=7 papeis=revisor,mecanico modelo=m1|k agente=kimi vagas=1 papeis= peso=2' "$(grep -E '^(a|k) ' "$conf_ag" | junta '|')"
cp "$conf_ag" "$tmp/ag.bak"
cfg conta.zz.vagas=1; igual 'config conta: inexistente, exit 2' 2 $?
grep -q 'inexistente' "$tmp/c.err" && ok 'config conta: mensagem de conta inexistente' || ruim 'config conta: sem mensagem'
cfg conta.a.papeis=banana; igual 'config conta: papel inválido, exit 2' 2 $?
cfg conta.a.peso=0; igual 'config conta: peso 0, exit 2' 2 $?
cfg pool.ram_min=-1; igual 'config pool: ram_min negativo, exit 2' 2 $?
cmp -s "$conf_ag" "$tmp/ag.bak" && ok 'config: erros de validação não gravam nada' || ruim 'config: arquivo mudou'
cfg conta.a.vagas=1 conta.k.papeis=escritor; igual 'config conta: contas.sh reprova, exit 2' 2 $?
grep -q 'kimi' "$tmp/c.err" && ok 'config conta: mensagem do contas.sh' || ruim "config conta: sem mensagem do contas.sh ($(cat "$tmp/c.err"))"
cmp -s "$conf_ag" "$tmp/ag.bak" && ok 'config conta: arquivo restaurado byte a byte' || ruim 'config conta: arquivo não restaurado'
ls "$conf_ag".*.tmp >/dev/null 2>&1 && ruim 'config conta: sobrou .tmp' || ok 'config conta: sem .tmp sobrando'
# O contas.sh confere o candidato (.tmp) enquanto o agentes.conf real continua intacto para os outros processos.
cat > "$HOME/.cache/contas.sh" <<'STUBC'
#!/usr/bin/env bash
[ "$1" = lista ] || exit 2
case "$CONTAS_CONF" in *.tmp) ;; *) echo "CONTAS_CONF não é o candidato: $CONTAS_CONF" >&2; exit 2 ;; esac
cmp -s "$HOME/.claude/agentes.conf" "$HOME/.claude/agentes.antes" || { echo 'agentes.conf mudou durante a validação' >&2; exit 2; }
grep -q 'vagas=5' "$CONTAS_CONF" || { echo 'candidato sem o valor novo' >&2; exit 2; }
STUBC
cp "$conf_ag" "$HOME/.claude/agentes.antes"
cfg conta.a.vagas=5; igual 'config conta: contas.sh valida o candidato com o arquivo real intacto' 0 $?
grep -q '^a .*vagas=5' "$conf_ag" && ok 'config conta: candidato aprovado vira o arquivo' || ruim 'config conta: valor novo não gravado'
rm -f "$HOME/.cache/contas.sh" "$HOME/.claude/agentes.antes"
rm -f "$conf_ag"; cfg pool.teto=3; igual 'config pool: cria agentes.conf' 'teto=3' "$(cat "$conf_ag" 2>/dev/null)"
cfg conta.a.vagas=1; igual 'config conta: sem conta no arquivo não cria conta' 2 $?
printf 'teto=4\nram_min=3\na agente=claude vagas=2 peso=5 papeis=escritor,revisor\nb agente=codex vagas=1\nb=3\n' > "$conf_ag"

# Servidor: sobe dentro do teste e morre no trap.
porta=$("$py" -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])')
trap 'kill "${srv:-0}" 2>/dev/null; rm -rf "$tmp"' EXIT
bash "$raiz/skills/delegacao/painel.sh" --servir "$porta" > "$tmp/srv.out" 2> "$tmp/srv.err" &  # sem a função: o kill tem de alcançar o servidor
srv=$!
url=http://127.0.0.1:$porta
for _ in $(seq 40); do curl -s -o /dev/null "$url/" && break; sleep 0.25; done
igual 'servir: imprime a URL' "$url/" "$(head -1 "$tmp/srv.out")"
curl -s "$url/" > "$tmp/pag.html"
grep -q 'Painel fluxo-orca' "$tmp/pag.html" && ok 'servir: GET / devolve a página' || ruim 'servir: página ausente'
grep -q 'http-equiv' "$tmp/pag.html" && ruim 'servir: página ainda tem meta refresh' || ok 'servir: página sem meta refresh'
token=$(grep -o 'var T="[^"]*"' "$tmp/pag.html" | cut -d'"' -f2)
[ ${#token} -ge 20 ] && ok 'servir: token embutido' || ruim 'servir: sem token na página'
curl -s "$url/estado.json" > "$tmp/s.json"
igual 'servir: /estado.json traz o bloco config' 'a b' "$(j '" ".join(c["nome"] for c in d["config"]["contas"])' "$tmp/s.json")"
post() { curl -s -o "$tmp/post.out" -w '%{http_code}' "$@"; }
cod=$(post -X POST -d 'fila.vagas=5' "$url/config"); case $cod in 400|403) ok "servir: POST sem token recusado ($cod)" ;; *) ruim "servir: POST sem token deu $cod" ;; esac
cod=$(post -X POST -d 'token=errado' -d 'fila.vagas=5' "$url/config"); case $cod in 400|403) ok "servir: POST com token errado recusado ($cod)" ;; *) ruim "servir: token errado deu $cod" ;; esac
grep -q '^FILA_TESTE_VAGAS=' "$conf_fila" && ruim 'servir: POST recusado gravou' || ok 'servir: POST recusado não grava'
cod=$(post -X POST -d "token=$token" -d 'fila.vagas=5' "$url/config"); igual 'servir: POST com token, HTTP' 200 "$cod"
grep -q '"ok": true' "$tmp/post.out" && ok 'servir: POST com token devolve ok' || ruim "servir: resposta $(cat "$tmp/post.out")"
grep -q '^FILA_TESTE_VAGAS=5$' "$conf_fila" && ok 'servir: POST gravou o fila.conf' || ruim 'servir: fila.conf não gravado'
cod=$(post -X POST -H 'Content-Type: application/json' -d "{\"token\":\"$token\",\"conta.a.vagas\":\"4\",\"conta.a.papeis\":[\"revisor\"]}" "$url/config"); igual 'servir: POST em JSON, HTTP' 200 "$cod"
grep -q '^a agente=claude vagas=4 peso=5 papeis=revisor$' "$conf_ag" && ok 'servir: POST em JSON gravou o agentes.conf' || ruim "servir: agentes.conf $(cat "$conf_ag")"
cod=$(post -X POST -d "token=$token" -d 'fila.vagas=0' "$url/config"); igual 'servir: valor inválido, HTTP' 400 "$cod"
grep -q '"ok": false' "$tmp/post.out" && grep -q '"erro"' "$tmp/post.out" && ok 'servir: valor inválido devolve erro' || ruim "servir: resposta $(cat "$tmp/post.out")"
igual 'servir: rota desconhecida' 404 "$(post "$url/nada")"
igual 'servir: POST em rota desconhecida' 404 "$(post -X POST -d "token=$token" "$url/estado.json")"
igual 'servir: método PUT' 405 "$(post -X PUT "$url/config")"
igual 'servir: método DELETE' 405 "$(post -X DELETE "$url/")"
igual 'servir: Host estranho' 403 "$(post -H 'Host: exemplo.com' "$url/estado.json")"
painel --servir "$porta" > /dev/null 2> "$tmp/ocup.err"; igual 'servir: porta ocupada, exit 2' 2 $?
grep -q 'porta' "$tmp/ocup.err" && ok 'servir: porta ocupada, mensagem' || ruim 'servir: porta ocupada sem mensagem'
kill "$srv" 2>/dev/null; wait "$srv" 2>/dev/null
curl -s -m 2 -o /dev/null "$url/" && ruim 'servir: servidor seguiu vivo após o kill' || ok 'servir: servidor encerrado'
painel --servir 99999 >/dev/null 2>&1; igual 'servir: porta inválida' 2 $?
[ "$falhas" = 0 ] && echo 'TUDO OK' || { echo "$falhas falha(s)"; exit 1; }

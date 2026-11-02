#!/usr/bin/env bash
# Prova do painel com HOME isolado e Orca falso: estado em JSON, escritor --config e falha do Orca/Python.
raiz=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export HOME="$tmp/home"
unset CLAUDE_CONFIG_DIR ORCA_TERMINAL_HANDLE FILA_TESTE_FILA FILA_TESTE_VAGAS FILA_TESTE_VAGAS_PROJETO FILA_TESTE_TETO FILA_TESTE_PROCESSOS GS_TESTE_FILA GS_TESTE_VAGAS GS_TESTE_VAGAS_PROJETO GS_TESTE_TETO GS_TESTE_PROCESSOS
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
    'account list') cx='{"status":"ok","session":{"usedPercent":95,"resetDescription":"14:48"},"weekly":{"usedPercent":50,"resetDescription":"qua., 10:01"},"updatedAt":0}'; [ -n "${PAINEL_TESTE_CODEX_ERRO:-}" ] && cx='{"status":"error","error":"token expirado","session":null,"weekly":null}'
        oc='[]'; [ -n "${PAINEL_TESTE_OPENCODE:-}" ] && oc='[{"id":"oc1","label":"Conta OC"}]'; echo '{"ok":true,"result":{"claude":{"accounts":[{"id":"abcdef1234567890","email":"gerenciada@x.com"}],"activeAccountId":null},"codex":{"accounts":[],"activeAccountId":null,"systemDefault":{"hasAuth":true,"authKind":"oauth","email":"cx@x.com"}},"opencode":{"accounts":'"$oc"',"activeAccountId":null},"devin":{"accounts":[{"id":"d1","label":"Devin A"}],"activeAccountId":null},"rateLimits":{"claude":{"status":"unavailable","session":null,"weekly":null},"codex":'"$cx"'}}}' ;;
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
igual 'fila: padrões' 'banco 2 3' "$(j 'd["fila"]["modo"]+" "+str(d["fila"]["vagas"])+" "+str(d["fila"]["teto"])' "$tmp/e.json")"
igual 'pool: usadas e vagas' '1 2' "$(j 'str(d["pool"]["contas"][0]["usadas"])+" "+str(d["pool"]["contas"][0]["vagas"])' "$tmp/e.json")"
igual 'pool: cota curta/longa/alerta' '90 25 True' "$(j 'str(d["pool"]["contas"][0]["cota"]["curta"])+" "+str(d["pool"]["contas"][0]["cota"]["longa"])+" "+str(d["pool"]["contas"][0]["cota"]["alerta"])' "$tmp/e.json")"
igual 'orca: cota nativa vale sobre a medida (codex sem medida)' '95 50 orca True' "$(j 'str(d["pool"]["contas"][1]["cota"]["curta"])+" "+str(d["pool"]["contas"][1]["cota"]["longa"])+" "+d["pool"]["contas"][1]["cota"]["fonte"]+" "+str(d["pool"]["contas"][1]["detectada"])' "$tmp/e.json")"
igual 'orca: conta sem cota nativa mantém a medida' 'None 90 False' "$(j 'str(d["pool"]["contas"][0]["cota"].get("fonte"))+" "+str(d["pool"]["contas"][0]["cota"]["curta"])+" "+str(d["pool"]["contas"][0]["detectada"])' "$tmp/e.json")"
igual 'auto: conta gerenciada do Orca entra sozinha no pool' 'claude-abcdef12 manual gerenciada@x.com claude' "$(j '" ".join([c["nome"],c["origem"],c["rotulo"],c["agente"]]) if (c:=[x for x in d["pool"]["contas"] if x["nome"]=="claude-abcdef12"][0]) else 0' "$tmp/e.json")"
igual 'auto: conta gerenciada entra so como medida (sem papel e sem medidor), porque o despacho usa a conta padrao' 1 "$(grep -c '^claude-abcdef12 agente=claude vagas=1 peso=1 papeis= medidor=-$' "$HOME/.claude/agentes.conf")"
igual 'auto: gerenciada sem papeis e ativa' ' True' "$(j '",".join([x for x in d["pool"]["contas"] if x["nome"]=="claude-abcdef12"][0]["papeis"])+" "+str([x for x in d["pool"]["contas"] if x["nome"]=="claude-abcdef12"][0]["ativo"])' "$tmp/e.json")"
igual 'auto: o contas.sh le a gerenciada sem papel e sem medidor (nao entra na escolha do escritor)' 'papeis= medidor=-' "$(CONTAS_CONF="$HOME/.claude/agentes.conf" bash "$raiz/skills/limites-cota/contas.sh" lista | grep '^claude-abcdef12 ' | grep -o 'papeis=.*')"
cp "$HOME/.claude/agentes.conf" "$tmp/ag.antes"; painel --json > "$tmp/e2.json"
cmp -s "$HOME/.claude/agentes.conf" "$tmp/ag.antes" && ok 'auto: idempotente, a segunda coleta nao muda o arquivo' || ruim 'auto: a segunda coleta mudou o arquivo' 
igual 'orca: manual não perde a origem' manual "$(j 'd["pool"]["contas"][0]["origem"]' "$tmp/e.json")"
igual 'origem: conta do agentes.conf que o Orca também detecta é ambos' ambos "$(j 'd["pool"]["contas"][1]["origem"]' "$tmp/e.json")"
igual 'origem: a conta adicionada sozinha passa a ser da lista (manual)' 'manual manual' "$(j 'd["pool"]["contas"][0]["origem"]+" "+[x for x in d["pool"]["contas"] if x["nome"]=="claude-abcdef12"][0]["origem"]' "$tmp/e.json")"
# Agentes instalados: catálogo (id-orca + comando) cruzado com o PATH; só entra o tipo que ainda não tem conta.
{ cat "$raiz/skills/limites-cota/agentes-catalogo.conf"; printf "%s
" "pi|pi|pi-cli||-|nao|nao|-|-|-|" "ghost|ghost|ghost-cli||-|nao|nao|-|-|-|" "semid||pi-cli||-|nao|nao|-|-|-|"; } > "$tmp/cat.conf"
printf '#!/usr/bin/env bash
' > "$tmp/bin/pi-cli"; chmod +x "$tmp/bin/pi-cli"; cp "$tmp/bin/pi-cli" "$tmp/bin/pi-cli.cmd"  # .cmd: o PATHEXT do Windows
PATH="$tmp/bin:$PATH" CONTAS_CATALOGO="$tmp/cat.conf" painel --json > "$tmp/i.json"
igual 'instalado: agente do catálogo no PATH entra sozinho no pool' 'pi manual pi' "$(j '" ".join([c["nome"],c["origem"],c["agente"]]) if (c:=[x for x in d["pool"]["contas"] if x["nome"]=="pi"][0]) else 0' "$tmp/i.json")"
igual 'instalado: a linha de pi foi gravada' 1 "$(grep -c '^pi agente=pi vagas=1 peso=1$' "$HOME/.claude/agentes.conf")"
igual 'instalado: o rótulo diz como o Orca abre' True "$(j '"orca agent launch --agent pi" in [x for x in d["pool"]["contas"] if x["nome"]=="pi"][0]["rotulo"]' "$tmp/i.json")"
igual 'instalado: sem CLI no PATH ou sem id-orca não aparece' 0 "$(j 'len([x for x in d["pool"]["contas"] if x["nome"] in ("ghost","semid")])' "$tmp/i.json")"
igual 'instalado: tipo que já tem conta não duplica' 0 "$(j 'len([x for x in d["pool"]["contas"] if x["nome"]=="claude"])' "$tmp/i.json")"
# Instalado: o catálogo fica em ~/.cache (ao lado do script), não em ../limites-cota.
(cat "$tmp/cat.conf"; echo 'qq|qq|pi-cli||-|nao|nao|-|-|-|') > "$HOME/.cache/agentes-catalogo.conf"
PATH="$tmp/bin:$PATH" painel --json > "$tmp/i2.json"
igual 'instalado: catálogo de ~/.cache vale quando não há CONTAS_CATALOGO' 'qq' "$(j '[x["nome"] for x in d["pool"]["contas"] if x["nome"]=="qq"][0]' "$tmp/i2.json")"
rm -f "$HOME/.cache/agentes-catalogo.conf"
igual 'catálogo: agentes para a conta nova' True "$(j '"claude" in d["pool"]["catalogo"] and "codex" in d["pool"]["catalogo"]' "$tmp/e.json")"
igual 'pool: linha conta=N muda as vagas' 3 "$(j 'd["pool"]["contas"][1]["vagas"]' "$tmp/e.json")"
igual 'pool: máquina' '1/4 ram_min 3' "$(j 'str(d["pool"]["maquina"]["usadas"])+"/"+str(d["pool"]["maquina"]["teto"])+" ram_min "+str(d["pool"]["ram_min"])' "$tmp/e.json")"
igual 'saída: JSON só ASCII (nenhum console estraga o acento)' 0 "$(LC_ALL=C grep -c -P '[^\x00-\x7F]' "$tmp/e.json")"
igual 'saúde: Orca' 9.9.9 "$(j 'd["saude"]["orca"]["versao"]' "$tmp/e.json")"
igual 'saúde: script novo desatualizado' True "$(j '"painel.sh" in d["saude"]["scripts_desatualizados"]' "$tmp/e.json")"

# Orca falhando não derruba o painel.
PAINEL_ORCA_FALHA=1 painel --json > "$tmp/f.json"; igual 'Orca fora: exit 0' 0 $?
igual 'Orca fora: aviso' True "$(j 'bool(d["aviso"])' "$tmp/f.json")"

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
igual 'config fila: --json lê fila.conf acima do ambiente' 'projeto 3 4 3' "$(j 'd["fila"]["modo"]+" "+str(d["fila"]["vagas"])+" "+str(d["fila"]["teto"])+" "+str(d["fila"]["config"]["vagas_projeto"]["valor"])' "$tmp/e.json")"
FILA_TESTE_PROCESSOS=7 painel --json > "$tmp/e.json"
igual 'config fila: ambiente vale quando o arquivo não define a chave' 7 "$(j 'd["fila"]["config"]["processos"]["valor"]' "$tmp/e.json")"
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

# --config do pool e das contas: preserva comentário, ordem e tokens alheios; contas.sh reprovando, o arquivo não é trocado.
conf_ag=$HOME/.claude/agentes.conf
printf '# comentário\nteto=4\nescolha=ritmo\na agente=claude vagas=2 peso=5 papeis=escritor,revisor modelo=m1\na=9\nk agente=kimi vagas=1 papeis=segunda-opiniao\n' > "$conf_ag"
cfg pool.ram_min=2 pool.teto=6 pool.escolha=ordem conta.a.vagas=3 conta.a.peso=7; igual 'config pool: exit 0' 0 $?
igual 'config pool: arquivo reescrito' '# comentário|teto=6|escolha=ordem|ram_min=2|a agente=claude vagas=3 peso=7 papeis=escritor,revisor modelo=m1|k agente=kimi vagas=1 papeis=segunda-opiniao' "$(junta '|' < "$conf_ag")"
painel --json > "$tmp/e.json"
igual 'config pool: --json reflete' '6 2 ordem 3 7' "$(j 'str(d["pool"]["teto"])+" "+str(d["pool"]["ram_min"])+" "+d["pool"]["escolha"]+" "+str(d["pool"]["contas"][0]["vagas"])+" "+str(d["pool"]["contas"][0]["peso"])' "$tmp/e.json")"
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
cmp -s "$conf_ag" "$tmp/ag.bak" && ok 'config conta: arquivo intacto byte a byte' || ruim 'config conta: arquivo mudou'
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
# Tudo ou nada com fila e conta na mesma chamada: fila.conf que não pode ser gravado (é um diretório) deixa o agentes.conf como estava.
cp "$conf_ag" "$tmp/ag.bak"; mv "$conf_fila" "$tmp/fila.bak"; mkdir "$conf_fila"
cfg conta.a.vagas=9 fila.teto=2; igual 'config misto: fila.conf não gravável, exit 2' 2 $?
cmp -s "$conf_ag" "$tmp/ag.bak" && ok 'config misto: agentes.conf intacto' || ruim 'config misto: agentes.conf mudou'
ls "$conf_ag".*.tmp >/dev/null 2>&1 && ruim 'config misto: sobrou .tmp' || ok 'config misto: sem .tmp sobrando'
rmdir "$conf_fila"; mv "$tmp/fila.bak" "$conf_fila"
rm -f "$conf_ag"; cfg pool.teto=3; igual 'config pool: cria agentes.conf' 'teto=3' "$(cat "$conf_ag" 2>/dev/null)"
cfg conta.a.vagas=1; igual 'config conta: sem conta no arquivo não cria conta' 2 $?
# Registro padrao (arquivo so com globais): nem a auto-adicao do --json nem "Nova conta" trocam o registro padrao por uma conta so.
printf 'ram_min=2\n' > "$conf_ag"
PATH="$tmp/bin:$PATH" CONTAS_CATALOGO="$tmp/cat.conf" painel --json > "$tmp/r.json"
igual 'registro padrao: o --json com agente instalado nao grava conta' 'ram_min=2' "$(cat "$conf_ag")"
cfg conta.novo.adicionar=codex; igual 'registro padrao: adicionar conta recusa, exit 2' 2 $?
grep -q 'registro padrão' "$tmp/c.err" && ok 'registro padrao: mensagem pede as contas antes' || ruim "registro padrao: mensagem $(cat "$tmp/c.err")"
igual 'registro padrao: recusa nao grava' 'ram_min=2' "$(cat "$conf_ag")"
igual 'registro padrao: o contas.sh ainda traz as contas padrao' 1 "$(CONTAS_CONF="$conf_ag" bash "$raiz/skills/limites-cota/contas.sh" lista | grep -c '^team ')"
printf 'teto=4\nram_min=3\na agente=claude vagas=2 peso=5 papeis=escritor,revisor\nb agente=codex vagas=1\nb=3\n' > "$conf_ag"

# Modo da fila: global | banco | projeto; recurso (nome antigo) é aceito e gravado como banco.
cfg fila.modo=recurso; igual 'config modo: recurso exit 0' 0 $?
igual 'config modo: recurso vira banco no arquivo' 1 "$(grep -c '^FILA_TESTE_FILA=banco$' "$conf_fila")"
printf 'FILA_TESTE_FILA=recurso
' > "$conf_fila"; painel --json > "$tmp/m.json"
igual 'modo: recurso antigo aparece como banco' banco "$(j 'd["fila"]["modo"]' "$tmp/m.json")"
cfg fila.modo=projeto; painel --json > "$tmp/m.json"
igual 'modo: projeto usa as vagas por projeto' 'projeto 1' "$(j 'd["fila"]["modo"]+" "+str(d["fila"]["vagas"])' "$tmp/m.json")"

# Faixas e entradas inválidas: nada é gravado.
cp "$conf_ag" "$tmp/ag.bak"; antes=$(cat "$conf_fila")
cfg fila.vagas=100; igual 'config fila: acima da faixa, exit 2' 2 $?
cfg conta.a.peso=101; igual 'config conta: peso acima da faixa, exit 2' 2 $?
cfg pool.teto=-1; igual 'config pool: teto negativo, exit 2' 2 $?
cfg pool.escolha=sorteio; igual 'config pool: escolha inválida, exit 2' 2 $?
cmp -s "$conf_ag" "$tmp/ag.bak" && [ "$antes" = "$(cat "$conf_fila")" ] && ok 'config: faixas e enums não gravam nada' || ruim 'config: arquivo mudou'

# Valor efetivo e origem: padrão < ambiente (inclusive GS_TESTE_*) < fila.conf < worktree.conf do projeto.
rm -f "$conf_fila"
painel --json > "$tmp/o.json"
igual 'origem: padrão sem ambiente nem arquivo' 'padrao 2' "$(j 'd["fila"]["config"]["vagas"]["origem"]+" "+str(d["fila"]["config"]["vagas"]["valor"])' "$tmp/o.json")"
GS_TESTE_VAGAS=7 painel --json > "$tmp/o.json"
igual 'origem: ambiente pelo nome antigo' 'ambiente 7' "$(j 'd["fila"]["config"]["vagas"]["origem"]+" "+str(d["fila"]["config"]["vagas"]["valor"])' "$tmp/o.json")"
cfg fila.vagas=4
GS_TESTE_VAGAS=7 painel --json > "$tmp/o.json"
igual 'origem: fila.conf vale sobre o ambiente' 'fila.conf 4 4' "$(j 'd["fila"]["config"]["vagas"]["origem"]+" "+str(d["fila"]["config"]["vagas"]["valor"])+" "+str(d["fila"]["vagas"])' "$tmp/o.json")"
# Projeto: repo com .orca/worktree.conf e uma trava cujo dono é o worktree dele.
mkdir -p "$tmp/meu-projeto/.orca"; proj=$(cd "$tmp/meu-projeto" && { pwd -W 2>/dev/null || pwd; }); git -C "$proj" init -q 2>/dev/null
printf 'export GS_TESTE_VAGAS=1\nFILA_TESTE_TETO="2"\nFILA_TESTE_FILA=xx\n' > "$proj/.orca/worktree.conf"
mkdir -p "$HOME/.cache/gs-teste-9999.lock1"; echo $$ > "$HOME/.cache/gs-teste-9999.lock1/pid"
echo "$proj [db] desde 20:00:00: runner x" > "$HOME/.cache/gs-teste-9999.lock1/dono"
painel --json > "$tmp/o.json"
igual 'projeto: sobrescreve vagas' 'meu-projeto 1' "$(j 'd["fila"]["config"]["vagas"]["projetos"][0]["projeto"]+" "+str(d["fila"]["config"]["vagas"]["projetos"][0]["valor"])' "$tmp/o.json")"
igual 'projeto: aspas e nome novo no teto' 2 "$(j 'd["fila"]["config"]["teto"]["projetos"][0]["valor"]' "$tmp/o.json")"
igual 'projeto: valor inválido ignorado' '[]' "$(j 'd["fila"]["config"]["modo"]["projetos"]' "$tmp/o.json")"
igual 'projeto: o valor da máquina não muda' 4 "$(j 'd["fila"]["config"]["vagas"]["valor"]' "$tmp/o.json")"
igual 'pool: papéis válidos e escolha' 'orquestra ritmo' "$(j 'd["pool"]["papeis_validos"][-1]+" "+d["pool"]["escolha"]' "$tmp/o.json")"


# Conta nova, adicionar a detectada e remover: pelo --config, validado pelo contas.sh antes de trocar o arquivo.
printf '# minhas contas\nteto=4\na agente=claude vagas=2 peso=5 papeis=escritor,revisor\nb agente=codex vagas=1\nb=3\n' > "$conf_ag"
cfg conta.nova.adicionar=codex conta.nova.vagas=2 conta.nova.config=~/.codex-nova conta.nova.papeis=revisor; igual 'conta nova: exit 0' 0 $?
igual 'conta nova: linha no fim, comentário e ordem preservados' '# minhas contas|teto=4|a agente=claude vagas=2 peso=5 papeis=escritor,revisor|b agente=codex vagas=1|b=3|nova agente=codex vagas=2 peso=1 config=~/.codex-nova papeis=revisor' "$(junta '|' < "$conf_ag")"
cfg conta.nova.adicionar=codex; igual 'conta nova: nome repetido, exit 2' 2 $?
grep -q 'já existe' "$tmp/c.err" && ok 'conta nova: mensagem de conta repetida' || ruim 'conta nova: sem mensagem'
cp "$conf_ag" "$tmp/ag.bak"
cfg conta.zz.adicionar=agente-fora-do-catalogo; igual 'conta nova: agente fora do catálogo, exit 2' 2 $?
grep -q 'fora do catálogo' "$tmp/c.err" && ok 'conta nova: mensagem do contas.sh' || ruim "conta nova: $(cat "$tmp/c.err")"
cfg 'conta.zz.config=com espaço' conta.zz.adicionar=codex; igual 'conta nova: config com espaço, exit 2' 2 $?
cfg conta.Zz.adicionar=codex; igual 'conta nova: nome inválido, exit 2' 2 $?
cmp -s "$conf_ag" "$tmp/ag.bak" && ok 'conta nova: recusas não gravam nada' || ruim 'conta nova: arquivo mudou'
cfg conta.b.remover=1; igual 'remover: exit 0' 0 $?
igual 'remover: some a linha da conta e a legada nome=N' '# minhas contas|teto=4|a agente=claude vagas=2 peso=5 papeis=escritor,revisor|nova agente=codex vagas=2 peso=1 config=~/.codex-nova papeis=revisor|# removida: b codex codex-padrao' "$(junta '|' < "$conf_ag")"
cfg conta.b.remover=1; igual 'remover: conta inexistente, exit 2' 2 $?
cfg conta.a.remover=2; igual 'remover: valor diferente de 1, exit 2' 2 $?
cfg conta.a.remover=1 conta.a.vagas=3 conta.nova.comando=codex; igual 'remover: edição da conta removida é descartada' 0 $?
igual 'remover: só a nova sobra, com o comando' '# minhas contas|teto=4|nova agente=codex vagas=2 peso=1 config=~/.codex-nova papeis=revisor comando=codex|# removida: a b claude claude-padrao codex codex-padrao' "$(junta '|' < "$conf_ag")"

# Remover conta detectada: a auto-adicao do --json nao a recria (codex-padrao), ate o usuario adicionar de novo.
printf 'teto=4\na agente=claude vagas=2 peso=5\nb agente=codex vagas=1\n' > "$conf_ag"
cfg conta.b.remover=1; igual 'remover detectada: exit 0' 0 $?
grep -q '^# removida: .*\bb\b' "$conf_ag" && ok 'remover detectada: a marca guarda o nome e o agente' || ruim "remover detectada: sem marca ($(junta '|' < "$conf_ag"))"
painel --json > "$tmp/rm.json"
igual 'remover detectada: o --json nao recria a conta (nem codex-padrao)' 0 "$(grep -c '^codex' "$conf_ag")"
igual 'remover detectada: a conta fica so como detectada, fora do pool' 'orca 0' "$(j '[x for x in d["pool"]["contas"] if x["nome"]=="codex-padrao"][0]["origem"]+" "+str([x for x in d["pool"]["contas"] if x["nome"]=="codex-padrao"][0]["vagas"])' "$tmp/rm.json")"
cfg conta.b.adicionar=codex; igual 'remover detectada: adicionar de novo, exit 0' 0 $?
igual 'remover detectada: adicionar tira a marca do nome' 0 "$(grep -c '^# removida: .*\bb\b' "$conf_ag")"
igual 'remover detectada: a conta voltou ao arquivo' 1 "$(grep -c '^b agente=codex' "$conf_ag")"

# Duas gravacoes ao mesmo tempo no agentes.conf (--config e auto-adicao do --json): nenhuma se perde.
printf 'teto=4\na agente=claude vagas=1 peso=1\nb agente=codex vagas=1 peso=1\n' > "$conf_ag"
printf '#!/usr/bin/env bash\nsleep 2\nexit 0\n' > "$HOME/.cache/contas.sh"
painel --config conta.a.vagas=3 > "$tmp/p1.out" 2>&1 & p1=$!
painel --config conta.b.peso=5 > "$tmp/p2.out" 2>&1 & p2=$!
wait $p1; r1=$?; wait $p2; r2=$?
igual 'trava: as duas gravacoes simultaneas terminam, exit 0' '0 0' "$r1 $r2"
igual 'trava: as duas mudancas estao no arquivo' 'a agente=claude vagas=3 peso=1|b agente=codex vagas=1 peso=5' "$(grep -E '^(a|b) ' "$conf_ag" | junta '|')"
[ -d "$conf_ag.trava" ] && ruim 'trava: sobrou a pasta de trava' || ok 'trava: liberada ao fim'
rm -f "$HOME/.cache/contas.sh"

# pool.ordem: só as linhas de conta mudam de lugar; comentário colado e linhas globais ficam.
printf '# minhas contas\nteto=4\n# principal\na agente=claude vagas=2 peso=5\nescolha=ordem\nb agente=codex vagas=1\n# extra\nc agente=claude vagas=1 config=~/.claude-c\nram_min=2\n' > "$conf_ag"
cfg pool.ordem=c,a,b; igual 'ordem: exit 0' 0 $?
igual 'ordem: contas trocadas, comentário viaja, globais no lugar' '# minhas contas|teto=4|# extra|c agente=claude vagas=1 config=~/.claude-c|escolha=ordem|# principal|a agente=claude vagas=2 peso=5|b agente=codex vagas=1|ram_min=2' "$(junta '|' < "$conf_ag")"
igual 'ordem: contas.sh lista na ordem nova' 'c a b' "$(CONTAS_CONF="$conf_ag" bash "$raiz/skills/limites-cota/contas.sh" lista | cut -d' ' -f1 | tr '\n' ' ' | sed 's/ $//')"
cp "$conf_ag" "$tmp/ag.bak"
cfg pool.ordem=c,a,zz; igual 'ordem: desconhecida, exit 2' 2 $?
grep -q 'inexistente' "$tmp/c.err" && ok 'ordem: mensagem de conta inexistente' || ruim 'ordem: sem mensagem'
cfg pool.ordem=c,a,a; igual 'ordem: repetida, exit 2' 2 $?
cfg pool.ordem=c,a; igual 'ordem: incompleta, exit 2' 2 $?
grep -q 'todas as contas' "$tmp/c.err" && ok 'ordem: mensagem de lista incompleta' || ruim 'ordem: sem mensagem'
cmp -s "$conf_ag" "$tmp/ag.bak" && ok 'ordem: recusas não gravam nada' || ruim 'ordem: arquivo mudou'
cfg pool.ordem=a,b,c pool.teto=5 conta.b.vagas=2; igual 'ordem: combinada com outras chaves' 0 $?
igual 'ordem: combinada, linhas' 'a agente=claude vagas=2 peso=5|b agente=codex vagas=2|c agente=claude vagas=1 config=~/.claude-c' "$(grep -E '^(a|b|c) ' "$conf_ag" | junta '|')"
igual 'ordem: combinada, teto gravado' 1 "$(grep -c '^teto=5$' "$conf_ag")"


# Conta manual sem escolher agente: o agente sai do executavel do comando (cruzado com o catalogo) ou do diretorio de config.
printf '# minhas contas\nteto=4\nbase agente=claude vagas=1 peso=1\n' > "$conf_ag"
cfg conta.cfg.adicionar=auto conta.cfg.config=~/.claude-x; igual 'manual: so diretorio de config e claude' 0 $?
cfg conta.env.adicionar=auto 'conta.env.comando=CLAUDE_CONFIG_DIR=~/.claude-e claude'; igual 'manual: claude por comando com env' 0 $?
cfg conta.oc.adicionar=auto conta.oc.comando=opencode; igual 'manual: opencode por comando' 0 $?
cfg conta.cb.adicionar=auto conta.cb.comando=claude-b; igual 'manual: claude-b e claude pelo prefixo' 0 $?
cfg conta.ca.adicionar=auto 'conta.ca.comando=claude --x'; igual 'manual: comando com argumento' 0 $?
igual 'manual: linhas gravadas (comentario preservado, comando do catalogo nao gravado, espaco entre aspas)' '# minhas contas|teto=4|base agente=claude vagas=1 peso=1|cfg agente=claude vagas=1 peso=1 config=~/.claude-x|env agente=claude vagas=1 peso=1 config=~/.claude-e|oc agente=opencode vagas=1 peso=1|cb agente=claude vagas=1 peso=1 comando=claude-b|ca agente=claude vagas=1 peso=1 comando="claude --x"' "$(junta '|' < "$conf_ag")"
cp "$conf_ag" "$tmp/ag.bak"
cfg conta.zz.adicionar=auto conta.zz.comando=xyzzy; igual 'manual: executavel desconhecido, exit 2' 2 $?
grep -q 'não reconheço o agente do comando xyzzy; agentes conhecidos: ' "$tmp/c.err" && grep -q 'claude' "$tmp/c.err" && ok 'manual: a mensagem lista os agentes conhecidos' || ruim "manual: mensagem $(cat "$tmp/c.err")"
cfg conta.vz.adicionar=auto; igual 'manual: sem comando nem diretorio, exit 2' 2 $?
grep -q 'informe o comando do CLI' "$tmp/c.err" && ok 'manual: mensagem de falta de dados' || ruim "manual: mensagem $(cat "$tmp/c.err")"
cfg conta.ev.adicionar=auto 'conta.ev.comando=FOO=1 claude'; igual 'manual: variavel de ambiente sem suporte, exit 2' 2 $?
cmp -s "$conf_ag" "$tmp/ag.bak" && ok 'manual: recusas nao gravam nada' || ruim 'manual: arquivo mudou'


# O contas.sh que reconhece ativo=nao vem da outra frente (painel-ativo): aqui o validador e um stub que aprova, para provar so o escritor do painel.
printf '#!/usr/bin/env bash\nexit 0\n' > "$HOME/.cache/contas.sh"
# Nao utilizar: ativo=nao fica na linha da conta (a linha nao some, entao nao e readicionada) e volta ao normal com sim.
printf 'teto=4\na agente=claude vagas=2 peso=5\n' > "$conf_ag"
cfg conta.a.ativo=nao; igual 'ativo: nao grava ativo=nao na linha da conta' 0 $?
igual 'ativo: a linha ganha o token e o resto fica igual' 'a agente=claude vagas=2 peso=5 ativo=nao' "$(grep '^a ' "$conf_ag")"
painel --json > "$tmp/at.json"
igual 'ativo: o --json traz ativo false para a conta marcada' False "$(j '[x for x in d["pool"]["contas"] if x["nome"]=="a"][0]["ativo"]' "$tmp/at.json")"
igual 'ativo: a conta marcada continua listada' a "$(j '[x["nome"] for x in d["pool"]["contas"] if x["nome"]=="a"][0]' "$tmp/at.json")"
igual 'ativo: a linha marcada nao e readicionada nem duplicada' 1 "$(grep -c '^a ' "$conf_ag")"
cfg conta.a.ativo=sim; igual 'ativo: sim volta ao normal, exit 0' 0 $?
igual 'ativo: sim tira o token' 'a agente=claude vagas=2 peso=5' "$(grep '^a ' "$conf_ag")"
painel --json > "$tmp/at.json"
igual 'ativo: o --json volta a ativo true' True "$(j '[x for x in d["pool"]["contas"] if x["nome"]=="a"][0]["ativo"]' "$tmp/at.json")"
cfg conta.a.ativo=talvez; igual 'ativo: valor invalido, exit 2' 2 $?
cfg conta.zz.ativo=nao; igual 'ativo: conta inexistente, exit 2' 2 $?
# Detectada marcada como nao utilizada antes da coleta seguinte: a linha existe e fica como esta.
cfg conta.claude-abcdef12.ativo=nao; igual 'ativo: detectada ja adicionada tambem aceita nao' 0 $?
painel --json > "$tmp/at.json"
igual 'ativo: detectada marcada nao e readicionada' 1 "$(grep -c '^claude-abcdef12 ' "$conf_ag")"
rm -f "$HOME/.cache/contas.sh"


# opencode2 e o perfil gerenciado pelo Orca: so conta como instalado quando o Orca tem conta opencode (orca account add --agent opencode).
{ grep -v '^opencode' "$raiz/skills/limites-cota/agentes-catalogo.conf"; printf '%s\n' 'opencode|opencode|pi-cli||-|sim|nao|-|-|-|' 'opencode2|opencode2|pi-cli||-|sim|nao|-|-|-|'; } > "$tmp/cat2.conf"
nomes_oc='",".join(sorted(x["nome"] for x in d["pool"]["contas"] if x["nome"].startswith("opencode")))'
printf 'teto=4\na agente=claude vagas=2 peso=5\n' > "$conf_ag"
PATH="$tmp/bin:$PATH" CONTAS_CATALOGO="$tmp/cat2.conf" painel --json > "$tmp/oc1.json"
igual 'opencode2: sem conta opencode no Orca so o opencode e detectado' opencode "$(j "$nomes_oc" "$tmp/oc1.json")"
printf 'teto=4\na agente=claude vagas=2 peso=5\n' > "$conf_ag"
PAINEL_TESTE_OPENCODE=1 PATH="$tmp/bin:$PATH" CONTAS_CATALOGO="$tmp/cat2.conf" painel --json > "$tmp/oc2.json"
igual 'opencode2: com conta opencode no Orca o perfil gerenciado entra tambem' 'opencode-oc1,opencode2' "$(j "$nomes_oc" "$tmp/oc2.json")"

# Inicio da trava em epoch ms (mtime do arquivo dono, senao da pasta), alem do desde de sempre.
touch -d @1767225600 "$HOME/.cache/gs-teste-3308.lock1/dono"
painel --json > "$tmp/ts.json"
igual 'fila: desde_ts e o mtime do arquivo dono em ms' 1767225600000 "$(j '[t for t in d["fila"]["travas"] if t["fila"]=="3308" and t["vaga"]==1][0]["desde_ts"]' "$tmp/ts.json")"
igual 'fila: trava sem dono usa o mtime da pasta' True "$(j 'isinstance([t for t in d["fila"]["travas"] if t["fila"]=="3308" and t["vaga"]==2][0]["desde_ts"], int)' "$tmp/ts.json")"
igual 'fila: o desde de hora do dono continua' 20:14:25 "$(j '[t for t in d["fila"]["travas"] if t["fila"]=="3308" and t["vaga"]==1][0]["desde"]' "$tmp/ts.json")"


# Os tres modos da fila e o que cada um grava.
for m in global banco projeto; do
    cfg fila.modo=$m; igual "modo: $m e aceito" 0 $?
    painel --json > "$tmp/m.json"
    igual "modo: $m sai normalizado no --json" $m "$(j 'd["fila"]["modo"]' "$tmp/m.json")"
done
cfg fila.modo=lixo; igual 'modo: valor fora de global, banco e projeto, exit 2' 2 $?

# fila.testes: lista unica (execucao, aguardando, parado), sem a trava do teto, com recurso, projeto e desde_ts em ms.
rm -rf "$HOME/.cache/gs-teste"*.lock* "$HOME/.cache/fila-espera"
mkdir -p "$HOME/.cache/gs-teste-3307.lock1" "$HOME/.cache/gs-teste-3307.lock2" "$HOME/.cache/gs-teste-teto.lock1" "$HOME/.cache/gs-teste-3307.lock3"
echo $$ > "$HOME/.cache/gs-teste-3307.lock1/pid"; echo 'C:/Herd/proj-um [db] desde 20:00:00: php artisan test' > "$HOME/.cache/gs-teste-3307.lock1/dono"
echo 'mysql 127.0.0.1:3307' > "$HOME/.cache/gs-teste-3307.lock1/recurso"; echo 1793640000000 > "$HOME/.cache/gs-teste-3307.lock1/inicio"
echo 99999999 > "$HOME/.cache/gs-teste-3307.lock2/pid"; echo 'C:/Herd/proj-dois [db] desde 19:00:00: pest' > "$HOME/.cache/gs-teste-3307.lock2/dono"
echo 'mysql 127.0.0.1:3307' > "$HOME/.cache/gs-teste-3307.lock2/recurso"; echo 1793630000000 > "$HOME/.cache/gs-teste-3307.lock2/inicio"
echo $$ > "$HOME/.cache/gs-teste-teto.lock1/pid"; echo 'C:/Herd/proj-um [db] desde 20:00:00: php artisan test' > "$HOME/.cache/gs-teste-teto.lock1/dono"
# lock3 acabou de ser criada: sem pid nem dono, ainda nao e teste
mkdir -p "$HOME/.cache/fila-espera/$$" "$HOME/.cache/fila-espera/99999998"
printf '%s\n' 'mysql 127.0.0.1:3307' > "$HOME/.cache/fila-espera/$$/recurso"; echo 1793645000000 > "$HOME/.cache/fila-espera/$$/inicio_ts"
echo 'C:/Herd/proj-tres' > "$HOME/.cache/fila-espera/$$/worktree"; echo 'php artisan test --filter X' > "$HOME/.cache/fila-espera/$$/comando"; echo 3307 > "$HOME/.cache/fila-espera/$$/fila"
echo 'mysql 127.0.0.1:3307' > "$HOME/.cache/fila-espera/99999998/recurso"
painel --json > "$tmp/t.json"
igual 'testes: tres itens (execucao, aguardando, parado), sem o teto, sem o ignorado e sem pid morto de espera' 'execucao aguardando parado' "$(j '" ".join(t["estado"] for t in d["fila"]["testes"])' "$tmp/t.json")"
igual 'testes: execucao com recurso, projeto, comando, vaga e desde_ts' 'mysql 127.0.0.1:3307|proj-um|php artisan test|1|1793640000000' "$(j '"|".join(str(d["fila"]["testes"][0][k]) for k in ("recurso","projeto","comando","vaga","desde_ts"))' "$tmp/t.json")"
igual 'testes: aguardando sem vaga, com inicio da espera' 'None 1793645000000 proj-tres php artisan test --filter X' "$(j 'str(d["fila"]["testes"][1]["vaga"])+" "+str(d["fila"]["testes"][1]["desde_ts"])+" "+d["fila"]["testes"][1]["projeto"]+" "+d["fila"]["testes"][1]["comando"]' "$tmp/t.json")"
igual 'testes: parado e a trava com pid morto' '99999999 proj-dois 2' "$(j 'str(d["fila"]["testes"][2]["pid"])+" "+d["fila"]["testes"][2]["projeto"]+" "+str(d["fila"]["testes"][2]["vaga"])' "$tmp/t.json")"
igual 'testes: cada item traz as chaves do contrato' 'comando desde_ts estado pid projeto recurso vaga worktree' "$(j '" ".join(sorted(d["fila"]["testes"][0]))' "$tmp/t.json")"
igual 'testes: a trava do teto continua em travas, marcada' True "$(j 'any(t["teto"] for t in d["fila"]["travas"])' "$tmp/t.json")"
echo 1793600000000 > "$HOME/.cache/gs-teste-3307.lock2/inicio"; echo 1793650000000 > "$HOME/.cache/fila-espera/$$/inicio_ts"
echo $$ > "$HOME/.cache/gs-teste-3307.lock2/pid"; mkdir -p "$HOME/.cache/fila-espera/$$x" 2>/dev/null
painel --json > "$tmp/t.json"
igual 'testes: dois em execucao saem do mais antigo para o mais novo' '1793600000000 1793640000000' "$(j '" ".join(str(t["desde_ts"]) for t in d["fila"]["testes"] if t["estado"]=="execucao")' "$tmp/t.json")"

# Teste que ja tem a vaga da fila e espera a do teto (fila-teste.sh): um item so, aguardando, com o inicio da espera.
rm -rf "$HOME/.cache/gs-teste"*.lock* "$HOME/.cache/fila-espera"
mkdir -p "$HOME/.cache/gs-teste-3307.lock1" "$HOME/.cache/fila-espera/$$"
echo $$ > "$HOME/.cache/gs-teste-3307.lock1/pid"; echo 'C:/Herd/proj-um [db] desde 20:00:00: pest' > "$HOME/.cache/gs-teste-3307.lock1/dono"; echo 1793640000000 > "$HOME/.cache/gs-teste-3307.lock1/inicio"
echo 1793650000000 > "$HOME/.cache/fila-espera/$$/inicio_ts"; echo gs-teste-teto.lock > "$HOME/.cache/fila-espera/$$/fila"; echo 'C:/Herd/proj-um' > "$HOME/.cache/fila-espera/$$/worktree"
painel --json > "$tmp/te.json"
igual 'testes: vaga da fila + espera do teto e um item so, aguardando, com o inicio da espera' '1 aguardando 1793650000000 1' "$(j 'str(len(d["fila"]["testes"]))+" "+d["fila"]["testes"][0]["estado"]+" "+str(d["fila"]["testes"][0]["desde_ts"])+" "+str(d["fila"]["testes"][0]["vaga"])' "$tmp/te.json")"

# Alertas: estado da cota por conta (medidas falsas de cada tipo) e a lista de alertas no topo.
rm -rf "$HOME/.cache/gs-teste"*.lock* "$HOME/.cache/fila-espera"
printf 'a agente=claude vagas=2\nb agente=codex vagas=1\nsl agente=claude vagas=1 config=/x/team\nil agente=claude vagas=1\nan agente=claude vagas=1\nsm agente=claude vagas=1\ninat agente=claude vagas=1 ativo=nao\n' > "$HOME/.claude/agentes.conf"
touch "$HOME/.cache/agentes/medida.a"
m="$HOME/.cache/agentes"
printf 'sl: sem login (rode CLAUDE_CONFIG_DIR=/x/team claude auth login)\n' > "$m/medida.sl"
printf 'il: ilegível\n' > "$m/medida.il"
printf 'an: sessão 10%% usado | semana 5%% usado\n#cand an 10 5 1793721600 168\n' > "$m/medida.an"; touch -d '2 hours ago' "$m/medida.an"
printf 'inat: sem login (rode claude auth login)\n' > "$m/medida.inat"
painel --json > "$tmp/al.json"
est() { j '[c for c in d["pool"]["contas"] if c["nome"]=="'"$1"'"][0]["cota"]["estado"]' "$tmp/al.json"; }
igual 'alerta: medida recente é ok' ok "$(est a)"
igual 'alerta: "sem login" vira sem_login' sem_login "$(est sl)"
igual 'alerta: ação é o comando entre parênteses' 'CLAUDE_CONFIG_DIR=/x/team claude auth login' "$(j '[c for c in d["pool"]["contas"] if c["nome"]=="sl"][0]["cota"]["acao"]' "$tmp/al.json")"
igual 'alerta: ilegível antigo vira erro' erro "$(est il)"
igual 'alerta: medida de mais de 30 min é antiga' antiga "$(est an)"
igual 'alerta: sem arquivo é sem_medida' sem_medida "$(est sm)"
igual 'alerta: cota nativa do Orca é ok' ok "$(est b)"
igual 'alerta: conta com cota sem medida ainda traz as chaves' 'None None' "$(j 'str([c for c in d["pool"]["contas"] if c["nome"]=="sm"][0]["cota"]["curta"])+" "+str([c for c in d["pool"]["contas"] if c["nome"]=="sm"][0]["cota"]["medida_ha_min"])' "$tmp/al.json")"
igual 'alerta: sem_login e erro viram alertas de nível erro, a inativa não' 'erro erro 2' "$(j 'd["alertas"][0]["nivel"]+" "+d["alertas"][1]["nivel"]+" "+str(len([a for a in d["alertas"] if "inat" in a["texto"]]) + 2)' "$tmp/al.json")"
igual 'alerta: texto claro e ação no alerta de sem_login' 'Conta sl desconectada: reconecte para voltar a medir a cota|CLAUDE_CONFIG_DIR=/x/team claude auth login' "$(j '[a["texto"]+"|"+a["acao"] for a in d["alertas"] if "sl " in a["texto"]][0]' "$tmp/al.json")"
igual 'alerta: antiga e sem_medida não geram alerta' 0 "$(j 'len([a for a in d["alertas"] if "Conta an " in a["texto"] or "Conta sm " in a["texto"]])' "$tmp/al.json")"
igual 'alerta: alerta sem ação não traz a chave' False "$(j '"acao" in [a for a in d["alertas"] if "il " in a["texto"]][0]' "$tmp/al.json")"
# Erro do Orca na conta detectada sem medida: a codex (b) sem medida.
PAINEL_TESTE_CODEX_ERRO=1 painel --json > "$tmp/al2.json"
igual 'alerta: erro do Orca vira erro com a mensagem do Orca' 'erro token expirado' "$(j '[c for c in d["pool"]["contas"] if c["nome"]=="b"][0]["cota"]["estado"]+" "+[c for c in d["pool"]["contas"] if c["nome"]=="b"][0]["cota"]["texto"]' "$tmp/al2.json")"
igual 'alerta: o erro do Orca entra em alertas' 1 "$(j 'len([a for a in d["alertas"] if "token expirado" in a["texto"]])' "$tmp/al2.json")"
igual 'alerta: claude com medida recente ignora o status "unavailable" do Orca' ok "$(j '[c for c in d["pool"]["contas"] if c["nome"]=="a"][0]["cota"]["estado"]' "$tmp/al2.json")"
# Orca fora do ar; testes parados; scripts desatualizados.
PAINEL_ORCA_FALHA=1 painel --json > "$tmp/al3.json"
igual 'alerta: Orca fora do ar' 1 "$(j 'len([a for a in d["alertas"] if a["nivel"]=="erro" and "Orca indisponível" in a["texto"]])' "$tmp/al3.json")"
mkdir -p "$HOME/.cache/gs-teste-3308.lock1"; echo 99999999 > "$HOME/.cache/gs-teste-3308.lock1/pid"; echo 'C:/Herd/proj-x [] desde 20:00:00: pest' > "$HOME/.cache/gs-teste-3308.lock1/dono"
painel --json > "$tmp/al4.json"
igual 'alerta: teste parado na fila vira aviso' 'aviso' "$(j '[a["nivel"] for a in d["alertas"] if "parado" in a["texto"]][0]' "$tmp/al4.json")"
rm -rf "$HOME/.cache/gs-teste-3308.lock1"
rm -f "$m/medida.sl" "$m/medida.il" "$m/medida.an" "$m/medida.inat"
painel --json > "$tmp/al5.json"
igual 'alerta: sem problemas, a lista vem vazia' '[]' "$(j '[a for a in d["alertas"] if "Conta" in a["texto"]]' "$tmp/al5.json")"

# Sem login de ponta a ponta: o limites.sh mede a conta deslogada, grava medida.<conta> e o painel alerta (em vez da cota velha).
mkdir -p "$HOME/.claude-team" "$tmp/bin2"
cat > "$tmp/bin2/claude" <<'STUBD'
#!/usr/bin/env bash
[ "$1 $2" = 'auth status' ] && { echo '{"loggedIn": false, "authMethod": "none"}'; exit 0; }
printf 'Total cost:            $0.0000\nTotal duration (API):  0s\n'
STUBD
chmod +x "$tmp/bin2/claude"
printf 'team agente=claude vagas=1 peso=1 config=~/.claude-team\n' > "$conf_ag"
printf 'team: sessão 84%% usado | semana 30%% usado\n#cand team 84 30 1793721600 168\n' > "$m/medida.team"; touch -d '10 minutes ago' "$m/medida.team"
PATH="$tmp/bin2:$PATH" LIMITES_SEM_API=1 bash "$raiz/skills/limites-cota/limites.sh" > /dev/null 2>&1
if ! head -n 1 "$m/medida.team" | grep -q ': sem login (rode '; then
    echo 'AVISO: este limites.sh ainda nao grava a saida "sem login" (frente POOL); medida.team simulada no formato do medidor'
    printf 'team: sem login (rode CLAUDE_CONFIG_DIR=~/.claude-team claude auth login)\n' > "$m/medida.team"
fi
painel --json > "$tmp/sl.json"
igual 'sem login: a cota da conta deslogada nao fica com o numero velho' 'sem_login None' "$(j '[c for c in d["pool"]["contas"] if c["nome"]=="team"][0]["cota"]["estado"]+" "+str([c for c in d["pool"]["contas"] if c["nome"]=="team"][0]["cota"]["curta"])' "$tmp/sl.json")"
igual 'sem login: alerta de reconexao com a acao' 'CLAUDE_CONFIG_DIR=~/.claude-team claude auth login' "$(j '[a["acao"] for a in d["alertas"] if "Conta team desconectada" in a["texto"]][0]' "$tmp/sl.json")"
rm -f "$m/medida.team"

[ "$falhas" = 0 ] && echo 'TUDO OK' || { echo "$falhas falha(s)"; exit 1; }

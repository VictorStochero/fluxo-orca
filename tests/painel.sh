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
    'account list') echo '{"ok":true,"result":{"claude":{"accounts":[{"id":"abcdef1234567890","email":"gerenciada@x.com"}],"activeAccountId":null},"codex":{"accounts":[],"activeAccountId":null,"systemDefault":{"hasAuth":true,"authKind":"oauth","email":"cx@x.com"}},"opencode":{"accounts":[],"activeAccountId":null},"devin":{"accounts":[{"id":"d1","label":"Devin A"}],"activeAccountId":null},"rateLimits":{"claude":{"status":"unavailable","session":null,"weekly":null},"codex":{"status":"ok","session":{"usedPercent":95,"resetDescription":"14:48"},"weekly":{"usedPercent":50,"resetDescription":"qua., 10:01"},"updatedAt":0}}}}' ;;
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
igual 'fila: padrões' 'global 2 3' "$(j 'd["fila"]["modo"]+" "+str(d["fila"]["vagas"])+" "+str(d["fila"]["teto"])' "$tmp/e.json")"
igual 'pool: usadas e vagas' '1 2' "$(j 'str(d["pool"]["contas"][0]["usadas"])+" "+str(d["pool"]["contas"][0]["vagas"])' "$tmp/e.json")"
igual 'pool: cota curta/longa/alerta' '90 25 True' "$(j 'str(d["pool"]["contas"][0]["cota"]["curta"])+" "+str(d["pool"]["contas"][0]["cota"]["longa"])+" "+str(d["pool"]["contas"][0]["cota"]["alerta"])' "$tmp/e.json")"
igual 'orca: cota nativa vale sobre a medida (codex sem medida)' '95 50 orca True' "$(j 'str(d["pool"]["contas"][1]["cota"]["curta"])+" "+str(d["pool"]["contas"][1]["cota"]["longa"])+" "+d["pool"]["contas"][1]["cota"]["fonte"]+" "+str(d["pool"]["contas"][1]["detectada"])' "$tmp/e.json")"
igual 'orca: conta sem cota nativa mantém a medida' 'None 90 False' "$(j 'str(d["pool"]["contas"][0]["cota"].get("fonte"))+" "+str(d["pool"]["contas"][0]["cota"]["curta"])+" "+str(d["pool"]["contas"][0]["detectada"])' "$tmp/e.json")"
igual 'orca: conta gerenciada fora do agentes.conf entra com origem orca' 'claude-abcdef12 orca gerenciada@x.com claude' "$(j '" ".join([c["nome"],c["origem"],c["rotulo"],c["agente"]]) if (c:=[x for x in d["pool"]["contas"] if x["origem"]=="orca"][0]) else 0' "$tmp/e.json")"
igual 'orca: contas detectadas não entram nas vagas' '0 0' "$(j 'str([x for x in d["pool"]["contas"] if x["origem"]=="orca"][0]["vagas"])+" "+str([x for x in d["pool"]["contas"] if x["origem"]=="orca"][0]["usadas"])' "$tmp/e.json")"
igual 'orca: manual não perde a origem' manual "$(j 'd["pool"]["contas"][0]["origem"]' "$tmp/e.json")"
igual 'origem: conta do agentes.conf que o Orca também detecta é ambos' ambos "$(j 'd["pool"]["contas"][1]["origem"]' "$tmp/e.json")"
igual 'origem: só no agentes.conf é manual, só no Orca é orca' 'manual orca' "$(j 'd["pool"]["contas"][0]["origem"]+" "+[x for x in d["pool"]["contas"] if x["nome"]=="claude-abcdef12"][0]["origem"]' "$tmp/e.json")"
# Agentes instalados: catálogo (id-orca + comando) cruzado com o PATH; só entra o tipo que ainda não tem conta.
printf '%s
' 'claude|claude|claude||claude|sim|sim|-|-|-|' 'pi|pi|pi-cli||-|nao|nao|-|-|-|' 'ghost|ghost|ghost-cli||-|nao|nao|-|-|-|' 'semid||pi-cli||-|nao|nao|-|-|-|' > "$tmp/cat.conf"
printf '#!/usr/bin/env bash
' > "$tmp/bin/pi-cli"; chmod +x "$tmp/bin/pi-cli"; cp "$tmp/bin/pi-cli" "$tmp/bin/pi-cli.cmd"  # .cmd: o PATHEXT do Windows
PATH="$tmp/bin:$PATH" CONTAS_CATALOGO="$tmp/cat.conf" painel --json > "$tmp/i.json"
igual 'instalado: agente do catálogo no PATH entra fora do pool' 'pi orca pi' "$(j '" ".join([c["nome"],c["origem"],c["agente"]]) if (c:=[x for x in d["pool"]["contas"] if x["nome"]=="pi"][0]) else 0' "$tmp/i.json")"
igual 'instalado: o rótulo diz como o Orca abre' True "$(j '"orca agent launch --agent pi" in [x for x in d["pool"]["contas"] if x["nome"]=="pi"][0]["rotulo"]' "$tmp/i.json")"
igual 'instalado: sem CLI no PATH ou sem id-orca não aparece' 0 "$(j 'len([x for x in d["pool"]["contas"] if x["nome"] in ("ghost","semid")])' "$tmp/i.json")"
igual 'instalado: tipo que já tem conta não duplica' 0 "$(j 'len([x for x in d["pool"]["contas"] if x["agente"]=="claude" and x["origem"]=="orca" and x["nome"]=="claude"])' "$tmp/i.json")"
# Instalado: o catálogo fica em ~/.cache (ao lado do script), não em ../limites-cota.
cp "$tmp/cat.conf" "$HOME/.cache/agentes-catalogo.conf"
PATH="$tmp/bin:$PATH" painel --json > "$tmp/i2.json"
igual 'instalado: catálogo de ~/.cache vale quando não há CONTAS_CATALOGO' 'pi' "$(j '[x["nome"] for x in d["pool"]["contas"] if x["origem"]=="orca" and x["nome"]=="pi"][0]' "$tmp/i2.json")"
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
printf 'teto=4\nram_min=3\na agente=claude vagas=2 peso=5 papeis=escritor,revisor\nb agente=codex vagas=1\nb=3\n' > "$conf_ag"

# Modo da fila: o painel grava global; recurso (nome antigo) é aceito e gravado como global.
cfg fila.modo=recurso; igual 'config modo: recurso exit 0' 0 $?
igual 'config modo: recurso vira global no arquivo' 1 "$(grep -c '^FILA_TESTE_FILA=global$' "$conf_fila")"
printf 'FILA_TESTE_FILA=recurso
' > "$conf_fila"; painel --json > "$tmp/m.json"
igual 'modo: recurso antigo aparece como global' global "$(j 'd["fila"]["modo"]' "$tmp/m.json")"
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
igual 'remover: some a linha da conta e a legada nome=N' '# minhas contas|teto=4|a agente=claude vagas=2 peso=5 papeis=escritor,revisor|nova agente=codex vagas=2 peso=1 config=~/.codex-nova papeis=revisor' "$(junta '|' < "$conf_ag")"
cfg conta.b.remover=1; igual 'remover: conta inexistente, exit 2' 2 $?
cfg conta.a.remover=2; igual 'remover: valor diferente de 1, exit 2' 2 $?
cfg conta.a.remover=1 conta.a.vagas=3 conta.nova.comando=codex; igual 'remover: edição da conta removida é descartada' 0 $?
igual 'remover: só a nova sobra, com o comando' '# minhas contas|teto=4|nova agente=codex vagas=2 peso=1 config=~/.codex-nova papeis=revisor comando=codex' "$(junta '|' < "$conf_ag")"

[ "$falhas" = 0 ] && echo 'TUDO OK' || { echo "$falhas falha(s)"; exit 1; }

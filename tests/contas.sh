#!/usr/bin/env bash
# Prova do registro de contas (catálogo do plugin + ~/.claude/agentes.conf) com HOME isolado.
raiz=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export HOME="$tmp/home"
mkdir -p "$HOME/.claude"
falhas=0
ok() { echo "ok   $1"; }
ruim() { echo "FALHA $1"; falhas=$((falhas + 1)); }
lib="$raiz/skills/limites-cota/contas.sh"
igual() { # nome esperado obtido
    if [ "$2" = "$3" ]; then ok "$1"; else ruim "$1: esperado [$2], veio [$3]"; fi
}
carrega() { # comando bash a rodar depois de carregar o registro
    bash -c 'source "$1" && contas_carrega && eval "$2"' bash "$lib" "$1" 2>"$tmp/erro"
}
rc_carrega() { bash -c 'source "$1" && contas_carrega' bash "$lib" >/dev/null 2>"$tmp/erro"; echo $?; }

# Catálogo real (nenhum agente novo passou pela prova do GUIA: testado=-) e o "provado": a mesma tabela com testado preenchido onde há trava.
real="$raiz/skills/limites-cota/agentes-catalogo.conf"
provado="$tmp/catalogo-provado.conf"
while IFS= read -r l || [ -n "$l" ]; do
    case "$l" in
        '' | '#'*) printf '%s\n' "$l" ;;
        *) IFS='|' read -r c1 c2 c3 c4 c5 c6 c7 c8 c9 c10 c11 <<< "$l"
           [ "$c6" = sim ] && c10=2026-10-30
           printf '%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s\n' "$c1" "$c2" "$c3" "$c4" "$c5" "$c6" "$c7" "$c8" "$c9" "$c10" "$c11" ;;
    esac
done < "$real" > "$provado"
export CONTAS_CATALOGO="$provado"
# Carimbo de trava instalada nesta máquina (instala-agente.sh --aplicar); as recusas por falta dele ficam mais abaixo.
mkdir -p "$HOME/.cache"; for ag in gemini kimi opencode; do date +%F > "$HOME/.cache/trava-$ag.ok"; done

# Catálogo: os 45 agentes da tela do Orca, chave única.
n=$(grep -cv -e '^#' -e '^[[:space:]]*$' "$raiz/skills/limites-cota/agentes-catalogo.conf")
igual 'catálogo com 45 agentes' 45 "$n"
dup=$(grep -v -e '^#' -e '^[[:space:]]*$' "$raiz/skills/limites-cota/agentes-catalogo.conf" | cut -d'|' -f1 | sort | uniq -d)
igual 'catálogo sem chave repetida' '' "$dup"

igual 'catálogo: 11 colunas por linha' 0 "$(grep -v -e '^#' -e '^[[:space:]]*$' "$raiz/skills/limites-cota/agentes-catalogo.conf" | awk -F'|' 'NF != 11' | wc -l | tr -d ' ')"

# Sem agentes.conf: as contas de hoje, na ordem de hoje.
igual 'padrão: contas' 'team pessoal codex agy' "$(carrega 'echo $CONTAS')"
igual 'padrão: escolha' 'ritmo' "$(carrega 'echo $ESCOLHA')"
igual 'padrão: peso' 1 "$(carrega 'conta_campo team peso')"
igual 'padrão: team usa ~/.claude-team' "$HOME/.claude-team" "$(carrega 'conta_campo team config')"
igual 'padrão: pessoal ilimitada' 0 "$(carrega 'conta_campo pessoal vagas')"
igual 'padrão: codex uma vaga' 1 "$(carrega 'conta_campo codex vagas')"
igual 'padrão: codex medido pelo Orca' 'orca:codex' "$(carrega 'conta_campo codex medidor')"
igual 'padrão: agy só segunda opinião' 'segunda-opiniao' "$(carrega 'conta_campo agy papeis')"
igual 'padrão: pessoal escreve' sim "$(carrega 'conta_tem_papel pessoal escritor && echo sim')"

# claude-b entra só medida quando a pasta existe.
mkdir -p "$HOME/.claude-b"
igual 'padrão: claude-b com a pasta' 'team pessoal codex agy claude-b' "$(carrega 'echo $CONTAS')"
igual 'padrão: claude-b não escreve' nao "$(carrega 'conta_tem_papel claude-b escritor || echo nao')"
rmdir "$HOME/.claude-b"

# Linhas antigas conta=N só mudam as vagas das contas padrão.
printf 'team=2\npessoal=0\ncodex=3\nagy=5\n' > "$HOME/.claude/agentes.conf"
igual 'legado: contas padrão' 'team pessoal codex agy' "$(carrega 'echo $CONTAS')"
igual 'legado: vagas do team' 2 "$(carrega 'conta_campo team vagas')"
igual 'legado: vagas do agy' 5 "$(carrega 'conta_campo agy vagas')"

# Registro do dev: só as contas listadas, na ordem das linhas.
cat > "$HOME/.claude/agentes.conf" <<'EOF'
escolha=ritmo
# contas desta máquina
pessoal agente=claude papeis=orquestra
team    agente=claude config=~/.claude-team vagas=1 papeis=escritor,revisor
claude-b agente=claude comando=claude-b config=~/.claude-b vagas=1 papeis=escritor,revisor
codex   agente=codex vagas=1 papeis=escritor modelo=gpt-6.1-sol
minimax agente=opencode modelo="minimax/MiniMax-M2" vagas=1 papeis=escritor medidor=orca:minimax
team=2
EOF
igual 'registro: contas na ordem' 'pessoal team claude-b codex minimax' "$(carrega 'echo $CONTAS')"
igual 'registro: legado sobrescreve vagas' 2 "$(carrega 'conta_campo team vagas')"
igual 'registro: comando próprio' 'claude-b' "$(carrega 'conta_campo claude-b comando')"
igual 'registro: ~ expandido' "$HOME/.claude-b" "$(carrega 'conta_campo claude-b config')"
igual 'registro: medidor sobrescrito' 'orca:minimax' "$(carrega 'conta_campo minimax medidor')"
igual 'registro: modelo entre aspas' 'minimax/MiniMax-M2' "$(carrega 'conta_campo minimax modelo')"
igual 'registro: argumentos do catálogo' '--dangerously-skip-permissions' "$(carrega 'conta_campo team args')"
igual 'registro: pessoal só orquestra' nao "$(carrega 'conta_tem_papel pessoal escritor || echo nao')"
igual 'registro: team revisa' sim "$(carrega 'conta_tem_papel team revisor && echo sim')"
igual 'registro: id do Orca do opencode' opencode "$(carrega 'conta_campo minimax id')"

# Agente sem a trava de comando remoto (fora de claude, codex e antigravity) só trabalha com papel escrito.
printf 'k agente=kimi vagas=1\nk2 agente=kimi vagas=1 papeis=escritor\nc agente=codex\n' > "$HOME/.claude/agentes.conf"
igual 'trava: kimi sem papeis não escreve' nao "$(carrega 'conta_tem_papel k escritor || echo nao')"
igual 'trava: kimi sem papeis fora do pool' nao "$(carrega 'conta_no_pool k || echo nao')"
igual 'trava: kimi com papel escrito escreve' sim "$(carrega 'conta_tem_papel k2 escritor && echo sim')"
igual 'trava: codex mantém o padrão' sim "$(carrega 'conta_tem_papel c escritor && echo sim')"
cat > "$HOME/.claude/agentes.conf" <<'EOF'
pessoal agente=claude papeis=orquestra
team    agente=claude config=~/.claude-team vagas=1 papeis=escritor,revisor
claude-b agente=claude comando=claude-b config=~/.claude-b vagas=1 papeis=escritor,revisor
codex   agente=codex vagas=1 papeis=escritor modelo=gpt-6.1-sol
EOF
# Capacidades do catálogo real (hook antes de comando, fim de turno, regras, skills, testado).
export CONTAS_CATALOGO="$real"
printf 'g agente=gemini
k agente=kimi
o agente=opencode
c agente=cursor
t agente=claude-agent-teams
cx agente=codex
' > "$HOME/.claude/agentes.conf"
igual 'capacidade: gemini pre' sim "$(carrega 'conta_campo g pre')"
igual 'capacidade: gemini fim' sim "$(carrega 'conta_campo g fim')"
igual 'capacidade: gemini regras' '~/.gemini/GEMINI.md' "$(carrega 'conta_campo g regras')"
igual 'capacidade: gemini skills' '~/.agents/skills' "$(carrega 'conta_campo g skills')"
igual 'capacidade: kimi mantém a nota' 'nao-testado' "$(carrega 'conta_campo k nota')"
igual 'capacidade: opencode sem fim' nao "$(carrega 'conta_campo o fim')"
igual 'capacidade: cursor sem trava' nao "$(carrega 'conta_campo c pre')"
igual 'capacidade: desconhecido' '-' "$(carrega 'conta_campo t pre')"
igual 'capacidade: testado ainda sem prova' '-' "$(carrega 'conta_campo cx testado')"

# Papel de trabalho só em agente com trava de comando (pre=sim); sem fim de turno a conta entra com aviso.
for ag in cursor claude-agent-teams; do
    for papel in escritor mecanico revisor verificador; do
        printf 'x agente=%s papeis=%s
' "$ag" "$papel" > "$HOME/.claude/agentes.conf"
        igual "papel: $ag recusa $papel" 2 "$(rc_carrega)"
        grep -q "$ag sem trava de comando: só segunda-opiniao" "$tmp/erro" || ruim "papel: mensagem de $ag/$papel: $(cat "$tmp/erro")"
    done
done
printf 'x agente=cursor papeis=segunda-opiniao,orquestra
' > "$HOME/.claude/agentes.conf"
igual 'papel: cursor aceita segunda-opiniao' 0 "$(rc_carrega)"
printf 'x agente=gemini papeis=escritor
' > "$HOME/.claude/agentes.conf"
igual 'papel: gemini com pre=sim e testado=- é recusado' 2 "$(rc_carrega)"
grep -q 'gemini: trava só documentada, rode a prova do GUIA fase 4b e registre testado=<data>' "$tmp/erro" || ruim "papel: mensagem da trava só documentada: $(cat "$tmp/erro")"
printf 'x agente=gemini papeis=segunda-opiniao
' > "$HOME/.claude/agentes.conf"
igual 'papel: gemini testado=- dá segunda opinião' 0 "$(rc_carrega)"
printf 'x agente=codex papeis=escritor,revisor\ny agente=antigravity papeis=escritor\nz agente=claude papeis=escritor\n' > "$HOME/.claude/agentes.conf"
igual 'papel: claude, codex e antigravity seguem sem testado' 0 "$(rc_carrega)"
export CONTAS_CATALOGO="$provado"
printf 'x agente=gemini papeis=escritor
' > "$HOME/.claude/agentes.conf"
rm "$HOME/.cache/trava-gemini.ok"
igual 'papel: gemini provado sem carimbo da máquina é recusado' 2 "$(rc_carrega)"
grep -q 'gemini: trava não instalada nesta máquina — rode bash ~/.cache/instala-agente.sh gemini --aplicar' "$tmp/erro" || ruim "papel: mensagem do carimbo: $(cat "$tmp/erro")"
date +%F > "$HOME/.cache/trava-gemini.ok"
igual 'papel: gemini com testado=2026-10-30 e carimbo escreve' 0 "$(rc_carrega)"
igual 'aviso: com fim de turno não avisa' '' "$(bash "$lib" lista | grep -c aviso | grep -v '^0$')"
printf 'o agente=opencode papeis=escritor
' > "$HOME/.claude/agentes.conf"
igual 'papel: opencode aceito sem fim' 0 "$(rc_carrega)"
case "$(bash "$lib" lista)" in *"aviso=sem fim de turno: coordenador cobra worker_done"*) ok 'aviso: sem fim de turno' ;; *) ruim 'aviso: sem fim de turno' ;; esac
printf 'o agente=opencode papeis=segunda-opiniao
' > "$HOME/.claude/agentes.conf"
case "$(bash "$lib" lista)" in *aviso*) ruim 'aviso: segunda-opiniao não precisa de fim' ;; *) ok 'aviso: segunda-opiniao não precisa de fim' ;; esac
cat > "$HOME/.claude/agentes.conf" <<'EOF'
pessoal agente=claude papeis=orquestra
team    agente=claude config=~/.claude-team vagas=1 papeis=escritor,revisor
claude-b agente=claude comando=claude-b config=~/.claude-b vagas=1 papeis=escritor,revisor
codex   agente=codex vagas=1 papeis=escritor modelo=gpt-6.1-sol
EOF

# Comando de lançamento para orca-libera.sh --cria --command.
lanca() { bash "$lib" lanca "$@" 2>"$tmp/erro"; }
igual 'lança: team escritor' "CLAUDE_CONFIG_DIR=$HOME/.claude-team claude --dangerously-skip-permissions --agent fluxo-orca:escritor --advisor opus --model claude-sonnet-5-5" "$(lanca team escritor claude-sonnet-5-5)"
igual 'lança: advisor próprio' "CLAUDE_CONFIG_DIR=$HOME/.claude-team claude --dangerously-skip-permissions --agent fluxo-orca:escritor --advisor sonnet" "$(CONTAS_ADVISOR=sonnet lanca team fluxo-orca:escritor)"
igual 'lança: advisor vazio desliga' "CLAUDE_CONFIG_DIR=$HOME/.claude-team claude --dangerously-skip-permissions --agent fluxo-orca:escritor" "$(CONTAS_ADVISOR= lanca team escritor)"
igual 'lança: codex usa o modelo da conta' 'codex --dangerously-bypass-approvals-and-sandbox --model gpt-6.1-sol' "$(lanca codex escritor)"
igual 'lança: claude-b com comando próprio' "CLAUDE_CONFIG_DIR=$HOME/.claude-b claude-b --dangerously-skip-permissions --agent fluxo-orca:revisor" "$(lanca claude-b revisor)"
igual 'lança: agente de outro plugin' "CLAUDE_CONFIG_DIR=$HOME/.claude-team claude --dangerously-skip-permissions --agent auditoria-pre-subida:auditor --model claude-opus-5-5" "$(lanca team auditoria-pre-subida:auditor claude-opus-5-5)"
lanca nenhuma escritor >/dev/null; igual 'lança: conta desconhecida' 2 $?

# Erros: linha inválida para tudo, com a linha na mensagem.
for linha in 'Team! agente=claude' 'x agente=inexistente' 'x agente=claude cor=azul' 'x agente=claude vagas=muitas' \
             'x config=~/.y' 'x agente=claude papeis=chefe' 'x agente=claude medidor=balanca' 'escolha=sorteio' \
             'x agente=claude peso=0' 'x agente=claude peso=-1' 'x agente=claude peso=1.5' \
             'teto=-1' 'teto=abc' 'team=abc' 'outra=2' 'x agente=claude modelo="sem fim'; do
    printf '%s\n' "$linha" > "$HOME/.claude/agentes.conf"
    igual "erro: $linha" 2 "$(rc_carrega)"
    grep -qF "$linha" "$tmp/erro" || ruim "erro sem a linha: $linha"
done
printf 'x agente=claude\nx agente=codex\n' > "$HOME/.claude/agentes.conf"
igual 'erro: conta repetida' 2 "$(rc_carrega)"
printf 'a-b agente=claude\na_b agente=codex\n' > "$HOME/.claude/agentes.conf"
igual 'erro: nomes que colidem na variável' 2 "$(rc_carrega)"

# Carregar duas vezes (o limites.sh recarrega as padrão quando o registro falha) não acusa repetida.
printf 'team agente=claude\n' > "$HOME/.claude/agentes.conf"
igual 'recarga limpa o registro anterior' 'team pessoal codex agy' "$(carrega 'CONTAS_CONF=/dev/null; contas_carrega && echo $CONTAS')"

# Caminho com espaço sai escapado na linha de lançamento.
printf 'sp agente=claude config="~/conta com espaço"\n' > "$HOME/.claude/agentes.conf"
igual 'lança: config com espaço' "CLAUDE_CONFIG_DIR=$(printf '%q' "$HOME/conta com espaço") claude --dangerously-skip-permissions --agent fluxo-orca:escritor --advisor opus" "$(bash "$lib" lanca sp escritor 2>&1)"

# Bash 3.2: nada de arrays associativos.
printf 'dev2 agente=claude config=~/.claude-dev2 vagas=1\n' > "$HOME/.claude/agentes.conf"
saida=$(bash -c '
    declare() { case "$1" in -A*) return 2 ;; esac; builtin declare "$@"; }
    source "$1" && contas_carrega && echo "$CONTAS $(conta_campo dev2 vagas)"' bash "$lib" 2>&1)
igual 'sem arrays associativos' 'dev2 1' "$saida"

[ "$falhas" = 0 ] && echo "tudo ok" || { echo "$falhas falha(s)"; exit 1; }

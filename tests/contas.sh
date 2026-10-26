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

# Catálogo: os 45 agentes da tela do Orca, chave única.
n=$(grep -cv -e '^#' -e '^[[:space:]]*$' "$raiz/skills/limites-cota/agentes-catalogo.conf")
igual 'catálogo com 45 agentes' 45 "$n"
dup=$(grep -v -e '^#' -e '^[[:space:]]*$' "$raiz/skills/limites-cota/agentes-catalogo.conf" | cut -d'|' -f1 | sort | uniq -d)
igual 'catálogo sem chave repetida' '' "$dup"

# Sem agentes.conf: as contas de hoje, na ordem de hoje.
igual 'padrão: contas' 'team pessoal codex agy' "$(carrega 'echo $CONTAS')"
igual 'padrão: escolha' 'ritmo' "$(carrega 'echo $ESCOLHA')"
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

# Comando de lançamento para orca-libera.sh --cria --command.
lanca() { bash "$lib" lanca "$@" 2>"$tmp/erro"; }
igual 'lança: team escritor' "CLAUDE_CONFIG_DIR=$HOME/.claude-team claude --dangerously-skip-permissions --agent fluxo-orca:escritor --model claude-sonnet-5-5" "$(lanca team escritor claude-sonnet-5-5)"
igual 'lança: codex usa o modelo da conta' 'codex --dangerously-bypass-approvals-and-sandbox --model gpt-6.1-sol' "$(lanca codex escritor)"
igual 'lança: claude-b com comando próprio' "CLAUDE_CONFIG_DIR=$HOME/.claude-b claude-b --dangerously-skip-permissions --agent fluxo-orca:revisor" "$(lanca claude-b revisor)"
lanca nenhuma escritor >/dev/null; igual 'lança: conta desconhecida' 2 $?

# Erros: linha inválida para tudo, com a linha na mensagem.
for linha in 'Team! agente=claude' 'x agente=inexistente' 'x agente=claude cor=azul' 'x agente=claude vagas=muitas' \
             'x config=~/.y' 'x agente=claude papeis=chefe' 'x agente=claude medidor=balanca' 'escolha=sorteio' \
             'team=abc' 'outra=2' 'x agente=claude modelo="sem fim'; do
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
igual 'lança: config com espaço' "CLAUDE_CONFIG_DIR=$(printf '%q' "$HOME/conta com espaço") claude --dangerously-skip-permissions --agent fluxo-orca:escritor" "$(bash "$lib" lanca sp escritor 2>&1)"

# Bash 3.2: nada de arrays associativos.
printf 'dev2 agente=claude config=~/.claude-dev2 vagas=1\n' > "$HOME/.claude/agentes.conf"
saida=$(bash -c '
    declare() { case "$1" in -A*) return 2 ;; esac; builtin declare "$@"; }
    source "$1" && contas_carrega && echo "$CONTAS $(conta_campo dev2 vagas)"' bash "$lib" 2>&1)
igual 'sem arrays associativos' 'dev2 1' "$saida"

[ "$falhas" = 0 ] && echo "tudo ok" || { echo "$falhas falha(s)"; exit 1; }

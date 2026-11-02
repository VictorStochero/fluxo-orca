#!/usr/bin/env bash
# Prova do instalar.sh (coordenar sem Claude Code) com HOME isolado: simulação, aplicação e segunda execução sem mudanças.
raiz=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export HOME="$tmp/home"
mkdir -p "$HOME"
falhas=0
ok() { echo "ok   $1"; }
ruim() { echo "FALHA $1"; falhas=$((falhas + 1)); }
comeca() { case "$3" in "$2"*) ok "$1" ;; *) ruim "$1: esperado começar com [$2], veio [$3]" ;; esac; }
igual() { if [ "$2" = "$3" ]; then ok "$1"; else ruim "$1: esperado [$2], veio [$3]"; fi; }
contem() { case "$3" in *"$2"*) ok "$1" ;; *) ruim "$1: faltou [$2] em [$3]" ;; esac; }
existe() { if [ -e "$2" ]; then ok "$1"; else ruim "$1: falta $2"; fi; }
snapshot() { (cd "$HOME" && find . -type f | sort | xargs cat | cksum; find . -type f | sort | tr '\n' ' '); }

bash "$raiz/instalar.sh" >/dev/null 2>&1; igual 'uso: sem --agente' 2 $?
bash "$raiz/instalar.sh" --agente >/dev/null 2>&1; igual 'uso: --agente sem valor' 2 $?
bash "$raiz/instalar.sh" --agente nenhum >/dev/null 2>&1; igual 'uso: agente fora do catálogo' 2 $?
contem 'uso: lista os agentes' 'codex' "$(bash "$raiz/instalar.sh" 2>&1)"

# Simulação: mostra e não grava nada.
saida=$(bash "$raiz/instalar.sh" --agente codex)
contem 'codex: simulação mostra regras' 'regras em' "$saida"
contem 'codex: simulação mostra trava' 'PreToolUse' "$saida"
igual 'codex: simulação não grava' '' "$(cd "$HOME" && find . -type f)"

# Aplicação: scripts, regras, skills, trava e fim.
bash "$raiz/instalar.sh" --agente codex --aplicar >/dev/null
existe 'codex: scripts em ~/.cache' "$HOME/.cache/orca-libera.sh"
existe 'codex: guarda em ~/.cache' "$HOME/.cache/guarda-externos.sh"
existe 'codex: regras' "$HOME/.codex/AGENTS.md"
existe 'codex: skills' "$HOME/.agents/skills/delegacao/SKILL.md"
existe 'codex: hooks.json' "$HOME/.codex/hooks.json"
existe 'codex: confiança' "$HOME/.codex/config.toml"
contem 'codex: regras do coordenador' 'Como coordenador' "$(cat "$HOME/.codex/AGENTS.md")"
antes=$(snapshot)
saida=$(bash "$raiz/instalar.sh" --agente codex --aplicar)
igual 'codex: segunda execução não muda nada' "$antes" "$(snapshot)"
case "$saida" in *"[instalado]"* | *"[instalaria]"*) ruim "codex: segunda execução diz que instalou: $saida" ;; *) ok 'codex: segunda execução só confirma' ;; esac

# Agente sem diretório de skills: o índice vai no arquivo de regras, apontando para as cópias.
printf '%s\n' '# teste' 'semskills|||||nao|nao|~/.semskills/REGRAS.md|-|-|' > "$tmp/catalogo.conf"
INSTALA_CATALOGO="$tmp/catalogo.conf" bash "$raiz/skills/limites-cota/instala-agente.sh" semskills --aplicar >/dev/null
regras=$(cat "$HOME/.semskills/REGRAS.md")
contem 'sem skills: índice nas regras' '~/.agents/skills/delegacao/SKILL.md' "$regras"
contem 'sem skills: regras do coordenador' 'Como coordenador' "$regras"
existe 'sem skills: cópias para o índice apontar' "$HOME/.agents/skills/delegacao/SKILL.md"

# Versão: sessão antiga (resume/compact) não rebaixa scripts nem skills já instalados por versão mais nova.
falso_plugin() { # versao: raiz com um script, um medidor e uma skill cujo conteúdo é a versão
    local r="$tmp/plugin-$1"
    mkdir -p "$r/.claude-plugin" "$r/hooks" "$r/skills/s"
    printf '{\n  "name": "x",\n  "version": "%s"\n}\n' "$1" > "$r/.claude-plugin/plugin.json"
    echo x.sh > "$r/hooks/scripts.lista"; echo velho.sh > "$r/hooks/scripts.removidos"
    echo "$1" > "$r/x.sh"; echo "$1" > "$r/skills/s/SKILL.md"
    echo "$r"
}
. "$raiz/hooks/lib-instala.sh"
novo=$(falso_plugin 2.13.0); velho=$(falso_plugin 2.12.1); antigo=$(falso_plugin 2.9.0)
c="$tmp/vcache"; s="$tmp/vskills"
copia_scripts "$novo" "$c"; copia_skills "$novo" "$s"
igual 'versão: instalação grava o marcador' 2.13.0 "$(cat "$c/fluxo-orca.versao")"
copia_scripts "$velho" "$c" 2> "$tmp/av.err"; copia_skills "$velho" "$s" 2>> "$tmp/av.err"
comeca 'versão: instalação mais velha avisa' 'fluxo-orca: ' "$(head -1 "$tmp/av.err")"
igual 'versão: aviso nos dois destinos' 2 "$(grep -c 'mais nova que 2.12.1' "$tmp/av.err")"
igual 'versão: 2.12.1 não rebaixa o script' 2.13.0 "$(cat "$c/x.sh")"
igual 'versão: 2.12.1 não rebaixa a skill' 2.13.0 "$(cat "$s/s/SKILL.md")"
igual 'versão: marcador intacto' 2.13.0 "$(cat "$c/fluxo-orca.versao")"
echo editado > "$c/x.sh"; echo editado > "$s/s/SKILL.md"
copia_scripts "$novo" "$c"; copia_skills "$novo" "$s"
igual 'versão: igual recopia o script alterado' 2.13.0 "$(cat "$c/x.sh")"
igual 'versão: igual recopia a skill alterada' 2.13.0 "$(cat "$s/s/SKILL.md")"
copia_scripts "$antigo" "$c"
igual 'versão: 2.9.0 < 2.13.0 (não é lexical)' 2.13.0 "$(cat "$c/x.sh")"
copia_scripts "$velho" "$tmp/c2"; copia_skills "$velho" "$tmp/s2"
igual 'versão: sem marcador copia' 2.12.1 "$(cat "$tmp/c2/x.sh")"
igual 'versão: sem marcador grava o marcador' 2.12.1 "$(cat "$tmp/c2/fluxo-orca.versao")"
copia_scripts "$novo" "$tmp/c2"
igual 'versão: mais nova atualiza' 2.13.0 "$(cat "$tmp/c2/x.sh")"


# 3.0: sem fila e pool próprios. Hook de teste fora, scripts removidos sem sobra no código, instalador só apaga o que é dele.
[ ! -e "$raiz/hooks/fila-testes.sh" ] && ok 'hook fila-testes.sh removido' || ruim 'hook fila-testes.sh ainda existe'
case "$(cat "$raiz/hooks/hooks.json")" in *fila-testes*) ruim 'hooks.json ainda chama fila-testes.sh' ;; *) ok 'hooks.json sem fila-testes.sh' ;; esac
sobra=$(grep -rlE 'fila-teste\.sh|gs-teste\.sh|e-teste\.sh|limites\.sh|contas\.sh|vaga-agente\.sh|painel\.sh|orca-ram\.sh' "$raiz/hooks" "$raiz/skills" "$raiz/instalar.sh" --include='*.sh' --include='*.json' --include='*.lista' 2>/dev/null)
igual 'nenhum script ou hook cita script removido' '' "$sobra"

h="$tmp/h3"; mkdir -p "$h/.cache/medidores" "$h/.agents"
for f in fila-teste.sh limites.sh contas.sh vaga-agente.sh orca-ram.sh painel.sh medidores/claude.sh; do echo velho > "$h/.cache/$f"; done
echo meu > "$h/.cache/meu-script.sh"; echo meu > "$h/.cache/medidores/meu.sh"
saida=$(echo '{"source":"startup"}' | HOME="$h" CLAUDE_PLUGIN_ROOT="$raiz" bash "$raiz/hooks/instala-scripts.sh"); rc=$?
igual 'instala-scripts: sai 0 sem agent-pool' 0 $rc
contem 'sem agent-pool: avisa em português' 'o agent-pool não está instalado' "$saida"
contem 'sem agent-pool: diz o que fazer' 'instale o plugin agent-pool no Orca' "$saida"
contem 'sem agent-pool: aviso no systemMessage' '{"systemMessage":"fluxo-orca:' "$saida"
apagou=""; for f in fila-teste.sh limites.sh contas.sh vaga-agente.sh orca-ram.sh painel.sh medidores/claude.sh; do [ -e "$h/.cache/$f" ] && apagou="$apagou $f"; done
igual 'instalador apaga os scripts da lista dos removidos' '' "$apagou"
existe 'instalador preserva arquivo que não é dele' "$h/.cache/meu-script.sh"
existe 'instalador preserva arquivo alheio em medidores/' "$h/.cache/medidores/meu.sh"
igual 'resume: sem aviso repetido' '' "$(echo '{"source":"resume"}' | HOME="$h" CLAUDE_PLUGIN_ROOT="$raiz" bash "$raiz/hooks/instala-scripts.sh")"
igual 'compact: sem aviso repetido' '' "$(echo '{"source":"compact"}' | HOME="$h" CLAUDE_PLUGIN_ROOT="$raiz" bash "$raiz/hooks/instala-scripts.sh")"
mkdir -p "$h/.agents/bin"; echo '#!/bin/sh' > "$h/.agents/bin/agent-pool"
igual 'com agent-pool: sem aviso' '' "$(echo '{"source":"startup"}' | HOME="$h" CLAUDE_PLUGIN_ROOT="$raiz" bash "$raiz/hooks/instala-scripts.sh")"
rm "$h/.agents/bin/agent-pool"; echo '@echo off' > "$h/.agents/bin/agent-pool.cmd"
igual 'com agent-pool.cmd: sem aviso' '' "$(echo '{"source":"startup"}' | HOME="$h" CLAUDE_PLUGIN_ROOT="$raiz" bash "$raiz/hooks/instala-scripts.sh")"
rm "$h/.agents/bin/agent-pool.cmd"
contem 'sem entrada (stdin vazio): avisa' 'não está instalado' "$(HOME="$h" CLAUDE_PLUGIN_ROOT="$raiz" bash "$raiz/hooks/instala-scripts.sh" < /dev/null)"

[ "$falhas" = 0 ] && echo "tudo ok" || { echo "$falhas falha(s)"; exit 1; }

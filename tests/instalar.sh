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
existe 'codex: fila de testes em ~/.cache' "$HOME/.cache/fila-teste.sh"
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
CONTAS_CATALOGO="$tmp/catalogo.conf" bash "$raiz/skills/limites-cota/instala-agente.sh" semskills --aplicar >/dev/null
regras=$(cat "$HOME/.semskills/REGRAS.md")
contem 'sem skills: índice nas regras' '~/.agents/skills/delegacao/SKILL.md' "$regras"
contem 'sem skills: regras do coordenador' 'Como coordenador' "$regras"
existe 'sem skills: cópias para o índice apontar' "$HOME/.agents/skills/delegacao/SKILL.md"

[ "$falhas" = 0 ] && echo "tudo ok" || { echo "$falhas falha(s)"; exit 1; }

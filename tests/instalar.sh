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

# Versão: sessão antiga (resume/compact) não rebaixa scripts nem skills já instalados por versão mais nova.
falso_plugin() { # versao: raiz com um script, um medidor e uma skill cujo conteúdo é a versão
    local r="$tmp/plugin-$1"
    mkdir -p "$r/.claude-plugin" "$r/hooks" "$r/skills/limites-cota/medidores" "$r/skills/s"
    printf '{\n  "name": "x",\n  "version": "%s"\n}\n' "$1" > "$r/.claude-plugin/plugin.json"
    echo x.sh > "$r/hooks/scripts.lista"
    echo "$1" > "$r/x.sh"; echo "$1" > "$r/skills/limites-cota/medidores/m.sh"; echo "$1" > "$r/skills/s/SKILL.md"
    echo "$r"
}
. "$raiz/hooks/lib-instala.sh"
novo=$(falso_plugin 2.13.0); velho=$(falso_plugin 2.12.1); antigo=$(falso_plugin 2.9.0)
c="$tmp/vcache"; s="$tmp/vskills"
copia_scripts "$novo" "$c"; copia_skills "$novo" "$s"
igual 'versão: instalação grava o marcador' 2.13.0 "$(cat "$c/fluxo-orca.versao")"
copia_scripts "$velho" "$c"; copia_skills "$velho" "$s"
igual 'versão: 2.12.1 não rebaixa o script' 2.13.0 "$(cat "$c/x.sh")"
igual 'versão: 2.12.1 não rebaixa o medidor' 2.13.0 "$(cat "$c/medidores/m.sh")"
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

[ "$falhas" = 0 ] && echo "tudo ok" || { echo "$falhas falha(s)"; exit 1; }

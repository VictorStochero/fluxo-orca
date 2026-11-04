#!/usr/bin/env bash
# Prova das skills dos plugins da lista (hooks/skills-de-plugins.lista) copiadas pelo SessionStart e pelo instala-agente.sh
# para os CLIs externos. HOME isolado, installed_plugins.json e plugins falsos: não toca em ~/.agents, ~/.gemini nem ~/.claude.
raiz=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
falhas=0
ok() { echo "ok   $1"; }
ruim() { echo "FALHA $1"; falhas=$((falhas + 1)); }
igual() { if [ "$2" = "$3" ]; then ok "$1"; else ruim "$1: esperado [$2], veio [$3]"; fi; }
contem() { case "$3" in *"$2"*) ok "$1" ;; *) ruim "$1: faltou [$2] em [$3]" ;; esac; }
nao_contem() { case "$3" in *"$2"*) ruim "$1: sobrou [$2] em [$3]" ;; *) ok "$1" ;; esac; }
existe() { if [ -e "$2" ]; then ok "$1"; else ruim "$1: falta $2"; fi; }
nao_existe() { if [ ! -e "$2" ]; then ok "$1"; else ruim "$1: sobrou $2"; fi; }

export HOME="$tmp/home"
export CLAUDE_CONFIG_DIR="$HOME/.claude"
mkdir -p "$HOME/.cache" "$HOME/.claude/plugins" "$tmp/bin"
# Codex e agy "instalados" só no PATH deste teste.
printf '#!/bin/sh\n' > "$tmp/bin/codex"; cp "$tmp/bin/codex" "$tmp/bin/agy"; chmod +x "$tmp/bin/codex" "$tmp/bin/agy"
export PATH="$tmp/bin:$PATH"

lista="$raiz/hooks/skills-de-plugins.lista"
existe 'lista de plugins versionada' "$lista"
plugins=$(grep -vE '^(#|$)' "$lista" 2>/dev/null | tr -d '\r')
igual 'lista: os três plugins' 'auditoria-pre-subida ponytail laravel-worktree' "$(echo $plugins)"

falso_plugin() { # nome versao skill...: plugin em $tmp/cache/<nome>/<versao>, cada skill com um SKILL.md que carrega a versão
    local n=$1 v=$2 r s; shift 2; r="$tmp/cache/$n/$v"
    mkdir -p "$r/.claude-plugin"
    printf '{\n  "name": "%s",\n  "version": "%s"\n}\n' "$n" "$v" > "$r/.claude-plugin/plugin.json"
    for s in "$@"; do mkdir -p "$r/skills/$s"; echo "$n $v" > "$r/skills/$s/SKILL.md"; done
    echo "$r"
}
instalados() { # nome=caminho...: grava o installed_plugins.json falso (caminho no estilo do Windows quando há cygpath)
    local par n c json="" sep=""
    for par in "$@"; do
        n=${par%%=*}; c=${par#*=}
        command -v cygpath >/dev/null 2>&1 && c=$(cygpath -w "$c")
        c=${c//\\/\\\\}
        json="$json$sep\"$n@mkt\": [{\"scope\": \"user\", \"installPath\": \"$c\", \"version\": \"x\"}]"; sep=", "
    done
    printf '{"version": 2, "plugins": {%s}}\n' "$json" > "$HOME/.claude/plugins/installed_plugins.json"
}
sessao() { echo '{"source":"startup"}' | CLAUDE_PLUGIN_ROOT="$raiz" bash "$raiz/hooks/instala-scripts.sh" 2>&1; }
sem_cp() { # mensagem [diff]: roda a sessão com cp (e diff, se pedido) que denunciam qualquer chamada
    local f
    for f in cp diff; do
        printf '#!/bin/sh\necho "$@" >> "%s/%s.log"\nexec /usr/bin/%s "$@"\n' "$tmp" "$f" "$f" > "$tmp/bin/$f"
        chmod +x "$tmp/bin/$f"; : > "$tmp/$f.log"
    done
    sessao > /dev/null
    igual "$1" '' "$(cat "$tmp/cp.log")$([ "${2:-}" = diff ] && cat "$tmp/diff.log")"
    rm "$tmp/bin/cp" "$tmp/bin/diff"
}
# O reparo de cópia editada à mão só roda quando a assinatura do destino muda: o teste a invalida.
invalida() { rm -f "$HOME/.agents/skills/.fluxo-orca.assinatura" "$HOME/.gemini/config/skills/.fluxo-orca.assinatura"; }

aud=$(falso_plugin auditoria-pre-subida 1.3.0 auditar)
pon=$(falso_plugin ponytail 5.3.2 ponytail ponytail-audit ponytail-review)
lw=$(falso_plugin laravel-worktree 0.4.0 laravel-worktree)
# Plugin da lista sem instalação (laravel-worktree fora do installed_plugins.json) é pulado.
instalados "auditoria-pre-subida=$aud" "ponytail=$pon"
saida=$(sessao)
agentes="$HOME/.agents/skills"; agy="$HOME/.gemini/config/skills"
existe 'codex: skill do auditoria-pre-subida' "$agentes/auditar/SKILL.md"
existe 'codex: skills do ponytail' "$agentes/ponytail-review/SKILL.md"
existe 'agy: skill do auditoria-pre-subida' "$agy/auditar/SKILL.md"
existe 'agy: skills do ponytail' "$agy/ponytail-audit/SKILL.md"
existe 'agy: skills do próprio fluxo-orca' "$agy/delegacao/SKILL.md"
existe 'codex: skills do próprio fluxo-orca' "$agentes/delegacao/SKILL.md"
nao_existe 'plugin ausente é pulado (codex)' "$agentes/laravel-worktree"
nao_existe 'plugin ausente é pulado (agy)' "$agy/laravel-worktree"
nao_contem 'plugin ausente não avisa' 'laravel-worktree' "$saida"

# Instalou depois: entra na sessão seguinte.
instalados "auditoria-pre-subida=$aud" "ponytail=$pon" "laravel-worktree=$lw"
sessao > /dev/null
existe 'plugin instalado depois entra (codex)' "$agentes/laravel-worktree/SKILL.md"
existe 'plugin instalado depois entra (agy)' "$agy/laravel-worktree/SKILL.md"

# Segunda execução: nada copiado.
sem_cp 'segunda sessão não roda cp nem diff' diff
# Coordenador sem CLAUDE_CONFIG_DIR e worker com ela apontando para a mesma pasta: mesma assinatura.
CLAUDE_CONFIG_DIR= sem_cp 'sessão sem CLAUDE_CONFIG_DIR depois de uma com ela não roda cp nem diff' diff

# Pasta ou link alheio com o mesmo nome (fora do marcador) não é tocado.
mar=.fluxo-orca.plugin-auditoria-pre-subida
invalida
rm -rf "$agentes/auditar" "$agy/auditar" "$agentes/$mar" "$agy/$mar"
mkdir -p "$agentes/auditar"; echo meu > "$agentes/auditar/SKILL.md"; ln -s "$tmp/cache" "$agy/auditar"; link=0; [ -L "$agy/auditar" ] && link=1
saida=$(sessao)
igual 'pasta alheia não é sobrescrita' meu "$(cat "$agentes/auditar/SKILL.md")"
contem 'pasta alheia avisa' 'auditar não copiada' "$saida"
if [ "$link" = 1 ]; then [ -L "$agy/auditar" ] && ok 'link alheio intocado' || ruim 'link alheio foi substituído'; else echo 'pulado: link alheio (sem symlink neste Windows)'; fi
existe 'o resto do plugin segue copiado' "$agentes/ponytail-review/SKILL.md"
rm -rf "$agentes/auditar" "$agy/auditar"
invalida
sessao > /dev/null
igual 'pasta removida volta na sessão seguinte' 'auditoria-pre-subida 1.3.0' "$(cat "$agentes/auditar/SKILL.md")"

# Cópia nossa alterada à mão: mesma assinatura não a refaz; installed_plugins.json alterado refaz.
echo editado > "$agy/ponytail-review/SKILL.md"
sessao > /dev/null
igual 'mesma assinatura: cópia alterada fica' editado "$(cat "$agy/ponytail-review/SKILL.md")"
echo ' ' >> "$HOME/.claude/plugins/installed_plugins.json"
sessao > /dev/null
igual 'installed_plugins.json alterado recopia' 'ponytail 5.3.2' "$(cat "$agy/ponytail-review/SKILL.md")"

# Versão nova atualiza; versão mais velha não rebaixa.
pon2=$(falso_plugin ponytail 5.4.0 ponytail ponytail-audit ponytail-review)
instalados "auditoria-pre-subida=$aud" "ponytail=$pon2" "laravel-worktree=$lw"
sessao > /dev/null
igual 'versão nova atualiza (codex)' 'ponytail 5.4.0' "$(cat "$agentes/ponytail/SKILL.md")"
igual 'versão nova atualiza (agy)' 'ponytail 5.4.0' "$(cat "$agy/ponytail-review/SKILL.md")"
pon1=$(falso_plugin ponytail 5.2.0 ponytail ponytail-audit ponytail-review)
instalados "auditoria-pre-subida=$aud" "ponytail=$pon1" "laravel-worktree=$lw"
saida=$(sessao)
igual 'versão mais velha não rebaixa' 'ponytail 5.4.0' "$(cat "$agentes/ponytail/SKILL.md")"
contem 'versão mais velha avisa' 'mais nova que 5.2.0' "$saida"
igual 'versão mais velha não rebaixa (agy)' 'ponytail 5.4.0' "$(cat "$agy/ponytail/SKILL.md")"

# Sem Codex nem agy: nada é gravado.
h2="$tmp/h2"; mkdir -p "$h2/.claude/plugins"; cp "$HOME/.claude/plugins/installed_plugins.json" "$h2/.claude/plugins/"
echo '{"source":"startup"}' | HOME="$h2" CLAUDE_CONFIG_DIR="$h2/.claude" PATH=/usr/bin:/bin CLAUDE_PLUGIN_ROOT="$raiz" bash "$raiz/hooks/instala-scripts.sh" >/dev/null 2>&1
nao_existe 'sem Codex nem agy: sem skills' "$h2/.agents"

# instala-agente.sh --aplicar dá o mesmo resultado do hook.
instalados "auditoria-pre-subida=$aud" "ponytail=$pon2" "laravel-worktree=$lw"
rm -rf "$HOME/.agents" "$HOME/.gemini"
saida=$(bash "$raiz/skills/limites-cota/instala-agente.sh" codex)
contem 'instala-agente: simulação anuncia as skills' '[instalaria]   skills em' "$saida"
nao_existe 'instala-agente: simulação não grava' "$HOME/.agents/skills"
bash "$raiz/skills/limites-cota/instala-agente.sh" codex --aplicar > /dev/null
existe 'instala-agente codex: skill de plugin' "$agentes/ponytail-review/SKILL.md"
bash "$raiz/skills/limites-cota/instala-agente.sh" antigravity --aplicar > /dev/null
existe 'instala-agente antigravity: skill de plugin' "$agy/laravel-worktree/SKILL.md"
saida=$(bash "$raiz/skills/limites-cota/instala-agente.sh" antigravity --aplicar)
nao_contem 'instala-agente: segunda execução não instala' '[instalado]' "$saida"
nao_contem 'instala-agente: segunda execução não planeja' '[instalaria]' "$saida"
sem_cp 'sessão depois do instala-agente não copia nada'

# Sessão interrompida no meio da cópia (cp falso: copia as duas primeiras skills do plugin e mata o hook na 3ª): a seguinte completa sem aviso.
lw2=$(falso_plugin laravel-worktree 0.5.0 laravel-worktree lw-b lw-c)
instalados "auditoria-pre-subida=$aud" "ponytail=$pon2" "laravel-worktree=$lw2"
echo 0 > "$tmp/cp.n"
printf '#!/bin/sh\ncase "$*" in *laravel-worktree*) n=$(cat "%s/cp.n"); [ "$n" -ge 2 ] && kill -9 $PPID; echo $((n + 1)) > "%s/cp.n" ;; esac\nexec /usr/bin/cp "$@"\n' "$tmp" "$tmp" > "$tmp/bin/cp"
chmod +x "$tmp/bin/cp"
sessao > /dev/null
rm "$tmp/bin/cp"; invalida
saida=$(sessao)
nao_contem 'sessão interrompida: a seguinte não avisa' 'não é cópia' "$saida"
existe 'sessão interrompida: a seguinte completa (codex)' "$agentes/lw-c/SKILL.md"
existe 'sessão interrompida: a seguinte completa (agy)' "$agy/lw-c/SKILL.md"

# Skill que sai do plugin: a pasta nossa some nos dois destinos.
pon3=$(falso_plugin ponytail 5.5.0 ponytail ponytail-review)
instalados "auditoria-pre-subida=$aud" "ponytail=$pon3" "laravel-worktree=$lw2"
sessao > /dev/null
nao_existe 'skill removida do plugin some (codex)' "$agentes/ponytail-audit"
nao_existe 'skill removida do plugin some (agy)' "$agy/ponytail-audit"
existe 'as demais do plugin ficam' "$agy/ponytail-review/SKILL.md"
nao_contem 'marcador sem a skill removida' 'ponytail-audit' "$(cat "$agy/.fluxo-orca.plugin-ponytail")"

[ "$falhas" = 0 ] && echo "tudo ok" || { echo "$falhas falha(s)"; exit 1; }

#!/bin/bash
# Instalação compartilhada: hooks/instala-scripts.sh (SessionStart do Claude Code), instalar.sh e skills/limites-cota/instala-agente.sh.

# Sessão aberta antes da atualização roda o hook da versão antiga (resume/compact): não pode rebaixar o que a nova instalou.
versao_do_plugin() { sed -n 's/.*"version": *"\([^"]*\)".*/\1/p' "$1/.claude-plugin/plugin.json" 2>/dev/null | head -1; }
versao_permite() { # raiz-do-plugin marcador: 0 se a versão instalada não for mais nova que a do plugin
    local v i; v=$(versao_do_plugin "$1"); i=$(head -1 "$2" 2>/dev/null)
    [ -z "$v" ] || [ -z "$i" ] || [ "$(printf '%s\n%s\n' "$i" "$v" | sort -V | tail -1)" = "$v" ]
}
avisa_mais_nova() { echo "fluxo-orca: $2 tem a versão $(head -1 "$2"), mais nova que $(versao_do_plugin "$1"); nada copiado (apague o marcador para forçar)" >&2; }
grava_versao() { local v; v=$(versao_do_plugin "$1"); [ -z "$v" ] || printf '%s\n' "$v" > "$2"; }

copia_scripts() { # raiz-do-plugin destino
    local s
    versao_permite "$1" "$2/fluxo-orca.versao" || { avisa_mais_nova "$1" "$2/fluxo-orca.versao"; return 0; }
    mkdir -p "$2"
    while IFS= read -r s || [ -n "$s" ]; do
        case "$s" in '' | '#'*) continue ;; esac
        cmp -s "$1/$s" "$2/$(basename "$s")" || cp "$1/$s" "$2/"
    done < "$1/hooks/scripts.lista"
    # Só os nomes da lista: o agent-pool substitui esses scripts, e nada além deles é tocado.
    while IFS= read -r s || [ -n "$s" ]; do
        case "$s" in '' | '#'*) continue ;; esac
        rm -f "$2/${s%$'\r'}"
    done < "$1/hooks/scripts.removidos"
    rmdir "$2/medidores" 2>/dev/null
    grava_atalho_raiz "$1" "$2"
    grava_versao "$1" "$2/fluxo-orca.versao"
}

# O instala-agente.sh precisa da árvore do plugin (extras, skills, hooks): ~/.cache guarda só a raiz e um atalho que a chama.
grava_atalho_raiz() { # raiz-do-plugin destino
    local raiz=$1
    command -v cygpath >/dev/null 2>&1 && raiz=$(cygpath -u "$raiz")
    [ "$(cat "$2/fluxo-orca-raiz" 2>/dev/null)" = "$raiz" ] || printf '%s\n' "$raiz" > "$2/fluxo-orca-raiz"
    cat > "$2/instala-agente.sh.novo" <<'E'
#!/bin/bash
s="$(cat "$HOME/.cache/fluxo-orca-raiz" 2>/dev/null)/skills/limites-cota/instala-agente.sh"
[ -f "$s" ] || { echo 'instala-agente: raiz do fluxo-orca desconhecida; abra o Claude Code com o plugin ou rode instalar.sh --agente <id> --aplicar no clone' >&2; exit 1; }
exec bash "$s" "$@"
E
    cmp -s "$2/instala-agente.sh.novo" "$2/instala-agente.sh" && rm "$2/instala-agente.sh.novo" || mv "$2/instala-agente.sh.novo" "$2/instala-agente.sh"
}

skills_do_catalogo() { # catalogo agente: diretório de skills do agente (coluna 9, "~" é o HOME); vazio se "-" ou ausente
    local d; d=$(awk -F'|' -v a="$2" '$1 == a {print $9; exit}' "$1" 2>/dev/null | tr -d '\r')
    case "$d" in '' | -) ;; "~/"*) printf '%s\n' "$HOME/${d#"~/"}" ;; *) printf '%s\n' "$d" ;; esac
}

copia_skills() { # raiz-do-plugin destino: o cache do plugin muda de caminho a cada versão, os CLIs externos leem uma cópia fixa
    local d n alvo
    mkdir -p "$2"
    versao_permite "$1" "$2/.fluxo-orca.versao" || { avisa_mais_nova "$1" "$2/.fluxo-orca.versao"; return 0; }
    for d in "$1"/skills/*/; do
        n=$(basename "$d"); alvo="$2/$n"
        [ ! -L "$alvo" ] && diff -rq "$d" "$alvo" >/dev/null 2>&1 && continue
        rm -rf "$alvo"; cp -r "$d" "$alvo"
    done
    grava_versao "$1" "$2/.fluxo-orca.versao"
}

# shortcut: lê o installPath do plugin em installed_plugins.json com sed (sem jq): vale a 1ª entrada do plugin.
raiz_do_plugin() { # nome: versão ativa do plugin; falha se não estiver instalado
    local c j p
    for c in "${CLAUDE_CONFIG_DIR:-}" "$HOME/.claude"; do
        j="$c/plugins/installed_plugins.json"
        [ -n "$c" ] && [ -f "$j" ] || continue
        p=$(tr -d '\r\n' < "$j" | sed -n "s/.*\"$1@[^\"]*\": *\[[^]}]*\"installPath\": *\"\([^\"]*\)\".*/\1/p")
        [ -n "$p" ] || continue
        p=${p//\\\\/\\}
        command -v cygpath >/dev/null 2>&1 && p=$(cygpath -u "$p")
        [ -d "$p/skills" ] && { printf '%s' "$p"; return 0; }
    done
    return 1
}

# Marcador por plugin (.fluxo-orca.plugin-<nome>): 1ª linha a versão copiada, depois as skills que a cópia criou.
# Pasta sem nome no marcador, ou link, não é nossa: avisa e não toca.
copia_skills_plugins() { # raiz-do-plugin destino [--dry]: --dry só diz, em PLUGINS_MUDOU, se copiaria
    local lista="$1/hooks/skills-de-plugins.lista" p r d n alvo marc donas conteudo
    PLUGINS_MUDOU=0
    [ -f "$lista" ] || return 0
    while IFS= read -r p || [ -n "$p" ]; do
        p=${p%$'\r'}; case "$p" in '' | '#'*) continue ;; esac
        r=$(raiz_do_plugin "$p") || continue
        marc="$2/.fluxo-orca.plugin-$p"
        versao_permite "$r" "$marc" || { avisa_mais_nova "$r" "$marc"; continue; }
        donas=$'\n'$(tail -n +2 "$marc" 2>/dev/null)$'\n'; conteudo=$(versao_do_plugin "$r")
        for d in "$r"/skills/*/; do
            [ -f "$d/SKILL.md" ] || continue
            n=$(basename "$d"); alvo="$2/$n"
            if [ -e "$alvo" ] || [ -L "$alvo" ]; then
                if [ -L "$alvo" ] || [[ "$donas" != *$'\n'"$n"$'\n'* ]]; then
                    echo "fluxo-orca: $alvo não é cópia do plugin $p; skill $n não copiada" >&2; continue
                fi
                diff -rq "$d" "$alvo" >/dev/null 2>&1 || { PLUGINS_MUDOU=1; [ "${3:-}" = --dry ] || { rm -rf "$alvo"; cp -r "$d" "$alvo"; }; }
            else
                PLUGINS_MUDOU=1
                [ "${3:-}" = --dry ] || { mkdir -p "$2"; cp -r "$d" "$alvo"; }
            fi
            conteudo=$conteudo$'\n'$n
        done
        [[ "$conteudo" == *$'\n'* ]] || continue
        [ "$(cat "$marc" 2>/dev/null)" = "$conteudo" ] && continue
        PLUGINS_MUDOU=1
        [ "${3:-}" = --dry ] || printf '%s\n' "$conteudo" > "$marc"
    done < "$lista"
}

# Windows: os CLIs chamam o hook por .cmd. Tem de ser o Git\bin\bash.exe, que monta o PATH do Git;
# o usr\bin\bash.exe roda sem grep no PATH e libera tudo.
gera_cmd() { # nome.cmd script.sh [argumento]: grava em ~/.cache
    local alvo="$HOME/.cache/$1" raiz bash_win
    raiz=$(cygpath -w /); bash_win="${raiz%\\}\\bin\\bash.exe"
    printf '@echo off\r\n"%s" %s %s\r\n' "$bash_win" "$(cygpath -m "$HOME/.cache/$2")" "$3" > "$alvo.tmp"
    cmp -s "$alvo.tmp" "$alvo" && rm "$alvo.tmp" || mv "$alvo.tmp" "$alvo"
}

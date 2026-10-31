#!/bin/bash
# Instalação compartilhada: hooks/instala-scripts.sh (SessionStart do Claude Code), instalar.sh e skills/limites-cota/instala-agente.sh.

copia_scripts() { # raiz-do-plugin destino
    local s
    mkdir -p "$2/medidores"
    while IFS= read -r s || [ -n "$s" ]; do
        case "$s" in '' | '#'*) continue ;; esac
        cmp -s "$1/$s" "$2/$(basename "$s")" || cp "$1/$s" "$2/"
    done < "$1/hooks/scripts.lista"
    # O limites.sh chama os medidores por $(dirname)/medidores/.
    for s in "$1"/skills/limites-cota/medidores/*.sh; do
        cmp -s "$s" "$2/medidores/$(basename "$s")" || cp "$s" "$2/medidores/"
    done
    rm -f "$2/codex-cota.sh"
    grava_atalho_raiz "$1" "$2"
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

copia_skills() { # raiz-do-plugin destino: o cache do plugin muda de caminho a cada versão, os CLIs externos leem uma cópia fixa
    local d n alvo
    mkdir -p "$2"
    for d in "$1"/skills/*/; do
        n=$(basename "$d"); alvo="$2/$n"
        [ ! -L "$alvo" ] && diff -rq "$d" "$alvo" >/dev/null 2>&1 && continue
        rm -rf "$alvo"; cp -r "$d" "$alvo"
    done
}

# Windows: os CLIs chamam o hook por .cmd. Tem de ser o Git\bin\bash.exe, que monta o PATH do Git;
# o usr\bin\bash.exe roda sem grep no PATH e libera tudo.
gera_cmd() { # nome.cmd script.sh [argumento]: grava em ~/.cache
    local alvo="$HOME/.cache/$1" raiz bash_win
    raiz=$(cygpath -w /); bash_win="${raiz%\\}\\bin\\bash.exe"
    printf '@echo off\r\n"%s" %s %s\r\n' "$bash_win" "$(cygpath -m "$HOME/.cache/$2")" "$3" > "$alvo.tmp"
    cmp -s "$alvo.tmp" "$alvo" && rm "$alvo.tmp" || mv "$alvo.tmp" "$alvo"
}

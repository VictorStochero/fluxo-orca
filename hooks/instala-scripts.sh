#!/bin/bash
# SessionStart: mantém em ~/.cache as cópias dos scripts que skills, agentes e workers chamam por caminho fixo.
mkdir -p "$HOME/.cache"
for s in skills/fila-testes/fila-teste.sh skills/fila-testes/gs-teste.sh skills/fila-testes/e-teste.sh skills/limites-cota/limites.sh \
         skills/limites-cota/contas.sh skills/limites-cota/agentes-catalogo.conf \
         skills/limites-cota/vaga-agente.sh skills/worktree-orca/wt-setup.sh skills/worktree-orca/wt-archive.sh \
         skills/worktree-orca/wt-lib.sh skills/delegacao/orca-espera.sh skills/delegacao/orca-libera.sh skills/delegacao/orca-inicia.sh skills/delegacao/orca-tela.sh hooks/guarda-externos.sh hooks/fim-worker.sh; do
    cmp -s "$CLAUDE_PLUGIN_ROOT/$s" "$HOME/.cache/$(basename "$s")" || cp "$CLAUDE_PLUGIN_ROOT/$s" "$HOME/.cache/"
done
# O limites.sh chama os medidores por $(dirname)/medidores/.
mkdir -p "$HOME/.cache/medidores"
for s in "$CLAUDE_PLUGIN_ROOT"/skills/limites-cota/medidores/*.sh; do
    cmp -s "$s" "$HOME/.cache/medidores/$(basename "$s")" || cp "$s" "$HOME/.cache/medidores/"
done
rm -f "$HOME/.cache/codex-cota.sh"
mkdir -p "$HOME/.claude/agents"
cmp -s "$CLAUDE_PLUGIN_ROOT/extras/somente-leitura.json" "$HOME/.claude/agents/somente-leitura.json" \
    || cp "$CLAUDE_PLUGIN_ROOT/extras/somente-leitura.json" "$HOME/.claude/agents/"

# Agentes externos (Codex, agy): sem eles, nada abaixo.
command -v codex >/dev/null 2>&1 || command -v agy >/dev/null 2>&1 || exit 0

# Windows: Codex e agy chamam o hook por .cmd. Tem de ser o Git\bin\bash.exe, que monta o PATH do Git;
# o usr\bin\bash.exe roda sem grep no PATH e libera tudo.
if command -v cygpath >/dev/null 2>&1; then
    raiz=$(cygpath -w /); bash_win="${raiz%\\}\\bin\\bash.exe"
    gera_cmd() { # nome.cmd script.sh argumento
        local alvo="$HOME/.cache/$1"
        printf '@echo off\r\n"%s" %s %s\r\n' "$bash_win" "$(cygpath -m "$HOME/.cache/$2")" "$3" > "$alvo.tmp"
        cmp -s "$alvo.tmp" "$alvo" && rm "$alvo.tmp" || mv "$alvo.tmp" "$alvo"
    }
    gera_cmd guarda-externos-codex.cmd guarda-externos.sh codex
    gera_cmd guarda-externos-agy.cmd guarda-externos.sh agy
    gera_cmd fim-worker-codex.cmd fim-worker.sh codex
fi

# Cópia das skills do plugin em ~/.agents/skills, que os CLIs externos leem (o cache do plugin muda de caminho a cada versão).
mkdir -p "$HOME/.agents/skills"
for d in "$CLAUDE_PLUGIN_ROOT"/skills/*/; do
    n=$(basename "$d"); alvo="$HOME/.agents/skills/$n"
    [ ! -L "$alvo" ] && diff -rq "$d" "$alvo" >/dev/null 2>&1 && continue
    rm -rf "$alvo"; cp -r "$d" "$alvo"
done
exit 0

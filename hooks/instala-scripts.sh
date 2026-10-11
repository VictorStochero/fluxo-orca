#!/bin/bash
# SessionStart: mantém em ~/.cache as cópias dos scripts que skills, agentes e workers chamam por caminho fixo.
mkdir -p "$HOME/.cache"
for s in skills/fila-testes/gs-teste.sh skills/limites-cota/limites.sh skills/limites-cota/kimi-cota.sh \
         skills/limites-cota/codex-cota.sh skills/worktree-orca/wt-setup.sh skills/worktree-orca/wt-archive.sh \
         skills/worktree-orca/wt-lib.sh hooks/guarda-externos.sh; do
    cmp -s "$CLAUDE_PLUGIN_ROOT/$s" "$HOME/.cache/$(basename "$s")" || cp "$CLAUDE_PLUGIN_ROOT/$s" "$HOME/.cache/"
done
mkdir -p "$HOME/.claude/agents"
cmp -s "$CLAUDE_PLUGIN_ROOT/extras/somente-leitura.json" "$HOME/.claude/agents/somente-leitura.json" \
    || cp "$CLAUDE_PLUGIN_ROOT/extras/somente-leitura.json" "$HOME/.claude/agents/"

# Agentes externos (Codex, agy, Kimi): sem eles, nada abaixo.
command -v codex >/dev/null 2>&1 || command -v agy >/dev/null 2>&1 || command -v kimi >/dev/null 2>&1 || exit 0

# Windows: Codex e agy chamam o hook por .cmd. Tem de ser o Git\bin\bash.exe, que monta o PATH do Git;
# o usr\bin\bash.exe roda sem grep no PATH e libera tudo.
if command -v cygpath >/dev/null 2>&1; then
    raiz=$(cygpath -w /); bash_win="${raiz%\\}\\bin\\bash.exe"; guarda=$(cygpath -m "$HOME/.cache/guarda-externos.sh")
    for f in codex agy; do
        printf '@echo off\r\n"%s" %s %s\r\n' "$bash_win" "$guarda" "$f" > "$HOME/.cache/guarda-externos-$f.cmd.tmp"
        cmp -s "$HOME/.cache/guarda-externos-$f.cmd.tmp" "$HOME/.cache/guarda-externos-$f.cmd" \
            && rm "$HOME/.cache/guarda-externos-$f.cmd.tmp" \
            || mv "$HOME/.cache/guarda-externos-$f.cmd.tmp" "$HOME/.cache/guarda-externos-$f.cmd"
    done
fi

# Cópia das skills do plugin em ~/.agents/skills, que os CLIs externos leem (o cache do plugin muda de caminho a cada versão).
mkdir -p "$HOME/.agents/skills"
for d in "$CLAUDE_PLUGIN_ROOT"/skills/*/; do
    n=$(basename "$d"); alvo="$HOME/.agents/skills/$n"
    [ ! -L "$alvo" ] && diff -rq "$d" "$alvo" >/dev/null 2>&1 && continue
    rm -rf "$alvo"; cp -r "$d" "$alvo"
done
exit 0

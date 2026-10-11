#!/bin/bash
# PreToolUse (Edit|Write): em projeto Laravel, editar .php exige laravel-best-practices carregado e, se houver, wiki/arquitetura lido na sessão.
in=$(cat)
arquivo=$(printf '%s' "$in" | grep -oE '"file_path"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed -E 's/.*"([^"]*)"$/\1/; s/\\\\/\//g')
case "$arquivo" in *.php) ;; *) exit 0 ;; esac
transcricao=$(printf '%s' "$in" | grep -oE '"transcript_path"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed -E 's/.*"([^"]*)"$/\1/; s/\\\\/\//g')
dir=$(dirname "$arquivo")
while [ ! -d "$dir" ] && [ "$dir" != "/" ] && [ "$dir" != "." ]; do dir=$(dirname "$dir"); done
raiz=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null) || exit 0
grep -q '"laravel/framework"' "$raiz/composer.json" 2>/dev/null || exit 0
[ -f "$transcricao" ] || exit 0
faltando=""
grep -qE '"skill"[[:space:]]*:[[:space:]]*"([^":]*:)?laravel-best-practices"' "$transcricao" \
    || faltando="invocar o skill laravel-best-practices"
guia=""
for g in wiki/arquitetura docs/arquitetura doc/arquitetura wiki/architecture docs/architecture doc/architecture; do
    [ -d "$raiz/$g" ] && { guia=$g; break; }
done
if [ -n "$guia" ]; then
    padrao=$(printf '%s' "$guia" | sed 's#/#[/\\\\]+#')
    grep -qE "\"file_path\"[[:space:]]*:[[:space:]]*\"[^\"]*${padrao}[/\\\\]" "$transcricao" \
        || faltando="${faltando:+$faltando e }ler o guia de arquitetura $guia/ (índice e a página do assunto)"
fi
[ -z "$faltando" ] && exit 0
echo "Antes de editar PHP neste projeto: $faltando. Siga também o CLAUDE.md do projeto (guidelines do Laravel Boost) e os skills de .claude/skills e .ai/skills que tocarem a tarefa." >&2
exit 2

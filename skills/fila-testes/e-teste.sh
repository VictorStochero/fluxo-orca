#!/bin/bash
# Detector de comando de teste fora da fila. Lê o JSON do hook no stdin.
# exit 0 = é comando de teste sem a fila; exit 1 = não é (ou não há comando).
# O comando vem em "command" (string, ou lista no Codex) ou "cmd"; usado por fila-testes.sh e guarda-externos.sh.
in=$(cat)
cmd=$(printf '%s' "$in" | grep -oE '"(command|cmd)"[[:space:]]*:[[:space:]]*("([^"\\]|\\.)*"|\[[^]]*\])' | head -1)
[ -z "$cmd" ] && exit 1
# Livres saem da análise por trecho (entre ; & |), não o comando inteiro: `npm ci && npm test` segue bloqueado.
# Texto de mensagem não é comando: o valor de -m/--message (git commit) e de --body/--subject/--title (gh, orca) sai antes de casar.
v='(\\"[^"]*\\"|'"'[^']*'"'|[^[:space:];&|"]+)'
cmd=$(printf '%s' "$cmd" | sed -E \
    -e 's/\\[nr]/;/g' \
    -e "/git[[:space:]]+commit/ s/(^|[[:space:]])(-a?m|--message)([[:space:]]+|=)$v//g" \
    -e "s/--(body|subject|title)([[:space:]]+|=)$v//g" \
    -e 's/[^;&|]*(--list-tests|--collect-only|--listTests|vitest[[:space:]]+list)[^;&|]*//g' \
    -e 's/(pip|pip3|uv|poetry|pipenv|npm|pnpm|yarn|bun|composer)[[:space:]]+(install|add|i|ci|sync|remove|uninstall|require)[^;&|]*//g')
s='(^|["[:space:];&|(/])'
cmd=$(printf '%s\n' "$cmd" | awk '
    function primeiro(s, i,c,q,t) {
        sub(/^[[:space:]]+/, "", s); t=""; q=""
        for (i=1; i<=length(s); i++) {
            c=substr(s,i,1)
            if (c == "\"" || c == sprintf("%c",39)) {
                if (q == c) { q=""; continue }
                if (q == "") { q=c; continue }
            }
            if (q == "" && c ~ /[[:space:]]/) break
            t=t c
        }
        resto=substr(s,i); sub(/^[[:space:]]+/, "", resto)
        return t
    }
    function nome(t, i,inicio,c) {
        inicio=1
        for (i=1; i<=length(t); i++) { c=substr(t,i,1); if (c == "/" || c == sprintf("%c",92)) inicio=i+1 }
        return tolower(substr(t,inicio))
    }
    function capa(s, n,t,b,p,a,q,j) {
        for (n=0; n<8; n++) {
            sub(/^[[:space:]]+/, "", s); sub(/[[:space:]]+$/, "", s)
            q=substr(s,2,1)
            if (substr(s,1,1) == "@" && (q == "\"" || q == sprintf("%c",39))) {
                j=index(substr(s,3),q "@")
                if (j) { s=substr(s,3,j-1) substr(s,j+4); continue }
            }
            t=primeiro(s); p=resto; b=nome(t)
            if (t == "&") { s=p; continue }
            if (t ~ /^[A-Za-z_][A-Za-z0-9_]*=/ && t !~ /\$\(/ && index(t,sprintf("%c",96)) == 0) { s=p; continue }
            if (b !~ /^(bash|sh|powershell|pwsh)([.]exe)?$/) break
            a=tolower(primeiro(p)); p=resto
            if (a !~ /^(-lc|-c|-command)$/) break
            if (substr(p,1,1) == "@") { s=p; continue }
            q=substr(p,1,1)
            if ((q == "\"" || q == sprintf("%c",39)) && substr(p,length(p),1) == q) { s=substr(p,2,length(p)-2); continue }
            break
        }
        return s
    }
    function chama_fila(s, original,t,b) {
        original=s; s=capa(s)
        if (s != original && s ~ /[;&|]/) return 0
        t=primeiro(s); b=nome(t)
        if (b ~ /^(bash|sh)([.]exe)?$/) b=nome(primeiro(resto))
        return b ~ /^(fila-teste|gs-teste)[.]sh$/
    }
    function emite() {
        busca = (!substituicao && trecho ~ /^[[:space:]]*(grep|egrep|fgrep|rg|git[[:space:]]+grep|findstr|Select-String)([[:space:]]|$)/)
        fila = chama_fila(trecho)
        if (!busca && !fila) print trecho
        trecho=""; substituicao=0
    }
    {
        sub(/^"(command|cmd)"[[:space:]]*:[[:space:]]*\[[[:space:]]*"(bash|sh|powershell([.]exe)?|pwsh([.]exe)?)"[[:space:]]*,[[:space:]]*"-(lc|c|Command)"[[:space:]]*,[[:space:]]*"/, "")
        sub(/"[[:space:]]*\]$/, "")
        sub(/^"(command|cmd)"[[:space:]]*:[[:space:]]*"/, "")
        sub(/"$/, ""); gsub(/\\"/, "\"")
        $0=capa($0)
        for (i=1; i<=length($0); i++) {
            c=substr($0,i,1)
            if (c == "\\" && substr($0,i+1,1) == "\\") i++
            if (escape) { trecho=trecho c; escape=0; continue }
            if (c == "\\" && aspas != sprintf("%c",39)) { trecho=trecho c; escape=1; continue }
            if (aspas != sprintf("%c",39) && ((c == "$" && substr($0,i+1,1) == "(") || c == sprintf("%c",96))) substituicao=1
            if (c == "\"" || c == sprintf("%c",39)) {
                if (aspas == c) aspas=""; else if (aspas == "") aspas=c
            }
            if (aspas == "" && c ~ /[;&|]/) emite(); else trecho=trecho c
        }
        emite()
    }')
e='([[:space:]"\\]|$)'
if printf '%s' "$cmd" | grep -qE "artisan[[:space:]]+test|vendor/bin/(pest|phpunit)|pestphp/pest/bin/pest|sail[[:space:]]+(test|pest)$e|${s}pytest$e|-m[[:space:]]+(pytest|unittest)|manage\.py[[:space:]]+test|${s}(vitest|jest)$e|${s}(npm|pnpm|yarn|bun)[[:space:]]+(run[[:space:]]+)?test(:[[:alnum:]:_-]+)?$e|${s}composer[[:space:]]+(run(-script)?[[:space:]]+)?test$e|${s}(cargo|go)[[:space:]]+test$e"; then
    exit 0
fi
# A opção de teste precisa estar no mesmo trecho da operação de banco.
while IFS= read -r trecho; do
    if printf '%s' "$trecho" | grep -qE "artisan[[:space:]]+(migrate(:[[:alnum:]_-]+)?|db:(wipe|seed))$e" \
        && printf '%s' "$trecho" | grep -qE -- "--env(=|[[:space:]]+)[\"']?testing([\"'[:space:]]|$)|--database(=|[[:space:]]+)[\"']?([[:alnum:]_.-]*[_.-])?test(ing)?([_.-][[:alnum:]_.-]*)?([\"'[:space:]]|$)"; then
        exit 0
    fi
    if printf '%s' "$trecho" | grep -qE "manage\.py[[:space:]]+(migrate|flush)$e" \
        && printf '%s' "$trecho" | grep -qE -- "--settings(=|[[:space:]]+)[\"']?[[:alnum:]_.]*test[[:alnum:]_.]*([\"'[:space:]]|$)"; then
        exit 0
    fi
done < <(printf '%s\n' "$cmd" | sed 's/\\"/"/g' | tr ';&|' '\n')
exit 1

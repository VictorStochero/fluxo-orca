#!/bin/bash
# Prova do vigia de saúde e da liberação com o contrato V3 do Orca.
raiz=$(cd "$(dirname "$0")/.." && pwd)
falhas=0
# macOS não tem timeout.
for py in python3 python; do "$py" -c '' 2>/dev/null && break; done
limite() { if command -v timeout >/dev/null 2>&1; then timeout "$@"; else perl -e 'alarm shift; exec @ARGV' "$@"; fi; }
# Relógio controlado: sleep avança o prazo sem esperar um minuto real.
relogio() {
    local data; data=$(command -v date)
    echo 0 > "$h/relogio"
    cat > "$h/bin/date" <<EOF
#!/bin/bash
if [ "\$*" = +%s ]; then echo \$(( \$("$data" +%s) + \$(cat "$h/relogio") )); else "$data" "\$@"; fi
EOF
    cat > "$h/bin/sleep" <<EOF
#!/bin/bash
echo \$(( \$(cat "$h/relogio") + \$1 )) > "$h/relogio"
EOF
    chmod +x "$h/bin/date" "$h/bin/sleep"
}
# Carência e limpeza: worker working sem progresso alerta uma vez; a rodada seguinte não repete; estado de dispatch encerrado é apagado.
h=$(mktemp -d); mkdir -p "$h/bin" "$h/.cache/orca-saude" "$h/wt"
git -C "$h/wt" init -q && git -C "$h/wt" -c user.name=t -c user.email=t@t commit -q --allow-empty -m t
wt="$h/wt"; command -v cygpath >/dev/null 2>&1 && wt=$(cygpath -m "$h/wt")
cat > "$h/bin/orca" <<EOF
#!/bin/bash
case "\$*" in
    *worker-list*--full*) echo '{"ok":true,"result":{"workers":[{"dispatchId":"ctx_p","dispatchStatus":"dispatched","projection":{"stage":{"worker":"ready","activity":"working"},"liveness":{"verdict":"live"},"workspace":{"id":"r::$wt"}}},{"dispatchId":"ctx_fim","dispatchStatus":"completed","projection":{}}]}}' ;;
    *worker-read*) echo '{"ok":true,"result":{"transcript":{"messages":[{"timestamp":1}],"limited":false}}}' ;;
    *check*) echo check >> "$h/checks"; sleep 60; echo '{"ok":true,"result":{}}' ;;
esac
EOF
chmod +x "$h/bin/orca"
relogio
# Windows: o Python do script chama o orca pelo PATHEXT; o .cmd repassa ao stub bash.
command -v cygpath >/dev/null 2>&1 && printf '@"%s" "%s" %%*\r\n' "$(cygpath -w "$(command -v bash)")" "$(cygpath -m "$h/bin/orca")" > "$h/bin/orca.cmd"
e="$h/.cache/orca-saude"
printf '{"progresso": %s, "timestamp": 1, "commit": "%s", "atividade": "working"}' "$(( $(date +%s) - 600 ))" "$(git -C "$h/wt" rev-parse HEAD)" > "$e/.estado-ctx_p.json"
echo '{}' > "$e/.estado-ctx_fim.json"
um=$(HOME="$h" PATH="$h/bin:$PATH" ORCA_ESPERA_PARADO_MIN=1 bash "$raiz/skills/delegacao/orca-espera.sh" --max-min 1 2>&1)
# Rearme logo depois do alerta: as primeiras rodadas não podem repetir (carência de 1 min).
dois=$(HOME="$h" PATH="$h/bin:$PATH" ORCA_ESPERA_PARADO_MIN=1 limite 10 bash "$raiz/skills/delegacao/orca-espera.sh" --max-min 1 2>&1)
if printf '%s' "$um" | grep -q '!! ctx_p parado' && ! printf '%s' "$dois" | grep -q '!!'; then echo "ok   carência: alerta uma vez, sem laço"
else echo "FALHA carência"; printf '1:\n%s\n2:\n%s\n' "$um" "$dois" | sed 's/^/     /'; falhas=$((falhas + 1)); fi
if [ ! -e "$e/.estado-ctx_fim.json" ]; then echo "ok   estado de dispatch encerrado apagado"; else echo "FALHA limpeza do estado"; falhas=$((falhas + 1)); fi
rm -rf "$h"

# Saída enxuta: worker com stub configurável (atividade).
cena() { # atividade
    h=$(mktemp -d); mkdir -p "$h/bin" "$h/wt"
    git -C "$h/wt" init -q && git -C "$h/wt" -c user.name=t -c user.email=t@t commit -q --allow-empty -m t
    wt="$h/wt"; command -v cygpath >/dev/null 2>&1 && wt=$(cygpath -m "$h/wt")
    cat > "$h/bin/orca" <<EOF2
#!/bin/bash
case "\$*" in
    *worker-list*--full*) echo '{"ok":true,"result":{"workers":[{"dispatchId":"ctx_k","dispatchStatus":"dispatched","agentTerminalHandle":"term_k","projection":{"stage":{"worker":"ready","activity":"$1"},"liveness":{"verdict":"live"},"workspace":{"id":"r::$wt"}}}]}}' ;;
    *worker-read*) echo '{"ok":true,"result":{"transcript":{"messages":[{"timestamp":1}],"limited":false}}}' ;;
    *terminal*read*) cat "$h/tela.json" 2>/dev/null || echo '{"ok":true,"result":{"terminal":{"tail":["pronto"]}}}' ;;
    *check*) echo check >> "$h/checks"; sleep 60; echo '{"ok":true,"result":{}}' ;;
esac
EOF2
    chmod +x "$h/bin/orca"
    relogio
    command -v cygpath >/dev/null 2>&1 && printf '@"%s" "%s" %%*\r\n' "$(cygpath -w "$(command -v bash)")" "$(cygpath -m "$h/bin/orca")" > "$h/bin/orca.cmd"
}
roda() { HOME="$h" PATH="$h/bin:$PATH" ORCA_ESPERA_PARADO_MIN=10 bash "$raiz/skills/delegacao/orca-espera.sh" --max-min 1 2>&1; }
cena working
um=$(roda)
git -C "$h/wt" -c user.name=t -c user.email=t@t commit -q --allow-empty -m novo
dois=$(roda)
if [ "$(printf '%s\n' "$um" | wc -l)" = 2 ] && [ "$(printf '%s\n' "$dois" | wc -l)" = 2 ]; then echo "ok   sem novidade imprime somente resumo e rearme"
else echo "FALHA saída sem novidade"; printf '%s\n' "$um" "$dois"; falhas=$((falhas + 1)); fi
if printf '%s' "$um" | grep -q '^Sem novidade em 1 min; ctx_k último commit [0-9a-f]* (.*)\.$' && printf '%s' "$um" | grep -q 'Rearmar'; then echo "ok   resumo no fim"
else echo "FALHA resumo"; printf '%s\n' "$um" | sed 's/^/     /'; falhas=$((falhas + 1)); fi
if [ ! -e "$h/checks" ]; then echo "ok   vigia não consome correspondência"; else echo "FALHA vigia chamou check"; falhas=$((falhas + 1)); fi
rm -rf "$h"
for atividade in done waiting blocked; do
    cena "$atividade"
    out=$(roda)
    if ! printf '%s' "$out" | grep -q '!!'; then echo "ok   $atividade fica a cargo do wake do Orca"
    else echo "FALHA $atividade"; printf '%s\n' "$out"; falhas=$((falhas + 1)); fi
    rm -rf "$h"
done

# Limite de cota: estourado na tela do worker e perto de estourar pelo limites.sh --alerta.
cena working
echo '{"ok":true,"result":{"terminal":{"tail":["Error: 403 You'"'"'ve reached your 5-hour usage limit.","> "]}}}' > "$h/tela.json"
out=$(roda)
if printf '%s' "$out" | grep -q '!! ctx_k bateu limite de cota: .*5-hour usage limit'; then echo "ok   limite estourado na tela do worker avisa"
else echo "FALHA limite na tela"; printf '%s\n' "$out" | sed 's/^/     /'; falhas=$((falhas + 1)); fi
out=$(roda)
if ! printf '%s' "$out" | grep -q 'bateu limite'; then echo "ok   mesmo limite não avisa de novo"
else echo "FALHA limite repetido"; printf '%s\n' "$out" | sed 's/^/     /'; falhas=$((falhas + 1)); fi
echo '{"ok":true,"result":{"terminal":{"tail":["  5-hour limit reached ∙ resets 3pm","> "]}}}' > "$h/tela.json"
out=$(roda)
if printf '%s' "$out" | grep -q 'bateu limite de cota: 5-hour limit reached'; then echo "ok   formato 'limit reached' do Claude avisa"
else echo "FALHA limit reached"; printf '%s\n' "$out" | sed 's/^/     /'; falhas=$((falhas + 1)); fi
echo '{"ok":true,"result":{"terminal":{"tail":["Tests: 429 passed","use Illuminate\\\\Cache\\\\RateLimiter;","> "]}}}' > "$h/tela.json"
out=$(roda)
if ! printf '%s' "$out" | grep -q 'bateu limite'; then echo "ok   429 de teste e RateLimiter não são limite"
else echo "FALHA falso positivo de limite"; printf '%s\n' "$out" | sed 's/^/     /'; falhas=$((falhas + 1)); fi
rm -f "$h/tela.json"
printf '#!/bin/bash\necho "codex: 5h 92%% (zera 04:38) · semana 10%%"; exit 3\n' > "$h/limites.sh"
out=$(ORCA_LIMITES="$h/limites.sh" ORCA_ESPERA_COTA_MIN=1 roda)
if printf '%s' "$out" | grep -q '^!! cota acima de 80%: codex: 5h 92%'; then echo "ok   cota acima de 80% avisa antes de estourar"
else echo "FALHA aviso de cota"; printf '%s\n' "$out" | sed 's/^/     /'; falhas=$((falhas + 1)); fi
out=$(ORCA_LIMITES="$h/limites.sh" ORCA_ESPERA_COTA_MIN=1 roda)
if ! printf '%s' "$out" | grep -q 'cota acima'; then echo "ok   mesmo fornecedor não avisa de novo"
else echo "FALHA aviso de cota repetido"; printf '%s\n' "$out" | sed 's/^/     /'; falhas=$((falhas + 1)); fi
c=$(ls "$h"/.cache/orca-saude/.cota-avisada.*.consulta 2>/dev/null | head -1)
[ -n "$c" ] && ok_int=1 || ok_int=0
printf '#!/bin/bash\necho conta; exit 1\n' > "$h/limites.sh"
out=$(ORCA_LIMITES="$h/limites.sh" ORCA_ESPERA_COTA_MIN=10 roda)
if [ "$ok_int" = 1 ] && ! printf '%s' "$out" | grep -q 'cota acima'; then echo "ok   intervalo da consulta vale entre rearmes"
else echo "FALHA intervalo entre rearmes"; falhas=$((falhas + 1)); fi
touch -d '20 minutes ago' "$c" 2>/dev/null
out=$(ORCA_LIMITES="$h/limites.sh" ORCA_ESPERA_COTA_MIN=10 roda)
printf '#!/bin/bash\necho "codex: 5h 92%% (zera 04:38) · semana 10%%"; exit 3\n' > "$h/limites.sh"; touch -d '20 minutes ago' "$c"
out=$(ORCA_LIMITES="$h/limites.sh" ORCA_ESPERA_COTA_MIN=10 roda)
if ! printf '%s' "$out" | grep -q 'cota acima'; then echo "ok   falha do limites.sh não apaga o que já foi avisado"
else echo "FALHA falha apagou deduplicação"; printf '%s\n' "$out" | sed 's/^/     /'; falhas=$((falhas + 1)); fi
rm -rf "$h"

# orca-libera: só fecha terminal criado pelo --cria e que nenhum dispatch ativo do run usa.
libera() { # nome registrado(sim|nao) outro_ativo(sim|nao|ilegivel) fecha_esperado(sim|nao)
    local h; h=$(mktemp -d); mkdir -p "$h/bin"
    local outro='' ; [ "$3" = sim ] && outro=',{"dispatchId":"ctx_b","dispatchStatus":"dispatched","agentTerminalHandle":"term_t","projection":{}}'
    # Indentado como o worker-list real (uma chave por linha).
    printf '%s' '{"ok":true,"result":{"workers":[{"dispatchId":"ctx_a","dispatchStatus":"completed","agentTerminalHandle":"term_t","projection":{}}'"$outro"']}}' \
        | "$py" -m json.tool > "$h/lista.json"
    [ "$3" = ilegivel ] && echo '{"ok":true,"result":' > "$h/lista.json"
    # worker-show --full real: indentado, runId em dispatch e o handle do terminal em worker.
    printf '%s' '{"ok":true,"result":{"dispatch":{"id":"ctx_a","runId":"run_t","status":"completed"},"worker":{"dispatchId":"ctx_a","state":"succeeded","agentTerminalHandle":"term_t"}}}' \
        | "$py" -m json.tool > "$h/show.json"
    cat > "$h/bin/orca" <<EOF
#!/bin/bash
case "\$*" in
    *"terminal create"*) echo '{"ok":true,"result":{"terminal":{"handle":"term_t"}}}' ;;
    *worker-release*) echo '{"ok":true,"result":{"state":"retained","reason":"external_terminal"}}' ;;
    *worker-show*--full*) cat "$h/show.json" ;;
    *worker-list*--full*) cat "$h/lista.json" ;;
    *worker-show*) echo '{"ok":true,"result":{"dispatchId":"ctx_a","state":"completed","terminal":"term_t"}}' ;;
    *worker-list*) echo '{"ok":true,"result":{"workers":[{"dispatchId":"ctx_b","state":"working","terminal":"term_t"}]}}' ;;
    *"terminal close"*) echo fechou >> "$h/fechou"; echo '{"ok":true}' ;;
esac
EOF
    chmod +x "$h/bin/orca"
    [ "$2" = sim ] && HOME="$h" PATH="$h/bin:$PATH" bash "$raiz/skills/delegacao/orca-libera.sh" --cria --worktree x >/dev/null
    saida=$(HOME="$h" PATH="$h/bin:$PATH" bash "$raiz/skills/delegacao/orca-libera.sh" ctx_a 2>&1)
    fechou=nao; [ -s "$h/fechou" ] && fechou=sim
    if [ "$fechou" = "$4" ]; then echo "ok   $1"; else echo "FALHA $1 (fechou=$fechou): $saida"; falhas=$((falhas + 1)); fi
    rm -rf "$h"
}
libera "libera fecha terminal criado e ocioso" sim nao sim
libera "libera mantém terminal reaproveitado por dispatch ativo" sim sim nao
libera "libera mantém terminal não criado pelo --cria" nao nao nao
libera "libera mantém terminal quando o worker-list é ilegível" sim ilegivel nao

[ $falhas = 0 ] && echo "TUDO OK" || { echo "$falhas falha(s)"; exit 1; }

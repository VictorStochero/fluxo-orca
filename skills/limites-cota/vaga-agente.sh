#!/usr/bin/env bash
# Pool da máquina: pega <conta> <dispatch>, solta <dispatch>, livres, troca <provisório> <dispatch>. Zero = ilimitado.
# Dono provisório (prefixo res-) não é consultado no Orca: vaga morta só após POOL_RESERVA_TTL s (padrão 600).
contas=(team pessoal codex kimi agy)
v_team=1 v_pessoal=0 v_codex=1 v_kimi=1 v_agy=1
dir="$HOME/.cache/agentes"
erro() { echo "vaga-agente: $*" >&2; exit 2; }
valida_dispatch() { [[ "$1" =~ ^[a-zA-Z0-9_-]+$ ]] || erro 'dispatch inválido'; }
if [ -f "$HOME/.claude/agentes.conf" ]; then
    while IFS= read -r linha || [ -n "$linha" ]; do
        linha=${linha%%#*}; linha=${linha//$'\r'/}
        [[ "$linha" =~ ^[[:space:]]*$ ]] && continue
        [[ "$linha" =~ ^[[:space:]]*(team|pessoal|codex|kimi|agy)=([0-9]+)[[:space:]]*$ ]] || erro "configuração inválida: $linha"
        chave=v_${BASH_REMATCH[1]}
        printf -v "$chave" '%s' "$((10#${BASH_REMATCH[2]}))"
        [ "${!chave}" -ge 0 ] || erro 'limite inválido'
    done < "$HOME/.claude/agentes.conf"
fi

morta() { # Só evidência explícita do Orca libera uma vaga; falhas de transporte não liberam.
    local resposta
    [ -n "$1" ] || return 1
    resposta=$("${ORCA_CMD:-${ORCA_CLI_COMMAND:-orca}}" orchestration worker-show --dispatch "$1" --json 2>/dev/null)
    [ -n "$resposta" ] || return 1
    if [ -z "${py:-}" ]; then
        for py in python3 python ""; do [ -n "$py" ] && "$py" -c '' 2>/dev/null && break; done
    fi
    [ -n "$py" ] || return 1
    POOL_JSON="$resposta" POOL_DISPATCH="$1" "$py" -I - <<'EOF'
import json, os, sys
try:
    r = json.loads(os.environ["POOL_JSON"])
    d = (r.get("result") or {}).get("dispatch") or {}
    morta = (r.get("ok") is False and (r.get("error") or {}).get("code") == "dispatch_not_found") or (
        r.get("ok") is True and d.get("id") == os.environ["POOL_DISPATCH"] and
        d.get("status") in ("completed", "failed", "stopped", "abandoned"))
except (ValueError, AttributeError, TypeError):
    morta = False
sys.exit(0 if morta else 1)
EOF
}

remove_vaga() { # Renomeia e confirma o dono para não apagar uma vaga já reutilizada.
    local alvo=$1 dono=$2 retirada="$1.retirada.$$"
    [ "$(cat "$alvo/dispatch" 2>/dev/null)" = "$dono" ] || return 0
    mv "$alvo" "$retirada" 2>/dev/null || return 0
    if [ "$(cat "$retirada/dispatch" 2>/dev/null)" = "$dono" ]; then
        rm -rf "$retirada"
    else
        [ -e "$alvo" ] || mv "$retirada" "$alvo" 2>/dev/null
    fi
}
reserva_morta() { # Reserva provisória expira por TTL; desde ilegível conserva a vaga.
    local ttl desde agora
    ttl=${POOL_RESERVA_TTL:-600}
    # Vazio enquanto o pega concorrente ainda grava: date -d "" seria meia-noite e a reserva nova cairia.
    [ -s "$1/desde" ] || return 1
    desde=$(date -d "$(cat "$1/desde" 2>/dev/null)" +%s 2>/dev/null) || return 1
    agora=$(date +%s)
    [ $((agora - desde)) -gt "$ttl" ]
}
recupera() {
    local dono
    dono=$(cat "$1/dispatch" 2>/dev/null)
    case "$dono" in
        res-*) reserva_morta "$1" && remove_vaga "$1" "$dono"; return 0 ;;
    esac
    morta "$dono" && remove_vaga "$1" "$dono"
    return 0
}

case "${1:-}" in
    pega)
        [ "$#" = 3 ] || erro 'uso: pega <conta> <dispatch>'
        conta=$2; dispatch=$3
        [[ " ${contas[*]} " = *" $conta "* ]] || erro 'conta desconhecida'
        valida_dispatch "$dispatch"
        chave=v_$conta; total=${!chave}
        [ "$total" = 0 ] && exit 0
        mkdir -p "$dir" || exit 2
        ocupadas=0
        for v in "$dir/$conta".lock[0-9]*; do
            [ -d "$v" ] || continue
            [[ "${v##*.lock}" =~ ^[0-9]+$ ]] || continue
            [ "$(cat "$v/dispatch" 2>/dev/null)" = "$dispatch" ] && exit 0
            recupera "$v"
            [ -d "$v" ] && ocupadas=$((ocupadas + 1))
        done
        [ "$ocupadas" -ge "$total" ] && { echo "POOL CHEIO: $conta" >&2; exit 75; }
        for ((i=1; i<=total; i++)); do
            v="$dir/$conta.lock$i"
            if mkdir "$v" 2>/dev/null; then
                if ! { printf '%s\n' "$dispatch" > "$v/dispatch" && date -u +%FT%TZ > "$v/desde"; }; then
                    remove_vaga "$v" "$dispatch"; exit 2
                fi
                exit 0
            fi
        done
        echo "POOL CHEIO: $conta" >&2; exit 75
        ;;
    solta)
        [ "$#" = 2 ] || erro 'uso: solta <dispatch>'
        valida_dispatch "$2"
        for conta in "${contas[@]}"; do
            for v in "$dir/$conta".lock[0-9]*; do
                [ -d "$v" ] || continue
                [[ "${v##*.lock}" =~ ^[0-9]+$ ]] || continue
                [ "$(cat "$v/dispatch" 2>/dev/null)" = "$2" ] && remove_vaga "$v" "$2"
            done
        done
        ;;
    troca)
        [ "$#" = 3 ] || erro 'uso: troca <provisório> <dispatch>'
        prov=$2; novo=$3
        valida_dispatch "$prov"; valida_dispatch "$novo"
        for conta in "${contas[@]}"; do
            for v in "$dir/$conta".lock[0-9]*; do
                [ -d "$v" ] || continue
                [[ "${v##*.lock}" =~ ^[0-9]+$ ]] || continue
                dono=$(cat "$v/dispatch" 2>/dev/null)
                [ "$dono" = "$novo" ] && exit 0
                [ "$dono" = "$prov" ] || continue
                tmp_d="$v/dispatch.troca.$$"
                if printf '%s\n' "$novo" > "$tmp_d" && mv "$tmp_d" "$v/dispatch"; then
                    date -u +%FT%TZ > "$v/desde"
                    exit 0
                fi
                rm -f "$tmp_d"
                exit 2
            done
        done
        erro "troca: vaga do dono $prov não encontrada"
        ;;
    livres)
        [ "$#" = 1 ] || erro 'uso: livres'
        for conta in "${contas[@]}"; do
            chave=v_$conta; total=${!chave}; ocupadas=0
            for v in "$dir/$conta".lock[0-9]*; do
                [ -d "$v" ] || continue
                [[ "${v##*.lock}" =~ ^[0-9]+$ ]] || continue
                recupera "$v"
                if [ -d "$v" ]; then
                    ocupadas=$((ocupadas + 1))
                    [ -n "$(cat "$v/dispatch" 2>/dev/null)" ] || printf 'AVISO: trava sem dono: %s (remoção manual)\n' "$v" >&2
                fi
            done
            livres=$((total - ocupadas)); [ "$livres" -ge 0 ] || livres=0
            [ "$total" = 0 ] && livres=0
            printf '%s %s/%s\n' "$conta" "$livres" "$total"
        done
        ;;
    *) erro 'uso: pega <conta> <dispatch> | solta <dispatch> | troca <provisório> <dispatch> | livres' ;;
esac
exit 0

#!/usr/bin/env bash
# Registro de contas: catálogo do plugin + ~/.claude/agentes.conf. `source` para as funções; executado: lanca|lista.
# Bash 3.2: cada campo vive em c_<conta>_<campo> (printf -v), sem arrays associativos.
CONTAS_CATALOGO=${CONTAS_CATALOGO:-$(dirname "${BASH_SOURCE[0]}")/agentes-catalogo.conf}
CONTAS_CONF=${CONTAS_CONF:-$HOME/.claude/agentes.conf}
CONTAS_PAPEIS=" escritor revisor verificador mecanico segunda-opiniao orquestra "
CONTAS_PAPEIS_PADRAO="escritor,revisor,verificador,mecanico"

_contas_var() { printf 'c_%s_%s' "${1//-/_}" "$2"; }
_contas_set() { printf -v "$(_contas_var "$1" "$2")" '%s' "$3"; }
conta_campo() { local v; v=$(_contas_var "$1" "$2"); printf '%s' "${!v}"; }
conta_tem_papel() { case ",$(conta_campo "$1" papeis)," in *",$2,"*) return 0 ;; esac; return 1; }
conta_existe() { case " $CONTAS " in *" $1 "*) return 0 ;; esac; return 1; }
# Só medida (sem papel, ou só orquestra) não ocupa vaga: fica fora do pool.
conta_no_pool() { conta_existe "$1" && case ",$(conta_campo "$1" papeis)," in ,, | ,orquestra,) return 1 ;; esac; }
CONTAS_CAMPOS="agente id comando args config modelo vagas papeis medidor nota"
_contas_erro() { echo "contas: $1: $2" >&2; return 2; }

_contas_define() { # conta chave-do-catálogo
    local l id cmd args med nota
    # "a-b" e "a_b" usam a mesma variável: contam como repetidas.
    conta_existe "$1" || [ -n "$(conta_campo "$1" agente)" ] && return 3
    while IFS= read -r l || [ -n "$l" ]; do
        l=${l%$'\r'}
        case "$l" in '' | '#'*) continue ;; esac
        [ "${l%%|*}" = "$2" ] || continue
        IFS='|' read -r _ id cmd args med nota <<< "$l"
        _contas_set "$1" agente "$2"; _contas_set "$1" id "$id"; _contas_set "$1" comando "$cmd"
        _contas_set "$1" args "$args"; _contas_set "$1" medidor "$med"; _contas_set "$1" nota "$nota"
        _contas_set "$1" config ""; _contas_set "$1" modelo ""; _contas_set "$1" vagas 1
        _contas_set "$1" papeis "$CONTAS_PAPEIS_PADRAO"
        CONTAS="${CONTAS:+$CONTAS }$1"
        return 0
    done < "$CONTAS_CATALOGO"
    return 1
}

_contas_padrao() { # As contas de antes do registro, na mesma ordem.
    _contas_define team claude; _contas_set team config "$HOME/.claude-team"
    _contas_define pessoal claude; _contas_set pessoal vagas 0
    _contas_define codex codex
    _contas_define agy antigravity; _contas_set agy papeis segunda-opiniao
    if [ -d "$HOME/.claude-b" ]; then
        _contas_define claude-b claude; _contas_set claude-b config "$HOME/.claude-b"
        _contas_set claude-b vagas 0; _contas_set claude-b papeis ""
    fi
}

_contas_valida() { # chave valor linha
    case "$1" in
        vagas) [[ "$2" =~ ^[0-9]+$ ]] || _contas_erro 'vagas inválidas' "$3" ;;
        medidor) [[ "$2" =~ ^(claude|-|orca:[A-Za-z]+)$ ]] || _contas_erro 'medidor desconhecido' "$3" ;;
        papeis)
            local p resto=$2,
            while [ -n "$resto" ]; do
                p=${resto%%,*}; resto=${resto#*,}
                case "$CONTAS_PAPEIS" in *" $p "*) ;; *) _contas_erro "papel desconhecido ($p)" "$3"; return ;; esac
            done ;;
        comando | args | config | modelo) ;;
        *) _contas_erro "chave desconhecida ($1)" "$3" ;;
    esac
}

_contas_linha() { # Conta do dev: nome chave=valor ..., valor com espaço entre aspas duplas.
    local linha=$1 nome resto chave valor agente="" pares=() i
    local re_conta='^[[:space:]]*([a-z0-9_-]{1,32})([[:space:]]+(.*))?$'
    local re_par='^[[:space:]]*([a-z]+)=("([^"]*)"|([^[:space:]"]*))(.*)$'
    [[ "$linha" =~ $re_conta ]] || { _contas_erro 'linha inválida' "$linha"; return; }
    nome=${BASH_REMATCH[1]}; resto=${BASH_REMATCH[3]}
    while [[ "$resto" =~ $re_par ]]; do
        chave=${BASH_REMATCH[1]}; valor=${BASH_REMATCH[3]}${BASH_REMATCH[4]}; resto=${BASH_REMATCH[5]}
        if [ "$chave" = agente ]; then agente=$valor; else pares+=("$chave" "$valor"); fi
    done
    [[ "$resto" =~ ^[[:space:]]*$ ]] || { _contas_erro 'linha inválida' "$linha"; return; }
    [ -n "$agente" ] || { _contas_erro 'falta agente=' "$linha"; return; }
    _contas_define "$nome" "$agente"
    case $? in
        1) _contas_erro "agente fora do catálogo ($agente)" "$linha"; return ;;
        3) _contas_erro 'conta repetida' "$linha"; return ;;
    esac
    for ((i = 0; i < ${#pares[@]}; i += 2)); do
        chave=${pares[i]}; valor=${pares[i + 1]}
        _contas_valida "$chave" "$valor" "$linha" || return
        [ "$chave" = config ] && [ "${valor:0:2}" = "~/" ] && valor=$HOME/${valor:2}
        _contas_set "$nome" "$chave" "$valor"
    done
}

contas_carrega() {
    local linha legado=() proprias=0 i conta f
    for conta in $CONTAS; do for f in $CONTAS_CAMPOS; do unset "$(_contas_var "$conta" "$f")"; done; done
    CONTAS=""; ESCOLHA=ritmo
    if [ -f "$CONTAS_CONF" ]; then
        while IFS= read -r linha || [ -n "$linha" ]; do
            linha=${linha%$'\r'}
            [[ "$linha" =~ ^[[:space:]]*(#.*)?$ ]] && continue
            if [[ "$linha" =~ ^[[:space:]]*escolha=([a-z]*)[[:space:]]*$ ]]; then
                case "${BASH_REMATCH[1]}" in ritmo | ordem) ESCOLHA=${BASH_REMATCH[1]} ;; *) _contas_erro 'escolha inválida' "$linha"; return ;; esac
            elif [[ "$linha" =~ ^[[:space:]]*([a-z0-9_-]+)=([^[:space:]]*)[[:space:]]*$ ]]; then
                legado+=("$linha")
            else
                proprias=1
                _contas_linha "$linha" || return
            fi
        done < "$CONTAS_CONF"
    fi
    [ "$proprias" = 1 ] || _contas_padrao
    for ((i = 0; i < ${#legado[@]}; i++)); do # conta=N: vagas de uma conta já definida
        [[ "${legado[i]}" =~ ^[[:space:]]*([a-z0-9_-]+)=([0-9]+)[[:space:]]*$ ]] || { _contas_erro 'configuração inválida' "${legado[i]}"; return; }
        conta=${BASH_REMATCH[1]}
        conta_existe "$conta" || { _contas_erro 'configuração inválida' "${legado[i]}"; return; }
        _contas_set "$conta" vagas "$((10#${BASH_REMATCH[2]}))"
    done
    return 0
}

contas_lanca() { # conta papel [modelo] → comando para orca-libera.sh --cria --command
    local cfg linha modelo
    conta_existe "$1" || { echo "contas: conta desconhecida: $1" >&2; return 2; }
    cfg=$(conta_campo "$1" config); modelo=${3:-$(conta_campo "$1" modelo)}
    linha=$(conta_campo "$1" comando)
    [ -n "$(conta_campo "$1" args)" ] && linha="$linha $(conta_campo "$1" args)"
    [ -n "$cfg" ] && linha="CLAUDE_CONFIG_DIR=$(printf '%q' "$cfg") $linha"
    # Só o Claude Code conhece os agentes de plugin; nos demais o papel vai no spec. Papel com ":" já é o agente (plugin:agente).
    if [ "$(conta_campo "$1" agente)" = claude ]; then
        case "$2" in *:*) linha="$linha --agent $2" ;; *) linha="$linha --agent fluxo-orca:$2" ;; esac
    fi
    [ -n "$modelo" ] && linha="$linha --model $(printf '%q' "$modelo")"
    printf '%s\n' "$linha"
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    contas_carrega || exit 2
    case "${1:-}" in
        lanca) [ $# -ge 3 ] || { echo 'uso: contas.sh lanca <conta> <papel> [modelo]' >&2; exit 2; }
               contas_lanca "$2" "$3" "${4:-}" ;;
        lista) for c in $CONTAS; do
                   printf '%s agente=%s vagas=%s papeis=%s medidor=%s\n' "$c" "$(conta_campo "$c" agente)" \
                       "$(conta_campo "$c" vagas)" "$(conta_campo "$c" papeis)" "$(conta_campo "$c" medidor)"
               done ;;
        *) echo 'uso: contas.sh lanca <conta> <papel> [modelo] | lista' >&2; exit 2 ;;
    esac
fi

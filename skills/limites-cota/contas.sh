#!/usr/bin/env bash
# Registro de contas: catálogo do plugin + ~/.claude/agentes.conf. `source` para as funções; executado: lanca|lista.
# Bash 3.2: cada campo vive em c_<conta>_<campo> (printf -v), sem arrays associativos.
CONTAS_CATALOGO=${CONTAS_CATALOGO:-$(dirname "${BASH_SOURCE[0]}")/agentes-catalogo.conf}
CONTAS_CONF=${CONTAS_CONF:-$HOME/.claude/agentes.conf}
CONTAS_PAPEIS=" escritor revisor verificador mecanico segunda-opiniao orquestra "
CONTAS_PAPEIS_PADRAO="escritor,revisor,verificador,mecanico"
CONTAS_FONTE=${BASH_SOURCE[0]}

# Sem subshell: cada $(...) custa um fork (~0,12 s no Git Bash).
_contas_set() { printf -v "c_${1//-/_}_$2" '%s' "$3"; }
conta_campo() { local v=c_${1//-/_}_$2; printf '%s' "${!v}"; }
conta_tem_papel() { local v=c_${1//-/_}_papeis; case ",${!v}," in *",$2,"*) return 0 ;; esac; return 1; }
conta_existe() { case " $CONTAS " in *" $1 "*) return 0 ;; esac; return 1; }
# Só medida (sem papel, ou só orquestra) não ocupa vaga: fica fora do pool.
conta_no_pool() { local v=c_${1//-/_}_papeis; conta_existe "$1" && case ",${!v}," in ,, | ,orquestra,) return 1 ;; esac; }
CONTAS_CAMPOS="agente id comando args config modelo vagas peso papeis medidor pre fim regras skills testado nota"
CONTAS_PAPEIS_TRABALHO=" escritor revisor verificador mecanico "
_contas_erro() { echo "contas: $1: $2" >&2; return 2; }

_contas_define() { # conta chave-do-catálogo
    local l id cmd args med pre fim regras skills testado nota
    # "a-b" e "a_b" usam a mesma variável: contam como repetidas.
    conta_existe "$1" || [ -n "$(conta_campo "$1" agente)" ] && return 3
    while IFS= read -r l || [ -n "$l" ]; do
        l=${l%$'\r'}
        case "$l" in '' | '#'*) continue ;; esac
        [ "${l%%|*}" = "$2" ] || continue
        IFS='|' read -r _ id cmd args med pre fim regras skills testado nota <<< "$l"
        _contas_set "$1" agente "$2"; _contas_set "$1" id "$id"; _contas_set "$1" comando "$cmd"
        _contas_set "$1" args "$args"; _contas_set "$1" medidor "$med"; _contas_set "$1" nota "$nota"
        _contas_set "$1" config ""; _contas_set "$1" modelo ""; _contas_set "$1" vagas 1
        _contas_set "$1" peso 1
        _contas_set "$1" pre "$pre"; _contas_set "$1" fim "$fim"; _contas_set "$1" regras "$regras"
        _contas_set "$1" skills "$skills"; _contas_set "$1" testado "$testado"
        # Papel de trabalho por padrão só onde há a trava de comando remoto (guarda-externos, GUIA fase 4b); o resto, só se escrito.
        case "$2" in
            claude | codex | antigravity) _contas_set "$1" papeis "$CONTAS_PAPEIS_PADRAO" ;;
            *) _contas_set "$1" papeis "" ;;
        esac
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

_contas_valida() { # chave valor linha conta
    case "$1" in
        vagas) [[ "$2" =~ ^[0-9]+$ ]] || _contas_erro 'vagas inválidas' "$3" ;;
        peso) [[ "$2" =~ ^[0-9]+$ ]] && [ "$2" -ge 1 ] || _contas_erro 'peso inválido' "$3" ;;
        medidor) [[ "$2" =~ ^(claude|-|orca:[A-Za-z]+)$ ]] || _contas_erro 'medidor desconhecido' "$3" ;;
        papeis)
            local p ag resto=$2,
            while [ -n "$resto" ]; do
                p=${resto%%,*}; resto=${resto#*,}
                case "$CONTAS_PAPEIS" in *" $p "*) ;; *) _contas_erro "papel desconhecido ($p)" "$3"; return ;; esac
                # Worker autônomo sem a trava de comando remoto (hook antes de comando) só dá segunda opinião; a trava só documentada
                # (testado=-) também não basta: claude, codex e antigravity têm a trava provada, os demais precisam da prova do GUIA.
                case "$CONTAS_PAPEIS_TRABALHO" in *" $p "*)
                    ag=$(conta_campo "$4" agente)
                    [ "$(conta_campo "$4" pre)" = sim ] || { _contas_erro "$ag sem trava de comando: só segunda-opiniao" "$3"; return; }
                    case "$ag" in claude | codex | antigravity) ;; *)
                        [[ "$(conta_campo "$4" testado)" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] \
                            || { _contas_erro "$ag: trava só documentada, rode a prova do GUIA fase 4b e registre testado=<data>" "$3"; return; }
                        # O catálogo é do repo; a trava é por máquina: o carimbo do instala-agente.sh prova que esta a tem.
                        [ -s "$HOME/.cache/trava-$ag.ok" ] \
                            || { _contas_erro "$ag: trava não instalada nesta máquina — rode bash ~/.cache/instala-agente.sh $ag --aplicar" "$3"; return; } ;;
                    esac ;;
                esac
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
        _contas_valida "$chave" "$valor" "$linha" "$nome" || return
        [ "$chave" = config ] && [ "${valor:0:2}" = "~/" ] && valor=$HOME/${valor:2}
        _contas_set "$nome" "$chave" "$valor"
    done
}

# Cache do registro parseado (mtime com nanossegundos: duas gravações no mesmo segundo não passam por iguais): atribuições bash em ~/.cache/agentes/registro.cache, válido enquanto o carimbo bater.
_contas_carimbo() { # entrada do registro (arquivo, catálogo, este script, conta claude-b, travas) → CONTAS_CARIMBO
    local st f t="" b=0
    if [ -f "$CONTAS_CONF" ]; then
        st=$(stat -c '%y %s' -- "$CONTAS_CONF" "$CONTAS_CATALOGO" "$CONTAS_FONTE" 2>/dev/null) || return 1
    else
        st=$(stat -c '%y %s' -- "$CONTAS_CATALOGO" "$CONTAS_FONTE" 2>/dev/null) || return 1
        st="-"$'\n'"$st"
    fi
    [ -d "$HOME/.claude-b" ] && b=1
    for f in "$HOME"/.cache/trava-*.ok; do [ -s "$f" ] && t="$t,${f##*/trava-}"; done
    CONTAS_CARIMBO="# stamp $CONTAS_CONF ${st//$'\n'/ } $CONTAS_CATALOGO b=$b t=$t"
}

_contas_cache_le() { # Só aceita carimbo igual e linhas de atribuição do registro; senão reconstrói.
    local arq=$HOME/.cache/agentes/registro.cache linha primeira=1
    [ -f "$arq" ] || return 1
    while IFS= read -r linha || [ -n "$linha" ]; do
        if [ "$primeira" = 1 ]; then [ "$linha" = "$CONTAS_CARIMBO" ] || return 1; primeira=0; continue; fi
        [[ "$linha" =~ ^(c_[a-z0-9_]+|CONTAS|ESCOLHA|CONTAS_TETO|CONTAS_SEGUNDA_TETO|RAM_MIN_GB)= ]] || return 1
        case "$linha" in *'$('* | *'${'* | *'`'*) return 1 ;; esac
    done < "$arq"
    [ "$primeira" = 0 ] || return 1
    source "$arq"
}

_contas_cache_grava() { # Atômico (.tmp + mv); falha de gravação não afeta o registro já carregado.
    local arq=$HOME/.cache/agentes/registro.cache conta f v
    mkdir -p "${arq%/*}" 2>/dev/null || return 0
    {
        printf '%s\n' "$CONTAS_CARIMBO"
        printf '%s=%q\n' CONTAS "$CONTAS" ESCOLHA "$ESCOLHA" CONTAS_TETO "$CONTAS_TETO" CONTAS_SEGUNDA_TETO "$CONTAS_SEGUNDA_TETO" RAM_MIN_GB "$RAM_MIN_GB"
        for conta in $CONTAS; do for f in $CONTAS_CAMPOS; do v=c_${conta//-/_}_$f; printf '%s=%q\n' "$v" "${!v}"; done; done
    } > "$arq.tmp.$$" 2>/dev/null && mv -f "$arq.tmp.$$" "$arq" 2>/dev/null
    rm -f "$arq.tmp.$$" 2>/dev/null
    return 0
}

contas_carrega() {
    local linha legado=() proprias=0 i conta f
    for conta in $CONTAS; do for f in $CONTAS_CAMPOS; do unset "c_${conta//-/_}_$f"; done; done
    CONTAS=""; ESCOLHA=ritmo; CONTAS_TETO=0; RAM_MIN_GB=0; CONTAS_SEGUNDA_TETO=60
    if _contas_carimbo; then _contas_cache_le && return 0; else CONTAS_CARIMBO=""; fi
    # Cache parcial ou ilegível pode ter atribuído algo antes de falhar.
    for conta in $CONTAS; do for f in $CONTAS_CAMPOS; do unset "c_${conta//-/_}_$f"; done; done
    CONTAS=""; ESCOLHA=ritmo; CONTAS_TETO=0; RAM_MIN_GB=0; CONTAS_SEGUNDA_TETO=60
    if [ -f "$CONTAS_CONF" ]; then
        while IFS= read -r linha || [ -n "$linha" ]; do
            linha=${linha%$'\r'}
            [[ "$linha" =~ ^[[:space:]]*(#.*)?$ ]] && continue
            if [[ "$linha" =~ ^[[:space:]]*escolha=([a-z]*)[[:space:]]*$ ]]; then
                case "${BASH_REMATCH[1]}" in ritmo | ordem) ESCOLHA=${BASH_REMATCH[1]} ;; *) _contas_erro 'escolha inválida' "$linha"; return ;; esac
            elif [[ "$linha" =~ ^[[:space:]]*ram_min=([0-9]+([.][0-9]+)?)[[:space:]]*$ ]]; then
                RAM_MIN_GB=${BASH_REMATCH[1]}
            elif [[ "$linha" =~ ^[[:space:]]*segunda_teto=(.*)$ ]]; then
                [[ "${BASH_REMATCH[1]}" =~ ^([0-9]+)[[:space:]]*$ ]] || { _contas_erro 'segunda_teto inválido' "$linha"; return; }
                CONTAS_SEGUNDA_TETO=$((10#${BASH_REMATCH[1]}))
            elif [[ "$linha" =~ ^[[:space:]]*teto=(.*)$ ]]; then
                [[ "${BASH_REMATCH[1]}" =~ ^([0-9]+)[[:space:]]*$ ]] || { _contas_erro 'teto inválido' "$linha"; return; }
                CONTAS_TETO=$((10#${BASH_REMATCH[1]}))
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
    [ -z "$CONTAS_CARIMBO" ] || _contas_cache_grava
    return 0
}

conta_aviso() { # Conta de trabalho em agente sem hook de fim de turno: o Orca acorda o coordenador se parar sem worker_done.
    local p v=c_${1//-/_}_fim
    [ "${!v}" = sim ] && return 1
    for p in $CONTAS_PAPEIS_TRABALHO; do conta_tem_papel "$1" "$p" && { CONTA_AVISO='sem fim de turno: Orca avisa parada sem worker_done'; echo "$CONTA_AVISO"; return 0; }; done
    return 1
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
        case "$2" in escritor | fluxo-orca:escritor)
            [ -z "${CONTAS_ADVISOR-opus}" ] || linha="$linha --advisor $(printf '%q' "${CONTAS_ADVISOR-opus}")" ;;
        esac
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
                   p=c_${c//-/_}_; ag=${p}agente; va=${p}vagas; pe=${p}peso; pa=${p}papeis; me=${p}medidor
                   printf '%s agente=%s vagas=%s peso=%s papeis=%s medidor=%s' "$c" "${!ag}" "${!va}" "${!pe}" "${!pa}" "${!me}"
                   conta_aviso "$c" > /dev/null && printf ' aviso=%s' "$CONTA_AVISO"
                   echo
               done ;;
        *) echo 'uso: contas.sh lanca <conta> <papel> [modelo] | lista' >&2; exit 2 ;;
    esac
fi

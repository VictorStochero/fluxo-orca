#!/usr/bin/env bash
# Archive genérico de worktree para o Orca (orca.yaml do repo ou Orca > repo > archive script: bash ~/.cache/wt-archive.sh).
# A pasta pode já ter sido removida: identidade por ORCA_WORKTREE_PATH; banco pelo registro que o wt-setup.sh grava
# em <.git comum>/wt-bancos/<pasta>; servidor de banco pelo .env do principal.
# Remove <banco>, <banco>_test e tudo que começa com <banco>_ (tenants, _test_test_N do --parallel, _template, _pool_*),
# exceto os de outro worktree vivo cujo nome começa com <banco>_. Aborta sem remover nada se: houver alteração não
# commitada, o git falhar, ou <banco> colidir com o banco do principal ou de outro worktree vivo.

set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/wt-lib.sh"

log="$HOME/.cache/wt-archive.log"
mkdir -p "$(dirname "$log")"
registra() { printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" | tee -a "$log"; }
aborta() { registra "ABORTADO ($pasta): $1 — nada removido."; exit 1; }

raiz_bruta="${ORCA_WORKTREE_PATH:-$(pwd)}"
raiz="$(caminho_canonico "$raiz_bruta")"
# O nome vem da pasta, como no setup (ORCA_WORKSPACE_NAME é o nome de exibição e pode divergir).
pasta="$(basename "$raiz")"
# Principal: argumento, senão ORCA_ROOT_PATH (o Orca passa a raiz do repo), senão o git do worktree se ainda existir.
principal_bruto="${1:-${ORCA_ROOT_PATH:-}}"
if [ -z "$principal_bruto" ] && [ -d "$raiz" ]; then
    principal_bruto="$(dirname "$(git -C "$raiz" rev-parse --path-format=absolute --git-common-dir)")"
fi
[ -n "$principal_bruto" ] || { echo "Uso: wt-archive.sh <pasta do checkout principal>" >&2; exit 1; }
principal="$(caminho_canonico "$principal_bruto")"
comum="$(git -C "$principal_bruto" rev-parse --path-format=absolute --git-common-dir)" || aborta "git falhou no principal"

[ "$raiz" = "$principal" ] && aborta "isso é o checkout principal"
if [ -d "$raiz" ]; then
    sujo="$(git -C "$raiz" status --porcelain)" || aborta "git status falhou no worktree"
    [ -z "$sujo" ] || { git -C "$raiz" status --short | head -20; aborta "alterações não commitadas"; }
fi

site="$(printf '%s' "$pasta" | tr '[:upper:]' '[:lower:]')"
if [ -f "$principal_bruto/.ddev/config.yaml" ]; then
    ddev delete --omit-snapshot --yes "$site" || true
    registra "ddev: projeto $site removido"
    exit 0
fi

registro="$(registro_bancos "$comum" "$pasta")"
# Sem registro (worktree criado fora do wt-setup.sh): não se adivinha nome de banco para apagar.
[ -f "$registro" ] || { registra "archive: $pasta sem registro em wt-bancos/ — nenhum banco removido (limpar à mão se houver)."; exit 0; }
banco="$(head -1 "$registro" | tr -d '\r')"
[ -n "$banco" ] || aborta "registro vazio"
registra "archive: pasta=$pasta raiz=$raiz banco=$banco"

[ -f "$principal_bruto/.env" ] || { registra "principal sem .env: bancos não removidos."; exit 0; }
db_info "$principal_bruto/.env"
[ -n "$DB_MOTOR" ] || { registra "banco do principal não identificado (MySQL/MariaDB/Postgres): nada removido."; exit 0; }
if conflito="$(colide_com_principal "$banco" "$principal_bruto")"; then
    aborta "o banco $banco é ou abrange o banco $conflito do principal"
fi
db_info "$principal_bruto/.env"

# Outros worktrees vivos: nome igual aborta; nome que começa com <banco>_ (ex.: app-fix-a-b ao arquivar app-fix-a) fica protegido.
protegidos=()
lista="$(git -C "$principal_bruto" worktree list --porcelain)" || aborta "git worktree list falhou"
while read -r linha; do
    case "$linha" in worktree\ *) ;; *) continue ;; esac
    p_bruto="${linha#worktree }"; p="$(caminho_canonico "$p_bruto")"
    [ "$p" = "$raiz" ] || [ "$p" = "$principal" ] && continue
    reg="$(registro_bancos "$comum" "$(basename "$p_bruto")")"
    if [ -f "$reg" ]; then b="$(head -1 "$reg" | tr -d '\r')"; else b="$(nome_banco "$(basename "$p_bruto")" 0)"; fi
    [ "$b" = "$banco" ] && aborta "o worktree vivo $p_bruto usa o mesmo banco $banco"
    case "$b" in "${banco}_"*) protegidos+=("$b") ;; esac
done <<< "$lista"

bancos="$(listar_bancos)" || aborta "não consegui listar os bancos"
removidos=""
while read -r b; do
    [ -n "$b" ] || continue
    case "$b" in "$banco"|"${banco}_"*) ;; *) continue ;; esac
    for o in ${protegidos[@]+"${protegidos[@]}"}; do
        case "$b" in "$o"|"${o}_"*) continue 2 ;; esac
    done
    dropar_banco "$b" && removidos="$removidos $b"
done <<< "$bancos"
rm -f "$registro"
registra "bancos removidos:${removidos:- nenhum}"

{ command -v herd >/dev/null 2>&1 && herd unsecure "$site" >/dev/null 2>&1; } || { command -v herd.bat >/dev/null 2>&1 && herd.bat unsecure "$site" >/dev/null 2>&1; } || true
if command -v lerd >/dev/null 2>&1 && [ -d "$raiz_bruta" ]; then (cd "$raiz_bruta" && lerd unlink >/dev/null 2>&1) || true; fi
exit 0

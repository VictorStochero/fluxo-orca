#!/bin/bash
# shortcut: remover quando configurações e chamadas antigas tiverem migrado para fila-teste.sh.
exec bash "$(dirname "$0")/fila-teste.sh" "$@"

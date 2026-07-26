#!/usr/bin/env bash
# tools/snapshot.sh <before|after>
#
# Roda os comandos principais do arn e salva a saída, pra comparar
# comportamento antes/depois de uma mudança com `diff`. Não é uma suíte
# de testes automatizada — é uma checagem rápida e manual.
#
# Uso:
#   ./tools/snapshot.sh before   # ANTES da mudança
#   # ... aplica a mudança, roda ./tools/build-arn.sh se editou core.sh/backends/ ...
#   ./tools/snapshot.sh after
#   diff /tmp/arnyx-snapshot-before.txt /tmp/arnyx-snapshot-after.txt
set -uo pipefail

[[ "${1:-}" == "before" || "${1:-}" == "after" ]] || {
    echo "Uso: $0 <before|after>" >&2
    exit 1
}

OUT="/tmp/arnyx-snapshot-$1.txt"
ARN="${ARN_BIN:-arn}"   # ARN_BIN=./bin/arn ./tools/snapshot.sh before, se quiser testar sem instalar

{
    echo "=== list ==="
    "$ARN" list 2>&1

    echo
    echo "=== diff ==="
    "$ARN" diff 2>&1

    echo
    echo "=== manage --all (só leitura — cancela com ESC assim que abrir) ==="
    echo "(rodar manualmente: '$ARN' manage --all — comparar visualmente a lista mostrada, não dá pra automatizar sem interação)"

    echo
    echo "=== rebuild --dry-run ==="
    "$ARN" rebuild --dry-run 2>&1
} > "$OUT"

echo "Salvo em $OUT"

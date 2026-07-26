#!/usr/bin/env bash
# build-arn.sh — gera bin/arn concatenando arch.sh + sources/{pacman,aur}.sh
# + src/core.sh. Não editar bin/arn direto — editar aqui/backends/ e rodar
# este script de novo.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

ARCH_GLUE="$REPO_ROOT/backends/arch/arch.sh"
PACMAN_SRC="$REPO_ROOT/backends/arch/sources/pacman.sh"
AUR_SRC="$REPO_ROOT/backends/arch/sources/aur.sh"
CORE="$REPO_ROOT/src/core.sh"
OUT="$REPO_ROOT/bin/arn"

for f in "$ARCH_GLUE" "$PACMAN_SRC" "$AUR_SRC" "$CORE"; do
    [[ -f "$f" ]] || { echo "Erro: $f não encontrado." >&2; exit 1; }
done

mkdir -p "$(dirname "$OUT")"
{
    echo "#!/usr/bin/env bash"
    echo "# bin/arn — GERADO por tools/build-arn.sh. NÃO EDITE DIRETAMENTE."
    echo "# Fonte: backends/arch/{arch.sh,sources/pacman.sh,sources/aur.sh} + src/core.sh"
    echo
    tail -n +2 "$ARCH_GLUE"
    echo
    tail -n +2 "$PACMAN_SRC"
    echo
    tail -n +2 "$AUR_SRC"
    echo
    tail -n +2 "$CORE"
} > "$OUT"

chmod +x "$OUT"
echo "✓ bin/arn gerado a partir de backends/ + src/core.sh"

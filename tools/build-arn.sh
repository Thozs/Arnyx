#!/usr/bin/env bash
# build-arn.sh — gera bin/arn concatenando arch.sh + sources/{pacman,aur}.sh
# + src/core.sh. Não editar bin/arn direto — editar aqui/backends/ e rodar
# este script de novo.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

# --backend=arch|gentoo (default: auto-detecta via /etc/os-release;
# se não conseguir detectar, cai pra arch — comportamento antigo).
BACKEND=""
for arg in "$@"; do
    case "$arg" in
        --backend=*) BACKEND="${arg#--backend=}" ;;
    esac
done

if [[ -z "$BACKEND" ]]; then
    if [[ -f /etc/os-release ]] && grep -qi '^ID=gentoo' /etc/os-release; then
        BACKEND="gentoo"
    else
        BACKEND="arch"
    fi
fi

CORE="$REPO_ROOT/src/core.sh"
OUT="$REPO_ROOT/bin/arn"
GLUE_FILES=()

case "$BACKEND" in
    arch)
        GLUE_FILES=(
            "$REPO_ROOT/backends/arch/arch.sh"
            "$REPO_ROOT/backends/arch/sources/pacman.sh"
            "$REPO_ROOT/backends/arch/sources/aur.sh"
        )
        ;;
    gentoo)
        GLUE_FILES=(
            "$REPO_ROOT/backends/gentoo/gentoo.sh"
            "$REPO_ROOT/backends/gentoo/sources/portage.sh"
        )
        ;;
    *)
        echo "Erro: backend desconhecido '$BACKEND' (use arch ou gentoo)." >&2
        exit 1
        ;;
esac

for f in "${GLUE_FILES[@]}" "$CORE"; do
    [[ -f "$f" ]] || { echo "Erro: $f não encontrado." >&2; exit 1; }
done

mkdir -p "$(dirname "$OUT")"
{
    echo "#!/usr/bin/env bash"
    echo "# bin/arn — GERADO por tools/build-arn.sh --backend=$BACKEND. NÃO EDITE DIRETAMENTE."
    echo "# Fonte: backends/$BACKEND/* + src/core.sh"
    echo
    for f in "${GLUE_FILES[@]}"; do
        tail -n +2 "$f"
        echo
    done
    tail -n +2 "$CORE"
} > "$OUT"

chmod +x "$OUT"
echo "✓ bin/arn gerado (backend: $BACKEND) a partir de backends/$BACKEND/* + src/core.sh"

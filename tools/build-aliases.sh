#!/usr/bin/env bash
# build-aliases.sh — gera aliases/{fish,bash,zsh}/aliases.* extraindo os
# aliases direto da seção "ALIASES FISH" dentro de bin/arn (fonte única —
# sem arquivo de config separado pra manter sincronizado à mão).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

ARN_BIN="$REPO_ROOT/bin/arn"
OUT_DIR="$REPO_ROOT/aliases"

FISH_OUT="$OUT_DIR/fish/aliases.fish"
SH_OUT="$OUT_DIR/sh/aliases.sh"   # compartilhado entre bash e zsh (sintaxe idêntica)

if [[ ! -f "$ARN_BIN" ]]; then
    echo "Erro: $ARN_BIN não encontrado." >&2
    exit 1
fi

# Extrai pares "nome:comando" da seção ALIASES FISH do help embutido em bin/arn.
# Formato esperado ali: "  arni    → arn install"
pairs="$(awk '
    /ALIASES FISH/ { capture=1; next }
    capture && /^[[:space:]]*$/ { exit }
    capture && /→/ {
        line=$0
        sub(/^[ \t]+/, "", line)
        n=split(line, parts, /[ \t]+→[ \t]+/)
        if (n==2) print parts[1] ":" parts[2]
    }
' "$ARN_BIN")"

if [[ -z "$pairs" ]]; then
    echo "Erro: nenhum alias encontrado em $ARN_BIN (seção 'ALIASES FISH' mudou de formato?)." >&2
    exit 1
fi

mkdir -p "$OUT_DIR/fish" "$OUT_DIR/sh"

HEADER="# Gerado automaticamente por tools/build-aliases.sh a partir de bin/arn
# Não edite este arquivo diretamente — edite a seção 'ALIASES FISH' em
# bin/arn (dentro da função usage()) e rode o script de novo."

echo "$HEADER" > "$FISH_OUT"
echo "$HEADER" > "$SH_OUT"

count=0
while IFS=: read -r name cmd; do
    [[ -z "$name" || -z "$cmd" ]] && continue
    echo "alias $name '$cmd'" >> "$FISH_OUT"
    echo "alias $name='$cmd'" >> "$SH_OUT"
    count=$((count + 1))
done <<< "$pairs"

echo "✓ $count aliases gerados a partir de bin/arn"
echo "✓ $FISH_OUT"
echo "✓ $SH_OUT (compartilhado entre bash e zsh)"

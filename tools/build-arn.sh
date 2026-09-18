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
    if [[ -f /etc/os-release ]] && grep -qiE '^ID=("|'"'"')?gentoo' /etc/os-release; then
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

if [[ "$BACKEND" == "gentoo" ]]; then
    # Depois do refactor pra backend-agnostic, o único uso que resta do
    # literal "pacman" em core.sh é como token/rótulo da fonte primária
    # (nome da seção no .conf, mensagens "encontrado no repo oficial →
    # pacman", etc.) — não sobrou nenhuma chamada direta ao binário
    # pacman. Por isso dá pra trocar tudo de uma vez com uma palavra só,
    # em vez de editar mensagem por mensagem: fica consistente entre
    # .conf, validação e texto exibido.
    sed -i 's/\bpacman\b/portage/g' "$OUT"

    # Gentoo não tem equivalente ao AUR — tira as referências que
    # ficariam confusas/erradas (a seção [yay] em si continua existindo
    # internamente, sempre vazia, pra não precisar reescrever o
    # parsing do .conf; só o que aparece pro usuário é limpo aqui).
    sed -i \
        -e '/Seção \[yay\]/d' \
        -e '/^\[yay\]$/d' \
        -e 's/"\$manager" == "portage" || "\$manager" == "yay"/"$manager" == "portage"/' \
        -e 's/Uso: add <portage|yay>/Uso: add <portage>/' \
        -e 's#não encontrado nem no repo oficial nem no AUR\.#não encontrado no repo oficial.#' \
        -e 's#não encontrado com esse nome exato no repo/AUR#não encontrado com esse nome exato no repo oficial#' \
        -e 's#(repo/AUR pode ter renomeado)#(o repo pode ter renomeado)#' \
        -e 's#não verificado no repo/AUR ao adotar#não verificado no repo oficial ao adotar#' \
        -e 's/no repo oficial e no AUR/no repo oficial/' \
        -e 's/Uso: upgrade \[portage|yay\]/Uso: upgrade [portage]/' \
        -e 's#Detecta portage/AUR sozinho#Detecta portage sozinho#' \
        -e 's/Busca no repo oficial + AUR/Busca no repo oficial/' \
        -e 's/add <portage|yay> <pkg>/add <portage> <pkg>  /' \
        -e 's/Atualiza todos os pacotes (portage + AUR)/Atualiza todos os pacotes/' \
        -e '/upgrade yay .*Atualiza somente pacotes AUR/d' \
        "$OUT"

    # Bloco de exibição "[yay / AUR]" em cmd_list (11 linhas, do echo
    # do cabeçalho até o 'done' do loop) — deletado por inteiro, já
    # que no Gentoo essa seção nunca tem nada dentro.
    awk '
        /\[yay \/ AUR\]/ { skip=11 }
        skip>0 { skip--; next }
        { print }
    ' "$OUT" > "$OUT.tmp" && mv "$OUT.tmp" "$OUT"
    chmod +x "$OUT"

    # A tabela ALIASES FISH é lida tanto por este script (via
    # build-aliases.sh, estático) quanto em runtime por 'arn aliases
    # install' (lendo o próprio $0) — corrigir o texto aqui já resolve
    # os dois. "yay/AUR" não existe no Gentoo; "arnup" deve apontar pro
    # token que o cmd_upgrade reconhece pro backend (portage, já
    # renomeado acima); e o arnunmask entra na mesma tabela pra sair
    # instalado automaticamente junto com os aliases comuns.
    sed -i \
        -e '/arnua *→ arn upgrade yay/d' \
        -e '/arnrb *→ arn rollback/a\  arnunmask               → arn unmask' \
        "$OUT"
fi

echo "✓ bin/arn gerado (backend: $BACKEND) a partir de backends/$BACKEND/* + src/core.sh"

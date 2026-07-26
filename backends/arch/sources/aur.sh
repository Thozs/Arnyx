#!/usr/bin/env bash
# backends/arch/sources/aur.sh — AUR, via yay ou paru.
#
# is_installed/remove/list_explicit ficam em src/core.sh (ver pacman.sh).

# Detecta qual AUR helper usar. Se só um dos dois estiver instalado, usa
# esse direto. Se ambos estiverem, pergunta uma vez e guarda a escolha em
# $CACHE_DIR/.aur_helper (mesmo padrão de cache usado pro nag de aliases).
# Se nenhum estiver instalado, retorna "yay" — quem chama já trata o "não
# encontrado" via `command -v`.
aur_detect_helper() {
    local cache_file="$CACHE_DIR/.aur_helper"
    local have_yay=0 have_paru=0
    command -v yay  >/dev/null 2>&1 && have_yay=1
    command -v paru >/dev/null 2>&1 && have_paru=1

    if (( have_yay )) && (( have_paru )); then
        if [[ -f "$cache_file" ]]; then
            local saved; saved="$(cat "$cache_file" 2>/dev/null)"
            [[ "$saved" == "yay" || "$saved" == "paru" ]] && { echo "$saved"; return 0; }
        fi

        local reply helper
        read -r -p "$(echo -e "${YELLOW}?${NC} Você tem yay e paru instalados. Qual usar? [Y/p] ")" reply
        case "$reply" in
            p|P) helper="paru" ;;
            *)   helper="yay"  ;;
        esac

        mkdir -p -m 700 "$CACHE_DIR" 2>/dev/null
        echo "$helper" > "$cache_file"
        chmod 600 "$cache_file" 2>/dev/null
        echo "$helper"
        return 0
    fi

    (( have_paru )) && { echo "paru"; return 0; }
    echo "yay"
}

aur_available() {
    local helper; helper="$(aur_detect_helper)"
    command -v "$helper" >/dev/null 2>&1 || return 1
    "$helper" -Si "$1" &>/dev/null
}

aur_search() {
    local helper; helper="$(aur_detect_helper)"
    command -v "$helper" >/dev/null 2>&1 || return 0
    LC_ALL=C "$helper" -Ssa "$1" 2>/dev/null | awk -v mgr="$helper" '
        /^aur\// {
            split($1, a, "/"); name = a[2]
            d = ""
            if ((getline d) > 0) sub(/^[ \t]+/, "", d)
            printf "%s\t%s\t%s\n", mgr, name, d
        }
    '
}

# Flags de automação (pular menus interativos) equivalentes entre yay e
# paru — não são as mesmas flags nos dois. yay: --cleanmenu=false
# --diffmenu=false. paru não tem equivalente a --cleanmenu; --skipreview
# cobre o --diffmenu. --removemake existe com o mesmo nome nos dois.
_aur_noninteractive_flags() {
    if [[ "$1" == "paru" ]]; then
        echo "--skipreview --removemake"
    else
        echo "--cleanmenu=false --diffmenu=false --removemake"
    fi
}

aur_install() {
    local helper; helper="$(aur_detect_helper)"
    command -v "$helper" >/dev/null 2>&1 || { err "'$helper' não encontrado. Instale o helper AUR antes de continuar."; return 1; }
    local flags; read -ra flags <<< "$(_aur_noninteractive_flags "$helper")"
    "$helper" -S --needed "${flags[@]}" "$1"
}

aur_install_batch() {
    local helper; helper="$(aur_detect_helper)"
    command -v "$helper" >/dev/null 2>&1 || { err "'$helper' não encontrado. Instale o helper AUR antes de continuar."; return 1; }
    local pkgs=("$@")
    (( ${#pkgs[@]} )) || return 0
    local flags; read -ra flags <<< "$(_aur_noninteractive_flags "$helper")"
    "$helper" -S --needed "${flags[@]}" "${pkgs[@]}"
}

aur_upgrade() {
    local helper; helper="$(aur_detect_helper)"
    command -v "$helper" >/dev/null 2>&1 || { err "'$helper' não encontrado. Instale o helper AUR antes de continuar."; return 1; }
    "$helper" -Syu --aur
}

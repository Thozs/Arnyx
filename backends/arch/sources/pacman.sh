#!/usr/bin/env bash
# backends/arch/sources/pacman.sh — repositórios oficiais do Arch.
#
# is_installed/remove/list_explicit ficam em src/core.sh, não aqui — falam
# com o banco LOCAL do pacman, que enxerga pacotes do AUR também.

pacman_available() {
    pacman -Si "$1" &>/dev/null
}

pacman_search() {
    LC_ALL=C pacman -Ss "$1" 2>/dev/null | awk '
        /^[a-zA-Z0-9_.+-]+\// {
            split($1, a, "/"); name = a[2]
            d = ""
            if ((getline d) > 0) sub(/^[ \t]+/, "", d)
            printf "pacman\t%s\t%s\n", name, d
        }
    '
}

pacman_install() {
    sudo pacman -S --needed "$1"
}

pacman_install_batch() {
    local pkgs=("$@")
    (( ${#pkgs[@]} )) || return 0
    sudo pacman -S --needed "${pkgs[@]}"
}

pacman_upgrade() {
    sudo pacman -Syu
}

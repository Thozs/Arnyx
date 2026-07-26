#!/usr/bin/env bash
# backends/arch/sources/pacman.sh
#
# Fonte: repositórios oficiais do Arch, via pacman.
#
# Contrato per-source (fala com o catálogo REMOTO do pacman):
#   pacman_available(pkg)        -> exit 0/1
#   pacman_search(termo)         -> stdout: "pacman\tnome\tdescrição" por linha
#   pacman_install(pkg)          -> exit 0/!=0
#   pacman_install_batch(pkgs...)-> exit 0/!=0
#   pacman_upgrade()             -> exit 0/!=0
#
# is_installed / remove / list_explicit NÃO estão aqui de propósito:
# são genéricos (falam com o banco LOCAL do pacman, que enxerga pacotes
# do AUR também) e continuam em src/core.sh. Ver backends/arch/arch.sh
# e o item 18 da interface pra a explicação completa dessa divisão.

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

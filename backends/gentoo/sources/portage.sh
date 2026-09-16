#!/usr/bin/env bash
# backends/gentoo/sources/portage.sh — árvore principal do Gentoo (Portage).
#
# Upgrade padrão: emerge --sync + emerge -avuDN @world. Não tenta
# detectar mudanças de CFLAGS/CHOST (o Portage também não detecta
# isso sozinho) — só USE flags, via --newuse, que é rastreado por
# pacote de verdade. Rebuild completo (emerge -e @world) fica de fora
# do escopo por enquanto: se precisar, rode manualmente.

portage_available() {
    emerge -s "^$1\$" 2>/dev/null | grep -q '^\*'
}

portage_search() {
    local term="$1"
    emerge -s "$term" 2>/dev/null | awk -v mgr="pacman" '
        /^\*/ {
            name = $2
            desc = ""
            getline d
            if (d ~ /^ {2,}/) { sub(/^[ \t]+/, "", d); desc = d }
            printf "%s\t%s\t%s\n", mgr, name, desc
        }
    '
}

portage_install() {
    sudo emerge --ask=n "$1"
}

portage_install_batch() {
    local pkgs=("$@")
    (( ${#pkgs[@]} )) || return 0
    sudo emerge --ask=n "${pkgs[@]}"
}

portage_upgrade() {
    sudo emerge --sync
    sudo emerge --ask=n --verbose --update --deep --newuse @world
}

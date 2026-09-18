#!/usr/bin/env bash
# backends/gentoo/sources/portage.sh — árvore principal do Gentoo (Portage).
#
# Usa `qsearch` (app-portage/portage-utils, já exigido pro qlist/qdepends)
# em vez de `emerge -s`: o qsearch é bem mais rápido e devolve uma linha
# por pacote ("categoria/nome: descrição"), enquanto o emerge -s tem
# formato multi-linha pensado pra humano (frágil de parsear) e em
# algumas versões nem mostra pacotes mascarados por keyword na busca —
# então "não encontrado" e "mascarado" ficavam indistinguíveis.
#
# Upgrade padrão: emerge --sync + emerge -avuDN @world. Não tenta
# detectar mudanças de CFLAGS/CHOST (o Portage também não detecta
# isso sozinho) — só USE flags, via --newuse, que é rastreado por
# pacote de verdade. Rebuild completo (emerge -e @world) fica de fora
# do escopo por enquanto: se precisar, rode manualmente.

# Remove sequências de cor ANSI, caso o qsearch as emita mesmo sem tty.
_portage_strip_color() { sed 's/\x1b\[[0-9;]*m//g'; }

portage_available() {
    local pkg="$1"
    command -v qsearch >/dev/null 2>&1 || { warn "qsearch não encontrado (pacote app-portage/portage-utils)."; return 1; }
    qsearch "$pkg" 2>/dev/null | _portage_strip_color | awk -F': ' -v p="$pkg" '
        NF>=2 { n=$1; sub(/.*\//, "", n); if (n == p) { found=1; exit } }
        END { exit !found }
    '
}

portage_search() {
    local term="$1"
    command -v qsearch >/dev/null 2>&1 || return 0
    qsearch "$term" 2>/dev/null | _portage_strip_color | awk -F': ' -v mgr="pacman" '
        NF>=2 {
            n=$1; sub(/.*\//, "", n)
            desc=$0; sub(/^[^:]*: /, "", desc)
            printf "%s\t%s\t%s\n", mgr, n, desc
        }
    '
}

portage_install() {
    local pkg="$1"
    local log; log="$(mktemp)"

    # tee pra tela E pra arquivo: output streaming ao vivo (compilação
    # visível conforme acontece), e ainda dá pra grepar "have been
    # masked" no fim sem depender só do exit code.
    sudo emerge --ask=n "$pkg" 2>&1 | tee "$log"
    local status="${PIPESTATUS[0]}"

    local masked=0
    if (( status != 0 )) && grep -q "have been masked" "$log"; then
        masked=1
    fi
    rm -f "$log"

    (( masked )) && return 2
    (( status == 130 )) && return 3   # SIGINT (Ctrl+C) — não é falha real
    return "$status"
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

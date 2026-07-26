#!/usr/bin/env bash
# backends/arch/arch.sh — dispatch: decide pacman vs aur, chama a função certa.
# "yay" é o nome da seção no .conf do usuário (não muda); "aur" é o vocabulário
# interno do código.

ARCH_SOURCES=(pacman aur)

_install_pkg() {
    local manager="$1" pkg="$2"
    if [[ "$manager" == "pacman" ]]; then
        pacman_install "$pkg" && return 0
    else
        aur_install "$pkg" && return 0
    fi

    warn "Instalação de '$pkg' falhou. Removendo do .conf..."
    _remove_from_conf "$pkg"
    err "'$pkg' não foi encontrado ou houve erro. Nome removido da lista."
    return 1
}

_install_batch() {
    local manager="$1"; shift
    local pkgs=("$@")
    (( ${#pkgs[@]} )) || return 0

    if [[ "$manager" == "pacman" ]]; then
        pacman_install_batch "${pkgs[@]}" && return 0
    else
        aur_install_batch "${pkgs[@]}" && return 0
    fi

    warn "Instalação em lote falhou, tentando pacote a pacote pra achar o culpado..."
    local pkg
    for pkg in "${pkgs[@]}"; do
        pacman -Q "$pkg" &>/dev/null || _install_pkg "$manager" "$pkg" || true
    done
}

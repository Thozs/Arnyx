#!/usr/bin/env bash
# backends/arch/sources/aur.sh — AUR, via helper (yay hoje; paru é item 3 do
# roadmap). aur_detect_helper() é o único lugar que muda quando paru entrar.
#
# is_installed/remove/list_explicit ficam em src/core.sh (ver pacman.sh).

aur_detect_helper() {
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
    LC_ALL=C "$helper" -Ssa "$1" 2>/dev/null | awk '
        /^aur\// {
            split($1, a, "/"); name = a[2]
            d = ""
            if ((getline d) > 0) sub(/^[ \t]+/, "", d)
            printf "yay\t%s\t%s\n", name, d
        }
    '
}

aur_install() {
    local helper; helper="$(aur_detect_helper)"
    command -v "$helper" >/dev/null 2>&1 || { err "'$helper' não encontrado. Instale o helper AUR antes de continuar."; return 1; }
    "$helper" -S --needed --cleanmenu=false --diffmenu=false --removemake "$1"
}

aur_install_batch() {
    local helper; helper="$(aur_detect_helper)"
    command -v "$helper" >/dev/null 2>&1 || { err "'$helper' não encontrado. Instale o helper AUR antes de continuar."; return 1; }
    local pkgs=("$@")
    (( ${#pkgs[@]} )) || return 0
    "$helper" -S --needed --cleanmenu=false --diffmenu=false --removemake "${pkgs[@]}"
}

aur_upgrade() {
    local helper; helper="$(aur_detect_helper)"
    command -v "$helper" >/dev/null 2>&1 || { err "'$helper' não encontrado. Instale o helper AUR antes de continuar."; return 1; }
    "$helper" -Syu --aur
}

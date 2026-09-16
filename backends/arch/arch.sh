#!/usr/bin/env bash
# backends/arch/arch.sh — dispatch: decide pacman vs aur, chama a função certa.
# "yay" é o nome da seção no .conf do usuário (não muda); "aur" é o vocabulário
# interno do código.

ARCH_SOURCES=(pacman aur)

PKG_DB_PATH="/var/lib/pacman/local"

backend_check_available() { command -v pacman >/dev/null 2>&1; }
backend_unavailable_msg() { echo "Isso não é um sistema Arch-based (pacman não encontrado)."; }

# Nomes genéricos que core.sh chama sempre (independente de manager
# escolhido) — aqui só apontam pras funções pacman_*/aur_* que já
# existem em sources/{pacman,aur}.sh.
primary_available()   { pacman_available "$@"; }
primary_search()      { pacman_search "$@"; }
primary_upgrade()     { pacman_upgrade "$@"; }
secondary_available() { aur_available "$@"; }
secondary_search()    { aur_search "$@"; }
secondary_upgrade()   { aur_upgrade "$@"; }

# Preenche INSTALLED_SET/INSTALLED_VER/EXPLICIT_SET a partir de
# `pacman -Qi` — parsing idêntico ao que core.sh fazia inline antes.
backend_populate_installed() {
    local name="" ver="" reason=""
    while IFS= read -r line; do
        case "$line" in
            Name*)              name="${line#*: }" ;;
            Version*)           ver="${line#*: }"  ;;
            "Install Reason"*)  reason="${line#*: }" ;;
            "")
                if [[ -n "$name" ]]; then
                    INSTALLED_SET["$name"]=1
                    INSTALLED_VER["$name"]="$ver"
                    [[ "$reason" == Explicitly* ]] && EXPLICIT_SET["$name"]=1
                fi
                name=""; ver=""; reason=""
                ;;
        esac
    done < <(LC_ALL=C pacman -Qi)
    # o último pacote da lista não tem linha em branco depois dele
    if [[ -n "$name" ]]; then
        INSTALLED_SET["$name"]=1
        INSTALLED_VER["$name"]="$ver"
        [[ "$reason" == Explicitly* ]] && EXPLICIT_SET["$name"]=1
    fi
}

# Pacotes "estrangeiros" (instalados via AUR/manual) — usado pelo
# `manage` pra rotular corretamente pacotes soltos.
backend_foreign_list() { LC_ALL=C pacman -Qmq 2>/dev/null; }

pkg_installed_now() { pacman -Q "$1" &>/dev/null; }
pkg_remove()        { sudo pacman -Rns "$1"; }
pkg_remove_force()  { sudo pacman -Rns --noconfirm "$1"; }

pkg_install_reason() {
    LC_ALL=C pacman -Qi "$1" 2>/dev/null | awk -F': ' '/^Install Reason/{print $2; exit}'
}

pkg_reverse_deps() {
    command -v pactree &>/dev/null || return 1
    pactree -r "$1" 2>/dev/null | tail -n +2
}

pkg_reverse_deps_tool_hint() {
    echo "pactree não encontrado (pacote pacman-contrib). Instale pra ver quem depende dele: arn install pacman-contrib"
}

pkg_unmask() {
    die "'arn unmask' não se aplica ao Arch — pacman não tem o conceito de mask/unmask do Portage."
}

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

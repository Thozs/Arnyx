#!/usr/bin/env bash
# backends/arch/arch.sh
#
# Glue do distro Arch: declara quais sources existem e traduz o nome de
# "manager" usado no .conf/no resto do código ("pacman" / "yay") pra
# chamada da função per-source certa (pacman_* ou aur_*).
#
# Nota: "yay" aqui é o nome da SEÇÃO no .conf do usuário (não muda, por
# compatibilidade) — o vocabulário interno da fonte é "aur" (ver
# backends/arch/sources/aur.sh).
#
# Este arquivo não dá `source` em sources/pacman.sh e sources/aur.sh
# porque nunca roda sozinho: tools/build-arn.sh concatena os três (mais
# src/core.sh) num `bin/arn` final. Ordem de concatenação é só por
# legibilidade (camadas de baixo pra cima) — bash não exige ordem entre
# definições de função, só que elas existam antes de serem chamadas, e
# isso só acontece no `case` de dispatch no fim do core.sh.

ARCH_SOURCES=(pacman aur)

# Retorna 0 se instalou, 1 se falhou (e removeu do .conf).
# Comportamento idêntico ao _install_pkg original — só troca a chamada
# direta a pacman/yay pela função per-source correspondente.
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

# Muito mais rápido (1 sync do pacman/yay em vez de N) e só pede
# a senha do sudo uma vez. Se o lote falhar, cai pro modo
# individual só para identificar e limpar o(s) pacote(s) ruim(ns).
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

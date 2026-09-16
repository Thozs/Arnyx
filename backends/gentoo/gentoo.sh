#!/usr/bin/env bash
# backends/gentoo/gentoo.sh — dispatch e funções genéricas do backend
# Gentoo/Portage. Diferente do Arch, não existe uma segunda fonte de
# pacotes tipo AUR aqui — só o Portage. As funções secondary_* existem
# só pra manter a mesma interface que core.sh espera; a seção [yay] do
# .conf fica sempre vazia no Gentoo (reservada pra um eventual suporte
# a overlays no futuro).
#
# Pré-requisito no sistema: app-portage/portage-utils (dá o `qlist` e
# o `qdepends` usados abaixo) — equivalente ao pacman-contrib no Arch.
#   sudo emerge --ask=n app-portage/portage-utils

GENTOO_SOURCES=(portage)

PKG_DB_PATH="/var/db/pkg"

backend_check_available() { command -v emerge >/dev/null 2>&1; }
backend_unavailable_msg() { echo "Isso não é um sistema Gentoo (emerge não encontrado)."; }

_install_pkg() {
    local manager="$1" pkg="$2"
    if [[ "$manager" == "pacman" ]]; then
        portage_install "$pkg" && return 0
    else
        warn "Seção '[$manager]' não é suportada no backend Gentoo (só existe [pacman], que aqui significa Portage). Pulando '$pkg'."
        return 1
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
        portage_install_batch "${pkgs[@]}" && return 0
    else
        warn "Seção '[$manager]' não é suportada no backend Gentoo. Pulando: ${pkgs[*]}"
        return 0
    fi

    warn "Instalação em lote falhou, tentando pacote a pacote pra achar o culpado..."
    local pkg
    for pkg in "${pkgs[@]}"; do
        pkg_installed_now "$pkg" || _install_pkg "$manager" "$pkg" || true
    done
}

primary_available()   { portage_available "$@"; }
primary_search()      { portage_search "$@"; }
primary_upgrade()     { portage_upgrade "$@"; }

# Sem fonte secundária no Gentoo — sempre "não encontrado"/"nada a fazer".
secondary_available() { return 1; }
secondary_search()    { :; }
secondary_upgrade()   { :; }
aur_detect_helper()   { echo ""; }

backend_foreign_list() { :; }  # sem conceito de "estrangeiro" (AUR) no Gentoo

# Preenche INSTALLED_SET/INSTALLED_VER/EXPLICIT_SET a partir do
# `qlist -Iv` (formato "categoria/nome-versão", uma linha por pacote)
# cruzado com /var/lib/portage/world pra saber o que foi instalado
# explicitamente (equivalente ao Install Reason do pacman).
backend_populate_installed() {
    command -v qlist >/dev/null 2>&1 || { warn "qlist não encontrado (pacote app-portage/portage-utils). Instale: sudo emerge --ask=n app-portage/portage-utils"; return; }

    declare -A world_set=()
    if [[ -f /var/lib/portage/world ]]; then
        local w
        while IFS= read -r w; do
            [[ -n "$w" && "$w" != \#* ]] && world_set["$w"]=1
        done < /var/lib/portage/world
    fi

    local line cat_pkg ver name
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        # "categoria/nome-versao(-rN)?" — captura gulosa garante que
        # pega o ÚLTIMO "-<digito>..." como início da versão, mesmo
        # com revisão (-r1) ou hífens no nome do pacote.
        if [[ "$line" =~ ^(.+)-([0-9][0-9A-Za-z_.]*(-r[0-9]+)?)$ ]]; then
            cat_pkg="${BASH_REMATCH[1]}"
            ver="${BASH_REMATCH[2]}"
        else
            continue
        fi
        name="${cat_pkg#*/}"
        INSTALLED_SET["$name"]=1
        INSTALLED_VER["$name"]="$ver"
        if [[ -n "${world_set[$cat_pkg]:-}" || -n "${world_set[$name]:-}" ]]; then
            EXPLICIT_SET["$name"]=1
        fi
    done < <(qlist -Iv 2>/dev/null)
}

pkg_installed_now() {
    command -v qlist >/dev/null 2>&1 || return 1
    [[ -n "$(qlist -Ie "$1" 2>/dev/null)" ]]
}

pkg_remove()       { sudo emerge --ask --depclean "$1"; }
pkg_remove_force() { sudo emerge --ask=n --quiet --depclean "$1"; }

pkg_install_reason() {
    local pkg="$1"
    if grep -qE "(^|/)${pkg}(:|$)" /var/lib/portage/world 2>/dev/null; then
        echo "Explicitly installed"
    else
        echo "Installed as a dependency"
    fi
}

pkg_reverse_deps() {
    command -v qdepends &>/dev/null || return 1
    qdepends -C -N -Q "$1" 2>/dev/null
}

pkg_reverse_deps_tool_hint() {
    echo "qdepends não encontrado (pacote app-portage/portage-utils). Instale pra ver quem depende dele: sudo emerge --ask=n app-portage/portage-utils"
}

# Desmascara SÓ o(s) pacote(s) passado(s) — nunca o sistema todo.
# Usa emerge --autounmask-write, que grava em /etc/portage/package.*
# (accept_keywords pra ~arch keyword, unmask pra mask de verdade em
# profiles/package.mask). Registra pacote+motivo+data num log separado
# em texto simples (não mexe no /etc/portage sem já mostrar o motivo
# e pedir confirmação antes).
UNMASK_LOG="${XDG_STATE_HOME:-$HOME/.local/state}/arnyx/gentoo-unmasked.log"

pkg_unmask() {
    local pkg="$1"
    header "Unmask — $pkg"

    if emerge --pretend "$pkg" &>/dev/null; then
        ok "'$pkg' já não está mascarado — nada a fazer."
        return 0
    fi

    info "Verificando o motivo do mask..."
    local reason
    reason="$(emerge --pretend --autounmask=y "$pkg" 2>&1 | grep -E 'masked by|keyword changes are necessary|^\[ebuild' | head -n 6)"

    if [[ -z "$reason" ]]; then
        err "Não consegui determinar o motivo (nome errado ou erro do emerge). Rode manualmente: emerge --pretend --autounmask=y $pkg"
        return 1
    fi

    echo -e "\n${BOLD}Motivo do mask:${NC}"
    echo "$reason" | sed 's/^/  /'
    echo

    local reply
    read -r -p "$(echo -e "${YELLOW}?${NC} Desmascarar '$pkg'? Isso grava em /etc/portage/package.* (só esse pacote). [s/N] ")" reply
    [[ "$reply" =~ ^[sS]$ ]] || { info "Cancelado — '$pkg' continua mascarado."; return 0; }

    if sudo emerge --ask=n --autounmask=y --autounmask-write "$pkg"; then
        ok "'$pkg' desmascarado."
        mkdir -p "$(dirname "$UNMASK_LOG")"
        {
            printf '%s | %s | %s\n' \
                "$(date '+%Y-%m-%d %H:%M:%S')" \
                "$pkg" \
                "$(echo "$reason" | tr '\n' ' ' | sed 's/  */ /g')"
        } >> "$UNMASK_LOG"
        info "Registrado em: $UNMASK_LOG"
        warn "Se o emerge avisou sobre arquivos em /etc/portage pra revisar, rode: sudo etc-update (ou dispatch-conf)"
        info "Depois: arn install $pkg"
    else
        err "Falha ao desmascarar '$pkg'. Nada foi registrado no log."
        return 1
    fi
}

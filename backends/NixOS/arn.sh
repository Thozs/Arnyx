#!/usr/bin/env bash
# ============================================================
#  arn — Arnyx (porte NixOS)
#  Gerenciador declarativo de pacotes para NixOS via nixpkgs.
#  Edita modules/packages.nix e chama nixos-rebuild.
# ============================================================

set -uo pipefail

NIXOS_DIR="/etc/nixos"
PKGFILE="$NIXOS_DIR/modules/packages.nix"
FLAKE_TARGET="$NIXOS_DIR#nixos"
STATE_DIR="/var/lib/arnyx"
LAST_APPLIED="$STATE_DIR/packages.nix.last-applied"

RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[1;33m'
BLUE=$'\033[0;34m'; CYAN=$'\033[0;36m'; BOLD=$'\033[1m'; NC=$'\033[0m'

info()   { echo -e "${CYAN}::${NC} $*"; }
ok()     { echo -e "${GREEN}✓${NC} $*"; }
warn()   { echo -e "${YELLOW}⚠${NC}  $*"; }
err()    { echo -e "${RED}✗${NC}  $*" >&2; }
header() { echo -e "\n${BOLD}${BLUE}══ $* ══${NC}"; }
die()    { err "$*"; exit 1; }

command -v nixos-rebuild >/dev/null 2>&1 || die "nixos-rebuild não encontrado — isso não parece ser um sistema NixOS."
[[ "$EUID" -ne 0 ]] || die "Não rode o arn diretamente como root — ele chama sudo sozinho quando precisa."
[[ -f "$PKGFILE" ]] || die "Não encontrei $PKGFILE — ajuste NIXOS_DIR no script se sua estrutura for diferente."

# ── Leitura/escrita de packages.nix ─────────────────────────
# O arquivo é root:root — leitura direta funciona (644 padrão),
# escrita sempre passa por sudo tee, nunca edita em memória como root.

_read_pkgfile() { cat "$PKGFILE" 2>/dev/null || sudo cat "$PKGFILE"; }

# Extrai só os nomes de pacote da lista (ignora comentários e chaves)
_declared_pkgs() {
    _read_pkgfile | awk '
        /environment\.systemPackages/ { insec=1; next }
        insec && /\]/ { insec=0; next }
        insec {
            line=$0
            sub(/#.*/, "", line)
            gsub(/^[ \t]+|[ \t]+$/, "", line)
            if (line != "") print line
        }
    '
}

_pkg_declared() { _declared_pkgs | grep -qx "$1"; }

# Insere pkg antes do "];" que fecha a lista de systemPackages.
_add_to_pkgfile() {
    local pkg="$1" tmp
    tmp="$(mktemp)"
    _read_pkgfile | awk -v pkg="$pkg" '
        /environment\.systemPackages/ { insec=1 }
        insec && /^\s*\];/ && !done { print "    " pkg; done=1 }
        { print }
    ' > "$tmp"
    sudo cp "$tmp" "$PKGFILE"
    rm -f "$tmp"
}

_remove_from_pkgfile() {
    local pkg="$1" tmp
    tmp="$(mktemp)"
    _read_pkgfile | awk -v pkg="$pkg" '
        {
            line=$0
            trimmed=line
            sub(/#.*/, "", trimmed)
            gsub(/^[ \t]+|[ \t]+$/, "", trimmed)
            if (trimmed == pkg) next
            print
        }
    ' > "$tmp"
    sudo cp "$tmp" "$PKGFILE"
    rm -f "$tmp"
}

_pkg_exists_in_nixpkgs() {
    local pkg="$1"
    nix search nixpkgs "^${pkg}$" --json 2>/dev/null | grep -q "\"legacyPackages\..*\.${pkg}\""
}

_mark_applied() {
    sudo mkdir -p "$STATE_DIR"
    sudo cp "$PKGFILE" "$LAST_APPLIED"
}

# ── Comandos ─────────────────────────────────────────────────

cmd_install() {
    (( $# )) || die "Uso: install <pacote> [pacote2 ...]"
    local pkg
    for pkg in "$@"; do
        if _pkg_declared "$pkg"; then
            warn "'$pkg' já está declarado em packages.nix"
            continue
        fi
        info "Verificando '$pkg' no nixpkgs..."
        if ! _pkg_exists_in_nixpkgs "$pkg"; then
            err "'$pkg' não encontrado no nixpkgs (nome exato). Confira com: arn search $pkg"
            continue
        fi
        _add_to_pkgfile "$pkg"
        ok "Adicionado '$pkg' em packages.nix"
    done
    info "Rode 'arn rebuild' pra aplicar."
}

cmd_remove() {
    (( $# )) || die "Uso: remove <pacote> [pacote2 ...]"
    local pkg
    for pkg in "$@"; do
        if ! _pkg_declared "$pkg"; then
            warn "'$pkg' não está declarado em packages.nix"
            continue
        fi
        _remove_from_pkgfile "$pkg"
        ok "Removido '$pkg' de packages.nix"
    done
    info "Rode 'arn rebuild' pra aplicar."
}

cmd_list() {
    header "Pacotes declarados em $PKGFILE"
    _declared_pkgs | sort | sed 's/^/  /'
    echo
}

cmd_diff() {
    header "Diff — packages.nix atual vs última aplicação (rebuild)"
    if [[ ! -f "$LAST_APPLIED" ]]; then
        warn "Nenhuma geração aplicada via arn ainda. Rode 'arn rebuild' ao menos uma vez."
        return
    fi
    local d
    d="$(diff -u <(awk '{print}' "$LAST_APPLIED") <(_read_pkgfile) 2>/dev/null | grep -E '^[+-]' | grep -Ev '^(\+\+\+|---)' || true)"
    if [[ -n "$d" ]]; then
        echo "$d" | sed \
            -e "s/^-/  ${RED}-${NC} /" \
            -e "s/^+/  ${GREEN}+${NC} /"
        echo
        warn "packages.nix mudou desde o último rebuild aplicado. Rode 'arn rebuild' pra aplicar."
    else
        ok "packages.nix idêntico à última aplicação."
    fi
}

cmd_edit() {
    sudo -e "$PKGFILE" 2>/dev/null || sudo "${EDITOR:-nano}" "$PKGFILE"
    info "Rode 'arn rebuild' pra aplicar as mudanças."
}

cmd_rebuild() {
    local dry=0
    [[ "${1:-}" == "--dry-run" || "${1:-}" == "-n" ]] && dry=1

    if (( dry )); then
        header "Rebuild (dry-run) — nada será aplicado"
        sudo nixos-rebuild dry-build --flake "$FLAKE_TARGET"
        return
    fi

    header "Rebuild — sudo nixos-rebuild switch --flake $FLAKE_TARGET"
    if sudo nixos-rebuild switch --flake "$FLAKE_TARGET"; then
        _mark_applied
        ok "Rebuild concluído!"
    else
        err "Rebuild falhou. packages.nix NÃO foi marcado como aplicado."
        return 1
    fi
}

# sync existe só por costume — no Nix não tem "instala sem remover
# órfão" separado de "aplica tudo", então sync = rebuild.
cmd_sync() { cmd_rebuild "$@"; }

cmd_upgrade() {
    header "Upgrade — nix flake update"
    (cd "$NIXOS_DIR" && sudo nix flake update)
    info "flake.lock atualizado. Rode 'arn rebuild' pra aplicar as novas versões."
}

cmd_search() {
    (( $# )) || die "Uso: search <termo>"
    command -v fzf >/dev/null 2>&1 || die "fzf não encontrado."
    local term="$*"
    info "Buscando '$term' no nixpkgs (pode demorar na primeira vez)..."

    local results
    results="$(nix search nixpkgs "$term" 2>/dev/null)"
    [[ -n "$results" ]] || { warn "Nada encontrado pra '$term'."; return; }

    # Formato do nix search: "* legacyPackages.x86_64-linux.NOME (versao)\n  descrição"
    local lines=() name desc
    while IFS= read -r l1 && IFS= read -r l2; do
        name="$(sed -E 's/^\* legacyPackages\.[^.]+\.([^ ]+).*/\1/' <<< "$l1")"
        desc="$(sed -E 's/^[ \t]+//' <<< "$l2")"
        [[ -n "$name" ]] && lines+=("$(printf '%-30s %s' "$name" "$desc")")
    done <<< "$results"

    (( ${#lines[@]} )) || { warn "Nada encontrado pra '$term'."; return; }

    local chosen
    chosen=$(printf '%s\n' "${lines[@]}" | fzf --multi --header 'TAB/espaço: marca vários • Enter: instala • ESC: cancela')
    [[ -z "$chosen" ]] && { info "Cancelado."; return; }

    local pkgs=()
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        pkgs+=("$(awk '{print $1}' <<< "$line")")
    done <<< "$chosen"

    (( ${#pkgs[@]} )) && cmd_install "${pkgs[@]}"
}

# Menu fzf: A adiciona (busca + valida no nixpkgs), D remove os marcados.
cmd_manage() {
    command -v fzf >/dev/null 2>&1 || die "fzf não encontrado."

    local declared=()
    mapfile -t declared < <(_declared_pkgs | sort)
    (( ${#declared[@]} )) || warn "Nenhum pacote declarado ainda."

    local raw
    raw=$(printf '%s\n' "${declared[@]}" | fzf \
        --multi \
        --header 'TAB/espaço: marca vários • D: remove marcados • A: adiciona novo(s) • ESC: cancela' \
        --bind 'space:toggle' \
        --expect='D,A')

    [[ -z "$raw" ]] && { info "Cancelado."; return; }

    local key; key=$(head -n1 <<< "$raw")
    local chosen=(); mapfile -t chosen < <(tail -n +2 <<< "$raw")

    case "$key" in
        D)
            (( ${#chosen[@]} )) || { warn "Nenhum pacote marcado."; return; }
            cmd_remove "${chosen[@]}"
            ;;
        A)
            local reply
            read -r -p "$(echo -e "${YELLOW}?${NC} Nome(s) do(s) pacote(s) a adicionar (separados por espaço): ")" reply
            [[ -n "$reply" ]] || { info "Nada digitado."; return; }
            # shellcheck disable=SC2206
            local reply_arr=($reply)
            cmd_install "${reply_arr[@]}"
            ;;
        *)
            info "Nenhuma ação escolhida (use D pra remover ou A pra adicionar)."
            ;;
    esac
}

cmd_rollback() {
    local target="${1:-}"

    if [[ -z "$target" ]]; then
        command -v fzf >/dev/null 2>&1 || die "fzf não encontrado. Informe o número direto: arn rollback <N>"

        local lines
        lines="$(sudo nixos-rebuild list-generations 2>/dev/null)"
        [[ -n "$lines" ]] || die "Não consegui listar gerações."

        local chosen
        chosen=$(echo "$lines" | fzf --header 'Geração pra restaurar (ESC cancela) — mostra a atual marcada' --header-lines=1)
        [[ -z "$chosen" ]] && { info "Cancelado."; return; }
        target="$(awk '{print $1}' <<< "$chosen")"
    fi

    [[ "$target" =~ ^[0-9]+$ ]] || die "Geração inválida: $target"

    header "Rollback → geração $target"
    warn "Isso troca o sistema INTEIRO pra geração $target (não só a lista de pacotes)."
    local reply
    read -r -p "$(echo -e "${YELLOW}?${NC} Confirma? [s/N] ")" reply
    [[ "$reply" =~ ^[sS]$ ]] || { info "Cancelado."; return; }

    sudo nix-env --profile /nix/var/nix/profiles/system --switch-generation "$target" \
        && sudo /nix/var/nix/profiles/system/bin/switch-to-configuration switch \
        && ok "Sistema restaurado pra geração $target." \
        || err "Rollback falhou."
}

# ── Aliases fish ─────────────────────────────────────────────
_aliases_pairs() {
    local marker='${BOLD}ALIASES FISH${NC}'
    awk -v marker="$marker" '
        $0 == marker { capture=1; next }
        capture && /^[[:space:]]*$/ { exit }
        capture && /→/ {
            line=$0
            sub(/^[ \t]+/, "", line)
            n=split(line, parts, /[ \t]+→[ \t]+/)
            if (n==2) print parts[1] ":" parts[2]
        }
    ' "$0"
}

_aliases_render() {
    local pairs="$1" name cmd
    echo "# Gerado por 'arn aliases install' — não edite direto."
    while IFS=: read -r name cmd; do
        [[ -z "$name" ]] && continue
        echo "alias $name '$cmd'"
    done <<< "$pairs"
}

_aliases_install() {
    command -v fish >/dev/null 2>&1 || die "fish não encontrado."
    local target="${XDG_CONFIG_HOME:-$HOME/.config}/fish/conf.d/arnyx-aliases.fish"
    local pairs; pairs="$(_aliases_pairs)"
    [[ -n "$pairs" ]] || die "Não consegui extrair os aliases do próprio script."
    local expected; expected="$(_aliases_render "$pairs")"

    mkdir -p "$(dirname "$target")"
    if [[ -f "$target" ]] && diff -q <(echo "$expected") "$target" &>/dev/null; then
        info "Aliases já instalados e atualizados."
        return
    fi
    echo "$expected" > "$target"
    ok "Aliases instalados em: $target"
    info "Abra um terminal novo (ou rode: source $target) pra usar."
}

cmd_aliases() {
    case "${1:-}" in
        install) _aliases_install ;;
        *) die "Uso: arn aliases install" ;;
    esac
}

usage() {
cat << EOF
${BOLD}arn${NC} — Arnyx, gerenciador declarativo de pacotes para NixOS (nixpkgs)

${BOLD}COMANDOS${NC}
  install <pkg>           Valida no nixpkgs, adiciona em packages.nix
  remove <pkg>             Remove de packages.nix
  search <termo>           Busca no nixpkgs, menu fzf pra instalar direto
  manage                   Menu fzf: adiciona (A) / remove (D) pacotes
  sync                     Alias de rebuild
  rebuild                  sudo nixos-rebuild switch --flake $FLAKE_TARGET
  rebuild --dry-run        Mostra o que mudaria, sem aplicar (dry-build)
  upgrade                  nix flake update (atualiza flake.lock)
  list                     Lista pacotes declarados
  diff                     Mudanças em packages.nix desde o último rebuild aplicado
  edit                     Abre packages.nix no \$EDITOR (via sudo)
  rollback                 Menu fzf com as gerações do sistema (rollback real)
  rollback <N>             Restaura a geração N direto
  aliases install          Instala os aliases automaticamente (fish, via conf.d)

${BOLD}ALIASES FISH${NC}
  arni                    → arn install
  arnrm                   → arn remove
  arns                    → arn sync
  arnr                    → arn rebuild
  arnu                    → arn upgrade
  arnl                    → arn list
  arnd                    → arn diff
  arne                    → arn edit
  arnf                    → arn search
  arnm                    → arn manage
  arnrb                   → arn rollback

${BOLD}PACKAGES.NIX${NC}: $PKGFILE
${BOLD}FLAKE TARGET${NC}: $FLAKE_TARGET
EOF
}

case "${1:-help}" in
    install)  shift; cmd_install "$@" ;;
    remove)   shift; cmd_remove "$@" ;;
    search)   shift; cmd_search "$@" ;;
    manage)   shift; cmd_manage "$@" ;;
    sync)     shift; cmd_sync "$@" ;;
    rebuild)  shift; cmd_rebuild "$@" ;;
    upgrade)  cmd_upgrade ;;
    list)     cmd_list ;;
    diff)     cmd_diff ;;
    edit)     cmd_edit ;;
    rollback) shift; cmd_rollback "$@" ;;
    aliases)  shift; cmd_aliases "$@" ;;
    help|-h|--help) usage ;;
    *) err "Comando desconhecido: $1"; usage; exit 1 ;;
esac

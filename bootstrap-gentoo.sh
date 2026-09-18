#!/usr/bin/env bash
# ============================================================
#  bootstrap-gentoo.sh — instala o Arnyx (arn) num sistema
#  Gentoo recém-instalado, e opcionalmente restaura um
#  packages.conf pessoal vindo de outro repositório (público
#  ou privado).
#
#  Uso:
#    # só instala o Arnyx, com .conf vazio
#    bash <(curl -fsSL https://raw.githubusercontent.com/Thozs/Arnyx/main/bootstrap-gentoo.sh)
#
#    # instala o Arnyx e restaura seu packages.conf pessoal
#    bash <(curl -fsSL https://raw.githubusercontent.com/Thozs/Arnyx/main/bootstrap-gentoo.sh) \
#         https://github.com/SEU_USUARIO/seu-repo-de-config.git
#
#  O repositório de config (2º caso) pode ser privado — o git vai
#  pedir autenticação normalmente (usuário + token) na hora do clone.
# ============================================================

set -euo pipefail

ARNYX_REPO="https://github.com/Thozs/Arnyx.git"
CONFIG_REPO="${1:-}"

RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[1;33m'
BLUE=$'\033[0;34m'; CYAN=$'\033[0;36m'; BOLD=$'\033[1m'; NC=$'\033[0m'

info()   { echo -e "${CYAN}::${NC} $*"; }
ok()     { echo -e "${GREEN}✓${NC} $*"; }
warn()   { echo -e "${YELLOW}⚠${NC}  $*"; }
err()    { echo -e "${RED}✗${NC}  $*" >&2; }
header() { echo -e "\n${BOLD}${BLUE}══ $* ══${NC}"; }
die()    { err "$*"; exit 1; }

header "Bootstrap do Arnyx (Gentoo)"

command -v emerge >/dev/null 2>&1 || die "Isso não é um sistema Gentoo (emerge não encontrado)."
[[ "$EUID" -ne 0 ]] || die "Não roda isso como root. O script usa sudo só quando precisa."

if [[ -n "$CONFIG_REPO" ]]; then
    msg="Vai instalar dev-vcs/git, app-portage/portage-utils, app-shells/fzf, instalar o Arnyx, e restaurar seu packages.conf de:\n   $CONFIG_REPO"
else
    msg="Vai instalar dev-vcs/git, app-portage/portage-utils, app-shells/fzf, e instalar o Arnyx com uma configuração vazia (sem restaurar pacotes)."
fi
echo -e "$msg"
read -rp "Continuar? [s/N] " confirm
[[ "$confirm" =~ ^[sS]$ ]] || { info "Cancelado."; exit 0; }

header "1/3 — Dependências base"
DEPS=()
command -v git    >/dev/null 2>&1 || DEPS+=(dev-vcs/git)
command -v qlist  >/dev/null 2>&1 || DEPS+=(app-portage/portage-utils)
command -v fzf    >/dev/null 2>&1 || DEPS+=(app-shells/fzf)

if (( ${#DEPS[@]} )); then
    info "Instalando: ${DEPS[*]}"
    sudo emerge --ask=n --quiet "${DEPS[@]}"
else
    ok "git, portage-utils e fzf já instalados."
fi

header "2/3 — Instalando o Arnyx"
tmp_arnyx="$(mktemp -d)"
git clone --depth 1 "$ARNYX_REPO" "$tmp_arnyx"
(cd "$tmp_arnyx" && ./tools/build-arn.sh --backend=gentoo)
sudo install -Dm755 "$tmp_arnyx/bin/arn" /usr/local/bin/arn
rm -rf "$tmp_arnyx"
ok "arn instalado em /usr/local/bin/arn"

header "3/3 — Configuração"
mkdir -p "$HOME/.config/arnyx"
conf_dst="$HOME/.config/arnyx/packages.conf"

if [[ -f "$conf_dst" ]]; then
    warn "Já existe um packages.conf em $conf_dst — não sobrescrevendo."
elif [[ -n "$CONFIG_REPO" ]]; then
    info "Clonando repositório de configuração..."
    tmp_conf="$(mktemp -d)"
    git clone --depth 1 "$CONFIG_REPO" "$tmp_conf"
    conf_src="$(find "$tmp_conf" -name packages.conf | head -n1)"
    [[ -n "$conf_src" ]] || die "Não encontrei packages.conf dentro de $CONFIG_REPO"
    cp "$conf_src" "$conf_dst"
    rm -rf "$tmp_conf"
    ok "packages.conf restaurado de $CONFIG_REPO"
    info "Sincronizando pacotes declarados..."
    arn sync
else
    arn init
    info "Nenhum repositório de config informado — .conf vazio criado."
    info "Use 'arn manage' ou 'arn install <pkg>' pra começar a declarar pacotes."
fi

echo
ok "Bootstrap concluído! Roda 'arn diff' pra conferir o estado atual."

#!/usr/bin/env bash
# ============================================================
#  bootstrap.sh — instala o Arnyx (arn) num sistema Arch/CachyOS
#  recém-formatado, e opcionalmente restaura um packages.conf
#  pessoal vindo de outro repositório (público ou privado).
#
#  Uso:
#    # só instala o Arnyx, com .conf vazio
#    bash <(curl -fsSL https://raw.githubusercontent.com/Thozs/Arnyx/main/bootstrap.sh)
#
#    # instala o Arnyx e restaura seu packages.conf pessoal
#    bash <(curl -fsSL https://raw.githubusercontent.com/Thozs/Arnyx/main/bootstrap.sh) \
#         https://github.com/SEU_USUARIO/seu-repo-de-config.git
#
#  O repositório de config (2º caso) pode ser privado — o git vai
#  pedir autenticação normalmente (usuário + token) na hora do clone.
# ============================================================

set -euo pipefail

ARNYX_REPO="https://github.com/Thozs/Arnyx.git"
CONFIG_REPO="${1:-}"

# ── Cores ──────────────────────────────────────────────────
RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[1;33m'
BLUE=$'\033[0;34m'; CYAN=$'\033[0;36m'; BOLD=$'\033[1m'; NC=$'\033[0m'

info()   { echo -e "${CYAN}::${NC} $*"; }
ok()     { echo -e "${GREEN}✓${NC} $*"; }
warn()   { echo -e "${YELLOW}⚠${NC}  $*"; }
err()    { echo -e "${RED}✗${NC}  $*" >&2; }
header() { echo -e "\n${BOLD}${BLUE}══ $* ══${NC}"; }
die()    { err "$*"; exit 1; }

header "Bootstrap do Arnyx"

command -v pacman >/dev/null 2>&1 || die "Isso não é um sistema Arch-based (pacman não encontrado)."
[[ "$EUID" -ne 0 ]] || die "Não roda isso como root. O script usa sudo só quando precisa."

if [[ -n "$CONFIG_REPO" ]]; then
    msg="Vai instalar git/base-devel, compilar o yay, instalar o Arnyx, e restaurar seu packages.conf de:\n   $CONFIG_REPO"
else
    msg="Vai instalar git/base-devel, compilar o yay, e instalar o Arnyx com uma configuração vazia (sem restaurar pacotes)."
fi
echo -e "$msg"
read -rp "Continuar? [s/N] " confirm
[[ "$confirm" =~ ^[sS]$ ]] || { info "Cancelado."; exit 0; }

# ── 1. Dependências base ─────────────────────────────────────
header "1/4 — Dependências base"
if ! command -v git >/dev/null 2>&1 || ! pacman -Qg base-devel &>/dev/null; then
    info "Instalando git e base-devel..."
    sudo pacman -S --needed --noconfirm git base-devel
else
    ok "git e base-devel já instalados."
fi

# ── 2. Instalar o Arnyx ───────────────────────────────────────
header "2/4 — Instalando o Arnyx"
tmp_arnyx="$(mktemp -d)"
git clone --depth 1 "$ARNYX_REPO" "$tmp_arnyx"
sudo install -Dm755 "$tmp_arnyx/bin/arn" /usr/local/bin/arn
rm -rf "$tmp_arnyx"
ok "arn instalado em /usr/local/bin/arn"

# ── 3. Bootstrap do yay ───────────────────────────────────────
header "3/4 — yay (AUR helper)"
if command -v yay >/dev/null 2>&1; then
    ok "yay já instalado."
else
    info "Compilando yay do AUR..."
    tmp_yay="$(mktemp -d)"
    git clone --depth 1 https://aur.archlinux.org/yay.git "$tmp_yay"
    (cd "$tmp_yay" && makepkg -si --noconfirm)
    rm -rf "$tmp_yay"
    ok "yay instalado."
fi

# ── 4. Configuração ───────────────────────────────────────────
header "4/4 — Configuração"
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

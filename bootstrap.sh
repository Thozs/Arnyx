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
CONFIG_REPO=""
AUR_HELPER_FLAG=""

for arg in "$@"; do
    case "$arg" in
        --aur-helper=*)
            AUR_HELPER_FLAG="${arg#--aur-helper=}"
            ;;
        --*)
            echo "Flag desconhecida: $arg" >&2
            exit 1
            ;;
        *)
            CONFIG_REPO="$arg"
            ;;
    esac
done

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
have_yay=0; have_paru=0
command -v yay  >/dev/null 2>&1 && have_yay=1
command -v paru >/dev/null 2>&1 && have_paru=1

if [[ -n "$AUR_HELPER_FLAG" ]]; then
    case "$AUR_HELPER_FLAG" in
        yay|yay-bin|paru|paru-bin|none) AUR_HELPER="$AUR_HELPER_FLAG" ;;
        *) die "--aur-helper invalido: $AUR_HELPER_FLAG (use yay, yay-bin, paru, paru-bin ou none)" ;;
    esac
elif (( have_yay )); then
    AUR_HELPER="existing-yay"
elif (( have_paru )); then
    AUR_HELPER="existing-paru"
else
    echo ""
    echo "  Escolha o AUR helper:"
    echo "    1) yay       - compila do AUR (lento, ~5 min)"
    echo "    2) yay-bin   - binario pre-compilado (rapido) [padrao]"
    echo "    3) paru      - compila do AUR (lento)"
    echo "    4) paru-bin  - binario pre-compilado (rapido)"
    echo "    5) nenhum    - nao instalar AUR helper"
    echo ""
    read -r -p "  Escolha [1-5, Enter=2]: " choice
    case "${choice:-2}" in
        1) AUR_HELPER="yay" ;;
        2) AUR_HELPER="yay-bin" ;;
        3) AUR_HELPER="paru" ;;
        4) AUR_HELPER="paru-bin" ;;
        5) AUR_HELPER="none" ;;
        *) warn "Opcao invalida - usando 2 (yay-bin)."; AUR_HELPER="yay-bin" ;;
    esac
fi

echo ""
echo "  == Resumo =="
if [[ "$AUR_HELPER" == existing-* ]]; then
    echo "    AUR helper:  ${AUR_HELPER#existing-} (ja instalado)"
elif [[ "$AUR_HELPER" == "none" ]]; then
    echo "    AUR helper:  nenhum (pode instalar depois: arn install yay-bin)"
else
    echo "    AUR helper:  $AUR_HELPER"
fi
if [[ -n "$CONFIG_REPO" ]]; then
    echo "    Config:      restaurar de $CONFIG_REPO"
else
    echo "    Config:      vazio (arn init)"
fi
read -rp "Continuar? [s/N] " confirm
[[ "$confirm" =~ ^[sS]$ ]] || { info "Cancelado."; exit 0; }

header "1/4 — Dependências base"
pkgs=()
command -v git >/dev/null 2>&1 || pkgs+=(git)

case "$AUR_HELPER" in
    yay|paru)
        if ! command -v gcc >/dev/null 2>&1 || ! command -v make >/dev/null 2>&1; then
            pkgs+=(base-devel)
        fi
        ;;
    yay-bin|paru-bin)
        command -v fakeroot >/dev/null 2>&1 || pkgs+=(fakeroot)
        command -v debugedit >/dev/null 2>&1 || pkgs+=(debugedit)
        ;;
esac

if (( ${#pkgs[@]} )); then
    info "Instalando ${pkgs[*]}..."
    sudo pacman -S --needed --noconfirm "${pkgs[@]}"
else
    ok "Dependências base já instaladas."
fi

header "2/4 — Instalando o Arnyx"
tmp_arnyx="$(mktemp -d)"
git clone --depth 1 "$ARNYX_REPO" "$tmp_arnyx"
(cd "$tmp_arnyx" && ./tools/build-arn.sh --backend=arch)
sudo install -Dm755 "$tmp_arnyx/bin/arn" /usr/local/bin/arn
rm -rf "$tmp_arnyx"
ok "arn instalado em /usr/local/bin/arn"

header "3/4 — AUR helper ($AUR_HELPER)"
case "$AUR_HELPER" in
    existing-yay)
        ok "yay já estava instalado — pulando."
        ;;
    existing-paru)
        ok "paru já estava instalado — pulando."
        ;;
    none)
        info "Pulado (nenhum AUR helper escolhido)."
        info "Pra instalar depois: arn install yay-bin"
        ;;
    *)
        if command -v "${AUR_HELPER%-bin}" >/dev/null 2>&1; then
            ok "${AUR_HELPER%-bin} já instalado — pulando."
        else
            info "Instalando $AUR_HELPER..."
            tmp_aur="$(mktemp -d)"
            if git clone --depth 1 "https://aur.archlinux.org/${AUR_HELPER}.git" "$tmp_aur" &&                (cd "$tmp_aur" && makepkg -si --noconfirm); then
                ok "$AUR_HELPER instalado."
            else
                warn "Falha ao instalar $AUR_HELPER — continuando sem AUR helper."
                info "Instale depois com: arn install $AUR_HELPER"
            fi
            rm -rf "$tmp_aur"
        fi
        ;;
esac

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

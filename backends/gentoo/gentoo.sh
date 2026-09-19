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
    local manager="$1" pkg="$2" rc
    if [[ "$manager" == "pacman" ]]; then
        portage_install "$pkg"
        rc=$?
        (( rc == 0 )) && return 0
        if (( rc == 2 )); then
            warn "'$pkg' está mascarado no Portage — não é 'não encontrado', só falta desmascarar."
            info "Rode: arn unmask $pkg"
            return 1
        fi
        if (( rc == 3 )); then
            warn "Build de '$pkg' interrompido (Ctrl+C) — mantido no .conf."
            return 1
        fi
    else
        warn "Seção '[$manager]' não é suportada no backend Gentoo. Pulando '$pkg'."
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

    # Nome de pacote seguro (categoria/nome ou só nome) — evita que
    # uma string maliciosa vire path no sudo cp mais abaixo.
    if [[ ! "$pkg" =~ ^[a-zA-Z0-9][a-zA-Z0-9+_.-]*(/[a-zA-Z0-9][a-zA-Z0-9+_.-]*)?$ ]]; then
        err "Nome de pacote inválido: '$pkg'"
        return 1
    fi

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

    # Snapshot dos ._cfg* já existentes, pra detectar só os que o
    # emerge criar AGORA (e não mexer em pendências antigas do usuário
    # que nada têm a ver com esse pacote).
    local before_list after_list
    before_list="$(mktemp)"; after_list="$(mktemp)"
    find /etc/portage -type f -name '._cfg????_*' 2>/dev/null | sort > "$before_list"

    local unmask_out
    unmask_out="$(sudo emerge --ask=n --autounmask=y --autounmask-write "$pkg" 2>&1)"
    local unmask_status=$?
    echo "$unmask_out"

    find /etc/portage -type f -name '._cfg????_*' 2>/dev/null | sort > "$after_list"
    local cfg_files=()
    mapfile -t cfg_files < <(comm -13 "$before_list" "$after_list")
    rm -f "$before_list" "$after_list"

    # --autounmask-write sai com status != 0 DE PROPÓSITO mesmo quando
    # grava certo (é assim que o Portage força revisar antes de aplicar
    # de verdade) — por isso não dá pra confiar só no exit code aqui.
    if (( unmask_status == 0 )) || grep -q "Autounmask changes successfully written" <<< "$unmask_out"; then
        ok "'$pkg' desmascarado (alterações pendentes pra aplicar)."

        # Aplica cada ._cfg* novo, mas em vez de mesclar de volta no
        # arquivo que o Portage escolheu (que pode ser um só pra tudo),
        # extrai as linhas adicionadas e escreve cada átomo no arquivo
        # com o nome do próprio pacote. Assim /etc/portage/package.*
        # fica organizado por pacote sem precisar rodar etc-update.
        local applied_files=() skipped_files=()
        if (( ${#cfg_files[@]} > 0 )); then
            local cfg dir base orig
            for cfg in "${cfg_files[@]}"; do
                dir="$(dirname "$cfg")"
                base="$(basename "$cfg")"
                orig="$dir/${base#._cfg????_}"

                local py_helper; py_helper="$(mktemp)"
                cat > "$py_helper" << 'PYEXTRACT'
import difflib, re, sys
from pathlib import Path

orig_path = Path(sys.argv[1])
cfg_path = Path(sys.argv[2])

# Detecta se o "arquivo de config" (package.license, package.use,
# etc.) é um arquivo ou um diretório. Portage aceita os dois layouts,
# mas nosso modo "por pacote" só funciona se for diretório. Se for
# arquivo, converte pra diretório (preservando conteúdo em _legacy).
raw_orig = orig_path
if raw_orig.parent == Path("/etc/portage"):
    config_dir = raw_orig
    if raw_orig.is_file():
        legacy_content = raw_orig.read_text()
        raw_orig.unlink()
        raw_orig.mkdir(parents=True, exist_ok=True)
        (raw_orig / "_legacy").write_text(legacy_content)
    elif not raw_orig.exists():
        raw_orig.mkdir(parents=True, exist_ok=True)
else:
    config_dir = raw_orig.parent

orig = (config_dir / "_legacy").read_text().splitlines() if (config_dir / "_legacy").exists() else []
cfg = cfg_path.read_text().splitlines()

added = []
for line in difflib.unified_diff(orig, cfg, n=0, lineterm=''):
    if line.startswith('+') and not line.startswith('+++'):
        added.append(line[1:])

def extract_pkg(atom_line):
    token = atom_line.strip().split()[0] if atom_line.strip() else ''
    m = re.match(r'^[=<>~]?\s*[a-zA-Z0-9+_.-]+/([a-zA-Z0-9+_.-]+?)(?:-[0-9].*)?$', token)
    return m.group(1) if m else None

chunks, current = [], []
for line in added:
    s = line.strip()
    if not s:
        continue
    if s.startswith('#'):
        current.append(line)
    else:
        current.append(line)
        chunks.append(current)
        current = []
if current:
    chunks.append(current)

if not chunks:
    print("  (nenhuma linha nova — ._cfg* idêntico ao original)")
    sys.exit(0)

dir_ = config_dir
wrote = []
for chunk in chunks:
    atom = next((l for l in chunk if l.strip() and not l.strip().startswith('#')), None)
    if not atom:
        continue
    pkg = extract_pkg(atom)
    if not pkg:
        continue
    target = dir_ / pkg
    existing = target.read_text().splitlines() if target.exists() else []
    to_write = [l for l in chunk if l not in existing]
    if to_write:
        with target.open('a') as f:
            for l in to_write:
                f.write(l + '\n')
        wrote.append((str(target), to_write))

if not wrote:
    print("  (nada novo pra gravar)")
    sys.exit(0)

print(f"Vai gravar em {dir_}:")
for path, lines in wrote:
    print(f"  {Path(path).name}")
    for l in lines:
        if not l.strip().startswith('#'):
            print(f"    + {l.strip()}")
PYEXTRACT
                sudo python3 "$py_helper" "$orig" "$cfg"
                rm -f "$py_helper"

                echo
                local apply_reply
                read -r -p "$(echo -e "${YELLOW}?${NC} Confirmar? [s/N] ")" apply_reply
                if [[ "$apply_reply" =~ ^[sS]$ ]]; then
                    sudo rm -f "$cfg"
                    applied_files+=("$orig (extraído por pacote)")
                    ok "Aplicado."
                else
                    skipped_files+=("$orig")
                    info "Cancelado — nada foi alterado."
                fi
            done
        fi

        # Log: motivo + arquivos efetivamente tocados
        mkdir -p "$(dirname "$UNMASK_LOG")"
        {
            printf '%s | %s | %s' \
                "$(date '+%Y-%m-%d %H:%M:%S')" \
                "$pkg" \
                "$(echo "$reason" | tr '\n' ' ' | sed 's/  */ /g')"
            if (( ${#applied_files[@]} > 0 )); then
                printf ' | arquivos: %s' "$(printf '%s ' "${applied_files[@]}")"
            fi
            printf '\n'
        } >> "$UNMASK_LOG"
        info "Registrado em: $UNMASK_LOG"

        if (( ${#skipped_files[@]} > 0 )); then
            warn "${#skipped_files[@]} arquivo(s) ficaram pendentes — rode 'sudo etc-update' (ou dispatch-conf) pra resolvê-los."
        fi

        info "Depois: arn install $pkg"
    else
        err "Falha ao desmascarar '$pkg'. Nada foi registrado no log."
        return 1
    fi
}

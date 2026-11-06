<div align="center">

# Arnyx

**Gerenciador declarativo de pacotes pra Arch e Gentoo, inspirado na filosofia do NixOS.**
Você declara o que quer num arquivo. O `arn` garante que o sistema reflita isso.

[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
![Shell: Bash](https://img.shields.io/badge/shell-bash-4EAA25?logo=gnubash&logoColor=white)
![Arch](https://img.shields.io/badge/Arch-CachyOS-1793D1?logo=archlinux&logoColor=white)
![Gentoo](https://img.shields.io/badge/Gentoo-portage-54487A?logo=gentoo&logoColor=white)

</div>

---

## Sumário

- [O que é](#o-que-é)
- [Recursos](#recursos)
- [Instalação](#instalação)
  - [Instalação rápida (sistema novo/formatado)](#instalação-rápida-sistema-novoformatado)
- [Backup automático do config pessoal (fish)](#backup-automático-do-config-pessoal-fish)
- [Rollback (Generations)](#rollback-generations)
- [Aliases](#aliases)
- [Automatização Aliases](#automatização-do-aliases-fish)
- [Gentoo](#gentoo-beta)
- [Roadmap](#roadmap)
- [Por que "Arnyx"?](#por-que-arnyx)
- [Licença](#licença)

---

## O que é

Projeto pessoal, em desenvolvimento desde 7 de maio de 2026. Construído com ajuda do Claude e testado no dia a dia no meu próprio sistema **Arch** (via **CachyOS**) e, mais recentemente, **Gentoo**, rodando **fish** + **kitty**.

Sistemas Arch e Gentoo não têm um jeito nativo de dizer *"esse é o conjunto exato de pacotes que eu quero instalado"* — você vai instalando e desinstalando coisa ao longo do tempo, e o sistema vira um acúmulo de decisões que ninguém lembra mais o porquê.

**Arnyx** resolve isso com um arquivo (`packages.conf`) que descreve o estado desejado do sistema. O comando `arn` compara esse arquivo com o que está de fato instalado e sincroniza os dois — instalando o que falta, e opcionalmente removendo o que sobrou.

---

## Recursos

| Comando | O que faz |
|---|---|
| `arn install <pkg>` | Detecta sozinho a fonte (repo oficial / AUR / Portage), adiciona ao `.conf` e instala |
| `arn search <termo>` | Busca no repo oficial + AUR (Arch) / GURU (Gentoo), menu fzf pra instalar direto |
| `arn manage` | Menu interativo (fzf) mostrando só o que precisa de decisão — pendente ou instalado manualmente |
| `arn sync` | Instala o que falta do `.conf` (não remove nada) |
| `arn rebuild` | Sincronização completa: instala o que falta + remove o que saiu do `.conf` (pede confirmação `[s/N]` antes de remover) |
| `arn rebuild --dry-run` | Mostra o que seria instalado/removido, sem aplicar nada |
| `arn diff` | Compara `.conf`, `.lock` e sistema real |
| `arn why` | Por que está instalado: declarado por você ou dependência de quê |
| `arn list` | Lista tudo com versão e status |
| `arn upgrade` | Atualiza todos os pacotes (pacman + AUR / Portage) |
| `arn unmask <pkg>` | **[Gentoo]** Desmascara pacote específico, extrai as entradas úteis do Portage e grava por pacote em `/etc/portage/` (ver [Gentoo](#gentoo-beta)) |
| `arn rollback` | Menu fzf com as gerações salvas (snapshots de sync/rebuild) |
| `arn rollback [N]` | Restaura o .conf da geração N direto |

Por baixo:
- **Parsing do `.conf` em `awk`/`grep` puro** — sem dependência de linguagem pesada no dia a dia
- **Cache do banco local** — evita revarredura cara em HDD a cada comando (pacman no Arch, qlist no Gentoo)
- **Instalação em lote** — uma transação só em vez de uma por pacote
- **Auto-limpeza** — se um pacote falha ao instalar, some do `.conf` sozinho, sem sujeira

---

## Instalação manual

```bash
git clone https://github.com/Thozs/Arnyx.git
cd Arnyx
./tools/build-arn.sh              # auto-detecta o backend (arch/gentoo)
sudo install -Dm755 bin/arn /usr/local/bin/arn
arn init
```

### Instalação rápida (sistema novo/formatado)

Se você acabou de formatar e quer instalar o Arnyx (e opcionalmente restaurar seus próprios pacotes declarados) num comando só.

**Arch:**

```bash
# só instala o arn, com .conf vazio
bash <(curl -fsSL https://raw.githubusercontent.com/Thozs/Arnyx/main/bootstrap.sh)

# instala o arn E restaura um packages.conf pessoal de outro repositório seu
bash <(curl -fsSL https://raw.githubusercontent.com/Thozs/Arnyx/main/bootstrap.sh) \
     https://github.com/SEU_USUARIO/seu-repo-de-config.git
```

O `bootstrap.sh` instala `git`/`base-devel`, compila o `yay` do zero e instala o `arn`.

**Gentoo:**

```bash
# só instala o arn, com .conf vazio
bash <(curl -fsSL https://raw.githubusercontent.com/Thozs/Arnyx/main/bootstrap-gentoo.sh)

# instala o arn E restaura um packages.conf pessoal de outro repositório seu
bash <(curl -fsSL https://raw.githubusercontent.com/Thozs/Arnyx/main/bootstrap-gentoo.sh) \
     https://github.com/SEU_USUARIO/seu-repo-de-config.git
```

O `bootstrap-gentoo.sh` instala `dev-vcs/git`, `app-portage/portage-utils` e `app-shells/fzf` via `emerge`, e instala o `arn`. Em ambos os casos, o segundo argumento é **opcional** e aponta pra outro repositório seu com um `packages.conf` — pode ser público ou privado.

---

## Backup automático do config pessoal (fish)

Se você estiver usando um repositório separado para armazenar suas configurações (veja Instalação rápida), o arquivo examples/arnyx-backup.fish automatiza o backup do seu packages.conf para esse repositório.

```fish
# ajuste os dois caminhos no topo do arquivo pro seu caso, depois:
source /caminho/pra/arnyx-backup.fish
```

Adicione essa linha ao seu config.fish para deixar o comando sempre disponível. Depois, sempre que quiser sincronizar seu packages.conf com o repositório de configuração, executa o comando:

```fish
arnb
```

Ele copia o `.conf` atual, verifica se algo mudou desde o último backup (não faz commit vazio à toa), e sobe pro repositório que estiver o seu backup.

---

## Rollback (Generations)

Todo `sync` ou `rebuild` que efetivamente muda o `.conf` salva uma **geração**: um snapshot desse `.conf` no momento, mais um log das versões instaladas naquela hora. Não duplica se nada mudou desde a última.

```bash
arn rollback        # menu fzf com as gerações salvas (mais recente primeiro)
arn rollback <N>    # vai direto pra geração N
```

Antes de aplicar, mostra o diff contra o `.conf` atual, o log de versões daquele momento, e pede confirmação `[s/N]`. O `.conf` anterior é sempre salvo como backup (`packages.conf.antes-rollback-N`) antes de sobrescrever.

**Importante:** isso restaura a *lista* de pacotes declarados, não trava a versão exata — nem o pacman nem o Portage fazem downgrade sozinhos, então o log de versões é só referência/auditoria. Depois do rollback, rode `arn rebuild --dry-run` pra ver o impacto real ou `arn sync` pra só instalar o que falta.

As gerações ficam em `~/.local/state/arnyx/generations/`, com as 20 mais recentes mantidas (as antigas são podadas automaticamente).

---

## Aliases

Os aliases (`arni`, `arns`, `arnr`, etc.) ficam documentados na seção `ALIASES FISH`
dentro do próprio [`bin/arn`](bin/arn) (função `usage()`) — é a fonte única da verdade.

Arquivos prontos pra copiar, gerados automaticamente a partir dali:

- [Fish](aliases/fish/aliases.fish)
- [Bash / Zsh](aliases/sh/aliases.sh)

## Automatização do Aliases (Fish)

```bash
arn aliases install
```

Detecta se você usa fish, mostra os aliases antes de aplicar, pede confirmação, e cria
`~/.config/fish/conf.d/arnyx-aliases.fish`. Se o arquivo já existir mas estiver
desatualizado em relação ao `bin/arn` atual (ex: alias novo adicionado), mostra o
diff e pergunta se quer atualizar. Bash/zsh continuam manuais (copie de
`aliases/sh/aliases.sh`).

Se os aliases ainda não estiverem instalados, o `arn` avisa automaticamente (1x por dia)
oferecendo instalar, adiar, ou não perguntar mais.

<details>
<summary>Contribuindo / editando os aliases (não necessário só pra usar o Arnyx)</summary>

Um hook de commit (`.githooks/pre-commit`) regenera esses arquivos sozinho sempre que
o código-fonte muda — não precisa rodar nada na mão. Isso só importa se você clonou o
repositório completo pra mexer no código-fonte; quem só instala e usa o `arn` nunca
precisa disso.

Nota sobre `bin/arn`: esse arquivo é **gerado** (igual os aliases acima) a partir de
`src/core.sh` (núcleo, editado à mão) + `backends/<distro>/` (lógica específica por
gerenciador — `arch/` com `pacman`/`aur`, `gentoo/` com `portage`), via
`tools/build-arn.sh` (que auto-detecta o backend por `/etc/os-release`, ou aceita
`--backend=arch|gentoo` explícito). **Não é commitado** — é gerado no momento da
instalação (os dois bootstraps rodam `build-arn.sh` antes de instalar) e está no
`.gitignore`. Quem só instala via `bootstrap.sh`/`bootstrap-gentoo.sh` não precisa
se preocupar; quem clona pra mexer no código roda `./tools/build-arn.sh` uma vez
antes de usar `./bin/arn`. Edite sempre `src/core.sh`/`backends/`, nunca `bin/arn`
direto.

Pra ativar, uma vez por clone:

```bash
git config core.hooksPath .githooks
chmod +x .githooks/pre-commit tools/build-arn.sh tools/build-aliases.sh
```

Depois disso, editar um alias é só mexer na seção `ALIASES FISH` de `src/core.sh`
(dentro da função `usage()`) e commitar normalmente — o hook roda
`tools/build-aliases.sh` automático e inclui os arquivos `aliases/` atualizados no
mesmo commit.

</details>
---

## Gentoo (beta)

O backend Gentoo/Portage usa os mesmos comandos do Arch sempre que
possível: `install`, `remove`, `sync`, `rebuild`, `search`, `list`,
`diff`, `why`, `upgrade`, `edit`, `rollback` e `aliases install`
funcionam igual. O que muda é o `unmask`.

### `arn unmask <pkg>`

No Gentoo, um pacote pode estar mascarado por dois motivos: palavra-
chave instável (`~amd64`, típico de ebuilds do GURU) ou bloqueio
explícito no perfil (`package.mask`). O `arn unmask` cuida dos dois
sem exigir que você saiba qual é o caso.

O fluxo é:

1. Mostra o motivo do mask
2. **Se o motivo envolver licença**, entra num gate à parte, mais
   rígido que o `[s/N]` comum (ver abaixo) — aceitar uma licença é
   uma decisão consciente, não algo que dá pra confirmar sem querer
3. Pede confirmação geral `[s/N]`
4. Roda `emerge --autounmask-write` — o Portage decide **o que**
   precisa ser escrito (keyword, licença, USE flag, etc.)
5. Detecta os arquivos de proposta (`._cfg*`) que o Portage acabou
   de criar em `/etc/portage/`
6. Extrai só as linhas novas e grava cada uma em
   `/etc/portage/package.<tipo>/<nome-do-pacote>` — assim cada
   pacote tem o próprio arquivo, em vez de tudo virar um só
7. Descarta o arquivo temporário do Portage — o conteúdo útil já
   foi extraído no passo anterior, então ele vira só lixo acumulando

**Nada é escrito em `/etc/portage` sem sua confirmação.** Se você
responder `N` no passo 6, a proposta do Portage fica pendente como
`._cfg*` — o Arnyx avisa no fim de `sync`/`rebuild`/`install`/`upgrade`
se existirem pendentes, e o comando pra resolvê-las é
`sudo etc-update` (ou `sudo dispatch-conf`).

#### Gate de licença

O Portage desliga `--autounmask-license` por padrão (desde a 2.1.10)
de propósito, pra ninguém aceitar uma licença sem perceber. O Arnyx
respeita essa cautela e só passa `--autounmask-license=y` pro emerge
depois que você aceitar **explicitamente, licença por licença**:

- Pra cada licença que o pacote exige, o Arnyx mostra o nome, o
  caminho do arquivo e **o texto completo da licença** direto no
  terminal (`cat` do arquivo em `/var/db/repos/*/licenses/`)
- A confirmação é um prompt separado, `[a/N]` (a = aceito) —
  diferente do `[s/N]` genérico usado no resto do Arnyx, pra não dar
  pra confirmar no automático sem perceber que é uma licença.
  Qualquer resposta que não seja `a`/`A` (incluindo `n`, vazio, etc.)
  cancela o unmask daquele pacote e nada é escrito em `/etc/portage`
- Se alguma licença for aceita, o log em
  `~/.local/state/arnyx/gentoo-unmasked.log` registra isso junto com
  motivo/data/arquivos tocados

Tudo fica registrado em `~/.local/state/arnyx/gentoo-unmasked.log` —
pacote, motivo, arquivos efetivamente tocados e data.

---

## Roadmap

Ideias exploradas mas ainda não implementadas — na fila pra quando der:

- [ ] **Downgrade real de pacotes** — `arn rollback <N> --downgrade` (ou `arn downgrade`): compara o log de versões da geração com o instalado hoje, reinstala via cache local do gerenciador (`pacman -U` no Arch, `emerge --usepkg` no Gentoo) os que mudaram; avisa sobre `IgnorePkg` (Arch) / `package.mask` (Gentoo) pra não ser sobrescrito no próximo upgrade
- [ ] **Snapshot via Btrfs** — ponto de restauração real do sistema antes de operações arriscadas
- [ ] **Camada de config declarativa** — versionar dotfiles (Hyprland, shell, etc.), não só pacotes
- [ ] **Motivo de instalação no `.conf`** — `arn install <pkg> -m "motivo"` grava um comentário acima do pacote no `.conf`, pra responder "por que instalei isso?" sem depender de memória
- [ ] **`arn health`** — checagem pós-upgrade: pacotes órfãos (`pacman -Qdt` no Arch / `emerge --depclean --pretend` no Gentoo), arquivos pendentes (`.pacnew` no Arch / `._cfg*` no Gentoo), serviços `systemd` que falharam desde o boot

---

## Por que "Arnyx"?

Ar(ch) + Nyx (mitologia grega, a deusa da noite — também o som de "Nix"). Sem relação com o projeto `nixy` (config de Hyprland/Caelestia) nem com o pacote `nyx` do repositório oficial (monitor de status do Tor) — nomes parecidos, projetos completamente diferentes.

---

## Licença

[MIT](LICENSE)

<div align="center">

# Arnyx

**Gerenciador declarativo de pacotes pra Arch/CachyOS, inspirado na filosofia do NixOS.**
Você declara o que quer num arquivo. O `arn` garante que o sistema reflita isso.

[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
![Shell: Bash](https://img.shields.io/badge/shell-bash-4EAA25?logo=gnubash&logoColor=white)
![Made for Arch](https://img.shields.io/badge/made%20for-Arch%20%2F%20CachyOS-1793D1?logo=archlinux&logoColor=white)
![No Python](https://img.shields.io/badge/dependencies-zero%20python-success)

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
- [Roadmap](#roadmap)
- [Por que "Arnyx"?](#por-que-arnyx)
- [Licença](#licença)

---

## O que é

Projeto pessoal, em desenvolvimento desde 7 de maio de 2026. Construído com ajuda do Claude e testado no dia a dia no meu próprio sistema **Arch/CachyOS**, rodando **fish** + **kitty**.

Arch/CachyOS não tem um jeito nativo de dizer *"esse é o conjunto exato de pacotes que eu quero instalado"* — você vai instalando e desinstalando coisa ao longo do tempo, e o sistema vira um acúmulo de decisões que ninguém lembra mais o porquê.

**Arnyx** resolve isso com um arquivo (`packages.conf`) que descreve o estado desejado do sistema. O comando `arn` compara esse arquivo com o que está de fato instalado e sincroniza os dois — instalando o que falta, e opcionalmente removendo o que sobrou.

---

## Recursos

| Comando | O que faz |
|---|---|
| `arn install <pkg>` | Detecta sozinho se é pacote oficial ou AUR, adiciona ao `.conf` e instala |
| `arn manage` | Menu interativo (fzf) mostrando só o que precisa de decisão — pendente ou instalado manualmente |
| `arn sync` | Instala o que falta do `.conf` (não remove nada) |
| `arn rebuild` | Sincronização completa: instala o que falta + remove o que saiu do `.conf` (pede confirmação `[s/N]` antes de remover) |
| `arn rebuild --dry-run` | Mostra o que seria instalado/removido, sem aplicar nada |
| `arn diff` | Compara `.conf`, `.lock` e sistema real |
| `arn list` | Lista tudo com versão e status |
| `arn upgrade` | Atualiza pacman + AUR |
| `arn rollback [N]` | Restaura um `.conf` anterior (menu fzf se `N` não for informado) |

Por baixo:
- **Zero dependência de Python** — parsing do `.conf` inteiro em `awk`/`grep` puro
- **Cache do banco local do pacman** — evita revarredura cara em HDD a cada comando
- **Instalação em lote** — uma transação só em vez de uma por pacote
- **Auto-limpeza** — se um pacote falha ao instalar, some do `.conf` sozinho, sem sujeira

---

## Instalação manual

```bash
git clone https://github.com/Thozs/arnyx.git
cd arnyx
sudo install -Dm755 bin/arn /usr/local/bin/arn
arn init
```

### Instalação rápida (sistema novo/formatado)

Se você acabou de formatar e quer instalar o Arnyx (e opcionalmente restaurar seus próprios pacotes declarados) num comando só:

```bash
# só instala o arn, com .conf vazio
bash <(curl -fsSL https://raw.githubusercontent.com/Thozs/Arnyx/main/bootstrap.sh)

# instala o arn E restaura um packages.conf pessoal de outro repositório seu
bash <(curl -fsSL https://raw.githubusercontent.com/Thozs/Arnyx/main/bootstrap.sh) \
     https://github.com/SEU_USUARIO/seu-repo-de-config.git
```

O `bootstrap.sh` instala `git`/`base-devel`, compila o `yay` do zero e instala o `arn`. O segundo argumento é **opcional** e aponta pra outro repositório seu com um `packages.conf` — pode ser público ou privado. Sem esse argumento, instala só a ferramenta, com config vazia.

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

**Importante:** isso restaura a *lista* de pacotes declarados, não trava a versão exata — o pacman não faz downgrade sozinho, então o log de versões é só referência/auditoria. Depois do rollback, rode `arn rebuild --dry-run` pra ver o impacto real ou `arn sync` pra só instalar o que falta.

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
`~/.config/fish/conf.d/arnyx-aliases.fish`. Bash/zsh continuam manuais (copie de
`aliases/sh/aliases.sh`).

Se os aliases ainda não estiverem instalados, o `arn` avisa automaticamente (1x por dia)
oferecendo instalar, adiar, ou não perguntar mais.

<details>
<summary>Contribuindo / editando os aliases (não necessário só pra usar o Arnyx)</summary>

Um hook de commit (`.githooks/pre-commit`) regenera esses arquivos sozinho sempre que
`bin/arn` muda — não precisa rodar nada na mão. Isso só importa se você clonou o
repositório completo pra mexer no código-fonte; quem só instala e usa o `arn` nunca
precisa disso.

Pra ativar, uma vez por clone:

```bash
git config core.hooksPath .githooks
chmod +x .githooks/pre-commit tools/build-aliases.sh
```

Depois disso, editar um alias é só mexer na seção `ALIASES FISH` do `bin/arn` e
commitar normalmente — `tools/build-aliases.sh` roda automático e inclui os arquivos
atualizados no mesmo commit.

</details>

---

## Roadmap

Ideias exploradas mas ainda não implementadas — na fila pra quando der:

- [ ] **Snapshot via Btrfs** — ponto de restauração real do sistema antes de operações arriscadas
- [ ] **Camada de config declarativa** — versionar dotfiles (Hyprland, shell, etc.), não só pacotes

---

## Por que "Arnyx"?

Ar(ch) + Nyx (mitologia grega, a deusa da noite — também o som de "Nix"). Sem relação com o projeto `nixy` (config de Hyprland/Caelestia) nem com o pacote `nyx` do repositório oficial (monitor de status do Tor) — nomes parecidos, projetos completamente diferentes.

---

## Licença

[MIT](LICENSE)

# arnyx-backup.fish
#
# Sobe o packages.conf real pro seu repositório de config (privado ou
# não). Requer fish e um repositório git já inicializado no caminho
# de ARNYX_CONFIG_REPO, com 'origin' apontando pro remoto.
#
# Uso:
#   1. Ajuste as duas variáveis abaixo pro seu caminho real.
#   2. No seu config.fish, adicione:
#        source /caminho/pra/arnyx-backup.fish
#   3. Rode 'arnb' quando quiser sincronizar.

set -g ARNYX_CONF_PATH  ~/.config/arnyx/packages.conf
set -g ARNYX_CONFIG_REPO ~/arnyx-config

function arnyx-backup --description "Sobe o packages.conf real pro repositório de config"
    if not test -f "$ARNYX_CONF_PATH"
        echo "⚠ packages.conf não encontrado em $ARNYX_CONF_PATH"
        return 1
    end

    if not test -d "$ARNYX_CONFIG_REPO/.git"
        echo "⚠ $ARNYX_CONFIG_REPO não é um repositório git. Rode 'git init' e configure o remote primeiro."
        return 1
    end

    cp "$ARNYX_CONF_PATH" "$ARNYX_CONFIG_REPO/packages.conf"

    pushd "$ARNYX_CONFIG_REPO" > /dev/null

    if git diff --quiet -- packages.conf
        echo ":: Nada mudou desde o último backup."
        popd > /dev/null
        return 0
    end

    git add packages.conf
    git commit -m "atualiza packages.conf ("(date +%Y-%m-%d)")"
    git push

    popd > /dev/null
    echo "✓ Backup enviado."
end

alias arnb 'arnyx-backup'

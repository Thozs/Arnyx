# aliases/fish/gentoo.fish — aliases ESPECÍFICOS do backend Gentoo.
# Diferente de aliases/fish/aliases.fish (gerado automaticamente por
# tools/build-aliases.sh a partir de bin/arn), este arquivo é escrito
# à mão e só deve ser sourced em sistemas Gentoo. Ele não é regenerado
# pelo build-aliases.sh — edite direto aqui.
#
# Pra ativar: source esse arquivo no seu config.fish, ou copie pra
# ~/.config/fish/conf.d/arnyx-gentoo.fish

# arnunmask <pkg> [pkg2...] → arn unmask <pkg> [pkg2...]
# Desmascara seletivamente só o(s) pacote(s) passado(s) (nunca o
# sistema todo), mostra o motivo do mask antes de aplicar, e registra
# em ~/.local/state/arnyx/gentoo-unmasked.log (pacote + motivo + data).
alias arnunmask 'arn unmask'

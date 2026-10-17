# Primeiro login como no GDM ("definir senha no próximo login" do
# AccountsService): a conta nasce com a senha vazia e expirada (users.nix,
# install.sh). O login aceita a senha vazia só por estar expirada e, no
# pam_chauthtok, o pam_unix pula a "senha atual" de uma senha vazia: o
# usuário só digita a nova senha e a confirmação.
#
# Vale para o serviço "login", que o greetd (substack/include) e o TTY herdam.
{
  flake.modules.nixos.first-login =
    { lib, ... }:
    {
      security.pam.services.login = {
        # Sem o nullok geral (o NixOS o liga no login): uma senha vazia que não
        # esteja expirada não entra.
        allowNullPassword = lib.mkForce false;
        rules = {
          # nullresetok: senha vazia só enquanto a troca é obrigatória.
          auth.unix.settings.nullresetok = true;
          auth.unix-early.settings.nullresetok = true;
          password.unix.settings.nullresetok = true;
        };
      };
    };
}

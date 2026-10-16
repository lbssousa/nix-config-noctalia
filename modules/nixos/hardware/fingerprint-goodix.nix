# Leitor de digital Goodix 538d (USB 27c6:538d), com o fork lbssousa do
# libfprint (drivers TLS da Goodix + matcher SIGFM). Ver modules/packages/.
{
  flake.modules.nixos.fingerprint-goodix =
    { pkgs, ... }:
    {
      services.fprintd = {
        enable = true;
        package = pkgs.fprintd-goodix;
      };

      # Login gráfico: digital (suficiente) ou senha.
      security.pam.services.greetd.fprintAuth = true;
    };
}

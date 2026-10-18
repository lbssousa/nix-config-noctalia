# Bitwarden como gerenciador de senhas padrão e agente SSH de todos os
# usuários (ver home/security/bitwarden.nix).
#
# Desbloqueio biométrico: nada de política polkit externa — o pacote
# bitwarden-desktop do nixpkgs já instala a ação polkit
# "com.bitwarden.Bitwarden.unlock" (auth_self) em share/polkit-1/actions, e o
# módulo security.polkit compõe share/polkit-1 de todos os systemPackages em
# /run/current-system/sw (environment.pathsToLink), de onde o polkitd a lê.
# (No Flatpak era preciso a política em /etc porque o polkitd não enxerga
# dentro do sandbox do app.)
{
  flake.modules.nixos.bitwarden =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.bitwarden-desktop ];
    };
}

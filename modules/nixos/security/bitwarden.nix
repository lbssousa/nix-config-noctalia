# App do Bitwarden para todos os usuários. O gerenciador de senhas padrão e o
# agente SSH são o KeePassXC e o ssh-agent (security/keepassxc.nix).
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

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
#
# Sem autostart para nenhum usuário: o app escreve
# ~/.config/autostart/bitwarden.desktop ao ligar "Iniciar com o sistema"; o
# home-manager o substitui por uma entrada oculta (Hidden=true), que também
# impede o app de reativá-lo.
{
  flake.modules.nixos.bitwarden =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.bitwarden-desktop ];

      home-manager.sharedModules = [
        {
          xdg.configFile."autostart/bitwarden.desktop" = {
            force = true;
            text = ''
              [Desktop Entry]
              Type=Application
              Name=Bitwarden
              Hidden=true
            '';
          };
        }
      ];
    };
}

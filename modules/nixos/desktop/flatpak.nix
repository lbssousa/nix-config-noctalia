# Flatpak (Flathub) como forma preferida para os aplicativos gráficos de
# usuário, declarados com o nix-flatpak. Cada feature acrescenta os seus em
# services.flatpak.packages (apps.nix, firefox.nix, bitwarden.nix); aqui ficam
# o serviço, as atualizações e as ferramentas de gerência dos Flatpaks.
#
# /var/lib/flatpak é um subvolume btrfs próprio (persistente); os dados de
# cada app ficam em ~/.var/app/<id>.
{ inputs, ... }:
{
  flake.modules.nixos.flatpak = {
    imports = [ inputs.nix-flatpak.nixosModules.nix-flatpak ];

    services.flatpak = {
      enable = true;
      packages = [
        "com.github.tchx84.Flatseal" # permissões
        "io.github.flattool.Warehouse" # gerência de apps e dados
        "io.github.kolunmi.Bazaar" # loja do Flathub
      ];
      update.onActivation = true;
      update.auto = {
        enable = true;
        onCalendar = "daily";
      };
    };

    # A instalação no switch/boot precisa de rede.
    systemd.services.flatpak-managed-install = {
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
    };

    # Os Flatpaks só enxergam as fontes do sistema por /run/host/fonts.
    fonts.fontDir.enable = true;

    # Administradores gerenciam Flatpaks do sistema sem senha.
    security.polkit.extraConfig = ''
      polkit.addRule(function(action, subject) {
        if (action.id.indexOf("org.freedesktop.Flatpak") === 0 &&
            subject.isInGroup("wheel")) {
          return polkit.Result.YES;
        }
      });
    '';
  };
}

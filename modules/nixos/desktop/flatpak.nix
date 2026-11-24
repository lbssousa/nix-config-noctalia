# Flatpak (Flathub) para os aplicativos gráficos de usuário, declarados com o
# nix-flatpak. Cada feature acrescenta os seus em services.flatpak.packages
# (apps.nix, firefox.nix, brave.nix, bitwarden.nix, artcraft.nix); aqui ficam
# o serviço, as atualizações, a aparência e as ferramentas de gerência.
#
# Ficam em Nix só os apps fora do Flathub, os terminais, os editores (FHS,
# com as toolchains do host) e o que plugins e scripts chamam pela linha de
# comando (desktop/apps.nix).
#
# /var/lib/flatpak persiste em /persist (core/preservation.nix); os dados de
# cada app ficam em ~/.var/app/<id>.
#
# Override local: `flatpak override --user` (ou o Flatseal) vence os daqui,
# e apps instalados à mão (Bazaar, `flatpak install`) não são removidos
# (uninstallUnmanaged = false).
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
      uninstallUnmanaged = false;
      update.onActivation = true;
      update.auto = {
        enable = true;
        onCalendar = "daily";
      };

      # Aparência da Noctalia nos Flatpaks: o gtk.css que o template GTK grava
      # (claro/escuro chega pelo portal) e os ícones do usuário.
      overrides.settings.global.Context.filesystems = [
        "xdg-config/gtk-3.0:ro"
        "xdg-config/gtk-4.0:ro"
        "~/.local/share/icons:ro"
      ];
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

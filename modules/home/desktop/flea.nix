# Flea: gerenciador de arquivos (packages/_flea).
#
# Com my.fileManager = "flea" (home/base/xdg.nix), o Flea substitui o Nautilus
# só para este usuário, no lugar do `flea --default` (que escreveria no
# ~/.config/mimeapps.list e nos atalhos do Hyprland):
#  - pastas (inode/directory): o mimeapps.list de defaults do xdg.nix;
#  - org.freedesktop.FileManager1 ("Mostrar na pasta"): o serviço em
#    ~/.local/share/dbus-1/services vence o do Nautilus no sistema (o
#    diretório do usuário vem antes);
#  - portal FileChooser (diálogos de abrir/salvar): o backend
#    org.freedesktop.impl.portal.desktop.flea, registrado pelo
#    nixos/desktop/file-manager.nix; ~/.config/xdg-desktop-portal/umbriel-portals.conf
#    substitui o do sistema inteiro, então repete o resto dele.
{
  flake.modules.homeManager.flea =
    {
      config,
      lib,
      pkgs,
      osConfig,
      ...
    }:
    {
      xdg = lib.mkIf (config.my.fileManager == "flea") {
        dataFile."dbus-1/services/org.freedesktop.FileManager1.service".source =
          "${pkgs.flea}/share/flea/com.thisisgm.flea.FileManager1.service";

        configFile."xdg-desktop-portal/umbriel-portals.conf".text = lib.generators.toINI { } {
          preferred = lib.mapAttrs (_: v: lib.concatStringsSep ";" (lib.toList v)) (
            osConfig.xdg.portal.config.umbriel
            // {
              "org.freedesktop.impl.portal.FileChooser" = [ "flea" ];
            }
          );
        };
      };
    };
}

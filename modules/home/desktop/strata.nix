# Strata: gerenciador de arquivos GTK4 (packages/_strata).
# Configuração base gravada em ~/.config/strata/settings.toml via mutable-config.
# Override local: ~/.config/strata/settings.toml.local (ver home/lib/mutable-config.nix).
#
# Com my.fileManager = "strata" (home/base/xdg.nix), o Strata substitui o
# Nautilus só para este usuário:
#  - org.freedesktop.FileManager1: o serviço em ~/.local/share/dbus-1/services
#    vence o do Nautilus no sistema (o diretório do usuário vem antes);
#  - portal FileChooser: ~/.config/xdg-desktop-portal/umbriel-portals.conf
#    substitui o do sistema inteiro, então repete o resto dele.
{
  flake.modules.homeManager.strata =
    {
      config,
      lib,
      pkgs,
      osConfig,
      ...
    }:
    {
      my.mutableConfigs."strata/settings.toml" = {
        format = "toml";
        base = {
          interface_font = lib.mkDefault "Adwaita Sans";
          text_size = lib.mkDefault 18;
          # Tema fixo (sem "Follow Omarchy"), escuro como a shell.
          mode = lib.mkDefault "theme";
          theme = lib.mkDefault "nord";
        };
      };

      xdg = lib.mkIf (config.my.fileManager == "strata") {
        dataFile."dbus-1/services/org.freedesktop.FileManager1.service".source =
          "${pkgs.strata}/share/strata/io.github.lgse.Strata.FileManager1.service";

        configFile."xdg-desktop-portal/umbriel-portals.conf".text = lib.generators.toINI { } {
          preferred = lib.mapAttrs (_: v: lib.concatStringsSep ";" (lib.toList v)) (
            osConfig.xdg.portal.config.umbriel
            // {
              "org.freedesktop.impl.portal.FileChooser" = [ "strata" ];
            }
          );
        };
      };
    };
}

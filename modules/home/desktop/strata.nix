# Strata: gerenciador de arquivos GTK4, do flake do próprio projeto (input
# strata em flake.nix, exposto como pkgs.strata em flake/packages.nix).
#
# Com my.fileManager = "strata" (home/base/xdg.nix), o Strata substitui o
# Nautilus só para este usuário:
#  - pastas (inode/directory): o mimeapps.list de defaults do xdg.nix;
#  - org.freedesktop.FileManager1 ("Mostrar na pasta"): o serviço em
#    ~/.local/share/dbus-1/services vence o do Nautilus no sistema (o
#    diretório do usuário vem antes);
#  - portal FileChooser (diálogos de abrir/salvar): o backend
#    org.freedesktop.impl.portal.desktop.strata, registrado pelo
#    nixos/desktop/file-manager.nix; ~/.config/xdg-desktop-portal/umbriel-portals.conf
#    substitui o do sistema inteiro, então repete o resto dele.
#
# Aparência da Noctalia: o template "strata" da comunidade (input
# noctalia-templates-community) grava a paleta ativa em
# ~/.config/strata/themes/noctalia.toml, que o Strata relê ao vivo; a fonte da
# interface é a da shell.
#
# Configuração base em ~/.config/strata/settings.toml via mutable-config.
# Override local: ~/.config/strata/settings.toml.local (ver home/lib/mutable-config.nix).
{ inputs, ... }:
{
  flake.modules.homeManager.strata =
    {
      config,
      lib,
      pkgs,
      osConfig,
      ...
    }:
    lib.mkIf (config.my.fileManager == "strata") {
      my.mutableConfigs."strata/settings.toml" = {
        format = "toml";
        base = {
          mode = lib.mkDefault "theme";
          theme = lib.mkDefault "noctalia";
          interface_font = lib.mkDefault config.programs.noctalia.settings.shell.font_family;
          text_size = lib.mkDefault 18;
        };
      };

      programs.noctalia.settings.theme.templates.user.strata = {
        input_path = "${inputs.noctalia-templates-community}/strata/strata.toml";
        output_path = "${config.xdg.configHome}/strata/themes/noctalia.toml";
        pre_hook = "mkdir -p '${config.xdg.configHome}/strata/themes'";
      };

      xdg = {
        dataFile."dbus-1/services/org.freedesktop.FileManager1.service".source =
          "${pkgs.strata.fileManagerService}/share/dbus-1/services/io.github.lgse.Strata.FileManager1.service";

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

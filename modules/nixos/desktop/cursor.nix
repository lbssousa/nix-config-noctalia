# Tema de cursor Adwaita (24 px) como padrão de todos os usuários, do greeter
# à sessão. O Umbriel usa o mesmo tema (home/desktop/umbriel.nix) e exporta
# XCURSOR_THEME/XCURSOR_SIZE para o que ele abre.
#
# Override local: ~/.icons/default/index.theme ou XCURSOR_THEME/XCURSOR_SIZE
# (ex.: ~/.config/environment.d/), o [input.cursor] do ~/.config/umbriel/
# local.toml e o cursor-theme do dconf do usuário (gsettings), que vence o
# banco do sistema.
{
  flake.modules.nixos.cursor =
    { lib, pkgs, ... }:
    let
      theme = "Adwaita";
      size = 24;
    in
    {
      environment.systemPackages = [ pkgs.adwaita-icon-theme ];

      # Programas sem configuração própria (XWayland, Qt, apps que só leem
      # o ambiente).
      environment.sessionVariables = {
        XCURSOR_THEME = theme;
        XCURSOR_SIZE = toString size;
      };

      # Quem procura o tema "default" (share/icons/default/index.theme).
      xdg.icons.fallbackCursorThemes = [ theme ];

      # GTK e portais leem o cursor do org.gnome.desktop.interface.
      programs.dconf.profiles.user.databases = [
        {
          settings."org/gnome/desktop/interface" = {
            cursor-theme = theme;
            cursor-size = lib.gvariant.mkInt32 size;
          };
        }
      ];

      services.displayManager.noctalia-greeter.cursorTheme = {
        package = pkgs.adwaita-icon-theme;
        name = theme;
      };
    };
}

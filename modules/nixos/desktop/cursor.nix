# Tema de cursor Bibata (24 px) para todos os usuários, do greeter à sessão:
# Bibata-Modern-Ice (claro) no modo diurno e Bibata-Modern-Classic (escuro) no
# noturno. Na sessão, a troca acompanha o modo claro/escuro da Noctalia, que já
# alterna pelo horário solar (hook em home/desktop/noctalia.nix). Fora dela
# (greeter, XWayland e apps antes do primeiro hook) vale o tema noturno.
#
# Override local: o [input.cursor] do ~/.config/umbriel/local.toml (vence o
# cursor.toml que o hook escreve), XCURSOR_THEME/XCURSOR_SIZE (ex.:
# ~/.config/environment.d/) e o cursor-theme do dconf do usuário.
{
  flake.modules.nixos.cursor =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.my.cursor;
    in
    {
      options.my.cursor = {
        package = lib.mkOption {
          type = lib.types.package;
          default = pkgs.bibata-cursors;
          description = "Pacote com os temas de cursor diurno e noturno.";
        };
        day = lib.mkOption {
          type = lib.types.str;
          default = "Bibata-Modern-Ice";
          description = "Tema de cursor do modo claro (diurno).";
        };
        night = lib.mkOption {
          type = lib.types.str;
          default = "Bibata-Modern-Classic";
          description = "Tema de cursor do modo escuro (noturno) e padrão do sistema.";
        };
        size = lib.mkOption {
          type = lib.types.ints.positive;
          default = 24;
          description = "Tamanho do cursor em pixels lógicos.";
        };
      };

      config = {
        environment.systemPackages = [
          cfg.package
          # Não é mais o cursor, mas continua sendo o tema de ícones de
          # fallback do GTK.
          pkgs.adwaita-icon-theme
        ];

        # Programas sem configuração própria (XWayland, Qt, apps que só leem
        # o ambiente).
        environment.sessionVariables = {
          XCURSOR_THEME = cfg.night;
          XCURSOR_SIZE = toString cfg.size;
        };

        # Quem procura o tema "default" (share/icons/default/index.theme).
        xdg.icons.fallbackCursorThemes = [ cfg.night ];

        # GTK e portais leem o cursor do org.gnome.desktop.interface; o hook
        # da Noctalia grava o tema do modo atual no dconf do usuário.
        programs.dconf.profiles.user.databases = [
          {
            settings."org/gnome/desktop/interface" = {
              cursor-theme = cfg.night;
              cursor-size = lib.gvariant.mkInt32 cfg.size;
            };
          }
        ];

        services.displayManager.noctalia-greeter.cursorTheme = {
          inherit (cfg) package;
          name = cfg.night;
        };
      };
    };
}

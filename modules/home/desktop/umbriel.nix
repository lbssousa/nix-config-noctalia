# Umbriel com layout dwindle e os atalhos do Omarchy (Super = Mod).
#
# Camadas: o config.toml gerado aqui inclui, por último e opcionalmente,
#   local.toml    — overrides do próprio usuário (não gerenciado pelo Nix);
#   noctalia.toml — cores escritas pelo template de tema da Noctalia (vencem
#                   o local.toml nas chaves de cor; para cores próprias, tire
#                   "umbriel" de theme.templates.builtin_ids).
# `umbriel config validate` roda no build, então chaves inválidas quebram o
# switch em vez de quebrar a sessão.
{
  flake.modules.homeManager.umbriel =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      toml = pkgs.formats.toml { };
      cfg = config.my.umbriel;

      noctalia = action: "spawn:noctalia msg ${action}";
      once = action: {
        inherit action;
        repeat = false;
      };
      locked = action: {
        inherit action;
        allow_when_locked = true;
      };

      workspaceBinds = lib.listToAttrs (
        lib.concatMap (n: [
          (lib.nameValuePair "Mod+${toString n}" "workspace-switch:${toString n}")
          (lib.nameValuePair "Mod+Shift+${toString n}" "window-move-to-workspace:${toString n}")
        ]) (lib.range 1 9)
      );

      settings = {
        # Esta é a ordem que o script de apply do template de tema da Noctalia
        # impõe; com ela o arquivo (somente leitura) não precisa ser reescrito.
        # Por isso as cores vêm sempre da paleta ativa.
        include.optional.files = [
          "local.toml"
          "noctalia.toml"
        ];

        general = {
          mod_key = "Super";
        };

        input = {
          keyboard = {
            layout = "br";
            variant = "abnt2";
            numlock_toggle = true;
          };
          focus.follows_mouse = true;
          # Mesmo cursor do sistema (nixos/desktop/cursor.nix); o Umbriel o
          # exporta como XCURSOR_THEME/XCURSOR_SIZE para o que ele abre.
          cursor = {
            theme = "Adwaita";
            size = 24;
          };
        };

        layout = {
          mode = "dwindle";
          gap = 8;
        };

        appearance.blur.radius = 3;

        hot_corners.top_left = {
          enabled = true;
          delay_ms = 500;
          action = "overview-open";
        };

        keybinds = {
          # Aplicativos
          "Mod+Return" = once "spawn:${cfg.terminal}";
          "Mod+Alt+Return" = once "spawn:${cfg.terminal} -e tmux new-session -A -s main";
          "Mod+Ctrl+Return" = once "spawn:${cfg.terminal} -e herdr";
          "Mod+Shift+Return" = once "spawn:firefox";
          "Mod+Shift+B" = once "spawn:firefox";
          "Mod+Shift+Alt+B" = once "spawn:firefox --private-window";
          "Mod+Shift+F" = once "spawn:${config.my.fileManagerApp.command}";
          "Mod+Shift+N" = once "spawn:${cfg.terminal} -e nvim";
          "Mod+Shift+D" = once "spawn:${cfg.terminal} -e lazydocker";
          "Mod+Shift+Slash" = once "spawn:bitwarden";
          "Mod+Ctrl+T" = once "spawn:${cfg.terminal} -e btop";

          # Web apps: Taskbar Tabs do Firefox nos seus containers (home/desktop/firefox.nix)
          "Mod+Shift+Y" = once "spawn:webapp youtube";
          "Mod+Shift+Alt+G" = once "spawn:webapp whatsapp";
          "Mod+Shift+Ctrl+G" = once "spawn:webapp google-messages";
          "Mod+Shift+Alt+T" = once "spawn:webapp teams";
          "Mod+Shift+S" = once "spawn:webapp google-maps";
          "Mod+Shift+P" = once "spawn:webapp google-photos";
          "Mod+Shift+X" = once "spawn:webapp x";

          # Menus da Noctalia
          "Mod" = noctalia "panel-toggle launcher";
          "Mod+Alt+Space" = once (noctalia "panel-toggle control-center");
          "Mod+Escape" = once (noctalia "panel-toggle session");
          "XF86PowerOff" = locked (noctalia "panel-toggle session");
          "Mod+Ctrl+E" = once (noctalia "panel-toggle launcher /emo");
          "Mod+Ctrl+V" = once (noctalia "panel-toggle clipboard");
          "Mod+Ctrl+Space" = once (noctalia "panel-toggle wallpaper");
          "Mod+Shift+Ctrl+Space" = once (noctalia "settings-toggle theme");
          "Mod+L" = once (noctalia "session lock");
          "Mod+Comma" = noctalia "notification-clear-active";
          "Mod+Alt+Comma" = noctalia "notification-invoke-latest";
          "Mod+K" = once "cheatsheet-toggle";

          # Captura de tela
          "Print" = once (noctalia "screenshot-region");
          "Shift+Print" = once (noctalia "screenshot-fullscreen");
          "Mod+Print" = once (noctalia "screenshot-annotate");
          "Alt+Print" = once "spawn:noctalia msg plugin noctalia/screen_recorder:service all toggle";

          # Janelas
          "Mod+W" = once "window-close";
          "Mod+T" = once "window-toggle-floating";
          "Mod+F" = once "window-toggle-fullscreen";
          "Mod+Alt+F" = once "window-toggle-maximize";
          "Mod+O" = once "window-toggle-pinned";
          # Super+J (alternar o split, no Omarchy) não tem ação equivalente nesta
          # versão do Umbriel.
          "Mod+Ctrl+L" = once "workspace-set-layout:toggle";
          "Mod+Left" = "window-focus-left";
          "Mod+Right" = "window-focus-right";
          "Mod+Up" = "window-focus-up";
          "Mod+Down" = "window-focus-down";
          "Mod+Shift+Left" = "window-swap-left";
          "Mod+Shift+Right" = "window-swap-right";
          "Mod+Shift+Up" = "window-swap-up";
          "Mod+Shift+Down" = "window-swap-down";
          "Mod+Minus" = "window-modify-primary-extent:-0.1";
          "Mod+Equal" = "window-modify-primary-extent:+0.1";
          "Alt+Tab" = "window-focus-next";
          "Alt+Shift+Tab" = "window-focus-previous";
          "Mod+Shift+Escape" = {
            action = "shortcuts-inhibit-toggle";
            allow_when_inhibited = true;
            repeat = false;
          };

          # Áreas de trabalho e scratchpad
          "Mod+Tab" = "workspace-next";
          "Mod+Shift+Tab" = "workspace-previous";
          "Mod+Ctrl+Tab" = "workspace-focus-last";
          "Mod+S" = "scratchpad-toggle";
          "Mod+Alt+S" = once "window-move-to-scratchpad";
          "Mod+Grave" = once "overview-toggle";

          # Mídia, volume e brilho
          "XF86AudioRaiseVolume" = locked (noctalia "volume-up");
          "XF86AudioLowerVolume" = locked (noctalia "volume-down");
          "XF86AudioMute" = locked (noctalia "volume-mute");
          "XF86AudioMicMute" = locked (noctalia "mic-mute");
          "XF86MonBrightnessUp" = locked (noctalia "brightness-up");
          "XF86MonBrightnessDown" = locked (noctalia "brightness-down");
          "XF86AudioPlay" = locked (noctalia "media play-pause");
          "XF86AudioPause" = locked (noctalia "media play-pause");
          "XF86AudioNext" = locked (noctalia "media next");
          "XF86AudioPrev" = locked (noctalia "media previous");

          # Ditado (voxtype)
          "Mod+Ctrl+X" = once "spawn:voxtype record toggle";
        }
        // workspaceBinds;

        window_rule = [
          {
            blur = true;
            blur_optimized = false;
          }
          {
            match.app_id = "^dev.noctalia.Noctalia$";
            default_floating = true;
            default_floating_size_px = {
              width = 1020;
              height = 900;
            };
          }
          {
            match.app_id = "^dev.noctalia.UmbrielSharePicker$";
            default_floating = true;
          }
          # Web apps do Firefox (Taskbar Tabs, classe firefox.webapp-<id>)
          # maximizados como o "fullscreen, 1" do Hyprland: ocupam a área do
          # layout, com a barra e os gaps, e continuam no tiling.
          {
            match.app_id = "^firefox\\.webapp-";
            default_maximize = true;
          }
          {
            match.title = "^(Picture-in-Picture|Picture in picture)$";
            default_floating = true;
            default_position = {
              x = 20;
              y = 20;
              anchor = "bottom_right";
            };
          }
        ];

        layer_rule = [
          {
            match.namespace = "^noctalia-(bar-[^\"]+|notification|dock|panel|attached-panel|osd|desktop-widget-[^\"]*)$";
            blur = true;
            blur_ignore_alpha = 0.5;
            blur_popups = true;
            blur_optimized = false;
          }
        ];
      };

      rawConfig = toml.generate "umbriel-config.toml" (lib.recursiveUpdate settings cfg.extraSettings);
    in
    {
      options.my.umbriel = {
        terminal = lib.mkOption {
          type = lib.types.str;
          default = "ghostty";
          description = "Terminal aberto por Super+Return.";
        };
        extraSettings = lib.mkOption {
          inherit (toml) type;
          default = { };
          description = "Chaves extras mescladas na config gerada (overrides declarativos).";
        };
      };

      config.xdg.configFile."umbriel/config.toml".source =
        pkgs.runCommand "umbriel-config.toml" { nativeBuildInputs = [ pkgs.umbriel ]; }
          ''
            cp ${rawConfig} config.toml
            HOME=$PWD umbriel config validate -c config.toml
            cp config.toml $out
          '';
    };
}

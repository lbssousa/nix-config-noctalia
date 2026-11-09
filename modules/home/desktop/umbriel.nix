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

      noctalia = action: "spawn noctalia msg ${action}";
      calculator = once (noctalia "panel-toggle samuelskovbakke/calculator-plus:panel");
      # Janelas que o Omarchy deixa translúcidas: a tag "terminal" de
      # default/hypr/apps/terminals.lua (mais o console Quake) e o Nautilus
      # (mais o Flea, que o substitui aqui).
      terminalApps = "Alacritty|kitty|com\\.mitchellh\\.ghostty|foot|org\\.codeberg\\.dnkl\\.foot|wezterm|org\\.wezfurlong\\.wezterm|dev\\.lbssousa\\.console";
      fileManagerApps = "org\\.gnome\\.Nautilus|com\\.thisisgm\\.flea";
      transparentApps = "^(${terminalApps}|${fileManagerApps})$";

      # Modos de omarchy-hyprland-window-transparency (Omarchy 4.5):
      #  - transparent (o padrão do Omarchy): o.transparent_window com
      #    "0.985 0.96" (ativa/inativa) nos apps acima;
      #  - glassy: o mesmo, mais o fundo dos terminais a 0.65 (terminals.nix),
      #    os gerenciadores de arquivos inteiros a 0.75 ("0.75 0.75", pois o
      #    GTK desenha o fundo sólido) e o blur de default/hypr/glass.lua;
      #  - opaque: nenhuma translucência.
      # A transição de foco é suave ([animation.windows_opacity], ligada por
      # padrão). O blur das janelas já vem da primeira regra de window_rule.
      transparencyRules =
        lib.optionals (cfg.transparency != "opaque") [
          {
            match.app_id = transparentApps;
            opacity = 0.985;
          }
          {
            match.app_id = transparentApps;
            match.is_focused = false;
            opacity = 0.96;
          }
        ]
        ++ lib.optional (cfg.transparency == "glassy") {
          match.app_id = "^(${fileManagerApps})$";
          opacity = 0.75;
        };

      # glass.lua: size 4, passes 2, contrast 1.0, brightness 0.75,
      # noise 0.01 (vibrancy não tem equivalente no Umbriel).
      blur =
        if cfg.transparency == "glassy" then
          {
            radius = 4;
            passes = 2;
            contrast = 1.0;
            brightness = 0.75;
            noise = 1.0e-2;
          }
        else
          { radius = 3; };
      # Trio de layouts do Omarchy (tiling, scrolling, flutuante); a lista ao
      # contrário volta ao anterior.
      layouts = [
        "dwindle"
        "scrolling"
        "stacking"
      ];
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
          (lib.nameValuePair "Mod+${toString n}" "workspace-switch ${toString n}")
          (lib.nameValuePair "Mod+Shift+${toString n}" "window-move-to-workspace ${toString n}")
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
            # Caps Lock = Esc, Shift + Caps Lock = Caps Lock (nixos/core/locale.nix).
            options = "caps:escape_shifted_capslock";
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

        appearance = { inherit blur; };

        # Scratchpads nomeados: o comum (Mod+S) e o console Quake (Mod+'), que
        # desce do topo com o desktop escurecido e abre um shell na primeira vez.
        # Com algum nome definido o "default" implícito deixa de existir.
        scratchpad = [
          { name = "scratchpad"; }
          {
            name = "console";
            spawn_when_empty = cfg.consoleCommand;
          }
        ];

        hot_corners.top_left = {
          enabled = true;
          delay_ms = 500;
          action = "overview-open";
        };

        keybinds = {
          # Aplicativos
          "Mod+Return" = once "spawn ${cfg.terminal}";
          "Mod+Alt+Return" = once "spawn ${cfg.terminal} -e tmux new-session -A -s main";
          "Mod+Ctrl+Return" = once "spawn ${cfg.terminal} -e herdr";
          "Mod+Shift+Return" = once "spawn firefox";
          "Mod+Shift+B" = once "spawn firefox";
          "Mod+Shift+Alt+B" = once "spawn firefox --private-window";
          "Mod+Shift+F" = once "spawn ${config.my.fileManagerApp.command}";
          "Mod+Shift+N" = once "spawn ${cfg.terminal} -e nvim";
          "Mod+Shift+D" = once "spawn ${cfg.terminal} -e lazydocker";
          "Mod+Shift+Slash" = once "spawn bitwarden";
          "Mod+Shift+T" = once "spawn ${cfg.terminal} -e btop";
          "Mod+Shift+Q" = calculator;
          "XF86Calculator" = calculator;

          # Web apps: Taskbar Tabs do Firefox nos seus containers (home/desktop/firefox.nix)
          "Mod+Shift+Y" = once "spawn webapp youtube";
          "Mod+Shift+Alt+G" = once "spawn webapp whatsapp";
          "Mod+Shift+Ctrl+G" = once "spawn webapp google-messages";
          "Mod+Shift+Alt+T" = once "spawn webapp teams";
          "Mod+Shift+S" = once "spawn webapp google-maps";
          "Mod+Shift+P" = once "spawn webapp google-photos";
          "Mod+Shift+X" = once "spawn webapp x";

          # Menus da Noctalia
          "Mod" = noctalia "panel-toggle launcher";
          "Mod+Alt+Space" = once (noctalia "panel-toggle control-center");
          "Mod+Escape" = once (noctalia "panel-toggle session");
          "XF86PowerOff" = locked (noctalia "panel-toggle session");
          "Mod+Ctrl+E" = once (noctalia "panel-toggle launcher /emo");
          "Mod+Ctrl+V" = once (noctalia "panel-toggle clipboard");
          "Mod+Ctrl+Space" = once (noctalia "panel-toggle wallpaper");
          "Mod+Ctrl+W" = once (noctalia "panel-toggle wallpaper");
          "Mod+Shift+Ctrl+Space" = once (noctalia "settings-toggle theme");
          "Mod+Ctrl+T" = once (noctalia "settings-toggle theme");
          "Mod+Ctrl+N" = once (noctalia "panel-toggle control-center network");
          # Digitais, chaves FIDO2, cartão OpenPGP e chaves SSH residentes
          # (plugin lbssousa/security-hardware).
          "Mod+Ctrl+K" = once (noctalia "panel-toggle lbssousa/security-hardware:panel");
          "Mod+Ctrl+Alt+F" = once (noctalia "bar-toggle");
          "Mod+L" = once (noctalia "session lock");
          "Mod+K" = once "cheatsheet-toggle";

          # Notificações (Omarchy 4.5). A Noctalia não dispensa uma só: Mod+Alt+,
          # dispensa as ativas, como Mod+Shift+,.
          "Mod+Comma" = once (noctalia "notification-invoke-latest");
          "Mod+Alt+Comma" = once (noctalia "notification-clear-active");
          "Mod+Shift+Comma" = once (noctalia "notification-clear-active");
          "Mod+Ctrl+Comma" = once (noctalia "panel-toggle control-center notifications");
          "Mod+Shift+Alt+Comma" = once (noctalia "panel-toggle control-center notifications");
          "Mod+Ctrl+Alt+Comma" = once (noctalia "notification-dnd-toggle");

          # Captura de tela
          "Print" = once (noctalia "screenshot-region");
          "Shift+Print" = once (noctalia "screenshot-fullscreen");
          "Mod+Ctrl+Alt+C" = once (noctalia "screenshot-region");
          "Mod+Print" = once (noctalia "screenshot-annotate");
          "Alt+Print" = once "spawn noctalia msg plugin noctalia/screen_recorder:service all toggle";

          # Janelas
          "Mod+W" = once "window-close";
          "Mod+Q" = once "window-close";
          # Só janelas flutuantes (layout stacking) minimizam no Umbriel.
          "Mod+M" = once "window-minimize";
          "Mod+Alt+M" = once "window-restore-minimized";
          "Mod+T" = once "window-toggle-floating";
          "Mod+F" = once "window-toggle-fullscreen";
          "Mod+Alt+F" = once "window-toggle-maximize";
          # Fullscreen dentro do tile (windowed fullscreen), como o
          # "fullscreenstate 0 2" do Hyprland.
          "Mod+Ctrl+F" = once "window-toggle-windowed-fullscreen";
          "Mod+O" = once "window-toggle-pinned";
          "Mod+J" = once "layout-toggle-split";
          # No Omarchy, Super+L alterna o layout e Super+Ctrl+L bloqueia; aqui
          # é o inverso, e Mod+Ctrl+Alt+L faz o papel do Super+Alt+L (volta).
          "Mod+Ctrl+L" = once "workspace-set-layout toggle ${lib.concatStringsSep " " layouts}";
          "Mod+Ctrl+Alt+L" =
            once "workspace-set-layout toggle ${lib.concatStringsSep " " (lib.reverseList layouts)}";
          # Na borda, o foco passa para o monitor vizinho.
          "Mod+Left" = "window-focus-or-output-left";
          "Mod+Right" = "window-focus-or-output-right";
          "Mod+Up" = "window-focus-or-output-up";
          "Mod+Down" = "window-focus-or-output-down";
          "Mod+Shift+Ctrl+Left" = once "window-move-to-output-left";
          "Mod+Shift+Ctrl+Right" = once "window-move-to-output-right";
          "Mod+Shift+Ctrl+Up" = once "window-move-to-output-up";
          "Mod+Shift+Ctrl+Down" = once "window-move-to-output-down";
          "Mod+Shift+Left" = "window-swap-left";
          "Mod+Shift+Right" = "window-swap-right";
          "Mod+Shift+Up" = "window-swap-up";
          "Mod+Shift+Down" = "window-swap-down";
          "Mod+Minus" = "window-modify-primary-extent -0.1";
          "Mod+Equal" = "window-modify-primary-extent +0.1";
          "Alt+Tab" = "window-focus-next";
          "Alt+Shift+Tab" = "window-focus-previous";
          "Mod+Shift+Escape" = {
            action = "shortcuts-inhibit-toggle";
            allow_when_inhibited = true;
            repeat = false;
          };

          # Áreas de trabalho e scratchpads. O overview fica no canto superior
          # esquerdo; o grave (Super+` no Omarchy) não existe no ABNT2, e o
          # console Quake usa a tecla na mesma posição, o apóstrofo.
          "Mod+Tab" = "workspace-next";
          "Mod+Shift+Tab" = "workspace-previous";
          "Mod+Ctrl+Tab" = "workspace-focus-last";
          "Mod+S" = "scratchpad-toggle scratchpad";
          "Mod+Alt+S" = once "window-move-to-scratchpad scratchpad";
          "Mod+Apostrophe" = "scratchpad-toggle console";
          "Mod+Shift+Apostrophe" = once "window-move-to-scratchpad console";

          # Mídia, volume e brilho
          "XF86AudioRaiseVolume" = locked (noctalia "volume-up");
          "XF86AudioLowerVolume" = locked (noctalia "volume-down");
          "XF86AudioMute" = locked (noctalia "volume-mute");
          "XF86AudioMicMute" = locked (noctalia "mic-mute");
          "XF86MonBrightnessUp" = locked (noctalia "brightness-up");
          "XF86MonBrightnessDown" = locked (noctalia "brightness-down");
          # Luz do teclado; Ctrl + brilho serve nos teclados sem as teclas próprias.
          "XF86KbdBrightnessUp" = locked (noctalia "keyboard-backlight-up");
          "XF86KbdBrightnessDown" = locked (noctalia "keyboard-backlight-down");
          "Ctrl+XF86MonBrightnessUp" = locked (noctalia "keyboard-backlight-up");
          "Ctrl+XF86MonBrightnessDown" = locked (noctalia "keyboard-backlight-down");
          "XF86KbdLightOnOff" = locked (noctalia "keyboard-backlight-toggle");
          "XF86AudioPlay" = locked (noctalia "media play-pause");
          "XF86AudioPause" = locked (noctalia "media play-pause");
          "XF86AudioNext" = locked (noctalia "media next");
          "XF86AudioPrev" = locked (noctalia "media previous");

          # Ditado (Superwhisper): começa e termina a gravação, que é colada
          # na janela em foco.
          "Mod+Ctrl+X" = once "spawn superwhisper record";
          "Alt+Space" = once "spawn superwhisper record";
        }
        // workspaceBinds;

        window_rule = [
          {
            blur = true;
            blur_optimized = false;
          }
        ]
        ++ transparencyRules
        ++ [
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
          # layout, com a barra e os gaps, e continuam no tiling. Abrem em
          # fullscreen dentro do tile (como o Mod+Ctrl+F), sem a interface do
          # Firefox.
          {
            match.app_id = "^firefox\\.webapp-";
            default_maximize = true;
            default_windowed_fullscreen = true;
          }
          # Console Quake: centralizado, colado no topo, metade da tela.
          {
            match.app_id = "^dev\\.lbssousa\\.console$";
            default_scratchpad = "console";
            default_floating = true;
            default_floating_size = {
              width = 0.5;
              height = 0.5;
            };
            default_position = {
              x = 0;
              y = 0;
              anchor = "top";
            };
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
        consoleCommand = lib.mkOption {
          type = lib.types.str;
          default = "ghostty --class=dev.lbssousa.console";
          description = "Comando do console Quake (Mod+'); a janela precisa do app id dev.lbssousa.console.";
        };
        transparency = lib.mkOption {
          type = lib.types.enum [
            "opaque"
            "transparent"
            "glassy"
          ];
          default = "glassy";
          description = "Translucência das janelas, como os modos do Omarchy 4.5 (omarchy-hyprland-window-transparency).";
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

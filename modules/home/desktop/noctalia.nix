# Noctalia: shell no estilo Omarchy (tema Tokyo Night, barra no topo, dock
# habilitado por padrão) com um conjunto de plugins pré-instalados.
#
# Camadas de configuração (todas mescladas pela própria Noctalia):
#   ~/.config/noctalia/config.toml    — gerado aqui (somente leitura);
#   ~/.config/noctalia/*.toml         — arquivos do usuário, ex. local.toml;
#   ~/.local/state/noctalia/settings.toml — mudanças feitas pela GUI (vencem).
{ inputs, ... }:
{
  flake.modules.homeManager.noctalia =
    { lib, ... }:
    {
      programs.noctalia = {
        enable = true;
        systemd.enable = true;

        settings = {
          # "Escala da Interface": toda a shell (painéis, launcher, central de
          # controle, notificações).
          accessibility.ui_scale = lib.mkDefault 1.0;

          shell = {
            font = lib.mkDefault "Adwaita Sans";
            clipboard_enabled = lib.mkDefault true;
            polkit_agent = lib.mkDefault true;
            # A config vem do Nix: o assistente de primeiro uso só atrapalharia.
            setup_wizard_enabled = lib.mkDefault false;
            telemetry_enabled = lib.mkDefault false;
            umbriel_overview_type_to_launch_enabled = lib.mkDefault true;
          };

          theme = {
            source = lib.mkDefault "builtin";
            builtin = lib.mkDefault "Tokyo-Night";
            mode = lib.mkDefault "dark";
            # Cores das outras aplicações acompanham a paleta da shell.
            templates = {
              enable_builtin_templates = lib.mkDefault true;
              builtin_ids = lib.mkDefault [
                "ghostty"
                "kitty"
                "foot"
                "gtk3"
                "gtk4"
                "qt"
                "btop"
                "umbriel"
              ];
            };
          };

          # Barra padrão da Noctalia com os widgets dos plugins abaixo, que não
          # entram na barra só por estarem habilitados. Cada lista substitui a
          # padrão inteira, por isso os widgets nativos estão repetidos aqui.
          # Emoji, calculadora e temas ficam de fora: já têm atalho no Umbriel
          # (Mod+Ctrl+E, launcher, Mod+Shift+Ctrl+Space).
          bar.default = {
            # Ícones, texto e espessura da barra ("Escala do Conteúdo").
            scale = lib.mkDefault 1.0;
            start = lib.mkDefault [
              "launcher"
              "wallpaper"
              "workspaces"
              "noctalia/umbriel-companion:bar"
              "media"
            ];
            center = lib.mkDefault [
              "clock"
              "notifications"
            ];
            end = lib.mkDefault [
              "tray"
              "clipboard"
              "jrohland/claudecode:pill"
              "weinguyen/opencode-companion:widget"
              "hy4ri/herdr:bar"
              "noctalia/screen_recorder:recorder"
              "alexander/screen-toolkit:widget"
              "mindnbytes/nix-status:status"
              "andrewdems/printers:printer"
              "bluetooth"
              "network"
              "volume"
              "battery"
              "control-center"
              "session"
            ];
          };

          # Rede e volume na barra só com o ícone, sem o nome da rede nem a
          # porcentagem; relógio com dia da semana e data (strftime, no idioma
          # do LC_TIME: "dom 18 out 20:15").
          widget = {
            clock.format = lib.mkDefault "{:%a %d %b  %H:%M}";
            network.show_label = lib.mkDefault false;
            volume.show_label = lib.mkDefault false;
          };

          # Atalhos padrão da central de controle mais os blocos dos plugins.
          control_center.shortcuts = lib.mkDefault (
            map (type: { inherit type; }) [
              "wifi"
              "bluetooth"
              "caffeine"
              "nightlight"
              "notification"
              "power_profile"
              "noctalia/screen_recorder:toggle"
              "alexander/screen-toolkit:toggle"
              "muhammadessam/umbriel-monitor-control:display"
            ]
          );

          # Habilitado para todos os usuários.
          dock = {
            enabled = lib.mkDefault true;
            position = lib.mkDefault "bottom";
            auto_hide = lib.mkDefault true;
            pinned = lib.mkDefault [
              "firefox"
              "com.mitchellh.ghostty"
              "org.gnome.Nautilus"
              "onlyoffice-desktopeditors"
            ];
          };

          plugins = {
            # Versões fixadas no flake.lock; atualizadas com `nix flake update`.
            auto_update = "none";
            source = [
              {
                name = "nix-official";
                kind = "path";
                location = "${inputs.noctalia-plugins-official}";
                enabled = true;
              }
              {
                name = "nix-community";
                kind = "path";
                location = "${inputs.noctalia-plugins-community}";
                enabled = true;
              }
            ];
            enabled = lib.mkDefault [
              # Oficiais
              "noctalia/screen_recorder"
              "noctalia/umbriel-companion"
              # Captura, cor, OCR e emoji (menu de captura do Omarchy)
              "alexander/screen-toolkit"
              "liamwh/emoji-picker"
              "samuelskovbakke/calculator-plus"
              # Temas (menu de temas do Omarchy)
              "theblackdon/theme-switcher"
              # Sistema
              "mindnbytes/nix-status"
              "knyrps/nix-search"
              "muhammadessam/umbriel-monitor-control"
              "andrewdems/printers"
              # Agentes de IA e terminal
              "jrohland/claudecode"
              "weinguyen/opencode-companion"
              "hy4ri/herdr"
            ];
          };
        };
      };
    };
}

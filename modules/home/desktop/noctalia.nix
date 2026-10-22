# Noctalia: shell no estilo Omarchy (tema Nord, barra no topo, dock
# habilitado por padrão) com um conjunto de plugins pré-instalados.
#
# Camadas de configuração (todas mescladas pela própria Noctalia):
#   ~/.config/noctalia/config.toml    — gerado aqui (somente leitura);
#   ~/.config/noctalia/*.toml         — arquivos do usuário, ex. local.toml;
#   ~/.local/state/noctalia/settings.toml — mudanças feitas pela GUI (vencem).
{ inputs, ... }:
{
  flake.modules.homeManager.noctalia =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      # Script hook para definir o wallpaper do Bluefin de acordo com o mês do ano
      # (01-bluefin em janeiro até 12-bluefin em dezembro) e sincronizar pares
      # diurno/noturno (day/night) quando o tema ou o período solar alternar.
      wallpaperPairSync = pkgs.writeShellScript "noctalia-wallpaper-pair-sync" ''
        set -euo pipefail

        # 1. Determina o modo atual (light ou dark)
        mode="''${NOCTALIA_THEME_MODE:-}"
        if [ -z "$mode" ]; then
          mode=$(${pkgs.noctalia}/bin/noctalia msg theme-mode-get 2>/dev/null || true)
          mode="''${mode//$'\n'/}"
        fi

        case "$mode" in
          light) period="day" ;;
          dark) period="night" ;;
          *) period="night" ;;
        esac

        # 2. Mês atual em dois dígitos (01 a 12)
        month=$(date +%m)

        # 3. Caminho alvo do wallpaper bluefin correspondente ao mês e período
        wallpapers_dir="${config.xdg.userDirs.pictures}/Wallpapers/bluefin"
        target_wp="$wallpapers_dir/$period/$month-bluefin.jpg"

        if [ -f "$target_wp" ]; then
          curr=$(${pkgs.noctalia}/bin/noctalia msg wallpaper-get 2>/dev/null || true)
          curr="''${curr//$'\n'/}"
          if [ "$curr" != "$target_wp" ]; then
            ${pkgs.noctalia}/bin/noctalia msg wallpaper-set "$target_wp"
          fi
        fi
      '';
    in
    {
      # Serviço e timer para garantir a transição de wallpaper na virada do mês
      systemd.user.services.noctalia-monthly-wallpaper = {
        Unit = {
          Description = "Sincronização do wallpaper mensal do Bluefin";
          PartOf = [ "graphical-session.target" ];
        };
        Service = {
          Type = "oneshot";
          ExecStart = "${wallpaperPairSync}";
        };
      };

      systemd.user.timers.noctalia-monthly-wallpaper = {
        Unit = {
          Description = "Temporizador diário para troca mensal do wallpaper do Bluefin";
          PartOf = [ "graphical-session.target" ];
        };
        Timer = {
          OnCalendar = "daily";
          Persistent = true;
        };
        Install = {
          WantedBy = [ "timers.target" ];
        };
      };

      programs.noctalia = {
        enable = true;
        systemd.enable = true;

        settings = {
          # "Escala da Interface": toda a shell (painéis, launcher, central de
          # controle, notificações).
          accessibility.ui_scale = lib.mkDefault 1.15;

          # Luz noturna com ativação automática baseada em geolocalização.
          nightlight = {
            enabled = lib.mkDefault true;
          };

          location = {
            auto_locate = lib.mkDefault true;
          };

          # Diretórios de wallpapers (com pastas separadas para modo claro e escuro).
          wallpaper = {
            directory = lib.mkDefault "${config.xdg.userDirs.pictures}/Wallpapers";
            directory_light = lib.mkDefault "${config.xdg.userDirs.pictures}/Wallpapers/bluefin/day";
            directory_dark = lib.mkDefault "${config.xdg.userDirs.pictures}/Wallpapers/bluefin/night";
            default.path = lib.mkDefault "${config.xdg.userDirs.pictures}/Wallpapers/bluefin/night/01-bluefin.jpg";
          };

          # Hooks para sincronização do wallpaper em pares diurno/noturno.
          hooks = {
            theme_mode_changed = "${wallpaperPairSync}";
            started = "${wallpaperPairSync}";
          };

          shell = {
            font = lib.mkDefault "Adwaita Sans";
            clipboard_enabled = lib.mkDefault true;
            polkit_agent = lib.mkDefault true;
            # Pinentry do GnuPG e SSH_ASKPASS no mesmo painel do polkit
            # (nixos/security/secret-prompts.nix aponta o gpg-agent e o
            # SSH_ASKPASS para eles, para todos os usuários).
            pinentry = lib.mkDefault true;
            ssh_askpass = lib.mkDefault true;
            # A config vem do Nix: o assistente de primeiro uso só atrapalharia.
            setup_wizard_enabled = lib.mkDefault false;
            telemetry_enabled = lib.mkDefault false;
            umbriel_overview_type_to_launch_enabled = lib.mkDefault true;
          };

          theme = {
            source = lib.mkDefault "builtin";
            builtin = lib.mkDefault "Nord";
            mode = lib.mkDefault "auto";
            # Superfícies da própria shell sempre escuras; o modo acima (auto)
            # continua valendo para os templates das outras aplicações.
            shell_mode = lib.mkDefault "dark";
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
            scale = lib.mkDefault 1.15;
            background_opacity = lib.mkDefault 0.75;
            # Flutuante: afastada da borda de cima e das laterais da tela.
            margin_edge = lib.mkDefault 8;
            margin_ends = lib.mkDefault 8;
            start = lib.mkDefault [
              "launcher"
              "wallpaper"
              "workspaces"
              "noctalia/umbriel-companion:bar"
              "media"
            ];
            # À esquerda do relógio: captura de tela (screen-toolkit), gravação
            # de tela, luz noturna, notificações e cafeína. O relógio é ancorado
            # no centro da barra (anchor = true), e o status do NixOS fica
            # imediatamente à sua direita.
            center = lib.mkDefault [
              "alexander/screen-toolkit:widget"
              "noctalia/screen_recorder:recorder"
              "nightlight"
              "notifications"
              "caffeine"
              "clock"
              "mindnbytes/nix-status:status"
            ];
            end = lib.mkDefault [
              "tray"
              "clipboard"
              "group:ai"
              "andrewdems/printers:printer"
              "bluetooth"
              "network"
              "volume"
              "battery"
              "control-center"
              "session"
            ];
            # Plugins de IA numa cápsula só ("group:ai" na lista acima).
            capsule_group = lib.mkDefault [
              {
                id = "ai";
                members = [
                  "ayagmar/headroom:usage"
                  "weinguyen/opencode-companion:widget"
                  "hy4ri/herdr:bar"
                ];
              }
            ];
          };

          # Rede e volume na barra só com o ícone, sem o nome da rede nem a
          # porcentagem; relógio com dia da semana e data (strftime, no idioma
          # do LC_TIME: "dom 18 out 20:15").
          widget = {
            clock = {
              format = lib.mkDefault "{:%a %d %b  %H:%M}";
              # Ancorado no centro da barra para que o relógio fique na linha média
              # exata do monitor, sem ser deslocado pelos widgets ao seu redor.
              anchor = lib.mkDefault true;
            };
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
            # Ocultação inteligente: visível com o workspace vazio, escondida
            # quando ele tem janelas (reaparece na borda). auto_hide é o modo
            # que só esconde quando o ponteiro sai da dock.
            auto_hide = lib.mkDefault false;
            smart_auto_hide = lib.mkDefault true;
            # Sem zona exclusiva: escondida, a dock não deixa a faixa vazia
            # embaixo das janelas lado a lado. Revelada, fica por cima delas.
            reserve_space = lib.mkDefault false;
            # Flutuante: afastada da borda de baixo da tela.
            margin_edge = lib.mkDefault 8;
            pinned = lib.mkDefault [
              "firefox"
              "com.mitchellh.ghostty"
              "io.github.lgse.Strata"
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
              "noctalia/timer"
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
              # Limites dos planos do Claude Code, do Codex e do Antigravity
              "ayagmar/headroom"
              "weinguyen/opencode-companion"
              "hy4ri/herdr"
            ];
          };
        };
      };
    };
}

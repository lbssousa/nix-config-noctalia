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

          # 5 minutos sem atividade: bloqueia a tela e suspende. A cafeína
          # (ou qualquer inibidor de ociosidade, como um vídeo tocando) impede.
          # Definir um comportamento aqui tira os padrões da Noctalia (bloqueio
          # e monitor desligado, ambos desativados).
          idle.behavior.suspend = {
            enabled = lib.mkDefault true;
            timeout = lib.mkDefault 300;
            action = lib.mkDefault "lock_and_suspend";
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
            # Cores das outras aplicações acompanham a paleta da shell. Os
            # aplicativos de terminal (emuladores e starship) são a exceção:
            # usam sempre a variante escura, conforme o remapeamento dos
            # templates em flake/packages.nix.
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
            # Flutuante: 4 px da borda de cima e 80 px de cada lateral da tela.
            margin_edge = lib.mkDefault 4;
            margin_ends = lib.mkDefault 80;
            start = lib.mkDefault [
              "launcher"
              "wallpaper"
              "workspaces"
              "spacer-start"
              "media"
            ];
            # Central de controle à esquerda do relógio; área de transferência
            # e notificações à direita ("group:inbox"), com um respiro de cada
            # lado. O relógio é ancorado no centro da barra (anchor = true).
            center = lib.mkDefault [
              "control-center"
              "spacer-clock-left"
              "clock"
              "spacer-clock-right"
              "group:inbox"
            ];
            end = lib.mkDefault [
              "tray"
              "spacer-tray"
              "felipeartur/ai-usagebar:bar"
              "andrewdems/printers:printer"
              "mindnbytes/nix-status:status"
              "group:toggles"
              "group:system"
              "session"
            ];
            # Cápsulas citadas nas listas acima ("group:<id>").
            capsule_group = lib.mkDefault [
              {
                id = "system";
                members = [
                  "bluetooth"
                  "network"
                  "volume"
                  "battery"
                ];
              }
              {
                id = "inbox";
                members = [
                  "clipboard"
                  "notifications"
                ];
              }
              {
                id = "toggles";
                members = [
                  "noctalia/umbriel-companion:bar"
                  "nightlight"
                  "caffeine"
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
            # Espaçadores da barra, um por posição (os ids repetidos nas listas
            # seriam o mesmo widget).
            spacer-start.type = "spacer";
            spacer-clock-left.type = "spacer";
            spacer-clock-right.type = "spacer";
            spacer-tray.type = "spacer";
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
              config.my.fileManagerApp.appId
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
              "notfinaldev/agentik"
              "miguelfm/ai-triage"
              # Uso dos planos de IA na barra
              "felipeartur/ai-usagebar"
            ];
          };

          # Logos coloridos pela paleta da shell no status do NixOS.
          plugin_settings."mindnbytes/nix-status".use_themed_logos = lib.mkDefault true;
        };
      };
    };
}

# Noctalia: shell no estilo Omarchy (paleta padrão Noctalia, barra no topo, dock
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
      osConfig,
      pkgs,
      ...
    }:
    let
      cursor = osConfig.my.cursor;

      # Tema de cursor do modo atual (nixos/desktop/cursor.nix): o diurno no
      # modo claro e o noturno no escuro, nas três fontes que os programas
      # leem. O Umbriel recarrega o cursor.toml sozinho; o GTK e os portais
      # seguem o dconf na hora; o ambiente do systemd vale para o que for
      # aberto depois. Só escreve o que mudou.
      cursorModeSync = pkgs.writeShellScript "noctalia-cursor-mode-sync" ''
        set -euo pipefail

        mode="''${NOCTALIA_THEME_MODE:-}"
        if [ -z "$mode" ]; then
          mode=$(${pkgs.noctalia}/bin/noctalia msg theme-mode-get 2>/dev/null || true)
          mode="''${mode//$'\n'/}"
        fi
        case "$mode" in
          light) theme=${lib.escapeShellArg cursor.day} ;;
          *) theme=${lib.escapeShellArg cursor.night} ;;
        esac

        file="${config.xdg.configHome}/umbriel/cursor.toml"
        content=$(printf '# Escrito pelo hook da Noctalia (modo %s); não editar.\n[input.cursor]\ntheme = "%s"' "$mode" "$theme")
        if [ "$(cat "$file" 2>/dev/null || true)" != "$content" ]; then
          mkdir -p "''${file%/*}"
          printf '%s\n' "$content" >"$file.tmp"
          mv -f "$file.tmp" "$file"
        fi

        key=/org/gnome/desktop/interface/cursor-theme
        if [ "$(${pkgs.dconf}/bin/dconf read "$key" 2>/dev/null || true)" != "'$theme'" ]; then
          ${pkgs.dconf}/bin/dconf write "$key" "'$theme'" || true
        fi

        systemctl --user set-environment XCURSOR_THEME="$theme" || true
      '';

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

        [ -f "$target_wp" ] || exit 0

        noctalia=${pkgs.noctalia}/bin/noctalia

        # 4. Padrão e, por cima, cada monitor conectado: um wallpaper por
        # monitor ([wallpaper.monitors.<conector>] no estado da Noctalia)
        # vence o padrão, e wallpaper-set sem conector não o substitui.
        sync_wp() {
          local curr
          curr=$("$noctalia" msg wallpaper-get "$@" 2>/dev/null || true)
          curr="''${curr//$'\n'/}"
          if [ "$curr" != "$target_wp" ]; then
            "$noctalia" msg wallpaper-set "$@" "$target_wp" || true
          fi
        }

        sync_wp
        for status in /sys/class/drm/card*-*/status; do
          [ -r "$status" ] || continue
          [ "$(cat "$status")" = connected ] || continue
          connector=$(basename "$(dirname "$status")")
          sync_wp "''${connector#card*-}"
        done
      '';

      # Hook de troca de modo claro/escuro (e de início da shell): wallpaper e
      # cursor do período.
      themeModeSync = pkgs.writeShellScript "noctalia-theme-mode-sync" ''
        ${cursorModeSync} || true
        exec ${wallpaperPairSync}
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
            theme_mode_changed = "${themeModeSync}";
            started = "${themeModeSync}";
          };

          shell = {
            font_family = lib.mkDefault "Adwaita Sans";
            clipboard_enabled = lib.mkDefault true;
            polkit_agent = lib.mkDefault true;
            # A config vem do Nix: o assistente de primeiro uso só atrapalharia.
            setup_wizard_enabled = lib.mkDefault false;
            telemetry_enabled = lib.mkDefault false;
            umbriel_overview_type_to_launch_enabled = lib.mkDefault true;
          };

          theme = {
            # Paleta padrão da Noctalia (embutida).
            source = lib.mkDefault "builtin";
            builtin = lib.mkDefault "Noctalia";
            mode = lib.mkDefault "auto";
            # Superfícies da própria shell acompanham o modo acima (auto).
            shell_mode = lib.mkDefault "follow";
            # Cores das outras aplicações acompanham a paleta da shell. Os
            # aplicativos de terminal (emuladores e btop; o starship usa as
            # cores ANSI do terminal) são a exceção: usam sempre a variante
            # escura, conforme o remapeamento dos templates em
            # flake/packages.nix.
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
                "luciole"
              ];
            };
          };

          # Barra padrão da Noctalia com os widgets dos plugins abaixo, que não
          # entram na barra só por estarem habilitados. Cada lista substitui a
          # padrão inteira, por isso os widgets nativos estão repetidos aqui.
          # Emoji, calculadora e temas ficam de fora: já têm atalho no Umbriel
          # (Mod+Ctrl+E, launcher, Mod+Shift+Ctrl+Space). Sem launcher,
          # wallpaper e central de controle na barra.
          bar.default = {
            background_opacity = lib.mkDefault 1.0;
            # Flutuante: 4 px da borda superior e estreitada proporcionalmente ao
            # monitor para acomodar confortavelmente os widgets atuais sem cortar
            # o fim.
            margin_edge = lib.mkDefault 4;
            margin_ends = lib.mkDefault "15%";
            start = lib.mkDefault [
              "noctalia/umbriel-companion:bar"
              "workspaces"
            ];
            # À direita do relógio, depois de um respiro: área de transferência,
            # notificações e status do NixOS. O relógio é ancorado no centro da
            # barra (anchor = true).
            center = lib.mkDefault [
              "clock"
              "spacer-clock-right"
              "clipboard"
              "notifications"
              "mindnbytes/nix-status:status"
            ];
            # "usage": limites dos planos de IA (headroom; widget.usage abaixo),
            # com um respiro antes das impressoras e dos ícones do sistema,
            # todos soltos, sem cápsulas agrupadas.
            end = lib.mkDefault [
              "tray"
              "spacer-tray"
              "usage"
              "spacer-headroom-right"
              "andrewdems/printers:printer"
              "nightlight"
              "caffeine"
              "bluetooth"
              "network"
              "volume"
              "battery"
              "session"
            ];
            capsule_group = lib.mkDefault [ ];
          };

          # Rede e volume na barra só com o ícone, sem o nome da rede nem a
          # porcentagem; relógio com dia da semana e data (strftime, no idioma
          # do LC_TIME: "dom 18 out 20:15"), em negrito.
          widget = {
            clock = {
              format = lib.mkDefault "{:%a %d %b  %H:%M}";
              # Peso CSS (400 normal, 700 negrito); sem ele, o relógio herda o
              # da barra (500).
              font_weight = lib.mkDefault 700;
              # Ancorado no centro da barra para que o relógio fique na linha média
              # exata do monitor, sem ser deslocado pelos widgets ao seu redor.
              anchor = lib.mkDefault true;
            };
            network.show_label = lib.mkDefault false;
            volume.show_label = lib.mkDefault false;
            # Bateria some da barra quando a carga está completa.
            battery.hide_when_full = lib.mkDefault true;
            # Espaçadores da barra, um por posição (os ids repetidos nas listas
            # seriam o mesmo widget).
            spacer-clock-right.type = "spacer";
            spacer-tray.type = "spacer";
            spacer-headroom-right.type = "spacer";
            usage.type = "ayagmar/headroom:usage";
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
              # Configurações > Segurança (patch noctalia-security-hardware).
              "security"
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
            # Botão do launcher no fim da dock e pontos nos apps abertos.
            launcher_position = lib.mkDefault "end";
            show_dots = lib.mkDefault true;
            pinned = lib.mkDefault [
              config.my.browserApp.appId
              "com.mitchellh.ghostty"
              config.my.fileManagerApp.appId
              "org.onlyoffice.desktopeditors"
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
              # Plugin próprio (github.com/lbssousa/noctalia-secret-prompts),
              # fixado no flake.lock.
              {
                name = "nix-secret-prompts";
                kind = "path";
                location = "${inputs.noctalia-secret-prompts}";
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
              # Pinentry do GnuPG e SSH_ASKPASS num painel da shell
              # (nixos/security/secret-prompts.nix aponta o gpg-agent e o
              # SSH_ASKPASS para os clientes, para todos os usuários).
              "lbssousa/secret-prompts"
              # Agentes de IA e terminal
              # Limites dos planos do Claude Code, do Codex e do Antigravity
              "ayagmar/headroom"
              "weinguyen/opencode-companion"
              "hy4ri/herdr"
              "notfinaldev/agentik"
              "miguelfm/ai-triage"
            ];
          };

          # Logos coloridos pela paleta da shell no status do NixOS.
          plugin_settings."mindnbytes/nix-status".use_themed_logos = lib.mkDefault true;
        };
      };
    };
}

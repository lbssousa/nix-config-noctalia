# Noctalia: shell no estilo Omarchy (paleta Osaka jade, barra no topo, dock
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

          # Tela de bloqueio no serviço PAM próprio (security/pam-policy.nix),
          # para o "login" ficar só com a senha. Chave do PR #4132 (patch em
          # flake/packages.nix).
          lockscreen.pam_service = lib.mkDefault "noctalia-lock";

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
            # Paleta da comunidade (baixada e guardada em cache pela própria
            # Noctalia em ~/.local/state/noctalia/community-palettes no
            # primeiro uso; exige rede nesse primeiro carregamento).
            source = lib.mkDefault "community";
            community_palette = lib.mkDefault "Osaka jade";
            builtin = lib.mkDefault "Nord";
            mode = lib.mkDefault "auto";
            # Superfícies da própria shell acompanham o modo acima (auto).
            shell_mode = lib.mkDefault "follow";
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

          bar.order = lib.mkDefault [ "default" "dock" ];

          # Barra padrão da Noctalia com os widgets dos plugins abaixo, que não
          # entram na barra só por estarem habilitados. Cada lista substitui a
          # padrão inteira, por isso os widgets nativos estão repetidos aqui.
          # Emoji, calculadora e temas ficam de fora: já têm atalho no Umbriel
          # (Mod+Ctrl+E, launcher, Mod+Shift+Ctrl+Space). Sem launcher,
          # wallpaper e central de controle na barra.
          bar.default = {
            # Ícones, texto e espessura da barra ("Escala do Conteúdo").
            scale = lib.mkDefault 1.15;
            background_opacity = lib.mkDefault 1.0;
            # Estilo Unity: preenche toda a largura da tela, flush com o topo.
            margin_edge = lib.mkDefault 0;
            margin_ends = lib.mkDefault 0;
            radius = lib.mkDefault 0;
            start = lib.mkDefault [
              "noctalia/umbriel-companion:bar"
              "workspaces"
              "spacer-start"
              "media"
            ];
            # À direita do relógio, depois de um respiro: área de transferência
            # e notificações ("group:inbox"), impressoras e status do NixOS. O
            # relógio é ancorado no centro da barra (anchor = true).
            center = lib.mkDefault [
              "clock"
              "spacer-clock-right"
              "group:inbox"
              "andrewdems/printers:printer"
              "mindnbytes/nix-status:status"
            ];
            # "usage": limites dos planos de IA (headroom; widget.usage abaixo).
            end = lib.mkDefault [
              "tray"
              "spacer-tray"
              "usage"
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
                  "nightlight"
                  "caffeine"
                ];
              }
            ];
          };

          # Barra vertical na lateral esquerda emulando a Unity Dock:
          # preenche 100% da altura da tela, sempre visível (sem ocultação),
          # reserva espaço exclusivo e posiciona o launcher no final.
          # Escala 2.0 define os ícones para 32 px (baseGlyphSize 16 px * 2.0).
          bar.dock = {
            enabled = lib.mkDefault true;
            position = lib.mkDefault "left";
            thickness = lib.mkDefault 48;
            scale = lib.mkDefault 2.0;
            background_opacity = lib.mkDefault 1.0;
            margin_edge = lib.mkDefault 0;
            margin_ends = lib.mkDefault 0;
            radius = lib.mkDefault 0;
            auto_hide = lib.mkDefault false;
            smart_auto_hide = lib.mkDefault false;
            reserve_space = lib.mkDefault true;
            start = lib.mkDefault [
              "dock-taskbar"
            ];
            center = lib.mkDefault [ ];
            end = lib.mkDefault [
              "dock-launcher"
            ];
          };

          # Rede e volume na barra só com o ícone, sem o nome da rede nem a
          # porcentagem; relógio com dia da semana e data (strftime, no idioma
          # do LC_TIME: "dom 18 out 20:15").
          widget = {
            # Alternador de espaços de trabalho no estilo GNOME:
            # pílulas animadas sem rótulos de texto, altura ajustada (~10 px).
            # Usa papéis de cor semânticos da paleta para inversão automática
            # entre modo claro e escuro:
            #   - Painel escuro: on_surface (branco), on_surface_variant (cinza claro), outline_variant (cinza escuro);
            #   - Painel claro:  on_surface (escuro/preto), on_surface_variant (cinza escuro), outline_variant (cinza claro).
            workspaces = {
              style = lib.mkDefault "regular";
              show_labels = lib.mkDefault false;
              pill_scale = lib.mkDefault 0.55;
              active_pill_size = lib.mkDefault 3.2;
              inactive_pill_size = lib.mkDefault 1.0;
              focused_color = lib.mkDefault "on_surface";
              occupied_color = lib.mkDefault "on_surface_variant";
              empty_color = lib.mkDefault "outline_variant";
            };
            clock = {
              format = lib.mkDefault "{:%a %d %b  %H:%M}";
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
            spacer-start.type = "spacer";
            spacer-clock-right.type = "spacer";
            spacer-tray.type = "spacer";
            usage.type = "ayagmar/headroom:usage";

            # Widgets da barra vertical (emulação da Unity Dock)
            dock-taskbar = {
              type = "taskbar";
              pinned = lib.mkDefault [
                "google-chrome"
                "com.mitchellh.ghostty"
                config.my.fileManagerApp.appId
                "onlyoffice-desktopeditors"
              ];
              icon_scale = lib.mkDefault 1.0;
              item_spacing = lib.mkDefault 8;
            };
            dock-launcher = {
              type = "launcher";
              glyph = lib.mkDefault "grid-dots";
            };
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

          # Desativa o componente dock nativo (substituído por bar.dock para preencher 100% da altura).
          dock = {
            enabled = lib.mkDefault false;
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
              # Plugins da comunidade com o patch local do Headroom (cota do
              # Antigravity com os grupos do Gemini); ver
              # flake/packages.nix.
              {
                name = "nix-community";
                kind = "path";
                location = "${pkgs.noctalia-plugins-community}";
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

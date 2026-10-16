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
          shell = {
            font = lib.mkDefault "JetBrainsMono Nerd Font";
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

          # Habilitado para todos; o usuário abutre o desliga em
          # modules/users/abutre.nix.
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

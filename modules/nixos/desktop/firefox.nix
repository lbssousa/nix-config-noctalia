# Firefox (Flatpak org.mozilla.firefox), navegador padrão do sistema; cada
# usuário escolhe o seu com my.browser (home/base/xdg.nix).
#
# Políticas do sistema, na extensão org.mozilla.firefox.systemconfig, que o
# Flatpak monta em /app/etc/firefox (um diretório comum em
# /var/lib/flatpak/extension conta como extensão instalada). O arquivo é
# copiado, não ligado à store: o sandbox não enxerga /nix/store.
#  - abas de container ligadas (privacy.userContext.enabled), como padrão
#    (Status = "default": o usuário ainda muda em about:config);
#  - extensões do Bitwarden, Multi-Account Containers e os "<empresa>
#    Container" (Facebook, Google, Microsoft, Twitter, Discord, Amazon e
#    TikTok) instaladas por padrão (o usuário pode desativá-las, não
#    removê-las); as demais vêm da sincronização com a conta Mozilla de cada
#    usuário. O native messaging com o Bitwarden é do próprio Bitwarden em
#    Flatpak (nixos/security/bitwarden.nix). Os containers não são
#    declarados: cada "<empresa> Container" cria o seu, com o nome da
#    empresa, e abre nele os domínios dela. O da Microsoft inclui o GitHub, a
#    menos que se marque "Ignore GitHub" nas opções dele; o do Twitter inclui
#    o x.com. O YouTube Container fica de fora: o do Google já leva o YouTube;
#  - diálogo de arquivos pelo portal (o Luciole; nixos/desktop/file-manager.nix).
# As Taskbar Tabs (web apps) são ligadas no user.js de cada perfil, e os web
# apps (my.firefox.webapps) são do perfil de cada usuário:
# home/desktop/firefox.nix.
#
# O comando do navegador (atalhos, BROWSER) é o exportado pelo Flatpak,
# /var/lib/flatpak/exports/bin/org.mozilla.firefox, no PATH.
{
  flake.modules.nixos.firefox =
    { lib, pkgs, ... }:
    let
      # id da extensão → slug em addons.mozilla.org.
      extensions = {
        "{446900e4-71c2-419f-a6a7-df9c091e268b}" = "bitwarden-password-manager";
        "@testpilot-containers" = "multi-account-containers";
        "@contain-facebook" = "facebook-container";
        "@contain-google" = "google-container";
        "@better-contain-microsoft" = "better-microsoft-container";
        "@contain-twitter" = "twitter-container";
        "@contain-discord" = "discord-container";
        "@contain-amazon" = "amazon-container";
        "@tiktok-container" = "tiktok-container";
      };

      policies = (pkgs.formats.json { }).generate "policies.json" {
        policies = {
          DisableTelemetry = true;
          DontCheckDefaultBrowser = true;
          ExtensionSettings = lib.mapAttrs (_: slug: {
            installation_mode = "normal_installed";
            install_url = "https://addons.mozilla.org/firefox/downloads/latest/${slug}/latest.xpi";
          }) extensions;
          Preferences =
            let
              default = value: {
                Value = value;
                Status = "default";
              };
            in
            {
              "privacy.userContext.enabled" = default true;
              "privacy.userContext.ui.enabled" = default true;
              "widget.use-xdg-desktop-portal.file-picker" = default 1;
            };
        };
      };
      systemconfig = "/var/lib/flatpak/extension/org.mozilla.firefox.systemconfig/${pkgs.stdenv.hostPlatform.parsed.cpu.name}/stable";
    in
    {
      options.my.firefox = {
        webapps = lib.mkOption {
          description = ''
            Web apps criados como Taskbar Tabs do Firefox para todos os usuários
            (`webapp <id>` abre cada um no seu container).
          '';
          type = lib.types.attrsOf (
            lib.types.submodule {
              options = {
                name = lib.mkOption { type = lib.types.str; };
                url = lib.mkOption {
                  type = lib.types.str;
                  description = "URL de início.";
                };
                container = lib.mkOption {
                  type = lib.types.nullOr lib.types.str;
                  default = null;
                  description = ''
                    Nome do container em que o web app abre (null: sem
                    container), um dos criados pelas extensões. Até a extensão
                    criá-lo (na primeira vez que o Firefox abre), o web app abre
                    sem container; a partir do login seguinte, no container.
                  '';
                };
                icon = lib.mkOption {
                  type = lib.types.nullOr lib.types.str;
                  default = null;
                  description = ''
                    URL do ícone, para os sites que só o mostram com login
                    (null: o maior que o site declara no manifest ou nos
                    <link rel="icon">).
                  '';
                };
                scopes = lib.mkOption {
                  type = lib.types.listOf lib.types.str;
                  description = ''
                    "host[/caminho]" que continuam na janela do web app; o resto
                    abre no navegador.
                  '';
                };
              };
            }
          );
          default = {
            whatsapp = {
              name = "WhatsApp";
              url = "https://web.whatsapp.com/";
              container = "Facebook";
              scopes = [ "web.whatsapp.com" ];
            };
            youtube = {
              name = "YouTube";
              url = "https://www.youtube.com/";
              container = "Google";
              icon = "https://www.gstatic.com/images/branding/productlogos/youtube/v9/web-512dp/logo_youtube_color_1x_web_512dp.png";
              scopes = [
                "www.youtube.com"
                "youtube.com"
                "m.youtube.com"
              ];
            };
            google-maps = {
              name = "Google Maps";
              url = "https://www.google.com/maps";
              container = "Google";
              icon = "https://www.gstatic.com/images/branding/productlogos/maps_2025_round/v1/web-512dp/logo_maps_2025_round_color_1x_web_512dp.png";
              scopes = [
                "www.google.com/maps"
                "maps.google.com"
              ];
            };
            google-photos = {
              name = "Google Photos";
              url = "https://photos.google.com/";
              container = "Google";
              icon = "https://www.gstatic.com/images/branding/product/1x/photos_512dp.png";
              scopes = [ "photos.google.com" ];
            };
            google-messages = {
              name = "Google Messages";
              url = "https://messages.google.com/web";
              container = "Google";
              icon = "https://ssl.gstatic.com/android-messages-web/images/2026/pwa_round_v2_512.png";
              scopes = [ "messages.google.com" ];
            };
            google-contacts = {
              name = "Google Contacts";
              url = "https://contacts.google.com/";
              container = "Google";
              icon = "https://www.gstatic.com/images/branding/product/1x/contacts_2022_512dp.png";
              scopes = [ "contacts.google.com" ];
            };
            teams = {
              name = "Microsoft Teams";
              url = "https://teams.cloud.microsoft/";
              container = "Microsoft";
              scopes = [
                "teams.cloud.microsoft"
                "teams.microsoft.com"
                "teams.live.com"
              ];
            };
          };
        };
      };

      config = {
        services.flatpak.packages = [ "org.mozilla.firefox" ];

        # Serviço, não activationScript: no boot, a ativação roda antes de
        # /var/lib/flatpak (preservation) ser montado.
        systemd.services.firefox-flatpak-policies = {
          description = "Políticas do Firefox em Flatpak (org.mozilla.firefox.systemconfig)";
          wantedBy = [ "multi-user.target" ];
          unitConfig.RequiresMountsFor = "/var/lib/flatpak";
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
          };
          script = ''
            ${pkgs.coreutils}/bin/install -Dm644 ${policies} ${systemconfig}/policies/policies.json
          '';
        };

        # Padrão do sistema; cada usuário troca com my.browser, na camada de
        # defaults do HM (que fica em XDG_CONFIG_DIRS, antes deste arquivo).
        xdg.mime.defaultApplications = lib.genAttrs [
          "text/html"
          "application/xhtml+xml"
          "x-scheme-handler/http"
          "x-scheme-handler/https"
          "x-scheme-handler/about"
          "x-scheme-handler/unknown"
        ] (_: "org.mozilla.firefox.desktop");
      };
    };
}

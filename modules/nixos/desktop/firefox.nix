# Firefox como navegador padrão de todos os usuários.
#
# Preferências e políticas do sistema (programs.firefox):
#  - Taskbar Tabs (web apps em janela própria) ligadas: no Linux vêm
#    desligadas, e browser.taskbarTabs.enabled não é aceita na chave
#    Preferences das políticas; vai pelo autoconfig, só como padrão;
#  - abas de container ligadas (privacy.userContext.enabled);
#  - extensões do KeePassXC, Multi-Account Containers e os "<empresa>
#    Container" (Facebook, Google, Microsoft, Twitter, Discord, Amazon e
#    TikTok) instaladas por padrão (o usuário pode desativá-las, não
#    removê-las); as demais vêm da sincronização com a conta Mozilla de cada
#    usuário. O native messaging do KeePassXC vem do módulo HM do KeePassXC.
#    Os containers não são declarados: cada "<empresa> Container" cria o seu,
#    com o nome da empresa, e abre nele os domínios dela. O da Microsoft
#    inclui o GitHub, a menos que se marque "Ignore GitHub" nas opções dele;
#    o do Twitter inclui o x.com. O YouTube Container fica de fora: o do
#    Google já leva o YouTube;
#  - diálogo de arquivos pelo portal (Nautilus ou Strata; nixos/desktop/file-manager.nix).
#
# Web apps (my.firefox.webapps) são do perfil de cada usuário:
# home/desktop/firefox.nix.
{
  flake.modules.nixos.firefox =
    { lib, ... }:
    let
      # id da extensão → slug em addons.mozilla.org.
      extensions = {
        "keepassxc-browser@keepassxc.org" = "keepassxc-browser";
        "@testpilot-containers" = "multi-account-containers";
        "@contain-facebook" = "facebook-container";
        "@contain-google" = "google-container";
        "@better-contain-microsoft" = "better-microsoft-container";
        "@contain-twitter" = "twitter-container";
        "@contain-discord" = "discord-container";
        "@contain-amazon" = "amazon-container";
        "@tiktok-container" = "tiktok-container";
      };
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
            discord = {
              name = "Discord";
              url = "https://discord.com/app";
              container = "Discord";
              scopes = [ "discord.com" ];
            };
            x = {
              name = "X";
              url = "https://x.com/";
              container = "Twitter";
              scopes = [
                "x.com"
                "twitter.com"
              ];
            };
          };
        };
      };

      config = {
        programs.firefox = {
          enable = true;
          # Só os padrões: o usuário ainda muda tudo em about:config.
          preferencesStatus = "default";
          preferences = {
            "browser.taskbarTabs.enabled" = true;
            "privacy.userContext.enabled" = true;
            "privacy.userContext.ui.enabled" = true;
            "widget.use-xdg-desktop-portal.file-picker" = 1;
          };
          policies = {
            DontCheckDefaultBrowser = true;
            ExtensionSettings = lib.mapAttrs (_: slug: {
              installation_mode = "normal_installed";
              install_url = "https://addons.mozilla.org/firefox/downloads/latest/${slug}/latest.xpi";
            }) extensions;
          };
        };

        # Padrão do sistema; cada usuário pode trocar em ~/.config/mimeapps.list.
        xdg.mime.defaultApplications = lib.genAttrs [
          "text/html"
          "application/xhtml+xml"
          "x-scheme-handler/http"
          "x-scheme-handler/https"
          "x-scheme-handler/about"
          "x-scheme-handler/unknown"
        ] (_: "firefox.desktop");
      };
    };
}

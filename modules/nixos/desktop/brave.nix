# brave-origin como navegador padrão de todos os usuários.
#
# Políticas (/etc/brave/policies/managed, lidas também pelo Brave comum):
#  - extensão do KeePassXC instalada por padrão (o usuário pode desativá-la,
#    não removê-la); o native messaging fica em home/desktop/brave.nix;
#  - os web apps (my.brave.webapps) instalados como PWAs, em janela própria.
#
# Containers (my.brave.containers), o container de cada PWA e o Traffic Control
# (regras que abrem os domínios de cada empresa no container dela) são do
# perfil de cada usuário: home/desktop/brave.nix.
{
  flake.modules.nixos.brave =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.my.brave;

      icons = [
        "personal"
        "work"
        "shopping"
        "social"
        "events"
        "banking"
        "star"
        "travel"
        "school"
        "private"
        "messaging"
      ];
    in
    {
      options.my.brave = {
        package = lib.mkPackageOption pkgs "brave-origin" { };

        containers = lib.mkOption {
          description = ''
            Containers do Brave criados (ou, se já existir um com o mesmo nome,
            ajustados) no perfil de cada usuário. O nome é o que vai em
            `--container=<nome>`.
          '';
          type = lib.types.attrsOf (
            lib.types.submodule {
              options = {
                icon = lib.mkOption {
                  type = lib.types.enum icons;
                  description = "Um dos ícones fixos do Brave.";
                };
                color = lib.mkOption {
                  type = lib.types.strMatching "#[0-9A-Fa-f]{6}";
                  description = "Cor de fundo do ícone (#RRGGBB).";
                };
                domains = lib.mkOption {
                  type = lib.types.listOf lib.types.str;
                  default = [ ];
                  description = ''
                    Domínios abertos neste container pelo Traffic Control (uma
                    regra por container; "exemplo.com" cobre os subdomínios).
                  '';
                };
              };
            }
          );
          default = {
            Google = {
              icon = "star";
              color = "#4285F4";
              domains = [
                "google.com"
                "google.com.br"
                "youtube.com"
                "youtu.be"
                "youtube-nocookie.com"
                "gmail.com"
                "googlemail.com"
                "goo.gl"
                "g.co"
                "g.page"
                "googleusercontent.com"
                "googleapis.com"
                "gstatic.com"
                "ggpht.com"
                "ytimg.com"
                "googlevideo.com"
                "android.com"
                "blogger.com"
                "blogspot.com"
                "withgoogle.com"
                "googleblog.com"
                "google.dev"
                "web.dev"
                "googlesource.com"
                "gemini.google"
                "notebooklm.google"
              ];
            };
            GitHub = {
              icon = "work";
              color = "#24292F";
              domains = [
                "github.com"
                "github.dev"
                "githubusercontent.com"
                "githubcopilot.com"
                "githubassets.com"
                "ghcr.io"
              ];
            };
            Microsoft = {
              icon = "messaging";
              color = "#F25022";
              domains = [
                "microsoft.com"
                "cloud.microsoft"
                "microsoft365.com"
                "office.com"
                "office.net"
                "office365.com"
                "outlook.com"
                "hotmail.com"
                "live.com"
                "live.net"
                "msn.com"
                "bing.com"
                "microsoftonline.com"
                "sharepoint.com"
                "onedrive.com"
                "1drv.ms"
                "onenote.com"
                "skype.com"
                "azure.com"
                "visualstudio.com"
                "xbox.com"
                "linkedin.com"
                "lnkd.in"
              ];
            };
            Meta = {
              icon = "social";
              color = "#0866FF";
              domains = [
                "facebook.com"
                "fb.com"
                "fb.me"
                "fb.watch"
                "facebook.net"
                "fbcdn.net"
                "messenger.com"
                "m.me"
                "instagram.com"
                "cdninstagram.com"
                "whatsapp.com"
                "whatsapp.net"
                "wa.me"
                "threads.com"
                "threads.net"
                "meta.com"
                "meta.ai"
                "oculus.com"
              ];
            };
          };
        };

        trafficControl = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = ''
            Liga o Traffic Control (e, enquanto ele for experimental, a flag
            brave://flags/#traffic-control) com as regras dos containers.
          '';
        };

        webapps = lib.mkOption {
          description = ''
            Web apps instalados como PWAs do Brave para todos os usuários
            (`webapp <id>` abre cada um no seu container).
          '';
          type = lib.types.attrsOf (
            lib.types.submodule {
              options = {
                name = lib.mkOption { type = lib.types.str; };
                url = lib.mkOption {
                  type = lib.types.str;
                  description = "URL de instalação.";
                };
                container = lib.mkOption {
                  type = lib.types.nullOr lib.types.str;
                  default = null;
                  description = "Container em que a PWA abre (null: sem container).";
                };
                match = lib.mkOption {
                  type = lib.types.listOf lib.types.str;
                  description = ''
                    "host[/caminho]" que identificam a PWA instalada pela URL de
                    início que o site declara (que pode diferir da de instalação).
                  '';
                };
              };
            }
          );
          default = {
            whatsapp = {
              name = "WhatsApp";
              url = "https://web.whatsapp.com/";
              container = "Meta";
              match = [ "web.whatsapp.com" ];
            };
            youtube = {
              name = "YouTube";
              url = "https://www.youtube.com/";
              container = "Google";
              match = [
                "www.youtube.com"
                "youtube.com"
                "m.youtube.com"
              ];
            };
            google-maps = {
              name = "Google Maps";
              url = "https://maps.google.com/";
              container = "Google";
              match = [
                "maps.google.com"
                "www.google.com/maps"
              ];
            };
            google-photos = {
              name = "Google Photos";
              url = "https://photos.google.com/";
              container = "Google";
              match = [ "photos.google.com" ];
            };
            google-messages = {
              name = "Google Messages";
              url = "https://messages.google.com/web";
              container = "Google";
              match = [ "messages.google.com" ];
            };
            google-contacts = {
              name = "Google Contacts";
              url = "https://contacts.google.com/";
              container = "Google";
              match = [ "contacts.google.com" ];
            };
            teams = {
              name = "Microsoft Teams";
              url = "https://teams.microsoft.com/";
              container = "Microsoft";
              match = [
                "teams.microsoft.com"
                "teams.cloud.microsoft"
                "teams.live.com"
              ];
            };
            discord = {
              name = "Discord";
              url = "https://discord.com/app";
              match = [ "discord.com" ];
            };
            x = {
              name = "X";
              url = "https://x.com/";
              match = [
                "x.com"
                "twitter.com"
              ];
            };
          };
        };
      };

      config = {
        environment.systemPackages = [ cfg.package ];

        environment.etc."brave/policies/managed/nix-config.json".text = builtins.toJSON {
          ExtensionSettings."oboonakemofpalcgghocfoadofidjkkk" = {
            installation_mode = "normal_installed";
            update_url = "https://clients2.google.com/service/update2/crx";
          };
          WebAppInstallForceList = lib.mapAttrsToList (_: app: {
            inherit (app) url;
            default_launch_container = "window";
            create_desktop_shortcut = false;
            fallback_app_name = app.name;
          }) cfg.webapps;
          DefaultBrowserSettingEnabled = false;
        };

        # Padrão do sistema; cada usuário pode trocar em ~/.config/mimeapps.list.
        xdg.mime.defaultApplications = lib.genAttrs [
          "text/html"
          "application/xhtml+xml"
          "x-scheme-handler/http"
          "x-scheme-handler/https"
          "x-scheme-handler/about"
          "x-scheme-handler/unknown"
        ] (_: "brave-origin.desktop");
      };
    };
}

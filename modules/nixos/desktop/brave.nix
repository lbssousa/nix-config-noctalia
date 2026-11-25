# Brave (Flatpak com.brave.Browser), navegador padrão do sistema; cada usuário
# escolhe o seu com my.browser (home/base/xdg.nix).
#
# Políticas em /etc/brave/policies/managed: o brave.sh do Flatpak liga os
# .json de /run/host/etc/brave/policies (permissão host-etc) no /etc do
# sandbox. Por isso são cópias (mode), e não symlinks para o /nix/store, que o
# sandbox não enxerga:
#  - extensão do Bitwarden instalada por padrão (o usuário pode desativá-la,
#    não removê-la); o native messaging com o app vem de
#    home/desktop/brave.nix. As demais extensões vêm da sincronização de
#    cada usuário;
#  - sem o resolvedor DNS próprio (fica o systemd-resolved) e sem o aviso de
#    navegador padrão;
#  - "Brave Origin" (my.brave.origin, ligado por padrão), em origin.json: os
#    mesmos recursos que a página Settings › System › Brave Origin desliga
#    (kBraveOriginBrowserMetadata e kBraveOriginProfileMetadata em
#    brave-core/browser/brave_origin/brave_origin_service_factory.cc). O
#    upgrade para o Origin só se ativa pela interface; pelas políticas, o
#    efeito é o mesmo, mas todas ficam travadas: as que o Origin deixa o
#    usuário religar (P3A, ping de uso, IA local, Wayback Machine,
#    Speedreader, Playlist, Web Discovery) não aceitam o nível
#    "recommended" (can_be_recommended: false), o que deixa o resultado mais
#    perto do Origin avulso, em que os recursos nem existem no binário.
#
# Cores da Noctalia: o template "chromium-based" da comunidade grava
# BrowserThemeColor em noctalia-color.json, que vale para a máquina inteira;
# um só usuário (my.brave.themeOwner) é o dono do arquivo e a cor é a da
# paleta dele (home/desktop/brave.nix).
#
# Web apps (my.brave.webapps): instalados como PWAs pelo próprio Brave
# (WebAppInstallForceList), em janela própria; `webapp <id>` os abre
# (home/desktop/brave.nix). O override `~/.local/share/icons:create` restaura a
# permissão de escrita do manifesto do Brave (rebaixada para `:ro` pelo
# override global em flatpak.nix) para o flextop instalar os ícones e
# lançadores das PWAs, e home/desktop/brave-pwa-fix.nix corrige o
# StartupWMClass e garante o ícone absoluto de maior resolução no Wayland.
#
# Containers (my.brave.containers): o equivalente às extensões "<empresa>
# Container" do Firefox. O Brave tem Containers e Traffic Control nativos, mas
# só pela interface; home/desktop/brave-containers.nix grava as preferências e
# liga a flag do Traffic Control com o Brave fechado, apenas nos perfis com
# my.braveContainers.enable (por ora, só o abutre).
{ config, ... }:
let
  flakeUsers = config.my.users;
in
{
  flake.modules.nixos.brave =
    { config, lib, ... }:
    let
      cfg = config.my.brave;
      bitwarden = "nngceckbapebfimnlniiiahkandclblb";
      # O primeiro administrador por uid.
      firstAdmin =
        let
          admins = lib.sort (a: b: a.uid < b.uid) (
            lib.mapAttrsToList (name: u: u // { inherit name; }) (lib.filterAttrs (_: u: u.sudo) flakeUsers)
          );
        in
        if admins == [ ] then null else (lib.head admins).name;
      policyDir = "brave/policies/managed";
    in
    {
      options.my.brave = {
        origin = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = ''
            Brave como o Brave Origin para todos: sem Rewards e anúncios do
            navegador, Wallet, VPN, Leo AI e IA local, News, Talk, Tor,
            Speedreader, Playlist, Wayback Machine, Web Discovery, aliases de
            e-mail, PSST, P3A e ping de uso (políticas travadas).
          '';
        };

        themeOwner = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = firstAdmin;
          defaultText = lib.literalMD "o primeiro usuário com `sudo = true`, por uid";
          description = ''
            Usuário cuja paleta da Noctalia colore o Brave de todos
            (BrowserThemeColor); null desliga.
          '';
        };

        webapps = lib.mkOption {
          description = ''
            Web apps instalados como PWAs do Brave para todos os usuários
            (`webapp <id>` abre cada um).
          '';
          type = lib.types.attrsOf (
            lib.types.submodule {
              options = {
                name = lib.mkOption {
                  type = lib.types.str;
                  description = "Nome do app (também o do lançador que o Brave cria).";
                };
                url = lib.mkOption {
                  type = lib.types.str;
                  description = "URL de início.";
                };
                container = lib.mkOption {
                  type = lib.types.nullOr lib.types.str;
                  default = null;
                  description = ''
                    Nome do container do Brave em que a PWA abre
                    (--container=<nome>; null: sem container), quando o usuário
                    tem my.braveContainers.enable.
                  '';
                };
                icon = lib.mkOption {
                  type = lib.types.nullOr (
                    lib.types.submodule {
                      options = {
                        url = lib.mkOption { type = lib.types.str; };
                        hash = lib.mkOption {
                          type = lib.types.str;
                          description = "SHA-256 (hex) do arquivo do ícone.";
                        };
                      };
                    }
                  );
                  default = null;
                  description = ''
                    Ícone próprio, para os sites que só o mostram com login
                    (null: o do manifest do site).
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
            };
            youtube = {
              name = "YouTube";
              url = "https://www.youtube.com/";
              container = "Google";
              icon = {
                url = "https://www.gstatic.com/images/branding/productlogos/youtube/v9/web-512dp/logo_youtube_color_1x_web_512dp.png";
                hash = "69d5eb245c6654e3aff32600ffa630ae0b9bce42d19cd754bf5942694c67f6ab";
              };
            };
            google-maps = {
              name = "Google Maps";
              url = "https://www.google.com/maps";
              container = "Google";
              icon = {
                url = "https://www.gstatic.com/images/branding/productlogos/maps_2025_round/v1/web-512dp/logo_maps_2025_round_color_1x_web_512dp.png";
                hash = "6d67afe14b7cd30f7f231b727454a54149516d54c53a2a6791b3056f64684c57";
              };
            };
            google-photos = {
              name = "Google Photos";
              url = "https://photos.google.com/";
              container = "Google";
              icon = {
                url = "https://www.gstatic.com/images/branding/product/1x/photos_512dp.png";
                hash = "52f51778cc5c2c5e650f42f2e2c4e9c0690267da8ddfdf99d11fd83f82f4b752";
              };
            };
            google-messages = {
              name = "Google Messages";
              url = "https://messages.google.com/web";
              container = "Google";
              icon = {
                url = "https://ssl.gstatic.com/android-messages-web/images/2026/pwa_round_v2_512.png";
                hash = "dd477181f054881cf7bca6b307cd490f709ccc27b0ee5967a9200ec872f4a910";
              };
            };
            google-contacts = {
              name = "Google Contacts";
              url = "https://contacts.google.com/";
              container = "Google";
              icon = {
                url = "https://www.gstatic.com/images/branding/product/1x/contacts_2022_512dp.png";
                hash = "26b538e7e72ebca50af5cb59e147320da83669309c6e2978855b7c41a77384e8";
              };
            };
            teams = {
              name = "Microsoft Teams";
              url = "https://teams.cloud.microsoft/";
              container = "Microsoft";
            };
          };
        };

        # Equivalente às extensões "<empresa> Container" do Firefox
        # (nixos/desktop/firefox.nix): um container por fabricante e uma regra de
        # Traffic Control que abre os domínios dele automaticamente no container.
        # São preferências do perfil, não políticas: o home-manager as grava com
        # o Brave fechado (home/desktop/brave-containers.nix), só para quem tem
        # my.braveContainers.enable.
        containers = lib.mkOption {
          type = lib.types.listOf (
            lib.types.submodule {
              options = {
                name = lib.mkOption {
                  type = lib.types.str;
                  description = "Nome do container, igual ao do Firefox.";
                };
                icon = lib.mkOption {
                  type = lib.types.enum [
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
                  default = "social";
                  description = "Ícone do container (containers.mojom.Icon).";
                };
                color = lib.mkOption {
                  type = lib.types.strMatching "0x[0-9A-Fa-f]{8}";
                  description = "Cor de fundo do ícone em 0xAARRGGBB.";
                };
                domains = lib.mkOption {
                  type = lib.types.listOf (lib.types.strMatching "([a-z0-9-]+\\.)+[a-z]{2,}");
                  default = [ ];
                  description = ''
                    Domínios do fabricante. Cada um vira uma linha
                    `https://dominio` no url_filter: casa o site e os subdomínios.
                  '';
                };
              };
            }
          );
          default = [
            {
              name = "Google";
              icon = "work";
              color = "0xFFD50000";
              # O Google Container do Firefox inclui o YouTube.
              domains = [
                "google.com"
                "googlemail.com"
                "youtube.com"
                "youtu.be"
                "g.co"
                "goo.gl"
                "blogger.com"
                "blogspot.com"
                "blog.google"
                "googleblog.com"
              ];
            }
            {
              name = "Microsoft";
              icon = "work";
              color = "0xFF0078D4";
              # O Better Microsoft Container do Firefox inclui o GitHub.
              domains = [
                "microsoft.com"
                "microsoftonline.com"
                "outlook.com"
                "live.com"
                "hotmail.com"
                "office.com"
                "office365.com"
                "sharepoint.com"
                "onedrive.com"
                "onenote.com"
                "skype.com"
                "xbox.com"
                "visualstudio.com"
                "azure.com"
                "github.com"
                "github.io"
                "githubusercontent.com"
              ];
            }
            {
              name = "Facebook";
              icon = "social";
              color = "0xFF1877F2";
              # O Facebook Container isola também Instagram, Messenger e Threads.
              domains = [
                "facebook.com"
                "facebook.net"
                "fb.com"
                "fb.me"
                "messenger.com"
                "m.me"
                "instagram.com"
                "threads.net"
                "meta.com"
                "workplace.com"
                "oculus.com"
              ];
            }
            {
              name = "Amazon";
              icon = "shopping";
              color = "0xFFFF9900";
              domains = [
                "amazon.com"
                "amazon.com.br"
                "amazon.co.uk"
                "amazon.de"
                "amazon.fr"
                "amazon.ca"
                "amazon.co.jp"
                "amazon.in"
                "amazon.es"
                "amazon.it"
                "amazon.nl"
                "amazon.com.au"
              ];
            }
            {
              name = "Twitter";
              icon = "social";
              color = "0xFF1DA1F2";
              # O Twitter Container do Firefox já inclui o x.com.
              domains = [
                "x.com"
                "twitter.com"
                "t.co"
                "twimg.com"
              ];
            }
            {
              name = "Discord";
              icon = "messaging";
              color = "0xFF5865F2";
              domains = [
                "discord.com"
                "discordapp.com"
                "discord.gg"
              ];
            }
            {
              name = "TikTok";
              icon = "social";
              color = "0xFFFE2C55";
              domains = [
                "tiktok.com"
                "tiktokv.com"
              ];
            }
          ];
          description = ''
            Containers do Brave e as regras de Traffic Control dos domínios de
            cada fabricante (o equivalente às extensões de container do Firefox).
          '';
        };

      };

      config = {
        services.flatpak.packages = [ "com.brave.Browser" ];
        # - Socket IPC e desktop_proxy do Bitwarden em Flatpak, abertos no
        #   diretório do Chrome em Flatpak (home/desktop/brave.nix).
        # - ~/.local/share/icons:create restaura a permissão de escrita do
        #   manifesto do Brave que o override global (`~/.local/share/icons:ro`
        #   em flatpak.nix) rebaixava para somente leitura, impedindo o flextop
        #   (xdg-desktop-menu / xdg-icon-resource) de instalar ícones e
        #   lançadores das PWAs.
        services.flatpak.overrides.settings."com.brave.Browser".Context.filesystems = [
          "~/.var/app/com.google.Chrome/config/google-chrome/NativeMessagingHosts"
          "~/.local/share/icons:create"
        ];

        environment.etc."${policyDir}/nix.json" = {
          mode = "0644";
          text = builtins.toJSON {
            BuiltInDnsClientEnabled = false;
            DefaultBrowserSettingEnabled = false;
            ExtensionSettings.${bitwarden} = {
              installation_mode = "normal_installed";
              update_url = "https://clients2.google.com/service/update2/crx";
            };
            WebAppInstallForceList = lib.mapAttrsToList (
              _: app:
              {
                inherit (app) url;
                default_launch_container = "window";
                custom_name = app.name;
                fallback_app_name = app.name;
              }
              // lib.optionalAttrs (app.icon != null) {
                custom_icon = {
                  inherit (app.icon) url hash;
                };
              }
            ) cfg.webapps;
          };
        };

        # Os 16 recursos da página Brave Origin, com os valores que ela aplica.
        environment.etc."${policyDir}/origin.json" = lib.mkIf cfg.origin {
          mode = "0644";
          text = builtins.toJSON {
            # Travados também no Origin.
            TorDisabled = true;
            BraveRewardsDisabled = true;
            BraveWalletDisabled = true;
            BraveAIChatEnabled = false;
            BraveNewsDisabled = true;
            BraveVPNDisabled = true;
            BraveTalkDisabled = true;
            EmailAliasesEnabled = false;
            PsstEnabled = false;
            # Só desligados por padrão no Origin; aqui travados (não aceitam
            # o nível recommended).
            BraveStatsPingEnabled = false;
            BraveP3AEnabled = false;
            BraveLocalAIEnabled = false;
            BraveWaybackMachineEnabled = false;
            BraveSpeedreaderEnabled = false;
            BravePlaylistEnabled = false;
            BraveWebDiscoveryEnabled = false;
          };
        };

        # Gravável pelo dono da paleta; "f" (sem "+") preserva a cor entre
        # rebuilds, e a Noctalia a regrava ao iniciar.
        systemd.tmpfiles.settings."10-noctalia-brave" = lib.mkIf (cfg.themeOwner != null) {
          "/etc/${policyDir}/noctalia-color.json".f = {
            user = cfg.themeOwner;
            group = cfg.themeOwner;
            mode = "0644";
            argument = "{}";
          };
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
        ] (_: "com.brave.Browser.desktop");
      };
    };
}

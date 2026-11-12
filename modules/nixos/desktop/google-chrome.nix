# Google Chrome como navegador padrão de todos os usuários.
#
# Políticas do sistema (/etc/opt/chrome/policies/managed, gravadas pelo
# programs.chromium do nixpkgs, que não instala o Chromium):
#  - extensão do Bitwarden instalada por padrão (o usuário pode desativá-la,
#    não removê-la); o native messaging com o app vem de
#    nixos/security/bitwarden.nix. As demais extensões vêm da sincronização
#    com a conta Google de cada usuário;
#  - web apps (my.webapps) instalados como PWAs pelo próprio Chrome
#    (WebAppInstallForceList), em janela própria; `webapp <id>` os abre
#    (home/desktop/webapps.nix);
#  - sem o aviso de navegador padrão: quem decide é o mimeapps.list abaixo.
#
# Cores da Noctalia: o template "chromium-based" da comunidade grava
# BrowserThemeColor (a cor "surface" da paleta) em noctalia-color.json, que o
# Chrome usa para gerar o tema da barra e das abas. A política vale para a
# máquina inteira, então um só usuário (my.chrome.themeOwner) é o dono do
# arquivo e a cor é a da paleta dele (home/desktop/webapps.nix).
#
# O diálogo de arquivos é o do portal (nixos/desktop/file-manager.nix).
{ config, ... }:
let
  flakeUsers = config.my.users;
in
{
  flake.modules.nixos.google-chrome =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.my;
      bitwarden = "nngceckbapebfimnlniiiahkandclblb";
      # O primeiro administrador por uid.
      firstAdmin =
        let
          admins = lib.sort (a: b: a.uid < b.uid) (
            lib.mapAttrsToList (name: u: u // { inherit name; }) (lib.filterAttrs (_: u: u.sudo) flakeUsers)
          );
        in
        if admins == [ ] then null else (lib.head admins).name;
      colorPolicy = "/etc/opt/chrome/policies/managed/noctalia-color.json";
    in
    {
      options.my = {
        webapps = lib.mkOption {
          description = ''
            Web apps instalados como PWAs do Chrome para todos os usuários
            (`webapp <id>` abre cada um).
          '';
          type = lib.types.attrsOf (
            lib.types.submodule {
              options = {
                name = lib.mkOption {
                  type = lib.types.str;
                  description = "Nome do app (também o do lançador que o Chrome cria).";
                };
                url = lib.mkOption {
                  type = lib.types.str;
                  description = "URL de início.";
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
            };
            youtube = {
              name = "YouTube";
              url = "https://www.youtube.com/";
            };
            google-maps = {
              name = "Google Maps";
              url = "https://www.google.com/maps";
            };
            google-photos = {
              name = "Google Photos";
              url = "https://photos.google.com/";
              icon = {
                url = "https://www.gstatic.com/images/branding/product/1x/photos_512dp.png";
                hash = "52f51778cc5c2c5e650f42f2e2c4e9c0690267da8ddfdf99d11fd83f82f4b752";
              };
            };
            google-messages = {
              name = "Google Messages";
              url = "https://messages.google.com/web";
            };
            google-contacts = {
              name = "Google Contacts";
              url = "https://contacts.google.com/";
              icon = {
                url = "https://www.gstatic.com/images/branding/product/1x/contacts_2022_512dp.png";
                hash = "26b538e7e72ebca50af5cb59e147320da83669309c6e2978855b7c41a77384e8";
              };
            };
            teams = {
              name = "Microsoft Teams";
              url = "https://teams.cloud.microsoft/";
            };
            discord = {
              name = "Discord";
              url = "https://discord.com/app";
            };
            x = {
              name = "X";
              url = "https://x.com/";
            };
          };
        };

        chrome.themeOwner = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = firstAdmin;
          defaultText = lib.literalMD "o primeiro usuário com `sudo = true`, por uid";
          description = ''
            Usuário cuja paleta da Noctalia colore o Chrome de todos
            (BrowserThemeColor); null desliga.
          '';
        };
      };

      config = {
        environment.systemPackages = [ pkgs.google-chrome ];

        # Só as políticas em /etc (o Chromium não é instalado).
        programs.chromium = {
          enable = true;
          extraOpts = {
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
              // lib.optionalAttrs (app.icon != null) { custom_icon = { inherit (app.icon) url hash; }; }
            ) cfg.webapps;
          };
        };

        # Gravável pelo dono da paleta; "f" (sem "+") preserva a cor entre
        # rebuilds, e a Noctalia a regrava ao iniciar.
        systemd.tmpfiles.settings."10-noctalia-chrome" = lib.mkIf (cfg.chrome.themeOwner != null) {
          ${colorPolicy}.f = {
            user = cfg.chrome.themeOwner;
            group = cfg.chrome.themeOwner;
            mode = "0644";
            argument = "{}";
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
        ] (_: "google-chrome.desktop");
      };
    };
}

# Web apps no estilo Omarchy, abertos no Firefox em janela própria.
#
# Cada web app usa um perfil dedicado (~/.mozilla/firefox/webapp-<id>), para
# ter processo e app_id Wayland próprios: o dock e o alternador de janelas
# tratam cada um como um aplicativo, e o userChrome.css esconde abas e barras.
#
# As entradas ficam no perfil do home-manager (XDG_DATA_DIRS), então o usuário
# pode ocultar ou substituir qualquer uma criando ~/.local/share/applications/
# webapp-<id>.desktop. Outros sites podem ser fixados à mão pelo recurso
# "Adicionar aba à barra de tarefas" do Firefox (browser.taskbarTabs.enabled).
{
  flake.modules.homeManager.webapps =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.my.webapps;

      userChrome = ''
        #TabsToolbar, #nav-bar, #PersonalToolbar, #sidebar-box, #titlebar { visibility: collapse !important; }
      '';

      launcher =
        id: app:
        pkgs.writeShellScript "webapp-${id}" ''
          exec ${config.my.webappBrowser} \
            --profile "$HOME/.mozilla/firefox/webapp-${id}" \
            --name webapp-${id} --class webapp-${id} \
            --new-window ${lib.escapeShellArg app.url}
        '';
    in
    {
      options.my = {
        webappBrowser = lib.mkOption {
          type = lib.types.str;
          # O Firefox do sistema (programs.firefox, com as políticas e o
          # pacote de idioma pt-BR), resolvido pelo PATH.
          default = "firefox";
          description = "Comando do Firefox usado pelos web apps.";
        };

        webapps = lib.mkOption {
          description = "Web apps (nome → URL e ícone).";
          default = { };
          type = lib.types.attrsOf (
            lib.types.submodule {
              options = {
                name = lib.mkOption { type = lib.types.str; };
                url = lib.mkOption { type = lib.types.str; };
                icon = lib.mkOption {
                  type = lib.types.str;
                  default = "firefox";
                  description = "Nome de ícone do tema ou caminho de imagem.";
                };
              };
            }
          );
        };
      };

      config = {
        # Lista padrão, a partir dos web apps do Omarchy deste usuário.
        my.webapps = lib.mapAttrs (_: lib.mkDefault) {
          whatsapp = {
            name = "WhatsApp";
            url = "https://web.whatsapp.com/";
            icon = "whatsapp";
          };
          youtube = {
            name = "YouTube";
            url = "https://www.youtube.com/";
            icon = "youtube";
          };
          google-maps = {
            name = "Google Maps";
            url = "https://maps.google.com/";
            icon = "google-maps";
          };
          google-photos = {
            name = "Google Photos";
            url = "https://photos.google.com/";
            icon = "google-photos";
          };
          google-messages = {
            name = "Google Messages";
            url = "https://messages.google.com/web";
            icon = "google-messages";
          };
          google-contacts = {
            name = "Google Contacts";
            url = "https://contacts.google.com/";
            icon = "google-contacts";
          };
          teams = {
            name = "Microsoft Teams";
            url = "https://teams.microsoft.com/";
            icon = "teams";
          };
          discord = {
            name = "Discord";
            url = "https://discord.com/channels/@me";
            icon = "discord";
          };
          x = {
            name = "X";
            url = "https://x.com/";
            icon = "twitter";
          };
        };

        xdg.desktopEntries = lib.mapAttrs' (
          id: app:
          lib.nameValuePair "webapp-${id}" {
            inherit (app) name icon;
            exec = "${launcher id app}";
            terminal = false;
            categories = [ "Network" ];
            settings.StartupWMClass = "webapp-${id}";
          }
        ) cfg;

        home.file = lib.mapAttrs' (
          id: _:
          lib.nameValuePair ".mozilla/firefox/webapp-${id}/chrome/userChrome.css" { text = userChrome; }
        ) cfg;

        # Comando estável para atalhos de teclado: `webapp <id>`.
        home.packages = [
          (pkgs.writeShellScriptBin "webapp" ''
            if [ -z "$1" ]; then
              echo "Uso: webapp <id>   (ids: ${lib.concatStringsSep " " (lib.attrNames cfg)})" >&2
              exit 1
            fi
            exec ${pkgs.gtk3}/bin/gtk-launch "webapp-$1"
          '')
        ];
      };
    };
}

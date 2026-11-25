# Aplicativos padrão por usuário, publicados como *camada de defaults*.
#
# O mimeapps.list gerado fica num diretório do perfil HM incluído em
# XDG_CONFIG_DIRS, e não em ~/.config/mimeapps.list: pela especificação XDG, o
# arquivo do usuário continua gravável (xdg-mime default, "Abrir com…") e tem
# precedência sobre estes defaults.
{
  flake.modules.homeManager.xdg-defaults =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      pdfTypes = [
        "application/pdf"
        "application/x-bzpdf"
        "application/x-gzpdf"
        "application/x-xzpdf"
        "application/x-ext-pdf"
      ];
      fileManagers = {
        luciole = {
          appId = "dev.noctalia.luciole";
          command = "luciole";
        };
      };
      browsers = {
        firefox = {
          appId = "org.mozilla.firefox";
          desktop = "org.mozilla.firefox.desktop";
          command = "org.mozilla.firefox";
        };
        brave = {
          appId = "com.brave.Browser";
          desktop = "com.brave.Browser.desktop";
          command = "com.brave.Browser";
        };
      };
      browserTypes = [
        "application/xhtml+xml"
        "text/html"
        "x-scheme-handler/about"
        "x-scheme-handler/http"
        "x-scheme-handler/https"
        "x-scheme-handler/unknown"
      ];
      defaults = {
        "inode/directory" = "${config.my.fileManagerApp.appId}.desktop";
      }
      // lib.genAttrs pdfTypes (_: config.my.pdfViewer)
      // lib.genAttrs browserTypes (_: config.my.browserApp.desktop);

      mimeappsDir = pkgs.writeTextDir "etc/xdg/mimeapps.list" (
        lib.generators.toINI { } {
          "Default Applications" = defaults;
        }
      );
    in
    {
      options.my = {
        pdfViewer = lib.mkOption {
          type = lib.types.str;
          default = "org.gnome.Papers.desktop";
          description = "Entrada .desktop padrão para PDFs.";
        };
        fileManager = lib.mkOption {
          type = lib.types.enum (lib.attrNames fileManagers);
          default = "luciole";
          description = "Gerenciador de arquivos padrão (pastas, FileManager1 e diálogo do portal).";
        };
        fileManagerApp = lib.mkOption {
          type = lib.types.attrsOf lib.types.str;
          readOnly = true;
          internal = true;
          default = fileManagers.${config.my.fileManager};
          description = "appId e comando do gerenciador escolhido em my.fileManager.";
        };
        browser = lib.mkOption {
          type = lib.types.enum (lib.attrNames browsers);
          default = "firefox";
          description = "Navegador web padrão (associações MIME, BROWSER e dock).";
        };
        browserApp = lib.mkOption {
          type = lib.types.attrsOf lib.types.str;
          readOnly = true;
          internal = true;
          default = browsers.${config.my.browser};
          description = "appId, arquivo .desktop e comando do navegador escolhido em my.browser.";
        };
      };

      config = {
        # Pastas do usuário em pt_BR, criadas na ativação do home-manager (nada
        # no sistema roda o xdg-user-dirs-update fora de sessões GNOME/KDE).
        # PROJECTS não existe no padrão do xdg-user-dirs; é usado pelo
        # xdg-user-dir em abutre.nix e install.sh.
        xdg = {
          enable = true;
          userDirs = {
            enable = true;
            createDirectories = true;
            desktop = "${config.home.homeDirectory}/Área de trabalho";
            documents = "${config.home.homeDirectory}/Documentos";
            download = "${config.home.homeDirectory}/Downloads";
            music = "${config.home.homeDirectory}/Música";
            pictures = "${config.home.homeDirectory}/Imagens";
            publicShare = "${config.home.homeDirectory}/Público";
            templates = "${config.home.homeDirectory}/Modelos";
            videos = "${config.home.homeDirectory}/Vídeos";
            extraConfig.PROJECTS = "${config.home.homeDirectory}/Projetos";
          };
          systemDirs.config = [ "${mimeappsDir}/etc/xdg" ];
        };
      };
    };
}

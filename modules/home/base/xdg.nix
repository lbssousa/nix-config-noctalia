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
      defaults = {
        "inode/directory" = config.my.fileManager;
      }
      // lib.genAttrs pdfTypes (_: config.my.pdfViewer);

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
          type = lib.types.str;
          default = "org.gnome.Nautilus.desktop";
          description = "Entrada .desktop padrão para pastas.";
        };
      };

      config = {
        # As pastas do usuário (Documentos, Projetos…) ficam com o
        # xdg-user-dirs-update do sistema, em pt_BR.
        xdg.enable = true;
        xdg.systemDirs.config = [ "${mimeappsDir}/etc/xdg" ];
      };
    };
}

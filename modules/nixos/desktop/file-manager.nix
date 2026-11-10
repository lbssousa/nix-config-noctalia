# Nautilus como gerenciador de arquivos padrão de todos os usuários: pastas
# (inode/directory), "Mostrar na pasta" (org.freedesktop.FileManager1) e o
# diálogo "Abrir arquivo..." / "Salvar como...". O Strata (flake do projeto,
# input em flake.nix) também fica instalado; quem o escolhe (my.fileManager,
# home/desktop/strata.nix) passa a usá-lo nas três coisas.
#
# O diálogo é o portal FileChooser: o Nautilus o implementa por trás do
# xdg-desktop-portal-gnome, e o Strata tem o próprio backend
# (org.freedesktop.impl.portal.desktop.strata, no passthru fileChooserPortal
# do pacote). Os apps só usam o portal
# quando pedido: GTK_USE_PORTAL no GTK3, GDK_DEBUG=portals no GTK4 e o tema
# xdgdesktopportal no Qt (OBS...); sem ele, o Qt abre o próprio
# diálogo. O Chrome (nixos/desktop/google-chrome.nix) e o Electron já o
# usam.
#
# Override local: ~/.config/mimeapps.list (xdg-mime default) para pastas.
{
  flake.modules.nixos.file-manager =
    { pkgs, ... }:
    {
      environment.systemPackages = with pkgs; [
        nautilus
        sushi
        strata
      ];

      # Miniaturas, lixeira, montagem de dispositivos e locais de rede.
      services.gvfs.enable = true;
      services.gnome.sushi.enable = true;

      xdg.mime.defaultApplications."inode/directory" = "org.gnome.Nautilus.desktop";

      xdg.portal = {
        extraPortals = [
          pkgs.xdg-desktop-portal-gnome
          pkgs.strata.fileChooserPortal
        ];
        config.umbriel."org.freedesktop.impl.portal.FileChooser" = [ "gnome" ];
      };

      environment.sessionVariables = {
        GTK_USE_PORTAL = "1";
        GDK_DEBUG = "portals";
        QT_QPA_PLATFORMTHEME = "xdgdesktopportal";
      };
    };
}

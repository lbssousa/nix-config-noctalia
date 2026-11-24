# Luciole (gerenciador de arquivos da Noctalia; input em flake.nix) como
# gerenciador de arquivos de todos os usuários: pastas (inode/directory),
# "Mostrar na pasta" (org.freedesktop.FileManager1) e o diálogo "Abrir
# arquivo..." / "Salvar como...".
#
# O diálogo é o portal FileChooser: o Luciole traz o backend
# (org.freedesktop.impl.portal.desktop.luciole, share/xdg-desktop-portal), que
# só é usado quando escolhido no portals.conf; o GTK fica de reserva. Os apps
# só usam o portal quando pedido: GTK_USE_PORTAL no GTK3, GDK_DEBUG=portals no
# GTK4 e o tema xdgdesktopportal no Qt (OBS...); sem ele, o Qt abre o próprio
# diálogo. O Chrome (nixos/desktop/google-chrome.nix) e o Electron já o usam.
#
# FileManager1: o serviço D-Bus do pacote
# (dev.noctalia.luciole.FileManager1.service, Name=org.freedesktop.FileManager1)
# chega ao D-Bus de sessão de todos pelo xdg.portal.extraPortals, que também
# põe o pacote em services.dbus.packages.
#
# Override local: ~/.config/mimeapps.list (xdg-mime default) para pastas.
{
  flake.modules.nixos.file-manager =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.luciole ];

      # Miniaturas, lixeira, montagem de dispositivos e locais de rede (o
      # Luciole não liga o GVfs sozinho).
      services.gvfs.enable = true;

      xdg.mime.defaultApplications."inode/directory" = "dev.noctalia.luciole.desktop";

      xdg.portal = {
        extraPortals = [ pkgs.luciole ];
        config.umbriel."org.freedesktop.impl.portal.FileChooser" = [
          "luciole"
          "gtk"
        ];
      };

      environment.sessionVariables = {
        GTK_USE_PORTAL = "1";
        GDK_DEBUG = "portals";
        QT_QPA_PLATFORMTHEME = "xdgdesktopportal";
      };
    };
}

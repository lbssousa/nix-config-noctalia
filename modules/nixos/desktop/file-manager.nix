# Nautilus como gerenciador de arquivos de todos os usuários: pastas
# (inode/directory), "Mostrar na pasta" (org.freedesktop.FileManager1) e o
# diálogo "Abrir arquivo..." / "Salvar como...".
#
# O diálogo é o portal FileChooser: o Nautilus implementa
# org.freedesktop.impl.portal.FileChooser, e o xdg-desktop-portal-gnome o
# repassa a ele. Os apps GTK só usam o portal quando pedido (GTK_USE_PORTAL no
# GTK3, GDK_DEBUG=portals no GTK4); o Firefox (nixos/desktop/firefox.nix),
# o Chromium e o Electron já o usam.
#
# Override local: ~/.config/mimeapps.list (xdg-mime default) para pastas.
{
  flake.modules.nixos.file-manager =
    { pkgs, ... }:
    {
      environment.systemPackages = with pkgs; [
        nautilus
        sushi
      ];

      # Miniaturas, lixeira, montagem de dispositivos e locais de rede.
      services.gvfs.enable = true;
      services.gnome.sushi.enable = true;

      xdg.mime.defaultApplications."inode/directory" = "org.gnome.Nautilus.desktop";

      xdg.portal = {
        extraPortals = [ pkgs.xdg-desktop-portal-gnome ];
        config.umbriel."org.freedesktop.impl.portal.FileChooser" = [ "gnome" ];
      };

      environment.sessionVariables = {
        GTK_USE_PORTAL = "1";
        GDK_DEBUG = "portals";
      };
    };
}

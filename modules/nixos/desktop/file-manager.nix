# Strata (packages/_strata) como gerenciador de arquivos de todos os usuários:
# pastas (inode/directory), "Mostrar na pasta" (org.freedesktop.FileManager1) e
# o diálogo "Abrir arquivo..." / "Salvar como...".
#
# O diálogo é o portal FileChooser: o Strata tem o próprio backend
# (org.freedesktop.impl.portal.desktop.strata), escolhido para a sessão do
# Umbriel. Os apps GTK só usam o portal quando pedido (GTK_USE_PORTAL no GTK3,
# GDK_DEBUG=portals no GTK4); o Firefox (nixos/desktop/firefox.nix), o
# Chromium e o Electron já o usam.
#
# O pacote só traz o serviço D-Bus do FileManager1 como modelo (instalar o
# Strata não deve trocar o gerenciador de ninguém); aqui ele é ativado para
# todos, já que nenhum outro pacote do sistema fornece esse nome.
#
# Override local: ~/.config/mimeapps.list (xdg-mime default) para pastas.
{
  flake.modules.nixos.file-manager =
    { pkgs, ... }:
    let
      fileManager1 = pkgs.runCommand "strata-file-manager1" { } ''
        install -Dm644 ${pkgs.strata}/share/strata/io.github.lgse.Strata.FileManager1.service \
          $out/share/dbus-1/services/io.github.lgse.Strata.FileManager1.service
      '';
    in
    {
      environment.systemPackages = [ pkgs.strata ];
      services.dbus.packages = [ fileManager1 ];

      # Lixeira, montagem de dispositivos e locais de rede (SMB, SFTP) pelo GIO.
      services.gvfs.enable = true;

      xdg.mime.defaultApplications."inode/directory" = "io.github.lgse.Strata.desktop";

      xdg.portal = {
        extraPortals = [ pkgs.strata ];
        config.umbriel."org.freedesktop.impl.portal.FileChooser" = [ "strata" ];
      };

      environment.sessionVariables = {
        GTK_USE_PORTAL = "1";
        GDK_DEBUG = "portals";
      };
    };
}

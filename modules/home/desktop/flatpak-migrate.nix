# Migração única das configurações dos apps que passaram de Nix para Flatpak
# (nixos/desktop/apps.nix): na ativação, cada caminho do app nativo é copiado
# para o diretório equivalente em ~/.var/app/<id>, só se a origem existir e o
# destino ainda não. Os originais ficam, para o usuário apagar quando quiser.
#
# O Bitwarden tem a sua migração (home/security/bitwarden.nix); o Dropbox
# enxerga o home inteiro e não precisa de uma; o perfil do Chrome não é
# copiado (o Brave e o Firefox importam dele).
{
  flake.modules.homeManager.flatpak-migrate =
    { config, lib, ... }:
    let
      home = config.home.homeDirectory;
      # origem (relativa ao home) → { app; destino relativo a ~/.var/app/<app> }
      moves = [
        {
          from = ".config/obs-studio";
          app = "com.obsproject.Studio";
          to = "config/obs-studio";
        }
        {
          from = ".config/inkscape";
          app = "org.inkscape.Inkscape";
          to = "config/inkscape";
        }
        {
          from = ".config/kdenliverc";
          app = "org.kde.kdenlive";
          to = "config/kdenliverc";
        }
        {
          from = ".config/xournalpp";
          app = "com.github.xournalpp.xournalpp";
          to = "config/xournalpp";
        }
        {
          from = ".config/zoomus.conf";
          app = "us.zoom.Zoom";
          to = "config/zoomus.conf";
        }
        {
          from = ".config/onlyoffice";
          app = "org.onlyoffice.desktopeditors";
          to = "config/onlyoffice";
        }
        {
          from = ".config/Pinta";
          app = "com.github.PintaProject.Pinta";
          to = "config/Pinta";
        }
        {
          from = ".config/fontforge";
          app = "org.fontforge.FontForge";
          to = "config/fontforge";
        }
        {
          from = ".local/share/org.localsend.localsend_app";
          app = "org.localsend.localsend_app";
          to = "data/org.localsend.localsend_app";
        }
      ];
      copy =
        m:
        let
          src = lib.escapeShellArg "${home}/${m.from}";
          dst = lib.escapeShellArg "${home}/.var/app/${m.app}/${m.to}";
        in
        ''
          if [[ -e ${src} && ! -e ${dst} ]]; then
            run mkdir -p "$(dirname ${dst})"
            run cp -a --reflink=auto ${src} ${dst}
          fi
        '';
    in
    {
      home.activation.flatpakMigrateAppData = lib.hm.dag.entryAfter [ "writeBoundary" ] (
        lib.concatMapStrings copy moves
      );
    };
}

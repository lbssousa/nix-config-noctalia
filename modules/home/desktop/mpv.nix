# mpv (Flatpak io.mpv.Mpv, desktop/apps.nix) com decodificação de vídeo por
# hardware, padrão do Omarchy 4.5. Dentro do sandbox, o XDG_CONFIG_HOME do app
# é ~/.var/app/io.mpv.Mpv/config.
{
  flake.modules.homeManager.mpv = {
    home.file.".var/app/io.mpv.Mpv/config/mpv/mpv.conf".text = ''
      hwdec=auto-safe
    '';
  };
}

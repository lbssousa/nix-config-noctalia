# mpv com decodificação de vídeo por hardware, padrão do Omarchy 4.5.
{
  flake.modules.homeManager.mpv = {
    xdg.configFile."mpv/mpv.conf".text = ''
      hwdec=auto-safe
    '';
  };
}

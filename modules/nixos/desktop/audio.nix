# PipeWire com compatibilidade ALSA e PulseAudio. Programas JACK rodam com o
# wrapper pw-jack (pacote pipewire.jack); jack.enable está obsoleto, porque
# põe a libjack do PipeWire no LD_LIBRARY_PATH de todo o sistema.
{
  flake.modules.nixos.audio = {
    services.pulseaudio.enable = false;
    security.rtkit.enable = true;
    services.pipewire = {
      enable = true;
      alsa.enable = true;
      alsa.support32Bit = true;
      pulse.enable = true;
      wireplumber.enable = true;
    };
  };
}

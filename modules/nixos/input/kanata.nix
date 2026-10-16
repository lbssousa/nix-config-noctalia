# Caps Lock via kanata (nível evdev: vale no TTY, no greeter e no Wayland):
#   toque         → Esc
#   segurar       → Ctrl
#   Shift + toque → Caps Lock
{
  flake.modules.nixos.kanata = {
    services.kanata = {
      enable = true;
      keyboards.default = {
        extraDefCfg = "process-unmapped-keys yes";
        config = ''
          (defsrc
            caps
          )

          (defalias
            caps (fork
              (tap-hold-press 200 200 esc lctrl)
              (tap-hold-press 200 200 caps lctrl)
              (lsft rsft))
          )

          (deflayer base
            @caps
          )
        '';
      };
    };
  };
}

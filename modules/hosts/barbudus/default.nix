# barbudus — Dell Inspiron 14 5490 (i5-10210U, 16 GB, UHD 620 + GeForce MX230)
{ config, inputs, ... }:
let
  m = config.flake.modules.nixos;
in
{
  my.hosts.barbudus.modules = [
    inputs.disko.nixosModules.disko
    m.workstation
    m.nvidia-prime
    m.fingerprint-goodix
    ./_hardware-configuration.nix
    (
      { lib, ... }:
      {
        imports = [
          (import ../_disko-btrfs.nix {
            inherit lib;
            device = "/dev/nvme0n1";
            swapSize = "20G"; # hibernação (16 GB de RAM + margem)
          })
        ];

        services.thermald.enable = true;

        # O teclado USB Redragon (0c45:5004) acorda o s2idle ~2 s depois de
        # suspender; acordar fica com a tampa, o botão de energia e o teclado
        # interno.
        services.udev.extraRules = ''
          ACTION=="add|change", SUBSYSTEM=="usb", ATTR{idVendor}=="0c45", ATTR{idProduct}=="5004", ATTR{power/wakeup}="disabled"
        '';
      }
    )
  ];
}

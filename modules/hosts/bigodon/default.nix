# bigodon — Morefine M6 (Intel N200, 16 GB, UHD integrada)
{ config, inputs, ... }:
let
  m = config.flake.modules.nixos;
in
{
  my.hosts.bigodon.modules = [
    inputs.disko.nixosModules.disko
    m.workstation
    m.intel-graphics
    ./_hardware-configuration.nix
    (
      { lib, ... }:
      {
        # Clone de trabalho do administrador (/etc/nixos aponta para ele).
        my.flakeDir = "/home/abutre/Projetos/lbssousa/nix-config-noctalia";

        imports = [
          (import ../_disko-btrfs.nix {
            inherit lib;
            device = "/dev/nvme0n1";
            swapSize = "20G";
          })
        ];
      }
    )
  ];
}

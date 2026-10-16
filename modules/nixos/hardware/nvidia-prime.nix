# NVIDIA MX230 em PRIME offload com a Intel UHD 620 (barbudus).
# Uso: `nvidia-offload <app>` ou `run-with-nvidia <app>`.
{
  flake.modules.nixos.nvidia-prime =
    { config, pkgs, ... }:
    {
      hardware.graphics = {
        enable = true;
        enable32Bit = true;
        extraPackages = with pkgs; [
          intel-media-driver
          intel-vaapi-driver
          nvidia-vaapi-driver
        ];
      };
      environment.sessionVariables.LIBVA_DRIVER_NAME = "iHD";

      # "nvidia" precisa constar aqui mesmo em offload: o módulo do nixpkgs só
      # constrói o driver quando ele está em videoDrivers.
      services.xserver.videoDrivers = [
        "modesetting"
        "nvidia"
      ];

      hardware.nvidia = {
        # 595.x (stable) não suporta a MX230.
        package = config.boot.kernelPackages.nvidiaPackages.legacy_580;
        modesetting.enable = true;
        open = false;
        powerManagement = {
          enable = true;
          finegrained = true;
        };
        prime = {
          intelBusId = "PCI:0:2:0";
          nvidiaBusId = "PCI:1:0:0";
          offload = {
            enable = true;
            enableOffloadCmd = true;
          };
        };
      };

      services.switcherooControl.enable = true;

      environment.systemPackages = [
        (pkgs.writeShellScriptBin "run-with-nvidia" ''
          if [ -z "$1" ]; then
            echo "Uso: run-with-nvidia <comando> [args...]" >&2
            exit 1
          fi
          exec nvidia-offload "$@"
        '')
      ];
    };
}

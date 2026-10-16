# GPU Intel integrada com VA-API (bigodon, Intel N200).
{
  flake.modules.nixos.intel-graphics =
    { pkgs, ... }:
    {
      hardware.graphics = {
        enable = true;
        enable32Bit = true;
        extraPackages = with pkgs; [
          intel-media-driver
          intel-vaapi-driver
          libvdpau-va-gl
        ];
      };
    };
}

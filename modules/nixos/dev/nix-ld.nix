# Binários FHS genéricos (ferramentas de dev baixadas fora do Nix).
{
  flake.modules.nixos.nix-ld =
    { pkgs, ... }:
    {
      programs.nix-ld = {
        enable = true;
        libraries = with pkgs; [
          stdenv.cc.cc.lib
          zlib
          alsa-lib
          wayland
        ];
      };
    };
}

# Podman rootless (com alias docker) + Distrobox.
{
  flake.modules.nixos.podman =
    { pkgs, ... }:
    {
      virtualisation.containers.enable = true;
      virtualisation.podman = {
        enable = true;
        dockerCompat = true;
        defaultNetwork.settings.dns_enabled = true;
        autoPrune = {
          enable = true;
          dates = "weekly";
          flags = [ "--all" ];
        };
      };

      environment.systemPackages = with pkgs; [
        distrobox
        podman-compose
        podman-tui
        lazydocker
      ];
    };
}

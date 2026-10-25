# Configuração do Nix, caches e ferramentas básicas do sistema.
{
  flake.modules.nixos.nix =
    { pkgs, ... }:
    let
      # `just` sem argumentos fora de um projeto cai no justfile do sistema
      # (/etc/nixos/justfile), como no nix-config.
      justWrapper = pkgs.writeShellApplication {
        name = "just";
        text = ''
          dir=$PWD
          for arg in "$@"; do
            case "$arg" in
              -f | --justfile | --justfile=* | -f=*) exec ${pkgs.just}/bin/just "$@" ;;
            esac
          done
          while :; do
            for f in justfile .justfile Justfile; do
              [ -f "$dir/$f" ] && exec ${pkgs.just}/bin/just "$@"
            done
            [ "$dir" = / ] && break
            dir=$(dirname "$dir")
          done
          exec ${pkgs.just}/bin/just --justfile /etc/nixos/justfile --working-directory /etc/nixos "$@"
        '';
      };
    in
    {
      nix = {
        settings = {
          experimental-features = [
            "nix-command"
            "flakes"
          ];
          auto-optimise-store = true;
          trusted-users = [ "@wheel" ];
          substituters = [
            "https://cache.nixos.org"
            "https://nix-community.cachix.org"
          ];
          trusted-public-keys = [
            "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
            "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
          ];
        };
        gc = {
          automatic = true;
          dates = "weekly";
          options = "--delete-older-than 30d";
        };
      };

      networking.networkmanager.enable = true;

      # O espelho /etc/nixos pertence ao root e é lido e avaliado pelos
      # usuários (o git recusa repositórios de outro dono sem isto).
      programs.git = {
        enable = true;
        config.safe.directory = [
          "/etc/nixos"
          "/persist/etc/nixos"
        ];
      };

      environment.systemPackages = with pkgs; [
        git-crypt
        gh
        glab
        wget
        curl
        pciutils
        usbutils
        lshw
        file
        tree
        jq
        justWrapper
        unzip
        zip
        p7zip
        nmap
        dig
        traceroute
        iperf3
        lm_sensors
        nvtopPackages.intel
        gptfdisk
        parted
        e2fsprogs
        cryptsetup
        lvm2
        nvd
        ffmpeg
        libva-utils
        gst_all_1.gst-libav
        gst_all_1.gst-plugins-good
        gst_all_1.gst-plugins-bad
        gst_all_1.gst-plugins-ugly
      ];

      system.stateVersion = "26.05";
    };
}

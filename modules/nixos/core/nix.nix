# Configuração do Nix, caches e ferramentas básicas do sistema.
{
  flake.modules.nixos.nix =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      inherit (config.my) flakeDir;
      # `just` sem argumentos fora de um projeto cai no justfile do sistema
      # (/etc/nixos/justfile, isto é, o do clone em my.flakeDir), como no
      # nix-config.
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
      # O clone de trabalho é a fonte única da configuração: switch e boot
      # avaliam o flake direto dele, com ou sem alterações não commitadas, e
      # cada geração registra a revisão (com sufixo -dirty, se for o caso;
      # ver modules/flake/lib.nix). /etc/nixos é só um atalho para ele.
      options.my.flakeDir = lib.mkOption {
        type = lib.types.str;
        default = "/persist/etc/nixos";
        example = "/home/abutre/Projetos/lbssousa/nix-config-noctalia";
        description = ''
          Clone git desta configuração, de um usuário administrador, para o
          qual /etc/nixos aponta. O scripts/install.sh o cria no dono da home
          que o contém (ou no primeiro usuário com sudo, fora de /home).
        '';
      };

      config = {
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

        # "/" é tmpfs: o atalho é recriado a cada boot (o "+" troca o diretório
        # vazio que o stage 2 cria em /etc/nixos). Fica pendente até o clone
        # existir, sem efeito sobre o sistema.
        systemd.tmpfiles.rules = [ "L+ /etc/nixos - - - - ${flakeDir}" ];

        # O clone pertence a um usuário e também é lido pelo root (run0
        # nixos-rebuild) e por outros administradores; o git recusa
        # repositórios de outro dono sem isto.
        programs.git = {
          enable = true;
          config.safe.directory = lib.unique [
            "/etc/nixos"
            flakeDir
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
    };
}

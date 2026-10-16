# Boot: kernel mais recente, initrd do systemd (exigido pelo preservation e
# usado pelo desbloqueio TPM2), Plymouth e Limine silencioso.
{
  flake.modules.nixos.boot =
    { lib, pkgs, ... }:
    {
      boot = {
        kernelPackages = lib.mkDefault pkgs.linuxPackages_latest;
        supportedFilesystems = [ "btrfs" ];

        initrd = {
          systemd.enable = true;
          verbose = false;
        };

        loader = {
          efi.canTouchEfiVariables = true;
          # O Limine só aceita teclado com timeout > 0; com o fundo preto e sem
          # wallpaper, 1 s é imperceptível até o Plymouth.
          timeout = 1;
          limine = {
            enable = true;
            maxGenerations = 10;
            style = {
              wallpapers = [ ];
              backdrop = "000000";
              interface.helpHidden = true;
            };
            # Suprime "linux: Loading kernel/module" na tela; erros reais
            # continuam visíveis (o Limine desliga o quiet em pânico).
            extraConfig = "quiet: yes\n";
          };
        };

        plymouth = {
          enable = true;
          theme = lib.mkDefault "bgrt";
        };

        consoleLogLevel = 0;
        kernelParams = [
          "quiet"
          "splash"
          "loglevel=3"
          "rd.systemd.show_status=false"
          "rd.udev.log_level=3"
          "udev.log_priority=3"
          "vt.global_cursor_default=0"
        ];
      };
    };
}

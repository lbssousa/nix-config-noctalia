# Boot: kernel mais recente, Plymouth e Limine silencioso. O initrd é sempre o
# do systemd (o nixpkgs removeu o initrd em script), que o preservation exige e
# o desbloqueio TPM2 usa.
{
  flake.modules.nixos.boot =
    { lib, pkgs, ... }:
    {
      boot = {
        kernelPackages = lib.mkDefault pkgs.linuxPackages_latest;
        supportedFilesystems = [ "btrfs" ];

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

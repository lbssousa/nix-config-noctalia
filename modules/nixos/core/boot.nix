# Boot: kernel mais recente, systemd-boot sem menu e Plymouth desde o logo do
# firmware (boot sem cintilação). O initrd é sempre o do systemd (o nixpkgs
# removeu o initrd em script), que o preservation exige e o desbloqueio TPM2
# usa.
#
# Com o Secure Boot (security/secureboot.nix), quem instala o systemd-boot é o
# lanzaboote, que lê daqui o timeout, o editor, o modo do console e o limite
# de gerações.
{
  flake.modules.nixos.boot =
    { lib, pkgs, ... }:
    {
      boot = {
        kernelPackages = lib.mkDefault pkgs.linuxPackages_latest;
        supportedFilesystems = [ "btrfs" ];

        loader = {
          efi.canTouchEfiVariables = true;
          # Sem menu: segure Espaço (ou Esc) no boot para vê-lo.
          timeout = 0;
          systemd-boot = {
            enable = lib.mkDefault true;
            configurationLimit = 10;
            editor = false;
            # Mantém o modo de vídeo do firmware: sem troca de resolução entre
            # o logo do fabricante e o Plymouth.
            consoleMode = "keep";
          };
        };

        # bgrt: o logo do fabricante continua na tela, com o spinner embaixo.
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
          # Plymouth já no framebuffer do firmware (simpledrm), antes do i915
          # (early KMS, no initrd dos hosts) assumir a tela.
          "plymouth.use-simpledrm"
        ];
      };
    };
}

# Secure Boot com o lanzaboote (systemd-boot e UKIs assinados) e chaves
# próprias do sbctl.
#
# As chaves são criadas pelo install.sh em /persist/etc/secureboot; depois do
# primeiro boot, com o firmware em Setup Mode, rode `scripts/setup-secureboot.sh`.
# O lanzaboote assina o stub de cada geração em /boot/EFI/Linux e o próprio
# systemd-boot; kernel e initrd ficam em /boot/EFI/nixos sem assinatura,
# verificados pelo hash gravado no stub.
{ inputs, ... }:
{
  flake.modules.nixos.secureboot =
    { lib, pkgs, ... }:
    {
      imports = [ inputs.lanzaboote.nixosModules.lanzaboote ];

      # O lanzaboote substitui o instalador do systemd-boot; timeout, editor,
      # modo do console e limite de gerações vêm de core/boot.nix.
      boot.loader.systemd-boot.enable = lib.mkForce false;
      boot.lanzaboote = {
        enable = true;
        # Direto em /persist: o nixos-install já assina sem o symlink abaixo.
        pkiBundle = "/persist/etc/secureboot";
      };

      environment.systemPackages = [ pkgs.sbctl ];

      # / é tmpfs: o sbctl procura as chaves em /var/lib/sbctl.
      systemd.tmpfiles.rules = [ "L+ /var/lib/sbctl - - - - /persist/etc/secureboot" ];
    };
}

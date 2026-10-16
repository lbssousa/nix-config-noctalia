# Secure Boot com o suporte nativo do Limine e chaves próprias do sbctl.
#
# As chaves são criadas pelo install.sh em /persist/etc/secureboot; depois do
# primeiro boot, com o firmware em Setup Mode, rode `scripts/setup-secureboot.sh`.
{
  flake.modules.nixos.secureboot =
    { pkgs, ... }:
    {
      boot.loader.limine.secureBoot.enable = true;

      environment.systemPackages = [ pkgs.sbctl ];

      # / é tmpfs: o sbctl procura as chaves em /var/lib/sbctl.
      systemd.tmpfiles.rules = [ "L+ /var/lib/sbctl - - - - /persist/etc/secureboot" ];
    };
}

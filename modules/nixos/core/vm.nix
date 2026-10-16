# `nixos-rebuild build-vm` (ou .#nixosConfigurations.<host>.config.system.build.vm):
# testa o desktop sem o disco real — sem LUKS, swap ou Secure Boot, com GPU
# virtio (renderização por software). Os segredos sops não existem na VM (sem chave
# age), então Wi-Fi e a chave SSH do GitHub ficam de fora.
{
  flake.modules.nixos.vm =
    { lib, ... }:
    {
      virtualisation.vmVariant = {
        virtualisation = {
          memorySize = 6144;
          cores = 4;
          diskSize = 16384;
          # Sem GL no host (o QEMU do Nix não carrega os drivers da GPU do
          # host): o convidado renderiza com llvmpipe.
          qemu.options = [
            "-vga none"
            "-device virtio-vga"
            "-display gtk"
          ];
        };
        boot = {
          initrd.luks.devices = lib.mkForce { };
          resumeDevice = lib.mkForce "";
          loader.limine.secureBoot.enable = lib.mkForce false;
        };
        swapDevices = lib.mkForce [ ];
        services.kanata.enable = lib.mkForce false;
      };
    };
}

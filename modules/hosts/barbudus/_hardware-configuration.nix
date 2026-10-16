# Hardware configuration for barbudus (Dell Inspiron 14 5490)
# NOTE: This file should be regenerated with: nixos-generate-config --no-filesystems --root /mnt
# after the disko install. The generated file should replace this template.
{ lib, modulesPath, ... }:

{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
  ];

  # Kernel modules for Intel + NVME + USB
  boot = {
    initrd = {
      availableKernelModules = [
        "xhci_pci"
        "ahci"
        "nvme"
        "usb_storage"
        "sd_mod"
        "rtsx_pci_sdmmc"
      ];
      kernelModules = [
        "dm-snapshot"
        # Intel KMS for flicker-free boot
        "i915"
      ];
    };
    kernelModules = [
      "kvm-intel"
      "nvidia"
      "nvidia_modeset"
      "nvidia_uvm"
      "nvidia_drm"
    ];
    extraModulePackages = [ ];
  };

  # Intel microcode
  hardware.cpu.intel.updateMicrocode = true;

  # Filesystems e swap (LV com resume) vêm do disko: modules/hosts/_disko-btrfs.nix
  # zram e sysctls de swap: modules/nixos/core/swap.nix

  # Networking
  networking.useDHCP = lib.mkDefault true;

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.enableRedistributableFirmware = true;
}

# Swap híbrido: zram (rápido, prioridade alta) + LV de swap em disco
# (criada pelo disko, usada para hibernação).
{
  flake.modules.nixos.swap = {
    zramSwap = {
      enable = true;
      memoryPercent = 50;
      algorithm = "zstd";
      priority = 100;
    };

    boot.kernel.sysctl = {
      "vm.swappiness" = 10;
      "vm.vfs_cache_pressure" = 50;
      "vm.dirty_ratio" = 10;
      "vm.dirty_background_ratio" = 5;
    };
  };
}

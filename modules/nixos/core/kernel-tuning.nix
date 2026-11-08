# Rede e disco como no Omarchy 4.5 (MIT):
# - TCP BBR com pacing fq: estima banda e RTT mínimo em vez de encher a fila
#   até perder pacotes (menos bufferbloat);
# - escalonador kyber nos discos inteiros: segura a latência de leitura
#   enquanto builds, cópias e atualizações enchem o disco de escritas.
#   Partições não têm escalonador próprio, e a zram não tem o que escalonar.
{
  flake.modules.nixos.kernel-tuning = {
    boot.kernel.sysctl = {
      "net.core.default_qdisc" = "fq";
      "net.ipv4.tcp_congestion_control" = "bbr";
    };

    services.udev.extraRules = ''
      ACTION=="add|change", SUBSYSTEM=="block", ENV{DEVTYPE}=="disk", KERNEL=="nvme*|sd*|mmcblk*|vd*", ATTR{queue/scheduler}="kyber"
    '';
  };
}

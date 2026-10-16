# Root efêmero: "/" é tmpfs (ver modules/hosts/_disko-btrfs.nix) e o estado
# que precisa sobreviver ao boot fica em /persist, montado pelo preservation.
# /home é um subvolume btrfs próprio e não precisa de regras por usuário.
{ inputs, ... }:
{
  flake.modules.nixos.preservation = {
    imports = [ inputs.preservation.nixosModules.default ];

    fileSystems = {
      "/persist".neededForBoot = true;
      "/home".neededForBoot = true;
    };

    preservation = {
      enable = true;
      preserveAt."/persist" = {
        directories = [
          # Symlinks: lidos por stat() comum.
          {
            directory = "/etc/nixos";
            how = "symlink";
          }
          {
            directory = "/etc/NetworkManager/system-connections";
            how = "symlink";
          }
          {
            directory = "/var/lib/nixos";
            how = "symlink";
          }
          # Bind mounts: StateDirectory=/lstat() recusam symlinks.
          "/var/lib/bluetooth"
          "/var/lib/fprint"
          "/var/lib/systemd"
          "/var/lib/cups"
          "/var/lib/AccountsService"
          "/var/db/sudo"
        ];
        files = [
          # O journald lê o machine-id antes das montagens comuns.
          {
            file = "/etc/machine-id";
            inInitrd = true;
          }
          # /etc/shadow fica de fora: é restaurado/persistido pelo módulo
          # users (renomeações atômicas desfazem bind mounts).
        ];
      };
    };

    # O machine-id já é persistente; o commit do systemd falharia ("not on a
    # temporary file system"), então a condição é invertida.
    systemd.services.systemd-machine-id-commit = {
      overrideStrategy = "asDropin";
      unitConfig.ConditionPathIsMountPoint = [
        ""
        "!/etc/machine-id"
      ];
    };

    systemd.tmpfiles.rules = [
      # O config do sistema é editável pelo grupo wheel.
      "z /persist/etc/nixos 0775 root wheel - -"
      # libdbus (não dbus-broker) lê este caminho, efêmero com / em tmpfs.
      "d  /var/lib/dbus 0755 root root - -"
      "L+ /var/lib/dbus/machine-id - - - - /etc/machine-id"
    ];
  };
}

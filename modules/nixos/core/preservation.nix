# Root efêmero: "/" é tmpfs (ver modules/hosts/_disko-btrfs.nix) e o estado
# que precisa sobreviver ao boot fica em /persist, montado pelo preservation.
# /home é um subvolume btrfs próprio e não precisa de regras por usuário.
#
# O módulo do preservation ainda lê boot.initrd.systemd.enable numa assertion
# ("cannot be used with scripted initrd"), mas o nixpkgs removeu a opção (o
# initrd é sempre o do systemd) e lê-la virou erro. Importa o mesmo módulo
# sem a assertion; remover quando o upstream corrigir.
{ inputs, ... }:
let
  preservationModule =
    args:
    let
      module = import inputs.preservation.nixosModules.default args;
    in
    assert module.config._type or null == "if";
    module
    // {
      _file = toString inputs.preservation.nixosModules.default;
      config = module.config // {
        content = removeAttrs module.config.content [ "assertions" ];
      };
    };
in
{
  flake.modules.nixos.preservation = {
    imports = [ preservationModule ];

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
          # sync.toml do greeter: último usuário, última sessão e tema escolhido
          # na tela de login. O greeter.toml é um symlink que o tmpfiles recria
          # a cada boot.
          {
            directory = "/var/lib/noctalia-greeter";
            user = "greeter";
            group = "greeter";
            mode = "0750";
          }
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
      # Espelho git do config (somente `git pull --ff-only`): criado se faltar,
      # setgid para que os arquivos herdem o grupo wheel.
      "d /persist/etc/nixos 2775 root wheel - -"
      # libdbus (não dbus-broker) lê este caminho, efêmero com / em tmpfs.
      "d  /var/lib/dbus 0755 root root - -"
      "L+ /var/lib/dbus/machine-id - - - - /etc/machine-id"
    ];
  };
}

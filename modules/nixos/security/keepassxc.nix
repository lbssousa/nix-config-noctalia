# KeePassXC como gerenciador de senhas padrão de todos os usuários
# (home/security/keepassxc.nix), com o agente SSH do sistema para a
# integração SSH dele. O Secret Service continua sendo o oo7
# (desktop/secret-service.nix), desbloqueado no login.
#
# Ao remover a YubiKey, todos os bancos abertos são travados, em todas as
# sessões (D-Bus org.keepassxc.KeePassXC.MainWindow.lockAllDatabases).
{ config, ... }:
let
  userNames = builtins.attrNames config.my.users;
in
{
  flake.modules.nixos.keepassxc =
    { lib, pkgs, ... }:
    let
      lockAll = pkgs.writeShellApplication {
        name = "keepassxc-lock-on-yubikey-remove";
        runtimeInputs = with pkgs; [
          coreutils
          glib
          util-linux
        ];
        text = ''
          for username in "$@"; do
            uid="$(id -u "$username" 2>/dev/null)" || continue
            runtime_dir="/run/user/$uid"
            [ -S "$runtime_dir/bus" ] || continue
            env=(XDG_RUNTIME_DIR="$runtime_dir" DBUS_SESSION_BUS_ADDRESS="unix:path=$runtime_dir/bus")

            has_owner="$(runuser -u "$username" -- env "''${env[@]}" \
              gdbus call --session --dest org.freedesktop.DBus --object-path /org/freedesktop/DBus \
              --method org.freedesktop.DBus.NameHasOwner org.keepassxc.KeePassXC.MainWindow 2>/dev/null || true)"
            case "$has_owner" in
              *"(true,"*) ;;
              *) continue ;;
            esac

            runuser -u "$username" -- env "''${env[@]}" \
              gdbus call --session --dest org.keepassxc.KeePassXC.MainWindow --object-path /keepassxc \
              --method org.keepassxc.KeePassXC.MainWindow.lockAllDatabases >/dev/null 2>&1 || true
          done
        '';
      };
    in
    {
      environment.systemPackages = [ pkgs.keepassxc ];

      # Agente SSH por usuário (systemd --user, SSH_AUTH_SOCK no ambiente da
      # sessão); o KeePassXC adiciona e remove as chaves dos bancos nele.
      programs.ssh.startAgent = true;

      # No "remove", ID_VENDOR_ID e afins já sumiram; o PRODUCT continua lá.
      services.udev.extraRules = ''
        ACTION=="remove", SUBSYSTEM=="usb", ENV{DEVTYPE}=="usb_device", ENV{PRODUCT}=="1050/407/*", RUN+="${pkgs.systemd}/bin/systemd-run --no-block --quiet --collect --service-type=oneshot ${lib.getExe lockAll} ${lib.escapeShellArgs userNames}"
      '';
    };
}

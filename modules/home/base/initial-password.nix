# Aviso persistente enquanto o usuário ainda não definiu uma senha (marcado em
# /run/initial-password/<usuario> por modules/nixos/core/users.nix). É só
# reserva: a conta nasce sem senha e expirada, e o greeter exige a definição
# antes de abrir a sessão.
{
  flake.modules.homeManager.initial-password =
    { config, pkgs, ... }:
    let
      flag = "/run/initial-password/${config.home.username}";
    in
    {
      systemd.user.services.initial-password-warning = {
        Unit = {
          Description = "Aviso de conta sem senha";
          After = [ "graphical-session.target" ];
          PartOf = [ "graphical-session.target" ];
          ConditionPathExists = flag;
        };
        Service = {
          Type = "oneshot";
          # Espera a shell (servidor de notificações) subir.
          ExecStartPre = "${pkgs.coreutils}/bin/sleep 5";
          ExecStart = ''
            ${pkgs.libnotify}/bin/notify-send --urgency=critical --expire-time=0 \
              --icon=dialog-password "Defina sua senha" \
              "Sua conta ainda está sem senha. Abra um terminal (Super+Return) e rode: passwd"
          '';
        };
        Install.WantedBy = [ "graphical-session.target" ];
      };

      programs.fish.interactiveShellInit = ''
        if test -e ${flag}
          set_color --bold red
          echo "⚠ Sua conta ainda está sem senha. Defina uma com: passwd"
          set_color normal
        end
      '';
    };
}

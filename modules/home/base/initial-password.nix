# Aviso persistente enquanto o usuário ainda usa a senha inicial (marcada em
# /run/initial-password/<usuario> por modules/nixos/core/users.nix).
{
  flake.modules.homeManager.initial-password =
    { config, pkgs, ... }:
    let
      flag = "/run/initial-password/${config.home.username}";
    in
    {
      systemd.user.services.initial-password-warning = {
        Unit = {
          Description = "Aviso de senha inicial";
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
              --icon=dialog-password "Troque sua senha inicial" \
              "Você ainda usa a senha provisória. Abra um terminal (Super+Return) e rode: passwd"
          '';
        };
        Install.WantedBy = [ "graphical-session.target" ];
      };

      programs.fish.interactiveShellInit = ''
        if test -e ${flag}
          set_color --bold red
          echo "⚠ Você ainda usa a senha provisória. Troque-a com: passwd"
          set_color normal
        end
      '';
    };
}

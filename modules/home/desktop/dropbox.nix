# Dropbox (cliente gráfico, ícone na bandeja) junto com a sessão, para cada
# usuário com my.dropbox.enable. Se o "Iniciar o Dropbox com o sistema" dele
# também estiver ligado, a segunda instância só vê que já há uma rodando e sai.
{
  flake.modules.homeManager.dropbox =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      options.my.dropbox.enable =
        lib.mkEnableOption "Dropbox (cliente gráfico na bandeja, iniciado com a sessão)";

      config = lib.mkIf config.my.dropbox.enable {
        home.packages = [ pkgs.dropbox ];

        systemd.user.services.dropbox = {
          Unit = {
            Description = "Dropbox";
            After = [ "graphical-session.target" ];
            PartOf = [ "graphical-session.target" ];
          };
          Service = {
            ExecStart = lib.getExe pkgs.dropbox;
            Restart = "on-failure";
            KillMode = "control-group";
          };
          Install.WantedBy = [ "graphical-session.target" ];
        };
      };
    };
}

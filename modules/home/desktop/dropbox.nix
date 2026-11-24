# Dropbox (Flatpak com.dropbox.Client; cliente gráfico, ícone na bandeja)
# junto com a sessão, para cada usuário com my.dropbox.enable. O Flatpak é
# instalado no sistema quando algum usuário o liga (nixos/desktop/apps.nix).
# Ele enxerga o home inteiro, então ~/.dropbox e ~/Dropbox ficam onde já
# estavam. Se o "Iniciar o Dropbox com o sistema" do app também estiver
# ligado, a segunda instância só vê que já há uma rodando e sai.
{
  flake.modules.homeManager.dropbox =
    {
      config,
      lib,
      osConfig,
      ...
    }:
    {
      options.my.dropbox.enable = lib.mkEnableOption "Dropbox (cliente gráfico na bandeja, iniciado com a sessão)";

      config = lib.mkIf config.my.dropbox.enable {
        systemd.user.services.dropbox = {
          Unit = {
            Description = "Dropbox";
            After = [ "graphical-session.target" ];
            PartOf = [ "graphical-session.target" ];
          };
          Service = {
            ExecStart = "${lib.getExe' osConfig.services.flatpak.package "flatpak"} run com.dropbox.Client";
            Restart = "on-failure";
            KillMode = "control-group";
          };
          Install.WantedBy = [ "graphical-session.target" ];
        };
      };
    };
}

# KeePassXC de cada usuário: ícone na bandeja, integração com o navegador e
# agente SSH (as chaves marcadas nos bancos entram no ssh-agent do sistema ao
# desbloquear e saem ao travar). Sem FdoSecrets: o Secret Service é o oo7.
#
# Override local: ~/.config/keepassxc/keepassxc.ini é do home-manager; ajustes
# feitos na interface que não estejam aqui continuam valendo até o próximo
# switch.
{
  flake.modules.homeManager.keepassxc =
    { lib, ... }:
    {
      programs.keepassxc = {
        enable = lib.mkDefault true;
        autostart = lib.mkDefault true;
        settings = {
          Browser = {
            Enabled = true;
            # O home-manager gera os manifestos; o KeePassXC não os reescreve.
            UpdateBinaryPath = false;
          };
          FdoSecrets.Enabled = false;
          GUI = {
            MinimizeOnClose = true;
            MinimizeToTray = true;
            MinimizeOnStartup = true;
            ShowTrayIcon = true;
            TrayIconAppearance = "monochrome-light";
            MonospaceNotes = true;
          };
          Security.IconDownloadFallback = true;
          SSHAgent.Enabled = true;
        };
      };

      xdg.autostart.enable = lib.mkDefault true;

      # O ssh-agent do sistema (programs.ssh.startAgent, security/keepassxc.nix)
      # escuta em $XDG_RUNTIME_DIR/ssh-agent. O NixOS só exporta o
      # SSH_AUTH_SOCK nos shells; pelo environment.d ele chega também à sessão
      # gráfica e ao KeePassXC, que adiciona as chaves dos bancos ao agente.
      systemd.user.sessionVariables.SSH_AUTH_SOCK = "\${XDG_RUNTIME_DIR}/ssh-agent";
    };
}

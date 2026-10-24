# Cliente SSH de todos os usuários. O agente é o do Bitwarden para quem tem
# my.bitwarden.enable (home/security/bitwarden.nix) e, para os demais, o
# ssh-agent do sistema (programs.ssh.startAgent, nixos/security/bitwarden.nix).
# O ssh não adiciona chaves ao agente por conta própria.
#
# Sem ControlMaster no sistema instalado: ele fica só na config SSH da
# instalação (scripts/import-ssh-yubikey.sh, usada pelo install.sh).
#
# Override local: ~/.ssh/config.d/*.conf, incluído ANTES dos blocos gerados
# (no ssh, vale o primeiro valor encontrado para cada opção).
{
  flake.modules.homeManager.ssh = {
    services.ssh-agent.enable = false;

    programs.ssh = {
      enable = true;
      enableDefaultConfig = false;
      includes = [ "~/.ssh/config.d/*.conf" ];
      settings."*" = {
        AddKeysToAgent = "no";
        ServerAliveInterval = 60;
        ServerAliveCountMax = 3;
      };
    };

    home.file.".ssh/config.d/.keep".text = "";

    # O ssh-agent do sistema escuta em $XDG_RUNTIME_DIR/ssh-agent, mas o NixOS
    # só exporta o SSH_AUTH_SOCK nos shells; pelo environment.d
    # (10-home-manager.conf) ele chega também à sessão gráfica. O do Bitwarden
    # vem num environment.d posterior e vence.
    systemd.user.sessionVariables.SSH_AUTH_SOCK = "\${XDG_RUNTIME_DIR}/ssh-agent";
  };
}

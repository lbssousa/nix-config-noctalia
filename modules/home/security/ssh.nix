# Cliente SSH de todos os usuários, com as chaves no ssh-agent do sistema
# (programs.ssh.startAgent, security/keepassxc.nix), alimentado pelo KeePassXC.
# O ssh não adiciona chaves ao agente por conta própria.
#
# Cada conexão mestra (ControlMaster) é reaproveitada por 10 minutos: a
# confirmação de uso da chave (noctalia-askpass) é pedida uma vez por host nessa
# janela, em vez de a cada operação (git fetch/push, nixos-rebuild buscando o
# nix-secrets…).
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
        ControlMaster = "auto";
        ControlPersist = "10m";
        ControlPath = "~/.ssh/cm/%C";
      };
    };

    home.file.".ssh/config.d/.keep".text = "";
    systemd.user.tmpfiles.rules = [ "d %h/.ssh/cm 0700 - - -" ];
  };
}

# Cliente SSH de todos os usuários, sem ssh-agent próprio: o agente é o do
# Bitwarden para quem tem my.bitwarden.enable (home/security/bitwarden.nix).
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
  };
}

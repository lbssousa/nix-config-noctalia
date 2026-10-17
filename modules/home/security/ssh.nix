# Cliente SSH de todos os usuários, com as chaves no agente SSH do Bitwarden
# (SSH_AUTH_SOCK definido em home/security/bitwarden.nix). Nenhum outro agente
# é iniciado e o ssh não adiciona chaves ao agente.
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

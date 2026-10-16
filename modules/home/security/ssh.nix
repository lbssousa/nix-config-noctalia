# Cliente SSH sem agente para todos os usuários.
#
# Override local: ~/.ssh/config.d/*.conf, incluído ANTES dos blocos gerados
# (no ssh, vale o primeiro valor encontrado para cada opção).
#
# my.sshGithub.enable: GitHub com a chave FIDO2 residente da YubiKey
# (id_ed25519_sk_rk_github.com_lbssousa). O "handle" da chave vem cifrado do
# nix-secrets (sops-nix); a chave privada nunca sai da YubiKey. Uma conexão
# mestra (ControlMaster) é reaproveitada por 15 minutos, então o toque na
# YubiKey é pedido uma vez em vez de a cada operação git.
{ inputs, ... }:
{
  flake.modules.homeManager.ssh =
    { config, lib, ... }:
    let
      keyName = "id_ed25519_sk_rk_github.com_lbssousa";
      keyPath = "${config.home.homeDirectory}/.ssh/${keyName}";
    in
    {
      options.my.sshGithub.enable = lib.mkEnableOption "acesso ao github.com com a chave residente da YubiKey";

      config = lib.mkMerge [
        {
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
        }

        (lib.mkIf config.my.sshGithub.enable {
          sops.secrets."ssh-github-key" = {
            sopsFile = inputs.nix-secrets + "/secrets.yaml";
            key = "abutre/ssh/github_com_lbssousa";
            path = keyPath;
            mode = "0600";
          };

          home.file.".ssh/${keyName}.pub".text = inputs.nix-secrets.abutre.sshPublicKeys.github + "\n";

          programs.ssh.settings."github.com" = {
            HostName = "github.com";
            User = "git";
            IdentityFile = keyPath;
            IdentitiesOnly = true;
            IdentityAgent = "none";
            AddKeysToAgent = "no";
            ControlMaster = "auto";
            ControlPersist = "15m";
            ControlPath = "~/.ssh/cm/%C";
          };

          systemd.user.tmpfiles.rules = [ "d %h/.ssh/cm 0700 - - -" ];
        })
      ];
    };
}

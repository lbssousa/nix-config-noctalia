# Servidor SSH: só chave pública, sem root, chaves do host em /persist.
{
  flake.modules.nixos.sshd =
    { lib, ... }:
    {
      services.openssh = {
        enable = true;
        settings = {
          PasswordAuthentication = lib.mkDefault false;
          KbdInteractiveAuthentication = false;
          PermitRootLogin = "no";
        };
        hostKeys = [
          {
            path = "/persist/etc/ssh/ssh_host_ed25519_key";
            type = "ed25519";
          }
          {
            path = "/persist/etc/ssh/ssh_host_rsa_key";
            type = "rsa";
            bits = 4096;
          }
        ];
      };

      # O agente SSH é o do Bitwarden, por usuário (ver
      # home/security/bitwarden.nix).
      programs.ssh.startAgent = false;
    };
}

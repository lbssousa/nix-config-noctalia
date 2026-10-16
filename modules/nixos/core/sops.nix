# sops-nix no sistema: a chave age do host fica em /persist (copiada pelo
# install.sh a partir do repositório nix-keys).
{ inputs, ... }:
{
  flake.modules.nixos.sops = {
    imports = [ inputs.sops-nix.nixosModules.sops ];

    sops = {
      defaultSopsFile = inputs.nix-secrets + "/secrets.yaml";
      age.keyFile = "/persist/etc/sops/age/keys.txt";
      # Sem chaves SSH de host como fonte age (são geradas no primeiro boot).
      age.sshKeyPaths = [ ];
      gnupg.sshKeyPaths = [ ];
    };
  };
}

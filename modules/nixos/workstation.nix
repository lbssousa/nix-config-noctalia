# Perfil comum a todos os hosts: compõe as features genéricas. Cada host em
# modules/hosts/ importa este perfil e acrescenta as features do seu hardware.
{ config, ... }:
let
  m = config.flake.modules.nixos;
in
{
  flake.modules.nixos.workstation = {
    imports = [
      # núcleo
      m.overlay
      m.nix
      m.boot
      m.locale
      m.swap
      m.preservation
      m.sops
      m.users
      m.home-manager
      m.vm
      # segurança (Secure Boot e TPM2 em todos os hosts)
      m.secureboot
      m.tpm2
      m.yubikey
      m.yubikey-notify
      m.pam-policy
      m.bitwarden
      m.keepassxc
      m.selinux
      m.sshd
      m.secret-prompts
      m.first-login
      # desktop
      m.session
      m.audio
      m.fonts
      m.cursor
      m.secret-service
      m.firefox
      m.apps
      m.file-manager
      # periféricos e rede
      m.printing
      m.wifi-home
      m.kanata
      # desenvolvimento
      m.podman
      m.nix-ld
      m.ai-agents
    ];
  };
}

# Bitwarden como gerenciador de senhas padrão: app desktop (Flatpak
# com.bitwarden.desktop) e CLI (`bw`, nativo) para todos os usuários. Ícone na
# bandeja, autostart, agente SSH e preferências do app são de cada usuário
# (home/security/bitwarden.nix, my.bitwarden.enable). O Secret Service
# continua sendo o oo7 (desktop/secret-service.nix), que o app alcança pela
# permissão org.freedesktop.secrets do Flatpak.
#
# Desbloqueio biométrico: o app pede a ação polkit "com.bitwarden.Bitwarden.unlock"
# (auth_self), que precisa estar no host; a política vem de
# apps/desktop/resources/com.bitwarden.desktop.policy (bitwarden/clients),
# guardada em _bitwarden/. A autenticação segue a pilha PAM "polkit-1"
# (digital, chave de segurança ou senha).
#
# Native messaging: o próprio app, em Flatpak, grava o manifesto, o proxy e o
# socket IPC nos navegadores em Flatpak que conhece (o Firefox, aqui); o Brave
# precisa de ajustes (home/desktop/brave.nix). A integração com o navegador
# vem sempre ligada no app.
{
  flake.modules.nixos.bitwarden =
    { pkgs, ... }:
    let
      policy = ./_bitwarden/com.bitwarden.Bitwarden.policy;
      # O polkitd lê as ações de share/polkit-1/actions do perfil do sistema.
      polkitActions = pkgs.runCommand "bitwarden-polkit-actions" { } ''
        install -Dm644 ${policy} $out/share/polkit-1/actions/com.bitwarden.Bitwarden.policy
      '';
    in
    {
      services.flatpak.packages = [ "com.bitwarden.desktop" ];

      environment.systemPackages = [
        pkgs.bitwarden-cli
        polkitActions
      ];

      # Sem ssh-agent do sistema: o agente SSH é o do próprio Bitwarden
      # (home/security/bitwarden.nix).
      programs.ssh.startAgent = false;

      # O app também procura a política em /usr/share/polkit-1/actions.
      system.activationScripts.bitwardenPolkitUsr = {
        text = ''
          mkdir -p /usr/share/polkit-1/actions
          ln -sf ${policy} /usr/share/polkit-1/actions/com.bitwarden.Bitwarden.policy
        '';
        deps = [ ];
      };
    };
}

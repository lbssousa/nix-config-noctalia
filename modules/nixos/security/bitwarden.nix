# Bitwarden como gerenciador de senhas padrão: app desktop e CLI (`bw`) para
# todos os usuários. Ícone na bandeja, autostart, agente SSH e preferências do
# app são de cada usuário (home/security/bitwarden.nix, my.bitwarden.enable).
# O Secret Service continua sendo o oo7 (desktop/secret-service.nix).
#
# Desbloqueio biométrico: o pacote bitwarden-desktop já instala a ação polkit
# "com.bitwarden.Bitwarden.unlock" (auth_self) em share/polkit-1/actions, que o
# polkitd lê de /run/current-system/sw; a autenticação segue a pilha PAM
# "polkit-1" (digital, chave de segurança ou senha).
#
# O app só oferece o desbloqueio se achar um Secret Service (oo7, no Rust).
# O ashpd que ele embute trata GTK_USE_PORTAL=1 (nixos/desktop/file-manager.nix)
# como sandbox, e aí o oo7 tenta o portal Secret, que recusa o Electron (não
# consegue abrir /proc/<pid>/root): sem segredos, o app esconde a biometria. O
# bitwarden fica num wrapper sem essa variável; o Electron usa o portal de
# arquivos por conta própria.
#
# Native messaging com a extensão do Firefox (nixos/desktop/firefox.nix): o
# manifesto com.8bit.bitwarden vai para o diretório do sistema do wrapper do
# Firefox (MOZ_SYSTEM_DIR) e aponta para o desktop_proxy do pacote, que
# conversa com o app em execução. O app ainda grava a própria cópia em
# ~/.mozilla/native-messaging-hosts quando essa pasta existe; as duas levam ao
# mesmo app.
#
# O ssh-agent do sistema fica para os usuários sem o Bitwarden: quem o tem
# ligado aponta o SSH_AUTH_SOCK para o agente dele.
{
  flake.modules.nixos.bitwarden =
    { pkgs, ... }:
    let
      bitwarden-desktop = pkgs.symlinkJoin {
        name = "bitwarden-desktop-${pkgs.bitwarden-desktop.version}";
        paths = [ pkgs.bitwarden-desktop ];
        nativeBuildInputs = [ pkgs.makeWrapper ];
        postBuild = ''
          wrapProgram $out/bin/bitwarden --unset GTK_USE_PORTAL
        '';
      };

      nativeMessagingHost = pkgs.writeTextFile {
        name = "bitwarden-native-messaging-host";
        destination = "/lib/mozilla/native-messaging-hosts/com.8bit.bitwarden.json";
        text = builtins.toJSON {
          name = "com.8bit.bitwarden";
          description = "Bitwarden desktop <-> browser bridge";
          path = "${pkgs.bitwarden-desktop}/libexec/desktop_proxy";
          type = "stdio";
          allowed_extensions = [ "{446900e4-71c2-419f-a6a7-df9c091e268b}" ];
        };
      };
    in
    {
      environment.systemPackages = [
        bitwarden-desktop
        pkgs.bitwarden-cli
      ];

      programs.firefox.nativeMessagingHosts.packages = [ nativeMessagingHost ];

      # Agente SSH por usuário (systemd --user, em $XDG_RUNTIME_DIR/ssh-agent).
      programs.ssh.startAgent = true;
    };
}

# Agente SSH do Bitwarden para todos os usuários.
#
# O SSH_AUTH_SOCK vai para o environment.d, lido pelo systemd --user no início
# da sessão: o Umbriel, a Noctalia e tudo o que eles abrem já o herdam, mesmo
# antes de o Bitwarden subir (o Umbriel o inicia no autostart). O agente
# precisa ser ligado uma vez no app (Configurações → "Ativar agente SSH"); as
# chaves ficam no cofre e cada uso pede autorização no Bitwarden.
#
# Override local: um ~/.config/environment.d/*.conf posterior (ex.:
# 90-ssh.conf) ou ~/.ssh/config.d/*.conf com IdentityAgent.
{
  flake.modules.homeManager.bitwarden =
    { config, lib, ... }:
    let
      sock = "${config.home.homeDirectory}/.bitwarden-ssh-agent.sock";
    in
    {
      xdg.configFile."environment.d/20-bitwarden-ssh-agent.conf".text = ''
        SSH_AUTH_SOCK=${sock}
      '';

      # Shells fora da sessão gráfica (login por SSH, su): só preenche o
      # SSH_AUTH_SOCK se não houver outro (ex.: um agente repassado).
      programs.fish.interactiveShellInit = lib.mkAfter ''
        set -q SSH_AUTH_SOCK; or set -gx SSH_AUTH_SOCK "${sock}"
      '';
      programs.bash.initExtra = lib.mkAfter ''
        [ -n "''${SSH_AUTH_SOCK:-}" ] || export SSH_AUTH_SOCK="${sock}"
      '';
    };
}

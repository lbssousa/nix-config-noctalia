# Pinentry do GnuPG e SSH_ASKPASS num painel da Noctalia (plugin
# lbssousa/secret-prompts, habilitado por padrão em home/desktop/noctalia.nix),
# para todos os usuários. Sem a shell ou sem o plugin, o pinentry cai no
# pinentry-curses e o askpass falha (o ssh volta a perguntar no TTY).
{
  flake.modules.nixos.secret-prompts =
    { lib, pkgs, ... }:
    {
      # /etc/gnupg/gpg-agent.conf (pinentry-program) e os sockets do gpg-agent
      # para todo usuário. Quem liga o gpg-agent pelo home-manager
      # (home/security/gpg-yubikey.nix) usa o mesmo pinentry.
      programs.gnupg.agent = {
        enable = true;
        pinentryPackage = pkgs.pinentry-noctalia;
      };

      # SSH_ASKPASS: ssh, ssh-add e git (sem GIT_ASKPASS, o git usa o
      # SSH_ASKPASS) fora de um terminal. Sem SSH_ASKPASS_REQUIRE: com um TTY,
      # o ssh continua perguntando nele.
      programs.ssh = {
        enableAskPassword = true;
        askPassword = lib.getExe pkgs.noctalia-askpass;
      };
    };
}

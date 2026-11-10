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
      # SSH_ASKPASS). Com SSH_ASKPASS_REQUIRE=prefer, também num terminal,
      # sempre que houver sessão gráfica (DISPLAY/WAYLAND_DISPLAY); sem ela
      # (console, ssh remoto), o ssh pergunta no TTY. O aviso "Confirm user
      # presence" das chaves FIDO é a exceção: o OpenSSH o escreve no terminal
      # quando o stderr é um TTY (notify_start), qualquer que seja esta variável.
      programs.ssh = {
        enableAskPassword = true;
        askPassword = lib.getExe pkgs.noctalia-askpass;
      };
      environment.sessionVariables.SSH_ASKPASS_REQUIRE = "prefer";
    };
}

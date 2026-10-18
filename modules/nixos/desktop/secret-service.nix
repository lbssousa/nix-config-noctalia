# oo7 como Secret Service (org.freedesktop.secrets) de todos os usuários, no
# lugar do gnome-keyring.
#
# O módulo do nixpkgs liga o daemon por usuário, o pam_oo7 no serviço "login"
# (o greetd herda: auth/session do greetd são substack/include do login) e o
# oo7-portal. O chaveiro padrão é desbloqueado no login com a mesma senha; se
# ela for diferente, o oo7 pede a do chaveiro depois do login.
{
  flake.modules.nixos.secret-service =
    { lib, ... }:
    {
      services.oo7.enable = true;
      services.gnome.gnome-keyring.enable = false;

      # Troca de senha (pilha "password" do login, herdada pelo greetd): o
      # pam_unix vem "sufficient" e o pam_oo7 "optional" depois dele. Se o
      # pam_unix falha, a falha é descartada e quem decide é o pam_oo7, que
      # ignora a fase preliminar (o PAM devolve o genérico PERM_DENIED no lugar
      # de "senha atual incorreta") e aceita a gravação (confirmação diferente
      # passava como troca feita). Com "required", a falha do pam_unix vale e o
      # pam_oo7 só acompanha, para trocar também a senha do chaveiro.
      security.pam.services.login.rules.password.unix.control = lib.mkForce "required";

      # Portal Secret (org.freedesktop.impl.portal.Secret). O oo7-portal só
      # se declara para GNOME
      # (UseIn=gnome) e o umbriel-portals.conf do pacote prefere umbriel;gtk,
      # que não oferecem Secret. Este arquivo substitui o do pacote, então o
      # "default" dele é repetido aqui.
      xdg.portal.config.umbriel = {
        default = [
          "umbriel"
          "gtk"
        ];
        "org.freedesktop.impl.portal.Secret" = [ "oo7-portal" ];
      };
    };
}

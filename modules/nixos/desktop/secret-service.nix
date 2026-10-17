# oo7 como Secret Service (org.freedesktop.secrets) de todos os usuários, no
# lugar do gnome-keyring.
#
# O módulo do nixpkgs liga o daemon por usuário, o pam_oo7 no serviço "login"
# (o greetd herda: auth/session do greetd são substack/include do login) e o
# oo7-portal. O chaveiro padrão é desbloqueado no login com a mesma senha; se
# ela for diferente, o oo7 pede a do chaveiro depois do login.
{
  flake.modules.nixos.secret-service = {
    services.oo7.enable = true;
    services.gnome.gnome-keyring.enable = false;

    # Portal Secret dos Flatpaks. O oo7-portal só se declara para GNOME
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

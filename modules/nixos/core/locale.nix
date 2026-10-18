# Idioma pt_BR, fuso de São Paulo e teclado ABNT2.
{
  flake.modules.nixos.locale = {
    time.timeZone = "America/Sao_Paulo";

    # Sem input method (fcitx5), o GTK (Ghostty) tenta o text-input do Wayland
    # e as teclas mortas (´ ` ~ ^) não compõem — só o ç, que tem tecla própria.
    # Forçar o contexto "simple" faz o GTK compor as letras acentuadas sozinho.
    environment.sessionVariables.GTK_IM_MODULE = "simple";

    i18n = {
      defaultLocale = "pt_BR.UTF-8";
      extraLocaleSettings = {
        LC_ADDRESS = "pt_BR.UTF-8";
        LC_IDENTIFICATION = "pt_BR.UTF-8";
        LC_MEASUREMENT = "pt_BR.UTF-8";
        LC_MONETARY = "pt_BR.UTF-8";
        LC_NAME = "pt_BR.UTF-8";
        LC_NUMERIC = "pt_BR.UTF-8";
        LC_PAPER = "pt_BR.UTF-8";
        LC_TELEPHONE = "pt_BR.UTF-8";
        LC_TIME = "pt_BR.UTF-8";
      };
    };

    # O TTY segue o layout XKB do sistema; o Umbriel e o greeter recebem o
    # mesmo layout pelas suas próprias configurações.
    console.useXkbConfig = true;
    services.xserver.xkb = {
      layout = "br";
      variant = "abnt2";
      model = "abnt2";
    };
  };
}

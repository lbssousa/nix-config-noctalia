# Sessão gráfica: compositor Umbriel + shell Noctalia + Noctalia Greeter.
{
  flake.modules.nixos.session =
    { pkgs, ... }:
    {
      programs.umbriel.enable = true;

      # A shell em si é iniciada pelo home-manager (programs.noctalia.systemd);
      # aqui ficam só os serviços de sistema que as integrações usam
      # (NetworkManager, bluetooth, UPower, power-profiles-daemon).
      programs.noctalia = {
        enable = true;
        recommendedServices.enable = true;
      };

      services.displayManager.noctalia-greeter = {
        enable = true;
        settings = {
          keyboard.layout = "br";
          keyboard.variant = "abnt2";
          # Patch do PR noctalia-greeter#131 (ver modules/flake/packages.nix):
          # mostra o nome completo (AccountsService RealName/GECOS).
          appearance.show_real_names = true;
          # Mesmo tema da shell. Esquemas embutidos usam sempre a variante
          # escura no greeter; fixado aqui, vence a última escolha feita na
          # tela de login (F7), que fica em /var/lib/noctalia-greeter/sync.toml.
          appearance.scheme = "Nord";
          # Enter com o campo vazio envia: é o primeiro login de uma conta sem
          # senha (security/first-login.nix). Quem decide é o PAM, que só
          # aceita senha vazia em conta expirada. O patch do greeter já começa
          # esse fluxo sozinho quando o AccountsService diz SetAtLogin; isto
          # cobre o caso de ele não responder.
          auth.allow_empty_password = true;
        };
      };

      hardware.bluetooth.powerOnBoot = true;

      xdg.portal = {
        enable = true;
        extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
      };

      environment.sessionVariables = {
        NIXOS_OZONE_WL = "1";
        ELECTRON_OZONE_PLATFORM_HINT = "auto";
      };

      environment.systemPackages = with pkgs; [
        wl-clipboard
        libnotify
        xdg-utils
      ];
    };
}

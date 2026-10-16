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
        };
        cursorTheme = {
          package = pkgs.adwaita-icon-theme;
          name = "Adwaita";
        };
      };

      # Chaveiro (Secret Service) desbloqueado no login gráfico.
      security.pam.services.greetd.enableGnomeKeyring = true;

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
        adwaita-icon-theme
      ];
    };
}

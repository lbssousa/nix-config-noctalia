# Firefox nativo como navegador padrão do sistema.
#
# As preferências vão em políticas com Status = "default" (não em user.js):
# viram o valor padrão, e o usuário pode mudá-las em about:config sem que o
# Nix as sobrescreva no próximo início. O idioma vem do languagePacks (pt-BR).
{
  flake.modules.nixos.firefox = {
    programs.firefox = {
      enable = true;
      languagePacks = [ "pt-BR" ];
      policies = {
        DisableTelemetry = true;
        DontCheckDefaultBrowser = true;
        Preferences =
          let
            default = value: {
              Value = value;
              Status = "default";
            };
          in
          {
            # "Adicionar aba à barra de tarefas" (Taskbar Tabs / web apps).
            "browser.taskbarTabs.enabled" = default true;
            # Necessário para o userChrome.css dos perfis de web apps.
            "toolkit.legacyUserProfileCustomizations.stylesheets" = default true;
            "widget.use-xdg-desktop-portal.file-picker" = default 1;
          };
      };
    };

    # Padrão do sistema; cada usuário pode trocar em ~/.config/mimeapps.list.
    xdg.mime.defaultApplications = {
      "text/html" = "firefox.desktop";
      "x-scheme-handler/http" = "firefox.desktop";
      "x-scheme-handler/https" = "firefox.desktop";
      "x-scheme-handler/about" = "firefox.desktop";
      "x-scheme-handler/unknown" = "firefox.desktop";
    };
  };
}

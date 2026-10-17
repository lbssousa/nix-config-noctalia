# Firefox (Flatpak org.mozilla.firefox) como navegador padrão do sistema.
#
# As políticas vão na extensão org.mozilla.firefox.systemconfig, que o Flatpak
# monta em /app/etc/firefox (um diretório comum em /var/lib/flatpak/extension
# conta como extensão instalada). O arquivo é copiado, não ligado à store: o
# sandbox não enxerga /nix/store. As preferências usam
# Status = "default": viram o valor padrão, e o usuário pode mudá-las em
# about:config sem que o Nix as sobrescreva no próximo início. O idioma vem
# das extensões de locale do próprio Flatpak (segue o idioma do sistema).
#
# O comando `firefox` (atalhos, BROWSER, web apps) é um wrapper para
# `flatpak run org.mozilla.firefox`.
{
  flake.modules.nixos.firefox =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      policies = (pkgs.formats.json { }).generate "policies.json" {
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
      systemconfig = "/var/lib/flatpak/extension/org.mozilla.firefox.systemconfig/${pkgs.stdenv.hostPlatform.parsed.cpu.name}/stable";
    in
    {
      services.flatpak.packages = [ "org.mozilla.firefox" ];

      # Serviço, não activationScript: no boot, a ativação roda antes de o
      # subvolume de /var/lib/flatpak ser montado.
      systemd.services.firefox-flatpak-policies = {
        description = "Install Firefox Flatpak enterprise policies";
        wantedBy = [ "multi-user.target" ];
        unitConfig.RequiresMountsFor = "/var/lib/flatpak";
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        script = ''
          ${pkgs.coreutils}/bin/install -Dm644 ${policies} ${systemconfig}/policies/policies.json
        '';
      };

      environment.systemPackages = [
        (pkgs.writeShellScriptBin "firefox" ''
          exec ${lib.getExe' config.services.flatpak.package "flatpak"} run org.mozilla.firefox "$@"
        '')
      ];

      # Padrão do sistema; cada usuário pode trocar em ~/.config/mimeapps.list.
      xdg.mime.defaultApplications = lib.genAttrs [
        "text/html"
        "x-scheme-handler/http"
        "x-scheme-handler/https"
        "x-scheme-handler/about"
        "x-scheme-handler/unknown"
      ] (_: "org.mozilla.firefox.desktop");
    };
}

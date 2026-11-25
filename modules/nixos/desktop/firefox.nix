# Firefox (Flatpak org.mozilla.firefox) disponível para todos os usuários; o
# padrão é o Brave, salvo my.browser de cada usuário (home/base/xdg.nix).
#
# Políticas do sistema, na extensão org.mozilla.firefox.systemconfig, que o
# Flatpak monta em /app/etc/firefox (um diretório comum em
# /var/lib/flatpak/extension conta como extensão instalada). O arquivo é
# copiado, não ligado à store: o sandbox não enxerga /nix/store.
#  - abas de container ligadas (privacy.userContext.enabled), como padrão
#    (Status = "default": o usuário ainda muda em about:config);
#  - extensões do Bitwarden, Multi-Account Containers e os "<empresa>
#    Container" (Facebook, Google, Microsoft, Twitter, Discord, Amazon e
#    TikTok) instaladas por padrão (o usuário pode desativá-las, não
#    removê-las); as demais vêm da sincronização com a conta Mozilla de cada
#    usuário. O native messaging com o Bitwarden é do próprio Bitwarden em
#    Flatpak (nixos/security/bitwarden.nix). Os containers não são
#    declarados: cada "<empresa> Container" cria o seu, com o nome da
#    empresa, e abre nele os domínios dela. O da Microsoft inclui o GitHub, a
#    menos que se marque "Ignore GitHub" nas opções dele; o do Twitter inclui
#    o x.com. O YouTube Container fica de fora: o do Google já leva o YouTube;
#  - diálogo de arquivos pelo portal (o Luciole; nixos/desktop/file-manager.nix).
#
# O comando do navegador (atalhos, BROWSER) é o exportado pelo Flatpak,
# /var/lib/flatpak/exports/bin/org.mozilla.firefox, no PATH.
{
  flake.modules.nixos.firefox =
    { lib, pkgs, ... }:
    let
      # id da extensão → slug em addons.mozilla.org.
      extensions = {
        "{446900e4-71c2-419f-a6a7-df9c091e268b}" = "bitwarden-password-manager";
        "@testpilot-containers" = "multi-account-containers";
        "@contain-facebook" = "facebook-container";
        "@contain-google" = "google-container";
        "@better-contain-microsoft" = "better-microsoft-container";
        "@contain-twitter" = "twitter-container";
        "@contain-discord" = "discord-container";
        "@contain-amazon" = "amazon-container";
        "@tiktok-container" = "tiktok-container";
      };

      policies = (pkgs.formats.json { }).generate "policies.json" {
        policies = {
          DisableTelemetry = true;
          DontCheckDefaultBrowser = true;
          ExtensionSettings = lib.mapAttrs (_: slug: {
            installation_mode = "normal_installed";
            install_url = "https://addons.mozilla.org/firefox/downloads/latest/${slug}/latest.xpi";
          }) extensions;
          Preferences =
            let
              default = value: {
                Value = value;
                Status = "default";
              };
            in
            {
              "privacy.userContext.enabled" = default true;
              "privacy.userContext.ui.enabled" = default true;
              "widget.use-xdg-desktop-portal.file-picker" = default 1;
            };
        };
      };
      systemconfig = "/var/lib/flatpak/extension/org.mozilla.firefox.systemconfig/${pkgs.stdenv.hostPlatform.parsed.cpu.name}/stable";
    in
    {
      services.flatpak.packages = [ "org.mozilla.firefox" ];

      # Serviço, não activationScript: no boot, a ativação roda antes de
      # /var/lib/flatpak (preservation) ser montado.
      systemd.services.firefox-flatpak-policies = {
        description = "Políticas do Firefox em Flatpak (org.mozilla.firefox.systemconfig)";
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
    };
}

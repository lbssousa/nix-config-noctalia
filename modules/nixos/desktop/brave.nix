# Brave (Flatpak com.brave.Browser) como segundo navegador de todos os
# usuários; o padrão é o Firefox (desktop/firefox.nix).
#
# Políticas em /etc/brave/policies/managed: o brave.sh do Flatpak liga os
# .json de /run/host/etc/brave/policies (permissão host-etc) no /etc do
# sandbox. Por isso são cópias (mode), e não symlinks para o /nix/store, que o
# sandbox não enxerga:
#  - extensão do Bitwarden instalada por padrão (o usuário pode desativá-la,
#    não removê-la); o native messaging com o app vem de
#    home/desktop/brave.nix. As demais extensões vêm da sincronização de
#    cada usuário;
#  - sem o resolvedor DNS próprio (fica o systemd-resolved) e sem o aviso de
#    navegador padrão.
#
# Cores da Noctalia: o template "chromium-based" da comunidade grava
# BrowserThemeColor em noctalia-color.json, que vale para a máquina inteira;
# um só usuário (my.brave.themeOwner) é o dono do arquivo e a cor é a da
# paleta dele (home/desktop/brave.nix).
#
# Sem PWAs forçadas: os web apps são Taskbar Tabs do Firefox. As PWAs que o
# usuário instalar no Brave têm os .desktop corrigidos por
# home/desktop/brave-pwa-fix.nix.
{ config, ... }:
let
  flakeUsers = config.my.users;
in
{
  flake.modules.nixos.brave =
    { config, lib, ... }:
    let
      cfg = config.my.brave;
      bitwarden = "nngceckbapebfimnlniiiahkandclblb";
      # O primeiro administrador por uid.
      firstAdmin =
        let
          admins = lib.sort (a: b: a.uid < b.uid) (
            lib.mapAttrsToList (name: u: u // { inherit name; }) (lib.filterAttrs (_: u: u.sudo) flakeUsers)
          );
        in
        if admins == [ ] then null else (lib.head admins).name;
      policyDir = "brave/policies/managed";
    in
    {
      options.my.brave.themeOwner = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = firstAdmin;
        defaultText = lib.literalMD "o primeiro usuário com `sudo = true`, por uid";
        description = ''
          Usuário cuja paleta da Noctalia colore o Brave de todos
          (BrowserThemeColor); null desliga.
        '';
      };

      config = {
        services.flatpak.packages = [ "com.brave.Browser" ];
        # Socket IPC e desktop_proxy do Bitwarden em Flatpak, abertos no
        # diretório do Chrome em Flatpak (home/desktop/brave.nix).
        services.flatpak.overrides.settings."com.brave.Browser".Context.filesystems = [
          "~/.var/app/com.google.Chrome/config/google-chrome/NativeMessagingHosts"
        ];

        environment.etc."${policyDir}/nix.json" = {
          mode = "0644";
          text = builtins.toJSON {
            BuiltInDnsClientEnabled = false;
            DefaultBrowserSettingEnabled = false;
            ExtensionSettings.${bitwarden} = {
              installation_mode = "normal_installed";
              update_url = "https://clients2.google.com/service/update2/crx";
            };
          };
        };

        # Gravável pelo dono da paleta; "f" (sem "+") preserva a cor entre
        # rebuilds, e a Noctalia a regrava ao iniciar.
        systemd.tmpfiles.settings."10-noctalia-brave" = lib.mkIf (cfg.themeOwner != null) {
          "/etc/${policyDir}/noctalia-color.json".f = {
            user = cfg.themeOwner;
            group = cfg.themeOwner;
            mode = "0644";
            argument = "{}";
          };
        };
      };
    };
}

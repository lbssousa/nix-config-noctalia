# Firefox (Flatpak org.mozilla.firefox, nixos/desktop/firefox.nix) de cada
# usuário: um perfil fixo ("default") e os web apps como Taskbar Tabs
# (my.firefox.webapps), cada um no container que a extensão da empresa cria.
#
# O perfil fica onde o Flatpak o procura (~/.var/app/org.mozilla.firefox/
# .mozilla/firefox); o caminho é o mesmo dentro e fora do sandbox, então o
# `-profile` dos lançadores vale nos dois lados.
#
# O Firefox não tem CLI nem política para criar Taskbar Tabs; o
# firefox-webapps grava o que o "Adicionar aba à barra de tarefas" grava: a
# entrada no taskbartabs/taskbartabs.json do perfil, com um id fixo por web
# app, e o lançador em ~/.local/share/applications. O nome do lançador
# (firefox.webapp-<id>.desktop) é também a classe da janela do web app.
# O registro só é gravado com o Firefox fechado (`flatpak ps`): na ativação
# (no boot, antes do login) e no login.
# `webapp <id>` abre o web app, para os atalhos de teclado.
#
# Override local: web apps criados no próprio Firefox ficam; os declarados
# voltam a ter a URL e o container daqui.
{
  flake.modules.homeManager.firefox =
    {
      config,
      lib,
      osConfig,
      pkgs,
      ...
    }:
    let
      cfg = osConfig.my.firefox;
      profile = "default";
      appId = "org.mozilla.firefox";

      settings = pkgs.writeText "firefox-webapps.json" (
        builtins.toJSON {
          inherit appId;
          # Os do sistema, e não caminhos no /nix/store: os lançadores
          # sobrevivem a atualizações e ao GC sem precisar ser reescritos.
          firefox = "/var/lib/flatpak/exports/bin/${appId}";
          flatpak = "/run/current-system/sw/bin/flatpak";
          profileDir = "${config.home.homeDirectory}/${config.programs.firefox.configPath}/${profile}";
          inherit (cfg) webapps;
        }
      );

      firefox-webapps = pkgs.writers.writePython3Bin "firefox-webapps" {
        flakeIgnore = [ "E501" ];
        libraries = [ pkgs.python3Packages.pillow ];
        makeWrapperArgs = [
          "--set"
          "FIREFOX_WEBAPPS_CONFIG"
          "${settings}"
        ];
      } (builtins.readFile ../../packages/_firefox-webapps/firefox-webapps.py);

      webapp = pkgs.writeShellScriptBin "webapp" ''
        if [ -z "$1" ]; then
          echo "Uso: webapp <id>   (ids: ${lib.concatStringsSep " " (lib.attrNames cfg.webapps)})" >&2
          exit 1
        fi
        exec ${lib.getExe firefox-webapps} launch "$@"
      '';
      nativeProfile = "${config.home.homeDirectory}/.mozilla/firefox/${profile}";
      flatpakProfile = "${config.home.homeDirectory}/${config.programs.firefox.configPath}/${profile}";
    in
    {
      options.my.firefox.migrateNativeProfile = lib.mkEnableOption ''
        cópia única do perfil do Firefox nativo (~/.mozilla/firefox/default:
        extensões instaladas, favoritos, logins, containers) para o perfil do
        Flatpak, enquanto o Firefox em Flatpak ainda não tiver aberto o dele.
        O perfil nativo fica onde está'';

      config = {
        home = {
          packages = [
            firefox-webapps
            webapp
          ];

          activation = {
            # Antes do firefox-webapps, que grava as Taskbar Tabs no perfil. Só
            # copia se o Flatpak ainda não usou o perfil (sem prefs.js) e nunca
            # sobrescreve: o user.js e o profiles.ini do home-manager ficam. Sem
            # os arquivos de trava e sem o compatibility.ini (caminhos do Firefox
            # nativo): o Firefox do Flatpak revalida as extensões no primeiro início.
            firefoxMigrateNativeProfile = lib.mkIf config.my.firefox.migrateNativeProfile (
              lib.hm.dag.entryBetween [ "firefoxWebapps" ] [ "writeBoundary" ] ''
                old=${lib.escapeShellArg nativeProfile}
                new=${lib.escapeShellArg flatpakProfile}
                if [[ -f $old/prefs.js && ! -e $new/prefs.js ]]; then
                  run mkdir -p "$new"
                  run cp -a --reflink=auto --no-clobber "$old/." "$new/"
                  run rm -f "$new/lock" "$new/.parentlock" "$new/parent.lock" "$new/compatibility.ini"
                  noteEcho "Perfil do Firefox nativo copiado para o Flatpak ($new)."
                fi
              ''
            );

            # Na ativação (no boot, antes do login, o Firefox está fechado).
            firefoxWebapps = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
              run ${lib.getExe firefox-webapps} apply || warnEcho "firefox-webapps apply falhou."
            '';
          };
        };

        programs.firefox = {
          enable = true;
          # O Firefox é o Flatpak do sistema; aqui só o perfil.
          package = null;
          configPath = ".var/app/${appId}/.mozilla/firefox";
          profiles.${profile} = {
            id = 0;
            isDefault = true;
            # Taskbar Tabs (web apps em janela própria): desligadas no Linux, e a
            # preferência não é aceita nas políticas nem há autoconfig do sistema
            # no Flatpak; o user.js a liga a cada início.
            settings."browser.taskbarTabs.enabled" = true;
          };
        };

        # No login: o mesmo, mais os ícones (que precisam de rede).
        systemd.user.services.firefox-webapps = {
          Unit.Description = "Taskbar Tabs do Firefox";
          Service = {
            Type = "oneshot";
            ExecStart = "${lib.getExe firefox-webapps} sync";
          };
          Install.WantedBy = [ "default.target" ];
        };
      };
    };
}

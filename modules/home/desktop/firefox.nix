# Firefox de cada usuário: um perfil fixo ("default") e os web apps como
# Taskbar Tabs (my.firefox.webapps, declarados no módulo NixOS
# desktop/firefox.nix), cada um no container que a extensão da empresa cria.
#
# O Firefox não tem CLI nem política para criar Taskbar Tabs; o
# firefox-webapps grava o que o "Adicionar aba à barra de tarefas" grava: a
# entrada no taskbartabs/taskbartabs.json do perfil, com um id fixo por web
# app, e o lançador em ~/.local/share/applications. O nome do lançador
# (firefox.webapp-<id>.desktop) é também a classe da janela do web app.
# O registro só é gravado com o Firefox fechado: na ativação (no boot, antes
# do login) e no login.
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

      settings = pkgs.writeText "firefox-webapps.json" (
        builtins.toJSON {
          # O do sistema, e não um caminho no /nix/store: os lançadores
          # sobrevivem a atualizações e ao GC sem precisar ser reescritos.
          firefox = "/run/current-system/sw/bin/firefox";
          profileDir = "${config.home.homeDirectory}/${config.programs.firefox.configPath}/${profile}";
          inherit (cfg) webapps;
        }
      );

      firefox-webapps = pkgs.writers.writePython3Bin "firefox-webapps" {
        flakeIgnore = [ "E501" ];
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
    in
    {
      home.packages = [
        firefox-webapps
        webapp
      ];

      programs.firefox = {
        enable = true;
        # O pacote (com as políticas) é o do sistema: nixos/desktop/firefox.nix.
        package = null;
        profiles.${profile} = {
          id = 0;
          isDefault = true;
        };
      };

      # Na ativação (no boot, antes do login, o Firefox está fechado).
      home.activation.firefoxWebapps = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        run ${lib.getExe firefox-webapps} apply || warnEcho "firefox-webapps apply falhou."
      '';

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
}

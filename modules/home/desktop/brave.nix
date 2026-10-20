# brave-origin de cada usuário: native messaging do KeePassXC, containers
# (my.brave.containers) e os web apps (my.brave.webapps), as duas listas
# declaradas no módulo NixOS desktop/brave.nix.
#
# As PWAs são instaladas pela política do sistema; o id de cada uma só existe
# depois da instalação (o Brave o deriva do manifesto do site). O serviço
# brave-webapps-sync acha cada web app pela URL de início, no registro de PWAs
# do perfil, e põe --container=<nome> nos lançadores que o Brave cria em
# ~/.local/share/applications (refeito sempre que o Brave os reescreve).
# `webapp <id>` abre o web app no container, para os atalhos de teclado.
#
# Override local: containers e PWAs podem ser mudados no próprio Brave; os
# containers declarados só voltam a ter o ícone e a cor daqui.
{
  flake.modules.homeManager.brave =
    {
      config,
      lib,
      osConfig,
      pkgs,
      ...
    }:
    let
      cfg = osConfig.my.brave;
      browser = lib.getExe cfg.package;

      settings = pkgs.writeText "brave-webapps.json" (
        builtins.toJSON {
          inherit browser;
          inherit (cfg) containers webapps;
        }
      );

      brave-webapps = pkgs.writers.writePython3Bin "brave-webapps" {
        libraries = [ pkgs.python3Packages.plyvel ];
        flakeIgnore = [ "E501" ];
        makeWrapperArgs = [
          "--set"
          "BRAVE_WEBAPPS_CONFIG"
          "${settings}"
        ];
      } (builtins.readFile ../../packages/_brave-webapps/brave-webapps.py);

      webapp = pkgs.writeShellScriptBin "webapp" ''
        if [ -z "$1" ]; then
          echo "Uso: webapp <id>   (ids: ${lib.concatStringsSep " " (lib.attrNames cfg.webapps)})" >&2
          exit 1
        fi
        exec ${lib.getExe brave-webapps} launch "$@"
      '';
    in
    {
      home.packages = [
        brave-webapps
        webapp
      ];

      # Extensão do KeePassXC (instalada pela política) ↔ keepassxc-proxy.
      xdg.configFile."BraveSoftware/Brave-Origin/NativeMessagingHosts/org.keepassxc.keepassxc_browser.json" =
        lib.mkIf config.programs.keepassxc.enable {
          text = builtins.toJSON {
            name = "org.keepassxc.keepassxc_browser";
            description = "KeePassXC integration with native messaging support";
            path = "${config.programs.keepassxc.package}/bin/keepassxc-proxy";
            type = "stdio";
            allowed_origins = [
              "chrome-extension://oboonakemofpalcgghocfoadofidjkkk/"
              "chrome-extension://pdffhmdngciaglkoonimfcmckehcpafo/"
            ];
          };
        };

      # Na ativação (no boot, antes do login, o Brave está fechado).
      home.activation.braveContainers = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        run ${lib.getExe brave-webapps} containers || warnEcho "brave-webapps containers falhou."
      '';

      systemd.user = {
        services.brave-webapps-sync = {
          Unit.Description = "Containers nos lançadores das PWAs do brave-origin";
          Service = {
            Type = "oneshot";
            ExecStart = "${lib.getExe brave-webapps} sync";
          };
          Install.WantedBy = [ "default.target" ];
        };
        # O Brave cria/reescreve os lançadores ao instalar ou atualizar uma PWA.
        paths.brave-webapps-sync = {
          Unit.Description = "Lançadores de PWAs do brave-origin";
          Path = {
            PathChanged = "${config.xdg.dataHome}/applications";
            MakeDirectory = true;
          };
          Install.WantedBy = [ "default.target" ];
        };
      };
    };
}

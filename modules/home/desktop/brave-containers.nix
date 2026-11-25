# Containers e Traffic Control do Brave (Flatpak com.brave.Browser) de cada
# usuário com my.braveContainers.enable (por ora, só o abutre).
#
# O Firefox usa extensões para criar um container por fabricante e redirecionar
# os domínios dele. O Brave tem Containers + Traffic Control nativos, mas só na
# interface. Este módulo grava no perfil exatamente o que a interface gravaria:
# a lista de containers, as regras de domínio e a flag do Traffic Control
# (desligada por padrão no Brave). As listas vêm de osConfig.my.brave.containers;
# a decisão de aplicá-las é por usuário, não global.
#
# Escrita só com o Brave fechado (flatpak ps), na ativação (antes do login) e no
# login, como o firefox-webapps. Containers e regras declarados têm prioridade;
# os criados pelo usuário no navegador ficam, desde que não choquem (mesmo id).
# Mudanças feitas na interface do Brave voltam ao declarado no próximo login.
{
  flake.modules.homeManager.brave-containers =
    {
      config,
      lib,
      osConfig,
      pkgs,
      ...
    }:
    let
      cfg = config.my.braveContainers;
      appId = "com.brave.Browser";
      profileDir = "${config.home.homeDirectory}/.var/app/${appId}/config/BraveSoftware/Brave-Browser";

      settings = pkgs.writeText "brave-containers.json" (
        builtins.toJSON {
          inherit appId profileDir;
          flatpak = "/run/current-system/sw/bin/flatpak";
          profile = "Default";
          containers = osConfig.my.brave.containers;
        }
      );

      brave-containers = pkgs.writers.writePython3Bin "brave-containers" {
        flakeIgnore = [ "E501" ];
        makeWrapperArgs = [
          "--set"
          "BRAVE_CONTAINERS_CONFIG"
          "${settings}"
        ];
      } (builtins.readFile ../../packages/_brave-containers/brave-containers.py);
    in
    {
      options.my.braveContainers.enable = lib.mkEnableOption "Containers e Traffic Control do Brave neste perfil";

      config = lib.mkIf cfg.enable {
        home.packages = [ brave-containers ];

        home.activation.braveContainers = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          run ${lib.getExe brave-containers} || warnEcho "brave-containers: não foi possível aplicar as preferências."
        '';

        # No login, depois da ativação (que roda no boot, antes do login) e
        # antes de o usuário abrir o Brave pela dock.
        systemd.user.services.brave-containers = {
          Unit.Description = "Containers e Traffic Control do Brave";
          Service = {
            Type = "oneshot";
            ExecStart = lib.getExe brave-containers;
          };
          Install.WantedBy = [ "default.target" ];
        };
      };
    };
}

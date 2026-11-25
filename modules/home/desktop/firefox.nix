# Firefox (Flatpak org.mozilla.firefox, nixos/desktop/firefox.nix) de cada
# usuário: um perfil fixo ("default"), os web apps como Taskbar Tabs
# (my.firefox.webapps), cada um no container que a extensão da empresa cria, e
# as cores da Noctalia via Pywalfox.
#
# O perfil fica onde o Flatpak o procura (~/.var/app/org.mozilla.firefox/
# .mozilla/firefox); o caminho é o mesmo dentro e fora do sandbox, então o
# `-profile` dos lançadores vale nos dois lados.
#
# Cores da Noctalia (Pywalfox): o template "pywalfox" da comunidade grava
# ~/.cache/wal/colors.json e roda a post_action "firefox-theme" da Noctalia.
# Como o Firefox em Flatpak não enxerga /nix/store nem pode executar o binário
# da Noctalia direto do host, um socket systemd de usuário
# (%t/noctalia-firefox-theme/host.sock, exposto sozinho ao sandbox) ativa
# `noctalia firefox-theme host` sob demanda; o manifesto pywalfox.json e o
# script-ponte (Python do runtime do Flatpak) vão copiados em
# ~/.var/app/org.mozilla.firefox/.mozilla/native-messaging-hosts, sem abrir o
# sandbox com org.freedesktop.Flatpak.
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
{ inputs, ... }:
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
      nativeMessagingHosts = "${config.home.homeDirectory}/.var/app/${appId}/.mozilla/native-messaging-hosts";

      # Ponte executada dentro do sandbox do Flatpak (usa o /usr/bin/python3 do
      # runtime org.freedesktop.Platform, sem depender do /nix/store): repassa
      # stdin/stdout do native messaging ao socket ativado pelo systemd no host.
      pywalfoxBridge = pkgs.writeText "noctalia-pywalfox-bridge" ''
        #!/usr/bin/python3
        import os
        import selectors
        import socket
        import sys


        def write_all(fd, data):
            view = memoryview(data)
            while view:
                written = os.write(fd, view)
                if written <= 0:
                    raise BrokenPipeError
                view = view[written:]


        def main():
            sock_path = os.path.join(
                os.environ["XDG_RUNTIME_DIR"], "noctalia-firefox-theme", "host.sock"
            )
            sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            sock.connect(sock_path)

            stdin_fd = sys.stdin.fileno()
            stdout_fd = sys.stdout.fileno()
            sel = selectors.DefaultSelector()
            sel.register(stdin_fd, selectors.EVENT_READ, "stdin")
            sel.register(sock, selectors.EVENT_READ, "sock")

            try:
                while True:
                    for key, _ in sel.select():
                        if key.data == "stdin":
                            chunk = os.read(stdin_fd, 65536)
                            if not chunk:
                                return
                            sock.sendall(chunk)
                        else:
                            chunk = sock.recv(65536)
                            if not chunk:
                                return
                            write_all(stdout_fd, chunk)
            except (BrokenPipeError, ConnectionResetError, OSError):
                pass
            finally:
                sel.close()
                sock.close()


        if __name__ == "__main__":
            main()
      '';

      pywalfoxManifest = pkgs.writeText "pywalfox.json" (
        builtins.toJSON {
          name = "pywalfox";
          description = "Noctalia Firefox theme native messaging host (Flatpak bridge)";
          path = "${nativeMessagingHosts}/.noctalia-pywalfox-bridge";
          type = "stdio";
          allowed_extensions = [ "pywalfox@frewacom.org" ];
        }
      );

      # Arquivos do perfil que o programs.firefox gera. Symlinks para o
      # /nix/store não resolvem no sandbox do Flatpak (a store não é montada):
      # o Firefox não via o profiles.ini nem o user.js. Vão como cópias.
      profileFiles = map (f: "${config.programs.firefox.configPath}/${f}") [
        "profiles.ini"
        "${profile}/user.js"
      ];
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

            # Cópias, e não symlinks, dos arquivos do perfil (profileFiles) e
            # do native messaging do Pywalfox. Depois do linkGeneration, que
            # apaga os symlinks de gerações antigas; reescritas a cada ativação.
            firefoxProfileFiles = lib.hm.dag.entryAfter [ "linkGeneration" ] (
              ''
                run mkdir -p ${lib.escapeShellArg flatpakProfile} ${lib.escapeShellArg nativeMessagingHosts}
              ''
              + lib.concatMapStrings (f: ''
                run rm -f ${lib.escapeShellArg "${config.home.homeDirectory}/${f}"}
                run install -m 0644 ${config.home.file.${f}.source} ${lib.escapeShellArg "${config.home.homeDirectory}/${f}"}
              '') profileFiles
              + ''
                run rm -f ${lib.escapeShellArg "${nativeMessagingHosts}/.noctalia-pywalfox-bridge"} \
                  ${lib.escapeShellArg "${nativeMessagingHosts}/pywalfox.json"}
                run install -m 0755 ${pywalfoxBridge} ${lib.escapeShellArg "${nativeMessagingHosts}/.noctalia-pywalfox-bridge"}
                run install -m 0644 ${pywalfoxManifest} ${lib.escapeShellArg "${nativeMessagingHosts}/pywalfox.json"}
              ''
            );

            # Na ativação (no boot, antes do login, o Firefox está fechado).
            firefoxWebapps = lib.hm.dag.entryAfter [ "writeBoundary" "firefoxProfileFiles" ] ''
              run ${lib.getExe firefox-webapps} apply || warnEcho "firefox-webapps apply falhou."
            '';
          };
        };

        programs = {
          firefox = {
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

          # Cores da Noctalia ao vivo no Firefox (Pywalfox): gera colors.json e
          # aciona o host nativo embutido na Noctalia (`firefox-theme`).
          noctalia.settings.theme.templates.user.pywalfox = {
            input_path = "${inputs.noctalia-templates-community}/pywalfox/pywalfox.json";
            output_path = "${config.xdg.cacheHome}/wal/colors.json";
            pre_hook = "mkdir -p '${config.xdg.cacheHome}/wal'";
            post_action = "firefox-theme";
          };
        };

        home.file = lib.genAttrs profileFiles (_: {
          enable = false;
        });

        # O profiles.ini é reescrito a cada ativação (firefoxProfileFiles).
        # Sem MOZ_LEGACY_PROFILES, o Firefox quer um perfil dedicado à
        # instalação ([Install<hash>]) e cria um *.default-release em vez de
        # usar o "default" daqui. Com a variável, usa o perfil Default=1 e não
        # reescreve o arquivo. Override do Flatpak no nível do usuário (lido
        # pelo flatpak no host, então o symlink serve), junto do perfil.
        xdg.dataFile."flatpak/overrides/${appId}".text = lib.generators.toINI { } {
          Environment.MOZ_LEGACY_PROFILES = "1";
        };

        systemd.user = {
          # Ponte de socket para o Firefox em Flatpak falar com
          # `noctalia firefox-theme host` no host sem sair do sandbox.
          sockets.noctalia-firefox-theme = {
            Unit.Description = "Ponte de native messaging do tema da Noctalia para o Firefox em Flatpak";
            Socket = {
              ListenStream = "%t/noctalia-firefox-theme/host.sock";
              DirectoryMode = "0700";
              SocketMode = "0600";
              Accept = true;
            };
            Install.WantedBy = [ "sockets.target" ];
          };

          services = {
            "noctalia-firefox-theme@" = {
              Unit.Description = "Host de native messaging do tema da Noctalia para o Firefox em Flatpak";
              Service = {
                ExecStart = "${lib.getExe pkgs.noctalia} firefox-theme host";
                StandardInput = "socket";
                StandardOutput = "socket";
                StandardError = "journal";
              };
            };

            # No login: o mesmo, mais os ícones (que precisam de rede).
            firefox-webapps = {
              Unit.Description = "Taskbar Tabs do Firefox";
              Service = {
                Type = "oneshot";
                ExecStart = "${lib.getExe firefox-webapps} sync";
              };
              Install.WantedBy = [ "default.target" ];
            };
          };
        };
      };
    };
}

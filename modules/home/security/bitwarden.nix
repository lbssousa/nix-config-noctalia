# Bitwarden de cada usuário com my.bitwarden.enable (por ora, só o abutre):
# agente SSH, autostart na bandeja e preferências do app. O app e o `bw` são
# do sistema (nixos/security/bitwarden.nix).
#
# Agente SSH: o app escuta em ~/.bitwarden-ssh-agent.sock. O SSH_AUTH_SOCK é
# exportado nos shells (home.sessionVariables) e no environment.d do
# systemd --user (systemd.user.sessionVariables, 10-home-manager.conf): o
# Umbriel, a Noctalia, os terminais e tudo o que eles abrem já o herdam, mesmo
# antes de o Bitwarden subir. Com o cofre travado, o próprio app pede o
# desbloqueio quando o ssh pede uma chave.
#
# Preferências: o app guarda tudo (inclusive o cofre criptografado) em
# ~/.config/Bitwarden/data.json, que ele reescreve inteiro enquanto roda. As
# opções my.bitwarden.settings (globais) e my.bitwarden.userSettings (de cada
# conta logada) entram por cima do arquivo, no formato do app
# (global_<estado>_<chave> e user_<id>_<estado>_<chave>), antes de cada
# autostart e no switch, se o app não estiver aberto. Uma conta nova recebe as
# preferências dela no início seguinte do app. O que não estiver nas opções
# continua como o usuário deixou na interface.
#
# Autostart: entrada própria (com.bitwarden.desktop.desktop, Exec com
# --autostart, que abre direto na bandeja). O "Iniciar com o sistema" do app
# fica desligado (openAtLogin), senão ele gravaria o seu bitwarden.desktop.
# Um drop-in na unidade gerada pelo systemd
# (app-com.bitwarden.desktop@autostart.service) segura o início até o
# Noctalia registrar a bandeja (StatusNotifierHost) e o xdg-desktop-portal
# responder: o Electron só consulta os dois ao iniciar.
{
  flake.modules.homeManager.bitwarden =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.my.bitwarden;
      sock = "${config.home.homeDirectory}/.bitwarden-ssh-agent.sock";
      dataFile = "${config.xdg.configHome}/Bitwarden/data.json";

      # { estado.chave = valor; } → { "<prefixo><estado>_<chave>" = valor; }
      flatten =
        prefix:
        lib.concatMapAttrs (
          state: keys: lib.mapAttrs' (key: lib.nameValuePair "${prefix}${state}_${key}") keys
        );

      settingsJson = pkgs.writeText "bitwarden-settings.json" (
        builtins.toJSON (flatten "global_" cfg.settings)
      );
      userSettingsJson = pkgs.writeText "bitwarden-user-settings.json" (
        builtins.toJSON (flatten "" cfg.userSettings)
      );

      # Sem o data.json (primeira execução), cria um só com as preferências: o
      # app trata o arquivo sem stateVersion como estado vazio e mantém o que
      # já estiver nele.
      applySettings = pkgs.writeShellApplication {
        name = "bitwarden-apply-settings";
        runtimeInputs = [
          pkgs.coreutils
          pkgs.jq
          pkgs.procps
        ];
        text = ''
          data=${lib.escapeShellArg dataFile}

          if pgrep -u "$(id -u)" -f '/opt/Bitwarden/resources/app\.asar' >/dev/null; then
            echo "Bitwarden aberto: as preferências do Nix entram no próximo início dele." >&2
            exit 0
          fi

          mkdir -p "$(dirname "$data")"
          [[ -s $data ]] || echo '{}' >"$data"

          tmp=$(mktemp "$data.XXXXXX")
          trap 'rm -f "$tmp"' EXIT
          jq --slurpfile global ${settingsJson} --slurpfile user ${userSettingsJson} '
            . + $global[0]
            | reduce ((.global_account_accounts // {}) | keys[]) as $id (.;
                . + ($user[0] | with_entries(.key = "user_\($id)_\(.key)")))
          ' "$data" >"$tmp"
          chmod 600 "$tmp"
          mv "$tmp" "$data"
        '';
      };

      # ExecStartPre= do autostart: espera a bandeja e o portal (até o
      # timeout) e depois libera o início de qualquer jeito.
      autostartWait = pkgs.writeShellApplication {
        name = "bitwarden-autostart-wait";
        runtimeInputs = [
          pkgs.coreutils
          pkgs.systemd
        ];
        text = ''
          timeout=''${BITWARDEN_AUTOSTART_TIMEOUT:-60}

          for ((i = 0; i < timeout; i++)); do
            tray=$(busctl --user get-property \
              org.kde.StatusNotifierWatcher /StatusNotifierWatcher \
              org.kde.StatusNotifierWatcher IsStatusNotifierHostRegistered 2>/dev/null || true)

            if [[ $tray == *" true"* ]] &&
              busctl --user --timeout=2 call \
                org.freedesktop.portal.Desktop /org/freedesktop/portal/desktop \
                org.freedesktop.portal.Settings ReadOne ss \
                org.freedesktop.appearance color-scheme &>/dev/null; then
              exit 0
            fi

            sleep 1
          done

          echo "Bandeja ou portal ausentes após ''${timeout}s; iniciando o Bitwarden assim mesmo" >&2
        '';
      };

      autostartEntry = pkgs.makeDesktopItem {
        name = "com.bitwarden.desktop";
        desktopName = "Bitwarden";
        exec = "bitwarden --autostart";
        icon = "bitwarden";
        noDisplay = true;
      };

      settingsType = lib.types.attrsOf (lib.types.attrsOf lib.types.anything);
    in
    {
      options.my.bitwarden = {
        enable = lib.mkEnableOption "Bitwarden (agente SSH, autostart e preferências do app)";

        autostart = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Inicia o Bitwarden com a sessão, direto na bandeja.";
        };

        settings = lib.mkOption {
          type = settingsType;
          description = ''
            Preferências globais do app (global_<estado>_<chave> no data.json),
            como { <estado>.<chave> = valor; }.
          '';
          default = { };
        };

        userSettings = lib.mkOption {
          type = settingsType;
          description = ''
            Preferências de cada conta logada no app (user_<id>_<estado>_<chave>
            no data.json), como { <estado>.<chave> = valor; }.
          '';
          default = { };
        };
      };

      config = lib.mkIf cfg.enable {
        my.bitwarden = {
          settings = {
            desktopSettings = {
              # Configurações → "Ativar agente SSH".
              sshAgentEnabled = lib.mkDefault true;
              # Fechar e minimizar levam à bandeja.
              runInBackground = lib.mkDefault true;
              # O autostart é o deste módulo.
              openAtLogin = false;
            };
            # Botões de cópia rápida na lista de itens.
            vaultAppearance.copyButtons = lib.mkDefault "quick";
          };

          userSettings = {
            # Travar (e não sair) só ao reiniciar o app.
            vaultTimeoutSettings = {
              vaultTimeout = lib.mkDefault "onRestart";
              vaultTimeoutAction = lib.mkDefault "lock";
            };
            # Desbloqueio pelo polkit, depois do primeiro com a senha mestra
            # (no Linux a chave só fica na memória do app); sem pedir sozinho
            # ao abrir.
            biometricSettings = {
              biometricUnlockEnabled = lib.mkDefault true;
              promptAutomatically = lib.mkDefault false;
            };
            # Cada chave SSH é autorizada uma vez até o cofre travar.
            desktopSettings.sshAgentRememberAuthorizations = lib.mkDefault "rememberUntilLock";
            sharedUnlockSettings = {
              allowSharingUnlockStateWithDesktop = lib.mkDefault false;
              allowSharingUnlockStateWithWeb = lib.mkDefault true;
            };
          };
        };

        home = {
          packages = [ applySettings ];
          sessionVariables.SSH_AUTH_SOCK = sock;

          activation = {
            bitwardenSettings = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
              run ${lib.getExe applySettings}
            '';

            # Restos do Bitwarden de antes: a entrada que o próprio app gravava
            # e a cópia .bkp do home-manager, que o systemd também executava.
            removeBitwardenAppAutostart = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
              run rm -f "${config.xdg.configHome}/autostart/bitwarden.desktop" \
                "${config.xdg.configHome}/autostart/bitwarden.desktop.bkp"
            '';
          };
        };

        systemd.user.sessionVariables.SSH_AUTH_SOCK = sock;

        xdg = lib.mkIf cfg.autostart {
          configFile."systemd/user/app-com.bitwarden.desktop@autostart.service.d/50-wait-for-desktop.conf".text =
            ''
              [Service]
              ExecStartPre=${lib.getExe autostartWait}
              ExecStartPre=${lib.getExe applySettings}
              TimeoutStartSec=90
            '';

          autostart = {
            enable = true;
            entries = [ "${autostartEntry}/share/applications/com.bitwarden.desktop.desktop" ];
          };
        };
      };
    };
}

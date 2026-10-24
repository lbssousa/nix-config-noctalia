# Usuário abutre (administrador).
{ inputs, ... }:
{
  my.users.abutre = {
    uid = 1000;
    sudo = true;

    home =
      {
        config,
        lib,
        pkgs,
        ...
      }:
      let
        personalAgeKey = "${config.xdg.configHome}/sops/age/keys.txt";
      in
      {
        my = {
          # Assinatura de commits com a chave OpenPGP da YubiKey.
          yubikeyGpg.enable = true;
          # Neovim completo (nixvim com LSPs).
          nixvim.enable = true;
          # Zathura como leitor de PDF padrão (Papers para os demais).
          pdfViewer = "org.pwmt.zathura.desktop";
          # Strata como gerenciador de arquivos (Nautilus para os demais).
          fileManager = "strata";
          # Bitwarden: agente SSH, autostart na bandeja e preferências do app
          # (desligado para os demais usuários, por ora).
          bitwarden.enable = true;

          # Provedores do ai-usagebar (plugin AI Usage da Noctalia): Claude Code
          # (OAuth de ~/.claude/.credentials.json) e Antigravity (`agy`). Os
          # que vêm ligados por padrão (Codex, Z.AI, OpenRouter) ficam
          # desligados para não aparecerem com erro. Ajustes locais vão em
          # ~/.config/ai-usagebar/config.toml.local.
          mutableConfigs."ai-usagebar/config.toml".base = {
            ui.overview_vendors = [
              "anthropic"
              "antigravity"
            ];
            anthropic.enabled = true;
            antigravity.enabled = true;
            openai.enabled = false;
            zai.enabled = false;
            openrouter.enabled = false;
          };
        };

        programs = {
          # Status do NixOS na barra (plugin nix-status) a partir deste flake.
          noctalia.settings.plugin_settings."mindnbytes/nix-status".flake_dir =
            "${config.xdg.userDirs.extraConfig.PROJECTS}/lbssousa/nix-config-noctalia";
          git = {
            signing = {
              key = "BAC0B1B569777A733E37447FB10712C404063D38";
              signByDefault = true;
            };
            settings = {
              user.name = inputs.nix-secrets.abutre.gitName;
              user.email = inputs.nix-secrets.abutre.gitEmail;
              safe.directory = [ "/etc/nixos" ];
            };
          };
        };

        # Chave age pessoal (sops-nix do HM). Na instalação pelo Bitwarden, o
        # install.sh já a grava; com o nix-keys (git-crypt, desbloqueado com a
        # chave GPG da YubiKey), esta ativação a copia de lá. Sem ela, os
        # segredos do HM simplesmente não são instalados até o próximo switch.
        sops.age.keyFile = personalAgeKey;

        # Dropbox (cliente gráfico, ícone na bandeja) junto com a sessão. Se o
        # "Iniciar o Dropbox com o sistema" dele também estiver ligado, a
        # segunda instância só vê que já há uma rodando e sai.
        systemd.user.services.dropbox = {
          Unit = {
            Description = "Dropbox";
            After = [ "graphical-session.target" ];
            PartOf = [ "graphical-session.target" ];
          };
          Service = {
            ExecStart = lib.getExe pkgs.dropbox;
            Restart = "on-failure";
            KillMode = "control-group";
          };
          Install.WantedBy = [ "graphical-session.target" ];
        };

        home = {
          packages = with pkgs; [
            gcc
            python3
            rustup
            pandoc
            github-copilot-cli
            antigravity-ide
            dropbox
          ];
          sessionPath = [ "${config.home.homeDirectory}/.cargo/bin" ];

          activation.installPersonalSopsAgeKey = lib.hm.dag.entryBefore [ "reloadSystemd" ] ''
            src="$(${pkgs.xdg-user-dirs}/bin/xdg-user-dir PROJECTS)/lbssousa/nix-keys/sops/age/abutre/keys.txt"
            if [ -f "$src" ] && ${pkgs.gnugrep}/bin/grep -q '^AGE-SECRET-KEY-' "$src"; then
              run ${pkgs.coreutils}/bin/install -Dm600 "$src" ${lib.escapeShellArg personalAgeKey}
            elif [ ! -f ${lib.escapeShellArg personalAgeKey} ]; then
              warnEcho "Chave age pessoal ausente: copie AGE_KEY_ABUTRE do Bitwarden (secretspec get AGE_KEY_ABUTRE -P install) ou clone e desbloqueie o nix-keys, e rode o switch de novo."
            fi
          '';
        };
      };
  };
}

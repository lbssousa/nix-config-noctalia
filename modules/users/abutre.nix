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
        };

        programs = {
          # Status do NixOS na barra (plugin nix-status) a partir do clone de
          # trabalho, não do espelho /etc/nixos: o plugin roda `nix flake
          # update` no diretório, e o lock só é atualizado (e publicado) aqui.
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
            };
          };
        };

        # Chave age pessoal (sops-nix do HM). Na instalação pelo Bitwarden, o
        # install.sh já a grava; com o nix-keys (git-crypt, desbloqueado com a
        # chave GPG da YubiKey), esta ativação a copia de lá. Sem ela, os
        # segredos do HM simplesmente não são instalados até o próximo switch.
        sops.age.keyFile = personalAgeKey;

        home = {
          packages = with pkgs; [
            gcc
            python3
            rustup
            pandoc
            github-copilot-cli
            antigravity-ide
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

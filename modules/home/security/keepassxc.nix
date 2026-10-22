# KeePassXC de cada usuário: ícone na bandeja, integração com o navegador e
# agente SSH (as chaves marcadas nos bancos entram no ssh-agent do sistema ao
# desbloquear e saem ao travar). Sem FdoSecrets: o Secret Service é o oo7.
#
# Quando o ssh precisa de uma chave e o agente não tem nenhuma (banco
# travado), um bloco `Match exec` no ~/.ssh/config abre o pedido de
# desbloqueio do KeePassXC e segura a conexão até as chaves chegarem.
#
# Override local: ~/.config/keepassxc/keepassxc.ini é do home-manager; ajustes
# feitos na interface que não estejam aqui continuam valendo até o próximo
# switch.
{
  flake.modules.homeManager.keepassxc =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      # Roda antes de cada conexão ssh (Match exec, abaixo). Agente sem
      # identidades = banco travado: abre o último banco ativo (um segundo
      # `keepassxc` repassa o arquivo à instância em execução, que mostra o
      # pedido de desbloqueio) e espera uma chave aparecer no agente. Sempre
      # sai com 1, para o Match nunca casar nem aplicar nada.
      sshUnlock = pkgs.writeShellApplication {
        name = "keepassxc-ssh-unlock";
        runtimeInputs = [
          config.programs.keepassxc.package
          pkgs.coreutils
          pkgs.gnused
          pkgs.openssh
          pkgs.util-linux
        ];
        text = ''
          timeout=''${KEEPASSXC_SSH_UNLOCK_TIMEOUT:-60}
          trap 'exit 1' EXIT

          # 0: o agente já tem chave; 2: não há agente para receber as chaves.
          rc=0
          ssh-add -l &>/dev/null || rc=$?
          ((rc == 1)) || exit

          # Sem sessão gráfica para mostrar o pedido (TTY, login via ssh).
          [[ -n ''${WAYLAND_DISPLAY:-} ]] || exit

          db=$(sed -n 's/^LastActiveDatabase=//p' "''${XDG_CACHE_HOME:-$HOME/.cache}/keepassxc/keepassxc.ini" 2>/dev/null || true)
          [[ -n $db && -f $db ]] || exit

          echo "ssh: aguardando o desbloqueio de $(basename "$db") no KeePassXC..." >&2
          setsid -f keepassxc "$db" &>/dev/null

          for ((i = 0; i < timeout; i++)); do
            sleep 1
            ssh-add -l &>/dev/null && exit
          done

          echo "ssh: KeePassXC ainda travado após ''${timeout}s; seguindo sem as chaves dele" >&2
        '';
      };
    in
    {
      programs.keepassxc = {
        enable = lib.mkDefault true;
        autostart = lib.mkDefault true;
        settings = {
          Browser = {
            Enabled = true;
            # O home-manager gera os manifestos; o KeePassXC não os reescreve.
            UpdateBinaryPath = false;
          };
          FdoSecrets.Enabled = false;
          GUI = {
            MinimizeOnClose = true;
            MinimizeToTray = true;
            MinimizeOnStartup = true;
            ShowTrayIcon = true;
            TrayIconAppearance = "monochrome-light";
            MonospaceNotes = true;
          };
          Security.IconDownloadFallback = true;
          SSHAgent.Enabled = true;
        };
      };

      programs.ssh.settings.keepassxc-unlock = {
        header = ''Match exec "${lib.getExe sshUnlock}"'';
      };

      xdg.autostart.enable = lib.mkDefault true;

      # O ssh-agent do sistema (programs.ssh.startAgent, security/keepassxc.nix)
      # escuta em $XDG_RUNTIME_DIR/ssh-agent. O NixOS só exporta o
      # SSH_AUTH_SOCK nos shells; pelo environment.d ele chega também à sessão
      # gráfica e ao KeePassXC, que adiciona as chaves dos bancos ao agente.
      systemd.user.sessionVariables.SSH_AUTH_SOCK = "\${XDG_RUNTIME_DIR}/ssh-agent";
    };
}

# Aplicativos gráficos e TUIs padrão — levantados a partir do sistema Omarchy
# do usuário, todos como pacotes Nix nativos.
{
  flake.modules.nixos.apps =
    { pkgs, ... }:
    {
      environment.systemPackages = with pkgs; [
        # Terminais
        ghostty
        kitty
        foot

        # Arquivos (Nautilus e Flea: desktop/file-manager.nix), discos e mídia
        gnome-disk-utility
        papers
        zathura
        imv
        mpv
        mpvScripts.mpris

        # Escritório e notas
        onlyoffice-desktopeditors
        xournalpp

        # Rede e utilitários
        localsend
        zoom-us

        # Gráficos, áudio e vídeo
        obs-studio
        kdePackages.kdenlive
        pinta
        inkscape
        fontforge-gtk

        # Gravação de tela (usada pelo plugin screen_recorder da Noctalia)
        gpu-screen-recorder

        # Editores
        zed-editor-fhs
        vscode-fhs
        emacs-pgtk

        # Tema Qt e ditado por voz (Superwhisper: packages/_superwhisper)
        libsForQt5.qt5ct
        kdePackages.qt6ct
        superwhisper

        # TUIs do Omarchy
        lazygit
        btop
        dua
        fastfetch
        tldr
        gum
        yt-dlp
        mise
        fzf
        ripgrep
        fd
        bat
        eza
        zoxide

        # Usados por plugins da Noctalia (captura, cor, OCR, QR, gravação,
        # calculadora e busca no nixpkgs)
        slurp
        hyprpicker
        tesseract
        imagemagick
        zbar
        translate-shell
        wl-screenrec
        bc
        pulseaudio
        libqalculate
        nix-search-tv
      ];

      # Serviço de usuário do Superwhisper (o daemon que grava, transcreve e
      # cola), na sessão gráfica de todo usuário. Os atalhos chamam
      # `superwhisper record` (home/desktop/umbriel.nix).
      systemd.packages = [ pkgs.superwhisper ];
      systemd.user.services.superwhisper.wantedBy = [ "graphical-session.target" ];

      # A porta do LocalSend precisa estar aberta para receber arquivos.
      networking.firewall = {
        allowedTCPPorts = [ 53317 ];
        allowedUDPPorts = [ 53317 ];
      };
    };
}

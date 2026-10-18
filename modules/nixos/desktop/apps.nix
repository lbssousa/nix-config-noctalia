# Aplicativos gráficos e TUIs padrão — levantados a partir do sistema Omarchy
# do usuário, todos como pacotes Nix nativos.
{
  flake.modules.nixos.apps =
    { pkgs, ... }:
    {
      # Gerenciador de arquivos padrão do sistema; cada usuário pode trocar
      # pelo home-manager (my.fileManager, home/base/xdg.nix) ou em
      # ~/.config/mimeapps.list.
      xdg.mime.defaultApplications."inode/directory" = "org.gnome.Nautilus.desktop";

      environment.systemPackages = with pkgs; [
        # Terminais
        ghostty
        kitty
        foot

        # Arquivos, discos e mídia
        nautilus
        sushi
        flea
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

        # Tema Qt e ditado por voz
        libsForQt5.qt5ct
        kdePackages.qt6ct
        voxtype

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

      # A porta do LocalSend precisa estar aberta para receber arquivos.
      networking.firewall = {
        allowedTCPPorts = [ 53317 ];
        allowedUDPPorts = [ 53317 ];
      };

      i18n.inputMethod = {
        enable = true;
        type = "fcitx5";
        fcitx5.waylandFrontend = true;
        fcitx5.addons = [ pkgs.fcitx5-gtk ];
      };
    };
}

# Aplicativos gráficos e TUIs padrão — levantados a partir do sistema Omarchy
# do usuário.
#
# Os aplicativos gráficos vêm do Flathub (services.flatpak.packages, ver
# flatpak.nix). Ficam em Nix:
#  - os que não estão no Flathub (ghostty, kitty, discos, imv, Superwhisper);
#  - o foot, que existe no Flathub, mas num terminal em sandbox o shell perde
#    as ferramentas do host;
#  - os editores, FHS e com as toolchains do host, e o zathura, que o vimtex do
#    nixvim usa com SyncTeX (o zathura chama o nvim de volta, o que o sandbox
#    impede);
#  - o que plugins e scripts chamam pela linha de comando (gpu-screen-recorder
#    do plugin screen_recorder, as TUIs e os utilitários dos plugins).
{
  flake.modules.nixos.apps =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      services.flatpak.packages = [
        # PDF, imagens e vídeo
        "org.gnome.Papers"
        "io.mpv.Mpv"

        # Escritório e notas
        "org.onlyoffice.desktopeditors"
        "com.github.xournalpp.xournalpp"

        # Rede
        "org.localsend.localsend_app"
        "us.zoom.Zoom"

        # Gráficos, áudio e vídeo
        "com.obsproject.Studio"
        "org.kde.kdenlive"
        "com.github.PintaProject.Pinta"
        "org.inkscape.Inkscape"
        "org.fontforge.FontForge"
      ]
      # Dropbox, só se algum usuário o ligar (my.dropbox.enable,
      # home/desktop/dropbox.nix).
      ++ lib.optional (lib.any (u: u.my.dropbox.enable) (
        lib.attrValues config.my.homes
      )) "com.dropbox.Client";

      environment.systemPackages = with pkgs; [
        # Terminais
        ghostty
        kitty
        foot

        # Arquivos (Luciole: desktop/file-manager.nix), discos, imagens e PDF
        gnome-disk-utility
        imv
        zathura

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

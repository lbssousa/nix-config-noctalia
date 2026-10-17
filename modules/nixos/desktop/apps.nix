# Aplicativos gráficos e TUIs padrão — levantados a partir do sistema Omarchy
# do usuário.
#
# Os aplicativos gráficos de usuário vêm do Flathub (services.flatpak.packages,
# ver flatpak.nix); ficam nativos só o que integra com o sistema ou com o fluxo
# de terminal: terminais, arquivos/discos, visualizadores de teclado (zathura,
# imv, mpv), editores de código (FHS, com as toolchains do host), o que os
# plugins da Noctalia chamam e as TUIs.
{
  flake.modules.nixos.apps =
    { pkgs, ... }:
    {
      services.flatpak.packages = [
        # Escritório, notas e PDF
        "org.onlyoffice.desktopeditors"
        "com.github.xournalpp.xournalpp"
        "org.gnome.Papers"

        # Rede
        "org.localsend.localsend_app"
        "us.zoom.Zoom"

        # Gráficos, áudio e vídeo
        "com.obsproject.Studio"
        "org.kde.kdenlive"
        "com.github.PintaProject.Pinta"
        "org.inkscape.Inkscape"
        "org.fontforge.FontForge"
      ];

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
        zathura
        imv
        mpv
        mpvScripts.mpris

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

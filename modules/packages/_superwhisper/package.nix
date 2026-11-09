# Superwhisper para Linux (https://superwhisper.com/linux), ditado local e na
# nuvem. Binários proprietários da Super Ultra, Inc., do canal oficial de
# releases (github.com/superultrainc/superwhisper-linux-releases), assinados com
# minisign; a chave pública está em app/assets/linux-release.pub.
#
# O instalador oficial (tux.superwhisper.com/install.sh) copia o app para
# ~/.local/share/superwhisper, instala dependências com o gerenciador de pacotes
# da distribuição e escreve um serviço systemd de usuário. Aqui o app vai para
# $out/libexec/superwhisper, com autoPatchelf nos binários e um wrapper que põe
# no PATH o que ele executa pelo nome (python3 com GObject, wl-copy, wtype,
# ffmpeg, paplay) e no LD_LIBRARY_PATH o que a janela de configurações (GPUI)
# carrega por dlopen. O serviço, o atalho e o desktop entry ficam em share/.
#
# Sem atualização automática: o app fica no Nix store, somente leitura. Nova
# versão é trocar `version` e os hashes abaixo.
{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  makeWrapper,
  wrapGAppsHook4,
  gobject-introspection,
  zstd,
  python3,
  gtk4,
  gtk4-layer-shell,
  at-spi2-core,
  gdk-pixbuf,
  librsvg,
  glib,
  cairo,
  graphene,
  libxcb,
  fontconfig,
  libxkbcommon,
  wayland,
  vulkan-loader,
  libGL,
  wl-clipboard,
  wtype,
  ffmpeg,
  pulseaudio,
  libnotify,
  minisign,
}:

let
  version = "1.2.0";
  arch = stdenv.hostPlatform.parsed.cpu.name;
  hashes = {
    x86_64 = "sha256-KLxXWO1s9CRouX75QOwqlrEU5rbqA7yywEvGeIV9AvA=";
    aarch64 = "sha256-sA448gPdW4xjS3bf2VwxEoWP3myQTniKN0GYHA6uafg=";
  };
  python = python3.withPackages (ps: [
    ps.pygobject3
    ps.pycairo
  ]);
in
stdenv.mkDerivation {
  pname = "superwhisper";
  inherit version;

  src = fetchurl {
    url = "https://github.com/superultrainc/superwhisper-linux-releases/releases/download/v${version}/superwhisper-linux-${arch}-${version}.tar.zst";
    hash = hashes.${arch};
  };

  nativeBuildInputs = [
    autoPatchelfHook
    makeWrapper
    wrapGAppsHook4
    gobject-introspection
    zstd
  ];

  buildInputs = [
    stdenv.cc.cc.lib
    gtk4
    gtk4-layer-shell
    at-spi2-core
    gdk-pixbuf
    librsvg
    glib
    cairo
    graphene
    libxcb
    fontconfig
    libxkbcommon
    vulkan-loader
  ];

  # Addon do fcitx5, usado só no Hyprland (a inserção sem área de
  # transferência); sem fcitx5 aqui, fica sem as bibliotecas dele.
  autoPatchelfIgnoreMissingDeps = [
    "libFcitx5Core.so.7"
    "libFcitx5Utils.so.2"
  ];

  # O wrapper abaixo leva os argumentos do wrapGAppsHook4 (GI_TYPELIB_PATH dos
  # scripts Python, XDG_DATA_DIRS, loaders do gdk-pixbuf).
  dontWrapGApps = true;
  dontConfigure = true;
  dontBuild = true;

  unpackPhase = ''
    runHook preUnpack
    tar --zstd -xf "$src"
    cd superwhisper-omarchy-${arch}-${version}
    runHook postUnpack
  '';

  installPhase = ''
    runHook preInstall

    app=$out/libexec/superwhisper
    mkdir -p $app $out/bin
    cp -r app/. $app/
    # O desinstalador do instalador oficial não faz sentido no Nix store.
    rm -f $app/uninstall.sh
    patchShebangs $app/run.sh

    install -Dm644 -t $out/share/licenses/superwhisper licenses/*
    install -Dm644 -t $out/share/fonts/truetype $app/assets/linux-status/*.ttf
    for icon in $app/assets/app-icon/*.png; do
      size=$(basename "$icon" .png)
      install -Dm644 "$icon" $out/share/icons/hicolor/''${size}x''${size}/apps/superwhisper.png
    done

    mkdir -p $out/share/applications
    cat > $out/share/applications/com.superwhisper.Superwhisper.desktop <<EOF
    [Desktop Entry]
    Type=Application
    Name=Superwhisper
    Comment=Fast local and cloud dictation
    Exec=$out/bin/superwhisper settings --window
    Icon=superwhisper
    Terminal=false
    StartupWMClass=com.superwhisper.Superwhisper
    Categories=Utility;Accessibility;
    EOF

    # O mesmo serviço que o install.sh oficial escreve, apontando para $out.
    mkdir -p $out/share/systemd/user
    cat > $out/share/systemd/user/superwhisper.service <<EOF
    [Unit]
    Description=Superwhisper dictation
    After=graphical-session.target pipewire.service
    PartOf=graphical-session.target

    [Service]
    Type=simple
    ExecStart=$out/bin/superwhisper daemon
    ExecStopPost=$out/bin/superwhisper playback-restore
    ExecStopPost=$out/bin/superwhisper desktop-release
    Restart=on-failure
    RestartSec=2
    KillMode=control-group
    TimeoutStopSec=15
    UMask=0077

    [Install]
    WantedBy=graphical-session.target
    EOF

    runHook postInstall
  '';

  postFixup = ''
    makeWrapper $out/libexec/superwhisper/run.sh $out/bin/superwhisper \
      "''${gappsWrapperArgs[@]}" \
      --prefix PATH : ${
        lib.makeBinPath [
          python
          wl-clipboard
          wtype
          ffmpeg
          pulseaudio
          libnotify
          minisign
        ]
      } \
      --prefix LD_LIBRARY_PATH : ${
        lib.makeLibraryPath [
          vulkan-loader
          libGL
          wayland
          libxkbcommon
        ]
      }
  '';

  meta = {
    description = "Local and cloud voice dictation for Wayland";
    homepage = "https://superwhisper.com/linux";
    license = lib.licenses.unfree;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
    mainProgram = "superwhisper";
  };
}

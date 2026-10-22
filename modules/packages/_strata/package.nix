# Strata, gerenciador de arquivos GTK4 (https://github.com/lgse/strata),
# compilado do código-fonte. Sem caminhos FHS no NixOS, o build embute:
#  - STRATA_TRUSTED_COMMAND_PATH: onde o processo principal acha o bwrap e os
#    outros auxiliares que executa direto;
#  - STRATA_SANDBOX_*: a árvore (/nix/store), os decodificadores e o prlimit
#    das prévias e miniaturas, que rodam no bubblewrap.
# O marcador share/strata/install-source.toml desliga o atualizador embutido
# (o Nix é o dono do binário). O serviço D-Bus do FileManager1 fica só como
# modelo em share/strata (packaging.md do Strata); quem o ativa é o módulo
# nixos/desktop/file-manager.nix.
{
  lib,
  rustPlatform,
  fetchFromGitHub,
  pkg-config,
  wrapGAppsHook4,
  glib,
  gtk4,
  gtksourceview5,
  poppler,
  fontconfig,
  gst_all_1,
  gnome,
  librsvg,
  webp-pixbuf-loader,
  bubblewrap,
  xdg-utils,
  coreutils,
  bash,
  util-linux,
  ffmpeg-headless,
  ffmpegthumbnailer,
  imagemagick,
  p7zip,
  gnutar,
  file,
  exiftool,
  squashfsTools,
}:

let
  pixbufLoaders = gnome._gdkPixbufCacheBuilder_DO_NOT_USE {
    extraLoaders = [
      librsvg
      webp-pixbuf-loader
    ];
  };
in
rustPlatform.buildRustPackage (finalAttrs: {
  pname = "strata";
  version = "1.1.0";

  src = fetchFromGitHub {
    owner = "lgse";
    repo = "strata";
    tag = "v${finalAttrs.version}";
    hash = "sha256-FoYYsjvWY+1SuZtvxancdVR6h7iFmnbtHXW2eTlVCJI=";
  };

  cargoHash = "sha256-U52ypUksrz/2G8apmyh7x9c+47ZBStT1lHIWso7KfU4=";

  nativeBuildInputs = [
    pkg-config
    wrapGAppsHook4
    glib
    rustPlatform.bindgenHook
  ];

  buildInputs = [
    glib
    gtk4
    gtksourceview5
    poppler
    fontconfig
    gst_all_1.gstreamer
    gst_all_1.gst-plugins-base
    gst_all_1.gst-plugins-good
    gst_all_1.gst-libav
  ];

  env = {
    STRATA_RELEASE_TAG = "v${finalAttrs.version}";
    STRATA_BUILD_COMMIT = "v${finalAttrs.version}";
    STRATA_BUILD_KIND = "stable";
    STRATA_TRUSTED_COMMAND_PATH = lib.makeBinPath [
      bubblewrap
      xdg-utils
      coreutils
      bash
    ];
    STRATA_SANDBOX_ROOT = "/nix/store";
    STRATA_SANDBOX_PATH = lib.makeBinPath [
      ffmpeg-headless
      ffmpegthumbnailer
      imagemagick
      p7zip
      gnutar
      file
      exiftool
      squashfsTools
      coreutils
    ];
    STRATA_SANDBOX_PRLIMIT = "${util-linux}/bin/prlimit";
    STRATA_SANDBOX_GDK_PIXBUF_MODULE_FILE = "${pixbufLoaders}";
  };

  # A suíte é de GUI (Xvfb, xdotool) e de dispositivos.
  doCheck = false;

  postInstall = ''
    install -Dm644 data/io.github.lgse.Strata.desktop -t $out/share/applications
    substituteInPlace $out/share/applications/io.github.lgse.Strata.desktop \
      --replace-fail "Exec=strata" "Exec=$out/bin/strata"
    install -Dm644 data/icons/scalable/apps/io.github.lgse.Strata.svg \
      -t $out/share/icons/hicolor/scalable/apps

    install -Dm644 data/io.github.lgse.Strata.FileManager1.service -t $out/share/strata
    substituteInPlace $out/share/strata/io.github.lgse.Strata.FileManager1.service \
      --replace-fail /usr/bin/strata $out/bin/strata

    install -Dm644 data/portal/strata.portal -t $out/share/xdg-desktop-portal/portals
    install -Dm644 data/portal/org.freedesktop.impl.portal.desktop.strata.service.in \
      $out/share/dbus-1/services/org.freedesktop.impl.portal.desktop.strata.service
    substituteInPlace $out/share/dbus-1/services/org.freedesktop.impl.portal.desktop.strata.service \
      --replace-fail @STRATA_EXECUTABLE@ $out/bin/strata

    cat > $out/share/strata/install-source.toml <<EOF
    manager = "Nix"
    package = "strata"
    channel = "stable"
    EOF
  '';

  meta = {
    description = "Fast, keyboard-first file manager for Linux";
    homepage = "https://github.com/lgse/strata";
    license = with lib.licenses; [
      mit
      unfreeRedistributable # UnRAR embutido
    ];
    mainProgram = "strata";
    platforms = lib.platforms.linux;
  };
})

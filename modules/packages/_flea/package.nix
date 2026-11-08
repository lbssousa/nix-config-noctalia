# Flea, gerenciador de arquivos (https://github.com/thisisgm/flea), compilado do
# código-fonte. Feito para a Omarchy, mas a 0.4 desenha a janela com GPUI
# (flea-gui) e só usa a Omarchy para o tema, a prateleira da barra e os
# atalhos do Hyprland; aqui roda sem ela, com o tema padrão.
#
# Sem caminhos FHS no NixOS, nixos-paths.patch troca:
#  - /usr/{bin,lib,share}/flea pelos de $out (@out@);
#  - as ferramentas executadas por caminho absoluto (qjs, 7z, diff, git,
#    gvfsd-fuse) e as bibliotecas abertas com dlopen (mpv, poppler, libheif,
#    ffmpegthumbnailer) pelos caminhos no Nix store: os auxiliares das jaulas
#    rodam com o ambiente limpo, sem LD_LIBRARY_PATH;
#  - o banco MIME por /run/current-system/sw/share/mime;
#  - e faz as jaulas do bubblewrap (miniaturas, prévias, busca, mídia) também
#    montarem /nix/store e /run/current-system/sw, onde estão as ferramentas.
# O wrapper põe no PATH o que o Flea executa pelo nome e no LD_LIBRARY_PATH
# o que o GPUI carrega (Vulkan, EGL, Wayland, xkbcommon).
#
# O backend do portal FileChooser vai para share/ (xdg.portal.extraPortals o
# registra). O serviço FileManager1 fica só como modelo em share/flea, como no
# pacote do Strata: no D-Bus do sistema ele disputaria o nome com o Nautilus de
# todos os usuários; quem o ativa por usuário é home/desktop/flea.nix, no lugar
# do `flea --default` (que escreveria em ~/.config/mimeapps.list e nos atalhos
# do Hyprland).
{
  lib,
  rustPlatform,
  fetchFromGitHub,
  pkg-config,
  makeWrapper,
  gobject-introspection,
  wrapGAppsNoGuiHook,
  python3,
  expect,
  fontconfig,
  freetype,
  glib,
  gdk-pixbuf,
  libxkbcommon,
  libxcb,
  wayland,
  vulkan-loader,
  libGL,
  mpv-unwrapped,
  poppler,
  poppler-utils,
  libheif,
  cairo,
  ffmpegthumbnailer,
  bubblewrap,
  util-linux,
  coreutils,
  bash,
  diffutils,
  gitMinimal,
  gvfs,
  bat,
  jq,
  ripgrep,
  quickjs-ng,
  wl-clipboard,
  xdg-utils,
  udisks,
  p7zip,
  libarchive,
  ffmpeg-headless,
  imagemagick,
  zoxide,
}:

let
  pythonEnv = python3.withPackages (ps: [ ps.pygobject3 ]);
  # Carregadas pelo GPUI (wgpu, glow, wayland-client, xkbcommon) no processo da janela.
  runtimeLibs = [
    vulkan-loader
    libGL
    wayland
    libxkbcommon
  ];
  # Executados pelo nome: os do PKGBUILD (depends e optdepends) que existem no nixpkgs.
  runtimePath = [
    bubblewrap
    util-linux
    coreutils
    bash
    bat
    jq
    ripgrep
    quickjs-ng
    wl-clipboard
    xdg-utils
    udisks
    glib
    gvfs
    expect
    poppler-utils
    p7zip
    libarchive
    ffmpeg-headless
    ffmpegthumbnailer
    imagemagick
    zoxide
  ];
in
rustPlatform.buildRustPackage (finalAttrs: {
  pname = "flea";
  version = "0.4.0";

  src = fetchFromGitHub {
    owner = "thisisgm";
    repo = "flea";
    tag = "v${finalAttrs.version}";
    hash = "sha256-zzGFgcpA2D3AwGKjt8H1cz9mwi/i/iqBNB4xLl35bZg=";
  };

  cargoHash = "sha256-eOl8EtxMEKpwRancasWjtYQ+su7WCpppiCtZ+rZ+WMU=";

  patches = [ ./nixos-paths.patch ];

  postPatch = ''
    substituteInPlace $(grep -rlE '@(out|quickjs|p7zip|bash|diffutils|git|gvfs|mpv|poppler|glib|cairo|libheif|ffmpegthumbnailer)@' src crates tools) \
      --subst-var out \
      --subst-var-by quickjs ${quickjs-ng} \
      --subst-var-by p7zip ${p7zip} \
      --subst-var-by bash ${bash} \
      --subst-var-by diffutils ${diffutils} \
      --subst-var-by git ${gitMinimal} \
      --subst-var-by gvfs ${gvfs} \
      --subst-var-by mpv ${lib.getLib mpv-unwrapped} \
      --subst-var-by poppler ${lib.getLib poppler} \
      --subst-var-by glib ${lib.getLib glib} \
      --subst-var-by cairo ${lib.getLib cairo} \
      --subst-var-by libheif ${lib.getLib libheif} \
      --subst-var-by ffmpegthumbnailer ${lib.getLib ffmpegthumbnailer}
  '';

  strictDeps = true;

  nativeBuildInputs = [
    pkg-config
    makeWrapper
    gobject-introspection
    wrapGAppsNoGuiHook
  ];

  buildInputs = [
    fontconfig
    freetype
    glib
    gdk-pixbuf
    libxkbcommon
    libxcb
    wayland
    pythonEnv
    expect
  ];

  cargoBuildFlags = [
    "--workspace"
    "--bins"
  ];

  # O LTO completo com uma unidade de código leva o link final a um único
  # núcleo por muito tempo; o thin dá praticamente o mesmo binário.
  env = {
    CARGO_PROFILE_RELEASE_LTO = "thin";
    CARGO_PROFILE_RELEASE_CODEGEN_UNITS = "16";
  };

  # As suítes de teste precisam de bubblewrap, de um /usr FHS e de um
  # compositor (o CI do Flea roda o Hyprland headless).
  doCheck = false;

  # O que o Makefile do Flea instala, com $out no lugar de /usr e sem os links
  # para /usr/share/omarchy/shell.
  postInstall = ''
    for tool in flea-gio-auth flea-udisks flea-portal flea-filemanager1 flea-mpris; do
      install -Dm755 tools/$tool -t $out/lib/flea
    done

    install -Dm644 packaging/flea.portal -t $out/share/xdg-desktop-portal/portals
    install -Dm644 packaging/org.freedesktop.impl.portal.desktop.flea.service -t $out/share/dbus-1/services
    install -Dm644 packaging/com.thisisgm.flea.FileManager1.service -t $out/share/flea
    substituteInPlace $out/share/dbus-1/services/*.service $out/share/flea/*.service \
      --replace-fail /usr/lib/flea $out/lib/flea

    install -Dm644 packaging/com.thisisgm.flea.desktop -t $out/share/applications
    substituteInPlace $out/share/applications/com.thisisgm.flea.desktop \
      --replace-fail "Exec=flea" "Exec=$out/bin/flea"
    install -Dm644 packaging/com.thisisgm.flea.svg -t $out/share/icons/hicolor/scalable/apps

    install -Dm644 ui/qmldir ui/*.qml ui/*.js -t $out/share/flea/ui
    install -Dm644 ui/js/*.js ui/js/*.mjs -t $out/share/flea/ui/js
    install -Dm644 ui/vendor/*.mjs -t $out/share/flea/ui/vendor
    install -Dm644 ui/boot/*.qml -t $out/share/flea/ui/boot
    install -Dm644 shelf/manifest.json shelf/README.md shelf/*.qml shelf/*.js -t $out/share/flea/shelf
    for catalog in i18n/*/flea.json; do
      install -Dm644 "$catalog" "$out/share/flea/$catalog"
    done
    install -Dm644 LICENSE THIRD-PARTY-LICENSES.txt -t $out/share/licenses/flea
  '';

  # Os auxiliares em lib/flea são Python com PyGObject (portal, FileManager1,
  # MPRIS, udisks) e expect (montagem com senha): mesmo ambiente dos binários.
  dontWrapGApps = true;
  postFixup = ''
    # flea-gui liga o gdk-pixbuf e a glib sem -L próprio, e o shrink tira os
    # dois do RPATH; o wrapper não basta, porque o mesmo binário também roda
    # como auxiliar dentro das jaulas, com o ambiente limpo.
    patchelf --add-rpath ${
      lib.makeLibraryPath [
        gdk-pixbuf
        glib
      ]
    } $out/bin/flea-gui
    patchShebangs --host $out/lib/flea
    for program in $out/bin/flea $out/bin/flea-gui $out/lib/flea/*; do
      wrapProgram "$program" "''${gappsWrapperArgs[@]}" \
        --prefix PATH : ${lib.makeBinPath runtimePath} \
        --prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath runtimeLibs}
    done
  '';

  meta = {
    description = "Fast, keyboard-first file manager built for Omarchy";
    homepage = "https://github.com/thisisgm/flea";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    mainProgram = "flea";
  };
})

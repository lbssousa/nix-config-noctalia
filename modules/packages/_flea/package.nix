# Flea — gerenciador de arquivos do Omarchy (front-end Quickshell, back-end Rust).
# https://github.com/thisisgm/flea
#
# Fora do Omarchy, três adaptações:
#  - a UI importa qs.Commons/qs.Ui do shell do Omarchy, então shell/{Commons,Ui}
#    vêm do repositório basecamp/omarchy (MIT) e são ligados dentro da UI,
#    como faz o PKGBUILD;
#  - os caminhos /usr/share/flea/ui, /usr/bin/qjs e /usr/lib/flea/* são
#    redirecionados pelas variáveis de ambiente que o próprio Flea consulta
#    (FLEA_UI, FLEA_QJS, FLEA_MPRIS, FLEA_GIO_AUTH, FLEA_UDISKS);
#  - as cores vêm de ~/.local/state/omarchy/current/theme/colors.toml quando
#    existe; sem ele o Flea usa a paleta embutida.
# Recursos que dependem de scripts omarchy-* (Taildrop, "abrir terminal aqui"
# do Omarchy, captura) ficam indisponíveis.
{
  lib,
  rustPlatform,
  fetchFromGitHub,
  makeWrapper,
  python3,
  quickshell,
  quickjs-ng,
  bat,
  jq,
  bubblewrap,
  expect,
  util-linux,
  udisks,
  wl-clipboard,
  xdg-utils,
  glib,
  libarchive,
  p7zip,
  ffmpeg,
  ffmpegthumbnailer,
  imagemagick,
  zoxide,
  kdePackages,
}:
let
  version = "0.3.11";

  omarchy = fetchFromGitHub {
    owner = "basecamp";
    repo = "omarchy";
    rev = "v4.0.4";
    hash = "sha256-nstxM+CP6al2I4N1LAKdYBvJ4tytD1m8jssiCD7PXTY=";
  };

  python = python3.withPackages (ps: [ ps.pygobject3 ]);

  runtimePath = lib.makeBinPath [
    quickshell
    quickjs-ng
    bat
    jq
    bubblewrap
    expect
    util-linux
    udisks
    wl-clipboard
    xdg-utils
    glib
    python
    libarchive
    p7zip
    ffmpeg
    ffmpegthumbnailer
    imagemagick
    zoxide
  ];
in
rustPlatform.buildRustPackage {
  pname = "flea";
  inherit version;

  src = fetchFromGitHub {
    owner = "thisisgm";
    repo = "flea";
    tag = "v${version}";
    hash = "sha256-pXs70V3iUohYt5PduB2uUwHKBM1HAVUVYiLTYtvJCnE=";
  };

  cargoLock.lockFile = ./Cargo.lock;
  postPatch = ''
    cp ${./Cargo.lock} Cargo.lock
  '';

  nativeBuildInputs = [ makeWrapper ];
  buildInputs = [ python ];

  # Os testes de integração procuram ./target/<perfil>/flea e /usr/bin/qjs.
  doCheck = false;

  postInstall = ''
    share=$out/share/flea
    libexec=$out/libexec/flea

    install -Dm755 tools/flea-gio-auth tools/flea-udisks tools/flea-portal \
      tools/flea-filemanager1 tools/flea-mpris -t $libexec
    patchShebangs --host $libexec
    for t in $libexec/*; do
      wrapProgram $t --prefix PATH : ${runtimePath} --prefix GI_TYPELIB_PATH : "${glib.out}/lib/girepository-1.0"
    done

    install -Dm644 ui/qmldir ui/*.qml ui/*.js -t $share/ui
    install -Dm644 ui/js/*.js ui/js/*.mjs -t $share/ui/js
    install -Dm644 ui/vendor/*.mjs -t $share/ui/vendor
    install -Dm644 ui/vendor/LICENSES/* -t $share/ui/vendor/LICENSES
    install -Dm644 ui/boot/shell.qml ui/boot/picker.qml ui/boot/fleatab.qml ui/boot/tabtearoff.qml -t $share/ui/boot
    install -Dm644 shelf/manifest.json shelf/README.md shelf/*.qml shelf/*.js -t $share/shelf

    # qs.Commons / qs.Ui do shell do Omarchy, nos dois diretórios-raiz da UI.
    mkdir -p $share/omarchy-shell
    cp -r ${omarchy}/shell/Commons ${omarchy}/shell/Ui $share/omarchy-shell/
    for d in $share/ui $share/ui/boot; do
      ln -s $share/omarchy-shell/Commons $d/Commons
      ln -s $share/omarchy-shell/Ui $d/Ui
    done

    install -Dm644 packaging/com.thisisgm.flea.desktop -t $out/share/applications
    install -Dm644 packaging/com.thisisgm.flea.svg -t $out/share/icons/hicolor/scalable/apps
    install -Dm644 packaging/flea.portal -t $out/share/xdg-desktop-portal/portals
    install -Dm644 packaging/org.freedesktop.impl.portal.desktop.flea.service -t $out/share/dbus-1/services
    substituteInPlace $out/share/dbus-1/services/org.freedesktop.impl.portal.desktop.flea.service \
      --replace-fail /usr/lib/flea/flea-portal $libexec/flea-portal

    wrapProgram $out/bin/flea \
      --prefix PATH : ${runtimePath} \
      --prefix QML_IMPORT_PATH : "${kdePackages.qtmultimedia}/lib/qt-6/qml:${kdePackages.qtwebengine}/lib/qt-6/qml" \
      --set-default FLEA_UI $share/ui \
      --set-default FLEA_QJS ${lib.getExe' quickjs-ng "qjs"} \
      --set-default FLEA_MPRIS $libexec/flea-mpris \
      --set-default FLEA_GIO_AUTH $libexec/flea-gio-auth \
      --set-default FLEA_UDISKS $libexec/flea-udisks
  '';

  meta = {
    description = "Fast, keyboard-first file manager for Omarchy";
    homepage = "https://github.com/thisisgm/flea";
    license = with lib.licenses; [
      mit
      asl20
      epl20
      bsd2
    ];
    mainProgram = "flea";
    platforms = lib.platforms.linux;
  };
}

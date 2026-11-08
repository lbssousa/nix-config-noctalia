# Auxiliar do plugin lbssousa/security-hardware da Noctalia
# (home/desktop/_noctalia-plugins): digitais pelo D-Bus do fprintd, chaves
# FIDO2/U2F (pamu2fcfg, fido2-token, pamtester no serviço "noctalia-lock-u2f")
# e o cartão OpenPGP (gpg). Antes era a página Segurança das Configurações, num
# patch da shell; os mantenedores mandam controles de hardware para plugins
# (SCOPE.md). Uma operação por processo, saída em JSON por linha.
{
  lib,
  stdenvNoCC,
  python3,
  gobject-introspection,
  wrapGAppsNoGuiHook,
  glib,
  gnupg,
  libfido2,
  pam_u2f,
  pamtester,
}:

stdenvNoCC.mkDerivation {
  pname = "noctalia-security-hw";
  version = "1.0.0";

  src = ./noctalia-security-hw.py;
  dontUnpack = true;

  strictDeps = true;
  __structuredAttrs = true;

  nativeBuildInputs = [
    gobject-introspection
    wrapGAppsNoGuiHook
  ];
  buildInputs = [
    glib
    (python3.withPackages (ps: [ ps.pygobject3 ]))
  ];

  installPhase = ''
    runHook preInstall
    install -Dm755 $src $out/bin/noctalia-security-hw
    patchShebangs --host $out/bin/noctalia-security-hw
    runHook postInstall
  '';

  preFixup = ''
    gappsWrapperArgs+=(--prefix PATH : ${
      lib.makeBinPath [
        gnupg
        libfido2
        pam_u2f
        pamtester
      ]
    })
  '';

  meta = {
    description = "Fingerprint, FIDO2 and OpenPGP card helper for the Noctalia security-hardware plugin";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    mainProgram = "noctalia-security-hw";
  };
}

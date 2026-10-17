# libfprint with support for the Goodix 538d sensor (lbssousa fork)
# Fork: https://github.com/lbssousa/libfprint (tag v1.94.100-goodix538d.1)
# Based on libfprint 1.94.100 with Goodix TLS drivers and the SIGFM matcher.
#
# Drivers included beyond upstream:
#   - goodixtls511  – Goodix 5110
#   - goodixtls52xd – Goodix 52xd family
#   - goodixtls53xd – Goodix 53xd family (includes 538d, USB 27c6:538d)
#
# The SIGFM matcher (reimplemented in C, no OpenCV) handles small-area
# fingerprints where the standard minutiae matcher fails.
{
  lib,
  stdenv,
  fetchFromGitHub,
  pkg-config,
  meson,
  python3,
  ninja,
  gusb,
  pixman,
  glib,
  gobject-introspection,
  cairo,
  libgudev,
  udevCheckHook,
  gtk-doc,
  docbook-xsl-nons,
  docbook_xml_dtd_43,
  openssl,
}:

stdenv.mkDerivation {
  pname = "libfprint-goodix";
  version = "1.94.100-goodix538d.1";

  src = fetchFromGitHub {
    owner = "lbssousa";
    repo = "libfprint";
    tag = "v1.94.100-goodix538d.1";
    hash = "sha256-9XLMdgyVQ0jHvjn+zqNeRXUAD1bsICgwUtu94CV5ICM=";
  };

  postPatch = ''
    patchShebangs \
      tests/test-runner.sh \
      tests/unittest_inspector.py \
      tests/virtual-image.py \
      tests/umockdev-test.py \
      tests/test-generated-hwdb.sh \
      || true
  '';

  nativeBuildInputs = [
    pkg-config
    meson
    ninja
    gtk-doc
    docbook-xsl-nons
    docbook_xml_dtd_43
    gobject-introspection
    udevCheckHook
  ];

  buildInputs = [
    gusb
    pixman
    glib
    cairo
    libgudev
    openssl
  ];

  mesonFlags = [
    "-Dudev_rules_dir=${placeholder "out"}/lib/udev/rules.d"
    "-Ddrivers=default"
    "-Ddoc=false"
    "-Dgtk-examples=false"
    "-Dintrospection=true"
    "-Dudev_hwdb=disabled"
  ];

  nativeInstallCheckInputs = [
    (python3.withPackages (p: with p; [ pygobject3 ]))
  ];

  doCheck = false;
  doInstallCheck = false;

  meta = {
    homepage = "https://github.com/lbssousa/libfprint";
    description = "libfprint with Goodix TLS drivers and SIGFM matcher (lbssousa fork), supporting the 538d sensor (USB 27c6:538d)";
    license = lib.licenses.lgpl21Only;
    platforms = lib.platforms.linux;
    maintainers = [ ];
  };
}

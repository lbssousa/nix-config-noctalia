# Clientes noctalia-pinentry (pinentry-program do gpg-agent) e
# noctalia-askpass (SSH_ASKPASS) que mostram o pedido no plugin
# lbssousa/secret-prompts da Noctalia (home/desktop/_noctalia-plugins). Antes
# eram um patch da shell; os mantenedores não aceitam segredos no core (PR
# #4951), então o protocolo Assuan roda aqui e a shell só desenha o painel.
# Ver src/prompt_bridge.h para o canal com o plugin.
{
  lib,
  stdenv,
  meson,
  ninja,
}:

stdenv.mkDerivation {
  pname = "noctalia-secret-prompts";
  version = "1.0.0";

  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./meson.build
      ./src
      ./tests
    ];
  };

  strictDeps = true;
  __structuredAttrs = true;

  nativeBuildInputs = [
    meson
    ninja
  ];

  doCheck = true;

  meta = {
    description = "pinentry and SSH_ASKPASS clients drawn by the Noctalia shell through a plugin";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    mainProgram = "noctalia-pinentry";
  };
}

# ai-usagebar (https://github.com/akitaonrails/ai-usagebar): CLI que lê o uso
# dos planos de IA (Claude, Codex, Copilot, Antigravity…), exigida pelo plugin
# felipeartur/ai-usagebar da Noctalia, que roda `ai-usagebar usage --json`.
# Adaptado do nix/package.nix do próprio projeto, com a fonte do GitHub.
{
  lib,
  makeWrapper,
  nasm,
  procps,
  rustPlatform,
  stdenv,
  fetchFromGitHub,
  xdg-utils,
}:
rustPlatform.buildRustPackage (finalAttrs: {
  pname = "ai-usagebar";
  version = "1.43.0";

  src = fetchFromGitHub {
    owner = "akitaonrails";
    repo = "ai-usagebar";
    tag = "v${finalAttrs.version}";
    hash = "sha256-fCpoee2gruVO4xCwpmH3bdYSOxozPmk2IIXRzi88/TQ=";
  };

  cargoHash = "sha256-X5VldvDOtNoEcjXGU8b764pmBJDP1IgJSZw1xmNLEs8=";

  # Os testes do claude_desktop::app chamam /usr/bin/tar, que não existe no
  # sandbox (o mesmo skip do pacote upstream).
  checkFlags = [ "--skip=claude_desktop::app::tests" ];

  nativeBuildInputs = [ makeWrapper ] ++ lib.optionals stdenv.hostPlatform.isx86_64 [ nasm ];

  postInstall = ''
    # No Linux o binário da bandeja só imprime uma mensagem e sai.
    rm -f "$out/bin/ai-usagebar-tray"
    install -Dm644 config.example.toml "$out/share/ai-usagebar/config.example.toml"
    for program in ai-usagebar ai-usagebar-tui; do
      wrapProgram "$out/bin/$program" \
        --prefix PATH : ${
          lib.makeBinPath [
            procps
            xdg-utils
          ]
        }
    done
  '';

  meta = {
    description = "Multi-provider AI plan usage for status bars, with a TUI";
    homepage = "https://github.com/akitaonrails/ai-usagebar";
    license = lib.licenses.mit;
    mainProgram = "ai-usagebar";
    platforms = lib.platforms.linux;
  };
})

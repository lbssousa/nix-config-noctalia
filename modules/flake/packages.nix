# Pacotes próprios (modules/packages/_*/package.nix), expostos como
# packages.<system>.<nome> e pelo overlay aplicado a todos os hosts.
{
  config,
  inputs,
  lib,
  ...
}:
let
  overlay =
    final: prev:
    let
      call = path: final.callPackage path { };
    in
    {
      run0-sudo = call ../packages/_run0-sudo/package.nix;
      libfprint-goodix = call ../packages/_libfprint-goodix/package.nix;
      fprintd-goodix = call ../packages/_fprintd-goodix/package.nix;
      yubikey-gpg-import = call ../packages/_yubikey-gpg-import/package.nix;
      superwhisper = call ../packages/_superwhisper/package.nix;

      # Senha expirada (pam_acct_mgmt: NEW_AUTHTOK_REQD) no login gráfico.
      # O greetd 0.10.3 só falhava; o patch chama pam_chauthtok na mesma
      # conversa, e os prompts (senha atual, nova, confirmação) chegam ao
      # greeter como auth_message. Patch local, sem PR upstream.
      greetd = prev.greetd.overrideAttrs (old: {
        patches = (old.patches or [ ]) ++ [ ../packages/patches/greetd-change-expired-authtok.patch ];
      });

      # Família Noctalia (noctalia, noctalia-greeter, umbriel,
      # xdg-desktop-portal-umbriel, luciole, noctalia-secret-prompts): do
      # overlay do flake noctalia-nix (github.com/lbssousa/noctalia-nix),
      # aplicado antes deste. Os patches são commits nos branches nix-config
      # dos forks lbssousa/noctalia, lbssousa/noctalia-greeter e
      # lbssousa/umbriel, rebaseados todo dia sobre o upstream; o CI do
      # noctalia-nix compila e publica tudo no Cachix lbssousa-noctalia, com o
      # mesmo nixpkgs deste flake (nixpkgs.follows em flake.nix).
      #
      # Na Noctalia, o branch nix-config já compila com
      # -Dpam_service=noctalia-lock e -Dpam_service_security_key=noctalia-lock-u2f
      # (security/pam-policy.nix) e traz a digital com 3 tentativas, os
      # destaques e o "Usar senha" do polkit, a chave de segurança e a sequência
      # digital → FIDO2 → senha na tela de bloqueio, e a página Segurança (com
      # o "Pedir o PIN junto com o toque", que a tela de bloqueio e o painel do
      # polkit atendem com um campo de PIN).
      #
      # O pinentry/askpass não é patch: os mantenedores não aceitam segredos no
      # core (PR #4951). É o plugin lbssousa/secret-prompts, com o auxiliar
      # noctalia-secret-prompts.
      #
      # Aqui, só o que é deste nix-config: os templates dos emuladores de
      # terminal remapeados de `.default` para `.dark` (sempre a variante
      # escura da paleta ativa, mesmo com [theme].mode = "auto"; os demais
      # templates seguem o modo global) e as ferramentas da página Segurança no
      # PATH. Reempacotar os assets (em vez de overrideAttrs/postInstall) evita
      # recompilar a Noctalia: basta copiar a saída já construída, ajustar os
      # templates e apontar NOCTALIA_ASSETS_DIR para a cópia.
      noctalia =
        let
          base = prev.noctalia;
        in
        final.runCommand "noctalia-${base.version}"
          {
            nativeBuildInputs = [ final.makeWrapper ];
            meta = base.meta // {
              mainProgram = "noctalia";
            };
            passthru = base.passthru or { };
          }
          ''
            mkdir -p $out
            cp -a ${base}/share $out/share
            chmod -R u+w $out/share

            for template in \
              alacritty/alacritty.toml \
              foot/foot \
              ghostty/ghostty \
              kitty/kitty.conf \
              wezterm/wezterm.toml
            do
              substituteInPlace "$out/share/noctalia/assets/templates/$template" \
                --replace-fail ".default." ".dark."
            done

            # Ferramentas da página Segurança no fim do PATH: as do usuário vêm antes.
            # O XDG_DATA_DIRS da sessão nem sempre chega à unit da Noctalia com
            # os exports do Flatpak (é onde vivem .desktop e ícones do Firefox).
            # --suffix preserva o valor existente e garante os ícones da dock.
            makeWrapper ${base}/bin/noctalia $out/bin/noctalia \
              --set-default NOCTALIA_ASSETS_DIR "$out/share/noctalia/assets" \
              --suffix XDG_DATA_DIRS : "/var/lib/flatpak/exports/share" \
              --suffix PATH : ${
                final.lib.makeBinPath [
                  final.libfido2
                  final.pam_u2f
                  final.openssh
                  final.gnupg
                ]
              }
          '';

      # pinentry-program do gpg-agent; fora da sessão gráfica cai no pinentry-curses.
      pinentry-noctalia =
        final.runCommand "pinentry-noctalia"
          {
            nativeBuildInputs = [ final.makeWrapper ];
            meta.mainProgram = "pinentry-noctalia";
          }
          ''
            makeWrapper ${final.noctalia-secret-prompts}/bin/noctalia-pinentry $out/bin/pinentry-noctalia \
              --set-default NOCTALIA_PINENTRY_FALLBACK ${final.pinentry-curses}/bin/pinentry-curses
          '';

      # SSH_ASKPASS (ssh, ssh-add e git); sem a shell, falha com status 1.
      noctalia-askpass = final.runCommand "noctalia-askpass" { meta.mainProgram = "noctalia-askpass"; } ''
        mkdir -p $out/bin
        ln -s ${final.noctalia-secret-prompts}/bin/noctalia-askpass $out/bin/noctalia-askpass
      '';
    };
in
{
  flake.overlays.default = overlay;

  # A família Noctalia do noctalia-nix primeiro; este overlay embrulha a
  # Noctalia dele e acrescenta os pacotes próprios.
  flake.modules.nixos.overlay = {
    nixpkgs.overlays = [
      inputs.noctalia-nix.overlays.default
      config.flake.overlays.default
    ];
    nixpkgs.config.allowUnfree = true;
  };

  perSystem =
    { pkgs, system, ... }:
    let
      pkgs' = import pkgs.path {
        inherit system;
        overlays = [
          inputs.noctalia-nix.overlays.default
          overlay
        ];
        config.allowUnfree = true;
      };
    in
    {
      packages = lib.genAttrs [
        "run0-sudo"
        "libfprint-goodix"
        "fprintd-goodix"
        "yubikey-gpg-import"
        "superwhisper"
        "greetd"
        "noctalia"
        "pinentry-noctalia"
        "noctalia-askpass"
      ] (n: pkgs'.${n});
    };
}

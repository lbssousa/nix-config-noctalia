# Pacotes próprios (modules/packages/_*/package.nix), expostos como
# packages.<system>.<nome> e pelo overlay aplicado a todos os hosts.
{ config, lib, ... }:
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
      flea = call ../packages/_flea/package.nix;

      # Senha expirada (pam_acct_mgmt: NEW_AUTHTOK_REQD) no login gráfico.
      # O greetd 0.10.3 só falhava; o patch chama pam_chauthtok na mesma
      # conversa, e os prompts (senha atual, nova, confirmação) chegam ao
      # greeter como auth_message. Patch local, sem PR upstream.
      greetd = prev.greetd.overrideAttrs (old: {
        patches = (old.patches or [ ]) ++ [ ../packages/patches/greetd-change-expired-authtok.patch ];
      });

      # Noctalia Greeter, dois patches (nesta ordem, ambos em greeter_surface.cpp):
      #  - nome completo na tela de login: PR aberto
      #    https://github.com/noctalia-dev/noctalia-greeter/pull/131
      #    ([appearance] show_real_names); remover quando chegar ao nixpkgs;
      #  - prompts PAM seguintes (troca de senha expirada) no placeholder do
      #    campo, sem apagar o aviso do PAM no status; patch local.
      noctalia-greeter = prev.noctalia-greeter.overrideAttrs (old: {
        patches = (old.patches or [ ]) ++ [
          ../packages/patches/noctalia-greeter-show-real-names.patch
          ../packages/patches/noctalia-greeter-pam-prompts.patch
        ];
      });
    };
in
{
  flake.overlays.default = overlay;

  flake.modules.nixos.overlay = {
    nixpkgs.overlays = [ config.flake.overlays.default ];
    nixpkgs.config.allowUnfree = true;
  };

  perSystem =
    { pkgs, system, ... }:
    let
      pkgs' = import pkgs.path {
        inherit system;
        overlays = [ overlay ];
        config.allowUnfree = true;
      };
    in
    {
      packages = lib.genAttrs [
        "run0-sudo"
        "libfprint-goodix"
        "fprintd-goodix"
        "yubikey-gpg-import"
        "flea"
        "greetd"
        "noctalia-greeter"
      ] (n: pkgs'.${n});
    };
}

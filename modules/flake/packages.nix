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

      # Nome completo do usuário na tela de login: patch do PR aberto
      # https://github.com/noctalia-dev/noctalia-greeter/pull/131
      # (adiciona [appearance] show_real_names). Remover quando o PR for
      # mergeado e chegar ao nixpkgs.
      noctalia-greeter = prev.noctalia-greeter.overrideAttrs (old: {
        patches = (old.patches or [ ]) ++ [ ../packages/patches/noctalia-greeter-show-real-names.patch ];
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
        "noctalia-greeter"
      ] (n: pkgs'.${n});
    };
}

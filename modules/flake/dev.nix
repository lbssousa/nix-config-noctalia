# Ferramentas de desenvolvimento do próprio repositório: formatter, devshell
# e checks. Os checks só AVALIAM cada host (drvPath sem contexto), para o
# `nix flake check` do CI não construir sistemas inteiros; o build completo
# é `just build <host>`.
{ config, lib, ... }:
{
  perSystem =
    { pkgs, ... }:
    {
      formatter = pkgs.nixfmt-tree;

      devShells.default = pkgs.mkShellNoCC {
        packages = with pkgs; [
          just
          nixfmt
          statix
          deadnix
          nvd
          sops
          age
          ssh-to-age
          secretspec
          bitwarden-cli
          keepassxc
          jq
        ];
      };

      checks = lib.mapAttrs' (
        name: nixos:
        lib.nameValuePair "eval-${name}" (
          pkgs.writeText "eval-${name}" (
            builtins.unsafeDiscardStringContext nixos.config.system.build.toplevel.drvPath
          )
        )
      ) config.flake.nixosConfigurations;
    };
}

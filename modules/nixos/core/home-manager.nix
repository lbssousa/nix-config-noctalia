# home-manager como módulo NixOS: todo usuário de config.my.users recebe todos
# os módulos HM (flake.modules.homeManager.*) e, por cima, o seu próprio
# módulo (my.users.<u>.home), que vence os valores lib.mkDefault da base.
# Features opcionais ficam atrás de opções my.<feature>.enable.
{ config, inputs, ... }:
let
  inherit (config.my) users;
  hm = config.flake.modules.homeManager;
in
{
  flake.modules.nixos.home-manager =
    { lib, ... }:
    {
      imports = [ inputs.home-manager.nixosModules.home-manager ];

      home-manager = {
        useGlobalPkgs = true;
        useUserPackages = true;
        backupFileExtension = "bkp";
        extraSpecialArgs = { inherit inputs; };
        sharedModules = [
          inputs.sops-nix.homeManagerModules.sops
          inputs.nixvim.homeModules.nixvim
        ]
        ++ lib.attrValues hm;
        users = lib.mapAttrs (_: u: u.home) users;
      };
    };
}

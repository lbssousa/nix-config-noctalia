# Inventário de hosts e usuários, e a geração de nixosConfigurations.
#
# Cada host declara em modules/hosts/<host>/ os módulos NixOS que compõe;
# cada usuário declara em modules/users/<usuario>.nix seu UID, sudo e o módulo
# home-manager próprio. Nenhuma lista central precisa ser editada: o
# import-tree carrega os arquivos novos automaticamente.
{
  config,
  inputs,
  lib,
  self,
  ...
}:
let
  inherit (lib) mkOption types;
in
{
  options.my = {
    hosts = mkOption {
      description = "Hosts NixOS gerados como nixosConfigurations.<nome>.";
      default = { };
      type = types.attrsOf (
        types.submodule {
          options = {
            system = mkOption {
              type = types.str;
              default = "x86_64-linux";
            };
            modules = mkOption {
              type = types.listOf types.deferredModule;
              default = [ ];
              description = "Módulos NixOS do host (features + hardware).";
            };
          };
        }
      );
    };

    users = mkOption {
      description = "Usuários criados em todos os hosts, com home-manager.";
      default = { };
      type = types.attrsOf (
        types.submodule {
          options = {
            uid = mkOption {
              type = types.int;
              description = "UID fixo (evita reatribuição ao adicionar/remover usuários).";
            };
            sudo = mkOption {
              type = types.bool;
              default = false;
              description = "Membro do grupo wheel.";
            };
            home = mkOption {
              type = types.deferredModule;
              default = { };
              description = "Overrides home-manager declarativos deste usuário.";
            };
          };
        }
      );
    };
  };

  config.flake.nixosConfigurations = lib.mapAttrs (
    name: host:
    inputs.nixpkgs.lib.nixosSystem {
      specialArgs = { inherit inputs self; };
      modules = [
        {
          networking.hostName = name;
          nixpkgs.hostPlatform = host.system;
        }
      ]
      ++ host.modules;
    }
  ) config.my.hosts;
}

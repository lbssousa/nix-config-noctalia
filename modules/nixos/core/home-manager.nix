# home-manager: todo usuário de config.my.users recebe todos os módulos HM
# (flake.modules.homeManager.*) e, por cima, o seu próprio módulo
# (my.users.<u>.home), que vence os valores lib.mkDefault da base. Features
# opcionais ficam atrás de opções my.<feature>.enable.
#
# Dois modos, por usuário (my.users.<u>.standaloneHome):
#   - módulo NixOS (padrão): o nixos-rebuild ativa o home-manager do usuário;
#   - standalone: o NixOS só avalia a configuração (mesmo pkgs, osConfig =
#     config do host) e a publica em homeConfigurations."<u>@<host>"; quem a
#     ativa é o próprio usuário, sem run0 (`just home switch`, alias hms).
#     No primeiro boot (instalação nova, sem perfil do home-manager), um
#     serviço do sistema faz a primeira ativação antes do greeter.
# my.homes reúne a configuração HM de todos, nos dois modos, para os módulos
# NixOS que consultam opções dos usuários (ex.: my.dropbox.enable).
{ config, inputs, ... }:
let
  inherit (config.my) users;
  hmModules = builtins.attrValues config.flake.modules.homeManager;
in
{
  flake = {
    modules.homeManager.standalone =
      { lib, ... }:
      {
        options.my.standaloneHome = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Este perfil é ativado pelo home-manager standalone (homeConfigurations).";
        };
      };

    modules.nixos.home-manager =
      {
        config,
        lib,
        pkgs,
        ...
      }:
      let
        sharedModules = [
          inputs.sops-nix.homeManagerModules.sops
          inputs.nixvim.homeModules.nixvim
        ]
        ++ hmModules;
        nixosUsers = lib.filterAttrs (_: u: !u.standaloneHome) users;
        standaloneUsers = lib.filterAttrs (_: u: u.standaloneHome) users;
      in
      {
        imports = [ inputs.home-manager.nixosModules.home-manager ];

        options.my = {
          homeConfigurations = lib.mkOption {
            type = lib.types.lazyAttrsOf lib.types.raw;
            readOnly = true;
            internal = true;
            description = "Configurações home-manager standalone deste host, por usuário.";
          };
          homes = lib.mkOption {
            type = lib.types.lazyAttrsOf lib.types.raw;
            readOnly = true;
            internal = true;
            description = "Configuração HM (config) de cada usuário, standalone ou não.";
          };
        };

        config = {
          home-manager = {
            useGlobalPkgs = true;
            useUserPackages = true;
            backupFileExtension = "bkp";
            extraSpecialArgs = { inherit inputs; };
            inherit sharedModules;
            users = lib.mapAttrs (_: u: u.home) nixosUsers;
          };

          my.homeConfigurations = lib.mapAttrs (
            name: u:
            inputs.home-manager.lib.homeManagerConfiguration {
              inherit pkgs;
              extraSpecialArgs = {
                inherit inputs;
                osConfig = config;
              };
              modules = sharedModules ++ [
                u.home
                {
                  home.username = name;
                  home.homeDirectory = config.users.users.${name}.home;
                  my.standaloneHome = true;
                  # O comando home-manager da mesma revisão do input.
                  programs.home-manager.enable = true;
                }
              ];
            }
          ) standaloneUsers;

          my.homes = config.home-manager.users // lib.mapAttrs (_: h: h.config) config.my.homeConfigurations;

          # Primeira ativação dos usuários standalone, só enquanto não há perfil
          # do home-manager (instalação nova): a sessão gráfica depende dos
          # arquivos do HM (Umbriel, Noctalia). Depois, quem ativa é o usuário.
          systemd.services = lib.mapAttrs' (
            name: hc:
            lib.nameValuePair "home-manager-bootstrap-${name}" {
              description = "Primeira ativação do home-manager standalone de ${name}";
              wantedBy = [ "multi-user.target" ];
              before = [ "display-manager.service" ];
              wants = [ "nix-daemon.socket" ];
              after = [ "nix-daemon.socket" ];
              unitConfig.ConditionPathExists = "!${hc.config.home.homeDirectory}/.local/state/nix/profiles/home-manager";
              environment.HOME_MANAGER_BACKUP_EXT = "bkp";
              serviceConfig = {
                Type = "oneshot";
                User = name;
                ExecStart = "${hc.activationPackage}/activate";
              };
            }
          ) config.my.homeConfigurations;
        };
      };

    # homeConfigurations."<usuário>@<host>": o nome que `home-manager switch
    # --flake` procura primeiro.
    homeConfigurations = builtins.foldl' (
      acc: host:
      let
        homes = config.flake.nixosConfigurations.${host}.config.my.homeConfigurations or { };
      in
      acc
      // builtins.listToAttrs (
        map (u: {
          name = "${u}@${host}";
          value = homes.${u};
        }) (builtins.attrNames homes)
      )
    ) { } (builtins.attrNames config.flake.nixosConfigurations);
  };
}

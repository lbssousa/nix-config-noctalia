{
  description = "NixOS com Umbriel + Noctalia, inspirado no Omarchy (btrfs, root efêmero, Secure Boot, TPM2)";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    # Composição dendritica: todo arquivo em ./modules é um módulo flake-parts,
    # carregado automaticamente pelo import-tree (arquivos/pastas com prefixo
    # "_" são ignorados e servem para dados e helpers).
    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };
    import-tree.url = "github:denful/import-tree";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    preservation.url = "github:nix-community/preservation";

    # Flatpaks declarativos (Flathub): a forma preferida para os aplicativos
    # gráficos de usuário.
    nix-flatpak.url = "github:gmodena/nix-flatpak/?ref=v0.7.0";

    sops-nix = {
      url = "github:mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixvim = {
      url = "github:nix-community/nixvim";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Repositórios de plugins da Noctalia, fixados no flake.lock e expostos à
    # shell como fontes "path" (somente leitura, sem git em tempo de execução).
    noctalia-plugins-official = {
      url = "github:noctalia-dev/official-plugins";
      flake = false;
    };
    noctalia-plugins-community = {
      url = "github:noctalia-dev/community-plugins";
      flake = false;
    };

    # Segredos (sops/age) e dados não-sensíveis (outputs do flake).
    nix-secrets = {
      url = "git+ssh://git@github.com/lbssousa/nix-secrets?shallow=1";
      flake = true;
    };
  };

  outputs = inputs: inputs.flake-parts.lib.mkFlake { inherit inputs; } (inputs.import-tree ./modules);
}

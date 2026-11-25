{
  description = "NixOS com Umbriel + Noctalia, inspirado no Omarchy (btrfs, root efêmero, Secure Boot, TPM2)";

  inputs = {
    # Família Noctalia (Noctalia, greeter, Umbriel, Luciole, secret-prompts)
    # com os patches dos forks de lbssousa, compilada e publicada no Cachix
    # lbssousa-noctalia pelo CI diário do próprio flake
    # (github.com/lbssousa/noctalia-nix).
    noctalia-nix.url = "github:lbssousa/noctalia-nix";
    # O nixpkgs do sistema é o do noctalia-nix: só avança para revisões que o
    # CI dele já compilou, e as derivações da família Noctalia batem com as
    # do cache (nada de compilação local).
    nixpkgs.follows = "noctalia-nix/nixpkgs";

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

    # Flatpaks declarativos (Flathub e o remoto OCI do ArtCraft): desktop/flatpak.nix.
    nix-flatpak.url = "github:gmodena/nix-flatpak/v0.8.0";

    # Secure Boot: systemd-boot com UKIs assinados (security/secureboot.nix).
    lanzaboote = {
      url = "github:nix-community/lanzaboote/v1.2.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };

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
    # Plugin próprio: a mesma revisão cujo auxiliar o noctalia-nix compila.
    noctalia-secret-prompts.follows = "noctalia-nix/noctalia-secret-prompts";

    # Templates de tema da comunidade Noctalia (Brave), fixados no flake.lock
    # e usados como templates de usuário (sem rede em tempo de execução).
    noctalia-templates-community = {
      url = "github:noctalia-dev/community-templates";
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

# Shells: fish (padrão de todos os usuários) e bash, com as ferramentas do
# Omarchy (eza, bat, zoxide, fzf, direnv).
#
# Override local: ~/.config/fish/conf.d/*.fish do usuário (lidos
# automaticamente) e ~/.config/fish/local.fish (carregado por último).
{
  flake.modules.homeManager.shell =
    { lib, pkgs, ... }:
    let
      aliases = {
        ls = "eza";
        ll = "eza -la";
        lt = "eza --tree";
        cat = "bat";
        g = "git";
        gs = "git status";
        ga = "git add";
        gc = "git commit";
        gp = "git push";
        gl = "git pull";
        lg = "lazygit";
        dk = "podman";
        dkc = "podman-compose";
        # O nixos-rebuild avalia o flake como o próprio usuário (que alcança o
        # nix-secrets pelo agente SSH do Bitwarden) e só a ativação usa sudo.
        # /etc/nixos é um espelho git: `nsync` o atualiza antes de reconstruir.
        nsync = "just sync";
        nrs = "nixos-rebuild switch --sudo --flake /etc/nixos";
        nrb = "nixos-rebuild boot --sudo --flake /etc/nixos";
        nrt = "nixos-rebuild test --sudo --flake /etc/nixos";
        nrd = "nixos-rebuild dry-activate --flake /etc/nixos";
        nrB = "nixos-rebuild build --flake /etc/nixos";
        nrr = "nixos-rebuild switch --sudo --rollback";
        nru = "just sync && nixos-rebuild switch --sudo --flake /etc/nixos";
        nfc = "nix flake check /etc/nixos";
        nfs = "nix flake show /etc/nixos";
        ngl = "nixos-rebuild list-generations";
        ngc = "sudo nix-collect-garbage --delete-older-than 30d";
      };
    in
    {
      home = {
        stateVersion = "26.05";
        packages = with pkgs; [
          run0-sudo
          grc
        ];
        sessionVariables = {
          EDITOR = lib.mkDefault "nvim";
          VISUAL = lib.mkDefault "nvim";
          BROWSER = lib.mkDefault "firefox";
        };
      };

      programs = {
        fish = {
          enable = true;
          shellAliases = aliases;
          interactiveShellInit = lib.mkAfter ''
            set -g fish_greeting
            if test -f ~/.config/fish/local.fish
              source ~/.config/fish/local.fish
            end
          '';
          plugins =
            map
              (name: {
                inherit name;
                inherit (pkgs.fishPlugins.${name}) src;
              })
              [
                "autopair"
                "forgit"
                "grc"
              ];
        };

        bash = {
          enable = true;
          historyControl = [ "ignoredups" ];
          shellAliases = aliases;
          initExtra = lib.mkAfter ''
            [ -f ~/.config/bash/local.sh ] && . ~/.config/bash/local.sh
          '';
        };

        zoxide.enable = true;
        fzf.enable = true;
        bat.enable = true;
        eza = {
          enable = true;
          icons = "auto";
          git = true;
        };
        direnv = {
          enable = true;
          nix-direnv.enable = true;
        };
      };
    };
}

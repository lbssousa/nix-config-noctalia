# Shells: fish (padrão de todos os usuários) e bash, com as ferramentas do
# Omarchy (eza, bat, zoxide, fzf, direnv).
#
# Override local: ~/.config/fish/conf.d/*.fish do usuário (lidos
# automaticamente) e ~/.config/fish/local.fish (carregado por último).
{
  flake.modules.homeManager.shell =
    { lib, pkgs, ... }:
    let
      # Sempre o justfile do espelho: dentro de um projeto com justfile próprio
      # (o clone de trabalho, por exemplo) o wrapper do just usaria o local.
      sysJust = "just --justfile /etc/nixos/justfile";
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
        # O sistema é reconstruído a partir do espelho /etc/nixos (`nsync` o
        # atualiza); o flake é avaliado pelo próprio usuário (que alcança o
        # nix-secrets pelo agente SSH do Bitwarden) e só a ativação usa run0.
        nsync = "${sysJust} sync";
        nrs = "${sysJust} switch";
        nrb = "${sysJust} boot";
        nrt = "${sysJust} test";
        nrB = "${sysJust} build";
        nrd = "${sysJust} diff";
        nru = "${sysJust} upgrade";
        nrr = "nixos-rebuild switch --elevate run0 --rollback";
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

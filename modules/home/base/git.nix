# Git comum a todos. Override local: ~/.config/git/local (incluído por último).
{
  flake.modules.homeManager.git = {
    programs.git = {
      enable = true;
      settings = {
        init.defaultBranch = "main";
        pull.rebase = true;
        rebase.autostash = true;
        core.editor = "nvim";
      };
      includes = [ { path = "~/.config/git/local"; } ];
    };
    programs.lazygit.enable = true;
  };
}

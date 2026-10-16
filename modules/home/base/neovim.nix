# Neovim simples para todos (o nixvim completo é opcional: my.nixvim.enable).
{
  flake.modules.homeManager.neovim =
    { config, lib, ... }:
    {
      programs.neovim = lib.mkIf (!config.my.nixvim.enable) {
        enable = true;
        defaultEditor = true;
        viAlias = true;
        vimAlias = true;
        withRuby = false;
        withPython3 = false;
        extraConfig = ''
          set number relativenumber expandtab tabstop=2 shiftwidth=2 smartindent
          set termguicolors clipboard=unnamedplus
          silent! source ~/.config/nvim/local.vim
        '';
      };
    };
}

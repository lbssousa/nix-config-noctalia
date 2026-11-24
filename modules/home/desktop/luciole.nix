# Luciole: cores da Noctalia. O template que vem no pacote
# (share/luciole/templates/colors.toml) grava a paleta ativa em
# ~/.config/luciole/colors.toml, que o Luciole relê assim que muda.
#
# Pastas, FileManager1 e o portal FileChooser vêm do sistema
# (nixos/desktop/file-manager.nix). As preferências feitas na interface ficam
# em ~/.config/luciole/settings.toml, gravável e fora do Nix.
{
  flake.modules.homeManager.luciole =
    { config, pkgs, ... }:
    {
      programs.noctalia.settings.theme.templates.user.luciole = {
        input_path = "${pkgs.luciole}/share/luciole/templates/colors.toml";
        output_path = "${config.xdg.configHome}/luciole/colors.toml";
        pre_hook = "mkdir -p '${config.xdg.configHome}/luciole'";
      };
    };
}

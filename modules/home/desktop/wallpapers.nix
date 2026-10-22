# Wallpapers importados do Omarchy (famílias Bluefin e Omadwaita).
# Disponibilizados em ~/Imagens/Wallpapers para os usuários.
_: {
  flake.modules.homeManager.wallpapers =
    { config, lib, ... }:
    let
      picturesRel =
        if lib.hasPrefix "${config.home.homeDirectory}/" config.xdg.userDirs.pictures then
          lib.removePrefix "${config.home.homeDirectory}/" config.xdg.userDirs.pictures
        else
          "Imagens";
    in
    {
      home.file."${picturesRel}/Wallpapers" = {
        source = ../../../assets/wallpapers;
        recursive = true;
      };
    };
}

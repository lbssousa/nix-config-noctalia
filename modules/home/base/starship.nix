# Prompt do Omarchy (_omarchy-starship.toml, copiado do Omarchy, licença MIT).
# Override local: ~/.config/starship.toml.local (ver home/lib/mutable-config.nix).
{
  flake.modules.homeManager.starship =
    { lib, ... }:
    {
      programs.starship.enable = true;
      my.mutableConfigs."starship.toml".base = lib.mkDefault (lib.importTOML ./_omarchy-starship.toml);
    };
}

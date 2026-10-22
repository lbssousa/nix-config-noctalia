# Prompt do Omarchy (_omarchy-starship.toml, copiado do Omarchy, licença MIT),
# acrescido de um badge "❄ dev" no início quando há uma dev shell do Nix ativa
# (nix develop, nix-shell ou direnv com `use flake`, que exportam IN_NIX_SHELL).
# Override local: ~/.config/starship.toml.local (ver home/lib/mutable-config.nix).
{
  flake.modules.homeManager.starship =
    { lib, ... }:
    let
      omarchy = lib.importTOML ./_omarchy-starship.toml;
    in
    {
      programs.starship.enable = true;
      my.mutableConfigs."starship.toml".base = lib.mkDefault (
        omarchy
        // {
          format = "$nix_shell" + omarchy.format;
          nix_shell = {
            format = "[ ❄ $state ]($style) ";
            style = "bold fg:black bg:cyan";
            impure_msg = "dev";
            pure_msg = "dev pure";
            unknown_msg = "dev";
          };
        }
      );
    };
}

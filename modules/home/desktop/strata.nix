# Strata: gerenciador de arquivos GTK4 (packages/_strata).
# Configuração base gravada em ~/.config/strata/settings.toml via mutable-config.
# Override local: ~/.config/strata/settings.toml.local (ver home/lib/mutable-config.nix).
{
  flake.modules.homeManager.strata =
    { lib, ... }:
    {
      my.mutableConfigs."strata/settings.toml" = {
        format = "toml";
        base = {
          interface_font = lib.mkDefault "Adwaita Sans";
          text_size = lib.mkDefault 18;
          # Tema fixo (sem "Follow Omarchy"), escuro como a shell.
          mode = lib.mkDefault "theme";
          theme = lib.mkDefault "nord";
        };
      };
    };
}

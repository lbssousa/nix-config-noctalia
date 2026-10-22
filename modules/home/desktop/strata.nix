# Strata: gerenciador de arquivos GTK4 (packages/_strata).
# Configuração base gravada em ~/.config/strata/settings.toml via mutable-config.
# Override local: ~/.config/strata/settings.toml.local (ver home/lib/mutable-config.nix).
#
# Tema Nord/Nord Light acompanhando o modo claro/escuro da Noctalia: o Strata
# usa o tema próprio "nord-auto" (~/.config/strata/themes/nord-auto.toml), que
# os hooks started e theme_mode_changed da Noctalia regravam com a paleta Nord
# ou Nord Light. O Strata observa a pasta de temas e reaplica as cores nas
# janelas abertas, sem reiniciar (docs/themes.md, "Live updates").
{
  flake.modules.homeManager.strata =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      toml = pkgs.formats.toml { };

      # Cópias das entradas "nord" e "nord-light" de data/themes/catalog.toml.
      palettes = {
        dark = toml.generate "strata-nord.toml" {
          name = "Nord (claro/escuro)";
          background = "#2E3440";
          surface = "#3B4252";
          text = "#E5E9F0";
          accent = "#81A1C1";
          danger = "#BF616A";
          muted = "#434C5E";
          highlight = "#434C5E";
          border = "#4C566A";
          dim_text = "#D8DEE9";
          syntax_keyword = "#b48ead";
          syntax_string = "#a3be8c";
          syntax_constant = "#d08770";
          syntax_type = "#ebcb8b";
          syntax_preprocessor = "#88c0d0";
        };
        light = toml.generate "strata-nord-light.toml" {
          name = "Nord (claro/escuro)";
          background = "#e5e9f0";
          surface = "#c2d0e7";
          text = "#2e3440";
          accent = "#3b6ea8";
          danger = "#99324b";
          muted = "#b8c5db";
          highlight = "#b8c5db";
          border = "#aebacf";
          dim_text = "#60728c";
          syntax_keyword = "#97365b";
          syntax_string = "#4f894c";
          syntax_constant = "#ac4426";
          syntax_type = "#9a7500";
          syntax_preprocessor = "#398eac";
        };
      };

      themesDir = "${config.xdg.configHome}/strata/themes";

      # Troca o arquivo de uma vez (mv na mesma pasta), para o Strata nunca ler
      # um TOML pela metade; o temporário não termina em .toml e é ignorado.
      themeSync = pkgs.writeShellScript "strata-theme-sync" ''
        set -euo pipefail

        mode="''${NOCTALIA_THEME_MODE:-}"
        if [ -z "$mode" ]; then
          mode=$(${pkgs.noctalia}/bin/noctalia msg theme-mode-get 2>/dev/null || true)
          mode="''${mode//$'\n'/}"
        fi

        case "$mode" in
          light) src=${palettes.light} ;;
          *) src=${palettes.dark} ;;
        esac

        dir=${lib.escapeShellArg themesDir}
        target="$dir/nord-auto.toml"
        mkdir -p "$dir"
        if ! ${pkgs.diffutils}/bin/cmp -s "$src" "$target"; then
          install -m644 "$src" "$dir/.nord-auto.tmp"
          mv -f "$dir/.nord-auto.tmp" "$target"
        fi
      '';
    in
    {
      my.mutableConfigs."strata/settings.toml" = {
        format = "toml";
        base = {
          interface_font = lib.mkDefault "Adwaita Sans";
          text_size = lib.mkDefault 18;
          # Tema fixo (sem "Follow Omarchy") apontando para o nord-auto.
          mode = lib.mkDefault "theme";
          theme = lib.mkDefault "nord-auto";
        };
      };

      programs.noctalia.settings.hooks = {
        started = [ "${themeSync}" ];
        theme_mode_changed = [ "${themeSync}" ];
      };

      # Antes da Noctalia rodar o hook pela primeira vez, o tema já existe
      # (escuro), para o Strata não cair no tema padrão ao não achá-lo.
      home.activation.strataNordTheme = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        if [ ! -e ${lib.escapeShellArg "${themesDir}/nord-auto.toml"} ]; then
          run mkdir -p ${lib.escapeShellArg themesDir}
          run install -m644 ${palettes.dark} ${lib.escapeShellArg "${themesDir}/nord-auto.toml"}
        fi
      '';
    };
}

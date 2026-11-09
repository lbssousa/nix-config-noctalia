# btop com o tema da Noctalia (template "btop" em noctalia.nix).
#
# O template grava ~/.config/btop/themes/noctalia.theme, mas o script de apply
# só escolhe o tema num btop.conf que já exista, e o btop só cria o seu ao
# sair. Por isso cada switch garante o arquivo, que continua editável (o btop
# grava nele as próprias configurações), e acerta duas chaves:
#  - color_theme = "noctalia";
#  - theme_background: False no modo glassy (my.umbriel.transparency), para o
#    btop não pintar o fundo por cima do vidro do terminal, como o main_bg
#    vazio do omarchy-theme-set-glass do Omarchy 4.5; True nos outros modos.
{
  flake.modules.homeManager.btop =
    { config, lib, ... }:
    let
      glassy = config.my.umbriel.transparency == "glassy";
    in
    {
      home.activation.btopNoctaliaTheme = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        btop_conf=${lib.escapeShellArg "${config.xdg.configHome}/btop/btop.conf"}
        run mkdir -p "$(dirname "$btop_conf")"
        [ -e "$btop_conf" ] || run touch "$btop_conf"

        btop_set() {
          if grep -qsE "^$1[[:space:]]*=" "$btop_conf"; then
            run sed -i -E "s|^$1[[:space:]]*=.*|$1 = $2|" "$btop_conf"
          else
            run sh -c 'printf "%s = %s\n" "$1" "$2" >>"$3"' _ "$1" "$2" "$btop_conf"
          fi
        }
        btop_set color_theme '"noctalia"'
        btop_set theme_background ${if glassy then "False" else "True"}
      '';
    };
}

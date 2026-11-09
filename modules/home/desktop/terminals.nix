# Terminais com os padrões do Omarchy. As cores vêm dos templates de tema da
# Noctalia (themes/noctalia*), sempre na variante escura da paleta ativa: os
# templates de alacritty, foot, ghostty, kitty, starship e wezterm são remapeados
# de `.default` para `.dark` no pacote Noctalia (flake/packages.nix).
#
# Os arquivos gerados aqui já contêm as linhas que os scripts de "apply" dos
# templates acrescentariam, então esses scripts não tentam reescrevê-los
# (são somente leitura, na store). O ajuste local do usuário vai em:
#   ~/.config/ghostty/local   ~/.config/kitty/local.conf   ~/.config/foot/local.ini
#
# No modo glassy (my.umbriel.transparency, umbriel.nix) o fundo fica a 0.65,
# como o omarchy-theme-set-glass do Omarchy 4.5 faz nos temas: no próprio
# terminal, e não pela opacidade da janela, para o texto continuar nítido. O
# blur por trás vem das regras de janela do Umbriel.
{
  flake.modules.homeManager.terminals =
    { config, lib, ... }:
    let
      glassy = config.my.umbriel.transparency == "glassy";
    in
    {
      xdg.configFile = {
        "ghostty/config".text = ''
          theme = noctalia

          font-family = "JetBrainsMono Nerd Font Mono"
          font-style = Regular
          font-size = 14

          window-theme = ghostty
          window-padding-x = 14
          window-padding-y = 14
          confirm-close-surface = false
          resize-overlay = never
          gtk-toolbar-style = flat
          quit-after-last-window-closed = true
          auto-update = off

          cursor-style = block
          cursor-style-blink = false
          shell-integration-features = no-cursor,ssh-env

          keybind = shift+insert=paste_from_clipboard
          keybind = control+insert=copy_to_clipboard
          keybind = shift+enter=csi:13;2u
          keybind = alt+shift+enter=csi:13;4u
          mouse-scroll-multiplier = 0.95
        ''
        + lib.optionalString glassy ''

          background-opacity = 0.65
        ''
        + ''

          config-file = ?local
        '';

        "kitty/kitty.conf".text = ''
          include themes/noctalia.conf
          font_family JetBrainsMono Nerd Font Mono
          font_size 14
          window_padding_width 14
          hide_window_decorations yes
          confirm_os_window_close 0
          enable_audio_bell no
        ''
        + lib.optionalString glassy ''
          background_opacity 0.65
        ''
        + ''
          globinclude local.conf
        '';

        "foot/foot.ini".text = ''
          [main]
          include=~/.config/foot/themes/noctalia
          term=xterm-256color
          font=JetBrainsMono Nerd Font Mono:size=14
          pad=14x14
          initial-window-mode=windowed
          workers=0
          include=~/.config/foot/local.ini

          [scrollback]
          lines=10000
          multiplier=7.0

          [cursor]
          style=block
          blink=no

          [key-bindings]
          clipboard-copy=Control+Insert Control+Shift+c XF86Copy
          primary-paste=none
          clipboard-paste=Shift+Insert Control+Shift+v XF86Paste

          [text-bindings]
          \x1b[13;2u=Shift+Return
          \x1b[13;4u=Mod1+Shift+Return
        ''
        # Mesma seção do tema da Noctalia; sem blur=yes o foot pede ao
        # compositor para não desfocar o fundo.
        + lib.optionalString glassy ''

          [colors-dark]
          alpha=0.65
          blur=yes
        '';
      };
    };
}

# Terminais com os padrões do Omarchy. As cores vêm dos templates de tema da
# Noctalia (themes/noctalia*), que acompanham a paleta ativa.
#
# Os arquivos gerados aqui já contêm as linhas que os scripts de "apply" dos
# templates acrescentariam, então esses scripts não tentam reescrevê-los
# (são somente leitura, na store). O ajuste local do usuário vai em:
#   ~/.config/ghostty/local   ~/.config/kitty/local.conf   ~/.config/foot/local.ini
{
  flake.modules.homeManager.terminals = {
    xdg.configFile = {
      "ghostty/config".text = ''
        theme = noctalia

        font-family = "JetBrainsMono Nerd Font"
        font-style = Regular
        font-size = 11

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

        config-file = ?local
      '';

      "kitty/kitty.conf".text = ''
        include themes/noctalia.conf
        font_family JetBrainsMono Nerd Font
        font_size 11
        window_padding_width 14
        hide_window_decorations yes
        confirm_os_window_close 0
        enable_audio_bell no
        globinclude local.conf
      '';

      "foot/foot.ini".text = ''
        [main]
        include=~/.config/foot/themes/noctalia
        term=xterm-256color
        font=JetBrainsMono Nerd Font:size=11
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
      '';
    };
  };
}

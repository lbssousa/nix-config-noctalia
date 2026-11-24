# Correção dos lançadores das PWAs do Brave em Flatpak (bug aberto no
# upstream: brave/brave-browser#60360, #50698; flathub/com.brave.Browser#894).
#
# No Wayland, o .desktop que o Brave em Flatpak grava para cada PWA
# (~/.local/share/applications/brave-<appid>-<perfil>.desktop):
#  - tem StartupWMClass=crx_<appid>, mas o app_id da janela é
#    brave-<appid>-<perfil>: a janela não é ligada ao lançador e aparece com
#    o ícone do Brave;
#  - aponta Icon= para um PNG em ~/.var/app/com.brave.Browser/data/icons que
#    o Brave nunca grava.
# O brave-pwa-fix acerta o StartupWMClass e instala os ícones que o próprio
# Brave guarda no perfil (Web Applications/Manifest Resources/<appid>/Icons)
# no tema do usuário, trocando Icon= pelo nome brave-<appid>-<perfil>. Só
# regrava o que mudou, então rodar de novo não altera nada.
#
# Roda sozinho quando o Brave grava um lançador ou um ícone (brave-pwa-fix.path)
# e no login (o Brave regrava os lançadores ao atualizar). `brave-pwa-fix
# --dry-run` mostra o que mudaria. Sai quando o upstream corrigir.
{
  flake.modules.homeManager.brave-pwa-fix =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      braveProfiles = "${config.home.homeDirectory}/.var/app/com.brave.Browser/config/BraveSoftware/Brave-Browser";

      fix = pkgs.writeShellApplication {
        name = "brave-pwa-fix";
        runtimeInputs = [
          pkgs.coreutils
          pkgs.desktop-file-utils
          pkgs.diffutils
          pkgs.gnugrep
          pkgs.gnused
        ];
        text = ''
          dry=false
          [[ ''${1:-} == --dry-run ]] && dry=true

          apps="''${XDG_DATA_HOME:-$HOME/.local/share}/applications"
          icons="''${XDG_DATA_HOME:-$HOME/.local/share}/icons/hicolor"
          profiles="$HOME/.var/app/com.brave.Browser/config/BraveSoftware/Brave-Browser"

          shopt -s nullglob
          for desktop in "$apps"/brave-*-*.desktop; do
            name=$(basename "$desktop" .desktop)
            # brave-<appid de 32 letras a-p>-<perfil>
            [[ $name =~ ^brave-([a-p]{32})-(.+)$ ]] || continue
            appid=''${BASH_REMATCH[1]}
            profile=''${BASH_REMATCH[2]}
            grep -q '^Exec=.*com\.brave\.Browser' "$desktop" || continue

            # "Profile_1" no nome do lançador é o diretório "Profile 1".
            res="$profiles/''${profile//_/ }/Web Applications/Manifest Resources/$appid/Icons"
            wantIcon=$(sed -n 's/^Icon=//p' "$desktop" | head -n1)
            pngs=("$res"/*.png)
            if ((''${#pngs[@]} > 0)); then
              wantIcon=$name
              for png in "''${pngs[@]}"; do
                size=$(basename "$png" .png)
                [[ $size =~ ^[0-9]+$ ]] || continue
                dest="$icons/''${size}x''${size}/apps/$name.png"
                if ! cmp -s "$png" "$dest"; then
                  echo "ícone: $dest"
                  $dry || install -Dm644 "$png" "$dest"
                fi
              done
            fi

            # Oculto e com .desktop (exigido pelo desktop-file-edit), no mesmo
            # diretório para o mv ser atômico.
            tmp=$(mktemp -p "$apps" --suffix=.desktop .brave-pwa-fix-XXXXXX)
            cp "$desktop" "$tmp"
            desktop-file-edit --set-key=StartupWMClass --set-value="$name" \
              --set-key=Icon --set-value="$wantIcon" "$tmp"
            if cmp -s "$desktop" "$tmp"; then
              rm -f "$tmp"
            elif $dry; then
              echo "lançador: $desktop"
              diff "$desktop" "$tmp" | sed 's/^/  /' || true
              rm -f "$tmp"
            else
              echo "lançador: $desktop"
              chmod --reference="$desktop" "$tmp"
              mv "$tmp" "$desktop"
            fi
          done
        '';
      };
    in
    {
      home.packages = [ fix ];

      systemd.user = {
        services.brave-pwa-fix = {
          Unit.Description = "Corrige os lançadores das PWAs do Brave (Flatpak)";
          Service = {
            Type = "oneshot";
            # O Brave grava o lançador e os ícones em rajada.
            ExecStartPre = "${pkgs.coreutils}/bin/sleep 2";
            ExecStart = lib.getExe fix;
          };
          Install.WantedBy = [ "graphical-session.target" ];
        };

        paths.brave-pwa-fix = {
          Unit.Description = "Lançadores e ícones novos das PWAs do Brave";
          Path = {
            PathChanged = [
              "%h/.local/share/applications"
              "${braveProfiles}/Default/Web Applications/Manifest Resources"
            ];
            TriggerLimitIntervalSec = "10s";
            TriggerLimitBurst = 5;
          };
          Install.WantedBy = [ "default.target" ];
        };
      };
    };
}

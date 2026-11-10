# Chrome de cada usuário: o comando `webapp <id>` e, para o dono da paleta
# (my.chrome.themeOwner), as cores da Noctalia no Chrome.
#
# Os web apps (my.webapps, nixos/desktop/google-chrome.nix) são instalados
# pelo próprio Chrome como PWAs (WebAppInstallForceList), que cria o lançador
# ~/.local/share/applications/chrome-<app-id>-Default.desktop com o nome
# declarado. `webapp <id>` abre esse lançador; antes de a PWA existir (o Chrome
# ainda não abriu, ou estava sem rede), abre a URL numa janela de app.
#
# Cores: template de usuário com o color.json do "chromium-based" da
# comunidade, gravado direto no arquivo de política que o tmpfiles do sistema
# prepara para este usuário; o post_hook faz o Chrome aberto reler as
# políticas, como o apply.sh do template (sem o pkexec dele).
{ inputs, ... }:
{
  flake.modules.homeManager.webapps =
    {
      config,
      lib,
      osConfig,
      pkgs,
      ...
    }:
    let
      inherit (osConfig.my) webapps;
      chrome = "google-chrome-stable";
      # id<TAB>nome<TAB>url, uma linha por web app.
      table = pkgs.writeText "webapps.tsv" (
        lib.concatMapStrings (id: "${id}\t${webapps.${id}.name}\t${webapps.${id}.url}\n") (
          lib.attrNames webapps
        )
      );

      webapp = pkgs.writeShellApplication {
        name = "webapp";
        runtimeInputs = [
          pkgs.gtk3
          pkgs.gawk
          pkgs.gnugrep
          pkgs.coreutils
        ];
        text = ''
          ids="${lib.concatStringsSep " " (lib.attrNames webapps)}"
          if [ $# -ne 1 ]; then
            echo "Uso: webapp <id>   (ids: $ids)" >&2
            exit 1
          fi
          line="$(awk -F '\t' -v id="$1" '$1 == id' ${table})"
          if [ -z "$line" ]; then
            echo "webapp: id desconhecido: $1 (ids: $ids)" >&2
            exit 1
          fi
          IFS=$'\t' read -r _ name url <<< "$line"
          apps="''${XDG_DATA_HOME:-$HOME/.local/share}/applications"
          for f in "$apps"/chrome-*-Default.desktop; do
            [ -e "$f" ] || continue
            if grep -qxF "Name=$name" "$f" && grep -q -- '--app-id=' "$f"; then
              exec gtk-launch "$(basename "$f" .desktop)"
            fi
          done
          exec ${chrome} --app="$url"
        '';
      };
    in
    {
      home.packages = [ webapp ];

      programs.noctalia.settings.theme.templates.user.chrome =
        lib.mkIf (osConfig.my.chrome.themeOwner == config.home.username)
          {
            input_path = "${inputs.noctalia-templates-community}/chromium-based/color.json";
            output_path = "/etc/opt/chrome/policies/managed/noctalia-color.json";
            post_hook = "timeout --kill-after=1s 5s ${chrome} --refresh-platform-policy --no-startup-window";
          };
    };
}

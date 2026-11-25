# Brave (Flatpak com.brave.Browser, nixos/desktop/brave.nix) de cada usuário:
# o comando `webapp <id>`, o native messaging com o Bitwarden em Flatpak e,
# para o dono da paleta (my.brave.themeOwner), as cores da Noctalia.
#
# Web apps (my.brave.webapps): instalados pelo próprio Brave como PWAs
# (WebAppInstallForceList), que cria o lançador
# ~/.local/share/applications/brave-<app-id>-Default.desktop com o nome
# declarado. `webapp <id>` abre esse lançador; antes de a PWA existir (o Brave
# ainda não abriu, ou estava sem rede, ou é um app com forceInstall = false
# ainda não instalado pela interface), abre a URL numa janela de app.
#
# Native messaging: o Bitwarden em Flatpak só prepara os navegadores em
# Flatpak que conhece (Firefox, Chrome, Chromium, Edge), e o Brave não é um
# deles. Ele abre o socket IPC (.app.bw.socket) e a cópia do desktop_proxy no
# diretório de native messaging de cada um que existir; o proxy, chamado pelo
# navegador, usa o primeiro socket que encontrar. Então:
#  - o diretório do Chrome em Flatpak é criado (sem o Chrome), e o Bitwarden
#    passa a usá-lo;
#  - o Brave recebe acesso a esse diretório (override do Flatpak);
#  - o manifesto com.8bit.bitwarden do Brave aponta para o proxy dali. É
#    uma cópia, e não um symlink do home.file: o alvo no /nix/store não
#    existe no sandbox, o Brave não lê o manifesto e a extensão não acha o
#    app.
# O Bitwarden precisa estar rodando (e ter iniciado depois de o diretório
# existir) para a extensão falar com o app.
#
# Cores: template de usuário com o color.json do "chromium-based" da
# comunidade, gravado direto no arquivo de política que o tmpfiles do sistema
# prepara para este usuário; o post_hook faz o Brave aberto reler as
# políticas.
{ inputs, ... }:
{
  flake.modules.homeManager.brave =
    {
      config,
      lib,
      osConfig,
      pkgs,
      ...
    }:
    let
      inherit (osConfig.my.brave) webapps;
      home = config.home.homeDirectory;
      sharedHosts = ".var/app/com.google.Chrome/config/google-chrome/NativeMessagingHosts";
      braveHosts = ".var/app/com.brave.Browser/config/BraveSoftware/Brave-Browser/NativeMessagingHosts";
      brave = "/var/lib/flatpak/exports/bin/com.brave.Browser";
      # id<TAB>nome<TAB>url<TAB>container, uma linha por web app.
      table = pkgs.writeText "webapps.tsv" (
        lib.concatMapStrings (
          id:
          let
            app = webapps.${id};
            container = if config.my.braveContainers.enable && app.container != null then app.container else "";
          in
          "${id}\t${app.name}\t${app.url}\t${container}\n"
        ) (lib.attrNames webapps)
      );

      webapp = pkgs.writeShellApplication {
        name = "webapp";
        runtimeInputs = [
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
          IFS=$'\t' read -r _ name url container <<< "$line"
          containerArgs=()
          if [ -n "$container" ]; then
            containerArgs=("--container=$container")
          fi
          apps="''${XDG_DATA_HOME:-$HOME/.local/share}/applications"
          for f in "$apps"/com.brave.Browser.flextop.brave-*-Default.desktop "$apps"/brave-*-Default.desktop; do
            [ -e "$f" ] || continue
            if grep -qxF "Name=$name" "$f"; then
              base="$(basename "$f" .desktop)"
              if [[ $base =~ ^(com\.brave\.Browser\.flextop\.)?brave-([a-p]{32})-Default$ ]]; then
                exec ${brave} --profile-directory=Default "--app-id=''${BASH_REMATCH[2]}" "''${containerArgs[@]}"
              fi
            fi
          done
          exec ${brave} "--app=$url" "''${containerArgs[@]}"
        '';
      };

      manifest = pkgs.writeText "com.8bit.bitwarden.json" (
        builtins.toJSON {
          name = "com.8bit.bitwarden";
          description = "Bitwarden desktop <-> browser bridge";
          path = "${home}/${sharedHosts}/.bitwarden_desktop_proxy";
          type = "stdio";
          allowed_origins = [ "chrome-extension://nngceckbapebfimnlniiiahkandclblb/" ];
        }
      );
    in
    {
      home.packages = [ webapp ];

      # Depois do linkGeneration, que apaga o symlink de gerações antigas.
      home.activation.bitwardenSharedNativeMessaging = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
        run mkdir -p ${lib.escapeShellArg "${home}/${sharedHosts}"} ${lib.escapeShellArg "${home}/${braveHosts}"}
        run rm -f ${lib.escapeShellArg "${home}/${braveHosts}/com.8bit.bitwarden.json"}
        run install -m 0644 ${manifest} ${lib.escapeShellArg "${home}/${braveHosts}/com.8bit.bitwarden.json"}
      '';

      programs.noctalia.settings.theme.templates.user.brave =
        lib.mkIf (osConfig.my.brave.themeOwner == config.home.username)
          {
            input_path = "${inputs.noctalia-templates-community}/chromium-based/color.json";
            output_path = "/etc/brave/policies/managed/noctalia-color.json";
            post_hook = "timeout --kill-after=1s 5s ${brave} --refresh-platform-policy --no-startup-window";
          };
    };
}

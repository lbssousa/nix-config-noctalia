# Firefox (Flatpak org.mozilla.firefox, nixos/desktop/firefox.nix) de cada
# usuário: perfil fixo ("default") em ~/.var/app/org.mozilla.firefox/.mozilla/firefox.
{
  flake.modules.homeManager.firefox =
    {
      config,
      lib,
      ...
    }:
    let
      profile = "default";
      appId = "org.mozilla.firefox";
      nativeProfile = "${config.home.homeDirectory}/.mozilla/firefox/${profile}";
      flatpakProfile = "${config.home.homeDirectory}/${config.programs.firefox.configPath}/${profile}";

      # Arquivos do perfil que o programs.firefox gera. Symlinks para o
      # /nix/store não resolvem no sandbox do Flatpak (a store não é montada):
      # o Firefox não via o profiles.ini. Vai como cópia.
      profileFiles = map (f: "${config.programs.firefox.configPath}/${f}") [
        "profiles.ini"
      ];
    in
    {
      options.my.firefox.migrateNativeProfile = lib.mkEnableOption ''
        cópia única do perfil do Firefox nativo (~/.mozilla/firefox/default:
        extensões instaladas, favoritos, logins, containers) para o perfil do
        Flatpak, enquanto o Firefox em Flatpak ainda não tiver aberto o dele.
        O perfil nativo fica onde está'';

      config = {
        home = {
          activation = {
            # Só copia se o Flatpak ainda não usou o perfil (sem prefs.js) e
            # nunca sobrescreve: o profiles.ini do home-manager fica. Sem os
            # arquivos de trava e sem o compatibility.ini (caminhos do Firefox
            # nativo): o Firefox do Flatpak revalida as extensões no primeiro início.
            firefoxMigrateNativeProfile = lib.mkIf config.my.firefox.migrateNativeProfile (
              lib.hm.dag.entryAfter [ "writeBoundary" ] ''
                old=${lib.escapeShellArg nativeProfile}
                new=${lib.escapeShellArg flatpakProfile}
                if [[ -f $old/prefs.js && ! -e $new/prefs.js ]]; then
                  run mkdir -p "$new"
                  run cp -a --reflink=auto --no-clobber "$old/." "$new/"
                  run rm -f "$new/lock" "$new/.parentlock" "$new/parent.lock" "$new/compatibility.ini"
                  noteEcho "Perfil do Firefox nativo copiado para o Flatpak ($new)."
                fi
              ''
            );

            # Cópias, e não symlinks, dos arquivos do perfil (profileFiles).
            # Depois do linkGeneration, que apaga os symlinks de gerações
            # antigas; reescritas a cada ativação, como o home.file faria.
            # Também remove lançadores residuais de Taskbar Tabs criados pelo
            # antigo firefox-webapps (marcados com X-Firefox-Webapps=nix).
            firefoxProfileFiles = lib.hm.dag.entryAfter [ "linkGeneration" ] (
              ''
                run mkdir -p ${lib.escapeShellArg flatpakProfile}
              ''
              + lib.concatMapStrings (f: ''
                run rm -f ${lib.escapeShellArg "${config.home.homeDirectory}/${f}"}
                run install -m 0644 ${config.home.file.${f}.source} ${lib.escapeShellArg "${config.home.homeDirectory}/${f}"}
              '') profileFiles
              + ''
                for f in ${lib.escapeShellArg "${config.xdg.dataHome}/applications"}/firefox.webapp-*.desktop; do
                  if [ -f "$f" ] && grep -qxF "X-Firefox-Webapps=nix" "$f"; then
                    run rm -f "$f"
                  fi
                done
              ''
            );
          };
        };

        programs.firefox = {
          enable = true;
          # O Firefox é o Flatpak do sistema; aqui só o perfil.
          package = null;
          configPath = ".var/app/${appId}/.mozilla/firefox";
          profiles.${profile} = {
            id = 0;
            isDefault = true;
          };
        };

        home.file = lib.genAttrs profileFiles (_: {
          enable = false;
        });

        # O profiles.ini é reescrito a cada ativação (firefoxProfileFiles).
        # Sem MOZ_LEGACY_PROFILES, o Firefox quer um perfil dedicado à
        # instalação ([Install<hash>]) e cria um *.default-release em vez de
        # usar o "default" daqui. Com a variável, usa o perfil Default=1 e não
        # reescreve o arquivo. Override do Flatpak no nível do usuário (lido
        # pelo flatpak no host, então o symlink serve), junto do perfil.
        xdg.dataFile."flatpak/overrides/${appId}".text = lib.generators.toINI { } {
          Environment.MOZ_LEGACY_PROFILES = "1";
        };
      };
    };
}

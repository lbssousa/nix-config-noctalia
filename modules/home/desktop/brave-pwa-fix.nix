# Correção dos lançadores das PWAs do Brave em Flatpak (bug aberto no
# upstream: brave/brave-browser#60360, #50698; flathub/com.brave.Browser#894).
#
# No Wayland, o .desktop que o Brave em Flatpak grava via flextop para cada PWA
# (~/.local/share/applications/com.brave.Browser.flextop.brave-<appid>-<perfil>.desktop):
#  - tem StartupWMClass=crx_<appid>, mas o app_id da janela é
#    brave-<appid>-<perfil>: a janela não é ligada ao lançador e aparece com
#    o ícone do Brave;
#  - aponta Icon= para um PNG em ~/.var/app/com.brave.Browser/data/icons que
#    não existe (os PNGs reais vão para ~/.local/share/icons/hicolor ou ficam
#    em Web Applications/Manifest Resources/<appid>/);
#  - usa aspas simples em Exec= (fora da especificação XDG Desktop Entry);
#  - não passa --container=<nome> (brave/brave-browser#58019): sem ele, o
#    Traffic Control redireciona a abertura da PWA para uma aba na janela
#    principal do navegador.
#
# O brave-pwa-fix corrige StartupWMClass, garante os ícones em hicolor e aponta
# Icon= para o caminho absoluto do PNG de maior resolução, normaliza o Exec= e
# adiciona --container=<nome> para as PWAs declaradas em my.brave.webapps
# (quando my.braveContainers.enable está ligado). Só regrava o que mudou.
#
# Roda na ativação do home-manager, no login e quando o Brave grava um lançador
# ou ícone (brave-pwa-fix.path). `brave-pwa-fix --dry-run` mostra o que mudaria.
{
  flake.modules.homeManager.brave-pwa-fix =
    {
      config,
      lib,
      osConfig,
      pkgs,
      ...
    }:
    let
      braveProfiles = "${config.home.homeDirectory}/.var/app/com.brave.Browser/config/BraveSoftware/Brave-Browser";

      containersByName =
        if config.my.braveContainers.enable then
          lib.listToAttrs (
            lib.concatMap (
              app:
              lib.optional (app.container != null) {
                inherit (app) name;
                value = app.container;
              }
            ) (lib.attrValues osConfig.my.brave.webapps)
          )
        else
          { };

      containersConfig = pkgs.writeText "brave-pwa-containers.json" (builtins.toJSON containersByName);

      fix =
        pkgs.writers.writePython3Bin "brave-pwa-fix"
          {
            flakeIgnore = [ "E501" ];
            makeWrapperArgs = [
              "--set"
              "BRAVE_PWA_CONTAINERS"
              "${containersConfig}"
            ];
          }
          ''
            import difflib
            import glob
            import json
            import os
            import re
            import shlex
            import shutil
            import sys
            import tempfile

            DESKTOP_RE = re.compile(
                r"^(?:com\.brave\.Browser\.flextop\.)?(brave-([a-p]{32})-(.+))\.desktop$"
            )
            FIELD_CODES = {"%f", "%F", "%u", "%U", "%d", "%D", "%n", "%N", "%i", "%c", "%k", "%v", "%m"}
            XDG_RESERVED = set(' \t\n"\'\\><~|&;$*?#()`')


            def quote_xdg_exec(arg):
                if not arg or any(ch in XDG_RESERVED for ch in arg):
                    escaped = arg.replace("\\", "\\\\").replace('"', '\\"').replace("$", "\\$").replace("`", "\\`")
                    return f'"{escaped}"'
                return arg


            def file_equal(src, dst):
                try:
                    if os.path.getsize(src) != os.path.getsize(dst):
                        return False
                    with open(src, "rb") as f1, open(dst, "rb") as f2:
                        return f1.read() == f2.read()
                except OSError:
                    return False


            def sync_icons(profiles, icons_dir, profile, appid, name, dry):
                res_base = os.path.join(
                    profiles,
                    profile.replace("_", " "),
                    "Web Applications",
                    "Manifest Resources",
                    appid,
                )
                pngs = []
                for subdir in ("Trusted Icons/Icons", "Trusted Icons", "Icons", "Icons Maskable"):
                    cand = sorted(glob.glob(os.path.join(res_base, subdir, "*.png")))
                    if cand:
                        pngs = cand
                        break

                best_size = 0
                best_path = None
                for png in pngs:
                    stem = os.path.splitext(os.path.basename(png))[0]
                    if not stem.isdigit():
                        continue
                    size = int(stem)
                    dest = os.path.join(icons_dir, f"{size}x{size}", "apps", f"{name}.png")
                    if not file_equal(png, dest):
                        print(f"ícone: {dest}")
                        if not dry:
                            os.makedirs(os.path.dirname(dest), exist_ok=True)
                            shutil.copyfile(png, dest)
                            os.chmod(dest, 0o644)
                    if size > best_size:
                        best_size = size
                        best_path = dest

                if best_path is None:
                    for existing in glob.glob(os.path.join(icons_dir, "*x*", "apps", f"{name}.png")):
                        size_dir = os.path.basename(os.path.dirname(os.path.dirname(existing)))
                        head = size_dir.split("x", 1)[0]
                        if head.isdigit() and int(head) > best_size:
                            best_size = int(head)
                            best_path = existing

                return best_path


            def update_exec(value, container):
                tokens = shlex.split(value)
                tokens = [t for t in tokens if not t.startswith("--container=")]
                if container:
                    insert_at = len(tokens)
                    for idx, tok in enumerate(tokens):
                        if tok in FIELD_CODES:
                            insert_at = idx
                            break
                    tokens.insert(insert_at, f"--container={container}")
                return " ".join(quote_xdg_exec(t) for t in tokens)


            def rewrite_desktop(text, name, icon_path, containers_by_name):
                lines = text.splitlines(keepends=True)
                in_entry = False
                app_name = None
                has_brave_exec = False
                for line in lines:
                    stripped = line.strip()
                    if stripped.startswith("["):
                        in_entry = stripped == "[Desktop Entry]"
                        continue
                    if not in_entry or "=" not in stripped or stripped.startswith("#"):
                        continue
                    key, val = stripped.split("=", 1)
                    if key == "Name":
                        app_name = val
                    elif key == "Exec" and "com.brave.Browser" in val:
                        has_brave_exec = True

                if not has_brave_exec:
                    return None

                container = containers_by_name.get(app_name) if app_name else None
                out = []
                in_entry = False
                seen_wm = False
                seen_icon = False
                entry_end = None

                for line in lines:
                    stripped = line.strip()
                    if stripped.startswith("["):
                        if in_entry and entry_end is None:
                            entry_end = len(out)
                        in_entry = stripped == "[Desktop Entry]"
                        out.append(line)
                        continue
                    if in_entry and "=" in stripped and not stripped.startswith("#"):
                        key, val = stripped.split("=", 1)
                        if key == "StartupWMClass":
                            out.append(f"StartupWMClass={name}\n")
                            seen_wm = True
                            continue
                        if key == "Icon" and icon_path:
                            out.append(f"Icon={icon_path}\n")
                            seen_icon = True
                            continue
                        if key == "Exec":
                            out.append(f"Exec={update_exec(val, container)}\n")
                            continue
                    out.append(line)

                if entry_end is None:
                    entry_end = len(out)
                extras = []
                if not seen_wm:
                    extras.append(f"StartupWMClass={name}\n")
                if not seen_icon and icon_path:
                    extras.append(f"Icon={icon_path}\n")
                if extras:
                    out[entry_end:entry_end] = extras

                return "".join(out)


            def main():
                dry = len(sys.argv) > 1 and sys.argv[1] == "--dry-run"
                xdg_data = os.environ.get("XDG_DATA_HOME") or os.path.join(
                    os.path.expanduser("~"), ".local", "share"
                )
                apps = os.path.join(xdg_data, "applications")
                icons_dir = os.path.join(xdg_data, "icons", "hicolor")
                profiles = os.path.join(
                    os.path.expanduser("~"),
                    ".var",
                    "app",
                    "com.brave.Browser",
                    "config",
                    "BraveSoftware",
                    "Brave-Browser",
                )
                with open(os.environ["BRAVE_PWA_CONTAINERS"], encoding="utf-8") as f:
                    containers_by_name = json.load(f)

                if not os.path.isdir(apps):
                    return

                for entry in sorted(os.listdir(apps)):
                    m = DESKTOP_RE.match(entry)
                    if not m:
                        continue
                    name, appid, profile = m.group(1), m.group(2), m.group(3)
                    desktop = os.path.join(apps, entry)
                    with open(desktop, encoding="utf-8") as f:
                        old_text = f.read()

                    icon_path = sync_icons(profiles, icons_dir, profile, appid, name, dry)
                    new_text = rewrite_desktop(old_text, name, icon_path, containers_by_name)
                    if new_text is None or new_text == old_text:
                        continue

                    print(f"lançador: {desktop}")
                    if dry:
                        for line in difflib.unified_diff(
                            old_text.splitlines(),
                            new_text.splitlines(),
                            lineterm="",
                        ):
                            print(f"  {line}")
                    else:
                        mode = os.stat(desktop).st_mode & 0o7777
                        fd, tmp = tempfile.mkstemp(dir=apps, prefix=".brave-pwa-fix-", suffix=".desktop")
                        try:
                            with os.fdopen(fd, "w", encoding="utf-8") as f:
                                f.write(new_text)
                            os.chmod(tmp, mode)
                            os.replace(tmp, desktop)
                        except BaseException:
                            try:
                                os.unlink(tmp)
                            except OSError:
                                pass
                            raise


            if __name__ == "__main__":
                main()
          '';
    in
    {
      home.packages = [ fix ];

      home.activation.bravePwaFix = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        run ${lib.getExe fix} || warnEcho "brave-pwa-fix falhou."
      '';

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
            TriggerLimitIntervalSec = "30s";
            TriggerLimitBurst = 30;
          };
          Install.WantedBy = [ "default.target" ];
        };
      };
    };
}

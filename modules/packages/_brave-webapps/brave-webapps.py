"""brave-webapps: containers e PWAs do brave-origin de um usuário.

  brave-webapps containers        cria/ajusta os containers declarados no
                                  Preferences do perfil (só com o Brave fechado)
  brave-webapps sync              acha cada web app declarado entre as PWAs
                                  instaladas e põe --container=<nome> nos
                                  lançadores que o próprio Brave cria
  brave-webapps launch <id|url>   abre o web app no seu container (sai com 2
                                  se a URL não é de um web app declarado)
  brave-webapps list              web apps declarados e o app id de cada um

A configuração (navegador, containers e web apps) vem do JSON em
$BRAVE_WEBAPPS_CONFIG, gerado pelo home-manager.
"""
import json
import os
import re
import shutil
import sys
import tempfile
import uuid

CONFIG = json.load(open(os.environ["BRAVE_WEBAPPS_CONFIG"]))
HOME = os.path.expanduser("~")


def xdg(var, default):
    return os.environ.get(var) or os.path.join(HOME, default)


USER_DATA = os.path.join(xdg("XDG_CONFIG_HOME", ".config"), "BraveSoftware", "Brave-Origin")
PROFILE = os.path.join(USER_DATA, "Default")
APPS_DIR = os.path.join(xdg("XDG_DATA_HOME", ".local/share"), "applications")
CACHE = os.path.join(xdg("XDG_CACHE_HOME", ".cache"), "brave-webapps.json")
ICONS = ["personal", "work", "shopping", "social", "events", "banking",
         "star", "travel", "school", "private", "messaging"]


def log(msg):
    print(f"brave-webapps: {msg}", file=sys.stderr)


def brave_running():
    """Algum processo deste usuário rodando o brave-origin."""
    uid = os.getuid()
    for pid in filter(str.isdigit, os.listdir("/proc")):
        try:
            if os.stat(f"/proc/{pid}").st_uid != uid:
                continue
            with open(f"/proc/{pid}/cmdline", "rb") as f:
                if b"brave.com/brave-origin/brave" in f.read():
                    return True
        except OSError:
            continue
    return False


def write_atomic(path, text, mode=0o644):
    """Troca o arquivo inteiro, mantendo a permissão de um que já exista."""
    os.makedirs(os.path.dirname(path), exist_ok=True)
    try:
        mode = os.stat(path).st_mode & 0o777
    except FileNotFoundError:
        pass
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path))
    with os.fdopen(fd, "w") as f:
        f.write(text)
    os.chmod(tmp, mode)
    os.replace(tmp, path)


# --- containers ---------------------------------------------------------------

def skcolor(hex_rgb):
    """#RRGGBB -> SkColor opaco, como o int32 com sinal que o Brave grava."""
    value = 0xFF000000 | int(hex_rgb.lstrip("#"), 16)
    return value - (1 << 32) if value >= (1 << 31) else value


def containers():
    """Mescla os containers declarados no Preferences, casando pelo nome.

    Um container que já existe com o mesmo nome mantém o id (e, com ele, os
    cookies e dados); só ícone e cor são ajustados. Os demais ficam como estão.
    """
    if brave_running():
        log("o brave-origin está aberto; os containers ficam para a próxima ativação.")
        return 0
    path = os.path.join(PROFILE, "Preferences")
    prefs = {}
    if os.path.exists(path):
        with open(path) as f:
            prefs = json.load(f)
    section = prefs.setdefault("brave", {}).setdefault("containers", {})
    current = section.get("list")
    if not isinstance(current, list):
        # Sem a lista, o Brave criaria os quatro containers padrão dele.
        current = []
    by_name = {c.get("name", "").casefold(): c for c in current if isinstance(c, dict)}

    changed = section.get("enabled") is not True
    section["enabled"] = True
    for name, spec in CONFIG["containers"].items():
        wanted = {"icon": ICONS.index(spec["icon"]), "background_color": skcolor(spec["color"])}
        entry = by_name.get(name.casefold())
        if entry is None:
            current.append({"id": str(uuid.uuid4()), "name": name, **wanted})
            changed = True
        elif any(entry.get(k) != v for k, v in wanted.items()):
            entry.update(wanted)
            changed = True
    section["list"] = current
    if changed:
        write_atomic(path, json.dumps(prefs, separators=(",", ":")), mode=0o600)
        log("containers atualizados: " + ", ".join(CONFIG["containers"]))
    return 0


# --- PWAs -----------------------------------------------------------------------

def installed_apps():
    """app id -> URL de início das PWAs do perfil (registro em LevelDB).

    O banco fica travado com o Brave aberto: lê-se uma cópia.
    """
    src = os.path.join(PROFILE, "Sync Data", "LevelDB")
    if not os.path.isdir(src):
        return {}
    import plyvel
    with tempfile.TemporaryDirectory() as tmp:
        dst = os.path.join(tmp, "db")
        shutil.copytree(src, dst, ignore=shutil.ignore_patterns("LOCK"))
        db = plyvel.DB(dst, create_if_missing=False)
        try:
            apps = {}
            for key, value in db.iterator(prefix=b"web_apps-dt-"):
                url = re.search(rb"https?://[\x21-\x7e]+", value)
                if url:
                    apps[key[len(b"web_apps-dt-"):].decode()] = url.group(0).decode()
            return apps
        finally:
            db.close()


def matches(url, patterns):
    bare = re.sub(r"^[a-z]+://", "", url)
    for p in patterns:
        if bare.startswith(p) and (len(bare) == len(p) or p.endswith("/") or bare[len(p)] in "/?#"):
            return True
    return False


def resolve():
    """id do web app -> app id da PWA instalada (e grava o cache)."""
    apps = installed_apps()
    found = {}
    for webapp, spec in CONFIG["webapps"].items():
        for app_id, url in sorted(apps.items()):
            if matches(url, spec["match"]):
                found[webapp] = app_id
                break
    write_atomic(CACHE, json.dumps(found, indent=2))
    return found


def patch_launchers(found):
    """--container=<nome> nos .desktop que o Brave cria para cada PWA."""
    if not os.path.isdir(APPS_DIR):
        return
    for webapp, app_id in found.items():
        container = CONFIG["webapps"][webapp].get("container")
        for name in os.listdir(APPS_DIR):
            if not name.endswith(f"-{app_id}-Default.desktop"):
                continue
            path = os.path.join(APPS_DIR, name)
            with open(path) as f:
                text = f.read()
            lines = []
            for line in text.splitlines():
                if line.startswith("Exec=") and f"--app-id={app_id}" in line:
                    line = re.sub(r" --container=\S+", "", line)
                    if container:
                        line = line.replace(f"--app-id={app_id}", f"--app-id={app_id} --container={container}", 1)
                lines.append(line)
            new = "\n".join(lines) + "\n"
            if new != text:
                write_atomic(path, new)
                log(f"{name}: container {container or '(nenhum)'}")


def sync():
    patch_launchers(resolve())
    return 0


def launch(target, args):
    webapp = target if target in CONFIG["webapps"] else None
    if webapp is None:
        webapp = next((w for w, s in CONFIG["webapps"].items() if matches(target, s["match"])), None)
    if webapp is None:
        return 2
    spec = CONFIG["webapps"][webapp]
    try:
        with open(CACHE) as f:
            app_id = json.load(f).get(webapp)
    except (OSError, ValueError):
        app_id = None
    if app_id is None:
        app_id = resolve().get(webapp)
    cmd = [CONFIG["browser"]]
    if spec.get("container"):
        cmd.append("--container=" + spec["container"])
    if app_id:
        cmd += ["--profile-directory=Default", "--app-id=" + app_id]
    else:
        # PWA ainda não instalada (a política instala no próximo início): abre
        # a URL numa janela, já no container.
        cmd += ["--new-window", target if "://" in target else spec["url"]]
    os.execv(cmd[0], cmd + args)


def main():
    cmd, args = (sys.argv[1], sys.argv[2:]) if len(sys.argv) > 1 else ("", [])
    if cmd == "containers":
        return containers()
    if cmd == "sync":
        return sync()
    if cmd == "launch" and args:
        return launch(args[0], args[1:])
    if cmd == "list":
        found = resolve()
        for webapp, spec in CONFIG["webapps"].items():
            print(f"{webapp:16} {spec.get('container') or '-':10} {found.get(webapp, '(não instalado)')}")
        return 0
    print(__doc__, file=sys.stderr)
    return 1


sys.exit(main())

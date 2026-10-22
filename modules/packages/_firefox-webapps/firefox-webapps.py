"""firefox-webapps: web apps (Taskbar Tabs) do Firefox de um usuário.

  firefox-webapps apply        põe os web apps declarados no taskbartabs.json
                               do perfil (só com o Firefox fechado), cada um no
                               seu container, e escreve os lançadores
  firefox-webapps sync         apply, mais os ícones que ainda faltam (rede)
  firefox-webapps launch <id>  abre o web app
  firefox-webapps list         web apps declarados e o id de cada um

A configuração (Firefox, perfil e web apps) vem do JSON em
$FIREFOX_WEBAPPS_CONFIG, gerado pelo home-manager.
"""
import json
import os
import shlex
import sys
import tempfile
import urllib.error
import urllib.parse
import urllib.request
import uuid

CONFIG = json.load(open(os.environ["FIREFOX_WEBAPPS_CONFIG"]))
HOME = os.path.expanduser("~")


def xdg(var, default):
    return os.environ.get(var) or os.path.join(HOME, default)


PROFILE = CONFIG["profileDir"]
CONTAINERS = os.path.join(PROFILE, "containers.json")
TASKBAR_TABS = os.path.join(PROFILE, "taskbartabs")
REGISTRY = os.path.join(TASKBAR_TABS, "taskbartabs.json")
ICONS = os.path.join(TASKBAR_TABS, "icons")
APPS_DIR = os.path.join(xdg("XDG_DATA_HOME", ".local/share"), "applications")
# Web apps que este script já criou, para apagar os que saírem da config.
STATE = os.path.join(TASKBAR_TABS, "nix-managed.json")
# Ids fixos: o mesmo web app tem o mesmo id em todo perfil e todo boot.
NAMESPACE = uuid.UUID("6f1d1c2e-4b8a-4f0e-9d3a-0c5e7b2a9f41")


def log(msg):
    print(f"firefox-webapps: {msg}", file=sys.stderr)


def firefox_running():
    """O symlink `lock` do perfil aponta para "<ip>:+<pid>" do Firefox que o usa.

    O Firefox não o apaga ao sair: só existir não basta, o pid tem de estar vivo.
    """
    try:
        target = os.readlink(os.path.join(PROFILE, "lock"))
    except OSError:
        return False
    pid = target.rpartition("+")[2]
    return pid.isdigit() and os.path.exists(f"/proc/{pid}")


def write_atomic(path, data, mode=0o644):
    """Troca o arquivo inteiro (texto ou bytes)."""
    os.makedirs(os.path.dirname(path), exist_ok=True)
    binary = isinstance(data, bytes)
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path), prefix=".firefox-webapps-")
    try:
        with os.fdopen(fd, "wb" if binary else "w") as f:
            f.write(data)
        os.chmod(tmp, mode)
        os.replace(tmp, path)
    except BaseException:
        os.unlink(tmp)
        raise


def read_json(path, default):
    try:
        with open(path) as f:
            return json.load(f)
    except FileNotFoundError:
        return default


def app_uuid(app_id):
    return str(uuid.uuid5(NAMESPACE, app_id))


def desktop_name(app_id):
    return f"firefox.webapp-{app_id}"


def scope(pattern):
    host, _, path = pattern.partition("/")
    # Sem `prefix` o Firefox não abre a janela do web app (sem erro nenhum).
    return {"hostname": host, "prefix": "/" + path}


def registry(ids):
    """Põe os web apps declarados no taskbartabs.json, com os ids fixos."""
    data = read_json(REGISTRY, None) or {"version": 1, "taskbarTabs": []}
    managed = {app_uuid(a) for a in CONFIG["webapps"]}
    stale = set(read_json(STATE, [])) - managed
    tabs = [t for t in data["taskbarTabs"] if t["id"] not in managed | stale]
    for app_id, app in CONFIG["webapps"].items():
        tabs.append({
            "id": app_uuid(app_id),
            "scopes": [scope(p) for p in app["scopes"]],
            "userContextId": ids.get(app["container"], 0),
            "startUrl": app["url"],
            "name": app["name"],
            "shortcutRelativePath": desktop_name(app_id) + ".desktop",
        })
    data["taskbarTabs"] = tabs
    write_atomic(REGISTRY, json.dumps(data, indent=2))
    write_atomic(STATE, json.dumps(sorted(managed)))
    for tab_id in stale:
        try:
            os.unlink(os.path.join(ICONS, tab_id + ".png"))
        except FileNotFoundError:
            pass


def exec_args(app_id, container_id):
    app = CONFIG["webapps"][app_id]
    return [CONFIG["firefox"], "-taskbar-tab", app_uuid(app_id), "-new-window", app["url"],
            "-profile", PROFILE, "-container", str(container_id)]


def launchers(ids):
    """Um lançador por web app; apaga os dos web apps que saíram da config."""
    os.makedirs(APPS_DIR, exist_ok=True)
    wanted = set()
    for app_id, app in CONFIG["webapps"].items():
        name = desktop_name(app_id)
        wanted.add(name + ".desktop")
        icon = os.path.join(ICONS, app_uuid(app_id) + ".png")
        args = exec_args(app_id, ids.get(app["container"], 0))
        write_atomic(os.path.join(APPS_DIR, name + ".desktop"), "\n".join([
            "[Desktop Entry]",
            "Type=Application",
            f"Name={app['name']}",
            f"Icon={icon if os.path.exists(icon) else 'firefox'}",
            "Exec=" + " ".join(shlex.quote(a) for a in args),
            f"StartupWMClass={name}",
            "Categories=Network;WebBrowser;",
            "X-Firefox-Webapps=nix",
            "",
        ]))
    for entry in os.listdir(APPS_DIR):
        if entry.startswith("firefox.webapp-") and entry not in wanted:
            path = os.path.join(APPS_DIR, entry)
            with open(path) as f:
                if "X-Firefox-Webapps=nix" in f.read():
                    os.unlink(path)


def icons():
    """Baixa o ícone (256 px) de cada web app que ainda não tem um."""
    for app_id, app in CONFIG["webapps"].items():
        path = os.path.join(ICONS, app_uuid(app_id) + ".png")
        if os.path.exists(path):
            continue
        labels = urllib.parse.urlsplit(app["url"]).hostname.split(".")
        # Sem ícone para o host (ex. web.whatsapp.com), tenta o domínio pai.
        for i in range(len(labels) - 1):
            url = f"https://www.google.com/s2/favicons?domain={'.'.join(labels[i:])}&sz=256"
            try:
                with urllib.request.urlopen(url, timeout=10) as r:
                    png = r.read()
            except urllib.error.HTTPError:
                continue
            except OSError as e:
                log(f"ícone de {app_id}: {e}")
                break
            if png.startswith(b"\x89PNG"):
                write_atomic(path, png)
                break


def container_ids():
    """{nome: userContextId} dos containers do perfil (os das extensões)."""
    data = read_json(CONTAINERS, {"identities": []})
    return {i["name"]: i["userContextId"]
            for i in data["identities"] if i.get("public") and "name" in i}


def stale_containers(ids):
    """Web apps cujo container no registro não é o declarado.

    O Firefox abre a janela do web app no userContextId do registro (o
    -container do lançador só vale para recriar um web app que sumiu). No
    primeiro boot os containers ainda não existem e o registro fica com 0;
    a extensão do container então tira a página da janela do web app.
    """
    tabs = {t["id"]: t for t in read_json(REGISTRY, {}).get("taskbarTabs", [])}
    return [app_id for app_id, app in CONFIG["webapps"].items()
            if tabs.get(app_uuid(app_id), {}).get("userContextId") != ids.get(app["container"], 0)]


def apply():
    ids = container_ids()
    if firefox_running():
        stale = stale_containers(ids)
        if stale:
            log(f"Firefox aberto; fora do container declarado: {' '.join(stale)}. "
                "Feche o Firefox e rode `firefox-webapps apply`.")
        else:
            log("Firefox aberto; o registro fica para o próximo boot/login.")
    else:
        registry(ids)
    launchers(ids)


def main():
    cmd, args = (sys.argv[1], sys.argv[2:]) if len(sys.argv) > 1 else ("", [])
    if cmd == "apply":
        apply()
    elif cmd == "sync":
        apply()
        icons()
        launchers(container_ids())
    elif cmd == "launch" and len(args) == 1 and args[0] in CONFIG["webapps"]:
        app_id = args[0]
        container = container_ids().get(CONFIG["webapps"][app_id]["container"], 0)
        os.execv(CONFIG["firefox"], exec_args(app_id, container))
    elif cmd == "list":
        for app_id, app in CONFIG["webapps"].items():
            print(f"{app_id}\t{app_uuid(app_id)}\t{app['url']}")
    else:
        print(__doc__, file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()

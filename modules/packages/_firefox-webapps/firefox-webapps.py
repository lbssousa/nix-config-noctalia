"""firefox-webapps: web apps (Taskbar Tabs) do Firefox de um usuário.

  firefox-webapps apply        põe os web apps declarados no taskbartabs.json
                               do perfil (só com o Firefox fechado), cada um no
                               seu container, e escreve os lançadores
  firefox-webapps sync         apply, mais os ícones que ainda faltam (rede)
  firefox-webapps icons        baixa de novo os ícones de todos os web apps
  firefox-webapps launch <id>  abre o web app
  firefox-webapps list         web apps declarados e o id de cada um

A configuração (Firefox, perfil e web apps) vem do JSON em
$FIREFOX_WEBAPPS_CONFIG, gerado pelo home-manager.
"""
import io
import json
import os
import shlex
import sys
import tempfile
import urllib.parse
import urllib.request
import uuid
from html.parser import HTMLParser

from PIL import Image, UnidentifiedImageError

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
# De onde veio cada ícone, para baixar de novo quando a origem mudar.
ICON_STATE = os.path.join(TASKBAR_TABS, "nix-icons.json")
ICON_VERSION = "2"
# Lado máximo do ícone gravado; maiores são reduzidos.
ICON_SIZE = 512
USER_AGENT = "Mozilla/5.0 (X11; Linux x86_64; rv:140.0) Gecko/20100101 Firefox/140.0"
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


def fetch(url, dest):
    """GET com os cabeçalhos de um Firefox: sem os Sec-Fetch-* o WhatsApp
    responde 400. `dest` é o Sec-Fetch-Dest (document, manifest, image)."""
    req = urllib.request.Request(url, headers={
        "User-Agent": USER_AGENT,
        "Accept": "text/html,application/xhtml+xml,*/*;q=0.8" if dest == "document" else "*/*",
        "Accept-Language": "pt-BR,pt;q=0.9,en;q=0.8",
        "Sec-Fetch-Dest": dest,
        "Sec-Fetch-Mode": "navigate" if dest == "document" else "no-cors",
        "Sec-Fetch-Site": "none" if dest == "document" else "same-origin",
    })
    with urllib.request.urlopen(req, timeout=15) as r:
        return r.geturl(), r.read()


class IconLinks(HTMLParser):
    """Os <link rel="...icon..."> e o <link rel="manifest"> da página."""

    def __init__(self):
        super().__init__()
        self.icons, self.manifest = [], None

    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        rel = (a.get("rel") or "").lower().split()
        if tag != "link" or not a.get("href"):
            return
        if "manifest" in rel:
            self.manifest = a["href"]
        elif any("icon" in r for r in rel):
            self.icons.append((a["href"], a.get("sizes"), a.get("type")))


def icon_size(sizes):
    """Maior lado em "48x48 96x96" (0 se não declarado ou "any")."""
    best = 0
    for s in (sizes or "").lower().split():
        w, _, h = s.partition("x")
        if w.isdigit() and h.isdigit():
            best = max(best, int(w), int(h))
    return best


def site_icons(url):
    """Ícones que o site declara, do maior para o menor, sem SVG.

    No manifest, os de purpose "maskable" e "monochrome" ficam de fora: são
    para o sistema recortar ou tingir, não para mostrar como estão.
    """
    host = urllib.parse.urlsplit(url).hostname
    final, html = fetch(url, "document")
    # Sem login, alguns sites redirecionam (ex. para accounts.google.com),
    # cujo ícone não é o do web app.
    if urllib.parse.urlsplit(final).hostname != host:
        return []
    page = IconLinks()
    page.feed(html.decode("utf-8", "replace"))
    found = [(urllib.parse.urljoin(final, href), icon_size(sizes), typ)
             for href, sizes, typ in page.icons]
    if page.manifest:
        manifest_url = urllib.parse.urljoin(final, page.manifest)
        try:
            manifest = json.loads(fetch(manifest_url, "manifest")[1])
        except (OSError, ValueError) as e:
            log(f"manifest de {url}: {e}")
            manifest = {}
        for icon in manifest.get("icons", []):
            if "any" in icon.get("purpose", "any").split() and "src" in icon:
                found.append((urllib.parse.urljoin(manifest_url, icon["src"]),
                              icon_size(icon.get("sizes")), icon.get("type")))
    found = [(u, size) for u, size, typ in found
             if "svg" not in (typ or "") and not urllib.parse.urlsplit(u).path.endswith(".svg")]
    return [u for u, _ in sorted(dict(found).items(), key=lambda i: -i[1])]


def load_icon(url):
    """A imagem (PNG, WebP, ICO...) em RGBA; no ICO, o Pillow pega a maior."""
    data = fetch(url, "image")[1]
    with Image.open(io.BytesIO(data)) as im:
        return im.convert("RGBA")


def best_icon(app):
    """O ícone de maior resolução: o declarado, os do site, ou o do Google.

    Os tamanhos declarados nem sempre batem com a imagem (o .ico não tem
    "sizes"), então baixa em ordem e fica com o maior de fato.
    """
    candidates = [app["icon"]] if app.get("icon") else []
    try:
        candidates += site_icons(app["url"])
    except OSError as e:
        log(f"ícones de {app['url']}: {e}")
    labels = urllib.parse.urlsplit(app["url"]).hostname.split(".")
    # Último recurso; sem ícone para o host (ex. web.whatsapp.com), o domínio pai.
    candidates += [f"https://www.google.com/s2/favicons?domain={'.'.join(labels[i:])}&sz=256"
                   for i in range(len(labels) - 1)]
    best = None
    for url in candidates:
        try:
            im = load_icon(url)
        except (OSError, ValueError, UnidentifiedImageError):
            continue
        if best is None or max(im.size) > max(best.size):
            best = im
        if max(best.size) >= ICON_SIZE:
            break
    return best


def icons(force=False):
    """Baixa o ícone de cada web app que não tem um (ou de todos, com force).

    Ícones de uma versão anterior deste script (ICON_VERSION) ou com outra
    URL declarada são baixados de novo.
    """
    done = read_json(ICON_STATE, {})
    for app_id, app in CONFIG["webapps"].items():
        tab_id = app_uuid(app_id)
        path = os.path.join(ICONS, tab_id + ".png")
        source = f"{ICON_VERSION}:{app.get('icon') or app['url']}"
        if not force and os.path.exists(path) and done.get(tab_id) == source:
            continue
        im = best_icon(app)
        if im is None:
            log(f"ícone de {app_id}: nenhum encontrado")
            continue
        if max(im.size) > ICON_SIZE:
            im.thumbnail((ICON_SIZE, ICON_SIZE), Image.LANCZOS)
        out = io.BytesIO()
        im.save(out, "PNG", optimize=True)
        write_atomic(path, out.getvalue())
        done[tab_id] = source
        log(f"ícone de {app_id}: {im.size[0]}x{im.size[1]}")
    write_atomic(ICON_STATE, json.dumps(done, indent=2, sort_keys=True))


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
    elif cmd == "icons":
        icons(force=True)
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

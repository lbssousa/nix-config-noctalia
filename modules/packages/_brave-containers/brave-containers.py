"""brave-containers: Containers e Traffic Control do Brave declarativos.

  brave-containers          grava containers e regras no perfil (Brave fechado)
  brave-containers --check  mostra o estado atual das chaves gerenciadas

O Firefox usa extensões para criar containers e redirecionar domínios. O Brave
tem isso nativamente (Containers + Traffic Control), mas só na interface: não
há política nem CLI. Este script grava as mesmas preferências que a interface
gravaria, preservando o resto do Preferences, do Local State e as entradas
criadas pelo usuário que não estão na lista declarada.

A configuração (perfil, containers e domínios) vem do JSON em
$BRAVE_CONTAINERS_CONFIG, gerado pelo home-manager.

Notas sobre o formato (brave-core v1.100.59):
  - Os nomes de preferências com ponto viram objetos aninhados no JSON do
    Chromium: "brave.containers.enabled" é `brave → containers → enabled` em
    Preferences, e "brave.traffic_control.list" é
    `brave → traffic_control → list`. Gravar chaves planas com o ponto no nome
    é silenciosamente ignorado pelo navegador.
  - brave.containers.enabled / brave.containers.list:
      [{"id": uuid, "name": str, "icon": int, "background_color": int}]
    Os ícones são o enum containers.mojom.Icon; as cores, SkColor (0xAARRGGBB)
    gravadas como int32 assinado: ContainerToDict() usa
    static_cast<int>(SkColor), FindInt() lê de volta, e um valor positivo
    acima de INT32_MAX viraria float no JSON do Chromium (e o container
    deixaria de ser lido).
  - brave.traffic_control.enabled / brave.traffic_control.list:
      [{"id": uuid, "enabled": bool,
        "condition": {"url_filter": "https://exemplo.com\\n..."},
        "target": {"container_id": uuid}}]
    O url_filter usa a sintaxe de URL blocklist: "https://exemplo.com" pega o
    site e os subdomínios. As regras são avaliadas na ordem da lista.
  - O Traffic Control é FEATURE_DISABLED_BY_DEFAULT no Brave; a flag
    "traffic-control" (brave://flags) precisa ser ligada no Local State, como
    "browser.enabled_labs_experiments": ["traffic-control@1"].
"""
import argparse
import copy
import json
import os
import subprocess
import sys
import tempfile
import uuid

CONFIG = json.load(open(os.environ["BRAVE_CONTAINERS_CONFIG"]))

BASE = CONFIG["profileDir"]
PREFERENCES = os.path.join(BASE, CONFIG["profile"], "Preferences")
LOCAL_STATE = os.path.join(BASE, "Local State")

# Ids estáveis: os mesmos nomes geram sempre os mesmos uuids, em todo perfil e
# em todo rebuild (não dependem de ordem nem de estado anterior).
CONTAINER_NAMESPACE = uuid.UUID("ab5abf19-5979-4e94-a32e-dd5d1f27a716")
RULE_NAMESPACE = uuid.UUID("c375afd1-7206-4389-b67e-bf2bbc8d810b")

# components/containers/core/mojom/containers.mojom, enum Icon.
ICON_IDS = {
    "personal": 0,
    "work": 1,
    "shopping": 2,
    "social": 3,
    "events": 4,
    "banking": 5,
    "star": 6,
    "travel": 7,
    "school": 8,
    "private": 9,
    "messaging": 10,
}

# Uma chave de SINGLE_VALUE de FEATURE_VALUE_TYPE: "internal-name@1" é a
# opção "Enabled" (0 = Default, 1 = Enabled, 2 = Disabled).
TRAFFIC_FLAG = "traffic-control@1"

# JsonPrefStore do Chromium aninha nomes com ponto; as chaves planas abaixo são
# do formato inválido que este script escreveu antes e precisam ser removidas.
CONTAINERS_PATH = ("brave", "containers")
TRAFFIC_PATH = ("brave", "traffic_control")
LEGACY_FLAT_KEYS = (
    "brave.containers.enabled",
    "brave.containers.list",
    "brave.traffic_control.enabled",
    "brave.traffic_control.list",
)


def log(msg):
    print(f"brave-containers: {msg}", file=sys.stderr)


def brave_running():
    """Instância do Flatpak do Brave deste usuário em execução.

    O lock do perfil não serve: o pid é o do namespace do sandbox. Na dúvida
    (falha ao consultar), trata como aberto para não corromper as prefs.
    """
    try:
        out = subprocess.run(
            [CONFIG["flatpak"], "ps", "--columns=application"],
            capture_output=True,
            text=True,
            check=True,
            timeout=15,
        ).stdout
    except (OSError, subprocess.SubprocessError):
        return True
    return CONFIG["appId"] in out.split()


def read_json(path):
    if not os.path.exists(path):
        return {}
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def write_json_atomic(path, data):
    """Troca o arquivo inteiro, no mesmo diretório, preservando o modo."""
    directory = os.path.dirname(path)
    os.makedirs(directory, exist_ok=True)
    payload = json.dumps(data, ensure_ascii=False, separators=(",", ":"))
    fd, tmp = tempfile.mkstemp(dir=directory, prefix=".brave-containers-")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(payload)
            f.flush()
            os.fsync(f.fileno())
        try:
            os.chmod(tmp, os.stat(path).st_mode & 0o7777)
        except FileNotFoundError:
            os.chmod(tmp, 0o600)
        os.replace(tmp, path)
    except BaseException:
        try:
            os.unlink(tmp)
        except FileNotFoundError:
            pass
        raise


def nested_get(root, path):
    """Lê um dict de preferência cujo nome tem pontos (brave.containers.*)."""
    current = root
    for key in path:
        if not isinstance(current, dict):
            return {}
        current = current.get(key)
    return current if isinstance(current, dict) else {}


def nested_dict(root, path):
    """Garante o caminho aninhado e devolve o dict final para escrita."""
    current = root
    for key in path:
        child = current.get(key)
        if not isinstance(child, dict):
            child = {}
            current[key] = child
        current = child
    return current


def merge_declared(declared, existing):
    """Declarados primeiro (na ordem do repo); extras do usuário ficam."""
    if not isinstance(existing, list):
        existing = []
    ids = {item["id"] for item in declared}
    extras = [
        item
        for item in existing
        if isinstance(item, dict) and item.get("id") not in ids
    ]
    return declared + extras


def skcolor_to_int(color):
    """0xAARRGGBB -> int32 assinado, igual a ContainerToDict() do Brave."""
    value = int(color, 16)
    return value - 0x100000000 if value >= 0x80000000 else value


def build():
    containers = []
    rules = []
    for entry in CONFIG["containers"]:
        name = entry["name"]
        container_id = str(uuid.uuid5(CONTAINER_NAMESPACE, f"container:{name}"))
        containers.append(
            {
                "id": container_id,
                "name": name,
                "icon": ICON_IDS[entry["icon"]],
                "background_color": skcolor_to_int(entry["color"]),
            }
        )
        rules.append(
            {
                "id": str(uuid.uuid5(RULE_NAMESPACE, f"rule:{name}")),
                "enabled": True,
                "condition": {
                    "url_filter": "\n".join(
                        f"https://{domain}" for domain in entry["domains"]
                    )
                },
                "target": {"container_id": container_id},
            }
        )
    return containers, rules


def check():
    local = read_json(LOCAL_STATE)
    prefs = read_json(PREFERENCES)
    experiments = local.get("browser", {}).get("enabled_labs_experiments", [])
    containers = nested_get(prefs, CONTAINERS_PATH)
    traffic = nested_get(prefs, TRAFFIC_PATH)
    print(
        json.dumps(
            {
                "perfil": PREFERENCES,
                "flag_traffic_control": TRAFFIC_FLAG in experiments,
                "containers_enabled": containers.get("enabled"),
                "containers": [
                    f"{c.get('name')} ({c.get('id')})"
                    for c in containers.get("list", [])
                    if isinstance(c, dict)
                ],
                "traffic_control_enabled": traffic.get("enabled"),
                "regras": [
                    f"{r.get('id')}: {r.get('condition', {}).get('url_filter', '')!r}"
                    for r in traffic.get("list", [])
                    if isinstance(r, dict)
                ],
            },
            indent=2,
            ensure_ascii=False,
        )
    )


def apply():
    if not os.path.isdir(BASE):
        log(f"perfil do Brave ainda não existe ({BASE}); nada a fazer")
        return 0
    if brave_running():
        log("Brave aberto; nada alterado (feche-o e rode de novo)")
        return 0

    containers, rules = build()

    local = read_json(LOCAL_STATE)
    browser = local.setdefault("browser", {})
    experiments = browser.setdefault("enabled_labs_experiments", [])
    if not isinstance(experiments, list):
        log("browser.enabled_labs_experiments inválido; abortando")
        return 1
    if TRAFFIC_FLAG not in experiments:
        experiments.append(TRAFFIC_FLAG)
        write_json_atomic(LOCAL_STATE, local)
        log("flag traffic-control ativada (brave://flags)")

    prefs = read_json(PREFERENCES)
    updated = copy.deepcopy(prefs)
    for key in LEGACY_FLAT_KEYS:
        updated.pop(key, None)

    containers_pref = nested_dict(updated, CONTAINERS_PATH)
    containers_pref["enabled"] = True
    containers_pref["list"] = merge_declared(
        containers, containers_pref.get("list", [])
    )

    traffic_pref = nested_dict(updated, TRAFFIC_PATH)
    traffic_pref["enabled"] = True
    traffic_pref["list"] = merge_declared(rules, traffic_pref.get("list", []))

    if updated == prefs:
        log("já aplicado")
    else:
        write_json_atomic(PREFERENCES, updated)
        log(
            f"{len(containers)} containers e {len(rules)} regras gravados "
            f"em {PREFERENCES}"
        )
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--check", action="store_true", help="mostra o estado atual das prefs"
    )
    args = parser.parse_args()
    try:
        return check() if args.check else apply()
    except (OSError, ValueError) as e:
        log(f"erro: {e}")
        return 1


if __name__ == "__main__":
    sys.exit(main())

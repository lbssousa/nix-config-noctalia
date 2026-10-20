# shellcheck shell=bash
# vault.sh — the vault behind the "install" profile of secretspec.toml (the
# sops-nix age keys), sourced by install-from-vault.sh, install.sh and
# store-age-keys.sh. Two providers, chosen in an initial dialog:
#
#   bitwarden  Through SecretSpec (provider bw_note): secure notes titled
#              secretspec/<project>/install/<KEY>, the whole keys.txt in the
#              note body. Session in BW_SESSION (lib/bitwarden.sh).
#   kdbx       A KeePass database opened with keepassxc-cli: password plus,
#              optionally, YubiKey HMAC-SHA1 challenge-response, which
#              SecretSpec's own kdbx provider can't do. Entries follow
#              SecretSpec's layout — group secretspec/<project>/install,
#              title <KEY> — with the AGE-SECRET-KEY line in the Password
#              field (what SecretSpec's kdbx provider reads) and the whole
#              keys.txt in Notes.
#
# Functions:
#   vault_choose_provider     sets VAULT_PROVIDER ($VAULT_PROVIDER or a dialog)
#   vault_open                unlocks the vault (asks what it needs)
#   vault_get <KEY>           prints the age key (keys.txt contents)
#   vault_set <KEY> <file>    stores keys.txt from <file>
#   vault_close               locks/forgets the session
#   vault_describe            "Bitwarden" / "KeePass (<file>)", for messages
#   vault_install_keys        AGE_KEY_* names declared in the "install" profile
#
# The unlocked state lives in the environment, so child scripts (install.sh)
# reuse it: BW_SESSION (bitwarden) or VAULT_KDBX_PATH, VAULT_KDBX_PASSWORD and
# VAULT_KDBX_YUBIKEY (kdbx; YubiKey "slot[:serial]", empty for none).
#
# Prompts use gum when it's on PATH.

_VAULT_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VAULT_SPEC="${VAULT_SPEC:-$_VAULT_LIB_DIR/../../secretspec.toml}"
VAULT_KDBX_DEFAULT="${VAULT_KDBX_DEFAULT:-$HOME/Dropbox/KeePass/LaercioSousa.kdbx}"
# The --reason recorded by audit-logging providers names the repository.
_VAULT_REASON="$(basename "$(cd "$_VAULT_LIB_DIR/../.." && pwd)")"

# shellcheck source-path=SCRIPTDIR source=bitwarden.sh
source "$_VAULT_LIB_DIR/bitwarden.sh"

# _vault_ask VAR "prompt" [--password] [gum input options] — same as _bw_ask.
_vault_ask() { _bw_ask "$@"; }

_vault_project() {
  sed -n '/^\[project\]/,/^\[/s/^name *= *"\(.*\)"/\1/p' "$VAULT_SPEC" | head -n1
}

vault_install_keys() {
  sed -n 's/^\(AGE_KEY_[A-Z0-9_]*\) *=.*/\1/p' "$VAULT_SPEC"
}

vault_describe() {
  case "${VAULT_PROVIDER:-}" in
    bitwarden) echo "Bitwarden" ;;
    kdbx) echo "KeePass ($(basename "${VAULT_KDBX_PATH:-?}"))" ;;
    *) echo "vault" ;;
  esac
}

vault_choose_provider() {
  case "${VAULT_PROVIDER:-}" in
    bitwarden | kdbx) return 0 ;;
    "") ;;
    *)
      echo "Unknown vault provider '$VAULT_PROVIDER' (bitwarden or kdbx)." >&2
      return 1
      ;;
  esac
  local choice
  if command -v gum >/dev/null 2>&1; then
    choice="$(gum choose --header "Where are the age keys (secretspec profile 'install')?" \
      "kdbx      — KeePass database (keepassxc-cli, password + YubiKey)" \
      "bitwarden — Bitwarden vault (bw + SecretSpec)")" || return 1
  else
    echo "Where are the age keys (secretspec profile 'install')?"
    select choice in "kdbx" "bitwarden"; do
      [[ -n "$choice" ]] && break
    done
  fi
  VAULT_PROVIDER="${choice%% *}"
  export VAULT_PROVIDER
}

# Commands each provider needs, and the nixpkgs attributes that provide them.
vault_required_cmds() {
  case "$VAULT_PROVIDER" in
    bitwarden) echo "bw secretspec" ;;
    kdbx) echo "keepassxc-cli" ;;
  esac
}
vault_required_pkgs() {
  case "$VAULT_PROVIDER" in
    bitwarden) echo "nixpkgs#bitwarden-cli nixpkgs#secretspec" ;;
    kdbx) echo "nixpkgs#keepassxc" ;;
  esac
}

# --- kdbx -------------------------------------------------------------------

_kdbx_entry() { echo "secretspec/$(_vault_project)/install/$1"; }

# _kdbx_cli <command> [args...] — keepassxc-cli with the database password
# (and, for add/edit -p, extra stdin lines) on stdin. Extra stdin lines come
# from _KDBX_STDIN_EXTRA. On the live ISO the user may lack access to the
# YubiKey's USB device; then it retries as root (passwordless sudo there).
_kdbx_cli() {
  local cmd="$1" err rc
  shift
  local args=("$cmd" -q)
  [[ -n "${VAULT_KDBX_YUBIKEY:-}" ]] && args+=(--yubikey "$VAULT_KDBX_YUBIKEY")
  err="$(mktemp)"
  { printf '%s\n' "$VAULT_KDBX_PASSWORD"; [[ -z "${_KDBX_STDIN_EXTRA:-}" ]] || printf '%s\n' "$_KDBX_STDIN_EXTRA"; } |
    keepassxc-cli "${args[@]}" "$@" 2>"$err" && rc=0 || rc=$?
  if ((rc != 0)) && [[ $EUID -ne 0 && -n "${VAULT_KDBX_YUBIKEY:-}" ]] &&
    grep -qiE 'yubikey|hardware key|chave de hardware|challenge' "$err" && sudo -n true 2>/dev/null; then
    { printf '%s\n' "$VAULT_KDBX_PASSWORD"; [[ -z "${_KDBX_STDIN_EXTRA:-}" ]] || printf '%s\n' "$_KDBX_STDIN_EXTRA"; } |
      sudo -n "$(command -v keepassxc-cli)" "${args[@]}" "$@" 2>"$err" && rc=0 || rc=$?
  fi
  ((rc == 0)) || cat "$err" >&2
  rm -f "$err"
  return "$rc"
}

_kdbx_open() {
  local path="${VAULT_KDBX_PATH:-}" yubikey="${VAULT_KDBX_YUBIKEY-1}" password=""
  if [[ -z "$path" ]]; then
    local default=""
    [[ -f "$VAULT_KDBX_DEFAULT" ]] && default="$VAULT_KDBX_DEFAULT"
    if command -v gum >/dev/null 2>&1; then
      path="$(gum input --prompt "KeePass database> " --value "$default" \
        --placeholder "path to the .kdbx (e.g. on a mounted USB stick)")" || return 1
    else
      read -r -e -p "KeePass database [$default]: " path || return 1
      path="${path:-$default}"
    fi
  fi
  path="${path/#\~/$HOME}"
  [[ -f "$path" ]] || { echo "KeePass database '$path' not found." >&2; return 1; }

  if [[ -z "${VAULT_KDBX_YUBIKEY+set}" ]] && command -v gum >/dev/null 2>&1; then
    yubikey="$(gum input --prompt "YubiKey slot[:serial]> " --value "1" \
      --placeholder "challenge-response slot; empty if the database has no YubiKey")" || return 1
  fi

  if [[ -n "${VAULT_KDBX_PASSWORD:-}" ]]; then
    password="$VAULT_KDBX_PASSWORD"
  else
    _vault_ask password "KeePass master password" --password --placeholder "" || return 1
  fi

  VAULT_KDBX_PATH="$path" VAULT_KDBX_YUBIKEY="$yubikey" VAULT_KDBX_PASSWORD="$password"
  export VAULT_KDBX_PATH VAULT_KDBX_YUBIKEY VAULT_KDBX_PASSWORD
  [[ -z "$yubikey" ]] || echo "Touch the YubiKey if it blinks (once per database access)." >&2
  _kdbx_cli db-info "$VAULT_KDBX_PATH" >/dev/null || {
    unset VAULT_KDBX_PASSWORD
    echo "Could not open '$VAULT_KDBX_PATH' (password, YubiKey?)." >&2
    return 1
  }
}

_kdbx_get() {
  _kdbx_cli show -s -a Password "$VAULT_KDBX_PATH" "$(_kdbx_entry "$1")"
}

# Each keepassxc-cli call opens the database again (one more YubiKey
# challenge), so the groups are only created when the first add fails.
_kdbx_set() {
  local name="$1" file="$2" entry group="" part secret notes parts
  entry="$(_kdbx_entry "$name")"
  secret="$(grep -m1 '^AGE-SECRET-KEY-' "$file")" || {
    echo "$file has no AGE-SECRET-KEY line." >&2
    return 1
  }
  notes="$(cat "$file")"

  if _kdbx_cli show "$VAULT_KDBX_PATH" "$entry" >/dev/null 2>&1; then
    _KDBX_STDIN_EXTRA="$secret" _kdbx_cli edit -p --notes "$notes" "$VAULT_KDBX_PATH" "$entry" >/dev/null
    return
  fi
  _KDBX_STDIN_EXTRA="$secret" _kdbx_cli add -p --notes "$notes" "$VAULT_KDBX_PATH" "$entry" >/dev/null 2>&1 &&
    return 0

  # mkdir creates one level at a time and fails when the group already exists.
  IFS=/ read -r -a parts <<<"${entry%/*}"
  for part in "${parts[@]}"; do
    group="${group:+$group/}$part"
    _kdbx_cli mkdir "$VAULT_KDBX_PATH" "$group" >/dev/null 2>&1 || true
  done
  _KDBX_STDIN_EXTRA="$secret" _kdbx_cli add -p --notes "$notes" "$VAULT_KDBX_PATH" "$entry" >/dev/null
}

# --- bitwarden ----------------------------------------------------------------

_bw_ss() {
  local cmd="$1"
  shift
  secretspec "$cmd" --file "$VAULT_SPEC" --profile install --reason "$_VAULT_REASON" "$@"
}

# --- dispatch -----------------------------------------------------------------

vault_open() {
  case "$VAULT_PROVIDER" in
    bitwarden)
      bw_session "${BW_EMAIL:-}" || return 1
      ;;
    kdbx)
      _kdbx_open || return 1
      ;;
  esac
}

vault_get() {
  case "$VAULT_PROVIDER" in
    bitwarden) _bw_ss get "$1" ;;
    kdbx) _kdbx_get "$1" ;;
  esac
}

vault_set() {
  case "$VAULT_PROVIDER" in
    bitwarden) _bw_ss set "$1" --from-file "$2" ;;
    kdbx) _kdbx_set "$1" "$2" ;;
  esac
}

vault_close() {
  case "${VAULT_PROVIDER:-}" in
    bitwarden) bw lock >/dev/null 2>&1 || true ;;
    kdbx) unset VAULT_KDBX_PASSWORD ;;
  esac
}

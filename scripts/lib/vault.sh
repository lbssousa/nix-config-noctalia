# shellcheck shell=bash
# vault.sh — the vault behind the "install" profile of secretspec.toml (the
# sops-nix age keys), sourced by install-from-vault.sh, install.sh and
# store-age-keys.sh. One provider:
#
#   bitwarden  Through SecretSpec (provider bw_note): secure notes titled
#              secretspec/<project>/install/<KEY>, the whole keys.txt in the
#              note body. Session in BW_SESSION (lib/bitwarden.sh).
#
# Functions:
#   vault_choose_provider     sets VAULT_PROVIDER (only "bitwarden")
#   vault_open                unlocks the vault (asks what it needs)
#   vault_get <KEY>           prints the age key (keys.txt contents)
#   vault_set <KEY> <file>    stores keys.txt from <file>
#   vault_close               locks the session
#   vault_describe            "Bitwarden", for messages
#   vault_install_keys        AGE_KEY_* names declared in the "install" profile
#
# The unlocked state (BW_SESSION) lives in the environment, so child scripts
# (install.sh) reuse it.
#
# Prompts use gum when it's on PATH.

_VAULT_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VAULT_SPEC="${VAULT_SPEC:-$_VAULT_LIB_DIR/../../secretspec.toml}"
# The --reason recorded by audit-logging providers names the repository.
_VAULT_REASON="$(basename "$(cd "$_VAULT_LIB_DIR/../.." && pwd)")"

# shellcheck source-path=SCRIPTDIR source=bitwarden.sh
source "$_VAULT_LIB_DIR/bitwarden.sh"

vault_install_keys() {
  sed -n 's/^\(AGE_KEY_[A-Z0-9_]*\) *=.*/\1/p' "$VAULT_SPEC"
}

vault_describe() {
  case "${VAULT_PROVIDER:-}" in
    bitwarden) echo "Bitwarden" ;;
    *) echo "vault" ;;
  esac
}

vault_choose_provider() {
  case "${VAULT_PROVIDER:-bitwarden}" in
    bitwarden) ;;
    *)
      echo "Unknown vault provider '$VAULT_PROVIDER' (only bitwarden)." >&2
      return 1
      ;;
  esac
  VAULT_PROVIDER=bitwarden
  export VAULT_PROVIDER
}

# Commands each provider needs, and the nixpkgs attributes that provide them.
vault_required_cmds() {
  case "$VAULT_PROVIDER" in
    bitwarden) echo "bw secretspec" ;;
  esac
}
vault_required_pkgs() {
  case "$VAULT_PROVIDER" in
    bitwarden) echo "nixpkgs#bitwarden-cli nixpkgs#secretspec" ;;
  esac
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
  esac
}

vault_get() {
  case "$VAULT_PROVIDER" in
    bitwarden) _bw_ss get "$1" ;;
  esac
}

vault_set() {
  case "$VAULT_PROVIDER" in
    bitwarden) _bw_ss set "$1" --from-file "$2" ;;
  esac
}

vault_close() {
  case "${VAULT_PROVIDER:-}" in
    bitwarden) bw lock >/dev/null 2>&1 || true ;;
  esac
}

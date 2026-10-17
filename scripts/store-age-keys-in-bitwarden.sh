#!/usr/bin/env bash
# store-age-keys-in-bitwarden.sh — Copies the sops-nix age keys from an
# unlocked nix-keys clone to Bitwarden (secretspec profile "install")
#
# For each AGE_KEY_* declared in the "install" profile of secretspec.toml:
#   AGE_KEY_SYSTEM  ← <nix-keys>/sops/age/keys.txt
#   AGE_KEY_<LOGIN> ← <nix-keys>/sops/age/<login>/keys.txt  (skipped if absent)
# then runs `secretspec check` and prints each stored key's public key, to be
# compared with the recipients in nix-secrets/.sops.yaml.
#
# Usage:
#   bash scripts/store-age-keys-in-bitwarden.sh [--nix-keys-dir <dir>] [--email <e-mail>]
#
# Options:
#   --nix-keys-dir  Unlocked nix-keys clone (default: ../nix-keys, sibling of
#                   this repository)
#   --email         Bitwarden account, if a login is needed (default: $BW_EMAIL)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SPEC="$CONFIG_DIR/secretspec.toml"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
RESET='\033[0m'
success() { echo -e "${GREEN}[OK]${RESET}   $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET} $*"; }
die()     { echo -e "${RED}[ERRO]${RESET} $*" >&2; exit 1; }

OPT_NIX_KEYS_DIR="$(dirname "$CONFIG_DIR")/nix-keys"
OPT_EMAIL=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --nix-keys-dir) OPT_NIX_KEYS_DIR="$2"; shift 2 ;;
    --email)        OPT_EMAIL="$2"; shift 2 ;;
    --help | -h)    sed -n '2,/^$/s/^# \{0,1\}//p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *)              die "Unknown option: $1" ;;
  esac
done

for _cmd in bw secretspec age-keygen; do
  command -v "$_cmd" >/dev/null 2>&1 \
    || die "Command '$_cmd' not found. Run inside: nix shell nixpkgs#bitwarden-cli nixpkgs#secretspec nixpkgs#age"
done

AGE_DIR="$OPT_NIX_KEYS_DIR/sops/age"
grep -qs '^AGE-SECRET-KEY-' "$AGE_DIR/keys.txt" \
  || die "$AGE_DIR/keys.txt is missing or still encrypted (git -C $OPT_NIX_KEYS_DIR crypt unlock)."

# shellcheck source-path=SCRIPTDIR source=lib/bitwarden.sh
source "$SCRIPT_DIR/lib/bitwarden.sh"
bw_session "$OPT_EMAIL" || die "Bitwarden login/unlock failed."

ss() {
  local cmd="$1"
  shift
  secretspec "$cmd" --file "$SPEC" --profile install --reason "nix-config-noctalia age key migration" "$@"
}

for name in $(sed -n 's/^\(AGE_KEY_[A-Z0-9_]*\) *=.*/\1/p' "$SPEC"); do
  if [[ "$name" == "AGE_KEY_SYSTEM" ]]; then
    file="$AGE_DIR/keys.txt"
  else
    login="${name#AGE_KEY_}"
    file="$AGE_DIR/${login,,}/keys.txt"
  fi
  if [[ ! -f "$file" ]]; then
    warn "$name: $file not found. Skipping."
    continue
  fi
  ss set "$name" --from-file "$file"
  success "$name ← $file ($(ss get "$name" | age-keygen -y))"
done

ss check --no-prompt

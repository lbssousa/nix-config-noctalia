#!/usr/bin/env bash
# store-age-keys.sh — Copies the sops-nix age keys from an unlocked nix-keys
# clone to the installation vault (secretspec profile "install"): Bitwarden,
# through SecretSpec.
#
# For each AGE_KEY_* declared in the "install" profile of secretspec.toml:
#   AGE_KEY_SYSTEM  ← <nix-keys>/sops/age/keys.txt
#   AGE_KEY_<LOGIN> ← <nix-keys>/sops/age/<login>/keys.txt  (skipped if absent)
# then reads each key back and prints its public key, to be compared with the
# recipients in nix-secrets/.sops.yaml. Layout in the vault: scripts/lib/vault.sh.
#
# Usage:
#   bash scripts/store-age-keys.sh [--nix-keys-dir <dir>] [--email <e-mail>]
#
# Options:
#   --nix-keys-dir  Unlocked nix-keys clone (default: ../nix-keys, sibling of
#                   this repository)
#   --email         Bitwarden account, if a login is needed (default: $BW_EMAIL)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
RESET='\033[0m'
success() { echo -e "${GREEN}[OK]${RESET}   $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET} $*"; }
die()     { echo -e "${RED}[ERRO]${RESET} $*" >&2; exit 1; }

OPT_NIX_KEYS_DIR="$(dirname "$CONFIG_DIR")/nix-keys"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --provider)     export VAULT_PROVIDER="$2"; shift 2 ;;
    --nix-keys-dir) OPT_NIX_KEYS_DIR="$2"; shift 2 ;;
    --email)        export BW_EMAIL="$2"; shift 2 ;;
    --help | -h)    sed -n '2,/^$/s/^# \{0,1\}//p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *)              die "Unknown option: $1" ;;
  esac
done

# shellcheck source-path=SCRIPTDIR source=lib/vault.sh
source "$SCRIPT_DIR/lib/vault.sh"

vault_choose_provider || die "No vault provider chosen."
for _cmd in $(vault_required_cmds) age-keygen; do
  command -v "$_cmd" >/dev/null 2>&1 ||
    die "Command '$_cmd' not found. Run inside: nix shell $(vault_required_pkgs) nixpkgs#age nixpkgs#gum"
done

AGE_DIR="$OPT_NIX_KEYS_DIR/sops/age"
grep -qs '^AGE-SECRET-KEY-' "$AGE_DIR/keys.txt" ||
  die "$AGE_DIR/keys.txt is missing or still encrypted (git -C $OPT_NIX_KEYS_DIR crypt unlock)."

vault_open || die "Could not unlock the vault."
trap 'vault_close' EXIT

for name in $(vault_install_keys); do
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
  vault_set "$name" "$file" || die "$name: could not store it in $(vault_describe)."
  pub="$(vault_get "$name" | age-keygen -y)" || die "$name: stored, but reading it back failed."
  [[ "$pub" == "$(age-keygen -y "$file")" ]] || die "$name: the stored key differs from $file."
  success "$name ← $file ($pub)"
done

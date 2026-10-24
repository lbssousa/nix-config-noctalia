#!/usr/bin/env bash
# install-from-vault.sh — Installation from the live ISO with the age keys
# stored in a vault (recommended path in INSTALLATION.md)
#
# Wraps every manual step around install.sh:
#   1. Provides git, openssh, gum and the vault tools (bw + secretspec),
#      re-running itself inside `nix shell` with the nixpkgs pinned in
#      flake.lock when any is missing
#   2. Unlocks the vault: Bitwarden (master password + YubiKey OTP)
#   3. Checks that every required key of the secretspec "install" profile is
#      there
#   4. Imports the YubiKey resident SSH keys for nix-secrets
#      (import-ssh-yubikey.sh), unless already done or --no-yubikey-ssh
#   5. Runs install.sh --age-keys-from-vault (it elevates itself)
#   6. Locks the vault on exit, whatever the outcome
#
# Usage:
#   bash scripts/install-from-vault.sh [--email <e-mail>] [--no-yubikey-ssh]
#                                      [install.sh options...]
#
# Options:
#   --email           Bitwarden account (default: $BW_EMAIL, else asks)
#   --no-yubikey-ssh  Don't import the YubiKey SSH keys (another key in the
#                     ssh-agent reaches nix-secrets)
#   Anything else is passed to install.sh (--host, --disk, --user, ...).
#
# Environment:
#   BW_2FA_METHOD     Bitwarden two-step login method (default 3, YubiKey OTP;
#                     see scripts/lib/bitwarden.sh)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

CYAN='\033[0;36m'
RED='\033[0;31m'
RESET='\033[0m'
info() { echo -e "${CYAN}[INFO]${RESET} $*"; }
die()  { echo -e "${RED}[ERRO]${RESET} $*" >&2; exit 1; }

[[ $EUID -ne 0 ]] || die "Run WITHOUT sudo: the vault session belongs to the live user (install.sh elevates itself)."

ORIG_ARGS=("$@")
OPT_YUBIKEY_SSH=true
INSTALL_ARGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --provider)       export VAULT_PROVIDER="$2"; shift 2 ;;
    --email)          export BW_EMAIL="$2"; shift 2 ;;
    --no-yubikey-ssh) OPT_YUBIKEY_SSH=false; shift ;;
    --help | -h)      sed -n '2,/^$/s/^# \{0,1\}//p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *)                INSTALL_ARGS+=("$1"); shift ;;
  esac
done

# shellcheck source-path=SCRIPTDIR source=lib/vault.sh
source "$SCRIPT_DIR/lib/vault.sh"

# _ensure_tools <commands> -- <nixpkgs attributes>: re-runs this script inside
# `nix shell` with the attributes when a command is missing. The provider
# chosen so far travels in VAULT_PROVIDER, so the dialog isn't repeated.
_ensure_tools() {
  local cmds=() pkgs=() cmd
  while [[ "$1" != "--" ]]; do cmds+=("$1"); shift; done
  shift
  pkgs=("$@")
  for cmd in "${cmds[@]}"; do
    command -v "$cmd" >/dev/null 2>&1 && continue
    [[ -z "${_INSTALL_FROM_VAULT_SHELL:-}" || "$_INSTALL_FROM_VAULT_SHELL" != "${pkgs[*]}" ]] ||
      die "Command '$cmd' still missing inside nix shell."
    info "Fetching ${pkgs[*]} from the flake's nixpkgs..."
    _INSTALL_FROM_VAULT_SHELL="${pkgs[*]}" exec nix --extra-experimental-features "nix-command flakes" \
      shell --inputs-from "$SCRIPT_DIR/.." "${pkgs[@]}" \
      --command bash "${BASH_SOURCE[0]}" "${ORIG_ARGS[@]}"
  done
}

# 1. Tools, vault provider, vault tools
BASE_PKGS=(nixpkgs#git nixpkgs#openssh nixpkgs#gum)
_ensure_tools git ssh gum -- "${BASE_PKGS[@]}"
vault_choose_provider || die "No vault provider chosen."
# shellcheck disable=SC2046 # word splitting of the lists is intended
_ensure_tools $(vault_required_cmds) -- "${BASE_PKGS[@]}" $(vault_required_pkgs)

# 2. Unlock
info "Unlocking the vault: $VAULT_PROVIDER"
vault_open || die "Could not unlock the vault."
trap 'vault_close' EXIT

# 3. Required keys of the "install" profile
info "Checking the keys in $(vault_describe)"
vault_get AGE_KEY_SYSTEM | grep -q '^AGE-SECRET-KEY-' ||
  die "AGE_KEY_SYSTEM missing in $(vault_describe) (see INSTALLATION.md → 'Chaves no cofre')."

# 4. SSH for nix-secrets
if [[ "$OPT_YUBIKEY_SSH" == "true" ]] && ! grep -qs 'IdentityAgent' "$HOME/.ssh/config"; then
  info "Importing the YubiKey SSH keys (nix-secrets)"
  bash "$SCRIPT_DIR/import-ssh-yubikey.sh"
fi

# 5. Installation (the unlocked session goes in the environment)
bash "$SCRIPT_DIR/install.sh" --age-keys-from-vault "${INSTALL_ARGS[@]}"

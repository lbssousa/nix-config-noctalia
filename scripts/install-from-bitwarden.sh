#!/usr/bin/env bash
# install-from-bitwarden.sh — Installation from the live ISO with the age keys
# stored in Bitwarden (recommended path in INSTALLATION.md)
#
# Wraps every manual step around install.sh:
#   1. Provides git, openssh, bitwarden-cli, secretspec and gum (re-runs itself
#      inside nix-shell when any of them is missing)
#   2. Logs in to Bitwarden (master password + YubiKey OTP) or unlocks it
#   3. Checks the "install" profile of secretspec.toml (no prompts)
#   4. Imports the YubiKey resident SSH keys for nix-secrets
#      (import-ssh-yubikey.sh), unless already done or --no-yubikey-ssh
#   5. Runs install.sh --age-keys-from-bitwarden (it elevates itself)
#   6. Locks the Bitwarden CLI on exit, whatever the outcome
#
# Usage:
#   bash scripts/install-from-bitwarden.sh [--email <e-mail>] [--no-yubikey-ssh]
#                                          [install.sh options...]
#
# Options:
#   --email           Bitwarden account (default: $BW_EMAIL, else asks)
#   --no-yubikey-ssh  Don't import the YubiKey SSH keys (another key in the
#                     ssh-agent reaches nix-secrets)
#   Anything else is passed to install.sh (--host, --disk, --user, ...).
#
# Environment:
#   BW_2FA_METHOD     Two-step login method (default 3, YubiKey OTP; see
#                     scripts/lib/bitwarden.sh)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SPEC="$SCRIPT_DIR/../secretspec.toml"

CYAN='\033[0;36m'
RED='\033[0;31m'
RESET='\033[0m'
info() { echo -e "${CYAN}[INFO]${RESET} $*"; }
die()  { echo -e "${RED}[ERRO]${RESET} $*" >&2; exit 1; }

[[ $EUID -ne 0 ]] || die "Run WITHOUT sudo: the Bitwarden session belongs to the live user (install.sh elevates itself)."

ORIG_ARGS=("$@")
OPT_EMAIL=""
OPT_YUBIKEY_SSH=true
INSTALL_ARGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --email)          OPT_EMAIL="$2"; shift 2 ;;
    --no-yubikey-ssh) OPT_YUBIKEY_SSH=false; shift ;;
    --help | -h)      sed -n '2,/^$/s/^# \{0,1\}//p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *)                INSTALL_ARGS+=("$1"); shift ;;
  esac
done

# 1. Tools
for _cmd in git ssh bw secretspec gum; do
  command -v "$_cmd" >/dev/null 2>&1 && continue
  [[ -z "${_INSTALL_FROM_BW_SHELL:-}" ]] || die "Command '$_cmd' still missing inside nix-shell."
  info "Fetching git, openssh, bitwarden-cli, secretspec and gum via nix-shell..."
  _INSTALL_FROM_BW_SHELL=1 exec nix-shell -p git openssh bitwarden-cli secretspec gum \
    --run "$(printf '%q ' bash "${BASH_SOURCE[0]}" "${ORIG_ARGS[@]}")"
done

# 2. Bitwarden
# shellcheck source-path=SCRIPTDIR source=lib/bitwarden.sh
source "$SCRIPT_DIR/lib/bitwarden.sh"
info "Bitwarden login"
bw_session "$OPT_EMAIL" || die "Bitwarden login/unlock failed."
trap 'bw lock >/dev/null 2>&1 || true' EXIT

# 3. Secrets of the "install" profile
info "Checking the secretspec 'install' profile"
secretspec check --file "$SPEC" --profile install --no-prompt --reason "nix-config-noctalia install" \
  || die "Missing secrets in Bitwarden (see INSTALLATION.md → 'Chaves no Bitwarden')."

# 4. SSH for nix-secrets
if [[ "$OPT_YUBIKEY_SSH" == "true" ]] && ! grep -qs 'IdentityAgent' "$HOME/.ssh/config"; then
  info "Importing the YubiKey SSH keys (nix-secrets)"
  bash "$SCRIPT_DIR/import-ssh-yubikey.sh"
fi

# 5. Installation
bash "$SCRIPT_DIR/install.sh" --age-keys-from-bitwarden "${INSTALL_ARGS[@]}"

#!/usr/bin/env bash
# live-opencode.sh — Runs opencode on the live ISO to debug the installation
#
# The live ISO channel lags behind, so opencode comes from elsewhere:
#   - default:     nixos-unstable (prebuilt in cache.nixos.org, quick)
#   - --upstream:  latest release of github.com/anomalyco/opencode, built from
#                  source by its flake (no binary cache: slow and needs RAM
#                  for the store on tmpfs)
# It starts in the repository root, so the scripts are at hand.
#
# Usage:
#   bash scripts/live-opencode.sh [--upstream] [-- opencode arguments...]
#
# Options:
#   --upstream  Latest upstream release instead of nixos-unstable
#   --help, -h  Show help and exit
#   Anything after -- is passed to opencode.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UPSTREAM_REPO="anomalyco/opencode"

CYAN='\033[0;36m'
RED='\033[0;31m'
RESET='\033[0m'
info() { echo -e "${CYAN}[INFO]${RESET} $*"; }
die()  { echo -e "${RED}[ERRO]${RESET} $*" >&2; exit 1; }

[[ $EUID -ne 0 ]] || die "Run WITHOUT sudo: opencode keeps its login and sessions in the live user's home."

OPT_UPSTREAM=false
OPENCODE_ARGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --upstream) OPT_UPSTREAM=true; shift ;;
    --help | -h) sed -n '2,/^$/s/^# \{0,1\}//p' "${BASH_SOURCE[0]}"; exit 0 ;;
    --)         shift; OPENCODE_ARGS=("$@"); break ;;
    *)          die "Unknown option: $1 (opencode arguments go after --)" ;;
  esac
done

if [[ "$OPT_UPSTREAM" == "true" ]]; then
  # The releases/latest redirect ends in /tag/<version>; no API token or jq needed
  tag="$(curl -fsSLI -o /dev/null -w '%{url_effective}' "https://github.com/$UPSTREAM_REPO/releases/latest")"
  tag="${tag##*/}"
  [[ "$tag" == v* ]] || die "Could not find the latest opencode release (got '$tag')."
  installable="github:$UPSTREAM_REPO/$tag#opencode"
  info "opencode $tag from $UPSTREAM_REPO (built from source, this takes a while)"
else
  installable="github:NixOS/nixpkgs/nixos-unstable#opencode"
  info "opencode from nixos-unstable"
fi

cd "$SCRIPT_DIR/.."
exec nix --extra-experimental-features "nix-command flakes" \
  shell "$installable" --command opencode "${OPENCODE_ARGS[@]}"

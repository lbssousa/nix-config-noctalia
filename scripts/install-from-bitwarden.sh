#!/usr/bin/env bash
# install-from-bitwarden.sh — kept for old instructions: install-from-vault.sh
# with the Bitwarden provider.
exec bash "$(dirname "${BASH_SOURCE[0]}")/install-from-vault.sh" --provider bitwarden "$@"

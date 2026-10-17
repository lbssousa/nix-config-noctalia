#!/usr/bin/env bash
# install.sh — Automated NixOS installation script
#
# Automates the steps described in INSTALLATION.md:
#   0a. (--age-keys-from-bitwarden) Fetches the age keys from Bitwarden via
#       SecretSpec, as the calling user
#   0b. Clones and unlocks the nix-keys repository via git-crypt
#   1.  Asks every question (gum form) and shows a summary to confirm
#   2.  Writes the chosen disk to the host file
#   3.  Partitions and formats the disk with disko (Btrfs + LUKS + LVM, tmpfs root)
#   3b. Activates the disk swap in the live environment (prevents OOM during install)
#   4.  Creates modules/users/<user>.nix from modules/users/_template.nix.in
#   5.  Adds the new files to the git index (git add)
#   6a. Creates the sbctl Secure Boot keys (all hosts use Secure Boot)
#   6b. Copies the sops-nix system age key to /persist
#   7.  Installs NixOS
#   7b. (--age-keys-from-bitwarden) Copies each user's personal age key
#   8.  Expires every user's empty initial password (set on first login)
#   8b. Registers the YubiKey for U2F authentication (pamu2fcfg)
#   9.  Home Manager is already activated by nixos-install (NixOS module)
#
# Usage:
#   bash scripts/install.sh [--host <hostname>] [--disk <device>]
#                           [--user "login:Full Name:sudo"]
#                           [--user "login2:Name2:nosudo"] ...
#                           [--nix-keys-dir <path>]
#                           [--age-keys-backup <file>]
#                           [--age-keys-from-bitwarden]
#                           [--luks-password-file <file>]
#                           [--non-interactive]
#                           [--help]
#
# Options:
#   --host              NixOS host name (e.g. barbudus, bigodon)
#   --disk              Disk device (e.g. /dev/nvme0n1, /dev/sda)
#   --user              User in the format "login:Full Name:sudo|nosudo".
#                       Can be repeated to create multiple users.
#                       "sudo" (default) adds the user to the wheel (sudo) group.
#                       "nosudo" creates the user without sudo permission.
#   --nix-keys-dir      Path to the local clone of the nix-keys repository
#                       (private repository with sops-nix age keys, encrypted
#                       with git-crypt). If omitted, looks in ../nix-keys (sibling of
#                       this repository) and, if not found, asks interactively.
#   --age-keys-backup   Direct path to the system age key's keys.txt file
#                       (sops-nix). Alternative to --nix-keys-dir when you only have
#                       the key file without the full repository. Copied to
#                       /persist/etc/sops/age/keys.txt on the installed system.
#   --age-keys-from-bitwarden
#                       Reads the age keys (system and per user) from
#                       Bitwarden, through the "install" profile of
#                       secretspec.toml. Replaces nix-keys/git-crypt. Run
#                       WITHOUT sudo, with `bw` unlocked and BW_SESSION
#                       exported — install-from-bitwarden.sh does all that.
#   --luks-password-file
#                       File with the LUKS passphrase. Without it, the
#                       interactive form asks for it (and, with
#                       --non-interactive, disko asks on the terminal).
#   --non-interactive   Doesn't ask questions; fails if required information
#                       isn't provided via flags
#   --help, -h          Show help and exit

set -euo pipefail

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

info()    { echo -e "${CYAN}[INFO]${RESET} $*"; }
success() { echo -e "${GREEN}[OK]${RESET}   $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET} $*"; }
error()   { echo -e "${RED}[ERRO]${RESET} $*" >&2; }
die()     { error "$*"; exit 1; }


require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Command '$1' not found. Make sure you're in the NixOS live environment."
}

# Runs pamu2fcfg with the given arguments.
# If it's not on PATH, fetches it via nix-shell (pam_u2f should already be
# in nixos-install's cache).
_run_pamu2fcfg() {
  if command -v pamu2fcfg >/dev/null 2>&1; then
    pamu2fcfg "$@"
  else
    local args_str=""
    local a
    for a in "$@"; do
      args_str+=" $(printf '%q' "$a")"
    done
    nix-shell -p pam_u2f \
      --option extra-substituters "$NIX_COMMUNITY_SUBSTITUTER" \
      --option extra-trusted-public-keys "$NIX_COMMUNITY_KEY" \
      --run "pamu2fcfg${args_str}"
  fi
}

# ---------------------------------------------------------------------------
# gum (interactive prompts)
# ---------------------------------------------------------------------------
# The questions use gum, like the Omarchy installer. The live ISO doesn't ship
# it, so the script re-runs itself inside `nix-shell -p gum`. Its absolute path
# goes to the root process in INSTALL_GUM (sudo -E keeps the environment, but
# not necessarily a PATH with gum in it).

_interactive=true
for _arg in "$@"; do
  [[ "$_arg" == "--non-interactive" ]] && _interactive=false
done
if [[ "$_interactive" == "true" && -z "${INSTALL_GUM:-}" ]]; then
  if ! command -v gum >/dev/null 2>&1; then
    [[ -z "${_INSTALL_GUM_SHELL:-}" ]] || die "gum still missing inside nix-shell."
    info "Fetching gum via nix-shell..."
    _INSTALL_GUM_SHELL=1 exec nix-shell -p gum --run "$(printf '%q ' bash "${BASH_SOURCE[0]}" "$@")"
  fi
  INSTALL_GUM="$(command -v gum)"
  export INSTALL_GUM
fi

gum() { command "${INSTALL_GUM:-gum}" "$@"; }

# ---------------------------------------------------------------------------
# 0a. Bitwarden (via SecretSpec) — runs as the calling user, before sudo
# ---------------------------------------------------------------------------
# The `bw` session (BW_SESSION + the CLI data in the user's $HOME) belongs to
# the live user, so the secrets are fetched here, before the re-execution as
# root. They go to a 0700 directory in RAM ($XDG_RUNTIME_DIR), handed to the
# root process via INSTALL_BW_KEYS_DIR and removed when the script exits:
#   system.txt       ← AGE_KEY_SYSTEM (copied to /persist in step 6b)
#   user-<login>.txt ← AGE_KEY_<LOGIN> (copied to the user's home in step 7b)
# SSH to github.com (nix-secrets) is unchanged: the YubiKey config written by
# import-ssh-yubikey.sh, or any key in the agent (sudo -E keeps SSH_AUTH_SOCK).

_bw_fetch_secrets() {
  local spec dir name login
  spec="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/secretspec.toml"

  require_cmd secretspec
  require_cmd bw
  [[ -n "${BW_SESSION:-}" ]] || die "BW_SESSION not set. Use scripts/install-from-bitwarden.sh, which logs in to Bitwarden."
  bw sync >/dev/null || die "bw sync failed. Is the vault unlocked (BW_SESSION)?"

  # secretspec options go after the subcommand: ss get <name> ...
  ss() {
    local cmd="$1"
    shift
    secretspec "$cmd" --file "$spec" --profile install --reason "nix-config-noctalia install.sh" "$@"
  }

  dir="$(mktemp -d "${XDG_RUNTIME_DIR:-/dev/shm}/install-bw.XXXXXX")"
  chmod 700 "$dir"
  export INSTALL_BW_KEYS_DIR="$dir"

  info "==> Step 0a: Fetching secrets from Bitwarden (secretspec profile 'install')"
  (umask 077 && ss get AGE_KEY_SYSTEM > "$dir/system.txt") \
    || die "Could not read AGE_KEY_SYSTEM from Bitwarden (run: secretspec check -P install)."
  grep -q '^AGE-SECRET-KEY-' "$dir/system.txt" || die "AGE_KEY_SYSTEM doesn't look like an age key."
  success "System age key read."

  # One AGE_KEY_<LOGIN> per user, as declared in the "install" profile.
  for name in $(sed -n 's/^\(AGE_KEY_[A-Z0-9_]*\) *=.*/\1/p' "$spec"); do
    [[ "$name" == "AGE_KEY_SYSTEM" ]] && continue
    login="${name#AGE_KEY_}"
    login="${login,,}"
    if (umask 077 && ss get "$name" > "$dir/user-$login.txt" 2>/dev/null) \
      && grep -q '^AGE-SECRET-KEY-' "$dir/user-$login.txt"; then
      success "Personal age key read for '$login'."
    else
      rm -f "$dir/user-$login.txt"
      warn "No personal age key for '$login' in Bitwarden ($name). Skipping."
    fi
  done
}

_bw_mode=false
for _arg in "$@"; do
  [[ "$_arg" == "--age-keys-from-bitwarden" ]] && _bw_mode=true
done
if [[ "$_bw_mode" == "true" && -z "${INSTALL_BW_KEYS_DIR:-}" ]]; then
  [[ $EUID -ne 0 ]] || die "--age-keys-from-bitwarden: run the script WITHOUT sudo (it elevates itself after reading Bitwarden)."
  _bw_fetch_secrets
fi

# ---------------------------------------------------------------------------
# Ensure running as root
# ---------------------------------------------------------------------------

if [[ $EUID -ne 0 ]]; then
  info "This script must run as root. Re-executing with sudo..."
  exec sudo -E bash "${BASH_SOURCE[0]}" "$@"
fi

# ---------------------------------------------------------------------------
# SSH for root (YubiKey resident keys)
# ---------------------------------------------------------------------------
# The script re-executed itself as root, so any SSH operation (the nix-secrets
# clone below AND nixos-install, which resolves the git+ssh:// nix-secrets flake
# input) runs with HOME=/root. Root doesn't read the ~/.ssh/config the user
# generated with import-ssh-yubikey.sh (IdentityFile + IdentityAgent none for
# the resident ED25519-SK keys); it falls back to whatever agent is on
# SSH_AUTH_SOCK, which replies "agent refused operation" for SK keys.
#
# Fix: export GIT_SSH_COMMAND pointing ssh (via -F) at that user's config, so
# both git clone and the flake evaluation use the FIDO2 path directly.
# Root can read the config and private keys regardless of the 700/600 perms.
NIX_SECRETS_SSH_CONFIG=""
if [[ "$_bw_mode" == "true" ]]; then
  [[ -d "${INSTALL_BW_KEYS_DIR:-}" ]] || die "INSTALL_BW_KEYS_DIR missing. Run the script without sudo."
fi
for _u in "${SUDO_USER:-}" $(find /home -maxdepth 2 -name config -path '*/.ssh/config' 2>/dev/null | sed 's|^/home/\([^/]*\)/\.ssh/config|\1|'); do
  _c="/home/$_u/.ssh/config"
  if [[ -n "$_u" && "$_u" != "root" && -f "$_c" ]] && grep -q 'IdentityAgent' "$_c" 2>/dev/null; then
    NIX_SECRETS_SSH_CONFIG="$_c"
    break
  fi
done
# With -F, "~" in the user config still expands to /root, so root would have
# no known_hosts and the first connection would ask to trust github.com —
# which fails ("Host key verification failed") when Nix runs git without a
# terminal. Pin GitHub's published host keys (docs.github.com, "GitHub's SSH
# key fingerprints") instead; command-line -o options win over the config.
GITHUB_KNOWN_HOSTS="$(mktemp /run/install-github-known-hosts.XXXXXX)"
cat > "$GITHUB_KNOWN_HOSTS" <<'EOF'
github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl
github.com ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBEmKSENjQEezOmxkZMy7opKgwFB9nkt5YRrYMjNuG5N87uRgg6CLrbo5wAdT/y6v0mKV0U2w0WZ2YB/++Tpockg=
github.com ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCj7ndNxQowgcQnjshcLrqPEiiphnt+VTTvDP6mHBL9j1aNUkY4Ue1gvwnGLVlOhGeYrnZaMgRK6+PKCUXaDbC7qtbW8gIkhL7aGCsOr/C56SJMy/BCZfxd1nWzAOxSDPgVsmerOBYfNqltV9/hWCqBywINIR+5dIg6JTJ72pcEpEjcYgXkE2YEFXV1JHnsKgbLWNlhScqb2UmyRkQyytRLtL+38TGxkxCflmO+5Z8CSSNY7GidjMIZ7Q4zMjA2n1nGrlTDkzwDCsw+wqFPGQA179cnfGWOWRVruj16z6XyvxvjJwbz0wQZ75XK5tKSb7FNyeIEs4TT4jk+S4dhPeAUC5y+bDYirYgM4GC7uEnztnZyaVWQ7B381AK4Qdrwt51ZqExKbQpTUNn+EjqoTwvqNj4kqx5QUCI0ThS/YkOxJCXmPUWZbhjpCg56i+2aB6CmK2JGhn57K5mj0MNdBXA4/WnwH6XoPWJzK5Nyu2zB3nAZp+S5hpQs+p1vN1/wsjk=
EOF
chmod 644 "$GITHUB_KNOWN_HOSTS"
# Temporary files of this run: the pinned known_hosts and, in Bitwarden mode,
# the age keys read in step 0a.
trap 'rm -f "$GITHUB_KNOWN_HOSTS"; [[ -z "${INSTALL_BW_KEYS_DIR:-}" ]] || rm -rf "$INSTALL_BW_KEYS_DIR"' EXIT

if [[ -n "$NIX_SECRETS_SSH_CONFIG" ]]; then
  info "Root runs with HOME=/root; using user SSH config ($NIX_SECRETS_SSH_CONFIG) for SSH-backed flake inputs."
  export GIT_SSH_COMMAND="ssh -F \"$NIX_SECRETS_SSH_CONFIG\" -o UserKnownHostsFile=\"$GITHUB_KNOWN_HOSTS\" -o StrictHostKeyChecking=yes"
else
  export GIT_SSH_COMMAND="ssh -o UserKnownHostsFile=\"$GITHUB_KNOWN_HOSTS\" -o StrictHostKeyChecking=yes"
fi

# ---------------------------------------------------------------------------
# Binary cache constants
# ---------------------------------------------------------------------------
# The nix-community cache provides pre-built artifacts for various packages,
# avoiding nixos-install having to compile from scratch and do
# dependency downloads that can fail with a 500 error.
NIX_COMMUNITY_SUBSTITUTER="https://nix-community.cachix.org"
NIX_COMMUNITY_KEY="nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCUSeBs="

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------

OPT_HOST=""
OPT_DISK=""
OPT_USERS_LOGIN=()
OPT_USERS_FULLNAME=()
OPT_USERS_SUDO=()
OPT_NIX_KEYS_DIR=""
OPT_AGE_KEYS_BACKUP=""
OPT_AGE_KEYS_FROM_BITWARDEN=false
OPT_LUKS_PASSWORD_FILE=""
OPT_NON_INTERACTIVE=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --host)           OPT_HOST="$2";          shift 2 ;;
    --disk)           OPT_DISK="$2";          shift 2 ;;
    --nix-keys-dir)   OPT_NIX_KEYS_DIR="$2";  shift 2 ;;
    --age-keys-backup) OPT_AGE_KEYS_BACKUP="$2"; shift 2 ;;
    --age-keys-from-bitwarden) OPT_AGE_KEYS_FROM_BITWARDEN=true; shift ;;
    --luks-password-file) OPT_LUKS_PASSWORD_FILE="$2"; shift 2 ;;
    --user)
      # Format: "login:Full Name:sudo|nosudo"
      # The third field is optional (default: sudo).
      _spec="$2"
      _login="${_spec%%:*}"
      _after_login="${_spec#*:}"
      if [[ "$_after_login" == "$_spec" ]]; then
        # Login only, no separators
        _fname=""
        _sudo_flag="true"
      else
        _last_field="${_after_login##*:}"
        if [[ "$_last_field" == "nosudo" || "$_last_field" == "false" || "$_last_field" == "no" ]]; then
          _sudo_flag="false"
          _fname="${_after_login%:*}"
        else
          _sudo_flag="true"
          _fname="$_after_login"
        fi
      fi
      OPT_USERS_LOGIN+=("$_login")
      OPT_USERS_FULLNAME+=("$_fname")
      OPT_USERS_SUDO+=("$_sudo_flag")
      shift 2 ;;
    --non-interactive) OPT_NON_INTERACTIVE=true; shift ;;
    --help|-h)
      cat <<'EOF'
Usage:
  bash scripts/install.sh [--host <hostname>] [--disk <device>]
                          [--user "login:Full Name:sudo"]
                          [--user "login2:Name2:nosudo"] ...
                          [--nix-keys-dir <path>]
                          [--age-keys-backup <file>]
                          [--age-keys-from-bitwarden]
                          [--luks-password-file <file>]
                          [--non-interactive] [--help]

Options:
  --host              NixOS host name (e.g. barbudus, bigodon).
                      The flake attribute used in nixos-install is simply
                      the host name (nixosConfigurations.<host>).
                      If omitted, it's asked interactively.
  --disk              Target disk device (e.g. /dev/nvme0n1, /dev/sda).
                      If omitted, it's asked interactively.
  --user              User in the format "login:Full Name:sudo|nosudo".
                      Can be repeated to create multiple users.
                      "sudo" (default) adds the user to the wheel (sudo) group.
                      "nosudo" creates the user without sudo permission.
                      If omitted, it's asked interactively.
  --nix-keys-dir      Path to the local clone of the nix-keys repository
                      (private repository with sops-nix age keys, encrypted with
                      git-crypt). If omitted, looks in ../nix-keys (sibling of
                      this repository). The repository needs to already be unlocked, or
                      the script will ask to unlock it via GPG or a symmetric key.
  --age-keys-backup   Direct path to the system age key's keys.txt file.
                      Alternative to --nix-keys-dir when you only have the file
                      without the full repository. Copied to
                      /persist/etc/sops/age/keys.txt on the installed system.
  --age-keys-from-bitwarden
                      Reads the age keys (system and per user) from Bitwarden,
                      through the "install" profile of secretspec.toml,
                      instead of nix-keys. Run WITHOUT sudo,
                      with bw unlocked and BW_SESSION exported
                      (scripts/install-from-bitwarden.sh does that).
  --luks-password-file
                      File with the LUKS passphrase. Without it, the form
                      asks for it (with --non-interactive, disko asks).
  --non-interactive   Doesn't ask questions; fails if required information
                      isn't provided via flags.
  --help, -h          Show this help and exit.

Examples:
  # Fully interactive installation (recommended):
  bash scripts/install.sh

  # Keys from Bitwarden (no nix-keys): login, checks and this script
  bash scripts/install-from-bitwarden.sh

  # Non-interactive installation, nix-keys at a custom path:
  bash scripts/install.sh \
    --host barbudus \
    --disk /dev/nvme0n1 \
    --nix-keys-dir /tmp/nix-keys \
    --user "cavalo:sudo" \
    --user "macaco:nosudo" \
    --non-interactive

Every question (host, disk, LUKS passphrase, users, system age key, root
password) comes first, followed by a summary and a single confirmation;
nothing touches the disk before that. In the prompts, Esc starts the
questions over and Ctrl+C cancels.

This script automates the steps described in INSTALLATION.md:
  0a. (--age-keys-from-bitwarden) Reads the keys from Bitwarden via SecretSpec
  0b. Clones and unlocks the nix-keys repository via git-crypt
  1.  Asks every question (gum form) and shows a summary to confirm
  2.  Writes the chosen disk to the host file
  3.  Partitions and formats the disk with disko (Btrfs + LUKS + LVM, tmpfs root)
  3b. Activates the disk swap in the live environment (prevents OOM during install)
  4.  Creates modules/users/<user>.nix from modules/users/_template.nix.in
  5.  Adds the new files to the git index (git add)
  6a. Creates the sbctl Secure Boot keys (all hosts use Secure Boot)
  6b. Copies the sops-nix system age key to /persist
  7.  Installs NixOS
  7b. (--age-keys-from-bitwarden) Copies each user's personal age key
  8.  Expires every user's empty initial password and optionally sets root's
  8b. Registers the YubiKey for U2F authentication (pamu2fcfg)
  9.  Home Manager is already activated by nixos-install (NixOS module)
EOF
      exit 0 ;;
    *) die "Unknown option: $1. Use --help to see the available options." ;;
  esac
done

# ---------------------------------------------------------------------------
# 0. Prerequisites
# ---------------------------------------------------------------------------

echo
echo -e "${BOLD}╔══════════════════════════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}║           NixOS Installation — Automated Script              ║${RESET}"
echo -e "${BOLD}╚══════════════════════════════════════════════════════════════╝${RESET}"
echo

# Detect the configuration's root directory (where this script lives)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
USERS_DIR="$CONFIG_DIR/modules/users"
HOSTS_DIR="$CONFIG_DIR/modules/hosts"
PRIVATE_AGE_KEY_REPO="$(dirname "$CONFIG_DIR")/nix-keys/sops/age/keys.txt"

NIX_KEYS_DIR=""                                          # set/validated in step 0b
NIX_KEYS_DIR_DEFAULT="$(dirname "$CONFIG_DIR")/nix-keys" # canonical location (sibling of this repo)

info "Configuration directory: $CONFIG_DIR"
cd "$CONFIG_DIR"

require_cmd git
require_cmd nix
require_cmd lsblk
require_cmd sed

# Enable Flakes and the nix-community cache for root (idempotent).
# The script already runs as root; we try /etc/nix/nix.conf (global) and
# fall back to /root/.config/nix/nix.conf when /etc/nix is read-only
# (typical case on the NixOS Live CD).
NIX_CONF_GLOBAL="/etc/nix/nix.conf"
NIX_CONF_USER="/root/.config/nix/nix.conf"

_nix_community_block() {
  printf 'extra-substituters = %s\nextra-trusted-public-keys = %s\n' \
    "$NIX_COMMUNITY_SUBSTITUTER" "$NIX_COMMUNITY_KEY"
}

_configure_nix_conf() {
  local conf="$1"

  if ! grep -q "experimental-features" "$conf" 2>/dev/null; then
    echo "experimental-features = nix-command flakes" >> "$conf"
    success "Flakes enabled in $conf"
  else
    info "Flakes are already enabled in $conf."
  fi

  if ! grep -qF "$NIX_COMMUNITY_KEY" "$conf" 2>/dev/null; then
    _nix_community_block >> "$conf"
    success "nix-community cache added to $conf."
  else
    info "nix-community cache already configured in $conf."
  fi
}

if mkdir -p "$(dirname "$NIX_CONF_GLOBAL")" 2>/dev/null && \
   { [[ -w "$NIX_CONF_GLOBAL" ]] || { [[ ! -e "$NIX_CONF_GLOBAL" ]] && [[ -w "$(dirname "$NIX_CONF_GLOBAL")" ]]; }; }; then
  _configure_nix_conf "$NIX_CONF_GLOBAL"
else
  warn "/etc/nix is read-only (Live CD). Using $NIX_CONF_USER as a fallback."
  mkdir -p "$(dirname "$NIX_CONF_USER")"
  _configure_nix_conf "$NIX_CONF_USER"
fi

# ---------------------------------------------------------------------------
# 0b. Clone and unlock the nix-keys repository
# ---------------------------------------------------------------------------
# The nix-keys repository is a private (SSH) repository separate from nix-config.
# It stores sops-nix age keys, encrypted with git-crypt:
#
#   nix-keys/
#     sops/age/keys.txt          ← SYSTEM age key (decrypts NixOS secrets,
#                                    e.g. Wi-Fi password). Copied to
#                                    /persist/etc/sops/age/keys.txt in step 6b.
#     sops/age/<user>/keys.txt   ← PERSONAL age key for each user (decrypts
#                                    Home Manager secrets, e.g. rclone). Copied
#                                    by the HM activation script on first login.
#
# Unlocking via git-crypt requires the YubiKey (GPG) or the exported symmetric key.
# Without the system key, sops-nix can't decrypt secrets during NixOS
# activation (Wi-Fi, etc.) and the service fails silently at boot.
# This step runs before the form: it only reads, and needs the YubiKey.

echo
info "==> Step 0b: nix-keys repository (sops-nix age keys)"

# Priority: Bitwarden > --nix-keys-dir flag > default (sibling of nix-config) > interactive
if [[ "$OPT_AGE_KEYS_FROM_BITWARDEN" == "true" ]]; then
  info "Keys read from Bitwarden in step 0a. Skipping nix-keys."
  [[ -z "$OPT_AGE_KEYS_BACKUP" ]] && OPT_AGE_KEYS_BACKUP="$INSTALL_BW_KEYS_DIR/system.txt"
elif [[ -n "$OPT_NIX_KEYS_DIR" ]]; then
  if [[ ! -d "$OPT_NIX_KEYS_DIR" ]]; then
    die "--nix-keys-dir: directory '$OPT_NIX_KEYS_DIR' not found."
  fi
  NIX_KEYS_DIR="$OPT_NIX_KEYS_DIR"
  info "Using nix-keys at: $NIX_KEYS_DIR (via --nix-keys-dir)"
elif [[ -d "$NIX_KEYS_DIR_DEFAULT/.git" ]]; then
  NIX_KEYS_DIR="$NIX_KEYS_DIR_DEFAULT"
  info "nix-keys found at: $NIX_KEYS_DIR"
elif [[ -n "$OPT_AGE_KEYS_BACKUP" ]]; then
  info "System age key given via --age-keys-backup. Skipping nix-keys."
elif [[ "$OPT_NON_INTERACTIVE" == "true" ]]; then
  # Non-interactive mode without nix-keys: just warn.
  warn "nix-keys not found at $NIX_KEYS_DIR_DEFAULT and --age-keys-backup not specified."
  warn "sops-nix secrets (Wi-Fi, etc.) won't be available without the system age key."
  warn "Use --nix-keys-dir or --age-keys-backup to provide the key."
else
  warn "nix-keys not found at $NIX_KEYS_DIR_DEFAULT."
  info "It holds the sops-nix age keys; without them, system secrets (e.g. Wi-Fi) won't work."
  _nix_keys_url="$(gum input --prompt "nix-keys URL> " \
    --placeholder "git@github.com:lbssousa/nix-keys.git (Enter to skip)")" \
    || die "Installation cancelled."
  if [[ -n "$_nix_keys_url" ]]; then
    info "Cloning nix-keys into $NIX_KEYS_DIR_DEFAULT..."
    # GIT_SSH_COMMAND (with the user's ~/.ssh/config via -F) is already
    # exported globally early in the script, so this root-run clone also uses
    # the resident YubiKey keys instead of falling back to the (refusing) agent.
    if git clone "$_nix_keys_url" "$NIX_KEYS_DIR_DEFAULT"; then
      NIX_KEYS_DIR="$NIX_KEYS_DIR_DEFAULT"
      success "nix-keys cloned into $NIX_KEYS_DIR."
    else
      warn "Failed to clone nix-keys. Check the URL and SSH connectivity."
      warn "The form will ask for the path of the system age key instead."
    fi
  else
    warn "nix-keys skipped. The form will ask for the path of the system age key."
  fi
fi

# If nix-keys was located, update the path to the system age key
if [[ -n "$NIX_KEYS_DIR" ]]; then
  PRIVATE_AGE_KEY_REPO="$NIX_KEYS_DIR/sops/age/keys.txt"
fi

# Check whether nix-keys needs unlocking via git-crypt: once decrypted, the age
# key starts with 'AGE-SECRET-KEY-' (a missing file counts as locked).
if [[ -n "$NIX_KEYS_DIR" && -d "$NIX_KEYS_DIR/.git-crypt" ]]; then
  if grep -q '^AGE-SECRET-KEY-' "$NIX_KEYS_DIR/sops/age/keys.txt" 2>/dev/null; then
    success "nix-keys is already unlocked."
  else
    warn "nix-keys is locked by git-crypt."
    command -v git-crypt >/dev/null 2>&1 \
      || die "git-crypt not found. Run the script inside: nix-shell -p git-crypt gnupg"
    [[ "$OPT_NON_INTERACTIVE" != "true" ]] \
      || die "Non-interactive mode: nix-keys locked. Unlock it before running the script."

    _git_crypt_key_path="$(gum input --prompt "git-crypt key> " \
      --placeholder "path to the exported symmetric key (Enter: GPG via YubiKey)")" \
      || die "Installation cancelled."
    if [[ -n "$_git_crypt_key_path" ]]; then
      (cd "$NIX_KEYS_DIR" && git-crypt unlock "$_git_crypt_key_path") \
        && success "nix-keys unlocked successfully." \
        || die "Failed to unlock nix-keys. Check the symmetric key."
    else
      info "Trying to unlock via GPG (YubiKey)..."
      (cd "$NIX_KEYS_DIR" && git-crypt unlock) \
        && success "nix-keys unlocked via GPG successfully." \
        || die "Failed to unlock nix-keys via GPG. Check that the YubiKey is inserted and GPG is configured."
    fi
  fi
fi

# ---------------------------------------------------------------------------
# 1. Questions (gum form) and confirmation
# ---------------------------------------------------------------------------
# Every answer is collected here, before anything is written: host, disk,
# LUKS passphrase, users, system age key and root password. A summary then
# asks for a single confirmation. As in Omarchy's setup form, each prompt
# returns gum's status: 0 = answered, 1 = Esc (start the questions over),
# 130 = Ctrl+C (cancel). Values given via flags aren't asked again.

echo
info "==> Step 1: Installation questions"

FORM_BACK=1

mapfile -t AVAILABLE_HOSTS < <(find "$HOSTS_DIR" -maxdepth 1 -mindepth 1 -type d ! -name '_*' -exec basename {} \; | sort)
[[ ${#AVAILABLE_HOSTS[@]} -gt 0 ]] || die "No host found in $HOSTS_DIR/"

# Already-existing user files (files starting with "_" are helpers).
_EXISTING_USERS=()
for _f in "$USERS_DIR/"*.nix; do
  _bname="$(basename "$_f" .nix)"
  [[ "$_bname" == _* ]] && continue
  _EXISTING_USERS+=("$_bname")
done

HOST=""
DISK=""
LUKS_PASSWORD=""
USERS_LOGIN=()
USERS_FULLNAME=()
USERS_SUDO=()
USERS_OVERWRITE=()
AGE_KEY_FILE=""
ROOT_HASH=""

# notice "message": validation feedback inside the form
notice() {
  gum style --foreground 1 "$*"
  sleep 1
}

# yes/no question; 0 = yes, 1 = no, anything else = Ctrl+C
_ask_yes_no() {
  gum confirm "$@"
}

# Hashes a password read from stdin (yescrypt, like NixOS' own passwd).
_hash_password() {
  if command -v mkpasswd >/dev/null 2>&1; then
    mkpasswd -m yescrypt --stdin
  else
    nix run nixpkgs#mkpasswd \
      --option extra-substituters "$NIX_COMMUNITY_SUBSTITUTER" \
      --option extra-trusted-public-keys "$NIX_COMMUNITY_KEY" \
      -- -m yescrypt --stdin
  fi
}

# _ask_secret VAR "prompt" "placeholder": masked input, typed twice
_ask_secret() {
  local __var="$1" prompt="$2" placeholder="$3" __value __again st
  while true; do
    __value="$(gum input --password --prompt "$prompt> " --placeholder "$placeholder")" && st=0 || st=$?
    ((st == 0)) || return "$st"
    __again="$(gum input --password --prompt "Confirm> " --placeholder "Type it again")" && st=0 || st=$?
    ((st == 0)) || return "$st"
    if [[ -z "$__value" ]]; then
      notice "It can't be blank."
    elif [[ "$__value" != "$__again" ]]; then
      notice "They didn't match. Try again."
    else
      printf -v "$__var" '%s' "$__value"
      return 0
    fi
  done
}

_form_host() {
  local st
  HOST="$OPT_HOST"
  if [[ -z "$HOST" ]]; then
    HOST="$(gum choose --header "Host to install" "${AVAILABLE_HOSTS[@]}")" && st=0 || st=$?
    ((st == 0)) || return "$st"
  fi
  [[ -d "$HOSTS_DIR/$HOST" ]] || die "Host '$HOST' not found in $HOSTS_DIR/"
}

_form_disk() {
  local st line
  DISK="$OPT_DISK"
  if [[ -z "$DISK" ]]; then
    line="$(lsblk -dpno NAME,SIZE,TRAN,MODEL,TYPE | awk '$NF == "disk" && $1 !~ /zram/' | sed 's/ *disk$//' \
      | gum choose --header "Disk to ERASE and install on")" && st=0 || st=$?
    ((st == 0)) || return "$st"
    DISK="${line%% *}"
  fi
  [[ -b "$DISK" ]] || die "Device '$DISK' not found or is not a block device."
}

_form_luks() {
  LUKS_PASSWORD=""
  if [[ -n "$OPT_LUKS_PASSWORD_FILE" ]]; then
    [[ -f "$OPT_LUKS_PASSWORD_FILE" ]] || die "--luks-password-file: '$OPT_LUKS_PASSWORD_FILE' not found."
    LUKS_PASSWORD="$(<"$OPT_LUKS_PASSWORD_FILE")"
    [[ -n "$LUKS_PASSWORD" ]] || die "--luks-password-file: '$OPT_LUKS_PASSWORD_FILE' is empty."
    return 0
  fi
  [[ "$OPT_NON_INTERACTIVE" == "true" ]] && return 0 # disko asks on the terminal
  _ask_secret LUKS_PASSWORD "LUKS passphrase" "Unlocks the disk at boot (until TPM2 is enrolled)"
}

_form_users() {
  local st login fname sudo more=true i
  USERS_LOGIN=("${OPT_USERS_LOGIN[@]}")
  USERS_FULLNAME=("${OPT_USERS_FULLNAME[@]}")
  USERS_SUDO=("${OPT_USERS_SUDO[@]}")
  USERS_OVERWRITE=()

  if [[ "$OPT_NON_INTERACTIVE" == "true" ]]; then
    [[ ${#USERS_LOGIN[@]} -gt 0 || ${#_EXISTING_USERS[@]} -gt 0 ]] \
      || die "Non-interactive mode: no user defined. Use --user 'login:Name:sudo'."
    for i in "${!USERS_LOGIN[@]}"; do USERS_OVERWRITE[i]=false; done
    return 0
  fi

  if [[ ${#USERS_LOGIN[@]} -eq 0 ]]; then
    if [[ ${#_EXISTING_USERS[@]} -gt 0 ]]; then
      _ask_yes_no --default=false "Users already defined: ${_EXISTING_USERS[*]}. Create more?" && st=0 || st=$?
      case "$st" in 0) ;; 1) more=false ;; *) return "$st" ;; esac
    fi
    while [[ "$more" == "true" ]]; do
      login="$(gum input --prompt "Login> " --placeholder "lowercase letters, digits, - and _ (like abutre)")" && st=0 || st=$?
      ((st == 0)) || return "$st"
      if ! [[ "$login" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]; then
        notice "Invalid login: use lowercase letters, digits, hyphens and underscores."
        continue
      fi
      fname="$(gum input --prompt "Full name> " --placeholder "$login (Enter keeps the login)")" && st=0 || st=$?
      ((st == 0)) || return "$st"
      _ask_yes_no "Grant sudo (wheel) to '$login'?" && st=0 || st=$?
      case "$st" in 0) sudo=true ;; 1) sudo=false ;; *) return "$st" ;; esac
      USERS_LOGIN+=("$login")
      USERS_FULLNAME+=("${fname:-$login}")
      USERS_SUDO+=("$sudo")
      _ask_yes_no --default=false "Add another user?" && st=0 || st=$?
      case "$st" in 0) ;; 1) more=false ;; *) return "$st" ;; esac
    done
  fi

  for i in "${!USERS_LOGIN[@]}"; do
    USERS_OVERWRITE[i]=false
    [[ -f "$USERS_DIR/${USERS_LOGIN[i]}.nix" ]] || continue
    _ask_yes_no --default=false "modules/users/${USERS_LOGIN[i]}.nix already exists. Overwrite it?" && st=0 || st=$?
    case "$st" in 0) USERS_OVERWRITE[i]=true ;; 1) ;; *) return "$st" ;; esac
  done
}

# Source of the system age key, in priority order: --age-keys-backup,
# Bitwarden (step 0a), nix-keys (step 0b), then the form (path or skip).
_form_age_key() {
  local st
  AGE_KEY_FILE="$OPT_AGE_KEYS_BACKUP"
  [[ -z "$AGE_KEY_FILE" && -f "$PRIVATE_AGE_KEY_REPO" ]] && AGE_KEY_FILE="$PRIVATE_AGE_KEY_REPO"
  if [[ -n "$AGE_KEY_FILE" ]]; then
    [[ -f "$AGE_KEY_FILE" ]] || die "System age key '$AGE_KEY_FILE' not found."
    return 0
  fi
  [[ "$OPT_NON_INTERACTIVE" == "true" ]] && return 0
  while true; do
    AGE_KEY_FILE="$(gum input --prompt "System age key> " \
      --placeholder "path to keys.txt (Enter to skip: no sops-nix secrets)")" && st=0 || st=$?
    ((st == 0)) || return "$st"
    [[ -z "$AGE_KEY_FILE" || -f "$AGE_KEY_FILE" ]] && return 0
    notice "File '$AGE_KEY_FILE' not found."
  done
}

# root isn't one of the my.users accounts: without a password it stays locked
# (nixos-install runs with --no-root-password), which also locks the
# emergency shell. Only the hash is kept.
_form_root() {
  local st password=""
  ROOT_HASH=""
  [[ "$OPT_NON_INTERACTIVE" == "true" ]] && return 0
  _ask_yes_no --default=false "Set a root password? (otherwise root stays locked)" && st=0 || st=$?
  case "$st" in 0) ;; 1) return 0 ;; *) return "$st" ;; esac
  _ask_secret password "Root password" "Also unlocks the emergency shell" || return
  ROOT_HASH="$(printf '%s' "$password" | _hash_password)" || die "Could not hash the root password."
}

_form() {
  _form_host && _form_disk && _form_luks && _form_users && _form_age_key && _form_root
}

_form_summary() {
  local users="" i sudo age_src luks="asked by disko" root="locked"

  for i in "${!USERS_LOGIN[@]}"; do
    sudo="sudo"
    [[ "${USERS_SUDO[i]}" == "false" ]] && sudo="no sudo"
    users+="${users:+, }${USERS_LOGIN[i]} (${USERS_FULLNAME[i]:-${USERS_LOGIN[i]}}, $sudo)"
  done
  [[ -n "$LUKS_PASSWORD" ]] && luks="passphrase set"
  [[ -n "$ROOT_HASH" ]] && root="set"
  if [[ "$OPT_AGE_KEYS_FROM_BITWARDEN" == "true" ]]; then
    age_src="Bitwarden (system + personal keys)"
  else
    age_src="${AGE_KEY_FILE:-none (no sops-nix secrets)}"
  fi

  gum style --border rounded --border-foreground 212 --padding "1 2" \
    "$(gum style --bold --foreground 212 "Installation summary")" \
    "" \
    "Host            $HOST" \
    "Disk            $DISK  $(lsblk -dno SIZE,MODEL "$DISK" | xargs)" \
    "                $(gum style --bold --foreground 1 "ALL DATA ON IT WILL BE ERASED")" \
    "LUKS            $luks" \
    "New users       ${users:-none}" \
    "Existing users  ${_EXISTING_USERS[*]:-none}" \
    "System age key  $age_src" \
    "Root password   $root"
}

if [[ "$OPT_NON_INTERACTIVE" == "true" ]]; then
  [[ -n "$OPT_HOST" ]] || die "Non-interactive mode: use --host <host>."
  [[ -n "$OPT_DISK" ]] || die "Non-interactive mode: use --disk <device>."
  _form
else
  while true; do
    _form && _st=0 || _st=$?
    case "$_st" in
      0) ;;
      "$FORM_BACK") info "Starting the questions over."; continue ;;
      *) die "Installation cancelled." ;;
    esac
    _form_summary
    gum confirm --default=false --affirmative "Erase and install" --negative "Back" \
      "Erase $DISK and install $HOST?" && _st=0 || _st=$?
    case "$_st" in
      0) break ;;
      1) info "Starting the questions over." ;;
      *) die "Installation cancelled." ;;
    esac
  done
fi

success "Host: $HOST — disk: $DISK"

# The flake attribute is simply the host name (nixosConfigurations.<host>).
# The host file (modules/hosts/<host>/default.nix) holds the disko device.
FLAKE_SYSTEM_ATTR="$HOST"
CFG_FILE="$HOSTS_DIR/$HOST/default.nix"
HW_FILE="$HOSTS_DIR/$HOST/_hardware-configuration.nix"

# ---------------------------------------------------------------------------
# 2. Write the disk to the host file
# ---------------------------------------------------------------------------

echo
info "==> Step 2: Installation disk"

# Extracts the value in quotes after 'device = ' using sed (more portable than grep -P)
CURRENT_DISK=$(sed -n 's|.*device = "\([^"]*\)".*|\1|p' "$CFG_FILE" | head -1)
if [[ "$CURRENT_DISK" != "$DISK" ]]; then
  info "Updating device in $CFG_FILE: $CURRENT_DISK → $DISK"
  sed -i "s|device = \"[^\"]*\"|device = \"$DISK\"|g" "$CFG_FILE"
  git add "$CFG_FILE"
  success "$CFG_FILE updated."
else
  info "$CFG_FILE is already configured for $DISK."
fi

# ---------------------------------------------------------------------------
# 3. Partition and format the disk
# ---------------------------------------------------------------------------
# The LUKS passphrase from the form goes to disko on stdin: its luks type
# (askPassword) reads it twice — passphrase and confirmation — with `read -s`.

echo
info "==> Step 3: Partition and format the disk ($DISK)"

_disko=(nix run github:nix-community/disko
  --option extra-substituters "$NIX_COMMUNITY_SUBSTITUTER"
  --option extra-trusted-public-keys "$NIX_COMMUNITY_KEY"
  -- --mode disko --flake "$CONFIG_DIR#$FLAKE_SYSTEM_ATTR")
if [[ -n "$LUKS_PASSWORD" ]]; then
  printf '%s\n%s\n' "$LUKS_PASSWORD" "$LUKS_PASSWORD" | "${_disko[@]}"
else
  "${_disko[@]}"
fi
unset LUKS_PASSWORD
success "Disk partitioned and formatted successfully."

# ---------------------------------------------------------------------------
# 3b. Activate disk swap in the live environment
# ---------------------------------------------------------------------------
# disko formats the swap partition/volume (mkswap) but does not activate it.
# The live CD runs without any swap, so nixos-install has only physical RAM
# for Nix expression evaluation and builds. Activating the newly formatted
# swap here gives nixos-install up to 20 GB of virtual memory, preventing
# OOM kills that would otherwise abort the installation.
#
# The device name is fixed by modules/hosts/_disko-btrfs.nix:
#   LUKS → LVM (root_vg) → /dev/root_vg/swap

echo
info "==> Step 3b: Activate disk swap"

_swap_device="/dev/root_vg/swap"

if [[ -n "$_swap_device" && -b "$_swap_device" ]]; then
  if grep -qF "$_swap_device" /proc/swaps 2>/dev/null; then
    info "Swap already active on $_swap_device."
  elif swapon "$_swap_device"; then
    success "Disk swap activated on $_swap_device."
    info "Available swap: $(free -h | awk '/^Swap:/{print $2}')."
  else
    warn "Could not activate swap on $_swap_device."
    warn "nixos-install will run with live-CD RAM only — risk of OOM on low-RAM machines."
  fi
elif [[ -n "$_swap_device" ]]; then
  warn "Swap device $_swap_device not found (host may have swap disabled)."
  warn "nixos-install will run with live-CD RAM only."
fi

# ---------------------------------------------------------------------------
# 4. Create user files
# ---------------------------------------------------------------------------

echo
info "==> Step 4: Create user accounts"

# Finds the next free numeric uid by scanning the existing modules/users/*.nix
# files for "uid = N;" and returning max+1 (or 1000 if none is set yet).
_next_free_uid() {
  local _max
  _max=$(grep -hoP 'uid\s*=\s*\K[0-9]+' "$USERS_DIR/"*.nix 2>/dev/null | sort -n | tail -1)
  if [[ -z "$_max" ]]; then
    echo 1000
  else
    echo $((_max + 1))
  fi
}

_create_user_file() {
  local user="$1" sudo_flag="$2" overwrite="$3"
  local user_file="$USERS_DIR/$user.nix"

  if [[ -f "$user_file" && "$overwrite" != "true" ]]; then
    info "Keeping the existing file for $user."
    return
  fi

  local uid
  uid="$(_next_free_uid)"

  # modules/users/_template.nix.in → modules/users/<user>.nix (picked up
  # automatically by import-tree; no central list to edit).
  sed -e "/^# Modelo usado/,/^# (@USERNAME@/d" \
    -e "s|@USERNAME@|$user|g" -e "s|@UID@|$uid|g" -e "s|@SUDO@|$sudo_flag|g" \
    "$USERS_DIR/_template.nix.in" > "$user_file"

  success "User file $user_file created (uid: $uid, sudo: $sudo_flag)."
}

if [[ ${#USERS_LOGIN[@]} -eq 0 ]]; then
  info "No new user. Using only the already-defined ones: ${_EXISTING_USERS[*]}"
fi
for _i in "${!USERS_LOGIN[@]}"; do
  _create_user_file "${USERS_LOGIN[$_i]}" "${USERS_SUDO[$_i]:-true}" "${USERS_OVERWRITE[$_i]:-false}"
done

# Full names are NOT stored in modules/users/<user>.nix — they're read from
# the private nix-secrets flake (inputs.nix-secrets.${username}.fullName, see
# modules/nixos/core/users.nix) and out of reach of this script.
if [[ ${#USERS_LOGIN[@]} -gt 0 ]]; then
  echo
  info "Remember to add the full name for each new user to nix-secrets:"
  for _i in "${!USERS_LOGIN[@]}"; do
    info "  ${USERS_LOGIN[$_i]} → ${USERS_FULLNAME[$_i]:-${USERS_LOGIN[$_i]}}"
  done
fi

# ---------------------------------------------------------------------------
# 5. Add user files to the git index (ESSENTIAL)
# ---------------------------------------------------------------------------

echo
info "==> Step 5: Register user files in the git index"

# Nix evaluates flakes from the git index.
# Untracked files (even if they exist on disk) are invisible to Nix,
# causing "module not found" errors in nixos-install.
# git add ensures the file is in the index and visible to Nix.
for _i in "${!USERS_LOGIN[@]}"; do
  _ufile="$USERS_DIR/${USERS_LOGIN[$_i]}.nix"
  git add "$_ufile"
  success "File $_ufile added to the git index."
done

git add "$CFG_FILE" "$HW_FILE"
success "Host files registered in the git index."

# ---------------------------------------------------------------------------
# 6a. Create Secure Boot keys (every host uses Secure Boot via Limine)
# ---------------------------------------------------------------------------

echo
info "==> Step 6a: Check Secure Boot support (Limine)"

if true; then
  # The boot.loader.limine module doesn't have a pkiBundle option: sbctl
  # always looks for keys in /var/lib/sbctl. Each host with Secure Boot
  # creates a /var/lib/sbctl -> /persist/etc/secureboot symlink via
  # systemd.tmpfiles.rules (see modules/nixos/security/secureboot.nix) to survive
  # the tmpfs root. This path needs to exist BEFORE the first boot for the
  # Limine installer to sign the bootloader during nixos-install.
  _SECUREBOOT_DIR="/mnt/persist/etc/secureboot"

  info "Host '$HOST' uses Secure Boot via Limine. Keys at: /persist/etc/secureboot"

  if [ -f "${_SECUREBOOT_DIR}/GUID" ]; then
    info "Secure Boot keys already exist at ${_SECUREBOOT_DIR}."
  else
    info "Creating PKI keys for Secure Boot at ${_SECUREBOOT_DIR}..."
    info "(Required for Limine to sign the bootloader during nixos-install)"
    # Why --disable-landlock is needed:
    #   sbctl activates the Landlock sandbox (a Linux LSM) before processing
    #   the --export and --database-path flags. Landlock is configured based
    #   on the default path /var/lib/sbctl, blocking access to any other
    #   path — even for root (it's a process restriction, not a user one).
    #   Without --disable-landlock, any access to ${_SECUREBOOT_DIR} results
    #   in EACCES, which sbctl reports as "sbctl requires root to run: open ...".
    #
    # Why --export and --database-path are separate:
    #   --database-path sets only the path of the GUID FILE (not the directory).
    #   --export sets the keys directory (keydir).
    #   Together they create the structure sbctl expects at /var/lib/sbctl
    #   (via the symlink created by the host's systemd.tmpfiles.rules):
    #     ${_SECUREBOOT_DIR}/GUID
    #     ${_SECUREBOOT_DIR}/keys/PK/{PK.key,PK.pem}
    #     ${_SECUREBOOT_DIR}/keys/KEK/{KEK.key,KEK.pem}
    #     ${_SECUREBOOT_DIR}/keys/db/{db.key,db.pem}
    mkdir -p "${_SECUREBOOT_DIR}"
    nix run \
      --option extra-substituters "$NIX_COMMUNITY_SUBSTITUTER" \
      --option extra-trusted-public-keys "$NIX_COMMUNITY_KEY" \
      nixpkgs#sbctl -- --disable-landlock create-keys \
      --export "${_SECUREBOOT_DIR}/keys" \
      --database-path "${_SECUREBOOT_DIR}/GUID"
    success "Secure Boot keys created at ${_SECUREBOOT_DIR}."
    warn "The keys still need to be enrolled in the firmware after the first boot."
    warn "See INSTALLATION.md → 'Secure Boot Configuration' for the next steps."
  fi
else
  info "Host '$HOST' does not use Secure Boot. Skipping key creation."
fi

# ---------------------------------------------------------------------------
# 6b. Copy the sops-nix system age key to /persist
# ---------------------------------------------------------------------------
# The system age key is required for sops-nix to decrypt secrets during
# NixOS activation (e.g. Wi-Fi profiles, certificates).
# It must exist at /persist/etc/sops/age/keys.txt before the first boot.
#
# The source was chosen in step 1 (AGE_KEY_FILE): --age-keys-backup,
# Bitwarden (step 0a), nix-keys (step 0b) or a path typed in the form.
#
# Note: each user's PERSONAL age key comes from Bitwarden in step 7b or, with
# nix-keys, is copied by the Home Manager activation script on first login.

echo
info "==> Step 6b: Copy the sops-nix system age key to /persist"

_AGE_KEYS_DST="/mnt/persist/etc/sops/age/keys.txt"

if [[ -n "$AGE_KEY_FILE" ]]; then
  install -d -o root -g root -m 700 "$(dirname "$_AGE_KEYS_DST")"
  install -o root -g root -m 600 "$AGE_KEY_FILE" "$_AGE_KEYS_DST"
  success "Age key copied to $_AGE_KEYS_DST."
else
  warn "No system age key. sops-nix secrets (Wi-Fi, etc.) won't be applied until"
  warn "it's copied to /persist/etc/sops/age/keys.txt."
fi

# ---------------------------------------------------------------------------
# 7. Install NixOS
# ---------------------------------------------------------------------------

echo
info "==> Step 7: Install NixOS"

# Copy the configuration to /persist/etc/nixos. "/" is a tmpfs: anything
# written to /mnt/etc/nixos itself would be gone on the first boot, when
# preservation turns /etc/nixos into a symlink to /persist/etc/nixos. The
# /mnt/etc/nixos symlink below only serves nixos-install.
mkdir -p /mnt/persist/etc/nixos /mnt/etc
# rsync is preferable but may not be available; use cp as a fallback
if command -v rsync >/dev/null 2>&1; then
  rsync -a --delete "$CONFIG_DIR/" /mnt/persist/etc/nixos/
else
  cp -r "$CONFIG_DIR/." /mnt/persist/etc/nixos/
fi
[[ -L /mnt/etc/nixos ]] || { rm -rf /mnt/etc/nixos; ln -s ../persist/etc/nixos /mnt/etc/nixos; }
success "Configuration copied to /mnt/persist/etc/nixos (linked at /mnt/etc/nixos)."

# Re-index user files, configuration and the private layer at /mnt/etc/nixos
# to make sure Nix sees them when evaluating the copied flake.
#
# Why this is necessary:
#   rsync copies the .git/ directory (including the index) from the source
#   repo, but the copied git index may contain entries with object hashes
#   pointing to the local live CD's store — not to the files under
#   /mnt/etc/nixos. Redoing git add at the destination ensures the index
#   at /mnt/etc/nixos reflects the LOCAL files, making them visible to
#   Nix's flake evaluator (which uses the git index to determine which
#   files to include in the flake source).
for _i in "${!USERS_LOGIN[@]}"; do
  _ufile_rel="modules/users/${USERS_LOGIN[$_i]}.nix"
  if [[ -f "/mnt/etc/nixos/$_ufile_rel" ]]; then
    git -C /mnt/etc/nixos add "$_ufile_rel" 2>/dev/null || true
    success "File $_ufile_rel re-indexed at /mnt/etc/nixos."
  else
    warn "File $_ufile_rel not found at /mnt/etc/nixos after rsync!"
  fi
done

# Re-index the host files (the disk device may have changed in step 2)
git -C /mnt/etc/nixos add \
  "modules/hosts/$HOST/default.nix" \
  "modules/hosts/$HOST/_hardware-configuration.nix" 2>/dev/null || true

info "Running nixos-install..."
# Passes the binary caches explicitly so nixos-install uses them even if
# the live CD's nix.conf doesn't have them. This avoids compiling from
# scratch and fragile dependency downloads.
# --no-root-password: the root password is set exclusively in step 8,
# where the copy to /persist/etc/shadow is guaranteed. Without this flag,
# nixos-install would also ask for a root password, but that password
# would never reach /persist/etc/shadow (the copy happens in step 8,
# after nixos-install).
nixos-install \
  --flake "/mnt/etc/nixos#$FLAKE_SYSTEM_ATTR" \
  --no-root-password \
  --option accept-flake-config true \
  --option extra-substituters "$NIX_COMMUNITY_SUBSTITUTER" \
  --option extra-trusted-public-keys "$NIX_COMMUNITY_KEY"
success "NixOS installed successfully!"

# -----------------------------------------------------------------------
# 7c. Copy Wi-Fi connections from the live CD to the installed system
# -----------------------------------------------------------------------
# The /etc/NetworkManager/system-connections directory is already
# declared in modules/nixos/core/preservation.nix to be persisted (symlink
# to /persist/etc/NetworkManager/system-connections). By
# copying the profiles here, they'll be available immediately on the
# first boot — with no need to retype the SSID and password. The
# declarative networks (modules/nixos/hardware/wifi-home.nix) are created by
# NixOS on activation, complementing the copied profiles.
# 600 permissions are mandatory: NetworkManager ignores/rejects profiles
# with more open permissions.
echo
info "==> Step 7c: Copy Wi-Fi connections to the installed system"
_NM_SRC="/etc/NetworkManager/system-connections"
_NM_DST="/mnt/persist/etc/NetworkManager/system-connections"
_nm_copied=0
if [[ -d "$_NM_SRC" ]]; then
  while IFS= read -r -d '' _profile; do
    mkdir -p "$_NM_DST"
    install -m 600 "$_profile" "$_NM_DST/"
    ((_nm_copied++)) || true
  done < <(find "$_NM_SRC" -maxdepth 1 -type f -print0)
fi
if ((_nm_copied > 0)); then
  success "$_nm_copied Wi-Fi connection(s) copied to $_NM_DST."
else
  info "No Wi-Fi connection found on the live CD. Skipping."
fi

# ---------------------------------------------------------------------------
# 7b. Personal age keys from Bitwarden
# ---------------------------------------------------------------------------
# Each user-<login>.txt read in step 0a becomes ~/.config/sops/age/keys.txt
# (the sops.age.keyFile of the Home Manager sops-nix). Ownership comes from
# /mnt/etc/passwd, written by nixos-install.

if [[ "$OPT_AGE_KEYS_FROM_BITWARDEN" == "true" ]]; then
  echo
  info "==> Step 7b: Personal age keys (Bitwarden)"
  shopt -s nullglob
  for _key in "$INSTALL_BW_KEYS_DIR"/user-*.txt; do
    _login="$(basename "$_key" .txt)"
    _login="${_login#user-}"
    _pw="$(grep "^${_login}:" /mnt/etc/passwd 2>/dev/null || true)"
    if [[ -z "$_pw" ]]; then
      info "'$_login' isn't a user of this installation. Skipping its key."
      continue
    fi
    IFS=: read -r _ _ _uid _gid _ _home _ <<<"$_pw"
    _dst_dir="/mnt${_home}/.config/sops/age"
    for _d in "/mnt${_home}" "/mnt${_home}/.config" "/mnt${_home}/.config/sops" "$_dst_dir"; do
      [[ -d "$_d" ]] || install -d -o "$_uid" -g "$_gid" -m 700 "$_d"
    done
    install -o "$_uid" -g "$_gid" -m 600 "$_key" "$_dst_dir/keys.txt"
    success "Personal age key installed for '$_login'."
  done
  shopt -u nullglob
fi

# ---------------------------------------------------------------------------
# 8. Initial passwords
# ---------------------------------------------------------------------------
# Every user starts without a password (users.users.*.initialHashedPassword
# = "" in modules/nixos/core/users.nix), already expired — GDM's "set the
# password at next login": the empty password only works while expired
# (nullresetok, security/first-login.nix), and on the first login the greeter
# asks just for the new password and its confirmation (greetd patched to call
# pam_chauthtok). detectInitialPasswords would expire it on the first boot
# anyway; doing it here also covers the very first login.

echo
info "==> Step 8: Initial passwords (none; each user sets theirs on first login)"

# Combine users already in the modules + created in this session, without duplicates.
# This ensures every user of the installed system gets the expired password.
declare -A _passwd_users_seen=()
_ALL_PASSWD_USERS=()
for _u in "${_EXISTING_USERS[@]}" "${USERS_LOGIN[@]}"; do
  if [[ -z "${_passwd_users_seen[$_u]+set}" ]]; then
    _passwd_users_seen[$_u]=1
    _ALL_PASSWD_USERS+=("$_u")
  fi
done

# chage/passwd --root /mnt write directly to /mnt/etc/shadow on the host
# (without chroot), avoiding interference with the /etc/shadow bind mount
# that restoreShadow may have created inside nixos-install's or
# nixos-enter's mount namespace.
for _user in "${_ALL_PASSWD_USERS[@]}"; do
  [[ "$_user" == "root" ]] && continue

  # Skip names that aren't users of the installed system (requires that
  # nixos-install, step 7, has completed).
  if ! grep -q "^${_user}:" /mnt/etc/passwd 2>/dev/null; then
    continue
  fi

  if chage --root /mnt -d 0 "$_user"; then
    success "'$_user': no password yet; the greeter asks for a new one on first login."
  else
    warn "Could not expire the initial password of '$_user'."
  fi
done

# Root password: hashed in step 1 (otherwise root stays locked).
if [[ -n "$ROOT_HASH" ]]; then
  if usermod --root /mnt -p "$ROOT_HASH" root; then
    success "Root password set."
  else
    warn "Could not set the root password."
  fi
fi

# Copy /etc/shadow to /persist/etc/shadow so passwords survive the boot
# (the tmpfs root is wiped on every boot, /persist is preserved via Btrfs).
#
# Note: chage/passwd --root /mnt write directly to /mnt/etc/shadow.
# If the restoreShadow activation script (users.nix) created a bind mount
# from /mnt/persist/etc/shadow → /mnt/etc/shadow inside nixos-install's
# mount namespace and that bind mount propagated to the host,
# /mnt/etc/shadow and /mnt/persist/etc/shadow point to the same file. Using
# `install` for the copy is safe in that case (reads the current content,
# writes to a new inode, replaces atomically). If the bind mount did NOT
# propagate, /mnt/etc/shadow is the shadow modified by chage/passwd and the copy
# ensures it persists.
mkdir -p /mnt/persist/etc
if [ -s /mnt/etc/shadow ]; then
  install -m 640 /mnt/etc/shadow /mnt/persist/etc/shadow
  success "/etc/shadow copied to /persist/etc/shadow (persists across boots)."
else
  warn "/mnt/etc/shadow not found or empty; skipping copy to /persist."
fi

# ---------------------------------------------------------------------------
# 8b. Register the YubiKey for U2F authentication (pamu2fcfg)
# ---------------------------------------------------------------------------
# The system uses pam_u2f as the sole authentication method for
# sudo/run0/pkexec (no password fallback). Without the
# /persist/etc/u2f-mappings file, it will be impossible to escalate
# privileges after boot.

echo
info "==> Step 8b: Register the YubiKey for U2F authentication (pamu2fcfg)"

_U2F_AUTHFILE="/mnt/persist/etc/u2f-mappings"

# Check whether the installed system configures pam_u2f for sudo
_U2F_CONFIGURED=false
if grep -qF "pam_u2f" /mnt/etc/static/pam.d/sudo 2>/dev/null || \
   grep -qF "pam_u2f" /mnt/etc/pam.d/sudo 2>/dev/null; then
  _U2F_CONFIGURED=true
fi

if [[ "$_U2F_CONFIGURED" != "true" ]]; then
  info "The installed system doesn't use pam_u2f for sudo. Skipping."
else
  # Find the wheel group's users on the installed system
  _WHEEL_USERS_U2F=()
  if [[ -f /mnt/etc/group ]]; then
    _wheel_members="$(grep "^wheel:" /mnt/etc/group | cut -d: -f4)"
    if [[ -n "$_wheel_members" ]]; then
      IFS=',' read -ra _WHEEL_USERS_U2F <<< "$_wheel_members"
    fi
  fi

  if [[ ${#_WHEEL_USERS_U2F[@]} -eq 0 ]]; then
    warn "No user found in the wheel group on the installed system. Skipping."
  else
    info "wheel users: ${_WHEEL_USERS_U2F[*]}"

    # Check whether the YubiKey is connected (vendor ID 1050 = Yubico)
    if ! lsusb 2>/dev/null | grep -qi "yubico"; then
      warn "YubiKey not detected (lsusb found no Yubico device)."
      warn "Without the $( basename "$_U2F_AUTHFILE" ) file, sudo/run0/pkexec will be denied after boot."
      warn "See INSTALLATION.md → 'sudo/run0 lockout' for recovery."
    else
      info "YubiKey detected. Starting registration for each wheel user..."
      mkdir -p "$(dirname "$_U2F_AUTHFILE")"
      _u2f_first=true

      for _wu in "${_WHEEL_USERS_U2F[@]}"; do
        _wu="${_wu// /}"  # remove leftover spaces from the split
        [[ -z "$_wu" ]] && continue

        echo
        info "Registering user '$_wu' — touch the YubiKey when its LED blinks."

        if [[ "$_u2f_first" == "true" ]]; then
          if _run_pamu2fcfg -u "$_wu" > "$_U2F_AUTHFILE"; then
            success "YubiKey registered for '$_wu'."
            _u2f_first=false
          else
            warn "Failed to register the YubiKey for '$_wu'. Try manually:"
            warn "  pamu2fcfg -u $_wu > /mnt/persist/etc/u2f-mappings"
          fi
        else
          if _run_pamu2fcfg -u "$_wu" >> "$_U2F_AUTHFILE"; then
            success "YubiKey registered for '$_wu'."
          else
            warn "Failed to register the YubiKey for '$_wu'. Try manually:"
            warn "  pamu2fcfg -u $_wu >> /mnt/persist/etc/u2f-mappings"
          fi
        fi
      done

      if [[ -f "$_U2F_AUTHFILE" && -s "$_U2F_AUTHFILE" ]]; then
        success "File $( basename "$_U2F_AUTHFILE" ) created:"
        while IFS= read -r _u2f_line; do
          info "  ${_u2f_line%%:*}: [credential registered]"
        done < "$_U2F_AUTHFILE"
      else
        warn "WARNING: $_U2F_AUTHFILE was not created or is empty."
        warn "sudo, run0 and pkexec will be denied after boot."
        warn "See INSTALLATION.md → 'sudo/run0 lockout' for recovery."
      fi
    fi
  fi
fi

# ---------------------------------------------------------------------------
# 9. Home Manager — already activated by nixos-install
# ---------------------------------------------------------------------------
# Home Manager runs as a NixOS module (modules/nixos/core/home-manager.nix),
# so nixos-install (Step 7) already:
#   1. Built all user HM derivations (nixvim plugins, Noctalia/Umbriel configs, dotfiles)
#   2. Activated each user's HM configuration via the hm-activate-<user>
#      system activation script, creating dotfile symlinks in $HOME
#
# Running "home-manager switch" again here would re-evaluate the same Nix
# expressions and re-run the same activation scripts — doubling the RAM
# consumed by Nix evaluation for zero additional benefit.
#
# If any managed dotfiles are missing after the first boot, run:
#   just switch

echo
info "==> Step 9: Home Manager"
info "Already activated by nixos-install (Home Manager runs as a NixOS module)."
_hm_hint_shown=false
for _user in "${_ALL_PASSWD_USERS[@]}"; do
  [[ "$_user" == "root" ]] && continue
  grep -q "^${_user}:" /mnt/etc/passwd 2>/dev/null || continue
  if [[ "$_hm_hint_shown" == "false" ]]; then
    info "If any dotfiles are missing after the first boot, run:"
    _hm_hint_shown=true
  fi
  info "  just switch   (as ${_user}, rebuilds the system and every user's Home Manager)"
done

# ---------------------------------------------------------------------------
# 10. Wrap up
# ---------------------------------------------------------------------------

echo
echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════════════════════════╗${RESET}"
echo -e "${GREEN}${BOLD}║              Installation completed successfully!            ║${RESET}"
echo -e "${GREEN}${BOLD}╚══════════════════════════════════════════════════════════════╝${RESET}"
echo
echo -e "  To finish, unmount and reboot:"
echo -e "    ${CYAN}sudo umount -R /mnt${RESET}"
echo -e "    ${CYAN}sudo reboot${RESET}"
echo
echo -e "  After the first boot:"
echo -e "    • Enroll the Secure Boot keys (firmware in Setup Mode): ${CYAN}sudo scripts/setup-secureboot.sh${RESET}"
echo -e "      (see ${BOLD}INSTALLATION.md${RESET} → 'Secure Boot')"
echo -e "    • Then enable automatic LUKS unlock via TPM2: ${CYAN}sudo scripts/enroll-tpm2.sh${RESET}"
if [[ "$OPT_AGE_KEYS_FROM_BITWARDEN" == "true" ]]; then
  echo -e "    • Personal age keys already installed from Bitwarden (step 7b)."
  echo -e "    • install-from-bitwarden.sh locks the Bitwarden CLI on exit (otherwise: ${CYAN}bw lock${RESET})."
else
  echo -e "    • Clone and unlock nix-keys for each user that uses sops in Home Manager:"
  echo -e "        ${CYAN}# Example for the abutre user:${RESET}"
  echo -e "        ${CYAN}git clone git@github.com:lbssousa/nix-keys.git \"\$(xdg-user-dir PROJECTS)/lbssousa/nix-keys\"${RESET}"
  echo -e "        ${CYAN}cd \"\$(xdg-user-dir PROJECTS)/lbssousa/nix-keys\" && git-crypt unlock${RESET}"
  echo -e "        ${CYAN}just switch        # activation copies the personal key automatically${RESET}"
fi
echo
if [[ "$_U2F_CONFIGURED" == "true" ]] && [[ ! -s "$_U2F_AUTHFILE" ]]; then
  echo -e "  ${YELLOW}${BOLD}⚠  WARNING: YubiKey not registered (step 8b incomplete).${RESET}"
  echo -e "  ${YELLOW}   sudo, run0 and pkexec will use a password until it's registered.${RESET}"
  echo -e "  ${YELLOW}   Register the YubiKey BEFORE unmounting (with the YubiKey inserted):${RESET}"
  echo
  if [[ ${#_WHEEL_USERS_U2F[@]} -gt 0 ]]; then
    _u2f_cmd_first=true
    for _wu in "${_WHEEL_USERS_U2F[@]}"; do
      _wu="${_wu// /}"
      [[ -z "$_wu" ]] && continue
      if [[ "$_u2f_cmd_first" == "true" ]]; then
        echo -e "    ${CYAN}pamu2fcfg -u $_wu > /mnt/persist/etc/u2f-mappings${RESET}"
        _u2f_cmd_first=false
      else
        echo -e "    ${CYAN}pamu2fcfg -u $_wu >> /mnt/persist/etc/u2f-mappings${RESET}"
      fi
    done
  else
    echo -e "    ${CYAN}pamu2fcfg -u <user> > /mnt/persist/etc/u2f-mappings${RESET}"
    echo -e "    ${CYAN}pamu2fcfg -u <other-user> >> /mnt/persist/etc/u2f-mappings${RESET}"
  fi
  echo
  echo -e "  ${YELLOW}   See INSTALLATION.md → 'Step 10' for complete instructions.${RESET}"
  echo
fi

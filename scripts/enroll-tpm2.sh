#!/usr/bin/env bash
# enroll-tpm2.sh — Set up automatic LUKS unlock via the TPM2 chip
#
# Uses systemd-cryptenroll to register the TPM2 as an authentication factor
# for the LUKS volume, letting the system automatically unlock the disk at
# boot — as long as the integrity measurements (PCRs) match the expected state.
#
# ⚠️  Run this script AFTER the system's first successful boot.
#
# Usage:
#   bash scripts/enroll-tpm2.sh [--device <partition>] [--pcrs <pcrs>]
#                               [--wipe] [--force] [--help]
#
# Options:
#   --device <partition>  LUKS partition (default: /dev/disk/by-partlabel/luks)
#   --pcrs <pcrs>         PCRs to watch (default: 0+2+7+15:sha256=<zeros>)
#                        0  = UEFI firmware
#                        2  = UEFI option code (ROM drivers)
#                        7  = Secure Boot state
#                        15 = volume key, required to still be zero: the
#                             initrd extends it right after unlocking
#                             (crypttab tpm2-measure-pcr=yes), so the TPM
#                             releases the key only once, before any volume
#                             (genuine or forged) has been opened
#   --wipe                Remove the existing TPM2 slot before re-enrolling
#                        (useful for re-enrolling after firmware changes)
#   --force               Enroll PCR 15 even if it is still zero right now
#                        (the measurement isn't active in the booted initrd)
#   --help, -h            Show help and exit

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

# ---------------------------------------------------------------------------
# Ensure running as root
# ---------------------------------------------------------------------------

if [[ $EUID -ne 0 ]]; then
  info "This script must run as root. Re-executing with run0..."
  exec run0 bash "${BASH_SOURCE[0]}" "$@"
fi

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------

ZERO_SHA256="0000000000000000000000000000000000000000000000000000000000000000"
OPT_DEVICE="/dev/disk/by-partlabel/luks"
OPT_PCRS="0+2+7+15:sha256=${ZERO_SHA256}"
OPT_WIPE=false
OPT_FORCE=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --device) OPT_DEVICE="$2"; shift 2 ;;
    --pcrs)   OPT_PCRS="$2";   shift 2 ;;
    --wipe)   OPT_WIPE=true;   shift ;;
    --force)  OPT_FORCE=true;  shift ;;
    --help|-h)
      cat <<'EOF'
Usage:
  bash scripts/enroll-tpm2.sh [--device <partition>] [--pcrs <pcrs>]
                              [--wipe] [--force] [--help]

Options:
  --device <partition>  LUKS partition (default: /dev/disk/by-partlabel/luks)
  --pcrs <pcrs>         PCRs to watch, + separated
                       (default: 0+2+7+15:sha256=<64 zeros>)
                       0  = UEFI firmware (firmware integrity)
                       2  = UEFI option code (ROM drivers)
                       7  = Secure Boot state
                       15 = volume key, required to still be zero. The
                            initrd extends it right after unlocking the
                            disk (crypttab tpm2-measure-pcr=yes), so the
                            TPM releases the key only before any volume
                            has been opened: neither a forged LUKS volume
                            put in place of the real one nor the running
                            system can obtain it.
  --wipe                Remove the existing TPM2 slot before re-enrolling.
                       Use after firmware updates or Secure Boot changes
                       that invalidate the current slot.
  --force               Enroll even if PCR 15 is still zero right now, i.e.
                       the booted initrd doesn't measure the volume key yet
                       (without it, the PCR 15 protection is inactive).

Examples:
  # Default enrollment (PCRs 0+2+7+15, recommended with Secure Boot):
  run0 bash scripts/enroll-tpm2.sh

  # Without Secure Boot (firmware and option code, plus PCR 15):
  run0 bash scripts/enroll-tpm2.sh --pcrs 0+2+15:sha256=0000…0000

  # Re-enroll after a firmware update:
  run0 bash scripts/enroll-tpm2.sh --wipe

  # Alternate LUKS partition:
  run0 bash scripts/enroll-tpm2.sh --device /dev/nvme0n1p2

To revoke TPM2 access (e.g. before selling the hardware):
  run0 systemd-cryptenroll --wipe-slot=tpm2 /dev/disk/by-partlabel/luks
EOF
      exit 0 ;;
    *) die "Unknown option: $1. Use --help to see the available options." ;;
  esac
done

DEVICE="$OPT_DEVICE"
PCRS="$OPT_PCRS"

echo
echo -e "${BOLD}╔══════════════════════════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}║              LUKS Unlock via TPM2 Setup                      ║${RESET}"
echo -e "${BOLD}╚══════════════════════════════════════════════════════════════╝${RESET}"
echo

# ---------------------------------------------------------------------------
# Checks
# ---------------------------------------------------------------------------

info "==> Checking prerequisites..."

# Check whether the LUKS device exists
if [[ ! -b "$DEVICE" ]]; then
  die "LUKS device not found: $DEVICE
  Check with: ls -la /dev/disk/by-partlabel/
  Or specify the correct path with --device <partition>"
fi
success "LUKS device found: $DEVICE"

# Check whether TPM2 is available
if ! command -v systemd-cryptenroll >/dev/null 2>&1; then
  die "systemd-cryptenroll not found. Check that systemd is installed."
fi

TPM_DEVICES=$(ls /dev/tpm* 2>/dev/null || true)
if [[ -z "$TPM_DEVICES" ]]; then
  die "No TPM device found at /dev/tpm*.
  Check whether TPM2 is enabled in the system's UEFI/BIOS."
fi
success "TPM2 detected: $TPM_DEVICES"

# Check whether cryptsetup is available
if ! command -v cryptsetup >/dev/null 2>&1; then
  die "cryptsetup not found."
fi

# Check whether the device is a LUKS volume
if ! cryptsetup isLuks "$DEVICE" 2>/dev/null; then
  die "$DEVICE is not a valid LUKS volume."
fi
success "Valid LUKS volume: $DEVICE"

echo
info "Device: $DEVICE"
info "PCRs:   $PCRS"
echo

# PCR 15 measurement: the policy requires PCR 15 to be zero, so it only
# protects anything if the booted initrd extends PCR 15 after unlocking
# (crypttab tpm2-measure-pcr=yes, modules/nixos/security/tpm2.nix). With that
# active, PCR 15 is no longer zero by now.
pcr15_value() {
  systemd-analyze pcrs 15 2>/dev/null | awk '$1 == "15" { print $NF }'
}

USES_PCR15=false
[[ "$PCRS" == *"15:sha256=${ZERO_SHA256}"* ]] && USES_PCR15=true

if [[ "$USES_PCR15" == "true" ]]; then
  _pcr15="$(pcr15_value)"
  if [[ -z "$_pcr15" ]]; then
    warn "Could not read PCR 15 (systemd-analyze pcrs 15)."
  elif [[ "$_pcr15" == "$ZERO_SHA256" ]]; then
    if [[ "$OPT_FORCE" == "true" ]]; then
      warn "PCR 15 is still zero: the booted initrd doesn't measure the volume key."
      warn "Enrolling anyway (--force); the PCR 15 protection stays inactive until"
      warn "you boot an initrd with tpm2-measure-pcr=yes."
    else
      die "PCR 15 is still zero: the booted initrd doesn't measure the volume key yet.
  Activate the configuration with tpm2-measure-pcr=yes (just boot), reboot and
  run this script again. Use --force to enroll anyway."
    fi
  else
    success "PCR 15 already measured by the initrd (volume key): ${_pcr15:0:16}…"
  fi
  echo
fi

# A recovery key keeps the disk reachable if the TPM refuses (firmware update,
# Secure Boot change) and the passphrase is lost.
if ! cryptsetup luksDump "$DEVICE" 2>/dev/null | grep -q 'systemd-recovery'; then
  warn "No recovery key enrolled on $DEVICE. Consider creating one (and storing it"
  warn "in Bitwarden): run0 systemd-cryptenroll --recovery-key $DEVICE"
  echo
fi

# ---------------------------------------------------------------------------
# Remove existing TPM2 slot (if --wipe)
# ---------------------------------------------------------------------------

if [[ "$OPT_WIPE" == "true" ]]; then
  info "==> Removing existing TPM2 slot..."
  if systemd-cryptenroll --wipe-slot=tpm2 "$DEVICE"; then
    success "TPM2 slot removed."
  else
    warn "No TPM2 slot found to remove (or removal failed)."
  fi
  echo
fi

# ---------------------------------------------------------------------------
# Enroll the TPM2
# ---------------------------------------------------------------------------

info "==> Enrolling the TPM2 for the LUKS volume..."
info "    (You may be prompted for the LUKS password to authorize this)"
echo

systemd-cryptenroll \
  --tpm2-device=auto \
  --tpm2-pcrs="$PCRS" \
  "$DEVICE"

echo
success "TPM2 enrolled successfully!"
echo

# ---------------------------------------------------------------------------
# Verify the enrolled policy
# ---------------------------------------------------------------------------

info "==> TPM2 token on $DEVICE:"
cryptsetup luksDump "$DEVICE" | grep -A8 'systemd-tpm2' || true
echo

if [[ "$USES_PCR15" == "true" ]]; then
  if ! cryptsetup luksDump "$DEVICE" | grep -A8 'systemd-tpm2' | grep -Eq 'pcrs:.*(^|[^0-9])15([^0-9]|$)'; then
    warn "Could not confirm PCR 15 in the TPM2 token above; check it by hand."
  elif [[ "$(pcr15_value)" != "$ZERO_SHA256" ]]; then
    # Negative check: the token requires PCR 15 = 0 and PCR 15 isn't zero now,
    # so the running system can't get the key from the TPM (only the initrd,
    # before unlocking, can).
    success "Negative check: PCR 15 ≠ 0 now, so the TPM refuses the key to the running system."
  fi
  echo
fi
info "The system will automatically unlock the disk on the next boot,"
info "as long as the PCR measurements [$PCRS] match the current state."
echo
warn "IMPORTANT: Re-enroll the TPM2 after:"
warn "  • Firmware updates (UEFI/BIOS)"
warn "  • Secure Boot configuration changes"
warn "  • Hardware swaps (motherboard, TPM chip)"
echo
info "To revoke TPM2 access:"
echo "  run0 systemd-cryptenroll --wipe-slot=tpm2 $DEVICE"

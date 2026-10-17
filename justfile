set shell := ["bash", "-euo", "pipefail", "-c"]

flake_root := env_var_or_default("FLAKE_DIR", justfile_directory())
justfile_file := justfile_directory() + "/justfile"

# When "true", flake.lock is committed and pushed automatically after
# update/upgrade, if the file was modified.
# Usage: just auto_commit=false update   or   AUTO_COMMIT=false just update
auto_commit := env_var_or_default("AUTO_COMMIT", "true")

u2f_authfile := "/persist/etc/u2f-mappings"

# The flake (including the git+ssh nix-secrets input) is evaluated by the
# calling user, who reaches github.com through the Bitwarden SSH agent
# (SSH_AUTH_SOCK). Only the activation is elevated (nixos-rebuild --sudo).
[private]
_rebuild action host='' *args:
  #!/usr/bin/env bash
  set -euo pipefail
  host="{{host}}"
  host="${host:-$(hostname)}"
  sudo_flag=()
  case "{{action}}" in switch|boot|test) sudo_flag=(--sudo) ;; esac
  old_system="$(readlink -f /run/current-system)"
  nixos-rebuild "{{action}}" "${sudo_flag[@]}" --flake "{{flake_root}}#${host}" {{args}}
  if [[ "{{action}}" == "switch" ]]; then
    new_system="$(readlink -f /run/current-system)"
    if [[ "$old_system" != "$new_system" ]]; then
      echo ""
      echo "Packages changed in this switch:"
      nvd diff "$old_system" "$new_system"
    fi
  fi

default:
  @just --justfile "{{justfile_file}}" --list --unsorted

[group("info")]
show:
  cd "{{flake_root}}" && nix flake show

[group("info")]
systems:
  cd "{{flake_root}}" && nix eval --json .#nixosConfigurations --apply builtins.attrNames | jq -r '.[]'

# Applies NixOS + Home Manager (HM is a NixOS module).
switch host='' *args:
  just --justfile "{{justfile_file}}" _rebuild switch "{{host}}" {{args}}

boot host='' *args:
  just --justfile "{{justfile_file}}" _rebuild boot "{{host}}" {{args}}

test host='' *args:
  just --justfile "{{justfile_file}}" _rebuild test "{{host}}" {{args}}

build host='' *args:
  just --justfile "{{justfile_file}}" _rebuild build "{{host}}" {{args}}

# Shows the package diff between the running system and the current config.
diff host='':
  #!/usr/bin/env bash
  set -euo pipefail
  host="{{host}}"
  host="${host:-$(hostname)}"
  next="$(nix build "{{flake_root}}#nixosConfigurations.${host}.config.system.build.toplevel" --no-link --print-out-paths)"
  nvd diff /run/current-system "$next"

upgrade host='' *args:
  just --justfile "{{justfile_file}}" auto_commit="{{auto_commit}}" update
  just --justfile "{{justfile_file}}" switch "{{host}}" {{args}}

[group("maintenance")]
update *inputs:
  #!/usr/bin/env bash
  set -euo pipefail
  cd "{{flake_root}}"
  old_lock=$(mktemp)
  trap 'rm -f "$old_lock"' EXIT
  cp flake.lock "$old_lock"
  nix flake update "$@"
  if ! diff -q "$old_lock" flake.lock > /dev/null 2>&1; then
    echo ""
    echo "Input update summary:"
    jq -r --slurpfile old "$old_lock" '
      def short: if . == null then "-" else .[0:7] end;
      def date: if . == null then "-" else (. | gmtime | strftime("%Y-%m-%d")) end;
      ($old[0].nodes) as $old |
      .nodes as $new |
      ($old | keys) as $old_names |
      ($new | keys) as $new_names |
      ($new_names - ["root"] - $old_names) as $added |
      ($old_names - ["root"] - $new_names) as $removed |
      (($new_names - ["root"]) - $added - $removed) as $common |
      ( $common[] |
        ($old[.].locked // {}) as $ol |
        ($new[.].locked // {}) as $nl |
        select($ol != $nl) |
        "  ~ \(.): \($ol.rev | short) (\($ol.lastModified | date)) -> \($nl.rev | short) (\($nl.lastModified | date))"
      ),
      ( $added[] | "  + \(.): new input" ),
      ( $removed[] | "  - \(.): removed" )
    ' flake.lock
    echo ""
  fi
  if [[ "{{auto_commit}}" == "true" ]] && ! git diff --quiet flake.lock; then
    git add flake.lock
    git commit -m "flake: update flake.lock"
    git push
  fi

[group("maintenance")]
gc period='30d':
  #!/usr/bin/env bash
  set -euo pipefail
  period_spec="${1:-30d}"

  case "$period_spec" in
    full)
      nix-collect-garbage --delete-old
      ;;
    *)
      nix-collect-garbage --delete-older-than "$period_spec"
      ;;
  esac

[group("verification")]
check *args:
  #!/usr/bin/env bash
  set -euo pipefail
  cd "{{flake_root}}"
  nix flake check "$@"

[group("verification")]
lint:
  cd "{{flake_root}}" && nix run nixpkgs#statix -- check .

[group("verification")]
deadcode:
  cd "{{flake_root}}" && nix run nixpkgs#deadnix -- --fail .

[group("verification")]
fmt:
  #!/usr/bin/env bash
  set -euo pipefail
  cd "{{flake_root}}"
  nix run nixpkgs#nixfmt -- $(find . -name '*.nix' -not -path './.git/*')

[group("verification")]
fmt-check:
  #!/usr/bin/env bash
  set -euo pipefail
  cd "{{flake_root}}"
  nix run nixpkgs#nixfmt -- --check $(find . -name '*.nix' -not -path './.git/*')

[group("verification")]
hooks:
  git config core.hooksPath .githooks
  @echo "✅ Git hooks configured in .githooks/"

[group("verification")]
validate:
  just --justfile "{{justfile_file}}" fmt-check
  just --justfile "{{justfile_file}}" lint
  just --justfile "{{justfile_file}}" deadcode
  just --justfile "{{justfile_file}}" check --show-trace

# Registers a YubiKey in the system authfile for the given user (default: current user).
# First key: creates the line in the authfile. Additional key: appends to the existing line.
# Reference: security/yubikey/setup.sh (dotfiles)
[group("yubikey")]
yubikey-register user='':
  #!/usr/bin/env bash
  set -euo pipefail
  authfile="{{u2f_authfile}}"
  target="{{user}}"
  target="${target:-$(id -un)}"

  echo "Registering YubiKey for '${target}'..."
  echo "Insert the YubiKey and touch it when prompted."
  echo ""

  if [ -f "${authfile}" ] && grep -q "^${target}:" "${authfile}"; then
    new_cred=$(pamu2fcfg -n -u "${target}")
    run0 sed -i "/^${target}:/ s|$|:${new_cred}|" "${authfile}"
    echo "Additional key registered for '${target}'."
  else
    new_line=$(pamu2fcfg -u "${target}")
    printf '%s\n' "${new_line}" | run0 tee -a "${authfile}" > /dev/null
    echo "First key registered for '${target}'."
  fi

  echo ""
  n=$(grep "^${target}:" "${authfile}" | tr ':' '\n' | tail -n +2 | grep ',' | wc -l)
  echo "Total keys for '${target}': ${n}"

# Removes all keys for a user from the authfile (asks for confirmation).
# Reference: security/yubikey/uninstall.sh (dotfiles)
[group("yubikey")]
yubikey-remove user:
  #!/usr/bin/env bash
  set -euo pipefail
  authfile="{{u2f_authfile}}"
  target="{{user}}"

  if [ ! -f "${authfile}" ] || ! grep -q "^${target}:" "${authfile}"; then
    echo "No key registered for '${target}'."
    exit 0
  fi

  n=$(grep "^${target}:" "${authfile}" | tr ':' '\n' | tail -n +2 | grep ',' | wc -l)
  read -rp "Remove ${n} key(s) from '${target}'? [y/N] " answer
  case "${answer}" in
    [yY]*)
      run0 sed -i "/^${target}:/d" "${authfile}"
      echo "Entries for '${target}' removed from the authfile."
      ;;
    *)
      echo "Operation cancelled."
      ;;
  esac

# Lists registered U2F keys. No argument: all users with a count.
[group("yubikey")]
yubikey-list user='':
  #!/usr/bin/env bash
  set -euo pipefail
  authfile="{{u2f_authfile}}"
  filter="{{user}}"

  if [ ! -f "${authfile}" ]; then
    echo "Authfile not found: ${authfile}"
    exit 1
  fi

  if [ -n "${filter}" ]; then
    if grep -q "^${filter}:" "${authfile}"; then
      n=$(grep "^${filter}:" "${authfile}" | tr ':' '\n' | tail -n +2 | grep ',' | wc -l)
      echo "${filter}: ${n} key(s) registered"
    else
      echo "No key registered for '${filter}'."
    fi
  else
    while IFS= read -r line; do
      u="${line%%:*}"
      n=$(printf '%s' "${line#*:}" | tr ':' '\n' | grep ',' | wc -l)
      printf "%-20s %s key(s)\n" "${u}" "${n}"
    done < "${authfile}"
  fi

# Checks hardware, authfile and PAM stack for U2F authentication diagnostics.
# Reference: security/yubikey/troubleshoot.sh (dotfiles)
[group("yubikey")]
yubikey-check:
  #!/usr/bin/env bash
  set -euo pipefail
  authfile="{{u2f_authfile}}"
  current_user=$(id -un)

  echo "=== U2F/FIDO2 diagnostics ==="
  echo ""

  echo "Hardware:"
  if lsusb 2>/dev/null | grep -qi yubico; then
    echo "  OK  YubiKey detected via USB"
    lsusb | grep -i yubico | sed 's/^/       /'
  else
    echo "  --  YubiKey not detected (plug in the YubiKey)"
  fi

  echo ""
  echo "Authfile (${authfile}):"
  if [ -f "${authfile}" ]; then
    echo "  OK  File exists"
    if grep -q "^${current_user}:" "${authfile}"; then
      n=$(grep "^${current_user}:" "${authfile}" | tr ':' '\n' | tail -n +2 | grep ',' | wc -l)
      echo "  OK  ${n} key(s) for '${current_user}'"
    else
      echo "  --  No entry for '${current_user}' — run: just yubikey-register"
    fi
    echo ""
    echo "  Registered users:"
    while IFS= read -r line; do
      u="${line%%:*}"
      n=$(printf '%s' "${line#*:}" | tr ':' '\n' | grep ',' | wc -l)
      printf "       %-20s %s key(s)\n" "${u}" "${n}"
    done < "${authfile}"
  else
    echo "  --  Authfile not found — run: just yubikey-register"
  fi

  echo ""
  echo "PAM sudo (auth):"
  grep "^auth" /etc/pam.d/sudo | sed 's|/nix/store/[^/]*/||g; s/^/  /'

# Tests interactive authentication (fingerprint → YubiKey → password) via run0.
[group("yubikey")]
yubikey-test:
  #!/usr/bin/env bash
  set -euo pipefail
  echo "Testing authentication (fingerprint → YubiKey → password)..."
  echo ""
  if run0 true; then
    echo ""
    echo "OK  Authentication succeeded."
  else
    echo ""
    echo "--  Authentication failed."
    exit 1
  fi

# NixOS VM test: login with an expired password through the patched greetd
# (modules/flake/tests.nix). Needs KVM.
[group("verification")]
test-greetd:
  cd "{{flake_root}}" && nix build -L --no-link ".#legacyPackages.$(nix eval --raw --impure --expr builtins.currentSystem).tests.greetd-expired-password"

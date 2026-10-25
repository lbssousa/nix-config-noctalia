set shell := ["bash", "-euo", "pipefail", "-c"]

flake_root := env_var_or_default("FLAKE_DIR", justfile_directory())
# The system's git mirror (root-owned, fast-forward only). switch/boot always
# build from it; a working clone only tests (build/test/diff/vm/check).
mirror := env_var_or_default("NIXOS_MIRROR", "/etc/nixos")
justfile_file := justfile_directory() + "/justfile"

# When "true", flake.lock is committed and pushed automatically after
# update/upgrade, if the file was modified.
# Usage: just auto_commit=false update   or   AUTO_COMMIT=false just update
auto_commit := env_var_or_default("AUTO_COMMIT", "true")

# pam_u2f's default per-user authfile, relative to each user's home. The
# Noctalia Security page (Configurações › Segurança) writes the same file.
u2f_keys := ".config/Yubico/u2f_keys"
# Central authfile used before the switch to per-user files; only read by yubikey-migrate.
u2f_legacy_authfile := "/persist/etc/u2f-mappings"

# The flake (including the git+ssh nix-secrets input) is evaluated by the
# calling user, who reaches github.com through the Bitwarden SSH agent
# (SSH_AUTH_SOCK). Only the activation is elevated (nixos-rebuild --elevate run0).
[private]
_rebuild action host='' *args:
  #!/usr/bin/env bash
  set -euo pipefail
  host="{{host}}"
  host="${host:-$(hostname)}"
  elevate_flag=()
  case "{{action}}" in switch|boot|test) elevate_flag=(--elevate run0) ;; esac
  flake="{{flake_root}}"
  case "{{action}}" in
    switch|boot)
      flake="{{mirror}}"
      if [[ "$(realpath "{{flake_root}}")" != "$(realpath "{{mirror}}")" ]] \
        && { [[ "$(git -C "{{flake_root}}" rev-parse HEAD)" != "$(git -C "{{mirror}}" rev-parse HEAD)" ]] \
          || [[ -n "$(git -C "{{flake_root}}" status --porcelain)" ]]; }; then
        echo "warning: building from {{mirror}}; changes in {{flake_root}} that were not" >&2
        echo "         pushed and synced (just sync) are not part of this generation" >&2
      fi
      ;;
  esac
  old_system="$(readlink -f /run/current-system)"
  nixos-rebuild "{{action}}" "${elevate_flag[@]}" --flake "${flake}#${host}" {{args}}
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

# Applies NixOS + Home Manager (HM is a NixOS module), always from the mirror.
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

# Update + push the lock (working clone only), then sync + switch.
upgrade host='' *args:
  #!/usr/bin/env bash
  set -euo pipefail
  if [[ "$(realpath "{{flake_root}}")" != "$(realpath "{{mirror}}")" ]]; then
    just --justfile "{{justfile_file}}" auto_commit="{{auto_commit}}" update
  fi
  just --justfile "{{justfile_file}}" sync
  just --justfile "{{justfile_file}}" switch "{{host}}" {{args}}

[group("maintenance")]
update *inputs:
  #!/usr/bin/env bash
  set -euo pipefail
  if [[ "$(realpath "{{flake_root}}")" == "$(realpath "{{mirror}}")" ]]; then
    echo "error: {{mirror}} is a mirror; update the lock in the working clone and push it" >&2
    exit 1
  fi
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

# Commits are made in the working clone and reach the mirror through its
# remote (HTTPS, no credentials).
# Fast-forwards the mirror to its remote.
[group("maintenance")]
sync:
  #!/usr/bin/env bash
  set -euo pipefail
  m="{{mirror}}"
  # The mirror belongs to root; git only runs elevated when it has to write.
  as_owner=()
  [[ -O "$m" ]] || as_owner=(run0)
  if [[ -n "$(git -C "$m" status --porcelain)" ]]; then
    echo "error: $m has local changes; it must stay a pure mirror" >&2
    git -C "$m" status --short >&2
    exit 1
  fi
  "${as_owner[@]}" git -C "$m" fetch --quiet origin
  if [[ "$(git -C "$m" rev-list --count '@{upstream}..HEAD')" -gt 0 ]]; then
    echo "error: $m has commits that are not on its remote:" >&2
    git -C "$m" log --oneline '@{upstream}..HEAD' >&2
    echo "Run 'just publish-mirror' in the working clone to push them." >&2
    exit 1
  fi
  "${as_owner[@]}" git -C "$m" merge --ff-only --quiet '@{upstream}'
  git -C "$m" log --oneline -1

# The mirror's own commits (the one install.sh makes for the generated user
# and host files) keep their hashes, so the next `just sync` fast-forwards.
# Pushes the mirror's local commits from the working clone.
[group("maintenance")]
publish-mirror:
  #!/usr/bin/env bash
  set -euo pipefail
  if [[ "$(realpath "{{flake_root}}")" == "$(realpath "{{mirror}}")" ]]; then
    echo "error: run this in the working clone, not in {{mirror}}" >&2
    exit 1
  fi
  cd "{{flake_root}}"
  git fetch --quiet "{{mirror}}" HEAD
  if git merge-base --is-ancestor FETCH_HEAD HEAD; then
    echo "Nothing to publish: the mirror has no commits missing here."
    exit 0
  fi
  git log --oneline HEAD..FETCH_HEAD
  # Local commits are replayed on top of the mirror's, never the other way.
  if git merge-base --is-ancestor HEAD FETCH_HEAD; then
    git merge --ff-only --quiet FETCH_HEAD
  else
    git rebase FETCH_HEAD
  fi
  git push

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

# Run inside `nix develop`.
# Copies the age keys from an unlocked nix-keys clone to the installation vault
# (secretspec "install"): Bitwarden.
[group("secrets")]
store-age-keys *args:
  bash "{{flake_root}}/scripts/store-age-keys.sh" {{args}}

# Registers a YubiKey in the user's authfile (~/.config/Yubico/u2f_keys; default: current user).
# First key: creates the line. Additional key: appends to the existing line.
# Another user's file is written as that user (run0 --user).
# Reference: security/yubikey/setup.sh (dotfiles)
[group("yubikey")]
yubikey-register user='':
  #!/usr/bin/env bash
  set -euo pipefail
  target="{{user}}"
  target="${target:-$(id -un)}"
  home=$(getent passwd "${target}" | cut -d: -f6)
  authfile="${home}/{{u2f_keys}}"
  as_target=()
  [ "${target}" = "$(id -un)" ] || as_target=(run0 --user="${target}")

  echo "Registering YubiKey for '${target}'..."
  echo "Insert the YubiKey and touch it when prompted."
  echo ""

  "${as_target[@]}" mkdir -p -m 700 "$(dirname "${authfile}")"
  if "${as_target[@]}" grep -q "^${target}:" "${authfile}" 2>/dev/null; then
    # -n prints ":<credential>" (no user name); normalize to a single leading ':'.
    new_cred=$(pamu2fcfg -n -u "${target}")
    new_cred="${new_cred#:}"
    "${as_target[@]}" sed -i "/^${target}:/ s|$|:${new_cred}|" "${authfile}"
    echo "Additional key registered for '${target}'."
  else
    new_line=$(pamu2fcfg -u "${target}")
    printf '%s\n' "${new_line}" | "${as_target[@]}" sh -c 'umask 077; cat >> "$1"' sh "${authfile}"
    echo "First key registered for '${target}'."
  fi

  echo ""
  n=$("${as_target[@]}" grep "^${target}:" "${authfile}" | tr ':' '\n' | tail -n +2 | grep -c ',' || true)
  echo "Total keys for '${target}': ${n}"

# Removes all keys of a user from their authfile (asks for confirmation).
# Reference: security/yubikey/uninstall.sh (dotfiles)
[group("yubikey")]
yubikey-remove user='':
  #!/usr/bin/env bash
  set -euo pipefail
  target="{{user}}"
  target="${target:-$(id -un)}"
  home=$(getent passwd "${target}" | cut -d: -f6)
  authfile="${home}/{{u2f_keys}}"
  as_target=()
  [ "${target}" = "$(id -un)" ] || as_target=(run0 --user="${target}")

  if ! "${as_target[@]}" grep -q "^${target}:" "${authfile}" 2>/dev/null; then
    echo "No key registered for '${target}'."
    exit 0
  fi

  n=$("${as_target[@]}" grep "^${target}:" "${authfile}" | tr ':' '\n' | tail -n +2 | grep -c ',' || true)
  read -rp "Remove ${n} key(s) from '${target}'? [y/N] " answer
  case "${answer}" in
    [yY]*)
      "${as_target[@]}" sed -i "/^${target}:/d" "${authfile}"
      echo "Entries for '${target}' removed from ${authfile}."
      ;;
    *)
      echo "Operation cancelled."
      ;;
  esac

# Lists the U2F keys registered for a user (default: current user).
[group("yubikey")]
yubikey-list user='':
  #!/usr/bin/env bash
  set -euo pipefail
  target="{{user}}"
  target="${target:-$(id -un)}"
  home=$(getent passwd "${target}" | cut -d: -f6)
  authfile="${home}/{{u2f_keys}}"
  as_target=()
  [ "${target}" = "$(id -un)" ] || as_target=(run0 --user="${target}")

  if "${as_target[@]}" grep -q "^${target}:" "${authfile}" 2>/dev/null; then
    n=$("${as_target[@]}" grep "^${target}:" "${authfile}" | tr ':' '\n' | tail -n +2 | grep -c ',' || true)
    echo "${target}: ${n} key(s) registered in ${authfile}"
  else
    echo "No key registered for '${target}'."
  fi

# One-time move from the central authfile ({{u2f_legacy_authfile}}) to each
# user's ~/.config/Yubico/u2f_keys. Run it BEFORE switching to the
# configuration without the central authfile, or sudo loses the YubiKey.
[group("yubikey")]
yubikey-migrate:
  #!/usr/bin/env bash
  set -euo pipefail
  legacy="{{u2f_legacy_authfile}}"
  if [ ! -f "${legacy}" ]; then
    echo "Nothing to migrate: ${legacy} does not exist."
    exit 0
  fi
  while IFS= read -r line; do
    [ -n "${line}" ] || continue
    user="${line%%:*}"
    creds="${line#*:}"
    if ! home=$(getent passwd "${user}" | cut -d: -f6) || [ -z "${home}" ]; then
      echo "Skipping '${user}': no such user."
      continue
    fi
    authfile="${home}/{{u2f_keys}}"
    # Runs as the user, so the file gets the right owner and mode.
    run0 --user="${user}" sh -c '
      set -eu
      umask 077
      mkdir -p "$(dirname "$1")"
      if grep -q "^$2:" "$1" 2>/dev/null; then
        echo "  $2: $1 already has an entry; left untouched."
      else
        printf "%s:%s\n" "$2" "$3" >> "$1"
        echo "  $2: migrated to $1"
      fi
    ' sh "${authfile}" "${user}" "${creds}"
  done < "${legacy}"
  read -rp "Delete ${legacy}? [y/N] " answer
  case "${answer}" in
    [yY]*) run0 rm -f "${legacy}" && echo "Removed ${legacy}." ;;
    *) echo "Kept ${legacy} (no longer read by pam_u2f)." ;;
  esac

# Checks hardware, authfile and PAM stack for U2F authentication diagnostics.
# Reference: security/yubikey/troubleshoot.sh (dotfiles)
[group("yubikey")]
yubikey-check:
  #!/usr/bin/env bash
  set -euo pipefail
  current_user=$(id -un)
  authfile="${HOME}/{{u2f_keys}}"

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
      n=$(grep "^${current_user}:" "${authfile}" | tr ':' '\n' | tail -n +2 | grep -c ',' || true)
      echo "  OK  ${n} key(s) for '${current_user}'"
    else
      echo "  --  No entry for '${current_user}' — run: just yubikey-register"
    fi
  else
    echo "  --  Authfile not found — run: just yubikey-register"
  fi
  if [ -f "{{u2f_legacy_authfile}}" ]; then
    echo "  --  {{u2f_legacy_authfile}} still exists and is no longer read — run: just yubikey-migrate"
  fi

  echo ""
  echo "PAM run0 (polkit-1, auth):"
  grep "^auth" /etc/pam.d/polkit-1 | sed 's|/nix/store/[^/]*/||g; s/^/  /'

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

# Boots a host's desktop in a throwaway VM (modules/nixos/core/vm.nix). The disk
# image (<host>.qcow2) stays in `dir` between runs; delete it to start over.
[group("verification")]
vm host='bigodon' dir='/tmp/nix-config-noctalia-vm':
  #!/usr/bin/env bash
  set -euo pipefail
  out="$(nix build "{{flake_root}}#nixosConfigurations.{{host}}.config.system.build.vm" --no-link --print-out-paths)"
  mkdir -p "{{dir}}"
  cd "{{dir}}"
  exec "$out/bin/run-{{host}}-vm"

#!/usr/bin/env bash
# activation-step.sh — Decide how to activate a freshly built generation
#
# Compares the running system with the next one and prints "switch" or "boot"
# on stdout (the reasons go to stderr). Used by `just upgrade` in auto mode.
#
# The answer is "boot" when switching now would either not take effect or
# tear down the graphical session (closing every open app, this terminal
# included):
#   - the kernel or its modules changed (out-of-tree ones, like NVIDIA,
#     included): they only load after a reboot, and a userspace driver that
#     no longer matches the loaded module breaks the GPU apps;
#   - the switch inhibitors changed: switch-to-configuration refuses to
#     switch (e.g. a different D-Bus implementation);
#   - a session-critical unit changed or disappeared and the next generation
#     would really restart or stop it (not X-RestartIfChanged=false,
#     X-ReloadIfChanged=true nor X-OnlyManualStart=true). Apps are Wayland
#     clients of the compositor (umbriel.service, a user unit): restarting it,
#     or what it is bound to, closes them.
# Anything else is "switch".
#
# Usage:
#   bash scripts/activation-step.sh [<current-system> [<next-system>]]
#   (defaults: /run/current-system and ./result)

set -euo pipefail

current="$(readlink -f "${1:-/run/current-system}")"
next="$(readlink -f "${2:-result}")"

# Units whose restart (or stop) ends the graphical session: display manager,
# logind, the user manager, the system and session buses, the compositor and
# the targets it is bound to.
system_units=(
  display-manager.service
  greetd.service
  systemd-logind.service
  user@.service
  dbus.service
  dbus-broker.service
)
user_units=(
  umbriel.service
  umbriel-session.target
  graphical-session.target
  graphical-session-pre.target
  dbus.service
  dbus-broker.service
)

reasons=()

same_path() {
  [[ "$(readlink -f "$current/$1" 2>/dev/null)" == "$(readlink -f "$next/$1" 2>/dev/null)" ]]
}

# Unit file plus drop-ins, in a stable order; empty when the unit is absent.
unit_content() {
  local dir="$1" unit="$2"
  [[ -e "$dir/$unit" ]] || return 0
  cat "$dir/$unit"
  if [[ -d "$dir/$unit.d" ]]; then
    find -L "$dir/$unit.d" -maxdepth 1 -name '*.conf' -type f -print0 | sort -z | xargs -0r cat
  fi
}

# Last assignment wins, as in systemd.
unit_flag() {
  local key="$1"
  grep -E "^${key}=" | tail -n 1 | cut -d= -f2- | tr -d '[:space:]'
}

check_units() {
  local scope="$1"
  shift
  local unit old new
  for unit in "$@"; do
    old="$(unit_content "$current/etc/systemd/$scope" "$unit")"
    new="$(unit_content "$next/etc/systemd/$scope" "$unit")"
    [[ "$old" == "$new" ]] && continue
    if [[ -z "$old" ]]; then
      continue # new unit: started, nothing torn down
    fi
    if [[ -z "$new" ]]; then
      reasons+=("$scope unit $unit would be stopped (removed)")
      continue
    fi
    if [[ "$(unit_flag X-RestartIfChanged <<< "$new")" == "false" ]] \
      || [[ "$(unit_flag X-ReloadIfChanged <<< "$new")" == "true" ]] \
      || [[ "$(unit_flag X-OnlyManualStart <<< "$new")" == "true" ]]; then
      continue
    fi
    reasons+=("$scope unit $unit would be restarted")
  done
}

same_path kernel || reasons+=("kernel changed")
same_path kernel-modules || reasons+=("kernel modules changed")
if ! cmp -s "$current/switch-inhibitors" "$next/switch-inhibitors" 2>/dev/null \
  && [[ -e "$current/switch-inhibitors" || -e "$next/switch-inhibitors" ]]; then
  reasons+=("switch inhibitors changed")
fi
check_units system "${system_units[@]}"
check_units user "${user_units[@]}"

if ((${#reasons[@]} > 0)); then
  {
    echo "auto: next step is boot:"
    printf '  - %s\n' "${reasons[@]}"
  } >&2
  echo boot
else
  echo "auto: no kernel change nor session restart; next step is switch" >&2
  echo switch
fi

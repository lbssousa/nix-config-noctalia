#!/usr/bin/env bash
# check-noctalia-cache.sh — fails if building a host would compile any package
# of the Noctalia family locally instead of fetching it from the
# lbssousa-noctalia Cachix (published by github.com/lbssousa/noctalia-nix).
#
#   scripts/check-noctalia-cache.sh [<flake dir>] <host>...
#
# It compares exact derivations: the drvPath of each package of the
# noctalia-nix input pinned in flake.lock against the "will be built" list of
# `nix build --dry-run` for each host. Light local derivations that only carry
# a family name (this repo's Noctalia wrapper, fish completions) don't count.
set -euo pipefail

flake=$PWD
if [[ $# -gt 0 && -d $1 ]]; then
  flake=$(cd "$1" && pwd)
  shift
fi
(($# > 0)) || { echo "usage: $0 [<flake dir>] <host>..." >&2; exit 2; }

pkgs=(noctalia noctalia-greeter umbriel xdg-desktop-portal-umbriel luciole noctalia-secret-prompts)
# Nix interpolation, not shell: keep the single quotes.
# shellcheck disable=SC2016
expr='flake: names: map (n: flake.inputs.noctalia-nix.packages.${builtins.currentSystem}.${n}.drvPath) names'
names=$(printf '"%s" ' "${pkgs[@]}")
mapfile -t drvs < <(nix eval --impure --json --expr \
  "($expr) (builtins.getFlake \"git+file://$flake\") [ $names ]" | jq -r '.[]')

status=0
for host in "$@"; do
  plan=$(nix build "$flake#nixosConfigurations.$host.config.system.build.toplevel" --dry-run 2>&1)
  built=$(awk '/will be built/{f=1; next} /will be fetched/{f=0} f' <<<"$plan")
  local_builds=$(grep -F -x -f <(printf '  %s\n' "${drvs[@]}") <<<"$built" || true)
  if [[ -n $local_builds ]]; then
    echo "$host: these Noctalia packages would be compiled locally instead of fetched from Cachix:" >&2
    echo "$local_builds" >&2
    status=1
  else
    echo "$host: Noctalia family fetched from the cache"
  fi
done
exit "$status"

#!/usr/bin/env bash
# noctalia-nix-secrets.sh — grava os segredos do CI do lbssousa/noctalia-nix
# (o flake agregador da família Noctalia) a partir do Bitwarden, pelo
# secretspec (provider bw://, perfil default de secretspec.toml):
#
#   CACHIX_AUTH_TOKEN  token de escrita do Cachix lbssousa-noctalia
#   FORKS_TOKEN        PAT fine-grained (Contents: read and write em
#                      lbssousa/noctalia, noctalia-greeter, umbriel e
#                      nix-config-noctalia): rebase dos forks e o
#                      repository_dispatch para este repositório
#
# Um token que ainda não esteja no cofre é pedido uma vez (sem eco) e
# guardado lá antes. Os valores nunca vão para a linha de comando nem para
# arquivos: passam pela entrada padrão do secretspec e do `gh secret set`.
#
# Rode no terminal (login e desbloqueio do Bitwarden são interativos):
#   bash scripts/noctalia-nix-secrets.sh [--repo dono/repo]
set -euo pipefail

repo=lbssousa/noctalia-nix
[[ ${1:-} == --repo ]] && repo=$2
keys=(CACHIX_AUTH_TOKEN FORKS_TOKEN)
provider=${SECRETSPEC_PROVIDER:-bw://}
flake_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

# --- Ferramentas: as do PATH (devShell do repo, NixOS) ou as do
# ~/.cache/lbssousa-tools (bw do npm, secretspec do release oficial).
tools="${XDG_CACHE_HOME:-$HOME/.cache}/lbssousa-tools"
if ! command -v bw >/dev/null 2>&1 && [[ -x $tools/npm/node_modules/.bin/bw ]]; then
  PATH="$tools/npm/node_modules/.bin:$PATH"
fi
if ! command -v secretspec >/dev/null 2>&1; then
  ss=$(find "$tools" -maxdepth 3 -type f -name secretspec 2>/dev/null | head -n1 || true)
  [[ -n $ss ]] && PATH="$(dirname "$ss"):$PATH"
fi
for tool in bw secretspec gh jq; do
  command -v "$tool" >/dev/null 2>&1 || {
    echo "Falta '$tool'. Use 'nix develop' neste repositório, ou rode antes o" >&2
    echo "script de configuração do Cachix, que instala bw e secretspec em $tools." >&2
    exit 1
  }
done
export PATH

# --- Sessão do Bitwarden.
status=$(bw status | jq -r .status)
if [[ $status == unauthenticated ]]; then
  bw login
  status=locked
fi
if [[ -z ${BW_SESSION:-} || $status != unlocked ]]; then
  BW_SESSION=$(bw unlock --raw)
  export BW_SESSION
fi
bw sync >/dev/null

cd "$flake_dir"
vault() { secretspec "$@" --provider "$provider" --profile default; }

for key in "${keys[@]}"; do
  if ! value=$(vault get "$key" 2>/dev/null) || [[ -z $value ]]; then
    read -rsp "$key não está no Bitwarden; cole o valor (sem eco): " value
    echo
    [[ -n $value ]] || { echo "Valor vazio para $key." >&2; exit 1; }
    printf '%s' "$value" | vault set "$key" --from-file -
    echo "  $key guardado no Bitwarden (secretspec, perfil default)."
  fi
  printf '%s' "$value" | gh secret set "$key" -R "$repo"
  echo "  $key gravado em $repo."
  unset value
done

echo "Pronto. Segredos de $repo:"
gh secret list -R "$repo"

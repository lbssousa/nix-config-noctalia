# shellcheck shell=bash
# bitwarden.sh — Bitwarden CLI session helper, sourced by the scripts that
# read the "install" profile of secretspec.toml.
#
#   bw_session [e-mail]
#     Exports BW_SESSION, reusing a valid session, unlocking a logged-in vault
#     or logging in from scratch. The two-step login defaults to YubiKey OTP
#     (method 3: the LONG touch, slot 2; slot 1 holds the HMAC-SHA1
#     challenge-response). Other methods: BW_2FA_METHOD=0 (authenticator app),
#     1 (e-mail). The e-mail comes from the argument, $BW_EMAIL or a prompt.
#     The master password only lives in this function's environment.
#     Prompts use gum when it's on PATH (install-from-bitwarden.sh provides it).

# _bw_ask VAR "prompt" [--password] [gum input options]
_bw_ask() {
  local __var="$1" prompt="$2" __value
  if command -v gum >/dev/null 2>&1; then
    __value="$(gum input --prompt "$prompt> " "${@:3}")" || return
  elif [[ "${3:-}" == "--password" ]]; then
    read -r -s -p "$prompt: " __value || return
    echo
  else
    read -r -p "$prompt: " __value || return
  fi
  printf -v "$__var" '%s' "$__value"
}

bw_session() {
  local email="${1:-${BW_EMAIL:-}}" method="${BW_2FA_METHOD:-3}"
  local status password code prompt

  if [[ -n "${BW_SESSION:-}" ]] && bw unlock --check >/dev/null 2>&1; then
    return 0
  fi

  status="$(bw status 2>/dev/null | sed -n 's/.*"status":"\([a-z]*\)".*/\1/p')"
  case "$status" in
    unlocked | locked)
      _bw_ask password "Bitwarden master password" --password --placeholder "" || return 1
      BW_SESSION="$(BW_PASSWORD="$password" bw unlock --passwordenv BW_PASSWORD --raw)" || return 1
      ;;
    unauthenticated)
      [[ -n "$email" ]] || _bw_ask email "Bitwarden e-mail" --placeholder "account of the vault" || return 1
      _bw_ask password "Bitwarden master password" --password --placeholder "" || return 1
      case "$method" in
        3) prompt="YubiKey OTP (touch and HOLD ~3 s)" ;;
        *) prompt="Two-step login code" ;;
      esac
      _bw_ask code "$prompt" --placeholder "" || return 1
      BW_SESSION="$(BW_PASSWORD="$password" bw login "$email" \
        --passwordenv BW_PASSWORD --method "$method" --code "$code" --raw)" || return 1
      ;;
    *)
      echo "bw status failed (is bitwarden-cli installed?)" >&2
      return 1
      ;;
  esac
  # bw exits 0 with an empty key when it gets no password (e.g. no terminal)
  [[ -n "$BW_SESSION" ]] && BW_SESSION="$BW_SESSION" bw unlock --check >/dev/null 2>&1 || {
    unset BW_SESSION
    echo "Bitwarden did not return a valid session." >&2
    return 1
  }
  export BW_SESSION
  bw sync >/dev/null
}

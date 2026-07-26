#!/usr/bin/env bash
set -Eeuo pipefail

readonly RULE_PATH="/etc/polkit-1/rules.d/49-browsec-deck-resolved.rules"

[[ "$(uname -s)" == "Linux" ]] || {
  printf 'Error: this script is intended for Linux/SteamOS\n' >&2
  exit 1
}
command -v sudo >/dev/null 2>&1 || {
  printf 'Error: sudo was not found\n' >&2
  exit 1
}

sudo rm -f -- "$RULE_PATH"
printf '%s\n' \
  "The rule was removed. systemd-resolved authentication prompts are restored."

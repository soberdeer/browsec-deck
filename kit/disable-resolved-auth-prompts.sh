#!/usr/bin/env bash
set -Eeuo pipefail

readonly RULE_PATH="/etc/polkit-1/rules.d/49-browsec-deck-resolved.rules"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
TARGET_USER="${SUDO_USER:-$(id -un)}"
TEMP_RULE=""

die() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

cleanup() {
  if [[ -n "$TEMP_RULE" && -f "$TEMP_RULE" ]]; then
    rm -f -- "$TEMP_RULE"
  fi
}
trap cleanup EXIT

while (($#)); do
  case "$1" in
    --user)
      (($# >= 2)) || die "--user requires a user name"
      TARGET_USER="$2"
      shift 2
      ;;
    -h|--help)
      printf 'Usage: ./disable-resolved-auth-prompts.sh [--user deck]\n'
      exit 0
      ;;
    *)
      die "unknown argument: $1"
      ;;
  esac
done

[[ "$(uname -s)" == "Linux" ]] || die "this script is intended for Linux/SteamOS"
command -v sudo >/dev/null 2>&1 || die "sudo was not found"
command -v getent >/dev/null 2>&1 || die "getent was not found"
id "$TARGET_USER" >/dev/null 2>&1 \
  || die "user '$TARGET_USER' does not exist"
[[ "$TARGET_USER" != "root" ]] || die "specify a regular user"
[[ "$TARGET_USER" =~ ^[a-z_][a-z0-9_-]*[$]?$ ]] \
  || die "the user name is incompatible with the safe Polkit template"

TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
[[ -n "$TARGET_HOME" && -d "$TARGET_HOME" ]] \
  || die "home directory for '$TARGET_USER' was not found"
[[ "$(id -un)" == "$TARGET_USER" || "${EUID:-$(id -u)}" -eq 0 ]] \
  || die "run this script as '$TARGET_USER'"
[[ -r "$SCRIPT_DIR/templates/49-browsec-deck-resolved.rules" ]] \
  || die "the Polkit rule template was not found"

mkdir -p -- "$TARGET_HOME/.cache"
TEMP_RULE="$(mktemp "$TARGET_HOME/.cache/browsec-resolved-polkit.XXXXXX")"
sed "s|@TARGET_USER@|$TARGET_USER|g" \
  "$SCRIPT_DIR/templates/49-browsec-deck-resolved.rules" >"$TEMP_RULE"

printf '%s\n' \
  "Passwordless authorization: org.freedesktop.resolve1.*" \
  "User: $TARGET_USER" \
  "Rule: $RULE_PATH"
sudo -v
sudo install -d -m 0755 -o root -g root /etc/polkit-1/rules.d
sudo install -m 0644 -o root -g root "$TEMP_RULE" "$RULE_PATH"

printf '%s\n' \
  "Done. Polkit will reload the rule automatically." \
  "Steam Deck and Browsec do not need to be restarted."

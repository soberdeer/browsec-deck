#!/usr/bin/env bash
set -Eeuo pipefail

TARGET_USER="${SUDO_USER:-$(id -un)}"
readonly POLKIT_RULE_PATH="/etc/polkit-1/rules.d/49-browsec-deck-resolved.rules"

die() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

while (($#)); do
  case "$1" in
    --user)
      (($# >= 2)) || die "--user requires a user name"
      TARGET_USER="$2"
      shift 2
      ;;
    -h|--help)
      printf 'Usage: ./uninstall.sh [--user deck]\n'
      exit 0
      ;;
    *)
      die "unknown argument: $1"
      ;;
  esac
done

command -v sudo >/dev/null 2>&1 || die "sudo was not found"
command -v getent >/dev/null 2>&1 || die "getent was not found"
command -v pgrep >/dev/null 2>&1 || die "pgrep was not found"
id "$TARGET_USER" >/dev/null 2>&1 || die "user '$TARGET_USER' does not exist"

TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
HOME_INSTALL_BASE="$TARGET_HOME/.local/share/browsec-deck-system"
LEGACY_INSTALL_BASE="/var/lib/browsec-deck"

if pgrep -f "^($HOME_INSTALL_BASE|$LEGACY_INSTALL_BASE)/app/(browsec-desktop|resources/xray/brow(box|ray))" \
  >/dev/null 2>&1
then
  die "The VPN is still running. Disconnect Browsec and quit the application first."
fi

sudo rm -rf -- "$HOME_INSTALL_BASE" "$LEGACY_INSTALL_BASE"
sudo rm -f -- "$POLKIT_RULE_PATH"
rm -f -- \
  "$TARGET_HOME/.local/bin/browsec-deck" \
  "$TARGET_HOME/.local/share/applications/browsec-deck.desktop" \
  "$TARGET_HOME/.local/share/icons/hicolor/256x256/apps/browsec-deck.png"

if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database "$TARGET_HOME/.local/share/applications" \
    >/dev/null 2>&1 || true
fi

printf '%s\n' \
  "Browsec Deck 1.0.0 has been removed." \
  "The systemd-resolved Polkit authorization has been removed." \
  "Account data and Electron settings were preserved in the user profile."

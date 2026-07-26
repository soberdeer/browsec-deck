#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
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
[[ "$TARGET_USER" != "root" ]] || die "specify a regular user"
[[ "$TARGET_USER" =~ ^[a-z_][a-z0-9_-]*[$]?$ ]] \
  || die "invalid target user name"
[[ "${EUID:-$(id -u)}" -eq 0 ]] \
  || die "uninstall must be started from the graphical installer"

TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
[[ -n "$TARGET_HOME" && -d "$TARGET_HOME" ]] \
  || die "home directory for '$TARGET_USER' was not found"
HOME_PARENT="$(cd -P -- "$(dirname -- "$TARGET_HOME")" && pwd -P)"
[[ "$HOME_PARENT" != "/" ]] || die "unsafe home parent"

SYSTEM_ROOT="$HOME_PARENT/.browsec-deck"
INSTALL_BASE="$SYSTEM_ROOT/$TARGET_USER"
LEGACY_HOME_INSTALL_BASE="$TARGET_HOME/.local/share/browsec-deck-system"
LEGACY_INSTALL_BASE="/var/lib/browsec-deck"

[[ -d "$SYSTEM_ROOT/.tmp" && ! -L "$SYSTEM_ROOT" && ! -L "$SYSTEM_ROOT/.tmp" ]] \
  || die "the verified root temporary directory is unavailable"
case "$SCRIPT_DIR/" in
  "$SYSTEM_ROOT/.tmp/"*) ;;
  *) die "the privileged uninstaller payload is outside the verified root temporary directory" ;;
esac

if pgrep -f "^($INSTALL_BASE|$LEGACY_HOME_INSTALL_BASE|$LEGACY_INSTALL_BASE)/app/(browsec-desktop|resources/xray/brow(box|ray))" \
  >/dev/null 2>&1
then
  die "The VPN is still running. Disconnect Browsec and quit the application first."
fi

if [[ -e "$SYSTEM_ROOT" || -L "$SYSTEM_ROOT" ]]; then
  [[ -d "$SYSTEM_ROOT" && ! -L "$SYSTEM_ROOT" ]] \
    || die "$SYSTEM_ROOT is not a real directory"
  owner="$(stat -c '%U:%G' "$SYSTEM_ROOT")"
  [[ "$owner" == "root:root" ]] \
    || die "unsafe owner for $SYSTEM_ROOT: $owner"
  mode="$(stat -c '%a' "$SYSTEM_ROOT")"
  [[ "$mode" =~ ^[0-7]{3,4}$ ]] || die "cannot verify $SYSTEM_ROOT permissions"
  (( (8#$mode & 0022) == 0 )) \
    || die "$SYSTEM_ROOT is writable by group or other users"

  [[ ! -L "$INSTALL_BASE" ]] || die "$INSTALL_BASE is a symbolic link"
  rm -rf -- "$INSTALL_BASE"
  rmdir -- "$SYSTEM_ROOT/.tmp" 2>/dev/null || true
  rmdir -- "$SYSTEM_ROOT" 2>/dev/null || true
fi

if [[ -L "$LEGACY_HOME_INSTALL_BASE" ]]; then
  rm -f -- "$LEGACY_HOME_INSTALL_BASE"
else
  rm -rf -- "$LEGACY_HOME_INSTALL_BASE"
fi
rm -rf -- "$LEGACY_INSTALL_BASE"
rm -f -- "$POLKIT_RULE_PATH"
rm -f -- \
  "$TARGET_HOME/.local/bin/browsec-deck" \
  "$TARGET_HOME/.local/share/applications/browsec-deck.desktop" \
  "$TARGET_HOME/.local/share/icons/hicolor/256x256/apps/browsec-deck.png"

if command -v update-desktop-database >/dev/null 2>&1; then
  sudo -u "$TARGET_USER" update-desktop-database \
    "$TARGET_HOME/.local/share/applications" \
    >/dev/null 2>&1 || true
fi

printf '%s\n' \
  "Browsec Deck 1.0.0 has been removed." \
  "The systemd-resolved Polkit authorization has been removed." \
  "Account data and Electron settings were preserved in the user profile."

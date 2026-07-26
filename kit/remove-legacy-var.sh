#!/usr/bin/env bash
set -Eeuo pipefail

readonly LEGACY_INSTALL_BASE="/var/lib/browsec-deck"
TARGET_USER="${SUDO_USER:-$(id -un)}"

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
      printf '%s\n' \
        "Removes only the old Browsec Deck installation from /var." \
        "Usage: ./remove-legacy-var.sh [--user deck]"
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
[[ -n "$TARGET_HOME" && -d "$TARGET_HOME" ]] \
  || die "home directory for '$TARGET_USER' was not found"

if pgrep -f "^$LEGACY_INSTALL_BASE/app/(browsec-desktop|resources/xray/brow(box|ray))" \
  >/dev/null 2>&1
then
  die "The old Browsec installation is still running. Disconnect the VPN and quit the application."
fi

if [[ -L "$LEGACY_INSTALL_BASE" ]]; then
  die "$LEGACY_INSTALL_BASE is a symlink; automatic removal was cancelled"
fi

legacy_kib=0
if sudo test -d "$LEGACY_INSTALL_BASE"; then
  legacy_kib="$(
    sudo du -sk -- "$LEGACY_INSTALL_BASE" 2>/dev/null | awk '{print $1}'
  )"
  [[ "$legacy_kib" =~ ^[0-9]+$ ]] || legacy_kib=0

  printf 'Removing only: %s\n' "$LEGACY_INSTALL_BASE"
  sudo rm -rf -- "$LEGACY_INSTALL_BASE"
  sudo test ! -e "$LEGACY_INSTALL_BASE" \
    || die "failed to remove $LEGACY_INSTALL_BASE completely"
else
  printf 'The old installation at %s was not found.\n' "$LEGACY_INSTALL_BASE"
fi

remove_if_legacy_reference() {
  local path="$1"
  local target=""

  if [[ -L "$path" ]]; then
    target="$(readlink -- "$path" 2>/dev/null || true)"
    if [[ "$target" == "$LEGACY_INSTALL_BASE" \
      || "$target" == "$LEGACY_INSTALL_BASE/"* ]]
    then
      rm -f -- "$path"
    fi
  elif [[ -f "$path" ]] && grep -Fq "$LEGACY_INSTALL_BASE" "$path"; then
    rm -f -- "$path"
  fi
}

remove_if_legacy_reference "$TARGET_HOME/.local/bin/browsec-deck"
remove_if_legacy_reference \
  "$TARGET_HOME/.local/share/applications/browsec-deck.desktop"

if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database "$TARGET_HOME/.local/share/applications" \
    >/dev/null 2>&1 || true
fi

if ((legacy_kib > 0)); then
  printf 'The old installation was removed; approximately %d MB was freed.\n' \
    "$((legacy_kib / 1024))"
else
  printf 'The current installation in ~/.local/share was not changed.\n'
fi

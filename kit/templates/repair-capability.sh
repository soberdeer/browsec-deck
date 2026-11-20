#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
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
      printf 'Usage: repair-capability.sh [--user deck]\n'
      exit 0
      ;;
    *)
      die "unknown argument: $1"
      ;;
  esac
done

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  die "repair must be started from the graphical installer"
fi

command -v getent >/dev/null 2>&1 || die "getent was not found"
command -v getcap >/dev/null 2>&1 || die "getcap was not found"
command -v setcap >/dev/null 2>&1 || die "setcap was not found"
id "$TARGET_USER" >/dev/null 2>&1 || die "user '$TARGET_USER' does not exist"
[[ "$TARGET_USER" != "root" ]] || die "specify a regular user"
[[ "$TARGET_USER" =~ ^[a-z_][a-z0-9_-]*[$]?$ ]] \
  || die "invalid target user name"

TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
[[ -n "$TARGET_HOME" && -d "$TARGET_HOME" ]] \
  || die "home directory for '$TARGET_USER' was not found"
HOME_PARENT="$(cd -P -- "$(dirname -- "$TARGET_HOME")" && pwd -P)"
[[ "$HOME_PARENT" != "/" ]] || die "unsafe home parent"

SYSTEM_ROOT="$HOME_PARENT/.browsec-deck"
INSTALL_BASE="$SYSTEM_ROOT/$TARGET_USER"
BROWBOX="$INSTALL_BASE/app/resources/xray/browbox"
POLKIT_RULE_PATH="/etc/polkit-1/rules.d/49-browsec-deck-resolved.rules"
RULE_TEMPLATE="$SCRIPT_DIR/49-browsec-deck-resolved.rules"

case "$SCRIPT_DIR/" in
  "$SYSTEM_ROOT/.tmp/"*) ;;
  *) die "the privileged repair payload is outside the verified root temporary directory" ;;
esac

for directory in "$HOME_PARENT" "$SYSTEM_ROOT" "$SYSTEM_ROOT/.tmp" "$INSTALL_BASE" "$INSTALL_BASE/app"; do
  [[ -d "$directory" && ! -L "$directory" ]] \
    || die "$directory is not a real directory"
  owner="$(stat -c '%U:%G' "$directory")"
  [[ "$owner" == "root:root" ]] \
    || die "unsafe directory owner for $directory: $owner"
  mode="$(stat -c '%a' "$directory")"
  [[ "$mode" =~ ^[0-7]{3,4}$ ]] || die "cannot verify $directory permissions"
  (( (8#$mode & 0022) == 0 )) \
    || die "$directory is writable by group or other users"
done

[[ -f "$BROWBOX" && ! -L "$BROWBOX" ]] \
  || die "$BROWBOX was not found or is a symbolic link"

owner="$(stat -c '%U:%G' "$BROWBOX")"
[[ "$owner" == "root:root" ]] || die "unsafe browbox owner: $owner"

if find "$INSTALL_BASE/app" -perm /0022 -print -quit | grep -q .; then
  die "group/world-writable application files were found; repair was stopped"
fi

setcap cap_net_admin+ep "$BROWBOX"
capability="$(getcap "$BROWBOX" || true)"
[[ "$capability" == *"cap_net_admin"* ]] \
  || die "failed to assign CAP_NET_ADMIN"

[[ -f "$RULE_TEMPLATE" && ! -L "$RULE_TEMPLATE" ]] \
  || die "the DNS authorization template is missing"
install -d -m 0755 -o root -g root /etc/polkit-1/rules.d
TEMP_RULE="$(mktemp "$SYSTEM_ROOT/.tmp/browsec-resolved.XXXXXX")"
trap 'rm -f -- "$TEMP_RULE"' EXIT
sed "s|@TARGET_USER@|$TARGET_USER|g" "$RULE_TEMPLATE" >"$TEMP_RULE"
install -m 0644 -o root -g root "$TEMP_RULE" "$POLKIT_RULE_PATH"

printf 'CAP_NET_ADMIN restored: %s\n' "$capability"
printf 'DNS authorization restored: %s\n' "$POLKIT_RULE_PATH"

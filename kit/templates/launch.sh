#!/usr/bin/env bash
set -Eeuo pipefail

readonly INSTALL_BASE="@INSTALL_BASE@"
readonly APP_DIR="$INSTALL_BASE/app"
readonly APP_BIN="$APP_DIR/browsec-desktop"
readonly BROWBOX="$APP_DIR/resources/xray/browbox"
readonly REPAIR="$INSTALL_BASE/repair-capability.sh"
readonly DECK_APP_ALIASES="$INSTALL_BASE/deck-app-aliases.json"

show_error() {
  local message="$1"
  if command -v kdialog >/dev/null 2>&1 && [[ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]]; then
    kdialog --title "Browsec Deck" --error "$message" || true
  elif command -v zenity >/dev/null 2>&1 && [[ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]]; then
    zenity --error --title="Browsec Deck" --text="$message" || true
  fi
  printf 'Browsec Deck: %s\n' "$message" >&2
}

[[ -x "$APP_BIN" ]] || {
  show_error "The application is not installed. Run install.sh again."
  exit 1
}

capability="$(getcap "$BROWBOX" 2>/dev/null || true)"
if [[ "$capability" != *"cap_net_admin"* ]]; then
  show_error "browbox is missing CAP_NET_ADMIN. Run: sudo $REPAIR"
  exit 1
fi

if [[ ! -c /dev/net/tun ]]; then
  show_error "/dev/net/tun is not available on this system."
  exit 1
fi

if [[ ! -r "$DECK_APP_ALIASES" ]]; then
  show_error "Steam Deck application profiles are missing. Run install.sh again."
  exit 1
fi

export BROWSEC_PRIVILEGE_MODE=manual
export BROWSEC_STEAM_DECK=1
export BDS="$(< "$DECK_APP_ALIASES")"
export BROWSEC_FORCED_X11=1
export ELECTRON_OZONE_PLATFORM_HINT=x11

exec "$APP_BIN" --ozone-platform=x11 "$@"

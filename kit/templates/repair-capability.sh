#!/usr/bin/env bash
set -Eeuo pipefail

readonly INSTALL_BASE="@INSTALL_BASE@"
readonly BROWBOX="$INSTALL_BASE/app/resources/xray/browbox"

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  printf 'Run through sudo: sudo %s\n' "$0" >&2
  exit 1
fi

[[ -f "$BROWBOX" ]] || {
  printf '%s was not found\n' "$BROWBOX" >&2
  exit 1
}

owner="$(stat -c '%U:%G' "$BROWBOX")"
[[ "$owner" == "root:root" ]] || {
  printf 'Unsafe browbox owner: %s\n' "$owner" >&2
  exit 1
}

if find "$INSTALL_BASE/app" -perm /0022 -print -quit | grep -q .; then
  printf 'Group/world-writable application files were found; repair was stopped.\n' >&2
  exit 1
fi

setcap cap_net_admin+ep "$BROWBOX"
capability="$(getcap "$BROWBOX" || true)"
[[ "$capability" == *"cap_net_admin"* ]] || {
  printf 'Failed to assign CAP_NET_ADMIN.\n' >&2
  exit 1
}

printf 'CAP_NET_ADMIN restored: %s\n' "$capability"

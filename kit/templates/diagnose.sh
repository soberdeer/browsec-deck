#!/usr/bin/env bash
set -u

readonly INSTALL_BASE="@INSTALL_BASE@"
readonly APP_DIR="$INSTALL_BASE/app"
readonly APP_BIN="$APP_DIR/browsec-desktop"
readonly BROWBOX="$APP_DIR/resources/xray/browbox"
readonly BROWRAY="$APP_DIR/resources/xray/browray"
readonly DECK_APP_ALIASES="$INSTALL_BASE/deck-app-aliases.json"
readonly EXPECTED_ASAR_SHA256="cfffdbdd82d216f1834449da993b7c1c1501462ea137645296839c4bf65f48e9"
readonly TARGET_USER="@TARGET_USER@"
readonly POLKIT_RULE="/etc/polkit-1/rules.d/49-browsec-deck-resolved.rules"

failures=0

ok() {
  printf 'OK    %s\n' "$*"
}

warn() {
  printf 'WARN  %s\n' "$*"
}

fail() {
  printf 'FAIL  %s\n' "$*"
  failures=$((failures + 1))
}

hash_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum -- "$1" | awk '{print $1}'
  else
    shasum -a 256 -- "$1" | awk '{print $1}'
  fi
}

printf 'Browsec Deck 1.0.0 — safe diagnostics without starting the VPN\n\n'

[[ "$(uname -s)" == "Linux" ]] && ok "Linux" || fail "Linux is required"
[[ "$(uname -m)" == "x86_64" ]] && ok "x86_64 architecture" || fail "architecture is not x86_64"
[[ -x "$APP_BIN" ]] && ok "Electron executable" || fail "$APP_BIN is missing"
[[ -x "$BROWBOX" ]] && ok "browbox" || fail "browbox is missing"
[[ -x "$BROWRAY" ]] && ok "browray" || fail "browray is missing"
[[ -c /dev/net/tun ]] && ok "/dev/net/tun" || fail "/dev/net/tun is missing"

if [[ -f "$APP_DIR/resources/app.asar" ]]; then
  actual_asar_sha="$(hash_file "$APP_DIR/resources/app.asar")"
  [[ "$actual_asar_sha" == "$EXPECTED_ASAR_SHA256" ]] \
    && ok "app.asar 1.2.2 with the verified Steam Deck patch" \
    || warn "app.asar differs: $actual_asar_sha"
else
  fail "app.asar is missing"
fi

if [[ -r "$DECK_APP_ALIASES" ]] \
  && grep -q '"key": "deck-steam"' "$DECK_APP_ALIASES" \
  && grep -q '"key": "deck-discover"' "$DECK_APP_ALIASES"
then
  ok "Steam Deck application profiles"
else
  fail "Steam Deck application profiles are missing"
fi

if command -v getcap >/dev/null 2>&1; then
  capability="$(getcap "$BROWBOX" 2>/dev/null || true)"
  [[ "$capability" == *"cap_net_admin"* ]] \
    && ok "browbox has CAP_NET_ADMIN" \
    || fail "CAP_NET_ADMIN is missing; run sudo $INSTALL_BASE/repair-capability.sh"
else
  fail "getcap was not found"
fi

if [[ -r "$POLKIT_RULE" ]] \
  && grep -Fq 'org.freedesktop.resolve1.' "$POLKIT_RULE" \
  && grep -Fq "subject.user === \"$TARGET_USER\"" "$POLKIT_RULE"
then
  ok "Polkit: systemd-resolved without password prompts for $TARGET_USER"
else
  fail "systemd-resolved Polkit rule is missing: $POLKIT_RULE"
fi

if [[ -O "$BROWBOX" ]]; then
  fail "browbox belongs to the current user; a root-owned file is required"
else
  owner="$(stat -c '%U:%G' "$BROWBOX" 2>/dev/null || printf unknown)"
  [[ "$owner" == "root:root" ]] && ok "browbox is root-owned" || warn "browbox owner: $owner"
fi

if command -v ldd >/dev/null 2>&1 && [[ -x "$BROWBOX" ]]; then
  missing="$(ldd "$BROWBOX" 2>/dev/null | awk '/not found/{print $1}' | paste -sd, -)"
  [[ -z "$missing" ]] && ok "browbox libraries found" || fail "missing libraries: $missing"
fi

if command -v unshare >/dev/null 2>&1 && unshare --user true >/dev/null 2>&1; then
  ok "unprivileged user namespaces"
else
  mode="$(stat -c '%a' "$APP_DIR/chrome-sandbox" 2>/dev/null || printf unknown)"
  [[ "$mode" == "4755" ]] \
    && ok "setuid Chromium sandbox" \
    || warn "user namespaces are unavailable, chrome-sandbox mode=$mode"
fi

printf '\n'
if ((failures == 0)); then
  printf 'Diagnostics complete: no critical problems found.\n'
  exit 0
fi

printf 'Diagnostics complete: %d problem(s) found.\n' "$failures"
exit 1

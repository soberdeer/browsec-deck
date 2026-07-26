#!/usr/bin/env bash
set -u

readonly INSTALL_BASE="@INSTALL_BASE@"
readonly APP_DIR="$INSTALL_BASE/app"
readonly APP_BIN="$APP_DIR/browsec-desktop"
readonly BROWBOX="$APP_DIR/resources/xray/browbox"
readonly BROWRAY="$APP_DIR/resources/xray/browray"
readonly DECK_APP_ALIASES="$INSTALL_BASE/deck-app-aliases.json"
readonly EXPECTED_ASAR_SHA256="ba3db3a0f8d8977113b8d96180f123f2082809c6490439bdd6a8de8bc6986f11"
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

if [[ "$(uname -s)" == "Linux" ]]; then ok "Linux"; else fail "Linux is required"; fi
if [[ "$(uname -m)" == "x86_64" ]]; then ok "x86_64 architecture"; else fail "architecture is not x86_64"; fi
if [[ -x "$APP_BIN" ]]; then ok "Electron executable"; else fail "$APP_BIN is missing"; fi
if [[ -x "$BROWBOX" ]]; then ok "browbox"; else fail "browbox is missing"; fi
if [[ -x "$BROWRAY" ]]; then ok "browray"; else fail "browray is missing"; fi
if [[ -c /dev/net/tun ]]; then ok "/dev/net/tun"; else fail "/dev/net/tun is missing"; fi

if [[ -f "$APP_DIR/resources/app.asar" ]]; then
  actual_asar_sha="$(hash_file "$APP_DIR/resources/app.asar")"
  if [[ "$actual_asar_sha" == "$EXPECTED_ASAR_SHA256" ]]; then
    ok "app.asar 1.2.2 with verified Steam Deck and Electron security patches"
  else
    warn "app.asar differs: $actual_asar_sha"
  fi
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
  if [[ "$capability" == *"cap_net_admin"* ]]; then
    ok "browbox has CAP_NET_ADMIN"
  else
    fail "CAP_NET_ADMIN is missing; open the installer and choose Repair VPN permissions"
  fi
else
  fail "getcap was not found"
fi

if [[ -r "$POLKIT_RULE" ]] \
  && grep -Fq 'org.freedesktop.resolve1.set-dns-servers' "$POLKIT_RULE" \
  && grep -Fq 'org.freedesktop.resolve1.set-domains' "$POLKIT_RULE" \
  && grep -Fq 'org.freedesktop.resolve1.set-default-route' "$POLKIT_RULE" \
  && grep -Fq 'org.freedesktop.resolve1.revert' "$POLKIT_RULE" \
  && grep -Fq "subject.user === \"$TARGET_USER\"" "$POLKIT_RULE"
then
  ok "Polkit: only required systemd-resolved actions are authorized for $TARGET_USER"
else
  fail "systemd-resolved Polkit rule is missing: $POLKIT_RULE"
fi

if [[ -O "$BROWBOX" ]]; then
  fail "browbox belongs to the current user; a root-owned file is required"
else
  owner="$(stat -c '%U:%G' "$BROWBOX" 2>/dev/null || printf unknown)"
  if [[ "$owner" == "root:root" ]]; then
    ok "browbox is root-owned"
  else
    warn "browbox owner: $owner"
  fi
fi

if command -v ldd >/dev/null 2>&1 && [[ -x "$BROWBOX" ]]; then
  missing="$(ldd "$BROWBOX" 2>/dev/null | awk '/not found/{print $1}' | paste -sd, -)"
  if [[ -z "$missing" ]]; then
    ok "browbox libraries found"
  else
    fail "missing libraries: $missing"
  fi
fi

if command -v unshare >/dev/null 2>&1 && unshare --user true >/dev/null 2>&1; then
  ok "unprivileged user namespaces"
else
  mode="$(stat -c '%a' "$APP_DIR/chrome-sandbox" 2>/dev/null || printf unknown)"
  if [[ "$mode" == "4755" ]]; then
    ok "setuid Chromium sandbox"
  else
    warn "user namespaces are unavailable, chrome-sandbox mode=$mode"
  fi
fi

printf '\n'
if ((failures == 0)); then
  printf 'Diagnostics complete: no critical problems found.\n'
  exit 0
fi

printf 'Diagnostics complete: %d problem(s) found.\n' "$failures"
exit 1

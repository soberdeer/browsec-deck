#!/usr/bin/env bash
set -Eeuo pipefail

readonly PRODUCT_NAME="Browsec Deck 1.0.0"
readonly EXPECTED_DEB_SHA256="479dcbfd72adb3d222c74acb06ef176aafd4472a2df90e37bc820083a5549896"
readonly EXPECTED_ASAR_SHA256="e1d60c72e0d02832d754a33e2d8a050adfc2a70d59c325aeb70f260141ae1907"
readonly PATCHED_ASAR_SHA256="cfffdbdd82d216f1834449da993b7c1c1501462ea137645296839c4bf65f48e9"
readonly EXPECTED_BROWBOX_SHA256="68aeab83cc4ab2659a5b92232261a20746ccdafc3b3d1e19b2d63247eec3bbf7"
readonly DECK_PATCH_OFFSET=167157093
readonly DECK_PATCH_LENGTH=962
readonly DECK_PATCH_SOURCE_SHA256="44837e0ab8d005eb8800d656748e78d4c6ccdfd6ff346f8941d98036b7570f92"
readonly DECK_PATCH_SHA256="333b332196767a4bf18c225c5096a4d48668a90bf453ef2dd56d6ee9ae488101"
readonly POLKIT_RULE_PATH="/etc/polkit-1/rules.d/49-browsec-deck-resolved.rules"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
DEB_PATH=""
TARGET_USER="${SUDO_USER:-$(id -un)}"
ALLOW_OTHER_VERSION=0
NO_DESKTOP_ENTRY=0
TEMP_DIR=""
INSTALL_BASE=""
APP_DIR=""

usage() {
  cat <<'EOF'
Install Browsec Deck 1.0.0 using the official Browsec 1.2.2 Linux payload.

Usage:
  ./install.sh [--deb /path/to/browsec-desktop_1.2.2_amd64.deb]
               [--user deck]
               [--allow-other-version]
               [--no-desktop-entry]

By default, the installer looks for the .deb in its payload directory, the
current directory, and ~/Downloads. The application is installed on the home
partition under ~/.local/share/browsec-deck-system.
EOF
}

die() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

note() {
  printf '%s\n' "$*"
}

cleanup() {
  if [[ -n "$TEMP_DIR" && -d "$TEMP_DIR" ]]; then
    rm -rf -- "$TEMP_DIR" 2>/dev/null || sudo rm -rf -- "$TEMP_DIR"
  fi
}
trap cleanup EXIT

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum -- "$1" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 -- "$1" | awk '{print $1}'
  else
    die "sha256sum or shasum was not found"
  fi
}

sha256_stream() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 | awk '{print $1}'
  else
    die "sha256sum or shasum was not found"
  fi
}

apply_deck_asar_patch() {
  local asar="$1"
  local patch="$SCRIPT_DIR/patches/deck-main-storage.patch"
  local source_block_sha

  [[ -f "$patch" ]] || die "the Steam Deck app.asar patch was not found"
  [[ "$(sha256_file "$patch")" == "$DECK_PATCH_SHA256" ]] \
    || die "the Steam Deck app.asar patch is damaged"
  [[ "$(sha256_file "$asar")" == "$EXPECTED_ASAR_SHA256" ]] \
    || die "the Steam Deck patch only supports the verified 1.2.2 app.asar"

  source_block_sha="$(
    dd if="$asar" bs=1M skip="$DECK_PATCH_OFFSET" count="$DECK_PATCH_LENGTH" \
      iflag=skip_bytes,count_bytes status=none | sha256_stream
  )"
  [[ "$source_block_sha" == "$DECK_PATCH_SOURCE_SHA256" ]] \
    || die "unexpected app.asar contents in the Steam Deck patch region"

  dd if="$patch" of="$asar" bs=1M seek="$DECK_PATCH_OFFSET" \
    conv=notrunc oflag=seek_bytes status=none

  [[ "$(sha256_file "$asar")" == "$PATCHED_ASAR_SHA256" ]] \
    || die "the patched app.asar failed verification"
}

find_deb() {
  local candidate
  local target_home
  target_home="$(getent passwd "$TARGET_USER" | cut -d: -f6)"

  for candidate in \
    "$SCRIPT_DIR/payload/browsec-desktop_1.2.2_amd64.deb" \
    "$SCRIPT_DIR/browsec-desktop_1.2.2_amd64.deb" \
    "$PWD/browsec-desktop_1.2.2_amd64.deb" \
    "$target_home/Downloads/browsec-desktop_1.2.2_amd64.deb"
  do
    if [[ -f "$candidate" ]]; then
      DEB_PATH="$candidate"
      return
    fi
  done
  die "browsec-desktop_1.2.2_amd64.deb was not found; use --deb"
}

extract_deb() {
  local deb="$1"
  local out="$2"
  local envelope="$TEMP_DIR/deb-envelope"
  local data_archive

  mkdir -p -- "$envelope" "$out"

  if command -v bsdtar >/dev/null 2>&1; then
    bsdtar -xf "$deb" -C "$envelope"
  elif command -v ar >/dev/null 2>&1; then
    (
      cd "$envelope"
      ar x "$deb"
    )
  else
    die "bsdtar or ar is required to extract the .deb"
  fi

  data_archive="$(find "$envelope" -maxdepth 1 -type f -name 'data.tar.*' -print -quit)"
  [[ -n "$data_archive" ]] || die "the .deb does not contain data.tar.*"

  if command -v bsdtar >/dev/null 2>&1; then
    bsdtar -xf "$data_archive" -C "$out"
  else
    tar -xf "$data_archive" -C "$out"
  fi
}

install_desktop_entry() {
  local payload_root="$1"
  local target_home="$2"
  local applications_dir="$target_home/.local/share/applications"
  local icons_dir="$target_home/.local/share/icons/hicolor/256x256/apps"
  local bin_dir="$target_home/.local/bin"
  local desktop_file="$applications_dir/browsec-deck.desktop"
  local source_icon="$payload_root/usr/share/icons/hicolor/256x256/apps/browsec-desktop.png"

  sudo install -d -m 0755 -o "$TARGET_USER" -g "$TARGET_GROUP" \
    "$applications_dir" "$icons_dir" "$bin_dir"

  if [[ -f "$source_icon" ]]; then
    sudo install -m 0644 -o "$TARGET_USER" -g "$TARGET_GROUP" \
      "$source_icon" "$icons_dir/browsec-deck.png"
  fi

  render_template "$SCRIPT_DIR/templates/browsec-deck.desktop" \
    "$TEMP_DIR/browsec-deck.desktop"
  sudo install -m 0644 -o "$TARGET_USER" -g "$TARGET_GROUP" \
    "$TEMP_DIR/browsec-deck.desktop" "$desktop_file"
  sudo -u "$TARGET_USER" ln -sfn \
    "$INSTALL_BASE/launch.sh" "$bin_dir/browsec-deck"
}

render_template() {
  local source="$1"
  local destination="$2"
  sed \
    -e "s|@INSTALL_BASE@|$INSTALL_BASE|g" \
    -e "s|@TARGET_USER@|$TARGET_USER|g" \
    "$source" >"$destination"
}

while (($#)); do
  case "$1" in
    --deb)
      (($# >= 2)) || die "--deb requires a path"
      DEB_PATH="$2"
      shift 2
      ;;
    --user)
      (($# >= 2)) || die "--user requires a user name"
      TARGET_USER="$2"
      shift 2
      ;;
    --allow-other-version)
      ALLOW_OTHER_VERSION=1
      shift
      ;;
    --no-desktop-entry)
      NO_DESKTOP_ENTRY=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "unknown argument: $1"
      ;;
  esac
done

[[ "$(uname -s)" == "Linux" ]] || die "the installer is intended for Linux/SteamOS"
[[ "$(uname -m)" == "x86_64" ]] || die "x86_64 architecture is required"
command -v sudo >/dev/null 2>&1 || die "sudo was not found"
command -v getent >/dev/null 2>&1 || die "getent was not found"
command -v setcap >/dev/null 2>&1 || die "setcap was not found (libcap package)"
command -v getcap >/dev/null 2>&1 || die "getcap was not found (libcap package)"
command -v pgrep >/dev/null 2>&1 || die "pgrep was not found"
command -v dd >/dev/null 2>&1 || die "dd was not found (coreutils package)"
id "$TARGET_USER" >/dev/null 2>&1 || die "user '$TARGET_USER' does not exist"
[[ "$TARGET_USER" != "root" ]] \
  || die "do not install the client for root; specify a regular user: --user deck"
[[ "$TARGET_USER" =~ ^[a-z_][a-z0-9_-]*[$]?$ ]] \
  || die "the user name is incompatible with the safe Polkit template"

TARGET_GROUP="$(id -gn "$TARGET_USER")"
TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
[[ -n "$TARGET_HOME" && -d "$TARGET_HOME" ]] || die "home directory for '$TARGET_USER' was not found"
[[ "$(id -un)" == "$TARGET_USER" || "${EUID:-$(id -u)}" -eq 0 ]] \
  || die "run the installer as '$TARGET_USER' or through sudo"

INSTALL_BASE="$TARGET_HOME/.local/share/browsec-deck-system"
APP_DIR="$INSTALL_BASE/app"

if pgrep -f "^$INSTALL_BASE/app/(browsec-desktop|resources/xray/brow(box|ray))" \
  >/dev/null 2>&1
then
  die "Browsec is still running; disconnect the VPN and quit the application"
fi

if [[ -z "$DEB_PATH" ]]; then
  find_deb
fi
DEB_PATH="$(cd -- "$(dirname -- "$DEB_PATH")" && pwd -P)/$(basename -- "$DEB_PATH")"
[[ -r "$DEB_PATH" ]] || die "cannot read $DEB_PATH"

actual_deb_sha="$(sha256_file "$DEB_PATH")"
if [[ "$actual_deb_sha" != "$EXPECTED_DEB_SHA256" && "$ALLOW_OTHER_VERSION" -ne 1 ]]; then
  die "the .deb SHA-256 does not match the verified 1.2.2 build: $actual_deb_sha"
fi

available_kib="$(df -Pk "$TARGET_HOME" | awk 'NR == 2 {print $4}')"
if [[ "$available_kib" =~ ^[0-9]+$ ]] && ((available_kib < 800000)); then
  die "the home partition needs at least 800 MB free; $((available_kib / 1024)) MB is available"
fi

note "============================================================"
note "Install location: $INSTALL_BASE"
note "Temporary files:  $TARGET_HOME/.cache"
note "/var is NOT used for the new installation."
note "============================================================"
note "Administrative authorization is only required during installation."
sudo -v
sudo install -d -m 0755 -o "$TARGET_USER" -g "$TARGET_GROUP" "$TARGET_HOME/.cache"

TEMP_DIR="$(mktemp -d "$TARGET_HOME/.cache/browsec-deck-install.XXXXXX")"
PAYLOAD_ROOT="$TEMP_DIR/payload"

note "Extracting $(basename -- "$DEB_PATH")..."
extract_deb "$DEB_PATH" "$PAYLOAD_ROOT"

SOURCE_APP="$PAYLOAD_ROOT/opt/Browsec"
SOURCE_BROWBOX="$SOURCE_APP/resources/xray/browbox"
SOURCE_ASAR="$SOURCE_APP/resources/app.asar"

[[ -x "$SOURCE_APP/browsec-desktop" ]] || die "browsec-desktop is missing from the payload"
[[ -x "$SOURCE_BROWBOX" ]] || die "browbox is missing from the payload"
[[ -f "$SOURCE_ASAR" ]] || die "app.asar is missing from the payload"

if [[ "$ALLOW_OTHER_VERSION" -ne 1 ]]; then
  [[ "$(sha256_file "$SOURCE_ASAR")" == "$EXPECTED_ASAR_SHA256" ]] \
    || die "unexpected app.asar"
  [[ "$(sha256_file "$SOURCE_BROWBOX")" == "$EXPECTED_BROWBOX_SHA256" ]] \
    || die "unexpected browbox"

  note "Adding Steam Deck application profiles..."
  apply_deck_asar_patch "$SOURCE_ASAR"
else
  note "Steam Deck profiles were skipped for an unverified application version."
fi

STAGE_DIR="$INSTALL_BASE/app.new"
BACKUP_DIR="$INSTALL_BASE/app.previous"

sudo install -d -m 0755 -o root -g root "$INSTALL_BASE"
sudo rm -rf -- "$STAGE_DIR"
sudo mv -- "$SOURCE_APP" "$STAGE_DIR"
sudo chown -R root:root "$STAGE_DIR"
sudo chmod -R go-w "$STAGE_DIR"
sudo chmod 0755 "$STAGE_DIR/browsec-desktop"
sudo chmod 0755 "$STAGE_DIR/resources/xray/browray" "$STAGE_DIR/resources/xray/browbox"

if command -v unshare >/dev/null 2>&1 && sudo -u "$TARGET_USER" unshare --user true >/dev/null 2>&1; then
  sudo chown root:root "$STAGE_DIR/chrome-sandbox"
  sudo chmod 0755 "$STAGE_DIR/chrome-sandbox"
else
  note "User namespaces are unavailable; enabling the standard setuid Chromium sandbox."
  sudo chown root:root "$STAGE_DIR/chrome-sandbox"
  sudo chmod 4755 "$STAGE_DIR/chrome-sandbox"
fi

sudo setcap cap_net_admin+ep "$STAGE_DIR/resources/xray/browbox"
getcap_output="$(sudo getcap "$STAGE_DIR/resources/xray/browbox" || true)"
[[ "$getcap_output" == *"cap_net_admin"* ]] || die "failed to assign CAP_NET_ADMIN"

sudo rm -rf -- "$BACKUP_DIR"
if [[ -d "$APP_DIR" ]]; then
  sudo mv -- "$APP_DIR" "$BACKUP_DIR"
fi
if ! sudo mv -- "$STAGE_DIR" "$APP_DIR"; then
  if [[ -d "$BACKUP_DIR" ]]; then
    sudo mv -- "$BACKUP_DIR" "$APP_DIR"
  fi
  die "failed to activate the new installation"
fi
sudo rm -rf -- "$BACKUP_DIR"

render_template "$SCRIPT_DIR/templates/launch.sh" "$TEMP_DIR/launch.sh"
render_template "$SCRIPT_DIR/templates/diagnose.sh" "$TEMP_DIR/diagnose.sh"
render_template "$SCRIPT_DIR/templates/repair-capability.sh" \
  "$TEMP_DIR/repair-capability.sh"
render_template "$SCRIPT_DIR/templates/49-browsec-deck-resolved.rules" \
  "$TEMP_DIR/49-browsec-deck-resolved.rules"

sudo install -m 0755 -o root -g root \
  "$TEMP_DIR/launch.sh" "$INSTALL_BASE/launch.sh"
sudo install -m 0755 -o root -g root \
  "$TEMP_DIR/diagnose.sh" "$INSTALL_BASE/diagnose.sh"
sudo install -m 0755 -o root -g root \
  "$TEMP_DIR/repair-capability.sh" "$INSTALL_BASE/repair-capability.sh"
sudo install -m 0644 -o root -g root \
  "$SCRIPT_DIR/templates/deck-app-aliases.json" \
  "$INSTALL_BASE/deck-app-aliases.json"
sudo install -d -m 0755 -o root -g root /etc/polkit-1/rules.d
sudo install -m 0644 -o root -g root \
  "$TEMP_DIR/49-browsec-deck-resolved.rules" "$POLKIT_RULE_PATH"

if [[ "$NO_DESKTOP_ENTRY" -ne 1 ]]; then
  install_desktop_entry "$PAYLOAD_ROOT" "$TARGET_HOME"
  if command -v update-desktop-database >/dev/null 2>&1; then
    sudo -u "$TARGET_USER" update-desktop-database \
      "$TARGET_HOME/.local/share/applications" >/dev/null 2>&1 || true
  fi
fi

note
note "$PRODUCT_NAME has been installed."
note "Launch: $INSTALL_BASE/launch.sh"
note "Diagnostics: $INSTALL_BASE/diagnose.sh"
note "Polkit: systemd-resolved is authorized without repeated password prompts."
note
note "The application is now available as 'Browsec Deck' in Desktop Mode."

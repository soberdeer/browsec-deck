#!/usr/bin/env bash
set -Eeuo pipefail

readonly PRODUCT_NAME="Browsec Deck 1.0.0"
readonly EXPECTED_DEB_SHA256="479dcbfd72adb3d222c74acb06ef176aafd4472a2df90e37bc820083a5549896"
readonly EXPECTED_ASAR_SHA256="e1d60c72e0d02832d754a33e2d8a050adfc2a70d59c325aeb70f260141ae1907"
readonly DECK_PATCHED_ASAR_SHA256="cfffdbdd82d216f1834449da993b7c1c1501462ea137645296839c4bf65f48e9"
readonly PATCHED_ASAR_SHA256="ba3db3a0f8d8977113b8d96180f123f2082809c6490439bdd6a8de8bc6986f11"
readonly EXPECTED_BROWBOX_SHA256="68aeab83cc4ab2659a5b92232261a20746ccdafc3b3d1e19b2d63247eec3bbf7"
readonly DECK_PATCH_OFFSET=167157093
readonly DECK_PATCH_LENGTH=962
readonly DECK_PATCH_SOURCE_SHA256="44837e0ab8d005eb8800d656748e78d4c6ccdfd6ff346f8941d98036b7570f92"
readonly DECK_PATCH_SHA256="333b332196767a4bf18c225c5096a4d48668a90bf453ef2dd56d6ee9ae488101"
readonly ELECTRON_SECURITY_PATCH_OFFSET=167331245
readonly ELECTRON_SECURITY_PATCH_LENGTH=342
readonly ELECTRON_SECURITY_SOURCE_SHA256="2809526e846d9605a55f008992085ba9e889cf06f8f45e74416ff2b33ba1e2f6"
readonly ELECTRON_SECURITY_PATCH_SHA256="d3722ea1c01ccd45e52af349a7f5cf675b863db0867540e64f52830085e99718"
readonly POLKIT_RULE_PATH="/etc/polkit-1/rules.d/49-browsec-deck-resolved.rules"
readonly SYSTEM_DIR_NAME=".browsec-deck"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
DEB_PATH="$SCRIPT_DIR/payload/browsec-desktop_1.2.2_amd64.deb"
TARGET_USER="${SUDO_USER:-$(id -un)}"
NO_DESKTOP_ENTRY=0
TEMP_DIR=""
SYSTEM_ROOT=""
INSTALL_BASE=""
APP_DIR=""
LEGACY_HOME_INSTALL_BASE=""

usage() {
  cat <<'EOF'
Install Browsec Deck 1.0.0 using the official Browsec 1.2.2 Linux payload.

Usage:
  ./install.sh [--user deck]
               [--no-desktop-entry]

The installer accepts only its bundled and hash-verified Browsec 1.2.2 Debian
payload. The application is installed on the home partition under a
root-controlled /home/.browsec-deck directory.
EOF
}

die() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

note() {
  printf '%s\n' "$*"
}

verify_root_directory() {
  local path="$1"
  local owner
  local mode

  [[ -d "$path" && ! -L "$path" ]] \
    || die "$path must be a real directory"
  owner="$(stat -c '%U:%G' "$path")"
  [[ "$owner" == "root:root" ]] \
    || die "$path must be owned by root:root (found $owner)"
  mode="$(stat -c '%a' "$path")"
  [[ "$mode" =~ ^[0-7]{3,4}$ ]] || die "cannot verify permissions for $path"
  (( (8#$mode & 0022) == 0 )) \
    || die "$path must not be writable by group or other users"
}

ensure_root_directory() {
  local path="$1"
  local mode="$2"

  [[ ! -L "$path" ]] || die "$path must not be a symbolic link"
  install -d -m "$mode" -o root -g root "$path"
  verify_root_directory "$path"
}

cleanup() {
  if [[ -n "$TEMP_DIR" && -d "$TEMP_DIR" ]]; then
    rm -rf -- "$TEMP_DIR"
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

  [[ "$(sha256_file "$asar")" == "$DECK_PATCHED_ASAR_SHA256" ]] \
    || die "the patched app.asar failed verification"
}

apply_electron_security_patch() {
  local asar="$1"
  local replacement
  local source_block_sha

  [[ "$(sha256_file "$asar")" == "$DECK_PATCHED_ASAR_SHA256" ]] \
    || die "the Electron security patch requires the verified Steam Deck app.asar"

  source_block_sha="$(
    dd if="$asar" bs=1M skip="$ELECTRON_SECURITY_PATCH_OFFSET" \
      count="$ELECTRON_SECURITY_PATCH_LENGTH" iflag=skip_bytes,count_bytes \
      status=none | sha256_stream
  )"
  [[ "$source_block_sha" == "$ELECTRON_SECURITY_SOURCE_SHA256" ]] \
    || die "unexpected app.asar contents in the Electron security patch region"

  replacement='Rx.webContents.on("will-navigate",(e,t)=>{t.split("#")[0]===Rx.webContents.getURL().split("#")[0]||e.preventDefault()}),Rx.webContents.setWindowOpenHandler(e=>(e.url.startsWith("https://")&&o.shell.openExternal(e.url).catch(()=>{}),{action:"deny"}))'
  [[ "${#replacement}" -le "$ELECTRON_SECURITY_PATCH_LENGTH" ]] \
    || die "the Electron security patch is too large"

  printf '%-*s' "$ELECTRON_SECURITY_PATCH_LENGTH" "$replacement" \
    | dd of="$asar" bs=1M seek="$ELECTRON_SECURITY_PATCH_OFFSET" \
      conv=notrunc oflag=seek_bytes status=none

  source_block_sha="$(
    dd if="$asar" bs=1M skip="$ELECTRON_SECURITY_PATCH_OFFSET" \
      count="$ELECTRON_SECURITY_PATCH_LENGTH" iflag=skip_bytes,count_bytes \
      status=none | sha256_stream
  )"
  [[ "$source_block_sha" == "$ELECTRON_SECURITY_PATCH_SHA256" ]] \
    || die "the Electron security patch failed block verification"
  [[ "$(sha256_file "$asar")" == "$PATCHED_ASAR_SHA256" ]] \
    || die "the hardened app.asar failed verification"
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

  install -d -m 0755 -o "$TARGET_USER" -g "$TARGET_GROUP" \
    "$applications_dir" "$icons_dir" "$bin_dir"

  if [[ -f "$source_icon" ]]; then
    install -m 0644 -o "$TARGET_USER" -g "$TARGET_GROUP" \
      "$source_icon" "$icons_dir/browsec-deck.png"
  fi

  render_template "$SCRIPT_DIR/templates/browsec-deck.desktop" \
    "$TEMP_DIR/browsec-deck.desktop"
  install -m 0644 -o "$TARGET_USER" -g "$TARGET_GROUP" \
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
    --user)
      (($# >= 2)) || die "--user requires a user name"
      TARGET_USER="$2"
      shift 2
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
command -v stat >/dev/null 2>&1 || die "stat was not found (coreutils package)"
command -v xz >/dev/null 2>&1 || die "xz was not found (xz package)"
id "$TARGET_USER" >/dev/null 2>&1 || die "user '$TARGET_USER' does not exist"
[[ "$TARGET_USER" != "root" ]] \
  || die "do not install the client for root; specify a regular user: --user deck"
[[ "$TARGET_USER" =~ ^[a-z_][a-z0-9_-]*[$]?$ ]] \
  || die "the user name is incompatible with the safe Polkit template"
[[ "${EUID:-$(id -u)}" -eq 0 ]] \
  || die "installation must be started by the graphical installer"

TARGET_GROUP="$(id -gn "$TARGET_USER")"
TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
[[ -n "$TARGET_HOME" && -d "$TARGET_HOME" ]] || die "home directory for '$TARGET_USER' was not found"
TARGET_HOME_PARENT="$(cd -P -- "$(dirname -- "$TARGET_HOME")" && pwd -P)"
[[ "$TARGET_HOME_PARENT" != "/" ]] || die "the target home must be on a dedicated home parent"
verify_root_directory "$TARGET_HOME_PARENT"

SYSTEM_ROOT="$TARGET_HOME_PARENT/$SYSTEM_DIR_NAME"
INSTALL_BASE="$SYSTEM_ROOT/$TARGET_USER"
APP_DIR="$INSTALL_BASE/app"
LEGACY_HOME_INSTALL_BASE="$TARGET_HOME/.local/share/browsec-deck-system"

verify_root_directory "$SYSTEM_ROOT"
verify_root_directory "$SYSTEM_ROOT/.tmp"
case "$SCRIPT_DIR/" in
  "$SYSTEM_ROOT/.tmp/"*) ;;
  *) die "the privileged installer payload is outside the verified root temporary directory" ;;
esac

if pgrep -f "^($INSTALL_BASE|$LEGACY_HOME_INSTALL_BASE)/app/(browsec-desktop|resources/xray/brow(box|ray))" \
    >/dev/null 2>&1
then
  die "Browsec is still running; disconnect the VPN and quit the application"
fi

[[ -r "$DEB_PATH" ]] || die "cannot read $DEB_PATH"

actual_deb_sha="$(sha256_file "$DEB_PATH")"
if [[ "$actual_deb_sha" != "$EXPECTED_DEB_SHA256" ]]; then
  die "the .deb SHA-256 does not match the verified 1.2.2 build: $actual_deb_sha"
fi

available_kib="$(df -Pk "$TARGET_HOME" | awk 'NR == 2 {print $4}')"
if [[ "$available_kib" =~ ^[0-9]+$ ]] && ((available_kib < 800000)); then
  die "the home partition needs at least 800 MB free; $((available_kib / 1024)) MB is available"
fi

note "============================================================"
note "Install location: $INSTALL_BASE"
note "Temporary files:  $SYSTEM_ROOT/.tmp"
note "/var is NOT used for the new installation."
note "============================================================"
note "Administrative authorization is only required during installation."
ensure_root_directory "$INSTALL_BASE" 0755

TEMP_DIR="$(mktemp -d "$SYSTEM_ROOT/.tmp/install.XXXXXX")"
chmod 0700 "$TEMP_DIR"
PAYLOAD_ROOT="$TEMP_DIR/payload"

note "Extracting $(basename -- "$DEB_PATH")..."
extract_deb "$DEB_PATH" "$PAYLOAD_ROOT"

SOURCE_APP="$PAYLOAD_ROOT/opt/Browsec"
SOURCE_BROWBOX="$SOURCE_APP/resources/xray/browbox"
SOURCE_ASAR="$SOURCE_APP/resources/app.asar"

[[ -x "$SOURCE_APP/browsec-desktop" ]] || die "browsec-desktop is missing from the payload"
[[ -x "$SOURCE_BROWBOX" ]] || die "browbox is missing from the payload"
[[ -f "$SOURCE_ASAR" ]] || die "app.asar is missing from the payload"

[[ "$(sha256_file "$SOURCE_ASAR")" == "$EXPECTED_ASAR_SHA256" ]] \
  || die "unexpected app.asar"
[[ "$(sha256_file "$SOURCE_BROWBOX")" == "$EXPECTED_BROWBOX_SHA256" ]] \
  || die "unexpected browbox"

note "Adding Steam Deck application profiles..."
apply_deck_asar_patch "$SOURCE_ASAR"
note "Applying Electron navigation safeguards..."
apply_electron_security_patch "$SOURCE_ASAR"

STAGE_DIR="$INSTALL_BASE/app.new"
BACKUP_DIR="$INSTALL_BASE/app.previous"

rm -rf -- "$STAGE_DIR"
mv -- "$SOURCE_APP" "$STAGE_DIR"
chown -R root:root "$STAGE_DIR"
chmod -R go-w "$STAGE_DIR"
chmod 0755 "$STAGE_DIR/browsec-desktop"
chmod 0755 "$STAGE_DIR/resources/xray/browray" "$STAGE_DIR/resources/xray/browbox"

if command -v unshare >/dev/null 2>&1 && sudo -u "$TARGET_USER" unshare --user true >/dev/null 2>&1; then
  chown root:root "$STAGE_DIR/chrome-sandbox"
  chmod 0755 "$STAGE_DIR/chrome-sandbox"
else
  note "User namespaces are unavailable; enabling the standard setuid Chromium sandbox."
  chown root:root "$STAGE_DIR/chrome-sandbox"
  chmod 4755 "$STAGE_DIR/chrome-sandbox"
fi

setcap cap_net_admin+ep "$STAGE_DIR/resources/xray/browbox"
getcap_output="$(getcap "$STAGE_DIR/resources/xray/browbox" || true)"
[[ "$getcap_output" == *"cap_net_admin"* ]] || die "failed to assign CAP_NET_ADMIN"

rm -rf -- "$BACKUP_DIR"
if [[ -d "$APP_DIR" ]]; then
  mv -- "$APP_DIR" "$BACKUP_DIR"
fi
if ! mv -- "$STAGE_DIR" "$APP_DIR"; then
  if [[ -d "$BACKUP_DIR" ]]; then
    mv -- "$BACKUP_DIR" "$APP_DIR"
  fi
  die "failed to activate the new installation"
fi
rm -rf -- "$BACKUP_DIR"

render_template "$SCRIPT_DIR/templates/launch.sh" "$TEMP_DIR/launch.sh"
render_template "$SCRIPT_DIR/templates/diagnose.sh" "$TEMP_DIR/diagnose.sh"
render_template "$SCRIPT_DIR/templates/49-browsec-deck-resolved.rules" \
  "$TEMP_DIR/49-browsec-deck-resolved.rules"

install -m 0755 -o root -g root \
  "$TEMP_DIR/launch.sh" "$INSTALL_BASE/launch.sh"
install -m 0755 -o root -g root \
  "$TEMP_DIR/diagnose.sh" "$INSTALL_BASE/diagnose.sh"
install -m 0644 -o root -g root \
  "$SCRIPT_DIR/templates/deck-app-aliases.json" \
  "$INSTALL_BASE/deck-app-aliases.json"
install -d -m 0755 -o root -g root /etc/polkit-1/rules.d
install -m 0644 -o root -g root \
  "$TEMP_DIR/49-browsec-deck-resolved.rules" "$POLKIT_RULE_PATH"

if [[ "$NO_DESKTOP_ENTRY" -ne 1 ]]; then
  install_desktop_entry "$PAYLOAD_ROOT" "$TARGET_HOME"
  if command -v update-desktop-database >/dev/null 2>&1; then
    sudo -u "$TARGET_USER" update-desktop-database \
      "$TARGET_HOME/.local/share/applications" >/dev/null 2>&1 || true
  fi
fi

if [[ -L "$LEGACY_HOME_INSTALL_BASE" ]]; then
  rm -f -- "$LEGACY_HOME_INSTALL_BASE"
elif [[ -d "$LEGACY_HOME_INSTALL_BASE" ]]; then
  rm -rf -- "$LEGACY_HOME_INSTALL_BASE"
fi

note
note "$PRODUCT_NAME has been installed."
note "Launch: $INSTALL_BASE/launch.sh"
note "Diagnostics: $INSTALL_BASE/diagnose.sh"
note "Polkit: systemd-resolved is authorized without repeated password prompts."
note
note "The application is now available as 'Browsec Deck' in Desktop Mode."

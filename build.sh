#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PROJECT_ROOT
readonly APP_VERSION="1.0.0"
readonly KIT_ROOT="$PROJECT_ROOT/kit"
readonly GUI_ROOT="$PROJECT_ROOT/gui"
readonly DIST_ROOT="$PROJECT_ROOT/dist"
readonly PAYLOAD_NAME="browsec-deck-$APP_VERSION"
readonly GUI_BINARY="Browsec Deck Installer"
readonly GUI_ARCHIVE="Browsec-Deck-Installer-$APP_VERSION.tar.gz"
readonly KIT_ARCHIVE="browsec-deck-$APP_VERSION.tar.gz"
readonly CHECKSUM_FILE="Browsec-Deck-$APP_VERSION.sha256"
readonly EXPECTED_DEB_SHA256="479dcbfd72adb3d222c74acb06ef176aafd4472a2df90e37bc820083a5549896"
readonly EXPECTED_ICON_SHA256="111a51070cd8eb42216fb84ed08f40dfe84b121c9923d9cdbe42f7d5fc2cda0e"

BUILD_ROOT=""

die() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

cleanup() {
  if [[ -n "$BUILD_ROOT" && -d "$BUILD_ROOT" ]]; then
    rm -rf -- "$BUILD_ROOT"
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

write_checksums() {
  local output="$DIST_ROOT/$CHECKSUM_FILE"
  (
    cd "$DIST_ROOT"
    if command -v sha256sum >/dev/null 2>&1; then
      sha256sum \
        "$GUI_ARCHIVE" \
        "$KIT_ARCHIVE"
    else
      shasum -a 256 \
        "$GUI_ARCHIVE" \
        "$KIT_ARCHIVE"
    fi
  ) >"$output"
}

[[ "$(uname -s)" == "Darwin" || "$(uname -s)" == "Linux" ]] \
  || die "the build host must be macOS or Linux"
command -v tar >/dev/null 2>&1 || die "tar was not found"
command -v awk >/dev/null 2>&1 || die "awk was not found"
[[ -f "$GUI_ROOT/main.go" ]] || die "gui/main.go was not found"
[[ -f "$KIT_ROOT/payload/browsec-desktop_1.2.2_amd64.deb" ]] \
  || die "the official Debian payload was not found"
[[ -f "$KIT_ROOT/assets/browsec-desktop.png" ]] \
  || die "the official Browsec icon was not found"

[[ "$(sha256_file "$KIT_ROOT/payload/browsec-desktop_1.2.2_amd64.deb")" \
  == "$EXPECTED_DEB_SHA256" ]] || die "the official Debian payload hash differs"
[[ "$(sha256_file "$KIT_ROOT/assets/browsec-desktop.png")" \
  == "$EXPECTED_ICON_SHA256" ]] || die "the official Browsec icon hash differs"

bash -n "$KIT_ROOT"/*.sh "$KIT_ROOT"/templates/*.sh
if command -v node >/dev/null 2>&1; then
  node --check --input-type=commonjs \
    <"$KIT_ROOT/templates/49-browsec-deck-resolved.rules"
fi

mkdir -p -- "$DIST_ROOT"
BUILD_ROOT="$(mktemp -d "$PROJECT_ROOT/.build.XXXXXX")"
mkdir -p -- "$BUILD_ROOT/$PAYLOAD_NAME"

(
  cd "$KIT_ROOT"
  COPYFILE_DISABLE=1 tar \
    --exclude='.DS_Store' \
    --exclude='._*' \
    -cf - .
) | (
  cd "$BUILD_ROOT/$PAYLOAD_NAME"
  tar -xf -
)

COPYFILE_DISABLE=1 tar -czf "$GUI_ROOT/payload.tar.gz" \
  -C "$BUILD_ROOT" "$PAYLOAD_NAME"
cp -- "$KIT_ROOT/assets/browsec-desktop.png" \
  "$GUI_ROOT/browsec-desktop.png"

printf 'Building the graphical installer...\n'
if command -v go >/dev/null 2>&1; then
  (
    cd "$PROJECT_ROOT"
    [[ -z "$(gofmt -l gui/*.go)" ]] \
      || die "Go sources are not formatted; run gofmt on gui/*.go"
    go test ./...
    CGO_ENABLED=0 GOOS=linux GOARCH=amd64 \
      go build -trimpath -ldflags='-s -w' \
      -o "$GUI_ROOT/$GUI_BINARY" ./gui
  )
elif command -v docker >/dev/null 2>&1; then
  docker run --rm \
    -v "$PROJECT_ROOT:/src" \
    -w /src \
    golang:1.26.5-bookworm \
    bash -c \
      'test -z "$(/usr/local/go/bin/gofmt -l gui/*.go)" && /usr/local/go/bin/go test ./... && CGO_ENABLED=0 GOOS=linux GOARCH=amd64 /usr/local/go/bin/go build -trimpath -ldflags="-s -w" -o "gui/Browsec Deck Installer" ./gui'
else
  die "Go 1.26.5+ or Docker is required"
fi

[[ -x "$GUI_ROOT/$GUI_BINARY" ]] \
  || die "the graphical installer executable was not produced"
install -m 0755 "$GUI_ROOT/$GUI_BINARY" "$DIST_ROOT/$GUI_BINARY"

printf 'Packaging distributions...\n'
COPYFILE_DISABLE=1 tar -czf \
  "$DIST_ROOT/$GUI_ARCHIVE" \
  -C "$DIST_ROOT" "$GUI_BINARY"
COPYFILE_DISABLE=1 tar -czf \
  "$DIST_ROOT/$KIT_ARCHIVE" \
  -C "$BUILD_ROOT" "$PAYLOAD_NAME"
write_checksums

printf '\nBuild complete:\n'
printf '  %s\n' \
  "$DIST_ROOT/$GUI_BINARY" \
  "$DIST_ROOT/$GUI_ARCHIVE" \
  "$DIST_ROOT/$KIT_ARCHIVE" \
  "$DIST_ROOT/$CHECKSUM_FILE"

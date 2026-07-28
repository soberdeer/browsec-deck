# Browsec Deck 1.0.0

Source project for Browsec Deck, based on the official Browsec Desktop Linux payload.

## Project layout

- `gui/main.go` — the statically linked graphical installer;
- `gui/test-fixtures/` — fake KDE and privilege helpers used by integration
  tests;
- `kit/` — verified installation scripts, Steam Deck profiles, app.asar patch,
  official Browsec icon, and the official Debian payload;
- `build.sh` — reproducible x86-64 build and packaging script;
- `dist/` — generated artifacts.

The GUI executable embeds a compressed copy of `kit/`. At runtime it displays
native KDE dialogs, requests administrator authorization through Polkit, and
extracts the privileged payload under the root-controlled
`/home/.browsec-deck` directory on the home partition.

## Build

Requirements:

- macOS or Linux;
- `tar`, `bash`, and either Go 1.26.5+ or Docker;
- approximately 1 GB of free disk space.

Run:

```bash
./build.sh
```

Generated files:

```text
dist/Browsec Deck Installer
dist/Browsec-Deck-Installer-1.0.0.tar.gz
dist/browsec-deck-1.0.0.tar.gz
dist/Browsec-Deck-1.0.0.sha256
```

The graphical distribution archive contains exactly one executable file. The
archive preserves its executable mode for extraction through Dolphin.

## Release

Push a version tag that matches `APP_VERSION` in `build.sh`:

```bash
git tag v1.0.0
git push origin v1.0.0
```

The GitHub Actions workflow builds and creates the corresponding GitHub
Release automatically. It publishes only:

```text
Browsec-Deck-Installer-1.0.0.tar.gz
Browsec-Deck-Installer-1.0.0.sha256
```

The release fails before publishing if the tag and project versions do not
match.

## Security boundaries

- The official `.deb`, app.asar patch region, `browbox`, and Browsec icon are
  verified by fixed SHA-256 values.
- Privileged extraction happens only after Polkit authorization.
- The installed application and privileged temporary files are below a
  root-owned `/home/.browsec-deck` boundary.
- Polkit executes the already-running installer inode through `/proc`, so a
  file in Downloads cannot be replaced during authorization.
- Only `browbox` receives `CAP_NET_ADMIN`.
- The verified ASAR patch blocks external navigation inside the privileged
  Electron renderer and restricts external links to HTTPS.
- The Polkit rule is limited to the active local target user and
  the four per-link DNS actions used by Browsec.
- No passwordless sudoers entry or permanent root daemon is installed.

This is an unofficial adaptation and not an official Browsec release.

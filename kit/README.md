# Browsec Deck 1.0.0

An unofficial Steam Deck adaptation based on the official Browsec Desktop
1.2.2 Linux payload.

## Installation

Download `Browsec-Deck-Installer-1.0.0.tar.gz`, extract it in Dolphin, and
double-click `Browsec Deck Installer`.

The graphical installer:

1. checks the embedded payload;
2. displays native administrator authentication dialog;
3. installs everything on the `home` partition;
4. displays progress and the final result;
5. offers to launch Browsec.

No terminal commands are required. The SteamOS read-only mode does not need to be disabled.

## Command-line installation

The source bundle remains available for diagnostics and advanced use:

```bash
cd ~/Downloads/browsec-deck-1.0.0
./install.sh
```

The `.deb` is included under `payload/`. Administrative authorization is required once.

The installer prints the following locations before making changes:

```text
Install location: /home/deck/.local/share/browsec-deck-system
Temporary files:  /home/deck/.cache
```

## Steam Deck application profiles

`Selected Apps` includes disabled-by-default profiles for:

- `Steam + all Steam games` — Steam, `steamwebhelper`, native games, Proton,
  Steam Runtime, and games on an SD card;
- `EmuDeck + emulators` — EmuDeck, ES-DE, RetroArch, and common standalone emulators;
- `Browsers` — Firefox, Chrome/Chromium, Brave, Vivaldi, Opera, LibreWolf, and Floorp;
- `Telegram`;
- `Discord`;
- `KDE Discover` — Discover, PackageKit, Flatpak, and `fwupd`.

The Steam profile also covers the store, sign-in, and downloads. To route only one game through the VPN, leave the broad Steam profile disabled and add that game executable with `Add app`.

## After a SteamOS update

Run the safe diagnostics:

```bash
~/.local/share/browsec-deck-system/diagnose.sh
```

If the capability was removed:

```bash
sudo ~/.local/share/browsec-deck-system/repair-capability.sh
```

The repair script refuses to operate if the application is no longer root-owned or contains group/world-writable files.


## Uninstallation

Disconnect the VPN, quit Browsec, and run:

```bash
./uninstall.sh
```

The application, capability, Polkit rule, and launchers are removed. Account data and Electron settings are preserved in the user profile.

## Important notes

- This is a personal adaptation, not an official Browsec Steam Deck release.
- `browbox`, the VPN protocol, and Browsec API behavior are unchanged.
- The desktop client stores `access_token` and `xray_uuid` in its regular Electron `config.json`, as the original Debian version does.

## Verified hashes

```text
Debian package:
479dcbfd72adb3d222c74acb06ef176aafd4472a2df90e37bc820083a5549896

Patched app.asar:
cfffdbdd82d216f1834449da993b7c1c1501462ea137645296839c4bf65f48e9
```

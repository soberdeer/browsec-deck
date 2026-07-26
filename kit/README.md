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

Only the bundled and hash-verified `.deb` is accepted. The privileged scripts
are internal payloads and refuse to run from a user-writable source directory.
The installer uses these locations:

```text
Install location: /home/.browsec-deck/deck
Temporary files:  /home/.browsec-deck/.tmp
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
/home/.browsec-deck/deck/diagnose.sh
```

If the capability was removed:

Open `Browsec Deck Installer`, choose `Repair VPN permissions`, and approve
the administrator prompt. Repair is executed from the installer's embedded
and verified payload rather than from an installed script.


## Uninstallation

Disconnect the VPN, quit Browsec, open `Browsec Deck Installer`, and choose
`Uninstall`.

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
ba3db3a0f8d8977113b8d96180f123f2082809c6490439bdd6a8de8bc6986f11
```

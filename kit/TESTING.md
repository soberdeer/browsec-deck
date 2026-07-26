# Build verification

Date: July 26, 2026.
Project version: 1.0.0.

## Completed

- Bash syntax checks for the installer, uninstaller, launcher, diagnostics,
  repair, Polkit helpers, and GUI support scripts;
- extraction of the real `browsec-desktop_1.2.2_amd64.deb`;
- SHA-256 verification of the `.deb`, `app.asar`, `browbox`, patch, and
  official application icon;
- fixed Steam Deck patch application to the verified `app.asar`;
- fixed-size Electron hardening patch that blocks external in-window
  navigation and permits only HTTPS URLs through `shell.openExternal`;
- JSON, JavaScript regular expression, and final `process_path_regex`
  validation with `browbox check`;
- complete installation as the unprivileged `deck` user;
- root-owned installation under
  `/home/.browsec-deck/deck`;
- confirmation that `/var/lib/browsec-deck` is not created;
- root-only temporary extraction under `/home/.browsec-deck/.tmp` and
  automatic cleanup;
- `root:root` ownership and `cap_net_admin=ep` verification;
- root-owned Polkit rule installation for
  the four required `org.freedesktop.resolve1` actions, target-user scoping,
  and removal;
- standalone Polkit authorization and restoration;
- dynamic library checks for `browbox`;
- root-owned setuid Chromium sandbox fallback when user namespaces are
  unavailable;
- desktop entry, official icon, and user launcher creation;
- statically linked x86-64 graphical installer with the verified official
  Browsec icon and embedded release payload;
- simulated KDE `kdialog`/`qdbus` double-click flow, including install,
  progress updates, native privilege handoff, completion, and uninstall;
- confirmation that privileged extraction occurs only after authorization in
  a root-owned directory outside every user-writable path;
- confirmation that all scripts, dialogs, diagnostics, and console output are
  English-only;
- safe diagnostics;
- full uninstallation;
- isolated removal of the legacy `/var/lib/browsec-deck` installation.

Integration environment:

```text
Arch Linux x86-64 container
Unprivileged user: deck
Official Debian payload: Browsec 1.2.2
```

## Not performed

- Electron GUI operation;
- rendering the final `kdialog` windows on a physical Steam Deck;
- sign-in to a real Browsec account;
- actual `browray` or `browbox` VPN traffic;
- route and DNS changes on a physical Steam Deck;
- sleep/resume and Wi-Fi switching;
- Gaming Mode integration.

These checks require the owner's physical Steam Deck and Premium account.

Final automated markers:

```text
GUI_EMBEDDED_ENGLISH_INSTALL_DIAGNOSE_UNINSTALL_OK
GUI_DOUBLE_CLICK_INSTALL_PROGRESS_UNINSTALL_OK
```

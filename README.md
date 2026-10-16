<div align="center">
  <img src="assets/AppIcon.png" alt="Dock Enhanced icon" width="96" />

# Dock Enhanced

**English** · [简体中文](README.zh-CN.md)

Smoother window switching on macOS.

**Dock previews · Click to minimize and restore · Window-level Command+Tab**

[Download](https://github.com/sunyifeng11111/yf-dock-enhanced/releases/latest) · [Features](#features) · [Get started](#get-started) · [Usage](#usage) · [Build from source](#build-from-source)

</div>

Dock Enhanced is a native macOS window utility. Hover over a Dock icon to preview and select individual windows, click the foreground app’s icon to minimize or restore its most recently used window, and use `⌘ Tab` to switch directly between windows across apps.

It runs in the background without a Dock icon of its own. Each enhancement can be enabled independently. Built with Swift, AppKit, and SwiftUI, with no third-party library dependencies.

## Features

### Hover over the Dock to find your window

Have several windows open in one app? Hover over its Dock icon to see thumbnails and titles, then click a preview to switch. Previews appear after **0.4 seconds** by default; you can adjust the delay in settings.

![Dock preview showing two Google Chrome windows side by side](docs/images/dock-preview-multiple.png)

A single window gets a compact preview layout.

![Compact Dock preview for a Visual Studio Code window](docs/images/dock-preview-single.png)

### Switch between windows with Command+Tab

Each card represents one window. Multiple windows from the same app appear separately, including minimized windows and windows belonging to hidden apps. Quickly press and release `⌘ Tab` to return to the previous window, or hold Command to open the panel and keep browsing.

![Window switcher showing thumbnails, titles, and minimized states across apps](docs/images/window-switcher.png)

> [!NOTE]
> The switcher lists windows. Browser tabs are not listed separately.

### Click the Dock to minimize and restore

Click the foreground app’s Dock icon to minimize its most recently used window. Click again to restore that same window. Clicking a background app retains the system’s normal app-switching behavior.

Preview panels use native Liquid Glass on macOS 26 and later, and frosted glass on earlier versions. Animations respect the system’s Reduce Motion setting.

## Get started

Requires **macOS 14 or later**. The downloadable DMG targets Apple Silicon (arm64). An Intel binary is not currently provided; building from source uses your machine’s native architecture.

1. Download the Apple Silicon `.dmg` from [GitHub Releases](https://github.com/sunyifeng11111/yf-dock-enhanced/releases/latest).
2. Open the DMG and drag **Dock Enhanced.app** to **Applications**, then double-click the app.
3. Grant permissions under **General → System Permissions** in the app’s settings (shown as **通用 → 系统权限** in the current Chinese interface).

| Permission | Purpose |
| --- | --- |
| Accessibility | Control windows and detect Dock clicks and window-switching shortcuts |
| Screen Recording | Generate thumbnails for Dock previews and the window switcher |

> [!IMPORTANT]
> Without Screen Recording permission, the window switcher still works with icons and titles. Click-to-minimize and restore does not require this permission. If thumbnails remain unavailable after granting access, quit and reopen the app.

Starting with **0.6.5**, release builds use a persistent self-signed certificate. The app is not notarized by Apple, so macOS may still block a download or display a security warning.

**Upgrading from 0.6.4 or earlier requires granting permissions once more**, because those builds used ad hoc signing. Subsequent updates signed with the same certificate are intended to retain permissions. This was verified with an isolated two-version test on the maintainer’s Mac; other macOS versions may behave differently. Keep the app in Applications, quit it before replacing it, and reopen it after the update. You do not need to install the signing certificate in your keychain.

## Usage

| Action | Result |
| --- | --- |
| Hover over a Dock icon | Preview that app’s windows |
| Click a preview thumbnail | Restore and switch to that window |
| Click the foreground app’s Dock icon | Minimize its most recently used window; click again to restore |
| Quickly press and release `⌘ Tab` | Return to the previous window without opening the panel |
| Hold `⌘` and press `Tab` repeatedly | Open the panel and cycle forward |
| Hold `⌘` and press `Shift Tab` | Cycle backward |
| Use arrow keys or the mouse | Select a window in the panel |
| Release `⌘`, press `Enter`, or click a card | Confirm the selection |
| Press `Esc` or click outside the panel | Cancel |

### Make it your own

Open settings from the menu bar. The three pages cover:

- **Dock Features (Dock 功能)**: Toggle hover previews and click-to-minimize/restore independently, and adjust the preview delay.
- **Window Switching (窗口切换)**: Toggle Command+Tab enhancement and check shortcut and thumbnail availability. Turning it off restores the system Command+Tab behavior.
- **General (通用)**: Manage launch at login, menu bar icon visibility, and system permissions.

If you hide the menu bar icon, search for `Dock Enhanced` in Spotlight or reopen it from Applications to access settings. The bottom of the settings sidebar includes a quit button.

## Privacy and compatibility

- **Local processing**: The app makes no network requests. Thumbnails stay in memory, with a maximum of 64 cached images. Window titles and usage history are not written to disk. Stopping image services, revoking Screen Recording permission, or quitting clears the image cache.
- **Minimized windows**: Previews use the last cached image. If none is available, they show the app icon and window title.
- **Native Dock interactions**: Right-clicking, dragging, and clicks with modifier keys retain system behavior. Click-to-minimize does not handle full-screen windows or windows that cannot be minimized.
- **Shortcut availability**: The app leaves system Command+Tab in place when control permissions are missing, event monitoring is unavailable, or Secure Input is active. Shortcut handling does not read or record typed text.
- **Full-screen window discovery**: Windows already identified during the current run can remain in the switcher. If an app is already full-screen when Dock Enhanced starts, macOS may temporarily omit some of its normal windows. Exit full screen once to let the tool discover them.
- **Compatibility coverage**: Accessibility support varies between apps. Multiple monitors, different Dock positions, Dock auto-hide, and multiple regular desktops still need further validation.

## Build from source

You need a Swift 6 toolchain, macOS Command Line Tools, and Python 3 for the build script. Clone the repository and build:

```sh
git clone https://github.com/sunyifeng11111/yf-dock-enhanced.git
cd yf-dock-enhanced
python3 scripts/setup-signing.py
scripts/build-app.sh
```

The app is generated at `dist/Dock Enhanced.app`. Move it to Applications and open it. The script builds with SwiftPM, bundles the icon, and signs with your persistent local certificate. OpenSSL is needed for the one-time signing setup.

### Package a DMG

```sh
scripts/build-dmg.sh
```

This builds the Release app and creates a compressed DMG in `dist/`, containing the app and an Applications shortcut. A `.dmg.sha256` checksum file is generated alongside it. Upload both files as GitHub Release assets; keep generated binaries out of the source repository.

> [!IMPORTANT]
> The script uses a fixed self-signed identity and does not notarize the app. Packaging it as a DMG does not remove macOS Gatekeeper warnings. Developer ID signing and Apple's notarization service are still needed for notarized distribution.

### Keep the signing identity stable

Run `python3 scripts/setup-signing.py` once per signing identity. Later runs reuse it; builds refuse to fall back to ad hoc signing. By default, private signing material lives outside the repository at `~/Library/Application Support/Dock Enhanced/Signing/`. Set `DOCK_ENHANCED_SIGNING_DIR` to use another private location.

Privately back up the entire directory, including the certificate, private key, keychain, and its password. Reuse that identity for every update; do not recreate it for each version or CI run. Never commit these files or upload them to Releases. Setup creates an isolated keychain without changing system certificate trust.

Building your own copy creates a different identity from official downloads. Switching between them may require authorization again. Losing or changing the signing identity can also require new authorization. This mechanism preserves app identity; it does not guarantee that macOS will never request consent again.

### Project structure

| Path | Contents |
| --- | --- |
| `Sources/DockCore/` | Dock click and hover policies, and window-switching state logic |
| `Sources/DockEnhanced/` | System window interaction, thumbnails, preview panels, settings, and menu bar integration |
| `Tests/DockCoreChecks/` | Core behavior checks |
| `scripts/` | App packaging, native interaction checks, and visual checks |
| `assets/` | App icons |
| `GLOSSARY.md` | Window and interaction terminology |

### Development checks

Run the core behavior checks:

```sh
swift run --build-system native DockCoreChecks
```

To check actual Dock and window-switching interactions:

```sh
scripts/check-native.sh
scripts/check-switcher-native.sh
```

> [!NOTE]
> Native checks require the relevant system permissions and temporarily move the pointer, create test windows, and switch focus. Run them one at a time while the desktop is idle, and quit any running instance of Dock Enhanced first.

Additional checks include `scripts/check-thumbnail-delivery.sh --stress` for thumbnail updates, and the window-switching script’s `--recovery`, `--review`, `--visual`, and `--reachability` options for recovery, behavior review, visual checks, and full-screen reachability.

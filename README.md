# RedClose

**Close the last window. Quit the app.** RedClose is a small macOS menu-bar utility that requests a normal quit after you click an app's last red close button. It also handles apps that hide themselves on close, when it can confirm that no other windows remain.

Save prompts stay under the app's control. If window information is uncertain, RedClose leaves the app running. Finder and protected system apps are excluded. Command-W, tab closures and minimizing are not triggers.

## Install and start

**Experimental [1.1.0-beta.1 download](https://github.com/IgneousRed/redclose/releases/tag/v1.1.0-beta.1)** for Apple Silicon (arm64). Builds target macOS 13 or later; runtime checks were performed on Apple Silicon with macOS 27.2.1 only. Older macOS versions and Intel have not been validated. This is not a stable release.

1. Extract the beta ZIP and move **RedClose.app** to `/Applications` or your user's `Applications` folder. No developer tools are needed for the packaged app.
2. Open it. **This app is ad-hoc signed, not Developer ID signed or notarized.** If macOS blocks a download you trust, use **System Settings → Privacy & Security → Open Anyway**, where available. Managed Macs may prohibit this. RedClose does not remove quarantine or disable security controls. See [Apple's opening guidance](https://support.apple.com/en-us/102445).
3. In RedClose's setup window, choose **Open Accessibility Settings** and enable this copy. **Show RedClose in Finder** helps locate it if you need to add it manually. RedClose confirms permission independently; an old approval switch alone is not sufficient.
4. Use the menu-bar icon to pause/resume, open Settings, or quit. **Launch at login** is opt-in.

An updated ad-hoc-signed build may need a fresh Accessibility approval: remove its old entry and add the new installed copy. Keep the app at its installed location rather than launching different copies from Downloads or the build directory.

### Existing script installations

The new app does not silently replace the old background app or its login entry. Open the new copy from Applications and choose **Settings → General → Replace Older Startup Entry**. This explicitly stops the old service, backs up its plist, and registers this copy using macOS Login Items. The old app is preserved for recovery. macOS may require login-item and Accessibility approval.

If another modern copy is running, reopening RedClose brings that copy forward. If a running copy cannot be located, quit it and use **Retry Monitoring**. The shared instance lock prevents two monitors from running together. An inactive copy cannot change settings or login registration; it reloads the latest preferences when it takes ownership.

## Settings

1. **General:** permission status, pause/resume, launch at login, setup help and removal instructions. No Dock icon during normal use.
2. **Apps:** choose **All apps except those listed** (the existing behavior and default) or **Only the apps listed**. The lists are independent and preserved when switching modes. Add apps with the native app picker. Selecting no apps in the second mode affects nothing. Apps without a bundle identity are conservatively excluded.
3. **Troubleshooting:** review permission, version, startup and window-query status. Optional activity recording remembers at most 50 recent decisions in memory. Recording is off by default; its enabled preference is remembered, but recorded events are cleared at quit or when recording is disabled. Exports contain exactly the preview captured when you click Export.

Pause and app-rule changes immediately cancel pending quit decisions. Preferences survive updates. Unreadable or future-version settings pause RedClose rather than silently enabling it for all apps.

RedClose reads close-button/window state, not document contents or window titles. It does not store keystrokes or need Screen Recording permission. There are no accounts, telemetry, automatic downloads or third-party dependencies. Check for Updates opens the [GitHub releases page](https://github.com/IgneousRed/redclose/releases) in your browser; it does not download or install updates.

## Updates and removal

Quit RedClose before replacing the app. Install the new copy at the same location; settings are retained. Reopen it and check Accessibility and login status. No Apple developer account is required to build or use this project; users handle their Mac's approval steps.

To remove a modern installation, turn off **Launch at login**, quit from the menu bar, move the app to the Trash, and remove its Accessibility entry. Optional source helper: `./uninstall.sh /path/to/RedClose.app` requires the app to be quit and unregisters its login item before removal. Preferences, old logs, backups and exported diagnostics remain unless you explicitly remove them. The old script installation can be removed with `./uninstall.sh --legacy`; this does not remove the new app.

See [the packaged installation/removal guide](docs/INSTALL.txt) for exact retained-data locations.

## Build and verify

Source builds require Xcode Command Line Tools. No dependency installation is needed.

```sh
./build.sh           # Native-architecture ad-hoc-signed beta in dist/RedClose.app
./build.sh --debug   # Native-architecture debug app in dist/Debug/RedClose.app
./package.sh         # Local ZIP plus SHA-256; never uploads
./test.sh            # Decision, settings, rollback, installation and icon checks
./test-ui.sh         # Brief isolated debug UI smoke; no global monitoring/login changes
```

`./test-hide.sh` checks a native visible-window close-to-hide transition. `./test-windows.sh` opens disposable windows, minimizes/restores one and briefly switches Spaces/full-screen. Neither fixture clicks or quits your applications. See [validation and the remaining release checks](docs/TESTING.md).

The optional `./install.sh` builds and opens a copy in `~/Applications`; it preserves the old script installation. Replacements require all RedClose copies to be quit, hold the instance lock through the full copy operation, and keep the prior installed app under Application Support. Ordinary login never builds or signs anything. Builds preserve the last verified generated app and reuse unchanged signed output.

## Implementation and compatibility

`Sources/RedClose.swift` owns close detection and conservative quit decisions. `Preferences.swift` holds app rules and optional bounded activity. `AppController.swift` owns native AppKit UI and lifecycle; `LoginManagement.swift` manages single-instance ownership and explicit login migration. `Resources/Info.plist` holds version/deployment metadata and the public release URL. `Tools/MakeIcon.swift` draws the icon from source without external assets.

The window-server query includes offscreen and full-screen windows. Three dynamically loaded private SkyLight functions distinguish closed window records from actual other-Space windows. If unavailable or uncertain, RedClose declines the affected quit. This dependency can break across macOS updates; this is a direct-download utility, not an App Store submission.

**Beta limitations:** custom inaccessible close controls and unusual hidden/helper windows may not work. Real target-app mouse clicks/save prompts, login migration, permission recovery after upgrades and a downloaded/quarantined package still require acceptance testing. Automated and native fixture checks are not a compatibility guarantee.

## Licence

[MIT](LICENSE) — Copyright (c) 2026 IgneousRed. The licence is included in the download and app bundle.

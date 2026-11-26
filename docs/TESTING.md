# Testing and compatibility

## Verified scope

The experimental 1.1.0-beta.1 was checked on Apple Silicon with macOS 27.2.1 (26B131). Release and debug builds compile with warnings as errors. Verification passed 104 Swift assertions, disposable signed installation/rollback fixtures, shell syntax checks, both isolated UI modes, and native hide/window fixtures. Settings tabs were visually checked in light and dark appearances. These checks do not certify real target-app mouse/save interactions, live login approval/migration, or installation of a downloaded app with quarantine intact.

Builds target macOS 13+, but older macOS runtime behavior and Intel are unvalidated. Private window-server APIs may change between macOS versions. Do not interpret the deployment target as a tested compatibility range.

## Automated checks

Run `./test.sh` for 35 close-decision/geometry checks, 29 app checks, 34 isolated lifecycle/rollback checks, 6 icon checks, and disposable signed installation fixtures. The latter cover default/selected/excluded app scope, pause, preference round-trip, corrupt and future settings, bounded opt-in activity, update URL handling, exclusive monitor ownership and rejection of unknown legacy login entries. The lifecycle checks inject Service Management/launchctl operations and use disposable files, including real file-permission failures; they do not change live login services. Installation fixtures test successful replacement, rejected invalid input, retained backups and strict legacy-entry validation without overriding HOME. Icon checks verify actual PNG pixel dimensions and transparency. Shell syntax is checked for root, Tools and Tests shell scripts.

Run `./test-ui.sh` for an isolated debug Settings window. It exercises pause, switching app scope, adding a rule, app-table selection preservation/reset, optional diagnostics and clearing history. A second run verifies that an inactive copy cannot change policy or login settings. It uses a disposable preferences suite, never acquires the live app lock, never installs a global monitor and never changes login items. Production builds do not contain the smoke runner. The debug runner accepts `--snapshot-directory <existing-directory>` to capture each native tab; capture requires the local environment's screen-capture permission.

`./test-windows.sh` verifies native ordinary/full-screen/other-Space window queries and closed-window handling. `./test-hide.sh` verifies that a close handler can hide its app while retaining its window and still reach a confirmed quit decision. The hide fixture first establishes that its window is onscreen: a background command-line fixture assigned to a different Space should not be mistaken for a real click on a visible close button.

These fixtures run actual AppKit windows but do not exercise global mouse monitoring against another app's Accessibility tree. They do not click or quit user apps.

## Build and package verification

`./build.sh` compiles the host architecture with warnings as errors and verifies the ad-hoc signature. `./build.sh --debug` produces a separate debug build. Neither installs the app or changes startup entries. A successful new build retains the prior generated app.

`./package.sh` prepares a local ZIP containing the app, installation guide and MIT licence, plus a SHA-256 checksum file. It does not upload or notarize anything. The licence is also inside the app bundle. To check a download, run `shasum -a 256 -c RedClose-1.1.0-beta.1-arm64.zip.sha256` in the directory containing both files. After extraction, run `codesign --verify --strict /path/to/RedClose.app`. An ad-hoc signature is an integrity check, not Apple developer identification or notarization.

## Acceptance checks before a stable release

1. On a test account/Mac, download the ad-hoc-signed package with quarantine intact, follow the user-facing opening instructions and grant Accessibility. Test denial/revocation/reapproval and confirm the status is truthful. Managed-device policies can prevent approval.
2. Test real red-button clicks in target apps: two ordinary windows; one minimized remaining window; one full-screen/other-Space window; last window; save then close; cancel save; close-to-hide; unrelated Hide shortcut; release outside the close button. Uncertain queries must not cause quits.
3. While a close is pending, pause or exclude its app. The pending decision must be cancelled. Selected-only mode with no apps must affect nothing.
4. Enable login, quit/relaunch, log out/in, revoke login approval and disable login. On a disposable legacy installation, migrate with approval and verify exactly one monitor, retained backup/app, and recovery on registration or bootout failure. Do not run migration tests against a working user's installation merely to obtain evidence.
5. Update the ad-hoc-signed app at the same path; verify settings survive and explain any necessary Accessibility reapproval. Test a duplicate launch and removal after disabling login. Uninstall must not silently erase preferences/exports.
6. Run on the oldest advertised macOS. Validate Intel separately before offering an Intel artifact. Compilation for a target is not runtime evidence. Verify keyboard/VoiceOver access and light/dark appearance.

Private SkyLight APIs remain a compatibility risk. Keep conservative failure behavior and recheck after macOS changes.

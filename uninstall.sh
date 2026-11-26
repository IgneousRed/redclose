#!/bin/sh
set -eu
script_directory=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
if [ "${1:-}" = "--legacy" ] && [ "$#" -eq 1 ]; then
    app="$HOME/Library/Application Support/RedClose/RedClose.app"
    agent="$HOME/Library/LaunchAgents/local.redclose.plist"
    entry_hash=""
    if [ -f "$agent" ]; then
        if ! /bin/sh "$script_directory/Tools/validate-legacy.sh" "$agent" "$app/Contents/MacOS/RedClose"; then
            printf 'Unrecognized login entry; nothing removed.\n' >&2
            exit 1
        fi
        entry_hash=$(/usr/bin/shasum -a 256 "$agent")
        service="gui/$(id -u)/local.redclose"
        if ! /bin/launchctl bootout "$service" 2>/dev/null; then
            if /bin/launchctl print "$service" >/dev/null 2>&1; then
                printf 'Could not stop the older service; nothing removed.\n' >&2
                exit 1
            fi
        fi
    fi
    if /usr/sbin/lsof -t "$app/Contents/MacOS/RedClose" >/dev/null 2>&1; then
        printf 'Quit the older app before removing it.\n' >&2
        exit 1
    fi
    if [ -n "$entry_hash" ]; then
        if [ "$(/usr/bin/shasum -a 256 "$agent")" != "$entry_hash" ]; then
            printf 'The startup entry changed during removal; files are preserved.\n' >&2
            exit 1
        fi
        rm "$agent"
    fi
    rm -rf "$app"
    printf 'Removed the legacy app/startup entry. Preferences, logs and migration backups remain.\n'
    exit 0
fi
if [ "$#" -gt 1 ]; then printf 'Usage: ./uninstall.sh [app-path | --legacy]\n' >&2; exit 2; fi
app="${1:-$HOME/Applications/RedClose.app}"
if [ "$(basename "$app")" != "RedClose.app" ] || [ ! -f "$app/Contents/MacOS/RedClose" ]; then
    printf 'Provide the path to the new RedClose.app; use --legacy for the old script installation.\n' >&2
    exit 2
fi
# Refuse older binaries rather than accidentally launching their UI with an
# unknown command. Manual removal remains available for those versions.
if [ "$(/usr/bin/plutil -extract RedCloseCommandVersion raw -expect integer "$app/Contents/Info.plist" 2>/dev/null || true)" != "1" ]; then
    printf 'This version has no locked removal helper. Turn off login, quit it, then move it to Trash (or use --legacy for the original background app).\n' >&2
    exit 2
fi
"$app/Contents/MacOS/RedClose" --while-idle --unregister-login /bin/rm -rf "$app"
printf 'Removed %s and its native login registration. Preferences and diagnostic exports remain.\n' "$app"
printf 'Remove its Accessibility entry in System Settings.\n'

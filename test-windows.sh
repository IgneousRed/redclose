#!/bin/sh
# Interactive native check: briefly opens disposable windows and switches Spaces.
set -eu
cd "$(dirname "$0")"
mkdir -p .work
scratch=$(mktemp -d "$PWD/.work/window-test.XXXXXX")
trap 'rm -rf "$scratch"' EXIT HUP INT TERM
xcrun swiftc -swift-version 5 -warnings-as-errors Sources/RedClose.swift Tests/WindowProbe.swift \
    -o "$scratch/window-probe" -framework AppKit -framework ApplicationServices
for name in WindowProbe WindowObserver; do
    app="$scratch/$name.app"
    mkdir -p "$app/Contents/MacOS"
    cp "$scratch/window-probe" "$app/Contents/MacOS/$name"
    /usr/bin/plutil -create xml1 "$app/Contents/Info.plist"
    /usr/bin/plutil -insert CFBundleExecutable -string "$name" "$app/Contents/Info.plist"
    /usr/bin/plutil -insert CFBundleIdentifier -string "local.redclose.$name" "$app/Contents/Info.plist"
    /usr/bin/plutil -insert CFBundleName -string "$name" "$app/Contents/Info.plist"
    /usr/bin/plutil -insert CFBundlePackageType -string APPL "$app/Contents/Info.plist"
    /usr/bin/plutil -insert NSPrincipalClass -string NSApplication "$app/Contents/Info.plist"
    /usr/bin/codesign --force --sign - "$app"
done

"$scratch/WindowProbe.app/Contents/MacOS/WindowProbe" "$scratch/probe-result.txt" viewer \
    "$scratch/WindowObserver.app/Contents/MacOS/WindowObserver"

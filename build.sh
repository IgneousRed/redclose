#!/bin/sh
set -eu
cd "$(dirname "$0")"
mode="release"
if [ "${1:-}" = "--debug" ]; then mode="debug"; shift; fi
if [ "$#" -ne 0 ]; then printf 'Usage: ./build.sh [--debug]\n' >&2; exit 2; fi
architecture=$(uname -m)
output="dist"
if [ "$mode" = "debug" ]; then output="dist/Debug"; fi
app="$output/RedClose.app"
stamp="$output/build-inputs.sha256"
build_key=$({ /usr/bin/shasum -a 256 Sources/*.swift Resources/Info.plist Tools/MakeIcon.swift LICENSE build.sh; xcrun swiftc --version; printf '%s\n' "$mode" "$architecture"; } | /usr/bin/shasum -a 256)
if [ -f "$stamp" ] && [ "$(cat "$stamp")" = "$build_key" ] && /usr/bin/codesign --verify --strict "$app" 2>/dev/null; then
    printf 'Build is current; preserving its signature.\n'
    exit 0
fi
mkdir -p "$output" .work
scratch=$(mktemp -d "$PWD/.work/build.XXXXXX")
trap 'rm -rf "$scratch"' EXIT HUP INT TERM
staged="$scratch/RedClose.app"
mkdir -p "$staged/Contents/MacOS" "$staged/Contents/Resources"
if [ "$mode" = "debug" ]; then
    xcrun swiftc -swift-version 5 -warnings-as-errors -g -Onone -D DEBUG \
        -target "$(uname -m)-apple-macos13.0" Sources/*.swift -o "$staged/Contents/MacOS/RedClose" \
        -framework AppKit -framework ApplicationServices -framework ServiceManagement
else
    xcrun swiftc -swift-version 5 -warnings-as-errors -O -target "$architecture-apple-macos13.0" \
        Sources/*.swift -o "$staged/Contents/MacOS/RedClose" \
        -framework AppKit -framework ApplicationServices -framework ServiceManagement
fi
xcrun swiftc -swift-version 5 -warnings-as-errors Tools/MakeIcon.swift -o "$scratch/make-icon" -framework AppKit
"$scratch/make-icon" "$scratch/RedClose.iconset"
/usr/bin/iconutil -c icns "$scratch/RedClose.iconset" -o "$staged/Contents/Resources/RedClose.icns"
cp Resources/Info.plist "$staged/Contents/Info.plist"
cp LICENSE "$staged/Contents/Resources/LICENSE"
/usr/bin/plutil -lint "$staged/Contents/Info.plist"
/usr/bin/codesign --force --sign - --identifier local.redclose "$staged"
/usr/bin/codesign --verify --strict "$staged"
# Keep the last working generated build until its replacement has passed verification.
if [ -d "$app" ]; then
    rm -rf "$output/RedClose.previous.app"
    mv "$app" "$output/RedClose.previous.app"
fi
mv "$staged" "$app"
printf '%s\n' "$build_key" > "$stamp"
printf 'Built %s/%s (ad-hoc signed; not notarized)\n' "$PWD" "$app"

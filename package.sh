#!/bin/sh
set -eu
cd "$(dirname "$0")"
./build.sh
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' dist/RedClose.app/Contents/Info.plist)
channel=$(/usr/libexec/PlistBuddy -c 'Print :RedCloseReleaseChannel' dist/RedClose.app/Contents/Info.plist)
if [ -n "$channel" ]; then version="$version-$channel"; fi
mkdir -p .work
scratch=$(mktemp -d "$PWD/.work/package.XXXXXX")
trap 'rm -rf "$scratch"' EXIT HUP INT TERM
folder="RedClose-$version-$(uname -m)"
mkdir -p "$scratch/$folder"
/usr/bin/ditto dist/RedClose.app "$scratch/$folder/RedClose.app"
cp docs/INSTALL.txt "$scratch/$folder/READ ME FIRST.txt"
cp LICENSE "$scratch/$folder/LICENSE"
# Publish portable app files, not the build machine's extended attributes/ACLs.
/usr/bin/ditto -c -k --norsrc --noextattr --noacl --keepParent "$scratch/$folder" "dist/$folder.zip"
(cd dist && /usr/bin/shasum -a 256 "$folder.zip" > "$folder.zip.sha256")
printf 'Prepared local beta: %s/dist/%s.zip\n' "$PWD" "$folder"
printf 'No upload, Developer ID signing, or notarization performed.\n'

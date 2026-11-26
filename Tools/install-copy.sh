#!/bin/sh
# File-only installation step; the caller holds the app lock for replacements.
set -eu
if [ "$#" -ne 3 ]; then exit 2; fi
source_app="$1"
destination="$2"
backup_root="$3"
scratch=$(mktemp -d "$(dirname "$destination")/.redclose-install.XXXXXX")
backup=""
cleanup() {
    if [ -n "$backup" ] && [ ! -e "$destination" ] && [ -d "$backup/RedClose.app" ]; then
        mv "$backup/RedClose.app" "$destination"
    fi
    rm -rf "$scratch"
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM
/usr/bin/ditto "$source_app" "$scratch/RedClose.app"
/usr/bin/codesign --verify --strict "$scratch/RedClose.app"
if [ -e "$destination" ]; then
    mkdir -p "$backup_root"
    backup=$(mktemp -d "$backup_root/install.XXXXXX")
    mv "$destination" "$backup/RedClose.app"
fi
mv "$scratch/RedClose.app" "$destination"
if [ -n "$backup" ]; then printf 'Previous app kept at %s/RedClose.app\n' "$backup"; fi

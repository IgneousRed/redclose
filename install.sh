#!/bin/sh
# Optional source install; downloaded apps can simply be moved in Finder.
set -eu
cd "$(dirname "$0")"
if [ "$#" -ne 0 ]; then printf 'Usage: ./install.sh\n' >&2; exit 2; fi
./build.sh
applications="$HOME/Applications"
destination="$applications/RedClose.app"
backup_root="$HOME/Library/Application Support/RedClose/Previous Installs"
mkdir -p "$applications"
if [ -e "$destination" ]; then
    dist/RedClose.app/Contents/MacOS/RedClose --while-idle /bin/sh "$PWD/Tools/install-copy.sh" \
        "$PWD/dist/RedClose.app" "$destination" "$backup_root"
else
    # A first install may coexist with the old background copy until UI migration.
    /bin/sh Tools/install-copy.sh "$PWD/dist/RedClose.app" "$destination" "$backup_root"
fi
# Launch only after the lock-owning helper has exited.
/usr/bin/open "$destination"
printf 'Installed %s. Launch at login is opt-in in Settings.\n' "$destination"
printf 'Older installations and their startup entries are preserved until you choose migration.\n'

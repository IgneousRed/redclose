#!/bin/sh
# Disposable signed file fixtures only: no app launch, login service or HOME override.
set -eu
fixture="$1/install fixture"
mkdir -p "$fixture/source/RedClose.app/Contents/MacOS" "$fixture/Applications"
source_app="$fixture/source/RedClose.app"
destination="$fixture/Applications/RedClose.app"
backup_root="$fixture/backups"
cp /usr/bin/true "$source_app/Contents/MacOS/RedClose"
/usr/bin/plutil -create xml1 "$source_app/Contents/Info.plist"
/usr/bin/plutil -insert CFBundleExecutable -string RedClose "$source_app/Contents/Info.plist"
/usr/bin/plutil -insert CFBundleIdentifier -string local.redclose.install-fixture "$source_app/Contents/Info.plist"
/usr/bin/codesign --force --sign - "$source_app" 2>/dev/null
/bin/sh Tools/install-copy.sh "$source_app" "$destination" "$backup_root" > "$fixture/install-output.txt"
/usr/bin/codesign --verify --strict "$destination"
printf 'keep original\n' > "$destination/old-marker.txt"
/usr/bin/ditto "$source_app" "$fixture/broken.app"
printf 'invalid executable\n' > "$fixture/broken.app/Contents/MacOS/RedClose"
if /bin/sh Tools/install-copy.sh "$fixture/broken.app" "$destination" "$backup_root" >"$fixture/expected-error.txt" 2>&1; then
    printf 'FAIL: invalid source unexpectedly installed\n' >&2
    exit 1
fi
[ "$(cat "$destination/old-marker.txt")" = 'keep original' ]
/bin/sh Tools/install-copy.sh "$source_app" "$destination" "$backup_root" > "$fixture/install-output.txt"
[ ! -f "$destination/old-marker.txt" ]
[ "$(cat "$backup_root"/install.*/RedClose.app/old-marker.txt)" = 'keep original' ]
/usr/bin/codesign --verify --strict "$destination"
[ -z "$(find "$fixture/Applications" -name '.redclose-install.*' -print)" ]
# Inject failure in the final move, after the old app has already been backed
# up. Source the real step in a separate shell; do not override PATH or HOME.
cat > "$fixture/fail-final-move.sh" <<'WRAPPER'
#!/bin/sh
failure_mode="$1"
shift
mv() {
    case "$1" in
        */.redclose-install.*/RedClose.app)
            if [ "$failure_mode" = interrupt ]; then kill -TERM "$$"; fi
            return 1 ;;
        *) /bin/mv "$@" ;;
    esac
}
. Tools/install-copy.sh
WRAPPER
printf 'restore current\n' > "$destination/current-marker.txt"
for failure_mode in error interrupt; do
    if /bin/sh "$fixture/fail-final-move.sh" "$failure_mode" "$source_app" "$destination" "$backup_root" >"$fixture/expected-$failure_mode.txt" 2>&1; then
        printf 'FAIL: failed final move reported success\n' >&2
        exit 1
    fi
    [ "$(cat "$destination/current-marker.txt")" = 'restore current' ]
    [ -z "$(find "$fixture/Applications" -name '.redclose-install.*' -print)" ]
done
agent="$fixture/legacy.plist"
/usr/bin/plutil -create xml1 "$agent"
/usr/bin/plutil -insert Label -string local.redclose "$agent"
/usr/bin/plutil -insert ProgramArguments -array "$agent"
/usr/bin/plutil -insert ProgramArguments.0 -string "$destination/Contents/MacOS/RedClose" "$agent"
/bin/sh Tools/validate-legacy.sh "$agent" "$destination/Contents/MacOS/RedClose"
/usr/bin/plutil -insert Program -string /unrelated/executable "$agent"
if /bin/sh Tools/validate-legacy.sh "$agent" "$destination/Contents/MacOS/RedClose"; then exit 1; fi
/usr/bin/plutil -remove Program "$agent"
/usr/bin/plutil -insert ProgramArguments.1 -string unexpected "$agent"
if /bin/sh Tools/validate-legacy.sh "$agent" "$destination/Contents/MacOS/RedClose"; then exit 1; fi
printf 'PASS: disposable installation, invalid-build rejection, failed/interrupted replacement recovery, cleanup and strict legacy-entry checks\n'

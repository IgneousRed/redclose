#!/bin/sh
set -eu
cd "$(dirname "$0")"
mkdir -p .work
scratch=$(mktemp -d "$PWD/.work/tests.XXXXXX")
trap 'rm -rf "$scratch"' EXIT HUP INT TERM
xcrun swiftc -swift-version 5 -warnings-as-errors Sources/RedClose.swift Tests/CloseTests.swift \
    -o "$scratch/close-tests" -framework AppKit -framework ApplicationServices
"$scratch/close-tests"
xcrun swiftc -swift-version 5 -warnings-as-errors -target "$(uname -m)-apple-macos13.0" \
    Sources/Preferences.swift Sources/LoginManagement.swift Tests/AppTests.swift \
    -o "$scratch/app-tests" -framework AppKit -framework ServiceManagement
"$scratch/app-tests" "$scratch"
xcrun swiftc -swift-version 5 -warnings-as-errors -target "$(uname -m)-apple-macos13.0" \
    Sources/LoginManagement.swift Tests/LifecycleTests.swift \
    -o "$scratch/lifecycle-tests" -framework AppKit -framework ServiceManagement
"$scratch/lifecycle-tests" "$scratch"
/bin/sh Tests/InstallTests.sh "$scratch"
xcrun swiftc -swift-version 5 -warnings-as-errors Tools/MakeIcon.swift -o "$scratch/make-icon" -framework AppKit
"$scratch/make-icon" "$scratch/test.iconset"
xcrun swiftc -swift-version 5 -warnings-as-errors Tests/AssetTests.swift -o "$scratch/asset-tests" -framework AppKit
"$scratch/asset-tests" "$scratch/test.iconset"
for script in ./*.sh Tools/*.sh Tests/*.sh; do /bin/sh -n "$script"; done

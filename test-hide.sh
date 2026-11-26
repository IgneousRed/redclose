#!/bin/sh
set -eu
cd "$(dirname "$0")"
mkdir -p .work
scratch=$(mktemp -d "$PWD/.work/hide-test.XXXXXX")
trap 'rm -rf "$scratch"' EXIT HUP INT TERM
xcrun swiftc -swift-version 5 -warnings-as-errors Sources/RedClose.swift Tests/HideProbe.swift \
    -o "$scratch/hide-probe" -framework AppKit -framework ApplicationServices
"$scratch/hide-probe"

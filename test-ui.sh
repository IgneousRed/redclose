#!/bin/sh
# Briefly opens an isolated debug Settings window; never monitors or quits other apps.
set -eu
cd "$(dirname "$0")"
./build.sh --debug
dist/Debug/RedClose.app/Contents/MacOS/RedClose --ui-smoke-test
dist/Debug/RedClose.app/Contents/MacOS/RedClose --ui-smoke-test --simulate-nonowner

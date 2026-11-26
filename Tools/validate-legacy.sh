#!/bin/sh
# Read-only counterpart of LegacyLogin.validate for the compiler-free remover.
set -eu
if [ "$#" -ne 2 ]; then exit 2; fi
agent="$1"
executable="$2"
[ "$(/usr/bin/plutil -extract Label raw -expect string "$agent")" = "local.redclose" ]
[ "$(/usr/bin/plutil -extract ProgramArguments raw -expect array "$agent")" = "1" ]
[ "$(/usr/bin/plutil -extract ProgramArguments.0 raw -expect string "$agent")" = "$executable" ]
if /usr/bin/plutil -type Program "$agent" >/dev/null 2>&1; then exit 1; fi

#!/bin/sh
# Runs the ZShotCore tests. With Command Line Tools only, swift test cannot find
# the Testing framework on its own, so point the compiler and linker at it.
set -eu

CLT=/Library/Developer/CommandLineTools
if [ "$(xcode-select -p 2>/dev/null || true)" = "$CLT" ]; then
    F="$CLT/Library/Developer/Frameworks"
    L="$CLT/Library/Developer/usr/lib"
    exec swift test \
        -Xswiftc -F -Xswiftc "$F" \
        -Xlinker -F -Xlinker "$F" \
        -Xlinker -rpath -Xlinker "$F" \
        -Xlinker -rpath -Xlinker "$L" \
        "$@"
fi
exec swift test "$@"

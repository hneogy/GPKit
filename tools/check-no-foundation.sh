#!/bin/sh
# GPKit's core without Foundation: every file of the library but the bridge to Foundation's Date (Date.swift) is
# type-checked as a module with no Foundation in it. If one of them came to use Foundation, this stops.
# Run from the package's root.
set -eu
files=$(ls Sources/GPKit/*.swift | grep -v '/Date\.swift$')
if grep -n 'import Foundation' $files; then
    echo "a file of the core imports Foundation" >&2
    exit 1
fi
swiftc -typecheck -swift-version 6 -module-name GPKit $files
echo "GPKit's core, $(echo "$files" | wc -l | tr -d ' ') files, compiles without Foundation"

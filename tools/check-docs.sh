#!/bin/sh
# GPKit's documentation and its tutorials built with DocC, a warning counted as an error: a broken link, a symbol
# that is no longer there, or a tutorial missing a part stops here. Run from the package's root, where Xcode's DocC is.
# The tutorials' code is held by Tests/GPKitTests/TutorialTests.swift.
set -eu
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
swift build --target GPKit -Xswiftc -emit-symbol-graph -Xswiftc -emit-symbol-graph-dir -Xswiftc "$out/symbols" > "$out/build.log" 2>&1 \
    || { cat "$out/build.log" >&2; exit 1; }
xcrun docc convert Sources/GPKit/GPKit.docc --additional-symbol-graph-dir "$out/symbols" \
    --fallback-display-name GPKit --fallback-bundle-identifier com.github.hneogy.GPKit \
    --output-path "$out/GPKit.doccarchive" --warnings-as-errors
echo "GPKit's documentation and its $(ls Sources/GPKit/GPKit.docc/Tutorials | command grep -cv '^Tutorials.tutorial$') tutorials build in DocC"

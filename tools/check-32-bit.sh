#!/bin/sh
# GPKit's core compiled where Int is 32 bits wide: for arm64_32 (Apple Watch), the same width as WebAssembly's wasm32.
# A count that does not fit, such as a day's microseconds in Int, stops it. The core is compiled to SIL, where an
# integer literal that overflows is found; type-checking alone does not find it. Run from the package's root on a Mac.
set -eu
sdk=$(xcrun --sdk watchos --show-sdk-path)
files=$(ls Sources/GPKit/*.swift | command grep -v '/Date\.swift$')
swiftc -emit-sil -wmo -o /dev/null -swift-version 6 -module-name GPKit -target arm64_32-apple-watchos9.0 -sdk "$sdk" $files
echo "GPKit's core, $(echo "$files" | wc -l | tr -d ' ') files, compiles where Int is 32 bits"

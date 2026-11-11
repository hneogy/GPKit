#!/bin/sh
# The bit record on this platform: the release build's Propagator.state outputs against the record committed in
# conformance/bit-records/ for this platform, every number to the bit. Run from the package's root. A difference
# fails the run: say it in the changelog and record the platform again (tools/bit-record/README.md).
set -eu
swift build -c release --package-path tools/bit-record
bin=$(swift build -c release --package-path tools/bit-record --show-bin-path)/gpkit-bit-record
platform=$("$bin" --platform)
record=conformance/bit-records/$platform.txt
test -f "$record" || { echo "no bit record for $platform ($record)" >&2; exit 1; }
"$bin" --check "$record"

#!/bin/sh
# The example projects in Examples/ built against this checkout of GPKit, and the two command-line ones run on the
# Space Station's first element set (Examples/data/iss-1998.tle), from its epoch, over 40° N, 75° W: their lines are
# held to what the tutorials print for the same set (Tests/GPKitTests/TutorialTests.swift). The SwiftUI one, SkyView,
# is built where SwiftUI is. Run from the package's root.
set -eu
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
from=1998-11-20T06:49:59.999808
for example in PassPredictor Doppler; do
    swift build --package-path "Examples/$example" > "$out/build.log" 2>&1 || { cat "$out/build.log" >&2; exit 1; }
done
swift run --skip-build --package-path Examples/PassPredictor pass-predictor Examples/data/iss-1998.tle 40 -75 --from $from > "$out/passes.txt"
swift run --skip-build --package-path Examples/Doppler doppler Examples/data/iss-1998.tle 40 -75 145800000 --uplink 145990000 \
    --from $from --step 60 > "$out/doppler.txt"
expect() {  # expect FILE LINE: the file holds the line
    grep -qxF -- "$2" "$out/$1" || { echo "$1 does not hold \"$2\"; it is:" >&2; cat "$out/$1" >&2; exit 1; }
}
expect passes.txt "  1998-11-20T14:05:39.422000  highest 15°  1998-11-20T14:12:14.859000"
expect passes.txt "  1998-11-20T21:54:14.805000  highest 17°  1998-11-20T22:01:00.048000"
[ "$(grep -c highest "$out/passes.txt")" = 6 ] || { echo "pass-predictor did not find the six passes" >&2; exit 1; }
expect doppler.txt "1998-11-20T14:05:39.422000   202.2°       0.0°  145803279      145986717"
expect doppler.txt "1998-11-20T14:12:14.859000    69.1°       0.0°  145796739      145993265"
echo "pass-predictor and doppler print the tutorials' figures"
if [ "$(uname)" = Darwin ]; then
    swift build --package-path Examples/SkyView > "$out/build.log" 2>&1 || { cat "$out/build.log" >&2; exit 1; }
    echo "SkyView builds"
fi

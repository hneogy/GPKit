#!/bin/sh
# The data-age tool on a known input: the ISS sample, and the same elements with the epoch a day later. Exactly one
# pair, one day old, low Earth, its error the one GPKit's Propagator gives (DataAgeTests holds the library to that);
# here, that the tool reads the files and writes what it says it writes. Run from the package's root.
set -eu
dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT
printf 'ISS\r\n1 25544U 98067A   98324.28472222 -.00003657  11563-4  00000+0 0    10\r\n2 25544  51.5908 168.3788 0125362  86.4185 359.7454 16.05064833    05\r\nISS\r\n1 25544U 98067A   98325.28472222 -.00003657  11563-4  00000+0 0    11\r\n2 25544  51.5908 168.3788 0125362  86.4185 359.7454 16.05064833    05\r\n' > "$dir/two.tle"
swift run --package-path tools/data-age gpkit-data-age "$dir/out" "$dir/two.tle"
test "$(sed -n 2p "$dir/out/samples.csv" | cut -d, -f1-5)" = "25544,LEO,1998-11-20T06:49:59.999808,1998-11-21T06:49:59.999808,1.0" \
    || { echo "samples.csv is not the one pair expected:" >&2; cat "$dir/out/samples.csv" >&2; exit 1; }
test "$(wc -l < "$dir/out/samples.csv" | tr -d ' ')" = 2 || { echo "more than one pair" >&2; exit 1; }
test "$(cut -d, -f1-4 "$dir/out/table.csv" | sed -n 2p)" = "LEO,0.0,1.0,1" || { echo "table.csv is not one row" >&2; cat "$dir/out/table.csv" >&2; exit 1; }
echo "the data-age tool: one pair, one day old, one row"

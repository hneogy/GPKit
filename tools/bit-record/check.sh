#!/bin/sh
# The bit record on this platform: the release build's Propagator.state outputs against the record committed in
# conformance/bit-records/ for this platform, every number to the bit. Run from the package's root; any arguments go to
# swift build (Windows CI gives --build-system native). A difference fails the run: say it in the changelog and record
# the platform again (tools/bit-record/README.md). With no record for this platform, the run fails too, and the record
# it made is left in tools/bit-record/.build/ for the owner to read, compare and commit (CI uploads it).
set -eu
swift build -c release --package-path tools/bit-record "$@"
bin=$(swift build -c release --package-path tools/bit-record "$@" --show-bin-path)/gpkit-bit-record
work=tools/bit-record/.build
platform=$("$bin" --platform)
record=conformance/bit-records/$platform.txt
GPKIT_SWIFT_VERSION=$(swift --version 2>&1 | head -n 1)
export GPKIT_SWIFT_VERSION

# the ULP arithmetic, on fixed pairs, before any record is trusted
"$bin" --self-test

# the counts the tool's README states are the ones the tool makes
"$bin" > "$work/bit-record-made.txt"
/usr/bin/grep -q '39 made-up sets at 22 times' "$work/bit-record-made.txt" \
  && /usr/bin/grep -q 'The sets:\*\* 39' tools/bit-record/README.md \
  && /usr/bin/grep -q 'ten days after: 22' tools/bit-record/README.md \
  || { echo "the counts (39 sets, 22 times) differ between the tool and its README" >&2; exit 1; }

if [ ! -f "$record" ]; then
  tr -d '\r' < "$work/bit-record-made.txt" > "$work/bit-record-new-$platform.txt"
  for other in conformance/bit-records/*.txt; do "$bin" --compare "$other"; done
  echo "no bit record for $platform: the one made here is $work/bit-record-new-$platform.txt; read it, compare it" \
    "with the others above, and commit it as $record" >&2
  exit 1
fi

"$bin" --check "$record"

# the check fails when it should: the record with the last hex digit of one number changed
tr -d '\r' < "$record" | awk '!/^#/ && !done && NF == 8 { d = substr($3, 16, 1); $3 = substr($3, 1, 15) (d == "0" ? "1" : "0"); done = 1 } { print }' > "$work/bit-record-planted.txt"
status=0; out=$("$bin" --check "$work/bit-record-planted.txt") || status=$?
[ "$status" = 1 ] || { echo "the check did not fail on a planted change (exit $status): $out" >&2; exit 1; }
echo "$out" | /usr/bin/grep -q ': 1 of [0-9]* numbers moved, 0 lines differ in kind' \
  || { echo "the planted change was not reported as one number moved: $out" >&2; exit 1; }
echo "a planted change is caught: $(echo "$out" | /usr/bin/grep 'numbers moved')"

# the record made twice in one run is the same (all but the time it was made)
"$bin" | /usr/bin/grep -v '^# made ' > "$work/bit-record-again.txt"
/usr/bin/grep -v '^# made ' "$work/bit-record-made.txt" | cmp -s - "$work/bit-record-again.txt" \
  || { echo "the record made twice in one run differs" >&2; exit 1; }
echo "the record made twice in this run is the same"

# the other platforms' records, for information only: platforms are not promised to agree
for other in conformance/bit-records/*.txt; do
  [ "$other" = "$record" ] || "$bin" --compare "$other"
done

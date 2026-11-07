#!/bin/sh
# The gpkit command-line tool, run on the Space Station's first element set (Examples/data/iss-1998.tle), from its
# epoch, over 40° N, 75° W: its lines are held to what the tutorials print for the same set (TutorialTests), and each
# kind of failure to its exit code. Run from the package's root, with the tool's path: sh tools/check-cli.sh PATH.
set -eu
gpkit=$1
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
data=Examples/data/iss-1998.tle
from=1998-11-20T06:49:59.999808
run() {  # run NAME EXPECTED-EXIT ARGUMENTS...: the tool's standard output in $out/NAME, its exit code checked
    name=$1 expected=$2
    shift 2
    status=0
    "$gpkit" "$@" > "$out/$name" 2> "$out/$name.err" || status=$?
    tr -d '\r' < "$out/$name" > "$out/$name.lf" && mv "$out/$name.lf" "$out/$name"
    [ "$status" = "$expected" ] || { echo "gpkit $*: exit $status, not $expected" >&2; cat "$out/$name.err" >&2; exit 1; }
}
expect() {  # expect NAME LINE: the output holds the line
    command grep -qxF -- "$2" "$out/$1" || { echo "gpkit's $1 does not hold \"$2\"; it is:" >&2; cat "$out/$1" >&2; exit 1; }
}
run read 0 read "$data"
expect read "ISS (ZARYA) (catalog number 25544)  epoch 1998-11-20T06:49:59.999808"
expect read "1 read, 0 refused"
# the set written as a TLE is the file's own lines
run tle 0 tle "$data"
tr -d '\r' < "$data" > "$out/data"
cmp -s "$out/tle" "$out/data" || { echo "gpkit tle does not give back the file's lines" >&2; diff "$out/data" "$out/tle" >&2; exit 1; }
run passes 0 passes "$data" 40 -75 --from $from --light
expect passes "  1998-11-20T14:05:39.422000  highest 15°  1998-11-20T14:12:14.859000  daylight"
expect passes "  1998-11-20T21:54:14.805000  highest 17°  1998-11-20T22:01:00.048000  twilight"
[ "$(command grep -c highest "$out/passes")" = 6 ] || { echo "gpkit passes did not find the six passes" >&2; exit 1; }
run where 0 where "$data" --at 1998-11-20T14:09:00 --observer 40 -75
expect where "  azimuth 137.3°  elevation 14.5°  range 665.2 km"
run track 0 track "$data" --from $from --minutes 3 --step 60
[ "$(command grep -c ' km$' "$out/track")" = 4 ] || { echo "gpkit track did not give four points" >&2; cat "$out/track" >&2; exit 1; }
# a rough close-approach screen of the station and a made-up copy tilted a degree: their nearest in six hours, and
# what the screen is said on standard error
run approaches 0 approaches Examples/data/iss-1998-and-tilted.tle --from $from --hours 6 --within 50
head -1 "$out/approaches" | command grep -q "^1998-11-20T07:13:00.49[0-9]*     0.399 km    0.135 km/s  ISS (ZARYA)" || {
    echo "gpkit approaches did not give the pair's nearest, 0.399 km at 07:13:00.49:" >&2; cat "$out/approaches" >&2; exit 1; }
command grep -q "not for operational collision avoidance" "$out/approaches.err" || { echo "gpkit approaches did not say what it is" >&2; exit 1; }
command grep -q "does not mean the objects are safe" "$out/approaches.err" || { echo "gpkit approaches did not say what no approach means" >&2; exit 1; }
# standard input with its format named
run stdin 0 read - --format tle < "$data"
expect stdin "1 read, 0 refused"
# a record GPKit refuses: exit 1, and the refusal said
sed 's/16.05064833    05$/16.05064833    06/' "$data" > "$out/bad.tle"
run refused 1 read "$out/bad.tle"
expect refused "0 read, 1 refused"
# a command line it does not understand: exit 2
run unknown 2 nope
run nonumber 2 passes "$data" north -75
echo "gpkit prints the tutorials' figures and exits 0, 1 and 2 as it says"

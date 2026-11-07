#!/bin/sh
# Hamlib's dummy rotator follows a pass that gpkit rotator gives: the Space Station's first element set
# (Examples/data/iss-1998.tle), its first pass over 40° N, 75° W from the epoch, a position a minute. Each command goes
# to rotctld (model 1, the dummy) through rotctl (model 2, a rotator over the network), and the rotator's position is
# read back until it is the one asked for. The track is held to the tutorial's figures at both ends, and the rotator
# must refuse a position outside its range, so that what answers is a rotator that can say no.
# Needs Hamlib's rotctl and rotctld. Run from the package's root: sh tools/check-rotator.sh PATH-TO-GPKIT
set -eu
gpkit=$1
port=4533
out=$(mktemp -d)
rotctld -m 1 -T 127.0.0.1 -t $port > "$out/rotctld.log" 2>&1 &
daemon=$!
trap 'kill $daemon 2>/dev/null || true; rm -rf "$out"' EXIT
rot() { rotctl -m 2 -r 127.0.0.1:$port "$@"; }
# wait for the daemon to answer
tries=0
until rot p > /dev/null 2>&1; do
    tries=$((tries + 1))
    [ $tries -lt 50 ] || { echo "rotctld did not answer" >&2; cat "$out/rotctld.log" >&2; exit 1; }
    sleep 0.2
done
echo "rotctld: $(rotctld --version 2>&1 | head -1)"

"$gpkit" rotator Examples/data/iss-1998.tle 40 -75 --from 1998-11-20T06:49:59.999808 --step 60 > "$out/commands" 2> "$out/notes"
cat "$out/notes"
[ "$(head -1 "$out/commands")" = "P 202.2 0.0" ] || { echo "the first position is not the tutorial's rise, 202.2 degrees" >&2; cat "$out/commands" >&2; exit 1; }
[ "$(tail -1 "$out/commands")" = "P 69.1 0.0" ] || { echo "the last position is not the tutorial's set, 69.1 degrees" >&2; cat "$out/commands" >&2; exit 1; }

followed=0
while read -r command azimuth elevation; do
    [ "$command" = P ] || { echo "not a set-position command: $command $azimuth $elevation" >&2; exit 1; }
    rot P "$azimuth" "$elevation" > "$out/answer" 2>&1 || { echo "rotctl refused P $azimuth $elevation:" >&2; cat "$out/answer" >&2; exit 1; }
    # the dummy turns at its own pace: read its position until it is there, up to 120 seconds
    waited=0
    while :; do
        rot p > "$out/position" 2>&1
        at_azimuth=$(sed -n 1p "$out/position")
        at_elevation=$(sed -n 2p "$out/position")
        if awk -v a="$at_azimuth" -v e="$at_elevation" -v wa="$azimuth" -v we="$elevation" \
            'BEGIN { d = a - wa; if (d < 0) d = -d; f = e - we; if (f < 0) f = -f; exit !(d <= 0.15 && f <= 0.15) }'; then
            break
        fi
        waited=$((waited + 1))
        [ $waited -lt 600 ] || { echo "the rotator did not reach $azimuth $elevation: it is at $at_azimuth $at_elevation" >&2; exit 1; }
        sleep 0.2
    done
    echo "P $azimuth $elevation -> at $at_azimuth $at_elevation"
    followed=$((followed + 1))
done < "$out/commands"
[ $followed = 8 ] || { echo "the rotator followed $followed positions, not the pass's 8" >&2; exit 1; }

# a position outside the rotator's range is refused
if rot P 999.0 0.0 > "$out/refused" 2>&1 && ! command grep -qiE 'RPRT -|error|invalid' "$out/refused"; then
    echo "the rotator took an azimuth of 999 degrees: what answers is not a rotator that keeps its limits" >&2
    cat "$out/refused" >&2
    exit 1
fi
echo "Hamlib's dummy rotator followed the pass's 8 positions, and refused an azimuth of 999 degrees"

#!/usr/bin/env python3
"""A named OEM reader reads what `gpkit oem` writes: the `oem` package for Python (https://github.com/bradsease/oem,
MIT), which follows CCSDS 502.0-B-3. CI installs it at a pinned version.

    python3 tools/check_oem.py PATH-TO-GPKIT

The Space Station's first element set (Examples/data/iss-1998.tle), a revolution from its epoch at one-minute steps:
the reader must open the message, give its metadata and its 96 states, each number the one written, and the states
must hang together (the position's change over two minutes, divided by the time, near the velocity written). The
reader must refuse two broken copies, so that what reads the message is a reader that can say no.
"""

import datetime
import os
import subprocess
import sys
import tempfile

from oem import OrbitEphemerisMessage


def main() -> None:
    gpkit = sys.argv[1]
    with tempfile.TemporaryDirectory() as folder:
        path = os.path.join(folder, "iss.oem")
        text = subprocess.run([gpkit, "oem", "Examples/data/iss-1998.tle", "--from", "1998-11-20T06:49:59.999808",
                               "--minutes", "95", "--step", "60", "--originator", "GPKit CI"],
                              check=True, capture_output=True, text=True).stdout
        with open(path, "w", encoding="utf-8") as f:
            f.write(text)
        message = OrbitEphemerisMessage.open(path)
        segments = list(message)
        assert len(segments) == 1, f"{len(segments)} segments"
        meta = segments[0].metadata
        for key, want in [("OBJECT_NAME", "ISS (ZARYA)"), ("OBJECT_ID", "1998-067A"), ("CENTER_NAME", "EARTH"),
                          ("REF_FRAME", "TEME"), ("TIME_SYSTEM", "UTC")]:
            assert meta[key] == want, f"{key}: {meta[key]!r}, not {want!r}"
        states = message.states
        assert len(states) == 96, f"{len(states)} states"

        # each number the one written
        written = [line.split() for line in text.splitlines() if line[:1].isdigit()]
        assert len(written) == 96
        for state, fields in zip(states, written):
            got = list(state.position) + list(state.velocity)
            assert got == [float(x) for x in fields[1:]], f"{fields[0]}: read {got}"
            # the reader's time against the text's, as instants: within a millisecond
            seconds = abs((state.epoch.utc.datetime - datetime.datetime.fromisoformat(fields[0])).total_seconds())
            assert seconds < 0.001, f"{state.epoch.utc.isot} against {fields[0]}"

        # the states hang together: the position's change over two minutes against the velocity at the middle
        worst = 0.0
        for before, middle, after in zip(states, states[1:], states[2:]):
            for k in range(3):
                rate = (after.position[k] - before.position[k]) / 120.0
                worst = max(worst, abs(rate - middle.velocity[k]))
        assert worst < 0.01, f"velocity and the positions' change differ by {worst} km/s"
        print(f"oem read gpkit's message: 1 segment, 96 states, TEME, UTC, every number as written; "
              f"positions' change and velocity within {worst * 1000:.2f} m/s")

        # two broken copies are refused
        def refused(name: str, broken: str) -> None:
            bad = os.path.join(folder, name)
            with open(bad, "w", encoding="utf-8") as f:
                f.write(broken)
            try:
                OrbitEphemerisMessage.open(bad)
            except Exception as error:
                print(f"oem refused {name}: {type(error).__name__}")
                return
            sys.exit(f"oem read {name}, which is broken: what reads gpkit's messages does not say no")

        refused("no-meta-stop.oem", text.replace("META_STOP\n", "", 1))
        lines = text.splitlines(keepends=True)
        first = next(i for i, line in enumerate(lines) if line[:1].isdigit())
        lines[first] = " ".join(lines[first].split()[:-1]) + "\n"
        refused("short-line.oem", "".join(lines))


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Earth-fixed states and right ascensions from Skyfield, for GPKit's to be compared with.

    python3 tools/skyfield_frames_reference.py

Reads Tests/GPKitTests/Resources/pass-check-sets.tle, the element sets of skyfield_passes_reference.py, and writes
Tests/GPKitTests/Resources/skyfield-frames.json: for each set, every ten minutes for six hours from its epoch cut to
the minute, the satellite's position and velocity in the Earth-fixed frame (Skyfield's ITRS, with no polar motion
given, so none applied), and its right ascension, declination and distance from one fixed place, geometric, for the
true equator and equinox of the date. The test FrameTests reads the file; it is committed, so CI makes the
comparison too.

Skyfield is not needed to build or test GPKit: only to make this file again.
"""
import json
import os

import sgp4
import skyfield
from skyfield.api import EarthSatellite, load, wgs84
from skyfield.framelib import itrs

HERE = os.path.dirname(os.path.abspath(__file__))
RESOURCES = os.path.join(HERE, "..", "Tests", "GPKitTests", "Resources")
LATITUDE, LONGITUDE, HEIGHT_M = 40.0, -75.0, 100.0


def describe(satellite, site, t):
    position, velocity = satellite.at(t).frame_xyz_and_velocity(itrs)
    ra, dec, distance = (satellite - site).at(t).radec(epoch="date")
    return {"time": t.utc_datetime().strftime("%Y-%m-%dT%H:%M:%S.%f"), "dut1": float(t.dut1),
            "position": [float(x) for x in position.km], "velocity": [float(x) for x in velocity.km_per_s],
            "right_ascension": ra.degrees, "declination": dec.degrees, "range": distance.km}


def main():
    ts = load.timescale(builtin=True)
    site = wgs84.latlon(LATITUDE, LONGITUDE, elevation_m=HEIGHT_M)
    lines = [l.rstrip("\r\n") for l in open(os.path.join(RESOURCES, "pass-check-sets.tle"))]
    sets = []
    for i in range(0, len(lines) - 2, 3):
        name, line1, line2 = lines[i], lines[i + 1], lines[i + 2]
        satellite = EarthSatellite(line1, line2, name, ts)
        y, mo, d, h, mi, _ = satellite.epoch.utc
        grid = [describe(satellite, site, ts.utc(y, mo, d, h, mi, 600.0 * n)) for n in range(0, 37)]
        sets.append({"name": name, "line1": line1, "line2": line2, "grid": grid})
        print(f"{name}: {len(grid)} times")
    out = {"skyfield": skyfield.__version__, "python_sgp4": sgp4.__version__,
           "observer": {"latitude": LATITUDE, "longitude": LONGITUDE, "height": HEIGHT_M}, "sets": sets}
    with open(os.path.join(RESOURCES, "skyfield-frames.json"), "w") as f:
        json.dump(out, f, indent=1)
        f.write("\n")


if __name__ == "__main__":
    main()

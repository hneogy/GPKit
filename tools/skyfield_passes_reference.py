#!/usr/bin/env python3
"""Pass predictions from Skyfield, for GPKit's to be compared with.

    python3 tools/skyfield_passes_reference.py

Reads Tests/GPKitTests/Resources/pass-check-sets.tle, a few element sets that are already public (see NOTICE), and
writes Tests/GPKitTests/Resources/skyfield-passes.json: for each set, every rise, culmination and set over one
fixed place in the two days after the set's epoch, as Skyfield's find_events gives them, with the altitude, azimuth,
distance and range rate Skyfield computes at each and the point of the WGS-84 ellipsoid it puts beneath the
satellite, and the same numbers on a grid of times whether the satellite is up or not. The test PassTests reads the file; it is committed, so CI makes the comparison too.

Skyfield is not needed to build or test GPKit: only to make this file again.
"""
import json
import os

import sgp4
import skyfield
from skyfield.api import EarthSatellite, load, wgs84

HERE = os.path.dirname(os.path.abspath(__file__))
RESOURCES = os.path.join(HERE, "..", "Tests", "GPKitTests", "Resources")
LATITUDE, LONGITUDE, HEIGHT_M = 40.0, -75.0, 100.0
DAYS = 2.0
KINDS = ["rise", "culmination", "set"]


def describe(satellite, site, t):
    topocentric = (satellite - site).at(t)
    altitude, azimuth, distance = topocentric.altaz()
    rate = topocentric.frame_latlon_and_rates(site)[5]
    beneath = wgs84.geographic_position_of(satellite.at(t))
    # dut1 is UT1 less UTC, in seconds, as Skyfield's timescale has it for the instant
    return {"time": t.utc_datetime().strftime("%Y-%m-%dT%H:%M:%S.%f"), "elevation": altitude.degrees, "azimuth": azimuth.degrees,
            "range": distance.km, "range_rate": rate.km_per_s, "dut1": float(t.dut1),
            "latitude": beneath.latitude.degrees, "longitude": beneath.longitude.degrees, "altitude": beneath.elevation.km}


def main():
    ts = load.timescale(builtin=True)
    site = wgs84.latlon(LATITUDE, LONGITUDE, elevation_m=HEIGHT_M)
    lines = [l.rstrip("\r\n") for l in open(os.path.join(RESOURCES, "pass-check-sets.tle"))]
    sets = []
    for i in range(0, len(lines) - 2, 3):
        name, line1, line2 = lines[i], lines[i + 1], lines[i + 2]
        satellite = EarthSatellite(line1, line2, name, ts)
        y, mo, d, h, mi, _ = satellite.epoch.utc
        start = ts.utc(y, mo, d, h, mi, 0)                 # the epoch, cut to the minute
        stop = ts.utc(y, mo, d, h, mi, DAYS * 86400.0)
        times, kinds = satellite.find_events(site, start, stop, altitude_degrees=0.0)
        events = [dict(describe(satellite, site, t), kind=KINDS[k]) for t, k in zip(times, kinds)]
        grid = [describe(satellite, site, ts.utc(y, mo, d, h, mi, 600.0 * n)) for n in range(0, 37)]   # every ten minutes, six hours
        sets.append({"name": name, "line1": line1, "line2": line2,
                     "start": start.utc_datetime().strftime("%Y-%m-%dT%H:%M:%S"), "duration": DAYS * 86400.0,
                     "events": events, "grid": grid})
        print(f"{name}: {len(events)} events, {sum(1 for e in events if e['kind'] == 'culmination')} culminations")
    out = {"skyfield": skyfield.__version__, "python_sgp4": sgp4.__version__,
           "observer": {"latitude": LATITUDE, "longitude": LONGITUDE, "height": HEIGHT_M}, "minimum_elevation": 0.0, "sets": sets}
    with open(os.path.join(RESOURCES, "skyfield-passes.json"), "w") as f:
        json.dump(out, f, indent=1)
        f.write("\n")


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Propagate every element set of a gpconf corpus with python-sgp4, for GPKit to be checked against.

    python3 tools/python_sgp4_reference.py CORPUS OUT.json

CORPUS is a copy of gp-omm-conformance that holds its fetched provider files; nothing is fetched and nothing is
written to it. OUT.json is written outside this repository: it holds positions computed from provider data, the
supplemental files' among them, and is not to be committed. The test `CrossCheckTests` reads it:

    GPKIT_CORPUS=CORPUS GPKIT_PYTHON_SGP4_REFERENCE=OUT.json swift test --filter CrossCheckTests

Each file is read by python-sgp4's own readers: Satrec.twoline2rv for TLE lines, sgp4.omm for CSV, XML and JSON.
python-sgp4 has no KVN reader, so KVN files are left out. It refuses a catalog number above 339999; such a record
is given to it under number 0, which propagation never looks at, and counted.
"""
import glob
import io
import json
import math
import os
import sys

from sgp4 import omm
from sgp4.api import Satrec, accelerated
import sgp4

TIMES = [0.0, 90.0, 720.0, 1440.0, 4320.0, 10080.0]   # minutes from each set's own epoch


def states(sat):
    out = []
    for t in TIMES:
        e, r, v = sat.sgp4_tsince(t)
        # where the call stopped with an error python-sgp4 gives no state; JSON has no NaN, and the state is not compared
        out.append([int(e)] + [float(x) if math.isfinite(x) else 0.0 for x in list(r) + list(v)])
    return out


def read(path, fmt, counts):
    text = open(path, "rb").read().decode("utf-8")
    if text.strip() in ("No GP data found", "No SupGP data found"):
        return None
    records = []
    if fmt == "tle":
        lines = text.splitlines()
        for i, line in enumerate(lines):
            if line.startswith("1 ") and i + 1 < len(lines) and lines[i + 1].startswith("2 "):
                sat = Satrec.twoline2rv(line, lines[i + 1])
                records.append({"id": sat.satnum, "states": states(sat)})
        return records
    if fmt == "csv":
        rows = list(omm.parse_csv(io.StringIO(text)))
    elif fmt == "xml":
        rows = list(omm.parse_xml(io.StringIO(text)))
    else:
        rows = json.loads(text)
    for fields in rows:
        fields = dict(fields)
        number = int(fields["NORAD_CAT_ID"])
        if number > 339999:
            counts["given to python-sgp4 under number 0"] += 1
            fields["NORAD_CAT_ID"] = "0"
        if not fields.get("OBJECT_ID"):
            fields["OBJECT_ID"] = ""   # 2.27 needs the key and reads its first characters
        sat = Satrec()
        omm.initialize(sat, fields)
        records.append({"id": number, "states": states(sat)})
    return records


def main(corpus, out):
    counts = {"given to python-sgp4 under number 0": 0}
    files = []
    paths = sorted(glob.glob(os.path.join(corpus, "fixtures", "*", "raw", "*")) + glob.glob(os.path.join(corpus, "derived", "alpha5-tle", "*")))
    for path in paths:
        ext = path.rsplit(".", 1)[-1].lower()
        fmt = {"tle": "tle", "2le": "tle", "csv": "csv", "json": "json", "xml": "xml"}.get(ext)
        if fmt is None or path.endswith(".meta.json") or path.endswith(".provenance.json") or "satcat" in os.path.basename(path):
            continue
        try:
            records = read(path, fmt, counts)
        except Exception as e:  # a file python-sgp4 cannot read is named, not hidden
            files.append({"path": os.path.relpath(path, corpus), "format": fmt, "unread": f"{type(e).__name__}: {e}"})
            continue
        if records is None:
            continue
        files.append({"path": os.path.relpath(path, corpus), "format": fmt, "records": records})
    with open(out, "w") as f:
        json.dump({"python_sgp4": sgp4.__version__, "accelerated": bool(accelerated), "times": TIMES, "counts": counts, "files": files}, f)
    read_files = [x for x in files if "records" in x]
    print(f"python-sgp4 {sgp4.__version__} (accelerated: {accelerated}): {len(read_files)} files, "
          f"{sum(len(x['records']) for x in read_files)} element sets, {len(TIMES)} times each; "
          f"{counts['given to python-sgp4 under number 0']} given under number 0; "
          f"{len(files) - len(read_files)} files it could not read")
    for x in files:
        if "unread" in x:
            print(f"  not read: {x['path']}: {x['unread'][:120]}")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2])

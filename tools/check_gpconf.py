#!/usr/bin/env python3
"""Read a gpconf JSON report and say whether GPKit met its bar.

    python3 tools/check_gpconf.py REPORT.json            the offline run, as CI makes it
    python3 tools/check_gpconf.py REPORT.json --gate     the full run, from a corpus that holds its provider files

It reads the report's numbers, never the runner's printed lines, and prints statuses and counts only: an item's
detail can quote provider values, and this output is kept.

Offline, the cases that run from files shipped with the corpus must pass and no case may fail; the cases that need
provider files report not-fetched, which is expected there. With --gate every case must pass, except the one that
checks data and runs no parser (it reports not-exercised for every library), and none may be skipped or left unfetched.
"""
import json
import sys

OFFLINE = ["alpha5-encoding-vectors", "alpha5-tle-derived", "kvn-syntax-variants", "tle-writer-alpha5", "corrupt-input"]
NO_PARSER = ["satcat-70000-cutoff"]


def main(path, gate):
    with open(path) as f:
        report = json.load(f)
    summary = report["summary"]
    status = {r["case"]: r["status"] for r in report["results"]}
    print(f"gpconf {report['gpconf']}, corpus {report['corpus_version']}")
    for case, s in status.items():
        print(f"  {case:<40} {s}")
    print("  " + ", ".join(f"{k} {v}" for k, v in summary.items()))
    for gate_report in report.get("gates", []):
        for fmt, g in gate_report.get("formats", {}).items():
            if g.get("state") == "measured":
                print(f"  gate, {gate_report['name']}, {fmt}: {g['loaded']} of {g['expected']} loaded, "
                      f"{g['refused']} refused, {g['misidentified']} misidentified, {g['dropped']} dropped")
    problems = [f"{c} is {s}" for c, s in status.items() if s == "fail"]
    problems += [f"{c} is {status.get(c, 'absent')}, not pass" for c in OFFLINE if status.get(c) != "pass"]
    if gate:
        problems += [f"{c} is {s}, not pass" for c, s in status.items() if c not in NO_PARSER and c not in OFFLINE and s != "pass"]
        problems += [f"{c} is {status.get(c, 'absent')}, not not-exercised" for c in NO_PARSER if status.get(c) != "not-exercised"]
    if problems:
        print("NOT MET: " + "; ".join(dict.fromkeys(problems)))
        return 1
    print("met: every case passes" + (" but the data check, which runs no parser" if gate else " that runs offline, and none fails"))
    return 0


if __name__ == "__main__":
    args = [a for a in sys.argv[1:] if a != "--gate"]
    if len(args) != 1:
        sys.exit(__doc__)
    sys.exit(main(args[0], "--gate" in sys.argv[1:]))

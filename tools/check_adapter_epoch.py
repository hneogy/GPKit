#!/usr/bin/env python3
"""Check the gpconf adapter's two epoch readings, as gpconf would call it.

    python3 tools/check_adapter_epoch.py .build/debug/gpkit-gpconf

parse declares the propagate op's constants and its epoch, "exact" by default and "vallado" with --epoch vallado;
vectors' propagate answers set 23333 of SGP4-VER.TLE within gpconf's 2e-7 bar of tcppver.out with --epoch vallado,
and outside it by default (the exact epoch, 19 microseconds from his reader's, is millimetres out on that orbit);
an unknown reading is a usage error. Every check must hold; the first that does not ends the run with exit 1.
"""
import json
import subprocess
import sys

LINE1 = "1 23333U 94071A   94305.49999999 -.00172956  26967-3  10000-3 0    15"
LINE2 = "2 23333  28.7490   2.3720 9728298  30.4360   1.3500  0.07309491    70"
# tcppver.out's rows for 23333: minutes, TEME position (km), velocity (km/s)
ROWS = [
    [0.0, -9301.24542292, 3326.10200382, 2318.36441127, -8.729303005, -0.828225037, -0.122314827],
    [720.0, -127965.80064891, -43363.32967165, -19809.90480432, -1.789652016, -0.888278463, -0.441254468],
    [1600.0, -200638.82986236, -82484.14969882, -39488.34331447, -1.186748462, -0.665472422, -0.337037582],
]
BAR = 2.0e-7


def call(adapter, args, stdin):
    return subprocess.run([adapter, *args], input=stdin.encode(), capture_output=True)


def declaration(adapter, flags):
    out = call(adapter, [*flags, "parse", "tle"], LINE1 + "\r\n" + LINE2 + "\r\n")
    if out.returncode != 0:
        sys.exit(f"parse {flags} exited {out.returncode}: {out.stderr.decode()[:200]}")
    entries = [e for e in json.loads(out.stdout) if isinstance(e, dict) and "_adapter" in e]
    if len(entries) != 1:
        sys.exit(f"parse {flags}: {len(entries)} _adapter entries, where one is wanted")
    return entries[0]["_adapter"]


def worst(adapter, flags):
    request = {"op": "propagate", "input": {"raw": LINE1 + "\n" + LINE2 + "\n", "fmt": "tle", "tsince": [r[0] for r in ROWS]}}
    out = call(adapter, [*flags, "vectors"], json.dumps(request))
    if out.returncode != 0:
        sys.exit(f"vectors {flags} exited {out.returncode}: {out.stdout.decode()[:200]}")
    steps = json.loads(out.stdout)["result"]
    return max(abs(mine - theirs) for step, row in zip(steps, ROWS) for mine, theirs in zip(step["r"] + step["v"], row[1:]))


def main(adapter):
    problems = []
    for flags, epoch in (([], "exact"), (["--epoch", "exact"], "exact"), (["--epoch", "vallado"], "vallado")):
        d = declaration(adapter, flags)
        want = {"refusals": True, "propagation": {"gravity": "wgs72", "opsmode": "i", "epoch": epoch}}
        if d != want:
            problems.append(f"parse {flags} declares {d}, not {want}")
    exact, vallado = worst(adapter, []), worst(adapter, ["--epoch", "vallado"])
    print(f"23333 against tcppver.out: --epoch vallado {vallado:.3g}, the default (exact) {exact:.3g}; the bar {BAR:g}")
    if not vallado <= BAR:
        problems.append(f"--epoch vallado is {vallado:.3g} from tcppver.out, outside the bar")
    if not exact > BAR:
        problems.append(f"the default is {exact:.3g} from tcppver.out, inside the bar: it is not the exact epoch")
    bad = call(adapter, ["--epoch", "julian", "vectors"], "{}")
    if bad.returncode != 2:
        problems.append(f"--epoch julian exited {bad.returncode}, not 2")
    if problems:
        print("NOT MET: " + "; ".join(problems))
        return 1
    print("met: both readings declared and answered as they should be")
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    sys.exit(main(sys.argv[1]))

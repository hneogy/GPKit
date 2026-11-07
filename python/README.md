# pygpkit

GPKit from Python. GPKit reads GP data (OMM as CSV, JSON, XML or KVN, and TLE with Alpha-5), writes TLE, propagates
with SGP4 (a port of David Vallado's `SGP4.cpp`), and finds passes over a place with look angles and Doppler.
pygpkit is GPKit itself, compiled, behind a small C interface: every number it gives is the one GPKit gives, to the
bit, and its tests hold it to that.

The distribution and the import are both `pygpkit`; it is not the `gpkit` package on PyPI, which is another project.

```python
import pygpkit

file = pygpkit.read("iss.tle")              # or pygpkit.read(data, format="json")
for refusal in file.refusals:
    print("not read:", refusal)             # each refused record, with GPKit's reason
iss = file.element_sets[0]

propagator = pygpkit.Propagator(iss)
state = propagator.state("2026-11-07T12:00:00")          # TEME, km and km/s
home = pygpkit.Observer(40.0, -75.0, height=100.0)       # degrees, metres
look = propagator.look(home, "2026-11-07T12:00:00")      # azimuth, elevation, range, range rate
beneath = propagator.position("2026-11-07T12:00:00")     # latitude, longitude, altitude
for p in propagator.passes(home, start=iss.epoch, seconds=86_400, above=10):
    print(p.rise.time if p.rise else "already up", round(p.culmination.look.elevation))

name, line1, line2 = iss.to_tle()
```

Times are UTC: CCSDS text (`2026-11-07T12:00:00.000000`) or timezone-aware `datetime` values. A `datetime` without
a time zone is refused rather than guessed at. A refusal to read or write raises `pygpkit.Refusal`, and SGP4
stopping raises `pygpkit.PropagationFailure`, each with GPKit's kind and message.

## How it is built and checked

- `Sources/PyGPKitCore` is the native library: one C function, `pygpkit_call`, takes a request as JSON and gives the
  answer as JSON. Element sets and propagators stay in the library, named to Python by a number.
- `Sources/pygpkit-reference` computes GPKit's own answers for the test files, with GPKit directly, into
  `tests/reference.json`. CI writes it again and stops if it differs from the one committed.
- `tests/test_pygpkit.py` asks pygpkit the same questions and compares every number with `==`.
- `build_wheel.py` writes the wheel with Python's standard library alone.

```bash
swift build -c release --product pygpkit_core
python3 build_wheel.py --library "$(swift build -c release --show-bin-path)/libpygpkit_core.dylib" --platform macosx_13_0_arm64
python3 -m venv /tmp/v && /tmp/v/bin/pip install --no-index dist/pygpkit-*.whl
/tmp/v/bin/python -m unittest discover -s tests
```

Both the reference and the library are release builds. On Apple's systems an optimised build calls
`__sincos_stret` where a sine and a cosine of one angle meet, and its sine differs from `sin`'s in the last bit for
about 3 arguments in 10,000; a debug build of GPKit can differ from a release build there, by about 10⁻¹² km.

Licence: MIT, as GPKit's; see GPKit's `LICENSE` and `NOTICE`.
